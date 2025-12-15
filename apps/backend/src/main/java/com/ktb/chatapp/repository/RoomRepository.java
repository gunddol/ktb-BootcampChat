package com.ktb.chatapp.repository;

import com.ktb.chatapp.model.Room;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.data.mongodb.repository.Update;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface RoomRepository extends MongoRepository<Room, String> {

    // 페이지네이션과 함께 모든 방 조회
    Page<Room> findAll(Pageable pageable);

    // 검색어와 함께 페이지네이션 조회
    Page<Room> findByNameContainingIgnoreCase(String name, Pageable pageable);

    // 가장 최근에 생성된 방 조회 (Health Check용)
    @Query(value = "{}", sort = "{ 'createdAt': -1 }")
    Optional<Room> findMostRecentRoom();

    // Health Check용 단순 조회 (지연 시간 측정)
    @Query(value = "{}", fields = "{ '_id': 1 }")
    Optional<Room> findOneForHealthCheck();

    @Query("{'_id': ?0}")
    @Update("{'$addToSet': {'participantIds': ?1}}")
    void addParticipant(String roomId, String userId);

    @Query("{'_id': ?0}")
    @Update("{'$pull': {'participantIds': ?1}}")
    void removeParticipant(String roomId, String userId);

    /**
     * 방 존재 여부 및 참여자 확인 (경량화된 권한 체크)
     * 전체 Room 객체를 로딩하지 않고 boolean만 반환하여 메모리와 DB I/O 절약
     * 
     * @param id            방 ID
     * @param participantId 참여자 ID
     * @return 방이 존재하고 사용자가 참여자인 경우 true
     */
    boolean existsByIdAndParticipantIdsContains(String id, String participantId);

}