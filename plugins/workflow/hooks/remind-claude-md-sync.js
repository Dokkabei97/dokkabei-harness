// PreToolUse: git commit/push 전 CLAUDE.md 갱신 검토를 세션당 1회 강제.
// 배경: workflow:sync-claude-md 스킬은 "커밋/푸시 요청 시 자동 발화"가 계약이지만
//       실측(observe 계측)상 모델이 미발화(2/2) — 스킬 발화를 모델 재량에 맡기지 않는
//       결정론 경로로 첫 commit/push 를 exit 2 차단하고 검토를 지시한다.
//       검토(필요시 갱신) 후 같은 명령을 재시도하면 마커로 통과된다.
// 명령 패턴 필터는 스크립트 내부 (hooks.json matcher 는 tool 명 regex 만 유효 —
// 표현식 matcher 미발화 실측, 2026-07).
// 셀프컨테인드 — base 플러그인 _lib 에 의존하지 않는다(플러그인 간 경로 결합 금지).

const fs = require("fs");
const os = require("os");
const path = require("path");

// 명령 시작 또는 구분자(;, &, |) 뒤의 git commit/push 만 발동 —
// "echo git commit" 같은 인자 위치 등장이나 "git commitfoo" 오탐 방지(\b).
const GIT_COMMIT_PUSH = /(^|[;&|]\s*)git\s+(commit|push)\b/;

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
      resolve({ raw: buf, json });
    });
  });

(async () => {
  const { raw, json } = await readEvent();
  const pass = () => {
    console.log(raw);
  };

  // 게이트 1: 킬스위치 — CLAUDE_MD_SYNC_REMIND=0 이면 항상 통과
  if (process.env.CLAUDE_MD_SYNC_REMIND === "0") return pass();

  const cmd = json.tool_input?.command || "";
  if (!GIT_COMMIT_PUSH.test(cmd)) return pass();

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
  if (!hasClaudeMd) return pass();

  // 세션당 1회 — tmpdir 마커로 재차단 방지(같은 명령 재시도는 통과)
  const sid = String(json.session_id || "nosession").replace(
    /[^A-Za-z0-9._-]/g,
    "_",
  );
  const marker = path.join(os.tmpdir(), "claude-md-sync-remind-" + sid);
  try {
    if (fs.existsSync(marker)) return pass();
    fs.writeFileSync(marker, new Date().toISOString() + "\n");
  } catch (_) {
    // 마커를 기록할 수 없으면 fail-open — 세션 내내 반복 차단되는 루프를 막는다
    return pass();
  }

  console.error(
    "[Hook] BLOCKED(세션당 1회): 커밋/푸시 전 workflow:sync-claude-md 로 CLAUDE.md 갱신 필요 여부를 검토하라. " +
      "검토(필요시 갱신) 후 같은 명령을 재시도하면 통과된다. 비활성화: CLAUDE_MD_SYNC_REMIND=0",
  );
  process.exit(2); // PreToolUse 차단은 exit 2 — exit 1 은 비차단 경고라 통과된다
})();
