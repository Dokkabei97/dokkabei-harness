# 스택 감지 표

원칙: 파일에 **적힌 값**만 쓴다. 범위 지정(`^3.4`, `>=3.12`)은 그대로 옮기고, lock 파일이 있으면 lock 의 해석 버전을 함께 적는다.
BOM·플랫폼이 관리하는 버전(예: Spring Boot BOM 의 `elasticsearch-java`, lock 없음)은 "BOM 관리(미확인)"로 적는다 — 버전 조건이 붙은
항목은 제외 대상이다. 확인이 꼭 필요하면 사용자에게 `./gradlew dependencyInsight --dependency <name>` 실행을 **제안**만 한다
(빌드 캐시·디렉터리에 쓰므로 이 스킬이 대상 저장소에서 직접 돌리지 않는다).
모노레포면 루트와 하위 프로젝트(`settings.gradle(.kts)` 의 `include`, `go.work`, workspace `package.json`)별로 프로필을 나눈다.

## 1. 감지 항목

### JVM / Kotlin / Spring
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| JDK toolchain | `build.gradle(.kts)` | `jvmToolchain(21)`, `JavaLanguageVersion.of(21)`, `sourceCompatibility`; Maven `<java.version>`, `<maven.compiler.release>` |
| Kotlin | `build.gradle(.kts)`, `gradle/libs.versions.toml`, `settings.gradle(.kts)` pluginManagement | `kotlin("jvm") version "…"`, `[versions] kotlin = "…"` |
| Spring Boot | 같은 곳, Maven parent | `id("org.springframework.boot") version "…"`, `spring-boot-starter-parent` |
| 영속 방식 | 의존성 | `spring-boot-starter-data-jpa`(JPA/Hibernate), `exposed-*`, `jooq`, `mybatis`, `spring-boot-starter-jdbc`(JdbcTemplate/JdbcClient), R2DBC |
| 런타임 | 의존성 | `spring-boot-starter-webflux` vs `-web`, `kotlinx-coroutines-*` |
| 배포 JVM 옵션 | `Dockerfile`, k8s/helm values, `JAVA_TOOL_OPTIONS` | `-Xmx`, `-XX:MaxRAMPercentage`, `-XX:+UseZGC`, base image(`eclipse-temurin:21-jre` 등) |
| Kotlin 컴파일러 옵션 | `kotlin { compilerOptions { freeCompilerArgs } }` | `-Xannotation-default-target=param-property`, `-Xjsr305=strict` — 항목 조건(KT-VAL-01 등)이 이 값에 걸린다 |

### Go
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| 언어 버전 | `go.mod` | `go 1.23`, `toolchain go1.23.4` (둘 다 기록 — 루프 변수 시맨틱 등은 `go` 줄 기준) |
| 라우터 | `go.mod` require | 없음(net/http 1.22+ 패턴), `go-chi/chi`, `labstack/echo`, `gin-gonic/gin` |
| DB | `go.mod` | `jackc/pgx/v5`(+`/stdlib`), `lib/pq`, `jmoiron/sqlx`, `gorm.io/gorm`, `entgo.io/ent`, `sqlc.yaml` 존재 |
| 마이그레이션 | 디렉터리·의존성 | `golang-migrate/migrate`(`*.up.sql`/`*.down.sql`), `pressly/goose`(`-- +goose Up`) |

### Python
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| 버전 | `pyproject.toml` `requires-python`, `.python-version` | |
| 패키지 관리 | lock 파일 | `uv.lock`, `poetry.lock`, `requirements*.txt` |
| 프레임워크 | 의존성 | `fastapi`, `starlette`, `pydantic` major |
| 영속 방식 | 의존성 | `sqlalchemy`/`sqlmodel`(ORM) vs `psycopg`/`asyncpg` 만(원시 SQL) |
| DB 풀·의존성 | 소스 | `AsyncConnectionPool`/`ConnectionPool`, `Depends(get_conn, scope=...)`, `async def` vs `def` 엔드포인트 비중 |
| PostGIS 컬럼 타입 | 마이그레이션 DDL | `geography(Point, 4326)` vs `geometry(Point, 4326)` — 거리 단위 항목(PY-GIS-01 등)의 적용 여부가 갈린다 |

### Node / Next.js
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| Next/React | `package.json` + lock | `next`, `react` 버전 |
| 요청 가로채기 파일 | 루트/`src/` | `proxy.ts`(Next 16+) 또는 `middleware.ts` — 있는 쪽을 그대로 기록 |
| 렌더링 모델 | `next.config.*` | `cacheComponents: true` 면 Cache Components 모델, 없으면 이전 모델 — NX-CACHE-* 조건이 갈린다 |
| Server Action | `'use server'` 파일 | 있으면 RSC-ACT-* 대상 |
| 패키지 매니저 | lock 파일 | `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock(b)` |

### Elasticsearch
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| 클라이언트 | 의존성 | `co.elastic.clients:elasticsearch-java`, `spring-boot-starter-elasticsearch`(Boot 4, 버전은 BOM 관리), `spring-data-elasticsearch`, `github.com/elastic/go-elasticsearch/v8`, `olivere/elastic`(레거시), Python `elasticsearch` |
| 서버 버전 | `docker-compose*.yml`, k8s, CI | `docker.elastic.co/elasticsearch/elasticsearch:8.x` — 없으면 "미확인" |
| 매핑 파일 | `*.json` | `grep -l '"mappings"'` 결과 디렉터리 |
| 벡터 저장소 | 의존성·compose | ES `dense_vector` 매핑 vs 외부 벡터 DB(Qdrant 등) — 외부면 VEC-IDX/VEC-QRY(ES kNN) 항목은 해당 없음 |
| 융합·재정렬 위치 | 소스 | ES `rrf` retriever/`rescore` vs 애플리케이션 코드 RRF — 앱 코드면 ES-RNK-03·VEC-HYB-02 해당 없음 |
| 샤드 수 | 인덱스 템플릿 `number_of_shards` | 1 이면 샤드 로컬 IDF·부분 샤드 실패 항목(ES-REL-01, ES-QRY-13, TST-INT-02)은 해당 없음 |
| 사용 코드 위치 | 소스 | 클라이언트 import 가 있는 디렉터리 → rules `paths` 후보 |

### 공통
| 사실 | 어디서 | 패턴 |
|------|--------|------|
| DB 엔진 | compose 이미지, JDBC URL, 드라이버 | `postgres`, `postgis/postgis`, `mysql` |
| SQL 마이그레이션 | 의존성·디렉터리 | Flyway(`flyway-core`, `db/migration/V*__*.sql`), Liquibase(`db/changelog`), Alembic(`alembic.ini`), dbmate(`-- migrate:up`), golang-migrate, goose |
| 메시징/캐시 | 의존성 | `spring-kafka`, `org.apache.kafka`, `segmentio/kafka-go`, `IBM/sarama`, `confluent-kafka`; Redis/Valkey 클라이언트 |
| 컨테이너 배포 | `Dockerfile`, k8s(`kind: Deployment`), `Chart.yaml` | **앱 자체**의 이미지·매니페스트가 있으면 "컨테이너 배포" 조건 충족. compose 로 DB·ES 같은 의존 서비스만 띄우면 해당 없음 |
| 검증 명령 | CI 설정(`.gitlab-ci.yml`, `.github/workflows/*.yml`), `Makefile`/`justfile`, 빌드 스크립트, 기존 CLAUDE.md | CI 에서 실제로 돌리는 명령을 우선 |
| 플러그인 활성 | `.claude/settings.local.json`, `.claude/settings.json` `enabledPlugins`, 사용자 전역 | 이미 켜져 있으면 (d) 안내 생략 |
| 기존 지침 | 블록 밖 `CLAUDE.md`, `@import` 대상, 하위 `CLAUDE.md`/`AGENTS.md` | 이미 적힌 사실·함정 → 블록·rules 에서 중복 제외 |
| VCS 호스트 | `git remote get-url origin` | `gitlab` 포함 → glab 계열, `github.com` → gh |

## 2. 프로필 → 스택 플러그인

접두사 소유는 바뀔 수 있다 — 최종 판단은 색인 출력의 `plugin`/`skill` 열을 따른다.
rules 파일은 플러그인이 아니라 **항목이 걸리는 코드 위치**로 묶는다. 예: PY-MIG·PY-GIS·PG-MIG 는 SQL·마이그레이션을 다룰 때
걸리므로 `data-specialist.md`(마이그레이션·쿼리 디렉터리 paths)에 둔다.

| 프로필 조건 | 플러그인 | 주요 접두 (2026-10 기준) | rules 파일 |
|-------------|----------|--------------------------|-----------|
| Kotlin/JVM/Spring | `kotlin-spring` | JVM, KT, SPR | `kotlin-specialist.md` |
| Go | `go-mux` | GO | `go-specialist.md` |
| Python/FastAPI | `python-fastapi` | PY, FA | `python-specialist.md` |
| Next.js | `nextjs` | NX, RSC, WEB | `nextjs-specialist.md` |
| Elasticsearch | `search` | ES, LUC, KO, VEC | `elasticsearch-specialist.md` |
| PostgreSQL / Kafka / Valkey | `backend-shared` | PG(async-event-patterns·migration-safety-checklist 두 스킬에 걸침), KFK, VK | `data-specialist.md` |
| 원격 호출이 있는 백엔드 서비스 / JSON DTO | `backend-shared` | DIST, DTO | 언어 파일(`kotlin-`/`python-`/`go-specialist.md`)에 합친다 |
| 테스트 인프라 | `test` | TST | `testing-specialist.md` |

## 3. rules `paths` 기본값

프로젝트 루트(`.claude` 가 있는 디렉터리) 기준 glob. 실제 존재하는 디렉터리로 좁힐수록 좋다. 모노레포는 하위 프로젝트 경로를
접두로 붙인다(`apps/api/**/*.py`, `apps/web/**/*.{ts,tsx}`) — `<subdir>` 모드도 같다. 브레이스 확장은 rules 한 파일당 1,000 패턴 예산을 공유한다.

| rules 파일 | paths |
|-----------|-------|
| kotlin | `"**/*.kt"`, `"**/*.kts"`, `"**/application*.{yml,yaml,properties}"`, `"**/Dockerfile*"` |
| go | `"**/*.go"`, `"go.mod"` |
| python | `"**/*.py"`, `"pyproject.toml"` |
| nextjs | `"**/*.{ts,tsx}"`, `"next.config.*"` |
| elasticsearch | 클라이언트 import 가 있는 디렉터리(`"<dir>/**"`) + 매핑 json 디렉터리 |
| data | 마이그레이션 디렉터리(`"db/migrations/**"` 등), `"**/*.sql"`, SQL 을 둔 쿼리·저장소 계층 디렉터리(`"apps/api/app/db/**"` 등) |
| testing | 테스트 디렉터리(`"src/test/**"`, `"**/*_test.go"`, `"tests/**"`) |
