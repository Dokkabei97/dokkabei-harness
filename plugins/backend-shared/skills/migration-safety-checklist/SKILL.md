---
name: migration-safety-checklist
description: |
  DB 마이그레이션 안전성 — 마이그레이션 작성·리뷰, ALTER TABLE 락 대기열, NOT NULL·FK·UNIQUE 추가, CREATE INDEX CONCURRENTLY(INVALID 인덱스), 대량 백필, 컬럼 rename/타입 변경, expand-contract, 롤백. 도구 중립(Flyway·Alembic·dbmate·golang-migrate 등 감지) + PostgreSQL 락 레벨 항목.
  Zero-downtime migration safety: PostgreSQL lock levels, lock_timeout, PG11+ fast defaults, CHECK NOT VALID→VALIDATE, batched backfill.
  Use when: writing or reviewing a schema migration or backfill on a large or hot table.
---

# DB 마이그레이션 안전성

목표: 실행 중인 트래픽과 **이전 버전 앱 파드**가 공존하는 동안 락 대기열·재작성·호환성 파괴 없이 스키마를 바꾼다.
본문은 트리아지 인덱스다. 근거·수치·처방은 `references/` 의 ID 항목을 읽는다.

## 0. 먼저 프로젝트 사실 확인 (단정 금지)

도구·버전·DB 를 추측하지 않는다. 아래를 먼저 확인하고, 프로젝트 CLAUDE.md / `.claude/rules` 에 이미 적혀 있으면 그것을 따른다.

| 확인 | 방법 |
|---|---|
| 마이그레이션 도구 | 빌드 파일·디렉터리로 감지 → [references/tools.md](references/tools.md) §감지표 |
| DB 엔진·메이저 버전 | 기존 마이그레이션, docker-compose/Testcontainers 이미지 태그, 인프라 문서. 버전별로 안전 판정이 달라진다(PG11/12/18) |
| 트랜잭션 래핑 방식 | 도구가 파일 단위로 BEGIN/COMMIT 을 감싸는가 → CONCURRENTLY·DO-COMMIT 가능 여부 결정 |
| 기존 컨벤션 | 파일 명명, down 마이그레이션 사용 여부, `lock_timeout` 선언 관례 |
| 테이블 크기·쓰기량 | `pg_total_relation_size`, `pg_stat_user_tables.n_tup_upd` — "대형/핫" 판정 기준 |

## 1. 변경 유형별 트리아지

| 변경 | 위험 신호 | 읽을 항목 |
|---|---|---|
| 모든 DDL 공통 | ACCESS EXCLUSIVE 대기열이 뒤 SELECT 까지 막음 | PG-MIG-01, PG-MIG-02 |
| 컬럼 추가 + DEFAULT | 휘발성 DEFAULT(`clock_timestamp()`, `random()`, `gen_random_uuid()`)는 PG11+ 에서도 재작성 | PG-MIG-03 |
| NOT NULL 추가 | 전체 스캔 + ACCESS EXCLUSIVE | PG-MIG-04 |
| FK / CHECK 추가 | 검증 스캔 동안 양쪽 테이블 락 | PG-MIG-05 |
| UNIQUE / PK 추가 | 인덱스 빌드가 쓰기 차단 | PG-MIG-06 |
| 인덱스 생성/삭제 | CONCURRENTLY 실패 시 INVALID 인덱스 잔존, 트랜잭션 블록 불가 | PG-MIG-07, PG-MIG-08, PG-MIG-09 |
| 파티션 테이블 인덱스 | 부모에 CONCURRENTLY 불가 | PG-MIG-10 |
| 컬럼 타입 변경 | int→bigint 등은 테이블+모든 인덱스 재작성 | PG-MIG-11, PG-MIG-12 |
| enum 값 추가 | 같은 트랜잭션에서 새 값 사용 불가 | PG-MIG-13 |
| 컬럼 DROP / rename | 구버전 파드·서버측 prepared statement 깨짐 | PG-MIG-14, [patterns.md](references/patterns.md) §expand-contract |
| 대량 백필 | 단일 UPDATE → 테이블 2배·WAL 폭증·복제 지연 | PG-MIG-15, PG-MIG-16 |
| 롤백 계획 | down 이 데이터를 되살리지 못함 | [patterns.md](references/patterns.md) §롤백 |

항목 본문: [references/postgres-ddl.md](references/postgres-ddl.md)

## 2. 작성 절차

1. **분류**: 변경을 위 표에 매핑하고 테이블 크기·쓰기량을 확인한다. 소형(수만 행 이하)·저트래픽이면 대부분의 항목은 과최적화다 — 각 항목의 `반례` 를 본다.
2. **분리**: 위험 변경은 expand → (코드 배포) → backfill → (코드 배포) → contract 로 파일을 나눈다. 한 파일 = 한 논리 변경.
   비트랜잭션 문장(CONCURRENTLY, 배치 COMMIT)은 도구별 방식으로 **단독 파일**에 둔다 → [tools.md](references/tools.md).
3. **락 예산**: 잠금이 필요한 DDL 파일 맨 앞에 `SET lock_timeout` (예: `'3s'`) 을 두고, 실패 시 재시도 가능한 형태로 만든다(PG-MIG-01).
4. **배포 순서 검증**: "구버전 앱 + 새 스키마" 와 "새 앱 + 구 스키마(롤백 시)" 두 조합이 모두 동작하는지 확인한다.
5. **검증 쿼리 첨부**: INVALID 인덱스, 제약 `convalidated`, 백필 잔여 행 수를 확인하는 SQL 을 리뷰 산출물에 포함한다.

## 3. 리뷰 체크리스트 (기존 마이그레이션 검토 시)

- [ ] 대형/핫 테이블 DDL 앞에 `lock_timeout` 이 있는가, 재시도 가능한가
- [ ] `CREATE INDEX` 에 CONCURRENTLY 가 빠졌거나, CONCURRENTLY 가 트랜잭션 래핑 파일 안에 있지 않은가
- [ ] `SET NOT NULL` / `ADD FOREIGN KEY` / `ADD CHECK` 가 NOT VALID→VALIDATE 단계 없이 대형 테이블에 바로 걸리지 않았는가
- [ ] `ALTER COLUMN TYPE` 이 binary-coercible 이 아닌데 대형 테이블에 직접 걸리지 않았는가
- [ ] 백필이 단일 UPDATE 가 아닌가, 배치가 키셋(PK 범위) 기반인가
- [ ] 컬럼 DROP/rename 이 코드 배포보다 먼저 나가지 않는가
- [ ] 이미 적용된 마이그레이션 파일을 수정하지 않았는가(체크섬·적용 이력 불일치)

## 4. 산출물 형식

```
## 마이그레이션 분석
- 도구/DB: <감지 결과와 근거 파일>   - 대상 테이블 규모: <행 수/크기/쓰기량>
- 위험 항목: PG-MIG-xx (사유)        - 전략: 단일 파일 | expand-contract N단계
| 단계 | 파일 | 락 레벨 | 트랜잭션 | 배포 선후 |
- 검증 SQL: ...                      - 롤백/전진수정 계획: ...
```

## 비범위

- MySQL/MariaDB 온라인 DDL(gh-ost, pt-osc, `ALGORITHM=INSTANT`)은 항목화하지 않았다 — 해당 프로젝트라면 공식 문서로 락 동작을 확인한다.
- 마이그레이션 실행·프로덕션 접근은 하지 않는다. 생성·리뷰까지만.
