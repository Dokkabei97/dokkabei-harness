# kubectl delete 안전 검사 스크립트

## Context

개발서버에서 시크릿 매니페스트를 `kubectl delete -f`로 제거하려다, 같은 파일에 포함된 `Namespace` 정의까지 삭제되면서 네임스페이스 내 전체 리소스가 날아가는 장애 발생. 이런 실수를 방지하기 위해 매니페스트 파일 내 위험 리소스를 사전에 감지하고 경고하는 래퍼 스크립트를 만든다.

## 생성 파일

**`scripts/safe-kubectl-delete.sh`** (신규 생성, ~250줄)

## 핵심 기능

### 1. YAML 파싱 (이중 전략)
- **Primary**: `kubectl apply --dry-run=client -o json` → `jq`로 kind/name/namespace 추출
- **Fallback**: `awk` 기반 파싱 (kubectl 실패 시, Helm 템플릿 `{{ }}` 감지 시)

### 2. 심각도 분류 (3단계)

| 등급 | 리소스 종류 | 이유 |
|------|------------|------|
| **CRITICAL** | Namespace, PersistentVolumeClaim, PersistentVolume, CustomResourceDefinition, Elasticsearch, PerconaServerMongoDB, StatefulSet | 데이터 손실 / 대규모 장애 |
| **HIGH** | ClusterRole, ClusterRoleBinding, ValidatingWebhookConfiguration, MutatingWebhookConfiguration, ServiceAccount, StorageClass | 클러스터 영향 |
| **MEDIUM** | Deployment, Service, ConfigMap, Secret, Ingress, HTTPRoute, Gateway, VirtualService, HorizontalPodAutoscaler, DaemonSet | 서비스 중단 |

### 3. 확인 흐름
- **CRITICAL 포함**: 리소스별 한글 위험 설명 출력 → `yes` 정확히 입력 요구 → 3초 카운트다운
- **HIGH 포함**: `y`/`yes` 입력 요구
- **MEDIUM 이하**: `y`/`yes` 입력 요구 (--force 시 생략 가능)

### 4. 사용법
```bash
# 기본 사용
scripts/safe-kubectl-delete.sh manifest.yaml

# 검사만 (삭제 안 함)
scripts/safe-kubectl-delete.sh --dry-run manifest.yaml

# 디렉토리 스캔
scripts/safe-kubectl-delete.sh --dry-run ./infra/pvc-shared/

# context/namespace 지정
scripts/safe-kubectl-delete.sh --context dev-cluster -n dev-search secret.yaml
```

## 스크립트 구조

```bash
#!/bin/bash
set -euo pipefail

# ── 상수 ──
# 색상 코드 (RED, GREEN, YELLOW, BLUE, NC)
# 심각도별 리소스 종류 문자열 목록

# ── 유틸 함수 ──
# print_error(), print_warning(), print_info(), print_success(), usage()

# ── 핵심 함수 ──
# classify_severity(kind)         → CRITICAL/HIGH/MEDIUM/LOW 반환
# parse_kinds_from_file(file)     → kubectl dry-run + jq 파싱
# parse_kinds_fallback(file)      → awk 기반 폴백 파싱
# get_critical_warning(kind,name) → 종류별 한글 위험 설명
# print_resource_summary()        → 리소스 테이블 출력
# confirm_deletion(max_severity)  → 심각도별 확인 프롬프트
# execute_delete(target)          → kubectl delete -f 실행

# ── 메인 ──
# 인자 파싱 → 전제조건 검증 → 파일/디렉토리 스캔 → 요약 출력 → 확인 → 실행
```

## 출력 예시

```
================================================================================
  kubectl delete 안전 검사 도구
================================================================================

[검사 대상] secret-manifest.yaml

────────────────────────────────────────────────────────────────
  #   심각도       종류(Kind)                 이름              네임스페이스
  1   CRITICAL     Namespace                  dev-search        -
  2   MEDIUM       Secret                     common-mongodb..  dev-search
  3   MEDIUM       Secret                     common-elastic..  dev-search
────────────────────────────────────────────────────────────────

  CRITICAL: 1개  |  HIGH: 0개  |  MEDIUM: 2개

!! 경고 !!  CRITICAL 등급 리소스가 포함되어 있습니다!

  - Namespace 'dev-search' 삭제 시 해당 네임스페이스 내 모든 리소스가 삭제됩니다.

  CRITICAL 리소스를 삭제하려면 'yes'를 정확히 입력하세요:
```

## 컨벤션 준수 사항
- `set -euo pipefail` (codex-hooks 패턴)
- 색상 코드: RED/GREEN/YELLOW/BLUE/NC (check-cluster-resources.sh 패턴)
- 한글 메시지 (기존 스크립트 동일)
- macOS bash 3.2 호환 (연관 배열 미사용, 문자열 목록 + for 루프)
- 필수 도구: `kubectl`, `jq`

## 엣지 케이스 처리
- Helm 템플릿 (`{{ }}`) → 감지 후 awk 폴백 + 경고
- 빈 YAML 문서 (`---`만 있는 경우) → 건너뜀
- kubectl 연결 실패 → awk 폴백 자동 전환
- `--force`에도 CRITICAL은 반드시 확인 요구

## 검증 방법
```bash
# 1. dry-run으로 PVC 파일 검사 (CRITICAL 감지 확인)
scripts/safe-kubectl-delete.sh --dry-run infra/pvc-shared/search-dictionary-shared-pvc.yaml

# 2. 다중 문서 파일 검사
scripts/safe-kubectl-delete.sh --dry-run infra/pvc-shared/afs-shared-nas.yaml

# 3. 디렉토리 전체 스캔
scripts/safe-kubectl-delete.sh --dry-run infra/pvc-shared/

# 4. Helm 템플릿 파일 (폴백 동작 확인)
scripts/safe-kubectl-delete.sh --dry-run apps/next-search/search-api/templates/deployment.yaml

# 5. helm lint 통과 확인 (기존 차트에 영향 없음)
helm lint apps/next-search/search-api
```
