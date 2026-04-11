---
name: e2e-chrome
description: "Chrome Extension 기반 E2E 테스트. 실제 Chrome 브라우저를 제어하여 자연어 시나리오로 시각적 검증을 수행합니다."
category: testing
---

# /e2e-chrome - Chrome Extension E2E Testing

## Triggers

- 실제 브라우저에서 UI 동작을 시각적으로 검증할 때
- 인증된 세션(SSO, OAuth)으로 테스트가 필요할 때
- 프론트엔드 변경 후 빠르게 눈으로 확인하고 싶을 때
- GIF/스크린샷으로 테스트 결과를 팀에 공유할 때
- Playwright로는 설정이 복잡한 인증 플로우를 테스트할 때

> **Note:** CI/CD 자동화에는 `/e2e` (Playwright)를 사용하세요. `/e2e-chrome`은 로컬 시각적 검증 전용입니다.

## Usage

```
/e2e-chrome <자연어 테스트 시나리오>

Options:
  --url <base-url>        테스트 시작 URL (기본: localhost:3000)
  --gif                   세션 GIF 녹화 활성화
  --viewport <size>       뷰포트 크기 (desktop|tablet|mobile, 기본: desktop)
```

## Behavioral Flow

### Phase 1: Environment Check

1. **Chrome 모드 확인**
   - `claude --chrome` 모드로 실행되었는지 확인
   - 비활성 시 사용자에게 `-c` 플래그로 세션 이어붙이기 안내:
     ```
     ⚠️ Chrome 연동이 필요합니다.
     현재 세션을 유지하면서 Chrome 모드로 재시작하세요:

     claude --chrome -c

     -c 플래그가 현재 세션의 컨텍스트를 이어받으므로
     대화 내용과 작업 상태가 그대로 유지됩니다.

     요구사항:
     - Claude in Chrome Extension v1.0.36+
     - Claude Code v2.0.73+
     - Chrome 또는 Edge 브라우저
     ```
   - 활성 상태면 Phase 2로 진행

### Phase 2: Scenario Parsing

1. **자연어 시나리오 분석**
   - 사용자가 입력한 자연어를 테스트 단계로 분해
   - 각 단계에 예상 결과(assertion)를 자동 추론
   - 단계 간 의존관계 파악

2. **테스트 계획 출력**
   ```
   ## Test Plan

   **Journey:** {parsed scenario}
   **Base URL:** {url}
   **Steps:** {count}

   1. {action} → expects: {expected result}
   2. {action} → expects: {expected result}
   ...

   Proceed? (y/n)
   ```

### Phase 3: Test Execution

`chrome-e2e-runner` 에이전트를 호출하여 실제 테스트를 수행합니다.

에이전트가 수행하는 작업:
1. Chrome 탭을 열고 대상 URL로 이동
2. 각 단계를 순차적으로 실행
3. 매 단계마다 DOM 상태, 콘솔 에러 확인
4. 스크린샷 캡처
5. 실패 시 원인 분석 및 의존 단계 스킵
6. `--gif` 옵션 시 세션 전체 녹화

### Phase 4: Report

단계별 체크리스트 형식으로 결과를 보고합니다:

```
## E2E Chrome Test Report

**Journey:** 로그인 → 대시보드 → 설정 변경
**URL:** http://localhost:3000
**Status:** ⚠️ PARTIAL PASS
**Duration:** 12.3s

### Steps
1. ✅ 로그인 페이지 접근 (1.2s)
2. ✅ 이메일/비밀번호 입력 (0.8s)
3. ✅ 대시보드 로딩 확인 (2.1s)
4. ❌ 설정 메뉴 클릭 실패
   └ 📸 screenshot: settings-btn-not-found.png
   └ 🔍 원인: data-testid="settings" 요소 없음
   └ 💡 제안: SettingsButton 컴포넌트의 조건부 렌더링 확인
5. ⏭ 설정 변경 (스킵 - 4번 의존)

### Console Errors
- [ERROR] Uncaught TypeError: Cannot read property 'role' of undefined (settings.js:42)

### Artifacts
- 📸 Screenshots: 4 files
- 🎬 GIF: session-recording.gif

### Issues Found
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 1 | 🔴 HIGH  | 설정 버튼 미렌더링 | SettingsButton.tsx |
| 2 | 🟡 MED   | role 프로퍼티 null 참조 | settings.js:42 |
```

## Tool Coordination

| Tool | Role |
|------|------|
| Agent (chrome-e2e-runner) | 실제 Chrome 브라우저 제어 및 테스트 수행 |
| Read | 프로젝트 소스코드 참조 (실패 원인 분석 시) |
| Grep | 에러 관련 코드 검색 |
| Glob | 테스트 대상 컴포넌트 파일 탐색 |

## Examples

### 기본 사용
```
/e2e-chrome 로그인 후 대시보드에서 최근 주문 목록이 보이는지 확인
```

### URL 지정
```
/e2e-chrome --url https://staging.example.com 상품 검색 후 장바구니에 추가하고 결제 페이지까지 진행
```

### GIF 녹화
```
/e2e-chrome --gif 회원가입 폼을 작성하고 이메일 인증 페이지로 리다이렉트되는지 확인
```

### 반응형 테스트
```
/e2e-chrome --viewport mobile 모바일에서 햄버거 메뉴를 열고 네비게이션이 정상 동작하는지 확인
```

### 인증된 앱 테스트
```
/e2e-chrome Google Docs에서 새 문서를 만들고 제목을 입력한 뒤 저장되는지 확인
```

## Playwright(/e2e)와의 비교

| 상황 | 추천 커맨드 |
|------|------------|
| CI/CD 회귀 테스트 | `/e2e` (Playwright) |
| 로컬 시각적 확인 | `/e2e-chrome` |
| 인증이 필요한 앱 | `/e2e-chrome` |
| 다중 브라우저 테스트 | `/e2e` (Playwright) |
| 헤드리스 자동화 | `/e2e` (Playwright) |
| 프론트엔드 변경 후 빠른 검증 | `/e2e-chrome` |
| 팀에 GIF로 결과 공유 | `/e2e-chrome` |
| 외부 서비스(Google, Notion) 테스트 | `/e2e-chrome` |

## Boundaries

**Will:**
- 실제 Chrome 브라우저에서 자연어 기반 E2E 테스트 수행
- 브라우저의 기존 인증 세션을 활용한 테스트
- 매 단계 스크린샷 캡처 및 GIF 녹화
- DOM 상태, 콘솔 에러 기반 실패 원인 분석
- 단계별 체크리스트 형식의 결과 보고
- 실패 시 소스코드 참조하여 수정 제안

**Will Not:**
- CI/CD 파이프라인에서 실행 (로컬 전용)
- Playwright 테스트 코드 생성 (그건 `/e2e`의 역할)
- 브라우저 외 다른 앱 제어
- 사용자 인증 정보 저장 또는 전송
- 프로덕션 환경 대상 자동 테스트

## Related

- `/e2e` - Playwright 기반 E2E 테스트 (CI/CD 자동화)
- `chrome-e2e-runner` agent - 이 커맨드가 호출하는 전용 에이전트
