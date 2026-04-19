---
name: migrate
description: "안전한 DB 마이그레이션 생성 — Flyway/Alembic, 무중단 호환성 검증, expand-contract 패턴, 롤백 스크립트"
category: database
complexity: intermediate
mcp-servers: []
personas: []
---

# /migrate - 안전한 DB 마이그레이션 생성

## Triggers
- 데이터베이스 스키마 변경이 필요할 때 (테이블, 컬럼, 인덱스 등)
- 무중단 배포 환경에서 안전한 마이그레이션 전략이 필요할 때
- 기존 마이그레이션 파일의 안전성을 검토하고 싶을 때
- 위험한 스키마 변경(컬럼 타입 변경, DROP 등)에 대한 롤백 계획이 필요할 때

## Usage
```
/migrate [설명] [옵션]

Options:
  --lang kotlin|python          Flyway SQL / Alembic Python (기본: auto-detect)
  --zero-downtime               무중단 호환성 강제 검증
  --rollback                    롤백 스크립트 동시 생성
  --check-only                  기존 마이그레이션 파일 안전성만 검토
```

## Behavioral Flow

### 마이그레이션 생성 플로우
1. **Discover**: 프로젝트 마이그레이션 디렉토리 탐색, 기존 마이그레이션 파일 분석, 현재 스키마 상태 파악
   - Flyway: `db/migration/` 디렉토리, 버전 넘버링 체계 확인
   - Alembic: `alembic/versions/` 디렉토리, revision 체인 확인
2. **Analyze**: 요청된 변경의 위험도 평가
   - 🔴 Critical: 데이터 손실 가능 (DROP TABLE/COLUMN, 타입 축소)
   - 🟡 Warning: 락 위험 (NOT NULL 추가, 대형 테이블 인덱스, 컬럼 이름 변경)
   - 🟢 Safe: 추가만 (ADD COLUMN nullable, CREATE INDEX CONCURRENTLY)
3. **Design**: 안전한 마이그레이션 전략 선택
   - 단순 변경: 단일 마이그레이션 파일
   - 위험 변경: expand-contract 패턴 (2~3개 마이그레이션 파일로 분리)
4. **Generate**: Flyway SQL 또는 Alembic Python 마이그레이션 파일 생성
5. **Rollback**: (--rollback) 각 마이그레이션의 롤백 스크립트 생성
6. **Validate**: (--zero-downtime) 무중단 배포 호환성 최종 검증

## Safety Checks

| 패턴 | 위험도 | 설명 |
|------|--------|------|
| `NOT NULL` without `DEFAULT` | 🟡 Warning | 기존 행에서 실패 가능 |
| Column rename | 🟡 Warning | 애플리케이션 코드 동시 변경 필요 |
| Type change (축소) | 🟡 Warning | 데이터 손실/변환 실패 가능 |
| `DROP TABLE/COLUMN` | 🔴 Critical | 데이터 영구 삭제 |
| Large table `INDEX` | 🟡 Warning | 테이블 락, `CONCURRENTLY` 사용 권고 |
| Foreign key addition | 🟡 Warning | 기존 데이터 무결성 위반 가능 |
| `ALTER TYPE` on ENUM | 🟡 Warning | PostgreSQL에서 트랜잭션 내 변경 제한 |

## Tool Coordination
- **Glob**: 마이그레이션 디렉토리 및 기존 파일 탐색
- **Read**: 기존 마이그레이션 파일, 엔티티/모델 코드 분석
- **Write**: 마이그레이션 파일 및 롤백 스크립트 생성
- **Bash**: 마이그레이션 dry-run 실행, 문법 검증

## Examples

### 안전한 컬럼 추가
```
/migrate "users 테이블에 email_verified boolean 추가" --zero-downtime
# 생성: V20260321__add_email_verified_to_users.sql
# → ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT false;
# 무중단 검증: PASS (nullable 컬럼 추가, 락 최소)
```

### 위험한 타입 변경 (expand-contract)
```
/migrate "orders.status 컬럼 VARCHAR에서 ENUM으로 변경" --rollback
# 생성:
#   V20260321_1__expand_orders_add_status_enum.sql (새 컬럼 추가)
#   V20260321_2__migrate_orders_status_data.sql (데이터 이관)
#   V20260321_3__contract_orders_drop_old_status.sql (구 컬럼 제거)
# 롤백:
#   U20260321_3__rollback_contract.sql
#   U20260321_2__rollback_data_migration.sql
#   U20260321_1__rollback_expand.sql
```

### 기존 마이그레이션 안전성 검토
```
/migrate --check-only
# 전체 마이그레이션 파일 스캔
# 위험 패턴 탐지 및 리포트 출력
```

### Alembic 마이그레이션 (Python)
```
/migrate "products 테이블에 category_id FK 추가" --lang python --zero-downtime
# 생성: alembic/versions/20260321_add_category_id_to_products.py
# FK 추가 시 기존 데이터 무결성 검증 포함
```

## Output Format
```
## 마이그레이션 분석 결과

### 위험도 평가
- 변경 유형: 컬럼 타입 변경 (VARCHAR → ENUM)
- 위험도: 🟡 Warning
- 전략: expand-contract 패턴 (3단계)

### 생성된 파일
| 단계 | 파일명                                          | 설명          |
|------|-----------------------------------------------|-------------|
| 1    | V20260321_1__expand_orders_add_status_enum.sql | 새 컬럼 추가    |
| 2    | V20260321_2__migrate_orders_status_data.sql    | 데이터 이관     |
| 3    | V20260321_3__contract_orders_drop_old_status.sql | 구 컬럼 제거  |

### 무중단 검증
- [PASS] 1단계: nullable 컬럼 추가 — 기존 쿼리 영향 없음
- [PASS] 2단계: 배치 UPDATE — 락 최소화
- [WARN] 3단계: 컬럼 삭제 — 애플리케이션 코드 먼저 배포 필요
```

## Boundaries

**Will:**
- 프로젝트 마이그레이션 도구(Flyway/Alembic)에 맞는 파일 생성
- 위험 변경에 대한 expand-contract 패턴 적용
- 무중단 배포 호환성 검증 및 위험도 리포트 제공
- 롤백 스크립트 동시 생성 (옵션 사용 시)
- 기존 마이그레이션 파일 안전성 검토

**Will Not:**
- 실제 데이터베이스에 마이그레이션 실행 (파일 생성만)
- 데이터 백업 또는 복원 수행
- 애플리케이션 코드(Entity/Model) 자동 수정
- 프로덕션 환경 직접 접근

## Related
- `/bean-check --focus transaction` — 트랜잭션 설정과 마이그레이션 호환성 확인
- `/api-gen` — 새 테이블에 대응하는 API 레이어 생성
