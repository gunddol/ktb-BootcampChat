package com.ktb.chatapp.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class CompleteUploadRequest {
    @NotBlank(message = "파일명은 필수입니다.")
    private String filename;

    @NotBlank(message = "원본 파일명은 필수입니다.")
    private String originalFilename;

    @NotBlank(message = "Content-Type은 필수입니다.")
    private String contentType;

    @NotNull(message = "파일 크기는 필수입니다.")
    @Positive(message = "파일 크기는 양수여야 합니다.")
    private Long fileSize;
}
