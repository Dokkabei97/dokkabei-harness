// SKILL.md 경로 읽기 휴리스틱 — Skill 툴이 없는 런타임(Codex·Antigravity)의 스킬 사용 감지(skill.detection "heuristic").
// 모델이 스킬을 쓰려면 SKILL.md 본문을 셸 읽기 명령(sed -n·cat·head …)이나 파일 보기 툴로 연다(Codex rollout 실측:
// `sed -n '1,220p' ~/.codex/plugins/cache/openai-curated/github/<ver>/skills/yeet/SKILL.md`). 그 경로에서 스킬 이름을 만든다.
// 읽기가 아닌 접촉(apply_patch 로 SKILL.md 편집, heredoc 본문 속 문자열, rg 검색)은 사용이 아니다 — 읽기 동사로 시작하는
// 세그먼트만 본다. 읽기 동사로 시작해도 쓰기인 것도 뺀다: 리다이렉트 대상(`cat > …/SKILL.md`, `cat a > …`), 제자리 편집
// (`sed -i`/`--in-place`). tee 는 읽기 동사가 아니라 이미 안 걸린다. glob 경로(`head plugins/*/skills/*/SKILL.md`)는
// 특정 스킬 사용이 아니라 목록 훑기라 이름에 glob 문자(*?[])가 남으면 버린다.
// 이름이 `.`·`..`(`cat ./SKILL.md`·`../SKILL.md`)이거나 셸 변수·중괄호(`$SKILL_DIR/SKILL.md`)면 실제 디렉터리 이름이 아니라 버린다.
// 플러그인 소스 편집용 읽기도 사용이 아니다: 호출측이 roots(세션 레포 루트)를 주면, 설치본 표지(plugins/cache·.codex/skills·
// .claude/skills·.agents/skills)가 없는 상대경로·레포 안 경로(`plugins/<p>/skills/<s>/SKILL.md` — 플러그인 저작 레포)는 버린다
// (실측 40건 중 2건: dokkabei-harness-codex 의 plugins/etc/skills/{web-fetch,with}). 레포 밖 절대경로는 그대로 센다.
// 같은 턴의 같은 스킬은 한 번만 센다(dedupe 는 호출측: 턴 요약은 Set, 훅은 (turn, skill) 마커).
const { segments } = require('../adapters/claude/transcript');

// 읽기 동사 — 세그먼트 첫 단어. grep/rg 는 검색이라 제외(스킬 목록 훑기와 사용을 구분 못 한다).
const READ_VERB = /^(?:sed|cat|head|tail|less|more|nl|bat|awk|Get-Content)\b/;
const SED_INPLACE = /^sed\b.*\s(?:-[A-Za-z]*i|--in-place)/; // sed -i / -ni / --in-place — 편집
const REDIRECT_BEFORE = />\|?\s*['"]?$/;                      // 경로 바로 앞이 > · >> · >| — 쓰기 대상
const GLOB = /[*?[\]]/;
const BAD_NAME = /^\.\.?$|[${}]/;
const INSTALLED = /(?:^|\/)(?:plugins\/cache|\.codex\/skills|\.claude\/skills|\.agents\/skills)\//;
// 레포 소스 읽기 — roots(비어 있지 않은)가 주어졌고, 설치본 표지가 없고, 상대경로이거나 roots 아래 절대경로
function sourceRead(s, roots) {
  if (!Array.isArray(roots) || !roots.length || INSTALLED.test(s)) return false;
  if (!/^[/~]/.test(s)) return true;
  const abs = s.startsWith('~/') ? require('os').homedir() + s.slice(1) : s;
  return roots.some((r) => r && abs.startsWith(r.replace(/\/$/, '') + '/'));
}
// 플러그인 레이아웃 → "<plugin>:<skill>" (Claude Skill 툴 이름과 같은 네임스페이스):
//   …/plugins/cache/<마켓>/<plugin>/<버전>/skills/<skill>/SKILL.md  (Codex·Claude 설치 캐시)
//   …/plugins/<plugin>/skills/<skill>/SKILL.md                     (마켓 레포·marketplaces 클론)
// 그 밖(~/.codex/skills/.system/imagegen, .agents/skills/x 등)은 부모 디렉터리 이름.
const PLUGIN_SKILL = /(?:^|\/)plugins\/(?:cache\/[^/]+\/([^/]+)\/[^/]+|([^/]+))\/skills\/([^/]+)\/SKILL\.md$/;
const SKILL_PATH = /(?:^|[\s'"=(])((?:[^\s'"`;|&<>()]*\/)?([^\s'"`;|&<>()/]+)\/SKILL\.md)(?=$|[\s'"`;|&<>)])/g;

// 경로 → 스킬 이름 (SKILL.md 가 아니거나, 이름이 디렉터리 이름이 아니거나, roots 기준 레포 소스 읽기면 null)
function skillNameOf(p, roots) {
  const s = String(p || '').replace(/\\/g, '/');
  if (!/(?:^|\/)SKILL\.md$/.test(s) || sourceRead(s, roots)) return null;
  const m = PLUGIN_SKILL.exec(s);
  const parts = s.split('/');
  const name = m ? `${m[1] || m[2]}:${m[3]}` : parts.length >= 2 ? parts[parts.length - 2] : '';
  return name && !name.split(':').some((x) => !x || BAD_NAME.test(x)) ? name : null;
}

// 셸 명령 → 읽은 스킬 이름 목록(명령 안 중복 제거, 등장 순). heredoc 본문은 세그먼트 첫 단어가 읽기 동사가 아니라 걸리지 않는다.
function skillReads(cmd, roots) {
  const out = [];
  for (const seg of segments(cmd)) {
    if (!READ_VERB.test(seg) || SED_INPLACE.test(seg)) continue;
    for (const m of seg.matchAll(SKILL_PATH)) {
      if (REDIRECT_BEFORE.test(seg.slice(0, m.index + m[0].length - m[1].length))) continue;
      const name = skillNameOf(m[1], roots);
      if (name && !GLOB.test(name) && !out.includes(name)) out.push(name);
    }
  }
  return out;
}

module.exports = { skillNameOf, skillReads };
