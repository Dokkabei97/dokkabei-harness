---
name: project-rules
description: |
  현재 프로젝트의 스택(빌드 파일 버전, 마이그레이션 도구, ORM 유무, ES 사용, git 호스트)을 감지해 프로젝트 CLAUDE.md 의 스택 사실 블록, 항상 로드되는 .claude/rules/specialist-core.md(핵심 함정 ≤15줄, paths 없음), 경로 한정 .claude/rules/<stack>-specialist.md(해당 버전에 실제로 맞는 상세 함정)를 diff 로 제안하고, 스택 플러그인을 프로젝트 범위로 켜는 법을 안내한다. --check 는 버전 불일치·사라진 ID·200줄 초과·core 중복을 점검.
  Detects the project's stack and proposes a CLAUDE.md stack-facts block, an always-loaded specialist core rule, and path-scoped specialist rules; --check audits drift.
  Use when: "이 프로젝트 세팅", "프로젝트 규칙 생성", "CLAUDE.md 점검", project setup, generate project rules, audit CLAUDE.md drift.
argument-hint: "[--check] [subdir]"
---

# Project Rules — 프로젝트별 스택 사실과 스페셜리스트 규칙

스택 플러그인은 "현직 시니어도 놓치는 함정"을 ID 붙은 항목으로 담고 있다(`### <PREFIX>-<AREA>-<NN> · 제목`
+ `- 적용:` 조건). 이 스킬은 그중 **이 프로젝트의 버전·구성에 실제로 해당하는 것만** 골라 프로젝트에 심고,
버전·도구 같은 사실은 프로젝트 CLAUDE.md 에 둔다. 범용 지식을 프로젝트에 복사하지 않는다.

모든 쓰기는 **diff 제안 → 사용자 승인 → 적용** 순서다. 승인 전에는 읽기만 한다.

## 로드 방식이 배치를 정한다

공식 동작(code.claude.com/docs/en/memory, …/context-window):

| 위치 | 언제 로드 | compaction 후 |
|------|-----------|---------------|
| 프로젝트 루트 `CLAUDE.md` | 기동 시 | 디스크에서 재주입 |
| `.claude/rules/*.md` **paths 없음** | 기동 시, `.claude/CLAUDE.md` 와 같은 우선순위 | 재주입 |
| `.claude/rules/*.md` **paths 있음** | Read/Write/Edit 도구로 매칭 파일을 다룰 때, 또는 단일 파일 `cat`·`head`·`sed -n` 처럼 "읽기로 치는" Bash | 요약돼 사라짐 — 다시 매칭될 때 재로드 |

Bash 리다이렉트·heredoc(`cat > f <<EOF`, `tee`, `sed -i`)로 **쓰는** 것은 어느 쪽에도 해당하지 않는다.
bypassPermissions 세션은 이 경로로 파일을 많이 쓰므로(새 마이그레이션·새 라우트를 heredoc 으로 생성)
paths rules 만으로는 정작 새 파일을 만들 때 규칙이 비어 있다. 그래서:

- **스택 사실** → CLAUDE.md 마커 블록 (항상)
- **핵심 스페셜리스트 요약 ≤15줄** → `.claude/rules/specialist-core.md`, `paths` 없음 (항상)
- **상세 항목** → `.claude/rules/<stack>-specialist.md`, `paths` 있음 (해당 파일을 읽을 때)

## 모드

| 인자 | 동작 |
|------|------|
| (없음) | 감지 → 생성 제안(a)(b)(c)(d) |
| `--check` | 감지 → 기존 블록·rules 와 대조해 드리프트 보고(수정은 승인 후) |
| `<subdir>` | 모노레포의 하위 프로젝트만 대상(규칙 `paths` 도 그 하위로 한정) |

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
- verify: ./gradlew check, go test ./..., pytest, pnpm test (빌드 파일·CI 설정·CLAUDE.md 에서 확인된 것만)
- existing: CLAUDE.md 블록 밖에 이미 적힌 사실·함정(중복 제안 방지용)
```

## Phase 2: 스페셜리스트 항목 수집

1. **원천 위치**는 지금 실행 중인 workflow 플러그인이 놓인 곳을 따른다:
   - `${CLAUDE_PLUGIN_ROOT}/../<plugin>/skills` 가 있으면(레포 clone·`--plugin-dir` 로드, 구조 `<plugin>/skills/…`)
     → `${CLAUDE_PLUGIN_ROOT}/..`
   - 아니면 설치본 `~/.claude/plugins/cache/dokkabei-harness` (구조 `<plugin>/<version>/skills/…`)
2. 프로필에 해당하는 플러그인만 색인한다(매핑은 [references/detection.md](references/detection.md) §2):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/specialist-index.sh" <원천> kotlin-spring backend-shared search
   ```
   출력은 `plugin  skill  id  title  applies  file`(절대 경로) TSV 한 줄씩 — 본문 전체를 읽지 않고 고른다.
3. 색인이 0건인 플러그인은 설치본이 구버전이다 → "`/plugin update <name>@dokkabei-harness` 후 재실행"을 안내하고
   해당 스택은 rules 생성을 건너뛴다(빈 rules 파일을 만들지 않는다).

## Phase 3: 선별 (스택당 ≤15, core 는 전체 ≤15)

[references/selection.md](references/selection.md) 의 기준으로 거른다. 요약:

1. **적용 조건 일치** — `applies` 의 버전·구성 조건이 프로필과 맞는 것만. 판단이 애매하면 제외.
2. **신호 확인** — 후보의 `- 신호:` 줄만 읽는다. 코드 패턴이면 Grep 으로 저장소에서 찾고, 런타임 증상(지연·로그·메트릭)이면
   그 증상을 만드는 **구성(construct)** 이 코드에 있는지 확인한다. 신호가 이미 대응돼 있으면 "대응됨"으로 표시한다.
3. **중복 배제** — 같은 메커니즘은 하나만(플러그인을 가로질러도), 블록 밖 CLAUDE.md 에 이미 적힌 함정도 제외.
4. **core 지정** — 선별된 것 중 ①새 파일을 만들 때 걸리는 함정(마이그레이션·라우트·액션·DTO) ②모델이 구버전 습관으로
   틀리는 버전 함정 ③신호가 발견된 운영 장애급 — 이 순서로 전체 ≤15줄.
5. 15개를 채우려고 억지로 넣지 않는다. 5개여도 된다.

## Phase 4: 생성 제안

템플릿은 [references/templates.md](references/templates.md).

**(a) 프로젝트 CLAUDE.md 스택 사실 블록** — `<!-- project-rules:start -->` … `<!-- project-rules:end -->`
- ≤30줄: 버전·빌드/마이그레이션 도구·검증 명령·VCS/CLI·rules 파일 안내 1줄
- 블록 밖에 이미 같은 사실이 있으면 블록에 다시 쓰지 않는다(블록 밖 수정은 `workflow:sync-claude-md` 소관 — 불일치만 보고)
- 블록이 이미 있으면 **그 안만** 교체(멱등). CLAUDE.md 가 없으면 블록만 담은 새 파일을 제안한다
- 적용 후 전체(+`@import` 파일)가 200줄을 넘으면 경고하고, 일부를 path-scoped rules 로 옮기는 안을 제시한다

**(b) `.claude/rules/specialist-core.md`** — 프로젝트당 1파일, **frontmatter 없음**
- 스택별 소제목 + 항목당 1줄, 전체 항목 ≤15줄. 각 줄은 "무엇을 하면 안 되는지/해야 하는지"가 줄 자체로 서야 한다
  (깊이 참조를 따라가지 않아도 행동이 바뀌어야 함)

**(c) `.claude/rules/<stack>-specialist.md`** — 스택(코드 위치)당 1파일, frontmatter 는 `paths` 만
- 본문: 생성 메타 주석 1줄 + 항목당 1줄 `- **<ID>** <함정 요약> — 깊이: /<plugin>:<skill> 의 <ID>`
- core 에 올린 ID 는 반복하지 않는다. 남는 항목이 없으면 파일을 만들지 않는다
- 기존 파일이 있으면 diff 로 제안(사용자가 손으로 추가한 줄은 보존)

**(d) 스택 플러그인 활성화 안내** — 이 프로젝트에서만 켜기(커밋되지 않는 local scope 권장):
```bash
claude plugin enable kotlin-spring@dokkabei-harness --scope local
```
`.claude/settings.local.json`·`.claude/settings.json` 의 `enabledPlugins` 나 사용자 전역에서 이미 켜져 있으면 생략한다.
명령은 안내만 하고 실행은 사용자 요청 시에만 한다. 반영은 다음 세션부터.

VCS 안내: gitlab 호스트면 `/workflow:review-mr`, `/workflow:release-notes`(glab 필요)를, github 이면 `gh pr` 흐름을
블록의 VCS 줄에 적는다.

## Phase 5: 승인과 적용

1. (a)~(d) 를 한 번에 보여준다: 파일별 diff + 선별 근거 표(ID · 적용 조건 · 신호 · core 여부) + 제외 요약
2. 사용자가 고른 것만 적용한다. 전체/부분/반려 모두 가능
3. 적용 후 요약 1~3줄. git commit 은 하지 않는다

## --check 모드

[references/selection.md](references/selection.md) §5 의 점검표로 보고만 한다.

| 점검 | 방법 | 보고 예 |
|------|------|---------|
| 버전 드리프트 | 블록/rules 메타의 버전 ↔ 현재 빌드 파일 | `Spring Boot 3.3.5 → 3.4.1 (build.gradle.kts)` |
| 없는 도구 참조 | 블록의 도구·명령 ↔ 실제 파일 | `Flyway 참조, 의존성 없음 — dbmate 사용 중` |
| 사라진 ID | core·rules 의 ID ↔ 현재 색인 | `JVM-GC-07 플러그인에서 사라짐` |
| 조건 이탈 | 항목의 `applies` ↔ 현재 프로필 | `JVM-CONC-01 은 가상 스레드(JDK 21+) 전제, 현재 17` |
| core 형식 | core 에 `paths` 가 없고 ≤15줄, path rules 와 ID 중복 없음 | `specialist-core.md 에 paths 있음 — 항상 로드되지 않음` |
| 크기 | `wc -l CLAUDE.md` (+ `@import`) | `CLAUDE.md 231줄 (>200)` |

드리프트가 있으면 "재생성 제안을 볼까요?" 로 끝낸다.

## 경계

- 쓰는 파일: 프로젝트 `CLAUDE.md` 의 마커 블록, `.claude/rules/specialist-core.md`, `.claude/rules/*-specialist.md` — 승인 후에만
- 쓰지 않는 것: `~/.claude/` 전역 설정, settings.json(플러그인 활성화는 명령 안내까지), 블록 밖 CLAUDE.md 내용
  (그건 `workflow:sync-claude-md` 소관), 스택 플러그인 본문
- 항목 원문을 rules 에 복사하지 않는다 — ID + 한 줄 요약 + 깊이 참조만
