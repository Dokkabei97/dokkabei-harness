# 스코어링 · 다중 필드 · 품질 평가 (ES-REL / ES-EVL)

> 적용 전 확인: 대상 인덱스의 샤드 수와 문서 수(작은 인덱스·다수 샤드면 IDF 왜곡이 큼), 필드별 analyzer, 품질 판단 근거(골든셋/클릭 로그 유무).

### ES-REL-01 · IDF 는 샤드 로컬 — 작은 인덱스·테스트 인덱스에서 순위가 샤드 배치에 좌우된다
- 적용: 기본 `query_then_fetch`
- 신호: 개발 환경과 운영의 순위가 다름, 문서를 몇 개 추가했더니 무관 문서 순위 급변, 같은 term 의 `_explain` idf 가 문서마다 다름
- 메커니즘: BM25 통계(docCount, docFreq)는 각 샤드에서 계산된다. 문서가 적으면 샤드 간 통계 편차가 크다
- 처방: 소규모 인덱스는 프라이머리 1개. 정밀 비교가 필요할 때만 `search_type=dfs_query_then_fetch`(추가 라운드트립). `_explain` 은 search_type 을 무시하므로 전역 IDF 는 `_search` + `explain: true` 로 확인
- 반례: 대형 인덱스는 통계가 수렴해 dfs 비용 대비 효과 미미
- 검증: 같은 쿼리를 dfs 유무로 `_rank_eval` 비교
- 근거: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/consistent-scoring.html

### ES-REL-02 · 같은 쿼리라도 프라이머리/레플리카에서 점수가 다르다 — 사용자별 `preference` 로 고정
- 적용: 레플리카 ≥1, 갱신·삭제가 있는 인덱스
- 신호: 새로고침할 때마다 동점 근처 결과 순서가 바뀜(페이지 넘기면 중복/누락)
- 메커니즘: 삭제 문서가 머지되기 전까지 통계에 포함되는데, 머지 시점이 샤드 복사본마다 다르다(LUC-SEG-02). 요청마다 다른 복사본이 응답
- 처방: `preference=<세션ID/사용자ID>` 로 같은 사용자를 같은 복사본으로 라우팅(캐시 재사용 효과도 있음). 정렬에 결정적 tiebreaker 추가
- 반례: `_primary` 같은 고정값은 부하를 한쪽에 몰아 권장하지 않음
- 검증: 같은 쿼리 N회 반복 시 상위 K 순서 일치율
- 근거: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/consistent-scoring.html, https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed

### ES-REL-03 · `cross_fields`/`combined_fields` 는 analyzer 가 같은 필드끼리만 하나로 묶인다
- 적용: 이름+성, 브랜드+상품명처럼 질의어가 여러 필드에 흩어지는 경우
- 신호: `cross_fields` 인데 기대한 "한 필드처럼" 동작이 안 됨 — nori 필드와 keyword/standard 필드를 섞음
- 메커니즘: cross_fields 는 analyzer 별 그룹으로 나눠 그룹 간은 best_fields 처럼 결합. `combined_fields`(BM25F)는 모든 필드가 같은 search analyzer 여야 한다
- 처방: 같은 분석 체인을 공유하는 필드끼리 묶고, 이종 필드는 별도 절(should)로. 필드 수가 많으면 `copy_to` 로 합친 필드 하나에 검색(ES 공식 권장: 검색 필드 수 최소화)
- 반례: 필드별 가중치 차이가 핵심이면 best_fields + tie_breaker 가 단순
- 검증: `_validate/query?rewrite=true` 로 생성된 쿼리 구조 확인
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-multi-match-query, https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-combined-fields-query

### ES-REL-04 · 짧은 필드(상품명·태그)는 길이 정규화가 노이즈 — 필드별 `b` 조정 또는 norms 제거
- 적용: BM25 기본(k1=1.2, b=0.75)
- 신호: 상품명이 짧은 문서가 일관되게 위로(긴 정식 명칭이 불리), 태그 개수가 적은 문서 우대
- 메커니즘: norms 는 필드 길이를 1바이트로 손실 압축해 저장하고, b 가 클수록 짧은 필드를 우대한다
- 처방: 필드별 `similarity` 정의로 `b` 를 낮추거나(예: 0.3), 매칭 여부만 중요한 필드는 `norms: false`. 처음부터 필드별 **이름 붙은 커스텀 similarity** 를 정의해 두면, 그 `b`/`k1` 은 인덱스 설정이라 close → `PUT _settings` → open 으로 재색인 없이 조정할 수 있다(norms 는 필드 길이만 저장하고 b 는 질의 시 적용). 기존 필드에 *다른* similarity 를 바인딩하는 것만 재색인 대상
- 반례: 본문 길이가 다양한 문서 검색은 기본 b 가 유효
- 검증: `_rank_eval` 전후 비교, `_explain` 의 tf 정규화 항
- 근거: https://www.elastic.co/docs/reference/elasticsearch/index-settings/similarity ("updating index settings", close 후 변경), https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/norms — close/open 은 검색 중단이므로 스테이징에서 먼저 확인

### ES-REL-05 · `minimum_should_match` 없는 한국어 `match` 는 OR — 분해된 형태소 하나만 맞아도 나온다
- 적용: nori 분석 필드 + `match`(기본 operator OR)
- 신호: 긴 질의("무선 블루투스 이어폰 노이즈캔슬링")에 한 단어만 맞는 문서가 다수, 무결과율은 낮은데 이탈률 높음
- 메커니즘: 질의가 여러 토큰으로 분해되면 각 토큰이 should 가 된다. decompound 로 토큰 수가 늘면 더 느슨해진다
- 처방: `minimum_should_match: "2<75%"` 같은 조건식, 정확 구문 부스트(rescore phrase), 무결과 시 완화 단계를 애플리케이션에서(질의 완화 캐스케이드)
- 반례: 짧은 질의(1~2 토큰)는 OR 가 재현율에 유리
- 검증: 질의 길이 구간별 nDCG/무결과율
- 근거: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-minimum-should-match

### ES-REL-06 · 다중값 필드 phrase 는 `position_increment_gap`(기본 100) 때문에 값 경계를 넘지 못한다
- 적용: 태그/키워드 배열을 text 로 색인
- 신호: 태그 ["무선", "이어폰"] 문서가 "무선 이어폰" phrase 에 안 맞음(의도한 것인지 확인)
- 메커니즘: 배열 값 사이에 위치 간격 100 을 넣어 값 경계를 넘는 phrase 를 막는다
- 처방: 의도와 맞으면 유지. 경계를 넘어 매칭시키려면 slop 가 아니라 값들을 하나의 문자열로 합친 필드를 별도로 둔다
- 반례: 값 경계 매칭은 대개 오탐 — 기본값이 안전
- 검증: `_analyze` 다중값 입력의 position
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/position-increment-gap

### ES-EVL-01 · `_rank_eval` 에서 라벨 없는 문서는 기본으로 무관 처리 — 골든셋 커버리지를 함께 본다
- 적용: `_rank_eval`(precision/recall/MRR/DCG/ERR)
- 신호: 랭킹을 바꿨더니 지표가 떨어졌는데 실제로는 라벨 안 된 좋은 문서가 올라온 경우
- 메커니즘: 판정되지 않은 문서는 관련 없음으로 계산된다. 응답의 `unrated_docs` 가 커버리지 신호
- 처방: 변경 후 상위 K 의 unrated 문서를 추가 판정하는 루프, `precision` 은 `ignore_unlabeled: true` 옵션 검토
- 반례: 라벨이 충분한 소규모 질의셋
- 검증: 응답 `details.<query>.unrated_docs` 수
- 근거: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/search-rank-eval

### ES-EVL-02 · 클릭률은 위치 편향의 함수 — 순위 변경 효과를 CTR 로 직접 비교하지 않는다
- 적용: 온라인 지표로 랭킹 개선을 판단하는 경우
- 신호: "1위 클릭률이 높으니 1위가 좋은 문서" 식 학습 데이터, A/B 에서 상위 노출 변화와 CTR 혼동
- 메커니즘: 사용자는 관련성과 무관하게 상위를 더 클릭한다. 학습(LTR)·평가 모두 편향 보정 없이는 기존 랭킹을 강화
- 처방: 평가는 A/B 또는 interleaving, 학습 데이터는 위치별 클릭 모델(예: position-based model)로 보정하거나 무작위화 구간 확보. 쿼리 그룹(헤드/토르소/테일)별로 분리 보고
- 반례: 없음
- 검증: 위치별 CTR 곡선, interleaving 승률
- 근거: https://www.cs.cornell.edu/people/tj/publications/joachims_etal_05a.pdf (Accurately Interpreting Clickthrough Data)
