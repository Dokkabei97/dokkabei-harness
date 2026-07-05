> [English](README.md) · **한국어**

# base

> 코드 편집·셸 명령에 자동으로 걸리는 공통 가드 훅 계층과 다중 언어 LSP를 제공하는, 루프 하네스의 기반 플러그인.

## 개요

`base`는 다른 플러그인들이 공통으로 깔고 가는 최하위 기반 계층이다. Claude Code의 `PreToolUse`/`PostToolUse` 훅에 붙어, 별도 호출 없이 셸 명령과 파일 편집 시점마다 자동으로 발화한다. 위험한 동작(예: tmux 밖 dev 서버, 문서 파일 남발)은 차단하고, 나머지는 포맷 정리·컴파일 검사·보안 취약점 경고 등 비차단 피드백을 준다.

핵심 설계 의도는 두 가지다. 첫째, 실시간 보안 경고(`warn-security`)로 시크릿·인젝션·역직렬화 등 고신호 패턴을 편집 즉시 잡아내되 절대 흐름을 막지 않는 경고 전용으로 동작시킨다. 둘째, `mvp`·`feature-loop` 같은 루프형 하네스가 `requires`로 전제하는 안전망 역할을 한다 — 자율 반복 루프가 돌 때 이 훅 계층이 가드레일이 된다. 이 플러그인 자체는 커맨드·에이전트·스킬을 노출하지 않고, 순수하게 훅과 LSP 설정만으로 구성된다.

## 구성요소

### 훅 (hooks/hooks.json → bin/hooks/*.js, 총 16종)

모든 훅은 Node.js 스크립트로, `hooks.json`의 matcher는 도구 이름(`Bash`/`Edit`/`Write`)만 지정하고 세부 명령·확장자 필터는 각 스크립트 내부에서 수행한다(표현식 matcher 미발화 실측 대응).

**PreToolUse — 차단/리마인더**

- `block-dev-server.js` (Bash) → dev 서버(`npm/pnpm/yarn/bun dev`, `uvicorn`, `flask run`, `manage.py runserver`, `uv run …`)를 tmux 밖에서 실행하면 로그 접근 보장을 위해 `exit 2`로 차단
- `warn-tmux.js` (Bash) → 장기 실행 명령(`npm/pnpm/yarn install·test`, `gradlew`, `pip install`, `uv sync`, `pytest`, `docker`, `make` 등)을 tmux 밖에서 실행하면 세션 유지 권고(비차단)
- `warn-git-push.js` (Bash) → `git push` 직전 변경 검토 리마인더(비차단, 통과)
- `block-md-creation.js` (Write) → 허용 목록(`README`/`CLAUDE`/`AGENTS`/`CONTRIBUTING`/`HANDOFF`/`CHANGELOG`) 및 `.planning/`·`tasks/` 경로 외의 `.md`/`.txt` 생성을 `exit 2`로 차단(문서 산발 방지)

**PostToolUse — 포맷/컴파일/린트**

- `format-prettier.js` (Edit) → `.ts/.tsx/.js/.jsx` 편집 후 Prettier 자동 포맷
- `format-ktlint.js` (Edit) → `.kt/.kts` 편집 후 ktlintFormat 자동 포맷
- `check-tsc.js` (Edit) → `.ts/.tsx` 편집 후 `tsc --noEmit` 타입 체크, 편집 파일 관련 에러만 보고
- `check-kotlin-compile.js` (Edit) → `.kt/.kts` 편집 후 컴파일 체크
- `check-py-compile.js` (Edit) → `.py` 편집 후 `py_compile` 문법 체크
- `warn-console-log.js` (Edit) → JS/TS의 `console.log` 잔존 경고
- `warn-println.js` (Edit) → Kotlin의 `println()` 잔존 경고
- `warn-print.js` (Edit) → Python의 `print()` 잔존 경고

**PostToolUse — 보안 경고**

- `warn-security.js` (Edit·Write) → 편집된 코드 파일에서 고신호 보안 패턴 15클래스(AWS/GitHub/Slack 토큰·Private Key·자격증명 URL·하드코딩 시크릿, SQL 인젝션·명령 결합·동적 eval/exec, pickle/`yaml.load`/ObjectInputStream 역직렬화, TLS 검증 비활성화, innerHTML/dangerouslySetInnerHTML XSS)를 탐지해 경고. **항상 통과하는 경고 전용**이며, 시크릿 값은 앞 4자만 남기고 마스킹해 출력

**PostToolUse — 빌드/협업**

- `log-pr-mr.js` (Bash) → `gh pr create`/`glab mr create` 성공 시 PR/MR URL과 리뷰·승인 명령 힌트 로깅
- `notify-build-async.js` (Bash, async, timeout 30s) → `npm/pnpm/yarn build` 완료 알림(백그라운드, 논블로킹)
- `notify-gradle-build-async.js` (Bash, async, timeout 60s) → Gradle 빌드 분석 알림(백그라운드, 논블로킹)

### LSP (.lsp.json)

편집 대상 언어별 Language Server를 등록해 진단·정의 이동 등을 제공한다.

- `typescript-language-server` → `.ts/.tsx/.js/.jsx`
- `kotlin-language-server` → `.kt/.kts`
- `jdtls` → `.java`
- `pyright-langserver` → `.py`
- `gopls` → `.go`

## 사용법

설치 후 별도 호출이 필요 없다. 플러그인이 활성화되어 있으면 셸 명령 실행(`Bash`)과 파일 편집(`Edit`/`Write`)마다 관련 훅이 자동으로 발화한다.

- **차단 훅**(`block-dev-server`, `block-md-creation`)은 `exit 2`로 해당 도구 호출을 막는다. dev 서버는 tmux 안에서 실행하고(`tmux new-session -d -s dev "npm run dev"`), 문서는 `README.md`나 허용 경로로 통합하면 통과한다.
- **경고 훅**은 표준 에러로 메시지만 남기고 그대로 진행된다.
- `warn-security` 경고가 의도된 코드라면 해당 라인에 `security-ok` 주석을 달아 억제한다.

## 의존성

- 이 플러그인 자체의 `requires`/`dependencies`는 없다(독립 설치 가능).
- `mvp`, `feature-loop` 등 루프형 하네스가 `requires`로 `base`를 전제한다 — 루프 실행 중 안전망이 되므로 이들과 함께 쓰는 것이 기본 조합이다.

## 참고

- **런타임**: 모든 훅은 `node`로 실행된다. Prettier/ktlint/tsc 등 검사·포맷 훅은 프로젝트에 해당 툴(및 `tsconfig.json` 등 설정)이 있을 때만 동작하고, 없으면 조용히 통과한다.
- **tmux 전제**: dev 서버 차단·장기 실행 경고는 `TMUX` 환경변수 유무로 tmux 세션을 판별한다.
- **경고 vs 차단 규약**: `PreToolUse` 차단은 반드시 `exit 2`(=`exit 1`은 비차단 경고로 통과). `warn-security`를 포함한 모든 경고 훅은 passthrough를 보장한다.
- **ReDoS 방어**: `warn-security`는 1MB 초과 파일·2000자 초과 라인·바이너리(NUL 바이트)·`.md`/`.lock`을 검사에서 제외해 정규식 백트래킹 폭주를 방지한다.
