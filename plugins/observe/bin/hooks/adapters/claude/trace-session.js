// SessionStart/SessionEnd: 세션 경계를 레포 .tracer 이벤트로 append — 하나의 스크립트가
// hook_event_name 으로 두 이벤트를 판별한다 (레코드 type: session_start | session_end).
// session_start 의 plugin_root 는 이 훅이 실행된 "설치 루트"의 근거로,
// 리포트가 미사용 자산의 분모(인벤토리)를 트레이스와 같은 설치본에서 열거하게 해준다
// (repo 디렉터리명과 설치 네임스페이스의 드리프트로 인한 join 오류 방지).
// 다이제스트(작업 방식 요약): SessionEnd 는 그 세션을 마감(마지막 턴 확정 + session_summary)하고, SessionStart 는
// 현재 세션 커서를 만들고 마감 안 된 이전 세션들을 따라잡는다 — 둘 다 detached worker(transcript.js --worker)로
// 넘기고 즉시 끝난다(SessionEnd 기본 예산 1.5s 는 플러그인 timeout 으로 못 늘린다). 처리 함수는 Stop 훅과 같다.
// SessionStart hook 의 stdout 은 컨텍스트로 주입되므로 무출력 필수. 항상 exit 0.
// Codex 도 같은 hooks.json 으로 부른다(SessionEnd 는 메인 스레드만, transcript_path 는 null 일 수 있음 — 바이너리 스키마) —
// runtimeOf 로 가르고 worker 는 런타임별 어댑터(Claude transcript.js / Codex rollout.js)의 것을 띄운다. plugin_root 는
// Codex 도 CLAUDE_PLUGIN_ROOT 를 호환 설정한다(문서).
const { readEvent } = require('../../_lib/hook-stdin');
const { enabled, emit, runtimeOf, CODEX } = require('../../_lib/writer');
const { repoRoot, isHome } = require('../../_lib/paths');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // 빈/깨진 stdin(json={})·비객체 payload·문자열이 아닌 session_id(파일명 키) 는 기록하지 않는다 — session_id:null 쓰레기 레코드 방지
    if (!json || typeof json.session_id !== 'string' || !json.session_id) return;
    const event = json.hook_event_name;
    if (event !== 'SessionStart' && event !== 'SessionEnd') return; // 오설정 이중 가드

    const root = repoRoot(json.cwd);
    const runtime = runtimeOf(json);
    const base = {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
    };
    if (event === 'SessionStart') {
      emit(root, {
        ...base,
        type: 'session_start',
        source: json.source || null, // startup | resume | clear | compact 등
        plugin_root: process.env.CLAUDE_PLUGIN_ROOT || null,
      }, runtime);
    } else {
      emit(root, {
        ...base,
        type: 'session_end',
        reason: json.reason || null, // clear | logout | prompt_input_exit | other 등
      }, runtime);
    }
    if (!isHome(root)) {
      const { spawnWorker } = require(runtime === CODEX ? '../codex/rollout' : './transcript');
      spawnWorker(event === 'SessionStart'
        ? { mode: 'catchup', root, session: json.session_id, transcript: json.transcript_path || null }
        : { mode: 'end', root, session: json.session_id, transcript: json.transcript_path || null });
    }
  } catch (_) { /* best-effort */ }
})();
