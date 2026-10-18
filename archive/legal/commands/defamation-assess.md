---
name: defamation-assess
description: |
  명예훼손·모욕 리스크 평가. 구성요건 성립 가능성을 분석하고 피해자/피의자 관점별 대응 옵션을 제시한다. 형사 사안은 변호사 선임을 강하게 권고한다.
  Assesses defamation and insult risk under Korean criminal law: analyzes whether statutory elements are met and lays out response options from both victim and accused perspectives, strongly recommending a lawyer for criminal matters. Use when: defamation or insult exposure check, cyber defamation over posts/reviews/comments, deciding how to respond as victim or accused.
category: legal
complexity: advanced
---

# /defamation-assess - 명예훼손·모욕 리스크 평가

## Triggers
- 명예훼손·모욕·사이버 명예훼손의 성립/대응을 평가하고 싶을 때
- 악성 댓글·허위사실 유포 피해 또는 자신의 표현에 대한 리스크 점검
- "명예훼손 되나?", "고소 가능?", "이거 모욕죄야?"

## Usage
```
/defamation-assess [상황 설명: 표현 내용·전파 범위·당사자]

Options:
  --role 피해자|피의자   의뢰인 입장(기본: 피해자)
  --channel online|offline  표현 매체(온라인이면 정통망법 §70 검토)
  --truth 사실|허위|불명  적시 내용의 진위
```

## Behavioral Flow

### Phase 1: 입장·사실관계 확정
- 의뢰인이 피해자/피의자인지 명확히 구분
- 표현 내용·시점·공연성·전파 범위·특정성 확정
- 친고죄/반의사불벌죄·시효 확인

### Phase 2: 구성요건 분석
- `dispute-risk-counsel` 에이전트에 위임 또는 직접 분석
- 명예훼손(형법 §307, 정통망법 §70): 공연성·사실/허위·특정성·비방목적
- 모욕(§311): 공연성 + 경멸적 가치판단
- 위법성조각(§310 공공의 이익) 검토

### Phase 3: 성립 가능성·대응 옵션
- 성립 가능성(높음/중간/낮음/불명확)과 예상 처벌 수준
- **피해자**: 증거 보전(캡처·URL·해시), 고소·삭제요청·민사 손배
- **피의자**: 삭제·정정·사과·합의(반의사불벌죄)

### Phase 4: 에스컬레이션
- 형사 입건·수사·진술 리스크가 있으면 **변호사 선임 필수** 강조
- 시간 민감 조치(증거 보전·확산 차단) 우선 표시

## Tool Coordination
- **Agent**: dispute-risk-counsel 위임
- **WebSearch**: 명예훼손·모욕 관련 최신 판례 확인
- **Write**: 평가 보고서 및 증거 보전 체크리스트 생성

## Examples

### 피해자 입장(온라인)
```
/defamation-assess --role 피해자 --channel online 커뮤니티에 허위사실 게시글 확산
```

### 피의자 입장(리스크 점검)
```
/defamation-assess --role 피의자 --truth 사실 리뷰에 실명 비판글 작성했는데 고소당함
```

## Boundaries

**Will:**
- 구성요건 분석 및 성립 가능성 평가
- 입장별 대응 옵션·증거 보전 안내

**Will Not:**
- 유무죄·처벌 수위 확정 단정
- 고소장 제출·수사 진술 대행
- 허위 고소·증거 인멸·2차 가해를 돕는 안내
- **형사 사안 — 변호사 선임을 대체하지 않음**
