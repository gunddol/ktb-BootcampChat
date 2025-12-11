package com.ktb.chatapp.websocket.socketio;

import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.LocalCachedMapOptions;
import org.redisson.api.LocalCachedMapOptions.EvictionPolicy;
import org.redisson.api.LocalCachedMapOptions.ReconnectionStrategy;
import org.redisson.api.LocalCachedMapOptions.SyncStrategy;
import org.redisson.api.RMap;
import org.redisson.api.RedissonClient;

/**
 * Redis-backed implementation of ChatDataStore using Redisson's Local Cache
 * (Near Cache).
 * Provides high-performance read operations (local memory speed) and
 * distributed consistency.
 * 
 * Optimized for:
 * - Read-heavy workloads (chat status checks)
 * - Distributed environments (12+ instances)
 * - Eventual consistency (~10ms delay)
 */
@Slf4j
public class RedisChatDataStore implements ChatDataStore {

    private final RMap<String, Object> storage;

    public RedisChatDataStore(RedissonClient redissonClient) {
        // Configure Local Cache options for "Near Cache" pattern
        LocalCachedMapOptions<String, Object> options = LocalCachedMapOptions.<String, Object>defaults()
                // Eviction Policy: LRU (Least Recently Used) to prevent memory explosion
                .evictionPolicy(EvictionPolicy.LRU)
                // Cache Size: Keep up to 10,000 active keys in local heap
                .cacheSize(10000)
                // Sync Strategy: UPDATE (Server sends invalidation + new value to all nodes)
                .syncStrategy(SyncStrategy.UPDATE)
                // Reconnection: Clear local cache on disconnect to avoid stale data
                .reconnectionStrategy(ReconnectionStrategy.CLEAR);

        // "chat:store" is the Redis key for the Hash
        this.storage = redissonClient.getMap("chat:store", options);

        log.info("RedisChatDataStore initialized with Near Cache (Size: 10000, Policy: LRU)");
    }

    @Override
    public <T> Optional<T> get(String key, Class<T> type) {
        // Read from Near Cache (Microsecond/Nanosecond latency)
        Object value = storage.get(key);

        if (value == null) {
            return Optional.empty();
        }

        try {
            return Optional.of(type.cast(value));
        } catch (ClassCastException e) {
            log.warn("Failed to cast value for key {} to type {}", key, type.getName());
            return Optional.empty();
        }
    }

    @Override
    public void set(String key, Object value) {
        // Write to Redis + Publish Invalidation Message (few millis latency)
        storage.fastPut(key, value);
    }

    @Override
    public void delete(String key) {
        // Delete from Redis + Publish Invalidation
        storage.fastRemove(key);
    }

    @Override
    public int size() {
        // Returns the size of the distributed map (global count), not just local
        return storage.size();
    }
}
