#!/usr/bin/env node
// observe git 훅 설치기 — opt-in 커밋 경계 수집 (로드맵 Phase 4 · 결정 3: 커밋 직전 비차단 1줄 + 커밋 뒤 detached 분석).
// 사용:
//   node observe-git-hooks.js install   [--root <레포>] [--no-pre-commit] [--trailer]
//   node observe-git-hooks.js uninstall [--root <레포>]
//   node observe-git-hooks.js status    [--root <레포>]
//   node observe-git-hooks.js print <post-commit|pre-commit|prepare-commit-msg>  — core.hooksPath·husky·lefthook 용 훅 본문(stdout)
// 설치하는 훅 (POSIX sh — node 는 필요할 때만 띄운다. observe 부분의 실패·출력은 커밋 결과를 바꾸지 않는다):
//   post-commit        — HEAD sha 를 넘겨 분석기(adapters/git/commit.js)를 백그라운드로 띄우고 즉시 끝난다
//                        (분석기는 다시 detached worker 로 분리 → .tracer/commits/<sha>.md, LLM 은 OBSERVE_LLM=1 일 때만).
//   pre-commit         — .tracer/index/precommit.txt(미처리 추천 1줄, 결정론·LLM 없음)를 stderr 로. recommendations.jsonl 이
//                        더 새롭거나, 캐시 줄이 비어 있지 않은데 하루(1440분) 넘게 묵었으면 node 로 다시 계산한다 — 쓰기 없이 시간만
//                        흘러 만료된 제안도 하루 안에 줄에서 빠진다(시간 경과는 항목을 빼기만 하므로 빈 캐시는 find 도 띄우지 않는다).
//                        그 파일이 없으면 아무것도 내지 않는다 — 옛 캐시 무시.
//                        차단하지 않는다 — 종료코드는 기존 훅의 것(없으면 0).
//   prepare-commit-msg — (--trailer 일 때만, 기본 미설치) Claude Code 세션 안의 커밋에 "Agent-Session: claude-code/<id>" trailer.
//                        메시지가 비었으면(주석·공백·scissors 아래뿐) 붙이지 않는다 — git 의 빈 메시지 커밋 중지를 살린다.
// 모든 훅은 체이닝한 기존 훅을 먼저 실행한 뒤, OBSERVE_CHILD=1 이거나 OBSERVE_TRACE(1|true|on|yes) 가 아니면 observe 부분을
// 건너뛴다(기존 훅은 게이트와 무관하게 늘 돈다) — 셸에서 직접 하는 사람 커밋을 기록하려면 그 셸에도 OBSERVE_TRACE=1 이
// 있어야 한다(settings.json env 는 Claude Code 세션 안에만 적용).
// 체이닝: 기존 훅은 <hooks>/observe-orig/<hook> 으로 옮겨 이름·내용·권한 그대로 보존하고(같은 이름이라 basename "$0" 으로
//   분기하는 디스패처 훅도 그대로 동작), 새 훅이 "$(dirname "$0")/observe-orig/<고정 훅 이름>" 을 먼저 같은 인자로 실행한다
//   — "$0" 에 기대지 않으므로 다른 도구가 observe 훅을 개명해 체이닝해도(pre-commit 프레임워크의 <hook>.legacy) 원래 훅이
//   계속 돈다. 실행 비트가 없던 훅은 git 처럼 실행하지 않는다. pre-commit·prepare-commit-msg 는 기존 훅이 실패하면 그 종료코드로
//   끝나고(차단 의미 보존), post-commit 은 git 이 종료코드를 무시하므로 기존 훅이 실패해도 observe 부분을 계속 돈다.
//   상대경로 심볼릭 링크 훅은 한 단계 깊어지는 만큼 "../" 를 붙여 옮기고 복원 때 뗀다(가리키는 대상 불변, 깨진 링크도 보존).
//   한계: 기존 훅이 "$(dirname "$0")" 기준으로 형제 파일을 찾으면 그 기준이 observe-orig/ 로 바뀐다.
//   uninstall 은 observe 표식이 있는 훅만 지우고 백업을 제자리로 되돌린다 — 표식 없는 훅(설치 뒤 사용자가 바꾼 것)과
//   그 백업은 건드리지 않는다.
// core.hooksPath·husky(.husky/)·lefthook(설정 파일)이 있으면 .git/hooks 가 실행되지 않거나 도구가 관리하므로 설치하지 않고
//   연결 방법만 안내한다(print 출력을 그 도구의 훅에 넣는다). 설치 뒤에 core.hooksPath 가 생기면(husky 설치 등) git-path
//   hooks 가 그 디렉터리를 가리키므로, uninstall·status 는 기본 위치(<git-common-dir>/hooks)도 함께 본다 — 남은 observe 훅은
//   hooksPath 를 다시 풀면 살아난다.
// 훅에는 이 플러그인 설치본의 절대경로가 박힌다 — /plugin update 로 경로가 바뀌면 훅은 조용히 무동작하고 status 가 stale 로
//   표시한다 → 다시 install (같은 표식 훅은 제자리 갱신, 백업은 그대로).
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const P = require('./hooks/_lib/paths');

const ANALYZER = path.join(__dirname, 'hooks', 'adapters', 'git', 'commit.js');
const MARK = '# observe-git-hook v1';
const BACKUP = 'observe-orig'; // <hooks>/observe-orig/<hook>
const HOOKS = ['post-commit', 'pre-commit', 'prepare-commit-msg'];
const LEFTHOOK = ['lefthook.yml', 'lefthook.yaml', '.lefthook.yml', '.lefthook.yaml', 'lefthook.toml', 'lefthook.json'];

const q = (s) => `'${String(s).replace(/'/g, "'\\''")}'`;
const git = (cwd, args) => cp.execFileSync('git', args, { cwd, encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
const gitOr = (cwd, args) => { try { return git(cwd, args); } catch (_) { return ''; } };
const readText = (f) => { try { return fs.readFileSync(f, 'utf8'); } catch (_) { return null; } };
const lexists = (f) => { try { fs.lstatSync(f); return true; } catch (_) { return false; } }; // 깨진 심볼릭 링크도 있음으로

// 훅 본문 — 공통 머리(체이닝·게이트) + 훅별 몸통. prepare-commit-msg 는 node 를 쓰지 않아 분석기 경로 검사가 없다.
const BODY = {
  'post-commit': [
    'sha=$(git rev-parse HEAD 2>/dev/null) || exit "$rc"',
    '"$N" "$A" post-commit "$sha" </dev/null >/dev/null 2>&1 &',
  ],
  'pre-commit': [
    `R=${P.TRACER_DIR}/recommendations.jsonl`,
    `L=${P.TRACER_DIR}/index/precommit.txt`,
    'if [ -f "$R" ]; then',
    '  if [ ! -f "$L" ] || [ "$R" -nt "$L" ]; then "$N" "$A" pre-commit </dev/null >/dev/null || :',
    '  elif [ -s "$L" ]; then',
    '    if [ -n "$(find "$L" -mmin +1440 2>/dev/null)" ]; then "$N" "$A" pre-commit </dev/null >/dev/null || :',
    '    else cat "$L" >&2',
    '    fi',
    '  fi',
    'fi',
  ],
  'prepare-commit-msg': [
    'case "${2-}" in merge|squash) exit 0 ;; esac',
    's=${CLAUDE_CODE_SESSION_ID-}',
    '[ -n "$s" ] || exit 0',
    // 빈 메시지(주석 줄·공백뿐, scissors 줄 아래 무시)면 그대로 둔다 — trailer 만 남아 git 의 빈 메시지 중지가 사라지지 않게
    'c=$(git config --get core.commentChar 2>/dev/null); case "$c" in \'\'|auto) c=\'#\' ;; esac',
    'awk -v c="$c" \'index($0, c " ------------------------ >8 ------------------------") == 1 { exit } ' +
      'index($0, c) == 1 { next } /[^[:space:]]/ { f = 1; exit } END { exit !f }\' "$1" || exit 0',
    'git interpret-trailers --in-place --if-exists doNothing --trailer "Agent-Session: claude-code/$s" "$1" >/dev/null 2>&1 || :',
  ],
};
function script(hook) {
  const node = hook === 'prepare-commit-msg' ? [] : [
    `N=${q(process.execPath)}`,
    '[ -x "$N" ] || N=node',
    `A=${q(ANALYZER)}`,
    '[ -f "$A" ] || exit "$rc"',
  ];
  return [
    '#!/bin/sh',
    `${MARK} (${hook}) — observe 플러그인이 설치·관리한다. 직접 고치지 말고 observe-git-hooks.js uninstall 로 원복.`,
    `# 기존 훅은 observe-orig/${hook} 로 보존되어 먼저 실행되고, 그 종료코드가 이 훅의 종료코드다(observe 부분은 비차단).`,
    'rc=0',
    `O="$(dirname "$0")/${BACKUP}/${hook}"`,
    'if [ -x "$O" ]; then "$O" "$@"; rc=$?; fi',
    // post-commit 은 git 이 종료코드를 무시한다 — 기존 훅이 실패해도(git-lfs 미설치 등) 기록은 계속
    ...(hook === 'post-commit' ? [] : ['[ "$rc" -eq 0 ] || exit "$rc"']),
    '[ "${OBSERVE_CHILD-}" = 1 ] && exit "$rc"',
    'case "${OBSERVE_TRACE-}" in 1|[Tt][Rr][Uu][Ee]|[Oo][Nn]|[Yy][Ee][Ss]) ;; *) exit "$rc" ;; esac',
    ...node,
    ...BODY[hook],
    'exit "$rc"', // pre-commit·prepare-commit-msg 는 여기서 늘 0
  ].join('\n') + '\n';
}

// 대상 레포 — { top, hooksDir, defaultDir(core.hooksPath 없을 때의 위치), managers:[감지된 훅 관리자] }. git 저장소가 아니면 throw.
function context(rootArg) {
  const top = git(rootArg ? path.resolve(rootArg) : process.cwd(), ['rev-parse', '--show-toplevel']);
  const hooksDir = path.resolve(top, git(top, ['rev-parse', '--git-path', 'hooks']));
  const defaultDir = path.resolve(top, git(top, ['rev-parse', '--git-common-dir']), 'hooks');
  const managers = [];
  const hp = gitOr(top, ['config', '--get', 'core.hooksPath']);
  if (hp) managers.push(`core.hooksPath=${hp}`);
  if (fs.existsSync(path.join(top, '.husky'))) managers.push('husky(.husky/)');
  for (const f of LEFTHOOK) if (fs.existsSync(path.join(top, f))) managers.push(`lefthook(${f})`);
  return { top, hooksDir, defaultDir, managers };
}

// 훅 하나를 옮긴다(백업 ↔ 제자리). 상대경로 심볼릭 링크는 깊이 차이(백업은 한 단계 아래)만큼 "../" 를 붙이거나 뗀다.
function move(from, to) {
  const st = fs.lstatSync(from);
  const t = st.isSymbolicLink() ? fs.readlinkSync(from) : null;
  if (t != null && !path.isAbsolute(t)) {
    const down = path.basename(path.dirname(to)) === BACKUP;
    fs.symlinkSync(down ? '../' + t : t.replace(/^\.\.\//, ''), to);
    fs.unlinkSync(from);
  } else fs.renameSync(from, to);
}

function writeHook(f, text) {
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, text, { mode: 0o755 });
  fs.chmodSync(tmp, 0o755);
  fs.renameSync(tmp, f);
}

function install(ctx, hooks) {
  fs.mkdirSync(ctx.hooksDir, { recursive: true });
  const res = [];
  for (const h of hooks) {
    const f = path.join(ctx.hooksDir, h);
    const bak = path.join(ctx.hooksDir, BACKUP, h);
    const cur = readText(f);
    if (cur != null && cur.includes(MARK)) { writeHook(f, script(h)); res.push([h, '갱신(이미 observe 훅)']); continue; }
    if (lexists(f)) {
      if (lexists(bak)) { res.push([h, `건너뜀 — 백업 ${bak} 이 이미 있음(수동 확인 필요)`]); continue; }
      fs.mkdirSync(path.dirname(bak), { recursive: true });
      move(f, bak);
      writeHook(f, script(h));
      res.push([h, `설치 — 기존 훅을 ${BACKUP}/${h} 로 보존·체이닝`]);
      continue;
    }
    writeHook(f, script(h));
    res.push([h, '설치']);
  }
  return res;
}

function uninstall(ctx, dir = ctx.hooksDir) {
  const res = [];
  for (const h of HOOKS) {
    const f = path.join(dir, h);
    const bak = path.join(dir, BACKUP, h);
    const cur = readText(f);
    if (cur != null && cur.includes(MARK)) {
      fs.unlinkSync(f);
      if (lexists(bak)) { move(bak, f); res.push([h, '제거 — 기존 훅 복원']); } else res.push([h, '제거']);
    } else if (lexists(bak)) {
      res.push([h, `건너뜀 — ${h} 가 observe 훅이 아님(설치 뒤 바뀜), 백업 ${BACKUP}/${h} 그대로`]);
    }
  }
  try { fs.rmdirSync(path.join(dir, BACKUP)); } catch (_) { /* 없거나 남은 백업이 있음 */ }
  return res;
}

function status(ctx, dir = ctx.hooksDir) {
  const res = [];
  for (const h of HOOKS) {
    const f = path.join(dir, h);
    const cur = readText(f);
    const chained = lexists(path.join(dir, BACKUP, h)) ? ' · 기존 훅 체이닝' : '';
    if (cur == null) { res.push([h, '없음']); continue; }
    if (!cur.includes(MARK)) { res.push([h, `observe 아님(다른 훅)${chained}`]); continue; }
    const m = /^A='((?:[^']|'\\'')*)'$/m.exec(cur);
    const target = m ? m[1].replace(/'\\''/g, "'") : null;
    res.push([h, `observe 훅${chained}${target && !fs.existsSync(target) ? ' · stale(분석기 경로 없음 — 다시 install)' : ''}`]);
  }
  return res;
}

function guidance(ctx) {
  return [
    `observe: ${ctx.managers.join(', ')} 감지 — .git/hooks 에 설치하지 않았습니다(그 훅 위치는 다른 도구가 관리하거나 git 이 읽지 않음).`,
    '  직접 연결: 아래 출력을 그 도구가 실행하는 훅 파일(예: <core.hooksPath>/post-commit, .husky/post-commit,',
    '  lefthook 의 post-commit run 스크립트)에 넣고 실행 권한을 주세요. pre-commit 도 같은 방식입니다.',
    `    node ${q(__filename)} print post-commit`,
    `    node ${q(__filename)} print pre-commit`,
  ].join('\n');
}

function main(argv) {
  const cmd = argv[0];
  const opt = (k) => argv.includes(k);
  const val = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : null; };
  if (cmd === 'print') {
    const h = argv[1];
    if (!HOOKS.includes(h)) { process.stderr.write(`알 수 없는 훅: ${h} (${HOOKS.join('|')})\n`); return 1; }
    process.stdout.write(script(h));
    return 0;
  }
  if (!['install', 'uninstall', 'status'].includes(cmd)) {
    process.stderr.write('사용: observe-git-hooks.js install|uninstall|status|print <hook> [--root <레포>] [--no-pre-commit] [--trailer]\n');
    return 1;
  }
  let ctx;
  try { ctx = context(val('--root')); } catch (_) {
    process.stderr.write(`git 저장소가 아님: ${val('--root') || process.cwd()}\n`);
    return 1;
  }
  const show = (rows) => { for (const [h, s] of rows) process.stdout.write(`  ${h.padEnd(19)} ${s}\n`); };
  // core.hooksPath 가 설치 뒤에 생긴 경우의 기본 위치 — observe 흔적이 있을 때만 보인다
  const other = ctx.defaultDir !== ctx.hooksDir ? ctx.defaultDir : null;
  const otherNote = '(core.hooksPath 밖 기본 위치 — 지금은 git 이 실행하지 않지만 hooksPath 를 풀면 다시 돈다)';
  if (cmd === 'install') {
    if (ctx.managers.length) { process.stdout.write(guidance(ctx) + '\n'); return 0; }
    const hooks = ['post-commit', ...(opt('--no-pre-commit') ? [] : ['pre-commit']), ...(opt('--trailer') ? ['prepare-commit-msg'] : [])];
    process.stdout.write(`observe git 훅 설치: ${ctx.hooksDir}\n`);
    show(install(ctx, hooks));
    process.stdout.write('  (OBSERVE_TRACE=1 인 셸·세션의 커밋만 기록 — 원복: uninstall)\n');
    return 0;
  }
  if (cmd === 'uninstall') {
    const rows = uninstall(ctx);
    process.stdout.write(`observe git 훅 제거: ${ctx.hooksDir}\n`);
    show(rows.length ? rows : [['-', 'observe 훅 없음']]);
    const more = other ? uninstall(ctx, other) : [];
    if (more.length) { process.stdout.write(`observe git 훅 제거: ${other} ${otherNote}\n`); show(more); }
    return 0;
  }
  process.stdout.write(`observe git 훅 상태: ${ctx.hooksDir}${ctx.managers.length ? ` (감지: ${ctx.managers.join(', ')})` : ''}\n`);
  show(status(ctx));
  const more = other ? status(ctx, other).filter(([, s]) => s.startsWith('observe 훅')) : [];
  if (more.length) { process.stdout.write(`  남은 observe 훅: ${other} ${otherNote} — uninstall 로 정리\n`); show(more); }
  return 0;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));
module.exports = { script, context, install, uninstall, status, MARK, BACKUP, HOOKS };
