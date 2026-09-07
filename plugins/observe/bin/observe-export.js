#!/usr/bin/env node
// observe-export.js — 집계 JSON → 위키 투입용 마크다운 스냅샷 결정론 렌더러 (의존성 없음).
//
// 파이프 계약: observe-report.js --json --candidates 0 --followups 0 의 stdout 을 stdin 으로
// 받아, llmwiki ingest 가 먹을 수 있는 마크다운 스냅샷을 stdout 으로 낸다. 파일은 절대 쓰지
// 않는다(stdout-온리) — observe 의 제안-온리 계약(파일 일절 미수정)은 이 스크립트에도 적용된다.
// 물화(파일 저장)와 ingest 는 wiki-ops 측(wiki-harness-feed 스킬)의 책임이다.
//
// 프라이버시 fail-closed (1차 게이트): 입력 JSON 어디든 프롬프트 원문 운반 필드
// (text/next_prompt/why/args/prompt_head/prompt)가 보이면 렌더를 거부하고 exit 2 로 죽는다 —
// "--candidates 0 --followups 0 을 기억하는" LLM 규율이 아니라 코드가 원문 유출을 막는다.
// 입력은 JSON 객체만 허용(비객체는 exit 2 — 상류 파이프 실패의 fail-open 방지). 자산명 등
// 데이터 유래 문자열은 제어문자·개행·마크업([[ ]] ** )을 살균해 claim 구조 주입을 막는다.
// 절대경로 준식별자(meta.trace/plugins_dir, unused[].path 등)는 렌더에서 드롭하고
// plugin:skill id 만 내보낸다. 최종 출력에 절대경로 루트(/Users|/home|/Volumes|/mnt|/media|/srv)
// 또는 attr: 줄이 남으면 exit 2 (자기 검사 — 살균 우회 회귀까지 코드로 차단).
//
// 렌더 형식 규약(소비측과 동기): wiki-ops/skills/wiki-harness-feed/references/snapshot-format.md
//   - 산문 1줄 = claim 1개 (llmwiki 는 헤딩 아닌 비어있지 않은 줄마다 claim 을 만든다)
//   - 자산명은 [[위키링크]] → entity 자동 upsert + 교차링크 동시 충족. **bold** 는 entity 만
//     만들고 링크는 못 만들어 missing_crossref lint 를 구조적으로 유발한다(E2E 실측 8건) —
//     자산명 평문/볼드 언급 금지, 전 occurrence 를 [[..]] 로 렌더한다
//   - attr: 줄 절대 금지 — 주기 변동값의 attr: 기입은 entity contradiction 오염 실측(0.83→0.61)
//   - 각 수치 claim 에 <env> <ISO주차> 를 박아 인용 시 자립성(시계열 비교 가능)을 보장
//
// 결정론: 동일 stdin + 동일 플래그 → 동일 바이트. 벽시계 접근 없음 — 기준 시각은
// --now > meta.now 로만 결정하고 둘 다 없으면 exit 2. 타임존 없는 타임스탬프는 UTC 로
// 정규화한다 (로컬타임 파싱은 머신 TZ 에 따라 주차가 갈리는 비결정론 — 실측 W52/W53 분기).
"use strict";

const FORBIDDEN_KEYS = new Set([
  "text",
  "next_prompt",
  "why",
  "args",
  "prompt_head",
  "prompt",
]);
// 홈/마운트 루트 준식별자 — /Users·/home 만으로는 회사 공유드라이브(/Volumes/<사명>/…)와
// 리눅스 마운트(/mnt·/media·/srv)가 새는 실측 우회가 있어 루트를 넓힌다.
const PATH_LEAK_RE = /\/(Users|home|Volumes|mnt|media|srv)\/[^\s)"']+/;

function parseArgs(argv) {
  const opts = { env: null, now: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--env") opts.env = argv[++i];
    else if (a === "--now") opts.now = argv[++i];
  }
  return opts;
}

function die(msg) {
  process.stderr.write(`observe-export: ${msg}\n`);
  process.exit(2);
}

// 데이터 유래 문자열 살균 — 트레이스의 skill/target 이름은 무검증 유래이므로(tool_input 원문)
// 제어문자·개행으로 claim 을 쪼개거나 [[ ]] · ** 로 위키 마크업을 주입하는 경로를 막는다.
function clean(s) {
  const out = String(s)
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\[\[|\]\]|\*\*/g, "")
    .trim();
  return out || "(unnamed)";
}

// 수치 방어 — null/문자열 수치가 "호출 null회" 류 쓰레기 claim 이 되지 않게 0 폴백
function num(v) {
  return Number.isFinite(v) ? v : 0;
}

// 원문 운반 필드 딥 스캔 — 현재 스키마상 2곳(candidates[].text, followups[].next_prompt)이지만
// additive 확장 드리프트까지 잡도록 키 이름 기준으로 전체를 훑는다.
function scanForbidden(node, path, hits) {
  if (Array.isArray(node)) {
    node.forEach((v, i) => scanForbidden(v, `${path}[${i}]`, hits));
  } else if (node && typeof node === "object") {
    for (const [k, v] of Object.entries(node)) {
      if (FORBIDDEN_KEYS.has(k)) hits.push(`${path}.${k}`);
      scanForbidden(v, `${path}.${k}`, hits);
    }
  }
  return hits;
}

function isoWeek(iso) {
  // 타임존 표기 없는 ISO 는 UTC 로 정규화 — new Date() 의 로컬타임 파싱은 머신 TZ 에 따라
  // 동일 입력이 다른 주차로 렌더되는 결정론 위반을 만든다.
  let ts = String(iso);
  if (/\dT\d/.test(ts) && !/(?:[zZ]|[+-]\d{2}:?\d{2})$/.test(ts)) ts += "Z";
  const d = new Date(ts);
  if (Number.isNaN(d.getTime()))
    die(`invalid --now/meta.now timestamp: ${iso}`);
  const t = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()),
  );
  const day = t.getUTCDay() || 7; // ISO: 월=1 … 일=7
  t.setUTCDate(t.getUTCDate() + 4 - day); // 그 주의 목요일로 이동
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function pct(rate) {
  return `${Math.round(num(rate) * 100)}%`;
}

// 호출 집계 1건 → 자립형 claim 1줄 (env·주차 내장 — 인용 시 시계열 비교 가능)
function usageLine(item, stamp) {
  const parts = [
    `호출 ${num(item.calls)}회 (user ${num(item.user)} / model ${num(item.model)})`,
    `완주 ${num(item.completed)}회`,
  ];
  if (Number.isFinite(item.avg_ms)) parts.push(`평균 ${item.avg_ms}ms`);
  if (Number.isFinite(item.why_rate))
    parts.push(`why 표착률 ${pct(item.why_rate)}`);
  return `[[${clean(item.name)}]] — ${stamp} 주간 ${parts.join(", ")}.`;
}

function capped(list, cap, renderOne, truncNote) {
  const lines = list.slice(0, cap).map(renderOne);
  if (list.length > cap) lines.push(truncNote(list.length - cap));
  return lines;
}

function render(report, opts) {
  const meta = report.meta || {};
  const baseTs = opts.now || meta.now;
  if (!baseTs)
    die("no timestamp: pass --now <ISO> or provide meta.now in input");
  const week = isoWeek(baseTs);
  const stamp = `${opts.env} ${week}`;
  const sessions = report.sessions || {};
  const prompts = report.prompts || {};
  const inv = report.inventory || {};
  const lifecycle = inv.lifecycle || {};
  const coverageDays = num(meta.coverage && meta.coverage.days);
  const envKo = opts.env === "personal" ? "개인" : "회사";

  const L = [];
  L.push(`# 하네스 건강 스냅샷 — ${stamp}`);
  L.push("");
  L.push(
    `이 문서는 ${envKo}(${opts.env}) 환경의 ${week} 주간 하네스 사용 집계 스냅샷이다.`,
  );
  L.push(
    `표본 — ${stamp} 기준 레코드 ${num(meta.records)}건, 세션 ${num(sessions.count)}개(종결 ${num(sessions.with_end)}), 프롬프트 ${num(prompts.total)}건(커맨드 ${num(prompts.commands)}), 관측 구간 ${coverageDays}일.`,
  );
  if (num(sessions.count) < 5)
    L.push(
      `표본 경고 — ${stamp} 스냅샷은 세션 5개 미만이라 수치는 경향 참고용이다.`,
    );
  L.push(
    "계측 경계 — 헤드리스 실행의 user-slash 커맨드는 skill 레코드를 남기지 않으므로 커맨드 사용이 과소 집계될 수 있다.",
  );
  L.push(
    "프라이버시 경계 — 미발화 후보와 교정 쌍은 프롬프트 원문을 포함하므로 이 스냅샷에서 구조적으로 제외됐다.",
  );
  L.push("");

  L.push(`## 스킬·커맨드 호출`);
  L.push("");
  const skills = report.skills || [];
  if (skills.length === 0) L.push(`${stamp} 주간 스킬 호출 관측이 없다.`);
  else
    L.push(
      ...capped(
        skills,
        15,
        (s) => usageLine(s, stamp),
        (n) => `호출 상위 15종 외 ${n}종은 생략됐다 (전체는 집계 JSON 참조).`,
      ),
    );
  L.push("");

  L.push(`## 에이전트 호출`);
  L.push("");
  const agents = report.agents || [];
  if (agents.length === 0) L.push(`${stamp} 주간 에이전트 호출 관측이 없다.`);
  else
    L.push(
      ...capped(
        agents,
        10,
        (a) => usageLine(a, stamp),
        (n) => `호출 상위 10종 외 ${n}종은 생략됐다 (전체는 집계 JSON 참조).`,
      ),
    );
  L.push("");

  L.push(`## 인벤토리 커버리지`);
  L.push("");
  L.push(
    `설치 인벤토리 분모 — ${stamp} 기준 플러그인 ${num(inv.plugins)}개, 스킬 ${num(inv.skills)}·커맨드 ${num(inv.commands)}·에이전트 ${num(inv.agents)} (분모 출처 ${clean(meta.plugins_dir_source || "unknown")}).`,
  );
  if (num(inv.plugins) <= 1)
    L.push(
      `분모 경고 — 인벤토리가 플러그인 ${num(inv.plugins)}개로 붕괴돼 있어 미사용·커버리지 수치를 신뢰할 수 없다.`,
    );
  L.push(
    `미사용 자산 — ${stamp} 관측에서 미사용 스킬 ${(inv.unused_skills || []).length}개, 미사용 커맨드 ${(inv.unused_commands || []).length}개, 미사용 에이전트 ${(inv.unused_agents || []).length}개.`,
  );
  const unknown = inv.unknown_called || [];
  if (unknown.length > 0)
    L.push(
      `인벤토리 밖 호출 — ${stamp} 에 ${unknown.length}종 관측: ${unknown
        .slice(0, 10)
        .map((n) => `[[${clean(n)}]]`)
        .join(
          ", ",
        )}${unknown.length > 10 ? ` 외 ${unknown.length - 10}종` : ""}.`,
    );
  L.push("");

  L.push(`## 사용 라이프사이클`);
  L.push("");
  const stale = lifecycle.stale || [];
  const archive = lifecycle.archive_candidates || [];
  if (stale.length === 0 && archive.length === 0)
    L.push(`${stamp} 기준 stale·archive 후보가 없다.`);
  L.push(
    ...capped(
      stale,
      10,
      (x) =>
        `[[${clean(x.id)}]] (${clean(x.kind)}) — ${stamp} 기준 마지막 사용 후 ${num(x.idle_days)}일 경과로 stale 후보다.`,
      (n) => `stale 후보 ${n}종 추가 생략 (전체는 집계 JSON 참조).`,
    ),
  );
  L.push(
    ...capped(
      archive,
      10,
      (x) =>
        `[[${clean(x.id)}]] (${clean(x.kind)}) — ${stamp} 기준 마지막 사용 후 ${num(x.idle_days)}일 경과로 archive 후보다.`,
      (n) => `archive 후보 ${n}종 추가 생략 (전체는 집계 JSON 참조).`,
    ),
  );
  L.push("");
  return L.join("\n");
}

function main() {
  const opts = parseArgs(process.argv);
  if (opts.env !== "personal" && opts.env !== "company")
    die("--env personal|company is required (fail-closed: no default)");

  let raw = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => (raw += c));
  process.stdin.on("end", () => {
    if (!raw.trim()) die("empty stdin: pipe observe-report.js --json output");
    let report;
    try {
      report = JSON.parse(raw);
    } catch (e) {
      die(`stdin is not valid JSON: ${e.message}`);
    }
    // 비객체(null/배열/스칼라)는 상류 파이프 실패의 산물 — "레코드 0건" 정상형 스냅샷으로
    // fail-open 되지 않게 여기서 죽인다.
    if (!report || typeof report !== "object" || Array.isArray(report))
      die("stdin must be the aggregate JSON object from observe-report.js");

    // 1차 게이트 — 원문 운반 필드 fail-closed
    if (
      (report.candidates || []).length > 0 ||
      (report.followups || []).length > 0
    )
      die(
        "raw-text carriers present (candidates/followups non-empty) — re-run observe-report.js with --candidates 0 --followups 0",
      );
    const hits = scanForbidden(report, "$", []);
    if (hits.length > 0)
      die(
        `forbidden raw-text field(s) detected: ${hits.slice(0, 5).join(", ")}`,
      );

    const md = render(report, opts);

    // 자기 검사 — 살균·드롭을 우회한 회귀(경로 누출·attr: 주입)까지 코드로 차단
    const leak = md.match(PATH_LEAK_RE);
    if (leak) die(`absolute path leaked into render: ${leak[0]}`);
    if (/^\s*attr:/m.test(md)) die("attr: line leaked into render");

    process.stdout.write(md);
  });
}

main();
