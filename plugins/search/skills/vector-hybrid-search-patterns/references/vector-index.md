# 벡터 인덱스 · 메모리 · 양자화 (VEC-MEM / VEC-IDX)

> 적용 전 확인: ES 버전(기본 `index_options` 가 버전마다 다름), 라이선스, `dense_vector` 매핑 원문, 벡터 수·차원·레플리카 수, 노드 RAM 과 힙. 기본값을 단정하지 말고 `GET idx/_mapping` + `include_defaults` 로 실제 값을 본다.

### VEC-MEM-01 · HNSW 는 "벡터 + 그래프" 가 페이지 캐시에 들어가야 빠르다 — 공식 산식으로 레플리카 포함 계산
- 적용: `dense_vector` + HNSW 계열 index_options
- 신호: 벡터 검색 p99 가 수십~수백 ms 로 들쭉날쭉, 디스크 read IOPS 상승, 힙은 한가함
- 메커니즘: 샤드 복사본마다 전체 사본을 갖는다. 벡터당 RAM: float = dims×4. 양자화 산식은 문서 버전마다 다르다 — 9.x 문서: int8 = dims+16, int4 = ⌈dims/2⌉+16, bbq = ⌈dims/64⌉×8+14 / 8.x 문서: int8 = dims+4, int4 = dims/2+4, bbq = dims/8+14 바이트. 사용 중인 버전의 문서 산식을 쓸 것. 그래프 = 벡터 수×4×m(기본 m=16) 바이트. 양자화 인덱스는 원본 float 은 디스크(재점수용)에 두고 양자화 사본+그래프만 RAM 필요. 작업 집합이 캐시를 넘으면 지연이 급증
- 처방: (양자화 사본 + 그래프) × (1 + 레플리카) 를 데이터 노드의 "힙 제외 메모리" 에 맞춘다. 예: 1M×1024d int8 ≈ 1.04GB + 64MB(그래프). 텍스트 필드의 캐시 몫도 남긴다
- 반례: 벡터 수가 작아 전부 캐시에 들어가면 양자화 이득보다 재현율 손실이 클 수 있다
- 검증: 노드 OS page cache 사용량, major faults, `_disk_usage` 의 벡터 필드 크기
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search

### VEC-IDX-01 · 기본 `index_options` 는 버전마다 다르다 — 8.14+ float 은 `int8_hnsw`, 9.1+ 은 384차원 이상이면 `bbq_hnsw`
- 적용: element_type float. byte/bit 은 모든 버전 `hnsw`(무양자화). Serverless/최신 9.x 는 `bbq_disk` 가 기본일 수 있음(문서 확인)
- 신호: 매핑에 index_options 미지정 → 버전 업그레이드 후 새 인덱스의 재현율/메모리 특성이 바뀜
- 메커니즘: 기본값 변경은 "새 필드" 에만 적용 — 같은 템플릿이라도 클러스터 버전에 따라 다른 인덱스가 생긴다
- 처방: 운영 템플릿은 `index_options.type` 을 명시하고, 변경은 재색인 + 재현율 측정과 함께
- 반례: 없음 — 명시가 항상 안전
- 검증: `GET idx/_mapping?include_defaults=true`
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector, https://www.elastic.co/guide/en/elasticsearch/reference/8.14/release-notes-8.14.0.html

### VEC-IDX-02 · 양자화(int8/int4/BBQ)는 oversample + rescore 와 세트 — 재현율은 측정으로 회복
- 적용: `int8_hnsw`/`int4_hnsw`/`bbq_hnsw`. `rescore_vector` 는 8.18/9.0 에 실험적(experimental)으로 도입, 이후 GA — 사용 버전 문서의 상태 배지 확인
- 신호: 양자화 전환 후 recall@10 하락, 특히 bbq
- 메커니즘: 양자화 거리로 후보를 찾고, 원본 float 으로 상위 후보를 재점수하면 정확도를 대부분 회복. 메모리 절감: int8 4배, int4 8배, bbq 32배
- 처방: `rescore_vector.oversample`(매핑 또는 쿼리)로 k×oversample 후보를 원본 재점수. `rescore_vector` 미지원 버전(8.18 이전)은 kNN + `rescore`(script_score 로 원본 벡터 재점수)로 동등 구현. oversample 은 지연과 trade-off
- 반례: byte/bit 벡터는 이미 양자화 형식이라 해당 없음
- 검증: 브루트포스(exact, script_score) 결과를 정답으로 recall@k 측정
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector, https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-knn-query, https://github.com/elastic/elasticsearch-specification/pull/3560 (rescore_vector `since 8.18.0`, experimental)

### VEC-IDX-03 · 세그먼트마다 HNSW 그래프 — 세그먼트 수가 곧 검색 비용, 머지는 그래프 재구축 비용
- 적용: 갱신이 잦은 벡터 인덱스, 대량 재임베딩
- 신호: 적재 직후 kNN 지연이 높다가 머지 후 개선, 색인 중 CPU 지속 포화
- 메커니즘: kNN 은 세그먼트별 그래프를 각각 탐색해 합친다. 머지는 그래프를 다시 만든다(비쌈). 색인과 검색이 같은 노드에서 경쟁
- 처방: 대량 적재는 ES-IDX-02 + 큰 초기 세그먼트(LUC-SEG-04, `max_merged_segment` 10~20GB 검토). 전면 재임베딩은 in-place update 대신 새 인덱스 재색인 + alias 스왑. 읽기 전용이 된 인덱스만 force merge
- 반례: 소량 실시간 갱신 인덱스는 기본 머지로 충분
- 검증: `_cat/segments` 수 vs kNN 지연 상관
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search

### VEC-IDX-04 · `_source` 에서 벡터 제외 — 9.2+ 는 `index.mapping.exclude_source_vectors`(신규 인덱스 기본 on), `excludes` 는 재색인을 깨뜨린다
- 적용: 9.2+ 신규 인덱스는 기본 제외(생성 시에만 설정 가능). 8.x 는 수동 처리 필요
- 신호: 검색 응답이 수 MB(벡터 포함), fetch 단계 지연, 디스크가 예상의 수 배
- 메커니즘: 벡터를 `_source` JSON 에 그대로 두면 저장·전송 비용이 크다. `exclude_source_vectors` 는 reindex/update/recovery 때 벡터를 재수화한다. 일반 `_source.excludes` 는 재수화가 없어 reindex·update 후 벡터 소실(ES-ING-05)
- 처방: 9.2+ 는 기본값 유지 확인. 8.x 는 synthetic `_source`(라이선스 확인) 또는 요청 시 `_source` 필터링 + 원본 재적재 경로 확보
- 반례: 벡터를 응답으로 받아야 하는 디버깅 경로는 명시 요청
- 검증: `GET idx/_settings?include_defaults=true&filter_path=**.exclude_source_vectors`, 응답 크기
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector, https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search

### VEC-IDX-05 · `dot_product` 는 단위 벡터 전제 — 정규화가 확실하지 않으면 `cosine`
- 적용: float 벡터 similarity 선택
- 신호: 모델 문서는 cosine 인데 매핑은 dot_product, 색인 에러 또는 점수 분포 이상
- 메커니즘: float + dot_product 는 모든 벡터가 단위 길이여야 한다. 모델/파이프라인이 정규화를 보장하지 않으면 랭킹이 왜곡되거나 색인이 거부된다
- 처방: 임베딩 파이프라인에서 L2 정규화를 명시하고 테스트로 보장한 경우에만 dot_product. 아니면 cosine
- 반례: 정규화가 보장되면 dot_product 가 연산상 유리
- 검증: 샘플 벡터 노름 분포, 색인 에러 로그
- 근거: https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector

### VEC-IDX-06 · 필요한 것만 preload — `.vec`(원본 float) 은 preload 하지 않는다
- 적용: `index.store.preload` 로 벡터 파일을 미리 올리는 경우
- 신호: preload 후 오히려 지연 증가
- 메커니즘: 양자화 HNSW 는 `.veq`/`.veb`(양자화 벡터) + `.vex`(그래프)가 핵심. 원본 `.vec` 까지 올리면 캐시가 원본에 밀려 핵심 구조가 축출
- 처방: 양자화 인덱스는 `.veq`(또는 `.veb`) + `.vex` 만, DiskBBQ 는 해당 문서 파일만. RAM 이 부족하면 preload 자체를 하지 않는다
- 반례: 무양자화 float HNSW 는 원본이 곧 검색 대상
- 검증: preload 전후 p99
- 근거: https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/approximate-knn-search
