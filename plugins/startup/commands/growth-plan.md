---
name: growth-plan
description: "AARRR 퍼널 기반 그로스 전략 수립. 채널 전략, 그로스 실험 백로그, 30/60/90일 실행 계획을 생성한다."
category: marketing
complexity: advanced
---

# /growth-plan - 그로스 전략 수립

## Triggers
- 제품 출시 후 성장 전략이 필요할 때
- 마케팅 채널과 실험을 체계적으로 계획할 때
- "마케팅 전략 세워줘", "그로스 플랜 만들어줘", "사용자 어떻게 모아?"

## Usage
```
/growth-plan [제품/서비스 설명]

Options:
  --stage pre-pmf|post-pmf|scale   성장 단계 (기본: pre-pmf)
  --budget [금액]                    월 마케팅 예산
  --focus acquisition|activation|retention|revenue|referral  AARRR 집중 단계
  --channel [채널명]                 특정 채널 심층 전략
```

## Behavioral Flow

### Phase 1: 성장 단계 진단
- 현재 제품/서비스의 성장 단계를 판단:
  - **Pre-PMF**: PMF 미달성, 리텐션 불안정 → 채널 실험보다 제품 개선 우선
  - **Post-PMF**: PMF 달성, 유기적 성장 시작 → 채널 발굴 및 최적화
  - **Scale**: 반복 가능한 성장 모델 확보 → 채널 확장 및 효율화
- North Star Metric 정의

### Phase 2: AARRR 퍼널 설계
- 각 단계별 정의와 핵심 지표 설정
- Aha Moment 정의 (활성화의 핵심 순간)
- 단계별 전환율 벤치마크 설정
- 가장 큰 병목 구간 식별

### Phase 3: 채널 전략 (Bullseye)
- 19개 트랙션 채널 브레인스토밍
- 상위 6개 채널 선정 및 저비용 테스트 설계
- 각 테스트의 예산, 기간, 성공 기준 정의
- 상위 1~3개 핵심 채널 집중 전략

### Phase 4: 그로스 실험 백로그
- ICE 프레임워크로 우선순위 결정:
  - **I**mpact (영향도): 1~10
  - **C**onfidence (확신도): 1~10
  - **E**ase (용이도): 1~10
  - ICE Score = (I + C + E) / 3
- 실험별 가설, 방법, 기간, 성공 기준 정의
- 주간 실험 리듬: 매주 1~2개 실험 실행

### Phase 5: 30/60/90일 실행 계획
- **30일**: 기초 세팅 + 첫 실험
  - 분석 도구 설치 (GA, Mixpanel, Amplitude 등)
  - 퍼널 계측 및 기초 데이터 수집
  - 2~3개 채널 테스트 시작
- **60일**: 채널 검증 + 최적화
  - 테스트 결과 분석 및 핵심 채널 확정
  - 전환율 최적화 (CRO)
  - 콘텐츠/SEO 기반 구축
- **90일**: 스케일링 + 시스템화
  - 검증된 채널 확장
  - 자동화 구축 (이메일, 리타겟팅)
  - 바이럴/레퍼럴 루프 시도

### Phase 6: 예산 배분
- 채널별 예산 할당 제안
- ROI 기반 재배분 기준 설정
- 실험 예산 vs 검증된 채널 예산 비율 (70/30 → 30/70)

## Tool Coordination
- **WebSearch**: 채널별 벤치마크, 성공 사례, 도구 리서치
- **WebFetch**: 경쟁사 마케팅 전략 분석
- **Write**: 그로스 전략서 마크다운 파일 생성
- **Read**: 기존 시장조사/린 캔버스 결과 참조

## Examples

### 기본 그로스 플랜
```
/growth-plan B2B SaaS HR 관리 도구 (월 유료 구독 모델)
```

### 예산 지정
```
/growth-plan --budget 500만원 --stage post-pmf 반려동물 커머스 앱
```

### 특정 퍼널 집중
```
/growth-plan --focus retention 구독형 밀키트 서비스
```

## Boundaries

**Will:**
- AARRR 퍼널 설계 및 병목 진단
- 채널 전략 수립 및 실험 설계
- 30/60/90일 실행 계획 생성
- 예산 배분 제안

**Will Not:**
- 광고 크리에이티브 제작
- 실제 광고 집행/캠페인 운영
- SNS 계정 운영 대행
- 개인정보 수집/처리 설계
