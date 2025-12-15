#!/bin/bash
# GitHub Actions용 Backend 배포 스크립트
# 사용법: ./deploy-backend-jar.sh <JAR_FILE_PATH>

set -e

if [ -z "$1" ]; then
    echo "❌ Usage: $0 <JAR_FILE_PATH>"
    exit 1
fi

JAR_FILE="$1"

if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    exit 1
fi

echo "🚀 Backend Deployment"
echo "======================================"
echo "JAR: $JAR_FILE"
echo ""

# 환경 변수 확인
REQUIRED_VARS=("BASTION_IP" "MONGO_URI" "REDIS_HOST" "REDIS_PORT" "REDIS_PASSWORD" "JWT_SECRET" "ENCRYPTION_KEY" "ENCRYPTION_SALT")

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Required environment variable not set: $var"
        exit 1
    fi
done

KEY_PATH="$HOME/.ssh/ktb-015-key.pem"
REGION="${AWS_REGION:-ap-northeast-2}"

if [ ! -f "$KEY_PATH" ]; then
    echo "❌ SSH key not found: $KEY_PATH"
    exit 1
fi

# Backend 인스턴스 IP 목록 가져오기
echo "📋 Getting Backend instance IPs..."
# 1) 우선 Name 패턴으로 검색 (backend-a-*, backend-b-*)
BACKEND_IPS=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
              "Name=tag:Name,Values=backend-a-*,backend-b-*" \
    --region "$REGION" \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text)

# 2) 없으면 이전 방식(Type=backend)으로 폴백
if [ -z "$BACKEND_IPS" ]; then
    BACKEND_IPS=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=backend" "Name=instance-state-name,Values=running" \
        --region "$REGION" \
        --query 'Reservations[].Instances[].PrivateIpAddress' \
        --output text)
fi

if [ -z "$BACKEND_IPS" ]; then
    echo "❌ No Backend instances found! (Name=backend-a/b-* or Type=backend)"
    exit 1
fi

INSTANCE_COUNT=$(echo "$BACKEND_IPS" | wc -w)
echo "✅ Found $INSTANCE_COUNT Backend instances"
echo "IPs: $BACKEND_IPS"
echo ""

# JAR 파일을 Bastion으로 먼저 복사 (한 번만, 모든 인스턴스가 공유)
echo "📤 Uploading JAR to Bastion..."
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no \
    "$JAR_FILE" ubuntu@${BASTION_IP}:/tmp/ktb-chat-backend.jar

# 병렬 배포를 위한 함수 정의
deploy_to_instance() {
    local IP=$1
    local LOG_FILE="/tmp/deploy-${IP}.log"
    local START_TIME=$(date +%s)
    
    {
        echo "[$IP] 🚀 Starting deployment..."
        echo "[$IP] [1/5] Copying JAR to instance..."
        
        ssh -T -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} bash -s << BASTION
set -e

IP="$IP"

# Backend 인스턴스로 JAR 복사
scp -o StrictHostKeyChecking=no /tmp/ktb-chat-backend.jar ubuntu@\$IP:/tmp/ 2>&1 | grep -v "Warning" || true

# Backend 인스턴스에 접속하여 배포 및 재시작
ssh -T -o StrictHostKeyChecking=no ubuntu@\$IP << 'INNER'
set -e

# JAR 파일 이동
echo "[$IP] [2/5] Moving JAR file..."
sudo mv /tmp/ktb-chat-backend.jar /opt/ktb-backend/ktb-BootcampChat/apps/backend/target/ktb-chat-backend-0.0.1-SNAPSHOT.jar

# .env 파일 업데이트
echo "[$IP] [3/5] Updating .env file..."
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend
sudo tee .env > /dev/null << 'ENVEOF'
MONGO_URI=$MONGO_URI
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
ENCRYPTION_SALT=$ENCRYPTION_SALT
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
PORT=5001
WS_PORT=5002
SPRING_PROFILES_ACTIVE=prod
ENVEOF

# Service 재시작
echo "[$IP] [4/5] Restarting service..."
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend
bash app-control.sh restart || {
    bash app-control.sh status || true
}

# 대기
echo "[$IP] [5/5] Waiting for service to start..."
sleep 15

# Health check
HEALTH_CHECK_PASSED=false
if curl -sf http://localhost:5001/api/health > /dev/null 2>&1; then
    HEALTH_CHECK_PASSED=true
else
    if [ -f app.pid ] && ps -p \$(cat app.pid) > /dev/null 2>&1; then
        HEALTH_CHECK_PASSED=true
    fi
fi

if [ "\$HEALTH_CHECK_PASSED" = "true" ]; then
    exit 0
else
    exit 1
fi
INNER
BASTION
        
        local END_TIME=$(date +%s)
        local DURATION=$((END_TIME - START_TIME))
        echo "[$IP] ✅ Success (${DURATION}s)"
        echo "SUCCESS:$IP"
    } > "$LOG_FILE" 2>&1 || {
        local END_TIME=$(date +%s)
        local DURATION=$((END_TIME - START_TIME))
        echo "[$IP] ❌ Failed (${DURATION}s)"
        echo "FAIL:$IP"
    }
}

# 진행 상황 표시 함수
show_progress() {
    local completed=0
    local running=0
    local total=${TOTAL_COUNT:-$INSTANCE_COUNT}
    
    if [ "$total" -eq 0 ]; then
        return
    fi
    
    for IP in $BACKEND_IPS; do
        if [ -f /tmp/deploy-${IP}.log ]; then
            if grep -q "SUCCESS:$IP\|FAIL:$IP" /tmp/deploy-${IP}.log 2>/dev/null; then
                ((completed++))
            else
                ((running++))
            fi
        else
            ((running++))
        fi
    done
    
    local progress_percent=$((completed * 100 / total))
    local bar_length=30
    local filled=$((progress_percent * bar_length / 100))
    local bar=""
    
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=filled; i<bar_length; i++)); do
        bar+="░"
    done
    
    printf "\r📊 Progress: [%s] %d%% (%d/%d 완료, %d 진행 중)" \
        "$bar" "$progress_percent" "$completed" "$total" "$running"
}

# 환경 변수 export (병렬 프로세스에서 사용)
export -f deploy_to_instance
export KEY_PATH BASTION_IP MONGO_URI REDIS_HOST REDIS_PORT REDIS_PASSWORD
export JWT_SECRET ENCRYPTION_KEY ENCRYPTION_SALT
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=$INSTANCE_COUNT

echo "🚀 Starting parallel deployment (max 4 concurrent)..."
echo ""

# 병렬 실행 (최대 4개 동시)
PIDS=()

for IP in $BACKEND_IPS; do
    deploy_to_instance "$IP" &
    PIDS+=($!)
    
    # 최대 4개까지만 동시 실행
    while [ ${#PIDS[@]} -ge 4 ]; do
        # 완료된 프로세스 확인 및 제거
        NEW_PIDS=()
        for PID in "${PIDS[@]}"; do
            if kill -0 "$PID" 2>/dev/null; then
                NEW_PIDS+=($PID)
            else
                wait "$PID" 2>/dev/null || true
            fi
        done
        PIDS=("${NEW_PIDS[@]}")
        
        # 진행 상황 출력
        show_progress
        
        sleep 0.5
    done
done

# 모든 프로세스 완료 대기 및 진행 상황 표시
while [ ${#PIDS[@]} -gt 0 ]; do
    # 완료된 프로세스 확인 및 제거
    NEW_PIDS=()
    for PID in "${PIDS[@]}"; do
        if kill -0 "$PID" 2>/dev/null; then
            NEW_PIDS+=($PID)
        else
            wait "$PID" 2>/dev/null || true
        fi
    done
    PIDS=("${NEW_PIDS[@]}")
    
    show_progress
    sleep 1
done

# 최종 진행 상황 표시
show_progress
echo ""

# 결과 수집
for IP in $BACKEND_IPS; do
    if [ -f /tmp/deploy-${IP}.log ] && grep -q "SUCCESS:$IP" /tmp/deploy-${IP}.log 2>/dev/null; then
        ((SUCCESS_COUNT++))
        # 성공 로그의 주요 메시지만 출력
        echo "[$IP] $(grep -E '\[.*\] (✅|❌)' /tmp/deploy-${IP}.log | tail -1)"
    else
        ((FAIL_COUNT++))
        echo "[$IP] ❌ 배포 실패"
        if [ -f /tmp/deploy-${IP}.log ]; then
            echo "    로그 확인: /tmp/deploy-${IP}.log"
            echo "    마지막 오류:"
            tail -3 /tmp/deploy-${IP}.log | sed 's/^/    /'
        fi
    fi
    rm -f /tmp/deploy-${IP}.log
done

# Bastion의 임시 파일 삭제
ssh -T -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} "rm -f /tmp/ktb-chat-backend.jar" 2>/dev/null || true

echo "======================================"
echo "📊 Deployment Summary"
echo "======================================"
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "⚠️  Some deployments failed!"
    exit 1
fi

echo "✅ All deployments successful!"
echo ""
