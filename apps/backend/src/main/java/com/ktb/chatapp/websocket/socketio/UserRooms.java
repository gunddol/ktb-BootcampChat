package com.ktb.chatapp.websocket.socketio;

import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.redisson.api.RSet;
import org.redisson.api.RedissonClient;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "socketio.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
public class UserRooms {

    private static final String USER_ROOM_KEY_PREFIX = "userroom:roomids:";

    private final RedissonClient redissonClient;

    /**
     * Get all room IDs for a user
     *
     * @param userId the user ID
     * @return the set of room IDs the user is currently in, or empty set if not in
     *         any room
     */
    public Set<String> get(String userId) {
        RSet<String> rooms = getRoomSet(userId);
        return rooms.readAll();
    }

    /**
     * Add a room ID for a user
     * ✅ Atomic operation: SADD command
     *
     * @param userId the user ID
     * @param roomId the room ID to add to the user's room set
     */
    public void add(String userId, String roomId) {
        RSet<String> rooms = getRoomSet(userId);
        rooms.add(roomId);
    }

    /**
     * Remove a specific room ID from a user's room set
     * ✅ Atomic operation: SREM command
     *
     * @param userId the user ID
     * @param roomId the room ID to remove
     */
    public void remove(String userId, String roomId) {
        RSet<String> rooms = getRoomSet(userId);
        rooms.remove(roomId);
        if (rooms.isEmpty()) {
            rooms.delete();
        }
    }

    /**
     * Remove all room associations for a user
     */
    public void clear(String userId) {
        RSet<String> rooms = getRoomSet(userId);
        rooms.delete();
    }

    /**
     * Check if a user is in a specific room
     * ✅ Atomic operation: SISMEMBER command
     *
     * @param userId the user ID
     * @param roomId the room ID to check
     * @return true if the user is in the room, false otherwise
     */
    public boolean isInRoom(String userId, String roomId) {
        RSet<String> rooms = getRoomSet(userId);
        return rooms.contains(roomId);
    }

    /**
     * Remove user from all rooms
     */
    public void removeAllRooms(String userId) {
        clear(userId);
    }

    /**
     * Helper method to get Redis Set
     */
    private RSet<String> getRoomSet(String userId) {
        return redissonClient.getSet(buildKey(userId));
    }

    private String buildKey(String userId) {
        return USER_ROOM_KEY_PREFIX + userId;
    }
}
