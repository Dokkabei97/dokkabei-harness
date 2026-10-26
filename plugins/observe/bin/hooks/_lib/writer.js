// 공통 writer — opt-in 게이트 + v0 레코드 → 스키마 v1 이벤트 변환 + 원문 분리·레드액션 + append.
// 모든 기록 경로(훅 5종·deferred-why 자식·observe-migrate)가 이 파일의 emit() 하나로 쓴다 —
// 훅은 기존 v0 모양 레코드({ts, session_id, type, ...})를 만들고, 변환은 여기서만 한다.
// 그래서 "훅이 새로 쓴 이벤트"와 "구 트레이스를 migrate 한 이벤트"가 구조적으로 같다.
//
// 저장 규약:
//   · events(영구): 원문 필드 0 — 이름·트리거·길이·크기·join 키 같은 파생 특징만.
//   · raw: 프롬프트 원문·why·args·description·prompt_head (기록 시점 레드액션 후). events 는 raw_ref
//     ("raw/<YYYY-MM>/<session>.jsonl#<id>")만 들고, why 가 있으면 why_ref 도 같은 줄을 가리킨다.
//   · .tracer/.gitignore 는 "*" 한 줄 — 디렉터리 전체(자기 자신 포함)를 git 에서 숨긴다.
//     로드맵의 "!.gitignore" 를 더하면 .gitignore 가 untracked 로 git status 에 뜬다(실측) — 넣지 않는다.
//   · 로테이션 없음 — 세션별 파일이라 단일 파일 비대가 없다.
// 실패는 전부 삼킨다(관측은 best-effort — 추적이 본 작업을 막지 않도록). stdout 무출력.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const P = require('./paths');

const RUNTIME = 'claude-code';
const CODEX = 'codex';

// 런타임 판별 — 같은 플러그인 hooks.json 을 Claude Code 와 Codex 가 함께 로드한다(Codex 는 Claude 형식 플러그인 훅을
// 호환 실행 — P0 codex-findings). 근거(실측: codex 0.164 바이너리에 내장된 훅 입력 스키마·플러그인 훅 env 이름):
//   ① PLUGIN_ROOT env — Codex 가 플러그인 훅에만 설정하는 이름(Claude Code 는 CLAUDE_PLUGIN_ROOT 만 — 2.1.310 바이너리 확인).
//      그래서 CLAUDE_PROJECT_DIR 이 새어 들어와도 Codex 플러그인 훅은 codex 로 잡힌다. Codex 는 호환 이름 CLAUDE_PLUGIN_ROOT
//      도 같은 값으로 둔다 — 둘이 다르면(사용자 셸의 무관한 PLUGIN_ROOT 가 Claude 훅에 상속) 근거로 쓰지 않는다.
//   ② payload turn_id(prompt_id 없음) — Codex 확장 필드("expose the active turn id"), 턴 범위 이벤트(UserPromptSubmit·
//      Pre/PostToolUse·Stop)에 필수. Claude Code 도 일부 이벤트(MessageDisplay) 스키마에 turn_id 를 쓰므로 prompt_id 가 함께
//      있으면 Claude 로 둔다(Claude 의 턴 키는 prompt_id).
//   ③ transcript_path 가 rollout-*.jsonl(.zst) — Codex rollout 파일명. turn_id 가 없는 SessionStart/SessionEnd 용.
//   ④ CLAUDE_PROJECT_DIR — Claude Code 가 훅에 항상 설정(Codex 바이너리에는 이 이름이 없다).
//   ⑤ CODEX_THREAD_ID — Codex 가 띄운 셸 env 에도 있어 그 셸에서 띄운 Claude Code 로 상속될 수 있다 → ④ 뒤 폴백.
// 아무 근거도 없으면 claude-code — 기존 동작 그대로.
function runtimeOf(json) {
  const j = json && typeof json === 'object' ? json : {};
  const pr = process.env.PLUGIN_ROOT;
  if (pr && (!process.env.CLAUDE_PLUGIN_ROOT || process.env.CLAUDE_PLUGIN_ROOT === pr)) return CODEX;
  if (typeof j.turn_id === 'string' && j.turn_id && !j.prompt_id) return CODEX;
  if (/(?:^|[\\/])rollout-[^\\/]*\.jsonl(?:\.zst)?$/.test(String(j.transcript_path || ''))) return CODEX;
  if (process.env.CLAUDE_PROJECT_DIR) return RUNTIME;
  if (process.env.CODEX_THREAD_ID) return CODEX;
  return RUNTIME;
}

// OBSERVE_TRACE=1(또는 true/on/yes) 일 때만 기록. 그 외엔 완전 무동작.
// OBSERVE_CHILD=1 은 observe 가 직접 띄운 자식 세션(분석기 등) 표식 — 자기 관측 루프 방지로 항상 무동작.
const enabled = () =>
  process.env.OBSERVE_CHILD !== '1' &&
  /^(1|true|on|yes)$/i.test(process.env.OBSERVE_TRACE || '');

// 슬래시 커맨드 토큰 — 절대경로("/Users/…") 선두 프롬프트 오탐을 배제하는 형태(공백/끝 종결).
// 리포트 집계(observe-report.js)의 커맨드 판정과 같은 정규식이다 — 이 파일이 단일 출처.
const CMD_TOKEN = /^\s*\/([A-Za-z0-9_:-]+)(\s|$)/;
const CMD_WRAP = /<command-name>\s*\/?([^<\s]+?)\s*<\/command-name>/;
// 프롬프트 → { is_command, command }. 리포트의 커맨드 턴 판정(is_command===true || CMD_TOKEN)과
// 커맨드명 추출(래퍼 우선, 토큰 폴백)을 그대로 옮겨, 원문 없이도 같은 집계가 나오게 한다.
function commandOf(text, isCommandFlag) {
  const t = String(text || '');
  if (!(isCommandFlag === true || CMD_TOKEN.test(t))) return { is_command: false, command: null };
  const wrap = CMD_WRAP.exec(t);
  const tok = CMD_TOKEN.exec(t);
  return { is_command: true, command: (wrap && wrap[1]) || (tok && tok[1]) || null };
}

// ── 기록 시점 시크릿 레드액션 ── 정규식 best-effort (사람 이름·사내 고유명사는 못 잡는다 —
// 그래서 원문은 raw/ 에만 두고 .tracer 전체를 git 에서 숨긴다). 순서: 여러 줄 블록 → 토큰 → 식별자.
const IP_OCTET = '(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)';
const REDACTIONS = [
  [/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)/g, '[REDACTED:private-key]'],
  [/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, '[REDACTED:jwt]'],
  [/\bAKIA[0-9A-Z]{16}\b/g, '[REDACTED:aws-key]'],
  [/\bgh[pousr]_[A-Za-z0-9]{20,}/g, '[REDACTED:github-token]'],
  [/\bgithub_pat_[A-Za-z0-9_]{20,}/g, '[REDACTED:github-token]'],
  [/\bsk-[A-Za-z0-9_-]{16,}/g, '[REDACTED:api-key]'],
  [/\bxox[bp]-[A-Za-z0-9-]{8,}/g, '[REDACTED:slack-token]'],
  // 로컬 파트 {1,64}(RFC 5321 상한) — 무제한 + 는 '@' 없는 긴 영숫자 덩어리에서 제곱 백트래킹(40K자 1s 실측)
  [/[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g, '[REDACTED:email]'],
  [new RegExp(`\\b(?:${IP_OCTET}\\.){3}${IP_OCTET}\\b`, 'g'), '[REDACTED:ip]'],
];
// 홈 경로 → "~" — 실제 홈 디렉터리 + 일반 형태(/Users/<이름>, /home/<이름>)
const HOME_LIKE = /\/(?:Users|home)\/[^/\s"'`<>]+/g;
function redact(s) {
  let out = String(s);
  for (const [re, rep] of REDACTIONS) out = out.replace(re, rep);
  const home = os.homedir();
  if (home && home.length > 1) out = out.split(home).join('~');
  return out.replace(HOME_LIKE, '~');
}
// 레드액션 대상 값 → 문자열 (비문자열 args 등은 직렬화 후 레드액션 — 객체 속 비밀도 통과 못 하게)
const redactValue = (v) => redact(typeof v === 'string' ? v : JSON.stringify(v));

// 이벤트에 남는 설치 경로(plugin_root)는 홈을 "~" 로 접어 둔다 — reader 가 다시 펼친다.
function tildify(p) {
  if (typeof p !== 'string' || !p) return p == null ? null : p;
  const home = os.homedir();
  return home && home.length > 1 && (p === home || p.startsWith(home + path.sep)) ? '~' + p.slice(home.length) : p;
}

// toV1 이 아는 v0 type — reader 도 v0 를 이 집합으로 걸러 migrate 전후 레코드 수를 맞춘다.
const V0_TYPES = new Set(['prompt', 'skill', 'agent', 'result', 'session_start', 'session_end']);

// v0 레코드 → { event, raw } (raw 는 원문 필드가 하나라도 있을 때만). 알 수 없는 type 은 null.
// 역변환(v1 → v0 모양)은 bin/lib/reader.js 의 normalizeV1 — 두 함수는 짝으로 유지한다.
// opts.keepTs — ts 없는 레코드를 지금 시각으로 채우지 않고 null 로 둔다(migrate: 이전 시각이
// coverage·last_ts·lifecycle 을 오염시키지 않도록). 훅은 항상 ts 를 넣으므로 영향 없다.
function toV1(rec, runtime = RUNTIME, opts = {}) {
  if (!rec || typeof rec !== 'object') return null;
  const ts = rec.ts || (opts.keepTs ? null : new Date().toISOString());
  const ev = {
    v: P.SCHEMA_VERSION, ts, runtime,
    session: rec.session_id || null,
    // turn = 런타임 고유 턴 id (Claude 는 prompt_id). 없으면 null — 합성 턴은 다이제스트 단계 몫
    turn: rec.prompt_id || null,
    turn_src: rec.prompt_id ? 'native' : null,
    kind: null,
  };
  const raw = {};
  let ext = null;
  switch (rec.type) {
    case 'prompt': {
      const text = String(rec.text || '');
      ev.kind = 'prompt';
      // 키 이름을 "prompt" 로 두지 않는다 — export FORBIDDEN_KEYS("prompt")와 같은 딥스캔을 events 도 통과하도록
      ev.prompt_meta = { len: text.length, ...commandOf(text, rec.is_command) };
      if (text) raw.text = text;
      break;
    }
    case 'skill':
      ev.kind = 'skill_use';
      // detection: explicit(Claude Skill 툴) | heuristic(Codex·Antigravity 의 SKILL.md 경로 읽기 — _lib/skill-read.js)
      ev.skill = { name: rec.skill ?? null, trigger: rec.trigger ?? null, detection: rec.detection || 'explicit', turn_command: rec.turn_command ?? null };
      ev.why_source = rec.why_source ?? null;
      if (rec.why) raw.why = rec.why;
      if (rec.args) raw.args = rec.args;
      ext = { tool_use_id: rec.tool_use_id ?? null, agent_id: rec.agent_id ?? null, agent_type: rec.agent_type ?? null };
      break;
    case 'agent':
      ev.kind = 'subagent';
      ev.subagent = { type: rec.agent ?? null, model: rec.model ?? null };
      ev.why_source = rec.why_source ?? null;
      if (rec.why) raw.why = rec.why;
      if (rec.description) raw.description = rec.description;
      if (rec.prompt_head) raw.prompt_head = rec.prompt_head;
      ext = { tool_use_id: rec.tool_use_id ?? null, parent_agent_id: rec.parent_agent_id ?? null, parent_agent_type: rec.parent_agent_type ?? null };
      break;
    case 'result':
      ev.kind = 'tool_result';
      ev.tool = rec.tool ?? null;
      ev.target = rec.target ?? null;
      ev.response_bytes = rec.response_bytes ?? null;
      ext = { tool_use_id: rec.tool_use_id ?? null };
      break;
    case 'session_start':
      ev.kind = 'session_start';
      ev.source = rec.source ?? null;
      ev.plugin_root = tildify(rec.plugin_root ?? null);
      break;
    case 'session_end':
      ev.kind = 'session_end';
      ev.reason = rec.reason ?? null;
      break;
    default:
      return null;
  }
  if (ext) ev.ext = { [runtime]: ext };
  const keys = Object.keys(raw);
  if (!keys.length) return { event: ev, raw: null };
  const id = crypto.randomBytes(6).toString('hex');
  const rel = P.rawRel(ev.session, ts);
  const rawRec = { v: P.SCHEMA_VERSION, id, ts, runtime, session: ev.session, kind: ev.kind };
  for (const k of keys) rawRec[k] = redactValue(raw[k]);
  ev.raw_ref = `${rel}#${id}`;
  if (raw.why) ev.why_ref = ev.raw_ref;
  return { event: ev, raw: rawRec, rawRel: rel };
}

const appendLine = (file, obj) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(file, JSON.stringify(obj) + '\n');
};

// 전역 레포 목록에 이 레포 루트를 idempotent 등록 (--all 합산의 입력). 원문은 올리지 않는다 —
// 경로 한 줄뿐이다. 레포당 마커 파일 1개(index/repos.d/<sha1(realpath)>, 내용=경로)라서 여러 레포가
// 동시에 첫 기록을 해도 공유 파일 read-modify-write 경합(갱신 유실)이 없다. 같은 레포의 동시
// 등록은 같은 내용을 같은 이름에 쓰므로 무해하다. 임시 파일 + rename 으로 부분 쓰기를 남기지 않는다.
function registerRepo(root) {
  try {
    const abs = P.real(root);
    const dir = P.reposDir();
    const f = path.join(dir, crypto.createHash('sha1').update(abs).digest('hex'));
    if (fs.existsSync(f)) return;
    fs.mkdirSync(dir, { recursive: true });
    const tmp = `${f}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, abs + '\n');
    fs.renameSync(tmp, f);
  } catch (_) { /* best-effort */ }
}

// .tracer 골격 — 첫 기록 전에 .gitignore("*")를 먼저 만들어 이벤트 파일이 한순간도 git 에 보이지 않게 한다.
function ensureSkeleton(root) {
  const dir = P.tracerDir(root);
  const gi = path.join(dir, '.gitignore');
  if (fs.existsSync(gi)) return;
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(gi, '*\n');
  fs.writeFileSync(path.join(dir, 'VERSION'), `${P.SCHEMA_VERSION}\n`);
  registerRepo(root);
}

// v0 레코드 1건 기록 — raw 줄을 먼저 쓰고 이벤트를 쓴다(이벤트가 가리키는 raw 가 항상 먼저 존재).
// session_start 마다 레포 등록을 재확인한다(전역 index 를 지워도 다음 세션에 복구 — 세션당 1회 비용).
// 반환: 기록했으면 true, 알 수 없는 type 이면 false. 실패는 throw (migrate 가 중단 판단에 쓴다).
// 루트가 홈이면 throw — <홈>/.tracer 는 전역 층이라 원문·이벤트를 쓰지 않는다(emit 은 조용히 무기록).
function write(root, rec, runtime = RUNTIME, opts = {}) {
  if (P.isHome(root)) throw new Error(`홈 디렉터리(${root})는 레포 루트로 기록하지 않음 — ~/.tracer 는 전역 층`);
  const conv = toV1(rec, runtime, opts);
  if (!conv) return false;
  ensureSkeleton(root);
  if (conv.raw) appendLine(path.join(P.tracerDir(root), conv.rawRel), conv.raw);
  appendLine(P.eventsFile(root, runtime, conv.event.session, conv.event.ts), conv.event);
  if (conv.event.kind === 'session_start') registerRepo(root);
  return true;
}

// v1 레코드 직접 append — v0 변환이 없는 P2 산출물(commit 이벤트·turn_summary·session_summary)용.
// write 와 같은 규약: 홈 루트 거부(throw), 골격(.gitignore "*") 선생성. 원문 필드는 호출측이 만들지 않는다.
function appendV1(root, file, obj) {
  if (P.isHome(root)) throw new Error(`홈 디렉터리(${root})는 레포 루트로 기록하지 않음 — ~/.tracer 는 전역 층`);
  ensureSkeleton(root);
  appendLine(file, obj);
}

// 훅용 — write 의 best-effort 래퍼 (어떤 실패도 삼킨다).
function emit(root, rec, runtime = RUNTIME) {
  try { write(root, rec, runtime); } catch (_) { /* 무시 — 관측은 best-effort */ }
}

module.exports = { RUNTIME, CODEX, runtimeOf, V0_TYPES, enabled, CMD_TOKEN, CMD_WRAP, commandOf, redact, tildify, toV1, write, emit, appendV1, ensureSkeleton, registerRepo };
