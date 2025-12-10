package com.ktb.chatapp.websocket.socketio;

import com.corundumstudio.socketio.SocketIOServer;
import com.ktb.chatapp.event.*;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import static com.ktb.chatapp.websocket.socketio.SocketIOEvents.*;

@Slf4j
@Component
@ConditionalOnProperty(name = "socketio.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
public class SocketIOEventListener {

  private final SocketIOServer socketIOServer;

  @EventListener
  public void handleSessionEndedEvent(SessionEndedEvent event) {
    try {
      socketIOServer.getRoomOperations("user:" + event.getUserId())
          .sendEvent("session_ended", Map.of(
              "reason", event.getReason(),
              "message", event.getMessage()));
      log.info("session_ended 이벤트 발송: userId={}, reason={}", event.getUserId(), event.getReason());
    } catch (Exception e) {
      log.error("session_ended 이벤트 발송 실패: userId={}", event.getUserId(), e);
    }
  }

  @EventListener
  public void handleRoomCreatedEvent(RoomCreatedEvent event) {
    try {
      socketIOServer.getRoomOperations("room-list").sendEvent(ROOM_CREATED, event.getRoomResponse());
      log.info("roomCreated 이벤트 발송: roomId={}", event.getRoomResponse().getId());
    } catch (Exception e) {
      log.error("roomCreated 이벤트 발송 실패", e);
    }
  }

  @EventListener
  public void handleRoomUpdatedEvent(RoomUpdatedEvent event) {
    try {
      socketIOServer.getRoomOperations(event.getRoomId()).sendEvent(ROOM_UPDATE, event.getRoomResponse());
      log.info("roomUpdate 이벤트 발송: roomId={}", event.getRoomId());
    } catch (Exception e) {
      log.error("roomUpdate 이벤트 발송 실패: roomId={}", event.getRoomId(), e);
    }
  }
}
