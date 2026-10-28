# PostGIS (위치 기반 조회)

> 스페셜리스트 항목. PostGIS 3.x + PostgreSQL 13+ 기준. 먼저 대상 스키마에서 컬럼 타입과 SRID 를 확인:
> `SELECT f_table_name, f_geometry_column, type, srid FROM geometry_columns UNION ALL SELECT f_table_name, f_geography_column, type, srid FROM geography_columns;`

## 목차
- PY-GIS-01 SRID 4326 geometry 에 미터 거리 → 실제로는 "도(degree)"
- PY-GIS-02 `ST_Distance(...) < r` 는 인덱스를 못 탄다 — `ST_DWithin`
- PY-GIS-03 쿼리의 캐스트/변환 식과 인덱스 식이 다르면 인덱스 미사용
- PY-GIS-04 geography vs 투영 geometry 선택
- PY-GIS-05 KNN `<->` 는 ORDER BY + 상수 기준점 + LIMIT 일 때만 인덱스
- PY-GIS-06 `ST_MakePoint(lon, lat)` — 축 순서와 `ST_SetSRID` vs `ST_Transform`
- PY-GIS-07 거대 폴리곤은 bbox 인덱스가 무력 — `ST_Subdivide`
- PY-GIS-08 psycopg 는 geometry 타입 로더가 없다 — SQL 에서 형식을 정해 받기

---

### PY-GIS-01 · SRID 4326 `geometry` 에 `ST_DWithin(a, b, 1000)` 은 "1000미터"가 아니라 "1000도"다
- 적용: `geometry(Point, 4326)` 컬럼에 거리 반경 조회
- 신호: 반경 검색이 테이블 전체를 반환, 혹은 `0.01` 같은 매직 넘버 반경(위도에 따라 오차가 커짐)
- 메커니즘: geometry 의 거리 단위는 SRID 의 좌표 단위다. 4326 은 경위도(도)이므로 평면 거리 계산이 도 단위로 수행된다. geography 는 미터, 기본 `use_spheroid=true`.
- 처방: (a) 컬럼을 `geography(Point, 4326)` 로, (b) geometry 유지 시 미터 단위 투영 SRID(한국: EPSG:5179 UTM-K, EPSG:5186 중부원점 등)로 저장/인덱싱, (c) 식 인덱스 `((geom::geography))` + 쿼리도 같은 캐스트(PY-GIS-03).
- 반례: 지도 타일 bbox 필터(`geom && ST_MakeEnvelope(..., 4326)`)처럼 거리 개념이 없는 연산은 4326 geometry 가 맞다.
- 검증: 알려진 두 지점(예: 서울시청–강남역) 거리를 `ST_Distance(a::geography, b::geography)` 로 계산해 실측값과 비교.
- 근거: https://postgis.net/docs/ST_DWithin.html · https://postgis.net/docs/using_postgis_dbmanagement.html#PostGIS_Geography

### PY-GIS-02 · 반경 필터에 `ST_Distance(...) < r` 를 쓰면 공간 인덱스를 못 탄다 — `ST_DWithin`
- 적용: "반경 r 안의 항목" 쿼리
- 신호: `EXPLAIN` 에 `Seq Scan` + `Filter: st_distance(...)`, 데이터가 늘수록 선형으로 느려짐
- 메커니즘: `ST_DWithin` 은 내부에 bbox 비교(`&&`)를 포함해 GiST 인덱스를 쓰고, 거리 계산은 후보에만 한다. `ST_Distance` 는 행마다 계산하는 일반 함수라 인덱스와 무관.
- 처방: `WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s)`; 거리 값이 필요하면 SELECT 절에서만 `ST_Distance`. geography 정밀도가 덜 중요하면 `use_spheroid => false` 로 구면 계산(더 빠름).
- 반례: 후보가 수십 행으로 이미 좁혀진 하위 쿼리 안이라면 차이가 미미.
- 검증: `EXPLAIN (ANALYZE, BUFFERS)` 에서 `Index Scan using ..._gist` 확인.
- 근거: https://postgis.net/docs/ST_DWithin.html

### PY-GIS-03 · 쿼리에서 컬럼을 `::geography` 캐스트하거나 `ST_Transform` 하면, 같은 식의 인덱스가 없는 한 인덱스를 못 쓴다
- 적용: geometry 컬럼 + geography 연산, 저장 SRID 와 다른 SRID 로 비교하는 쿼리
- 신호: GiST 인덱스가 "있는데" Seq Scan
- 메커니즘: PostgreSQL 인덱스는 컬럼 또는 **동일한 식**에만 매칭된다. `geom::geography`, `ST_Transform(geom, 5179)` 는 다른 식이다. 행마다 변환하면 CPU 도 크게 든다.
- 처방: 변환은 상수(입력 좌표) 쪽에 적용: `ST_DWithin(geom, ST_Transform(:pt, <컬럼 SRID>), r)`. 컬럼 측 변환이 불가피하면 식 인덱스 `CREATE INDEX ... USING GIST ((geom::geography));` 를 만들고 쿼리 식을 정확히 일치. 대량 생성은 PY-MIG-01(CONCURRENTLY).
- 반례: 없음.
- 검증: `EXPLAIN` 의 Index Cond 에 기대한 식이 나타나는지.
- 근거: https://www.postgresql.org/docs/current/indexes-expressional.html · https://postgis.net/workshops/postgis-intro/indexing.html

### PY-GIS-04 · geography vs 투영 geometry 는 "범위·연산 종류·정밀도"로 고른다
- 적용: 새 공간 컬럼 설계
- 신호: 전국 단위 서비스에 경위도 geometry + 도 단위 매직 넘버, 혹은 반대로 geography 에서 지원 안 되는 함수 때문에 캐스트 남발
- 메커니즘: geography 는 지구 곡면 기준 미터 단위 계산이 정확하지만 지원 함수가 적고 연산이 비싸다. 투영 geometry 는 평면 계산이라 빠르고 함수가 풍부하지만 투영 범위를 벗어나면 왜곡된다(한국 전역은 EPSG:5179 가 일반적).
- 처방: 한국 내 반경·면적·버퍼 연산 위주 → 투영 geometry(5179) 저장 + 입출력 시 4326 변환. 전 세계 범위·대권거리 → geography. 둘 다 필요하면 저장은 하나로 하고 다른 쪽은 생성 컬럼/식 인덱스.
- 반례: 데이터가 수천 건 이하면 성능 차이보다 단순성(geography 하나)이 이득.
- 검증: 대표 쿼리를 두 방식으로 `EXPLAIN ANALYZE` 비교, 거리 오차를 실측 샘플로 확인.
- 근거: https://postgis.net/docs/using_postgis_dbmanagement.html#PostGIS_GeographyVSGeometry

### PY-GIS-05 · 최근접 정렬 `ORDER BY geom <-> :pt LIMIT k` 는 기준점이 상수이고 ORDER BY 안에 있을 때만 인덱스를 쓴다
- 적용: "가까운 순 k개" 조회
- 신호: `<->` 를 WHERE/SELECT 에 쓰거나 기준점을 서브쿼리/CTE 컬럼으로 넘겨서 정렬이 전체 정렬(Sort)로 실행
- 메커니즘: KNN 인덱스 탐색은 ORDER BY 절의 `<->` 에서만 동작하고, 한쪽이 상수여야 한다(서브쿼리/CTE 값이면 미적용). geography 의 `<->` 는 회전타원체가 아닌 구면 거리다. PostGIS 2.2+/PG 9.5+ 에서 실제 거리 KNN.
- 처방: 기준점을 파라미터로 직접 바인딩. "반경 r 안에서 가까운 순"은 `WHERE ST_DWithin(...) ORDER BY geom <-> :pt LIMIT k` 로 결합. LATERAL 로 행마다 최근접을 구할 때는 LATERAL 안에서 외부 값이 상수 취급되어 인덱스를 탈 수 있으니 `EXPLAIN` 확인.
- 반례: k 가 크거나(수천) 필터 선택도가 높으면 일반 필터 후 정렬이 나을 수 있다.
- 검증: `EXPLAIN` 에서 `Index Scan ... Order By: (geom <-> ...)`.
- 근거: https://postgis.net/docs/geometry_distance_knn.html

### PY-GIS-06 · `ST_MakePoint(x, y)` 는 (경도, 위도) 순서 — 그리고 `ST_SetSRID` 는 라벨, `ST_Transform` 은 좌표 변환
- 적용: 클라이언트 위경도 입력을 받는 모든 쿼리
- 신호: 한국 좌표가 소말리아 근처로 찍힘(위경도 뒤바뀜), 투영 좌표에 `ST_SetSRID(..., 4326)` 을 붙여 엉뚱한 결과
- 메커니즘: PostGIS 는 x=경도, y=위도. 프런트/지도 SDK 는 `(lat, lng)` 순서를 흔히 쓴다. `ST_SetSRID` 는 좌표를 바꾸지 않고 SRID 메타데이터만 붙인다.
- 처방: API 스키마 필드명을 `lat`/`lng` 로 명시하고 SQL 바인딩 순서를 한 곳(헬퍼 함수)에서만 정의. 입력 범위 검증(위도 −90~90, 경도 −180~180; 국내 서비스면 대략 위도 33~39, 경도 124~132)으로 뒤바뀜을 조기 차단. 다른 좌표계 입력은 `ST_Transform(ST_SetSRID(ST_MakePoint(x, y), src), dst)`.
- 반례: 없음.
- 검증: 알려진 랜드마크 좌표의 왕복 테스트(`ST_X`/`ST_Y`).
- 근거: https://postgis.net/docs/ST_MakePoint.html · https://postgis.net/docs/ST_SetSRID.html

### PY-GIS-07 · 행정구역 같은 거대 폴리곤은 bbox 가 넓어 인덱스가 거의 모든 행을 후보로 낸다 — `ST_Subdivide`
- 적용: 포인트-인-폴리곤(`ST_Intersects`/`ST_Contains`)을 큰·복잡한 폴리곤 테이블에 수행
- 신호: 인덱스 스캔은 하는데 `Rows Removed by Filter` 가 크고 정밀 판정(GEOS) 시간이 지배적
- 메커니즘: GiST 는 bbox 만 색인하므로 꼭짓점이 많은 큰 폴리곤은 후보 필터링 효과가 낮고, 후보마다 전체 폴리곤과 정밀 판정을 한다.
- 처방: 조회 전용 보조 테이블에 `ST_Subdivide(geom)` 결과를 원본 ID 와 함께 저장 + GiST 인덱스 → 그 테이블로 판정 후 원본 ID 로 집계.
- 반례: 폴리곤 수가 적고 단순하면 불필요. 쓰기가 잦은 폴리곤은 보조 테이블 동기화 비용을 고려.
- 검증: 동일 포인트 집합으로 원본 vs 분할 테이블 `EXPLAIN ANALYZE`.
- 근거: https://postgis.net/docs/ST_Subdivide.html

### PY-GIS-08 · psycopg 는 PostGIS 타입 로더가 없어 geometry 를 문자열(hex EWKB)로 돌려준다 — 원하는 형식을 SQL 에서 정해 받는다
- 적용: 원시 SQL(psycopg 3) + PostGIS
- 신호: 응답에 `0101000020E6100000...` 같은 문자열 노출, 파이썬에서 WKB 파싱 코드 산재
- 메커니즘: psycopg 는 알 수 없는 타입 OID 를 텍스트로 반환한다. 파싱을 앱에서 하면 shapely 의존 + CPU 비용.
- 처방: 필요한 형식으로 SELECT — 좌표면 `ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lng`, GeoJSON 이면 `ST_AsGeoJSON(geom)::json`(또는 FeatureCollection 을 `json_agg` 로 DB 에서 조립), 지도 타일이면 `ST_AsMVT`. 입력은 `ST_SetSRID(ST_MakePoint(%s, %s), 4326)` 로 바인딩. shapely 객체가 정말 필요할 때만 psycopg 커스텀 로더/덤퍼 등록.
- 반례: 공간 연산을 파이썬에서 대량 수행해야 하는 분석 배치는 WKB + shapely(벡터화) 가 맞을 수 있다.
- 검증: 응답 스키마 테스트에서 좌표 필드 타입 확인.
- 근거: https://www.psycopg.org/psycopg3/docs/advanced/adapt.html · https://postgis.net/docs/ST_AsGeoJSON.html
