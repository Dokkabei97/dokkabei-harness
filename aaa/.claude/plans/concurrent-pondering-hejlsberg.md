# Plan: `legacy-sync` Helm Chart 생성

## Context
`apps/next-search/` 하위에 새로운 `legacy-sync` 서비스의 Helm 차트를 생성합니다. 기존 `dynamic-indexer`와 `search-api` 차트의 공통 패턴을 따르되, `search-api`의 심플한 ConfigMap 패턴을 기반으로 합니다.

## 생성할 파일 구조 (11개 파일)

```
apps/next-search/legacy-sync/
├── .helmignore              # 표준 Helm ignore 패턴
├── Chart.yaml               # name: legacy-sync, apiVersion: v2
├── values.yaml              # 기본값 (image: harbor.cowave.kr/search/legacy-sync)
├── values/
│   ├── values-dev.yaml      # dev-cmn-legacy-sync, 1 replica, 1CPU/2Gi
│   └── values-prod.yaml     # cmn-legacy-sync, HPA 2-5, 2CPU/4Gi
└── templates/
    ├── _helpers.tpl          # legacy-sync.* 헬퍼 함수 6종
    ├── configmap.yaml        # OTEL + search index 환경변수
    ├── deployment.yaml       # Spring Boot 앱 Deployment
    ├── hpa.yaml              # 조건부 HPA (autoscaling.enabled)
    ├── ingress.yaml          # 조건부 Ingress (nginx)
    ├── NOTES.txt             # 배포 후 안내 메시지
    ├── service.yaml          # ClusterIP:8080
    ├── serviceaccount.yaml   # 조건부 ServiceAccount
    └── tests/
        └── test-connection.yaml  # Helm test pod
```

## 주요 설계 결정

| 항목 | 결정 | 근거 |
|------|------|------|
| Chart name | `legacy-sync` | search-api 패턴 (환경 prefix는 nameOverride에서) |
| ConfigMap | OTEL + index 설정만 | search-api의 심플한 패턴 (Kafka 설정 없음) |
| Dev 리소스 | 1 replica, 1CPU/2Gi | 신규 서비스 보수적 시작 |
| Prod 리소스 | HPA 2-5, 2CPU/4Gi | 부하 프로파일 미확인 상태의 합리적 기본값 |
| envFrom 참조 | 공통ConfigMap + 서비스ConfigMap + Secret | search-api와 동일한 3-reference 패턴 |
| Image | `harbor.cowave.kr/search/legacy-sync` | 기존 레지스트리 네이밍 컨벤션 준수 |

## 구현 순서

1. 디렉토리 생성 (`legacy-sync/`, `templates/`, `templates/tests/`, `values/`)
2. `Chart.yaml`, `.helmignore` 생성
3. `values.yaml` (기본값) 생성
4. `templates/` 하위 모든 템플릿 파일 생성 (search-api 기반, `legacy-sync`으로 치환)
5. `values/` 환경별 values 파일 생성 (dev, prod)
6. `helm lint`로 검증

## 검증 방법

```bash
# Lint 검증
helm lint apps/next-search/legacy-sync

# Dev 환경 dry-run 렌더링
helm template legacy-sync apps/next-search/legacy-sync \
  -f apps/next-search/legacy-sync/values/values-dev.yaml

# Prod 환경 dry-run 렌더링
helm template legacy-sync apps/next-search/legacy-sync \
  -f apps/next-search/legacy-sync/values/values-prod.yaml
```

## 참고 파일 (복사 기반)
- `apps/next-search/search-api/templates/*` → 모든 템플릿의 기본 소스
- `apps/next-search/search-api/values.yaml` → 기본값 구조
- `apps/next-search/search-api/values/values-dev.yaml` → dev 환경 패턴
