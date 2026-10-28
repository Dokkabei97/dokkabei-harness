#!/usr/bin/env node
// observe-report.js — 하네스 트레이스 결정론 집계기 (의존성 없음, /observe-report 의 산출 엔진).
//
// 입력: 레포 .tracer/ 의 v1 이벤트 + 구 경로 .claude/skill-trace.jsonl(.1) 의 v0 레코드를
//   호환 reader(bin/lib/reader.js)가 v0 모양 한 스트림으로 정규화한 것. --all 이면
//   ~/.tracer/index/repos.d/ 에 등록된 레포 전부를 원문 없이 합산한다(candidates/followups 비움).
// 하는 일: 트레이스(prompt/skill/agent/result/session_* 레코드)를 tolerant reader 로 읽어
//   ① 스킬/에이전트별 호출·user/model 트리거·로드(result join)·소요시간
//      — "로드"는 PostToolUse(Skill|Agent) result 가 있다는 뜻일 뿐 작업 완주가 아니다(Skill result 는 스킬 본문
//        로드 시점에 찍힌다 — 실측: sync-claude-md 7회 모두 result 존재, 사용자는 대부분 취소). 작업 결과는 ⑦.
//   ⑦ 턴 결과 — Stop 다이제스트(turn_summary)의 outcome(committed|cancelled|corrected|failed|unknown) 분포와
//      스킬/에이전트별 분포(그 스킬·에이전트를 쓴 턴이 어떻게 끝났나). corrected 는 교정 "후보"(⑥과 같은 규칙).
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
const reader = require("./lib/reader");
const recommend = require("./lib/recommend");
const P = require("./hooks/_lib/paths");

// 커맨드 토큰·래퍼 정규식 — 기록 측 writer 와 단일 출처 (절대경로 "/Users/…" 오탐 배제 형태)
const { CMD_TOKEN, CMD_WRAP } = require("./hooks/_lib/writer");

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
    trace: null, // 구 v0 단일 파일만 읽기 (호환·픽스처용)
    root: null, // 레포 루트 지정 (기본: 기록 측과 같은 탐지 — CLAUDE_PROJECT_DIR → git toplevel → cwd)
    all: false, // 전역 합산 (~/.tracer/index/repos.d/ 의 레포 전부, 원문 제외)
    pluginsDir: null,
    // 추천 엔진(P3) — θ·margin 은 수동 상수(자동 보정은 백로그), 표본·연쇄 임계는 실험용 오버라이드
    theta: recommend.DEFAULTS.theta,
    margin: recommend.DEFAULTS.margin,
    minSample: recommend.DEFAULTS.minSample,
    orchMin: recommend.DEFAULTS.orchMin,
    record: true, // .tracer 가 있는 레포 모드에서 recommendations.jsonl 에 생성 이벤트 append (--no-record 로 끔)
    effectDays: recommend.DEFAULTS.effectDays, // git 반영(Observe-Rec) 전후 비교 창 — 추천·기록과 무관한 읽기 전용 파라미터
    // 명시 피드백(P5) — --accept/--reject/--snooze <id>[,<id>…] 가 하나라도 있으면 집계 대신 status 이벤트만 append
    feedbackMode: false,
    feedback: [],
    feedbackBad: [], // 값 없는 피드백 플래그(끝에 오거나 값 자리에 다른 플래그) — runFeedback 이 아무것도 쓰지 않고 exit 1
    snoozeDays: recommend.DEFAULTS.snoozeDays,
  };
  const FEEDBACK_FLAG = {
    "--accept": "accepted",
    "--reject": "rejected",
    "--snooze": "snoozed",
  };
  for (let i = 2; i < argv.length; i++) {
    let a = argv[i];
    // 피드백 플래그·--snooze-days 는 --flag=값 형태도 받는다 — 못 알아보면 일반 리포트(기록 실행)로 빠져 응답이 조용히 사라진다
    let inline = null;
    const eq = a.indexOf("=");
    if (
      eq > 0 &&
      (FEEDBACK_FLAG[a.slice(0, eq)] || a.slice(0, eq) === "--snooze-days")
    ) {
      inline = a.slice(eq + 1);
      a = a.slice(0, eq);
    }
    if (a === "--json") opts.json = true;
    else if (a === "--trace") opts.trace = argv[++i];
    else if (a === "--root") opts.root = argv[++i];
    else if (a === "--all") opts.all = true;
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
    else if (a === "--theta") opts.theta = parseFloat(argv[++i]) || 0;
    else if (a === "--margin") opts.margin = parseFloat(argv[++i]) || 0;
    else if (a === "--min-sample")
      opts.minSample = parseInt(argv[++i], 10) || 0;
    else if (a === "--orch-min") opts.orchMin = parseInt(argv[++i], 10) || 1;
    else if (a === "--no-record") opts.record = false;
    else if (a === "--effect-days")
      opts.effectDays =
        Math.max(0, parseInt(argv[++i], 10) || 0) ||
        recommend.DEFAULTS.effectDays; // 0·음수·숫자 아님 = 기본값
    else if (FEEDBACK_FLAG[a]) {
      opts.feedbackMode = true;
      // 값 자리에 다른 플래그가 오면 ID 로 먹지 않는다(그 플래그는 다음 회차에 정상 처리)
      const v =
        inline !== null
          ? inline
          : argv[i + 1] === undefined || argv[i + 1].startsWith("--")
            ? ""
            : argv[++i];
      const ids = v
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      if (!ids.length) opts.feedbackBad.push(a);
      for (const tok of ids) {
        // <id>@<evidence_n> — Phase 6 이 보여 준 재노출 항목의 근거 수(쿨다운 안 2배 재노출이면 feedback 이 새 회차 created 를 먼저 쓴다)
        const at = tok.lastIndexOf("@");
        if (at > 0)
          opts.feedback.push({
            id: tok.slice(0, at),
            status: FEEDBACK_FLAG[a],
            evidence_n: Number(tok.slice(at + 1)),
          });
        else opts.feedback.push({ id: tok, status: FEEDBACK_FLAG[a] });
      }
    } else if (a === "--snooze-days")
      opts.snoozeDays = inline !== null ? inline : argv[++i]; // 검증은 runFeedback — 양의 정수가 아니면 exit 1 (기본값·과거 쿨다운으로 조용히 바꾸지 않는다)
  }
  return opts;
}

// ── 명시 피드백 (P5) ─────────────────────────────────────────────────────────
// /observe-report 끝에서 사용자가 추천 ID 별로 답한 응답을 status 이벤트로 recommendations.jsonl 에 append 하고 끝낸다.
// 집계는 하지 않는다. 레포 모드 전용(--all·--trace 에는 응답을 남길 recommendations.jsonl 이 없다).
// 오류(모르는 ID·서로 다른 응답·기록 없음)는 아무것도 쓰지 않고 stderr 한 줄 + exit 1 — 사용자가 직접 부르는 명령이라 조용히 넘기지 않는다.
function runFeedback(opts) {
  const fail = (msg) => {
    process.stderr.write(`observe-report: ${msg}\n`);
    process.exitCode = 1;
  };
  if (opts.all || opts.trace)
    return fail(
      "--accept/--reject/--snooze 는 레포 모드에서만 쓴다 (--all·--trace 와 함께 쓸 수 없다)",
    );
  if (opts.feedbackBad.length)
    return fail(
      `${opts.feedbackBad.join("·")} 뒤에 추천 ID 가 없다 (예: --reject rec_0123456789ab) — 아무것도 쓰지 않았다`,
    );
  if (!opts.feedback.length)
    return fail("응답할 추천 ID 가 없다 (예: --reject rec_0123456789ab)");
  if (!/^[1-9]\d*$/.test(String(opts.snoozeDays)))
    return fail(
      `--snooze-days 는 양의 정수여야 한다 (받은 값: ${opts.snoozeDays}) — 아무것도 쓰지 않았다`,
    );
  const root = opts.root || P.findRoot(process.cwd());
  const nowParsed = opts.now ? Date.parse(opts.now) : NaN;
  const nowMs = Number.isFinite(nowParsed) ? nowParsed : Date.now();
  const r = recommend.feedback(root, opts.feedback, nowMs, {
    snoozeDays: Number(opts.snoozeDays),
  });
  if (r.error === "no_recommendations")
    return fail(
      `${P.recommendationsFile(root)} 가 없다 — 기록된 추천이 없어 응답을 남길 수 없다`,
    );
  if (r.error === "invalid")
    return fail(`응답을 하나도 쓰지 않았다 — ${r.detail.join(" / ")}`);
  if (r.error)
    return fail(`응답 기록 실패(${r.error}) — ${r.recorded}건만 기록됐다`);
  if (opts.json) {
    process.stdout.write(
      JSON.stringify(
        { feedback: { applied: r.applied, recorded: r.recorded } },
        null,
        2,
      ) + "\n",
    );
    return;
  }
  const L = r.applied.map(
    (a) =>
      `- ${a.id} [${a.type}] ${a.target} → ${a.status}${a.unchanged ? " (이미 그 상태 — 기록 안 함)" : ""}${a.reopened ? " (재노출 — 새 회차)" : ""}${a.cooldown_until ? ` (쿨다운 ${a.cooldown_until.slice(0, 10)} 까지)` : ""}`,
  );
  L.push(`응답 ${r.recorded}건 기록 — ${P.recommendationsFile(root)}`);
  process.stdout.write(L.join("\n") + "\n");
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
    if (!fs.existsSync(path.join(root, ".claude-plugin", "plugin.json"))) {
      // 버전 간접 레이아웃(<플러그인>/<버전>/.claude-plugin) — 최신 버전 하나만 분모로 인정
      const vroot = latestVersionRoot(root);
      if (!vroot) continue; // plugin.json 없는 디렉터리는 플러그인이 아니다 (템플릿 오염 가드)
      root = vroot;
    }
    inv.plugins++;
    inv.items.push(...pluginItems(root, dir));
  }
  return inv;
}

// 플러그인 설치 루트 하나 → 스킬·커맨드·에이전트 항목 (id = <plugin.json name>:<frontmatter name>)
function pluginItems(root, dir) {
  const items = [];
  let plugin = dir;
  try {
    const pj = JSON.parse(
      fs.readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8"),
    );
    if (pj.name) plugin = pj.name;
  } catch (_) {
    /* 깨진 plugin.json — 플러그인은 실재하므로 디렉터리명 폴백으로 계속 열거 */
  }
  for (const s of listDir(path.join(root, "skills"))) {
    const f = path.join(root, "skills", s, "SKILL.md");
    if (!fs.existsSync(f)) continue;
    items.push({
      id: `${plugin}:${frontmatterName(f) || s}`,
      kind: "skill",
      path: f,
    });
  }
  for (const c of listDir(path.join(root, "commands"))) {
    if (!c.endsWith(".md")) continue;
    const f = path.join(root, "commands", c);
    items.push({
      id: `${plugin}:${frontmatterName(f) || c.replace(/\.md$/, "")}`,
      kind: "command",
      path: f,
    });
  }
  for (const a of listDir(path.join(root, "agents"))) {
    if (!a.endsWith(".md")) continue;
    const f = path.join(root, "agents", a);
    items.push({
      id: `${plugin}:${frontmatterName(f) || a.replace(/\.md$/, "")}`,
      kind: "agent",
      path: f,
    });
  }
  return items;
}

// ── 매칭 인벤토리 (추천 엔진 입력) ─────────────────────────────────────────────
// 미사용 분모(enumerateInventory)는 그대로 두고, 매칭 후보만 넓힌다(로드맵 5.2).
// 플러그인 출처: 설치 목록(~/.claude/plugins/installed_plugins.json — user 범위 + 이 레포 project 범위의 installPath)이
//   읽히면 그것만 쓴다 — 트레이스 plugin_root 역산 분모(마켓 캐시 루트)에는 archive 된 구버전 플러그인이 남아 있어
//   (실측: mvp·feature-loop·startup) 지금 설치되지 않은 자산을 추천하게 된다. --plugins-dir 명시 또는 설치 목록 부재면 분모 항목.
// 비플러그인 출처: 스킬·커맨드·에이전트(<root>/.claude/·~/.claude/·<root>/.agents/skills·~/.agents/skills — 읽기만).
// 비플러그인 자산 id 는 접두어 없는 이름(호출 이름 그대로). 같은 id 는 먼저 열거된 출처가 이긴다.
function matchInventory(inv, root, preferInv) {
  const os = require("os");
  const home = os.homedir();
  const out = [];
  const seen = new Set();
  const add = (items, source) => {
    for (const it of items) {
      const k = it.id.toLowerCase();
      if (seen.has(k)) continue;
      seen.add(k);
      out.push({ ...it, source });
    }
  };
  let installed = null;
  if (!preferInv) {
    try {
      const j = JSON.parse(
        fs.readFileSync(
          path.join(home, ".claude", "plugins", "installed_plugins.json"),
          "utf8",
        ),
      );
      installed = [];
      for (const [key, list] of Object.entries(j.plugins || {}).sort()) {
        for (const e of Array.isArray(list) ? list : []) {
          if (!e || !e.installPath || !fs.existsSync(e.installPath)) continue;
          // user·managed 외 범위(project·local)는 projectPath 하나에 묶인다 — 이 레포가 아니면 이 레포에서 쓸 수 없는 자산
          if (
            e.scope !== "user" &&
            e.scope !== "managed" &&
            (!root || path.resolve(e.projectPath || "") !== path.resolve(root))
          )
            continue;
          installed.push(...pluginItems(e.installPath, key.split("@")[0]));
        }
      }
    } catch (_) {
      installed = null; // 설치 목록 없음·깨짐 — 분모 항목으로 폴백
    }
  }
  if (installed) add(installed, "installed");
  else add(inv.items, "plugins");
  // SKILL.md 탐색 — 깊이 3까지(~/.claude/skills/synced/<id>/<name>/SKILL.md 실측 레이아웃)
  const skillsUnder = (dir, depth = 3) => {
    const found = [];
    for (const n of listDir(dir).sort()) {
      const d = path.join(dir, n);
      const f = path.join(d, "SKILL.md");
      if (fs.existsSync(f))
        found.push({ id: frontmatterName(f) || n, kind: "skill", path: f });
      else if (depth > 1) {
        try {
          if (fs.statSync(d).isDirectory())
            found.push(...skillsUnder(d, depth - 1));
        } catch (_) {
          /* 깨진 링크 */
        }
      }
    }
    return found;
  };
  const mdUnder = (dir, kind) =>
    listDir(dir)
      .filter((n) => n.endsWith(".md"))
      .sort()
      .map((n) => {
        const f = path.join(dir, n);
        return {
          id: frontmatterName(f) || n.replace(/\.md$/, ""),
          kind,
          path: f,
        };
      });
  const bases = [
    ...(root ? [[path.join(root, ".claude"), "project"]] : []),
    [path.join(home, ".claude"), "user"],
  ];
  for (const [b, src] of bases) {
    add(skillsUnder(path.join(b, "skills")), `${src}-skills`);
    add(mdUnder(path.join(b, "commands"), "command"), `${src}-commands`);
    add(mdUnder(path.join(b, "agents"), "agent"), `${src}-agents`);
  }
  if (root)
    add(
      skillsUnder(path.join(root, ".agents", "skills")),
      "project-agents-skills",
    );
  add(skillsUnder(path.join(home, ".agents", "skills")), "user-agents-skills");
  return out;
}

// ── 집계 ─────────────────────────────────────────────────────────────────────
const tail = (id) => String(id).toLowerCase().split(":").pop();

function aggregate(records, opts, digests = []) {
  const skills = new Map();
  const agents = new Map();
  const sessions = new Map();
  const preByToolUse = new Map(); // tool_use_id → pre 엔트리 (정밀 join)
  const prePending = new Map(); // `${sid}\0${target}` → pre 엔트리 목록 (tool_use_id 부재 시 근사 join)
  // result 는 즉시 join 하지 않고 모아 뒀다가 전체 인덱싱 후 join 한다(2-pass).
  // pre 훅은 why 해석을 detached 자식에 맡겨 지연 append 하므로, 같은 호출의 result 가
  // pre 보다 "파일상 먼저" 기록되는 것이 정상 경로다 (실측: result 27건 중 19건 선행).
  const results = [];
  const prompts = { total: 0, commands: 0 };
  const candidates = [];
  const pending = new Map(); // session_id → {ts, session_id, turn, text}
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
        heuristic: 0, // skill.detection "heuristic"(Codex SKILL.md 읽기) — 로드(result) 신호가 원천에 없다
        loaded: 0,
        dur_ms: [],
        last_ts: null,
      });
    const e = map.get(key);
    e.calls++;
    return e;
  };
  const pushPre = (sid, target, entry, r, idx) => {
    const pre = {
      entry,
      ts: r.ts,
      idx,
      joined: false,
      id: r.tool_use_id || null,
    };
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

  for (let idx = 0; idx < records.length; idx++) {
    const r = records[idx];
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
        // v1 이벤트는 기록 시점에 뽑은 command 를 들고 온다 — 원문 없는 전역 합산에서도 같은 크레딧
        const wrap = CMD_WRAP.exec(r.text || "");
        const tok = CMD_TOKEN.exec(r.text || "");
        const name = r.command || (wrap && wrap[1]) || (tok && tok[1]);
        if (name) addUsed(name, r.ts);
      } else {
        pending.set(sid, {
          ts: r.ts || null,
          session_id: sid,
          turn: r.prompt_id || null, // 추천 근거 ref(session#turn — turn 없으면 ts)와 맞추는 키
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
      if (r.why || r.why_ref) e.why++; // why 원문은 raw/ 에 — 원문 없이 읽어도 why_ref 로 존재를 센다
      if (r.turn_command) e.turn_command++;
      if (r.detection === "heuristic") e.heuristic++;
      e.last_ts = r.ts || e.last_ts;
      if (r.skill) addUsed(r.skill, r.ts);
      if (r.turn_command) addUsed(r.turn_command, r.ts);
      lastAction.set(sid, { kind: "skill", target: key, ts: r.ts || null });
      pushPre(sid, key, e, r, idx);
    } else if (r.type === "agent") {
      pending.delete(sid);
      const key = r.agent || "(default)";
      const e = bump(agents, key);
      if (r.why || r.why_ref) e.why++;
      e.last_ts = r.ts || e.last_ts;
      if (r.agent) addUsed(r.agent, r.ts);
      lastAction.set(sid, { kind: "agent", target: key, ts: r.ts || null });
      pushPre(sid, key, e, r, idx);
    } else if (r.type === "result") {
      results.push({ r, sid, idx });
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

  // ── result join (2-pass) ── 모든 pre 가 인덱싱된 뒤 수행한다.
  //   pass 1: tool_use_id 정밀 join — 파일 순서와 무관 (result 선행 기록 허용)
  //           id 가 같은 pre 가 있으면 이미 joined 여도(중복 result) 근사 join 으로 넘기지 않는다.
  //   pass 2: 정밀 짝이 없는 result 만 근사 join — 같은 세션·같은 target 에서 "파일상 result
  //           보다 앞선" 최근 미조인 pre (tool_use_id 없는 구버전 레코드는 지연 append 이전이라
  //           순서가 보존된다 — 기존 의미 유지). pass 1 을 먼저 끝내 정밀 짝을 가로채지 않는다.
  //           양쪽 모두 tool_use_id 가 있으면 서로 다른 호출이므로 짝짓지 않는다.
  const joinTo = (pre, r) => {
    pre.joined = true;
    pre.entry.loaded++;
    const d = Date.parse(r.ts) - Date.parse(pre.ts);
    if (Number.isFinite(d) && d >= 0) pre.entry.dur_ms.push(d);
  };
  const unmatched = [];
  for (const x of results) {
    const pre = x.r.tool_use_id ? preByToolUse.get(x.r.tool_use_id) : null;
    if (pre) {
      if (!pre.joined) joinTo(pre, x.r);
    } else unmatched.push(x);
  }
  for (const { r, sid, idx } of unmatched) {
    const fallbackKey =
      sid + "\0" + (r.target || (r.tool === "Skill" ? "(null)" : "(default)"));
    const list = prePending.get(fallbackKey) || [];
    for (let k = list.length - 1; k >= 0; k--)
      if (
        !list[k].joined &&
        list[k].idx < idx &&
        !(r.tool_use_id && list[k].id)
      ) {
        joinTo(list[k], r);
        break;
      }
  }

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
        ...(e.heuristic ? { heuristic: e.heuristic } : {}), // 있을 때만 — Claude 만 쓰는 리포트 JSON 은 키까지 그대로
        loaded: e.loaded,
        avg_ms: e.dur_ms.length
          ? Math.round(e.dur_ms.reduce((a, b) => a + b, 0) / e.dur_ms.length)
          : null,
        last_ts: e.last_ts,
      }))
      .sort((a, b) => b.calls - a.calls);

  // 다른 런타임 다이제스트 턴의 스킬 이름도 사용 신호 — Skill 툴이 없는 런타임(Codex·Antigravity 백필)은 skill_use 이벤트
  // 없이 turn_summary.skills 에만 남는다(미사용·라이프사이클 오판 방지). 호출수(calls)에는 넣지 않는다(턴 단위라 이벤트와
  // 단위가 다르다). Claude 턴은 같은 사용이 skill_use 이벤트로 이미 들어오므로 건너뛴다(Claude 집계 무변경).
  for (const t of digests)
    if (
      t &&
      t.kind === "turn_summary" &&
      t.runtime &&
      t.runtime !== "claude-code"
    )
      for (const x of t.skills || [])
        if (x && x.name) addUsed(x.name, t.ts_end || t.ts_start || null);

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

// ── 턴 결과(다이제스트) 집계 ─────────────────────────────────────────────────
const OUTCOMES = ["committed", "cancelled", "corrected", "failed", "unknown"];
const zeroOutcomes = () => Object.fromEntries(OUTCOMES.map((k) => [k, 0]));

// turn_summary 목록 → { count, system, outcomes, commits, tokens, by_skill[], by_agent[] }. 원문 없음.
// count·outcomes·by_skill/by_agent 는 사람 턴(prompt_kind user, 없으면 user)만 — async 완료 알림·! 모드 같은
// 시스템 주입 턴은 system 으로만 센다(턴 결과 분모를 부풀리지 않게). commits·tokens 는 모든 턴 합.
// by_skill/by_agent: 그 이름을 쓴 턴 수와 그 턴들의 outcome 분포 (한 턴에 같은 이름 여러 번이어도 1턴).
function aggregateTurns(digests) {
  const out = {
    count: 0,
    system: 0,
    outcomes: zeroOutcomes(),
    commits: 0,
    tokens: { in: 0, out: 0, cache_r: 0, cache_w: 0 },
    by_skill: [],
    by_agent: [],
  };
  const bySkill = new Map();
  const byAgent = new Map();
  const bump = (map, name, outcome) => {
    if (!map.has(name))
      map.set(name, { name, turns: 0, outcomes: zeroOutcomes() });
    const e = map.get(name);
    e.turns++;
    if (outcome in e.outcomes) e.outcomes[outcome]++;
  };
  for (const t of digests) {
    if (!t || t.kind !== "turn_summary") continue;
    out.commits += ((t.git && t.git.commits) || []).length;
    for (const k of Object.keys(out.tokens))
      out.tokens[k] +=
        (t.tokens && Number.isFinite(t.tokens[k]) && t.tokens[k]) || 0;
    if (t.prompt_kind && t.prompt_kind !== "user") {
      out.system++;
      continue;
    }
    out.count++;
    const oc = OUTCOMES.includes(t.outcome) ? t.outcome : "unknown";
    out.outcomes[oc]++;
    for (const n of new Set(
      (t.skills || []).map((x) => x.name).filter(Boolean),
    ))
      bump(bySkill, n, oc);
    for (const n of new Set(
      (t.subagents || []).map((x) => x.type || "(default)"),
    ))
      bump(byAgent, n, oc);
  }
  const sorted = (m) =>
    [...m.values()].sort(
      (a, b) => b.turns - a.turns || (a.name < b.name ? -1 : 1),
    );
  out.by_skill = sorted(bySkill);
  out.by_agent = sorted(byAgent);
  return out;
}

// ── main ─────────────────────────────────────────────────────────────────────
function main() {
  const opts = parseArgs(process.argv);
  if (opts.feedbackMode) return runFeedback(opts);
  // 소스 선택: --all(전역, 원문 제외) > --trace(구 v0 단일 파일) > 레포(.tracer + 구 경로 폴백).
  // 레포 루트는 paths.findRoot — cwd 에서 위로 .tracer/구 경로가 있는 가장 가까운 조상(git toplevel 까지).
  // 훅은 CLAUDE_PROJECT_DIR(하위 패키지일 수 있음)에 쓰지만 Bash 툴엔 이 변수가 없어 toplevel 만 보면 어긋난다.
  let loaded;
  let traceLabel;
  let root = null; // 레포 모드에서만 — 추천 이벤트 기록·프로젝트 인벤토리 출처
  if (opts.all) {
    loaded = reader.loadAll();
    traceLabel = P.globalDir();
  } else if (opts.trace) {
    loaded = reader.loadRepo(path.dirname(opts.trace), {
      legacy: [opts.trace + ".1", opts.trace],
      tracer: false,
    });
    traceLabel = opts.trace;
  } else {
    root = opts.root || P.findRoot(process.cwd());
    loaded = reader.loadRepo(root);
    traceLabel = P.tracerDir(root);
  }
  const { records: all, parseErrors, files } = loaded;

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
    // Claude Code session_start 만(v0 는 runtime 없음) — Codex 도 CLAUDE_PLUGIN_ROOT 를 자기 설치 캐시로 설정해 plugin_root 를
    // 남기므로, 런타임을 안 가리면 마지막에 시작한 런타임에 따라 분모가 바뀐다.
    const withRoot = [...all]
      .reverse()
      .find(
        (r) =>
          r.type === "session_start" &&
          r.plugin_root &&
          (!r.runtime || r.runtime === "claude-code"),
      );
    const derived = withRoot ? pluginsDirFromRoot(withRoot.plugin_root) : null;
    if (derived) {
      pluginsDir = derived;
      pluginsDirSource = "trace";
    } else {
      pluginsDir = path.dirname(path.resolve(__dirname, ".."));
      pluginsDirSource = "self";
    }
  }

  const digests = cutoff
    ? (loaded.digests || []).filter(
        (d) => !d.ts_end || Date.parse(d.ts_end) >= cutoff,
      )
    : loaded.digests || [];
  const agg = aggregate(records, opts, digests);
  const turns = aggregateTurns(digests);
  // 스킬/에이전트 항목에 턴 결과 분포를 붙인다 — 다이제스트가 없는 이름(구 v0 기록만 있는 경우 등)은 null
  const outcomeOf = (list, name) => {
    const e = list.find((x) => x.name === name);
    return e ? { turns: e.turns, ...e.outcomes } : null;
  };
  for (const s of agg.skills) s.outcome = outcomeOf(turns.by_skill, s.name);
  for (const a of agg.agents) a.outcome = outcomeOf(turns.by_agent, a.name);
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
      trace: traceLabel,
      trace_files: files,
      trace_missing: files.length === 0,
      scope: opts.all ? "all" : "repo",
      schema: loaded.schema, // 출처별 레코드 수 {v0: 구 경로, v1: .tracer}
      ...(opts.all ? { repos: loaded.repos } : {}),
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
    turns,
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
    // 전역 합산은 원문 운반 섹션을 구조적으로 비운다 (raw 를 읽지 않으므로 내용도 없다)
    candidates: opts.all ? [] : agg.candidates,
    followups: opts.all ? [] : agg.followups,
  };

  // 추천 엔진(P3) — additive 섹션 matches·recommendations. 원문 매칭은 레포/--trace 모드만(--all 은 raw:false 라
  // 연쇄 n-gram 만 남는다). --candidates 0(export 파이프)이면 원문 파생 tune 용어와 턴 목록을 싣지 않는다.
  const rec = recommend.analyze({
    records,
    digests,
    items: matchInventory(inv, root, pluginsDirSource === "flag"),
    events: root ? recommend.readEvents(root) : null, // null = 이벤트를 읽지 않는 실행(--all·--trace) — precision 도 null
    // git 반영 원장(Observe-Rec trailer) — 레포 모드만. --all 은 레포별 git 을 돌지 않는다(단순한 쪽 — 문서에 명시), --trace 는 레포가 없다
    applied: root ? recommend.gitApplied(root) : null,
    raw: !opts.all,
    showTerms: !opts.all && opts.candidates > 0,
    listLimit: opts.all ? 0 : opts.candidates,
    now: nowMs,
    params: {
      theta: opts.theta,
      margin: opts.margin,
      minSample: opts.minSample,
      orchMin: opts.orchMin,
      effectDays: opts.effectDays,
    },
  });
  // 생성 이벤트 기록 — 기본 파라미터로 레포 전체를 본 실행일 때만, .tracer 가 있어야 한다.
  //   --window 부분 관측·임계 오버라이드(--theta/--margin/--min-sample/--orch-min) 실험은 근거 시그니처와 쿨다운 기준
  //   (거절 직전 created 의 evidence_n)을 흔든다. --candidates 0(export 파이프)은 추천을 사람에게 보여주지 않는 읽기 경로다.
  const D = recommend.DEFAULTS;
  const defaultParams =
    opts.theta === D.theta &&
    opts.margin === D.margin &&
    opts.minSample === D.minSample &&
    opts.orchMin === D.orchMin;
  if (
    root &&
    opts.record &&
    !opts.window &&
    defaultParams &&
    opts.candidates > 0
  ) {
    const w = recommend.appendEvents(root, rec.append);
    rec.recommendations.recorded = w.recorded;
    if (w.error) rec.recommendations.record_error = w.error; // 부수 기록 실패는 리포트를 막지 않는다
  }
  report.matches = rec.matches;
  report.recommendations = rec.recommendations;
  // 노출 추천의 근거 턴은 --candidates 상한 밖이어도 candidates 에 보강한다 — Phase 3 가 근거 ref 로 원문을 찾는 곳
  const candKey = (c) => `${c.session_id}#${c.turn || c.ts || "?"}`;
  const haveCand = new Set(report.candidates.map(candKey));
  for (const c of rec.evidenceTurns)
    if (!haveCand.has(candKey(c))) report.candidates.push(c);

  if (opts.json) {
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    return;
  }

  // 텍스트 요약 (사람용 — 기계 소비는 --json)
  const pct = (n, d) => `${Math.round((n / d) * 100)}%`;
  const outcomeText = (oc) =>
    oc && oc.turns
      ? `, 턴 ${oc.turns}: 커밋 ${pct(oc.committed, oc.turns)}·취소 ${pct(oc.cancelled, oc.turns)}·교정후보 ${pct(oc.corrected, oc.turns)}`
      : "";
  const L = [];
  L.push(`# observe 하네스 계측 리포트`);
  L.push(
    `트레이스: ${report.meta.trace_missing ? "없음 (OBSERVE_TRACE=1 미활성 — 수집부터 시작하세요)" : `${traceLabel} (파일 ${files.length}개 — .tracer v1 ${loaded.schema.v1}건 / 구 경로 v0 ${loaded.schema.v0}건${opts.all ? `, 레포 ${loaded.repos.length}개 합산·원문 제외` : ""})`}`,
  );
  L.push(
    `레코드 ${report.meta.records}건 / 파싱 실패 ${parseErrors}건 / 세션 ${report.sessions.count}개(종결 ${report.sessions.with_end}) / 프롬프트 ${agg.prompts.total}건(커맨드 ${agg.prompts.commands})`,
  );
  // 리포트 머리의 유형별 precision(로드맵 5.4) — 분모(수락+거절) < 10 이면 값 대신 "표본 부족"
  const PR = rec.recommendations.precision;
  L.push(
    PR
      ? `추천 precision(명시 응답 + git 반영 기준): ${Object.entries(PR)
          .map(
            ([t, x]) =>
              (x.status === "ok"
                ? `${t} ${x.precision} (수락 ${x.accepted}/응답 ${x.n})`
                : `${t} 표본 부족 (응답 ${x.n}<${x.min})`) +
              (x.applied ? ` [git 반영 ${x.applied} 포함]` : ""),
          )
          .join(" · ")}`
      : "추천 precision: 레포 모드에서만 집계 (--all·--trace 는 recommendations.jsonl 을 읽지 않는다)",
  );
  L.push("");
  L.push(`## 스킬/커맨드 호출 상위 (${agg.skills.length}종)`);
  for (const s of agg.skills.slice(0, 20))
    L.push(
      `- ${s.name}: ${s.calls}회 (user ${s.user}/model ${s.model}, 로드 ${s.calls && s.heuristic === s.calls ? "n/a(heuristic)" : s.loaded}${s.heuristic && s.heuristic < s.calls ? ` · heuristic ${s.heuristic}` : ""}${s.avg_ms != null ? `, 평균 ${s.avg_ms}ms` : ""}${outcomeText(s.outcome)})`,
    );
  L.push("");
  L.push(`## 에이전트 호출 (${agg.agents.length}종)`);
  for (const a of agg.agents.slice(0, 20))
    L.push(
      `- ${a.name}: ${a.calls}회 (반환 ${a.loaded}${outcomeText(a.outcome)})`,
    );
  L.push("");
  L.push(
    `## 턴 결과 (Stop 다이제스트 ${turns.count}턴${turns.system ? ` + 시스템 주입 ${turns.system}턴 제외` : ""})`,
  );
  if (!turns.count)
    L.push(
      "- 다이제스트 없음 — Stop 훅이 기록한 turn_summary 가 아직 없다 (OBSERVE_TRACE=1 세션의 턴이 끝나면 쌓인다)",
    );
  else {
    const o = turns.outcomes;
    L.push(
      `- 커밋 ${o.committed} / 취소 ${o.cancelled} / 교정 후보 ${o.corrected} / 실패 ${o.failed} / 미상 ${o.unknown} (커밋 SHA ${turns.commits}개)`,
    );
  }
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
    `## 미발화 후보 턴 ${report.candidates.length}건 (스킬/에이전트 무동작 — LLM 판정 대상, 상세는 --json)`,
  );
  L.push(
    `## 교정 후보 쌍 ${report.followups.length}건 (호출 직후 평문 프롬프트 — 교정 여부는 LLM 판정, 상세는 --json)`,
  );
  const R = rec.recommendations;
  const G = rec.matches.gold;
  L.push("");
  L.push(
    `## 추천 후보 ${R.items.length}건 (결정론 랭킹 — 판정은 LLM, 유형별 ≤${R.params.cap})`,
  );
  if (R.record_error)
    L.push(
      `- 추천 이벤트 기록 실패(${R.record_error}) — recommendations.jsonl 에 쓰지 못했다(리포트 내용은 그대로)`,
    );
  if (!R.sample.ok)
    L.push(
      `- 표본 부족 — 사람 프롬프트 ${R.sample.human_prompts}건 < ${R.sample.min} 이라 추천을 내지 않는다`,
    );
  else if (!R.sample.exact)
    L.push(
      `- 사람 프롬프트 ${R.sample.human_prompts}건은 상한값 — 원문 없이 합산해 시스템 주입 프롬프트를 다이제스트로만 걸렀다`,
    );
  for (const it of R.items)
    L.push(
      `- [${it.type}] ${it.target} ${it.id} (근거 세션 ${it.evidence_n}${it.status === "new" ? "" : `, ${it.status}${it.resurfaced_from ? `(${it.resurfaced_from})` : ""}`}${it.skill_type && it.skill_type !== "action" ? `, ${it.skill_type}형` : ""}${it.tune ? `, tune 하위 제안(${it.tune.reason})` : ""})`,
    );
  L.push(
    `- 매칭: 미발화 턴 ${rec.matches.turns_scored}건 채점 / 골드 라벨 N=${G.n}${G.status === "ok" ? ` top-3 ${Math.round(G.rate * 100)}%` : " (측정불가 — N<10)"}`,
  );
  // git 반영(Observe-Rec trailer) — 반영 기록이나 모르는 ID 가 있을 때만 절을 낸다(git 없음·trailer 없음은 조용히 생략)
  const AP = R.applied;
  if (AP && AP.available && (AP.items.length || AP.unknown.length)) {
    L.push("");
    L.push(
      `## 반영된 추천 ${AP.items.length}건 (커밋 trailer Observe-Rec — 다시 제안하지 않음)`,
    );
    const pctOf = (x) =>
      x.rate == null ? "-" : `${Math.round(x.rate * 100)}%`;
    for (const it of AP.items) {
      const last = it.commits[it.commits.length - 1];
      const e = it.effect;
      const eff =
        e.status === "ok" || e.status === "표본 부족"
          ? `호출 비율 ${pctOf(e.before)} → ${pctOf(e.after)} (전 ${e.before.fired}/${e.before.n} · 후 ${e.after.fired}/${e.after.n}턴, 각 ${e.window_days}일 창)${e.status === "ok" ? "" : ` — 표본 부족(각 ≥${e.min}턴 필요)`}`
          : e.status;
      L.push(
        `- [${it.type}] ${it.target} ${it.id} 커밋 ${last.sha.slice(0, 7)} ${last.ts.slice(0, 10)}${it.commits.length > 1 ? ` 외 ${it.commits.length - 1}개` : ""} — ${eff}`,
      );
    }
    if (AP.unknown.length)
      L.push(
        `- 모르는 ID trailer ${AP.unknown.length}건 (recommendations.jsonl·이번 후보에 없음): ${AP.unknown.slice(0, 5).join(", ")}${AP.unknown.length > 5 ? " 외" : ""}`,
      );
  }
  process.stdout.write(L.join("\n") + "\n");
}

main();
