// PreToolUse(Bash): git commit/push 시 CLAUDE.md 갱신 검토를 세션당 1회 "안내"하는 비차단 넛지.
// 동작: 대상 명령 첫 회에 stdout 으로
//   {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"…"}}
// 를 1회 출력하고 exit 0. permissionDecision 은 넣지 않는다 — 권한 흐름 불간섭.
// 그 외(비대상·2회차·킬스위치·CLAUDE.md 부재·마커 기록 실패·파싱 오류)는 무출력 exit 0.
// 근거: code.claude.com/docs/en/hooks "PreToolUse decision control" — additionalContext 는
//   "String added to Claude's context alongside the tool result" 로 PreToolUse 에서 지원된다.
//   즉 안내는 명령 실행 결과와 함께 도착한다(실행 전 차단 아님) — 커밋 후라면 후속 커밋으로 반영.
//   stdout 은 단일 JSON 객체여야 파싱되므로 v1.x 의 stdin 에코(pass-through)는 제거했다.
// 이력: v1.x 는 exit 2 로 첫 commit/push 를 차단해 스킬을 강제 발동시켰다(observe 실측 미발화 2/2 대응).
//   2026-10 사용자 승인으로 "억제·강제 말고 가이드" 원칙에 맞춰 비차단화.
// 명령 패턴 필터는 스크립트 내부 (hooks.json matcher 는 tool 명 regex 만 유효 —
// 표현식 matcher 미발화 실측, 2026-07).
// 셀프컨테인드 — base 플러그인 _lib 에 의존하지 않는다(플러그인 간 경로 결합 금지).
// 킬스위치: CLAUDE_MD_SYNC_REMIND=0. 어떤 오류도 fail-open(무출력 exit 0).

const fs = require("fs");
const os = require("os");
const path = require("path");

// 명령 시작 또는 구분자(;, &, |, (, 줄바꿈) 뒤의 git commit/push 만 발동 —
// "echo git commit" 같은 인자 위치 등장이나 "git commitfoo" 오탐 방지(\b).
const GIT_COMMIT_PUSH = /(^|[;&|(\n]\s*)git\s+(commit|push)\b/;

const NUDGE =
  "[workflow] 이번 세션 첫 commit/push 입니다. 변경이 아키텍처·통합·컨벤션·도구/환경을 바꿨다면 " +
  "workflow:sync-claude-md 로 CLAUDE.md 갱신 여부를 검토하세요(해당 없으면 무시). " +
  "끄기: CLAUDE_MD_SYNC_REMIND=0";

const readEvent = () =>
  new Promise((resolve) => {
    let buf = "";
    process.stdin.on("data", (c) => {
      buf += c;
    });
    process.stdin.on("end", () => {
      let json = {};
      try {
        json = JSON.parse(buf);
      } catch (_) {}
      resolve(json || {});
    });
  });

(async () => {
  const json = await readEvent();

  // 게이트 1: 킬스위치
  if (process.env.CLAUDE_MD_SYNC_REMIND === "0") return;

  const cmd = (json.tool_input && json.tool_input.command) || "";
  if (typeof cmd !== "string" || !GIT_COMMIT_PUSH.test(cmd)) return;

  // 게이트 2: CLAUDE.md 부재 프로젝트는 비대상 — 검토할 파일이 없다
  const projectDir =
    process.env.CLAUDE_PROJECT_DIR || json.cwd || process.cwd();
  const hasClaudeMd = ["CLAUDE.md", "claude/CLAUDE.md"].some((p) => {
    try {
      return fs.existsSync(path.join(projectDir, p));
    } catch (_) {
      return false;
    }
  });
  if (!hasClaudeMd) return;

  // 게이트 3: 세션당 1회 — tmpdir 마커. wx(O_EXCL) 원자 생성 — 동시 실행에서도 1개만 안내(exists→write 경합 제거)
  const sid = String(json.session_id || "nosession").replace(
    /[^A-Za-z0-9._-]/g,
    "_",
  );
  const marker = path.join(os.tmpdir(), "claude-md-sync-remind-" + sid);
  try {
    fs.writeFileSync(marker, new Date().toISOString() + "\n", { flag: "wx" });
  } catch (_) {
    // 이미 존재(EEXIST)거나 기록 불가 — 무출력. 기록 불가 시 fail-open 으로 매 명령 반복 안내를 막는다
    return;
  }

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: NUDGE,
      },
    }) + "\n",
  );
})().catch(() => {
  // fail-open: 예외는 무출력 exit 0
});
