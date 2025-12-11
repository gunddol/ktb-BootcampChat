package com.ktb.chatapp.controller;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.HandlerMapping;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetUrlRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;

/**
 * S3에 저장된 파일을 /api/uploads/** 경로로 서빙하는 프록시 컨트롤러
 * 
 * 기존 LocalFileService에서 S3FileService로 전환하면서 발생한
 * 상대 경로 URL 호환성 문제를 해결합니다.
 */
@Slf4j
@RestController
@RequestMapping("/api/uploads")
public class UploadsProxyController {

  @Value("${aws.s3.bucket}")
  private String bucketName;

  @Value("${aws.region}")
  private String region;

  /**
   * /api/uploads/** 경로로 요청이 오면 S3 URL로 리다이렉트
   * 
   * @param request HTTP 요청
   * @return S3 URL로 리다이렉트
   */
  @GetMapping("/**")
  public ResponseEntity<Void> redirectToS3(HttpServletRequest request) {
    try {
      // URL 패턴에서 실제 파일 경로 추출
      String path = (String) request.getAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE);

      // /api/uploads/ 부분 제거하여 S3 key 생성
      String s3Key = path.replace("/api/uploads/", "");

      log.debug("S3 proxy request - Path: {}, S3 Key: {}", path, s3Key);

      // S3 클라이언트 생성 (매 요청마다 생성하지만 가벼운 작업)
      try (S3Client s3Client = S3Client.builder()
          .region(Region.of(region))
          .build()) {

        // S3에 파일이 존재하는지 확인
        try {
          HeadObjectRequest headRequest = HeadObjectRequest.builder()
              .bucket(bucketName)
              .key(s3Key)
              .build();

          s3Client.headObject(headRequest);

          // 파일이 존재하면 S3 URL 생성
          String s3Url = s3Client.utilities().getUrl(GetUrlRequest.builder()
              .bucket(bucketName)
              .key(s3Key)
              .build()).toExternalForm();

          log.info("Redirecting to S3: {} -> {}", path, s3Url);

          // S3 URL로 리다이렉트 (302 Found)
          return ResponseEntity.status(HttpStatus.FOUND)
              .location(URI.create(s3Url))
              .build();

        } catch (NoSuchKeyException e) {
          log.warn("File not found in S3: {}", s3Key);
          return ResponseEntity.notFound().build();
        }
      }

    } catch (Exception e) {
      log.error("Error proxying to S3", e);
      return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
    }
  }
}
