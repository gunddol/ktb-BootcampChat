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

        redisTemplate.opsForValue().set(clientIdKey, rateLimit);

        return rateLimit;

    }

    public void deleteAll(){
        Set<String> clientIdKeys = redisTemplate.keys(ClientIdKey("*"));
        if(clientIdKeys != null && !clientIdKeys.isEmpty()){
            redisTemplate.delete(clientIdKeys);
        }
    }
}
