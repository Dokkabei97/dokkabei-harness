---
name: compliance-check
description: |
  규제 컴플라이언스 점검. 개인정보보호법·전자상거래법·정보통신망법 준수 항목을 점검하고 위반 리스크와 시정 조치를 제시한다.
  Runs a regulatory compliance check against Korean law — PIPA (privacy), E-Commerce Act, and Network Act — and reports violation risks with corrective actions. Use when: privacy/data-protection compliance check, e-commerce or online ad regulation review, Korean regulatory audit of a service.
category: legal
complexity: standard
---

# /compliance-check - 규제 컴플라이언스 점검

## Triggers
- 서비스/제품의 규제 준수 여부를 점검하고 싶을 때
- 개인정보 처리·전자상거래·광고 규제 적합성 확인이 필요할 때
- "개인정보 처리 괜찮아?", "약관 법적으로 맞아?", "규제 점검"

## Usage
```
/compliance-check [점검 대상/서비스 설명]

Options:
  --regulation privacy|ecommerce|network|all  규제 범위(기본: all)
  --target [경로]   코드·약관·처리방침 경로
  --service b2c|platform|saas|content  서비스 유형
```

## Behavioral Flow

### Phase 1: 적용 규제 식별
- 서비스 유형·개인정보 처리 여부로 적용 법령 매핑
- 국외이전·제3자 제공·아동 대상 여부 등 가중 요소 확인

### Phase 2: 개인정보 라이프사이클 점검
- `compliance-counsel` 에이전트에 위임 또는 직접 점검
- 수집·이용·제공·위탁·국외이전·보관·파기·권리보장 전 주기 확인
- `--target`이 코드면 Grep으로 수집 필드·동의 로직·로그 보존 흔적 탐지

### Phase 3: 전자상거래·광고 규제 점검
- 사업자 정보 표시, 통신판매 신고, 청약철회·환불
- 영리 광고성 정보 동의·수신거부·야간 전송 제한

### Phase 4: 리스크 정량화 및 시정
- 항목별 위반 시 제재(과징금·과태료·형사)와 발생 가능성
- 우선순위(즉시/단기/모니터링)와 구체적 시정 조치

## Tool Coordination
- **Agent**: compliance-counsel 위임
- **Grep/Glob/Read**: 코드·약관·처리방침에서 처리 흔적 분석
- **WebSearch**: 개인정보위 가이드라인·최신 개정 확인
- **Write**: 점검 보고서 생성

## Examples

### 개인정보 처리 점검(코드 대상)
```
/compliance-check --regulation privacy --target ./src 회원가입·로그 수집 점검
```

### 커머스 전자상거래법 점검
```
/compliance-check --regulation ecommerce --service b2c 환불·청약철회 정책 점검
```

## Boundaries

**Will:**
- 적용 규제 식별, 준수 항목 점검, 시정 조치 제시
- 위반 리스크 정량화

**Will Not:**
- 규제기관 신고·질의 대행
- 유권해석이 갈리는 쟁점의 확정 판단
- **변호사·규제 전문가 자문을 대체하지 않음**
