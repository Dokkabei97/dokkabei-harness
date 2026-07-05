# etc
> 외부 AI CLI(Antigravity·Codex·Copilot)를 Claude Code에 연결하는 범용 유틸리티 스킬 모음

## 개요
`etc`는 특정 도메인에 묶이지 않는 범용 유틸리티 스킬을 모아둔 "기타" 플러그인입니다. 현재는 외부 AI CLI 도구를 Claude Code 세션 안에서 슬래시 커맨드로 호출하는 두 스킬을 제공합니다. 하나는 Antigravity CLI(`agy`)로 웹 페이지를 깔끔한 Markdown으로 가져오는 폴백 fetcher, 다른 하나는 Codex·Antigravity·Copilot에게 작업을 복잡도 기반으로 라우팅해 협업·위임·병렬로 실행하는 오케스트레이터입니다. 두 스킬 모두 `disable-model-invocation: true`로 설정되어 모델이 스스로 발화하지 않고, 사용자가 명시적으로 슬래시 커맨드를 입력할 때만 실행되는 opt-in 방식입니다.

## 구성요소

### 스킬
- `web-fetch` (`/web-fetch <url> [추출 지시]`) — Antigravity CLI(`agy`)의 네이티브 웹 브라우징으로 URL 콘텐츠를 깔끔한 Markdown으로 가져옵니다. Claude 네이티브 `WebFetch`가 실패했을 때의 폴백 또는 명시적 URL 조회·부분 추출에 사용하며, 속도를 위해 `Gemini 3.5 Flash (Low)` 모델을 사용합니다. 허용 도구는 `Bash(agy *)`로 제한됩니다.
- `with` (`/with <agent|all> <작업 설명>`) — Codex·Antigravity·Copilot 외부 AI CLI 에이전트에 작업을 전달하는 오케스트레이터입니다. 작업 복잡도를 6개 항목으로 자동 점수화(0~5+)해 에이전트별 모델과 effort를 선택하고, 협업(Claude 주도 + 에이전트 참고)·위임(에이전트 주도)·병렬(전 에이전트 응답 비교·종합) 세 가지 모드로 동작합니다. 컨텍스트 분리를 위해 `context: fork`로 실행됩니다.

## 사용법
두 스킬 모두 자동 발화하지 않으므로 슬래시 커맨드로 직접 호출합니다.

**web-fetch**
- `/web-fetch https://docs.python.org/3/library/asyncio.html`
- `/web-fetch https://react.dev/reference/react/useState API 레퍼런스 테이블만 추출`

**with** — 첫 단어로 에이전트를 지정하거나(`codex` / `antigravity`(별칭 `agy`) / `copilot` / `all`), 생략하면 작업 유형으로 자동 선택합니다(코드→Codex, 리서치→Antigravity, GitHub→Copilot). 프롬프트의 키워드로 모드를 판별합니다("같이·의견"→협업, "맡겨·처리해"→위임, "비교·전부·all"→병렬, 키워드가 없으면 기본값 협업).
- `/with codex 이 함수 리팩토링해줘` → Simple, Codex 단일
- `/with antigravity 맡겨 - REST API 설계` → Medium 위임
- `/with all 이 아키텍처 접근법 비교해줘` → Complex 병렬
- `/with 이 에러 디버깅해줘` → 에이전트 자동 선택(Codex)

## 참고
- 플러그인 자체의 선언적 의존성은 없으나, 각 스킬은 외부 CLI가 설치되어 있어야 동작합니다.
  - `web-fetch`: Antigravity CLI `agy` 필요 (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
  - `with`: `codex`, `agy`, `copilot` 중 최소 하나. 미설치 시 설치 명령을 안내하고, 병렬 실행에서는 설치된 에이전트 결과만 표시합니다.
- `agy --model`에는 식별자가 아닌 따옴표로 감싼 표시명을 전달합니다(정확한 목록은 `agy models`로 확인).
- 인증이 필요하거나 접근 불가한 URL은 실패하며, 실패 시 사용자에게 안내합니다.
- 외부 에이전트 호출은 복잡도에 따라 최대 20분까지 소요될 수 있습니다(병렬 실행 시 에이전트별 타임아웃이 개별 적용됨).
