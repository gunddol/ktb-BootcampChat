package com.ktb.chatapp.config;

import com.corundumstudio.socketio.AuthTokenListener;
import com.corundumstudio.socketio.SocketConfig;
import com.corundumstudio.socketio.SocketIOServer;
import com.corundumstudio.socketio.annotation.SpringAnnotationScanner;
import com.corundumstudio.socketio.namespace.Namespace;
import com.corundumstudio.socketio.protocol.JacksonJsonSupport;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.ktb.chatapp.websocket.socketio.ChatDataStore;
import com.ktb.chatapp.websocket.socketio.RedisChatDataStore;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.RedissonClient;
import org.redisson.config.Config;
import org.redisson.Redisson;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;
import org.springframework.context.annotation.Role;

import static org.springframework.beans.factory.config.BeanDefinition.ROLE_INFRASTRUCTURE;

@Slf4j
@Configuration
@ConditionalOnProperty(name = "socketio.enabled", havingValue = "true", matchIfMissing = true)
public class SocketIOConfig {

  @Value("${socketio.server.host:localhost}")
  private String host;

  @Value("${socketio.server.port:5002}")
  private Integer port;

  @Value("${spring.data.redis.host}")
  private String redisHost;

  @Value("${spring.data.redis.password}")
  private String redisPassword;

  @Value("${spring.data.redis.replicas:}")
  private String redisReplicas; // 예: "10.0.101.164:6379,10.0.101.11:6379"

  @Bean(destroyMethod = "shutdown")
  public RedissonClient redissonClient() {
    Config config = new Config();
    
    // Master-Slave 모드로 변경하여 Replica 활용 및 자동 Failover
    if (redisReplicas != null && !redisReplicas.isEmpty()) {
      // Master-Slave 모드: 읽기 분산 및 자동 Failover
      String masterAddress = "redis://" + redisHost + ":6379";
      String[] replicaList = redisReplicas.split(",");
      
      // Replica 주소를 "redis://" 형식으로 변환
      String[] replicaAddresses = new String[replicaList.length];
      for (int i = 0; i < replicaList.length; i++) {
        String replica = replicaList[i].trim();
        if (!replica.startsWith("redis://")) {
          replicaAddresses[i] = "redis://" + replica;
        } else {
          replicaAddresses[i] = replica;
        }
      }
      
      var masterSlaveConfig = config.useMasterSlaveServers()
          .setMasterAddress(masterAddress)
          .setPassword(redisPassword)
          .setMasterConnectionPoolSize(10)  // Master 연결 풀
          .setMasterConnectionMinimumIdleSize(5)
          .setSlaveConnectionPoolSize(10)   // 각 Replica 연결 풀
          .setSlaveConnectionMinimumIdleSize(5);
      
      // Replica 주소 추가
      for (String replicaAddr : replicaAddresses) {
        masterSlaveConfig.addSlaveAddress(replicaAddr);
      }
      
      masterSlaveConfig
          .setReadMode(org.redisson.config.ReadMode.SLAVE)  // 읽기는 Replica에서
          .setRetryAttempts(3)
          .setRetryInterval(1500)
          .setTimeout(3000)
          .setConnectTimeout(10000)
          .setFailedSlaveReconnectionInterval(5000)
          .setFailedSlaveCheckInterval(180000);  // 3분마다 실패한 Replica 체크
      
      log.info("Redisson configured in Master-Slave mode: Master={}, Replicas={}", 
          masterAddress, String.join(", ", replicaAddresses));
    } else {
      // Fallback: Single Server 모드 (Replica 정보가 없을 때)
      config.useSingleServer()
          .setAddress("redis://" + redisHost + ":6379")
          .setPassword(redisPassword)
          .setConnectionPoolSize(10)
          .setConnectionMinimumIdleSize(5)
          .setRetryAttempts(3)
          .setRetryInterval(1500)
          .setTimeout(3000)
          .setConnectTimeout(10000);
      
      log.info("Redisson configured in Single Server mode: {}", redisHost);
    }
    
    return Redisson.create(config);
  }

  @Bean(initMethod = "start", destroyMethod = "stop")
  public SocketIOServer socketIOServer(AuthTokenListener authTokenListener, RedissonClient redissonClient) {
    com.corundumstudio.socketio.Configuration config = new com.corundumstudio.socketio.Configuration();
    config.setHostname(host);
    config.setPort(port);

    var socketConfig = new SocketConfig();
    socketConfig.setReuseAddress(true);
    socketConfig.setTcpNoDelay(false);
    socketConfig.setAcceptBackLog(10);
    socketConfig.setTcpSendBufferSize(4096);
    socketConfig.setTcpReceiveBufferSize(4096);
    config.setSocketConfig(socketConfig);

    config.setOrigin("*");

    // Socket.IO settings
    config.setPingTimeout(60000);
    config.setPingInterval(25000);
    config.setUpgradeTimeout(10000);

    config.setJsonSupport(new JacksonJsonSupport(new JavaTimeModule()));

    // Use the injected RedissonClient for Socket.IO store
    config.setStoreFactory(new com.corundumstudio.socketio.store.RedissonStoreFactory(redissonClient));

    log.info("Socket.IO server configured on {}:{} with {} boss threads and {} worker threads",
        host, port, config.getBossThreads(), config.getWorkerThreads());
    var socketIOServer = new SocketIOServer(config);
    socketIOServer.getNamespace(Namespace.DEFAULT_NAME).addAuthTokenListener(authTokenListener);

    return socketIOServer;
  }

  /**
   * SpringAnnotationScanner는 BeanPostProcessor로서
   * ApplicationContext 초기화 초기에 등록되고,
   * 내부에서 사용하는 SocketIOServer는 Lazy로 지연되어
   * 다른 Bean들의 초기화 과정에 간섭하지 않게 한다.
   */
  @Bean
  @Role(ROLE_INFRASTRUCTURE)
  public BeanPostProcessor springAnnotationScanner(@Lazy SocketIOServer socketIOServer) {
    return new SpringAnnotationScanner(socketIOServer);
  }

  // Redis 기반 분산 저장소 (Near Cache 적용)
  @Bean
  @ConditionalOnProperty(name = "socketio.enabled", havingValue = "true", matchIfMissing = true)
  public ChatDataStore chatDataStore(RedissonClient redissonClient) {
    return new RedisChatDataStore(redissonClient);
  }
}
