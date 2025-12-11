# KTB BootcampChat 운영 가이드

> AWS 프로덕션 환경 운영 가이드

## 🎯 서비스 정보

- **Frontend**: https://chat.goorm-ktb-015.goorm.team
- **Backend API**: https://api.chat.goorm-ktb-015.goorm.team
- **Health Check**: https://api.chat.goorm-ktb-015.goorm.team/api/health

### 인프라 구성
- **Backend**: 12 x t3.small (HTTP:5001, Socket.IO:5002)
- **MongoDB**: 2 x t3.small (Primary + Backup)
- **Redis**: 3 x t3.small (Master + 2 Replicas)
- **ALB**: Application Load Balancer (HTTPS:443, HTTP:80→HTTPS)
- **Frontend**: S3 + CloudFront

---

## 📋 주요 스크립트

### 상태 확인
```bash
# 전체 배포 상태 확인
./deployment-scripts/99-check-deployment.sh
```

### Backend 관리
```bash
# 전체 backend 인스턴스 업데이트
./deployment-scripts/fix-all-backends.sh

# 개별 backend 인스턴스 수정
./deployment-scripts/fix-one-backend.sh [INSTANCE_IP]

# Backend Redis 설정 수정
./deployment-scripts/fix-backend-redis.sh
```

### Frontend 배포
```bash
# Frontend 빌드 및 S3 배포
./deployment-scripts/05-deploy-frontend.sh
```

### SSL 인증서 관리
```bash
# 와일드카드 인증서 생성 (필요시)
./deployment-scripts/setup-wildcard-certificate.sh

# ALB 인증서 업데이트
./deployment-scripts/update-alb-certificate.sh [CERTIFICATE_ARN]

# Target Group Health Check HTTP로 변경
./deployment-scripts/fix-target-group-healthcheck.sh
```

---

## 🔧 운영 작업

### Backend 인스턴스 접속
```bash
# 인스턴스 목록 확인
cat .backend-instances

# SSH 접속
ssh -i ~/.ssh/ktb-015-key.pem ubuntu@[INSTANCE_IP]
```

### 애플리케이션 제어
각 backend 인스턴스에서:
```bash
cd /home/ubuntu/ktb-chat-backend

# 상태 확인
./app-control.sh status

# 재시작
./app-control.sh restart

# 로그 확인
tail -f logs/app.log
```

### Target Health 확인
```bash
aws elbv2 describe-target-health \
  --target-group-arn [TG_ARN] \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' \
  --output table
```

---

## 🚨 트러블슈팅

### Backend Unhealthy
```bash
# 1. 인스턴스 접속
ssh -i ~/.ssh/ktb-015-key.pem ubuntu@[INSTANCE_IP]

# 2. 애플리케이션 상태 확인
cd /home/ubuntu/ktb-chat-backend
./app-control.sh status

# 3. 로그 확인
tail -100 logs/app.log

# 4. 재시작
./app-control.sh restart
```

### MongoDB 연결 문제
```bash
# MongoDB primary IP 확인
cat .env.deployment | grep MONGODB_PRIMARY_IP

# MongoDB 연결 테스트
mongosh mongodb://[MONGODB_PRIMARY_IP]:27017
```

### Redis 연결 문제
```bash
# Redis master IP 확인
cat .env.deployment | grep REDIS_MASTER_IP

# Redis 연결 테스트
redis-cli -h [REDIS_MASTER_IP] ping
```

### SSL 인증서 오류
```bash
# HTTP로 health check 테스트
curl http://api.chat.goorm-ktb-015.goorm.team/api/health

# HTTPS 인증서 확인
openssl s_client -connect api.chat.goorm-ktb-015.goorm.team:443 \
  -servername api.chat.goorm-ktb-015.goorm.team < /dev/null 2>/dev/null | \
  openssl x509 -noout -text | grep -A 2 "Subject Alternative Name"
```

---

## 📊 환경 변수

주요 환경 변수는 `.env.deployment` 파일에 저장되어 있습니다:
```bash
# 프로젝트 설정
PROJECT_NAME=ktb-BootcampChat
DOMAIN=chat.goorm-ktb-015.goorm.team
KEY_NAME=ktb-015-key

# Database
MONGODB_PRIMARY_IP=10.0.102.22
REDIS_MASTER_IP=[자동 설정]

# Security Group IDs
BACKEND_SG_ID=sg-09a1bbb62bcd82f2d
DATABASE_SG_ID=sg-0dfb543bdca2ec8a1
ALB_SG_ID=sg-04decdff52481d3b0
```

---

## 🔐 보안

### SSH 키
- **파일**: `~/.ssh/ktb-015-key.pem`
- **권한**: `chmod 400 ~/.ssh/ktb-015-key.pem`

### 비밀번호
```bash
MONGODB_ADMIN_PASSWORD=ktb-015
REDIS_PASSWORD=ktb-015
```

---

## 📞 긴급 연락

시스템 장애 발생 시:
1. **`99-check-deployment.sh`** 실행하여 전체 상태 확인
2. **Unhealthy 인스턴스** 재시작
3. **ALB 로그** 확인
4. **CloudWatch 메트릭** 확인
