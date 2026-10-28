---
name: shipping-guide
description: |
  프로덕션 배포 전후 가이드 — 배포 전 체크리스트, 피처 플래그 수명주기, 단계적 롤아웃과 진행/보류/롤백 임계값, 롤백 계획 템플릿, 배포 후 모니터링.
  Production shipping guide: pre-launch checklist, feature-flag lifecycle, staged rollout with go/hold/rollback thresholds, rollback plan template, post-launch monitoring.
  Use when: "배포 준비", "릴리즈 전 점검", "롤아웃 계획", "롤백 계획", preparing a production deploy, staged rollout, feature flags.
---

# Shipping Guide — 배포 및 런칭

검증 명령·마이그레이션 도구·헬스체크 경로는 프로젝트마다 다르다 — 프로젝트 CLAUDE.md
(또는 `workflow:project-rules` 블록)와 빌드 파일에서 확인해 아래 항목을 구체화한다.

## Pre-Launch Checklist

- **품질**: 테스트·빌드·린트 통과, 리뷰 승인, 임시 디버그 로그 제거
- **보안**: 하드코딩 시크릿 없음, 의존성 취약점 스캔, 입력 검증·인가 적용, CORS/레이트 리밋 의도대로
- **성능**: 새 조회 경로의 N+1·인덱스, 응답 시간 목표, 대용량은 스트리밍/페이지네이션
- **인프라**: 환경변수, 스키마 마이그레이션의 무중단 호환(expand-contract), 헬스체크, 구조화 로그, 리소스 요청/제한
- **문서**: API 문서, 변경 설명(MR/PR·Changelog), 운영 메모(새 설정·알람)

## Feature Flags

```
DEPLOY(OFF) → 내부/베타 → 5% → 25% → 50% → 100% → 플래그 코드 정리
```
- 큰 변경은 킬 스위치를 둔다. 플래그마다 담당자·만료일, 100% 후 2주 내 정리
- 이름은 의미 기반: `order-async-processing-enabled`

## Staged Rollout 임계값 (베이스라인 대비)

| 메트릭 | 진행 | 보류 | 롤백 |
|--------|------|------|------|
| Error rate | ±10% | +10~100% | 2배 초과 |
| P95 latency | ±20% | +20~50% | +50% 초과 |
| DB query time | 정상 | slow query 증가 | 타임아웃 |
| 비즈니스 지표 | 중립/긍정 | <5% 감소 | >5% 감소 |

각 단계 1~2일 관찰이 일반적이며, 트래픽이 적은 서비스는 단계 시간을 늘린다.

## Rollback Plan (배포 전에 작성)

```markdown
## Rollback Plan: [기능]
- Trigger: error rate 2배 / P95 > [값] / 핵심 플로우 실패
- Steps: 1) 플래그 OFF  2) 이전 버전 재배포  3) 스키마 변경 포함 시 —
  expand 단계면 새 컬럼 무시로 충분, 비호환 변경이면 프로젝트 마이그레이션 도구의 down/수동 스크립트
- 예상 시간: 플래그 <1분 / 재배포 <10분 / DB 별도 판단
```

## Post-Launch (최소 1시간)

헬스체크, 에러율, P95/P99, 핵심 사용자 플로우 수동 확인, 로그 흐름, 플래그 OFF 동작 확인.

## Related

- `workflow:deprecation-guide` — 구 시스템 폐기와 함께 배포할 때
- `/release-notes` — 릴리즈 노트·다음 버전(GitLab)
- `/review-mr` — 배포 전 최종 리뷰(GitLab)
