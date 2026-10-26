// Antigravity CLI brain transcript → 턴 다이제스트(turn_summary) + 커밋 이벤트 — 백필 전용(훅 없음, 결정 4).
// 저장은 _lib/digest.js run() 공용(마감 모드, upsert-skip), 명령 분석은 Claude 어댑터 것을 그대로 쓴다. 원문은 남기지 않는다.
//
// 형식 실측 (~/.gemini/antigravity-cli/brain/<uuid>/.system_generated/logs/transcript.jsonl — 로컬 1개 세션 107줄, 2026-07-11):
//   · 줄 = {step_index, source(USER_EXPLICIT|MODEL|SYSTEM), type, status(DONE|ERROR|RUNNING), created_at, content?, tool_calls?,
//     thinking?, truncated_fields?}. 첫 줄에 숫자 step_index·문자열 type 이 없으면 형식 불명 → skip.
//   · 사람 프롬프트 = type USER_INPUT(source USER_EXPLICIT). 모델 = PLANNER_RESPONSE{tool_calls:[{name, args}]}, 그 뒤에 결과 단계
//     (RUN_COMMAND·VIEW_FILE·CODE_ACTION·LIST_DIRECTORY·GREP_SEARCH·GENERIC …)가 호출 순서대로 하나씩 이어진다.
//     args 값은 JSON 문자열로 한 번 더 감싸여 있다("CommandLine":"\"git status\""). 실패 = 결과 단계 status ERROR.
//   · 대화 절단(CHECKPOINT) 뒤 transcript 가 step 0 부터 다시 기록된다(같은 step_index 가 두 번, 실측 0~3·5~29) →
//     step_index 가 고유 키(native id)이고 마지막 기록이 정본이다. 턴 id = "step:<USER_INPUT 의 step_index>".
//   · SYSTEM_MESSAGE("not actually sent by the user" — stop hook 차단·백그라운드 작업 완료 알림)는 턴 경계가 아니다.
//   · 커밋 = run_command CommandLine 의 git commit + 결과 content 의 "[branch sha] …" 줄(실측 1건 622eb09).
//   · 토큰·모델·사용자 취소 마커는 transcript 에 없다(미실측) → tokens·model null, cancelled 판정 없음.
//   · 레포 루트: cwd 필드가 없다 → run_command Cwd 최빈값(없으면 view_file/write_to_file 경로의 디렉터리)을 git toplevel 로.
//     ~/.gemini 아래(antigravity 자체 scratch·brain)는 후보에서 뺀다.
const fs = require('fs');
const os = require('os');
const path = require('path');
const P = require('../../_lib/paths');
const { skillReads, skillNameOf } = require('../../_lib/skill-read');
const C = require('../claude/transcript');

const RUNTIME = 'antigravity';

const CATS = {
  run_command: 'exec', send_command_input: 'exec', command_status: 'exec',
  view_file: 'read', view_file_outline: 'read', view_code_item: 'read',
  list_dir: 'search', grep_search: 'search', find_by_name: 'search', codebase_search: 'search',
  write_to_file: 'edit', replace_file_content: 'edit', multi_replace_file_content: 'edit',
  read_url_content: 'web', search_web: 'web',
};
const catOf = (name) => (/^mcp_/.test(String(name)) ? 'mcp' : /^browser_/.test(String(name)) ? 'web' : CATS[name] || 'other');
// args 값 → 원래 값("\"x\"" → "x"). 감싸지 않은 값은 그대로.
const argOf = (v) => {
  if (typeof v !== 'string') return v;
  try { return /^"/.test(v) ? JSON.parse(v) : v; } catch (_) { return v; }
};

// 파일 → { steps(step_index 오름차순, 중복은 마지막 기록), ok } — 형식 불명이면 ok:false
function readSteps(file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (_) { return { steps: [], ok: false }; }
  const byIdx = new Map();
  let first = true;
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let r;
    try { r = JSON.parse(line); } catch (_) { continue; }
    const valid = r && Number.isInteger(r.step_index) && typeof r.type === 'string';
    if (first) { first = false; if (!valid) return { steps: [], ok: false }; }
    if (valid) byIdx.set(r.step_index, r);
  }
  return { steps: [...byIdx.values()].sort((a, b) => a.step_index - b.step_index), ok: byIdx.size > 0 };
}

// 세션의 레포 루트 후보 디렉터리 (git toplevel 은 호출측이 paths.repoRoot 로)
function cwdOf(steps) {
  const home = path.join(os.homedir(), '.gemini');
  const tally = new Map();
  const add = (d, w) => { if (d && path.isAbsolute(d) && !d.startsWith(home)) tally.set(d, (tally.get(d) || 0) + w); };
  for (const s of steps) for (const c of s.tool_calls || []) {
    const a = c.args || {};
    if (c.name === 'run_command') add(argOf(a.Cwd), 10);
    for (const k of ['AbsolutePath', 'TargetFile', 'DirectoryPath', 'SearchPath']) {
      const v = argOf(a[k]);
      if (typeof v === 'string') add(k === 'DirectoryPath' || k === 'SearchPath' ? v : path.dirname(v), 1);
    }
  }
  let best = null;
  for (const [d, n] of tally) if (!best || n > best[1]) best = [d, n];
  return best ? best[0] : null;
}

// 턴 분할 — USER_INPUT 경계. 첫 USER_INPUT 이전 단계는 버린다.
function segment(steps) {
  const turns = [];
  let cur = null;
  for (const s of steps) {
    if (s.type === 'USER_INPUT') { cur = { id: `step:${s.step_index}`, steps: [], prompt: String(s.content || '') }; turns.push(cur); }
    if (cur) cur.steps.push(s);
  }
  return turns;
}

function summarize(turn, next, session, root) {
  const roots = root ? [...new Set([root, P.real(root)])] : [];
  const order = [];
  const pending = []; // 결과 단계를 기다리는 호출(호출 순서)
  let assistant = 0; let fail = 0; let results = 0; let tsEnd = null; let pushed = false; let branch = null;
  const edited = new Set(); let readN = 0; let newN = 0;
  const skills = []; const commits = []; const shaSeen = new Set();
  for (const s of turn.steps) {
    if (s.created_at && (!tsEnd || s.created_at > tsEnd)) tsEnd = s.created_at;
    if (s.source !== 'MODEL') continue;
    if (s.type === 'PLANNER_RESPONSE') {
      assistant++;
      for (const c of s.tool_calls || []) {
        const a = c.args || {};
        const u = { name: c.name, cat: catOf(c.name), cmd: c.name === 'run_command' ? String(argOf(a.CommandLine) || '') : '', ts: s.created_at, args: a };
        order.push(u);
        pending.push(u);
      }
      continue;
    }
    const u = pending.shift(); // 결과 단계 — 앞선 호출과 순서대로 짝
    results++;
    if (s.status === 'ERROR') fail++;
    if (!u) continue;
    u.status = s.status;
    u.out = typeof s.content === 'string' ? s.content : '';
    u.endTs = s.created_at;
  }
  if (!assistant) return null;

  const counts = { read: 0, search: 0, edit: 0, exec: 0, web: 0, subagent: 0, skill: 0, mcp: 0, plan: 0, other: 0 };
  const execKinds = { test: 0, git: 0, lint: 0, build: 0, pkg: 0, other: 0 };
  const runs = [];
  for (const u of order) {
    counts[u.cat]++;
    let tok = C.LETTER[u.cat];
    if (u.cat === 'exec' && u.cmd) { const k = C.execKind(u.cmd); execKinds[k]++; tok += `(${k})`; }
    const lastRun = runs[runs.length - 1];
    if (lastRun && lastRun[0] === tok) lastRun[1]++;
    else runs.push([tok, 1]);
    if (u.cat === 'read') {
      readN++;
      const n = skillNameOf(argOf(u.args.AbsolutePath), roots);
      if (n && !skills.some((x) => x.name === n)) skills.push({ name: n, trigger: 'model', detection: 'heuristic' });
    }
    if (u.cat === 'edit') {
      const rel = C.relPath(argOf(u.args.TargetFile), roots);
      if (rel) edited.add(rel); // 레포 밖(brain 의 task.md·walkthrough.md 같은 아티팩트)은 세지 않는다
      if (rel && u.name === 'write_to_file' && /^Created file /m.test(u.out || '')) newN++;
    }
    if (!u.cmd) continue;
    for (const n of skillReads(u.cmd, roots)) if (!skills.some((x) => x.name === n)) skills.push({ name: n, trigger: 'model', detection: 'heuristic' });
    if (u.status !== 'DONE') continue; // RUNNING(백그라운드)·ERROR 는 커밋·푸시 근거가 아니다
    if (C.hasGitSub(u.cmd, 'push')) pushed = true;
    if (!C.hasGitSub(u.cmd, 'commit')) continue;
    const found = [];
    // 결과 본문은 탭 들여쓰기("\t\t\t\tOutput:\n\t\t\t\t[main 622eb09] …", 실측)라 줄 머리 공백을 지우고 찾는다
    for (const mm of String(u.out || '').replace(/^[ \t]+/gm, '').matchAll(C.COMMIT_LINE_RE)) {
      found.push([mm[1], 'stdout']);
      const b = /^\[([^\]\s]+)/.exec(mm[0]);
      if (b) branch = b[1];
    }
    if (!found.length && u.endTs) for (const c of C.pickOwnCommit(C.gitCommitsBetween(root, Date.parse(u.ts), Date.parse(u.endTs)), u.cmd)) found.push([c.sha, c.source]);
    for (const [sha, source] of found) {
      if (shaSeen.has(sha)) continue;
      shaSeen.add(sha);
      commits.push({ sha, source, ts: u.endTs || u.ts });
    }
  }
  let seq = runs.slice(0, C.SEQ_MAX_RUNS).map(([t, n]) => t + n).join('>');
  if (runs.length > C.SEQ_MAX_RUNS) seq += `>…+${runs.length - C.SEQ_MAX_RUNS}`;

  const nextIsPlain = next && next.prompt != null && !/^\s*\/[A-Za-z]/.test(next.prompt);
  let outcome = 'unknown';
  if (commits.length) outcome = 'committed';
  else if (skills.length && nextIsPlain) outcome = 'corrected';
  else if (results && fail / results >= C.FAIL_RATIO) outcome = 'failed';

  const tsStart = turn.steps[0].created_at || null;
  const dur = Date.parse(tsEnd) - Date.parse(tsStart);
  const summary = {
    v: P.SCHEMA_VERSION, kind: 'turn_summary', runtime: RUNTIME, session, turn: turn.id, turn_src: 'native', prompt_kind: 'user',
    ts_start: tsStart, ts_end: tsEnd, dur_ms: Number.isFinite(dur) ? dur : null,
    model: null, effort: null, permission_mode: null,
    tokens: { in: null, out: null, cache_r: null, cache_w: null },
    tools: { seq_compact: seq, counts, fail, interrupt: 0, rejected: 0 },
    exec_kinds: execKinds,
    files: { edited: [...edited].slice(0, C.EDITED_MAX), edited_n: edited.size, read_n: readN, new_n: newN },
    skills, subagents: [],
    git: { branch, commits: commits.map((c) => c.sha), pushed },
    outcome,
  };
  const commitEvents = commits.map((c) => ({
    v: P.SCHEMA_VERSION, ts: c.ts, runtime: RUNTIME, session, turn: turn.id, turn_src: 'native',
    kind: 'commit', commit: { sha: c.sha, branch, source: c.source },
  }));
  return { summary, commits: commitEvents };
}

// 마지막 턴은 transcript 가 IDLE_FINAL_MS 넘게 갱신이 없을 때만(=닫힌 기록) 확정한다(final) — 진행 중 세션을 백필하면
// 마지막 사람 턴을 보류한다(Claude·Codex 확정 규칙과 같다). 미완 턴을 확정하면 upsert-skip 때문에 완성본이 영영 못 들어간다.
// 증분 offset 은 쓰지 않는다 — 체크포인트 뒤 파일 앞쪽이 다시 써지므로 바이트 오프셋이 의미가 없다.
// 중복은 digest.run 의 (runtime, session, turn) upsert-skip 이 막는다.
function parseSteps(steps, root, session, final = true) {
  const turns = segment(steps);
  const out = [];
  for (let i = 0; i < (final ? turns.length : turns.length - 1); i++) {
    const s = summarize(turns[i], turns[i + 1] || null, session, root);
    if (s) out.push(s);
  }
  return out;
}

// 세션 id = brain 디렉터리 이름(<uuid>)
const sessionOf = (file) => path.basename(path.resolve(file, '..', '..', '..'));

function digestFile(root, file, now = Date.now()) {
  const { steps, ok } = readSteps(file);
  if (!ok) return null;
  const session = sessionOf(file);
  const D = require('../../_lib/digest');
  let size = 0; let mtime = 0;
  try { const st = fs.statSync(file); size = st.size; mtime = st.mtimeMs; } catch (_) { /* 무시 */ }
  const final = now - mtime > C.IDLE_FINAL_MS;
  return D.run(root, RUNTIME, session, file, (t, off, fin, r) => ({ turns: parseSteps(steps, r, session, fin), offset: size }), { final });
}

module.exports = { RUNTIME, catOf, readSteps, cwdOf, segment, summarize, parseSteps, sessionOf, digestFile };
