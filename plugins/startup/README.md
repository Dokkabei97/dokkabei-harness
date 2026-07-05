# startup

> 린 스타트업 방법론으로 아이디어를 검증 가능한 비즈니스 가설로 만들고, 시장·제품·그로스·재무를 전문 에이전트로 분업해 산출물을 생성하는 하네스.

## 개요

`startup`은 아이디어 단계의 비즈니스를 시장조사 → 제품 기획 → 그로스 마케팅 → 재무 모델링 흐름으로 구조화하는 스타트업 워크벤치다. 각 도메인을 전용 에이전트(maker)에 위임하고, 모든 산출물은 `.planning/business/` 아래 파일로 물화(materialize)한다 — 톤·가설·지표 같은 상태를 세션 기억이 아니라 파일이 보장한다는 설계 원칙을 따른다.

핵심 특징은 **maker/checker 분리**다. 시장조사·린 캔버스·유닛 이코노믹스·그로스 플랜 같은 비즈니스 산출물은 만든 사람의 확증 편향 때문에 거의 항상 "기회 있음(GO)"으로 수렴한다. `assumption-killer`는 maker와 완전히 분리된 checker로서, 의도적으로 Edit 도구 없이 "이 사업을 하지 말아야 할 이유"만 찾는 반대 평형추(kill-gate) 역할을 한다.

경계도 뚜렷하다. 비즈니스 가설이 굳으면 `/mvp-from-startup`으로 `mvp` 하네스(코드 단계)에 연계하고, 콘텐츠의 광고 규제 판정은 `legal` 플러그인에, 피치덱 pptx 변환은 공식 `pptx` 스킬에 위임한다. 이 플러그인 자체는 비즈니스 가설·전략·산출물 작성까지를 범위로 삼는다.

## 구성요소

### 커맨드

- `/lean-canvas` — 린 캔버스 9블록으로 아이디어를 구조화된 비즈니스 가설로 변환.
- `/market-research` — TAM/SAM/SOM 산정·경쟁사 분석·고객 세그먼트를 포함한 시장조사 리포트 생성.
- `/validate-idea` — Build-Measure-Learn 기반으로 리스크 높은 가설을 식별하고 실험을 설계.
- `/unit-economics` — CAC·LTV·번레이트·런웨이를 계산하고 재무 건전성을 평가.
- `/growth-plan` — AARRR 퍼널 기반 채널 전략·실험 백로그·30/60/90일 실행 계획 수립.
- `/pitch-deck` — 투자자 관점 스토리라인과 슬라이드별 핵심 메시지 설계 (`--export pptx`로 공식 pptx 스킬 연계).
- `/content-draft` — 브랜드 보이스 기반 blog/sns/pr/email 콘텐츠 초안 생성. 첫 실행 시 5문항 인터뷰로 `brand-voice.md`를 물화하고 이후 모든 콘텐츠가 이를 참조.
- `/feedback-synthesis` — 확보한 인터뷰 노트·VoC·리뷰 덤프를 패턴·인사이트·기회 가설로 구조화. '스토리 후보' 섹션은 mvp 하네스가 읽는 형태로 산출 (피드백 파일이 있을 때만 발동).
- `/kill-check` — 비즈니스 산출물의 하중 가정을 적대적으로 반증하고 GO/PIVOT/KILL 판정.

### 에이전트

- `market-researcher` — TAM/SAM/SOM 산정, 경쟁사 분석, 고객 세그먼트·페르소나 도출, 산업 트렌드 분석 (웹 검색 기반).
- `product-strategist` — 린 캔버스 작성, MVP 정의, 검증 가능한 가설 수립, Build-Measure-Learn·Customer Development 적용.
- `financial-modeler` — 유닛 이코노믹스, 번레이트/런웨이, 수익 모델·매출 예측, 펀딩 전략·밸류에이션.
- `growth-marketer` — AARRR 퍼널 설계, Bullseye 채널 전략, CAC/LTV 최적화, 콘텐츠·SEO/ASO, 그로스 실험 설계 (콘텐츠 초안 작성도 담당).
- `assumption-killer` — 다른 에이전트가 남긴 산출물을 회의적으로 반증하는 checker. 하중 가정 식별 → 취약성×영향 순위로 적대적 공격 → GO/PIVOT/KILL 판정. Edit 미보유로 산출물을 고쳐 통과시키는 경로를 원천 차단.

### 스킬

- `lean-startup-guide` — Build-Measure-Learn, Customer Development 4단계, MVP 유형 선택, 피벗 판단 프레임워크.
- `market-sizing-guide` — Top-Down/Bottom-Up/Value Theory 시장 규모 산정법과 투자자 관점 검증 기준.
- `unit-economics-guide` — CAC/LTV/Payback 계산법, 수익 모델별 지표, 번레이트/런웨이 관리와 벤치마크.
- `growth-hacking-guide` — AARRR 퍼널, Bullseye 채널 전략, ICE 실험 우선순위, 바이럴 루프, North Star Metric.
- `pitch-deck-guide` — Sequoia/YC 슬라이드 구조, 라운드별 강조점, 스토리텔링, 흔한 실수와 Q&A 준비.
- `content-guide` — blog/sns/pr/email 유형별 구조 템플릿과 `brand-voice.md` 스키마·5문항 인터뷰 규격 (유형별 템플릿은 `references/` 참조).

## 사용법

각 커맨드를 직접 호출하거나 자연어 요청으로 트리거한다. 대부분의 산출물은 `.planning/business/` 아래에 파일로 저장되어 이후 커맨드의 입력이 된다.

- **초기 가설**: `/lean-canvas [아이디어]` → `/market-research [산업]` → `/validate-idea`로 실험 설계.
- **재무·투자**: `/unit-economics --model saas` → `/pitch-deck --stage seed --export pptx`.
- **그로스**: 출시 후 `/growth-plan --stage post-pmf`로 채널·실험·실행 계획 수립.
- **콘텐츠**: `/content-draft --type blog [주제]` — 첫 실행 시 브랜드 보이스 인터뷰, `--revoice`로 갱신.
- **고객 피드백**: `/feedback-synthesis --source review ./reviews.csv` (피드백 파일 필수). `--kill-check`로 도출 가설을 즉시 반증.
- **의사결정 게이트**: 투자/착수 직전, 혹은 `/mvp-from-startup` 진입 전 `/kill-check`로 하중 가정을 반증받는다.

## 의존성

하드 의존성은 없다. 다만 다음 플러그인/스킬과 함께 쓰면 흐름이 이어진다.

- `mvp` — `/mvp-from-startup`으로 비즈니스 가설을 코드 단계로 연계. `/feedback-synthesis`의 '스토리 후보'는 mvp의 `product-strategist`가 PRD 작성(Stage 1) 소재로 읽는다.
- `legal` — 콘텐츠의 표시광고법·광고성 정보 규제 판정은 `/compliance-check`로 위임.
- 공식 `pptx` 스킬(document-skills) — `/pitch-deck --export pptx` 실행 시 슬라이드 구조+스피커 노트를 pptx로 변환 (설치 시).

## 참고

- 에이전트는 `WebSearch`/`WebFetch`로 실시간 데이터를 수집한다. 근거 없는 수치는 `[추정]`/`[근거 필요]`로 표기하며 창작하지 않는다.
- `/content-draft`는 과장 광고·표시광고법 리스크 표현을 감지하면 안내를 남기지만, 규제 준수 판정 자체는 `legal` 플러그인의 몫이다.
- 이 플러그인은 사업·재무·법무에 대한 1차 진단 도구이며, 회계사·변호사·투자 전문가의 자문을 대체하지 않는다.
