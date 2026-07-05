# mvp

> 아이디어 한 줄을 기획(PRD) → 디자인 → 스택 선택·스캐폴딩 → PRD-driven 개발 루프로 완주시키는 그린필드 MVP 루프 엔지니어링 하네스.

## 개요

`mvp`는 빈 레포에서 신규 사업/서비스를 만들 때, "무엇을 만들지"조차 정해지지 않은 아이디어 한 줄에서 출발해
동작하는 MVP까지를 **게이트 기반 상태기계**로 끌고 가는 하네스다. Stage 0(인테이크) → 1(기획 PRD) → 2(디자인 스펙)
→ 3(스택 선택·스캐폴딩) → 4(PRD-driven 개발 루프)로 이어지며, 각 Stage 전이는 결정론 게이트 스크립트와
회의적 checker 에이전트의 반증을 모두 통과해야만 열린다.

설계의 핵심은 **완료 판정의 주체가 모델이 아니라 하네스**라는 점이다. Stage 4 개발 루프는 `Stop` 훅 루프 엔진이
매 반복마다 정지조건(결정론 게이트 그린 + 전 스토리 passes + verified 마커 + E2E 게이트(선택) + completion promise)을
검증하고, 미충족 시 `exit 2` 재주입으로 루프를 지속시킨다. maker(구현)와 checker(반증)를 완전히 분리한
Producer-Reviewer 교차검증으로 "테스트 사기"를 막고, max-iter·no-progress·시간 상한·킬스위치 등 가드레일로
폭주를 봉쇄한다. `.planning/` 디렉토리가 메모리 겸 재개 지점이 되어 세션이 끊겨도 이어서 진행할 수 있다.

이 하네스는 **그린필드 전용**이다. 기존(브라운필드) 코드베이스의 기능 추가·수정은 `feature-loop` 또는 스택별
플러그인(kotlin-spring·python-fastapi·go-mux·nextjs·search)에 위임한다. 반대로 사업 가설 수립 단계는 `startup`
플러그인이 담당하며, `/mvp-from-startup`으로 그 산출물을 이어받는다.

## 구성요소

### 커맨드 (7)

- `/mvp-new "<아이디어 한 줄>"` — 하네스 진입점. Stage 0~3(인테이크→기획→디자인→스캐폴딩)을 게이트 기반으로 실행하고 개발 루프 가동 여부를 확인.
- `/mvp-from-startup` — `startup` 플러그인 산출물(`.planning/business/`)을 Stage 0 인테이크로 승계하는 브릿지. 검증된 사업 가설에서 곧장 기획 PRD로 진입.
- `/mvp-run` — Stage 4 개발 루프 시작/재개. 재개 프로토콜 수행 후 `loop-active`·`loop-state.json`을 초기화하고 Stop훅 루프 엔진에 진입.
- `/mvp-status` — 진행 현황 읽기 전용 조회(스토리 n/m·반복 수·경과 시간·verified 마커·BLOCKED·loop-active 잔존). 어떤 상태도 변경하지 않음.
- `/mvp-stop` — 루프 안전 중단 킬스위치. `loop-active` 삭제로 Stop훅 엔진을 즉시 무력화하고 핸드오프 기록 후 status를 paused로 전환.
- `/mvp-gate` — 현 Stage 게이트 수동 (재)실행. 마스터 파일에서 Stage를 판별해 해당 게이트 스크립트와 checker를 돌리고 통과/실패/모호를 보고.
- `/mvp-eval` — 제품 검증(평가) 실행. PRD 성공지표가 모델 품질(F1·정확도 등)일 때 골든셋 + 실제 모델 호출로 실측하고 `gate-eval.sh`로 임계값 판정.

### 에이전트 (6, 전원 opus)

- `product-strategist` — 기획 전략가. 아이디어 인테이크(질문 최대 3개+추천 기본값), PRD 작성, prd.json 유저 스토리 초안, Stage 2 커버리지 매트릭스 검증.
- `ux-designer` — 디자인 스펙 설계자. PRD를 `design-spec.md` 단일 산출로 변환(IA·유저플로우·화면 명세·와이어프레임·토큰·4상태). 코드 생성 금지.
- `tech-architect` — 스택 선정·스캐폴딩 전문가. 표준 4스택 후보 2~3개 비교 추천(비강제), 레포 골격+smoke 테스트 생성, `.planning/` 초기화·gate-cmd 기록·초기 커밋.
- `mvp-builder` — 개발 루프 maker 규율. 미완 스토리 1개를 test-first로 구현해 게이트 그린을 만들고 검증 통과 후 1커밋으로 마감(기본은 메인 세션이 체화).
- `mvp-verifier` — 회의적 checker. maker와 분리된 이중 반증(Stage 1 PRD 반증 / Stage 4 스토리 AC 반증). 반증 실패 시에만 `verified/{story-id}` 마커 생성.
- `eval-engineer` — 제품 검증 엔지니어. "검증된 코드 ≠ 검증된 제품" 간극을 메운다. 골든셋 구축·실제 모델 호출·지표 산출(macro F1 등)을 결정론 회귀와 분리해 수행.

### 스킬 (5)

- `mvp-orchestrator` — 하네스 오케스트레이터 정본. Stage 상태기계 전체 로직을 수행하며 "MVP 만들어줘"·그린필드 신규 구축·`/mvp-new`·`/mvp-run`에 자동 트리거. (references: gate-policy·headless-recipe·stack-presets)
- `mvp-loop-protocol` — Stage 4 루프 운영 프로토콜. 매 반복 표준 사이클, `/mvp-run` 재개 4단계, 정지조건 3결합, 환경변수 튜닝, `loop-active` 수명주기, 가드레일 5종, BLOCKED 에스컬레이션.
- `prd-authoring` — PRD 작성 표준. 필수 섹션, Given-When-Then AC(반증 가능한 검증형), prd.json 스키마·jq 검증식, 스코프 컷 2주 룰, 1 스토리=1 반복 크기.
- `mvp-design-spec` — 디자인 스펙 작성 표준. IA·유저플로우·화면 명세·토큰 필수 구조, `[story: S-xx]` 매핑 태그 형식(gate-design.sh 호환), 4상태 의무, 커버리지 매트릭스.
- `mvp-eval-harness` — 제품 검증(평가) 하니스 표준. 골든셋 구축 기준, `@pytest.mark.eval` 분리(기본 skip), report.json 스키마, `gate-eval.sh` 소프트 게이트 계약, 임계값=PRD 정본 원칙.

### 훅 (6)

- `SessionStart` → `mvp-session-init.sh` — `.planning/mvp-*.md` status가 in_progress일 때만 재개 안내 컨텍스트 주입, 그 외 무동작.
- `Stop` → `mvp-loop-stop-hook.sh` — 루프 엔진. `loop-active` 존재 시에만 정지조건 3결합을 검증하고 미충족 시 `exit 2` 재주입.
- `PreCompact` → `precompact-anchor.sh mvp` — compaction 직전 재개 앵커(마스터 경로·다음 대상·게이트·반복·규율)를 5줄 이내 출력, 일반 세션 무개입.
- `SubagentStop` → `subagent-stop-verify.sh mvp` — verify-round pending인데 verified/refuted 마커 없이 종료하면 `exit 2` 재주입(최대 2라운드, 차단 시 자가치유).
- `PreToolUse(Bash)` → `test-guard.sh` — 루프 활성 중 테스트 파일 삭제(`rm test|spec`) 차단. 테스트 삭제 금지 규칙의 결정론 집행.
- `PostToolUse(Edit|Write)` → `prd-guard.sh` — maker/checker 분리 강제. verified 마커 없는 `passes:true`를 `exit 2` 차단하고 false로 되돌림.

### 게이트 스크립트 (훅 미등록 — 오케스트레이터/커맨드가 Bash 호출)

- `gate-prd.sh` (Stage 1) — prd.md 필수 헤딩 + prd.json jq 스키마 + 스토리 수 3~10.
- `gate-design.sh` (Stage 2) — 전 story id의 `[story: S-xx]` 태그가 design-spec.md에 등장하는지 grep 확인.
- `gate-scaffold.sh` (Stage 3) — 작업 트리 클린 + 초기 커밋 존재 + `.planning/` 필수 파일·verified 디렉토리.
- `gate-eval.sh` (평가) — report.json 존재·필수 필드·`value ≥ threshold`. 데이터/모델 의존 소프트 게이트(미측정=경고 exit 2).

### 러너

- `bin/mvp-headless.sh` — Stage 4 무인/야간 루프 러너(컨텍스트 리셋형 Ralph 패턴). 외부 `while`가 매 반복 `claude -p`를 새로 띄운다. Stop훅 엔진과 동일 `.planning`·동일 게이트·동일 판정 규약을 공유하는 보조 엔진.

## 사용법

1. **시작**: `/mvp-new "구직자용 이력서 첨삭 서비스"` → 인테이크 질문(최대 3개) → PRD → 디자인 스펙 → 스택 선택·스캐폴딩. 진행 중 사용자 게이트 2개(★G1 스코프 승인, ★G2 스택 선택)에서 확인을 받는다.
2. **루프 가동**: 스캐폴딩까지 통과하면 `/mvp-run`으로 Stage 4 개발 루프에 진입. 이후 완료 판정은 Stop훅이 자동으로 수행한다.
3. **상태 확인**: 언제든 `/mvp-status`(읽기 전용)로 스토리 진행·반복 수·경과 시간·잔존 플래그를 조회.
4. **중단**: `/mvp-stop`으로 즉시 안전 중단(킬스위치). 이후 `/mvp-run`으로 재개.
5. **재검증·평가**: 산출물을 손본 뒤 `/mvp-gate`로 현 Stage 게이트를 재실행. 모델 품질 지표가 있으면 `/mvp-eval`로 실측.

옵션: `--auto`(게이트 2개를 추천안으로 자동 채택, 해커톤용), `--stack <preset>`(kotlin-spring·python-fastapi·react-next·go-mux 사전 지정으로 ★G2 생략), `--stories-max <n>`(스토리 수 상한, 기본 10), `--max-iter`/`--max-minutes`(이번 가동 가드레일 조정), `--headless`(무인 러너 실행 안내), `--cross-check`(교차 모델 반증 opt-in).

자동 발화: `mvp-orchestrator` 스킬은 "MVP 만들어줘"·"신규 서비스 프로토타입"·"아이디어를 동작하는 제품으로" 같은 요청과 그린필드 신규 구축에 트리거된다. 기존 코드베이스의 단일 기능 작업에는 발동하지 않는다.

## 의존성

- **requires**: `base` — 공통 훅/설정 기반.
- **연계**: `startup`(사업 가설 → `/mvp-from-startup`으로 승계), `feature-loop`(브라운필드 대응 루프, 루프 엔진 공유), 스택별 플러그인(kotlin-spring·python-fastapi·go-mux·nextjs·search — 루프 안에서 호출), `etc`(`--cross-check`의 교차 모델 반증에 `etc:with` 활용, 미설치 시 동일 모델 2라운드로 폴백).

## 참고

- **모델 품질 평가는 회귀를 대체하지 않는다**: `/mvp-eval`·`eval-engineer`는 결정론 회귀 스위트(`@pytest.mark.eval` 분리, 기본 skip)와 별개의 소프트 게이트다. `MVP_EVAL_F1_MIN`으로 임계값 override 가능하나 정본은 PRD 성공지표.
- **환경변수 튜닝**: `LOOP_TEST_CMD`·`LOOP_PROMISE`·`LOOP_MAX_ITER`(기본 24)·`LOOP_MAX_MINUTES`(기본 120)·`MVP_STORIES_MAX`(기본 10)·`LOOP_CLAUDE_BIN`·`LOOP_WATCHDOG_INTERVAL`.
- **가드레일**: max-iter(기본 24)·no-progress(2회)·시간 상한(기본 120분)·킬스위치(`/mvp-stop`). 세션 비정상 종료 시 `loop-active` 잔존을 `/mvp-status`로 점검하고 `/mvp-stop`으로 정돈.
- **레포당 MVP 1개 전제**: `.planning/mvp-*.md`가 이미 있으면 `/mvp-new`는 새로 만들지 않고 재개를 안내한다.
- **표준 4스택은 비강제**: `tech-architect`는 후보를 비교 추천하되 강제하지 않으며, 4스택 밖 제안에는 근거를 요구한다.
