> [English](README.md) · **한국어**

# eng-gov

> ADR·변경 증적·위협 모델·공급망 통제를 로컬 `exit 0/1` 게이트로 물화하는 개발 거버넌스 하네스 — SOC 2 / ISO 27001 감사 증적을 git 네이티브로 생성한다.

## 개요

`eng-gov`는 무거운 변경심의위(CAB) 대신 엔지니어링 거버넌스를 **결정론 로컬 게이트**로 바꾼다. 모든 통제는 `exit 0 = 검사했고 통과했다` 계약을 가진 bash 스크립트라, 서버 없이 기존 루프 엔진(mvp·feature-loop·generic)과 CI에 그대로 꽂힌다. 설계 철학은 다른 하네스와 동일하다: **단일 패스 커맨드 파이프라인 + maker/checker(checker는 Edit 미보유) + 결정론 게이트 + ".planning/ 파일이 상태를 보장한다"**.

차별화 지점은 git 히스토리를 감사 증적으로 바꾸는 것이다: `/gov-audit`가 git 네이티브 증적(변경 번들·게이트 결과)을 SOC 2 CC8.1 · ISO 27001:2022 Annex A 통제에 매핑한 **감사 증적 문서**로 변환해 SOC 2 Type II·ISO 27001 심사에 대응한다.

**도구 부재 정책 — "등록 시점 skip, 런타임 fail-closed"**: 등록된 게이트의 도구 부재는 fail-closed(`exit 1` + 설치 안내)다. skip green은 심사 허위 증적이 되기 때문이다. "이 게이트를 안 돌린다"는 판단은 `/gov-init` 시점(`gates.json` `enabled:false` + `reason`)으로 명시적으로 옮긴다. 유일한 degraded 예외는 `gate-threat-model`(결정론 반쪽은 항상 판정, threagile 재생성만 경고와 함께 skip).

## 컴포넌트

### 커맨드 (8)

| 커맨드 | 역할 |
|--------|------|
| `/gov-init` | 스택·도구 감지 → `.planning/gov/` + `docs/decisions/` 스캐폴딩 → `gates.json` 등록(미설치 도구 `enabled:false`) → 시운전 |
| `/gov-adr` | MADR ADR 작성/supersede + fitness function 변환 제안 → adr-checker → gate-adr |
| `/gov-threat` | 코드베이스 분석 → `threagile.yaml` 초안 → threagile(있으면) → threat-model-checker → gate-threat-model |
| `/gov-slo` | SLO 문서 + 에러버짓 정책 + `thresholds.yaml` 분리 → gate-error-budget 시운전 |
| `/gov-postmortem` | 블레임리스 포스트모템(타임라인·5-why·owner/due 액션) → postmortem-checker (게이트 없음) |
| `/gov-change` | diff 통계 bash 선계산 → change-risk-classifier → `evidence.json` → gate-change-evidence |
| `/gov-audit` | run-registered.sh로 등록 게이트 일괄 실행 → `audit-log.jsonl` append → 감사 증적 문서 |
| `/gov-dora` | DORA 4 Keys(git로 DF/LT, 포스트모템 원장으로 CFR/MTTR) — 읽기 전용 |

### 에이전트 (4, 전부 opus)

- `change-risk-classifier` (**maker**) — diff를 standard/normal/high로 등급화하고 `evidence.json` 조립. 개인정보·인증·결제·인프라 또는 500+ 라인은 high 강제. 법 진단은 legal 위임.
- `adr-checker` (**checker, Edit 미보유**) — ADR 선언 vs 코드 실태 반증. import 위반 결정론 검사는 gate-fitness 몫, analyze:arch-review와 경계. PASS/FIX/BLOCK.
- `threat-model-checker` (**checker, Edit 미보유**) — STRIDE 커버리지 갭·누락 자산·근거 없는 accepted 반증. PASS/FIX/BLOCK.
- `postmortem-checker` (**checker, Edit 미보유**) — 블레임 언어·얕은 루트코즈·소유자 없는 액션 반증. PASS/FIX/BLOCK.

> checker 3종은 의도적으로 `Edit`를 갖지 않는다. `Write`는 오직 `verdict.json`(`.planning/gov/<영역>/verdict.json`)에만 쓰며, 검증 대상 산출물은 절대 수정하지 않는다.

### 스킬 (3)

- `governance-templates` — 형식 단일 진실 원천. MADR·SLO·포스트모템·변경정책 템플릿 + SOC 2 / ISO 27001 통제 매핑표(references/). 각 템플릿은 대응 게이트 계약에 정렬돼 있다.
- `fitness-function-guide` — 스택별 도구 선택(dependency-cruiser/import-linter/ArchUnit) + ADR→강제 가능 검사 변환 패턴집.
- `supply-chain-guide` — gitleaks baseline 운영·syft/grype·라이선스 denylist 정책(references/license-denylist.json 기본값).

### 게이트 스크립트 (훅 미등록 — 커맨드/루프가 Bash 호출)

`gate-adr` · `gate-fitness` · `gate-secrets` · `gate-supply-chain` · `gate-policy` · `gate-change-evidence` · `gate-threat-model` · `gate-error-budget` · `run-registered`(`gates.json` 집계 어댑터). 전부 인자 없이 동작하고 `exit 0 = 통과 / 1 = 실패`(`gate-error-budget`만 `2 = 미측정`) 계약을 지킨다. 외부 도구는 `<TOOL>_BIN` env로 오버라이드.

## 산출물 계약 (`.planning/gov/` + `docs/decisions/`)

```
docs/decisions/NNNN-<slug>.md          # ADR (업계 표준 경로)
.planning/gov/
├── gov-master.json                    # 스택·초기화·adr_dir
├── gates.json                         # 등록 게이트(plugin_root 절대경로 + enabled/reason)
├── change/<sha>/evidence.json         # 변경 증적 (gate-change-evidence)
├── threat/threagile.yaml, risks.json  # 위협 모델
├── slo/thresholds.yaml, budget.json   # SLO 임계값(플랫) + 버짓(observe/otel 입력)
├── postmortems/YYYY-MM-DD-<slug>.md    # 블레임리스 포스트모템
├── <영역>/verdict.json                # checker 판정
└── audit-log.jsonl                    # append-only (수기 편집 금지 — /gov-audit만 append)
```

## 루프 엔진 결합

1. **(a)** 모든 게이트와 `run-registered.sh`는 인자 없는 `exit 0/1` 계약을 지킨다 → floop/mvp 루프의 `.planning/gate-cmd` 한 줄에 직접 등록 가능.
2. **(b)** `/loop-run "<목표>" --gate-cmd 'bash <plugin_root>/hooks/gates/run-registered.sh'` 로 generic 루프를 등록 게이트 전체에 직결.
3. **(c)** `/gov-change`의 `evidence.json`(`loop_artifacts`를 `tasks.json`/`baseline.json`에서 채움)이 "루프 산출물 = 감사 증적"을 연결.
4. **(d)** `gates.json`의 절대 `plugin_root`는 **플러그인 캐시 갱신 시 stale** → `/gov-init` 재실행으로 재등록(해소 규약).

## 의존성

- **requires**: 없음(`hooks.json` 없음 — 게이트는 커맨드/루프가 수동 호출하므로 공통 훅 기반이 불필요).
- **연계**: `observe`·`infra/otel`(`budget.json` SLI 입력), `mvp`·`feature-loop`·`harness:loop-run`(게이트를 돌리는 루프 엔진), `legal`/`finance`/`hr`(법·재무·인사 판단 위임 경계).

## 노트

- **게이트 그린 = "검사했고 통과했다"** — 등록 게이트의 도구 부재를 skip green으로 통과시키지 않는다. skip은 `gates.json`(`enabled:false` + `reason`)으로 투명하게 명시한다.
- **thresholds.yaml는 플랫**(`key: value`) — 게이트가 grep/sed로 파싱, yq 무의존.
- **audit-log.jsonl / evidence 번들은 증적** — 수기 편집·소급 기록 금지. `/gov-audit`·`/gov-change`만 기록한다.
- **CI 서버 의존 없음**: cosign/in-toto SLSA provenance는 문서화 수준, SaaS GRC/스캐너 API 미연동(CSV/JSON export 입력만).
