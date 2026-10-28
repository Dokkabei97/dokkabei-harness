# 커버리지 해석 · 뮤테이션 테스트

### TST-COV-01 · 커버리지는 "실행됨"이지 "검증됨"이 아니다
- 적용: 커버리지 % 를 품질 게이트로 쓰는 팀
- 신호: 커버리지는 높은데 회귀가 샘, assert 없는(또는 `assertNotNull` 뿐인) 테스트, 예외만 안 나면 통과하는 테스트
- 메커니즘: 라인/브랜치 커버리지는 코드가 실행됐는지만 측정한다. 결과를 검증하지 않아도 100% 가 나온다. 또한 언어별 생성 코드가 수치를 왜곡한다 — Kotlin 은 컴파일러가 만든 null 체크·`when` 분기가 바이트코드 브랜치로 잡혀 JaCoCo 브랜치 수치가 소스와 1:1 이 아니고(필터 범위는 JaCoCo 버전별 changes 문서 확인), Go 기본 커버리지는 테스트 대상 패키지만 센다(TST-GO-06).
- 처방: 변경 diff 기준으로 "새/바뀐 분기와 에러 경로가 assert 로 검증되는가"를 리뷰. 숫자 게이트를 둔다면 전체 % 보다 변경 라인 커버리지(diff coverage).
- 반례: 레거시 무테스트 코드에선 커버리지 증가 자체가 의미 있는 첫 신호.
- 검증: 아래 뮤테이션 테스트로 assert 의 실효성 측정.
- 근거: https://www.jacoco.org/jacoco/trunk/doc/counters.html · https://www.jacoco.org/jacoco/trunk/doc/changes.html

### TST-COV-02 · 뮤테이션 테스트로 assert 실효성을 잰다 — 변경 범위로 좁혀서
- 적용: 결제·권한·정산처럼 "테스트가 정말 잡아내는가"가 중요한 모듈
- 신호: 커버리지 100% 인데 조건 반전(`>`→`>=`)·반환값 변경 버그가 통과
- 메커니즘: 뮤테이션 도구는 코드를 작게 변형(조건 경계, 반환값, 연산자)한 뒤 테스트를 돌려, 변형이 **살아남으면** 그 동작을 검증하는 assert 가 없다는 뜻이다. 비용은 (변이 수 × 관련 테스트 시간)이라 전체 실행은 비싸다.
- 처방: JVM 은 PIT(Gradle 플러그인 `info.solidsoft.pitest`; Kotest 는 PIT 연동 확장 필요 — Kotest 문서 확인), TS/JS 는 StrykerJS(Vitest/Jest 러너 지원). 대상 클래스/파일을 변경 범위로 한정하고, PIT 는 history 파일로 증분 분석. 살아남은 변이 → 경계값 테스트 추가.
- 반례: 로깅·DTO·설정 코드에 돌리면 "동등 변이"(행위가 같은 변형) 노이즈만 많다. CI 상시 게이트보다 핵심 모듈의 주기적 점검이 현실적.
- 검증: mutation score(사망 변이 비율)와 생존 변이 목록.
- 근거: https://pitest.org/quickstart/ · https://gradle-pitest-plugin.solidsoft.info/ · https://stryker-mutator.io/docs/stryker-js/introduction/
