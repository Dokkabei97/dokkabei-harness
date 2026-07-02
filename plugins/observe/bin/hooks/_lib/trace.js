// 공통 트레이스 헬퍼 — opt-in 게이트 + JSONL append (trace-prompt/trace-skill 공유).
const fs = require('fs');
const path = require('path');

const MAX_BYTES = 10 * 1024 * 1024; // 로그 상한 — 초과 시 .1 로 1세대 로테이션

// OBSERVE_TRACE=1(또는 true) 일 때만 기록. 그 외엔 완전 무동작.
exports.enabled = () => /^(1|true|on|yes)$/i.test(process.env.OBSERVE_TRACE || '');

// 로그 경로 — 프로젝트 루트의 .claude/skill-trace.jsonl.
// CLAUDE_PROJECT_DIR(훅 실행 시 항상 프로젝트 루트) 최우선 — payload cwd 는 Claude 가
// cd 한 현재 디렉토리라 하위/외부일 수 있어 폴백으로만 쓴다 (트레이스 산개 방지).
exports.logPath = (cwd) => {
  const base = process.env.CLAUDE_PROJECT_DIR || cwd || process.cwd();
  return path.join(base, '.claude', 'skill-trace.jsonl');
};

// 프롬프트 원문이 저장소에 커밋되지 않도록 최초 기록 시 .gitignore 안전망을 idempotent 추가.
// git 저장소가 아니거나 실패하면 조용히 넘어간다 (best-effort).
function ensureGitignore(file) {
  try {
    const root = path.dirname(path.dirname(file)); // <root>/.claude/skill-trace.jsonl
    if (!fs.existsSync(path.join(root, '.git'))) return;
    const gi = path.join(root, '.gitignore');
    const line = '.claude/skill-trace.jsonl*';
    const cur = fs.existsSync(gi) ? fs.readFileSync(gi, 'utf8') : '';
    if (!cur.split('\n').some((l) => l.trim() === line)) {
      fs.appendFileSync(gi, (cur && !cur.endsWith('\n') ? '\n' : '') + line + '\n');
    }
  } catch (_) { /* best-effort */ }
}

// append-only JSONL 한 줄 추가. 디렉토리 보장 + 상한 로테이션 + gitignore 안전망.
// 실패는 삼킨다(추적이 본 작업을 막지 않도록).
exports.append = (file, record) => {
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const exists = fs.existsSync(file);
    if (!exists) ensureGitignore(file);
    else if (fs.statSync(file).size > MAX_BYTES) fs.renameSync(file, file + '.1');
    fs.appendFileSync(file, JSON.stringify(record) + '\n');
  } catch (_) { /* 무시 — 관측은 best-effort */ }
};
