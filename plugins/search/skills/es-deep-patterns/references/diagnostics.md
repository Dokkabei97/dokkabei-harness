# 증상 기반 진단 (diagnostics)

> 추측하지 말고 측정한다 — 증상에서 진단 API 시퀀스로. 원래 `search-diagnostics` 스킬(2026-10 허브로 병합). 각 단계에서 의심 항목이 나오면 해당 ID 파일로 이동.

## 증상→도구 마스터 테이블

| 증상 | 1차 진입 도구 | 다음 단계 시퀀스 | 깊은 참조 |
|------|--------------|----------------|----------|
| **timeout / 느림** | `_profile` (`profile:true`) — 5섹션 1차 절단(query·collector·aggregations·fetch, '가장 느린 단일 샤드' 기준) | 주범 단계 정밀 breakdown(query 9필드 / agg 6필드 / fetch load_source·load_stored_fields) → took vs Σ`time_in_nanos` 갭 → [단계 밖] hot_threads + `_tasks` + thread_pool/search + breaker | LUC-EXE-01 / ES-JVM-04·05 |
| **무결과 / 문서 누락** | `_explain/{id}` (`matched:false`? filter 제거 재호출로 filter vs query 이분) | `_validate/query?rewrite=true&all_shards=true`(파싱된 Lucene term) → `_analyze`(search_analyzer 명시) → `_termvectors/{id}`(색인된 실제 토큰); _analyze ∩ _termvectors = ∅ 이면 분석기 불일치 확정 → [일치하는데 0건] `_field_caps`(searchable:false / type conflict) | KO-ANA-* (search-relevance-engineering) / ES-MAP-13 |
| **오정렬 / 순위·스코어 이상** | `_explain/{id}` (BM25 / function_score 트리) | `_search` `explain:true`(상위 hit 좌우 비교; ★dfs 전역 IDF·rescore 점수는 여기서만) → `_termvectors` `term_statistics:true`(doc_freq를 _explain idf의 n과 교차) → min_score/from·size(`track_total_hits:true`) 컷 배제 → `_rank_eval`(골든셋 nDCG/MRR) | ES-REL-01·02 (search-relevance-engineering) |
| **불안정 latency** | `_nodes/hot_threads?type=cpu` (여러 번 스냅샷) | thread_pool/search?v(active/queue/rejected) → breaker(data too big tripped, 증가율) → [첫 쿼리만 느림] global ordinals lazy → eager_global_ordinals 검토 → [페이지마다 변동] PIT(`_pit`)+search_after → [벤치마크 변동] `_cache/clear?request=true` 후 재측정 | ES-AGG-02 / ES-QRY-06 |

## timeout / 느림

```
_profile(profile:true)
  └─ 5섹션 1차 절단: query vs collector vs aggregations vs fetch
     기준 = '가장 느린 단일 샤드' (평균 아님)
       │
       ├─ query가 주범 → query breakdown 9필드
       ├─ aggregations 주범 → agg breakdown 6필드
       └─ fetch 주범 → fetch breakdown(load_source / load_stored_fields)
       │
       └─ took vs Σtime_in_nanos 갭 확인
            took >> 합  →  '단계 밖' (coordinating 머지·네트워크·rewrite·global ordinals)
              └─ _nodes/hot_threads + _tasks + _cat/thread_pool/search + _nodes/stats/breaker
```

**함정**
- `profile`은 **shard-level만** 측정한다 — coordinating 머지·네트워크·rewrite·global ordinals는 누락/과소계상. 그래서 took(전체) >> Σtime_in_nanos(샤드 합) 갭이 '단계 밖' 신호다.
- profiling은 WAND/block-max 등 Lucene 최적화를 비활성화 → 절대 nanos가 부풀려진다. **단계 간 상대 비교 전용**이며 프로덕션 기본 활성 금지('non-negligible overhead' 공식).
- collector time은 query time과 시간대가 중복되므로 **합산 금지**.

자세히: profile 해석 원칙은 LUC-EXE-01, 단계 밖 지표(스레드풀·브레이커)는 ES-JVM-04/05, 클라이언트 측 대기(커넥션 풀)는 ES-CLI-02.

## 무결과 / 문서 누락

```
_explain/{id}
  └─ matched:false?
       └─ filter 제거하고 재호출  →  filter vs query 이분
            │
            └─ _validate/query?rewrite=true&all_shards=true   (파싱된 Lucene term 문자열)
                 │
                 └─ _analyze (search_analyzer 명시, 쿼리 토큰)  ┐
                 └─ _termvectors/{id} (색인된 실제 토큰)        ┘
                      │
                      ├─ _analyze ∩ _termvectors = ∅  →  분석기 불일치 확정
                      │    ※ term_vector 미저장 필드(기본)면 _termvectors 는 _source 를 '현재' 분석기로 재분석한다
                      │      → 교집합이 있어도 "색인 당시 분석기 ≠ 현재 분석기"(사전·동의어 변경 후 미재색인)를 부정할 수 없다
                      │      → 저장된 term vector 필드 또는 새 인덱스 reindex 후 비교로 교차검증(아래 함정 모음, ES-MAP-13)
                      └─ 토큰 일치하는데 0건  →  _field_caps (searchable:false / 멀티인덱스 type conflict)
```

**함정**
- `_validate/query`에서 Lucene term을 보려면 `rewrite=true`이며 `all_shards=true`가 **필수**다 — 미지정 시 단일 랜덤 샤드라 비결정적. (`explain=true`는 '에러 시 상세'용, 역할이 다르다.)
- nori `decompound_mode` 기본은 `discard`(분해만, 원형 폐기). '미분해=설정오류'로 단정 말고 `_analyze`로 실측하라 — nori는 형태소·user_dictionary로 인식 가능한 합성어만 분해한다.

자세히: nori 토큰 mismatch·search_analyzer 는 search-relevance-engineering 의 KO-ANA-*, 분석기 변경 후 미재색인은 ES-MAP-13, `ignore_above` 초과 값 누락은 ES-MAP-02.

## 오정렬 / 순위·스코어 이상

```
_explain/{id}          (BM25 / function_score 트리 해부)
  │
  └─ _search explain:true  (상위 hit 좌우 비교)
       ★ dfs 전역 IDF·rescore 반영 점수는 여기서만 본다
       │
       └─ _termvectors term_statistics:true
            doc_freq를 _explain idf의 n과 교차 검증
            │
            └─ min_score / from·size (track_total_hits:true)로 컷 배제
                 │
                 └─ _rank_eval (골든셋 nDCG / MRR로 회귀 정량화)
```

**함정**
- `_explain`은 **search_type을 무시한다**(issue#2612) — `dfs_query_then_fetch`를 줘도 per-shard IDF만 반영한다. **전역 IDF·rescore 점수는 `_search explain:true`로만** 확인된다.
- `_termvectors`의 `doc_freq`/`ttf`는 `_explain` idf 식의 `n`과 동일 출처다 — 교차하면 스코어 괴리의 통계 원인을 짚을 수 있다.

자세히: 샤드 로컬 IDF·레플리카 간 점수 흔들림은 search-relevance-engineering 의 ES-REL-01/02.

## 불안정 latency

```
_nodes/hot_threads?type=cpu   (여러 번 스냅샷 — 단발 금지)
  │
  └─ _cat/thread_pool/search?v   (active / queue / rejected)
       │
       └─ _nodes/stats/breaker   (data too big tripped, 증가율)
            │
            ├─ [첫 쿼리만 느림]     → global ordinals lazy 빌드 의심 → eager_global_ordinals 검토
            ├─ [페이지마다 결과 변동] → PIT(_pit) + search_after
            └─ [벤치마크 변동]       → _cache/clear?request=true 후 재측정
```

**함정**
- global ordinals는 `eager_global_ordinals=true`면 refresh-time으로 이동해 **profile에 완전 부재**, lazy(기본)면 첫 쿼리 collect에 과소계상되어 **took 갭**으로 드러난다 = '첫 쿼리만 느림' 신호.
- `terminate_after` → 응답 `terminated_early`(boolean), `timeout` → 응답 `timed_out`(boolean)은 **별개 필드**다. terminate_after는 샤드별·세그먼트 across 미보장, timeout은 best-effort.

자세히: global ordinals 는 ES-AGG-02, PIT 는 ES-QRY-06, 쿼리 캐시 조건은 ES-QRY-01.

## 도구 빠른 레퍼런스

| API | 1줄 요약 | 대표 요청 |
|-----|---------|----------|
| `_profile` | shard-level 단계별 nanos (상대 비교 전용) | `POST /idx/_search {"profile":true,"query":{...}}` |
| `_explain/{id}` | 단일 문서의 매칭 여부·스코어 트리 (search_type 무시) | `GET /idx/_explain/42 {"query":{...}}` |
| `_search explain:true` | 결과셋 hit별 스코어 분해 (전역 IDF·rescore 반영) | `POST /idx/_search {"explain":true,"query":{...}}` |
| `_validate/query` | 쿼리 파싱·rewrite된 Lucene term 확인 | `GET /idx/_validate/query?rewrite=true&all_shards=true {"query":{...}}` |
| `_analyze` | 분석기가 텍스트를 어떤 토큰으로 쪼개는지 | `POST /idx/_analyze {"analyzer":"nori_search","text":"검색어"}` |
| `_termvectors/{id}` | 색인된 실제 토큰·term_freq·통계 | `GET /idx/_termvectors/42 {"fields":["title"],"term_statistics":true}` |
| `_mtermvectors` | 다중 문서 term vector / artificial doc | `POST /idx/_mtermvectors {"ids":["1","2"],"fields":["title"],"term_statistics":true}` |
| `_field_caps` | 필드 searchable·aggregatable·멀티인덱스 type conflict | `GET /idx/_field_caps?fields=title` |
| `_tasks` | 실행 중 task 목록·소요시간 | `GET /_tasks?actions=*search*&detailed=true` |
| `_nodes/hot_threads` | 노드별 CPU 핫스팟 스냅샷 | `GET /_nodes/hot_threads?type=cpu&threads=5` |
| `_cat/thread_pool/search` | search 풀 active/queue/rejected | `GET /_cat/thread_pool/search?v&h=node_name,active,queue,rejected` |
| `_nodes/stats/breaker` | circuit breaker tripped·한계치 | `GET /_nodes/stats/breaker` |
| `_rank_eval` | 골든셋 기준 nDCG/MRR 등 relevance 메트릭 | `POST /idx/_rank_eval {"requests":[...],"metric":{"dcg":{"k":10}}}` |
| `_pit` | Point-in-Time 컨텍스트(일관 페이징) | `POST /idx/_pit?keep_alive=1m` |
| `_cache/clear` | request/query/fielddata 캐시 비우기 | `POST /idx/_cache/clear?request=true` |

## 함정 모음 (검증됨)

- **★`termvectors` `dfs` 파라미터 금지** — ES 5.0(PR#16452)에서 제거되어 8.x에 존재하지 않는다. 멀티샤드 score 편차는 단일 샤드 테스트 인덱스 / 클라이언트 재계산으로 대응한다.
- **`_explain`은 search_type 무시**(issue#2612) — dfs를 줘도 per-shard IDF만. 전역 IDF·rescore는 `_search explain:true`로만.
- **profiling 오버헤드** — Lucene 최적화 비활성화로 절대 nanos 부풀림 + shard-level만. 단계 간 상대 비교 전용, 프로덕션 기본 활성 금지.
- **termvectors on-the-fly drift** — 매핑 `term_vector:no`(기본)면 `_source`를 '현재' index_analyzer로 재분석하므로, analyzer 변경 후 reindex를 빠뜨리면 stored(과거)와 on-the-fly(현재) drift를 **탐지하지 못한다**. 진짜 색인 토큰은 `term_vector:with_positions_offsets` 또는 reindex로 교차검증.
- **포터빌리티** — `_disk_usage`·`_field_usage_stats`는 ES 8.x 전용(OpenSearch no handler). PIT 엔드포인트도 ES=`_pit` vs OpenSearch=`_search/point_in_time`로 다르다.
