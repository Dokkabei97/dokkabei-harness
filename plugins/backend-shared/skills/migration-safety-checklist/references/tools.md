# 마이그레이션 도구 감지와 트랜잭션 경계

도구를 단정하지 않는다. 아래 신호로 감지하고, 둘 이상이면 실제로 CI/배포에서 실행되는 쪽을 확인한다.
도구 버전에 따라 지시자 이름이 다를 수 있으므로 **프로젝트가 쓰는 버전의 공식 문서로 최종 확인**한다.

## 감지표

| 도구 | 감지 신호 | 파일 단위 트랜잭션 | 비트랜잭션 실행 방법 (CONCURRENTLY·배치 COMMIT) |
|---|---|---|---|
| Flyway | `flyway-core`/`org.flywaydb` (build.gradle(.kts)/pom.xml), `db/migration/V*__*.sql`, `spring.flyway.*` | 예 (PG) | PostgreSQL 에서 트랜잭션 안에서 실행할 수 없는 문장(CIC 등)을 감지하면 해당 마이그레이션을 non-transactional 로 표시해 트랜잭션 없이 실행([트랜잭션 처리](https://documentation.red-gate.com/fd/migration-transaction-handling-273973399.html)). `group=true` 이면 한 실행에 트랜잭션·비트랜잭션 마이그레이션을 섞을 때 `mixed=true` 가 필요하므로 CIC 는 **단독 파일**로. 스크립트별 설정 파일 `V2__x.sql.conf` 의 `executeInTransaction=false` 로 명시 가능([Script Configuration](https://documentation.red-gate.com/flyway/reference/script-configuration), 6.1.0+ 도입 — 구버전·에디션별 지원은 해당 버전 문서로 확인). CIC 가 Flyway 의 트랜잭션 advisory lock 과 얽혀 멈추는 경우 `postgresql.transactional.lock=false`(기본 true) |
| Liquibase | `liquibase-core`, `db.changelog-master.*`, `spring.liquibase.*` | 예 (changeSet 단위) | changeSet 속성 `runInTransaction="false"` / formatted SQL `--changeset a:id runInTransaction:false` |
| Alembic | `alembic.ini`, `alembic/versions/*.py` (또는 `migrations/versions`) | 예 (env.py 설정에 따름) | `with op.get_context().autocommit_block(): op.execute("CREATE INDEX CONCURRENTLY ...")` |
| dbmate | `db/migrations/*.sql` 안의 `-- migrate:up` / `-- migrate:down`, Makefile·compose 의 `dbmate` | 예 | 섹션 헤더에 `-- migrate:up transaction:false` |
| golang-migrate | `NNNN_name.up.sql`/`.down.sql` 쌍, `github.com/golang-migrate/migrate` import | 아니오 (래핑 안 함) | 래핑은 없지만 파일 전체를 한 번에 Exec → 여러 문장이 한 **암묵적 트랜잭션**이 됨(PG-MIG-08). CIC 는 **파일 단독**. 실패 시 `dirty` 상태 → 원인 정리 후 `migrate force <version>` |
| goose | `-- +goose Up` 주석, `github.com/pressly/goose` | 예 | 파일 상단 `-- +goose NO TRANSACTION` |
| Atlas | `atlas.hcl`, `atlas.sum` | 기본 파일 단위 | 파일 지시자 `-- atlas:txmode none` 또는 `--tx-mode` 플래그 |
| (없음) ORM 자동 DDL | `spring.jpa.hibernate.ddl-auto=update`, `Base.metadata.create_all()` | — | 운영 스키마 변경 경로로 쓰고 있으면 그 자체가 리뷰 지적 대상(락·순서 통제 불가). 도입 시 현재 스키마를 baseline 으로 잡는다 |

## 공통 규칙

- **적용된 파일은 수정하지 않는다.** Flyway/Liquibase 는 체크섬 불일치로 기동이 실패하고, dbmate/golang-migrate/goose 는 조용히 재실행하지 않아 환경 간 스키마가 갈라진다. 고칠 것은 새 파일로.
- **한 파일 = 한 논리 변경.** 특히 비트랜잭션 문장은 단독. 실패 시 어디까지 적용됐는지 판단 가능해야 한다.
- **lock_timeout 위치**: 트랜잭션 래핑 도구는 파일 첫 줄 `SET lock_timeout = '3s';` 가 그 트랜잭션에만 적용되도록 `SET LOCAL` 을 써도 된다. 비트랜잭션 파일은 세션 설정이므로 커넥션 풀을 공유하는 런처라면 파일 끝에서 `RESET lock_timeout;`.
- **down 마이그레이션**: 프로젝트 관례를 따른다. down 이 데이터를 복원하지 못하는 변경(DROP, 타입 축소)은 down 을 비우고 "전진 수정" 계획을 리뷰에 명시한다 → [patterns.md](patterns.md) §롤백.
- **앱 기동 시 자동 마이그레이션**(Spring Boot Flyway/Liquibase 자동 실행): 롤링 배포에서 여러 파드가 동시에 시도한다. 도구 락으로 직렬화되지만 장시간 DDL 이면 readiness 타임아웃으로 파드가 재시작될 수 있다 — 대형 변경은 배포 전 별도 잡으로 실행하는 편이 안전.
