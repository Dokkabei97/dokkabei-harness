// Claude Code transcript → 턴 다이제스트(turn_summary) + 커밋 이벤트 파서, 그리고 detached worker 진입점.
// 저장(커서·upsert-skip·락)은 _lib/digest.js 의 run() 이 하고, 이 파일은 "바이트 오프셋부터 읽어 턴으로 자르고
// 결정론 요약을 만드는" 일만 한다. 원문(프롬프트·명령·출력)은 결과에 남기지 않는다 — 카테고리·개수·상대경로·SHA 만.
//
// transcript 실측 사실 (v2.1.283~2.1.302, 이 머신의 전 프로젝트 transcript, 2026-10-25):
//   · 턴 키 = user 레코드의 promptId (훅 payload 의 prompt_id 와 같은 값). assistant 레코드에는 없다.
//     user 레코드 1,896건 중 17건만 promptId 가 없다(대부분 /clear·/login 같은 로컬 커맨드, 1건은 실 프롬프트)
//     → promptId 가 바뀌면 새 턴, promptId 없는 실 프롬프트 레코드는 합성 턴("syn:<uuid>", turn_src synthetic).
//   · assistant 메시지는 블록마다 별도 레코드로 기록되고 같은 message.id·같은 usage 를 반복한다 → 토큰은 message.id 로 중복 제거.
//   · api-request-blob 등 type 이 user/assistant/system 이 아닌 레코드에도 tool_use 사본이 있다 → 세지 않는다.
//   · 사용자 취소 마커 2종 (전부 user 레코드, 같은 promptId):
//       ① Esc 중단:   content [{type:"text", text:"[Request interrupted by user]"}]
//       ② 도구 거부:  tool_result {is_error:true, content:"The user doesn't want to proceed with this tool use. …"}
//                     + toolUseResult "User rejected tool use", 바로 뒤에 "[Request interrupted by user for tool use]"
//     PreToolUse 훅 차단(exit 2)도 is_error:true 지만 toolUseResult 가 "Error: PreToolUse:…" 라 거부가 아니라 실패로 센다.
//     거부 뒤 모델이 계속 진행한 턴(피드백 거부 "To tell you how to proceed, the user said: …" — 로컬 실 샘플 0건)은
//     취소로 보지 않는다: cancelled = interrupt 마커 또는 "뒤에 assistant 진행이 없는" 거부.
//   · 사람 프롬프트 레코드에는 origin {kind:"human"} 이 있다(실측 2026-10-26, 전 프로젝트 promptId 그룹 166개 중 사람 93건 전부).
//     사람 프롬프트가 아닌 user 레코드도 자체 promptId 를 가진다 — 턴 경계로 삼지 않는다(실측 형태):
//       async Agent·백그라운드 Bash 완료 알림 — origin.kind "task-notification", 본문 "<task-notification>…" (뒤에 assistant 응답)
//       사용자 ! 모드 — "<bash-input>…" + "<bash-stdout>…" (origin 없음, 뒤에 assistant 응답)
//       로컬 커맨드(/plugin·/clear 등) — isMeta "<local-command-caveat>…" + "<command-name>…"(origin 없음) + "<local-command-stdout>…"
//       isMeta 단독(/context 출력 등)
//     알림·! 모드는 이전 사람 턴에 흡수한다(그 턴의 활동으로 센다 — 알림마다 turn_summary 를 만들지 않는다). 로컬 커맨드 그룹
//     레코드는 활동이 없어 턴에 넣지도 않는다(ts_end 가 나중의 /plugin 시각으로 늘지 않게). 창 첫머리에 이전 사람 턴 없이
//     온 알림·! 모드(마감 뒤 resume·유휴 마감 뒤 완료 알림)만 자기 턴이 되고 prompt_kind(notification|bash) 로 표시한다.
//     origin 이 없는 옛 형식은 본문 규칙으로 판정 — caveat 바로 뒤의 "<command-name>" 은 로컬 커맨드다(스킬 슬래시 커맨드는
//     caveat 없이 온다, 실측). corrected 판정의 "다음 프롬프트"는 곧 다음 사람 턴이다(리포트 UserPromptSubmit 쌍과 같은 기준).
//   · 훅 출력은 type "attachment" 레코드(hook_success·hook_additional_context 등, 실측)라 턴 분할에 끼지 않는다.
//     Stop 훅 차단(exit 2) 시 기록 형태는 미실측(로컬 0건) — promptId 없는 "Stop hook feedback:" user 텍스트면
//     합성 턴을 만들지 않게 isPromptRec 에서 제외해 둔다(방어).
//   · toolUseResult.gitOperation 은 실측 14건 전부 {"push":{"branch":…}} — 커밋 SHA 를 담은 사례는 0건.
//     게다가 실측 git commit 35건은 전부 -q 라 stdout 에 "[branch sha]" 줄도 없다. 그래서 SHA 는
//     ① gitOperation.commit(향후 형식 대비, tolerant) → ② stdout 의 "[branch sha] …" 줄 → ③ 성공한 git commit 명령의
//     실행 구간 [tool_use 시각, tool_result 시각](초 절사)에 committer time(%ct, 다시 확인)이 드는 커밋(git log --all --reflog
//     — 확정 시점의 HEAD·브랜치 전환·amend·rebase 와 무관. 다른 턴에 이미 배정된 SHA 는 후보에서 뺀다. 명령 1회당 1개 —
//     제목이 명령에 나오는 것 우선, 대조 실패는 source "git-log-weak", 후보가 없으면 귀속하지 않는다)
//     순으로 찾는다. git commit 판정은 따옴표 문자열·heredoc 본문을 지운 명령 세그먼트 기준(grep "git commit" 은 아님).
//     창 앞쪽 여유는 없다 — 실측(2026-10-26, 4개 레포 성공 커밋 명령 24건): ct ≥ floor(tool_use) 가 전부, 창 앞 2s 안의
//     커밋 0건, 대신 창 앞 3s 에 앞 명령의 커밋 4개가 있던 사례 1건(여유를 두면 그쪽이 끼어든다).
//   · Codex rollout(첫 줄 type "session_meta")이 transcript_path 로 들어오면 아무것도 하지 않는다(커서도 안 만듦) —
//     Codex 가 이 마켓플레이스 플러그인을 Claude 형식으로 설치해 이 훅을 부를 수 있다(로드맵 실측). Codex 는
//     훅 진입점이 런타임을 판별해 adapters/codex/rollout.js 로 보낸다 — 이 가드는 판별이 빗나갔을 때의 방어선.
//   · 명령 분석 함수(segments·execKind·hasGitSub·커밋 SHA 찾기)는 Codex·Antigravity 어댑터도 같은 것을 쓴다(export).
//   · Stop 시점 transcript 에는 그 턴의 마지막 레코드가 아직 없을 수 있고, generic 루프가 Stop 을 막으면 같은 턴이
//     이어진다 → Stop 에서는 "다음 턴 경계가 이미 기록된" 턴만 확정하고 마지막 턴은 다음 Stop·SessionEnd 가 확정한다.
const fs = require('fs');
const path = require('path');
const P = require('../../_lib/paths');
const { CMD_WRAP } = require('../../_lib/writer');

const RUNTIME = 'claude-code';
const FAIL_RATIO = 0.5;       // outcome failed — 툴 결과 중 실패(거부 제외) 비율 임계
const EDITED_MAX = 20;        // files.edited 상대경로 상한
const SEQ_MAX_RUNS = 40;      // seq_compact 런 상한 (넘으면 ">…+N")
const GIT_SLACK_S = 0;        // git log 시각 창의 시작 쪽 여유(초) — 실측상 불필요(헤더). 끝 쪽도 여유 없음(gitCommitsBetween)
const IDLE_FINAL_MS = 30 * 60 * 1000; // 따라잡기: 이 시간 넘게 갱신 없는 다른 세션은 마감(final)으로 본다

const INTERRUPT_RE = /^\[Request interrupted by user/;
const REJECT_TEXT_RE = /^The user doesn't want to proceed with this tool use/;
const STOP_FEEDBACK_RE = /^Stop hook feedback:/;
const CAVEAT_RE = /^<local-command-caveat>/;
const SYS_PROMPTS = [['notification', /^<task-notification>/], ['bash', /^<bash-(?:input|stdout|stderr)>/]];
const COMMIT_LINE_RE = /^\[[^\]\s]+(?: \(root-commit\))? ([0-9a-f]{7,40})\]/gm;

// 툴 → 카테고리 (seq_compact 문자). 목록 밖은 other(O).
const CATS = {
  Read: 'read', NotebookRead: 'read',
  Grep: 'search', Glob: 'search', LS: 'search',
  Edit: 'edit', Write: 'edit', MultiEdit: 'edit', NotebookEdit: 'edit',
  Bash: 'exec', PowerShell: 'exec', BashOutput: 'exec', KillShell: 'exec',
  WebFetch: 'web', WebSearch: 'web',
  Agent: 'subagent', Task: 'subagent',
  Skill: 'skill',
  TodoWrite: 'plan', EnterPlanMode: 'plan', ExitPlanMode: 'plan', TaskCreate: 'plan', TaskUpdate: 'plan', TaskList: 'plan',
};
const LETTER = { read: 'R', search: 'G', edit: 'E', exec: 'B', web: 'W', subagent: 'A', skill: 'S', mcp: 'M', plan: 'P', other: 'O' };
const catOf = (name) => (String(name).startsWith('mcp__') ? 'mcp' : CATS[name] || 'other');

// Bash 명령 종류 — 첫 "의미 있는" 세그먼트(cd·export·set·echo 와 env 대입 접두를 건너뜀)로 판정. 원문은 남기지 않는다.
const EXEC_RULES = [
  ['git', /^git\b/],
  ['test', /\b(bats|pytest|jest|vitest|mocha|rspec|go test|cargo test|node --test|(npm|pnpm|yarn)( run)? test)\b/],
  ['lint', /\b(eslint|ruff|shellcheck|prettier|biome|golangci-lint|flake8|mypy|tsc --noEmit)\b/],
  ['build', /^(make|tsc|go build|cargo build|docker build)\b|\b((npm|pnpm|yarn)( run)? build|gradlew? build|mvn (package|install)|(next|vite) build)\b/],
  ['pkg', /\b((npm|pnpm) (i|install|ci|add)|yarn (add|install)|pip3? install|uv (add|remove|sync|pip)|brew install|cargo add|go get|poetry add)\b/],
];
const segments = (cmd) => String(cmd || '').split(/&&|\|\||;|\n|\|/)
  .map((seg) => seg.trim().replace(/^[({]\s*/, '').replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+/, ''));
function execKind(cmd) {
  for (const seg of segments(cmd)) {
    if (!seg || /^(cd|pushd|popd|set|export|echo|true|:)\b/.test(seg)) continue;
    for (const [k, re] of EXEC_RULES) if (re.test(seg)) return k;
    return 'other';
  }
  return 'other';
}

// 명령에 실제 git <sub> 세그먼트가 있는지 — heredoc 본문·따옴표 문자열을 지운 뒤 execKind 와 같은 세그먼트로 판정.
// grep -rn "git commit" · echo '… git commit …' · 커밋 메시지 heredoc 안의 문자열은 명령이 아니다.
function hasGitSub(cmd, sub) {
  const bare = String(cmd || '')
    .replace(/<<-?[ \t]*(['"]?)([A-Za-z_]\w*)\1[^\n]*\n[\s\S]*?\n[ \t]*\2[ \t]*(?=\n|$)/g, ' ')
    .replace(/'[^']*'|"(?:\\[\s\S]|[^"\\])*"/g, "''");
  const re = new RegExp(`^git\\b(?:\\s+-[cC]\\s+\\S+)*\\s+${sub}\\b`);
  return segments(bare).some((seg) => re.test(seg));
}

// 메시지 content → 텍스트 블록만 (tool_result 는 제외)
function textOf(content) {
  if (typeof content === 'string') return content.trim();
  if (!Array.isArray(content)) return '';
  return content.filter((b) => b && b.type === 'text' && b.text).map((b) => b.text.trim()).join('\n').trim();
}
const contentOf = (r) => (r && r.message && r.message.content);
const hasToolResult = (r) => Array.isArray(contentOf(r)) && contentOf(r).some((b) => b && b.type === 'tool_result');
// 시스템 주입 프롬프트 레코드 → 'notification' | 'bash' | null (헤더 실측 참고)
function sysKindOf(r) {
  if (!r || r.type !== 'user' || r.isMeta === true || hasToolResult(r)) return null;
  if (r.origin && r.origin.kind === 'task-notification') return 'notification';
  const t = textOf(contentOf(r));
  for (const [k, re] of SYS_PROMPTS) if (re.test(t)) return k;
  return null;
}
// 실 사용자 프롬프트 레코드 — meta·tool_result·로컬 커맨드 출력·취소 마커·시스템 주입·Stop 훅 피드백 제외.
// origin.kind 가 있으면 그것을 따른다("human" 만 사람). 없으면(옛 형식) 본문 규칙 — afterCaveat(직전 user 레코드가
// local-command-caveat)면 로컬 커맨드의 "<command-name>" 레코드라 사람 프롬프트가 아니다.
function isPromptRec(r, afterCaveat) {
  if (!r || r.type !== 'user' || r.isMeta === true || hasToolResult(r) || sysKindOf(r)) return false;
  const t = textOf(contentOf(r));
  if (!t) return false;
  if (r.origin && r.origin.kind) return r.origin.kind === 'human';
  return !afterCaveat && !/^<local-command-/.test(t) && !INTERRUPT_RE.test(t) && !STOP_FEEDBACK_RE.test(t);
}
const toolResultText = (b) => (typeof b.content === 'string' ? b.content : textOf(b.content));

// [offset, 마지막 완결 라인 끝) 을 라인 단위로 파싱 → { lines:[{off, rec}], end, size }. 깨진 줄은 건너뛴다.
function readLines(file, offset) {
  const fd = fs.openSync(file, 'r');
  try {
    const size = fs.fstatSync(fd).size;
    const start = offset > 0 && offset <= size ? offset : 0; // 파일이 줄었으면 처음부터
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lastNl = buf.lastIndexOf(0x0a);
    const lines = [];
    let pos = 0;
    while (pos <= lastNl) {
      const nl = buf.indexOf(0x0a, pos);
      if (nl > pos) {
        try {
          const rec = JSON.parse(buf.toString('utf8', pos, nl));
          if (rec && typeof rec === 'object') lines.push({ off: start + pos, rec });
        } catch (_) { /* 깨진 줄 */ }
      }
      pos = nl + 1;
    }
    return { lines, end: lastNl < 0 ? start : start + lastNl + 1, size };
  } finally {
    fs.closeSync(fd);
  }
}

// 라인 → 턴 분할. 경계는 사람 프롬프트 레코드뿐 — promptId 가 바뀌어도 사람 프롬프트가 아니면(알림·! 모드·로컬 커맨드·
// isMeta) 새 턴이 아니다(헤더 실측). 알림·! 모드 그룹은 현재 사람 턴에 흡수하고, 로컬 커맨드 그룹(새 promptId 인데 사람도
// 시스템 주입도 아닌 레코드로 시작)의 user 레코드는 버린다. 첫 경계 이전 레코드는 이미 확정된 이전 턴의 꼬리(또는 세션
// 서두)라 버린다 — 단 그 자리의 시스템 주입은 흡수할 사람 턴이 이미 확정됐으므로 자기 턴(sys)을 만든다.
function segment(lines) {
  const turns = [];
  let cur = null;
  let afterCaveat = false;
  const localPids = new Set();
  for (const { off, rec } of lines) {
    if (rec.isSidechain === true) continue;
    if (rec.type !== 'user' && rec.type !== 'assistant' && rec.type !== 'system') continue;
    const isUser = rec.type === 'user';
    const pid = isUser ? rec.promptId || null : null;
    const human = isPromptRec(rec, afterCaveat);
    const sys = sysKindOf(rec);
    if (isUser && !hasToolResult(rec)) afterCaveat = rec.isMeta === true && CAVEAT_RE.test(textOf(contentOf(rec)));
    if (human && (!cur || !cur.promptRec || !pid || cur.pid !== pid)) {
      cur = { pid, pids: new Set([pid]), id: pid || `syn:${rec.uuid || off}`, off, recs: [], promptRec: rec, sysRec: null, sys: null };
      turns.push(cur);
    } else if (sys && !cur) {
      cur = { pid, pids: new Set([pid]), id: pid || `syn:${rec.uuid || off}`, off, recs: [], promptRec: null, sysRec: rec, sys };
      turns.push(cur);
    } else if (sys && cur) {
      cur.pids.add(pid); // 흡수한 알림·! 모드 그룹 — 그 그룹의 isMeta·tool_result 도 이 턴 것
    } else if (isUser && !human && pid && cur && !cur.pids.has(pid) && !hasToolResult(rec)) {
      localPids.add(pid); // 로컬 커맨드·isMeta 단독 그룹
    }
    if (!cur) continue;
    if (isUser && !human && !sys && !hasToolResult(rec)
      && (localPids.has(pid) || (!pid && /^<(?:local-command-|command-name>)/.test(textOf(contentOf(rec)))))) continue;
    cur.recs.push(rec);
  }
  return turns;
}

// 스킬 trigger — 턴 프롬프트가 그 스킬의 슬래시 커맨드면 user (trace-skill.js classifyTrigger 와 같은 규칙)
function triggerOf(name, prompt) {
  const full = String(name).toLowerCase();
  const tail = full.split(':').pop();
  const m = (tok) => { const t = String(tok || '').replace(/^\//, '').toLowerCase(); return t === full || t === tail || t.endsWith(':' + tail); };
  const w = CMD_WRAP.exec(prompt);
  if (w && m(w[1])) return 'user';
  if (/^\//.test(prompt) && m(prompt.split(/\s+/)[0])) return 'user';
  return 'model';
}
// 실 슬래시 커맨드 확장은 transcript 에 항상 <command-name> 래퍼가 있다(실측 28+6건) — "/tmp 폴더 정리해줘" 같은
// 경로로 시작하는 평문을 커맨드로 오인하지 않게 래퍼만 본다.
const commandName = (prompt) => {
  const w = CMD_WRAP.exec(prompt);
  return w ? w[1].replace(/^\//, '') : null;
};

// 레포의 모든 ref + reflog 에서 committer time 이 [since, until] 초 구간인 커밋 [{ sha(짧은 형식), ct, subject }] (오래된 것부터). 실패는 [].
// HEAD 만 보면 확정(지연 1턴·SessionEnd·따라잡기) 전에 브랜치를 바꾸거나 amend·rebase 한 커밋을 놓친다 → --all --reflog.
// 끝은 tool_result 시각(초 절사)에서 자른다 — 커밋은 결과보다 먼저 끝나므로 커미터 시각 ≤ 결과 시각. 여유를 두면 결과
// 몇 초 뒤의 amend(다음 턴·pre-commit 수정 뒤 재커밋)가 이 명령의 커밋으로 잡히고 원래 커밋은 SHA 연결을 잃는다(실측).
// 창은 git 의 --since/--until 에만 맡기지 않고 %ct 로 다시 확인한다(창 밖 커밋은 어떤 경로로도 후보가 아니다).
function gitCommitsBetween(root, sinceMs, untilMs) {
  if (!root || !Number.isFinite(sinceMs) || !Number.isFinite(untilMs)) return [];
  const lo = Math.floor(sinceMs / 1000) - GIT_SLACK_S;
  const hi = Math.floor(untilMs / 1000);
  try {
    const out = require('child_process').execFileSync('git', [
      'log', '--all', '--reflog', '--format=%h%x00%ct%x00%s', '-n', '20', `--since=@${lo}`, `--until=@${hi}`,
    ], { cwd: root, encoding: 'utf8', timeout: 2000, stdio: ['ignore', 'pipe', 'ignore'] });
    return out.split('\n').filter((l) => l.trim()).map((l) => {
      const [sha, ct, subject = ''] = l.split('\0');
      return { sha: sha.trim(), ct: Number(ct), subject: subject.trim() };
    }).filter((c) => c.ct >= lo && c.ct <= hi).reverse(); // 오래된 것부터
  } catch (_) { return []; }
}
// 다른 턴에 이미 배정된 SHA 인가 — 이번 파싱에서 앞 턴들이 가져간 것(ctx.assigned) + 이 레포 다이제스트(모든 런타임·세션)의
// turn_summary git.commits. 다이제스트는 세션 첫 기록 월 파일에 모이므로 창 시각의 달과 그 전 달을 읽는다(git-log 경로에서만,
// 파싱당 1회). 같은 (runtime, session, turn) — 같은 턴의 재파싱 — 은 빼고 본다. 짧은/긴 SHA 는 접두로 비교.
const shaEq = (a, b) => a.startsWith(b) || b.startsWith(a);
function shaTaken(ctx, root, ms, key, sha) {
  if (ctx.assigned.some((x) => x.key !== key && shaEq(x.sha, sha))) return true;
  if (!ctx.recorded) {
    ctx.recorded = [];
    const d = new Date(ms);
    const months = [P.month(d.toISOString()), P.month(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - 1, 15)).toISOString())];
    for (const m of new Set(months)) {
      let names;
      try { names = fs.readdirSync(path.join(P.digestsDir(root), m)); } catch (_) { continue; }
      for (const n of names) {
        let text;
        try { text = fs.readFileSync(path.join(P.digestsDir(root), m, n), 'utf8'); } catch (_) { continue; }
        for (const line of text.split('\n')) {
          if (!line.includes('"turn_summary"') || line.includes('"commits":[]')) continue;
          let r;
          try { r = JSON.parse(line); } catch (_) { continue; }
          const k = `${r.runtime}\0${r.session}\0${r.turn}`;
          for (const s of (r.git && Array.isArray(r.git.commits) ? r.git.commits : [])) if (typeof s === 'string') ctx.recorded.push({ key: k, sha: s });
        }
      }
    }
  }
  return ctx.recorded.some((x) => x.key !== key && shaEq(x.sha, sha));
}
// git commit 명령 1회 → 커밋 1개. 제목이 명령 문자열(-m·heredoc)에 나오는 것 중 최신 1개(source "git-log").
// 대조가 다 빗나가면(-F·--amend --no-edit 등) 창의 최신 1개를 낮은 신뢰로(source "git-log-weak") — 같은 창의
// 다른 터미널·세션·사람의 커밋을 오귀속할 수 있다. 버리지 않는 이유: -F 커밋까지 committed 에서 빠진다.
function pickOwnCommit(cands, cmd) {
  const own = cands.filter((c) => c.subject && cmd.includes(c.subject));
  return own.length ? own.slice(-1).map((c) => ({ ...c, source: 'git-log' }))
    : cands.slice(-1).map((c) => ({ ...c, source: 'git-log-weak' }));
}

const relPath = (p, roots) => {
  if (typeof p !== 'string' || !p) return null;
  for (const r of roots) {
    const rel = path.relative(r, path.resolve(r, p));
    if (rel && !rel.startsWith('..') && !path.isAbsolute(rel)) return rel.split(path.sep).join('/');
  }
  return null;
};

// 턴 1개 → { summary(turn_summary), commits:[commit 이벤트] }. 요약할 게 없으면(assistant·취소 둘 다 없음) null.
// ctx — 한 파싱 실행의 턴 간 공유 상태(배정된 SHA). 단독 호출이면 빈 상태.
function summarize(turn, next, session, root, ctx = { assigned: [], recorded: null }) {
  const key = `${RUNTIME}\0${session}\0${turn.id}`;
  const prompt = turn.promptRec ? textOf(contentOf(turn.promptRec)) : '';
  const roots = root ? [...new Set([root, P.real(root)])] : [];
  const usage = new Map(); // message.id → usage (마지막 값)
  const uses = new Map();  // tool_use id → { name, input, ts, cat }
  const order = [];
  let model = null; let effort = null; let assistant = 0;
  let interrupt = 0; let rejected = 0; let fail = 0; let results = 0;
  let rejectOpen = false; // 마지막 거부 뒤 assistant 진행이 아직 없음
  let pushed = false; let branch = null; let tsEnd = null;
  const shaSeen = new Set();
  const commits = []; // { sha, source, ts }
  let readN = 0; let newN = 0;
  const edited = new Set();
  const subagents = [];
  const skills = [];

  for (const r of turn.recs) {
    if (r.timestamp && (!tsEnd || r.timestamp > tsEnd)) tsEnd = r.timestamp;
    if (r.gitBranch) branch = r.gitBranch;
    const c = contentOf(r);
    if (r.type === 'assistant') {
      const m = r.message || {};
      if (m.model && m.model !== '<synthetic>') {
        assistant++;
        rejectOpen = false;
        model = m.model;
        if (m.id && m.usage) usage.set(m.id, m.usage);
      }
      if (r.effort) effort = r.effort;
      for (const b of Array.isArray(c) ? c : []) {
        if (!b || b.type !== 'tool_use' || !b.id || uses.has(b.id)) continue;
        const u = { name: b.name, input: b.input || {}, ts: r.timestamp, cat: catOf(b.name) };
        uses.set(b.id, u);
        order.push(u);
        if (b.name === 'Read' || b.name === 'NotebookRead') readN++;
        if (u.cat === 'edit') {
          const rel = relPath(u.input.file_path || u.input.notebook_path, roots);
          if (rel) edited.add(rel);
        }
        if (b.name === 'Skill' && u.input.skill) skills.push({ name: u.input.skill, trigger: triggerOf(u.input.skill, prompt) });
        if (u.cat === 'subagent') { u.sub = { type: u.input.subagent_type || null, agent_id: null, async: false, dur_ms: null, tools_n: null }; subagents.push(u.sub); }
      }
      continue;
    }
    if (r.type !== 'user') continue;
    if (INTERRUPT_RE.test(textOf(c))) { interrupt++; continue; }
    for (const b of Array.isArray(c) ? c : []) {
      if (!b || b.type !== 'tool_result') continue;
      results++;
      const u = uses.get(b.tool_use_id);
      const tur = r.toolUseResult;
      const isReject = b.is_error === true && (tur === 'User rejected tool use' || REJECT_TEXT_RE.test(toolResultText(b)));
      if (isReject) { rejected++; rejectOpen = true; }
      else if (b.is_error === true) fail++;
      if (!u) continue;
      if (tur && typeof tur === 'object') {
        if (u.cat === 'edit' && tur.type === 'create') newN++;
        if (u.sub) {
          u.sub.agent_id = tur.agentId || null;
          u.sub.async = tur.isAsync === true || tur.status === 'async_launched';
          u.sub.dur_ms = Number.isFinite(tur.totalDurationMs) ? tur.totalDurationMs : null;
          u.sub.tools_n = Number.isFinite(tur.totalToolUseCount) ? tur.totalToolUseCount : null;
        }
        const gop = tur.gitOperation;
        if (gop && gop.push) pushed = true;
        if (u.name === 'Bash' && b.is_error !== true) {
          const cmd = String(u.input.command || '');
          if (hasGitSub(cmd, 'push')) pushed = true;
          if (hasGitSub(cmd, 'commit') || (gop && gop.commit)) {
            const found = [];
            const gc = gop && gop.commit;
            const gsha = gc && (typeof gc === 'string' ? gc : gc.sha || gc.hash);
            if (typeof gsha === 'string' && /^[0-9a-f]{7,40}$/.test(gsha)) found.push([gsha, 'gitop']);
            if (!found.length) for (const mm of String(tur.stdout || '').matchAll(COMMIT_LINE_RE)) found.push([mm[1], 'stdout']);
            if (!found.length) {
              const t0 = Date.parse(u.ts);
              const cands = gitCommitsBetween(root, t0, Date.parse(r.timestamp))
                .filter((cc) => !commits.some((x) => shaEq(x.sha, cc.sha)) && !shaTaken(ctx, root, t0, key, cc.sha));
              for (const cc of pickOwnCommit(cands, cmd)) found.push([cc.sha, cc.source]);
            }
            for (const [sha, source] of found) {
              if (shaSeen.has(sha)) continue;
              shaSeen.add(sha);
              commits.push({ sha, source, ts: r.timestamp });
              ctx.assigned.push({ key, sha });
            }
          }
        }
      }
    }
  }
  if (!assistant && !interrupt) return null; // 로컬 커맨드만 있는 턴 등 — 요약 대상 아님

  // 사용자 슬래시 커맨드가 스킬로 확장된 턴 — Skill 툴 호출이 없으므로 커맨드명을 user 스킬로 남긴다
  const cmd = commandName(prompt);
  if (cmd && !skills.some((s) => triggerOf(s.name, '/' + cmd) === 'user')) skills.unshift({ name: cmd, trigger: 'user', via: 'command' });

  const counts = { read: 0, search: 0, edit: 0, exec: 0, web: 0, subagent: 0, skill: 0, mcp: 0, plan: 0, other: 0 };
  const execKinds = { test: 0, git: 0, lint: 0, build: 0, pkg: 0, other: 0 };
  const runs = [];
  for (const u of order) {
    counts[u.cat]++;
    let tok = LETTER[u.cat];
    if (u.cat === 'exec' && u.name === 'Bash') { const k = execKind(u.input.command); execKinds[k]++; tok += `(${k})`; }
    const lastRun = runs[runs.length - 1];
    if (lastRun && lastRun[0] === tok) lastRun[1]++;
    else runs.push([tok, 1]);
  }
  let seq = runs.slice(0, SEQ_MAX_RUNS).map(([t, n]) => t + n).join('>');
  if (runs.length > SEQ_MAX_RUNS) seq += `>…+${runs.length - SEQ_MAX_RUNS}`;

  const tokens = { in: 0, out: 0, cache_r: 0, cache_w: 0 };
  for (const u of usage.values()) {
    tokens.in += u.input_tokens || 0;
    tokens.out += u.output_tokens || 0;
    tokens.cache_r += u.cache_read_input_tokens || 0;
    tokens.cache_w += u.cache_creation_input_tokens || 0;
  }

  // outcome (결정론, 우선순위 순): committed > cancelled > corrected > failed > unknown
  //   corrected = 리포트 교정 후보 쌍 규칙 그대로 — 스킬/에이전트를 쓴 턴 직후의 평문(비커맨드) 프롬프트.
  //   사용자 슬래시 커맨드(via:"command")는 리포트처럼 직접 호출로 보고 쌍을 만들지 않는다 — Skill 툴·서브에이전트만.
  //   "교정 후보"이지 확정이 아니다(교정 여부 판정은 리포트 시점 LLM 몫).
  //   next 는 다음 사람 턴이다 — 알림·! 모드는 턴이 아니라(segment) 평문 후속으로 세지 않는다.
  //   cancelled = Esc 마커 또는 뒤에 assistant 진행이 없는 거부(거부 뒤 계속 진행한 턴은 취소가 아니다).
  const nextPrompt = next && next.promptRec ? textOf(contentOf(next.promptRec)) : null;
  const nextIsPlain = nextPrompt != null && !CMD_WRAP.test(nextPrompt);
  let outcome = 'unknown';
  if (commits.length) outcome = 'committed';
  else if (interrupt || (rejected && rejectOpen)) outcome = 'cancelled';
  else if ((skills.some((s) => s.via !== 'command') || subagents.length) && nextIsPlain) outcome = 'corrected';
  else if (results && fail / results >= FAIL_RATIO) outcome = 'failed';

  const first = turn.recs.find((r) => r.timestamp);
  const tsStart = first ? first.timestamp : null;
  const dur = Date.parse(tsEnd) - Date.parse(tsStart);
  const turnSrc = turn.pid ? 'native' : 'synthetic';
  const lead = turn.promptRec || turn.sysRec;
  const summary = {
    v: P.SCHEMA_VERSION, kind: 'turn_summary', runtime: RUNTIME, session, turn: turn.id, turn_src: turnSrc,
    prompt_kind: turn.sys || 'user', // user | notification | bash — 리포트는 user 턴만 outcome 분모로 쓴다
    ts_start: tsStart, ts_end: tsEnd, dur_ms: Number.isFinite(dur) ? dur : null,
    model, effort, permission_mode: (lead && lead.permissionMode) || null,
    tokens,
    tools: { seq_compact: seq, counts, fail, interrupt, rejected },
    exec_kinds: execKinds,
    files: { edited: [...edited].slice(0, EDITED_MAX), edited_n: edited.size, read_n: readN, new_n: newN },
    skills,
    subagents: subagents.map(({ type, agent_id: aid, async, dur_ms: d, tools_n: n }) => ({ type, agent_id: aid, async, dur_ms: d, tools_n: n })),
    git: { branch, commits: commits.map((c) => c.sha), pushed },
    outcome,
  };
  const commitEvents = commits.map((c) => ({
    v: P.SCHEMA_VERSION, ts: c.ts, runtime: RUNTIME, session, turn: turn.id, turn_src: turnSrc,
    kind: 'commit', commit: { sha: c.sha, branch, source: c.source },
  }));
  return { summary, commits: commitEvents };
}

// digest.run 의 parse 콜백 — offset 부터 읽어 확정 가능한 턴만 요약한다.
//   final=false: 마지막 턴(진행 중·Stop 직후 미flush·generic 루프 재진입·뒤따를 완료 알림 흡수 가능)은 남기고 그 시작
//                바이트를 새 offset 으로 — 확정하는 턴마다 corrected 판정용 "다음 사람 턴"이 창 안에 있게. 시스템 주입 턴은
//                창 첫머리에만 생기므로(segment) 그 뒤의 턴은 모두 사람 턴이다 — 다음 사람 턴이 오면 바로 확정된다.
//   final=true : 마지막 턴까지 확정, offset = 마지막 완결 라인 끝.
function parseTurns(transcript, offset, final, root, session) {
  const { lines, end } = readLines(transcript, offset);
  const turns = segment(lines);
  const upto = final ? turns.length : Math.max(0, turns.length - 1);
  const ctx = { assigned: [], recorded: null };
  const out = [];
  for (let i = 0; i < upto; i++) {
    const s = summarize(turns[i], turns[i + 1] || null, session, root, ctx);
    if (s) out.push(s);
  }
  return { turns: out, offset: upto < turns.length ? turns[upto].off : end };
}

// Codex rollout 인가 — 첫 줄이 type "session_meta" (실측). 읽기 실패는 false(digest.run 이 알아서 무처리).
function foreignTranscript(file) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const b = Buffer.alloc(256);
    const n = fs.readSync(fd, b, 0, b.length, 0);
    return /^\{[^\n]*?"type":"session_meta"/.test(b.toString('utf8', 0, n));
  } catch (_) { return false; } finally { if (fd !== undefined) fs.closeSync(fd); }
}

// 런타임 고정 래퍼 — digest.run 호출 (Stop 훅·worker 공용). Claude transcript 가 아니면 아무것도 하지 않는다.
function digestSession(root, session, transcript, final) {
  if (foreignTranscript(transcript)) return null;
  const D = require('../../_lib/digest');
  return D.run(root, RUNTIME, session, transcript,
    (t, off, fin, r) => parseTurns(t, off, fin, r, session), { final });
}

// detached worker 띄우기 — SessionEnd(1.5s 예산)·SessionStart 는 기다리지 않는다. 실패는 삼킨다.
function spawnWorker(job) {
  try {
    const child = require('child_process').spawn(process.execPath, [__filename, '--worker', JSON.stringify(job)],
      { detached: true, stdio: 'ignore' });
    child.unref();
  } catch (_) { /* best-effort */ }
}

// worker 본체 — mode "end": 그 세션 마감(final) + session_summary.
//   mode "catchup": 현재 세션 커서 확보 + 마감 안 된(또는 마감 뒤 resume 으로 자란) 세션 커서들을 따라잡는다(같은 함수, upsert-skip).
//   다른 세션은 transcript 가 IDLE_FINAL_MS 넘게 갱신이 없으면 마감(SessionEnd 를 못 받은 세션), 아니면 확정 턴만.
function runJob(job) {
  const D = require('../../_lib/digest');
  if (job.mode === 'end') return digestSession(job.root, job.session, job.transcript, true);
  if (job.mode !== 'catchup') return null;
  if (job.session && job.transcript && !foreignTranscript(job.transcript)) D.ensureCursor(job.root, RUNTIME, job.session, job.transcript);
  const now = job.now || Date.now();
  for (const c of D.listCursors(job.root, RUNTIME)) {
    const t = c.session === job.session ? job.transcript : D.untildify(c.transcript);
    if (c.final && !D.grownSince(c, t)) continue; // 마감 후 resume 으로 자란 세션은 다시 처리
    let mtime;
    try { mtime = fs.statSync(t).mtimeMs; } catch (_) { continue; } // transcript 소실 — 건너뜀
    const final = c.session !== job.session && now - mtime > IDLE_FINAL_MS;
    try { digestSession(job.root, c.session, t, final); } catch (_) { /* 세션 하나 실패가 나머지를 막지 않게 */ }
  }
  return null;
}

module.exports = {
  RUNTIME, readLines, segment, summarize, parseTurns, digestSession, spawnWorker, runJob, execKind, hasGitSub, catOf, IDLE_FINAL_MS,
  // 다른 런타임 어댑터 공용 (P6)
  segments, gitCommitsBetween, pickOwnCommit, relPath, COMMIT_LINE_RE, FAIL_RATIO, EDITED_MAX, SEQ_MAX_RUNS, LETTER,
};

if (require.main === module && process.argv[2] === '--worker') {
  try { runJob(JSON.parse(process.argv[3])); } catch (_) { /* best-effort */ }
}
