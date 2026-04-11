---
name: validate-idea
description: "Build-Measure-Learn 기반 아이디어/가설 검증. 리스크가 높은 가설을 식별하고 실험을 설계한다."
category: strategy
complexity: advanced
---

# /validate-idea - 아이디어 검증

## Triggers
- 사업 아이디어의 타당성을 검증하고 싶을 때
- 가설을 수립하고 실험을 설계할 때
- "아이디어 검증해줘", "이거 되는 사업이야?", "가설 검증 설계해줘"

## Usage
```
/validate-idea [아이디어 설명]

Options:
  --stage discovery|validation|creation  Customer Development 단계 (기본: discovery)
  --hypothesis [가설]                     특정 가설 검증에 집중
  --mvp-type concierge|wizard|landing|video|piecemeal  MVP 유형 지정
```

## Behavioral Flow

### Phase 1: 아이디어 해부
- 아이디어를 구성 요소로 분해:
  - 타겟 고객은 누구인가?
  - 어떤 문제를 해결하는가?
  - 제안하는 솔루션은 무엇인가?
  - 어떻게 돈을 벌 것인가?
- 암묵적 가정(assumptions)을 명시적으로 추출

### Phase 2: 가설 매트릭스 작성
- 추출된 가정을 검증 가능한 가설로 변환
- 각 가설을 분류:
  - **고객 가설**: 이 사람들이 이 문제를 겪고 있는가?
  - **문제 가설**: 이 문제가 충분히 심각한가?
  - **솔루션 가설**: 이 솔루션이 문제를 해결하는가?
  - **수익 가설**: 고객이 비용을 지불할 의향이 있는가?
  - **채널 가설**: 이 방법으로 고객에게 도달 가능한가?
- Riskiest Assumption Test (RAT): 가장 위험한 가설 우선순위

### Phase 3: 실험 설계
- 각 우선순위 가설에 대한 최소 실험 설계:
  ```
  가설: [구체적 가설문]
  실험 방법: [인터뷰/랜딩페이지/프로토타입/연기 테스트]
  성공 기준: [정량적 기준]
  기간: [1~4주]
  비용: [예산]
  필요 표본: [수]
  ```

### Phase 4: MVP 스코핑
- 검증에 필요한 최소한의 제품 정의
- MVP 유형 선택 및 근거:
  - Concierge: 수동으로 서비스 제공 (문제/솔루션 검증)
  - Wizard of Oz: 자동처럼 보이지만 수동 (솔루션 검증)
  - Landing Page: 가치 제안만 공개 (수요 검증)
  - Video: 데모 영상으로 반응 측정 (솔루션 관심도)
  - Piecemeal: 기존 도구 조합으로 제공 (운영 가능성)
- 핵심 기능 vs 제거 가능 기능 구분

### Phase 5: 판단 프레임워크
- 실험 결과 해석 가이드:
  - 가설 검증됨 → 다음 가설로 진행
  - 가설 반증됨 → 피벗 옵션 검토
  - 결과 불분명 → 실험 재설계 또는 표본 확대
- 피벗 유형별 적용 시나리오 제시
- Go/No-Go 체크리스트

### Phase 6: 액션 플랜
- 즉시 실행 가능한 다음 3가지 액션
- 각 액션의 담당자, 기한, 필요 리소스
- 1주/2주/4주 마일스톤 설정

## Tool Coordination
- **WebSearch**: 유사 서비스, 시장 데이터, 실패 사례 조사
- **WebFetch**: 경쟁사/유사 서비스 상세 분석
- **Write**: 검증 계획서 마크다운 파일 생성
- **Read**: 기존 린 캔버스/시장조사 결과 참조

## Examples

### 기본 아이디어 검증
```
/validate-idea AI 기반 이력서 자동 최적화 서비스
```

### 특정 가설 집중 검증
```
/validate-idea --hypothesis "프리랜서 개발자의 70%가 프로젝트 매칭에 주 5시간 이상 소비한다"
```

### MVP 유형 지정
```
/validate-idea --mvp-type concierge 시니어를 위한 맞춤형 운동 코칭
```

## Boundaries

**Will:**
- 암묵적 가정을 명시적 가설로 추출
- 검증 실험 설계 (방법, 기준, 기간, 비용)
- MVP 스코핑 및 유형 추천
- 피벗 판단 프레임워크 제공

**Will Not:**
- 실제 고객 인터뷰 수행
- 랜딩페이지/프로토타입 구현 (설계까지만)
- "이 아이디어는 성공합니다" 같은 확정적 판단
- 기술적 타당성 심층 검토 (개발 하네스로 위임)
