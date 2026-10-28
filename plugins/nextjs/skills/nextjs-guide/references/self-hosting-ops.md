# 셀프호스팅·운영 함정 (NX-OPS)

> 확인 문서: `node_modules/next/dist/docs/01-app/02-guides/self-hosting.md`, `02-guides/environment-variables.md`.
> 공개본: https://nextjs.org/docs/app/guides/self-hosting. Vercel 배포라면 대부분 플랫폼이 대신 처리한다 — 먼저 배포 대상을 확인.
> 관련 항목: 스트리밍 버퍼링 NX-DATA-04, 액션 키·버전 스큐 RSC-ACT-08, 인스턴스별 캐시 NX-CACHE-05, 이미지 최적화 부하 WEB-IMG-04.

### NX-OPS-01 · NEXT_PUBLIC_ 값은 빌드 시 동결 — "한 이미지 여러 환경" 배포에서 스테이징 값이 운영에 나간다
- 적용: Docker 이미지 1회 빌드 → dev/stage/prod 승격 파이프라인
- 신호: 운영 브라우저가 스테이징 API 도메인 호출, 환경변수를 바꿔 재시작해도 클라이언트 값 불변
- 메커니즘: `process.env.NEXT_PUBLIC_X` 참조는 `next build` 시점 값으로 클라이언트 JS 에 문자열 치환된다. 런타임 env 변경은 서버 코드에만 반영
- 처방: 환경별 공개 값은 서버 컴포넌트(동적 렌더)에서 `process.env` 로 읽어 props/Context 로 내리거나, 초기화 시 설정 엔드포인트에서 받기. 또는 환경별 빌드
- 반례: 환경별로 빌드하는 파이프라인이면 문제 없음
- 검증: 운영 산출물 `grep -r "staging" .next/static`
- 근거: `environment-variables.md`(build time inlining Note)

### NX-OPS-02 · 다중 인스턴스에서 revalidateTag 는 호출한 인스턴스만 무효화
- 적용: 레플리카 2+ 의 App Router(ISR/`'use cache'`/fetch 캐시 사용)
- 신호: 저장 직후 새로고침할 때마다 새 값/옛 값이 번갈아 보임(로드밸런서가 다른 파드로 보냄)
- 메커니즘: 기본 캐시는 인스턴스 로컬. 태그 무효화도 로컬에만 적용되고 다른 인스턴스는 스스로 발견할 때까지 stale 제공
- 처방: 커스텀 cache handler 를 공유 저장소(Redis 등)로 두고 `refreshTags()` 를 구현해 요청 전 태그 상태 동기화. 공유 캐시는 `'use cache: remote'` + `cacheHandlers`
- 반례: 단일 인스턴스 또는 sticky session + 짧은 TTL 허용이면 생략 가능(정합성 보장 아님)
- 검증: 레플리카 2개에 번갈아 요청하며 무효화 후 응답 비교
- 근거: `self-hosting.md#multi-instance-cache-coordination`, `#shared-cache`, `02-guides/how-revalidation-works.md`

### NX-OPS-03 · 롤링 배포 버전 스큐 — 사라진 청크·구 액션 ID·호환 안 되는 prefetch 데이터
- 적용: 무중단 롤링 배포
- 신호: 배포 직후 `ChunkLoadError`, "Failed to find Server Action", 클라이언트 내비게이션 실패
- 메커니즘: 구 빌드를 실행 중인 클라이언트가 새 서버(또는 반대)에 요청. 정적 자산 해시·액션 ID·RSC 페이로드 포맷이 빌드마다 다르다
- 처방: `deploymentId` 설정 → 정적 자산에 `?dpl=`, 내비게이션 요청에 `x-deployment-id` 가 붙고 불일치 시 하드 내비게이션(전체 리로드). 스큐 자체를 없애려면 **배포 버전 기반 라우팅**을 CDN/Ingress 에서 구성(Next 는 `?dpl=` 로 라우팅하지 않는다 — 쿼리는 캐시 버스팅용)하거나 블루/그린으로 구 버전을 일정 기간 유지. 이전 빌드의 정적 자산을 일정 기간 보존(CDN/버킷)
- 반례: 버전 기반 라우팅 없이 `deploymentId` 만 두면 에러가 "전체 리로드"로 바뀔 뿐이다 — 롤아웃 동안 다른 버전 파드에 닿을 때마다 리로드되어 긴 폼·에디터의 미저장 입력과 클라이언트 상태가 유실되고, 롤아웃 중 반복될 수 있다. 블루/그린 즉시 전환 + 세션 짧은 내부 도구는 비용 대비 이득 작음
- 검증: 배포 전 연 탭으로 배포 후 내비게이션·폼 제출
- 근거: `self-hosting.md#version-skew`, `#deployment-identifier`, `03-api-reference/05-config/01-next-config-js/deploymentId.md`(Good to know: `?dpl=` 미라우팅)

### NX-OPS-04 · SIGTERM 후 드레인 시간이 짧으면 진행 중 요청과 after() 콜백이 잘린다
- 적용: k8s 등 컨테이너 오케스트레이션 + `after()` 로 로깅/분석 전송
- 신호: 배포 때마다 분석 이벤트 유실, 502 스파이크
- 메커니즘: `next start` 는 SIGINT/SIGTERM 수신 시 진행 중 요청과 대기 중 `after()` 를 마친 뒤 종료 — 플랫폼이 그만큼 기다려야 한다(문서 권장 드레인 10–30초)
- 처방: `terminationGracePeriodSeconds` 를 드레인보다 길게, preStop 으로 LB 제외 후 종료 신호. PID 1 문제(셸 래퍼가 신호를 전달 안 함) 확인 — `node` 를 직접 exec
- 반례: 없음
- 검증: 부하 중 롤아웃하며 5xx·이벤트 유실 측정
- 근거: `self-hosting.md#after`
