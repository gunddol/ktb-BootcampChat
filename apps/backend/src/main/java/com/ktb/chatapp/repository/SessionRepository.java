package com.ktb.chatapp.repository;

import com.ktb.chatapp.model.Session;
import lombok.RequiredArgsConstructor;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Repository;

import java.time.Duration;
import java.util.List;
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

        if (sessionIds == null || sessionIds.isEmpty()) {
            return Optional.empty();
        }

        // 성능 개선: Pipeline을 사용하여 여러 키를 한 번에 조회 (N+1 문제 해결)
        List<String> sessionKeyList = sessionIds.stream()
            .map(obj -> sessionKey(obj.toString()))
            .collect(java.util.stream.Collectors.toList());

        // Pipeline으로 일괄 조회
        List<Object> sessions = redisTemplate.executePipelined(
            (org.springframework.data.redis.core.RedisCallback<Object>) connection -> {
                for (String key : sessionKeyList) {
                    connection.get(key.getBytes());
                }
                return null;
            }
        );

        // 첫 번째 유효한 세션 반환 및 죽은 세션 정리
        int index = 0;
        for (Object sessionObj : sessions) {
            if (sessionObj instanceof Session) {
                return Optional.of((Session) sessionObj);
            } else {
                // 죽은 세션 정리
                String sessionId = sessionIds.stream()
                    .skip(index)
                    .findFirst()
                    .map(Object::toString)
                    .orElse(null);
                if (sessionId != null) {
                    redisTemplate.opsForSet().remove(userKey, sessionId);
                }
            }
            index++;
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


