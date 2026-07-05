---
name: market-research
description: |
  시장조사 리포트 생성. TAM/SAM/SOM 산정, 경쟁사 분석, 고객 세그먼트 분석을 포함한다.
  Generates a market research report including TAM/SAM/SOM sizing, competitor analysis, and customer segment analysis. Use when: researching a market, estimating TAM/SAM/SOM, analyzing competitors or customer segments, or preparing market data for an investor deck.
category: research
complexity: advanced
---

# /market-research - 시장조사 리포트

## Triggers
- 새로운 시장에 진입하기 전 조사가 필요할 때
- 투자 유치를 위한 시장 데이터가 필요할 때
- "시장조사해줘", "시장 규모 알려줘", "경쟁사 분석해줘"

## Usage
```
/market-research [산업/제품 설명]

Options:
  --scope full|sizing|competition|customer  조사 범위 (기본: full)
  --region kr|us|global                      지역 범위 (기본: kr)
  --depth quick|standard|deep               조사 깊이 (기본: standard)
  --output [파일경로]                         리포트 저장 경로 (기본: .planning/business/market-research.md)
```

## Behavioral Flow

### Phase 1: 산업 스코핑
- 사용자 입력에서 타겟 산업/시장을 식별
- 산업 분류 체계 결정 (KSIC, NAICS 참조)
- 조사 범위와 깊이를 확인

### Phase 2: 데이터 수집
- WebSearch로 산업 리포트, 시장 데이터, 뉴스 수집
- 공개 데이터 소스 탐색 (통계청, KOSIS, IR 자료)
- 경쟁사 웹사이트, 앱스토어, 채용 공고 분석
- 투자/M&A 동향 조사

### Phase 3: 시장 규모 산정
- Top-Down과 Bottom-Up 양 방향으로 산출
- TAM → SAM → SOM 계층 구조 작성
- 산출 근거와 가정을 명시
- CAGR(연평균 성장률) 추정

### Phase 4: 경쟁 분석
- 직접/간접 경쟁사 목록 작성 (최소 5개)
- 경쟁사별 강점, 약점, 차별점 분석
- 가격 비교표 작성
- 2×2 포지셔닝 맵 설계

### Phase 5: 고객 분석
- 고객 세그먼트 정의 (3~5개)
- 세그먼트별 규모, 성장률, 접근성 평가
- 얼리어답터 세그먼트 식별
- 대표 페르소나 1~2개 작성

### Phase 6: 리포트 생성
- 구조화된 마크다운 리포트 작성
- 데이터 출처와 신뢰도 표기
- 전략적 시사점 및 Go/No-Go 판단 근거
- 지정 경로에 파일 저장

## Tool Coordination
- **WebSearch**: 시장 데이터, 경쟁사 정보, 산업 리포트 검색
- **WebFetch**: 구체적 웹페이지 데이터 수집
- **Write**: 리포트를 `.planning/business/market-research.md`에 저장 (표준 경로, `--output`으로 override — mvp 하네스 인테이크에서 시장 컨텍스트로 참조)
- **Bash**: 데이터 정리/계산 스크립트 실행
- **Read**: 기존 조사 결과 참조 (`.planning/business/` 하위)

## Examples

### 전체 조사
```
/market-research 국내 반려동물 건강관리 앱 시장
```

### 경쟁사 집중 분석
```
/market-research --scope competition 온라인 코딩 교육 플랫폼
```

### 글로벌 시장 빠른 조사
```
/market-research --region global --depth quick AI 코드 리뷰 도구
```

## Boundaries

**Will:**
- 공개 데이터 기반 시장 규모 산정
- 경쟁사 공개 정보 분석
- 정량적 근거가 있는 추정치 제시
- 데이터 출처 명시

**Will Not:**
- 유료 리서치 보고서 접근
- 비공개 기업 데이터 수집
- 법률/규제 전문 자문
- 확정적 투자 의사결정 대행
