# 생성 템플릿

## (a) AGENTS.md 마커 블록 (스택 사실 ≤30줄 + 핵심 ≤15줄, 블록 ≤50줄·≤6,000바이트)

감지된 것만 쓰고, 미확인 줄은 빼거나 "미확인"으로 둔다. 블록 밖은 건드리지 않는다. 블록 밖에 이미 적힌 사실은 반복하지 않는다.
Codex·Antigravity 는 이 파일만 읽고 `@import` 를 따라가지 않으므로 블록은 그 자체로 완결돼야 한다.

```markdown
<!-- project-rules:start -->
<!-- workflow:project-rules 관리 블록 · --check 로 점검 -->
## Stack facts (generated YYYY-MM-DD)

- JDK 21 (Gradle toolchain) · Kotlin 2.1.0 · Spring Boot 3.4.1 · Gradle Kotlin DSL + version catalog
- 영속: Spring Data JPA (Hibernate) · PostgreSQL 16 · 마이그레이션: Flyway (`src/main/resources/db/migration`)
- 검색: Elasticsearch 8.x (`elasticsearch-java`) · 매핑: `src/main/resources/es/`
- 배포: 컨테이너 (`Dockerfile`, k8s) — JVM 옵션은 `JAVA_TOOL_OPTIONS`
- 검증: `./gradlew check` (CI: `.gitlab-ci.yml` test stage)
- VCS: GitLab (`glab`) — MR 리뷰 `/workflow:review-mr`, 릴리즈 노트 `/workflow:release-notes`
- 상세 스페셜리스트(Claude Code 전용): `.claude/rules/kotlin-specialist.md`·`elasticsearch-specialist.md` — 해당 파일을 읽을 때 로드

## Specialist core (이 프로젝트 해당분 — 항상 적용)
<!-- source kotlin-spring@<ver>/<items>, search@<ver>/<items> -->

### Kotlin/Spring
- **KT-CORO-02** MVC 요청 경로에서 `runBlocking` 금지 — 블로킹 호출 병렬화는 전용 executor/디스패처로 (kotlin-spring:kotlin-spring-guide)
- **SPR-JSON-02** Boot 4 = Jackson 3: `tools.jackson.*` 를 import, `com.fasterxml.jackson.databind` 쓰지 말 것(애노테이션만 예외)

### Elasticsearch
- **ES-MAP-13** analyzer·매핑 변경은 기존 문서를 재분석하지 않는다 — 새 인덱스 + alias 스왑 (search:es-deep-patterns)
<!-- project-rules:end -->
```

주석 비용은 런타임마다 다르다: Claude Code 는 블록 수준 HTML 주석을 주입 전에 지운다(공식 문서 + `@AGENTS.md` import 경유 실측).
Codex 는 주석을 그대로 넣는다(실측) — 그래서 주석은 마커와 짧은 메타 2줄로 제한한다. Antigravity 의 처리 여부는 미실측.

규칙:
- core 줄 자체가 행동 지시여야 한다("~금지", "~할 것"). 제목을 옮겨 적는 것으로는 부족하다 — 깊이 참조를 열지 않아도 쓸 수 있게
- `##`·`###` 소제목은 줄 수에 넣지 않는다. core 항목 줄만 전체 ≤15
- 깊이 참조는 괄호 안 `<plugin>:<skill>`(런타임 중립 — Claude·Antigravity 는 `/` 를, Codex 는 `$` 를 앞에 붙여 부른다). `--check` 는 `**<ID>**` 로 ID 를 파싱한다
- `<items>` 는 색인 stderr 의 그 플러그인 items 값 — 버전 필드가 같아도 내용이 바뀐 원천(레포 clone vs 구 설치본)을 구분하는 용도
- 크기 확인: `awk '/project-rules:start/,/project-rules:end/' AGENTS.md | wc -lc`, `wc -c AGENTS.md`
- Antigravity 는 always-on·전역 규칙 합계가 20,000토큰을 넘으면 넘친 규칙을 본문 대신 파일 경로 포인터로 강등한다(`agy-customizations/docs/rules.md:34-38`) — 루트 AGENTS.md 가 크면 블록째 강등될 수 있다

GitHub 프로젝트의 VCS 줄 예: `- VCS: GitHub (\`gh\`) — PR 은 \`gh pr create\`/\`gh pr view\``

개인 프로젝트 예(FastAPI + 원시 SQL):

```markdown
- Python ≥3.12 (uv) · FastAPI · ORM 없음 — psycopg 3 원시 SQL
- PostgreSQL + PostGIS · 마이그레이션: dbmate (`db/migrations`, `-- migrate:up/down`)
- Next.js 16 (`proxy.ts`) · React 19 · pnpm
- 검증: `uv run pytest`, `pnpm lint && pnpm test`
```

멱등 갱신: 마커 줄은 정확히 `<!-- project-rules:start -->` / `<!-- project-rules:end -->` 이다. 그 사이를 통째로 교체한다.
마커가 없으면 첫 `##` 섹션 앞(없으면 파일 끝)에 삽입을 제안한다 — Codex(바이트)·Antigravity(줄) 모두 파일 뒤쪽부터 잘리므로.

## (b) CLAUDE.md 연결

공식 문서(code.claude.com/docs/en/memory §AGENTS.md): "By default, Claude reads `AGENTS.md` only when you have no `CLAUDE.md` in
your working directory or above it." 그리고 §Share one file with other coding tools: "putting an `@AGENTS.md` import in a
`CLAUDE.md` next to it. … Add any Claude-specific instructions below the import, and Claude reads the imported file first, then the rest".
import 는 "Relative paths resolve relative to the file containing the import", 코드 스팬·펜스 안의 `@…` 는 import 되지 않는다.

```markdown
@AGENTS.md

# CLAUDE.md
…(기존 내용 그대로)
```

- 이미 코드 밖에 `@AGENTS.md`(또는 `@./AGENTS.md`)가 있으면 생략
- CLAUDE.md 가 없으면 기본은 만들지 않는다(직접 읽기는 Claude Code v2.1.277+, 2.1.312 에서 실측). 사용자가 원하면 위 첫 줄만 담은 파일
- `CLAUDE.md` 가 AGENTS.md 로의 심볼릭 링크면 아무것도 하지 않는다(문서: "Either way Claude reads the content once")

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

이 코드를 작성·리뷰할 때 아래 함정을 확인한다. 핵심은 AGENTS.md 의 project-rules 블록에 있고 여기는 상세분이다.
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

## (d) 플러그인 활성화 안내 (런타임별)

```bash
# Claude Code — 이 프로젝트에서만(커밋되지 않는 .claude/settings.local.json). 팀 공유는 --scope project(.claude/settings.json)
claude plugin enable kotlin-spring@dokkabei-harness --scope local
# 설치 전이면: claude plugin install kotlin-spring@dokkabei-harness --scope local

# Codex — 설치는 전역(설치하면 ~/.codex/config.toml 에 enabled = true). dependencies 는 따라 설치되지 않는다
codex plugin add backend-shared@dokkabei-harness
codex plugin add kotlin-spring@dokkabei-harness
```

```toml
# Codex — 이 프로젝트에서만: ~/.codex/config.toml 에서 enabled = false 로 두고 <repo>/.codex/config.toml 에
[plugins."kotlin-spring@dokkabei-harness"]
enabled = true
```

```bash
# Antigravity — 전역 설치(~/.gemini/config/plugins/<name>, Claude 형식을 변환). dependencies 무시 → backend-shared 도 함께
agy plugin install <dokkabei-harness clone>/plugins/backend-shared
agy plugin install <dokkabei-harness clone>/plugins/kotlin-spring
# 이 프로젝트에서만: 위 변환본 디렉터리를 <repo>/.agents/plugins/<name>/ 로 복사(원본 Claude 디렉터리는 로드되지 않음)
```

- 이미 켜져 있으면 생략하고 "이미 활성(<런타임>/<범위>)"으로만 적는다. 확인 위치: Claude `enabledPlugins`
  (`.claude/settings.local.json`, `.claude/settings.json`, 사용자 전역), Codex `~/.codex/config.toml`·`<repo>/.codex/config.toml`
  의 `[plugins."<name>@dokkabei-harness"]`, Antigravity `~/.gemini/config/plugins/<name>`·`<repo>/.agents/plugins/<name>`
- Codex 의 `<repo>/.codex/config.toml` 은 신뢰된 프로젝트에서만 읽힌다(격리 CODEX_HOME 실측: 미신뢰 0건, `trust_level = "trusted"` 후 로드).
  커밋 대상 파일이므로 개인용이면 `.gitignore` 에 넣으라고 덧붙인다. Codex 는 플러그인 훅을 `/hooks` 에서 신뢰해야 실행한다
- Antigravity `agy plugin enable|disable <dir>` 는 전역 스위치다. 새로 설치한 디렉터리는 agy 재시작 후 반영.
  서브커맨드 뒤 `--help` 는 도움말이 아니라 실행으로 처리된다(`agy plugin uninstall --help` 가 실제 제거를 시도 — 실측)
- 설치본이 구버전(색인 0건)이면 Phase 2-3 의 런타임별 갱신 명령 안내
- 반영은 다음 세션부터

## (e) 선택 — Antigravity 경로 한정 rules `.agents/rules/<stack>-specialist.md`

(c) 와 본문이 같고 frontmatter 만 다르다. `agy plugin validate` 실측: `trigger` 는 `always_on|model_decision|glob|manual`,
`glob` 에는 `globs` 가 필요하고, `globs` 를 YAML 리스트로 쓰면 "cannot unmarshal !!seq into string … The loader skips this rule".

```markdown
---
trigger: glob
globs: "**/*.kt,**/*.kts,**/application*.yml"
---
<!-- project-rules: generated YYYY-MM-DD · mirror of .claude/rules/kotlin-specialist.md -->
…(c) 와 같은 본문
```

- 쉼표가 패턴 구분자로 해석되는지, 파일을 열 때 실제로 로드되는지는 미실측 — 제안 시 그렇게 고지하고 사용자가 원할 때만 만든다
- `--check` 는 (c) 와 본문(frontmatter 제외)이 같은지 본다

## (f) 이전 예 (이전 버전 출력 → AGENTS.md)

```diff
--- CLAUDE.md
+@AGENTS.md
+
 # CLAUDE.md
 …
-<!-- project-rules:start -->
-…(옛 스택 사실 블록)
-<!-- project-rules:end -->
--- AGENTS.md   (없으면 새 파일)
+<!-- project-rules:start -->
+…(재감지한 Stack facts + specialist-core.md 에서 옮긴 Specialist core)
+<!-- project-rules:end -->
--- .claude/rules/specialist-core.md   (삭제)
```
