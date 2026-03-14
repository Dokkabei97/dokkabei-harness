# 이미지 URL 마이그레이션 - 2단계 캐싱 설계 (리뷰 반영 v2)

## Context

기존 이미지 URL은 productCode로부터 결정론적으로 경로를 계산했으나(`GetProductImageURLOriginal`), 새 시스템에서는 파일명이 UUID로 변경되어 proxy API를 통해 조회해야 한다. ~3천만 카탈로그 건수와 검색 API의 높은 QPS를 고려하여, L1(로컬) + L2(ES 인덱스) 2단계 캐싱 전략을 적용한다.

**변경 범위**: `GetProductImageURLOriginal`만 (카탈로그 이미지, prodType "1"). Option mark URL, PC shop URL은 제외.

---

## 캐시 조회 흐름

```
검색 결과 N건 (10~40개 상품)
  → 1차: L1 일괄 조회 (sharded map, in-memory)
      HIT 건은 즉시 할당
      MISS 건 수집 →
        → 2차: L2 일괄 조회 (ES _mget 1회, singleflight로 중복 제거)
            HIT 건은 L1 승격 후 할당
            MISS 건 수집 →
              → 3차: Proxy API 배치 1회 (circuit breaker 적용)
                  SUCCESS → L2 저장, L1 저장, 할당
                  FAILURE → 레거시 URL 반환 + WARN 로그
```

---

## 리뷰 반영 주요 변경사항

| 항목 | 기존 설계 | 리뷰 후 변경 | 근거 |
|------|----------|-------------|------|
| L1 라이브러리 | go-cache | **sharded map 직접 구현** (또는 ristretto) | go-cache의 단일 RWMutex가 고QPS에서 병목 (Critical) |
| Cache stampede | 미고려 | **singleflight 적용** | golang.org/x/sync 이미 go.mod에 존재 (Critical) |
| 조회 방식 | 건별 호출 | **배치 수집 후 일괄 조회** | per-item L2 호출 → O(1) _mget으로 개선 (High) |
| Proxy 타임아웃 | 200ms | **50ms** | 기존 ES plugin 타임아웃(100-150ms) 대비 비례 (High) |
| ES 샤드 수 | 3 | **1** | 30M×100byte=5-8GB, _mget fan-out 제거 |
| ES 설정 | 기본값 | **refresh 30s, async translog, best_compression** | 캐시 인덱스 최적화 |
| ES alias | 미사용 | **image-cache alias 사용** | 무중단 리인덱싱 지원 |
| 패키지 위치 | `common/imagecache/` | **루트 `imagecache/`** | common/ 레이어 역전 방지 |
| Circuit breaker | 단순 atomic | **atomic.Pointer + CAS** | 상태 일관성 보장 |
| resty 클라이언트 | 미명시 | **싱글톤 재사용** | 기존 코드의 per-call 생성 안티패턴 방지 |
| 초기화 보호 | 미고려 | **sync.Once + 미초기화 시 fallback** | 기존 cache/cache.go의 race condition 방지 |

---

## 1. L1 캐시 (로컬 in-memory)

### 옵션 A: Sharded Map 직접 구현 (권장 - 외부 의존성 없음)
- 256개 샤드, 각 샤드별 `sync.RWMutex`
- FNV-1a 해시로 샤드 분배
- TTL: 24시간, 만료 체크는 조회 시 lazy + 5분 주기 백그라운드 정리
- Write lock 영향 범위: ~1/256로 축소

### 옵션 B: ristretto (새 의존성 추가 시)
- `github.com/dgraph-io/ristretto` - 입증된 concurrent cache
- admission policy, cost-based eviction 내장
- NumCounters: 20M, MaxCost: 500MB

### Cache Stampede 방지
```go
var sfGroup singleflight.Group  // golang.org/x/sync (이미 go.mod에 존재)

func resolveFromL2OrProxy(productCode string) string {
    result, _, _ := sfGroup.Do(productCode, func() (interface{}, error) {
        // L2 → Proxy → Fallback
        return fetchAndCache(productCode), nil
    })
    return result.(string)
}
```

### 메모리 추정
- 활성 상품 ~100만~200만건 × ~220byte ≈ 220MB~440MB

## 2. L2 캐시 (ES 인덱스)

- **클러스터**: Main (`EsClient`)
- **인덱스명**: `image-cache-v1`, **alias**: `image-cache`
- **Document ID**: productCode (`_id` 직접 사용)

### 인덱스 설정
```json
{
  "mappings": {
    "properties": {
      "imageUrl": { "type": "keyword", "index": false },
      "updatedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1,
    "refresh_interval": "30s",
    "codec": "best_compression",
    "translog.durability": "async",
    "translog.sync_interval": "30s",
    "merge.scheduler.max_thread_count": 1,
    "unassigned.node_left.delayed_timeout": "5m"
  }
}
```

### 조회 최적화
- `_mget` + `Preference("_local")` 로 로컬 샤드 우선
- ES 클라이언트: 별도 `*elastic.Client` (MaxRetries: 1, 캐시 전용 타임아웃)
  - 기존 EsClient의 MaxRetries(5)는 캐시 조회에 과도

### 벌크 워밍 시 임시 설정
```
워밍 전: refresh_interval=-1, number_of_replicas=0
워밍 후: refresh_interval=30s, number_of_replicas=1, _forcemerge?max_num_segments=1
```

## 3. Proxy API 연동

- **형식**: `POST {baseURL}/api/images` body: `{"productCodes": ["123","456"]}`
- **응답**: `[{"productCode":"123","imageUrl":"https://..."}]`
- **HTTP 클라이언트**: `resty` 싱글톤 인스턴스 (connection pool 재사용)
- **타임아웃**: 50ms (기존 ES plugin 100-150ms 대비 비례)
- **배치 전략**: L1 miss → L2 _mget 1회 → 나머지 miss → proxy POST 1회

## 4. Circuit Breaker

- `atomic.Pointer[cbState]` + CAS 기반 (상태 일관성 보장)
- 연속 실패 3회 → circuit open (15초)
- Half-open 시 CAS로 단일 프로브만 허용
- Circuit open 시 즉시 fallback

## 5. Fallback 전략

- Cache miss + proxy 실패 시: **`utils.GetProductImageURLOriginal` 결과 반환 + WARN 로그**
- Fallback URL은 캐시에 저장하지 않음 (다음 요청 시 재시도)
- `defer func() { recover() }()` 추가 (기존 LogForPanic 패턴 준수)
- 미초기화 상태에서는 자동으로 레거시 URL 반환

---

## 패키지 구조 (아키텍처 리뷰 반영)

```
imagecache/                     ← 루트 레벨 (common/ 아님!)
  imagecache.go                 ← Init, GetProductImageURL, GetProductImageURLBatch
  sharded_cache.go              ← L1 sharded map 구현
  circuit_breaker.go            ← CAS 기반 circuit breaker
  proxy_client.go               ← resty 싱글톤 HTTP 클라이언트
  warmup.go                     ← 관리 API용 캐시 워밍/통계
```

### 의존성 방향 (레이어 역전 없음)
```
main.go ──→ imagecache.Init(esClient, proxyURL)
             ↓
imagecache/ ──→ elastic/v7 (라이브러리)
             ──→ common/config (설정)
             ──→ common/utils (fallback용 GetProductImageURLOriginal)
             ──→ golang.org/x/sync/singleflight
             ✗ elasticConn/ 직접 import 하지 않음 (main.go에서 주입)

handler/*-es.go ──→ imagecache.GetProductImageURL(code)
```

## 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `handler/product-es.go` (L412, L464) | `utils.GetProductImageURLOriginal` → `imagecache.GetProductImageURL` |
| `handler/rankingViewer-es.go` (L354, L401) | 동일 교체 |
| `handler/estimate-es.go` (L448) | 동일 교체 |
| `handler/openapi-es.go` (L104, L246) | 동일 교체 |
| `cmd/sapid/main.go` (L217 이후) | `imagecache.Init(elasticConn.EsClient, config.GetImageProxyURL())` 추가 |
| `common/config/config.go` | `GetImageProxyURL()`, `GetImageCacheTTL()` 등 설정 함수 추가 |
| `config/config.yml` | 환경별 `imageProxyURL` 설정 추가 |
| `router/managements.go` | `/managements/warm-image-cache`, `/managements/image-cache-stats` 추가 |
| `controller/managements.go` | `WarmImageCache()`, `ImageCacheStats()` 메서드 추가 |

---

## 핵심 함수 시그니처

```go
// imagecache/imagecache.go
package imagecache

var initOnce sync.Once

func Init(esClient *elastic.Client, proxyBaseURL string)
func GetProductImageURL(productCode string) string
func GetProductImageURLBatch(productCodes []string) map[string]string
func GetCacheStats() map[string]interface{}

// imagecache/sharded_cache.go
type ShardedCache struct { shards [256]cacheShard }
func NewShardedCache(ttl time.Duration) *ShardedCache
func (c *ShardedCache) Get(key string) (string, bool)
func (c *ShardedCache) Set(key, value string)
func (c *ShardedCache) GetMulti(keys []string) map[string]string  // L1 배치 조회

// imagecache/proxy_client.go
type ProxyClient struct { client *resty.Client; baseURL string }
func NewProxyClient(baseURL string, timeout time.Duration) *ProxyClient
func (c *ProxyClient) FetchImageURLs(productCodes []string) (map[string]string, error)

// imagecache/circuit_breaker.go
type CircuitBreaker struct { state atomic.Pointer[cbState] }
func NewCircuitBreaker(threshold int, timeout time.Duration) *CircuitBreaker
func (cb *CircuitBreaker) Allow() bool
func (cb *CircuitBreaker) RecordSuccess()
func (cb *CircuitBreaker) RecordFailure()
```

---

## 환경변수 추가

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `IMAGE_PROXY_URL` | Proxy API base URL | (필수) |
| `IMAGE_CACHE_TTL` | L1 캐시 TTL (시간 단위) | `24` |
| `IMAGE_CACHE_ES_INDEX` | L2 ES alias명 | `image-cache` |
| `IMAGE_CACHE_WARM_YN` | 기동 시 L2→L1 워밍 여부 | `N` |

---

## 구현 순서

1. **sharded_cache.go** - L1 sharded map (256샤드, TTL, GetMulti)
2. **circuit_breaker.go** - CAS 기반 circuit breaker
3. **proxy_client.go** - resty 싱글톤 Proxy API 클라이언트 (50ms 타임아웃)
4. **imagecache.go** - 통합 로직: L1→L2(_mget+singleflight)→Proxy→Fallback
5. **config 추가** - 환경변수/YAML 설정
6. **main.go 초기화** - `imagecache.Init()` 호출
7. **warmup.go** - scroll 기반 워밍 + 통계 API
8. **router/controller 추가** - 관리 엔드포인트 (기존 패턴 준수)
9. **handler 교체** - 7개 callsite에서 함수 교체 (기계적 변경)
10. **ES 인덱스 생성** - `image-cache-v1` + alias `image-cache`

---

## 검증 방법

1. **단위 테스트**: `go test ./imagecache/` - L1/L2/proxy/fallback 각 경로
2. **동시성 테스트**: singleflight, sharded cache, circuit breaker race condition
3. **수동 검증**:
   - `/product/search` 호출 → `productImageURL` 필드에 새 URL 확인
   - `GET /image-cache/_count` 로 캐시 적재 확인
   - `/managements/image-cache-stats` 로 hit/miss 비율 확인
4. **Fallback 검증**: `IMAGE_PROXY_URL`을 잘못된 값으로 → 레거시 URL 반환 확인
5. **부하 검증**: 기존 검색 응답 시간 대비 L1 hit 시 성능 저하 없음 확인
6. **Circuit breaker 검증**: proxy 다운 시 3회 실패 후 즉시 fallback 전환 확인
