package com.ktb.chatapp.controller;

import com.ktb.chatapp.dto.CompleteUploadRequest;
import com.ktb.chatapp.dto.PresignedUrlRequest;
import com.ktb.chatapp.dto.StandardResponse;
import com.ktb.chatapp.model.File;
import com.ktb.chatapp.model.User;
import com.ktb.chatapp.repository.FileRepository;
import com.ktb.chatapp.security.CustomUserDetails;
import com.ktb.chatapp.service.FileService;
import com.ktb.chatapp.service.FileUploadResult;
import com.ktb.chatapp.service.UserService;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.Principal;
import java.util.HashMap;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;

@Tag(name = "파일 (Files)", description = "파일 업로드 및 다운로드 API")
@Slf4j
@RestController
@RequestMapping("/api/files")
public class FileController {

    private final FileService fileService;
    private final FileRepository fileRepository;
    private final UserService userService;
    
    // Presigned URL 생성을 위해 S3FileService 직접 주입
    private final com.ktb.chatapp.service.S3FileService s3FileService;

    public FileController(FileService fileService,
                         FileRepository fileRepository,
                         UserService userService,
                         com.ktb.chatapp.service.S3FileService s3FileService) {
        this.fileService = fileService;
        this.fileRepository = fileRepository;
        this.userService = userService;
        this.s3FileService = s3FileService;
    }

    /**
     * 파일 업로드
     */
    @Operation(summary = "파일 업로드", description = "파일을 업로드합니다. 최대 50MB까지 가능합니다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "파일 업로드 성공"),
            @ApiResponse(responseCode = "400", description = "잘못된 파일", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "401", description = "인증 실패", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "413", description = "파일 크기 초과", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "500", description = "서버 내부 오류", content = @Content(schema = @Schema(implementation = StandardResponse.class)))
    })
    @PostMapping("/upload")
    public ResponseEntity<?> uploadFile(
            @Parameter(description = "업로드할 파일") @RequestParam("file") MultipartFile file,
            Principal principal) {
        try {
            String userId = getUserIdFromPrincipal(principal);
            User user = userService.getUserProfile(userId);

            FileUploadResult result = fileService.uploadFile(file, user.getId());

            if (result.isSuccess()) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", true);
                response.put("message", "파일 업로드 성공");

                Map<String, Object> fileData = new HashMap<>();
                fileData.put("_id", result.getFile().getId());
                fileData.put("filename", result.getFile().getFilename());
                fileData.put("originalname", result.getFile().getOriginalname());
                fileData.put("mimetype", result.getFile().getMimetype());
                fileData.put("size", result.getFile().getSize());
                fileData.put("uploadDate", result.getFile().getUploadDate());

                response.put("file", fileData);

                return ResponseEntity.ok(response);
            } else {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "파일 업로드에 실패했습니다.");
                return ResponseEntity.status(500).body(errorResponse);
            }

        } catch (Exception e) {
            log.error("파일 업로드 중 에러 발생", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "파일 업로드 중 오류가 발생했습니다.");
            errorResponse.put("error", e.getMessage());
            return ResponseEntity.status(500).body(errorResponse);
        }
    }

    /**
     * 보안이 강화된 파일 다운로드
     */
    @Operation(summary = "파일 다운로드", description = "업로드된 파일을 다운로드합니다. 본인이 업로드한 파일만 다운로드 가능합니다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "파일 다운로드 성공"),
            @ApiResponse(responseCode = "401", description = "인증 실패", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "403", description = "권한 없음", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "404", description = "파일을 찾을 수 없음", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "500", description = "서버 내부 오류", content = @Content(schema = @Schema(implementation = StandardResponse.class)))
    })
    @GetMapping("/download/{filename:.+}")
    public ResponseEntity<?> downloadFile(
            @Parameter(description = "다운로드할 파일명") @PathVariable String filename,
            HttpServletRequest request,
            Principal principal) {
        try {
            String userId = getUserIdFromPrincipal(principal);
            User user = userService.getUserProfile(userId);

            Resource resource = fileService.loadFileAsResource(filename, user.getId());

            File fileEntity = fileRepository.findByFilename(filename)
                    .orElse(null);

            String originalFilename = fileEntity != null ? fileEntity.getOriginalname() : filename;
            String encodedFilename = URLEncoder.encode(originalFilename, StandardCharsets.UTF_8)
                    .replaceAll("\\+", "%20");

            String contentDisposition = String.format(
                    "attachment; filename*=UTF-8''%s",
                    encodedFilename);

            long contentLength = fileEntity != null ? fileEntity.getSize() : resource.contentLength();

            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType(fileEntity.getMimetype()))
                    .contentLength(contentLength)
                    .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition)
                    .header(HttpHeaders.CACHE_CONTROL, "private, no-cache, no-store, must-revalidate")
                    .header(HttpHeaders.ACCESS_CONTROL_EXPOSE_HEADERS, "Content-Disposition")
                    .body(resource);

        } catch (Exception e) {
            log.error("파일 다운로드 중 에러 발생: {}", filename, e);
            return handleFileError(e);
        }
    }

    private ResponseEntity<?> handleFileError(Exception e) {
        String errorMessage = e.getMessage();
        int statusCode = 500;
        String responseMessage = "파일 처리 중 오류가 발생했습니다.";

        if (errorMessage != null) {
            if (errorMessage.contains("잘못된 파일명") || errorMessage.contains("Invalid filename")) {
                statusCode = 400;
                responseMessage = "잘못된 파일명입니다.";
            } else if (errorMessage.contains("인증") || errorMessage.contains("Authentication")) {
                statusCode = 401;
                responseMessage = "인증이 필요합니다.";
            } else if (errorMessage.contains("잘못된 파일 경로") || errorMessage.contains("Invalid file path")) {
                statusCode = 400;
                responseMessage = "잘못된 파일 경로입니다.";
            } else if (errorMessage.contains("찾을 수 없습니다") || errorMessage.contains("not found")) {
                statusCode = 404;
                responseMessage = "파일을 찾을 수 없습니다.";
            } else if (errorMessage.contains("메시지를 찾을 수 없습니다")) {
                statusCode = 404;
                responseMessage = "파일 메시지를 찾을 수 없습니다.";
            } else if (errorMessage.contains("권한") || errorMessage.contains("Unauthorized")) {
                statusCode = 403;
                responseMessage = "파일에 접근할 권한이 없습니다.";
            }
        }

        Map<String, Object> errorResponse = new HashMap<>();
        errorResponse.put("success", false);
        errorResponse.put("message", responseMessage);

        return ResponseEntity.status(statusCode).body(errorResponse);
    }

    @GetMapping("/view/{filename:.+}")
    public ResponseEntity<?> viewFile(
            @PathVariable String filename,
            HttpServletRequest request,
            Principal principal) {

        try {
            String userId = getUserIdFromPrincipal(principal);
            User user = userService.getUserProfile(userId);

            Resource resource = fileService.loadFileAsResource(filename, user.getId());

            File fileEntity = fileRepository.findByFilename(filename)
                    .orElseThrow(() -> new RuntimeException("파일을 찾을 수 없습니다."));

            if (!fileEntity.isPreviewable()) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "미리보기를 지원하지 않는 파일 형식입니다.");
                return ResponseEntity.status(415).body(errorResponse);
            }

            String originalFilename = fileEntity.getOriginalname();
            String encodedFilename = URLEncoder.encode(originalFilename, StandardCharsets.UTF_8)
                    .replaceAll("\\+", "%20");

            String contentDisposition = String.format(
                    "inline; filename=\"%s\"; filename*=UTF-8''%s",
                    originalFilename,
                    encodedFilename);

            long contentLength = fileEntity.getSize();

            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType(fileEntity.getMimetype()))
                    .contentLength(contentLength)
                    .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition)
                    .header(HttpHeaders.CACHE_CONTROL, "public, max-age=31536000, immutable")
                    .body(resource);

        } catch (Exception e) {
            log.error("파일 미리보기 중 에러 발생: {}", filename, e);
            return handleFileError(e);
        }
    }

    /**
     * Presigned URL 생성 (클라이언트 직접 S3 업로드용)
     */
    @Operation(summary = "Presigned URL 생성", description = "클라이언트가 직접 S3에 업로드할 수 있는 Presigned URL을 생성합니다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Presigned URL 생성 성공"),
            @ApiResponse(responseCode = "400", description = "잘못된 요청", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "401", description = "인증 실패", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "500", description = "서버 내부 오류", content = @Content(schema = @Schema(implementation = StandardResponse.class)))
    })
    @PostMapping("/upload/presigned")
    public ResponseEntity<?> generatePresignedUrl(
            @Valid @RequestBody PresignedUrlRequest request,
            Principal principal) {
        try {
            String userId = getUserIdFromPrincipal(principal);
            userService.getUserProfile(userId); // 사용자 인증 확인

            // 파일 크기 검증
            if (request.getFileSize() > 50 * 1024 * 1024) { // 50MB
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "파일 크기는 50MB를 초과할 수 없습니다.");
                return ResponseEntity.status(400).body(errorResponse);
            }

            // Presigned URL 생성
            String presignedUrl = s3FileService.generatePresignedUploadUrl(
                request.getFilename(), request.getContentType(), request.getFileSize());
            
            // 안전한 파일명 생성 (서버에서 생성한 파일명 사용)
            String safeFileName = com.ktb.chatapp.util.FileUtil.generateSafeFileName(request.getFilename());

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("presignedUrl", presignedUrl);
            response.put("filename", safeFileName);
            response.put("expiresIn", 900); // 15분 (초 단위)

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Presigned URL 생성 중 에러 발생", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Presigned URL 생성 중 오류가 발생했습니다.");
            errorResponse.put("error", e.getMessage());
            return ResponseEntity.status(500).body(errorResponse);
        }
    }

    /**
     * Presigned URL 업로드 완료 콜백
     */
    @Operation(summary = "업로드 완료 콜백", description = "클라이언트가 Presigned URL로 S3에 업로드 완료 후 호출하는 엔드포인트입니다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "파일 정보 저장 성공"),
            @ApiResponse(responseCode = "400", description = "잘못된 요청", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "401", description = "인증 실패", content = @Content(schema = @Schema(implementation = StandardResponse.class))),
            @ApiResponse(responseCode = "500", description = "서버 내부 오류", content = @Content(schema = @Schema(implementation = StandardResponse.class)))
    })
    @PostMapping("/upload/complete")
    public ResponseEntity<?> completeUpload(
            @Valid @RequestBody CompleteUploadRequest request,
            Principal principal) {
        try {
            String userId = getUserIdFromPrincipal(principal);
            User user = userService.getUserProfile(userId);

            // 파일 메타데이터 저장
            File savedFile = s3FileService.saveFileMetadata(
                request.getFilename(), request.getOriginalFilename(), 
                request.getContentType(), request.getFileSize(), user.getId());

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "파일 업로드 완료");

            Map<String, Object> fileData = new HashMap<>();
            fileData.put("_id", savedFile.getId());
            fileData.put("filename", savedFile.getFilename());
            fileData.put("originalname", savedFile.getOriginalname());
            fileData.put("mimetype", savedFile.getMimetype());
            fileData.put("size", savedFile.getSize());
            fileData.put("uploadDate", savedFile.getUploadDate());

            response.put("file", fileData);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("업로드 완료 처리 중 에러 발생", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "업로드 완료 처리 중 오류가 발생했습니다.");
            errorResponse.put("error", e.getMessage());
            return ResponseEntity.status(500).body(errorResponse);
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteFile(@PathVariable String id, Principal principal) {

        try {
            String userId = getUserIdFromPrincipal(principal);
            User user = userService.getUserProfile(userId);

            boolean deleted = fileService.deleteFile(id, user.getId());

            if (deleted) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", true);
                response.put("message", "파일이 삭제되었습니다.");
                return ResponseEntity.ok(response);
            } else {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "파일 삭제에 실패했습니다.");
                return ResponseEntity.status(400).body(errorResponse);
            }

        } catch (RuntimeException e) {
            log.error("파일 삭제 중 에러 발생: {}", id, e);
            String errorMessage = e.getMessage();

            if (errorMessage != null && errorMessage.contains("찾을 수 없습니다")) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "파일을 찾을 수 없습니다.");
                return ResponseEntity.status(404).body(errorResponse);
            } else if (errorMessage != null && errorMessage.contains("권한")) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "파일을 삭제할 권한이 없습니다.");
                return ResponseEntity.status(403).body(errorResponse);
            }

            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "파일 삭제 중 오류가 발생했습니다.");
            errorResponse.put("error", errorMessage);
            return ResponseEntity.status(500).body(errorResponse);
        }
    }

    private String getUserIdFromPrincipal(Principal principal) {
        if (principal instanceof JwtAuthenticationToken) {
            Jwt jwt = (Jwt) ((JwtAuthenticationToken) principal).getPrincipal();
            return jwt.getClaimAsString("userId");
        } else if (principal instanceof UsernamePasswordAuthenticationToken) {
            CustomUserDetails userDetails = (CustomUserDetails) ((UsernamePasswordAuthenticationToken) principal)
                    .getPrincipal();
            return userDetails.getId();
        }
        throw new IllegalStateException("Unsupported authentication type: " + principal.getClass().getName());
    }
}
