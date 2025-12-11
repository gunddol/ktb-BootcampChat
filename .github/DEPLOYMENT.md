# GitHub Actions CI/CD 배포 가이드

> 자동화된 Backend/Frontend 배포 사용 가이드

## 📋 목차

- [개요](#개요)
- [GitHub Secrets 설정](#github-secrets-설정)
- [워크플로우 사용법](#워크플로우-사용법)
- [트러블슈팅](#트러블슈팅)

---

## 개요

이 프로젝트는 GitHub Actions를 사용하여 Backend와 Frontend를 자동으로 배포합니다.

### 자동 배포 트리거

- **Backend**: `apps/backend/` 경로의 파일이 변경되면 자동 배포
- **Frontend**: `apps/frontend/` 경로의 파일이 변경되면 자동 배포

### 수동 배포

GitHub Actions 탭에서 원하는 워크플로우를 선택하고 "Run workflow" 버튼으로 수동 실행 가능

---

## GitHub Secrets 설정

### 1. GitHub 저장소 설정 페이지 이동

```
Settings → Secrets and variables → Actions → New repository secret
```

### 2. 필수 Secrets 추가

#### AWS 자격 증명
```
이름:AWS_ACCESS_KEY_ID
값: (AWS IAM Access Key)

이름: AWS_SECRET_ACCESS_KEY
값: (AWS IAM Secret Key)
```

> [!IMPORTANT]
> IAM 사용자는 다음 권한 필요:
> - EC2: DescribeInstances
> - ELB: DescribeTargetHealth
> - S3: PutObject, DeleteObject, ListBucket
> - CloudFront: CreateInvalidation

#### Backend 배포용
```
이름: EC2_SSH_KEY
값: (ktb-015-key.pem 파일의 전체 내용)

이름: BASTION_IP
값: 52.79.105.90

이름: BACKEND_TARGET_GROUP_ARN
값: arn:aws:elasticloadbalancing:ap-northeast-2:613482338543:targetgroup/ktb-backend-tg/11e1ba2e4e456aeb
```

#### Backend 환경 변수
```
이름: MONGO_URI
값: mongodb://10.0.101.160:27017/ktb-chat

이름: REDIS_HOST
값: localhost

이름: REDIS_PORT
값: 6379

이름: REDIS_PASSWORD
값: ktb-015

이름: JWT_SECRET
값: (현재 사용 중인 JWT Secret)

이름: ENCRYPTION_KEY
값: (현재 사용 중인 Encryption Key)

이름: ENCRYPTION_SALT
값: (현재 사용 중인 Encryption Salt)
```

#### Frontend 배포용
```
이름: S3_BUCKET_NAME
값: ktb-015-chat-frontend

이름: CLOUDFRONT_DISTRIBUTION_ID
값: (CloudFront Distribution ID - AWS Console에서 확인)
```

---

## 워크플로우 사용법

### Backend 배포

#### 자동 배포
```bash
# 1. Backend 코드 수정
vim apps/backend/src/main/java/...

# 2. Commit & Push
git add apps/backend/
git commit -m "Update backend feature"
git push origin main

# 3. GitHub Actions 자동 실행
# - JAR 빌드
# - EC2 배포
# - Health check
```

#### 수동 배포
1. GitHub 저장소의 **Actions** 탭으로 이동
2. 왼쪽에서 **Backend Deployment** 선택
3. **Run workflow** 버튼 클릭
4. 브랜치 선택 (main) → **Run workflow**

### Frontend 배포

#### 자동 배포
```bash
# 1. Frontend 코드 수정
vim apps/frontend/pages/...

# 2. Commit & Push
git add apps/frontend/
git commit -m "Update frontend UI"
git push origin main

# 3. GitHub Actions 자동 실행
# - Next.js 빌드
# - S3 업로드
# - CloudFront 무효화
```

#### 수동 배포
1. GitHub 저장소의 **Actions** 탭으로 이동
2. 왼쪽에서 **Frontend Deployment** 선택
3. **Run workflow** 버튼 클릭
4. 브랜치 선택 (main) → **Run workflow**

---

## 배포 프로세스

### Backend Deployment Workflow

```
1. Code Checkout
     ↓
2. Java 21 Setup
     ↓
3. Maven Build (JAR)
     ↓
4. Upload JAR Artifact
     ↓
5. AWS Credentials Setup
     ↓
6. SSH Key Configuration
     ↓
7. Deploy to 12 EC2 Instances
     ↓
8. Verify Target Health
     ↓
9. Success/Failure Notification
```

**예상 시간**: 3-5분

### Frontend Deployment Workflow

```
1. Code Checkout
     ↓
2. Node.js Setup
     ↓
3. Install Dependencies
     ↓
4. Next.js Build (Static Export)
     ↓
5. AWS Credentials Setup
     ↓
6. Upload to S3
     ↓
7. CloudFront Cache Invalidation
     ↓
8. Verify Deployment
     ↓
9. Success/Failure Notification
```

**예상 시간**: 2-3분

---

## 트러블슈팅

### Backend 배포 실패

#### 1. JAR 빌드 실패
```
오류: Build failed with Maven

해결:
- 로컬에서 빌드 확인: cd apps/backend && ./mvnw clean package
- Java 버전 확인 (21 필요)
- pom.xml 문법 확인
```

#### 2. EC2 연결 실패
```
오류: Permission denied (publickey)

해결:
1. EC2_SSH_KEY Secret 확인
2. 키 형식 확인 (-----BEGIN RSA PRIVATE KEY-----)
3. Bastion IP 확인: BASTION_IP = 52.79.105.90
```

#### 3. Health Check 실패
```
오류: Instances are unhealthy

해결:
1. EC2 콘솔에서 인스턴스 상태 확인
2. 로그 확인:
   ssh -i ~/.ssh/ktb-015-key.pem ubuntu@[BASTION_IP]
   ssh ubuntu@[BACKEND_IP]
   sudo journalctl -u ktb-backend -n 100
3. 환경 변수 확인 (Secrets 설정)
```

### Frontend 배포 실패

#### 1. Build 실패
```
오류: Next.js build failed

해결:
- 로컬에서 빌드 확인: cd apps/frontend && npm run build
- Node 버전 확인 (18 필요)
- 의존성 확인: npm install
```

#### 2. S3 업로드 실패
```
오류: Access Denied (S3)

해결:
1. AWS credentials 확인
2. S3 버킷 권한 확인
3. IAM 사용자 S3 권한 확인 (PutObject, DeleteObject)
```

#### 3. CloudFront 무효화 실패
```
오류: Invalid Distribution ID

해결:
1. CLOUDFRONT_DISTRIBUTION_ID Secret 확인
2. AWS Console에서 Distribution ID 재확인:
   CloudFront → Distributions → ID 복사
```

### 워크플로우 로그 확인

1. GitHub 저장소의 **Actions** 탭
2. 실패한 워크플로우 클릭
3. 각 Step 클릭하여 상세 로그 확인

---

## 배포 확인

### Backend
```bash
# Health check
curl https://api.chat.goorm-ktb-015.goorm.team/api/health

# 예상 응답
{"status":"ok","env":"prod"}
```

### Frontend
```bash
# 접속
open https://chat.goorm-ktb-015.goorm.team

# 또는
curl -I https://chat.goorm-ktb-015.goorm.team
```

---

## 롤백

### 이전 버전으로 롤백
```bash
# 1. 이전 커밋으로 revert
git revert HEAD
git push origin main

# 2. 자동으로 이전 버전 배포됨
```

### 또는 수동 배포
```bash
# 로컬에서 기존 스크립트 사용
./deployment-scripts/fix-all-backends.sh  # Backend
./deployment-scripts/05-deploy-frontend.sh  # Frontend
```

---

## FAQ

**Q: main 브랜치가 아닌 다른 브랜치에서 배포하려면?**

A: 워크플로우 파일 수정:
```yaml
on:
  push:
    branches: [main, develop]  # develop 추가
```

**Q: 특정 시간에만 배포하려면?**

A: workflow_dispatch만 사용하고 push 트리거 제거

**Q: 배포 알림을 Slack으로 받으려면?**

A: [slack-github-action](https://github.com/marketplace/actions/slack-send) 사용

---

## 관련 파일

- Backend Workflow: [`.github/workflows/backend-deploy.yml`](../.github/workflows/backend-deploy.yml)
- Frontend Workflow: [`.github/workflows/frontend-deploy.yml`](../.github/workflows/frontend-deploy.yml)
- Backend Deploy Script: [`deployment-scripts/deploy-backend-jar.sh`](../deployment-scripts/deploy-backend-jar.sh)
