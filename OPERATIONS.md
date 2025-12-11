# Redis Cluster 수동 구축 가이드 (AWS Console)

AWS 콘솔을 사용하여 Redis Master 1대와 Replica 2대를 직접 생성하고 설정하는 방법입니다.

## 1. 인스턴스 생성 (EC2)

총 3개의 인스턴스를 생성해야 합니다 (`ktb-redis-master`, `ktb-redis-replica-1`, `ktb-redis-replica-2`).
모든 인스턴스는 **Private Subnet**에 위치해야 합니다.

### 공통 설정
- **OS 이미지 (AMI)**: `Ubuntu Server 22.04 LTS (HVM)` (**중요**: 24.04 아님)
- **인스턴스 유형**: `t3.small`
- **키 페어**: `ktb-015-key`

### 네트워크 설정
- **VPC**: `vpc-08ae450f390b4239a` (기존 VPC)
- **보안 그룹**: `ktb-db-sg` (sg-0dfb543bdca2ec8a1) 선택

### 인스턴스별 Subnet 위치
| 인스턴스 이름 | Subnet | AZ |
|---|---|---|
| `ktb-redis-master` | `subnet-0e70679bd11132649` (Private 2A) | ap-northeast-2a |
| `ktb-redis-replica-1` | `subnet-08c47df015df6ff1a` (Private 2C) | ap-northeast-2c |
| `ktb-redis-replica-2` | `subnet-0e70679bd11132649` (Private 2A) | ap-northeast-2a |

---

## 2. Redis 설치 및 설정 (Bastion 경유)

Private Subnet은 인터넷 연결이 없으므로 Bastion Host를 통해 접속하여 설치해야 합니다.

### 2.1. 접속 방법
터미널에서 Bastion Host로 먼저 접속한 뒤, 각 Redis 서버로 SSH 접속합니다.

```bash
# 로컬 -> Bastion
ssh -i ~/.ssh/ktb-015-key.pem ubuntu@52.79.105.90

# Bastion -> Redis (Private IP)
ssh -i ~/.ssh/ktb-015-key.pem ubuntu@[REDIS_PRIVATE_IP]
```
> **Tip**: Bastion에 `ktb-015-key.pem`이 없다면 로컬에서 `scp`로 복사하세요.

### 2.2. Redis 설치 (Master/Replica 공통)
각 Redis 서버에서 아래 명령어를 실행합니다. (인터넷이 안되므로 Bastion에서 미리 다운로드 받은 deb 파일을 scp로 전송하는 것이 가장 확실하지만, NAT Gateway가 있다면 `apt-get` 사용 가능)

```bash
sudo apt-get update
sudo apt-get install -y redis-server
```

### 2.3. Redis 설정 (`/etc/redis/redis.conf`)
`sudo vim /etc/redis/redis.conf` 파일을 열어 수정합니다.

#### 공통 설정 (모든 서버)
```conf
# 외부 접속 허용 (기존 bind 127.0.0.1 ::1 주석 처리 또는 변경)
bind 0.0.0.0

# 비밀번호 설정
requirepass ktb-015

# 데이터 영속성 (선택 사항)
appendonly yes
```

#### Replica 설정 (`replica-1`, `replica-2` 만 해당)
Config 파일 맨 아래에 추가합니다:
```conf
# Master 연결 정보
replicaof [REDIS_MASTER_PRIVATE_IP] 6379

# Master 비밀번호
masterauth ktb-015
```

### 2.4. 서비스 재시작
```bash
sudo systemctl restart redis-server
```

---

## 3. 연결 확인 및 Backend 업데이트

### 3.1. Replication 확인 (Master 서버에서)
```bash
redis-cli -a ktb-015 info replication
```
출력 결과에 `connected_slaves:2` 라고 나오면 성공입니다.

### 3.2. Backend 업데이트
모든 Backend 인스턴스가 새로운 Redis Master를 바라보도록 업데이트해야 합니다. 로컬에서 아래 스크립트를 실행하세요:

```bash
# 사용법: ./deployment-scripts/fix-all-backends-redis.sh [REDIS_MASTER_IP]
./deployment-scripts/fix-all-backends-redis.sh 10.0.1.x
```
