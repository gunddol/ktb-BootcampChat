# KTB BootcampChat

> Next.js + Spring Boot 실시간 채팅 애플리케이션

## 🔗 서비스 URL

- **Frontend**: https://chat.goorm-ktb-015.goorm.team
- **Backend API**: https://api.chat.goorm-ktb-015.goorm.team
- **Health Check**: https://api.chat.goorm-ktb-015.goorm.team/api/health

## 📚 문서

- **[운영 가이드](OPERATIONS.md)** - 프로덕션 운영 및 트러블슈팅
- **[Backend README](apps/backend/README.md)** - Backend 개발 가이드
- **[Frontend README](apps/frontend/README.md)** - Frontend 개발 가이드

## 🛠️ 기술 스택

### Frontend
- Next.js 15.1.9
- React 18.3.1
- Tailwind CSS 4.0
- Socket.IO Client

### Backend
- Spring Boot 3.5.7
- Java 21
- MongoDB 8.x
- Redis
- Netty Socket.IO 2.0.13

## 🚀 주요 스크립트

```bash
# 배포 상태 확인
./deployment-scripts/deploy-checking.sh

# Backend 업데이트
./deployment-scripts/fix-all-backends.sh

# Frontend 배포
./deployment-scripts/05-deploy-frontend.sh
```

## 📝 인프라

- **Backend**: 12 x t3.small
- **MongoDB**: 2 x t3.small (Primary + Backup)
- **Redis**: 3 x t3.small (Master + 2 Replicas)
- **Frontend**: S3 + CloudFront
- **Load Balancer**: ALB (Application Load Balancer)

## 📞 긴급 지원

시스템 장애 시 [OPERATIONS.md](OPERATIONS.md)의 트러블슈팅 섹션 참조
