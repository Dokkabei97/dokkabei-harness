---
name: observe-git-hooks
description: "observe 커밋 경계 수집용 git 훅 opt-in 설치·제거·상태 확인 — post-commit(commit 이벤트 + detached 분석기 → .tracer/commits/<sha>.md, LLM 은 OBSERVE_LLM=1 일 때만·일일 상한), 비차단 pre-commit(미처리 추천 결정론 1줄 stderr, 항상 기존 훅 종료코드), 선택 prepare-commit-msg trailer(--trailer). 기존 훅은 체이닝·백업, core.hooksPath/husky/lefthook 감지 시 안내만. Installs, removes, or reports opt-in git hooks for observe's commit boundary: post-commit commit event plus detached analyzer writing .tracer/commits/<sha>.md (LLM only with OBSERVE_LLM=1, daily cap), a non-blocking pre-commit one-line recommendation summary, and an optional Agent-Session trailer; chains existing hooks with backup and only prints guidance when core.hooksPath, husky, or lefthook manage hooks. Use when: installing or uninstalling observe git hooks, linking commits to agent sessions, commit-time harness summary."
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /observe-git-hooks - 커밋 경계 git 훅 (opt-in)

## Triggers
- 커밋과 에이전트 세션·턴을 연결해 커밋 단위 분석(`.tracer/commits/<sha>.md`)을 남기고 싶을 때
- 커밋 직전에 미처리 추천(스킬 미발화 등)을 한 줄로 보고 싶을 때
- 설치한 observe git 훅을 제거(원복)하거나 상태(stale 여부)를 확인할 때

## Usage
```
/observe-git-hooks install [--no-pre-commit] [--trailer]
/observe-git-hooks uninstall | status
/observe-git-hooks print <post-commit|pre-commit|prepare-commit-msg>
```

## Behavioral Flow
1. `node ${CLAUDE_PLUGIN_ROOT}/bin/observe-git-hooks.js $ARGUMENTS` 를 현재 레포에서 실행하고 출력을 그대로 보여준다
   (`${CLAUDE_PLUGIN_ROOT}` 미치환이면 저장소의 `plugins/observe/bin/observe-git-hooks.js`).
2. 인자가 없으면 `status` 를 실행하고, 설치는 사용자가 명시적으로 `install` 을 요청했을 때만 한다(사용자 저장소 설정 변경).
3. `install` 출력에 "감지"(core.hooksPath·husky·lefthook)가 있으면 설치되지 않은 것이다 — 안내된 `print` 출력을 그 도구의 훅에
   넣는 방법만 설명하고, 도구 설정 파일은 수정하지 않는다.
4. 기록은 `OBSERVE_TRACE=1` 인 셸·세션의 커밋만 남는다고 한 줄 안내한다(터미널에서 직접 하는 사람 커밋은 그 셸에도 필요).

## Will Not
- 사용자 요청 없이 훅을 설치하거나 husky·lefthook·core.hooksPath 설정을 바꾸지 않는다
- pre-commit 에서 LLM 을 호출하거나 커밋을 차단하지 않는다(기존 훅의 종료코드만 그대로 전달)
