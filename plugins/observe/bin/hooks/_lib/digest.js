// 작업 방식 다이제스트 저장 계층 — 런타임 중립 (커서·락·upsert-skip·기록). transcript 해석은 어댑터 몫
// (Claude: adapters/claude/transcript.js 의 parseTurns). 이 파일의 run() 하나가 turn_summary·commit 이벤트·
// session_summary 의 유일한 생산 경로다 — Stop 훅(동기)·SessionEnd worker·SessionStart 따라잡기가 같은 함수를 부른다.
//
// 저장 규약:
//   · cursors/<runtime>/<session>.json — { offset, transcript(~ 접힘), final, turns, updated, src_size(.zst 만) }
//     offset = "아직 확정 안 된 첫 턴"의 시작 바이트(또는 전부 확정이면 마지막 완결 라인 끝).
//     .zst transcript(Codex) 의 offset 은 해제본 바이트라 압축 파일 크기와 비교할 수 없다 — 그래서 처리 시점의 압축 파일
//     크기(src_size)를 따로 두고 "자랐는가"를 그것으로 판정한다(grownSince).
//     다음 실행은 그 바이트부터만 읽는다(증분). 파일이 줄었으면(교체·절단) 0 부터 다시 — upsert-skip 이 중복을 막는다.
//   · digests/<YYYY-MM>/<session>.jsonl — turn_summary / session_summary. 키 (runtime, session, turn) 가
//     이미 있으면 다시 쓰지 않는다(upsert-skip). 세션의 다이제스트는 첫 기록 월 파일 하나에 모은다.
//   · events/<runtime>/<YYYY-MM>/<session>.jsonl 의 kind:"commit" — 그 턴의 turn_summary 와 같은 실행에서만 쓴다
//     (턴 upsert-skip 이 커밋 이벤트 중복도 막는다).
//   · 동시 실행(Stop 과 SessionEnd worker 가 겹침 등)은 세션별 락 파일(O_EXCL)로 직렬화 — 락을 못 잡으면 이번 실행은
//     건너뛴다(다음 실행이 커서부터 처리). 단 마감(final)은 detached worker 라 잠깐(100ms×30) 기다린다 — 마감을 놓치면
//     마지막 턴이 다음 SessionStart 따라잡기(30분 유휴)까지 밀리거나, 그 레포에 새 세션이 없으면 영영 안 쓰인다.
//     30초 넘은 락은 죽은 프로세스의 잔재로 보고 회수한다.
//   · 마감(final)은 영구 상태가 아니다 — 같은 session id 로 resume 되면 transcript 가 커서 뒤로 자라고, 그 뒤 Stop·마감·
//     따라잡기가 다시 처리한다(resume 뒤 Esc 취소 턴은 Stop 이 안 불려 마감 경로로만 잡힌다). 마감 조기 반환/건너뛰기는
//     "이미 마감 + transcript 가 커서 이후로 자라지 않음"(grownSince=false)일 때만.
//   · session_summary 는 마감 때마다, 마지막 요약의 turns 와 지금 턴 수가 다를 때만 새로 append — 세션별 정본은
//     파일의 마지막 session_summary 다(resume 으로 턴이 늘면 새 요약이 뒤에 붙는다).
// 원문은 다루지 않는다 — 어댑터가 넘기는 요약에는 이름·개수·상대경로·SHA 만 있다. stdout 무출력.
const fs = require('fs');
const os = require('os');
const path = require('path');
const P = require('./paths');
const { appendV1, ensureSkeleton, tildify } = require('./writer');

const LOCK_STALE_MS = 30000;
const FINAL_LOCK_TRIES = 30; // 마감 worker 의 락 대기 — 100ms × 30
const FINAL_LOCK_WAIT_MS = 100;

const untildify = (p) =>
  typeof p === 'string' && (p === '~' || p.startsWith('~/')) ? path.join(os.homedir(), p.slice(1)) : p;

function readCursor(root, runtime, session) {
  try { return JSON.parse(fs.readFileSync(P.cursorFile(root, runtime, session), 'utf8')); } catch (_) { return null; }
}
// 커서는 tmp + rename 으로 갱신 — 부분 쓰기 커서가 남지 않게
function writeCursor(root, runtime, session, cur) {
  ensureSkeleton(root); // .gitignore("*") 가 커서보다 먼저 — 다이제스트 없이 커서만 생겨도 git 에 안 보이게
  const f = P.cursorFile(root, runtime, session);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(cur) + '\n');
  fs.renameSync(tmp, f);
}
// 커서가 없을 때만 만든다(offset 0) — SessionStart 가 "관측 중인 세션" 목록을 남기는 용도(따라잡기 입력)
function ensureCursor(root, runtime, session, transcript) {
  if (readCursor(root, runtime, session)) return;
  writeCursor(root, runtime, session, { v: 1, runtime, session, transcript: tildify(transcript), offset: 0, final: false, turns: 0, updated: new Date().toISOString() });
}
function listCursors(root, runtime) {
  let names;
  try { names = fs.readdirSync(P.cursorsDir(root, runtime)); } catch (_) { return []; }
  return names.filter((n) => n.endsWith('.json')).map((n) => {
    try { return JSON.parse(fs.readFileSync(path.join(P.cursorsDir(root, runtime), n), 'utf8')); } catch (_) { return null; }
  }).filter((c) => c && c.session);
}

// 이미 마감된 커서 이후로 transcript 가 자랐는가(resume). transcript 를 못 읽으면 false — 처리할 게 없다.
// .zst 는 다시 압축된 파일이라 크기가 단조 증가하지 않는다 — 마지막 처리 때 크기(src_size)와 다르면 자란 것으로 본다
// (src_size 가 없는 커서 = 아직 이 파일을 처리한 적 없음 → 자람. 다시 읽어도 upsert-skip 이라 중복 0).
const isZst = (t) => /\.zst$/.test(String(t));
function grownSince(cur, transcript) {
  try {
    const size = fs.statSync(transcript).size;
    return isZst(transcript) ? size !== cur.src_size : size > (cur.offset || 0);
  } catch (_) { return false; }
}

const sleepSync = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function lock(root, runtime, session) {
  ensureSkeleton(root);
  const f = P.cursorFile(root, runtime, session).replace(/\.json$/, '.lock');
  fs.mkdirSync(path.dirname(f), { recursive: true });
  for (let i = 0; i < 2; i++) {
    try { fs.closeSync(fs.openSync(f, 'wx')); return () => { try { fs.unlinkSync(f); } catch (_) { /* 무시 */ } }; } catch (_) {
      try { if (Date.now() - fs.statSync(f).mtimeMs > LOCK_STALE_MS) { fs.unlinkSync(f); continue; } } catch (_) { continue; }
      return null; // 다른 실행이 처리 중
    }
  }
  return null;
}

// 세션의 기존 다이제스트 — { file(첫 기록 월 파일 | null), turns:Set(키), summaryTurns(마지막 session_summary 의
//   turns | null), list:[turn_summary] }
function existingDigests(root, runtime, session) {
  const out = { file: null, turns: new Set(), summaryTurns: null, list: [] };
  let months;
  try { months = fs.readdirSync(P.digestsDir(root)).sort(); } catch (_) { return out; }
  for (const m of months) {
    const f = P.digestFile(root, m, session);
    let text;
    try { text = fs.readFileSync(f, 'utf8'); } catch (_) { continue; }
    if (!out.file) out.file = f;
    for (const line of text.split('\n')) {
      if (!line) continue;
      let r;
      try { r = JSON.parse(line); } catch (_) { continue; }
      if (r.runtime !== runtime || r.session !== session) continue;
      if (r.kind === 'turn_summary') { out.turns.add(r.turn); out.list.push(r); }
      else if (r.kind === 'session_summary') out.summaryTurns = r.turns;
    }
  }
  return out;
}

const addCounts = (acc, obj) => {
  for (const [k, v] of Object.entries(obj || {})) if (Number.isFinite(v)) acc[k] = (acc[k] || 0) + v;
  return acc;
};

// 세션 요약 — 그 세션의 turn_summary 들을 합산한다(원문 없음). outcomes 는 사람 턴만(prompt_kind 가 user 가 아닌
// 시스템 주입 턴은 system_turns 로만 센다 — 리포트 턴 결과 분모와 같은 기준), 나머지는 모든 턴 합.
function sessionSummary(runtime, session, list) {
  const outcomes = {};
  const skills = {};
  const commits = [];
  const tokens = {};
  const counts = {};
  const execKinds = {};
  let fail = 0; let interrupt = 0; let rejected = 0; let subagents = 0; let system = 0;
  let first = null; let last = null;
  const models = new Set();
  for (const t of list) {
    if (t.prompt_kind && t.prompt_kind !== 'user') system++;
    else outcomes[t.outcome] = (outcomes[t.outcome] || 0) + 1;
    for (const s of t.skills || []) skills[s.name] = (skills[s.name] || 0) + 1;
    for (const c of (t.git && t.git.commits) || []) if (!commits.includes(c)) commits.push(c);
    addCounts(tokens, t.tokens);
    addCounts(counts, t.tools && t.tools.counts);
    addCounts(execKinds, t.exec_kinds);
    fail += (t.tools && t.tools.fail) || 0;
    interrupt += (t.tools && t.tools.interrupt) || 0;
    rejected += (t.tools && t.tools.rejected) || 0;
    subagents += (t.subagents || []).length;
    if (t.model) models.add(t.model);
    if (t.ts_start && (!first || t.ts_start < first)) first = t.ts_start;
    if (t.ts_end && (!last || t.ts_end > last)) last = t.ts_end;
  }
  const d = Date.parse(last) - Date.parse(first);
  return {
    v: P.SCHEMA_VERSION, kind: 'session_summary', runtime, session,
    ts_start: first, ts_end: last, dur_ms: Number.isFinite(d) ? d : null,
    turns: list.length, system_turns: system, outcomes, tokens,
    tools: { counts, fail, interrupt, rejected }, exec_kinds: execKinds,
    skills, subagents_n: subagents, commits, models: [...models].sort(),
  };
}

// 한 세션 증분 처리. parse(transcript, offset, final) → { turns:[{summary, commits:[event]}], offset, size }
//   summary 는 turn_summary 레코드(필수 키 runtime/session/turn 포함), commits 는 kind:"commit" 이벤트.
//   opts.final — 마지막(진행 중일 수 있는) 턴까지 확정 + session_summary 기록 (SessionEnd·유휴 세션 따라잡기)
// 반환: { written(새 turn_summary 수), skipped(upsert-skip 수), locked(true=다른 실행이 처리 중) }
function run(root, runtime, session, transcript, parse, opts = {}) {
  const res = { written: 0, skipped: 0, locked: false };
  if (P.isHome(root) || !session || !transcript) return res;
  let release = lock(root, runtime, session);
  for (let i = 0; !release && opts.final && i < FINAL_LOCK_TRIES; i++) {
    sleepSync(FINAL_LOCK_WAIT_MS);
    release = lock(root, runtime, session);
  }
  if (!release) { res.locked = true; return res; }
  try {
    const cur = readCursor(root, runtime, session) || { v: 1, runtime, session, offset: 0, final: false, turns: 0 };
    if (cur.final && opts.final && !grownSince(cur, transcript)) return res; // 이미 마감 + resume 없음
    let srcSize = null; // .zst 만 — 파싱 전 크기(파싱 중 자라면 다음 실행이 한 번 더 읽는다: upsert-skip)
    if (isZst(transcript)) try { srcSize = fs.statSync(transcript).size; } catch (_) { /* 무시 */ }
    const parsed = parse(transcript, cur.offset || 0, !!opts.final, root);
    const ex = existingDigests(root, runtime, session);
    for (const t of parsed.turns) {
      if (ex.turns.has(t.summary.turn)) { res.skipped++; continue; }
      const file = ex.file || P.digestFile(root, P.month(t.summary.ts_start), session);
      ex.file = file;
      for (const c of t.commits) appendV1(root, P.eventsFile(root, runtime, session, c.ts), c);
      appendV1(root, file, t.summary);
      ex.turns.add(t.summary.turn);
      ex.list.push(t.summary);
      res.written++;
    }
    if (opts.final && ex.list.length && ex.summaryTurns !== ex.list.length) {
      appendV1(root, ex.file, sessionSummary(runtime, session, ex.list));
    }
    writeCursor(root, runtime, session, {
      v: 1, runtime, session, transcript: tildify(transcript), offset: parsed.offset,
      // 비마감 실행이 새로 읽은 게 없으면 마감 상태 유지(따라잡기가 닫힌 세션을 다시 열지 않게)
      final: !!opts.final || (!!cur.final && parsed.offset <= (cur.offset || 0)), turns: (cur.turns || 0) + res.written, updated: new Date().toISOString(),
      ...(srcSize != null ? { src_size: srcSize } : {}),
    });
  } finally {
    release();
  }
  return res;
}

module.exports = { run, readCursor, ensureCursor, listCursors, existingDigests, sessionSummary, grownSince, untildify };
