package com.ktb.chatapp.repository;

import com.ktb.chatapp.model.RateLimit;
import java.util.Optional;
import java.util.Set;

import lombok.RequiredArgsConstructor;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Repository;

@Repository
@RequiredArgsConstructor
public class RateLimitRepository{


    private final RedisTemplate<String, Object> redisTemplate;

    private String ClientIdKey(String clientId) {
        return  "ClientId:" + clientId;
    }



    public Optional<RateLimit> findByClientId(String clientId){
        String clientIdKey = ClientIdKey(clientId);

        Object value = redisTemplate.opsForValue().get(clientIdKey);

        if(value == null){
            return Optional.empty();
        }
        return Optional.of( (RateLimit) value);
    }

    public RateLimit save(RateLimit rateLimit) {
        String clientIdKey = ClientIdKey(rateLimit.getClientId());

        // TTL 계산: expiresAt까지 남은 시간
        long ttlSeconds = java.time.Duration.between(
            java.time.Instant.now(), 
            rateLimit.getExpiresAt()
        ).getSeconds();
        
        // TTL이 0보다 크면 설정, 아니면 기본 1시간
        if (ttlSeconds > 0) {
            redisTemplate.opsForValue().set(
                clientIdKey, 
                rateLimit, 
                java.time.Duration.ofSeconds(ttlSeconds)
            );
        } else {
            // 만료 시간이 지났거나 없으면 기본 1시간 TTL
            redisTemplate.opsForValue().set(
                clientIdKey, 
                rateLimit, 
                java.time.Duration.ofHours(1)
            );
        }

        return rateLimit;
    }

    public void deleteAll(){
        Set<String> clientIdKeys = redisTemplate.keys(ClientIdKey("*"));
        if(clientIdKeys != null && !clientIdKeys.isEmpty()){
            redisTemplate.delete(clientIdKeys);
        }
    }
}
