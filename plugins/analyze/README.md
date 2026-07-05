# analyze

> 코드 품질·보안·성능·아키텍처·SQL을 정적 분석하고, 심각도 등급이 매겨진 개선안을 제시하는 종합 코드 분석 플러그인.

## 개요

`analyze`는 소스를 수정하지 않고 읽기 전용으로 훑어 코드의 구조적 문제를 찾아내는 정적 분석 도구 모음이다. 여러 도메인을 한 번에 보는 종합 커맨드(`/analyze`)와, 아키텍처·성능·SQL 각각을 깊게 파고드는 전문 커맨드(`/arch-review`, `/perf-review`, `/sql-analyze`)로 나뉜다. 각 전문 커맨드는 동일 도메인을 담당하는 전용 에이전트(`arch-reviewer`, `perf-reviewer`, `sql-analyzer`)에 실제 분석 방법론을 위임하고, 스킬(`*-guide`)이 안티패턴·규칙 퀵 레퍼런스를 필요한 순간 자동으로 붙여준다.

모든 분석 결과는 Critical / High / Medium / Low 심각도로 분류되고, 지적마다 Bad/Good 코드 예시와 구체적 개선안이 따라온다. 코드 리뷰 게이트(PR 머지 전), 슬로우 쿼리 원인 규명, 아키텍처 건강도 점검, 리팩터링 착수 전 정리 대상 식별 등에 쓴다. Kotlin(Spring Boot), Python(FastAPI/Django), TypeScript/JavaScript(Next.js/NestJS)를 지원하며 SQL은 PostgreSQL·MySQL·Oracle 방언을 다룬다.

## 구성요소

### 커맨드

- `/analyze` — 품질·보안·성능·아키텍처를 아우르는 멀티 도메인 정적 분석. `--focus`, `--depth`, `--format`으로 범위와 출력을 조절하고 심각도별 발견 사항과 개선 로드맵을 리포트로 낸다.
- `/arch-review` — 의존성 방향 분석, 레이어 위반 탐지, 네이밍/패키지 일관성 검사, MSA 성숙도 평가를 수행해 0~100 아키텍처 건강도 점수를 산출한다. 6단계 분석과 위반 체크리스트(V-C1~V-L3) 기반.
- `/perf-review` — 메모리·I/O·동시성·직렬화 등 9개 카테고리의 성능 안티패턴을 Grep 기반으로 스캔하고, 지적마다 예상 개선 효과와 Bad/Good 예시를 제시한다.
- `/sql-analyze` — SQL 쿼리의 풀스캔·인덱스 무효화·서브쿼리 비효율·조인/페이지네이션 문제를 2단계(쿼리 단독 → 메타데이터 정밀)로 분석하고 누락 인덱스 CREATE 문까지 생성한다.

### 에이전트

- `arch-reviewer` — 아키텍처 리뷰 전문가. 코드베이스 구조, 의존성 방향, 설계 패턴 준수 여부를 분석한다. `/arch-review`의 실제 분석 엔진.
- `perf-reviewer` — 성능 리뷰 전문가. 메모리 누수, I/O 병목, 동시성 이슈, 직렬화 오버헤드, 언어별 성능 함정을 탐지한다. `/perf-review`의 실제 분석 엔진.
- `sql-analyzer` — SQL 성능 분석가. 풀 테이블 스캔, 슬로우 쿼리 패턴, 서브쿼리 비효율, 누락 인덱스, 조인 최적화 이슈를 진단한다. `/sql-analyze`의 실제 분석 엔진.

### 스킬

- `arch-review-guide` — 아키텍처 위반 탐지, 의존성 방향 규칙, 구조 건강도 평가 퀵 레퍼런스(세부 레퍼런스 `guide/arch-review-guide.md` 포함).
- `perf-review-guide` — 성능 민감 코드 작성·리뷰 시 참조하는 대표 안티패턴과 최적화 전략 퀵 레퍼런스.
- `sql-analyze-guide` — SQL 작성·리뷰 시 참조하는 성능 안티패턴, 인덱스 전략, 서브쿼리/조인 튜닝 퀵 레퍼런스.
- `code-simplification-guide` — 기존 코드 단순화·리팩터링·정리 시 참조하는 원칙, 정리 대상 분류, 안전한 단순화 절차 가이드. (전용 커맨드 없이 단순화 작업 맥락에서 자동 활성화)

## 사용법

커맨드는 `/analyze`, `/arch-review`, `/perf-review`, `/sql-analyze`로 직접 호출한다. 대상 경로와 옵션을 붙여 범위를 좁힐 수 있다.

```
# 프로젝트 전체 멀티 도메인 분석
/analyze

# 인증 모듈 심층 보안 분석
/analyze src/auth --focus security --depth deep

# PR 머지 전 아키텍처 게이트 (Critical/High만 빠르게)
/arch-review src --depth quick

# 저장소 계층 I/O·DB 성능 리뷰 (N+1, 배치 누락 등)
/perf-review src/repository --focus io

# SQL 붙여넣고 인덱스/서브쿼리 분석
/sql-analyze
SELECT ... FROM orders o JOIN customers c ON ...
```

전문 커맨드는 대응 에이전트에 분석을 위임하며, 스킬은 별도 호출 없이 관련 작업(아키텍처 리뷰, 성능 튜닝, SQL 작성, 코드 단순화) 맥락에서 자동으로 로드되어 판단 기준을 보강한다. `/sql-analyze`는 쿼리만으로 1차 분석(Phase 1)을 내고, 사용자가 테이블 행 수·인덱스 정보·EXPLAIN 결과를 추가하면 자동으로 정밀 분석(Phase 2)으로 넘어간다.

## 참고

- 모든 커맨드는 **제안만** 하며 소스 코드를 직접 수정하지 않는다. 발견 사항과 Bad/Good 예시를 리포트로 제공한다.
- 빌드/컴파일, 실제 프로파일러·벤치마크 실행, 실 DB 접속 EXPLAIN 등은 사용자 승인 없이 수행하지 않는다(실행할 명령을 안내하는 수준).
- 성능 개선 효과와 아키텍처 건강도 점수는 정적 분석 기반 **추정치**이며 특정 수치를 보장하지 않는다.
- 특정 아키텍처 스타일을 강요하지 않고 감지·검증하며, 비즈니스 로직의 정확성이 아니라 품질/성능/구조 관점만 다룬다.
- 언어중립·프레임워크별 리뷰가 필요하면 백엔드 계열(`backend-*`) 플러그인과, ES/검색 도메인 리뷰가 필요하면 `search` 플러그인과 함께 쓰면 좋다.
