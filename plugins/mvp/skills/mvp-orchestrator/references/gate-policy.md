# Gate Policy — 게이트 스크립트 판정 기준 · Stop훅 정지조건 · 가드레일 명세

MVP 하네스의 모든 결정론 판정 기준을 정의한다. 게이트 3종(`gate-prd.sh` / `gate-design.sh` / `gate-scaffold.sh`)은 **훅에 등록하지 않으며**, 오케스트레이터 또는 `/mvp-gate` 커맨드가 Bash로 직접 호출한다. Stage 4 루프 판정은 Stop훅(`mvp-loop-stop-hook.sh`)과 PostToolUse 훅(`prd-guard.sh`)이 수행한다.

## 공통 규약

| 항목 | 규약 |
|------|------|
| 실행 위치 | 프로젝트 루트(`${CLAUDE_PROJECT_DIR:-.}`). 모든 `.planning/` 경로는 이 기준의 상대경로 |
| 호출 방법 | `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-prd.sh"` (design·scaffold 동일) |
| exit code | `0` = 통과 / `1` = 실패(stderr에 위반 항목별 사유 1줄씩) |
| 판정 원칙 | 결정론만 — grep/jq/git/exit code. LLM 판단·휴리스틱 점수화 금지 |
| 후속 동작 | 통과 → 1줄 보고 후 자동 진행 / 실패 → 중단 + 원인·시도·옵션 보고 / 판정 불가(파일 부재 등) → "모호" 처리, 권장안 보고 |

---

## gate-prd.sh — Stage 1 기획 게이트

**입력**: `.planning/prd.md`, `.planning/prd.json`

| # | 검사 | 판정 기준 |
|---|------|----------|
| 1 | prd.md 존재 | 파일 존재 + 비어 있지 않음 |
| 2 | prd.md 필수 헤딩 | 아래 헤딩이 모두 행두 앵커 grep으로 발견될 것(prd-authoring 스킬 §2 표준과 동일 문자열): `## 문제 정의` / `## 페르소나` / `## 범위`(+ `### In` / `### Out`) / `## 유저 스토리` / `## 성공 지표` |
| 3 | prd.json 파싱 | `jq -e .` 성공 (유효 JSON) |
| 4 | 스토리 수 | `.stories` 배열 길이 **3 이상 10 이하** — 상한은 `MVP_STORIES_MAX` env로 치환 가능(기본 10), 하한 3 고정 |
| 5 | 스토리 스키마 | 전 스토리가 **무조건** 충족: `id`는 `^S-[0-9]{2}$` 패턴, `title` 비어 있지 않은 문자열, `acceptance` 1개 이상의 비어 있지 않은 문자열 배열. `passes` 전건 false 검사는 **첫 번째 인자 `--initial` 전달 시에만**(스코프 재협상 후 재검증 호환) |
| 6 | id 유일성 | `(.stories | map(.id) | unique | length) == (.stories | length)` |

스키마 검증 jq 식(4·5·6 통합):

```bash
MAX="${MVP_STORIES_MAX:-10}"
jq -e --argjson max "$MAX" '
  (.stories | type == "array" and length >= 3 and length <= $max)
  and (.stories | all(
        (.id | test("^S-[0-9]{2}$"))
        and (.title | type == "string" and length > 0)
        and (.acceptance | type == "array" and length >= 1
             and all(type == "string" and length > 0))))
  and ((.stories | map(.id) | unique | length) == (.stories | length))
' .planning/prd.json

# --initial 전달 시에만 추가 검사 (작성 시점 전건 false):
# jq -e '[.stories[].passes] | all(. == false)' .planning/prd.json
```

> AC 품질(반증 가능한 Given-When-Then인가)은 결정론으로 잡을 수 없다 — MV의 Stage 1 반증 라운드가 담당한다. 이 게이트는 형식 보증선이다.

## gate-design.sh — Stage 2 디자인 게이트

**입력**: `.planning/prd.json`, `.planning/design-spec.md`

| # | 검사 | 판정 기준 |
|---|------|----------|
| 1 | design-spec.md 존재 | 파일 존재 + 비어 있지 않음 |
| 2 | 스토리 전건 매핑 | prd.json의 **모든** story id에 대해 design-spec.md에 `[story: S-xx]` 리터럴이 `grep -qF`로 발견될 것. 누락 id는 전부 stderr에 나열 |

판정 골격:

```bash
missing=0
for id in $(jq -r '.stories[].id' .planning/prd.json); do
  grep -qF "[story: ${id}]" .planning/design-spec.md || {
    echo "[gate-design] 매핑 누락: ${id}" >&2; missing=1; }
done
exit "$missing"
```

> 알려진 한계(설계 트레이드오프 3): 이 grep은 **매핑 누락만** 잡는다. 와이어프레임·4상태·디자인 토큰의 품질은 PS 교차검증(확률적)이 담당하며, 3결합 중 가장 약한 고리임을 통합 보고에 명시한다.

## gate-scaffold.sh — Stage 3 스캐폴딩 게이트

**입력**: `.planning/` 전체, git 저장소, `.planning/gate-cmd`

| # | 검사 | 판정 기준 |
|---|------|----------|
| 1 | .planning 필수 파일 | `mvp-*.md`(마스터 1개 이상) / `prd.md` / `prd.json` / `design-spec.md` / `stack-decision.md` / `gate-cmd` / `progress.md` 존재 + `verified/` 디렉토리 존재. (`loop-state.json`·`loop-active`는 `/mvp-run`이 생성하므로 검사 제외) |
| 2 | gate-cmd 형식 | 비어 있지 않은 **정확히 1줄** (`wc -l` 기준 개행 포함 1 이하, 공백만인 줄 불가) |
| 3 | 결정론 게이트 그린 | `bash -c "$(cat .planning/gate-cmd)"` exit 0 — 빈 골격에서 smoke 테스트 통과 |
| 4 | 초기 커밋 | `git rev-parse --verify HEAD` 성공 (커밋 1개 이상 존재) |
| 5 | 워킹트리 클린 | `git status --porcelain` 출력 없음 — 골격이 전부 커밋됐을 것 |

---

## Stop훅 정지조건 3결합 상세 (`mvp-loop-stop-hook.sh`)

flow-scaffolding `templates/loop-stop-hook.sh`의 확장. 판정 주체는 모델이 아니라 훅이다.

### 안전핀 (최우선)

```bash
[ -f "${CLAUDE_PROJECT_DIR:-.}/.planning/loop-active" ] || exit 0
```

`loop-active`가 없으면 **무조건 종료 허용** — 루프 미가동 세션(플러그인이 설치된 모든 일반 세션)의 종료를 절대 방해하지 않는다. `stop_hook_active` 재진입 검사는 템플릿 로직을 유지한다.

### ① 결정론 게이트

- 명령 로드: `LOOP_TEST_CMD` env가 있으면 우선, 없으면 `.planning/gate-cmd` 파일에서 동적 로드.
- 판정: **exit code 우선** — `bash -c "$GATE_CMD"`의 exit 0이 그린. 출력의 `grep -Ei 'fail|error'`는 no-progress 시그니처 생성용 **보조**로만 쓴다(출력 문자열 기반 성패 판정은 오탐 위험).
- AND 조건: `jq -e '[.stories[].passes] | all' .planning/prd.json` — 전 스토리 passes:true.
- **verified 마커 재검사**: all-passes 확인 시 `passes:true`인 각 id에 대해 `.planning/verified/{id}` 파일 존재까지 확인. 마커 없는 passes:true 발견 시 미충족(exit 2) — 재주입 메시지에 해당 id와 "mvp-verifier 반증을 통과시켜 마커를 생성하라" 안내.

### ② 회의적 Evaluator (verified 마커)

- `passes:true` 전환은 MV의 `.planning/verified/{story-id}` 마커(내용 = 반증 시도 요약)가 **선행**해야 한다.
- 집행자는 Stop훅이 아니라 PostToolUse 훅 `prd-guard.sh`: `prd.json` Edit/Write 직후 passes:true인 모든 story id에 대해 마커 존재를 검사하고, 위반 시 jq로 해당 passes를 false로 되돌린 뒤 exit 2로 차단 사유를 재주입한다.
- 설계 핵심: **Evaluator의 확률적 판정을 파일 마커로 물화해 결정론 검사로 변환**. 단 prd-guard는 Edit/Write만 포착하고 Bash 리다이렉션 우회가 가능하므로, **Stop훅이 종료 판정 시 마커를 재검사한다(최종 방어선)** — ①의 verified 마커 재검사 항목 참조.

### ③ Completion promise

- `.planning/progress.md`에 `<promise>MVP_COMPLETE</promise>` **정확 문자열**이 존재할 것. 검사는 `grep -qF`(고정 문자열) — 정규식 금지(부분 일치·변형 토큰 오탐 방지).
- `LOOP_PROMISE` env는 **태그를 포함한 전체 문자열**이다(기본값 `<promise>MVP_COMPLETE</promise>`). 훅은 `$LOOP_PROMISE` 값 그대로를 `grep -qF`로 찾는다 — 변경 시 progress.md 기록 문자열도 동일하게 맞출 것.

### 종료 판정식

```
종료 허용(exit 0) = ① (gate-cmd exit 0 ∧ jq all-passes ∧ verified 마커 전건) ∧ ③ promise 존재
```

②는 prd-guard의 1차 차단에만 의존하지 않고 **Stop훅이 마커를 재검사한다(최종 방어선)**. 미충족이면 exit 2 + stderr로 미완 사유(실패 테스트 tail, 미완 스토리, 마커 없는 passes:true id, promise 누락)를 재주입한다.

### 종료 경로 공통 의무

정지조건 충족·max-iter·no-progress·시간 상한 — **모든** 종료 경로에서 `loop-active`를 삭제하고, 비정상 계열(no-progress·상한)은 `BLOCKED.md`에 iteration·시그니처·게이트 출력 tail을 기록한다. 그래도 잔존하는 시나리오(프로세스 강제 종료 등)는 0으로 만들 수 없으므로 `/mvp-status`가 잔존을 감지해 수동 해제법을 안내한다.

---

## 가드레일 환경변수 표

| 변수 | 기본값 | 적용 엔진 | 의미 |
|------|--------|----------|------|
| `LOOP_TEST_CMD` | (미설정 — `.planning/gate-cmd` 사용) | Stop훅 · headless | 결정론 게이트 명령 override. 비대화형 + exit code 성패 표현 필수 |
| `LOOP_PROMISE` | `<promise>MVP_COMPLETE</promise>` | Stop훅 · headless | promise **전체 문자열**(태그 포함). 두 엔진 모두 값 그대로 grep -qF |
| `LOOP_MAX_ITER` | `24` | Stop훅 · headless | 반복 상한. 권장 = 스토리 수 × 3. 로드 순서: **env > `loop-state.json`의 `max_iter` 필드 > 기본값 24** (`/mvp-run --max-iter`는 필드에 기록). 도달 시 exit 0 + 미완 보고 |
| `LOOP_MAX_MINUTES` | `120` | Stop훅 · headless | 시간 상한(분). 로드 순서: **env > `loop-state.json`의 `max_minutes` 필드 > 기본값 120** (`/mvp-run --max-minutes`는 필드에 기록). Stop훅은 `loop-state.json`의 `started_at`(**epoch 초**, `date +%s`) 대비, headless는 스크립트 시작 시각 대비. 초과 시 현 반복 완료 후 종료 + 재개 방법 보고 |

**env 외 가드 (환경변수 아님):**

| 가드 | 집행 주체 | 동작 |
|------|----------|------|
| no-progress | 훅/스크립트 — 게이트 실패 출력의 `fail|error` 행 md5 시그니처가 연속 2회 동일 | exit 0 종료 + `BLOCKED.md` 기록 |
| 킬스위치 | `/mvp-stop` 커맨드 | `loop-active` 삭제 → 안전핀에 의해 훅 즉시 무력화, 핸드오프 기록, 마스터 `status: paused` |
| circuit breaker | 오케스트레이터 정책(코드 아님) — 동일 스토리 연속 3회 실패 | 해당 스토리 skip + BLOCKED 기록 후 다음 미완 스토리로 진행 |
| 테스트 삭제 차단 | PreToolUse 훅 `test-guard.sh` — `loop-active` 존재 시 `rm` 대상이 `test|spec` 패턴이면 | exit 2 차단, 정당한 삭제는 BLOCKED 경유 사용자 승인 안내 |

> 가드 발동 순서: 실패가 **동일하게** 반복되면 no-progress(2회)가 max-iter보다 먼저 멈춘다. 실패 양상이 매번 달라질 때만 max-iter가 backstop으로 작동한다. 둘 다 있어야 "stuck"과 "느린 진전" 양쪽을 막는다.
