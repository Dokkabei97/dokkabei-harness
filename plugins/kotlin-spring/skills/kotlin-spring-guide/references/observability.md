# 관측·프로파일링 — 추측 대신 측정 (JVM-OBS)

> 다른 레퍼런스의 모든 "검증" 필드가 이 도구들에 기댄다. 처방 전에 최소 하나의 측정 결과를 확보한다.

### JVM-OBS-01 · JFR 상시 기록 — 장애 후에 꺼낼 수 있게
- 적용: JDK 11+(8u262+ 백포트). 운영 상시 실행 가능.
- 신호: "재현이 안 된다", "그 시점 스레드·GC·락 상태를 모른다".
- 메커니즘: JFR 은 JVM 내장 이벤트 기록기로 기본(default) 설정의 오버헤드는 보통 1% 미만이다. 실행 샘플러가 safepoint 편향이 적어 JMX/jstack 기반 샘플러보다 핫 메서드를 정확히 보여준다.
- 처방: `-XX:StartFlightRecording=disk=true,maxage=6h,maxsize=500m,settings=default,dumponexit=true,filename=<영속 경로>`. 문제 시 `jcmd <pid> JFR.dump name=1 filename=/dumps/x.jfr`. 짧은 정밀 분석은 `settings=profile`.
- 반례: 디스크 쓰기가 제한된 환경은 maxsize 를 작게.
- 검증: JDK Mission Control, `jfr summary x.jfr`, `jfr print --events jdk.ExecutionSample x.jfr`.
- 근거: https://openjdk.org/jeps/328 , https://docs.oracle.com/en/java/javase/21/jfapi/

### JVM-OBS-02 · async-profiler — 모드를 문제에 맞춘다
- 적용: Linux/macOS HotSpot.
- 신호: GC 가 잦다 → **alloc**, CPU 가 높다 → **cpu**, CPU 는 낮은데 느리다(블로킹·풀 대기) → **wall**, 락 경합 → **lock**.
- 메커니즘: `-e alloc` 은 TLAB 경계·외부 할당을 샘플링해 할당 사이트를 보여준다 — GC 튜닝보다 할당 제거가 대부분 더 큰 효과다. `-e wall` 은 대기 중인 스레드까지 샘플링한다(`-t` 로 스레드별 분리).
- 처방: `asprof -e alloc -d 60 -f alloc.html <pid>`, `asprof -e wall -t -d 30 -f wall.html <pid>`. 컨테이너에서 perf_events 가 막혀 있으면 `-e itimer`/`ctimer`. JFR 형식(`-o jfr`)으로 받아 JMC 에서 함께 보기.
- 반례: —
- 검증: 개선 전후 같은 부하에서 flame graph 비교.
- 근거: https://github.com/async-profiler/async-profiler

### JVM-OBS-03 · GC·safepoint 로그 상시 + 회전
- 적용: JDK 9+ 통합 로깅.
- 신호: GC pause 는 짧은데 애플리케이션 정지가 길다(TTSP — safepoint 도달 시간).
- 메커니즘: 모든 스레드가 safepoint 에 도달해야 pause 가 시작된다. GC 로그만 보면 이 대기 시간이 안 보인다.
- 처방: `-Xlog:gc*,safepoint:file=<경로>/gc.log:time,uptime,level,tags:filecount=5,filesize=20m`.
- 반례: —
- 검증: GCeasy·GCViewer 류 분석 또는 로그의 safepoint 구간 합계.
- 근거: https://openjdk.org/jeps/158 , https://docs.oracle.com/en/java/javase/21/docs/specs/man/java.html#enable-logging-with-the-jvm-unified-logging-framework

> 결번: JVM-OBS-04(손수 만든 타이밍 루프 대신 JMH) — 범용 지식이라 제거. 미시 최적화 비교는 JMH(`-prof gc`, `@Fork` ≥ 1)로. ID 는 재사용하지 않는다.
