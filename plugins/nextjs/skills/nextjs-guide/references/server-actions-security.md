# Server Actions(Server Functions) 보안·동작 함정 (RSC-ACT)

> 확인 문서: `node_modules/next/dist/docs/01-app/02-guides/data-security.md`, `02-guides/server-actions.md`,
> `03-api-reference/05-config/01-next-config-js/serverActions.md`, `02-guides/self-hosting.md`.
> 공개본: https://nextjs.org/docs/app/guides/data-security · https://nextjs.org/docs/app/guides/server-actions

### RSC-ACT-01 · 'use server' 파일의 export 는 전부 공개 POST 엔드포인트 — 페이지 인증은 액션을 보호하지 않는다
- 적용: 모든 Server Action
- 신호: 페이지/레이아웃에서만 `auth()`/redirect 하고 액션 본문에 인증 없음; `'use server'` 파일에 헬퍼(`export async function getUserById`)까지 export; zod 검증만 하고 소유권 확인 없음
- 메커니즘: 액션은 UI 와 무관하게 직접 POST 로 호출 가능. 미사용 액션 ID 는 클라이언트 번들에서 제거되지만 문서는 "직접 POST 로 도달 가능하다고 간주하라"고 명시. 레이아웃 체크는 Partial Rendering 때문에 내비게이션마다 재실행되지도 않는다. zod 는 "모양"만 검증 — 잘 생긴 `{ id }` 가 남의 행일 수 있다(IDOR)
- 처방: 각 액션 첫 줄에서 세션 재검증 + 대상 리소스 소유권/권한 확인. 인증·인가·DB 를 `server-only` DAL 로 모으고 액션은 얇게. 헬퍼는 `'use server'` 파일 밖으로
- 반례: 없음
- 검증: 로그아웃 상태 쿠키로 액션 ID 를 재전송(DevTools 에서 요청 복사 → curl)해 401/거부 확인; `grep -rn "'use server'"` 결과의 모든 export 에 인증 호출이 있는지 리뷰
- 근거: `data-security.md#built-in-server-actions-security-features`, `#authentication-and-authorization`, `02-guides/authentication.md`(Layout 체크 주의)

### RSC-ACT-02 · 클라이언트를 왕복하는 값(클로저 캡처·.bind 인자·hidden input)을 신뢰하지 말 것
- 적용: 컴포넌트 안 인라인 `'use server'` 함수, `action.bind(null, id)`, `<input type="hidden">`
- 신호: 클로저로 `price`, `role`, `ownerId` 를 캡처해 그대로 DB 반영; hidden input 의 userId 로 업데이트
- 메커니즘: 클로저 캡처 변수는 클라이언트로 보내졌다 돌아온다 — Next 가 빌드별 키로 암호화하지만 문서는 "암호화만 믿지 말라"고 명시. hidden input 은 HTML 평문. 어떤 경로든 액션 호출자는 인자를 바꿔 보낼 수 있다
- 처방: 클라이언트는 "어느 항목인지(ID)+사용자 변경분"만 보내고, 가격·소유자·권한 등 나머지는 세션 기반으로 서버에서 재조회
- 반례: 렌더 시점 스냅샷(예: 게시 버전 번호)을 낙관적 동시성 검사용으로 캡처하는 것은 정당 — 단 서버에서 현재 값과 비교
- 검증: 변조 인자 재전송 테스트
- 근거: `data-security.md#closures-and-encryption`, `02-guides/forms.md`(hidden input 비인코딩 주석), `server-actions.md`(reference + change 원칙)

### RSC-ACT-03 · 액션 반환값은 클라이언트로 직렬화된다
- 적용: `useActionState`/직접 호출의 반환값
- 신호: `return await db.user.update(...)`(행 전체 반환), 에러 시 `return { error: e }`(스택·SQL 노출)
- 메커니즘: 반환값은 RSC 직렬화되어 응답에 실린다 — 필드 필터 없음
- 처방: `{ ok, fieldErrors, id }` 같은 최소 형태로 매핑. 예외 메시지는 로그로, 사용자에겐 일반 메시지
- 반례: 없음
- 검증: 액션 응답 본문(Network 탭) 검사
- 근거: `server-actions.md`, `data-security.md`

### RSC-ACT-04 · 클라이언트의 액션 호출은 한 번에 하나씩 순차 디스패치 — Promise.all 병렬화 안 됨
- 적용: 클라이언트에서 여러 액션을 동시에 호출하거나 액션으로 "조회"를 하는 코드
- 신호: `await Promise.all([actA(), actB()])` 로 속도 기대, 검색 자동완성을 액션으로 구현해 타이핑 지연 누적
- 메커니즘: Next 는 클라이언트당 액션을 하나씩 큐잉해 결과 트리 일관성을 보장. 또 액션은 POST 라 캐시되지 않는다
- 처방: 병렬 작업은 하나의 액션 안에서 `Promise.all`. 조회는 서버 컴포넌트 fetch 또는 Route Handler(GET)
- 반례: 순서 보장이 필요한 연속 변경에는 이 성질이 오히려 이점
- 검증: Network 워터폴에서 액션 요청 직렬 여부
- 근거: `server-actions.md#sequential-dispatch-on-the-client`

### RSC-ACT-05 · redirect()/notFound() 는 throw — try/catch 안에 두면 삼켜지고, 뒤 코드는 실행 안 됨
- 적용: 액션·Route Handler·서버 컴포넌트
- 신호: `try { await save(); redirect('/done') } catch (e) { return { error } }` → 리다이렉트 대신 에러 반환; redirect 뒤의 `revalidatePath`
- 메커니즘: 둘 다 제어 흐름 예외. catch 가 가로채면 프레임워크가 처리 못 함
- 처방: `redirect` 는 try 밖에서 호출, 무효화(`updateTag`/`revalidatePath`)는 redirect **전에**. 광범위 catch 가 불가피하면 `unstable_rethrow(e)` 를 catch 첫 줄에
- 반례: 없음
- 검증: 성공 경로 e2e 에서 URL 변경 확인
- 근거: `03-api-reference/04-functions/redirect.md`, `03-api-reference/04-functions/unstable_rethrow.md`, `server-actions.md`

### RSC-ACT-06 · 액션 요청 본문 기본 상한 1MB
- 적용: 파일 업로드·대량 폼을 액션으로 처리
- 신호: 큰 파일에서만 실패(413 류), 이미지 업로드 기능이 로컬 테스트(작은 파일)에선 통과
- 메커니즘: `serverActions.bodySizeLimit` 기본 1MB(DoS 방지)
- 처방: 대용량은 스토리지 presigned URL 로 브라우저→스토리지 직접 업로드 후 액션엔 키만 전달. 불가피하면 `bodySizeLimit: '5mb'` 등으로 최소 상향 + 앞단 리버스 프록시 상한과 일치
- 반례: 상한을 크게 올리면 파싱 메모리·DoS 표면 증가
- 검증: 경계값(1MB±) 업로드 테스트
- 근거: `serverActions.md#bodysizelimit`, `server-actions.md`

### RSC-ACT-07 · 리버스 프록시 뒤에서 Origin ≠ Host 로 액션이 거부된다
- 적용: nginx/Ingress/API 게이트웨이가 Host 를 바꾸거나 다른 도메인에서 프록시하는 구성
- 신호: 로컬은 정상, 운영에서만 모든 액션 실패
- 메커니즘: CSRF 방어로 `Origin` 을 `Host`(또는 `X-Forwarded-Host`)와 비교해 불일치 시 중단
- 처방: 프록시가 `X-Forwarded-Host` 를 올바로 전달하게 하거나 `serverActions.allowedOrigins: ['my-proxy.com', '*.my-proxy.com']`
- 반례: 와일드카드를 넓게 열면 CSRF 방어 약화 — 실제 도메인만
- 검증: 운영 경로로 액션 호출 + 요청 헤더 확인
- 근거: `data-security.md#allowed-origins-advanced`, `serverActions.md#allowedorigins`

### RSC-ACT-08 · 다중 인스턴스·롤링 배포에서 "Failed to find Server Action"
- 적용: 셀프호스팅 레플리카 2+ 또는 롤링 배포
- 신호: 간헐적 "Failed to find Server Action", 배포 직후 열려 있던 탭에서 폼 제출 실패
- 메커니즘: (a) 클로저 암호화 키가 인스턴스마다 다르면 다른 인스턴스가 복호화 못 함. (b) 액션 ID 는 빌드 산출물 — 새 배포는 새 ID(소스 동일해도 최대 14일마다 회전)라 구 클라이언트가 없는 ID 호출
- 처방: (a) 모든 인스턴스에 동일 `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY`(base64, 디코드 16/24/32바이트 AES 키) 주입·로테이션 정책. (b) `deploymentId` 설정 → 불일치 시 하드 내비게이션(리로드)으로 복구. 미저장 폼 입력 유실까지 막으려면 CDN/Ingress 의 배포 버전 기반 라우팅 또는 블루/그린(NX-OPS-03 반례)
- 반례: 단일 인스턴스 + 무중단 배포 아님이면 불필요
- 검증: 레플리카 2개에 라운드로빈으로 액션 호출, 배포 전 연 탭에서 배포 후 제출
- 근거: `data-security.md#overwriting-encryption-keys-advanced`, `self-hosting.md#server-functions-encryption-key`, `#version-skew`

### RSC-ACT-09 · 렌더 중 변이 금지 — GET 렌더에서 로그아웃·쿠키 설정·무효화 시도
- 적용: 서버 컴포넌트 렌더 본문
- 신호: 페이지 렌더에서 `cookies().set`, `revalidateTag`, 조회수 증가 UPDATE
- 메커니즘: Next 는 렌더 메서드에서 쿠키 설정·재검증을 명시적으로 막는다. 렌더는 prefetch·재시도로 여러 번 실행될 수 있어 부수효과가 중복된다
- 처방: 변이는 액션/Route Handler 로. 조회수 같은 비핵심 기록은 `after()`(단 NX-CACHE-13 참고)
- 반례: 없음
- 검증: prefetch 시 서버 로그에 변이 쿼리가 찍히는지
- 근거: `data-security.md#avoiding-side-effects-during-rendering`

### RSC-ACT-10 · RSC 보안 패치 하한 — Server Action 을 안 써도 Flight 역직렬화가 공격면이다
- 적용: App Router(RSC) 를 프로덕션에서 서비스하는 Next 15.x/16.x(14.3 canary 포함). Pages Router 전용·Edge Runtime 은 CVE-2025-66478 대상 아님
- 신호: 설치된 `next` 버전이 보안 공지의 패치 하한 미만. "우리는 Server Action 이 없다"는 이유로 업그레이드를 미룸
- 메커니즘: React2Shell — RSC 요청 역직렬화(Flight)의 비인증 RCE(CVSS 10.0, React CVE-2025-55182 / Next CVE-2025-66478). React 공지: Server Function 엔드포인트를 구현하지 않아도 RSC 를 지원하면 취약할 수 있다. 후속 공지로 DoS(CVE-2025-55184·67779, CVE-2026-23864)·소스 노출(CVE-2025-55183) 추가 — 첫 DoS 수정이 불완전해 패치 하한이 한 번 더 올라갔다. Next 는 `react-server-dom-*` 를 `dist/compiled` 에 번들하므로 판단 기준은 `next` 버전이다(`npm ls react-server-dom-webpack` 이 비어도 안전하다는 뜻 아님)
- 처방: 릴리즈 라인별 최신 패치로 업그레이드(RCE 하한: 15.0.5 / 15.1.9 / 15.2.6 / 15.3.6 / 15.4.8 / 15.5.7 / 16.0.7 — 후속 DoS·소스 노출 수정은 그 이후 버전이므로 GitHub Security Advisories 의 현재 하한을 확인). 우회책 없음. 패치 전 노출 기간이 있었다면 재배포 후 앱 비밀(키·토큰) 로테이션
- 반례: 하한 숫자를 규칙 파일에 고정하지 말 것 — 공지가 추가되며 바뀐다. 규칙에는 "advisory 대조" 절차만 둔다
- 검증: `node -p "require('next/package.json').version"` 또는 `npm ls next` 를 https://github.com/vercel/next.js/security/advisories 와 대조, `npm audit --omit=dev`, `npx fix-react2shell-next`(버전 점검·범프 도구)
- 근거: https://nextjs.org/blog/CVE-2025-66478 , https://react.dev/blog/2025/12/03/critical-security-vulnerability-in-react-server-components , https://react.dev/blog/2025/12/11/denial-of-service-and-source-code-exposure-in-react-server-components
