> [English](README.md) · **한국어**

# enterprise

> GRC(리스크·통제·인증·컴플라이언스)와 전사 계획(전략 캐스케이드·경영계획·롤링 포캐스트·M&A 스크리닝)을 증적 결정론 게이트가 지키는 문서화 파이프라인으로 물화하는 중견·대기업 거버넌스 OS.

## 개요

`enterprise`는 기업 거버넌스를 **GRC**와 **전사 계획** 두 파일 계약 파이프라인으로 구조화한다. 상태를 세션 기억이 아니라 `.planning/grc/`·`.planning/enterprise/` 아래 파일이 보장한다는 하네스 설계 원칙을 따른다. 자유 대화형 가상 임원 회의(실측 안티패턴)는 배제하고, **maker 초안 → checker 반증 → 결정론 게이트**로만 움직인다.

핵심 특징은 **maker/checker 분리 + 증적 결정론 게이트**다. maker(`risk-assessor`·`strategy-analyst`·`fpna-planner`)가 산출물을 만들고, checker(`grc-challenger`·`plan-challenger`)는 의도적으로 Edit 도구 없이 이를 반증해 `verdict.json` 으로 물화하며, 이후 로컬 bash 게이트(exit 0/1)가 산술·enum 불변식을 재계산한다. 결정론으로 잡히는 것(숫자·enum·합·기한)은 게이트가 선처리하고, checker 는 의미 판단 잔여분만 담당한다.

경계는 뚜렷하다. 법적 판단(상법·중대재해·기업결합신고·공익신고·개인정보)은 `legal`, 재무제표·세무·실적 수치 검증은 `finance`, JD·온보딩·징계는 `hr`, 시장조사·유닛이코노믹스·유닛 레벨 재무는 `startup` 에 위임한다.

## 구성요소

### 커맨드 — GRC 파이프라인

- `/grc-intake` — 회사 프로파일 인터뷰 → 자산구간·상시근로자 법정 의무 매핑(감사위·K-SOX·ISMS-P·중대재해).
- `/risk-register` — 리스크 성향 선언 + COSO/ISO31000 5x5 레지스터 → grc-challenger → `gate-risk-register.sh --require-verdict`.
- `/control-matrix` — 리스크별 통제 매핑(예방/적발·1/2/3선·증적) + K-SOX RCM 골격 → `gate-control-matrix.sh`.
- `/policy-suite` — 행동강령→정책→지침→절차 계층 + 내부신고 규정 스캐폴딩 → `gate-policy-suite.sh`.
- `/cert-gap` — ISMS-P 101항목 갭 분석(증적 경로) + ISO27001/SOC2 크로스맵 → `gate-cert-readiness.sh`.
- `/comp-calendar` — 정기 의무 캘린더(기한·D-14·중대재해 증적 주기) → `gate-calendar.sh`.

### 커맨드 — 전략·계획 파이프라인

- `/strategy-cascade` — Playing to Win 5선택 + Three Horizons 태그 + 7S → plan-challenger (게이트 없음).
- `/annual-plan` — 한국 4Q 경영계획 → budget.json(CLAP·시나리오·Σ부서=전사) → plan-challenger → `gate-budget.sh`.
- `/rolling-forecast` — 드라이버 기반 롤링 포캐스트 + variance/DERP 커멘터리 → `gate-variance.sh`.
- `/biz-screen` — M&A 5카테고리 스코어카드(stop_rule·disqualifier) → plan-challenger → `gate-screen.sh --require-verdict`.
- `/enterprise-from-scaleup` — `.planning/scaleup/` 산출물을 GRC/계획 인테이크로 승계하는 브릿지(부재 시 풀 인터뷰 폴백).

### 에이전트

- `risk-assessor`(maker) — COSO/ISO31000 리스크 식별·평가·통제 매핑.
- `strategy-analyst`(maker) — Playing to Win/3H/9box/7S 캐스케이드·M&A 스코어카드.
- `fpna-planner`(maker) — 전사 레벨 경영계획·부서 배분·전사 손익·롤링 포캐스트(유닛 레벨은 startup:financial-modeler).
- `grc-challenger`(checker, Edit 미보유) — 리스크 과소평가·의무 누락·owner 실재성·정책 공백 반증 → `grc/verdict.json`(ACCEPT/REMEDIATE/ESCALATE).
- `plan-challenger`(checker, Edit 미보유) — 캐스케이드 논리 단절·hockey-stick·sandbagging·synergy substitution 반증 → `verdict.json`(APPROVE/REBASELINE/REJECT).

### 스킬

- `enterprise-orchestrator` — 2개 파이프라인 라우팅 마스터. 판정 기준·스키마·결선표는 `references/gate-policy.md` 정본.
- `grc-frameworks` — COSO ERM·ISO 31000·IIA Three Lines(2020)·5x5(`references/risk-matrix.json` 게이트 정본).
- `k-grc-context` — 한국 법정 맥락(자산구간 의무·K-SOX·ISMS-P 101·중대재해 증적) + `references/obligation-triggers.json`·`isms-p-items.json`.
- `strategy-frameworks` — Playing to Win·3H·9box·7S·M&A 5카테고리·기업결합 임계 참조표.
- `fpna-planning` — 4Q 캘린더·CLAP 5요소(`references/clap-keys.json`)·드라이버 트리·DERP(`references/derp-template.md`).

## 사용법

각 커맨드를 직접 호출하거나 자연어로 트리거한다. 산출물은 `.planning/grc/`·`.planning/enterprise/` 아래 파일로 저장되어 후속 커맨드·게이트의 입력이 된다.

- **GRC 구축**: `/grc-intake` → `/risk-register` → `/control-matrix` → `/policy-suite` → `/cert-gap` → `/comp-calendar`.
- **계획 사이클**: `/strategy-cascade` → `/annual-plan` → `/rolling-forecast`; 딜은 `/biz-screen`.
- **scaleup 승계**: `/enterprise-from-scaleup` 로 `.planning/scaleup/` 에서 인테이크 프리필.

게이트는 순수 로컬 bash(`plugins/enterprise/hooks/gates/*.sh`)이며 커맨드가 `bash "${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-*.sh"` 로 호출한다. 회귀 테스트는 `tests/hooks/enterprise-gates.bats`.

## 의존성

하드 의존성은 없다. 다음과 함께 쓰면 흐름이 이어진다.

- `scaleup` — `/enterprise-from-scaleup` 로 OKR·조직·보드 산출물을 거버넌스 인테이크로 승계.
- `legal` — 상법·중대재해·기업결합신고·공익신고·개인정보 판단.
- `finance` — 재무제표·세무·K-SOX 숫자·실적 수치 검증.
- `startup` — 시장조사·유닛이코노믹스·유닛 레벨 재무 모델링.

## 참고

- 규제/enum 데이터는 스킬 `references/*.json`(ISMS-P 101항목·의무 트리거·5x5 매트릭스·CLAP 키)이 단일 진실 원천이며, 게이트는 이 파일을 참조하고 하드코딩하지 않는다.
- ISMS-P 항목·KSSB ESG 로드맵은 '미확정, 갱신 필요' 스탬프를 단다 — 수치 사용 전 JSON 을 먼저 갱신한다.
- 이 플러그인은 거버넌스 1차 도구이며 변호사·회계사·감사인의 자문을 대체하지 않는다. 모든 대외 산출물은 사람 승인 게이트를 전제한다.
