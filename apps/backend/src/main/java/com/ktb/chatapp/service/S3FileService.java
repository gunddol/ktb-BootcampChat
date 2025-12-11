package com.ktb.chatapp.service;

import com.ktb.chatapp.model.File;
import com.ktb.chatapp.model.Message;
import com.ktb.chatapp.model.Room;
import com.ktb.chatapp.repository.FileRepository;
import com.ktb.chatapp.repository.MessageRepository;
import com.ktb.chatapp.repository.RoomRepository;
import com.ktb.chatapp.util.FileUtil;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetUrlRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.io.IOException;
import java.net.MalformedURLException;
import java.time.Duration;
import java.time.LocalDateTime;

@Slf4j
@Service
@Primary
public class S3FileService implements FileService {

  private final FileRepository fileRepository;
  private final MessageRepository messageRepository;
  private final RoomRepository roomRepository;

  @Value("${aws.s3.bucket}")
  private String bucketName;

  @Value("${aws.region}")
  private String region;

  @Value("${aws.access-key}")
  private String accessKey;

  @Value("${aws.secret-key}")
  private String secretKey;

  // 로컬 다운로드를 위한 임시 디렉토리
  @Value("${file.upload-dir:./uploads}")
  private String localDownloadDir;

  private S3Client s3Client;
  private S3Presigner s3Presigner;

  public S3FileService(FileRepository fileRepository,
      MessageRepository messageRepository,
      RoomRepository roomRepository) {
    this.fileRepository = fileRepository;
    this.messageRepository = messageRepository;
    this.roomRepository = roomRepository;
  }

  @PostConstruct
  public void init() {
    StaticCredentialsProvider credentialsProvider = StaticCredentialsProvider.create(
        AwsBasicCredentials.create(accessKey, secretKey));
    Region awsRegion = Region.of(region);
    
    this.s3Client = S3Client.builder()
        .region(awsRegion)
        .credentialsProvider(credentialsProvider)
        .build();
    
    this.s3Presigner = S3Presigner.builder()
        .region(awsRegion)
        .credentialsProvider(credentialsProvider)
        .build();
  }

  @Override
  public FileUploadResult uploadFile(MultipartFile file, String uploaderId) {
    try {
      FileUtil.validateFile(file);

      String originalFilename = file.getOriginalFilename();
      if (originalFilename == null)
        originalFilename = "file";
      String safeFileName = FileUtil.generateSafeFileName(StringUtils.cleanPath(originalFilename));

      // S3 Upload
      PutObjectRequest putOb = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(safeFileName)
          .contentType(file.getContentType())
          .build();

      s3Client.putObject(putOb, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

      // Get URL
      String fileUrl = s3Client.utilities().getUrl(GetUrlRequest.builder()
          .bucket(bucketName)
          .key(safeFileName)
          .build()).toExternalForm();

      log.info("S3 파일 업로드 완료: {}", fileUrl);

      // DB Save
      File fileEntity = File.builder()
          .filename(safeFileName)
          .originalname(FileUtil.normalizeOriginalFilename(originalFilename))
          .mimetype(file.getContentType())
          .size(file.getSize())
          .path(fileUrl) // Store S3 URL instead of local path
          .user(uploaderId)
          .uploadDate(LocalDateTime.now())
          .build();

      File savedFile = fileRepository.save(fileEntity);

      return FileUploadResult.builder()
          .success(true)
          .file(savedFile)
          .build();

    } catch (IOException e) {
      log.error("S3 업로드 실패", e);
      throw new RuntimeException("S3 업로드 중 오류가 발생했습니다.", e);
    }
  }

  @Override
  public String storeFile(MultipartFile file, String subDirectory) {
    try {
      FileUtil.validateFile(file);

      String originalFilename = file.getOriginalFilename();
      if (originalFilename == null)
        originalFilename = "file";
      String safeFileName = FileUtil.generateSafeFileName(StringUtils.cleanPath(originalFilename));

      String key = (subDirectory != null && !subDirectory.isEmpty())
          ? subDirectory + "/" + safeFileName
          : safeFileName;

      PutObjectRequest putOb = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(key)
          .contentType(file.getContentType())
          .build();

      s3Client.putObject(putOb, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

      // Return Public URL
      return s3Client.utilities().getUrl(GetUrlRequest.builder()
          .bucket(bucketName)
          .key(key)
          .build()).toExternalForm();

    } catch (IOException e) {
      throw new RuntimeException("S3 저장 실패", e);
    }
  }

  @Override
  public Resource loadFileAsResource(String fileName, String requesterId) {
    // S3에서는 직접 URL로 접근하므로 이 메서드는 다운로드/중계 용도로 사용되거나
    // URL을 리소스 래핑해서 반환할 수 있음
    try {
      // 1. 권한 체크 로직은 동일하게 유지
      File fileEntity = fileRepository.findByFilename(fileName)
          .orElseThrow(() -> new RuntimeException("파일을 찾을 수 없습니다: " + fileName));

      Message message = messageRepository.findByFileId(fileEntity.getId())
          .orElseThrow(() -> new RuntimeException("파일과 연결된 메시지를 찾을 수 없습니다"));

      Room room = roomRepository.findById(message.getRoomId())
          .orElseThrow(() -> new RuntimeException("방을 찾을 수 없습니다"));

      if (!room.getParticipantIds().contains(requesterId)) {
        throw new RuntimeException("파일 접근 권한이 없습니다.");
      }

      // S3 URL을 바로 UrlResource로 반환
      String fileUrl = fileEntity.getPath();
      if (!fileUrl.startsWith("http")) {
        // 혹시 예전 로컬 경로 데이터가 있다면 처리 필요하지만 일단 S3 가정
        fileUrl = s3Client.utilities().getUrl(GetUrlRequest.builder()
            .bucket(bucketName)
            .key(fileName)
            .build()).toExternalForm();
      }

      return new UrlResource(fileUrl);

    } catch (MalformedURLException e) {
      throw new RuntimeException("URL 형식이 잘못되었습니다.", e);
    }
  }

  @Override
  public boolean deleteFile(String fileId, String requesterId) {
    File fileEntity = fileRepository.findById(fileId)
        .orElseThrow(() -> new RuntimeException("파일 없음"));

    if (!fileEntity.getUser().equals(requesterId)) {
      throw new RuntimeException("삭제 권한 없음");
    }

    // S3 Delete
    // DB에 저장된 path가 URL이라면 key만 추출해야 함.
    // 간단히 filename 필드를 key로 사용한다고 가정 (uploadFile 메서드 참고)
    try {
      s3Client.deleteObject(b -> b.bucket(bucketName).key(fileEntity.getFilename()));
      fileRepository.delete(fileEntity);
      return true;
    } catch (Exception e) {
      log.error("S3 삭제 실패", e);
      return false;
    }
  }

  //Presigned URL 생성 (클라이언트 직접 업로드)
  public String generatePresignedUploadUrl(String filename, String contentType, long fileSize) {
    try {
      // 파일명으로 검증
      if (filename == null || filename.trim().isEmpty()) {
        throw new RuntimeException("파일명이 올바르지 않습니다.");
      }

      String safeFileName = FileUtil.generateSafeFileName(filename);

      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(safeFileName)
          .contentType(contentType)
          .contentLength(fileSize)
          .build();

      PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
          .signatureDuration(Duration.ofMinutes(15))
          .putObjectRequest(putObjectRequest)
          .build();

      PresignedPutObjectRequest presignedRequest = s3Presigner.presignPutObject(presignRequest);
      String presignedUrl = presignedRequest.url().toString();

      log.info("Presigned URL 생성 완료: {} (유효기간: 15분)", safeFileName);
      return presignedUrl;

    } catch (Exception e) {
      log.error("Presigned URL 생성 실패", e);
      throw new RuntimeException("Presigned URL 생성 중 오류가 발생했습니다.", e);
    }
  }

  //Presigned URL 업로드 완료 후 파일 정보 저장
  public File saveFileMetadata(String filename, String originalFilename, String contentType, 
                                long fileSize, String uploaderId) {
    try {
      // S3 URL 생성
      String fileUrl = s3Client.utilities().getUrl(GetUrlRequest.builder()
          .bucket(bucketName)
          .key(filename)
          .build()).toExternalForm();

      // DB 저장
      File fileEntity = File.builder()
          .filename(filename)
          .originalname(FileUtil.normalizeOriginalFilename(originalFilename))
          .mimetype(contentType)
          .size(fileSize)
          .path(fileUrl)
          .user(uploaderId)
          .uploadDate(LocalDateTime.now())
          .build();

      File savedFile = fileRepository.save(fileEntity);
      log.info("파일 메타데이터 저장 완료: {}", savedFile.getId());
      return savedFile;

    } catch (Exception e) {
      log.error("파일 메타데이터 저장 실패", e);
      throw new RuntimeException("파일 메타데이터 저장 중 오류가 발생했습니다.", e);
    }
  }
}
