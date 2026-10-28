# 생성 템플릿

## (a) CLAUDE.md 스택 사실 블록 (≤30줄)

감지된 것만 쓰고, 미확인 줄은 빼거나 "미확인"으로 둔다. 블록 밖은 건드리지 않는다. 블록 밖에 이미 적힌 사실은 반복하지 않는다.

```markdown
<!-- project-rules:start -->
<!-- workflow:project-rules 가 관리하는 블록. 직접 수정하면 --check 에서 드리프트로 보고된다 -->
## Stack facts (generated YYYY-MM-DD)

- JDK 21 (Gradle toolchain) · Kotlin 2.1.0 · Spring Boot 3.4.1 · Gradle Kotlin DSL + version catalog
- 영속: Spring Data JPA (Hibernate) · PostgreSQL 16 · 마이그레이션: Flyway (`src/main/resources/db/migration`)
- 검색: Elasticsearch 8.x (`elasticsearch-java`) · 매핑: `src/main/resources/es/`
- 배포: 컨테이너 (`Dockerfile`, k8s) — JVM 옵션은 `JAVA_TOOL_OPTIONS`
- 검증: `./gradlew check` (CI: `.gitlab-ci.yml` test stage)
- VCS: GitLab (`glab`) — MR 리뷰 `/workflow:review-mr`, 릴리즈 노트 `/workflow:release-notes`
- 스페셜리스트: 핵심 `.claude/rules/specialist-core.md`(항상), 상세 `.claude/rules/kotlin-specialist.md`·`elasticsearch-specialist.md`(해당 파일을 읽을 때)
<!-- project-rules:end -->
```

블록 수준 HTML 주석(`<!-- … -->`)은 컨텍스트에 주입되기 전에 제거되므로 마커·메타 주석은 토큰을 쓰지 않는다.

GitHub 프로젝트의 VCS 줄 예: `- VCS: GitHub (\`gh\`) — PR 은 \`gh pr create\`/\`gh pr view\``

개인 프로젝트 예(FastAPI + 원시 SQL):

```markdown
- Python ≥3.12 (uv) · FastAPI · ORM 없음 — psycopg 3 원시 SQL
- PostgreSQL + PostGIS · 마이그레이션: dbmate (`db/migrations`, `-- migrate:up/down`)
- Next.js 16 (`proxy.ts`) · React 19 · pnpm
- 검증: `uv run pytest`, `pnpm lint && pnpm test`
```

멱등 갱신: 마커 줄은 정확히 `<!-- project-rules:start -->` / `<!-- project-rules:end -->` 이다. 그 사이를 통째로 교체한다. 마커가 없으면 파일 끝(또는 첫 `##` 섹션 앞)에 삽입을 제안한다.

## (b) `.claude/rules/specialist-core.md` (항상 로드, ≤15줄)

**frontmatter 를 두지 않는다.** 공식 문서: "Rules without `paths` frontmatter are loaded at launch with the same priority as
`.claude/CLAUDE.md`." 또한 compaction 후 "Project-root CLAUDE.md and unscoped rules — Re-injected from disk".
paths rules 는 쓰기 경로가 Bash heredoc 이면 로드되지 않으므로, 새 파일 생성 시 걸리는 함정은 여기에 둔다.

```markdown
<!-- project-rules: generated YYYY-MM-DD · core · source kotlin-spring@<ver>, search@<ver> · 상세는 *-specialist.md -->
# 스페셜리스트 핵심 (이 프로젝트 해당분 — 항상 적용)

## Kotlin/Spring
- **KT-CORO-02** MVC 요청 경로에서 `runBlocking` 금지 — 블로킹 호출 병렬화는 전용 executor/디스패처로 (/kotlin-spring:kotlin-spring-guide)
- **SPR-JSON-02** Boot 4 = Jackson 3: `tools.jackson.*` 를 import, `com.fasterxml.jackson.databind` 쓰지 말 것(애노테이션만 예외)

## Elasticsearch
- **ES-MAP-13** analyzer·매핑 변경은 기존 문서를 재분석하지 않는다 — 새 인덱스 + alias 스왑 (/search:es-deep-patterns)
```

규칙:
- 줄 자체가 행동 지시여야 한다("~금지", "~할 것"). 제목을 옮겨 적는 것으로는 부족하다 — 깊이 참조를 열지 않아도 쓸 수 있게
- 스택별 `##` 소제목은 줄 수에 넣지 않는다. 항목 줄만 전체 ≤15
- 깊이 참조는 괄호 안 `/<plugin>:<skill>` 만(ID 는 줄 앞에 이미 있음). `--check` 는 `**<ID>**` 로 ID 를 파싱한다

## (c) `.claude/rules/<stack>-specialist.md` (paths 한정)

`paths` 는 Claude Code 가 rules 에서 읽는 유일한 frontmatter 키다(그 외 키는 오류 없이 무시). 다른 메타데이터는 HTML 주석으로 둔다.
공식 문서: "A path-scoped rule loads when Claude uses the Read, Write, or Edit tool on a matching file. It also loads when Claude
views a matching file with a Bash command that counts as a read, such as `cat` or `head` on a single file." — 읽기로 치는 Bash 는
`cat`/`nl`/`head`/`tail`/`sed -n`/`grep`/`rg` 를 파이프·리다이렉트 없이 파일 하나에 쓴 경우뿐이다. heredoc·`>` 쓰기는 트리거가 아니다.
YAML 이 파싱되지 않으면 frontmatter 를 무시하고 paths 없는 규칙처럼 **항상** 로드하므로 따옴표로 감싼 리스트 형식을 지킨다.

```markdown
---
paths:
  - "**/*.kt"
  - "**/*.kts"
  - "**/application*.{yml,yaml}"
  - "**/Dockerfile*"
---
<!-- project-rules: generated YYYY-MM-DD · source kotlin-spring@<version>/<색인 항목 수> · profile JDK 21, Kotlin 2.1.0, Boot 3.4.1, container -->

# Kotlin/JVM 스페셜리스트 체크 (이 프로젝트 해당분)

이 코드를 작성·리뷰할 때 아래 함정을 확인한다. 핵심은 specialist-core.md 에 있고 여기는 상세분이다.
상세(메커니즘·처방·반례·검증)는 각 ID 의 스킬 레퍼런스에서.

- **JVM-GC-02** 컨테이너 힙이 리밋의 25%로 잡힘(-Xmx/MaxRAMPercentage 미지정) — 깊이: /kotlin-spring:kotlin-spring-guide 의 JVM-GC-02
- **SPR-TX-02** 같은 빈 내부 호출로 @Transactional 프록시 우회 — 깊이: /kotlin-spring:kotlin-spring-guide 의 SPR-TX-02
- …(≤15, core 에 올린 ID 제외)
```

`<색인 항목 수>` 는 그 플러그인의 색인 줄 수다 — 버전 필드가 같아도 내용이 바뀐 원천(레포 clone vs 구 설치본)을 구분하는 용도.

규칙:
- 한 줄 요약은 항목 제목을 이 프로젝트 맥락으로 줄인 것. 처방 코드·수치를 복사하지 않는다(원천이 갱신되면 낡는다)
- 깊이 참조 형식은 `/<plugin>:<skill> 의 <ID>` 고정 — `--check` 가 이 형식으로 ID 를 파싱한다
- 사용자가 직접 추가한 줄(`<!-- manual -->` 표시 권장)은 재생성 시 보존

## (d) 플러그인 활성화 안내

```bash
# 이 프로젝트에서만(커밋되지 않는 .claude/settings.local.json)
claude plugin enable kotlin-spring@dokkabei-harness --scope local
claude plugin enable search@dokkabei-harness --scope local
# 팀 전체와 공유하려면 --scope project (.claude/settings.json 에 기록, 커밋 대상)
```

- 이미 `enabledPlugins` 에 있으면 생략하고 "이미 활성(local)"으로만 적는다
- 설치되지 않은 플러그인이면 먼저 `claude plugin install <name>@dokkabei-harness --scope local`
- 설치본이 구버전(색인 0건)이면 `/plugin update` 안내
- 반영은 다음 세션부터
