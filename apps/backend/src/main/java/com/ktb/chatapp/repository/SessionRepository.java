package com.ktb.chatapp.repository;

import com.ktb.chatapp.model.Session;
import lombok.RequiredArgsConstructor;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Repository;

import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import java.util.Set;


@Repository
@RequiredArgsConstructor
public class SessionRepository {

    private final RedisTemplate<String, Object> redisTemplate;


    private String sessionKey(String sessionId) {
        return "session:" + sessionId;
    }
    private String userKey(String userId) {
        return "user:" + userId;
    }




    public Session save(Session session) {


        String sessionKey = sessionKey(session.getSessionId());
        String userKey = userKey(session.getUserId());


//        redisTemplate.opsForHash().putAll(sessionKey, session.toMap());
//        //만료시 session 데이터 삭제
//        redisTemplate.expire(sessionKey, Duration.ofMinutes(30));

        redisTemplate.opsForValue().set(sessionKey, session, Duration.ofMinutes(30));

        redisTemplate.opsForSet().add(userKey, session.getSessionId());

        return session;

    }

    public Optional<Session> findByUserId(String userId) {

        String userKey = userKey(userId);
        Set<Object> sessionIds = redisTemplate.opsForSet().members(userKey);

        if (sessionIds == null|| sessionIds.isEmpty()) {
            return Optional.empty();
        }

        for (Object obj : sessionIds) {
            String sessionId = obj.toString();
            String sessionKey = sessionKey(sessionId);

            Object sessionObject = redisTemplate.opsForValue().get(sessionKey);

            // 살아있는 세션이면 바로 반환
            if (sessionObject instanceof Session) {
                return Optional.of((Session) sessionObject);
            }
            // 죽은 세션이면 정리
            redisTemplate.opsForSet().remove(userKey, sessionId);
        }

        return Optional.empty();


    }

    //deleteall
    public void deleteByUserId(String userId) {

        Set<Object> sessionIds = redisTemplate.opsForSet().members(userKey(userId));
        if(sessionIds != null && !sessionIds.isEmpty()) {
            for (Object obj : sessionIds) {
                String sessionId = obj.toString();
                String sessionKey = sessionKey(sessionId);
                redisTemplate.delete(sessionKey);
            }
        }
        redisTemplate.delete(userKey(userId));
    }

    //session만 제거
    public void delete(Session session) {
        String sessionId = session.getSessionId();
        String sessionKey = sessionKey(sessionId);
        String userKey = userKey(session.getUserId());


        redisTemplate.delete(sessionKey);
        redisTemplate.opsForSet().remove(userKey, sessionId);
    }
}


