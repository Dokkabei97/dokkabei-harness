---
name: lean-canvas
description: "린 캔버스 9블록 작성. 아이디어를 구조화된 비즈니스 가설로 변환한다."
category: strategy
complexity: intermediate
---

# /lean-canvas - 린 캔버스 작성

## Triggers
- 새로운 사업 아이디어를 구조화할 때
- 기존 비즈니스 모델을 정리/재검토할 때
- "린 캔버스 작성해줘", "비즈니스 모델 정리해줘"

## Usage
```
/lean-canvas [아이디어 설명]

Options:
  --focus problem|solution|all  특정 블록에 집중 (기본: all)
  --format table|detail         출력 형식 (기본: detail)
  --compare                     기존 캔버스와 비교 (피벗 시)
```

## Behavioral Flow

### Phase 1: 아이디어 파악
- 사용자의 아이디어/제품 설명을 분석
- 핵심 도메인과 타겟 고객을 식별
- 부족한 정보가 있으면 질문 (최대 3개)

### Phase 2: 문제-고객 블록 작성
- **Customer Segments**: 얼리어답터를 구체적으로 정의
  - "모든 직장인"이 아닌 "주 3회 이상 야근하는 IT 스타트업 개발자"
- **Problem**: 상위 3가지 문제 + 기존 대안(Existing Alternatives)
  - 문제는 "있으면 좋겠다" 수준이 아닌 "해결하지 않으면 안 되는" 수준인지 평가

### Phase 3: 솔루션-가치 블록 작성
- **Unique Value Proposition**: "유일하게 다른 한 가지"를 한 문장으로
  - High-concept pitch: "[유명 서비스]의 [카테고리] 버전" (예: "Uber for X")
- **Solution**: 각 문제에 1:1 대응하는 최소 솔루션
  - 이 단계에서는 기능이 아닌 "결과"에 집중

### Phase 4: 비즈니스 블록 작성
- **Channels**: 고객에게 도달하는 무료/유료 경로
- **Revenue Streams**: 수익 모델 (구독, 거래 수수료, 광고 등)
- **Cost Structure**: 핵심 비용 항목과 고정/변동 구분

### Phase 5: 지표-경쟁우위 블록 작성
- **Key Metrics**: 현재 단계에 맞는 AARRR 핵심 지표
- **Unfair Advantage**: 쉽게 복제 불가능한 것만 (없으면 "없음"이라고 정직하게)
  - 유효한 예: 내부 정보, 전문가 네트워크, 특허, 커뮤니티, 기존 고객
  - 무효한 예: "열정", "기술력", "먼저 시작" (복제 가능)

### Phase 6: 가설 도출
- 린 캔버스에서 가장 리스크가 큰 가설 3개를 도출
- 각 가설의 검증 방법 제안
- 다음 단계 액션 아이템 제시

## Tool Coordination
- **WebSearch**: 경쟁사, 시장 규모, 벤치마크 데이터 수집
- **WebFetch**: 경쟁사 웹사이트, 앱스토어 정보 확인
- **Write**: 린 캔버스 결과를 `.planning/business/lean-canvas.md`에 저장 (표준 경로 — mvp 하네스의 `/mvp-from-startup`이 이 위치를 자동 탐지해 PRD 인테이크로 승계한다. `--output`으로 경로 override 가능)
- **Read**: 기존 캔버스 파일 읽기 (--compare 시)

## Examples

### 기본 사용
```
/lean-canvas 프리랜서 개발자를 위한 프로젝트 매칭 플랫폼
```

### 특정 블록 집중
```
/lean-canvas --focus problem 배달 음식 건강 관리 앱
```

### 피벗 후 비교
```
/lean-canvas --compare B2B SaaS로 피벗한 HR 관리 도구
```

## Boundaries

**Will:**
- 9블록 전체 또는 지정 블록 작성
- 웹 검색 기반 경쟁사/시장 정보 포함
- 가설 도출 및 검증 방법 제안
- 파일로 저장하여 버전 관리 가능

**Will Not:**
- 실제 고객 인터뷰 대행
- 확정적 시장 진입 판단
- 법적/규제 타당성 평가
