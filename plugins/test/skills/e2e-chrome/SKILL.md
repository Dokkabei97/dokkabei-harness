---
name: e2e-chrome
description: |
  브라우저 E2E·화면 검증 체크리스트 — Chrome(claude-in-chrome)이나 Playwright MCP 로 "화면에서 직접 확인", UI 동작 확인, 로그인 세션 필요한 플로우, 반응형 확인 시 시나리오 분해·단계별 증거(스크린샷·스냅샷·콘솔·네트워크·GIF/트레이스)·판정 리포트. Playwright flaky 함정 포함.
  Checklist for verifying UI in a real browser via Claude in Chrome or Playwright MCP: step plan, per-step evidence, pass/fail report, Playwright flakiness pitfalls.
  Use when: checking a page or user flow in the browser, visual or responsive verification, E2E smoke test, flaky Playwright test.
---

# 브라우저 E2E 검증 체크리스트

브라우저 도구(claude-in-chrome 또는 Playwright MCP)로 사용자 여정을 확인할 때, **무엇을 증거로 남기고 어떻게 판정할지**를 정리한 가이드.
Playwright 테스트 코드를 생성·실행해 저장소에 남기려면 사용자가 `/e2e` 를 쓴다.

## 1. 경로 고르기

| 상황 | 도구 |
|------|------|
| 로그인된 실제 세션·SSO·외부 서비스, 로컬에서 눈으로 빠르게 확인, GIF 공유 | claude-in-chrome (`mcp__claude-in-chrome__*`) — 사용자의 실제 Chrome 프로필 |
| 깨끗한 브라우저, 재현 가능한 확인, 콘솔/네트워크 로그 수집 | Playwright MCP (`mcp__plugin_playwright_playwright__*` 등) |
| 회귀 테스트로 저장소에 남기기·CI 게이트 | `/e2e` (Playwright 테스트 코드) |

도구가 세션에 없으면: claude-in-chrome 은 `claude --chrome` 으로 연결(현재 대화 유지는 `claude --chrome -c`), Playwright MCP 는 플러그인/MCP 설정 필요 — 사용자에게 안내하고 멈춘다.
claude-in-chrome 을 쓰기 전에는 `claude-in-chrome`(또는 `chrome-browser`) 스킬의 탭·권한·다이얼로그 규칙을 먼저 따른다.

## 2. 시작 전 확인

- [ ] 대상 URL·환경: 로컬/스테이징인가. **운영 환경에서 데이터를 바꾸는 시나리오는 사용자 확인 없이 실행하지 않는다**
- [ ] 결제·메일 발송·삭제 등 되돌릴 수 없는 단계가 있는가 → 해당 단계 직전에 멈추고 확인
- [ ] 필요한 계정·테스트 데이터, 기대 결과의 출처(요구사항/이슈/디자인)
- [ ] 뷰포트(desktop/tablet/mobile)와 브라우저 상태(로그인 여부, 쿠키)
- [ ] 앱 서버가 떠 있는지, 어떤 브랜치/빌드인지 (다른 브랜치의 dev 서버를 검증하는 실수가 흔함)

## 3. 시나리오 분해

자연어 요청을 단계로 쪼개고, 각 단계에 **관찰 가능한 기대 결과**를 붙인다. "잘 되는지 확인" 은 기대 결과가 아니다.

```
1. /login 이동            → 기대: 이메일·비밀번호 입력란과 "로그인" 버튼 표시
2. 자격증명 입력·제출      → 기대: /dashboard 로 이동, 헤더에 사용자 이름
3. "최근 주문" 영역 확인   → 기대: 1건 이상 행, 각 행에 주문번호·금액
```

실행 전 이 계획을 사용자에게 보여주고, 의존 관계(2 실패 시 3 스킵)를 표시한다.

## 4. 단계별 증거 체크리스트

각 단계마다 아래를 남긴다. 판정은 스크린샷의 "느낌"이 아니라 텍스트로 확인 가능한 증거로 한다.

- [ ] 수행한 동작(클릭 대상은 역할+이름 — 예: button "로그인")
- [ ] 안정화 대기: 기대 요소/텍스트가 나타날 때까지 대기(고정 sleep 은 느리거나 flaky — 조건 대기로, TST-PW-01)
- [ ] DOM/접근성 스냅샷 또는 페이지 텍스트로 기대 결과 확인
- [ ] 스크린샷 (실패 단계는 필수, 성공 단계는 핵심 화면)
- [ ] 콘솔 error 레벨 메시지 (패턴으로 필터)
- [ ] 이 단계에서 발생한 네트워크 요청 중 4xx/5xx, 실패 요청
- [ ] 판정: PASS / FAIL(원인 가설 + 근거) / SKIP(의존 단계 실패)

실패하면 다음 단계로 밀어붙이지 말고: 현재 화면 증거 수집 → 의존 단계 SKIP → 독립 단계만 계속.
원인 분석이 필요하면 Read/Grep 으로 해당 컴포넌트·API 핸들러를 찾아 **수정안은 제안만** 한다(검증 중에 코드를 고치지 않는다).

## 5. 완료 판정

- [ ] 모든 단계 PASS, 또는 FAIL/SKIP 의 원인과 증거가 기록됨
- [ ] 여정 전체에서 콘솔 error 0건(있으면 기존 이슈인지 이번 변경 때문인지 구분)
- [ ] 네트워크 5xx 0건, 의도치 않은 4xx 없음
- [ ] 요청한 뷰포트 모두 확인(반응형이면 최소 desktop + mobile)
- [ ] 테스트로 만든 데이터의 정리 여부 기록

## 6. 리포트 형식

```
## 브라우저 검증 결과
여정: <요약> · URL: <base> · 도구: claude-in-chrome | playwright-mcp · 뷰포트: <...>
상태: PASS | PARTIAL | FAIL

| # | 단계 | 기대 | 결과 | 증거 |
|---|------|------|------|------|
| 1 | /login 이동 | 로그인 폼 표시 | PASS | snapshot: textbox "이메일" |
| 2 | 제출 | /dashboard 이동 | FAIL | screenshot, POST /api/login 500 |
| 3 | 최근 주문 | 1건 이상 | SKIP (2 의존) | - |

콘솔 에러: <목록 또는 없음>
네트워크 이상: <메서드 경로 상태>
이슈: <심각도 · 설명 · 의심 위치(파일:라인) · 수정 제안>
아티팩트: <스크린샷/GIF/트레이스 위치>
```

## 7. 위임과 반복

- 단계가 많거나 스크린샷이 많아 메인 컨텍스트를 아끼고 싶으면 `chrome-e2e-runner` 에이전트에 계획(3절)을 넘겨 실행시킨다.
- 같은 여정을 반복 검증해야 하면 브라우저 수동 확인을 Playwright 테스트로 굳히는 것을 제안한다(`/e2e`) — 그 다음부터는 `/loop-run --gate-cmd "npx playwright test"` 로 게이트화 가능.

## 레퍼런스

- [references/browser-tools.md](references/browser-tools.md) — claude-in-chrome / Playwright MCP 운용 메모(증거 수집 도구, 다이얼로그, 실제 프로필 주의)
- [references/playwright.md](references/playwright.md) — Playwright 테스트 flaky·느림 함정 TST-PW-01~10 (`/e2e` 도 참조)
