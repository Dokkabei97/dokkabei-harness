---
name: shipping-guide
description: Use this skill when preparing to deploy a feature or service to production. Covers pre-launch checklist, feature flags, staged rollout, rollback strategy, and post-launch monitoring for backend services (Kotlin/Spring Boot, Python/FastAPI).
---

# Shipping Guide — 배포 및 런칭 가이드

프로덕션 배포 전후의 체계적 검증 프로세스. 안전한 롤아웃, 모니터링, 롤백 전략을 포함한다.

## When to Activate

- 새 기능을 프로덕션에 배포할 때
- 서비스 인프라를 변경할 때
- DB 마이그레이션을 프로덕션에 적용할 때
- 피처 플래그로 점진적 롤아웃을 수행할 때

---

## Pre-Launch Checklist

### 1. Code Quality
- [ ] 모든 테스트 통과 (`./gradlew test` / `pytest`)
- [ ] 빌드 성공 (`./gradlew build`)
- [ ] 린트/타입체크 통과 (`ktlint` / `ruff` / `mypy`)
- [ ] 코드 리뷰 완료 (MR 승인)
- [ ] TODO/FIXME 잔존 없음 (의도적인 것 제외)
- [ ] 디버그 로그 제거 (`println`, `print()`, `log.debug`의 임시 사용)

### 2. Security
- [ ] 시크릿이 코드/설정에 하드코딩되지 않음
- [ ] 의존성 취약점 스캔 통과 (`./gradlew dependencyCheckAnalyze` / `pip-audit` / `trivy`)
- [ ] 입력값 검증 적용 (Bean Validation / Pydantic)
- [ ] 인증/인가 적용 확인
- [ ] 레이트 리밋 설정 확인
- [ ] CORS 설정이 의도한 범위인지 확인

### 3. Performance
- [ ] N+1 쿼리 없음 (신규 데이터 조회 로직)
- [ ] 필요한 DB 인덱스 추가됨
- [ ] API 응답 시간 목표 이내 (P95 < 200ms 등)
- [ ] 커넥션 풀 사이즈 적절 (HikariCP / SQLAlchemy pool)
- [ ] 캐싱 전략 적용 (해당하는 경우)
- [ ] 대용량 데이터 처리 시 스트리밍/페이지네이션 사용

### 4. Infrastructure
- [ ] 환경변수 설정 완료 (staging/production)
- [ ] DB 마이그레이션 준비 (Flyway/Alembic, 무중단 호환성 확인)
- [ ] 헬스체크 엔드포인트 동작 (`/actuator/health` / `/health`)
- [ ] 로깅 설정 확인 (구조화된 JSON 로그, 적절한 레벨)
- [ ] 시크릿 매니저 연동 (Vault / K8s Secret)
- [ ] 리소스 요청/제한 설정 (K8s resources)

### 5. Documentation
- [ ] API 문서 업데이트 (OpenAPI / GraphQL SDL)
- [ ] 변경 사항 설명 (MR description 또는 Changelog)
- [ ] 아키텍처 결정 기록 (ADR, 해당하는 경우)
- [ ] 운영 가이드 (새 설정, 모니터링 항목 등)

---

## Feature Flag Strategy

### 라이프사이클

```
DEPLOY (OFF) → ENABLE (팀/베타) → GRADUAL ROLLOUT → MONITOR → CLEAN UP
                                   5% → 25% → 50% → 100%
```

### 피처 플래그 규칙
- 모든 주요 기능 변경에 피처 플래그 적용 (킬 스위치)
- 각 플래그에 **만료일**과 **담당자** 지정
- 100% 롤아웃 후 **2주 이내** 플래그 코드 정리
- 플래그 이름은 의미를 담는다: `order-async-processing-enabled` (O) / `flag-123` (X)

```kotlin
// Kotlin/Spring Boot
@ConditionalOnProperty("feature.order-async-processing.enabled")
@Service
class AsyncOrderProcessor { /* ... */ }

// 또는 런타임 체크
if (featureToggle.isEnabled("order-async-processing")) {
    asyncOrderProcessor.process(order)
} else {
    syncOrderProcessor.process(order)
}
```

---

## Staged Rollout

| 단계 | 대상 | 기간 | 검증 |
|------|------|------|------|
| 1. Staging | 스테이징 환경 | — | 기능 검증, 통합 테스트 |
| 2. Prod (OFF) | 프로덕션 배포, 플래그 OFF | — | 배포 자체의 안정성 확인 |
| 3. Internal | 내부 사용자/팀 | 1일 | 실제 데이터로 기능 확인 |
| 4. 5% | 전체 트래픽 5% | 1~2일 | 에러율, 레이턴시 모니터링 |
| 5. 25% | 전체 트래픽 25% | 1~2일 | 부하 패턴 확인 |
| 6. 50% | 전체 트래픽 50% | 1~2일 | 안정성 최종 확인 |
| 7. 100% | 전체 트래픽 | — | GA, 플래그 정리 일정 수립 |

### Rollout Decision Thresholds

| 메트릭 | 진행 (Green) | 보류 (Yellow) | 롤백 (Red) |
|--------|-------------|--------------|-----------|
| Error rate | 베이스라인 대비 ±10% | 10~100% 증가 | 2배 초과 |
| P95 latency | ±20% | 20~50% 증가 | 50% 초과 |
| DB query time | 정상 범위 | slow query 증가 | 타임아웃 발생 |
| Business metrics | 중립 또는 긍정 | <5% 감소 | >5% 감소 |

---

## Rollback Strategy

배포 전에 롤백 계획을 **반드시 문서화**한다:

```markdown
## Rollback Plan: [기능명]

### Trigger Conditions
- Error rate > 베이스라인 2배
- P95 latency > 500ms (목표 200ms의 2.5배)
- 크리티컬 유저 플로우 실패

### Rollback Steps
1. 피처 플래그 OFF (즉시 효과, 코드 롤백 불필요)
2. 피처 플래그로 해결 안 되면: 이전 버전 재배포
3. DB 마이그레이션이 포함된 경우:
   - Expand-contract 패턴 사용 시: 새 컬럼만 무시 (롤백 불필요)
   - 비호환 변경 시: `flyway undo` / `alembic downgrade -1`

### Estimated Rollback Time
- 피처 플래그: < 1분
- 재배포: < 10분 (CI/CD 파이프라인)
- DB 롤백: 별도 판단 필요
```

---

## Post-Launch Monitoring

배포 후 **최소 1시간** 동안 모니터링:

- [ ] 헬스체크 200 OK
- [ ] Error rate 정상 (Sentry / Grafana)
- [ ] P95/P99 레이턴시 목표 이내 (Grafana / Prometheus)
- [ ] 크리티컬 유저 플로우 수동 테스트 (주문 생성, 결제 등)
- [ ] 로그 정상 흐름 (Kibana / Loki)
- [ ] 롤백 메커니즘 동작 확인 (피처 플래그 OFF 테스트)

---

## Common Rationalizations

| Rationalization | Reality |
|----------------|---------|
| "스테이징에서 됐으니 프로덕션도 될 것" | 프로덕션은 다른 데이터/트래픽/엣지케이스. 모니터링 필수 |
| "피처 플래그 불필요, 간단한 변경" | 모든 기능에 킬 스위치 필요. "간단한" 변경도 깨질 수 있다 |
| "모니터링은 나중에 추가" | 런칭 전에 추가. 보이지 않으면 디버깅 불가 |
| "롤백은 실패를 인정하는 것" | 롤백은 책임감 있는 엔지니어링. 깨진 기능 배포가 진짜 실패 |
| "금요일 오후에 배포하자" | 금요일 오후 배포는 주말 장애 대응 리스크. 주 초~중에 배포 |

## Red Flags

- 롤백 계획 없는 배포
- 프로덕션에 모니터링/에러 리포팅 없음
- 전체 한 번에 배포 (staged rollout 없이)
- 만료일 없는 피처 플래그
- 배포 후 1시간 모니터링 미수행

## Verification

- [ ] Pre-Launch Checklist 전체 완료
- [ ] 피처 플래그 설정 및 테스트
- [ ] 롤백 계획 문서화
- [ ] 모니터링 대시보드 준비
- [ ] 팀에 배포 알림 발송

---

## Related

- `spec-driven-dev` — 배포할 기능의 스펙 확인
- `deprecation-guide` — 기존 시스템 폐기와 함께 배포할 때
- `/review-mr` — 배포 전 최종 코드 리뷰
