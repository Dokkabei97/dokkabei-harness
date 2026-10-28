---
name: deprecation-guide
description: |
  시스템·모듈·API 폐기와 소비자 이관 가이드 — 폐기 결정 5질문, 권고형/강제형 구분, 대체 구축→공지→점진 이관→사용량 0 확인 후 제거, Strangler·Adapter·Feature Flag 패턴, 좀비 코드 신호.
  Deprecation and migration guide: decision questions, advisory vs compulsory, replace-announce-migrate-remove process, Strangler/Adapter/Feature-Flag patterns, zombie-code signals.
  Use when: "폐기", "레거시 제거", "마이그레이션 계획", "좀비 코드", "API 버전 전환", deprecating a system or API, removing dead code.
---

# Deprecation & Migration Guide

핵심 전제: **Hyrum's Law** — 사용자가 충분히 많으면 API 의 모든 관찰 가능한 동작(버그·타이밍 포함)에
누군가 의존한다. 공지만으로는 이관되지 않으므로 능동적 이관과 사용량 측정이 필요하다.

## 1. 결정

| # | 질문 | 판단 |
|---|------|------|
| 1 | 아직 고유한 가치가 있는가? | 대체 불가 기능이 있으면 보류 |
| 2 | 소비자는 몇인가? | 호출처·트래픽으로 정량화 |
| 3 | 대체가 존재하는가? | **없으면 먼저 구축** |
| 4 | 소비자별 이관 비용은? | 자동화 가능하면 소유자가 수행 |
| 5 | 유지 비용은? | 보안·운영 시간·복잡성 |

- **Advisory**: 이관 선택적, 구 시스템 안정 — 경고 로그·문서
- **Compulsory**: 보안·차단 이슈 — 확정 기한 + 이관 도구/가이드 제공 필수
- **Churn Rule**: 인프라/라이브러리 소유자가 이관 책임을 진다(또는 하위 호환을 제공)

## 2. 프로세스

1. **대체 구축** — 핵심 유스케이스 커버, 프로덕션 검증
2. **공지** — 상태·대체·제거 예정일·이유·이관 가이드·담당자. 코드에는 언어별 deprecation 표시
   (Kotlin `@Deprecated(replaceWith = ReplaceWith(...))`, Go `// Deprecated:` 주석 단락 — `staticcheck` SA1019 가 사용처를 경고)
3. **점진 이관** — 소비자별: 접점 식별 → 교체 → 테스트 → 구 참조 제거
4. **제거** — 사용량 0 을 메트릭/로그로 확인 → 코드·테스트·문서·설정 삭제 → 스키마 정리는 expand-contract 의 contract 단계로

## 3. 패턴

| 패턴 | 방식 | 적합 |
|------|------|------|
| Strangler | 신구 병렬, 트래픽 0→100% 이동 | 대규모 교체, API 버전 전환 |
| Adapter | 구 인터페이스 유지, 내부만 신구현 위임 | 소비자가 많아 인터페이스 즉시 변경 불가 |
| Feature Flag | 소비자/요청별 분기 | 점진 전환, 비교, 빠른 롤백 |

## 4. 좀비 코드 신호

6개월+ 무커밋인데 소비자 존재 / 소유자 없음 / 방치된 실패 테스트 / CVE 방치 의존성 / 사라진 시스템을 가리키는 문서.
발견 시: 소유자 확인 → 폐기 여부 결정 → 위 프로세스.

## Red Flags

대체 없는 폐기 공지, 이관 도구 없는 기한, 수년째 진전 없는 소프트 폐기, 폐기된 시스템에 새 기능, 사용량 측정 없이 삭제.

## Related

- `workflow:shipping-guide` — 대체 시스템의 플래그·롤아웃
- `observe:observe-report` — 하네스 자산(스킬·커맨드)의 미사용 후보 탐지
