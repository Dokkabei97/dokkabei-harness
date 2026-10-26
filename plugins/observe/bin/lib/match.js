// 결정론 매처 — 프롬프트 ↔ 자산(스킬·커맨드) description 의 BM25 랭킹 (의존성 없음).
//
// 위치: 추천 엔진(recommend.js)의 후보 수집기다. 판정은 /observe-report 의 LLM 단계 몫이라
//   정밀도가 다소 낮아도 된다 — 대신 같은 입력이면 같은 점수·같은 순서(동점은 id 오름차순)를 보장한다.
// 토크나이즈: 한글 구간은 문자 bigram(ES cjk_bigram 과 같은 방식, 한 글자 구간은 unigram),
//   영문·숫자는 소문자 단어(2자 이상, 짧은 불용어 제외). 코드 식별자 "sync-claude-md" 는 sync/claude/md.
// 필드 가중치(BM25F — 필드별 tf 를 가중 합산한 뒤 BM25 포화):
//   따옴표 트리거 문구 정확 일치(보너스) > triggers:(+auto_activate.patterns, 커맨드 ## Triggers) > Use when 절 > 산문.
//   따옴표 문구는 토큰이 아니라 "프롬프트에 그 문구가 통째로 들어 있나"로 본다(공백 무시, 소문자).
const fs = require('fs');

const K1 = 1.2;
const B = 0.75;
const W = { triggers: 3, usewhen: 2, prose: 1 };
const PHRASE_BONUS = 5; // 따옴표 트리거 문구 1개 정확 일치당 가산 (필드 가중치보다 위)
const QUERY_MAX = 1000; // 질의는 앞 1000자만 — 붙여넣은 로그로 점수 척도가 폭주하지 않게

const STOP = new Set(('the a an and or of to in on for with by is are be as at it its this that from into use when ' +
  'used using via any all not no do does can will should you your user users skill skills when how what which ' +
  'only also then than more most such these those there here about after before over under up out if').split(' '));

const HANGUL = /\p{Script=Hangul}+/gu; // 음절·자모·호환 자모

function tokenize(text) {
  const s = String(text || '').toLowerCase();
  const out = [];
  // 한글 구간 → bigram, 나머지 → 영숫자 단어. 구간 순서는 토큰 순서에 의미가 없어 따로 모은다.
  for (const m of s.match(HANGUL) || []) {
    if (m.length === 1) out.push(m);
    else for (let i = 0; i + 1 < m.length; i++) out.push(m.slice(i, i + 2));
  }
  for (const w of s.replace(HANGUL, ' ').match(/[a-z0-9]+/g) || [])
    if (w.length >= 2 && !STOP.has(w)) out.push(w);
  return out;
}

// 따옴표 문구 정규화 — 정확 일치 판정용 (공백 제거 + 소문자)
const squash = (s) => String(s || '').toLowerCase().replace(/\s+/g, '');

// ── frontmatter 최소 파서 ── YAML 전체가 아니라 이 레포 실측 형태만: 인라인 스칼라(따옴표 유무),
// 블록 스칼라(| >), 들여쓴 "- 항목" 목록, 한 단계 중첩 맵 안의 목록(auto_activate.patterns).
function frontmatter(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
  if (!m) return { fields: {}, body: text };
  const blocks = {}; // 최상위 키 → { inline, lines[] }
  let cur = null;
  for (const line of m[1].split(/\r?\n/)) {
    const k = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(line);
    if (k) { cur = blocks[k[1]] = { inline: k[2], lines: [] }; continue; }
    if (cur) cur.lines.push(line);
  }
  const unq = (v) => {
    const t = String(v).trim();
    if (t.startsWith('"')) { try { return JSON.parse(t); } catch (_) { return t.replace(/^"|"$/g, ''); } }
    return t.replace(/^'|'$/g, '');
  };
  const scalar = (b) => {
    if (!b) return '';
    const v = b.inline.trim();
    if (/^[|>][-+]?$/.test(v)) return b.lines.map((l) => l.trim()).join('\n').trim();
    // 인라인 값 + 들여쓴 연속 줄(plain multi-line)
    return [unq(v), ...b.lines.filter((l) => /^\s+\S/.test(l) && !/^\s*-\s/.test(l)).map((l) => l.trim())].join(' ').trim();
  };
  const items = (b) => {
    if (!b) return [];
    const v = b.inline.trim();
    if (v.startsWith('[')) return v.replace(/^\[|\]$/g, '').split(',').map(unq).filter(Boolean);
    return b.lines.map((l) => /^\s*-\s+(.*)$/.exec(l)).filter(Boolean).map((x) => unq(x[1])).filter(Boolean);
  };
  return {
    fields: {
      name: scalar(blocks.name),
      description: scalar(blocks.description),
      triggers: [...items(blocks.triggers), ...items(blocks.auto_activate)],
    },
    body: text.slice(m[0].length),
  };
}

// description → { quoted[], usewhen, prose }. Use when 절은 "Use when" 부터 문장 끝(마침표+공백/끝)까지,
// 여러 개면 전부(이 레포 bilingual 규약: 한국어 원문 쪽 + 영어 요약 쪽). 산문 = 나머지.
function splitDescription(desc) {
  const d = String(desc || '');
  const quoted = [];
  // 따옴표 쌍은 줄바꿈을 넘을 수 있다(블록 스칼라에서 문구가 두 줄로 접힘 — 실측 evolve) — 넘지 못하면 짝이 어긋난다
  for (const m of d.matchAll(/["“「]([^"”」]{2,60})["”」]/g)) {
    const p = m[1].replace(/\s+/g, ' ').trim();
    if (/[\p{L}\p{N}]/u.test(p) && !/^[,;:]/.test(p)) quoted.push(p);
  }
  const uw = [];
  const prose = d.replace(/use when\b[\s\S]*?(?:[.。](?=\s|$)|$)/gi, (x) => { uw.push(x); return ' '; });
  return { quoted, usewhen: uw.join(' '), prose };
}

// 커맨드 본문의 "## Triggers" 절 불릿 — 커맨드는 frontmatter 에 트리거가 없고 여기에 둔다(레포 규약)
function bodyTriggers(body) {
  const m = /^##\s*Triggers\s*\n([\s\S]*?)(?=^##\s|$(?![\s\S]))/m.exec(body || '');
  return m ? m[1].split('\n').map((l) => /^\s*[-*]\s+(.*)$/.exec(l)).filter(Boolean).map((x) => x[1]) : [];
}

// 자산 유형 공변량 — 오케스트레이터·가이드형은 단발 프롬프트에서 언어와 무관하게 잘 발화하지 않는다(메모리 실측).
// 미발화를 "description 탓"으로 돌리지 않게 함께 기록만 한다(판정에 쓰지 않음).
function skillType(name, desc) {
  const n = String(name || '').toLowerCase();
  const head = String(desc || '').slice(0, 120);
  if (/orchestrat/.test(n) || /오케스트레이터|orchestrator/i.test(head)) return 'orchestrator';
  if (/(^|-)(guide|patterns|internals|conventions|checklist|architecture)$/.test(n) || /가이드|레퍼런스|reference|guide\b/i.test(head)) return 'guide';
  return 'action';
}

// 자산 문서 하나 → 매칭 문서. item = {id, kind, path, source}
function docOf(item) {
  let text = '';
  try { text = fs.readFileSync(item.path, 'utf8'); } catch (_) { /* 읽기 실패 — 빈 문서 */ }
  const { fields, body } = frontmatter(text);
  const parts = splitDescription(fields.description);
  const triggers = [...fields.triggers, ...(item.kind === 'command' ? bodyTriggers(body) : [])];
  const nameTok = String(item.id).split(':').pop();
  const type = skillType(nameTok, fields.description);
  return {
    id: item.id, kind: item.kind, source: item.source || null, type,
    has_use_when: /use when/i.test(fields.description),
    // triggers: 항목은 문구 보너스 없이 필드 가중치만(순서 규약). 영문·숫자만인 문구는 단어 경계 정규식으로 맞춘다 —
    // 공백 제거 substring 이면 "PR" 이 "improve"·"express" 안에서 맞는다. 한글이 섞인 문구는 띄어쓰기 변형("코드 리뷰"/"코드리뷰")
    // 때문에 공백 제거 substring 그대로.
    // 같은 문구(공백 제거 기준)는 한 번만 가산한다.
    quoted: [...new Map(parts.quoted.filter((q) => squash(q).length >= 2).map((q) => [squash(q), /^[\x20-\x7e]+$/.test(q)
      ? new RegExp(`(?<![a-z0-9])${q.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/ +/g, '\\s*')}(?![a-z0-9])`)
      : squash(q)])).values()],
    fields: {
      triggers: tokenize(triggers.join(' ')),
      usewhen: tokenize(parts.usewhen),
      prose: tokenize(parts.prose + ' ' + nameTok.replace(/[-_]/g, ' ')),
    },
    body: type === 'orchestrator' ? body.toLowerCase() : null, // 오케스트레이터만 — orchestrate→missed 분기의 "연쇄 포함" 판정용
  };
}

// 인덱스 — docs 의 가중 tf·길이·df 를 미리 계산
function buildIndex(items) {
  const docs = items.map(docOf);
  const df = new Map();
  let total = 0;
  for (const d of docs) {
    d.tf = new Map();
    d.len = 0;
    for (const [f, toks] of Object.entries(d.fields)) {
      d.len += W[f] * toks.length;
      for (const t of toks) d.tf.set(t, (d.tf.get(t) || 0) + W[f]);
    }
    for (const t of d.tf.keys()) df.set(t, (df.get(t) || 0) + 1);
    total += d.len;
  }
  const N = docs.length;
  const avgdl = N ? total / N : 0;
  const idf = (t) => Math.log(1 + (N - (df.get(t) || 0) + 0.5) / ((df.get(t) || 0) + 0.5));
  return { docs, df, N, avgdl, idf };
}

// 질의 → 전체 랭킹 [{id, score}] (점수 > 0 만, 점수 내림차순·id 오름차순). 점수는 소수 셋째 자리 반올림.
function search(index, query) {
  const q = String(query || '').slice(0, QUERY_MAX);
  const terms = [...new Set(tokenize(q))];
  const qs = squash(q);
  const ql = q.toLowerCase();
  const out = [];
  for (const d of index.docs) {
    let s = 0;
    for (const t of terms) {
      const tf = d.tf.get(t);
      if (!tf) continue;
      const norm = K1 * (1 - B + B * (index.avgdl ? d.len / index.avgdl : 1));
      s += index.idf(t) * (tf * (K1 + 1)) / (tf + norm);
    }
    for (const p of d.quoted) if (typeof p === 'string' ? qs.includes(p) : p.test(ql)) s += PHRASE_BONUS;
    if (s > 0) out.push({ id: d.id, score: Math.round(s * 1000) / 1000 });
  }
  return out.sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

module.exports = { tokenize, frontmatter, splitDescription, bodyTriggers, skillType, docOf, buildIndex, search, W, PHRASE_BONUS };
