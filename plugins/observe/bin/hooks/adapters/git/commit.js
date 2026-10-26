// git 커밋 경계 어댑터 — observe-git-hooks.js 가 설치한 git 훅(POSIX sh)이 부르는 진입점 + detached 분석 worker.
//   post-commit <sha> : 훅이 백그라운드(&)로 띄운다. 게이트 확인 뒤 detached worker(setsid — 터미널 Ctrl-C·Bash 툴의
//                       프로세스 그룹 정리와 무관)를 띄우고 즉시 끝난다. git commit 은 이 프로세스를 기다리지 않는다.
//                       한계: 이 중계 프로세스는 worker 를 띄울 때까지(~30–40ms) git 의 프로세스 그룹에 있다 — git 종료
//                       직후 그룹 전체를 SIGKILL 하는 환경(CI 러너·timeout 래퍼)에선 commit 이벤트·.md 가 다 없고, 이벤트가
//                       없어 relink 로도 못 살린다. 이식 가능한 sh setsid 가 없어(macOS) 훅에서 직접 분리하지 않는다.
//                       Claude Code Bash 툴은 백그라운드 잡을 죽이지 않는다(실측).
//   pre-commit        : 미처리 추천 1줄(결정론, LLM 없음)을 다시 계산해 .tracer/index/precommit.txt 에 쓰고 stderr 로 낸다.
//                       훅은 평소 그 파일을 cat 만 하고, recommendations.jsonl 이 더 새로울 때만 이 모드를 부른다(node 기동 회피).
//   --worker <job>    : commit 이벤트 append(events/git-hook/<YYYY-MM>.jsonl) → 세션 귀속(lib/commits) → commits/<sha>.md
//                       → (OBSERVE_LLM=1 이고 일일 상한 안이면) LLM 해석 덧붙임 → 최근 커밋 중 sha 귀속이 아닌 것 재연결.
// 규약: stdout 무출력(pre-commit 의 1줄만 stderr), 항상 exit 0, OBSERVE_TRACE opt-in·OBSERVE_CHILD=1 즉시 종료(writer.enabled).
// LLM 자식(claude -p)은 OBSERVE_CHILD=1 로 띄운다 — 자식 세션의 observe 훅·git 훅이 무동작해 자기 관측·재귀가 없다.
// 일일 상한은 .tracer/index/llm-budget.json({day, used}) — 호출 전에 예약(+1)하므로 실패한 호출도 센다(비용 상한 보수적).
// 동시 커밋 두 개가 같은 순간 예약하면 상한을 1 넘길 수 있다(잠금 없음 — 수동 상수 상한이라 허용).
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const P = require('../../_lib/paths');
const { enabled, appendV1, redact } = require('../../_lib/writer');
const C = require('../../../lib/commits');

const RUNTIME = 'git-hook';
const LLM_DAILY_DEFAULT = 5;     // OBSERVE_LLM_DAILY 로 조정 (0 이면 사실상 끔)
const LLM_TIMEOUT_MS = 120000;
const LLM_OUT_MAX = 2000;
const RELINK_MAX = 10;           // 재연결 대상: 최근 git 훅 커밋 수
const RELINK_DAYS = 7;
const SHA_RE = C.SHA_RE;
const LLM_INSTR = '아래는 방금 만든 git 커밋의 결정론 요약(원문 없음)이다. 이 커밋을 만든 작업 방식에서 기존 스킬·커맨드·하네스를 ' +
  '썼다면 나았을 지점이 있으면 3줄 이내 한국어 불릿으로 제안하고, 없으면 "없음" 한 줄만 써라. 파일을 수정하거나 도구를 실행하지 마라.';
// 자식은 도구 0개(--tools "")·MCP 0개(--strict-mcp-config) — 지시문이 아니라 CLI 로 막는다(허용적 defaultMode 레포에서도 무행동).
// 다른 플러그인의 훅은 그대로 돈다(--bare 는 OAuth 인증을 끊어 쓰지 않음).
const LLM_ARGS = ['-p', LLM_INSTR, '--tools', '', '--strict-mcp-config'];

// 훅 환경의 GIT_* 경로 변수는 커밋 중 임시값(GIT_INDEX_FILE 상대경로 등) — worker·자식 git 은 cwd(레포 루트)로 다시 찾는다
function gitEnv(extra) {
  const e = { ...process.env, ...(extra || {}) };
  for (const k of ['GIT_DIR', 'GIT_INDEX_FILE', 'GIT_WORK_TREE', 'GIT_PREFIX']) delete e[k];
  return e;
}
const git = (root, args) => cp.execFileSync('git', args, {
  cwd: root, encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'], env: gitEnv(), maxBuffer: 16 * 1024 * 1024,
});
const gitOr = (root, args, dflt) => { try { return git(root, args); } catch (_) { return dflt; } };

// sha → { sha, short, ts(커미터 시각 ISO), subject, branch, parents_n, action, files, trailer }. 실패는 throw.
function gitInfo(root, sha) {
  const [full, parents, ct, subject, body] = git(root, ['show', '-s', '--format=%H%x00%P%x00%cI%x00%s%x00%B', sha]).split('\0');
  const files = gitOr(root, ['diff-tree', '--no-commit-id', '--name-only', '-r', '--root', full], '').split('\n').filter(Boolean);
  // 동작 — reflog 의 그 커밋 줄(“commit (amend): …” 등). 못 찾으면 commit
  let action = 'commit';
  for (const l of gitOr(root, ['reflog', '-n', '50', '--format=%H%x00%gs'], '').split('\n')) {
    const [h, gs = ''] = l.split('\0');
    if (h !== full) continue;
    const m = /^(?:commit \((amend|initial|merge)\)|(rebase|cherry-pick|revert|pull|merge))/.exec(gs);
    action = m ? (m[1] || m[2]) : 'commit';
    break;
  }
  const tr = /^Agent-Session:\s*([A-Za-z0-9._-]+)\/(\S+)\s*$/m.exec(body || '');
  const d = new Date(ct);
  return {
    sha: full, short: full.slice(0, 7), ts: Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString(),
    subject: subject || '', branch: gitOr(root, ['symbolic-ref', '--short', '-q', 'HEAD'], '').trim() || null,
    parents_n: parents.trim() ? parents.trim().split(/\s+/).length : 0, action, files,
    trailer: tr ? { runtime: tr[1], session: tr[2] } : null,
  };
}

// 커서 이후 아직 확정 안 된 턴(Claude·Codex) — 읽기 전용 요약(기록하지 않는다). 커밋 시점엔 그 턴 다이제스트가 아직 없어서다
// (둘 다 마지막 사람 턴을 1턴 늦게 확정한다). 커서의 offset 은 그 커서가 가리키는 transcript 기준이라 같은 파일만 읽는다.
function pendingTurns(root, ctMs) {
  const D = require('../../_lib/digest');
  const T = require('../claude/transcript');
  const X = require('../codex/rollout');
  const parsers = [
    [T.RUNTIME, (t, c) => T.parseTurns(t, c.offset || 0, true, root, c.session).turns],
    [X.RUNTIME, (t, c) => { // rollout 은 .zst 해제 포함 버퍼 단위 — 세션 키는 session_meta.id (digestSession 과 같다)
      const buf = X.loadBuffer(t);
      const meta = X.metaOf(buf);
      return meta ? X.parseBuffer(buf, meta, c.offset || 0, true, root, meta.id || c.session).turns : [];
    }],
  ];
  const out = [];
  for (const [runtime, parse] of parsers) {
    for (const c of D.listCursors(root, runtime)) {
      const t = D.untildify(c.transcript);
      let st;
      try { st = fs.statSync(t); } catch (_) { continue; }
      if (!D.grownSince(c, t) || (ctMs != null && st.mtimeMs < ctMs - C.WINDOW_MS)) continue;
      try { for (const x of parse(t, c)) out.push(x.summary); } catch (_) { /* 세션 하나 실패 무시 */ }
    }
  }
  return out;
}

const mdFile = (root, sha) => path.join(P.commitsDir(root), sha + '.md');
const readText = (f) => { try { return fs.readFileSync(f, 'utf8'); } catch (_) { return null; } };
function writeAtomic(f, text) {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, f);
}

// 커밋 1개 분석 → { attr, md(LLM 절 제외 결정론 본문) }
function render(root, info, env, pending) {
  const turns = C.mergeTurns(C.digestTurns(root), pending);
  const attr = C.attribute({ sha: info.sha, ts: info.ts, files: info.files, trailer: info.trailer, env }, turns, C.runtimeCommits(root));
  return { attr, md: C.renderMd(info, attr, C.precommitLine(root)) };
}
// 기존 .md 의 LLM 절(있으면)을 보존하며 쓴다
function writeMd(root, sha, md) {
  const f = mdFile(root, sha);
  const prev = readText(f);
  const i = prev ? prev.indexOf(C.LLM_HEAD) : -1;
  writeAtomic(f, i >= 0 ? md + '\n' + prev.slice(i) : md);
}

// LLM 해석 — OBSERVE_LLM=1 일 때만. 반환: 덧붙일 절 텍스트 | null(꺼짐)
function llmSection(root, md) {
  if (!/^(1|true|on|yes)$/i.test(process.env.OBSERVE_LLM || '')) return null;
  const n = Number.parseInt(process.env.OBSERVE_LLM_DAILY, 10);
  const max = Number.isFinite(n) && n >= 0 ? n : LLM_DAILY_DEFAULT;
  const f = path.join(P.indexDir(root), 'llm-budget.json');
  const day = new Date().toLocaleDateString('sv'); // 로컬 날짜 YYYY-MM-DD
  let b = {};
  try { b = JSON.parse(fs.readFileSync(f, 'utf8')) || {}; } catch (_) { b = {}; }
  const used = b.day === day && Number.isFinite(b.used) ? b.used : 0;
  if (used >= max) return `${C.LLM_HEAD}\n- (생략: 일일 상한 ${max}회 도달)\n`;
  writeAtomic(f, JSON.stringify({ v: 1, day, used: used + 1, max }) + '\n'); // 호출 전 예약
  const env = gitEnv({ OBSERVE_CHILD: '1' });
  delete env.CLAUDECODE; // 중첩 세션 표식·세션 id 를 자식에 넘기지 않는다(자식은 독립 헤드리스 세션)
  delete env.CLAUDE_CODE_SESSION_ID;
  try {
    const out = cp.execFileSync('claude', LLM_ARGS, {
      cwd: root, input: md, encoding: 'utf8', timeout: LLM_TIMEOUT_MS, stdio: ['pipe', 'pipe', 'ignore'], env, maxBuffer: 1024 * 1024,
    });
    return `${C.LLM_HEAD}\n${redact(String(out)).trim().slice(0, LLM_OUT_MAX) || '- (빈 응답)'}\n`;
  } catch (e) {
    return `${C.LLM_HEAD}\n- (실패: ${e.code || (e.signal ? 'signal ' + e.signal : 'exit ' + e.status)})\n`;
  }
}

// worker 본체 — job = { root, sha, env:{runtime,session}|null }. opts.relink=false 면 재연결 생략, opts.llm=false 면 LLM 생략.
function analyze(job, opts = {}) {
  const root = job.root;
  const info = gitInfo(root, job.sha);
  const prior = C.hookCommits(root);
  const known = prior.find((e) => e.commit.sha === info.sha);
  const env = job.env || (known && known.agent) || null;
  if (!known) {
    appendV1(root, P.gitHookEventsFile(root, info.ts), {
      v: P.SCHEMA_VERSION, ts: info.ts, runtime: RUNTIME, session: null, turn: null, turn_src: null, kind: 'commit',
      commit: { sha: info.sha, branch: info.branch, parents_n: info.parents_n, action: info.action, files_n: info.files.length, source: 'post-commit' },
      agent: env, // 커밋 시점 세션 힌트(env) — 원문 없음
    });
  }
  const pending = pendingTurns(root, Date.parse(info.ts));
  const { attr, md } = render(root, info, env, pending);
  writeMd(root, info.sha, md);
  const llm = opts.llm === false ? null : llmSection(root, md);
  if (llm) writeAtomic(mdFile(root, info.sha), md + '\n' + llm);
  if (opts.relink !== false) relink(root, info.sha, prior, pending);
  return { sha: info.sha, file: mdFile(root, info.sha), attr };
}
// 최근 커밋 중 sha 귀속이 아닌 것 — 그 뒤 다이제스트가 쌓였으면 귀속이 바뀐다(바뀐 것만 다시 쓴다)
function relink(root, cur, prior, pending) {
  const since = Date.now() - RELINK_DAYS * 86400000;
  for (const e of prior.slice(-RELINK_MAX)) {
    if (e.commit.sha === cur || !(Date.parse(e.ts) >= since)) continue;
    const head = C.readHead(readText(mdFile(root, e.commit.sha)));
    if (head && head.method === 'sha') continue;
    try {
      const { attr, md } = render(root, gitInfo(root, e.commit.sha), e.agent || null, pending);
      if (head && head.method === attr.method && head.session === attr.session && head.turn === attr.turn) continue;
      writeMd(root, e.commit.sha, md);
    } catch (_) { /* 이력에서 사라진 커밋(rebase·gc) 등 — 건너뜀 */ }
  }
}

function precommit(root) {
  const line = C.precommitLine(root);
  if (line) process.stderr.write(line + '\n'); // 캐시 쓰기보다 먼저 — index 에 못 써도 줄은 낸다
  try { writeAtomic(path.join(P.indexDir(root), 'precommit.txt'), line ? line + '\n' : ''); } catch (_) { /* 다음 커밋도 다시 계산 */ }
}

module.exports = { analyze, gitInfo, pendingTurns, precommit, RUNTIME };

if (require.main === module) {
  const [mode, arg] = process.argv.slice(2);
  try {
    if (mode === 'post-commit') {
      process.on('SIGINT', () => {}); // 백그라운드 중계 프로세스 — worker 를 띄울 때까지 터미널 신호로 죽지 않게
      process.on('SIGHUP', () => {});
      if (enabled() && SHA_RE.test(arg || '')) {
        const sid = process.env.CLAUDE_CODE_SESSION_ID;
        const job = { root: process.cwd(), sha: arg, env: sid ? { runtime: 'claude-code', session: sid } : null };
        cp.spawn(process.execPath, [__filename, '--worker', JSON.stringify(job)], { detached: true, stdio: 'ignore', env: gitEnv() }).unref();
      }
    } else if (mode === 'pre-commit') {
      if (enabled()) precommit(process.cwd());
    } else if (mode === '--worker') {
      if (enabled()) analyze(JSON.parse(arg));
    }
  } catch (_) { /* best-effort — 커밋 결과에 영향 없음 */ }
  process.exitCode = 0;
}
