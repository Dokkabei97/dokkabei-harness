---
name: unit-economics
description: "유닛 이코노믹스 분석. CAC, LTV, 번레이트, 런웨이를 계산하고 재무 건전성을 평가한다."
category: finance
complexity: intermediate
---

# /unit-economics - 유닛 이코노믹스 분석

## Triggers
- 비즈니스의 재무 건전성을 분석할 때
- 투자 유치 전 핵심 재무 지표를 정리할 때
- "유닛이코노믹스 분석해줘", "CAC/LTV 계산해줘", "번레이트 계산해줘"

## Usage
```
/unit-economics [비즈니스 설명]

Options:
  --model saas|marketplace|ecommerce|ad   수익 모델 유형
  --data [파일경로]                        실제 데이터 파일 (CSV/JSON)
  --scenario conservative|base|optimistic  시나리오 (기본: base)
  --projection [개월]                      예측 기간 (기본: 36)
```

## Behavioral Flow

### Phase 1: 비즈니스 모델 파악
- 수익 모델 유형 확인 (SaaS, 마켓플레이스, 커머스, 광고)
- 핵심 수익 흐름과 비용 구조 파악
- 실제 데이터 유무 확인 (없으면 가정 기반 분석)

### Phase 2: 핵심 지표 계산
**수익 지표:**
- ARPU (Average Revenue Per User): 사용자당 평균 매출
- MRR/ARR: 월/연 반복 매출 (구독 모델)
- GMV & Take Rate: 총 거래액 & 수수료율 (마켓플레이스)

**비용 지표:**
- CAC: 고객 획득 비용 = (마케팅 + 영업) / 신규 고객
- COGS: 매출 원가 (서버, 결제 수수료, CS 등)
- Gross Margin: 매출 총이익률

**건전성 지표:**
- LTV: 고객 생애 가치 = ARPU × Gross Margin / Churn
- LTV/CAC Ratio: 3.0 이상이 건강
- Payback Period: CAC 회수 기간 (12개월 이내 목표)

### Phase 3: 번레이트 & 런웨이
- Gross Burn Rate: 월 총 지출
- Net Burn Rate: 월 순 현금 소모 (지출 - 수입)
- Runway: 잔여 현금 / Net Burn Rate
- 시나리오별 런웨이 (보수적/기본/낙관적)

### Phase 4: 코호트 분석 구조
- 월별 가입 코호트 리텐션 커브 설계
- 리텐션 안정화 시점(Flattening Point) 식별
- Churn Rate 계산 (월간/연간)

### Phase 5: 시나리오 분석
- 3가지 시나리오 (보수적/기본/낙관적)로 예측
- 각 시나리오의 가정 명시
- Break-even Point(손익분기점) 산출
- 민감도 분석: 어떤 변수가 가장 큰 영향을 미치는가

### Phase 6: 개선 레버 식별
- CAC 절감 방안 (채널 최적화, 바이럴, 콘텐츠)
- LTV 향상 방안 (업셀, 리텐션, 가격 인상)
- Churn 감소 방안 (온보딩, CS, 기능 개선)
- 마진 개선 방안 (자동화, 규모의 경제)

## Tool Coordination
- **WebSearch**: 산업별 벤치마크, SaaS 지표 참조
- **Bash**: 데이터 계산 스크립트 실행
- **Read**: 실제 데이터 파일 또는 기존 재무 모델 참조
- **Write**: 분석 리포트 마크다운 파일 생성

## Examples

### SaaS 모델 분석
```
/unit-economics --model saas 월 9,900원 구독형 프로젝트 관리 SaaS (현재 MAU 500)
```

### 데이터 기반 분석
```
/unit-economics --data ./data/metrics.csv --scenario conservative
```

### 마켓플레이스 분석
```
/unit-economics --model marketplace 프리랜서 매칭 플랫폼 (수수료 15%)
```

## Boundaries

**Will:**
- 유닛 이코노믹스 프레임워크 적용 및 계산
- 시나리오별 재무 예측
- 개선 레버 식별 및 제안
- 산업 벤치마크 비교

**Will Not:**
- 법적 구속력 있는 재무제표 작성
- 세무/회계 전문 자문
- 실제 결제/송금 처리
- 확정적 투자 수익률 보장
