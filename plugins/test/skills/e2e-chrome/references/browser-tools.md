# 브라우저 도구 운용 메모

도구 이름·파라미터는 세션에 로드된 스키마가 정답이다. 아래는 증거 수집 관점의 매핑과 주의점.

## claude-in-chrome (사용자의 실제 Chrome)

| 목적 | 도구 |
|------|------|
| 열린 탭 확인 → 새 탭에서 작업 | `tabs_context_mcp` → `tabs_create_mcp` (사용자가 쓰는 탭을 건드리지 않는다) |
| 이동·클릭·입력 | `navigate`, `computer`, `form_input`, `find` |
| 기대 결과 확인 (텍스트 증거) | `read_page`(접근성 트리), `get_page_text` |
| 스크린샷 | `computer`(screenshot 동작) |
| 콘솔 에러 | `read_console_messages` — 패턴 필터로 error 만 |
| 네트워크 | `read_network_requests` — 4xx/5xx·실패 요청 |
| 여정 녹화 | `gif_creator` |
| 뷰포트 | `resize_window` |

- 지연 로드 도구라면 필요한 도구를 **한 번의 ToolSearch** 로 같이 로드한다.
- **실제 프로필·실제 로그인 세션**이다. 클릭 한 번이 실제 메일 발송·결제·삭제가 될 수 있다 → 되돌릴 수 없는 동작 직전에 사용자 확인.
- 네이티브 JS 다이얼로그(`alert`/`confirm`/`prompt`, 파일 선택 창)는 확장의 페이지 조작을 막을 수 있다. 유발하는 버튼은 사용자에게 알리고, 필요하면 사용자가 직접 처리하게 한다.
- 사이트 권한이 없다는 응답이 오면 확장에서 해당 사이트 허용을 요청하고 멈춘다.
- 자격증명을 대화나 리포트에 적지 않는다. 로그인 필요 시 사용자가 이미 로그인한 세션을 쓰거나 사용자에게 로그인을 요청.

## Playwright MCP (격리된 브라우저)

| 목적 | 도구(이름 예) |
|------|------|
| 이동·조작 | `browser_navigate`, `browser_click`, `browser_type`, `browser_fill_form`, `browser_select_option` |
| 기대 결과 확인 | `browser_snapshot`(접근성 스냅샷 — 판정의 1차 근거), `browser_wait_for`(텍스트 등장/사라짐 대기) |
| 스크린샷 | `browser_take_screenshot` |
| 콘솔·네트워크 | `browser_console_messages`, `browser_network_requests` |
| 뷰포트 | `browser_resize` |

- 접근성 스냅샷으로 판정하면 스크린샷 해석보다 정확하고 토큰도 적다. 스크린샷은 레이아웃·시각 이슈 증거용.
- 로그인 상태가 없는 새 브라우저다 — 로그인 단계를 시나리오에 포함하거나 테스트 계정 사용.
- 대기는 `browser_wait_for` 로 기대 텍스트 기준. 고정 시간 대기는 마지막 수단.

## 공통

- 판정 근거는 텍스트(스냅샷·페이지 텍스트·콘솔·네트워크)로 남기고 스크린샷은 보조.
- 콘솔/네트워크는 단계마다 "새로 생긴 것"을 기록해야 원인 단계가 특정된다.
- 반응형: desktop(예: 1440×900) → mobile(예: 390×844) 순으로 같은 단계 반복, 차이만 기록.
