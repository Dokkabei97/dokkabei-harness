---
name: legal-risk-scan
description: "종합 법적 리스크 스캔. 사안을 분석해 관련 전문 에이전트를 병렬 투입하고, 영역 교차 리스크를 통합 보고한다."
category: legal
complexity: advanced
---

# /legal-risk-scan - 종합 법적 리스크 스캔

## Triggers
- 사업/서비스/문서/상황의 법적 리스크를 종합 점검하고 싶을 때
- 여러 법 영역(계약·규제·노동·IP·형사)이 얽힌 복합 사안일 때
- "법적으로 문제없어?", "리스크 전체 점검", "법무 종합 검토" 요청

## Usage
```
/legal-risk-scan [점검 대상/상황 설명]

Options:
  --scope contract|corporate|labor-ip|compliance|dispute|all  점검 범위(기본: all)
  --target [파일/디렉토리]   계약서·약관·코드 등 점검 대상 경로
  --role 피해자|사업자|개인  의뢰인 입장(형사·분쟁 사안 시)
```

## Behavioral Flow

### Phase 1: 사안 분류
- `legal-team-orchestrator` 스킬의 라우팅 규칙으로 사안을 분류
- 관련 법 영역을 식별하고 투입할 전문 에이전트를 선정
- 누락된 사실관계는 사용자에게 확인

### Phase 2: 전문가 병렬 디스패치
- 선정된 에이전트를 **단일 메시지에 병렬 Agent 호출**로 투입
- 각 에이전트에 점검 대상·맥락·입장·출력형식을 명시한 프롬프트 전달
- 의존 관계가 있으면 순차 실행(예: 계약 구조 → 규제 영향)

### Phase 3: 결과 통합
- 에이전트별 발견을 리스크 매트릭스로 통합
- **교차 분석**: 한 영역의 조치가 다른 영역에 미치는 부작용 표시
- 공통 지적 이슈는 severity 상향

### Phase 4: 우선순위 액션 플랜
- Critical/High/Medium 순으로 조치 정리
- 시간 민감 항목(증거 보전·신고 기한·계약 해지 시점) 별도 표시

### Phase 5: 에스컬레이션 안내
- 오케스트레이터의 에스컬레이션 정책에 해당하는 사안은 **변호사 상담 필수**로 강조

## Tool Coordination
- **Agent**: 전문 에이전트(contract/corporate/labor-ip/compliance/dispute) 병렬 호출
- **Read/Grep/Glob**: 계약서·약관·코드 등 점검 대상 분석
- **WebSearch**: 최신 법령·판례 1차 출처 확인
- **Write**: 통합 리스크 보고서 생성

## Examples

### 서비스 출시 전 종합 점검
```
/legal-risk-scan B2C 헬스케어 앱 출시 전 법적 리스크 전체 점검 --target ./docs
```

### 특정 영역 한정
```
/legal-risk-scan --scope compliance 개인정보 수집 동의 플로우 점검 --target ./src/auth
```

### 분쟁 사안(입장 명시)
```
/legal-risk-scan --scope dispute --role 피해자 악성 댓글로 인한 명예훼손 대응
```

## Boundaries

**Will:**
- 사안 분류 및 전문 에이전트 라우팅/병렬 디스패치
- 교차 영역 리스크 통합 및 우선순위화
- 에스컬레이션 필요 사안 식별

**Will Not:**
- 개별 영역의 확정적 법률 판단 (에이전트 Boundaries 준수)
- 변호사 자문 대체 — 통합 보고서는 1차 진단
- 규제기관·수사기관 절차 대행
