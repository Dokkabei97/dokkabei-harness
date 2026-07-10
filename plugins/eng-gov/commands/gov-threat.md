---
name: gov-threat
description: |
  위협 모델링 커맨드 — 코드베이스(엔드포인트·외부 연동·데이터 흐름·신뢰 경계)를 분석해 threat/threagile.yaml 초안을 작성하고, threagile 룰엔진이 있으면 실행해 risks.json을 생성/갱신한 뒤(없으면 degraded 경고와 함께 기존 risks.json 사용), threat-model-checker(Edit 미보유)로 STRIDE 커버리지 갭·누락 자산·근거 없는 accepted를 반증하고 gate-threat-model.sh로 미완화 critical 0건을 결정론 판정한다. 완화/수용 결정을 위협별로 기록한다. Use when 서비스의 위협 모델을 처음 작성하거나, 아키텍처 변경 후 위협 모델을 갱신할 때.
  Threat-modeling command: analyzes the codebase (endpoints, integrations, data flows, trust boundaries) to draft threat/threagile.yaml, runs the threagile rule engine if present to (re)generate risks.json (else uses the existing one with a degraded warning), falsifies STRIDE coverage gaps / missing assets / ungrounded accepted risks with threat-model-checker (no Edit), and deterministically checks zero unmitigated criticals via gate-threat-model.sh. Records mitigation/acceptance per risk. Use when: first authoring a threat model or updating it after an architecture change.
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /gov-threat — 위협 모델링 (Threagile/STRIDE)

코드베이스를 분석해 위협 모델(`threagile.yaml`)을 작성하고 미완화 critical을 게이트로 판정한다. 형식·STRIDE 규범은 `governance-templates`가 참조하며, 이 커맨드는 분석·작성·검증 디스패치를 수행한다.

## Triggers
- 신규/기존 서비스의 위협 모델을 처음 만들 때
- 새 외부 연동·인증 방식·데이터 흐름 추가 후 위협 모델 갱신
- "위협 모델 만들어줘", "STRIDE 분석", "공격면 정리" 요청

## Usage
```
/gov-threat [옵션]
Options:
  --scope <path>   분석 범위 제한(기본 레포 전체)
  --regen          threagile 재실행으로 risks.json 강제 갱신
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/gov/threat/` 존재 확인(없으면 `/gov-init` 안내). `threagile`(`command -v THREAGILE_BIN`) 가용성 확인 — 없으면 degraded 모드 고지.

### Phase 1: 코드베이스 분석 → 자산·흐름 추출
1. Grep/Glob으로 **자산**(엔드포인트·핸들러·DB·시크릿·큐), **외부 연동**(HTTP 클라이언트·SDK), **신뢰 경계**(인증·인가 지점, 외부/내부 구분)를 수집.
2. 데이터 흐름(누가 어떤 데이터를 어디로)을 개략화.

### Phase 2: threagile.yaml 초안
1. `.planning/gov/threat/threagile.yaml`에 자산·데이터 흐름·신뢰 경계를 threagile 스키마로 작성.
2. 각 자산·흐름에 STRIDE 6범주(Spoofing/Tampering/Repudiation/Info disclosure/DoS/Elevation) 검토를 배치.

### Phase 3: 룰엔진 실행(있으면)
1. threagile 존재 시: `threagile -model threagile.yaml -output .planning/gov/threat/`로 `risks.json` 생성/갱신.
2. 부재 시: **degraded** — 기존 `risks.json`으로 진행하되 "risks.json이 stale일 수 있음" 경고. risks.json도 없으면 수기로 초안 작성(severity/status 필드 포함) 후 진행.

### Phase 4: 완화/수용 결정 기록
- 각 위협의 `status`를 `mitigated`(완화 조치 명시) 또는 `accepted`(보상 통제·잔여 위험 서명·기한 명시)로 기록. 근거 없는 accepted 금지.

### Phase 5: threat-model-checker 반증 + 게이트
1. `threat-model-checker` 디스패치 — STRIDE 커버리지 갭·모델 누락 자산·근거 없는 accepted 반증(verdict는 `.planning/gov/threat/verdict.json`).
2. `bash ${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-threat-model.sh` — 미완화 critical(status ∉ {mitigated,accepted}) 0건 판정. 통과/실패 보고.

## Tool Coordination
- **Grep/Glob/Read**: 자산·연동·신뢰 경계 추출
- **Bash**: threagile 실행(있으면), `gate-threat-model.sh` 판정
- **Task**: `threat-model-checker` 디스패치
- **Write**: `threagile.yaml` 작성, (필요 시) risks.json 초안

## Boundaries

**Will:** 코드베이스 분석 기반 위협 모델 작성, threagile 실행(있으면)/degraded 폴백, checker 반증 + gate 판정.
**Will Not:**
- 보안 코드 리뷰(injection·authz 로직 결함) → 기존 security-review·backend-shared:security-check 위임
- 근거 없는 accepted 처리 허용
- 침투 테스트·실제 익스플로잇 수행(모델링 문서화만)
