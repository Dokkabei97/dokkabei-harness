// PostToolUse: 편집(Edit|Write)된 코드 파일에서 고신호 보안 취약점 패턴을 경고 (경고 전용 — 항상 passthrough).
//
// 탐지 클래스 15종 — 시크릿 / 인젝션 / 안전하지 않은 역직렬화 / 전송·신뢰 / XSS.
// 억제 규약: 라인에 security-ok 주석이 있으면 스킵.
// 스킵 대상: 1MB 초과 파일, 2000자 초과 라인(생성/압축 코드로 간주), 바이너리(NUL 바이트), .md/.lock 파일.
// 시크릿 값은 앞 4자만 노출하고 마스킹해 출력한다.

const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

const MAX_SIZE = 1024 * 1024; // 1MB
// 초장문 라인은 생성/압축 코드로 간주하고 검사 스킵 — 정규식 백트래킹 폭주(ReDoS) 방지 1차 방어선
const MAX_LINE_LEN = 2000;

// 검사 대상 코드 파일 확장자. hooks.json 이 tool 명 matcher(Edit|Write)로 등록되므로
// 확장자 필터를 스크립트 내부에서 수행한다 — 표현식 matcher 는 실측상 미발화(2026-07)라
// tool 명 regex + 스크립트 내부 필터 컨벤션(bff01ca)을 따른다.
const CODE_EXT = /\.(ts|tsx|js|jsx|kt|kts|py|go|java|sql|sh|yaml|yml|json|properties)$|\.env(\.[A-Za-z0-9_-]+)?$/i;

// placeholder/env 참조가 포함된 라인은 하드코딩 시크릿으로 보지 않는다.
// '<...>' 는 <API_KEY> 류 대문자 placeholder 만 인정(i 플래그 없는 별도 정규식) —
// 단독 '<' 매칭 시 JSX/제네릭 라인 전체가 억제되는 미탐 방지.
const PLACEHOLDER = /example|changeme|dummy|xxx|\{\{|\$\{|process\.env|os\.getenv|System\.getenv/i;
const ANGLE_PLACEHOLDER = /<[A-Z][A-Z0-9_]*>/;
const isPlaceholder = (l) => PLACEHOLDER.test(l) || ANGLE_PLACEHOLDER.test(l);

// 시크릿 값 마스킹 — 앞 4자만 노출
const maskValue = (v) => (v.length <= 4 ? v : v.slice(0, 4) + '****');

// SQL 키워드 판정(대문자 + 후속 절 형태만 — "delete this" 류 일반 문장 오탐 방지).
// SELECT..FROM / UPDATE..SET 은 `.+` alternation 백트래킹(ReDoS) 회피를 위해 indexOf 순서 검사로 판정.
const hasSqlStmt = (l) => {
  if (/\b(INSERT\s+INTO|DELETE\s+FROM)\s/.test(l)) return true;
  const sel = l.indexOf('SELECT ');
  if (sel !== -1 && l.indexOf(' FROM ', sel + 7) !== -1) return true;
  const upd = l.indexOf('UPDATE ');
  return upd !== -1 && l.indexOf(' SET ', upd + 7) !== -1;
};

// SQL 문자열 결합/보간 판정
const isSqlConcat = (l) => {
  if (!hasSqlStmt(l)) return false;
  return /["']\s*\+/.test(l) || /\+\s*["']/.test(l) // 따옴표 문자열 + 결합
    || /`[^`]*\$\{/.test(l)                          // JS/TS 템플릿 리터럴 보간
    || (/\bf["']/.test(l) && /\{/.test(l))           // Python f-string 보간
    || /"[^"]*\$[\w{]/.test(l);                      // Kotlin 문자열 템플릿
};

// 명령 실행 + 문자열 결합 판정 (리터럴만 실행하는 경우는 제외)
const isCmdConcat = (l) =>
  /\bexec(Sync)?\s*\(\s*["'][^)]*\+/.test(l)         // child_process exec + 따옴표 문자열 결합
  || /\bexec(Sync)?\s*\(\s*`[^`]*\$\{/.test(l)       // child_process exec + 템플릿 보간
  || /os\.system\s*\(\s*(f["']|["'][^)]*\+)/.test(l) // os.system + f-string/문자열 결합
  || /Runtime\.getRuntime\(\)\.exec\s*\([^)]*\+/.test(l); // Java Runtime exec + 결합

// innerHTML 에 순수 문자열 리터럴이 아닌 값(변수/결합/보간) 대입 판정
const isInnerHtmlVar = (l) => {
  const m = l.match(/\.innerHTML\s*\+?=(?!=)\s*(.+)$/);
  if (!m) return false;
  const rhs = m[1].trim();
  if (/^(["'])(?:(?!\1).)*\1\s*;?\s*$/.test(rhs)) return false; // 순수 따옴표 리터럴
  if (/^`[^`$]*`\s*;?\s*$/.test(rhs)) return false;             // 보간 없는 템플릿 리터럴
  return true;
};

// 탐지 규칙 15종 — label(클래스 라벨), test(라인 판정), redact(시크릿 마스킹 출력, 선택).
// 라인당 첫 매치 규칙만 보고한다 (구체적 규칙을 앞에 배치).
const RULES = [
  {
    label: 'AWS Access Key',
    test: (l) => /AKIA[0-9A-Z]{16}/.test(l),
    redact: (l) => l.replace(/AKIA[0-9A-Z]{16}/g, maskValue),
  },
  {
    label: 'GitHub 토큰',
    test: (l) => /\b(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/.test(l),
    redact: (l) => l.replace(/\b(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, maskValue),
  },
  {
    label: 'Slack 토큰',
    test: (l) => /\bxox[baprs]-[A-Za-z0-9-]{8,}/.test(l),
    redact: (l) => l.replace(/\bxox[baprs]-[A-Za-z0-9-]{8,}/g, maskValue),
  },
  {
    label: 'Private Key 블록',
    test: (l) => /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(l),
  },
  {
    label: '자격증명 포함 URL',
    test: (l) => /:\/\/[^\s/:@"'`]+:[^\s/@"'`]+@/.test(l) && !isPlaceholder(l),
    redact: (l) => l.replace(/(:\/\/[^\s/:@"'`]+:)([^\s/@"'`]+)@/g, (m, pre, pw) => pre + maskValue(pw) + '@'),
  },
  {
    label: '하드코딩된 시크릿',
    test: (l) => /(api[_-]?key|secret|password|token)["']?\s*[:=]\s*["'][^"']{8,}["']/i.test(l) && !isPlaceholder(l),
    redact: (l) => l.replace(
      /((api[_-]?key|secret|password|token)["']?\s*[:=]\s*["'])([^"']{8,})(["'])/gi,
      (m, pre, _k, val, post) => pre + maskValue(val) + post
    ),
  },
  { label: 'SQL 인젝션 의심(문자열 결합)', test: isSqlConcat },
  { label: '명령 실행 문자열 결합', test: isCmdConcat },
  {
    label: '동적 eval/exec',
    test: (l) => /(?<![.\w])(eval|exec)\s*\(\s*(?!\)|["'`])/.test(l),
  },
  {
    label: '안전하지 않은 역직렬화(pickle)',
    test: (l) => /\bpickle\.loads\s*\(/.test(l),
  },
  {
    label: '안전하지 않은 역직렬화(yaml.load)',
    test: (l) => /\byaml\.load\s*\(/.test(l) && !/SafeLoader/.test(l),
  },
  {
    label: '안전하지 않은 역직렬화(ObjectInputStream)', // security-ok — 라벨이 패턴 단어를 포함
    test: (l) => /\bObjectInputStream\b/.test(l),
  },
  {
    label: 'TLS 검증 비활성화(verify=False)', // security-ok — 라벨이 패턴 단어를 포함
    test: (l) => /\bverify\s*=\s*False\b/.test(l),
  },
  {
    label: 'TLS 검증 비활성화(rejectUnauthorized)',
    test: (l) => /rejectUnauthorized["']?\s*:\s*false/i.test(l),
  },
  {
    label: 'XSS 위험(innerHTML/dangerouslySetInnerHTML)', // security-ok — 라벨이 패턴 단어를 포함
    test: (l) => /dangerouslySetInnerHTML/.test(l) || isInnerHtmlVar(l), // security-ok
  },
];

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);
  if (/\.(md|lock)$/i.test(p)) return passthrough(raw);
  if (!CODE_EXT.test(p)) return passthrough(raw); // 코드 파일 외 스킵(확장자 화이트리스트)

  let stat;
  try { stat = fs.statSync(p); } catch (_) { return passthrough(raw); }
  if (!stat.isFile() || stat.size > MAX_SIZE) return passthrough(raw);

  // existsSync 통과 후에도 읽기는 실패할 수 있다(EACCES/TOCTOU) — 조용히 passthrough
  let buf;
  try { buf = fs.readFileSync(p); } catch (_) { return passthrough(raw); }
  if (buf.includes(0)) return passthrough(raw); // 바이너리(NUL 바이트) 스킵

  const findings = [];
  buf.toString('utf8').split('\n').forEach((l, idx) => {
    if (l.length > MAX_LINE_LEN) return; // 초장문 라인 — 생성/압축 코드로 간주(ReDoS 방지)
    if (/security-ok/.test(l)) return; // 의도된 라인 — 억제 주석
    for (const r of RULES) {
      if (r.test(l)) {
        findings.push((idx + 1) + ': [' + r.label + '] ' + (r.redact ? r.redact(l) : l).trim());
        break; // 라인당 첫 매치만 보고
      }
    }
  });

  if (findings.length) {
    console.error('[Hook] WARNING: 잠재적 보안 이슈 발견 in ' + p);
    findings.slice(0, 5).forEach((m) => console.error(m));
    console.error('[Hook] 의도된 경우 해당 라인에 security-ok 주석을 추가하세요');
  }
  passthrough(raw);
})();
