package com.ktb.chatapp.dto;

import lombok.Getter;

/**
 * 메시지 내용과 AI 멘션을 처리하는 클래스
 */
@Getter
public class MessageContent {
  private final String rawContent;
  private final String trimmedContent;

  private MessageContent(String content) {
    this.rawContent = content != null ? content : "";
    this.trimmedContent = this.rawContent.trim();
  }

  /**
   * 메시지 내용으로부터 MessageContent 객체 생성
   */
  public static MessageContent from(String content) {
    return new MessageContent(content);
  }

  /**
   * 내용이 비어있는지 확인
   */
  public boolean isEmpty() {
    return trimmedContent.isEmpty();
  }
}
