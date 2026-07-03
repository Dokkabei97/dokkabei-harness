---
name: expense-review
description: "경비·지출 증빙 적격성 검토. 지출 내역을 분석해 적격증빙 공백, 사적 비용 혼입, 계정 분류 이상을 탐지하고 보완 방향을 제시한다."
category: finance
complexity: standard
mcp-servers: []
personas: [finance-analyst, tax-risk-advisor]
---

# /expense-review - 경비·증빙 적격성 검토

## Triggers
- 법인카드·경비 지출 내역의 증빙 적격성을 점검하고 싶을 때
- 무증빙·간이영수증 지출이 얼마나 되는지, 손금 인정 리스크가 있는지 확인할 때
- "경비 처리 괜찮아?", "이 지출 증빙 문제없어?", "법인카드 내역 검토" 요청
- 결산·신고 전 경비 항목을 미리 정리하고 싶을 때

## Usage
```
/expense-review [지출 내역 설명 또는 파일 경로]

Options:
  --target [파일/디렉토리]     경비 내역 파일(엑셀 변환 CSV·텍스트 등) 경로
  --period [기간]             점검 기간 (예: 2026-1H, 2026-05)
  --focus 증빙|분류|사적혼입   집중 점검 축 (기본: 전체)
```

## Behavioral Flow

### Phase 1: 자료 확인
- 점검 대상(파일·기간·계정 체계)을 확인하고, 자료가 없으면 필요한 형식을 안내
- 사업자 유형(법인/개인)을 확인 — 증빙 요건 판단의 전제

### Phase 2: 경비 분석 디스패치
- `finance-analyst` 에이전트를 Agent 도구로 호출해 증빙 적격성 검토 수행
- 프롬프트에 대상 경로·기간·사업자 유형·집중 축을 명시
- 증빙 한도·요건 수치가 쟁점이면 WebSearch로 당해연도 기준 확인을 지시 (`korean-tax-foundations` 규약)

### Phase 3: 세무 연계 판정
- 손금불산입·가산세와 직결되는 발견(증빙불비 다수, 가지급금 신호 등)이 있으면 `tax-risk-advisor`를 추가 호출해 세무 관점 교차 확인
- `finance-escalation-policy` 트리거 해당 여부 판정

### Phase 4: 보고
- 발견 사항을 등급별로 통합하고 증빙 보완 방법을 항목별로 제시
- 강제 트리거 해당 시 보고서 최상단에 "⚠️ 반드시 세무사/회계사 상담" 배치

## Tool Coordination
- **Agent**: finance-analyst 호출 (필요 시 tax-risk-advisor 교차 확인)
- **Read/Grep/Glob**: 경비 내역·계정 데이터 분석
- **WebSearch**: 증빙 요건·한도의 당해연도 기준 확인
- **Write**: 검토 보고서 생성 (요청 시)

## Examples

### 파일 기반 점검
```
/expense-review --target ./경비내역_2026상반기.csv --period 2026-1H
```

### 특정 축 집중 점검
```
/expense-review --focus 사적혼입 법인카드 주말 사용 건이 많은데 문제 없는지 점검
```

## Boundaries

**Will:**
- 증빙 적격성 1차 분류와 리스크 패턴 탐지
- 증빙 공백의 보완 방향 제시
- 세무 직결 항목의 교차 확인 및 에스컬레이션 판정

**Will Not:**
- 확정 판단("전액 손금 인정된다", "문제없다") — 리스크 신호 수준으로만 서술
- 경비 데이터 수정·분개 대행 (에이전트는 read-only)
- 사적 비용의 경비 위장 등 탈루 조력
- 세무사/회계사 자문 대체 — 본 검토는 1차 진단이며, 중요 판단 전 전문가 상담 권고
