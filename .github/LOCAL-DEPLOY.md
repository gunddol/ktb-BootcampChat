# 로컬 수동 배포 가이드 (Manual Deployment)

이 문서는 GitHub Actions를 사용하지 않고 로컬 환경에서 수동으로 Backend 및 Frontend를 배포하는 방법을 설명합니다.

## Backend 수동 배포

Backend 배포는 3단계로 진행됩니다:
1. 환경 변수 설정
2. Maven Build (JAR 생성)
3. 배포 스크립트 실행 (Bastion -> EC2 배포)

### 1. 터미널에서 실행
아래 명령어를 복사하여 터미널에서 순차적으로 실행하세요:

```bash
# ------------------------------------------------------------------
# 1. 환경변수 설정 (필수)
# ------------------------------------------------------------------
export BASTION_IP=52.79.105.90
export MONGO_URI=mongodb://10.0.101.160:27017/ktb-chat
export REDIS_HOST=10.0.101.163
export REDIS_PORT=6379
export REDIS_PASSWORD=ktb-015
export JWT_SECRET=78ba3b45fa8b7a3c50e34acbcd887f76ca387034712e152b7bb20bd82841067a
export ENCRYPTION_KEY=7132063e4cae50af2b8b834e417de700985d82c081c072a91a8c96692fb61f625ec487c6e9d54d61507115db8d61a0e18e90647739fc6c69a56e3a63ef821fe8
export ENCRYPTION_SALT=c6e78f35b4414a26e69142befdd7561ae14bccd8e31b50aafedd2d834eeeb061

# ------------------------------------------------------------------
# 2. JAR 빌드
# ------------------------------------------------------------------
echo "🔨 Building Backend JAR..."
cd apps/backend
./mvnw clean package -DskipTests
cd ../..

# ------------------------------------------------------------------
# 3. 배포 스크립트 실행
# ------------------------------------------------------------------
echo "🚀 Deploying to EC2..."
./deployment-scripts/deploy-backend-jar.sh apps/backend/target/ktb-chat-backend-0.0.1-SNAPSHOT.jar
```

---

## Frontend 수동 배포

Frontend는 전용 스크립트를 통해 빌드, S3 업로드, CloudFront 무효화가 자동으로 수행됩니다.

### 1. 실행 명령어

```bash
./deployment-scripts/05-deploy-frontend.sh
```

### 2. 주요 기능
- `package.json` 의존성 자동 설치
- `next.config.js` 자동 생성 (`output: 'export'` 적용)
- `.env.production` 자동 생성
- Next.js 빌드 및 S3 업로드
- CloudFront 캐시 무효화 및 배포 확인

> **참고**: 별도의 환경 변수 설정 없이 스크립트 내부에서 `.env.deployment`를 로드하거나 기본값을 사용하여 배포합니다.
