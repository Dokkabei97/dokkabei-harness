# uvicorn 프로세스 모델 · 배포 설정

> 스페셜리스트 항목. uvicorn 공식 문서(Kludex/uvicorn docs) 기준. 실제 기동 명령(Dockerfile `CMD`, compose, k8s manifest, `fastapi run`)을 먼저 확인할 것.
> 커넥션 총량 산식(레플리카 × 워커 × 풀 max)은 PY-PG-03(`psycopg-postgres.md`) 한 곳에서 다룬다(구 FA-SRV-01 병합).

## 목차
- FA-SRV-02 컨테이너에서 CPU 수로 워커 수를 정하면 과할당된다
- FA-SRV-03 keep-alive 기본 5초 < LB idle 타임아웃 → 간헐 502
- FA-SRV-04 프록시 뒤 client IP: `forwarded-allow-ips` 기본은 localhost 만 신뢰
- FA-SRV-05 `--limit-concurrency` 는 대기열이 아니라 즉시 503 / `--limit-max-requests` jitter 기본 0
- FA-SRV-06 graceful shutdown 과 k8s 종료 순서

---

### FA-SRV-02 · 컨테이너에서 `os.cpu_count()` 로 워커 수를 정하면 CPU limit 을 무시하고 과할당된다
- 적용: k8s/ECS 등 CPU limit 이 있는 컨테이너, gunicorn `workers = cpu_count()*2+1` 류 설정
- 신호: 노드 코어 수(예: 32)만큼 워커가 떠서 CPU 1코어 limit 에서 스로틀링·메모리 초과
- 메커니즘: `os.cpu_count()` 는 시스템 논리 CPU 수다. 3.13 의 `os.process_cpu_count()` 도 CPU affinity 만 반영하며 cgroup CPU quota 는 반영하지 않는다. 3.13+ 는 `-X cpu_count=N`/`PYTHON_CPU_COUNT` 로 강제 지정 가능.
- 처방: 워커 수는 명시적 환경변수(`WEB_CONCURRENCY`)로. k8s 에서는 "파드당 1 프로세스 + 수평 확장"이 일반적 권장(FastAPI 배포 문서) — 메모리·헬스체크·롤링이 단순해진다. 파드당 다중 워커가 필요하면 CPU limit(코어)에 맞춰 지정.
- 반례: VM/베어메탈 단독 배포는 코어 수 기반이 합리적.
- 검증: 컨테이너 안에서 `ps` 로 워커 수, cgroup `cpu.max` 와 비교, 스로틀링 메트릭(`container_cpu_cfs_throttled_seconds_total`).
- 근거: https://docs.python.org/3/library/os.html#os.process_cpu_count · https://fastapi.tiangolo.com/deployment/docker/

### FA-SRV-03 · uvicorn `--timeout-keep-alive` 기본 5초가 앞단 LB 의 idle 타임아웃보다 짧으면 간헐 502 가 난다
- 적용: ALB/NLB/nginx/Ingress 가 업스트림 keep-alive 커넥션을 재사용하는 구성
- 신호: 저트래픽 시간대에 드문드문 502/`upstream prematurely closed connection`, 재시도하면 성공
- 메커니즘: 서버가 idle 커넥션을 5초에 닫는 순간 LB 가 같은 커넥션으로 요청을 보내면 경합으로 리셋된다. LB 의 idle 타임아웃(예: AWS ALB 기본 60초)보다 **업스트림 서버의 keep-alive 가 길어야** LB 가 먼저 닫는다.
- 처방: `--timeout-keep-alive` 를 LB idle 타임아웃 + 여유(예: ALB 60초 → 65~75초)로. nginx 업스트림이면 `keepalive_timeout` 을 uvicorn 값보다 짧게.
- 반례: LB 가 업스트림 keep-alive 를 쓰지 않으면(요청마다 새 커넥션) 무관. 너무 길게 잡으면 idle 커넥션이 `--limit-concurrency` 예산을 소모(FA-SRV-05).
- 검증: LB 액세스 로그의 502 + `target_processing_time = -1` 패턴, 값 변경 후 재현 여부.
- 근거: https://github.com/Kludex/uvicorn/blob/main/docs/settings.md · https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#connection-idle-timeout

### FA-SRV-04 · 프록시 뒤에서 `request.client.host` 는 프록시 IP — `--forwarded-allow-ips` 기본은 127.0.0.1/::1 만 신뢰
- 적용: Ingress/LB/사이드카 뒤의 uvicorn, IP 기반 rate limit·감사 로그·지오IP
- 신호: 모든 요청의 client IP 가 Ingress 파드 IP, rate limit 이 전체 사용자를 한 명으로 취급
- 메커니즘: `--proxy-headers` 는 기본 활성이지만 연결 상대가 `forwarded-allow-ips`(기본 `$FORWARDED_ALLOW_IPS` 또는 127.0.0.1, ::1)에 있을 때만 `X-Forwarded-For/Proto` 를 반영한다.
- 처방: 프록시 대역(CIDR)을 `FORWARDED_ALLOW_IPS` 로 지정. `'*'` 는 앱 포트가 외부에서 직접 닿지 않는 것이 보장될 때만 — 아니면 클라이언트가 XFF 를 위조할 수 있다.
- 반례: 프록시가 PROXY protocol 을 쓰는 경우는 별도 설정 경로.
- 검증: 외부에서 `X-Forwarded-For: 1.2.3.4` 를 붙여 요청해 로그에 위조값이 찍히지 않는지.
- 근거: https://github.com/Kludex/uvicorn/blob/main/docs/settings.md

### FA-SRV-05 · `--limit-concurrency` 는 줄 세우지 않고 즉시 503 — idle keep-alive 도 예산을 먹는다 / `--limit-max-requests-jitter` 기본 0
- 적용: 과부하 보호·메모리 누수 완화 설정을 쓰는 배포. `--limit-max-requests-jitter` 는 uvicorn **0.41+** (0.40 이하에는 없음 — lock 파일 확인)
- 신호: 부하가 낮은데 503, 혹은 모든 워커가 같은 시각에 재시작해 순간 가용성 하락
- 메커니즘: limit-concurrency 는 헤더 수신 후 "열린 커넥션 수 또는 진행 중 태스크 수"가 한도에 닿으면 즉시 503 이며 대기시키지 않는다(공식 문서). idle keep-alive 커넥션도 카운트된다. `--backlog`(기본 2048)는 OS accept 큐로 별개 — 루프가 막혔을 때만 찬다. `--limit-max-requests` 는 N 요청 후 프로세스 종료이며 jitter 기본 0 이라 워커들이 동시에 재시작할 수 있다.
- 처방: 대기열이 필요하면 앞단 프록시에서. limit-concurrency 는 (예상 동시 요청 + keep-alive 커넥션)보다 넉넉히. max-requests 를 쓰면 jitter 를 함께 지정(예: max 10000, jitter 1000).
- 반례: max-requests 는 누수의 근본 해결이 아니다 — PY-MEM-* 로 원인 추적이 우선.
- 검증: 부하 테스트에서 503 비율과 연결 수 관계, 워커 재시작 타임스탬프 분포.
- 근거: https://github.com/Kludex/uvicorn/blob/main/docs/server-behavior.md · https://github.com/Kludex/uvicorn/blob/main/docs/settings.md

### FA-SRV-06 · 롤링 배포 중 요청 유실은 대부분 종료 순서 문제 — preStop 지연 + graceful 타임아웃 < 파드 종료 유예
- 적용: k8s 롤링 업데이트(기본 `terminationGracePeriodSeconds` 30초)
- 신호: 배포 때마다 소량의 502/연결 리셋
- 메커니즘: SIGTERM 과 엔드포인트 제거(Ingress/kube-proxy 반영)는 병렬로 진행돼, 종료 중인 파드로 새 요청이 잠시 더 들어온다. uvicorn 은 SIGTERM 에 새 연결 수락을 멈추고 진행 중 요청을 마무리하며, `--timeout-graceful-shutdown` 을 넘기면 남은 요청을 끊는다. 이 값의 기본은 `None`(config.py) = **타임아웃 없음**이라, 명시하지 않으면 uvicorn 은 무한정 기다리고 결국 `terminationGracePeriodSeconds` 에서 SIGKILL 로 죽는다(lifespan 종료·풀 close 도 실행되지 않음). 진행 중 `BackgroundTasks` 도 이 시간 안에 끝나야 하며, 넘기면 조용히 유실된다(FA-BG-01).
- 처방: `preStop: sleep 5~10` 으로 엔드포인트 제거 전파를 기다린 뒤 SIGTERM, `--timeout-graceful-shutdown` 을 (grace period − preStop − 여유)로. lifespan 종료에서 풀 close.
- 반례: 장시간 스트리밍/웹소켓은 grace 안에 못 끝난다 — 클라이언트 재연결 설계가 필요.
- 검증: 지속 부하 중 롤링 배포를 수행하고 오류율 측정.
- 근거: https://github.com/Kludex/uvicorn/blob/main/docs/settings.md · https://github.com/Kludex/uvicorn/blob/main/uvicorn/config.py (`timeout_graceful_shutdown: int | None = None`) · https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination
