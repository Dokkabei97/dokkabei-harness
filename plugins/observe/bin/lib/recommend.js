// 추천 엔진 결정론 층 — 턴 추출 → BM25 매칭(match.js) → 1차 3유형(missed/tune/orchestrate) 산출 → 노이즈 억제
// → recommendations.jsonl(append-only) 상태 반영. LLM 판정은 여기서 하지 않는다(/observe-report Phase 3~4 몫).
//
// 입력: reader 가 정규화한 v0 모양 레코드(ts 정렬) + 다이제스트(turn_summary) + 매칭 인벤토리(skill·command).
// 턴: 세션별 사람 프롬프트 1개가 턴 하나. 시스템 주입 프롬프트(async 완료 알림·! 모드·백그라운드 에이전트 중단 알림)는
//   턴을 나누지 않고 앞 사람 턴에 붙는다(그 뒤의 스킬/에이전트 호출은 사람 요청의 연장). 확정 = 뒤에 사람 턴이나 session_end 가 있음.
// 유형:
//   missed      — 스킬·에이전트 무동작 확정 턴에서 BM25 top1 ≥ θ 이고 margin(top1-top2) ≥ M 인 자산, 또는 골드 라벨
//                 (그 턴 바로 다음 사람 턴이 그 자산의 슬래시 직접 입력). 근거 세션 2개 미만이면 원오프로 보고 내지 않는다(골드는 예외).
//   tune        — ① 같은 자산의 missed 근거 중 프롬프트 텍스트 근거(bm25·골드 — orchestrate 경유 세션 제외) ≥3 → 프롬프트엔
//                 있고 description 엔 없는 고-IDF 용어를 Use when 추가안 재료로
//                 ② "Use when" 절이 없는 스킬 중 미발화 턴 top-3 에 점수 ≥ θ/2 로 든 것(근거 0 은 사용 데이터와 무관한 정적 lint,
//                 점수 하한이 없으면 bigram 하나 공유로도 근거가 된다). missed 와 같은 원오프 제외(근거 세션 ≥2)를 적용한다.
//                 대상이 missed 후보이기도 하면 별도 항목이 아니라 그 missed 항목의 하위 제안(item.tune)으로 붙는다
//                 (5.3 "같은 대상은 한 번만" — missed 의 처방이 곧 description 튜닝이라 같은 대상이 두 슬롯을 차지하지 않게).
//   orchestrate — 세션 안 스킬·에이전트·커맨드 연쇄 n-gram(3~4) 또는 턴 툴 흐름 n-gram(turn_summary.seq_compact)이
//                 서로 다른 세션 ≥ orchMin(기본 3). 연쇄 원소는 사용자 자산만 — 빌트인 에이전트(Explore·Plan 등)·이름 없는
//                 호출과 인벤토리에서 해석되지 않는 슬래시(/clear·/model 같은 내장 커맨드)는 넣지 않는다. 연쇄 원소를 본문에
//                 단어 경계로 모두 언급하는 기존 오케스트레이터가 있으면 새 하네스 대신 그 오케스트레이터의 missed 로
//                 분기한다(update-over-create). 같은 세션 집합에서 한 칸씩 겹치는 창(A>B>C>D · B>C>D>E)은 한 패턴으로 합친다.
// 노이즈 억제: 표본(사람 프롬프트) < 20 이면 미추천 · 근거는 세션당 1회만 센다(evidence_n = 근거 세션 수)
//   · 유형별 ≤3 · 거절/스누즈는 ID 기준 30일 쿨다운, 그 안에서는 evidence_n 이 거절 당시의 2배 이상일 때만 재노출
//   (거절 직전 created 가 없으면 — 기록되지 않은 실행에서 본 추천 — 2배 비교 없이 시간 쿨다운만 건다).
// recommendations.jsonl 동시 실행: read→decide→append 사이에 잠금이 없어 같은 created 가 중복 append 될 수 있다.
//   줄 단위 O_APPEND 라 줄은 깨지지 않고 stateOf 는 마지막 created 를 쓰므로 상태는 같다 — 중복 created 허용(마지막 우선).
// 원문: 매칭 결과·이벤트에는 원문이 없다(id·점수·세션/턴 키만). tune 용어(프롬프트 bigram)만 원문 파생이라
//   리포트 출력에만 싣고(raw 허용 시) recommendations.jsonl 에는 쓰지 않는다. 근거 턴 원문(evidenceTurns)도 같은 규율 —
//   반환값으로만 넘겨 리포트의 candidates 에 보강하고(Phase 3 판정 입력), 추천 섹션·이벤트에는 넣지 않는다.
// 공변량: skill_type(자산 유형)과 models(근거 턴 모델 분포 — 다이제스트 turn_summary.model, 이름만)을 항목·created 에 함께 싣는다.
// 피드백(Phase 5, 로드맵 5.4): 상태 전이 proposed → accepted | rejected | snoozed | expired.
//   accepted·rejected·snoozed 는 사용자가 ID 별로 명시 응답한 것만 status 이벤트로 append(feedback — observe-report --accept 등).
//   expired 는 쓰는 주체가 없는 파생 상태다(currentStatus): 응답 없이 expireDays 가 지난 제안. 파일은 갱신하지 않고 매번 다시 계산한다.
//   precision(precisionOf) = 유형별 accepted / (accepted + rejected), 분모 < 10 이면 "표본 부족". θ 는 수동 상수(자동 보정은 백로그).
// 반영(git 원장): 커밋 메시지 trailer "Observe-Rec: <id>"(harness:evolve 가 반영 커밋에 붙인다)를 git log 로 결정론 수집한다(gitApplied).
//   trailer 가 있는 추천 = applied — accepted 를 포함하는 상위 상태라 다시 제안하지 않는다. recommendations.jsonl 에는 쓰지 않는다
//   (git 이 원장 — 리포트가 매번 다시 계산). precision 에서는 그 회차를 수락으로 센다(명시 응답이 없어도).
//   효과: 마지막 반영 커밋 전/후 같은 길이 창(effectDays, 경과일이 더 짧으면 그만큼)에서 대상 자산의 "매칭 턴 중 실제 호출 비율"
//   = 호출 턴 / (호출 턴 + missed 근거 턴)을 비교한다. 어느 쪽이든 매칭 턴 < effectMin 이면 "표본 부족". 레포 모드만(--all·--trace 는 git 을 읽지 않는다).
//   "암묵 수락(SKILL.md diff 추측)" 백로그는 이 결정론 방식으로 대체됐다 — diff 를 해석하지 않고 커밋에 남긴 ID 만 믿는다.
const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const P = require('../hooks/_lib/paths');
const { commandOf } = require('../hooks/_lib/writer');
const M = require('./match');

// θ·margin 은 수동 상수(자동 보정은 백로그) — 이 레포 실데이터(미발화 확정 턴 45건) 점수 분포 기준:
// "이어서 진행해"·"좋아 진행해"·"푸시해줘"류 짧은 범용 후속은 top1 ≤6, 짧지만 명백한 요청("커밋 푸시 진행해줘" →
// sync-claude-md)은 top1 ≈11·margin ≈6. 긴 프롬프트는 점수가 커지므로 margin 3 으로 애매한 1·2위 근접을 거른다.
// expireDays: 응답 없는 제안의 만료(파생) · snoozeDays: --snooze 기본 기간 · precisionMin: precision 을 보여 줄 최소 분모
// effectDays: 반영 전후 비교 창(--effect-days) · effectMin: 전후 각 창의 최소 매칭 턴 수 — 전부 수동 상수
const DEFAULTS = { theta: 10, margin: 3, minSample: 20, orchMin: 3, cap: 3, tuneMin: 3, cooldownDays: 30, expireDays: 30, snoozeDays: 7, precisionMin: 10, effectDays: 30, effectMin: 5 };
const TYPES = ['missed', 'tune', 'orchestrate'];
const EVIDENCE_MAX = 20; // 이벤트 한 줄에 싣는 근거 ref 상한 (PIPE_BUF 이하 유지)
const LINE_MAX = 4000;
const SYS_TEXT = /^\s*(?:<task-notification>|<bash-(?:input|stdout|stderr)>|(?:\d+\s+)?background agents?\b[\s\S]{0,400}?\b(?:was|were) stopped\b)/i;
// Claude Code 빌트인 서브에이전트 — 사용자 자산이 아니라 연쇄(하네스 후보) 원소에서 뺀다
const BUILTIN_AGENTS = new Set(['general-purpose', 'explore', 'plan', 'claude-code-guide', 'statusline-setup', 'output-style-setup']);

const sha1 = (s) => crypto.createHash('sha1').update(s).digest('hex');
// ID = sha1(type|target) — 근거 시그니처를 넣으면 근거 하나만 늘어도 새 ID 가 되어 쿨다운이 무력화된다(로드맵 3.3)
const recId = (type, target) => 'rec_' + sha1(`${type}|${target}`).slice(0, 12);
const ref = (t) => `${t.session}#${t.turn || t.ts || '?'}`;
const tailOf = (id) => String(id).toLowerCase().split(':').pop();

// ── 턴 추출 ──────────────────────────────────────────────────────────────────
// sysTurns = 다이제스트가 시스템 주입(prompt_kind ≠ user)으로 표시한 턴 키(session#turn) — 원문이 없는 --all 에서도
//   SYS_TEXT 대신 이것으로 거른다(다이제스트 없는 v0 세션의 시스템 주입은 원문 없이는 못 거른다 → sample.exact=false)
function extractTurns(records, sysTurns) {
  const bySession = new Map();
  for (const r of records) {
    if (!r || !r.session_id) continue; // session 없는 쓰레기 레코드(v0 실측 6줄)는 턴이 아니다
    const sid = r.session_id;
    if (!bySession.has(sid)) bySession.set(sid, { turns: [], cur: null });
    const S = bySession.get(sid);
    if (r.type === 'prompt') {
      const text = String(r.text || '');
      if (SYS_TEXT.test(text) || (sysTurns && r.prompt_id && sysTurns.has(`${sid}#${r.prompt_id}`))) continue; // 시스템 주입 — 앞 사람 턴의 연장
      if (S.cur) S.cur.settled = true;
      const c = r.command ? { is_command: true, command: r.command } : commandOf(text, r.is_command);
      S.cur = { session: sid, turn: r.prompt_id || null, ts: r.ts || null, text, command: c.is_command ? c.command : null, is_command: c.is_command, acts: [], settled: false };
      S.turns.push(S.cur);
    } else if ((r.type === 'skill' || r.type === 'agent') && S.cur) {
      S.cur.acts.push({ kind: r.type, name: r.type === 'skill' ? (r.skill || '(null)') : (r.agent || '(default)') });
    } else if (r.type === 'session_end' && S.cur) {
      S.cur.settled = true;
    }
  }
  return [...bySession.values()].map((S) => S.turns);
}

// ── 인벤토리 이름 해석 ── 정확 일치(소문자) 우선, 없으면 bare 이름의 tail 일치(여럿이면 id 정렬 첫째)
function resolver(docs) {
  const full = new Map();
  const tails = new Map();
  for (const d of [...docs].sort((a, b) => (a.id < b.id ? -1 : 1))) {
    full.set(d.id.toLowerCase(), d);
    if (!tails.has(tailOf(d.id))) tails.set(tailOf(d.id), d);
  }
  return (name) => {
    if (!name) return null;
    const n = String(name).toLowerCase().replace(/^\//, '');
    return full.get(n) || (n.includes(':') ? null : tails.get(n)) || null;
  };
}

// ── recommendations.jsonl ────────────────────────────────────────────────────
const recFile = (root) => P.recommendationsFile(root);
function readEvents(root) {
  const out = [];
  let text = '';
  try { text = fs.readFileSync(recFile(root), 'utf8'); } catch (_) { return out; }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try { const v = JSON.parse(line); if (v && v.id && v.ev) out.push(v); } catch (_) { /* 깨진 줄 무시 */ }
  }
  return out;
}
// 리포트는 저장소를 새로 만들지 않는다 — .tracer 가 있는 레포에서만 append (한 줄씩 O_APPEND, 줄 < PIPE_BUF).
// 쓰기 실패(권한·그 자리에 디렉터리 등)는 리포트를 막지 않는다 — 부수 기록이라 쓴 줄 수와 오류 코드만 돌려준다.
function appendEvents(root, events) {
  if (!events.length || !root || P.isHome(root) || !fs.existsSync(P.tracerDir(root))) return { recorded: 0, error: null };
  let n = 0;
  try {
    for (const e of events) { fs.appendFileSync(recFile(root), JSON.stringify(e) + '\n'); n++; }
  } catch (err) {
    return { recorded: n, error: err.code || String(err.message || err) };
  }
  return { recorded: n, error: null };
}

// 쿨다운 기준 시각이 없는 거절·스누즈 줄(ts·cooldown_until 둘 다 파싱 불가)은 깨진 줄로 본다 — until=NaN 이면 쿨다운이 통째로 빠진다
const brokenStatus = (e) => (e.status === 'rejected' || e.status === 'snoozed') && Number.isNaN(Date.parse(e.cooldown_until)) && Number.isNaN(Date.parse(e.ts));
// 시각을 파싱할 수 없는 created 도 깨진 줄이다 — 만료 시계가 없어 영원히 proposed 로 남는다. 건너뛰면 그 ID 는 앞 created 로
// 돌아가거나(없으면 new) 다음 기록 리포트가 새 created 를 붙여 스스로 낫는다. 코드가 쓰는 created 는 늘 ISO ts 다.
const brokenCreated = (e) => Number.isNaN(Date.parse(e.ts));

// ── git 반영 원장 ─────────────────────────────────────────────────────────────
// HEAD 에서 닿는 커밋 중 Observe-Rec trailer 가 있는 것 → { ok, commits, malformed, byId: Map id → { first, last, commits:[{sha, ts}] } }.
// trailer 해석은 git 자신의 파서(%(trailers:key=…))에 맡긴다 — 메시지 마지막 문단의 trailer 블록만 인정하고 본문 중간의 같은 문자열은
// 세지 않는다. --grep 은 후보 커밋을 좁히는 용도일 뿐이다. 값은 rec_<12 hex> 만 받는다(한 줄에 쉼표·공백으로 여러 개도 허용) —
// 그 밖의 값은 원문일 수 있어 개수(malformed)만 세고 싣지 않는다. 시각은 커밋 시각(%cI).
// git 이 없거나 저장소 밖·커밋 없음·시간 초과면 조용히 ok:false(0건). 읽기만 한다(--no-show-signature: 서명 출력이 stdout 에 섞이지 않게).
const REC_ID = /^rec_[0-9a-f]{12}$/;
function gitApplied(root) {
  const out = { ok: false, commits: 0, malformed: 0, byId: new Map() };
  if (!root) return out;
  let text = '';
  try {
    text = cp.execFileSync('git', ['-C', root, 'log', '--no-show-signature', '--basic-regexp', '--regexp-ignore-case', '--grep=^observe-rec[[:space:]]*:',
      '--format=%x1e%H%x1f%cI%x1f%(trailers:key=Observe-Rec,valueonly)'],
    { encoding: 'utf8', timeout: 5000, maxBuffer: 16 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
  } catch (_) { return out; }
  out.ok = true;
  for (const rec of text.split('\x1e')) {
    const [sha, ts, vals] = rec.split('\x1f');
    if (!/^[0-9a-f]{40}([0-9a-f]{24})?$/.test(sha || '') || Number.isNaN(Date.parse(ts)) || !vals) continue;
    let hit = false;
    for (const v of vals.split(/[\s,]+/).filter(Boolean)) {
      if (!REC_ID.test(v)) { out.malformed++; continue; }
      if (!out.byId.has(v)) out.byId.set(v, { first: null, last: null, commits: [] });
      const a = out.byId.get(v);
      if (!a.commits.some((c) => c.sha === sha)) a.commits.push({ sha, ts }); // 한 커밋에 같은 ID 두 줄이어도 1회
      hit = true;
    }
    if (hit) out.commits++;
  }
  for (const a of out.byId.values()) {
    a.commits.sort((x, y) => Date.parse(x.ts) - Date.parse(y.ts) || (x.sha < y.sha ? -1 : 1));
    a.first = a.commits[0].ts;
    a.last = a.commits[a.commits.length - 1].ts;
  }
  return out;
}

// id → { created(마지막 created), status(그 뒤 파일 순서상 마지막 status), createdAtStatus(status 직전 created), applied? }
// applied(gitApplied().byId — 선택): 그 ID 의 git 반영 기록. 파일 순서와 무관하게 상태를 덮는다(반영 뒤의 created·응답보다 우선).
function stateOf(events, applied) {
  const st = new Map();
  for (const e of events) {
    if (!st.has(e.id)) st.set(e.id, { created: null, status: null, createdAtStatus: null });
    const s = st.get(e.id);
    if (e.ev === 'created') { if (!brokenCreated(e)) { s.created = e; s.status = null; } }
    else if (e.ev === 'status') {
      if (brokenStatus(e)) continue;
      s.status = e; s.createdAtStatus = s.created;
    }
  }
  if (applied) for (const [id, a] of applied) if (st.has(id)) st.get(id).applied = a;
  return st;
}

// 현재 상태 — stateOf 한 항목 → 'applied' | 'proposed' | 'accepted' | 'rejected' | 'snoozed' | 'expired' | null(기록 없음).
// applied = git 반영(stateOf 에 applied 를 넘긴 경우만) — 다른 상태보다 우선한다.
// expired = 마지막 created 뒤 응답 없이 expireDays 경과(파생, 이벤트 없음). 쿨다운 경과 여부는 analyze 가 따로 본다.
function currentStatus(s, nowMs, params) {
  const p = { ...DEFAULTS, ...(params || {}) };
  if (!s) return null;
  if (s.applied) return 'applied';
  if (s.status) return s.status.status;
  if (!s.created) return null;
  const t = Date.parse(s.created.ts);
  return Number.isFinite(t) && nowMs - t >= p.expireDays * 86400000 ? 'expired' : 'proposed';
}

// 유형별 precision = accepted / (accepted + rejected). 세는 단위는 제안 회차(created 하나 ~ 같은 ID 의 다음 created 전)의
// 마지막 응답이다 — 같은 회차의 번복은 마지막 것만, 재노출(새 created) 뒤 응답은 새 회차로 센다. snoozed·무응답·만료는 분모 밖.
// 회차는 거절·보류의 쿨다운이 끝난 뒤의 응답에서도 나뉜다 — 쿨다운 경과는 analyze 가 재노출하는 조건이라, 그 뒤 응답은 기록 리포트가
// created 를 끼웠든(기록 실행) 안 끼웠든(--window·--no-record 실행이나 CLI 직접 응답) 같은 새 회차로 센다(앞 회차의 거절을 덮지 않게).
// 쿨다운 안의 근거 2배 재노출은 시각으로 가려지지 않으니 created 로만 나뉜다 — 기록 실행은 리포트가, 미기록 실행에서 본 것은 feedback 이
// 응답 직전에 created(source:feedback)를 쓴다. 그래서 사용자에게 보인 재노출에 대한 응답은 어느 실행에서든 새 회차다.
// 분모 < precisionMin 이면 값 대신 "표본 부족"(로드맵 5.4 — 리포트당 유형별 ≤3 이라 분모가 몇 달 한 자릿수에 머문다).
// applied([{id, type, target, ts}] — 선택): git 반영을 그 시각의 수락 응답으로 끼운다(withApplied). 명시 응답 없이 반영만 있어도
// 그 회차는 수락이다. 유형별 applied = git 반영으로 닫힌 회차 수(accepted 에 포함).
function precisionOf(events, params, applied) {
  const p = { ...DEFAULTS, ...(params || {}) };
  const acc = {};
  for (const t of TYPES) acc[t] = { accepted: 0, rejected: 0, applied: 0 };
  const cur = new Map(); // id → { type, last, until(마지막 거절·보류의 쿨다운 끝 ms) }
  const close = (c) => {
    if (!c || !acc[c.type]) return;
    if (c.last === 'applied') { acc[c.type].accepted++; acc[c.type].applied++; }
    else if (c.last === 'accepted' || c.last === 'rejected') acc[c.type][c.last]++;
  };
  for (const e of withApplied(events || [], applied || [])) {
    if (e.ev === 'created') { if (!brokenCreated(e)) { close(cur.get(e.id)); cur.set(e.id, { type: e.type, last: null, until: NaN }); } }
    else if (e.ev === 'status' && cur.has(e.id) && !brokenStatus(e)) {
      let c = cur.get(e.id);
      if (Date.parse(e.ts) >= c.until) { close(c); c = { type: c.type, last: null, until: NaN }; cur.set(e.id, c); }
      c.last = e.status;
      // 쿨다운 끝 = analyze·feedback 과 같은 기준(cooldown_until, 없으면 ts + cooldownDays)
      c.until = e.status === 'rejected' || e.status === 'snoozed' ? Date.parse(e.cooldown_until) || Date.parse(e.ts) + p.cooldownDays * 86400000 : NaN;
    }
  }
  for (const c of cur.values()) close(c);
  const out = {};
  for (const t of TYPES) {
    const n = acc[t].accepted + acc[t].rejected;
    const okN = n >= p.precisionMin;
    out[t] = { ...acc[t], n, min: p.precisionMin, precision: okN ? Math.round((acc[t].accepted / n) * 1000) / 1000 : null, status: okN ? 'ok' : '표본 부족' };
  }
  return out;
}

// git 반영을 가상 이벤트(source git, 파일에는 쓰지 않음)로 이벤트열에 끼운다 — 커밋 시각 순 자리, 단 그 ID 의 첫 created 보다
// 앞이면 그 바로 뒤(반영이 제안보다 먼저 기록된 경우에도 그 회차를 닫게). created 가 아예 없는 ID 는 유형을 아는 경우만
// (이번 후보에서 해석된 ID) 가상 created 를 함께 끼워 회차 하나로 센다.
function withApplied(events, applied) {
  if (!applied.length) return events;
  const out = [...events];
  for (const a of applied) {
    if (!a.type) continue;
    const t = Date.parse(a.ts);
    let at = out.findIndex((e) => Date.parse(e.ts) > t);
    if (at < 0) at = out.length;
    const first = out.findIndex((e) => e.ev === 'created' && e.id === a.id && !brokenCreated(e));
    const ins = [];
    if (first < 0) ins.push({ ev: 'created', id: a.id, type: a.type, target: a.target, ts: a.ts, source: 'git' });
    else if (at <= first) at = first + 1;
    ins.push({ ev: 'status', id: a.id, type: a.type, target: a.target, status: 'applied', ts: a.ts, source: 'git' });
    out.splice(at, 0, ...ins);
  }
  return out;
}

// 명시 피드백 — decisions: [{ id, status: accepted|rejected|snoozed }]. 사용자가 ID 별로 답한 것만 status 이벤트로 append 한다.
// 전부 먼저 검증하고(.tracer 의 recommendations.jsonl 에 created 가 있는 ID 만) 하나라도 틀리면 아무것도 쓰지 않는다.
// 현재 상태와 같은 응답(이미 수락된 것을 다시 수락 등)은 쓰지 않고 unchanged 로 돌려준다 — 단 거절·보류는 쿨다운이 아직 살아 있을
// 때만이다(경과 뒤 같은 응답 = 새 쿨다운이자 precision 의 새 회차. 기록하는 리포트가 끼지 않아 created 가 새로 안 붙었어도 재거절이 사라지지 않게).
// 쿨다운 안의 재노출(근거 2배): 사용자에게 보인 재노출에 대한 응답은 항상 새 회차다. CLI 는 근거 수를 모르므로 Phase 6 이 보여 준
// 항목의 evidence_n 을 함께 넘긴다(d.evidence_n — CLI 의 <id>@<n>). 마지막 status 가 쿨다운 중인 거절·보류이고 n ≥ 2×(거절 직전
// created 의 evidence_n)이면 analyze 와 같은 재노출 판정이라, 기록 실행이 썼을 created(resurfaced)를 status 바로 앞에 먼저 append 한다
// — 기록·미기록(--window·--no-record·임계 오버라이드) 실행이 같은 이벤트열·같은 precision 이 된다. 조건 미달이면(보일 수 없던 재노출)
// invalid. 이미 새 회차인 경우(기록 실행의 created 가 status 뒤에 있음·쿨다운 경과)는 n 을 무시한다. n 없이 쿨다운 중 다른 응답(거절 뒤
// 보류 등)은 사용자의 번복으로 보고 그대로 쓴다 — 마지막 명시 응답이 이기고, 보류면 쿨다운도 보류 기간으로 바뀐다.
// 쿨다운: rejected = cooldownDays, snoozed = snoozeDays — cooldown_until 로 명시해 analyze·pre-commit 이 같은 기준을 읽는다. 원문은 없다(id·유형·대상·시각).
const FEEDBACK = new Set(['accepted', 'rejected', 'snoozed']);
function feedback(root, decisions, nowMs, params) {
  const p = { ...DEFAULTS, ...(params || {}) };
  if (!root || P.isHome(root) || !fs.existsSync(recFile(root))) return { error: 'no_recommendations', applied: [] };
  const state = stateOf(readEvents(root));
  const seen = new Map();
  const shownN = new Map(); // id → 보여 준 항목의 evidence_n (재노출 판정용)
  const bad = [];
  for (const d of decisions) {
    if (!FEEDBACK.has(d.status)) bad.push(`${d.id}: 알 수 없는 응답 ${d.status}`);
    else if (!(state.get(d.id) || {}).created) bad.push(`${d.id}: recommendations.jsonl 에 없는 ID`);
    else if (seen.has(d.id) && seen.get(d.id) !== d.status) bad.push(`${d.id}: 한 번에 서로 다른 응답(${seen.get(d.id)}·${d.status})`);
    else if (d.evidence_n !== undefined && !(Number.isInteger(d.evidence_n) && d.evidence_n > 0)) bad.push(`${d.id}: @ 뒤 근거 수가 양의 정수가 아니다`);
    else if (d.evidence_n !== undefined) shownN.set(d.id, d.evidence_n);
    seen.set(d.id, d.status);
  }
  // 쿨다운 끝 = analyze 와 같은 기준(cooldown_until, 없으면 ts + cooldownDays)
  const untilOf = (st) => Date.parse(st.cooldown_until) || (Date.parse(st.ts) + p.cooldownDays * 86400000);
  const reopen = new Map(); // id → 새 회차를 여는 근거 수 (쿨다운 안 2배 재노출)
  for (const [id, n] of shownN) {
    const s = state.get(id);
    if (!s.status || (s.status.status !== 'rejected' && s.status.status !== 'snoozed') || nowMs >= untilOf(s.status)) continue;
    const prevN = (s.createdAtStatus && s.createdAtStatus.evidence_n) || 0;
    if (!prevN || n < 2 * prevN) bad.push(`${id}: 쿨다운 중이고 근거 ${n} 이 재노출 조건(${s.status.status} 당시 ${prevN || '?'} 의 2배) 미달`);
    else reopen.set(id, n);
  }
  if (bad.length) return { error: 'invalid', detail: bad, applied: [] };
  const ts = new Date(nowMs).toISOString();
  const applied = [];
  const events = [];
  for (const [id, status] of seen) {
    const s = state.get(id);
    const base = { id, type: s.created.type, target: s.created.target, status };
    const n = reopen.get(id);
    // 재노출 회차 — 기록 실행이 썼을 created 를 응답 앞에 끼운다(새 회차라 같은 응답도 unchanged 가 아니다)
    if (n !== undefined) events.push({ ev: 'created', id, type: base.type, target: base.target, evidence_n: n, resurfaced_from: s.status.status, ts, source: 'feedback' });
    const live = !s.status || (status !== 'rejected' && status !== 'snoozed') || nowMs < untilOf(s.status);
    if (n === undefined && currentStatus(s, nowMs, p) === status && live) { applied.push({ ...base, unchanged: true }); continue; }
    const days = status === 'rejected' ? p.cooldownDays : status === 'snoozed' ? p.snoozeDays : 0;
    const ev = { ev: 'status', ...base, ts, ...(days ? { cooldown_until: new Date(nowMs + days * 86400000).toISOString() } : {}), source: 'explicit' };
    events.push(ev);
    applied.push({ ...base, ...(n !== undefined ? { reopened: true } : {}), ...(ev.cooldown_until ? { cooldown_until: ev.cooldown_until } : {}) });
  }
  const w = appendEvents(root, events);
  return { error: w.error, applied, recorded: w.recorded };
}

// ── 본체 ─────────────────────────────────────────────────────────────────────
// args: { records, digests, items, events, applied(gitApplied 결과 — null 이면 git 을 읽지 않는 실행), raw(원문 사용 가능),
//   showTerms(원문 파생 tune 용어 출력), listLimit(matches.turns 출력 상한), now(ms), params }
function analyze(args) {
  const p = { ...DEFAULTS, ...(args.params || {}) };
  const nowMs = args.now;
  const items = (args.items || []).filter((i) => i.kind === 'skill' || i.kind === 'command');
  const index = M.buildIndex(items);
  const resolve = resolver(index.docs);
  const docById = new Map(index.docs.map((d) => [d.id, d]));
  const sysTurns = new Set();
  for (const d of args.digests || []) if (d.kind === 'turn_summary' && d.turn && d.prompt_kind && d.prompt_kind !== 'user') sysTurns.add(`${d.session}#${d.turn}`);
  const sessions = extractTurns(args.records || [], sysTurns);
  const modelOf = new Map();
  for (const d of args.digests || []) if (d.kind === 'turn_summary' && d.turn) modelOf.set(`${d.session}#${d.turn}`, d.model || null);

  // ① 매칭 + 골드
  const scored = []; // 원문 있는 미발화 확정 턴
  const gold = { n: 0, hits_top3: 0, unresolved: 0 };
  const humanPrompts = sessions.reduce((n, ts) => n + ts.length, 0);
  for (const turns of sessions) {
    for (let i = 0; i < turns.length; i++) {
      const t = turns[i];
      if (t.is_command || t.acts.length || !t.settled) continue;
      const next = turns[i + 1];
      let g = null;
      if (next && next.is_command && next.command) {
        const d = resolve(next.command);
        if (d) g = d.id; else gold.unresolved++;
      }
      if (!args.raw || !t.text.trim()) continue;
      const ranked = M.search(index, t.text);
      const top3 = ranked.slice(0, 3).map((x) => ({ id: x.id, score: x.score, type: docById.get(x.id).type }));
      const margin = top3.length ? Math.round((top3[0].score - (top3[1] ? top3[1].score : 0)) * 1000) / 1000 : 0;
      const e = { t, top3, margin, gold: g };
      scored.push(e);
      if (g) {
        gold.n++;
        if (top3.some((x) => x.id === g)) gold.hits_top3++;
      }
    }
  }

  // ② missed
  const missed = new Map(); // target → {sessions:Set, refs[], gold, top1, margin, via}
  const addEv = (map, target, t, extra) => {
    if (!map.has(target)) map.set(target, { sessions: new Set(), refs: [], gold: 0, top1: 0, margin: 0, ...extra });
    const m = map.get(target);
    if (m.sessions.has(t.session)) return m; // 세션당 1회
    m.sessions.add(t.session);
    m.refs.push(ref(t));
    return m;
  };
  for (const s of scored) {
    const top = s.top3[0];
    const pass = top && top.score >= p.theta && s.margin >= p.margin;
    if (pass) {
      const m = addEv(missed, top.id, s.t, { via: 'bm25' });
      m.top1 = Math.max(m.top1, top.score);
      m.margin = Math.max(m.margin, s.margin);
    }
    if (s.gold) {
      const m = addEv(missed, s.gold, s.t, { via: 'gold' });
      (m.goldSessions = m.goldSessions || new Set()).add(s.t.session); // 골드도 세션당 1회
      m.gold = m.goldSessions.size;
    }
  }

  // ③ orchestrate (연쇄 + 툴 흐름 n-gram) — 오케스트레이터 포함 시 missed 로 분기
  const grams = (seq, sizes) => {
    const out = [];
    for (const n of sizes) for (let i = 0; i + n <= seq.length; i++) {
      const g = seq.slice(i, i + n);
      if (new Set(g.map((x) => x.k)).size >= 2) out.push({ key: g.map((x) => x.k).join('>'), at: g[0].t, n });
    }
    return out;
  };
  const chainMap = new Map();
  const flowMap = new Map();
  for (const turns of sessions) {
    const seq = [];
    for (const t of turns) {
      // 커맨드는 인벤토리에서 해석될 때만(내장 /clear·/model 반복은 하네스 후보가 아니다), 에이전트는 빌트인·이름 없는 호출 제외
      if (t.is_command && t.command && resolve(t.command)) seq.push({ k: t.command.toLowerCase(), t });
      for (const a of t.acts) {
        const k = String(a.name).toLowerCase();
        if (k.startsWith('(') || (a.kind === 'agent' && BUILTIN_AGENTS.has(k))) continue;
        seq.push({ k, t });
      }
    }
    const collapsed = seq.filter((x, i) => i === 0 || x.k !== seq[i - 1].k); // 연속 반복은 한 원소(reviewer×3 → reviewer)
    for (const g of grams(collapsed, [3, 4])) addEv(chainMap, g.key, g.at, { n: g.n });
  }
  for (const d of args.digests || []) {
    if (d.kind !== 'turn_summary' || (d.prompt_kind && d.prompt_kind !== 'user')) continue;
    const runs = String((d.tools && d.tools.seq_compact) || '').split('>').filter((x) => x && !x.startsWith('…'))
      .map((x) => x.replace(/\d+$/, ''));
    const t = { session: d.session, turn: d.turn, ts: d.ts_start };
    for (const g of grams(runs.map((k) => ({ k, t })), [3, 4])) addEv(flowMap, g.key, g.at, { n: g.n });
  }
  const qualified = (map) => [...map.entries()].filter(([, v]) => v.sessions.size >= p.orchMin);
  // 같은 근거 수의 4-gram 에 포함되는 3-gram 은 중복이라 뺀다
  const unsubsumed = (list) => list.filter(([k, v]) => v.n !== 3 ||
    !list.some(([k2, v2]) => v2.n === 4 && v2.sessions.size === v.sessions.size && `>${k2}>`.includes(`>${k}>`)));
  // 같은 세션 집합에서 한 칸씩 겹치는 창(R>E>B>R · E>B>R>E)은 긴 시퀀스 하나의 조각이라 한 패턴(R>E>B>R>E)으로 합친다
  const mergeOverlap = (list) => {
    const arr = list.map(([k, v]) => ({ els: k.split('>'), v, sig: [...v.sessions].sort().join('\n') }));
    for (let again = true; again;) {
      again = false;
      for (const a of arr) {
        const b = arr.find((x) => x !== a && x.sig === a.sig &&
          a.els.slice(-(x.els.length - 1)).join('>') === x.els.slice(0, -1).join('>'));
        if (b) { a.els = a.els.concat(b.els.slice(-1)); arr.splice(arr.indexOf(b), 1); again = true; break; }
      }
    }
    return arr.map((x) => [x.els.join('>'), { ...x.v, n: x.els.length }]);
  };
  // 단어 경계 일치 — substring 이면 "explores…plans" 같은 무관한 문장이 연쇄 원소를 "언급"한 것으로 잡힌다
  const mentions = (body, name) => new RegExp(`(?<![\\w-])${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\w-])`).test(body);
  const orchestrate = new Map();
  const orchDocs = index.docs.filter((d) => d.type === 'orchestrator' && d.body);
  for (const [k, v] of mergeOverlap(unsubsumed(qualified(chainMap)))) {
    const elems = k.split('>').map(tailOf);
    const host = orchDocs.find((d) => elems.every((e) => mentions(d.body, e)));
    if (host) {
      const m = missed.get(host.id) || { sessions: new Set(), refs: [], gold: 0, top1: 0, margin: 0, via: 'orchestrate' };
      // tune 근거는 프롬프트 텍스트 근거(bm25·골드)만 — orchestrate 경유 세션은 스킬이 호출된 턴이라 description 괴리 신호가 아니다
      if (!m.textRefs) m.textRefs = [...m.refs];
      for (const [i, s] of [...v.sessions].entries()) if (!m.sessions.has(s)) { m.sessions.add(s); m.refs.push(v.refs[i]); }
      if (!missed.has(host.id)) missed.set(host.id, m);
      m.chain = k;
    } else orchestrate.set(`chain:${k}`, { ...v, source: 'chain' });
  }
  for (const [k, v] of mergeOverlap(unsubsumed(qualified(flowMap)))) orchestrate.set(`flow:${k}`, { ...v, source: 'flow' });

  // ④ tune
  const tune = new Map();
  const promptDf = new Map(); // 프롬프트 코퍼스 df (고-IDF 용어 판정)
  for (const s of scored) for (const tok of new Set(M.tokenize(s.t.text))) promptDf.set(tok, (promptDf.get(tok) || 0) + 1);
  const termsFor = (target, refs) => {
    const d = docById.get(target);
    const own = new Set(Object.values(d.fields).flat());
    const cnt = new Map();
    for (const s of scored) if (refs.has(ref(s.t))) for (const tok of new Set(M.tokenize(s.t.text))) if (!own.has(tok)) cnt.set(tok, (cnt.get(tok) || 0) + 1);
    // 고-IDF: 근거 턴 ≥2 에 나오고, 그 토큰이 나온 프롬프트의 절반 이상이 이 자산의 근거 턴(집중도) — "는데"·"진행" 같은
    // 범용 bigram 은 전체 프롬프트에 퍼져 있어 걸러진다. 순서: 집중도 → 근거 턴 수 → 코퍼스 희소도 → 사전순.
    return [...cnt.entries()].filter(([tok, c]) => c >= 2 && tok.length >= 2 && c / (promptDf.get(tok) || c) >= 0.5)
      .sort((a, b) => b[1] / promptDf.get(b[0]) - a[1] / promptDf.get(a[0]) || b[1] - a[1] || promptDf.get(a[0]) - promptDf.get(b[0]) || (a[0] < b[0] ? -1 : 1))
      .slice(0, 5).map(([tok]) => tok);
  };
  for (const [target, m] of missed) {
    const tr = m.textRefs || m.refs; // 프롬프트 텍스트 근거만(세션당 1 ref) — orchestrate 경유 세션 제외
    if (tr.length < p.tuneMin || !docById.has(target)) continue;
    tune.set(target, { sessions: new Set(tr.map((r) => r.slice(0, r.indexOf('#')))), refs: tr, reason: 'missed', missed_n: tr.length, terms: args.raw && args.showTerms ? termsFor(target, new Set(tr)) : null });
  }
  for (const s of scored) for (const x of s.top3) {
    const d = docById.get(x.id);
    if (d.kind !== 'skill' || d.has_use_when || x.score < p.theta / 2 || (tune.has(x.id) && tune.get(x.id).reason === 'missed')) continue;
    addEv(tune, x.id, s.t, { reason: 'no_use_when', missed_n: missed.has(x.id) ? missed.get(x.id).sessions.size : 0, terms: null });
  }

  // ⑤ 후보 목록 → 노이즈 억제 → 이벤트
  const cands = [];
  for (const [target, m] of missed) {
    if (m.sessions.size < 2 && !m.gold) continue; // 원오프 제외 (골드는 사용자가 직접 확인해 준 근거라 예외)
    // 같은 대상은 한 번만 — 이 대상의 tune 은 별도 항목 대신 이 missed 항목의 하위 제안(item.tune)으로 싣는다
    const tn = tune.get(target);
    if (tn) tune.delete(target);
    cands.push({ type: 'missed', target, m, strength: [m.gold, m.sessions.size, m.top1],
      signal: { bm25_top1: m.top1 || null, margin: m.margin || null, gold: m.gold, via: m.via, ...(m.chain ? { chain: m.chain } : {}) },
      sub: tn ? { reason: tn.reason, missed_n: tn.missed_n, ...(tn.terms ? { terms: tn.terms } : {}) } : null });
  }
  for (const [target, m] of tune) {
    if (m.reason === 'no_use_when' && m.sessions.size < 2) continue; // 원오프 제외 — missed 와 같은 규칙
    cands.push({ type: 'tune', target, m, strength: [m.reason === 'missed' ? 1 : 0, m.sessions.size, 0],
      signal: { reason: m.reason, missed_n: m.missed_n }, terms: m.terms });
  }
  for (const [target, m] of orchestrate)
    cands.push({ type: 'orchestrate', target, m, strength: [m.sessions.size, m.n, 0], signal: { source: m.source, n: m.n } });

  const appliedById = (args.applied && args.applied.byId) || new Map();
  const state = stateOf(args.events || [], appliedById);

  // ⑥ git 반영(applied) — 대상은 recommendations.jsonl 의 created 우선, 없으면 이번 후보(ID = sha1(type|target) 이라 같은 대상이면
  // 같은 ID). 둘 다 없으면 모르는 ID(unknown — 다른 레포의 ID·오타·후보에서 사라진 미기록 추천)로 따로 센다.
  // 효과: 마지막 반영 커밋 C 기준 [C-L, C) vs [C, C+L), L = min(effectDays, 경과일). 매칭 턴 = 사람 턴(커맨드 턴 제외, 확정 턴)
  // 중 대상 스킬을 호출한 턴(fired) 또는 대상이 missed 근거가 되는 미발화 턴(top1=대상·θ·margin 통과, 또는 골드). 원문이 있어야 채점된다.
  const candById = new Map(cands.map((c) => [recId(c.type, c.target), c]));
  const round3 = (x) => Math.round(x * 1000) / 1000;
  const effectOf = (type, target, C) => {
    if (type === 'orchestrate' || !docById.has(target)) return { status: '측정 대상 아님' };
    if (!args.raw) return { status: '측정 불가' };
    const L = Math.max(0, Math.min(p.effectDays * 86400000, nowMs - C));
    const before = { fired: 0, missed: 0 };
    const after = { fired: 0, missed: 0 };
    const side = (ts) => {
      const t = Date.parse(ts);
      if (!Number.isFinite(t) || !L) return null;
      return t >= C - L && t < C ? before : t >= C && t < C + L ? after : null;
    };
    for (const turns of sessions) for (const t of turns) {
      if (t.is_command || !t.settled || !t.acts.some((a) => a.kind === 'skill' && (resolve(a.name) || {}).id === target)) continue;
      const sd = side(t.ts);
      if (sd) sd.fired++;
    }
    for (const s of scored) {
      const top = s.top3[0];
      if (!((top && top.id === target && top.score >= p.theta && s.margin >= p.margin) || s.gold === target)) continue;
      const sd = side(s.t.ts);
      if (sd) sd.missed++;
    }
    const fin = (x, from, to) => {
      const n = x.fired + x.missed;
      return { from: new Date(from).toISOString(), to: new Date(to).toISOString(), fired: x.fired, missed: x.missed, n, rate: n ? round3(x.fired / n) : null };
    };
    const b = fin(before, C - L, C);
    const a = fin(after, C, C + L);
    const ok = b.n >= p.effectMin && a.n >= p.effectMin;
    return { metric: 'fire_rate', window_days: Math.round((L / 86400000) * 10) / 10, before: b, after: a, min: p.effectMin, delta: ok ? round3(a.rate - b.rate) : null, status: ok ? 'ok' : '표본 부족' };
  };
  const appliedItems = [];
  const appliedUnknown = [];
  const appliedPrec = []; // precisionOf 입력 — 유형을 아는 반영만
  for (const [id, a] of [...appliedById].sort((x, y) => Date.parse(x[1].first) - Date.parse(y[1].first) || (x[0] < y[0] ? -1 : 1))) {
    const s = state.get(id);
    const c = (s && s.created) || candById.get(id);
    if (!c) { appliedUnknown.push(id); continue; }
    appliedPrec.push({ id, type: c.type, target: c.target, ts: a.first });
    appliedItems.push({ id, type: c.type, target: c.target, applied_at: a.first, commits: a.commits.map((x) => ({ sha: x.sha, ts: x.ts })),
      effect: effectOf(c.type, c.target, Date.parse(a.last)) });
  }
  // exact=false: 원문이 없어(--all) 시스템 주입을 다이제스트 prompt_kind 로만 거른 값 — 다이제스트 없는 세션 몫만큼 상한값이다
  const sample = { human_prompts: humanPrompts, min: p.minSample, ok: humanPrompts >= p.minSample, exact: !!args.raw };
  const items_out = [];
  const suppressed = [];
  const append = [];
  const ts = new Date(nowMs).toISOString();
  for (const type of TYPES) {
    const list = cands.filter((c) => c.type === type)
      .sort((a, b) => b.strength[0] - a.strength[0] || b.strength[1] - a.strength[1] || b.strength[2] - a.strength[2] || (a.target < b.target ? -1 : 1));
    let shown = 0;
    for (const c of list) {
      const id = recId(c.type, c.target);
      const evidence_n = c.m.sessions.size;
      const refsSorted = [...c.m.refs].sort();
      const evidence_sig = sha1(refsSorted.join('\n')).slice(0, 12);
      const s = state.get(id);
      let status = s && s.created ? 'proposed' : 'new';
      let resurfacedFrom = null; // resurfaced 의 이유 — rejected·snoozed(쿨다운 경과·2배) 또는 expired(무응답 만료 뒤 재제안)
      if (!sample.ok) { suppressed.push({ id, type, target: c.target, reason: 'sample', evidence_n }); continue; }
      // git 반영(커밋 trailer)이 있으면 응답·쿨다운과 무관하게 다시 내지 않는다(accepted 를 포함하는 상위 상태)
      if (appliedById.has(id)) { suppressed.push({ id, type, target: c.target, reason: 'applied', evidence_n }); continue; }
      if (s && s.status) {
        const st = s.status.status;
        if (st === 'accepted') { suppressed.push({ id, type, target: c.target, reason: 'accepted', evidence_n }); continue; }
        if (st === 'rejected' || st === 'snoozed') {
          const until = Date.parse(s.status.cooldown_until) || (Date.parse(s.status.ts) + p.cooldownDays * 86400000);
          const prevN = (s.createdAtStatus && s.createdAtStatus.evidence_n) || 0;
          // prevN 0 = 거절 직전 created 없음(기록 안 된 실행에서 본 추천) — 2배 비교 대상이 없으니 시간 쿨다운만
          if (nowMs < until && (!prevN || evidence_n < 2 * prevN)) {
            suppressed.push({ id, type, target: c.target, reason: 'cooldown', evidence_n, prev_evidence_n: prevN, cooldown_until: new Date(until).toISOString() });
            continue;
          }
          status = 'resurfaced';
          resurfacedFrom = st;
        }
      } else if (currentStatus(s, nowMs, p) === 'expired') {
        // 응답 없이 만료된 제안이 아직 후보 — 다시 제안한다(created 를 새로 append 해 만료 시계를 되돌린다)
        status = 'resurfaced';
        resurfacedFrom = 'expired';
      }
      if (shown >= p.cap) { suppressed.push({ id, type, target: c.target, reason: 'cap', evidence_n }); continue; }
      shown++;
      const d = docById.get(c.target);
      const evidence = refsSorted.slice(-EVIDENCE_MAX); // 근거 턴 ref(session#turn, 원문 없음) — created 이벤트와 같은 값
      const models = {}; // 근거 턴 모델 분포(이름만) — 다이제스트 없는 턴은 세지 않는다
      for (const r of refsSorted) { const mo = modelOf.get(r); if (mo) models[mo] = (models[mo] || 0) + 1; }
      const out = { id, type, target: c.target, status, evidence_n, evidence_sig, evidence, signal: c.signal, skill_type: d ? d.type : null, models };
      if (resurfacedFrom) out.resurfaced_from = resurfacedFrom;
      if (c.terms) out.terms = c.terms;
      if (c.sub) out.tune = c.sub;
      items_out.push(out);
      if (status === 'new' || status === 'resurfaced' || s.created.evidence_sig !== evidence_sig) {
        const ev = { ev: 'created', id, type, target: c.target, evidence: [...evidence], evidence_sig, evidence_n, signal: c.signal, skill_type: out.skill_type, models, ts };
        while (JSON.stringify(ev).length > LINE_MAX && ev.evidence.length) ev.evidence.shift();
        append.push(ev);
      }
    }
  }

  const byType = (t) => items_out.filter((x) => x.type === t).length;
  const sourceCount = {};
  for (const d of index.docs) sourceCount[d.source || 'plugins'] = (sourceCount[d.source || 'plugins'] || 0) + 1;
  // 턴 목록 = 최근 listLimit 개 + 노출 항목 근거 턴(상한 밖이어도) — Phase 3 가 근거마다 랭킹·원문을 찾을 수 있게
  const evRefs = new Set(items_out.flatMap((x) => x.evidence));
  const listed = args.listLimit > 0 ? scored.filter((s, i) => i >= scored.length - args.listLimit || evRefs.has(ref(s.t))) : [];
  const turnsOut = listed.reverse().map((s) => ({
    session: s.t.session, turn: s.t.turn, ts: s.t.ts, top3: s.top3, margin: s.margin, gold: s.gold,
    model: modelOf.get(ref(s.t)) ?? null,
  }));
  return {
    matches: {
      inventory: {
        docs: index.N, skills: index.docs.filter((d) => d.kind === 'skill').length, commands: index.docs.filter((d) => d.kind === 'command').length,
        by_source: sourceCount, no_use_when: index.docs.filter((d) => d.kind === 'skill' && !d.has_use_when).length,
        by_type: index.docs.reduce((m, d) => ((m[d.type] = (m[d.type] || 0) + 1), m), {}),
      },
      params: { theta: p.theta, margin: p.margin, k1: 1.2, b: 0.75, weights: M.W, phrase_bonus: M.PHRASE_BONUS },
      raw: !!args.raw,
      turns_scored: scored.length,
      gold: { ...gold, rate: gold.n >= 10 ? Math.round((gold.hits_top3 / gold.n) * 1000) / 1000 : null, status: gold.n >= 10 ? 'ok' : '측정불가' },
      turns: turnsOut,
    },
    recommendations: {
      sample,
      params: { min_sample: p.minSample, cap: p.cap, orch_min: p.orchMin, tune_min: p.tuneMin, cooldown_days: p.cooldownDays, expire_days: p.expireDays, snooze_days: p.snoozeDays },
      // 유형별 precision(명시 피드백 + git 반영 기준) — 이벤트를 읽지 않는 실행(--all·--trace)은 null
      precision: args.events ? precisionOf(args.events, p, appliedPrec) : null,
      candidates: { missed: cands.filter((c) => c.type === 'missed').length, tune: cands.filter((c) => c.type === 'tune').length, orchestrate: cands.filter((c) => c.type === 'orchestrate').length },
      items: items_out,
      counts: { missed: byType('missed'), tune: byType('tune'), orchestrate: byType('orchestrate') },
      suppressed,
      // git 반영(Observe-Rec trailer) — git 을 읽지 않는 실행(--all·--trace)은 null, git 없음·실패는 available:false(0건)
      applied: args.applied ? {
        source: 'git', available: !!args.applied.ok, commits: args.applied.commits, malformed: args.applied.malformed,
        params: { effect_days: p.effectDays, effect_min: p.effectMin }, items: appliedItems, unknown: appliedUnknown,
      } : null,
      recorded: 0,
    },
    append,
    // 노출 항목 근거 턴 중 채점 턴(미발화 확정 턴)의 원문 — 리포트 candidates 보강용(raw·목록 허용 시만, 추천 섹션엔 넣지 않음)
    evidenceTurns: args.raw && args.listLimit > 0
      ? scored.filter((s) => evRefs.has(ref(s.t))).map((s) => ({ ts: s.t.ts, session_id: s.t.session, turn: s.t.turn, text: s.t.text.slice(0, 200) }))
      : [],
  };
}

module.exports = { analyze, extractTurns, readEvents, appendEvents, stateOf, currentStatus, precisionOf, feedback, gitApplied, recId, recFile, DEFAULTS, SYS_TEXT };
