# legacy-sync CI 규칙 정리: search-admin 패턴 + 모노레포 changes 필터

## Context

현재 legacy-sync CI 규칙이 search-api/dynamic-indexer에서 복사한 조건을 그대로 사용 중이다:
- `web` 파이프라인 소스 + `FORCE_BUILD_TARGET` — 이 프로젝트에서 사용하지 않는 기능
- MR 타겟 브랜치 필터 (`develop || main`) — 불필요한 복잡도

search-admin의 간결한 규칙 패턴을 따르되, 모노레포 특성상 `changes:` 필터를 추가하여 불필요한 파이프라인 실행을 방지한다.

## 변경 파일

| 파일 | 변경 |
|------|------|
| `bootstrap/legacy-sync/.gitlab/.gitlab-ci.yml` | 규칙 간소화 (search-admin 패턴 + changes 필터) |

> `.gitlab-ci.yml` (루트)는 변경 없음. `helm-update.yml` 유지 (1 pod 1 container이므로 helm-multi-update 불필요)

## 현재 vs 변경 후 비교

### 규칙 (Before)
```yaml
# 불필요한 web 트리거 + 복잡한 조건
.legacy_sync_ci_rules: &legacy_sync_ci_rules
  - if: '$CI_PIPELINE_SOURCE == "web" && $FORCE_BUILD_TARGET != "" && ...'  # ← 사용 안 함
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && ($CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "develop" || ...)'
    changes: *legacy_sync_changes
  - if: '$CI_PIPELINE_SOURCE == "push" && ($CI_COMMIT_BRANCH == "develop" || ...)'
    changes: *legacy_sync_changes
  - when: never
```

### 규칙 (After — search-admin 패턴)
```yaml
# MR → 테스트만 (코드 검증)
.mr_rules: &mr_rules
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    changes: *legacy_sync_changes

# main/develop push → 배포 (MR에서 이미 검증됨)
.deploy_rules: &deploy_rules
  - if: '$CI_COMMIT_BRANCH == "main" || $CI_COMMIT_BRANCH == "develop"'
    changes: *legacy_sync_changes
```

### 파이프라인 흐름 (Before vs After)

**Before** — ci_rules가 test~docker를 모두 커버:
```
MR:  test → image_tag → docker_build_push
Push: test → image_tag → docker_build_push → chart_update
```

**After** — search-admin 패턴으로 역할 분리:
```
MR:   test (코드 검증만)
Push: image_tag → docker_build_push → chart_update (배포만)
```

### helm 템플릿

`helm-update.yml` (`.helm_update_push`) 유지. 1 pod 1 container 구조이므로 `helm-multi-update` 불필요.

## 변경 상세

### 1. `bootstrap/legacy-sync/.gitlab/.gitlab-ci.yml`

```yaml
# changes 목록 — 유지 (모노레포 필터)
.legacy_sync_changes: &legacy_sync_changes
  - .gitlab-ci.yml
  - bootstrap/legacy-sync/**/*
  - shared/**/*
  - domain/cdc/**/*
  - domain/index/**/*
  - domain/proxy/**/*
  - application/index/**/*
  - inbound-adapter/legacy/**/*
  - outbound-adapter/proxy/**/*
  - outbound-adapter/legacy/**/*
  - outbound/client/legacy-api/**/*
  - outbound/client/proxy-api/**/*
  - outbound/repository/cache/**/*

# MR → 테스트 (코드 검증)
.mr_rules: &mr_rules
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    changes: *legacy_sync_changes

# Push → 배포 (main/develop)
.deploy_rules: &deploy_rules
  - if: '$CI_COMMIT_BRANCH == "main" || $CI_COMMIT_BRANCH == "develop"'
    changes: *legacy_sync_changes

# Jobs
legacy_sync_test:         rules: *mr_rules
legacy_sync_image_tag:    rules: *deploy_rules,  needs: []
legacy_sync_docker_build_push: rules: *deploy_rules,  needs: [image_tag]
legacy_sync_chart_update: rules: *deploy_rules,  needs: [docker_build_push, image_tag]
```

핵심 변경:
- `web` + `FORCE_BUILD_TARGET` 제거
- MR 타겟 브랜치 필터 제거 (어떤 브랜치 대상 MR이든 테스트)
- test는 MR에서만, 배포는 push에서만 (search-admin 패턴)
- `image_tag`는 `needs: []`로 test와 독립 (push 파이프라인에서 test가 안 돌므로)
- `.helm_update_push` 유지 (1 pod 1 container)

## 검증

1. **MR 파이프라인**: `legacy_sync_test`만 실행, image_tag/docker/chart_update 미실행
2. **develop push**: `legacy_sync_image_tag` → `docker_build_push` → `chart_update` (values-dev.yaml)
3. **main push**: 동일 흐름 (values-prod.yaml)
4. **무관한 파일 변경**: `domain/search/**` 변경 시 legacy-sync 파이프라인 미실행 (changes 필터)
