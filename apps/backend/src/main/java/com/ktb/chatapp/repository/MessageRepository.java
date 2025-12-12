package com.ktb.chatapp.repository;

import com.ktb.chatapp.model.Message;
import java.time.LocalDateTime;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.stereotype.Repository;



import com.ktb.chatapp.model.Message;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;


@Repository
public class MessageRepository {

    // RedisTemplate의 Value 타입이 Object이지만, Message 객체가 JSON으로 처리됨을 가정합니다.
    private final RedisTemplate<String, Object> redisTemplate;
    private final ListOperations<String, Object> listOperations;
    private final ValueOperations<String, Object> valueOperations;

    private static final String CHAT_KEY_PREFIX = "chat:room:";
    private static final String MESSAGE_KEY_PREFIX = "message:";


    public MessageRepository(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;

        this.listOperations = redisTemplate.opsForList();
        this.valueOperations = redisTemplate.opsForValue();

    }


    // --- 유틸리티 메서드 ---
    private String getRoomKey(String roomId) {
        return CHAT_KEY_PREFIX + roomId;
    }

    private String getMessageKey(String messageId) {
        return MESSAGE_KEY_PREFIX + messageId;
    }

    // Redis의 Object 타입을 Message로 안전하게 캐스팅
    private Message castToMessage(Object obj) {
        // 실제로는 JSON 역직렬화 설정이 올바르면 직접 Message 타입으로 캐스팅됨
        // 하지만 RedisTemplate<String, Object>이므로 예방적으로 확인
        if (obj instanceof Message) {
            return (Message) obj;
        }
        // 캐스팅 오류 발생 시 (JSON Serializer 설정 오류 가능성)
        return null;
    }


    /**
     * [구현 필요] 특정 조건에 맞는 메시지를 필터링 및 페이지네이션하여 조회합니다.
     * (주의: List 전체를 가져와 필터링하므로, 대용량 데이터에서는 성능이 느릴 수 있습니다.)
     */
    public Page<Message> findByRoomIdAndIsDeletedAndTimestampBefore(
            String roomId,
            Boolean isDeleted,
            LocalDateTime timestamp,
            Pageable pageable
    ) {
        String key = getRoomKey(roomId);

        List<Object> allObjects = listOperations.range(key, 0, -1);
        if (allObjects == null || allObjects.isEmpty()) {
            return new PageImpl<>(Collections.emptyList(), pageable, 0);
        }

        // 2. Java 코드에서 조건에 맞는 메시지만 필터링합니다.
        List<Message> filteredMessages = allObjects.stream()
                .map(this::castToMessage)
                .filter(m -> m != null &&
                        m.getIsDeleted().equals(isDeleted) &&
                        m.getTimestamp().isBefore(timestamp))
                .collect(Collectors.toList());

        // 3. 필터링된 결과에 대해 수동으로 페이지네이션을 적용합니다.
        int totalFilteredElements = filteredMessages.size();
        int pageSize = pageable.getPageSize();
        int currentPage = pageable.getPageNumber();
        long start = pageable.getOffset();

        // 페이지 경계를 벗어나는 경우 처리
        if (start > totalFilteredElements) {
            return new PageImpl<>(Collections.emptyList(), pageable, totalFilteredElements);
        }

        int end = Math.min((int) (start + pageSize), totalFilteredElements);

        // 4. 요청된 페이지의 데이터만 추출
        List<Message> pageContent = filteredMessages.subList((int) start, end);

        // 5. Page 객체 생성 및 반환
        return new PageImpl<>(pageContent, pageable, totalFilteredElements);
    }

    public Optional<Message> findById(String messageId) {
        String key = getMessageKey(messageId);

        // 1. Redis에서 키를 사용하여 값을 조회 (GET 명령)
        Object foundObject = valueOperations.get(key);

        // 2. 결과가 없는 경우 Optional.empty() 반환
        if (foundObject == null) {
            return Optional.empty();
        }

        // 3. 조회된 Object를 Message로 캐스팅 (JSON 역직렬화 가정)
        Message message = castToMessage(foundObject);

        // 4. Message 객체를 Optional로 래핑하여 반환
        return Optional.ofNullable(message);
    }


    /**
     * [구현 필요] 특정 시간 이후의 메시지 수 카운트 (삭제되지 않은 메시지만)
     * (주의: 이 역시 Redis List 전체를 순회해야 하므로 성능에 주의해야 합니다.)
     */
    public long countRecentMessagesByRoomId(String roomId, LocalDateTime since) {
        String key = getRoomKey(roomId);

        // 필터링을 위해 전체 메시지 조회
        List<Object> allObjects = listOperations.range(key, 0, -1);
        if (allObjects == null) {
            return 0;
        }

        // Java 코드에서 필터링 및 카운트
        return allObjects.stream()
                .map(this::castToMessage)
                .filter(m -> m != null &&
                        !m.getIsDeleted() &&
                        m.getTimestamp().isAfter(since)) // since 이후 (>=) 메시지
                .count();
    }

    /**
     * [구현 필요] fileId로 메시지 조회 (파일 권한 검증용)
     * (주의: List에서 특정 필드 값으로 찾는 것은 매우 비효율적이며, Redis Hash 또는 DB가 적합합니다.)
     */
    public Optional<Message> findByFileId(String fileId) {
        // 파일 ID로 직접 메시지를 조회하려면, Redis의 List 구조 대신
        // Hash 구조나 보조적인 Set/Hash 인덱스가 필요합니다.
        // List를 사용하는 현재 구조에서는 모든 채팅방의 모든 메시지를 순회해야 하는 비효율이 발생합니다.

        // 임시 방편으로, 조회 없이 비어있는 Optional 반환을 제안합니다.
        // 실제 운영 환경에서는 findByFileId를 위해 DB(MongoDB, JPA 등)를 사용하거나,
        // Redis에 별도의 인덱스 키 (예: fileId:abc -> roomId)를 만들어야 합니다.
        return Optional.empty();
    }

    // 기존 코드에는 없지만, Repository가 있어야 하므로 추가합니다.
    public Message save(Message message) {
        String roomKey = getRoomKey(message.getRoomId());
        String messageKey = getMessageKey(message.getId());

        // 1. List에 저장 (채팅방 타임라인용)
        listOperations.rightPush(roomKey, message);

        // 2. 개별 String Key로 저장 (ID로 빠르게 찾기 위함)
        valueOperations.set(messageKey, message);

        return message;
    }

    public List<Message> findAllById(List<String> messageIds) {

        // 1. messageId 목록을 Redis Key 목록으로 변환
        List<String> keys = messageIds.stream()
                .map(this::getMessageKey)
                .collect(Collectors.toList());

        // 2. MGET (Multi Get) 명령으로 한 번에 여러 Key의 Value를 조회
        List<Object> foundObjects = valueOperations.multiGet(keys);

        // 3. 조회된 Object 목록을 Message 객체로 변환 및 필터링
        if (foundObjects == null) {
            return Collections.emptyList();
        }

        return foundObjects.stream()
                .filter(java.util.Objects::nonNull) // Redis에 없는 Key는 null로 반환됨 (필터링)
                .map(this::castToMessage)
                .filter(java.util.Objects::nonNull)
                .collect(Collectors.toList());
    }
}