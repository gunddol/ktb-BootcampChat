import axios, { isCancel, CancelToken } from 'axios';
import axiosInstance from './axios';
import { Toast } from '../components/Toast';

class FileService {
  constructor() {
    this.baseUrl = process.env.NEXT_PUBLIC_API_URL;
    this.uploadLimit = 50 * 1024 * 1024; // 50MB
    this.retryAttempts = 3;
    this.retryDelay = 1000;
    this.activeUploads = new Map();

    this.allowedTypes = {
      image: {
        extensions: ['.jpg', '.jpeg', '.png', '.gif', '.webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp'],
        maxSize: 10 * 1024 * 1024,
        name: '이미지'
      },
      document: {
        extensions: ['.pdf'],
        mimeTypes: ['application/pdf'],
        maxSize: 20 * 1024 * 1024,
        name: 'PDF 문서'
      }
    };
  }

  async validateFile(file) {
    if (!file) {
      const message = '파일이 선택되지 않았습니다.';
      Toast.error(message);
      return { success: false, message };
    }

    if (file.size > this.uploadLimit) {
      const message = `파일 크기는 ${this.formatFileSize(this.uploadLimit)}를 초과할 수 없습니다.`;
      Toast.error(message);
      return { success: false, message };
    }

    let isAllowedType = false;
    let maxTypeSize = 0;
    let typeConfig = null;

    for (const config of Object.values(this.allowedTypes)) {
      if (config.mimeTypes.includes(file.type)) {
        isAllowedType = true;
        maxTypeSize = config.maxSize;
        typeConfig = config;
        break;
      }
    }

    if (!isAllowedType) {
      const message = '지원하지 않는 파일 형식입니다.';
      Toast.error(message);
      return { success: false, message };
    }

    if (file.size > maxTypeSize) {
      const message = `${typeConfig.name} 파일은 ${this.formatFileSize(maxTypeSize)}를 초과할 수 없습니다.`;
      Toast.error(message);
      return { success: false, message };
    }

    const ext = this.getFileExtension(file.name);
    if (!typeConfig.extensions.includes(ext.toLowerCase())) {
      const message = '파일 확장자가 올바르지 않습니다.';
      Toast.error(message);
      return { success: false, message };
    }

    return { success: true };
  }

  async uploadFile(file, onProgress, token, sessionId, usePresignedUrl = true) {
    const validationResult = await this.validateFile(file);
    if (!validationResult.success) {
      return validationResult;
    }

    // Presigned URL 방식 사용 (기본값)
    if (usePresignedUrl) {
      return this.uploadFileWithPresignedUrl(file, onProgress, token, sessionId);
    }

    // 기존 방식 (하위 호환성)
    return this.uploadFileLegacy(file, onProgress, token, sessionId);
  }

  async uploadFileWithPresignedUrl(file, onProgress, token, sessionId, retryCount = 0) {
    const source = CancelToken.source();
    this.activeUploads.set(file.name, source);

    try {
      // 1. Presigned URL 요청 (재시도 가능)
      let presignedResponse;
      try {
        const presignedUrlEndpoint = this.baseUrl ?
          `${this.baseUrl}/api/files/upload/presigned` :
          '/api/files/upload/presigned';

        presignedResponse = await axiosInstance.post(
          presignedUrlEndpoint,
          {
            filename: file.name,
            contentType: file.type,
            fileSize: file.size
          },
          {
            cancelToken: source.token,
            withCredentials: true,
            timeout: 10000 // 10초 타임아웃
          }
        );
      } catch (error) {
        // Presigned URL 요청 실패 시 재시도
        if (retryCount < this.retryAttempts && this.isRetryableError(error)) {
          await this.delay(this.retryDelay * (retryCount + 1));
          return this.uploadFileWithPresignedUrl(file, onProgress, token, sessionId, retryCount + 1);
        }
        throw error;
      }

      if (!presignedResponse.data || !presignedResponse.data.success) {
        throw new Error(presignedResponse.data?.message || 'Presigned URL 생성에 실패했습니다.');
      }

      const { presignedUrl, filename: serverFilename } = presignedResponse.data;

      // 2. Presigned URL로 직접 S3 업로드 (재시도 가능)
      let s3UploadResponse;
      try {
        s3UploadResponse = await axios.put(presignedUrl, file, {
          headers: {
            'Content-Type': file.type
          },
          cancelToken: source.token,
          timeout: 300000, // 5분 타임아웃 (대용량 파일용)
          onUploadProgress: (progressEvent) => {
            if (onProgress) {
              const percentCompleted = Math.round(
                (progressEvent.loaded * 100) / progressEvent.total
              );
              onProgress(percentCompleted);
            }
          }
        });
      } catch (error) {
        // S3 업로드 실패 시 재시도
        if (retryCount < this.retryAttempts && this.isRetryableError(error)) {
          await this.delay(this.retryDelay * (retryCount + 1));
          return this.uploadFileWithPresignedUrl(file, onProgress, token, sessionId, retryCount + 1);
        }
        throw error;
      }

      // 3. 업로드 완료 콜백 (재시도 가능)
      let completeResponse;
      try {
        const completeEndpoint = this.baseUrl ?
          `${this.baseUrl}/api/files/upload/complete` :
          '/api/files/upload/complete';

        completeResponse = await axiosInstance.post(
          completeEndpoint,
          {
            filename: serverFilename,
            originalFilename: file.name,
            contentType: file.type,
            fileSize: file.size
          },
          {
            cancelToken: source.token,
            withCredentials: true,
            timeout: 10000
          }
        );
      } catch (error) {
        // 콜백 실패 시 재시도
        if (retryCount < this.retryAttempts && this.isRetryableError(error)) {
          await this.delay(this.retryDelay * (retryCount + 1));
          return this.uploadFileWithPresignedUrl(file, onProgress, token, sessionId, retryCount + 1);
        }
        throw error;
      }

      this.activeUploads.delete(file.name);

      if (!completeResponse.data || !completeResponse.data.success) {
        return {
          success: false,
          message: completeResponse.data?.message || '파일 업로드 완료 처리에 실패했습니다.'
        };
      }

      const fileData = completeResponse.data.file;
      return {
        success: true,
        data: {
          ...completeResponse.data,
          file: {
            ...fileData,
            url: this.getFileUrl(fileData.filename, true)
          }
        }
      };

    } catch (error) {
      this.activeUploads.delete(file.name);

      if (isCancel(error)) {
        return {
          success: false,
          message: '업로드가 취소되었습니다.'
        };
      }

      if (error.response?.status === 401) {
        throw new Error('Authentication expired. Please login again.');
      }

      // 최대 재시도 횟수 초과 시 기존 방식으로 폴백
      if (retryCount >= this.retryAttempts) {
        console.warn('Presigned URL 업로드 최대 재시도 횟수 초과, 기존 방식으로 폴백:', error);
        return this.uploadFileLegacy(file, onProgress, token, sessionId);
      }

      return this.handleUploadError(error);
    }
  }

  delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async uploadFileLegacy(file, onProgress, token, sessionId) {
    const source = CancelToken.source();
    this.activeUploads.set(file.name, source);

    try {
      const formData = new FormData();
      formData.append('file', file);

      const uploadUrl = this.baseUrl ?
        `${this.baseUrl}/api/files/upload` :
        '/api/files/upload';

      const response = await axiosInstance.post(uploadUrl, formData, {
        headers: {
          'Content-Type': 'multipart/form-data'
        },
        cancelToken: source.token,
        withCredentials: true,
        onUploadProgress: (progressEvent) => {
          if (onProgress) {
            const percentCompleted = Math.round(
              (progressEvent.loaded * 100) / progressEvent.total
            );
            onProgress(percentCompleted);
          }
        }
      });

      this.activeUploads.delete(file.name);

      if (!response.data || !response.data.success) {
        return {
          success: false,
          message: response.data?.message || '파일 업로드에 실패했습니다.'
        };
      }

      const fileData = response.data.file;
      return {
        success: true,
        data: {
          ...response.data,
          file: {
            ...fileData,
            url: this.getFileUrl(fileData.filename, true)
          }
        }
      };

    } catch (error) {
      this.activeUploads.delete(file.name);

      if (isCancel(error)) {
        return {
          success: false,
          message: '업로드가 취소되었습니다.'
        };
      }

      if (error.response?.status === 401) {
        throw new Error('Authentication expired. Please login again.');
      }

      return this.handleUploadError(error);
    }
  }
  async downloadFile(filename, originalname, token, sessionId) {
    try {
      // 파일 존재 여부 먼저 확인
      const downloadUrl = this.getFileUrl(filename, false);
      // axios 인터셉터가 자동으로 인증 헤더를 추가합니다
      const checkResponse = await axiosInstance.head(downloadUrl, {
        validateStatus: status => status < 500,
        withCredentials: true
      });

      if (checkResponse.status === 404) {
        return {
          success: false,
          message: '파일을 찾을 수 없습니다.'
        };
      }

      if (checkResponse.status === 403) {
        return {
          success: false,
          message: '파일에 접근할 권한이 없습니다.'
        };
      }

      if (checkResponse.status !== 200) {
        return {
          success: false,
          message: '파일 다운로드 준비 중 오류가 발생했습니다.'
        };
      }

      // axios 인터셉터가 자동으로 인증 헤더를 추가합니다
      const response = await axiosInstance({
        method: 'GET',
        url: downloadUrl,
        responseType: 'blob',
        timeout: 30000,
        withCredentials: true
      });

      const contentType = response.headers['content-type'];
      const contentDisposition = response.headers['content-disposition'];
      let finalFilename = originalname;

      if (contentDisposition) {
        const filenameMatch = contentDisposition.match(
          /filename\*=UTF-8''([^;]+)|filename="([^"]+)"|filename=([^;]+)/
        );
        if (filenameMatch) {
          finalFilename = decodeURIComponent(
            filenameMatch[1] || filenameMatch[2] || filenameMatch[3]
          );
        }
      }

      const blob = new Blob([response.data], {
        type: contentType || 'application/octet-stream'
      });

      const blobUrl = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = blobUrl;
      link.download = finalFilename;
      link.style.display = 'none';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      setTimeout(() => {
        window.URL.revokeObjectURL(blobUrl);
      }, 100);

      return { success: true };

    } catch (error) {
      if (error.response?.status === 401) {
        throw new Error('Authentication expired. Please login again.');
      }

      return this.handleDownloadError(error);
    }
  }

  getFileUrl(filename, forPreview = false) {
    if (!filename) return '';

    const baseUrl = process.env.NEXT_PUBLIC_API_URL || '';
    const endpoint = forPreview ? 'view' : 'download';
    return `${baseUrl}/api/files/${endpoint}/${filename}`;
  }

  getPreviewUrl(file, token, sessionId, withAuth = true) {
    if (!file?.filename) return '';

    const baseUrl = `${process.env.NEXT_PUBLIC_API_URL}/api/files/view/${file.filename}`;

    if (!withAuth) return baseUrl;

    if (!token || !sessionId) return baseUrl;

    // URL 객체 생성 전 프로토콜 확인
    const url = new URL(baseUrl);
    url.searchParams.append('token', encodeURIComponent(token));
    url.searchParams.append('sessionId', encodeURIComponent(sessionId));

    return url.toString();
  }

  getFileType(filename) {
    if (!filename) return 'unknown';
    const ext = this.getFileExtension(filename).toLowerCase();
    for (const [type, config] of Object.entries(this.allowedTypes)) {
      if (config.extensions.includes(ext)) {
        return type;
      }
    }
    return 'unknown';
  }

  getFileExtension(filename) {
    if (!filename) return '';
    const parts = filename.split('.');
    return parts.length > 1 ? `.${parts.pop().toLowerCase()}` : '';
  }

  formatFileSize(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${parseFloat((bytes / Math.pow(1024, i)).toFixed(2))} ${units[i]}`;
  }

  getHeaders(token, sessionId) {
    if (!token || !sessionId) {
      return {
        'Accept': 'application/json, */*'
      };
    }
    return {
      'x-auth-token': token,
      'x-session-id': sessionId,
      'Accept': 'application/json, */*'
    };
  }

  handleUploadError(error) {
    console.error('Upload error:', error);

    if (error.code === 'ECONNABORTED') {
      return {
        success: false,
        message: '파일 업로드 시간이 초과되었습니다.'
      };
    }

    if (axios.isAxiosError(error)) {
      const status = error.response?.status;
      const message = error.response?.data?.message;

      switch (status) {
        case 400:
          return {
            success: false,
            message: message || '잘못된 요청입니다.'
          };
        case 401:
          return {
            success: false,
            message: '인증이 필요합니다.'
          };
        case 413:
          return {
            success: false,
            message: '파일이 너무 큽니다.'
          };
        case 415:
          return {
            success: false,
            message: '지원하지 않는 파일 형식입니다.'
          };
        case 500:
          return {
            success: false,
            message: '서버 오류가 발생했습니다.'
          };
        default:
          return {
            success: false,
            message: message || '파일 업로드에 실패했습니다.'
          };
      }
    }

    return {
      success: false,
      message: error.message || '알 수 없는 오류가 발생했습니다.',
      error
    };
  }

  handleDownloadError(error) {
    console.error('Download error:', error);

    if (error.code === 'ECONNABORTED') {
      return {
        success: false,
        message: '파일 다운로드 시간이 초과되었습니다.'};
    }

    if (axios.isAxiosError(error)) {
      const status = error.response?.status;
      const message = error.response?.data?.message;

      switch (status) {
        case 404:
          return {
            success: false,
            message: '파일을 찾을 수 없습니다.'
          };
        case 403:
          return {
            success: false,
            message: '파일에 접근할 권한이 없습니다.'
          };
        case 400:
          return {
            success: false,
            message: message || '잘못된 요청입니다.'
          };
        case 500:
          return {
            success: false,
            message: '서버 오류가 발생했습니다.'
          };
        default:
          return {
            success: false,
            message: message || '파일 다운로드에 실패했습니다.'
          };
      }
    }

    return {
      success: false,
      message: error.message || '알 수 없는 오류가 발생했습니다.',
      error
    };
  }

  cancelUpload(filename) {
    const source = this.activeUploads.get(filename);
    if (source) {
      source.cancel('Upload canceled by user');
      this.activeUploads.delete(filename);
      return {
        success: true,
        message: '업로드가 취소되었습니다.'
      };
    }
    return {
      success: false,
      message: '취소할 업로드를 찾을 수 없습니다.'
    };
  }

  cancelAllUploads() {
    let canceledCount = 0;
    for (const [filename, source] of this.activeUploads) {
      source.cancel('All uploads canceled');
      this.activeUploads.delete(filename);
      canceledCount++;
    }
    
    return {
      success: true,
      message: `${canceledCount}개의 업로드가 취소되었습니다.`,
      canceledCount
    };
  }

  getErrorMessage(status) {
    switch (status) {
      case 400:
        return '잘못된 요청입니다.';
      case 401:
        return '인증이 필요합니다.';
      case 403:
        return '파일에 접근할 권한이 없습니다.';
      case 404:
        return '파일을 찾을 수 없습니다.';
      case 413:
        return '파일이 너무 큽니다.';
      case 415:
        return '지원하지 않는 파일 형식입니다.';
      case 500:
        return '서버 오류가 발생했습니다.';
      case 503:
        return '서비스를 일시적으로 사용할 수 없습니다.';
      default:
        return '알 수 없는 오류가 발생했습니다.';
    }
  }

  isRetryableError(error) {
    if (!error.response) {
      return true; // 네트워크 오류는 재시도 가능
    }

    const status = error.response.status;
    return [408, 429, 500, 502, 503, 504].includes(status);
  }
}

export default new FileService();