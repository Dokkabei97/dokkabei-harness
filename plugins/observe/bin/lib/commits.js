// 커밋 경계 분석 코어 — git 훅 commit 이벤트 ↔ 세션·턴 귀속, commits/<sha>.md 렌더, pre-commit 1줄 요약.
// 런타임을 모른다: 입력은 .tracer 의 이벤트·다이제스트와 호출측(adapters/git/commit.js)이 넘기는 git 정보·미확정 턴뿐이다.
// 원문(프롬프트·명령·출력)은 다루지 않는다 — 커밋 제목(레드액션 후)·상대경로·SHA·다이제스트의 이름/개수만.
//
// 귀속 우선순위 (결정론 → 휴리스틱, 앞에서 정해지면 끝):
//   sha          — 런타임 어댑터가 transcript 에서 뽑은 kind:"commit" 이벤트(events/<runtime>/…, P2)와 SHA 일치(짧은 SHA 접두).
//                  근거(commit.source: gitop·stdout 은 결정론, git-log·git-log-weak 는 시각창 휴리스틱)를 그대로 싣는다.
//   trailer      — 커밋 메시지의 "Agent-Session: <runtime>/<session>" trailer (prepare-commit-msg 옵션 훅이 붙인다).
//   env          — 커밋 시점 훅 환경의 CLAUDE_CODE_SESSION_ID (Claude Code Bash 툴 환경에 있음 — 실측 v2.1.310).
//                  trailer·env 의 턴 = 그 세션에서 커밋 시각 이전에 시작한 마지막 턴(진행 중 턴 — 미확정 턴도 후보).
//                  "이전" 의 여유는 커밋 시각의 초 단위 절사(ROUND_MS)뿐 — 커밋 직후 시작한 다음 턴이 가져가지 않게.
//                  경계 동률은 이전 턴 우선: 절사된 커밋 초 [ct, ct+ROUND_MS] 안에 시작한 턴은 그 1초 안에 커밋까지 했을 리
//                  없으므로, ct 전에 시작한 턴이 있으면 그쪽을 고르고 없을 때만 경계 턴을 쓴다. ts_start 같으면 앞(먼저 읽힌) 턴.
//                  (한 세션의 턴은 겹치지 않으므로 "커밋 시각을 품은 턴" 우선 규칙은 따로 두지 않는다 — 사이드체인은 턴이 아님)
//   window+files — 사람 커밋: 커밋 시각 이전 WINDOW_MS(~ 이후 SLACK_MS) 안에 끝난 턴 중 편집 파일(files.edited)이
//                  커밋 변경 파일과 겹치는 턴(커밋 뒤에 시작한 턴 제외). 점수 = 겹친 수 / 커밋 파일 수, 동점은 더 늦게
//                  끝난 턴. 겹침 0 이면 none.
// 커밋 시점에는 그 턴의 다이제스트가 아직 없다(Stop 은 지연 1턴 확정) — 호출측이 커서 이후 미확정 턴을 읽기 전용으로
// 요약해 넘기고(같은 키면 다이제스트 우선), sha 귀속은 다이제스트가 쌓인 뒤 재연결(relink)에서 생긴다.
const path = require('path');
const P = require('../hooks/_lib/paths');
const { redact } = require('../hooks/_lib/writer');
const { walkJsonl, readJsonl } = require('./reader');
const R = require('./recommend');

const WINDOW_MS = 2 * 60 * 60 * 1000; // 사람 커밋 귀속 창 — 커밋 이전 2시간 안에 끝난 턴 (수동 상수)
const SLACK_MS = 60 * 1000;           // 시계 오차·flush 지연 여유 — 커밋 뒤 1분 안에 끝난 턴까지 후보
const ROUND_MS = 1000;                // 커밋 시각(%cI)은 초 단위 절사 — 턴 시작이 커밋보다 "이전" 인지 볼 때의 여유
const FILES_MAX = 20;                 // .md 에 나열하는 변경 파일 상한
const LINE_MAX = 300;                 // pre-commit 1줄 상한
const LLM_HEAD = '## 해석 (LLM)';      // worker 가 덧붙이는 절 — 재렌더(relink) 때 보존한다
const HEAD_RE = /^<!-- observe-commit (\{.*\}) -->/;

const tsOf = (s) => { const t = Date.parse(s); return Number.isFinite(t) ? t : null; };
const sameSha = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length >= 7 && b.length >= 7 &&
  (a.startsWith(b) || b.startsWith(a));
const turnKey = (t) => `${t.runtime}|${t.session}|${t.turn}`;
const gitHookDir = (root) => path.join(P.eventsDir(root), 'git-hook');

// 런타임 어댑터의 commit 이벤트(git-hook 제외) → [{ sha, runtime, session, turn, source }]
function runtimeCommits(root) {
  const out = [];
  const skip = gitHookDir(root) + path.sep;
  for (const f of walkJsonl(P.eventsDir(root))) {
    if (f.startsWith(skip)) continue;
    readJsonl(f, (e) => {
      if (e.kind === 'commit' && e.commit && typeof e.commit.sha === 'string') {
        out.push({ sha: e.commit.sha, runtime: e.runtime || null, session: e.session || null, turn: e.turn || null, source: e.commit.source || null });
      }
    });
  }
  return out;
}
// git 훅 commit 이벤트 (파일·줄 순 = 기록 순)
const SHA_RE = /^[0-9a-f]{40}([0-9a-f]{24})?$/; // sha1 / sha256
function hookCommits(root) {
  const out = [];
  // sha 는 전체 16진 SHA 만(깨진 줄의 "HEAD" 같은 ref 이름이 relink 에서 commits/HEAD.md 를 만들지 않게)
  for (const f of walkJsonl(gitHookDir(root))) readJsonl(f, (e) => { if (e.kind === 'commit' && e.commit && SHA_RE.test(e.commit.sha)) out.push(e); });
  return out;
}
// 다이제스트 turn_summary 전부
function digestTurns(root) {
  const out = [];
  for (const f of walkJsonl(P.digestsDir(root))) readJsonl(f, (d) => { if (d.kind === 'turn_summary') out.push(d); });
  return out;
}
// 다이제스트 + 미확정 턴 (같은 (runtime, session, turn) 이면 다이제스트 우선)
function mergeTurns(digests, pending) {
  const seen = new Set(digests.map(turnKey));
  return digests.concat((pending || []).filter((t) => !seen.has(turnKey(t))));
}

// c = { sha, ts, files:[레포 상대경로], trailer:{runtime,session}|null, env:{runtime,session}|null }
// → { method, runtime, session, turn, source?, score?, overlap?, files_n?, summary(turn_summary|null) }
function attribute(c, turns, rcommits) {
  const findTurn = (rt, sid, tid) => turns.find((t) => t.runtime === rt && t.session === sid && t.turn === tid) || null;
  const hit = rcommits.find((x) => sameSha(x.sha, c.sha));
  if (hit) return { method: 'sha', runtime: hit.runtime, session: hit.session, turn: hit.turn, source: hit.source, summary: findTurn(hit.runtime, hit.session, hit.turn) };
  const ct = tsOf(c.ts);
  const hint = (c.trailer && c.trailer.session && c.trailer) || (c.env && c.env.session && c.env) || null;
  if (hint) {
    const cands = turns.filter((t) => t.session === hint.session && (!hint.runtime || t.runtime === hint.runtime) &&
      tsOf(t.ts_start) != null && (ct == null || tsOf(t.ts_start) <= ct + ROUND_MS));
    const before = ct == null ? cands : cands.filter((x) => tsOf(x.ts_start) < ct);
    let t = null;
    for (const x of (before.length ? before : cands)) if (!t || tsOf(x.ts_start) > tsOf(t.ts_start)) t = x;
    return { method: hint === c.trailer ? 'trailer' : 'env', runtime: hint.runtime || (t && t.runtime) || null, session: hint.session, turn: t ? t.turn : null, summary: t };
  }
  const files = new Set(c.files || []);
  let best = null;
  if (ct != null && files.size) {
    for (const t of turns) {
      const te = tsOf(t.ts_end);
      if (te == null || te < ct - WINDOW_MS || te > ct + SLACK_MS) continue;
      const ts = tsOf(t.ts_start);
      if (ts != null && ts > ct + ROUND_MS) continue; // 커밋 뒤에 시작한 턴은 그 커밋을 만들 수 없다
      const overlap = (Array.isArray(t.files && t.files.edited) ? t.files.edited : []).filter((f) => files.has(f)).length;
      if (!overlap) continue;
      const score = overlap / files.size;
      if (!best || score > best.score || (score === best.score && te > best.te)) best = { t, te, score, overlap };
    }
  }
  if (best) {
    return {
      method: 'window+files', runtime: best.t.runtime, session: best.t.session, turn: best.t.turn,
      score: Math.round(best.score * 1000) / 1000, overlap: best.overlap, files_n: files.size, summary: best.t,
    };
  }
  return { method: 'none', runtime: null, session: null, turn: null, summary: null };
}

// 미처리 추천 1줄 — recommendations.jsonl 의 상태가 proposed(마지막 created 뒤 수락·거절·스누즈 없음, 만료 전)인 것만
// 결정론으로. 없으면 ''. "마지막 리포트" 의 근사다: created 는 새 추천·근거 변경 때만 append 되므로, 그 뒤 리포트에서 빠진
// 추천은 응답하거나 만료(expireDays, 파생 상태 — Phase 5)될 때까지 남는다. 줄 안에는 유형·대상·근거 세션 수·날짜만 있다(원문 없음).
function precommitLine(root, nowMs = Date.now()) {
  const events = R.readEvents(root);
  const open = [];
  for (const s of R.stateOf(events).values()) if (R.currentStatus(s, nowMs) === 'proposed') open.push(s.created);
  if (!open.length) return '';
  let last = '';
  for (const e of open) if (typeof e.ts === 'string' && e.ts > last) last = e.ts;
  open.sort((a, b) => (b.evidence_n || 0) - (a.evidence_n || 0) || String(a.target).localeCompare(String(b.target)));
  const byType = {};
  for (const e of open) byType[e.type] = (byType[e.type] || 0) + 1;
  const types = Object.entries(byType).map(([k, v]) => `${k} ${v}`).join('·');
  const top = open.slice(0, 3).map((e) => `${e.type} ${e.target}(근거 ${e.evidence_n || 0})`).join(', ');
  const line = `[observe] 미처리 추천 ${open.length}건(${types}): ${top}${open.length > 3 ? ' 외' : ''}` +
    `${last ? ` — ${last.slice(0, 10)} 리포트 기준` : ''}, /observe-report 로 확인`;
  return line.length > LINE_MAX ? line.slice(0, LINE_MAX - 1) + '…' : line;
}

const METHOD_DESC = {
  sha: 'transcript 의 커밋 SHA 일치',
  trailer: '커밋 메시지 Agent-Session trailer',
  env: '커밋 시점 훅 환경의 세션 id(CLAUDE_CODE_SESSION_ID)',
  'window+files': `사람 커밋 휴리스틱 — 커밋 전 ${WINDOW_MS / 3600000}시간 안에 끝난 턴의 편집 파일 교집합`,
  none: '귀속 없음(세션 근거·파일 교집합 없음)',
};
// sha 귀속의 근거(P2 commit.source) — git-log 계열은 명령 실행 구간의 시각창으로 찾은 것이라 결정론이 아니다
const SOURCE_DESC = {
  gitop: '결정론 — 툴 결과의 gitOperation',
  stdout: '결정론 — 커밋 출력의 [branch sha] 줄',
  'git-log': '휴리스틱 — 명령 실행 구간의 커밋 중 제목 일치',
  'git-log-weak': '휴리스틱(낮은 신뢰) — 명령 실행 구간의 최신 커밋',
};
const list = (xs, n) => xs.slice(0, n).map((x) => '`' + x + '`').join(', ') + (xs.length > n ? ` 외 ${xs.length - n}개` : '');
const kv = (obj) => Object.entries(obj || {}).filter(([, v]) => v).map(([k, v]) => `${k} ${v}`).join(' · ') || '없음';

// info = { sha, short, ts, subject, branch, parents_n, action, files } (adapters/git/commit.js gitInfo)
function renderMd(info, attr, line) {
  const head = { v: P.SCHEMA_VERSION, sha: info.sha, method: attr.method, runtime: attr.runtime, session: attr.session, turn: attr.turn };
  const out = [
    `<!-- observe-commit ${JSON.stringify(head)} -->`,
    `# 커밋 ${info.short}`,
    '',
    `- 제목: ${redact(info.subject || '').replace(/\s+/g, ' ').slice(0, 200)}`,
    `- 시각 ${info.ts} · 브랜치 ${info.branch || '(detached)'} · 동작 ${info.action} · 부모 ${info.parents_n}`,
    `- 변경 파일 ${info.files.length}개${info.files.length ? ': ' + list(info.files.map((f) => redact(f)), FILES_MAX) : ''}`,
    '',
    '## 세션 귀속',
    `- 방법: ${attr.method} — ${METHOD_DESC[attr.method]}` +
      (attr.method === 'sha' ? ` (SHA 근거 ${attr.source || '?'}: ${SOURCE_DESC[attr.source] || '근거 미상'})` : ''),
  ];
  if (attr.session) out.push(`- 런타임 ${attr.runtime || '?'} · 세션 \`${attr.session}\` · 턴 ${attr.turn ? '`' + attr.turn + '`' : '미확인'}`);
  if (attr.method === 'window+files') out.push(`- 겹친 파일 ${attr.overlap}/${attr.files_n} (점수 ${attr.score})`);
  out.push('', '## 그 턴의 작업 방식');
  const t = attr.summary;
  if (!t) out.push('- 턴 다이제스트 없음');
  else {
    const tools = t.tools || {};
    out.push(
      `- 결과 ${t.outcome || '?'} · 프롬프트 ${t.prompt_kind || 'user'} · 모델 ${t.model || '?'} · ${t.dur_ms != null ? Math.round(t.dur_ms / 1000) + 's' : '소요 ?'}`,
      `- 툴 흐름 \`${tools.seq_compact || ''}\` · 실패 ${tools.fail || 0} · 중단 ${tools.interrupt || 0} · 거부 ${tools.rejected || 0}`,
      `- 스킬: ${(t.skills || []).map((s) => `${s.name}(${s.trigger}${s.via ? '/' + s.via : ''})`).join(', ') || '없음'}` +
        ` · 서브에이전트: ${(t.subagents || []).map((s) => s.type || '?').join(', ') || '없음'}`,
      `- 실행 종류: ${kv(t.exec_kinds)} · 편집 ${(t.files && t.files.edited_n) || 0}개`,
    );
  }
  out.push('', '## 미처리 추천', `- ${line || '없음'}`, '');
  return out.join('\n');
}
// .md 첫 줄 머리(귀속 메타) — 없거나 깨졌으면 null
function readHead(text) {
  const m = HEAD_RE.exec(String(text || ''));
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch (_) { return null; }
}

module.exports = {
  WINDOW_MS, SLACK_MS, LLM_HEAD, SHA_RE, runtimeCommits, hookCommits, digestTurns, mergeTurns, attribute,
  precommitLine, renderMd, readHead, sameSha,
};
