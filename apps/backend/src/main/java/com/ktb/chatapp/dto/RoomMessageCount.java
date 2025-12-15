package com.ktb.chatapp.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class RoomMessageCount {
    private String id; // maps to _id (roomId)
    private long count;
}
