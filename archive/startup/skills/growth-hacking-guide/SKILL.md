---
name: growth-hacking-guide
description: |
  그로스 해킹 프레임워크 가이드. AARRR 퍼널 설계, Bullseye 채널 전략, ICE 실험 우선순위,
  바이럴 루프 설계, North Star Metric 정의를 제공한다.
  Use when: 마케팅 전략 수립, 그로스 실험 설계, 채널 선택, 퍼널 최적화 시
  Growth hacking framework guide covering AARRR funnel design, Bullseye channel strategy,
  ICE experiment prioritization, viral loop design, and North Star Metric definition.
  Use when: building a marketing strategy, designing growth experiments, selecting acquisition channels, or optimizing a funnel.
metadata:
  version: 1.0.0
  category: marketing
---

# Growth Hacking Guide — 그로스 해킹 프레임워크

## When to Apply
- 제품 출시 후 사용자 성장 전략을 수립할 때
- 마케팅 채널을 선택하고 실험을 설계할 때
- 퍼널 병목을 진단하고 최적화할 때
- 바이럴/레퍼럴 시스템을 설계할 때

## AARRR Pirate Metrics

| 단계 | 의미 | 핵심 질문 | 주요 지표 |
|------|------|----------|----------|
| **Acquisition** | 획득 | 사용자가 어디서 오는가? | 채널별 방문자, CPA |
| **Activation** | 활성화 | 첫 가치를 경험하는가? | 온보딩 완료율, Time to Value |
| **Retention** | 유지 | 다시 돌아오는가? | D1/D7/D30 리텐션, DAU/MAU |
| **Revenue** | 수익 | 돈을 지불하는가? | 전환율, ARPU, MRR |
| **Referral** | 추천 | 다른 사람을 데려오는가? | K-factor, NPS, 공유율 |

**퍼널 최적화 우선순위:** Retention > Activation > Acquisition > Revenue > Referral
(리텐션이 안 되면 물 새는 양동이에 물 붓기)

## North Star Metric

NSM은 제품의 핵심 가치 전달을 가장 잘 대표하는 단일 지표:

| 비즈니스 유형 | NSM 예시 |
|-------------|---------|
| SaaS | 주간 활성 사용자의 핵심 기능 사용 횟수 |
| 마켓플레이스 | 주간 완료 거래 수 |
| 미디어 | 일간 콘텐츠 소비 시간 |
| 커머스 | 주간 재구매 고객 수 |
| 소셜 | 일간 콘텐츠 생산량 |

**좋은 NSM 기준:** 가치 반영 + 선행 지표 + 측정 가능 + 팀 전체 정렬

## Bullseye Framework — 채널 선택

**19개 트랙션 채널:**

| # | 채널 | Pre-PMF 적합도 | Post-PMF 적합도 |
|---|------|:---:|:---:|
| 1 | 바이럴 마케팅 | ● | ● |
| 2 | PR (언론 보도) | ● | ○ |
| 3 | 비전통 PR (게릴라) | ● | ○ |
| 4 | SEM (검색 광고) | ○ | ● |
| 5 | 소셜/디스플레이 광고 | ○ | ● |
| 6 | 오프라인 광고 | ✕ | ○ |
| 7 | SEO | ○ | ● |
| 8 | 콘텐츠 마케팅 | ● | ● |
| 9 | 이메일 마케팅 | ○ | ● |
| 10 | 엔지니어링 as 마케팅 | ● | ● |
| 11 | 블로그 타겟팅 | ● | ○ |
| 12 | 사업 개발 (BD) | ○ | ● |
| 13 | 영업 (Sales) | ○ | ● |
| 14 | 제휴/어필리에이트 | ✕ | ● |
| 15 | 기존 플랫폼 활용 | ● | ○ |
| 16 | 컨퍼런스/이벤트 | ● | ○ |
| 17 | 커뮤니티 빌딩 | ● | ● |
| 18 | 오프라인 매장/이벤트 | ✕ | ○ |
| 19 | Speaking/Thought Leadership | ○ | ● |

● 높음 / ○ 보통 / ✕ 낮음

## ICE Framework — 실험 우선순위

```
ICE Score = (Impact + Confidence + Ease) / 3

Impact (영향도): 성공 시 지표에 미치는 영향 (1~10)
Confidence (확신도): 가설이 맞을 확률 (1~10)
Ease (용이도): 구현 난이도의 역수 (1~10)
```

| ICE 점수 | 우선순위 | 액션 |
|---------|---------|------|
| 8~10 | 즉시 실행 | 이번 주 시작 |
| 5~7 | 백로그 상위 | 다음 스프린트 |
| 3~4 | 백로그 하위 | 리소스 여유 시 |
| 1~2 | 보류 | 조건 변경 시 재평가 |

## Viral Loop Design

```
사용자 행동 → 공유 트리거 → 초대 메커니즘 → 신규 가입 → 가치 경험 → 반복
```

**바이럴 계수 (K-factor):**
```
K = 사용자당 초대 수 × 초대 → 가입 전환율

K > 1: 유기적 성장 (지수적 증가)
K = 0.5~1: 보조적 성장 채널
K < 0.5: 바이럴 효과 미미
```

**바이럴 유형:**
| 유형 | 메커니즘 | 예시 |
|------|---------|------|
| 고유 바이럴 | 제품 사용 자체가 노출 | Zoom 초대 링크 |
| 인공 바이럴 | 인센티브 기반 초대 | 토스 친구 초대 보상 |
| 워드오브마우스 | 자발적 추천 | Tesla (광고 없이 입소문) |
| 콘텐츠 바이럴 | 사용자 생성 콘텐츠 확산 | TikTok, Canva |

## 성장 단계별 전략

| 단계 | 핵심 목표 | 전략 |
|------|----------|------|
| **Pre-PMF** (0~100명) | 문제-솔루션 적합성 | 수동 영업, 커뮤니티, 콘텐츠 |
| **PMF 탐색** (100~1,000명) | 리텐션 안정화 | Aha Moment 최적화, 온보딩 개선 |
| **초기 성장** (1,000~10,000명) | 반복 가능 채널 발굴 | Bullseye 테스트, 3개 채널 집중 |
| **스케일링** (10,000명+) | 채널 확장 및 효율화 | 자동화, 유료 채널 스케일, BD |

## References
- Dave McClure, "Startup Metrics for Pirates" (2007) — AARRR
- Gabriel Weinberg, "Traction" (2015) — Bullseye Framework
- Sean Ellis, "Hacking Growth" (2017) — Growth Hacking 체계
