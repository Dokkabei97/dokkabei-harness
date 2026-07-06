#!/usr/bin/env node
// observe-report.js — skill-trace.jsonl 결정론 집계기 (의존성 없음, /observe-report 의 산출 엔진).
//
// 하는 일: 트레이스(prompt/skill/agent/result/session_* 레코드)를 tolerant reader 로 읽어
//   ① 스킬/에이전트별 호출·user/model 트리거·완주(result join)·소요시간
//   ② 미사용 자산 — 설치 인벤토리(스킬·커맨드·에이전트) 대비 한 번도 호출 안 된 것
//   ③ 미발화 후보 — 스킬/에이전트 무동작으로 끝난 사용자 턴 (LLM judge 의 입력)
//   ④ 세션 경계 요약
//   ⑤ 라이프사이클 — 사용된 자산의 최종 관측 사용 시점 기반 stale/archive 후보
//      (hermes-agent curator 의 30/90일 결정론 전이 이식 — 판정 기준 시각은 --now 로 주입 가능)
//   ⑥ 교정 후보 쌍(followups) — 스킬/에이전트 호출 직후의 평문 사용자 프롬프트
//      (교정 여부 판정은 LLM 몫 — candidates 와 같은 "결정론 수집, 해석 분리" 계약)
// 을 JSON(--json) 또는 한국어 텍스트로 출력한다. LLM 판단(미발화 확정, description 진단)은
// 여기서 하지 않는다 — 결정론 집계와 해석의 경계가 이 파일의 계약이다.
//
// 인벤토리 분모는 "트레이스를 쓴 설치본"에서 열거해야 한다(repo 디렉터리명과 설치
// 네임스페이스의 드리프트 방지). 우선순위: --plugins-dir > 트레이스의 session_start.plugin_root
// 역산 > 이 파일 자신의 위치(plugins/observe/bin → 형제 플러그인) 역산.
// plugin_root 역산은 설치 캐시의 버전 간접 레이아웃(cache/<마켓>/<플러그인>/<버전>/)을
// 인식한다 — 버전 디렉토리면 마켓플레이스 루트(조부모)까지 상향해 전체 설치본을 분모로 삼는다.
const fs = require("fs");
const path = require("path");

// prompt 레코드의 is_command 와 동일한 커맨드 토큰 형태 — 절대경로("/Users/…") 오탐 배제.
// trace-prompt.js 의 정규식과 반드시 동기 유지(구 레코드 폴백 판정에도 쓰인다).
const CMD_TOKEN = /^\s*\/([A-Za-z0-9_:-]+)(\s|$)/;

// ── CLI ──────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const opts = {
    json: false,
    window: 0,
    candidates: 30,
    followups: 30,
    staleDays: 30,
    archiveDays: 90,
    now: null, // 라이프사이클 판정 기준 시각(ISO) — 미지정 시 실행 시각. 테스트 결정론 주입용
    trace: null,
    pluginsDir: null,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--json") opts.json = true;
    else if (a === "--trace") opts.trace = argv[++i];
    else if (a === "--plugins-dir") opts.pluginsDir = argv[++i];
    else if (a === "--window") opts.window = parseInt(argv[++i], 10) || 0;
    else if (a === "--candidates")
      opts.candidates = parseInt(argv[++i], 10) || 0;
    else if (a === "--followups") opts.followups = parseInt(argv[++i], 10) || 0;
    else if (a === "--stale-days")
      opts.staleDays = parseInt(argv[++i], 10) || 0;
    else if (a === "--archive-days")
      opts.archiveDays = parseInt(argv[++i], 10) || 0;
    else if (a === "--now") opts.now = argv[++i];
  }
  return opts;
}

// ── 트레이스 로드 (rotation .1 → 본 파일 순으로 시간순 병합) ─────────────────
function loadTrace(file) {
  const out = { records: [], parseErrors: 0, files: [] };
  for (const f of [file + ".1", file]) {
    if (!fs.existsSync(f)) continue;
    out.files.push(f);
    for (const line of fs.readFileSync(f, "utf8").split("\n")) {
      if (!line.trim()) continue;
      try {
        const v = JSON.parse(line);
        // 유효 JSON 이어도 객체가 아니면(null, 숫자 등) 레코드가 아니다 — tolerant reader
        if (v && typeof v === "object" && !Array.isArray(v))
          out.records.push(v);
        else out.parseErrors++;
      } catch (_) {
        out.parseErrors++;
      }
    }
  }
  return out;
}

// ── 인벤토리 열거 ────────────────────────────────────────────────────────────
// frontmatter name 추출 — YAML 파서 없이 첫 `---` 쌍 안의 name: 한 줄만 읽는다 (CRLF 허용).
function frontmatterName(file) {
  try {
    const text = fs.readFileSync(file, "utf8");
    const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
    if (!m) return null;
    const n = /^name:\s*["']?([^"'\r\n]+?)["']?\s*$/m.exec(m[1]);
    return n ? n[1].trim() : null;
  } catch (_) {
    return null;
  }
}

function listDir(p) {
  try {
    return fs.readdirSync(p);
  } catch (_) {
    return [];
  }
}

// ── 버전 간접 캐시 레이아웃 (cache/<마켓플레이스>/<플러그인>/<버전>/) 지원 ────
const VERSIONISH = /^\d+(\.\d+)*([.+-][0-9A-Za-z.+-]*)?$/; // "1.1.0", "1.0.0-beta.2" 등

const hasPluginJson = (dir) =>
  fs.existsSync(path.join(dir, ".claude-plugin", "plugin.json"));

// semver 유사 비교 — 숫자 세그먼트 좌→우 비교, 전부 동률이면 세그먼트 적은 쪽(정식 릴리스)이 크다
function cmpVersion(a, b) {
  const pa = String(a).split(/[.+-]/);
  const pb = String(b).split(/[.+-]/);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = parseInt(pa[i], 10);
    const y = parseInt(pb[i], 10);
    const nx = Number.isFinite(x) ? x : -1;
    const ny = Number.isFinite(y) ? y : -1;
    if (nx !== ny) return nx - ny;
  }
  return pb.length - pa.length;
}

// <플러그인>/<버전>/.claude-plugin/plugin.json 구조에서 최신 버전 디렉토리 반환 (없으면 null)
function latestVersionRoot(pluginDir) {
  const vers = listDir(pluginDir).filter(
    (v) => VERSIONISH.test(v) && hasPluginJson(path.join(pluginDir, v)),
  );
  if (!vers.length) return null;
  vers.sort(cmpVersion);
  return path.join(pluginDir, vers[vers.length - 1]);
}

// plugin_root → plugins-dir 역산. 설치 캐시에서는 plugin_root 가 버전 디렉토리를
// 가리키므로 단순 dirname 은 플러그인 디렉토리가 되어 그 플러그인 하나만 열거된다
// (분모 붕괴). 버전 디렉토리 판별(부모에 plugin.json 존재 또는 semver형 basename +
// 자기 안에 .claude-plugin) 시 조부모(마켓플레이스 루트)로 상향한다.
// 레포 플랫 레이아웃(plugins/<name>/)은 기존대로 부모를 쓴다. trace 의 plugin_root
// 기록 의미는 불변 — 보정은 전적으로 집계기(reader) 측이다.
function pluginsDirFromRoot(pluginRoot) {
  let dir = path.dirname(pluginRoot);
  const versionDir =
    VERSIONISH.test(path.basename(pluginRoot)) &&
    fs.existsSync(path.join(pluginRoot, ".claude-plugin"));
  if (hasPluginJson(dir) || versionDir) dir = path.dirname(dir);
  return fs.existsSync(dir) ? dir : null;
}

function enumerateInventory(pluginsDir) {
  const inv = { plugins: 0, items: [] }; // items: {id, kind, path}
  if (!pluginsDir || !fs.existsSync(pluginsDir)) return inv;
  for (const dir of listDir(pluginsDir)) {
    let root = path.join(pluginsDir, dir);
    let pjPath = path.join(root, ".claude-plugin", "plugin.json");
    if (!fs.existsSync(pjPath)) {
      // 버전 간접 레이아웃(<플러그인>/<버전>/.claude-plugin) — 최신 버전 하나만 분모로 인정
      const vroot = latestVersionRoot(root);
      if (!vroot) continue; // plugin.json 없는 디렉터리는 플러그인이 아니다 (템플릿 오염 가드)
      root = vroot;
      pjPath = path.join(root, ".claude-plugin", "plugin.json");
    }
    let plugin = dir;
    try {
      const pj = JSON.parse(fs.readFileSync(pjPath, "utf8"));
      if (pj.name) plugin = pj.name;
    } catch (_) {
      /* 깨진 plugin.json — 플러그인은 실재하므로 디렉터리명 폴백으로 계속 열거 */
    }
    inv.plugins++;
    for (const s of listDir(path.join(root, "skills"))) {
      const f = path.join(root, "skills", s, "SKILL.md");
      if (!fs.existsSync(f)) continue;
      inv.items.push({
        id: `${plugin}:${frontmatterName(f) || s}`,
        kind: "skill",
        path: f,
      });
    }
    for (const c of listDir(path.join(root, "commands"))) {
      if (!c.endsWith(".md")) continue;
      const f = path.join(root, "commands", c);
      inv.items.push({
        id: `${plugin}:${frontmatterName(f) || c.replace(/\.md$/, "")}`,
        kind: "command",
        path: f,
      });
    }
    for (const a of listDir(path.join(root, "agents"))) {
      if (!a.endsWith(".md")) continue;
      const f = path.join(root, "agents", a);
      inv.items.push({
        id: `${plugin}:${frontmatterName(f) || a.replace(/\.md$/, "")}`,
        kind: "agent",
        path: f,
      });
    }
  }
  return inv;
}

// ── 집계 ─────────────────────────────────────────────────────────────────────
const tail = (id) => String(id).toLowerCase().split(":").pop();

function aggregate(records, opts) {
  const skills = new Map();
  const agents = new Map();
  const sessions = new Map();
  const preByToolUse = new Map(); // tool_use_id → pre 엔트리 (정밀 join)
  const prePending = new Map(); // `${sid}\0${target}` → pre 엔트리 목록 (tool_use_id 부재 시 근사 join)
  const prompts = { total: 0, commands: 0 };
  const candidates = [];
  const pending = new Map(); // session_id → {ts, session_id, text}
  // 사용 신호 — 네임스페이스가 기록된 이름은 정확 일치만 인정하고(usedFull),
  // 접두어 없는 bare 이름만 tail 일치를 허용한다(usedTail). 동명 자산 오폭 방지.
  const usedFull = new Set();
  const usedTail = new Set();
  // 최종 관측 사용 시각 — usedFull/usedTail 과 같은 이름 규율로 별도 유지 (라이프사이클 입력)
  const lastUsedFull = new Map();
  const lastUsedTail = new Map();
  const laterTs = (a, b) => {
    if (!a) return b;
    if (!b) return a;
    return Date.parse(b) > Date.parse(a) ? b : a;
  };
  const addUsed = (name, ts) => {
    const n = String(name).toLowerCase();
    if (n.includes(":")) {
      usedFull.add(n);
      if (ts) lastUsedFull.set(n, laterTs(lastUsedFull.get(n), ts));
    } else {
      usedTail.add(n);
      if (ts) lastUsedTail.set(n, laterTs(lastUsedTail.get(n), ts));
    }
  };
  // 교정 후보 쌍 — 호출(스킬/에이전트) 직후의 평문 프롬프트. 커맨드 프롬프트는
  // 직접 호출이라 쌍 없이 액션만 소거한다 (신호 순도 우선).
  const followups = [];
  const lastAction = new Map(); // session_id → {kind, target, ts}

  const bump = (map, key) => {
    if (!map.has(key))
      map.set(key, {
        name: key,
        calls: 0,
        user: 0,
        model: 0,
        trigger_null: 0,
        why: 0,
        turn_command: 0,
        completed: 0,
        dur_ms: [],
        last_ts: null,
      });
    const e = map.get(key);
    e.calls++;
    return e;
  };
  const pushPre = (sid, target, entry, r) => {
    const pre = { entry, ts: r.ts, joined: false };
    if (r.tool_use_id) preByToolUse.set(r.tool_use_id, pre);
    const key = sid + " " + target;
    if (!prePending.has(key)) prePending.set(key, []);
    prePending.get(key).push(pre);
  };
  const flushPending = (sid) => {
    const p = pending.get(sid);
    if (p) {
      candidates.push(p);
      pending.delete(sid);
    }
  };

  for (const r of records) {
    if (!r || typeof r !== "object") continue;
    const sid = r.session_id || "(none)";
    if (r.type === "prompt") {
      prompts.total++;
      flushPending(sid); // 다음 사용자 입력 도착 = 직전 턴 종료 → 무동작이었다면 후보 확정
      const isCmd = r.is_command === true || CMD_TOKEN.test(r.text || "");
      const act = lastAction.get(sid);
      if (act) {
        lastAction.delete(sid);
        if (!isCmd)
          followups.push({
            ts: r.ts || null,
            session_id: sid,
            kind: act.kind,
            target: act.target,
            action_ts: act.ts,
            next_prompt: String(r.text || "").slice(0, 200),
          });
      }
      if (isCmd) {
        prompts.commands++; // 커맨드 턴은 미발화 분모에서 제외 (직접 호출)
        // 커맨드 사용 크레딧 — 프롬프트 확장 전용 커맨드(Skill 툴 호출 없음)도 미사용에서 구제
        const wrap = /<command-name>\s*\/?([^<\s]+?)\s*<\/command-name>/.exec(
          r.text || "",
        );
        const tok = CMD_TOKEN.exec(r.text || "");
        const name = (wrap && wrap[1]) || (tok && tok[1]);
        if (name) addUsed(name, r.ts);
      } else {
        pending.set(sid, {
          ts: r.ts || null,
          session_id: sid,
          text: String(r.text || "").slice(0, 200),
        });
      }
    } else if (r.type === "skill") {
      pending.delete(sid);
      const key = r.skill || "(null)";
      const e = bump(skills, key);
      if (r.trigger === "user") e.user++;
      else if (r.trigger === "model") e.model++;
      else e.trigger_null++;
      if (r.why) e.why++;
      if (r.turn_command) e.turn_command++;
      e.last_ts = r.ts || e.last_ts;
      if (r.skill) addUsed(r.skill, r.ts);
      if (r.turn_command) addUsed(r.turn_command, r.ts);
      lastAction.set(sid, { kind: "skill", target: key, ts: r.ts || null });
      pushPre(sid, key, e, r);
    } else if (r.type === "agent") {
      pending.delete(sid);
      const key = r.agent || "(default)";
      const e = bump(agents, key);
      if (r.why) e.why++;
      e.last_ts = r.ts || e.last_ts;
      if (r.agent) addUsed(r.agent, r.ts);
      lastAction.set(sid, { kind: "agent", target: key, ts: r.ts || null });
      pushPre(sid, key, e, r);
    } else if (r.type === "result") {
      // 정밀 join(tool_use_id) 우선, 부재 시 같은 세션·같은 target 의 최근 미조인 pre 로 근사 join
      let pre = r.tool_use_id ? preByToolUse.get(r.tool_use_id) : null;
      if (!pre) {
        const fallbackKey =
          sid +
          " " +
          (r.target || (r.tool === "Skill" ? "(null)" : "(default)"));
        const list = prePending.get(fallbackKey) || [];
        for (let k = list.length - 1; k >= 0; k--)
          if (!list[k].joined) {
            pre = list[k];
            break;
          }
      }
      if (pre && !pre.joined) {
        pre.joined = true;
        pre.entry.completed++;
        const d = Date.parse(r.ts) - Date.parse(pre.ts);
        if (Number.isFinite(d) && d >= 0) pre.entry.dur_ms.push(d);
      }
    } else if (r.type === "session_start") {
      if (!sessions.has(sid)) sessions.set(sid, {});
      sessions.get(sid).start = r.ts;
      sessions.get(sid).plugin_root = r.plugin_root || null;
    } else if (r.type === "session_end") {
      if (!sessions.has(sid)) sessions.set(sid, {});
      sessions.get(sid).end = r.ts;
      sessions.get(sid).reason = r.reason || null;
      flushPending(sid); // 세션이 닫혔으므로 마지막 무동작 턴도 확정
      lastAction.delete(sid); // 후속 프롬프트 없이 닫힘 — 교정 쌍 미성립
    }
    if (r.session_id && !sessions.has(r.session_id))
      sessions.set(r.session_id, {});
  }
  // 세션 미종결 pending 은 "진행 중이던 턴"일 수 있어 후보로 확정하지 않는다 (로그 절단 구분)

  const finish = (map) =>
    [...map.values()]
      .map((e) => ({
        name: e.name,
        calls: e.calls,
        user: e.user,
        model: e.model,
        trigger_null: e.trigger_null,
        why_rate: e.calls ? +(e.why / e.calls).toFixed(2) : 0,
        turn_command_calls: e.turn_command,
        completed: e.completed,
        avg_ms: e.dur_ms.length
          ? Math.round(e.dur_ms.reduce((a, b) => a + b, 0) / e.dur_ms.length)
          : null,
        last_ts: e.last_ts,
      }))
      .sort((a, b) => b.calls - a.calls);

  return {
    prompts,
    skills: finish(skills),
    agents: finish(agents),
    sessions,
    usedFull,
    usedTail,
    lastUsedFull,
    lastUsedTail,
    candidates:
      opts.candidates > 0 ? candidates.slice(-opts.candidates).reverse() : [],
    followups:
      opts.followups > 0 ? followups.slice(-opts.followups).reverse() : [],
  };
}

// ── main ─────────────────────────────────────────────────────────────────────
function main() {
  const opts = parseArgs(process.argv);
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const traceFile =
    opts.trace || path.join(projectDir, ".claude", "skill-trace.jsonl");
  const { records: all, parseErrors, files } = loadTrace(traceFile);

  const cutoff = opts.window > 0 ? Date.now() - opts.window * 86400000 : 0;
  const records = cutoff
    ? all.filter((r) => !r.ts || Date.parse(r.ts) >= cutoff)
    : all;

  // plugins-dir 결정 — 트레이스에 설치 루트 근거가 있으면 그것이 진실원.
  // plugin_root 탐색은 윈도우 필터 이전의 전체 레코드에서 한다(오래된 session_start 가
  // 윈도우 밖으로 잘려도 "동일 설치 루트 열거" 계약이 깨지지 않도록).
  let pluginsDir = opts.pluginsDir;
  let pluginsDirSource = "flag";
  if (!pluginsDir) {
    const withRoot = [...all]
      .reverse()
      .find((r) => r.type === "session_start" && r.plugin_root);
    const derived = withRoot ? pluginsDirFromRoot(withRoot.plugin_root) : null;
    if (derived) {
      pluginsDir = derived;
      pluginsDirSource = "trace";
    } else {
      pluginsDir = path.dirname(path.resolve(__dirname, ".."));
      pluginsDirSource = "self";
    }
  }

  const agg = aggregate(records, opts);
  const inv = enumerateInventory(pluginsDir);

  // 미사용 판정 — 네임스페이스 정확 일치(usedFull) 또는 bare 이름의 tail 일치(usedTail)만 인정
  const isUsed = (item) =>
    agg.usedFull.has(item.id.toLowerCase()) || agg.usedTail.has(tail(item.id));
  const unused = (kind) =>
    inv.items
      .filter((i) => i.kind === kind && !isUsed(i))
      .map(({ id, path: p }) => ({ id, path: p }));
  const invFull = new Set(inv.items.map((i) => i.id.toLowerCase()));
  const invTails = new Set(inv.items.map((i) => tail(i.id)));
  const unknownCalled = [
    ...new Set(
      [...agg.skills, ...agg.agents]
        .map((e) => e.name)
        .filter((n) => n && n !== "(null)" && n !== "(default)")
        .map((n) => n.toLowerCase())
        // 네임스페이스가 기록된 이름은 정확 일치로만 알려짐 판정 — tail 일치로 은폐하지 않는다
        .filter((n) => (n.includes(":") ? !invFull.has(n) : !invTails.has(n))),
    ),
  ];

  // 라이프사이클 판정 기준 시각 — --now(ISO) 주입 시 그 시각, 아니면 실행 시각.
  // hermes-agent curator 의 결정론 전이(stale 30d → archive 90d)를 "제안 생성"으로만 이식 —
  // 상태 전이 실행은 이 스크립트 밖(사용자 승인)이다.
  const nowParsed = opts.now ? Date.parse(opts.now) : NaN;
  const nowMs = Number.isFinite(nowParsed) ? nowParsed : Date.now();

  // 관측 커버리지 — 라이프사이클 판정의 신뢰 한계 표기용 (관측 기간 < 임계면 참고용)
  let covFirst = null;
  let covLast = null;
  for (const r of records) {
    const t = r && r.ts ? Date.parse(r.ts) : NaN;
    if (!Number.isFinite(t)) continue;
    if (covFirst === null || t < covFirst) covFirst = t;
    if (covLast === null || t > covLast) covLast = t;
  }
  const coverageDays =
    covFirst !== null ? +((covLast - covFirst) / 86400000).toFixed(1) : 0;

  // 사용된 자산의 최종 관측 사용 시각 — isUsed 와 동일한 이름 규율(정확 일치 우선, bare tail 허용)
  const lastUsedOf = (item) => {
    const a = agg.lastUsedFull.get(item.id.toLowerCase()) || null;
    const b = agg.lastUsedTail.get(tail(item.id)) || null;
    if (a && b) return Date.parse(b) > Date.parse(a) ? b : a;
    return a || b;
  };
  const lifecycle = {
    stale_days: opts.staleDays,
    archive_days: opts.archiveDays,
    stale: [],
    archive_candidates: [],
  };
  if (opts.staleDays > 0) {
    for (const item of inv.items) {
      // 미사용-전체는 unused_* 버킷 소관 — 관측 개시 전 이력 부재와 구분 불가하므로 여기 안 섞는다
      if (!isUsed(item)) continue;
      const lu = lastUsedOf(item);
      const t = lu ? Date.parse(lu) : NaN;
      if (!Number.isFinite(t)) continue;
      const idle = Math.floor((nowMs - t) / 86400000);
      const entry = {
        id: item.id,
        kind: item.kind,
        last_used: lu,
        idle_days: idle,
      };
      if (opts.archiveDays > 0 && idle >= opts.archiveDays)
        lifecycle.archive_candidates.push(entry);
      else if (idle >= opts.staleDays) lifecycle.stale.push(entry);
    }
    lifecycle.stale.sort((a, b) => b.idle_days - a.idle_days);
    lifecycle.archive_candidates.sort((a, b) => b.idle_days - a.idle_days);
  }

  const sessionsArr = [...agg.sessions.values()];
  const report = {
    meta: {
      trace: traceFile,
      trace_files: files,
      trace_missing: files.length === 0,
      records: records.length,
      parse_errors: parseErrors,
      window_days: opts.window,
      now: new Date(nowMs).toISOString(),
      coverage: {
        first_ts: covFirst !== null ? new Date(covFirst).toISOString() : null,
        last_ts: covLast !== null ? new Date(covLast).toISOString() : null,
        days: coverageDays,
      },
      plugins_dir: pluginsDir,
      plugins_dir_source: pluginsDirSource,
    },
    sessions: {
      count: agg.sessions.size,
      with_end: sessionsArr.filter((s) => s.end).length,
      reasons: sessionsArr.reduce((m, s) => {
        if (s.reason) m[s.reason] = (m[s.reason] || 0) + 1;
        return m;
      }, {}),
    },
    prompts: agg.prompts,
    skills: agg.skills,
    agents: agg.agents,
    inventory: {
      plugins: inv.plugins,
      skills: inv.items.filter((i) => i.kind === "skill").length,
      commands: inv.items.filter((i) => i.kind === "command").length,
      agents: inv.items.filter((i) => i.kind === "agent").length,
      unused_skills: unused("skill"),
      unused_commands: unused("command"),
      unused_agents: unused("agent"),
      unknown_called: unknownCalled,
      lifecycle,
    },
    candidates: agg.candidates,
    followups: agg.followups,
  };

  if (opts.json) {
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    return;
  }

  // 텍스트 요약 (사람용 — 기계 소비는 --json)
  const L = [];
  L.push(`# observe 하네스 계측 리포트`);
  L.push(
    `트레이스: ${report.meta.trace_missing ? "없음 (OBSERVE_TRACE=1 미활성 — 수집부터 시작하세요)" : files.join(", ")}`,
  );
  L.push(
    `레코드 ${report.meta.records}건 / 파싱 실패 ${parseErrors}건 / 세션 ${report.sessions.count}개(종결 ${report.sessions.with_end}) / 프롬프트 ${agg.prompts.total}건(커맨드 ${agg.prompts.commands})`,
  );
  L.push("");
  L.push(`## 스킬/커맨드 호출 상위 (${agg.skills.length}종)`);
  for (const s of agg.skills.slice(0, 20))
    L.push(
      `- ${s.name}: ${s.calls}회 (user ${s.user}/model ${s.model}, 완주 ${s.completed}${s.avg_ms != null ? `, 평균 ${s.avg_ms}ms` : ""})`,
    );
  L.push("");
  L.push(`## 에이전트 호출 (${agg.agents.length}종)`);
  for (const a of agg.agents.slice(0, 20))
    L.push(`- ${a.name}: ${a.calls}회 (완주 ${a.completed})`);
  L.push("");
  L.push(
    `## 미사용 자산 (인벤토리 ${inv.plugins}플러그인: 스킬 ${report.inventory.skills}·커맨드 ${report.inventory.commands}·에이전트 ${report.inventory.agents})`,
  );
  L.push(
    `- 미사용 스킬 ${report.inventory.unused_skills.length} / 커맨드 ${report.inventory.unused_commands.length} / 에이전트 ${report.inventory.unused_agents.length} (상세는 --json)`,
  );
  if (unknownCalled.length)
    L.push(
      `- 인벤토리 밖 호출 ${unknownCalled.length}종 (번들·타 마켓플레이스 자산 포함 가능 — 네임스페이스 드리프트만 의심하지 말 것): ${unknownCalled.slice(0, 10).join(", ")}`,
    );
  if (lifecycle.stale.length || lifecycle.archive_candidates.length)
    L.push(
      `- 라이프사이클(마지막 관측 사용 기준): stale ${lifecycle.stale.length}종(≥${lifecycle.stale_days}일) / archive 후보 ${lifecycle.archive_candidates.length}종(≥${lifecycle.archive_days}일)${coverageDays < lifecycle.stale_days ? " — 관측 기간이 임계보다 짧아 참고용" : ""} (상세는 --json)`,
    );
  L.push("");
  L.push(
    `## 미발화 후보 턴 ${agg.candidates.length}건 (스킬/에이전트 무동작 — LLM 판정 대상, 상세는 --json)`,
  );
  L.push(
    `## 교정 후보 쌍 ${report.followups.length}건 (호출 직후 평문 프롬프트 — 교정 여부는 LLM 판정, 상세는 --json)`,
  );
  process.stdout.write(L.join("\n") + "\n");
}

main();
