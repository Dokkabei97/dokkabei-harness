---
name: feedback-synthesis
description: "고객 피드백 종합. 이미 확보한 인터뷰 노트·VoC·리뷰 덤프 파일을 입력받아 패턴·인사이트·기회 가설을 구조화하고 .planning/business/feedback-synthesis.md를 산출한다. '스토리 후보' 섹션은 mvp 하네스(prd-authoring)가 읽을 수 있는 형태. 고객 피드백 파일이 있을 때만 발동."
category: research
complexity: advanced
mcp-servers: []
personas: [market-researcher]
---

# /feedback-synthesis - 고객 피드백 종합

이미 확보한 고객 피드백 파일(인터뷰 노트·VoC 덤프·앱스토어/스토어 리뷰 등)을 읽어
패턴 → 인사이트 → 기회 가설로 구조화하고 `.planning/business/feedback-synthesis.md`를 산출한다.
분석은 `market-researcher` 에이전트에 위임한다. 산출물의 **`## 스토리 후보`** 섹션은
mvp 하네스의 `product-strategist`가 Stage 1(prd-authoring)에서 스토리 소재로 읽을 수 있는
형태(3~10개 후보)로 작성된다. `--kill-check`로 도출 가설을 기존 kill-gate에 통과시킬 수 있다.

## Triggers
- **고객 피드백 파일이 이미 있을 때** — 인터뷰 노트·VoC 덤프·리뷰 수출 파일을 구조화하고 싶을 때
- "이 인터뷰 노트 정리해줘", "리뷰 덤프에서 패턴 뽑아줘", "VoC 종합해줘" + 파일/디렉터리 경로 제시
- 다음 MVP 이터레이션의 스토리 소재를 고객 근거 기반으로 만들고 싶을 때
- (오발동 방지) 피드백 파일이 없는 상태의 "고객 조사해줘"에는 발동하지 않는다 — 시장·고객 조사는 `/market-research`, 가설 검증 설계는 `/validate-idea`

## Usage
```
/feedback-synthesis [피드백 파일/디렉터리 경로]

Options:
  --source interview|voc|review|mixed  입력 유형 힌트 (기본: 자동 감지)
  --stories-max <n>                    스토리 후보 수 상한 (기본 10, 범위 3~10)
  --kill-check                         도출된 기회 가설을 /kill-check(assumption-killer)로 즉시 반증
  --output [파일경로]                   산출 경로 (기본: .planning/business/feedback-synthesis.md)
```

## Behavioral Flow

### Phase 0: 입력 확인
- 인자로 받은 파일/디렉터리 존재를 확인. **피드백 파일이 없으면 중단**하고 안내한다
  (이 커맨드는 피드백 '수집'이 아니라 '종합' — 수집 설계는 `/validate-idea`, 시장 조사는 `/market-research`)
- 경로 미지정 시 후보(`./research/`, `./feedback/`, 최근 언급 파일)를 제시하고 확인받는다

### Phase 1: 정규화 (market-researcher 위임)
- 파일을 읽어 발화 단위로 분리하고 소스·고객 세그먼트를 태깅
- 이름·연락처 등 개인 식별 정보는 산출물에서 마스킹

### Phase 2: 패턴 추출
- 발화를 페인포인트 / 니즈 / 만족 요인 / 이탈 사유로 클러스터링
- 클러스터별 **빈도(인용 수) × 강도(감정·이탈 언급)** 를 집계해 우선순위화
- 소수 의견도 버리지 않고 "약한 신호" 섹션에 보존

### Phase 3: 인사이트·기회 가설 구조화
- 패턴에서 인사이트를 도출하고, 기회 가설을 반증 가능한 문장으로 작성:
  "[세그먼트]는 [문제] 때문에 [대안]을 쓰고 있으므로, [해결책]을 제공하면 [행동 변화]가 일어날 것이다"
- 각 가설에 **근거 인용 수와 대표 인용문**을 병기 — 근거 없는 가설은 `[추정]` 표기
  (assumption-killer가 공격할 수 있도록 반증 조건을 함께 명시)

### Phase 4: 스토리 후보 도출 (3~10개, `--stories-max` 상한)
- mvp `prd-authoring` 규격과 호환되는 형태로 작성. 후보 id는 `C-NN`(스토리 확정 전이므로 `S-NN` 미사용):
```markdown
## 스토리 후보
### C-01 [스토리 제목 — 1 스토리 = 1 루프 반복 크기]
- 페르소나: [세그먼트/페르소나명]
- 근거: 인용 N건 — "대표 인용문" (소스)
- AC 힌트: [실행·관찰로 판정 가능한 결과 서술 — Given-When-Then 변환용 소재]
```
- **경계**: 후보는 소재일 뿐 prd.json 자동 생성이 아니다 — 검증형 AC(Given-When-Then) 작성과
  `S-NN` 부여는 mvp `product-strategist`의 몫이며, 후보도 Stage 1에서 동일하게 반증받는다

### Phase 5: 산출·연계
- `.planning/business/feedback-synthesis.md` 저장 — 섹션: `## 입력 소스` / `## 패턴` /
  `## 인사이트` / `## 기회 가설` / `## 스토리 후보` / `## 약한 신호`
- `--kill-check` 지정 시 `/kill-check`를 이어 실행 — 도출된 기회 가설을 `assumption-killer`의
  적대적 반증(하중 가정·출처·민감도·정합성)에 통과시켜 GO/PIVOT/KILL 판정을 받는다

## Tool Coordination
- **Agent**: market-researcher 위임 (정규화·패턴·인사이트 분석)
- **Read/Glob/Grep**: 피드백 파일 로딩, 키워드 빈도 탐색
- **Bash**: 인용 수 집계 등 정량화 스크립트
- **Write**: `.planning/business/feedback-synthesis.md` 산출 (mvp 하네스가 스토리 소재로 참조)
- **연계**: `--kill-check` → `/kill-check`(assumption-killer), 스토리 후보 → mvp `prd-authoring`

## Examples

### 인터뷰 노트 디렉터리 종합
```
/feedback-synthesis ./research/interviews/
```

### 리뷰 덤프 종합 + 가설 즉시 반증
```
/feedback-synthesis --source review --kill-check ./data/appstore-reviews.csv
```

### 스토리 후보 수 제한
```
/feedback-synthesis --stories-max 5 ./feedback/voc-2026-06.md
```

## Boundaries

**Will:**
- 확보된 피드백 파일 기반 패턴·인사이트·기회 가설 구조화
- 모든 가설·후보에 근거 인용 수 병기, 근거 없는 항목 `[추정]` 표기
- mvp prd-authoring이 읽을 수 있는 스토리 후보 3~10개 산출
- `--kill-check`로 기존 kill-gate(assumption-killer) 연계

**Will Not:**
- 피드백 파일 없이 동작 — 수집·설문 설계 대행 안 함 (→ `/validate-idea`, `/market-research`)
- prd.json 자동 생성 — 검증형 AC 작성은 mvp product-strategist가 수행
- 정성 데이터에 통계적 유의성 주장 부여 (가설일 뿐임을 명시)
- 개인 식별 정보를 산출물에 노출
