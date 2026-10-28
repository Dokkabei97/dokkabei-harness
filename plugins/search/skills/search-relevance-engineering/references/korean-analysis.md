# 한국어 분석 · 동의어 · 자동완성 (KO-ANA / KO-SYN / KO-AC)

> 적용 전 확인: 실제 분석기 정의(`GET idx/_settings?filter_path=**.analysis`), index analyzer 와 search analyzer 가 다른지, 사용자 사전이 파일인지 inline(`user_dictionary_rules`)인지, 동의어가 파일·inline·Synonyms API 중 무엇인지. 판단은 항상 `_analyze` 실측으로.

### KO-ANA-01 · nori `decompound_mode` 기본은 `discard` — 원형이 사라진다
- 적용: `analysis-nori` 플러그인(`none`/`discard`/`mixed`)
- 신호: "삼성전자" 로 검색했는데 "삼성"·"전자" 가 따로 들어간 무관 문서가 상위, 또는 복합어 정확 일치 부스트가 안 걸림
- 메커니즘: discard 는 사전/형태소로 분해 가능한 복합어를 구성요소로만 남긴다. mixed 는 원형+구성요소를 함께 내며 원형이 여러 위치를 덮는(positionLength>1) 토큰 그래프가 된다. 사전에 없는 합성어는 애초에 분해되지 않는다
- 처방: 흔한 구성 — 색인은 `mixed`(원형·부분 둘 다 색인), 검색은 `discard` 또는 `none`(질의 그래프 단순화)으로 분리하고 원형 정확 일치는 별도 서브필드(`none`) + 부스트. 반드시 `_analyze` 로 대표 질의 토큰을 확인
- 반례: 부분어 재현율이 핵심인 도메인(법률 조문 등)은 검색에도 mixed 가 나을 수 있음 — `_rank_eval` 로 결정
- 검증: `POST idx/_analyze {"analyzer":"...","text":"삼성전자","explain":true}` 에서 positionLength, `_validate/query?rewrite=true`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-tokenizer

### KO-ANA-02 · 품사 필터(`nori_part_of_speech`)로 조사를 지우면 위치 간격이 남는다 — phrase 에는 slop 필요
- 적용: 기본 stoptags(조사·어미 등)를 쓰는 nori 분석기 + `match_phrase`
- 신호: "서울 맛집" 구문 검색이 "서울의 맛집" 문서를 못 찾음, 또는 그 반대
- 메커니즘: Lucene 의 필터링 토큰 필터는 제거된 토큰의 position increment 를 보존한다 → 원문에 조사가 있었는지에 따라 위치 간격이 달라 slop 0 phrase 가 불일치
- 처방: 한국어 phrase 는 `slop: 1~2` 로 시작, 근접 부스트는 rescore 의 `match_phrase`(slop 포함)로
- 반례: 고유명사 정확 구문(제품 모델명)은 keyword/`none` 서브필드로 따로 처리
- 검증: `_analyze` 출력의 position 값 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-speech, https://lucene.apache.org/core/9_0_0/core/org/apache/lucene/analysis/FilteringTokenFilter.html

### KO-ANA-03 · nori 사용자 사전은 리로드되지 않는다 — 색인 분석기에 쓰면 재색인까지
- 적용: `user_dictionary`(config 경로 파일) / `user_dictionary_rules`(inline)
- 신호: 사전에 신조어·브랜드명을 추가했는데 반영 안 됨, 노드마다 결과 다름(파일 배포 누락)
- 메커니즘: 토크나이저는 분석기 생성 시 사전을 읽는다. `_reload_search_analyzers` 는 `updateable` 토큰 필터(동의어)만 다시 읽는다. 색인 시점 토큰은 이미 세그먼트에 고정
- 처방: 사전 변경 = 새 인덱스(사전 반영) + 재색인 + alias 스왑(ES-MAP-13). 파일 방식이면 모든 노드에 동일 배포, inline 방식은 설정과 함께 버전 관리. 중복 항목은 기본 에러(`lenient: false`)
- 반례: 검색 분석기에만 쓰는 사전은 인덱스 close/open 으로 반영 가능하나 색인 토큰과 어긋날 위험 — 대개 권장하지 않음
- 검증: 변경 후 `_analyze` 와 `_termvectors`(기존 문서) 비교
- 근거: https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-tokenizer, https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-reload-search-analyzers

### KO-ANA-04 · `discard_punctuation` 기본 true — 모델명·버전 문자열이 쪼개진다
- 적용: 제품 모델명(`SM-S928N`), 버전(`3.5`), 소수 금액이 있는 도메인
- 신호: 모델명 검색 정확도 낮음, 숫자 단위 검색 실패
- 메커니즘: 구두점이 버려지면서 토큰 경계가 바뀐다. 한글 숫자 정규화 필터 `nori_number` 는 소수점 등을 처리하려면 `discard_punctuation: false` 가 필요하다
- 처방: 모델명은 별도 keyword/`lowercase` normalizer 서브필드 + edge_ngram. 한글 수사(십만, 이천) 정규화가 필요하면 `nori_number` + `discard_punctuation: false` 조합을 `_analyze` 로 검증
- 반례: 일반 본문은 기본값이 더 깔끔
- 검증: `_analyze` 로 대표 모델명·금액 문자열
- 근거: https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-tokenizer, https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-number

### KO-ANA-05 · 커스텀 analyzer 로 `nori_tokenizer` 를 쓰면 `nori_readingform`·`lowercase` 를 직접 넣어야 한다
- 적용: `nori_tokenizer` 기반 **커스텀** analyzer(사용자 사전·decompound 설정 때문에 대부분 커스텀). 내장 `nori` analyzer 는 이미 `nori_part_of_speech`·`nori_readingform`·`lowercase` 를 포함. 한자 병기 문서(뉴스·법률), 영문 브랜드 혼용
- 신호: "大韓民國" 문서가 "대한민국" 검색에 안 나옴, "iPhone" vs "iphone" 불일치
- 메커니즘: `nori_tokenizer` 자체는 한자를 한글 독음으로 바꾸지 않고 대소문자를 정규화하지 않는다 — 내장 analyzer 를 커스텀으로 옮기면서 이 필터들이 빠지기 쉽다
- 처방: 필터 순서 예: `nori_tokenizer` → `nori_part_of_speech` → `nori_readingform` → `lowercase` → (검색 분석기에만) `synonym_graph`. 동의어 규칙은 이 체인을 통과한 형태로 작성(KO-SYN-02)
- 반례: 한자 원문 구분이 필요한 검색은 원문 서브필드 유지
- 검증: `_analyze`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-readingform, https://www.elastic.co/docs/reference/elasticsearch/plugins/analysis-nori-analyzer

### KO-SYN-01 · `synonym_graph` 는 검색 분석기 전용 — 다중어 동의어를 색인 시점에 쓰면 위치가 깨진다
- 적용: 다중 토큰 동의어("노트북, 랩탑 컴퓨터")
- 신호: 색인 분석기에 synonym_graph, phrase 쿼리가 엉뚱하게 매칭
- 메커니즘: 인덱스는 토큰 그래프(positionLength)를 저장하지 못해 평탄화된다. 검색 시점에는 쿼리 파서가 그래프를 해석해 올바른 phrase/불리언을 만든다(`auto_generate_synonyms_phrase_query` 기본 true)
- 처방: 동의어는 search_analyzer 의 `synonym_graph` 로, `updateable: true` 로 두면 재색인 없이 반영. 색인 시점 확장이 꼭 필요하면 단일어만 `synonym`
- 반례: 검색 시점 동의어는 IDF 가 원어/동의어별로 달라 점수가 흔들릴 수 있다 — 대등 동의어는 `expand` 와 부스트로 조정
- 검증: `_validate/query?rewrite=true` 로 생성된 쿼리 확인
- 근거: https://www.elastic.co/docs/reference/text-analysis/analysis-synonym-graph-tokenfilter

### KO-SYN-02 · 동의어 규칙 자체가 앞단 토크나이저로 분석된다 — nori 가 규칙 문자열을 쪼갠다
- 적용: nori 뒤의 synonym(_graph) 필터
- 신호: 동의어가 일부만 동작, 규칙 로딩 에러, 복합어 규칙이 의도와 다른 다중 토큰 규칙으로 변함
- 메커니즘: 규칙의 각 항목은 해당 필터 앞까지의 분석 체인으로 토큰화된다. decompound 로 같은 위치에 여러 토큰이 나오는 체인은 동의어 파싱과 충돌할 수 있고, Lucene `SynonymGraphFilter` 는 입력 그래프를 소비하지 못한다
- 처방: 동의어를 거는 검색 분석기는 `decompound_mode: discard`/`none` 처럼 단일 경로를 내는 설정으로. 규칙은 `_analyze` 로 각 항목의 토큰을 확인한 형태로 작성. 다중 토큰을 내는 필터와 섞어야 하면 `multiplexer` 분기
- 반례: 없음
- 검증: 규칙의 각 항목을 `_analyze`(해당 분석기의 tokenizer+앞단 filter) 로 확인, 인덱스 open 시 에러 로그
- 근거: https://www.elastic.co/docs/reference/text-analysis/analysis-synonym-graph-tokenfilter, https://lucene.apache.org/core/9_0_0/analysis/common/org/apache/lucene/analysis/synonym/SynonymGraphFilter.html

### KO-SYN-03 · Synonyms API 세트는 인덱스보다 먼저 존재해야 하고, `lenient: false` 의 잘못된 규칙은 인덱스를 못 열게 한다
- 적용: `synonyms_set` 참조(Synonyms Management API)
- 신호: 세트 삭제/오타 후 인덱스가 red/열리지 않음, 동의어 갱신 후 리로드 실패
- 메커니즘: 세트가 없으면 인덱스가 동작 불능. lenient 기본값은 `updateable` 값을 따르며 false 면 파싱 불가 규칙이 리로드·reopen 을 막는다
- 처방: 세트 생성 → 인덱스 생성 순서 고정(마이그레이션 스크립트), 운영 갱신 경로는 `updateable: true` + 리뷰된 규칙만. 세트 삭제 전 참조 인덱스 확인
- 반례: 없음
- 검증: 스테이징에서 규칙 변경 → `_analyze` → 인덱스 상태
- 근거: https://www.elastic.co/docs/reference/text-analysis/analysis-synonym-graph-tokenfilter

### KO-AC-01 · 한글 자동완성은 음절 edge_ngram 만으로 부족 — 입력 중 자모("검ㅅ")를 처리하려면 자모 분해 필드
- 적용: 검색창 실시간 자동완성
- 신호: 마지막 글자 조합 중인 입력에서 제안이 사라졌다 나타남, 초성 검색("ㅅㅁㅈ") 요구
- 메커니즘: IME 조합 중 입력은 완성 음절이 아니라 자모로 들어온다. 음절 단위 n-gram 은 "검ㅅ" 을 "검색" 의 접두로 보지 못한다
- 처방: 색인 시(애플리케이션 또는 커스텀 분석 플러그인) 자모 분해·초성 추출 문자열을 별도 필드로 저장해 edge_ngram, 질의도 같은 변환 후 조회. 표시용 원문 필드와 분리
- 반례: 서버 왕복을 조합 완료 시점에만 하는 UI 라면 음절 단위로 충분
- 검증: 조합 중 입력 시퀀스("ㄱ","거","검","검ㅅ","검새","검색")별 결과 테스트
- 근거: https://www.elastic.co/docs/reference/text-analysis/analysis-edgengram-tokenizer (edge_ngram), https://www.unicode.org/charts/PDF/U1100.pdf (한글 자모 블록)

### KO-AC-02 · edge_ngram 은 색인 분석기에만 — 검색 분석기까지 n-gram 하면 무관 결과 폭증
- 적용: `edge_ngram`/`search_as_you_type` 자동완성 필드
- 신호: "삼" 입력에 "삼성"과 무관한 "삼"으로 시작하는 n-gram 이 대량 매칭, 점수 의미 없음
- 메커니즘: 질의도 n-gram 되면 질의의 짧은 접두 토큰들이 모두 OR 매칭된다
- 처방: `search_analyzer` 는 n-gram 없이(토크나이저+lowercase). `max_gram` 은 실제 입력 길이에 맞춰 제한(디스크 비례). 대안으로 `search_as_you_type` 필드 + `bool_prefix` multi_match
- 반례: 중간 일치가 필요하면 ngram(edge 아님) 이지만 디스크 비용 큼(ES-MAP-10 참고)
- 검증: `_analyze` 로 색인/검색 토큰 각각 확인, `_disk_usage`
- 근거: https://www.elastic.co/docs/reference/text-analysis/analysis-edgengram-tokenizer, https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/search-as-you-type
