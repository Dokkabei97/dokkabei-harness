> [English](README.md) · **한국어**

# harness

> 하네스(멀티 에이전트 팀)를 설계·생성·검증하고, 단발 반복 작업을 안전하게 돌리는 경량 루프까지 제공하는 메타 플러그인.

## 개요

`harness`는 다른 하네스를 만들기 위한 하네스다. 도메인을 분석해 에이전트 팀을 설계하고(`team-harness`),
결정된 설계를 실제 컴포넌트 파일로 스캐폴딩하며(`create-flow` + `flow-scaffolding`),
생성물을 10개 룰셋으로 기계 검증한다(`verify-flow` + `flow-validation`). 즉 "설계 → 생성 → 검증"의
단일 책임을 세 스킬 + 두 커맨드로 분리한 구조다. [revfactory/harness](https://github.com/revfactory/harness)(Apache-2.0)의
모놀리식 단일 스킬에서 출발해 사내 마켓플레이스에 맞게 재구조화한 fork이며, 상세 매핑은 `docs/ARCHITECTURE.md`에 있다.

여기에 더해 산출물 구조(prd/tasks) 없이 "게이트 그린까지"만 반복하는 **경량 범용 루프 엔진**(`/loop-run`·`/loop-stop`)을
내장한다. 이 루프는 `loop-active`에 `engine=generic`을 기록해, 그린필드 파이프라인(mvp)·브라운필드 작업분해(feature-loop)
루프와 소유권이 겹치지 않는 3중 경계를 이룬다. 완료 판정의 주체는 모델이 아니라 하네스 — Stop 훅이 결정론 게이트와
completion promise를 직접 검증한다.

## 구성요소

### 커맨드

- `/create-flow` — 에이전트·커맨드·스킬·훅·플러그인·팀을 프로젝트 컨벤션에 맞춰 대화형으로 스캐폴딩한다. `--type` 미지정 시 이름 패턴으로 자동 감지하며, `--team`으로 팀 컴포넌트를 일괄 생성하고, `--from-lessons`로 `tasks/lessons.md`의 `#가드-훅-후보` 태그 항목을 warn/block 가드 훅 초안으로 만든다(사용자 승인 게이트 필수).
- `/verify-flow` — 기존 컴포넌트를 컨벤션 대비 검증한다. 구조·콘텐츠 품질·교차참조·보안을 심각도별로 판정해 Health Score 리포트를 내고, `--fix auto`로 결정론적 결함을 자동 수정한다.
- `/loop-run` — 목표 프롬프트와 `--gate-cmd`(필수)로 `loop-active(engine=generic)`·`loop-state.json`을 초기화하고 Stop 훅 루프 엔진에 진입한다. "lint 0까지"·"테스트 그린까지"처럼 검증 명령 하나로 완료가 정의되는 단발 반복에 쓴다.
- `/loop-stop` — `engine=generic` 루프의 수동 킬스위치. `loop-active`를 삭제해 Stop 훅을 즉시 무력화하고 목표·iteration·마지막 게이트 결과를 `progress.md`에 핸드오프로 남긴다. 타 엔진(mvp/floop) 소유 루프는 건드리지 않고 해당 킬스위치를 안내한다.

### 스킬

- `team-harness` — 멀티 에이전트 팀 설계 메타 스킬. 도메인 분석, 6종 아키텍처 패턴 선택(Pipeline/Fan-out·Fan-in/Expert Pool/Producer-Reviewer/Supervisor/Hierarchical), 검증·루프 보강 패턴, 오케스트레이터 설계를 수행하고 생성은 `/create-flow`, 검증은 `/verify-flow`에 위임한다. "하네스 구성해줘", "팀 설계해줘" 등에서 발화.
- `flow-scaffolding` — 각 컴포넌트 유형의 표준 템플릿 시스템(커맨드·에이전트·스킬·훅·플러그인·팀 에이전트·오케스트레이터·팀 설정·루프 Stop 훅 9종). 프론트매터 필드 레퍼런스와 네이밍 컨벤션을 포함하며 `/create-flow`가 사용한다.
- `flow-validation` — 컴포넌트 검증 룰셋과 체크리스트. 10개 카테고리(CMD·AGT·SKL·HK·LOOP·TEAM·ORC·XRF·SEC·QUA)의 규칙, 심각도 척도, Health Score 계산법을 담으며 `/verify-flow`가 사용한다. 그중 LOOP 룰셋(10룰)은 Stop 훅 루프 엔진 전용 안전 규약이다.

### 훅

- `Stop` (`*`) → `hooks/generic-loop-stop-hook.sh` — 경량 범용 루프 엔진. `.planning/loop-active`에 `engine=generic`이 명시된 경우에만 활성화되며, 매 종료 시도마다 정지조건(① 결정론 게이트 그린 ② `progress.md`의 completion promise 정확 문자열)을 검증한다. 미충족이면 `exit 2`로 종료를 차단하고 실패 출력과 함께 작업을 재주입하며, 충족 또는 가드레일 도달 시 `loop-active`를 해제하고 종료를 허용한다. 레거시/타 엔진 `loop-active`에는 무개입(`exit 0`)한다.

## 사용법

- **하네스 설계**: "팀 설계해줘"·"하네스 구성해줘" 같은 요청이면 `team-harness`가 자동 발화해 도메인 분석 → 패턴 선택 → 오케스트레이터 설계를 진행하고, 실제 파일 생성은 `/create-flow --team`, 검증은 `/verify-flow --target team`으로 이어진다.
- **컴포넌트 생성·검증**: 단일 컴포넌트가 필요하면 `/create-flow <name> --type skill` 처럼 직접 호출하고, 생성 직후 `/verify-flow <path> --target skill`로 컨벤션 준수를 확인한다. 두 커맨드는 상호 보완 쌍이다.
- **경량 루프 시작/중지**:
  ```
  /loop-run "ESLint 에러를 0으로 만들어라" --gate-cmd "npx eslint src --max-warnings 0"
  # 게이트 시운전 → loop-active(engine=generic)·loop-state.json 초기화 → 루프 진입
  # 가드레일: max-iter 12 / 60분 / no-progress 2회 / 킬스위치 /loop-stop
  # 게이트 그린 + progress.md에 <promise>LOOP_COMPLETE</promise> 기록 시 정상 종료
  /loop-stop
  # engine=generic loop-active 삭제 → Stop 훅 즉시 무력화 + progress.md 핸드오프 기록
  ```
  `--promise`·`--max-iter`·`--max-minutes`로 정지 문자열과 상한을 조정할 수 있다. 스토리/작업 목록이 필요할 만큼 커지면 `/mvp-new`·`/floop-new`로 승격한다.

## 의존성

`plugin.json`에 하드 의존성은 없다. 다음 플러그인과 함께 쓰면 시너지가 있다.

- `mvp`(`/mvp-run`)·`feature-loop`(`/floop-run`) — 산출물 구조가 필요한 그린필드/브라운필드 루프. `engine` 스코프 공유 계약으로 `/loop-run`과 3중 경계를 이룬다.
- `observe`(`/observe-report`) — 여기서 만든 하네스가 실제로 어떤 프롬프트에서 발화·완주했는지 관측·개선한다.
- `workflow`(`/retro`) — 반복 실수를 `tasks/lessons.md`에 `#가드-훅-후보`로 태깅한다. `/create-flow --from-lessons`의 입력원이다.

## 참고

- **루프는 opt-in**: Stop 훅은 `engine=generic` `loop-active`가 있을 때만 개입한다. `/loop-run`을 쓰지 않은 일반 세션의 종료는 절대 방해하지 않는다.
- **완료 판정 주체는 하네스**: 정지조건은 모델의 자기평가가 아니라 훅이 결정론 게이트(exit code + 실패 표지 보정)와 promise 정확 문자열(`grep -qF`)로 판정한다.
- **가드레일 기본값**: max-iter 12회 · 시간 상한 60분 · no-progress(동일 실패 시그니처 연속 2회). 도달 시 루프를 자동 해제하고 `BLOCKED.md`에 사유를 기록한다.
- **`jq` 필요**: 루프 엔진은 상태 판정에 `jq`를 쓴다. 미설치 시 판정 불가로 종료를 허용(graceful degrade)하며 `loop-active`는 유지된다.
- **출처·라이선스**: `revfactory/harness`(Apache-2.0) fork. upstream 동기화는 버전 추종이 아니라 개념 선별 이식이 원칙이다(`docs/ARCHITECTURE.md` 참조).
