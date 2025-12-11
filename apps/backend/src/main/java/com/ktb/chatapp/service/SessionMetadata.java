package com.ktb.chatapp.service;

import java.io.Serializable;

public record SessionMetadata(String userAgent, String ipAddress, String deviceInfo) {
}
