#!/usr/bin/env node
// observe-backfill.js — 다른 런타임의 세션 기록을 이 레포 .tracer 다이제스트로 백필한다 (의존성 없음, 결정 4).
//
// 사용: node observe-backfill.js [--root <레포>] [--runtime claude|codex|antigravity|all] [--claude-dir <dir>]…
//                                [--codex-dir <dir>]… [--antigravity-dir <dir>] [--dry-run] [--json]
//   --root             기본은 리포트와 같은 탐지(paths.findRoot)
//   --runtime          기본 all
//   --claude-dir       이 레포의 Claude Code 프로젝트 디렉터리(반복 가능). 기본 ~/.claude/projects/<인코딩된 루트>
//                      (루트·실경로 각각). 직접 지정하면 그 디렉터리를 이 레포 것으로 보고 cwd 대조를 생략한다(레포 사본 검증용)
//   --codex-dir        Codex rollout 디렉터리(반복 가능). 기본 ~/.codex/sessions, ~/.codex/archived_sessions
//   --antigravity-dir  Antigravity CLI brain 디렉터리. 기본 ~/.gemini/antigravity-cli/brain
//   --dry-run          이 레포 세션 수만 세고 아무것도 쓰지 않는다
//
// 하는 일: 각 세션 기록의 작업 디렉터리(Codex session_meta.cwd / Antigravity run_command Cwd 최빈값)를 git toplevel 로
// 올려 이 레포 루트와 같은 세션만 골라, 훅 경로와 같은 digest.run 으로 turn_summary·commit 이벤트·session_summary 를 만든다.
// Claude Code 는 훅이 기록하기 전(또는 훅 없이) 쌓인 과거 transcript 용 — 이 레포에 대응하는 프로젝트 디렉터리의 최상위
// <session>.jsonl 만(하위 subagents/ 는 사이드체인이라 제외), Stop 훅·따라잡기와 같은 transcript.digestSession 으로 처리한다
// (새 파서 없음). 프로젝트 디렉터리 이름은 경로의 영숫자 아닌 문자를 '-' 로 바꾼 것(실측)이라 다른 경로와 겹칠 수 있어,
// 기본 탐색에서는 transcript 의 cwd 를 git toplevel 로 올려 한 번 더 대조한다.
// 마감 모드(마지막 턴 확정 + session_summary)는 기록 파일이 IDLE_FINAL_MS(30분) 넘게 갱신이 없을 때만 — 진행 중 세션은
// 확정된 턴만 쓰고 마지막 사람 턴을 보류한다(SessionStart 따라잡기와 같은 규칙). 미완 턴을 확정해 버리면 upsert-skip 때문에
// 완성된 요약(커밋 SHA·committed)이 다시는 못 들어간다. 키가 (runtime, session, turn) upsert-skip 이라 여러 번 돌려도,
// Codex 훅(Stop)이 이미 쓴 턴이 있어도 중복이 없다. 같은 Codex 세션의 평문 .jsonl 과 .jsonl.zst 는 평문 하나만 읽는다(.zst 만 있으면 zstd CLI 로 해제,
// zstd 가 없으면 그 세션은 건너뛰고 skipped.zstd 로 보고 — zstd 가 있는데 해제가 실패한 손상 .zst 는 skipped.format).
// 형식을 모르는 파일·하위 에이전트 스레드·Codex Desktop 의 외부 세션 import(Claude Code 등에서 한 작업의 사본이라 Codex 턴으로
// 세면 이중 집계 — 위 Claude 백필이 원본을 센다)는 건너뛴다(skipped.imported, 세션마다 사유를 stderr 한 줄로). import 판별
// 실측(2026-10-26, rollout 119개 중 import 27개 · 평문/.zst 같음): session_meta 에는 구별 신호가 없다 — originator "Codex Desktop"·
// source "vscode" 가 네이티브 Desktop 세션 6개와 같고 키 집합도 겹친다. 그래서 내용 신호 두 개를 쓴다:
//   ① turn_id — task_started 가 전부 "external-import-turn-N" (27/27)
//   ② 마커   — import 블록 끝 agent_message "<EXTERNAL SESSION IMPORTED>"(평문 event_msg agent_message / .zst item_completed
//              AgentMessage, 세션당 1개·마지막 import 턴 안 27/27) 뒤에 시작한 턴이 없음 — turn_id 형식이 바뀌어도 잡는다.
//   (보조 관찰: import 턴은 turn_context 가 0/153, 툴은 "[external_agent_tool_call: …]" 텍스트뿐 — 판별에는 안 쓴다.)
// 섞인 세션(import 뒤 Codex 에서 이어 간 세션 — 실측 0개)은 건너뛰지 않고 rollout.segment 가 import 턴(turn_id)만 버린다.
// 원문은 쓰지 않는다(다이제스트에는 이름·개수·상대경로·SHA 만). 홈 디렉터리는 루트로 받지 않는다.
// 사용자가 명시 실행하는 CLI 다 — OBSERVE_TRACE 게이트 없이 결과를 stdout 으로 보고한다(migrate 와 같은 규약).
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const P = require("./hooks/_lib/paths");
const codex = require("./hooks/adapters/codex/rollout");
const ag = require("./hooks/adapters/antigravity/transcript");
const claude = require("./hooks/adapters/claude/transcript");
const { IDLE_FINAL_MS } = claude;

function parseArgs(argv) {
  const o = { root: null, runtime: "all", claudeDirs: [], codexDirs: [], agDir: null, dry: false, json: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--root") o.root = argv[++i];
    else if (a === "--runtime") o.runtime = argv[++i];
    else if (a === "--claude-dir") o.claudeDirs.push(argv[++i]);
    else if (a === "--codex-dir") o.codexDirs.push(argv[++i]);
    else if (a === "--antigravity-dir") o.agDir = argv[++i];
    else if (a === "--dry-run") o.dry = true;
    else if (a === "--json") o.json = true;
  }
  return o;
}

function walk(dir, test) {
  const out = [];
  const rec = (d) => {
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (_) { return; }
    for (const e of ents) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) rec(p);
      else if (e.isFile() && test(p)) out.push(p);
    }
  };
  rec(dir);
  return out.sort();
}

// 작업 디렉터리 → 레포 루트 (git toplevel, 없으면·사라진 디렉터리면 그대로). 같은 디렉터리는 한 번만 묻는다.
// paths.repoRoot 는 쓰지 않는다 — CLAUDE_PROJECT_DIR 이 설정된 환경에서 실행하면 모든 세션이 그 루트로 잡힌다.
const rootCache = new Map();
function rootOf(dir) {
  if (!dir) return null;
  if (!rootCache.has(dir)) rootCache.set(dir, P.real((fs.existsSync(dir) && P.gitTop(dir)) || dir));
  return rootCache.get(dir);
}

// zstd CLI 존재 — 해제 실패를 "zstd 없음"과 "손상 파일"로 가르는 데만 쓴다(첫 실패 때 한 번 확인)
let zstdOk = null;
const hasZstd = () => {
  if (zstdOk == null) zstdOk = require("child_process").spawnSync("zstd", ["--version"], { stdio: "ignore" }).status === 0;
  return zstdOk;
};

// import 전용 세션의 판별 신호 — "turn_id" | "marker" | null (헤더의 ① ② — ① 우선)
const IMPORT_MARKER = "<EXTERNAL SESSION IMPORTED>";
function isImportMarker(rec) {
  const p = rec.payload || {};
  if (rec.type !== "event_msg") return false;
  if (p.type === "agent_message") return p.message === IMPORT_MARKER;
  const it = p.type === "item_completed" ? p.item || {} : null; // .zst 형식
  return !!it && it.type === "AgentMessage" && (it.content || []).some((b) => b && b.text === IMPORT_MARKER);
}
function importSignal(buf) {
  let starts = 0; let native = 0; let afterMarker = 0; let marker = false;
  for (const { rec } of codex.linesOf(buf, 0).lines) {
    const p = rec.payload || {};
    if (rec.type === "event_msg" && p.type === "task_started") {
      starts++;
      if (!codex.isImported(p.turn_id)) native++;
      if (marker) afterMarker++;
    } else if (isImportMarker(rec)) { marker = true; afterMarker = 0; }
  }
  if (starts && !native) return "turn_id";
  if (marker && !afterMarker) return "marker";
  return null;
}

function backfillCodex(root, dirs, dry) {
  const st = { files: 0, sessions: 0, matched: 0, written: 0, skipped: { format: 0, zstd: 0, subagent: 0, imported: 0, other_repo: 0 } };
  // 세션 uuid → 파일 (평문 우선). rollout-<시각>-<uuid>.jsonl(.zst)
  const bySession = new Map();
  for (const d of dirs) {
    for (const f of walk(d, (p) => /rollout-.*\.jsonl(?:\.zst)?$/.test(path.basename(p)))) {
      st.files++;
      const m = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl(?:\.zst)?$/.exec(path.basename(f));
      const key = m ? m[1] : f;
      const prev = bySession.get(key);
      if (!prev || (/\.zst$/.test(prev) && !/\.zst$/.test(f))) bySession.set(key, f);
    }
  }
  st.sessions = bySession.size;
  for (const f of bySession.values()) {
    const buf = codex.loadBuffer(f);
    if (!buf) { st.skipped[/\.zst$/.test(f) && !hasZstd() ? "zstd" : "format"]++; continue; }
    const meta = codex.metaOf(buf);
    if (!meta) { st.skipped.format++; continue; }
    if (codex.isSubagent(meta)) { st.skipped.subagent++; continue; }
    if (rootOf(meta.cwd) !== P.real(root)) { st.skipped.other_repo++; continue; }
    const imp = importSignal(buf);
    if (imp) {
      st.skipped.imported++;
      process.stderr.write(`observe-backfill: codex ${meta.id} 건너뜀 — Codex Desktop 외부 세션 import(${imp}), 원본 런타임 기록이 센다\n`);
      continue;
    }
    st.matched++;
    if (dry) continue;
    let mtime = 0;
    try { mtime = fs.statSync(f).mtimeMs; } catch (_) { /* 무시 */ }
    const r = codex.digestSession(root, meta.id, f, Date.now() - mtime > IDLE_FINAL_MS);
    if (r) st.written += r.written;
  }
  return st;
}

// Claude Code transcript 의 작업 디렉터리 — 앞쪽 레코드의 첫 "cwd"(실측: 첫 ~4KB 안). 없으면 null
const CWD_SCAN_BYTES = 256 * 1024;
function claudeCwdOf(file) {
  let fd;
  try {
    fd = fs.openSync(file, "r");
    const b = Buffer.alloc(CWD_SCAN_BYTES);
    const n = fs.readSync(fd, b, 0, b.length, 0);
    const m = /"cwd":("(?:[^"\\]|\\.)*")/.exec(b.toString("utf8", 0, n));
    return m ? JSON.parse(m[1]) : null;
  } catch (_) { return null; } finally { if (fd !== undefined) fs.closeSync(fd); }
}
// Claude Code 프로젝트 디렉터리 이름 — 절대경로의 영숫자 아닌 문자를 '-' 로(실측: /Users/a/b.c → -Users-a-b-c)
const claudeProjectName = (p) => p.replace(/[^A-Za-z0-9]/g, "-");

function backfillClaude(root, dirs, verifyCwd, dry) {
  const st = { files: 0, sessions: 0, matched: 0, written: 0, active: 0, skipped: { no_cwd: 0, other_repo: 0 } };
  const now = Date.now();
  const seen = new Set();
  for (const d of dirs) {
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (_) { continue; }
    for (const e of ents.filter((x) => x.isFile() && x.name.endsWith(".jsonl")).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const f = path.join(d, e.name);
      const session = e.name.slice(0, -".jsonl".length);
      st.files++;
      if (seen.has(session)) continue; // 루트·실경로 디렉터리가 같은 세션을 둘 다 가질 때
      seen.add(session);
      st.sessions++;
      if (verifyCwd) {
        const cwd = claudeCwdOf(f);
        if (!cwd) { st.skipped.no_cwd++; continue; }
        if (rootOf(cwd) !== P.real(root)) { st.skipped.other_repo++; continue; }
      }
      st.matched++;
      if (dry) continue;
      let mtime = 0;
      try { mtime = fs.statSync(f).mtimeMs; } catch (_) { /* 무시 */ }
      const final = now - mtime > IDLE_FINAL_MS; // 진행 중(최근 갱신) 세션은 마지막 턴을 보류 — catchup 과 같은 규칙
      if (!final) st.active++;
      const r = claude.digestSession(root, session, f, final);
      if (r) st.written += r.written;
    }
  }
  return st;
}

function backfillAntigravity(root, dir, dry) {
  const st = { files: 0, sessions: 0, matched: 0, written: 0, skipped: { format: 0, no_cwd: 0, other_repo: 0 } };
  let ents;
  try { ents = fs.readdirSync(dir); } catch (_) { ents = []; }
  for (const id of ents.sort()) {
    const f = path.join(dir, id, ".system_generated", "logs", "transcript.jsonl");
    if (!fs.existsSync(f)) continue;
    st.files++;
    st.sessions++;
    const { steps, ok } = ag.readSteps(f);
    if (!ok) { st.skipped.format++; continue; }
    const cwd = ag.cwdOf(steps);
    if (!cwd) { st.skipped.no_cwd++; continue; }
    if (rootOf(cwd) !== P.real(root)) { st.skipped.other_repo++; continue; }
    st.matched++;
    if (dry) continue;
    const r = ag.digestFile(root, f);
    if (r) st.written += r.written;
  }
  return st;
}

function main() {
  const o = parseArgs(process.argv);
  const root = o.root || P.findRoot(process.cwd());
  if (P.isHome(root)) {
    console.error(`observe-backfill: 홈 디렉터리(${root})는 레포 루트로 받지 않음 — ~/.tracer 는 전역 층`);
    process.exit(1);
  }
  if (!["claude", "codex", "antigravity", "all"].includes(o.runtime)) {
    console.error(`observe-backfill: --runtime 은 claude|codex|antigravity|all (받은 값: ${o.runtime})`);
    process.exit(1);
  }
  const home = os.homedir();
  const out = { root, dry_run: o.dry };
  const want = (k) => o.runtime === "all" || o.runtime === k;
  if (want("claude")) {
    const proj = path.join(home, ".claude", "projects");
    const dirs = o.claudeDirs.length ? o.claudeDirs : [...new Set([root, P.real(root)].map((r) => path.join(proj, claudeProjectName(r))))];
    out.claude = backfillClaude(root, dirs, !o.claudeDirs.length, o.dry);
  }
  if (want("codex")) {
    const dirs = o.codexDirs.length ? o.codexDirs : [path.join(home, ".codex", "sessions"), path.join(home, ".codex", "archived_sessions")];
    out.codex = backfillCodex(root, dirs, o.dry);
  }
  if (want("antigravity")) {
    out.antigravity = backfillAntigravity(root, o.agDir || path.join(home, ".gemini", "antigravity-cli", "brain"), o.dry);
  }
  if (o.json) { console.log(JSON.stringify(out, null, 2)); return; }
  console.log(`observe-backfill: ${root}${o.dry ? " (dry-run — 쓰지 않음)" : ""}`);
  for (const k of ["claude", "codex", "antigravity"]) {
    const s = out[k];
    if (!s) continue;
    const sk = Object.entries(s.skipped).filter(([, n]) => n).map(([n, v]) => `${n} ${v}`).join(", ");
    const act = s.active ? ` · 진행 중 ${s.active}(마지막 턴 보류)` : "";
    console.log(`- ${k}: 파일 ${s.files} · 세션 ${s.sessions} · 이 레포 ${s.matched} · 새 turn_summary ${s.written}${act}${sk ? ` · 건너뜀(${sk})` : ""}`);
  }
}

main();
