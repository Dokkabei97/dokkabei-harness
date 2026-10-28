---
name: go-mux-guide
description: |
  Go 런타임·성능 스페셜리스트 트리아지 + stdlib net/http mux 가이드. map 사전할당·메모리 미반환, 슬라이스 앨리어싱·부분문자열 유지, GC·GOGC·GOMEMLIMIT·컨테이너 GOMAXPROCS, 이스케이프 분석·sync.Pool, 고루틴 누수·context·타이머, http.Client 풀·서버 타임아웃·ServeMux 패턴, pprof·trace·PGO, database/sql 풀.
  Go runtime/performance specialist triage plus stdlib mux guide: maps, slices, GC tuning, escape analysis, goroutine leaks, net/http pools and timeouts, pprof/PGO, database/sql pools. Use when: writing, reviewing, or profiling Go code; Go memory, latency, or GC issues; Go HTTP server/client or ServeMux routing.
---

# Go 런타임·성능 스페셜리스트 트리아지 + stdlib mux 가이드

목적: 모델·시니어 제너럴리스트가 이미 아는 관용구(에러 래핑, table-driven 테스트 등)를 반복하지 않고,
**강한 시니어도 놓칠 법한 런타임·성능 함정**을 증상에서 바로 해당 항목으로 연결한다.
각 항목(`GO-<AREA>-<NN>`)은 적용 조건·신호·메커니즘·처방·반례·검증·근거를 갖는다.

## 0. 먼저 확인할 사실 (단정 금지)

항목을 적용하기 전에 프로젝트에서 확인한다 — 버전·도구를 가정하지 말 것.

| 확인 | 어디서 | 왜 |
|------|--------|----|
| go.mod `go`/`toolchain` 라인 | `go.mod` | loopvar(1.22)·ServeMux(1.22)·timer(1.23)·컨테이너 GOMAXPROCS(1.25) 기본값이 여기에 달림 (GO-VER-01) |
| 실제 빌드 툴체인 | Dockerfile/CI 이미지, `go version -m <bin>` | 1.24 Swiss map, 1.26 Green Tea GC, 1.27 json/v2 백엔드 등 툴체인 의존 동작 |
| 배포 환경 | k8s 매니페스트 `resources.limits` | GOMEMLIMIT·GOMAXPROCS 처방 여부 (GO-GC-01, 03) |
| 라우터 | `http.NewServeMux` vs chi/gin/echo | stdlib mux 항목 적용 범위 |
| DB 접근 | `go.mod` 의 pgx / database/sql 드라이버 / sqlx / ORM, 마이그레이션 도구 디렉터리 | GO-DB 항목·`db-patterns.md` 적용 범위 |
| 기존 컨벤션 | 프로젝트 CLAUDE.md, `.claude/rules/`, 기존 handler/repository 코드 | 생성·리뷰 시 컨벤션이 이 가이드보다 우선 |

버전 민감 API 는 `backend-shared:context7-docs-guide` 규약으로 최신 문서를 확인(미설치 시 생략).
프로젝트별로 적용할 항목 ID 를 고정하려면 `workflow:project-rules`(설치돼 있으면)로 프로젝트 `.claude/rules/` 에 선별 기록한다.

## 1. 증상 → 항목 트리아지

### 메모리·GC

| 증상/신호 | 먼저 볼 항목 | 레퍼런스 |
|-----------|-------------|----------|
| 컨테이너 OOMKilled, 라이브 힙은 limit 절반쯤 | GO-GC-01, GO-GC-02 | `gc-memory.md` |
| CPU 낮은데 p99 가 100ms 단위로 튐, `nr_throttled` | GO-GC-03 | `gc-memory.md` |
| GC CPU 비중 큼(`scanobject`, `gcDrain`) | GO-GC-07, GO-GC-13, GO-MAP-06 | `gc-memory.md`, `maps.md` |
| 요청 고루틴이 `gcAssistAlloc` 에서 시간 소모 | GO-OBS-05, GO-GC-04 | `observability.md` |
| 할당 많음(`convT*`, `growslice`, `slicebytetostring`) | GO-GC-06, GO-SLC-04, GO-SLC-05 | `gc-memory.md`, `slices-strings.md` |
| len 은 작은데 힙이 피크에서 안 내려옴 | GO-MAP-02, GO-SLC-02, GO-SLC-03 | `maps.md`, `slices-strings.md` |
| RSS 가 안 줄어 누수 의심 | GO-GC-08 → GO-OBS-01 | `gc-memory.md` |
| sync.Pool 을 넣었는데 효과 없음/메모리 증가 | GO-GC-05 | `gc-memory.md` |
| 같은 문자열이 대량 상주 | GO-GC-10 | `gc-memory.md` |

### 자료구조 (map·slice·string)

| 증상/신호 | 항목 |
|-----------|------|
| 맵을 루프로 채움, `mapassign`/grow 할당 상위 | GO-MAP-01 |
| 1.23 이하 근거의 맵 성능 규칙 | GO-MAP-03 |
| 조밀한 정수 키 집합 | GO-MAP-04 |
| 큰 구조체 값 맵, `m[k].f = x` 우회 코드 | GO-MAP-05 |
| 수백만 엔트리 캐시 | GO-MAP-06 |
| 반복 순서 의존 출력/무작위 선택 | GO-MAP-07 |
| `concurrent map writes` 크래시, sync.Map 남용 | GO-MAP-08 |
| `m[a+":"+b]`, `[]byte` 키 조회 | GO-MAP-09 |
| float/time.Time/any 키 | GO-MAP-10 |
| append 후 다른 슬라이스 값이 바뀜 | GO-SLC-01 |
| 루프 내 `+=`, Builder 복사 panic | GO-SLC-06 |
| `strings.Split(...)[0]` | GO-SLC-07 |
| 큰 구조체 range 복사 | GO-SLC-08 |
| JSON `null` vs `[]`, 0값 time 노출 | GO-SLC-09, GO-SLC-10 |

### 동시성

| 증상/신호 | 항목 |
|-----------|------|
| 고루틴 수 단조 증가 | GO-CON-01, GO-OBS-08 |
| for-select 의 `time.After`, Timer Stop/드레인 | GO-CON-02 |
| 루프 변수 캡처, `v := v` | GO-CON-03 |
| 비동기 후속 작업이 `context canceled` | GO-CON-04 |
| 어느 타임아웃인지 모름 | GO-CON-05 |
| `ctx.Value` 로 의존성 전달 | GO-CON-06 |
| errgroup 팬아웃으로 다운스트림 포화 | GO-CON-07 |
| RWMutex 경합, 재귀 RLock | GO-CON-08 |
| 락 경합 시 처리량 급락 | GO-CON-09 |
| 코어 늘려도 카운터 처리량 정체 | GO-CON-10 |
| 함수형 64비트 atomic | GO-CON-11 |
| Recovery 미들웨어가 있는데 panic 으로 재시작 | GO-CON-12 |
| WaitGroup.Add 위치 | GO-CON-13 |
| `time.Sleep` 기반 플래키 테스트 | GO-CON-14 |

### net/http · DB

| 증상/신호 | 항목 |
|-----------|------|
| 함수 안 `&http.Client{}`, `http.Get` | GO-HTTP-01 |
| 단일 다운스트림 고QPS에 TIME_WAIT·핸드셰이크 | GO-HTTP-02 |
| 에러 분기에서 Body 미종료 | GO-HTTP-03 |
| 유휴 후 첫 요청 EOF/reset | GO-HTTP-04 |
| `http.ListenAndServe` 직접 호출, 서버 타임아웃 미설정 | GO-HTTP-05 |
| 바디 크기 무제한 디코딩 | GO-HTTP-06 |
| ServeMux 충돌 panic, 405/리다이렉트 동작 | GO-HTTP-07 |
| 메트릭 path 라벨 카디널리티 폭발 | GO-HTTP-08 |
| `import _ "net/http/pprof"` | GO-HTTP-09 |
| 롤링 배포 중 502 | GO-HTTP-10 |
| 200 + 잘린 JSON | GO-HTTP-11 |
| 쿠키 세션 CSRF | GO-HTTP-12 |
| ES 429 미재시도, bulk 부분 실패 유실 | GO-HTTP-13 |
| DB 신규 연결 폭증 / 풀 대기 / InUse 고착 | GO-DB-01, GO-DB-02, GO-DB-03 |
| pgx + PgBouncer 준비 문장 에러 | GO-DB-04 |
| 페일오버 후 read-only 에러 지속 | GO-DB-05 |
| 트랜잭션 안에서 db 직접 호출, 부하 시 정지 | GO-DB-06 |
| 파드마다 pgxpool 크기가 다름, too many clients | GO-DB-07 |

### 측정·툴체인

| 상황 | 항목 |
|------|------|
| heap 프로파일 해석 | GO-OBS-01 |
| CPU 낮은데 지연 큼 | GO-OBS-02, GO-OBS-03 |
| 간헐 지연 스파이크 | GO-OBS-04 |
| PGO 도입/프로파일 대표성 | GO-OBS-06 |
| 성능 PR 벤치마크 근거 | GO-OBS-07 |
| 툴체인 올렸는데 동작 변화 없음 | GO-VER-01, GO-VER-02 |
| CI 검사 보강 | GO-VER-03 |

## 2. 적용 원칙

- **측정 먼저**: 처방은 "신호" 가 관찰되거나 핫 경로임이 확인될 때만. 각 항목의 "반례" 를 반드시 읽는다 — 과최적화는 가독성 부채다.
- **리뷰 시**: 지적에 항목 ID 를 붙이고 "검증" 방법(벤치마크/프로파일)을 함께 제시한다. 근거 없는 수치 주장 금지.
- **생성 시**: 새 코드에는 비용 없는 처방만 기본 적용(클라이언트 재사용, 서버 타임아웃, Body 종료, 결과 채널 버퍼 1, `r.Pattern` 라벨, 용량 힌트). 비용·복잡도가 있는 처방(포인터 제거 구조, unsafe 변환, 샤딩)은 측정 근거가 있을 때만 제안.

## 3. stdlib net/http mux 핵심 (Go 1.22+)

```go
mux := http.NewServeMux()
mux.HandleFunc("GET /api/v1/orders/{id}", h.GetByID)   // GET 은 HEAD 도 매치
mux.HandleFunc("POST /api/v1/orders", h.Create)
mux.HandleFunc("GET /api/v1/{$}", h.Index)             // 정확 매치
mux.HandleFunc("GET /files/{path...}", h.File)          // 나머지 경로

srv := &http.Server{
	Addr:              addr,
	Handler:           middleware.Chain(mux, middleware.Recovery, middleware.Logging),
	ReadHeaderTimeout: 5 * time.Second,   // 기본 0 = 무제한 (GO-HTTP-05)
	IdleTimeout:       120 * time.Second,
}
```

- 경로 값은 `r.PathValue("id")`, 매치된 패턴은 `r.Pattern`(1.23+, 메트릭 라벨용).
- 메서드 불일치는 자동 405 + `Allow`. 겹치는 패턴은 더 구체적인 쪽이 이기고, 우열이 없으면 등록 시 panic (GO-HTTP-07).
- 정규식 경로 제약·라우트 그룹은 stdlib 범위 밖 — 핸들러에서 검증하거나, 프로젝트가 이미 쓰는 라우터를 유지.

## 4. 계층·생성 컨벤션 레퍼런스 (스캐폴딩용)

`/go-gen`, `/go-api-design`, `go-mux-developer` 가 코드를 생성할 때 참조한다. 프로젝트 기존 컨벤션이 있으면 그쪽이 우선.

| 파일 | 내용 |
|------|------|
| `references/layer-patterns.md` | Handler/Service/Repository/DTO, 에러 타입·매핑, 미들웨어(Chain·Logging·Recovery·statusWriter), main 와이어링 |
| `references/db-patterns.md` | database/sql CRUD·트랜잭션·DBTX·Null 처리·동적 쿼리, 마이그레이션(프로젝트 도구 우선) |
| `references/testing-patterns.md` | table-driven, 수동 mock, httptest, testcontainers, 테스트 격리 |

계층 규율 요약: Handler(HTTP 계약·DTO 검증) → Service(비즈니스, `http.*` 비의존) → Repository(데이터 접근). 의존은 위→아래, 경계는 작은 인터페이스, `context.Context` 첫 인자, `%w` 래핑.

## 5. 스페셜리스트 레퍼런스 목록

| 파일 | 접두사 | 항목 수 |
|------|--------|---------|
| `references/maps.md` | GO-MAP | 10 |
| `references/slices-strings.md` | GO-SLC | 10 |
| `references/gc-memory.md` | GO-GC | 13 |
| `references/concurrency.md` | GO-CON | 14 |
| `references/net-http.md` | GO-HTTP | 13 |
| `references/observability.md` | GO-OBS | 8 |
| `references/database-sql.md` | GO-DB | 7 |
| `references/toolchain-versions.md` | GO-VER | 3 |

항목 포맷: `### GO-<AREA>-<NN> · 제목` + 적용 / 신호 / 메커니즘 / 처방 / 반례 / 검증 / 근거.
수치·기본값은 Go 1.27.3 소스와 공식 릴리스노트(1.22~1.27)로 확인한 값이다 — 툴체인이 바뀌면 근거 링크로 재확인한다.
