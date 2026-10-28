# Pydantic v2 검증 비용 · FastAPI 응답 직렬화

> 스페셜리스트 항목. 기준: Pydantic 2.8+, FastAPI 0.130+(직렬화 경로 변경). 대상 프로젝트의 FastAPI 버전에 따라 FA-RESP-01/02 중 하나만 해당한다. 버전 경계: 0.128 에서 응답 모델 인스턴스 사전 dump(`_prepare_response_content`) 제거(FA-RESP-03), 0.130 에서 Rust JSON 직렬화(FA-RESP-01).

## 목차
- FA-RESP-01 0.130+: 반환 타입이 있으면 Pydantic(Rust)이 JSON 바이트로 직접 직렬화 — `response_class` 를 주면 그 경로를 잃는다
- FA-RESP-02 0.130 미만: jsonable_encoder 경로와 ORJSONResponse 판단
- FA-RESP-03 반환 타입 클래스 ≠ 응답 모델 → 응답마다 전체 재검증 (인스턴스 통과는 0.128+)
- FA-RESP-04 대용량 목록은 4중 복사 — 페이지네이션 또는 스트리밍
- FA-PYD-01 `model_validate(json.loads(x))` 대신 `model_validate_json(x)`
- FA-PYD-02 `TypeAdapter` 를 호출마다 만들면 스키마 빌드 비용을 매번 낸다
- FA-PYD-03 `model_construct` 는 중첩까지 검증을 건너뛴다 — 신뢰 경계에서만
- FA-PYD-04 검증 핫패스 타입 선택: list>Sequence, discriminator, TypedDict, wrap validator 회피
- FA-PYD-05 `revalidate_instances='never'` 기본값 — 변형된 인스턴스가 그대로 통과

---

### FA-RESP-01 · FastAPI 0.130+ 는 반환 타입/`response_model` 이 있으면 Pydantic Rust 직렬화로 JSON 바이트를 바로 만든다 — `response_class` 를 지정하면 이 빠른 경로가 꺼진다
- 적용: FastAPI 0.130.0+ (2026-02). 0.131.0 에서 `ORJSONResponse`/`UJSONResponse` deprecated.
- 신호: 성능 목적으로 `default_response_class=ORJSONResponse` 나 `response_class=JSONResponse` 를 지정한 앱, 반환 타입 표기 없는 엔드포인트
- 메커니즘: 응답 필드가 있고 `response_class` 가 기본값(placeholder)일 때만 `serialize_json` 으로 Rust 에서 바로 bytes 를 만든다(fastapi/routing.py `use_dump_json`). 커스텀 응답 클래스를 주면 `jsonable_encoder` → 파이썬 dict → 응답 클래스의 json 직렬화 단계를 다시 거친다. 공식 문서도 "최대 성능은 response model + response_class 미지정".
- 처방: 업그레이드 후 `ORJSONResponse`/`default_response_class` 를 제거하고 모든 엔드포인트에 반환 타입(`-> ItemOut`) 또는 `response_model` 을 단다. `Response` 를 직접 반환하는 코드는 검증·직렬화·OpenAPI 를 모두 건너뛰므로 의도된 곳(파일·바이너리)에만.
- 반례: orjson 전용 기능(numpy 배열, 비 str 키 dict)을 응답에서 쓰고 있다면 그 엔드포인트만 유지.
- 검증: 대표 엔드포인트 wrk/locust 비교, py-spy 에서 `jsonable_encoder` 프레임이 사라졌는지.
- 근거: https://fastapi.tiangolo.com/advanced/custom-response/#json-performance · https://fastapi.tiangolo.com/release-notes/ (0.130.0, 0.131.0)

### FA-RESP-02 · FastAPI 0.130 미만에서는 응답이 "검증 → 파이썬 객체로 직렬화 → stdlib json.dumps" 를 거친다
- 적용: FastAPI < 0.130 (업그레이드 불가한 프로젝트)
- 신호: 큰 응답에서 `json.dumps`·`jsonable_encoder` 가 프로파일 상위
- 메커니즘: 응답 모델 검증 후 `field.serialize`(mode=json 파이썬 객체) 결과를 `JSONResponse` 가 표준 `json` 으로 다시 bytes 화한다. 반환 타입이 없으면 재귀 파이썬 함수인 `jsonable_encoder` 로 처리돼 더 느리다.
- 처방: 1순위는 0.130+ 업그레이드(FA-RESP-01). 불가하면 핫 엔드포인트에 한해 `ORJSONResponse`(orjson 설치) 또는 `Response(content=Model.model_dump_json(), media_type="application/json")` 를 직접 반환하되, 이 경우 응답 검증이 생략됨을 테스트로 보완.
- 반례: 응답이 작고 RPS 가 낮으면 차이가 의미 없다 — 측정 후 결정. 0.128 미만에선 응답 모델 인스턴스를 반환해도 dump→dict 재검증이 일어나 FA-RESP-03 의 "인스턴스 통과" 최적화도 성립하지 않는다(0.128~0.129 는 인스턴스 통과는 되지만 이 항목의 stdlib json 경로는 그대로).
- 검증: 동일 페이로드로 엔드포인트별 p50/p99.
- 근거: https://fastapi.tiangolo.com/advanced/custom-response/

### FA-RESP-03 · 반환 객체의 클래스가 응답 모델과 다르면 응답마다 전체 재검증이 일어난다
- 적용: FastAPI **0.128+** (`_prepare_response_content` 제거 이후). 서비스가 도메인 모델/ORM 객체/dict 를 반환하고 라우터가 다른 `response_model` 을 선언한 구조, 원시 SQL 행(dict)을 그대로 반환하는 구조
- 신호: 프로파일에서 `validate_python` 비중이 큼, 서비스에서 이미 `OutModel(**row)` 를 만들고 라우터가 또 다른 모델로 검증
- 메커니즘: FastAPI 는 반환값을 응답 필드로 `validate` 한 뒤 직렬화한다. 반환값이 **정확히 그 모델의 인스턴스**면 Pydantic 기본 `revalidate_instances='never'` 로 사실상 통과, dict/ORM 객체/다른 클래스면 `from_attributes`/dict 검증을 전 필드에 수행. 서비스에서 모델을 만들고 라우터에서 다른 모델로 다시 검증하면 2회. **0.128 미만**은 `serialize_response` 가 먼저 `_prepare_response_content` 로 반환된 BaseModel 을 `model_dump` → dict 로 바꾼 뒤 전 필드를 검증하므로, 정확히 응답 모델 인스턴스를 반환해도 dump + 재검증 비용이 든다 — 인스턴스/dict 반환 간 차이가 거의 없으니 이 경우 1순위는 업그레이드(FA-RESP-02).
- 처방: 검증은 한 번만 — (a) 원시 SQL 경로: 행(dict)을 그대로 반환하고 응답 타입 검증 1회에 맡기거나, (b) (0.128+) 서비스가 응답 모델 인스턴스를 직접 만들고 라우터 반환 타입을 같은 클래스로. psycopg `class_row(OutModel)` 로 행을 바로 응답 모델로 만들고 같은 클래스를 반환하는 것도 검증 1회다 — 피해야 할 것은 "행→모델A→모델B" 의 2회.
- 반례: 내부 도메인 모델과 API 계약을 분리하는 설계 가치가 더 크면 2회 검증을 감수 — 핫 엔드포인트만 최적화.
- 검증: `python -m cProfile` 또는 pyinstrument 로 요청 1건의 검증 호출 수 확인.
- 근거: https://github.com/fastapi/fastapi/blob/master/fastapi/routing.py (`serialize_response`) · https://docs.pydantic.dev/latest/api/config/#pydantic.config.ConfigDict.revalidate_instances

### FA-RESP-04 · 대용량 목록 응답은 메모리에 4중 복사된다 — 페이지네이션이 기본, 필요하면 스트리밍
- 적용: 수천 행 이상을 한 응답으로 반환하는 엔드포인트(export, 지도 마커 전체 등)
- 신호: 해당 엔드포인트 호출 시 워커 RSS 급증, 동시 호출 몇 개로 OOMKilled
- 메커니즘: 결과 버퍼(libpq, PY-PG-08) → 파이썬 행 객체 → 검증된 모델 리스트 → JSON bytes 가 응답 완료까지 동시에 살아 있다. 파이썬 객체는 원시 데이터보다 수 배 크다.
- 처방: 커서/keyset 페이지네이션(`WHERE (created_at, id) < (%s, %s) ORDER BY ... LIMIT %s`). 전체 export 가 필요하면 `StreamingResponse` + 서버측 커서/`cur.stream()` 으로 NDJSON/CSV 청크 생성 — 이때 커넥션은 스트림 끝까지 점유되므로 FA-BG-02 의 의존성 수명 확인. 지도 데이터는 DB 에서 `ST_AsMVT`/GeoJSON 으로 집계해 bytes 로 받는 방법도 있다.
- 반례: 수백 행 이하에서 스트리밍은 복잡도만 늘린다.
- 검증: `tracemalloc` 피크 또는 컨테이너 메모리 메트릭을 행 수별로 비교.
- 근거: https://fastapi.tiangolo.com/advanced/custom-response/#streamingresponse · https://www.psycopg.org/psycopg3/docs/advanced/cursors.html

### FA-PYD-01 · `Model.model_validate(json.loads(raw))` 대신 `Model.model_validate_json(raw)`
- 적용: Redis 캐시·외부 API 응답·메시지 큐 페이로드를 직접 파싱하는 코드
- 신호: `json.loads` 직후 `model_validate`/`TypeAdapter.validate_python`
- 메커니즘: 두 단계 방식은 파이썬 dict 를 한 번 만들고 다시 검증한다. `*_validate_json` 은 Rust 에서 파싱과 검증을 한 번에 한다(Pydantic 성능 문서).
- 처방: `Model.model_validate_json(resp.content)`, 목록은 `TypeAdapter(list[Model]).validate_json(...)` (어댑터는 FA-PYD-02 대로 모듈 수준).
- 반례: 모델에 `mode='before'`/`'wrap'` 검증기가 있으면 두 단계 방식이 더 빠를 수 있다(공식 문서 명시).
- 검증: `timeit` 으로 실제 페이로드 비교.
- 근거: https://docs.pydantic.dev/latest/concepts/performance/

### FA-PYD-02 · `TypeAdapter(...)` 를 함수 안에서 만들면 호출마다 검증기·직렬화기를 새로 빌드한다
- 적용: 핫패스에서 `TypeAdapter(list[X])` 를 생성하는 코드
- 신호: 프로파일 상위에 `GenerateSchema`/core schema 빌드
- 메커니즘: TypeAdapter 인스턴스화 = 새 validator·serializer 구성(공식 문서). 모델 클래스는 정의 시 1회 빌드되지만 어댑터는 생성할 때마다다.
- 처방: 모듈 수준 상수 `ITEMS = TypeAdapter(list[Item])` 로 재사용.
- 반례: 타입이 런타임에 동적으로 결정되는 드문 경우는 `functools.cache` 로 타입별 캐싱.
- 검증: 프로파일에서 스키마 빌드 프레임 소멸.
- 근거: https://docs.pydantic.dev/latest/concepts/performance/

### FA-PYD-03 · `model_construct()` 는 검증을 통째로 건너뛴다 — 중첩 필드는 dict 로 남는다
- 적용: 성능 때문에 `model_construct` 를 쓰는 코드
- 신호: `model_construct(**row)` 후 `.nested.attr` AttributeError, 직렬화 시 `PydanticSerializationUnexpectedValue` 경고, 타입 불일치 값이 API 로 노출
- 메커니즘: 기본값 채우기만 하고 타입 변환·제약·중첩 모델 생성을 하지 않는다. DB 에서 온 `Decimal`/`datetime` 이 기대 타입과 다르면 그대로 흘러간다.
- 처방: 자기 코드가 방금 검증한 데이터를 재구성할 때만 사용. 외부·DB 입력은 `model_validate`, 비용이 문제면 FA-RESP-03 의 "검증 1회" 구조로 해결.
- 반례: 없음 — 신뢰 경계 밖 데이터에는 쓰지 않는다.
- 검증: 해당 경로의 응답 스키마 계약 테스트(OpenAPI 기반 schemathesis 등).
- 근거: https://docs.pydantic.dev/latest/concepts/models/#creating-models-without-validation

### FA-PYD-04 · 검증 핫패스의 타입 선택: `list`/`dict` > `Sequence`/`Mapping`, discriminator 유니온, 내부 중첩은 `TypedDict`, wrap validator 회피
- 적용: 큰 요청 바디(배열 수천 개), 다형 페이로드, 내부 DTO
- 신호: 요청 파싱 단계 지연, 유니온 필드 오류 메시지가 후보 수만큼 쏟아짐
- 메커니즘: `Sequence` 는 isinstance 검사·여러 시퀀스 타입 시도가 필요하다. 태그 없는 유니온은 후보를 차례로 시도한다. 공식 벤치에서 중첩 BaseModel 대신 `TypedDict` 가 약 2.5배 빠르다. wrap validator 는 데이터를 파이썬으로 물질화해야 해서 느리다. `FailFast`(2.8+)는 시퀀스 첫 오류에서 중단.
- 처방: 구체 컨테이너 타입, `Field(discriminator="type")`, 응답·내부 전달용 중첩 구조는 `TypedDict`, 커스텀 검증은 after validator 우선, 대량 배열 입력에 `Annotated[list[X], FailFast()]`.
- 반례: 공개 API 입력 모델은 오류 메시지 품질이 중요하므로 FailFast·TypedDict 남용 금지.
- 검증: `pytest-benchmark` 로 대표 페이로드 검증 시간.
- 근거: https://docs.pydantic.dev/latest/concepts/performance/

### FA-PYD-05 · `revalidate_instances` 기본값은 `'never'` — 생성 후 변형된 인스턴스는 다른 모델에 넣어도 다시 검증되지 않는다
- 적용: 모델 인스턴스를 수정(`m.x = ...`)한 뒤 다른 모델 필드로 넘기는 코드, `validate_assignment` 미사용
- 신호: 제약(`gt=0`)을 위반한 값이 응답/DB 까지 도달
- 메커니즘: 같은 클래스 인스턴스는 신뢰하고 그대로 통과시킨다(성능 기본값). 할당 검증도 기본 꺼짐.
- 처방: 불변 모델(`model_config = ConfigDict(frozen=True)`) + `model_copy(update=...)` 후 필요 시 `model_validate(m.model_dump())`, 또는 해당 모델만 `validate_assignment=True`.
- 반례: 전역 `revalidate_instances='always'` 는 FA-RESP-03 의 비용을 모든 경로에 부과한다.
- 검증: 변형 후 직렬화 테스트.
- 근거: https://docs.pydantic.dev/latest/api/config/#pydantic.config.ConfigDict.revalidate_instances
