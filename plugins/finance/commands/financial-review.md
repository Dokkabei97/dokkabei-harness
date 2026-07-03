---
name: financial-review
description: "재무제표·손익 1차 해석. 손익계산서/재무상태표의 추세·비율·이상 항목을 분석하고 현금흐름 경고 신호를 식별한다."
category: finance
complexity: standard
mcp-servers: []
personas: [finance-analyst, tax-risk-advisor]
---

# /financial-review - 재무제표·손익 1차 해석

## Triggers
- 재무제표(손익계산서·재무상태표)를 받아 들었는데 어디를 봐야 할지 모를 때
- 전기 대비 급변한 계정, 이익률 변화, 현금흐름 경고 신호를 점검하고 싶을 때
- "재무제표 해석해줘", "손익 좀 봐줘", "우리 회사 재무 상태 어때?" 요청
- 결산·기장 자료를 세무사에게 보내기 전 스스로 이해하고 싶을 때

## Usage
```
/financial-review [재무 자료 설명 또는 파일 경로]

Options:
  --target [파일/디렉토리]        재무제표·원장 파일 경로
  --compare [전기 파일]           기간 비교용 전기 자료 경로
  --focus 손익|재무상태|현금흐름   집중 해석 축 (기본: 전체)
```

## Behavioral Flow

### Phase 1: 자료 확인
- 대상 자료의 종류(손익/재무상태/원장)·기간·비교 자료 유무 확인
- 자료가 부족하면 해석 가능한 범위를 먼저 안내 (추측 해석 금지)

### Phase 2: 해석 디스패치
- `finance-analyst` 에이전트를 Agent 도구로 호출해 1차 해석 수행
- 프롬프트에 대상 경로·기간·비교 기준·집중 축을 명시
- 추세·비율·이상 항목·현금흐름 경고 신호를 등급과 함께 요구

### Phase 3: 세무 연계 판정
- 가지급금 누적, 증빙불비 비용 급증 등 세무 리스크 신호가 발견되면 `tax-risk-advisor` 추가 호출로 교차 확인
- `finance-escalation-policy` 트리거 해당 여부 판정

### Phase 4: 보고
- 계정·비율별 발견을 통합하고, 원인 후보는 단정 없이 나열
- 강제 트리거 해당 시 보고서 최상단에 "⚠️ 반드시 세무사/회계사 상담" 배치

## Tool Coordination
- **Agent**: finance-analyst 호출 (세무 신호 시 tax-risk-advisor 교차 확인)
- **Read/Grep/Glob**: 재무제표·원장 데이터 분석
- **WebSearch**: 업종 벤치마크·회계 기준 쟁점의 1차 출처 확인
- **Write**: 해석 보고서 생성 (요청 시)

## Examples

### 기간 비교 해석
```
/financial-review --target ./재무제표_2025.csv --compare ./재무제표_2024.csv
```

### 특정 축 집중
```
/financial-review --focus 현금흐름 매출은 늘었는데 통장 잔고가 계속 줄어드는 이유 점검
```

## Boundaries

**Will:**
- 추세·비율 기반 1차 해석과 이상 항목 식별
- 현금흐름 경고 신호·세무 연계 리스크 표시
- 세무사 상담 시 물어볼 질문 목록 정리

**Will Not:**
- 재무제표 작성·수정, 결산 대행 (에이전트는 read-only)
- 확정 판단("부실이다", "분식이다") — 이상 신호·원인 후보 수준으로만 서술
- 감사의견·기업가치 평가 등 전문 자격 업무
- 회계사/세무사 자문 대체 — 본 해석은 1차 진단이며, 중요 의사결정 전 전문가 상담 권고
