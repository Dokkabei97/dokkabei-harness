# shared-resources ConfigMap → 개별 서비스 ConfigMap 마이그레이션

## Context

`apps/next-search/shared-resources/`는 인프라 연결 정보(Elasticsearch, Valkey, Keyword Analysis)를 하나의 공통 ConfigMap으로 관리하고, 4개 서비스가 `envFrom`으로 참조하는 구조이다.
이를 각 서비스가 자체 ConfigMap에서 직접 관리하도록 변경하여, 서비스별 독립 배포와 설정 커스터마이징을 가능하게 한다.

## 설계 결정: `values-config.yaml` vs 기존 values 파일

**결정: 기존 `values-dev.yaml` / `values-prod.yaml`에 통합**

| 기준 | values-config.yaml 분리 | 기존 파일에 통합 |
|------|------------------------|----------------|
| 레포 컨벤션 | 전체 레포에 선례 없음 | fixity-shopping 등 모든 서비스가 이 패턴 |
| CI/CD 영향 | `helm upgrade` 명령에 `-f` 추가 필요 | 변경 없음 |
| 추가 라인 수 | - | 서비스당 ~15줄 추가 |
| 설정 파악 | 파일 2개 봐야 함 | 한 파일에서 전체 환경 설정 확인 |

## 변경 대상 파일 (총 14개)

### Phase 1: ConfigMap 템플릿 수정 (4 파일)

각 서비스의 `templates/configmap.yaml`에 인프라 설정 블록 추가:

**1. `search-api/templates/configmap.yaml`** (line 21 이후 추가)
```yaml
  # ===== 인프라 공통 설정 (shared-resources에서 이관) =====
  {{- with .Values.config.elasticsearch }}
  ELASTICSEARCH_URLS: {{ .urls | quote }}
  ELASTICSEARCH_CONNECTION_TIMEOUT: {{ .connectionTimeout | quote }}
  ELASTICSEARCH_SOCKET_TIMEOUT: {{ .socketTimeout | quote }}
  {{- end }}
  {{- with .Values.config.valkey }}
  {{- with .backend }}
  VALKEY_BACKEND_HOST: {{ .host | quote }}
  VALKEY_BACKEND_PORT: {{ .port | quote }}
  VALKEY_BACKEND_DATABASE: {{ .database | quote }}
  VALKEY_BACKEND_MAX_CONNECTION: {{ .maxConnection | quote }}
  VALKEY_BACKEND_CLUSTER_MODE: {{ .clusterMode | quote }}
  {{- end }}
  {{- end }}
  {{- with .Values.config.keywordAnalysis }}
  KEYWORD_ANALYSIS_URL: {{ .url | quote }}
  KEYWORD_ANALYSIS_CONNECTION_TIMEOUT: {{ .connectionTimeout | quote }}
  KEYWORD_ANALYSIS_SOCKET_TIMEOUT: {{ .socketTimeout | quote }}
  {{- end }}
```

**2. `legacy-sync/templates/configmap.yaml`** (line 21 이후 추가)
- search-api와 동일한 블록 추가

**3. `dynamic-indexer/templates/configmap.yaml`** (line 29 이후 추가)
- `KEYWORD_ANALYSIS_*`는 이미 존재(line 27-29) → **elasticsearch + valkey만** 추가
```yaml
  {{- with .Values.config.elasticsearch }}
  ELASTICSEARCH_URLS: {{ .urls | quote }}
  ELASTICSEARCH_CONNECTION_TIMEOUT: {{ .connectionTimeout | quote }}
  ELASTICSEARCH_SOCKET_TIMEOUT: {{ .socketTimeout | quote }}
  {{- end }}
  {{- with .Values.config.valkey }}
  {{- with .backend }}
  VALKEY_BACKEND_HOST: {{ .host | quote }}
  VALKEY_BACKEND_PORT: {{ .port | quote }}
  VALKEY_BACKEND_DATABASE: {{ .database | quote }}
  VALKEY_BACKEND_MAX_CONNECTION: {{ .maxConnection | quote }}
  VALKEY_BACKEND_CLUSTER_MODE: {{ .clusterMode | quote }}
  {{- end }}
  {{- end }}
```

**4. `search-admin/templates/configmap.yaml`** (line 9 이후 추가)
- search-api와 동일한 블록 추가 (elasticsearch + valkey + keywordAnalysis)

### Phase 2: Values 파일에 인프라 설정 추가 (8 파일)

각 서비스의 `config:` 블록에 아래 값 추가. 값은 `shared-resources/values/`에서 복사.

**Dev 환경 (`values-dev.yaml`) — 4개 서비스:**

`search-api`, `legacy-sync`, `search-admin`의 `config:` 블록에 추가:
```yaml
config:
  # ... 기존 설정 유지 ...
  elasticsearch:
    urls: "http://dev-cmn-es-http:9200"
    connectionTimeout: "5000"
    socketTimeout: "5000"
  valkey:
    backend:
      host: "dev-cmn-infra-valkey-cluster-headless.cmn-infra.svc.cluster.local"
      port: "6379"
      database: "0"
      maxConnection: "10"
      clusterMode: "true"
  keywordAnalysis:
    url: "http://dev-cmn-es-data:9200"
    connectionTimeout: "5000"
    socketTimeout: "5000"
```

`dynamic-indexer/values/values-dev.yaml` — `config:` 블록에 `elasticsearch`와 `valkey`만 추가:
```yaml
config:
  # ... 기존 설정(profile, index, kafka, keywordAnalysis 등) 유지 ...
  elasticsearch:
    urls: "http://dev-cmn-es-http:9200"
    connectionTimeout: "5000"
    socketTimeout: "5000"
  valkey:
    backend:
      host: "dev-cmn-infra-valkey-cluster-headless.cmn-infra.svc.cluster.local"
      port: "6379"
      database: "0"
      maxConnection: "10"
      clusterMode: "true"
```
(keywordAnalysis는 이미 line 87-90에 존재)

**Prod 환경 (`values-prod.yaml`) — 4개 서비스:**

`search-api`, `legacy-sync`, `search-admin`의 `config:` 블록에 추가:
```yaml
config:
  # ... 기존 설정 유지 ...
  elasticsearch:
    urls: "http://cmn-elasticsearch.danuricorp.com:80"
    connectionTimeout: "5000"
    socketTimeout: "5000"
  valkey:
    backend:
      host: "cmn-valkey.danuricorp.com"
      port: "6379"
      database: "0"
      maxConnection: "10"
      clusterMode: "true"
  keywordAnalysis:
    url: "http://cmn-keyword-analysis-api.danuricorp.com:80"
    connectionTimeout: "5000"
    socketTimeout: "5000"
```

`dynamic-indexer/values/values-prod.yaml` — 특수 케이스:
- 이미 자체 `config.elasticsearch` 구조를 사용 중 (frontend/backend 분리 패턴)
- `envFrom`이 없는 별도 구조이므로, shared-resources 참조가 없음
- **prod values는 변경하지 않음** (이미 독립 구조)

### Phase 3: envFrom에서 shared ConfigMap 참조 제거 (8 파일)

각 서비스의 `values-dev.yaml`과 `values-prod.yaml`에서 공통 ConfigMap 참조 삭제:

**search-api, legacy-sync, dynamic-indexer (단일 컨테이너 패턴)**:
```yaml
# Before
envFrom:
  - configMapRef:
      name: dev-cmn-search-config        # ← 삭제
  - configMapRef:
      name: dev-cmn-{service}-config
  - secretRef:
      name: "dev-cmn-search-credentials"

# After
envFrom:
  - configMapRef:
      name: dev-cmn-{service}-config
  - secretRef:
      name: "dev-cmn-search-credentials"
```

**search-admin (multi-container 패턴)**:
`containers[0].envFrom`에서 동일하게 공통 ConfigMap 참조 삭제

**dynamic-indexer prod**: envFrom이 없으므로 변경 없음

### Phase 4: shared-resources 정리 (선택)

모든 서비스 마이그레이션 및 검증 완료 후:
- `apps/next-search/shared-resources/` 디렉토리 삭제
- 클러스터에서 shared-resources Helm release 삭제
- `CLAUDE.md` 업데이트 (3-layer → 2-layer 패턴 반영)

## 작업 순서

1. **legacy-sync** (dev → prod) — 가장 단순, 파일럿
2. **search-api** (dev → prod) — legacy-sync와 동일 패턴
3. **search-admin** (dev → prod) — multi-container이므로 주의
4. **dynamic-indexer** (dev만) — prod는 이미 독립 구조

## 검증 방법

각 서비스 수정 후:

```bash
# 1. Helm 템플릿 렌더링 비교
helm template shared apps/next-search/shared-resources \
  -f apps/next-search/shared-resources/values/values-dev.yaml > /tmp/shared.yaml

helm template <svc> apps/next-search/<svc> \
  -f apps/next-search/<svc>/values/values-dev.yaml > /tmp/after.yaml

# 2. shared ConfigMap의 env var가 service ConfigMap에 모두 포함되는지 확인
# ELASTICSEARCH_URLS, VALKEY_BACKEND_HOST, KEYWORD_ANALYSIS_URL 등 11개 키 검증

# 3. helm lint 통과 확인
helm lint apps/next-search/<svc> -f apps/next-search/<svc>/values/values-dev.yaml
```

## 제외/드롭 항목

shared-resources 템플릿에는 있지만 values에 값이 없는 섹션은 마이그레이션하지 않음:
- `VALKEY_FRONT_*` (5개 env var) — values 미정의
- `MONGODB_BACKEND_*` (2개 env var) — values 미정의

향후 필요 시 개별 서비스에 추가 가능.
