// 경로 상수 — observe 가 읽고 쓰는 모든 경로의 단일 출처 (기록 훅·리포트·migrate 공유).
//
// 레이아웃 (스키마 v1):
//   <repo>/.tracer/.gitignore                                — "*" 자기 무시 (커밋 차단 안전망)
//   <repo>/.tracer/VERSION                                   — 저장소 스키마 버전
//   <repo>/.tracer/events/<runtime>/<YYYY-MM>/<session>.jsonl — 정규 이벤트(원문 없음), 세션별 파일
//   <repo>/.tracer/raw/<YYYY-MM>/<session>.jsonl              — 프롬프트 원문·why 등 원문 파생 텍스트(레드액션 후)
//   <repo>/.tracer/digests/<YYYY-MM>/<session>.jsonl          — turn_summary / session_summary (원문 없음)
//   <repo>/.tracer/cursors/<runtime>/<session>.json           — transcript 증분 파싱 커서(바이트 오프셋)
//   <repo>/.tracer/recommendations.jsonl                     — 추천 생성·상태 전이 이벤트(append-only, 원문 없음)
//   <repo>/.tracer/events/git-hook/<YYYY-MM>.jsonl            — git post-commit 훅의 commit 이벤트(월 파일, 한 줄 < PIPE_BUF)
//   <repo>/.tracer/commits/<sha>.md                          — 커밋 분석 결과(post-commit detached 분석기, 원문 없음)
//   <repo>/.tracer/index/                                    — 파생물(삭제해도 안전): precommit.txt(pre-commit 1줄)·llm-budget.json
//   ~/.tracer/index/repos.d/<sha1(root)>                     — 전역 합산(--all)용 레포 등록 마커(레포당 1파일, 내용=루트 경로)
// 홈 디렉터리는 레포 루트가 될 수 없다 — <홈>/.tracer 가 곧 전역 층이라 원문(raw/)이 전역에 섞인다.
// 그래서 세션 루트가 홈이면 기록하지 않는다(writer.write 가 거부, isHome).
// 구 경로 <repo>/.claude/skill-trace.jsonl(.1) 은 v0 으로 읽기만 한다 (호환 reader, migrate 대상).
// 쓰기는 .tracer/ 하위로만 한다 — 다른 에이전트의 설정 공간(.agents/·.claude/)에는 쓰지 않는다.
const fs = require('fs');
const os = require('os');
const path = require('path');

const TRACER_DIR = '.tracer';
const SCHEMA_VERSION = 1;

// 레포 루트 탐지 — CLAUDE_PROJECT_DIR → git rev-parse --show-toplevel(cwd 기준) → cwd.
// CLAUDE_PROJECT_DIR(Claude Code 훅 실행 시 항상 프로젝트 루트)이 최우선이다. 이 변수가 없는
// 런타임(Codex 등)에서 payload cwd 를 그대로 쓰면 하위 디렉터리마다 트레이스가 흩어지므로
// git toplevel 로 끌어올린다. git 이 없거나 저장소 밖이면 cwd 폴백 (best-effort, stdout 무출력).
function repoRoot(cwd) {
  if (process.env.CLAUDE_PROJECT_DIR) return process.env.CLAUDE_PROJECT_DIR;
  const dir = cwd || process.cwd();
  return gitTop(dir) || dir;
}
function gitTop(dir) {
  try {
    const top = require('child_process').execFileSync('git', ['rev-parse', '--show-toplevel'], {
      cwd: dir, encoding: 'utf8', timeout: 2000, stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return top || null;
  } catch (_) { return null; } // git 부재·저장소 밖·cwd 소실 → 폴백
}

// realpath 비교용 (미존재면 resolve 값)
function real(p) {
  const abs = path.resolve(p);
  try { return fs.realpathSync(abs); } catch (_) { return abs; }
}
// 루트가 홈 디렉터리인가 — 홈의 .tracer 는 전역 층(globalDir)과 같은 디렉터리다.
const isHome = (root) => real(root) === real(os.homedir());

// 읽기 측(리포트·migrate) 루트 탐지 — 기록 측과 같은 위치를 찾아야 한다.
// 훅은 CLAUDE_PROJECT_DIR(=Claude Code 를 띄운 디렉터리, 하위 패키지일 수 있음)에 쓰지만,
// Bash 툴 환경에는 이 변수가 없다(실측). 그래서 cwd 에서 위로 올라가며 .tracer/ 또는 구 경로
// .claude/skill-trace.jsonl(.1) 이 있는 가장 가까운 조상을 쓴다. 탐색은 git toplevel(있으면, 없으면
// 파일시스템 루트)에서 멈추고 홈은 건너뛴다(홈의 .tracer 는 전역 층). 못 찾으면 기록 측 탐지로 폴백.
function findRoot(cwd) {
  if (process.env.CLAUDE_PROJECT_DIR) return process.env.CLAUDE_PROJECT_DIR;
  const start = real(cwd || process.cwd());
  const top = gitTop(start);
  const stop = top ? real(top) : null;
  for (let d = start; ; d = path.dirname(d)) {
    if (!isHome(d)) {
      const leg = legacyTrace(d);
      if (fs.existsSync(path.join(d, TRACER_DIR)) || fs.existsSync(leg) || fs.existsSync(leg + '.1')) return d;
    }
    if (d === stop || d === path.dirname(d)) break;
  }
  return top || start;
}

// 파일명 안전화 — session/runtime 은 payload 유래(무검증)라 경로 구분자·'..' 로 .tracer 밖을
// 가리킬 수 없게 한다. 빈 값은 "_none"(session_id 부재 레코드 — v0 쓰레기 레코드 migrate 경로).
const safe = (s) => String(s || '').replace(/[^A-Za-z0-9._-]/g, '_').replace(/^\.+/, '_') || '_none';
// ts → "YYYY-MM" (월 샤딩). 파싱 불가면 현재 월.
function month(ts) {
  const d = new Date(ts || Date.now());
  return (Number.isNaN(d.getTime()) ? new Date() : d).toISOString().slice(0, 7);
}

const tracerDir = (root) => path.join(root, TRACER_DIR);
const eventsDir = (root) => path.join(root, TRACER_DIR, 'events');
const rawDir = (root) => path.join(root, TRACER_DIR, 'raw');
// raw ref 는 .tracer 기준 상대경로 + "#<id>" — 레포를 옮겨도 깨지지 않는다.
const rawRel = (session, ts) => path.posix.join('raw', month(ts), safe(session) + '.jsonl');
const eventsFile = (root, runtime, session, ts) =>
  path.join(eventsDir(root), safe(runtime), month(ts), safe(session) + '.jsonl');
const digestsDir = (root) => path.join(root, TRACER_DIR, 'digests');
const digestFile = (root, mon, session) => path.join(digestsDir(root), mon, safe(session) + '.jsonl');
const cursorsDir = (root, runtime) => path.join(root, TRACER_DIR, 'cursors', safe(runtime));
const cursorFile = (root, runtime, session) => path.join(cursorsDir(root, runtime), safe(session) + '.json');
const recommendationsFile = (root) => path.join(root, TRACER_DIR, 'recommendations.jsonl');
const gitHookEventsFile = (root, ts) => path.join(eventsDir(root), 'git-hook', month(ts) + '.jsonl');
const commitsDir = (root) => path.join(root, TRACER_DIR, 'commits');
const indexDir = (root) => path.join(root, TRACER_DIR, 'index');
const legacyTrace = (root) => path.join(root, '.claude', 'skill-trace.jsonl');

// 전역 층 — os.homedir() 는 POSIX 에서 $HOME 을 따른다 (검증 시 HOME 을 임시 디렉터리로 바꿔 격리).
const globalDir = () => path.join(os.homedir(), TRACER_DIR);
const reposDir = () => path.join(globalDir(), 'index', 'repos.d');

module.exports = {
  TRACER_DIR, SCHEMA_VERSION, repoRoot, gitTop, findRoot, isHome, real, safe, month,
  tracerDir, eventsDir, rawDir, rawRel, eventsFile, digestsDir, digestFile, cursorsDir, cursorFile,
  recommendationsFile, gitHookEventsFile, commitsDir, indexDir, legacyTrace, globalDir, reposDir,
};
