// 호환 reader — 레포 기록(.tracer v1 이벤트 + 구 .claude/skill-trace.jsonl(.1) v0)을 읽어
// 집계기(observe-report.js aggregate)가 소비하는 v0 모양 레코드 하나의 스트림으로 정규화한다.
//
// 계약:
//   · v1 → v0 모양 역변환(normalizeV1)은 writer.toV1 의 짝이다 — 같은 v0 레코드를 구 경로에서
//     읽든 migrate/신 훅으로 .tracer 에서 읽든 집계 결과가 같아야 한다(P1 완료 기준).
//   · 원문은 raw 줄을 raw_ref 로 붙여 복원한다. raw:false(전역 --all)면 원문을 아예 읽지 않고,
//     v0 레코드의 원문 필드도 지운다 — 그때도 집계가 같도록 why 존재·커맨드명은 파생 필드로 남긴다.
//   · 소스 간 순서는 ts 안정 정렬로 맞춘다(구/신 혼합의 분할 지점과 무관하게 같은 순서).
//     deferred-why 로 늦게 append 된 Pre 레코드도 제 시각 자리로 돌아간다.
//   · 다이제스트(digests/ 의 turn_summary·session_summary)는 v0 모양으로 바꾸지 않고 digests 배열로 따로 넘긴다
//     (원문이 없어 raw:false 에서도 그대로). commit·tool_call 이벤트는 이 집계의 입력이 아니라 건너뛴다.
//   · tolerant: 깨진 줄·비객체는 parse_errors 로만 센다. 알 수 없는 kind 는 건너뛴다 — v0 도
//     writer.toV1 이 아는 type(V0_TYPES)만 넘긴다(migrate 가 버리는 레코드를 구 경로에서만 세지 않도록).
const fs = require('fs');
const os = require('os');
const path = require('path');
const P = require('../hooks/_lib/paths');
const { commandOf, V0_TYPES } = require('../hooks/_lib/writer');

function readJsonl(file, onRec) {
  let bad = 0;
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (_) { return 0; }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const v = JSON.parse(line);
      // 유효 JSON 이어도 객체가 아니면(null, 숫자 등) 레코드가 아니다
      if (v && typeof v === 'object' && !Array.isArray(v)) onRec(v);
      else bad++;
    } catch (_) { bad++; }
  }
  return bad;
}

// dir 아래 *.jsonl 전부 (경로 정렬 — 결정론)
function walkJsonl(dir) {
  const out = [];
  const rec = (d) => {
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (_) { return; }
    for (const e of ents) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) rec(p);
      else if (e.isFile() && e.name.endsWith('.jsonl')) out.push(p);
    }
  };
  rec(dir);
  return out.sort();
}

// ts 안정 정렬 ({r, i} 목록) — 파싱 불가 ts 는 맨 앞(-∞), 동률은 읽은 순서(i)
function sortByTs(keyed) {
  const key = (r) => { const t = Date.parse(r.ts); return Number.isFinite(t) ? t : -Infinity; };
  return keyed.sort((a, b) => (key(a.r) - key(b.r)) || (a.i - b.i)).map((x) => x.r);
}

const untildify = (p) =>
  typeof p === 'string' && (p === '~' || p.startsWith('~/')) ? path.join(os.homedir(), p.slice(1)) : p;

// v1 이벤트 → v0 모양 레코드 (writer.toV1 의 역). raw = 이 이벤트의 raw 줄(없으면 null).
function normalizeV1(ev, raw) {
  const R = raw || {};
  const ext = (ev.ext && ev.runtime && ev.ext[ev.runtime]) || {};
  const base = { ts: ev.ts, session_id: ev.session ?? null, prompt_id: ev.turn ?? null, runtime: ev.runtime || null };
  switch (ev.kind) {
    case 'prompt': {
      const m = ev.prompt_meta || {};
      return { ...base, type: 'prompt', text: R.text ?? '', is_command: m.is_command === true, command: m.command ?? null };
    }
    case 'skill_use': {
      const s = ev.skill || {};
      return {
        ...base, type: 'skill', skill: s.name ?? null, trigger: s.trigger ?? null, detection: s.detection ?? null, turn_command: s.turn_command ?? null,
        why: R.why ?? null, why_ref: ev.why_ref ?? null, why_source: ev.why_source ?? null, args: R.args ?? '',
        tool_use_id: ext.tool_use_id ?? null, agent_id: ext.agent_id ?? null, agent_type: ext.agent_type ?? null,
      };
    }
    case 'subagent': {
      const a = ev.subagent || {};
      return {
        ...base, type: 'agent', agent: a.type ?? null, model: a.model ?? null,
        description: R.description ?? null, prompt_head: R.prompt_head ?? null,
        why: R.why ?? null, why_ref: ev.why_ref ?? null, why_source: ev.why_source ?? null,
        tool_use_id: ext.tool_use_id ?? null, parent_agent_id: ext.parent_agent_id ?? null, parent_agent_type: ext.parent_agent_type ?? null,
      };
    }
    case 'tool_result':
      return { ...base, type: 'result', tool: ev.tool ?? null, target: ev.target ?? null, tool_use_id: ext.tool_use_id ?? null, response_bytes: ev.response_bytes ?? null };
    case 'session_start':
      return { ...base, type: 'session_start', source: ev.source ?? null, plugin_root: untildify(ev.plugin_root ?? null) };
    case 'session_end':
      return { ...base, type: 'session_end', reason: ev.reason ?? null };
    default:
      return null;
  }
}

// raw:false 용 v0 원문 제거 — 집계에 필요한 신호(커맨드 판정·커맨드명·why 존재)만 파생 필드로 남긴다.
function stripV0(r) {
  const o = { ...r };
  if (o.type === 'prompt') {
    Object.assign(o, commandOf(o.text, o.is_command));
    o.text = '';
  }
  if (o.why) o.why_ref = 'v0';
  for (const k of ['why', 'args', 'description', 'prompt_head']) delete o[k];
  return o;
}

// 다이제스트 읽기 — turn_summary / session_summary 만, ts_start 안정 정렬
function loadDigests(root, out) {
  const keyed = [];
  for (const f of walkJsonl(P.digestsDir(root))) {
    out.files.push(f);
    out.parseErrors += readJsonl(f, (d) => {
      if (d.kind === 'turn_summary' || d.kind === 'session_summary') keyed.push({ r: { ...d, ts: d.ts_start }, i: keyed.length });
    });
  }
  return sortByTs(keyed);
}

// 레포 하나 읽기 → { records(ts 정렬, v0 모양), digests, parseErrors, files, schema:{v0,v1} }
//   opts.raw     — 원문 복원 여부 (기본 true)
//   opts.legacy  — 구 경로 파일 목록 지정(기본 <root>/.claude/skill-trace.jsonl(.1)), [] 이면 구 경로 생략
//   opts.tracer  — false 면 .tracer 를 읽지 않는다 (--trace 단일 파일 모드)
function loadRepo(root, opts = {}) {
  const raw = opts.raw !== false;
  const out = { records: [], digests: [], parseErrors: 0, files: [], schema: { v0: 0, v1: 0 } };
  const keyed = [];
  const push = (r) => keyed.push({ r, i: keyed.length });

  const legacyBase = P.legacyTrace(root);
  const legacy = opts.legacy || [legacyBase + '.1', legacyBase];
  for (const f of legacy) {
    if (!fs.existsSync(f)) continue;
    out.files.push(f);
    out.parseErrors += readJsonl(f, (r) => {
      if (!V0_TYPES.has(r.type)) return;
      out.schema.v0++;
      push(raw ? r : stripV0(r));
    });
  }

  if (opts.tracer !== false) {
    const rawMap = new Map();
    if (raw) {
      for (const f of walkJsonl(P.rawDir(root))) {
        const rel = path.relative(P.tracerDir(root), f).split(path.sep).join('/');
        readJsonl(f, (x) => { if (x.id) rawMap.set(`${rel}#${x.id}`, x); });
      }
    }
    for (const f of walkJsonl(P.eventsDir(root))) {
      out.files.push(f);
      out.parseErrors += readJsonl(f, (ev) => {
        const r = normalizeV1(ev, raw && ev.raw_ref ? rawMap.get(ev.raw_ref) : null);
        if (!r) return; // 미래 kind(tool_call/turn_summary 등) — 이 집계의 입력이 아니다
        out.schema.v1++;
        push(r);
      });
    }
    out.digests = loadDigests(root, out);
  }

  out.records = sortByTs(keyed);
  return out;
}

// 전역 레포 목록(~/.tracer/index/repos.d/* 마커, 내용=루트 경로) — 없으면 []. 경로 정렬·중복 제거.
function listRepos() {
  const dir = P.reposDir();
  let names;
  try { names = fs.readdirSync(dir); } catch (_) { return []; }
  const out = new Set();
  for (const n of names) {
    if (n.endsWith('.tmp')) continue;
    try {
      const r = fs.readFileSync(path.join(dir, n), 'utf8').trim();
      if (r) out.add(r);
    } catch (_) { /* 깨진 마커 — 건너뜀 */ }
  }
  return [...out].sort();
}

// 전역 합산 — 등록된 레포 전부를 원문 없이(raw:false) 읽어 하나로 합친다. 사라진 레포는 건너뛴다.
function loadAll() {
  const out = { records: [], digests: [], parseErrors: 0, files: [], schema: { v0: 0, v1: 0 }, repos: [] };
  const keyed = [];
  const dkeyed = [];
  for (const root of listRepos()) {
    // 홈은 레포가 아니다(<홈>/.tracer = 전역 층) — 수동 등록돼 있어도 합산하지 않는다
    if (!fs.existsSync(root) || P.isHome(root)) continue;
    const one = loadRepo(root, { raw: false });
    out.repos.push(root);
    out.parseErrors += one.parseErrors;
    out.files.push(...one.files);
    out.schema.v0 += one.schema.v0;
    out.schema.v1 += one.schema.v1;
    for (const r of one.records) keyed.push({ r, i: keyed.length });
    for (const d of one.digests) dkeyed.push({ r: d, i: dkeyed.length });
  }
  out.records = sortByTs(keyed);
  out.digests = sortByTs(dkeyed);
  return out;
}

module.exports = { loadRepo, loadAll, listRepos, normalizeV1, stripV0, walkJsonl, readJsonl };
