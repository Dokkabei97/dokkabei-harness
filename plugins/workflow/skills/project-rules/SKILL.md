---
name: project-rules
description: |
  현재 프로젝트의 스택(빌드 파일 버전, 마이그레이션 도구, ORM 유무, ES 사용, git 호스트)을 감지해 프로젝트 루트 AGENTS.md 의 마커 블록(스택 사실 + 항상 적용되는 스페셜리스트 핵심 ≤15줄 — Claude Code·Codex·Antigravity 공통)과 CLAUDE.md 의 `@AGENTS.md` 연결, Claude 전용 경로 한정 .claude/rules/<stack>-specialist.md(해당 버전에 실제로 맞는 상세 함정)를 diff 로 제안하고, 스택 플러그인을 런타임별로 프로젝트 범위에서 켜는 법을 안내한다. 이전 버전 출력(CLAUDE.md 블록·specialist-core.md)은 AGENTS.md 로 이전을 제안. --check 는 버전 불일치·사라진 ID·크기 한도·연결 누락을 점검.
  Detects the project's stack and proposes a cross-runtime AGENTS.md block (stack facts + always-on specialist core) linked from CLAUDE.md via @AGENTS.md, plus Claude-only path-scoped specialist rules; migrates the older CLAUDE.md-block layout; --check audits drift.
  Use when: "이 프로젝트 세팅", "프로젝트 규칙 생성", "AGENTS.md/CLAUDE.md 점검", project setup, generate project rules, audit AGENTS.md or CLAUDE.md drift.
argument-hint: "[--check] [subdir]"
---

# Project Rules — 프로젝트별 스택 사실과 스페셜리스트 규칙

스택 플러그인은 "현직 시니어도 놓치는 함정"을 ID 붙은 항목으로 담고 있다(`### <PREFIX>-<AREA>-<NN> · 제목`
+ `- 적용:` 조건). 이 스킬은 그중 **이 프로젝트의 버전·구성에 실제로 해당하는 것만** 골라 프로젝트에 심고,
버전·도구 같은 사실은 프로젝트 지침 파일에 둔다. 범용 지식을 프로젝트에 복사하지 않는다.

모든 쓰기는 **diff 제안 → 사용자 승인 → 적용** 순서다. 승인 전에는 읽기만 한다.

## 로드 방식이 배치를 정한다

세 런타임이 공통으로 항상 읽는 파일은 **AGENTS.md 하나**다. 그래서 항상 적용돼야 하는 것은 AGENTS.md 에 둔다.

| 런타임 | 항상 로드 | 근거 |
|--------|-----------|------|
| Claude Code | `CLAUDE.md`(+`@import`). CLAUDE.md 가 **없을 때만** AGENTS.md 를 직접 읽는다(v2.1.277+). CLAUDE.md 가 있으면 `@AGENTS.md` import 가 있어야 AGENTS.md 가 들어온다. 블록 수준 HTML 주석은 제거된다 | code.claude.com/docs/en/memory §AGENTS.md, §Share one file with other coding tools |
| Codex CLI | git 루트→cwd 의 `AGENTS.md`(디렉터리당 1개, `AGENTS.override.md` 우선)를 이어 붙임. CLAUDE.md·`@import` 는 읽지 않는다. 합계 `project_doc_max_bytes`=32 KiB 초과분은 잘린다. HTML 주석이 그대로 들어간다 | 런타임 실측(codex 0.165) |
| Antigravity | cwd(파일을 열면 그 디렉터리)→레포 루트의 `AGENTS.md`/`GEMINI.md`. CLAUDE.md 는 읽지 않는다. 파일당 24,000바이트에서 줄 단위로 잘림 | `agy-customizations/docs/rules.md:12-15,31-33`, `agy-customizations/SKILL.md:49-51`, 실측(agy 1.4.7) |

Claude Code 의 경로 한정 rules(`.claude/rules/*.md` + `paths`)는 Read/Write/Edit(또는 단일 파일 `cat`·`head`·`sed -n` 같은
읽기형 Bash)로 매칭 파일을 다룰 때만 로드되고 compaction 뒤엔 다시 매칭될 때까지 빠진다. Bash heredoc·`tee`·`sed -i` 로
**쓰는** 것은 트리거가 아니다 — 새 파일을 만들 때 걸리는 함정은 항상 로드되는 쪽에 둬야 한다. 그래서:

- **스택 사실 + 스페셜리스트 핵심 ≤15줄** → 프로젝트 루트 `AGENTS.md` 마커 블록 (세 런타임 공통, 항상)
- **CLAUDE.md 연결** → `@AGENTS.md` 한 줄 (CLAUDE.md 가 있을 때. 없으면 만들지 않는 것이 기본 — Phase 4 (b))
- **상세 항목** → `.claude/rules/<stack>-specialist.md`, `paths` 있음 — **Claude Code 전용 보너스**. Codex 에는 파일 경로로 켜지는
  규칙이 확인되지 않았고(하위 AGENTS.md 는 cwd 경로 기준), Antigravity 는 선택 출력 (e) 로만 대응한다

## 모드

| 인자 | 동작 |
|------|------|
| (없음) | 감지 → 생성 제안(a)~(d), 선택 (e). 이전 버전 출력이 있으면 이전 제안(Phase 4 (f))을 함께 |
| `--check` | 감지 → AGENTS.md 블록·CLAUDE.md 연결·rules 와 대조해 드리프트 보고(수정은 승인 후) |
| `<subdir>` | 모노레포의 하위 프로젝트만 대상 — 블록은 `<subdir>/AGENTS.md`, 규칙 `paths` 도 그 하위로 한정 |

## Phase 1: 감지 (읽기 전용)

[references/detection.md](references/detection.md) 의 표대로 파일을 읽어 아래 **스택 프로필**을 만든다.
값을 확인하지 못하면 비워 두고 "미확인"으로 표시한다 — 추측해서 채우지 않는다. BOM·카탈로그가 관리하는
버전(lock 없음)은 "BOM 관리(미확인)"이다. 대상 저장소에서 빌드 도구를 실행하지 않는다(캐시·빌드 디렉터리에 쓴다).

```
stack profile
- jvm: JDK toolchain=21 / Kotlin=2.1.0 / Spring Boot=3.4.1 / build=Gradle(kts, version catalog)
- go: go=1.23 (toolchain go1.23.4) / router=net/http / db=pgx stdlib
- python: requires-python>=3.12 / FastAPI / ORM=없음(psycopg 원시 SQL)
- node: next=16.x / react=19.x
- elasticsearch: client=co.elastic.clients:elasticsearch-java 8.x / mappings=src/main/resources/es/*.json
- db: PostgreSQL(+PostGIS) / migrations=dbmate(db/migrations)
- infra: Dockerfile, k8s manifests → 컨테이너 배포 (compose 로 의존 서비스만 띄우는 것은 앱 컨테이너 배포가 아니다)
- vcs: gitlab.<company> → glab / github.com → gh
- verify: ./gradlew check, go test ./..., pytest, pnpm test (빌드 파일·CI 설정·AGENTS.md·CLAUDE.md 에서 확인된 것만)
- instructions: AGENTS.md 4.1KB(블록 없음) / CLAUDE.md 133줄, `@AGENTS.md` 없음 / AGENTS.override.md·CLAUDE.local.md 없음
       / legacy: CLAUDE.md 에 project-rules 블록, .claude/rules/specialist-core.md 있음 → 이전 대상
- existing: AGENTS.md·CLAUDE.md 블록 밖에 이미 적힌 사실·함정(중복 제안 방지용)
```

## Phase 2: 스페셜리스트 항목 수집

1. 프로필에 해당하는 플러그인만 색인한다(매핑은 [references/detection.md](references/detection.md) §2):
   ```bash
   bash "<스킬 디렉터리>/scripts/specialist-index.sh" auto kotlin-spring backend-shared search
   ```
   - `<스킬 디렉터리>` = 이 SKILL.md 가 있는 디렉터리. Claude Code 는 `${CLAUDE_SKILL_DIR}` 로 쓴다. Codex·Antigravity 는
     `${CLAUDE_SKILL_DIR}`·`${CLAUDE_PLUGIN_ROOT}` 를 스킬 본문에서 치환하지 않으므로 이 SKILL.md 를 읽은 절대 경로에서
     잡는다(Codex 는 스킬 목록의 skill roots 표, Antigravity 는 `~/.gemini/config/plugins/workflow/skills/project-rules`)
   - `auto` 는 원천을 스크립트가 정한다: 지금 실행 중인 workflow 와 **같은 설치본의 형제 플러그인**(레포 `plugins/`,
     Claude·Codex 캐시 `<plugin>/<version>/`, Antigravity 변환본 `<plugin>/`)을 먼저 보고, 없는 플러그인만
     `~/.claude/plugins/cache/dokkabei-harness` → `${CODEX_HOME:-~/.codex}/plugins/cache/dokkabei-harness` →
     `./.agents/plugins` → `~/.gemini/config/plugins` 순으로 찾는다. 원천을 직접 주려면 `auto` 대신 그 디렉터리
2. stdout 은 `plugin  skill  id  title  applies  file`(절대 경로) TSV 한 줄씩 — 본문 전체를 읽지 않고 고른다.
   stderr 의 `source  plugin  version  items  dir` 줄이 rules 메타(`source <plugin>@<version>/<items>`)의 값이다
3. `items` 가 0 이거나 `dir` 이 `-` 인 플러그인은 설치본이 구버전이거나 없다 → 런타임별 갱신 명령(Claude
   `/plugin update <name>@dokkabei-harness`, Codex `codex plugin add <name>@dokkabei-harness`, Antigravity
   `agy plugin install <clone>/plugins/<name>`) 후 재실행을 안내하고 해당 스택은 건너뛴다(빈 rules 를 만들지 않는다)

## Phase 3: 선별 (스택당 ≤15, core 는 전체 ≤15)

[references/selection.md](references/selection.md) 의 기준으로 거른다. 요약:

1. **적용 조건 일치** — `applies` 의 버전·구성 조건이 프로필과 맞는 것만. 판단이 애매하면 제외.
2. **신호 확인** — 후보의 `- 신호:` 줄만 읽는다. 코드 패턴이면 Grep 으로 저장소에서 찾고, 런타임 증상(지연·로그·메트릭)이면
   그 증상을 만드는 **구성(construct)** 이 코드에 있는지 확인한다. 신호가 이미 대응돼 있으면 "대응됨"으로 표시한다.
3. **중복 배제** — 같은 메커니즘은 하나만(플러그인을 가로질러도), 블록 밖 AGENTS.md·CLAUDE.md 에 이미 적힌 함정도 제외.
4. **core 지정** — 선별된 것 중 ①새 파일을 만들 때 걸리는 함정(마이그레이션·라우트·액션·DTO) ②모델이 구버전 습관으로
   틀리는 버전 함정 ③신호가 발견된 운영 장애급 — 이 순서로 전체 ≤15줄. Codex·Antigravity 에는 경로 rules 가 없으므로
   core 가 그 런타임이 받는 스페셜리스트의 전부다 — 둘 중 하나를 고를 때는 core 쪽을 택한다.
5. 15개를 채우려고 억지로 넣지 않는다. 5개여도 된다.

## Phase 4: 생성 제안

템플릿은 [references/templates.md](references/templates.md).

**(a) 프로젝트 루트 `AGENTS.md` 마커 블록** — `<!-- project-rules:start -->` … `<!-- project-rules:end -->`
- `## Stack facts`(≤30줄: 버전·빌드/마이그레이션 도구·검증 명령·VCS/CLI·rules 안내 1줄) + `## Specialist core`(항목 ≤15줄,
  스택별 `###` 소제목. 각 줄은 "무엇을 하면 안 되는지/해야 하는지"가 줄 자체로 서야 한다 — 깊이 참조를 열지 않아도 행동이 바뀌게)
- 크기: 블록 ≤50줄·≤6,000바이트. 적용 후 AGENTS.md 전체 ≤24,000바이트(Antigravity 파일 한도 — 넘으면 줄 단위로 잘림),
  git 루트→가장 깊은 작업 디렉터리의 AGENTS.md 합계 ≤32,768바이트(Codex `project_doc_max_bytes` 기본값 — 넘으면 잘리고
  더 깊은 파일은 빠진다). 넘으면 블록 밖을 줄이라고 보고만 한다(블록 밖은 이 스킬 소관이 아니다)
- 위치: 블록이 없으면 첫 `##` 섹션 앞(잘림은 파일 뒤부터라 블록이 살아남게). 있으면 **그 안만** 교체(멱등).
  AGENTS.md 가 없으면 블록만 담은 새 파일을 제안한다
- 블록 밖에 이미 같은 사실이 있으면 블록에 다시 쓰지 않는다(블록 밖 수정은 `workflow:sync-claude-md` 소관 — 불일치만 보고)
- 블록 안 깊이 참조는 런타임 중립 표기 `(<plugin>:<skill>)` — 슬래시 명령 표기는 런타임마다 다르다

**(b) `CLAUDE.md` 연결** — Claude Code 가 AGENTS.md 블록을 보게 한다

| 상태 | 제안 |
|------|------|
| CLAUDE.md 없음 | 만들지 않는 것이 기본(Claude Code v2.1.277+ 는 CLAUDE.md 가 없으면 AGENTS.md 를 직접 읽는다). 승인 게이트에서 "`@AGENTS.md` 한 줄짜리 CLAUDE.md 도 만들까요?"를 묻는다 — 구버전·AGENTS.md 지원이 꺼진 세션, 나중에 `CLAUDE.local.md` 를 둘 계획이면 필요(`CLAUDE.local.md` 가 생기면 AGENTS.md 직접 읽기가 멈춘다) |
| CLAUDE.md 있음, 코드 밖 `@AGENTS.md` 없음 | 맨 위에 `@AGENTS.md` 한 줄 추가(이 스킬이 블록 밖에서 하는 유일한 편집). 단 AGENTS.md 가 CLAUDE.md 의 사본에 가까우면 import 로 같은 내용이 두 번 들어간다 — (f)-3 판정을 먼저 한다 |
| 이미 `@AGENTS.md` 있음 | 생략 |

적용 후 CLAUDE.md(+`@import` 대상, 즉 AGENTS.md 포함)가 200줄을 넘으면 경고하고 일부를 path-scoped rules 로 옮기는 안을 제시한다.

**(c) `.claude/rules/<stack>-specialist.md`** — **Claude Code 전용 보너스**. 스택(코드 위치)당 1파일, frontmatter 는 `paths` 만
- 본문: 생성 메타 주석 1줄 + 항목당 1줄 `- **<ID>** <함정 요약> — 깊이: /<plugin>:<skill> 의 <ID>`
- core 에 올린 ID 는 반복하지 않는다. 남는 항목이 없으면 파일을 만들지 않는다
- 기존 파일이 있으면 diff 로 제안(사용자가 손으로 추가한 줄은 보존)

**(d) 스택 플러그인 활성화 안내** — 이 프로젝트에서만 켜기. 런타임별 명령은 templates.md (d):
- Claude Code: `claude plugin enable <name>@dokkabei-harness --scope local` (커밋되지 않는 `.claude/settings.local.json`)
- Codex: 프로젝트 `.codex/config.toml` 의 `[plugins."<name>@dokkabei-harness"] enabled = true`(신뢰된 프로젝트에서만 읽힘;
  설치는 `codex plugin add`, 전역에서 끄려면 `~/.codex/config.toml` 에 `enabled = false`)
- Antigravity: 프로젝트 범위 스위치가 없다 — 전역 `agy plugin install <clone>/plugins/<name>`, 또는 변환본을
  `<repo>/.agents/plugins/<name>/` 에 둔다
- Codex·Antigravity 는 `dependencies` 를 따라 설치하지 않는다 — kotlin-spring·go-mux·python-fastapi 는 backend-shared 를 함께
- 이미 켜져 있으면 생략한다. 명령은 안내만 하고 실행은 사용자 요청 시에만 한다. 반영은 다음 세션부터

VCS 안내: gitlab 호스트면 `/workflow:review-mr`, `/workflow:release-notes`(glab 필요)를, github 이면 `gh pr` 흐름을
블록의 VCS 줄에 적는다.

**(e) 선택 — Antigravity 경로 한정 rules** `.agents/rules/<stack>-specialist.md`: 사용자가 Antigravity 를 쓴다고 할 때만.
(c) 와 같은 본문에 frontmatter 만 `trigger: glob` + `globs: "<쉼표 구분 문자열>"`(YAML 리스트는 로더가 거부 — `agy plugin
validate` 실측). Claude Code 는 `.agents/` 아래를 읽지 않고 Codex 도 읽지 않으므로 중복 로드는 없다. 쉼표 구분자의 실제 매칭과
런타임 발화는 미실측 — 제안할 때 그렇게 고지한다.

**(f) 이전 버전 출력의 이전** — 블록이 CLAUDE.md 에 있거나 `.claude/rules/specialist-core.md`(메타 주석 `project-rules:`)가 있으면:
1. AGENTS.md 에 (a) 블록을 새로 만든다. 스택 사실은 재감지 결과로, core 는 specialist-core.md 항목을 Phase 3 로 재판정해
   `## Specialist core` 로 옮긴다(`<!-- manual -->` 줄은 그대로 보존)
2. CLAUDE.md 에서 옛 블록(마커 줄 포함)을 지우고 (b) 대로 `@AGENTS.md` 를 단다. specialist-core.md 는 삭제를 제안한다 —
   남기면 Claude 에 같은 core 가 두 번 들어간다. path rules 의 "핵심은 specialist-core.md" 문구도 AGENTS.md 로 고친다
3. AGENTS.md 가 이미 있고 CLAUDE.md 와 거의 같은 사본이면(블록 밖 비어 있지 않은 줄의 절반 이상이 같음 —
   `grep -Fxf CLAUDE.md AGENTS.md | grep -c .` 대 `grep -c . AGENTS.md`) import 하면 내용이 두 번 들어간다. 둘 중 하나를 고르게 한다:
   - **통합**: CLAUDE.md 를 `@AGENTS.md` + 두 파일의 차이 줄(Claude 전용분)만 남기는 diff — 블록 밖 편집이므로 diff 를 보여주고 별도 승인
   - **미러**: import 없이 같은 블록을 AGENTS.md 와 CLAUDE.md 양쪽에 둔다. `--check` 가 두 사본이 같은지 본다
4. 적용 순서는 AGENTS.md 쓰기 → CLAUDE.md 수정 → specialist-core.md 삭제. 중간에 멈춰도 내용이 사라지지 않게

## Phase 5: 승인과 적용

1. (a)~(f) 중 해당하는 것을 한 번에 보여준다: 파일별 diff + 선별 근거 표(ID · 적용 조건 · 신호 · core 여부) + 제외 요약
   + 크기(블록·AGENTS.md 바이트, CLAUDE.md+import 줄 수)
2. 사용자가 고른 것만 적용한다. 전체/부분/반려 모두 가능
3. 적용 후 요약 1~3줄. git commit 은 하지 않는다

## --check 모드

[references/selection.md](references/selection.md) §5 의 점검표로 보고만 한다. 기준 파일은 AGENTS.md 블록이다.

| 점검 | 방법 | 보고 예 |
|------|------|---------|
| 블록 위치 | AGENTS.md 에 마커 한 쌍, CLAUDE.md 에 블록 없음(미러 모드면 두 사본 동일) | `블록이 CLAUDE.md 에만 있음 — 이전 필요 (f)` |
| Claude 연결 | CLAUDE.md 가 있으면 코드 밖 `@AGENTS.md`(또는 미러) | `CLAUDE.md 에 @AGENTS.md 없음 — Claude 는 블록을 못 본다` |
| 버전 드리프트 | 블록/rules 메타의 버전 ↔ 현재 빌드 파일 | `Spring Boot 3.3.5 → 3.4.1 (build.gradle.kts)` |
| 없는 도구 참조 | 블록의 도구·명령 ↔ 실제 파일 | `Flyway 참조, 의존성 없음 — dbmate 사용 중` |
| 사라진 ID | core·rules 의 ID ↔ 현재 색인 | `JVM-GC-07 플러그인에서 사라짐` |
| 조건 이탈 | 항목의 `applies` ↔ 현재 프로필 | `JVM-CONC-01 은 가상 스레드(JDK 21+) 전제, 현재 17` |
| core 형식 | `## Specialist core` 항목 ≤15줄, path rules 와 ID 중복 없음, 옛 specialist-core.md 없음 | `SPR-TX-02 가 core 와 kotlin-specialist.md 에 중복` |
| 크기 | 블록 ≤50줄·6,000B, `wc -c AGENTS.md` ≤24,000, 루트→하위 AGENTS.md 합계 ≤32,768, CLAUDE.md+import ≤200줄 | `AGENTS.md 25,310B (>24,000, Antigravity 에서 잘림)` |
| 가림 | `AGENTS.override.md`(Codex 가 대신 읽음), CLAUDE.md 없이 `CLAUDE.local.md`(Claude 가 AGENTS.md 를 안 읽음) | `AGENTS.override.md 있음 — Codex 는 블록을 못 본다` |

드리프트가 있으면 "재생성 제안을 볼까요?" 로 끝낸다.

## 경계

- 쓰는 파일(승인 후에만): 프로젝트 `AGENTS.md` 의 마커 블록, `CLAUDE.md` 의 `@AGENTS.md` 한 줄(없을 때)과 옛 블록 제거·
  통합/미러((f)), `.claude/rules/*-specialist.md`, 선택 `.agents/rules/*-specialist.md`, 옛 `.claude/rules/specialist-core.md` 삭제
- 쓰지 않는 것: `~/.claude/`·`~/.codex/`·`~/.gemini/` 전역 설정, settings.json·`.codex/config.toml`(플러그인 활성화는 명령 안내까지),
  블록 밖 AGENTS.md·CLAUDE.md 내용(그건 `workflow:sync-claude-md` 소관 — (f)-3 통합만 예외로 별도 승인), 스택 플러그인 본문
- 항목 원문을 블록·rules 에 복사하지 않는다 — ID + 한 줄 요약 + 깊이 참조만
