---
name: tax-risk-scan
description: "한국 세무 리스크 스크리닝. 부가세·원천세·법인세(종합소득세) 신고 관점에서 무신고/과소신고/증빙불비 리스크를 탐지하고 임박 기한을 표시한다."
category: finance
complexity: advanced
mcp-servers: []
personas: [tax-risk-advisor, finance-analyst]
---

# /tax-risk-scan - 세무 리스크 스크리닝

## Triggers
- 부가세·원천세·법인세(종합소득세) 신고 전 리스크를 미리 점검하고 싶을 때
- 세무서 소명 요구·수정신고 권고 등 통지를 받았거나 세무조사가 걱정될 때
- "세금 문제 없을까?", "신고 빠뜨린 것 없는지 점검", "가산세 리스크 확인" 요청
- 프리랜서 인건비·국외 거래 등 처리 방식이 애매한 거래가 생겼을 때

## Usage
```
/tax-risk-scan [사안 설명]

Options:
  --scope vat|withholding|corporate|all   점검 세목 (기본: all)
  --entity 법인|개인-일반|개인-간이        사업자 유형
  --target [파일/디렉토리]                거래 내역·경비 데이터 경로
  --deadline [YYYY-MM-DD]                 인지하고 있는 신고·납부 기한
```

## Behavioral Flow

### Phase 1: 사안 분류
- 사업자 유형·점검 세목·임박 기한을 확인 (불명확하면 사용자에게 질문)
- 세무조사·소명 요구 등 통지 수령 여부를 확인 — `finance-escalation-policy` 강제 트리거 사전 판별

### Phase 2: 스크리닝 디스패치
- `tax-risk-advisor` 에이전트를 Agent 도구로 호출해 세목별 스크리닝 수행
- 프롬프트에 사업자 유형·세목 범위·데이터 경로·기한 정보를 명시
- 세율·기준금액·기한이 판정에 개입하면 **WebSearch로 당해연도 기준 확인 후 출처 병기**를 지시 (`korean-tax-foundations` 규약)

### Phase 3: 증빙 교차 확인
- 증빙불비·경비 적격성이 핵심 쟁점이면 `finance-analyst`를 추가 호출해 증빙 실태 교차 확인
- 두 에이전트 결과가 상충하면 보수적 안을 우선 제시

### Phase 4: 에스컬레이션 판정 및 보고
- 트리거 축(세무조사 가능성 × 금액 규모 × 신고기한 임박)으로 `finance-escalation-policy` 판정
- 강제 트리거 해당 시 보고서 **최상단**에 "⚠️ 반드시 세무사/회계사 상담"과 사유 배치
- 시간 민감 항목(기한·수정신고·기한후신고)을 별도 섹션으로 정리

## Tool Coordination
- **Agent**: tax-risk-advisor 호출 (증빙 쟁점 시 finance-analyst 교차 확인)
- **Read/Grep/Glob**: 거래 내역·경비 데이터 분석
- **WebSearch**: 당해연도 세율·기준금액·신고 일정 확인 (국세청·국가법령정보센터 등 1차 출처)
- **Write**: 스크리닝 보고서 생성 (요청 시)

## Examples

### 신고 전 종합 점검
```
/tax-risk-scan --entity 법인 --scope all 7월 부가세 확정신고 전 리스크 점검 --target ./거래내역
```

### 통지 수령 후 점검
```
/tax-risk-scan --entity 개인-일반 세무서에서 매출 과소신고 소명 요구를 받음 --deadline 2026-07-20
```

### 거래 유형 판단
```
/tax-risk-scan --scope withholding 개발 외주를 프리랜서 사업소득으로 처리 중인데 근로자성 리스크 점검
```

## Boundaries

**Will:**
- 세목별 리스크 신호 스크리닝과 가산세 유형 매핑
- 당해연도 기준의 WebSearch 검증 및 출처 병기
- 에스컬레이션 판정과 강제 경고 최상단 배치

**Will Not:**
- 확정 판단("가산세 없다", "적법하다") — 리스크 신호·가능성으로만 서술
- 세무 신고서 작성·제출, 홈택스·불복 절차 대행
- 매출 누락 은폐·가공경비 등 탈루 조력
- 세무사/회계사 자문 대체 — 본 스캔은 1차 진단이며, 신고·소명·불복 등 실행 전 전문가 상담 권고
