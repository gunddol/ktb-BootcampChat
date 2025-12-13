package com.ktb.chatapp.service;

import com.ktb.chatapp.model.Message;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.RList;
import org.redisson.api.RedissonClient;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class RedisMessageService {

    private final RedissonClient redissonClient;

    private static final String MESSAGE_KEY_PREFIX = "chat:room:%s:messages";

    /**
     * Save message to Redis List
     */
    public Message save(Message message) {
        try {
            if (message.getId() == null) {
                message.setId(UUID.randomUUID().toString());
            }
            if (message.getTimestamp() == null) {
                message.setTimestamp(LocalDateTime.now());
            }

            String key = String.format(MESSAGE_KEY_PREFIX, message.getRoomId());
            RList<Message> list = redissonClient.getList(key);
            list.add(message);

            log.debug("Saved message to Redis: {} (Room: {})", message.getId(), message.getRoomId());
            return message;
        } catch (Exception e) {
            log.error("Failed to save message to Redis", e);
            throw e;
        }
    }

    /**
     * Get recent messages from Redis List (Pagination support)
     */
    public Page<Message> findByRoomId(String roomId, Pageable pageable) {
        String key = String.format(MESSAGE_KEY_PREFIX, roomId);
        RList<Message> list = redissonClient.getList(key);

        int totalSize = list.size();
        if (totalSize == 0) {
            return new PageImpl<>(Collections.emptyList(), pageable, 0);
        }

        // Logic for "Recent" messages usually means accessing the END of the list.
        // If sorting is DESC (Newest first):
        // Page 0 = Last N elements.

        int pageSize = pageable.getPageSize();
        int pageNumber = pageable.getPageNumber();

        int endIndex = totalSize - 1 - (pageNumber * pageSize);
        int startIndex = endIndex - pageSize + 1;

        if (endIndex < 0) {
            return new PageImpl<>(Collections.emptyList(), pageable, totalSize);
        }
        if (startIndex < 0)
            startIndex = 0;

        // Fetch range
        List<Message> messages = list.range(startIndex, endIndex);

        return new PageImpl<>(messages, pageable, totalSize);
    }
}
