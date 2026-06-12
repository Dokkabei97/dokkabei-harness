---
name: mvp-new
description: "MVP 하네스 진입점 — 아이디어 한 줄을 받아 Stage 0~3(인테이크→기획 PRD→디자인 스펙→스택 선택·스캐폴딩)을 게이트 기반으로 실행하고 개발 루프 가동 여부를 확인. 그린필드 전용"
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /mvp-new - MVP 하네스 진입점 (Stage 0~3)

`mvp-orchestrator` 스킬을 진입시켜 아이디어 한 줄을 기획(PRD) → 디자인 스펙 → 스택 선택·스캐폴딩까지
게이트 기반 상태기계로 끌고 간다. 이 커맨드는 진입점이며, Stage 로직 전체는 `mvp-orchestrator`가 수행한다
(커맨드에 로직을 중복 기술하지 않음). 그린필드 전용 — 기존 코드베이스 작업은 각 팀 오케스트레이터에 위임한다.

## Triggers
- "이런 서비스를 만들고 싶다"는 아이디어 한 줄에서 MVP를 시작할 때
- 기획서(PRD) 없이 신규 사업/서비스의 스코프·디자인·스택을 처음부터 정의해야 할 때
- 빈 레포에서 PRD-driven 개발 루프(Stage 4)에 진입하기 위한 사전 산출물(.planning/)이 필요할 때
- 해커톤/실험에서 게이트 승인을 추천안으로 자동 처리하며 빠르게 골격을 세우고 싶을 때

## Usage
```
/mvp-new "<아이디어 한 줄>" [옵션]

Options:
  --auto              사용자 게이트 2개(★G1 스코프 승인·★G2 스택 선택)를 추천안으로 자동 채택·기록 (해커톤/실험용)
  --stack <preset>    스택 사전 지정으로 ★G2 생략 — kotlin-spring | python-fastapi | react-next | go-mux
  --stories-max <n>   prd.json 스토리 수 상한 (기본 10, 게이트 허용 범위 3~10)
```

## Behavioral Flow

### Phase 1: 사전 점검
진입 가능 여부를 판단한다.
1. **그린필드 확인**: 기존 코드베이스(소스 트리·빌드 파일 존재) 위에서 호출되면 중단하고 스택별 플러그인(kotlin-spring·python-fastapi·go-mux·nextjs·search 등)을 안내
2. **기존 MVP 감지**: `.planning/mvp-*.md`가 이미 존재하면(레포당 MVP 1개 전제) 새로 만들지 않고 `/mvp-run` 재개 또는 `/mvp-status` 확인을 안내
3. **옵션 해석**: `--auto`/`--stack`/`--stories-max`를 검증하여 오케스트레이터에 전달 (비표준 preset 값은 거부하고 4스택 목록 제시)

### Phase 2: Stage 0 — 인테이크 (mvp-orchestrator 위임)
1. **질문**: `product-strategist` 디스패치로 아이디어를 보강할 질문 패키지(최대 3개+추천 기본값) 리포트를 받아, 메인 세션이 제시·답변 수집 (`--auto`면 기본값 자동 채택 후 채택 내역 기록)
2. **목표 고정**: 답변을 종합해 마스터 파일의 `## Goal`(불변)로 확정

### Phase 3: Stage 1 — 기획 (PS 작성 → MV 반증 → G1)
1. **PS 디스패치**: `product-strategist`가 prd.md + prd.json 스토리 초안(`{id,title,acceptance[],passes:false}`) 작성 (유사 서비스 WebSearch 1-pass 조사 허용)
2. **MV 반증**: `mvp-verifier`가 "이 스코프가 틀렸다면 왜?" 관점으로 반증 — 범위 비대·검증 불가 AC·측정 불가 지표·페르소나-스토리 불일치 (Producer-Reviewer 최대 2라운드, 반증 실패 시 통과)
3. **결정론 게이트**: `gate-prd.sh --initial` 실행 — prd.md 필수 헤딩 grep + prd.json jq 스키마 + passes 전건 false + 스토리 수 3~10(`--stories-max <n>` 지정 시 `MVP_STORIES_MAX=<n>` env로 상한 전달)
4. **★G1 스코프 승인**: 사용자 게이트(항상). `--auto`면 추천안 자동 승인 후 마스터 `## Gates`에 스탬프 기록

### Phase 4: Stage 2 — 디자인 (UX 작성 → PS 검증)
1. **UX 디스패치**: `ux-designer`가 design-spec.md 단일 산출 — IA·Mermaid 유저플로우·화면 명세(각 화면 `[story: S-xx]` 매핑 태그 의무)·텍스트/ASCII 와이어프레임·디자인 토큰·빈/로딩/에러/성공 4상태
2. **PS 교차검증**: `product-strategist`가 디자인-PRD 커버리지 매트릭스 검증 (비평가 재사용, 자기발견 제외)
3. **결정론 게이트**: `gate-design.sh` — prd.json 전 story id가 design-spec.md에 `[story: S-xx]`로 등장하는지 grep. 통과 시 자율 진행 + 1줄 보고 (사용자 게이트 없음)

### Phase 5: Stage 3 — 스캐폴딩 (TA → G2 → 골격 생성)
1. **스택 추천**: `tech-architect`가 표준 4스택(Kotlin/Spring·Python/FastAPI·React/Next.js·Go/stdlib mux) 중 후보 2~3개 트레이드오프 비교 추천 (강제 금지, 비표준 제안 시 근거 필수)
2. **★G2 스택 선택**: 사용자 게이트(항상). `--stack <preset>` 지정 시 생략, `--auto`면 추천 1순위 채택 — 선택·근거 상세는 stack-decision.md에 기록하고, 마스터 `## Gates`의 G2 스탬프는 TA가 Stage 3 `.planning` 갱신 시 기록(메인 세션은 G1 스탬프만 기록)
3. **스캐폴딩**: 레포 골격 + smoke 테스트 + `.planning/gate-cmd` 기록(예: `pnpm test`·`./gradlew test`·`pytest -q`·`go test ./...`) + prd.json 확정 + .planning/ 초기화 + 빈 프로젝트 게이트 그린 확인 + 초기 커밋
4. **결정론 게이트**: `gate-scaffold.sh` — gate-cmd 그린 + git 초기 커밋 + .planning 필수 파일 존재

### Phase 6: 루프 가동 확인
1. **요약 보고**: Stage 0~3 산출물(.planning/ 파일 목록·게이트 스탬프·초기 커밋 해시) 1화면 요약
2. **가동 질의**: Stage 4 개발 루프 진입 여부 확인 — 즉시 가동이면 `/mvp-run` 절차로 연결, 아니면 재개 방법 안내 후 status 유지

게이트 정책(전 Stage 공통): 통과 = 1줄 보고 후 자동 진행 / 실패 = 중단 + 원인·시도·옵션 보고 / 모호 = 중단 + 권장안 보고.

## Tool Coordination
- **Skill**: `mvp-orchestrator` 로드 — Stage 0~3 상태기계·게이트 정책·P-R 규약의 단일 진실 공급원
- **Task**: product-strategist / ux-designer / tech-architect / mvp-verifier 에이전트 디스패치
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-prd.sh`·`gate-design.sh`·`gate-scaffold.sh` 실행, git 초기 커밋 확인
- **Read/Glob**: 기존 MVP(.planning/mvp-*.md)·코드베이스 유무 감지, 산출물 검수
- **Write/Edit**: 마스터 파일 `## Gates` G1 승인 스탬프·`## Stage` 전이 기록 (G2 스탬프는 TA가 Stage 3 갱신 시 기록)

## Examples

### 기본 진입 (게이트 2개 모두 사용자 승인)
```
/mvp-new "동네 반려견 산책 메이트 매칭 서비스"
# Stage 0: 질문 최대 3개(+추천 기본값) → Goal 확정
# Stage 1: prd.md + prd.json(S-01~S-06) → MV 반증 1라운드 → gate-prd.sh ✅ → ★G1 승인 대기
# Stage 2: design-spec.md([story: S-xx] 전 매핑) → PS 검증 → gate-design.sh ✅ (1줄 보고)
# Stage 3: 스택 후보 2개 비교 → ★G2 선택 대기 → 스캐폴딩 → gate-scaffold.sh ✅
# 종료: 루프 가동 여부 질의 (가동 시 /mvp-run 연결)
```

### 해커톤 모드 (게이트 자동 + 스토리 상한 축소)
```
/mvp-new "사내 점심 메뉴 투표 봇" --auto --stories-max 5
# G1: 추천 스코프 자동 승인(채택 내역 마스터에 기록), G2: 추천 1순위 스택 자동 채택
# 스토리 수 5개 이내로 컷 — 시장성 판단을 LLM 추천에 위임하므로 해커톤/실험 한정
```

### 스택 사전 지정 (G2 생략)
```
/mvp-new "재고 알림 백오피스" --stack python-fastapi
# ★G2 생략, stack-decision.md에 사전 지정 사실 기록
# ★G1 스코프 승인은 그대로 사용자 게이트로 수행
```

## Boundaries

**Will:**
- Stage 0~3을 `mvp-orchestrator` 상태기계에 위임해 게이트 기반으로 실행
- 사용자 게이트 정확히 2개(★G1 스코프·★G2 스택)만 운영하고 승인 스탬프를 마스터에 기록
- `.planning/` 메모리(마스터·prd.md·prd.json·design-spec.md·stack-decision.md·gate-cmd) 초기화와 초기 커밋까지 완료
- 결정론 게이트(gates/*.sh) 통과를 Stage 전이의 전제로 강제

**Will Not:**
- Stage 4 개발 루프 직접 가동 (→ `/mvp-run` — 본 커맨드는 가동 여부 확인까지만)
- 기존 코드베이스 위 작업 (→ kotlin-spring·python-fastapi·go-mux·nextjs·search 등 스택별 플러그인)
- 게이트 실패 상태에서 다음 Stage 진행, 또는 G1/G2를 사용자 확인 없이 통과 (`--auto`/`--stack` 명시 시 제외)
- 조직 표준 외 스택의 무근거 채택

## Related
- `mvp-orchestrator` — Stage 0~4 상태기계·게이트 정책·P-R 규약 (본 커맨드의 위임 대상)
- `prd-authoring` / `mvp-design-spec` — Stage 1·2 산출물 표준
- `/mvp-run` — Stage 4 개발 루프 시작/재개
- `/mvp-gate` — 현 Stage 게이트 수동 재실행
