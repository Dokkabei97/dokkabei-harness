---
name: unit-economics-guide
description: |
  유닛 이코노믹스 프레임워크 가이드. CAC/LTV/Payback Period 계산법,
  수익 모델별 핵심 지표, 번레이트/런웨이 관리, 벤치마크를 제공한다.
  Use when: 재무 지표 분석, 수익 모델 설계, 투자 유치 재무 준비 시
  Unit economics framework guide covering CAC/LTV/Payback Period calculation methods,
  key metrics per revenue model, burn rate/runway management, and benchmarks.
  Use when: analyzing financial metrics, designing a revenue model, or preparing financials for fundraising.
metadata:
  version: 1.0.0
  category: finance
---

# Unit Economics Guide — 유닛 이코노믹스 프레임워크

## When to Apply
- 비즈니스의 재무 건전성을 분석할 때
- 수익 모델을 설계하거나 검증할 때
- 투자 유치를 위한 재무 지표를 정리할 때
- 비용 구조 최적화 방향을 결정할 때

## 핵심 공식

### CAC (Customer Acquisition Cost)
```
CAC = (마케팅 비용 + 영업 비용) / 신규 고객 수

Blended CAC: 전체 비용 기준 (유기적 + 유료)
Paid CAC: 유료 채널 비용만 (더 정확한 채널 평가)
Fully Loaded CAC: 마케팅 팀 인건비 포함
```

### LTV (Lifetime Value)
```
기본: LTV = ARPU × 평균 고객 수명 (월)
구독: LTV = ARPU / Monthly Churn Rate
마진 반영: LTV = (ARPU × Gross Margin) / Monthly Churn Rate
할인율 반영: LTV = Σ (ARPU × Margin) / (1 + d)^t
```

### 건전성 지표
```
LTV/CAC Ratio
  < 1.0  → 고객 확보할수록 적자 (긴급)
  1.0~3.0 → 개선 필요 (최적화 집중)
  3.0~5.0 → 건강한 비즈니스 (스케일 가능)
  > 5.0   → 마케팅 투자 여력 있음

Payback Period = CAC / (ARPU × Gross Margin)
  목표: 12개월 이내 (SaaS 기준)
  이상: 6개월 이내
```

## 수익 모델별 핵심 지표

### SaaS (구독 모델)
| 지표 | 공식 | 벤치마크 |
|------|------|---------|
| MRR | 유료 사용자 × 월 구독료 | - |
| ARR | MRR × 12 | - |
| Net Revenue Retention | (시작 MRR + 업셀 - 다운그레이드 - 이탈) / 시작 MRR | >110% |
| Gross Margin | (매출 - COGS) / 매출 | >70% |
| Monthly Churn | 이탈 고객 / 시작 고객 | <5% |
| Quick Ratio | (New MRR + Expansion) / (Churn + Contraction) | >4 |

### 마켓플레이스
| 지표 | 공식 | 벤치마크 |
|------|------|---------|
| GMV | 총 거래액 | - |
| Take Rate | 수수료 / GMV | 5~30% |
| 유동성 | 매칭률 (공급 매칭된 수요 / 전체 수요) | >50% |
| 리스트 대비 거래 전환 | 거래 수 / 리스트 수 | 업종별 상이 |

### 커머스 (이커머스)
| 지표 | 공식 | 벤치마크 |
|------|------|---------|
| AOV | 총 매출 / 주문 수 | - |
| 재구매율 | 재구매 고객 / 전체 고객 | >30% |
| 장바구니 전환율 | 결제 완료 / 장바구니 담기 | >50% |
| 반품률 | 반품 건수 / 주문 건수 | <10% |

## 번레이트 & 런웨이

```
Gross Burn Rate = 월 총 지출
Net Burn Rate = 월 지출 - 월 수입
Runway (개월) = 잔여 현금 / Net Burn Rate
```

**런웨이 관리 원칙:**
| 런웨이 | 상태 | 액션 |
|--------|------|------|
| 18개월+ | 안전 | 성장 투자 가능 |
| 12~18개월 | 주의 | 펀드레이징 준비 시작 |
| 6~12개월 | 경고 | 적극적 펀드레이징 + 비용 절감 |
| 6개월 미만 | 위험 | 긴급 조치 (Bridge Round, 비용 대폭 절감) |

## 시나리오 분석 템플릿

| 구분 | 보수적 | 기본 | 낙관적 |
|------|--------|------|--------|
| 월 성장률 | 5% | 15% | 30% |
| Churn Rate | 8% | 5% | 3% |
| CAC | 높음 | 보통 | 낮음 |
| Gross Margin | 60% | 70% | 80% |
| Break-even | 24개월 | 18개월 | 12개월 |

## 개선 레버

| 레버 | 방법 | 영향도 |
|------|------|--------|
| **CAC 절감** | 콘텐츠 마케팅, 바이럴, 채널 최적화 | 높음 |
| **ARPU 향상** | 업셀, 가격 인상, 프리미엄 티어 | 높음 |
| **Churn 감소** | 온보딩 개선, CS 강화, 기능 개선 | 매우 높음 |
| **마진 개선** | 자동화, 인프라 최적화, 규모의 경제 | 중간 |
| **Payback 단축** | 연 결제 할인, 선불 인센티브 | 중간 |

**Churn 1% 감소의 효과 > 새 고객 10% 증가의 효과** (복리 효과)

## 투자 라운드별 기대 수준

| 지표 | Pre-Seed | Seed | Series A |
|------|---------|------|---------|
| LTV/CAC | 이론적 추정 OK | >1.5 | >3.0 |
| Payback | 추정 OK | <18개월 | <12개월 |
| MRR | 무관 | $5K~$50K | $100K+ |
| 성장률 (MoM) | 무관 | 15%+ | 15~20% |
| Churn | 무관 | <10% | <5% |

## References
- David Skok, "SaaS Metrics 2.0" — SaaS 핵심 지표 체계
- Bill Gurley, "All Revenue is Not Created Equal" — 매출 품질 평가
- Bessemer Venture Partners, "Cloud Index" — SaaS 벤치마크
