#!/usr/bin/env bash
# =============================================================================
# floop-headless.sh — 브라운필드 기능 개발 루프(Stage C) 무인 러너 (컨텍스트 리셋형 Ralph 패턴)
# mvp/bin/mvp-headless.sh 골격의 브라운필드판. 확장 1건: ②ᴿ baseline 회귀 게이트.
# 외부 while 루프가 매 반복 `claude -p`를 새로 띄운다(매 반복 컨텍스트 리셋).
# Stop훅 엔진(floop-loop-stop-hook.sh)의 보조 엔진 — 동일 .planning·동일 게이트 공유.
#   - exit 0 : 완료(정지조건 충족) / 가드레일 도달(max-iter·no-progress·시간 상한)
#              — 어느 경우든 같은 명령 재실행으로 재개 가능
#   - exit 1 : 시작 거부 (loop-active·headless-active 락 / 전제조건 미충족),
#              또는 반복 중 loop-active 출현(Stop훅 엔진 활성) 감지 시 충돌 방지 중단
#
# 정지조건 (판정 주체 = 본 러너의 외부 루프, 모델 아님 — Stop훅과 판정 규약 동일):
#   ①∧②ᴿ 게이트(baseline 맥락): "게이트 통과"를 .planning/baseline.json 기준선 대비
#      신규 실패 0 으로 판정한다 — 기존 실패는 용인하고 내 변경이 추가로 깬 것만 차단.
#      판정 이전에 raw_pass 보정(exit 0 이어도 출력에 실패 표지가 있으면 레드 —
#      has_failure_marker, Stop훅과 공유 규약)을 적용한다.
#        - baseline 부재            : 순수 green(raw_pass) 요구 (MVP 동작 100% 호환)
#        - baseline green(exit 0)   : 현재도 raw_pass 요구 (green 이 곧 회귀 0)
#        - baseline red(fail_count=N): 현재 fail_count <= N 이면 통과 (신규 실패만 차단)
#        - 현재 실패 수 파싱 불가    : 보수적 실패 (회귀 가능성 배제 불가)
#      AND jq -e '[.tasks[].passes]|all' .planning/tasks.json
#   ② verified 마커: passes==true 각 id 의 .planning/verified/{id} 존재
#   ②ᴱ E2E 수용 게이트(선택): e2e-gate-cmd(또는 LOOP_E2E_CMD env) 있으면 all-passes
#      도달 시에만 실행(Stop훅과 동일 규약) — exit 0 + has_failure_marker 보정.
#      부재 시 미적용(통과 간주).
#   ③ completion promise: progress.md 의 정확 문자열 일치 (grep -qF, 정규식 금지)
#   완료 = ①∧②ᴿ ∧ ② ∧ ②ᴱ ∧ ③ — 모델이 promise 를 성급히 기록해도 게이트 레드면 계속.
# 가드레일: max iterations(기본 24) · no-progress(md5 시그니처 연속 동일) · 시간 상한(기본 120분)
#   기본값(24회/120분)은 하드 기본값 — 비용 상한이 곧 안전장치($3600/day 과금 사고 대응).
#   반복 도중의 행(hang)은 워치독(기본 30초 폴링, LOOP_WATCHDOG_INTERVAL env)이
#   전역 시간 상한 초과 시 TERM→(최대 5초)→KILL 로 강제 종료해 시간 상한 경로로 합류.
#   no-progress 시그니처는 게이트 축(②ᴿ 판정) 실패 또는 E2E 레드일 때만 산출한다 —
#   red 기준선에서 기존 실패가 그대로인 정상 진행(회귀 0)을 오탐하지 않으며, 산출·
#   정규화(E2E 출력 'E2E:' 접두 결합 + 숫자 토큰 제거 + sort + md5)는 Stop훅과 동일 규약.
#   gate-cmd 는 반복당 1회만 실행 — 같은 출력·exit 를 정지 판정과 시그니처에 재사용한다.
# 이중 가동 금지:
#   - .planning/loop-active 존재 시 시작 거부(exit 1) + 매 반복 시작 시 재검사 —
#     러너 가동 중 /floop-run 으로 Stop훅 루프를 켜면 다음 반복에서 감지해 중단한다.
#     headless 는 loop-active 를 생성하지 않는다 — Stop훅 안전핀이 내부 세션의 정상
#     종료를 보장하고, 반복은 외부 while 이 전담한다.
#   - .planning/headless-active 락(PID 기록): 기록 PID 생존 시 시작 거부(크론 중첩
#     방지), 사망(스테일) 시 제거 후 진행. 자기 PID 기록 + EXIT trap 정리.
# 사용: 프로젝트 루트에서  bash "<플러그인 루트>/bin/floop-headless.sh"
#       (경로 안내·백그라운드 구문은 /floop-run --headless 참조)
# =============================================================================
set -euo pipefail

PLAN=".planning"
MAX_ITER="${LOOP_MAX_ITER:-24}"          # 반복 상한 (권장: task 수×3)
MAX_MINUTES="${LOOP_MAX_MINUTES:-120}"   # 시간 상한(분)
PROMISE="${LOOP_PROMISE:-<promise>FEATURE_COMPLETE</promise>}"  # promise 전체 문자열(Stop훅과 동일 규약)
CLAUDE_BIN="${LOOP_CLAUDE_BIN:-claude}"  # claude 바이너리 주입 지점

# 숫자 방어 — 비정상 값이면 하드 기본값으로 복원 (set -e 환경에서 -ge 오류 방지)
case "$MAX_ITER" in (''|*[!0-9]*) MAX_ITER=24;; esac
case "$MAX_MINUTES" in (''|*[!0-9]*) MAX_MINUTES=120;; esac

# 시간 상한(초)·워치독 폴링 주기 — LOOP_MAX_SECONDS 는 테스트용 내부 override
# (기본 MAX_MINUTES*60. 워치독·시간 상한 경로를 수 초 단위로 검증하기 위한 것 —
#  운영에서는 LOOP_MAX_MINUTES 를 사용하라).
MAX_SECONDS="${LOOP_MAX_SECONDS:-$(( MAX_MINUTES * 60 ))}"
WATCHDOG_INTERVAL="${LOOP_WATCHDOG_INTERVAL:-30}"
case "$MAX_SECONDS" in (''|*[!0-9]*) MAX_SECONDS=$(( MAX_MINUTES * 60 ));; esac
case "$WATCHDOG_INTERVAL" in (''|0|*[!0-9]*) WATCHDOG_INTERVAL=30;; esac

# 이중 가동 금지: Stop훅 엔진이 살아 있으면 시작 거부
if [ -f "$PLAN/loop-active" ]; then
  echo "[floop-headless] loop-active 존재 — Stop훅 엔진 가동 중. /floop-stop 후 재시도하라." >&2
  exit 1
fi

# 전제조건 검증 — 부재 시 명확한 에러로 시작 거부. Stop훅과 달리 세션 종료를
# 방해할 일이 없으므로 graceful degrade(exit 0)가 아니라 명시적 거부(exit 1)가 안전하다.
if ! command -v jq >/dev/null 2>&1; then
  echo "[floop-headless] 전제조건 미충족: jq 미설치 — 정지조건(all-passes·baseline) 판정 불가. jq 설치 후 재실행하라." >&2
  exit 1
fi
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "[floop-headless] 전제조건 미충족: claude 바이너리 없음($CLAUDE_BIN) — claude CLI 를 설치하거나 LOOP_CLAUDE_BIN 으로 경로를 지정하라." >&2
  exit 1
fi
if [ ! -f "$PLAN/tasks.json" ]; then
  echo "[floop-headless] 전제조건 미충족: $PLAN/tasks.json 부재 — /floop-new 로 Stage A~B 를 먼저 완료하라." >&2
  exit 1
fi

# 게이트 명령 동적 로드 — LOOP_TEST_CMD env 우선, 없으면 .planning/gate-cmd 1행 (Stop훅과 동일)
GATE_CMD="${LOOP_TEST_CMD:-}"
if [ -z "$GATE_CMD" ] && [ -s "$PLAN/gate-cmd" ]; then
  GATE_CMD="$(head -n 1 "$PLAN/gate-cmd" | tr -d '\r')"
fi
if [ -z "$GATE_CMD" ]; then
  echo "[floop-headless] 전제조건 미충족: 게이트 명령 없음($PLAN/gate-cmd 비어있음, LOOP_TEST_CMD 미지정) — /floop-gate 로 점검 후 재실행하라." >&2
  exit 1
fi

# E2E 수용 게이트(선택) — env 우선, 없으면 e2e-gate-cmd 1행, 그것도 없으면 미적용
E2E_CMD="${LOOP_E2E_CMD:-}"
if [ -z "$E2E_CMD" ] && [ -s "$PLAN/e2e-gate-cmd" ]; then
  E2E_CMD="$(head -n 1 "$PLAN/e2e-gate-cmd" | tr -d '\r')"
fi

# baseline 부재는 에러가 아니라 미적용(순수 green 요구) — 시작 시 1회만 경고
if [ ! -f "$PLAN/baseline.json" ]; then
  echo "[floop-headless] 경고: baseline.json 부재 — 회귀 게이트 미적용(순수 green 요구). 정확한 회귀 추적을 원하면 hooks/gates/capture-baseline.sh 를 1회 실행해 기준선을 캡처하라." >&2
fi

# headless-active 락 — 러너끼리의 중첩 실행(크론 겹침) 방지. 기록된 PID 가
# 살아 있으면 시작 거부, 죽어 있으면(스테일 락) 제거 후 진행한다.
# 자기 PID 를 기록하고 EXIT trap 으로 정리한다 (bash 3.2 호환).
LOCK_FILE="$PLAN/headless-active"
if [ -f "$LOCK_FILE" ]; then
  lock_pid="$(head -n 1 "$LOCK_FILE" 2>/dev/null | tr -d '[:space:]')"
  case "$lock_pid" in (''|*[!0-9]*) lock_pid="";; esac
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "[floop-headless] headless-active 락 존재(PID $lock_pid 가동 중) — 중첩 실행 방지로 시작 거부. 기존 러너 종료 후 재시도하라." >&2
    exit 1
  fi
  echo "[floop-headless] 스테일 headless-active 락 감지(PID ${lock_pid:-판독 불가} 사망) — 제거 후 진행." >&2
  rm -f "$LOCK_FILE"
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# 반복 프롬프트 — floop-loop-protocol 규율 고정 문구(재개 프로토콜·task 1개·테스트
# 삭제 금지·baseline 회귀 금지). read -d '' 로 heredoc 를 변수에 담는다(macOS bash 3.2
# 의 "$(cat <<EOF)" 파싱 결함 회피). EOF 도달 시 read 가 1을 반환하므로 || true 필수.
read -r -d '' ITER_PROMPT <<'PROMPT' || true
feature-loop Stage C 개발 루프의 1회 반복을 수행하라. floop-loop-protocol 스킬의 재개 프로토콜을 따른다:
1) .planning/floop-*.md 마스터와 git log --oneline -10, .planning/progress.md 로 현재 상태를 파악한다.
2) .planning/tasks.json 에서 passes:false 인 최우선 task 1개만 선택한다.
3) 테스트 먼저 작성 → 최소 구현 → .planning/gate-cmd 의 명령이 그린이 될 때까지 수정한다.
   기존 red 기준선(.planning/baseline.json 참조) 프로젝트의 그린 기준은 "신규 실패 0
   (현재 실패 수 <= 기준선 fail_count)"이다 — 기존 실패 해소는 환영, 신규 실패는 금지.
4) feature-verifier 에이전트를 디스패치해 해당 task AC 를 반증시킨다(회귀 반증·사기 적발 포함).
   반증 실패 시에만 .planning/verified/{task-id} 마커가 생성되며, 마커가 생긴 뒤에만
   passes:true 로 마킹한다.
5) feat: T-xx 형식으로 커밋하고 .planning/progress.md 에 1줄을 추가한다.
6) 모든 task 가 passes:true 이고 게이트 그린(회귀 0)이면, .planning/e2e-gate-cmd 가 있을 경우
   그 명령을 실행해 E2E 그린까지 확인한 뒤에만 progress.md 에 <promise>FEATURE_COMPLETE</promise> 를
   정확히 기록한다. E2E 레드면 promise 를 적지 말고 깨진 플로우를 보완한다.
규칙: 이번 세션에서는 task 1개만 처리하고 종료한다. 기존 테스트 삭제·약화·기대값 역수정 금지.
baseline 회귀 금지 — 네 변경이 기존 테스트를 추가로 깨면 신규 실패를 0으로 되돌린 뒤에만 진행한다.
진행 불가 시 .planning/BLOCKED.md 에 시도·원인·권장 다음 행동을 기록하고 종료한다.
PROMPT

hash_text() {  # no-progress 시그니처 (macOS/Linux 이식성 폴백)
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# 출력의 명백한 실패 표지 판정 — exit 0이어도 출력에 실패 카운트가 있으면 보수적으로
# 레드. "0 failed" 류 오탐 방지: 행두 FAIL 또는 1 이상 카운트가 붙은 실패 표지만 매칭.
# ※ Stop훅(floop-loop-stop-hook.sh has_failure_marker)과 공유 규약 — 정규식 변경 시 두 곳을 함께 갱신할 것.
has_failure_marker() { printf '%s\n' "$1" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; }

# 출력에서 실패 수 추출 — capture-baseline.sh·floop-loop-stop-hook.sh 와 동일 규약 복제
# (일관된 회귀 판정의 전제 — 규약 변경 시 세 곳을 함께 갱신할 것).
# "N failed/failures/errors" 최대값. 못 찾으면 exit 0 → 0 / exit!=0 → -1(카운트 불명).
extract_fail_count() {
  local out="$1" exit_code="$2" n
  n="$(printf '%s\n' "$out" | grep -oiE '[1-9][0-9]* +(fail(ed|ure|ures)?|errors?)' | grep -oE '^[0-9]+' | sort -rn | head -n1 || true)"
  if [ -n "$n" ]; then echo "$n"
  elif [ "$exit_code" -eq 0 ]; then echo 0
  else echo -1; fi
}

# ②ᴿ baseline 맥락의 게이트 판정 — $1=게이트 출력, $2=exit code. 통과면 return 0.
# 정책은 Stop훅(floop-loop-stop-hook.sh)과 동일: gate_green 판정 이전에 raw_pass
# 보정(exit 0 이어도 출력에 실패 표지가 있으면 레드 — Stop훅 raw_pass 와 동일
# 위치·의미)을 적용한 뒤, 부재→순수 green / green 기준선→raw green 요구 /
# red 기준선→fail_count<=기준선 통과 / 파싱 불가→보수적 실패.
gate_green_for() {
  local out="$1" gate_exit="$2" raw_pass=false baseline_exit baseline_fc cur_fc
  if [ "$gate_exit" -eq 0 ] && ! has_failure_marker "$out"; then
    raw_pass=true
  fi
  if [ ! -f "$PLAN/baseline.json" ]; then
    [ "$raw_pass" = true ]; return
  fi
  baseline_exit="$(jq -r '.baseline_exit // 0' "$PLAN/baseline.json" 2>/dev/null || echo 0)"
  baseline_fc="$(jq -r '.fail_count // 0' "$PLAN/baseline.json" 2>/dev/null || echo 0)"
  case "$baseline_exit" in (''|*[!0-9-]*) baseline_exit=0;; esac
  case "$baseline_fc" in (''|*[!0-9-]*) baseline_fc=0;; esac
  if [ "$baseline_exit" -eq 0 ]; then
    # 클린 기준선(green) — green 이 곧 회귀 0
    [ "$raw_pass" = true ]; return
  fi
  # red 기준선인데 현재 전부 green — 기존 실패까지 해소(개선). 당연히 회귀 0
  [ "$raw_pass" = true ] && return 0
  cur_fc="$(extract_fail_count "$out" "$gate_exit")"
  [ "$cur_fc" -ge 0 ] || return 1        # 파싱 불가(-1) — 보수적 실패
  [ "$cur_fc" -le "$baseline_fc" ]       # 신규 실패 0(동수·감소)이면 통과
}

# verified 마커 재검사 — passes:true 각 id 의 .planning/verified/{id} 존재 확인.
# tasks-guard 는 Edit|Write 만 포착하고 Bash 리다이렉션 우회가 가능하므로 러너도
# Stop훅과 동일하게 최종 방어선을 세운다.
markers_ok() {
  local tid
  while IFS= read -r tid; do
    [ -n "$tid" ] || continue
    [ -f "$PLAN/verified/$tid" ] || return 1
  done < <(jq -r '.tasks[]? | select(.passes == true) | .id' "$PLAN/tasks.json" 2>/dev/null || true)
  return 0
}

started_at="$(date +%s)"
last_sig=""
i=0
while [ "$i" -lt "$MAX_ITER" ]; do
  # 가드 0: 매 반복 시작 시 loop-active 재검사 — 러너 가동 중 /floop-run 으로
  # Stop훅 루프가 켜지면 두 엔진 동시 가동이 되므로 즉시 중단한다.
  if [ -f "$PLAN/loop-active" ]; then
    echo "[floop-headless] Stop훅 엔진 활성 감지(loop-active 출현) — 충돌 방지 위해 중단. /floop-stop 으로 해제 후 재실행하라." >&2
    exit 1
  fi

  # 가드 1: 시간 상한 (반복 사이 검사 — 반복 도중의 행(hang)은 워치독이 담당)
  elapsed_sec=$(( $(date +%s) - started_at ))
  if [ "$elapsed_sec" -ge "$MAX_SECONDS" ]; then
    echo "[floop-headless] 시간 상한 도달(경과 ${elapsed_sec}초 >= ${MAX_SECONDS}초) — 중단. 같은 명령으로 재개 가능." >&2
    exit 0
  fi

  # ── 판정 1회: gate-cmd 를 반복당 1회만 실행 — 같은 출력·exit 를 정지 판정과
  #    no-progress 시그니처 산출에 재사용한다 ──
  gate_exit=0
  gate_out="$(bash -c "$GATE_CMD" 2>&1)" || gate_exit=$?

  # ①∧②ᴿ 게이트 그린 — baseline 맥락 판정 (raw_pass 보정 포함, Stop훅과 동일 규약)
  gate_green=false
  if gate_green_for "$gate_out" "$gate_exit"; then gate_green=true; fi

  # ① AND 결합: 전 task passes
  all_passes=false
  if jq -e '[.tasks[].passes] | all' "$PLAN/tasks.json" >/dev/null 2>&1; then
    all_passes=true
  fi

  # ② verified 마커 재검사
  m_ok=false
  if markers_ok; then m_ok=true; fi

  # ②ᴱ E2E 수용 게이트 — all-passes 도달 시에만 실행(Stop훅과 동일 규약).
  # 판정도 게이트와 동일: exit 0 + has_failure_marker 보정.
  e2e_required=false; e2e_pass=true; e2e_out=""; e2e_exit=0
  if [ -n "$E2E_CMD" ] && [ "$all_passes" = true ]; then
    e2e_required=true
    e2e_out="$(bash -c "$E2E_CMD" 2>&1)" || e2e_exit=$?
    if [ "$e2e_exit" -eq 0 ]; then
      e2e_pass=true
      has_failure_marker "$e2e_out" && e2e_pass=false
    else
      e2e_pass=false
    fi
  fi

  # ③ completion promise — 정확 문자열 일치 (grep -qF, 정규식 금지)
  promise_found=false
  if grep -qF "$PROMISE" "$PLAN/progress.md" 2>/dev/null; then promise_found=true; fi

  # 정지 판정 — Stop훅과 동일 결합: 게이트 그린(회귀 0) ∧ all-passes ∧ verified
  # 마커 ∧ E2E 그린(있을 때) ∧ promise
  if [ "$gate_green" = true ] && [ "$all_passes" = true ] && [ "$m_ok" = true ] && [ "$e2e_pass" = true ] && [ "$promise_found" = true ]; then
    e2e_note=""
    [ "$e2e_required" = true ] && e2e_note=" + E2E 그린"
    echo "[floop-headless] 정지조건 충족(게이트 그린 + 회귀 0 + all-passes + verified 마커${e2e_note} + promise) — 기능 완료 (iteration $i)." >&2
    exit 0
  fi

  # 가드 2: no-progress — 게이트 축(②ᴿ 판정) 실패 또는 E2E 레드의 실패 시그니처가
  # 직전 반복과 동일하면 중단. red 기준선의 용인된 기존 실패(회귀 0)는 오탐하지
  # 않으며, 산출(E2E 출력 'E2E:' 접두 결합 + grep -Ei 'fail|error' + 숫자 토큰
  # 제거 + sort + md5)은 Stop훅과 동일 규약.
  sig=""
  if [ "$gate_green" = false ] || [ "$e2e_pass" = false ]; then
    sig_src_raw="$gate_out"
    [ "$e2e_required" = true ] && sig_src_raw="$sig_src_raw"$'\n'"E2E:"$'\n'"$e2e_out"
    # 숫자 토큰 제거 정규화 — "1 failed in 0.01s" 류 소요시간 비결정성 제거 (Stop훅과 동일)
    sig_src="$(printf '%s' "$sig_src_raw" | grep -Ei 'fail|error' | sed -E 's/[0-9]+([.][0-9]+)?//g' | sort || true)"
    if [ -z "$sig_src" ]; then
      sig_src="exit=$gate_exit e2e=$e2e_exit"$'\n'"$(printf '%s' "$sig_src_raw" | tail -20)"
    fi
    sig="$(printf '%s' "$sig_src" | hash_text 2>/dev/null || echo "")"
  fi
  # 초회 패스(i=0, claude 실행 전 초기 상태)는 비교 체인에서 제외 — "반복 결과가
  # 연속 2회 동일"이라는 원 의미 유지 (Stop훅도 작업 1회 이후에만 시그니처를 평가).
  if [ "$i" -gt 0 ]; then
    if [ -n "$sig" ] && [ "$sig" = "$last_sig" ]; then
      {
        echo ""
        echo "## headless no-progress 차단 — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- iteration: $i/$MAX_ITER"
        echo "- 실패 시그니처(md5): $sig (연속 2회 동일)"
        echo "- gate-cmd: $GATE_CMD (exit=$gate_exit)"
        echo "- 테스트 출력 tail -20:"
        echo '```'
        printf '%s\n' "$gate_out" | tail -20
        echo '```'
        echo "- 권장 다음 행동: 실패 원인 분석 후 같은 명령으로 재개. 스코프 결함은 task-planner 재분해, 구조 한계는 해당 스택 플러그인 가이드 참조."
      } >> "$PLAN/BLOCKED.md"
      echo "[floop-headless] no-progress 감지(동일 실패 시그니처 연속) — 중단. $PLAN/BLOCKED.md 참조." >&2
      exit 0
    fi
    last_sig="$sig"
  fi

  i=$((i + 1))
  # /floop-status 가시성을 위해 loop-state.json 갱신 (Stop훅과 동일 필드)
  jq -n --argjson it "$i" --arg sig "$last_sig" --argjson st "$started_at" \
    --argjson mi "$MAX_ITER" --argjson mm "$MAX_MINUTES" \
    '{iteration:$it, last_fail_sig:$sig, started_at:$st, max_iter:$mi, max_minutes:$mm}' > "$PLAN/loop-state.json"

  # 1 반복 = 1 task — 매 회 새 세션(컨텍스트 리셋). claude 는 백그라운드로 띄우고
  # 워치독이 LOOP_WATCHDOG_INTERVAL(기본 30초) 주기로 전역 시간 상한을 검사한다 —
  # 초과 시 TERM → 최대 5초 대기 → 생존 시 KILL 후 시간 상한 종료 경로로 합류
  # (claude -p 행(hang) 대응). 생존 확인은 1초 단위로 수행해 정상 종료 후 잔여
  # 대기를 최소화한다.
  claude_exit=0
  "$CLAUDE_BIN" -p --permission-mode acceptEdits "$ITER_PROMPT" &
  claude_pid=$!
  watchdog_killed=0
  while kill -0 "$claude_pid" 2>/dev/null; do
    if [ $(( $(date +%s) - started_at )) -ge "$MAX_SECONDS" ]; then
      kill -TERM "$claude_pid" 2>/dev/null || true
      grace=0
      while [ "$grace" -lt 5 ] && kill -0 "$claude_pid" 2>/dev/null; do
        sleep 1; grace=$(( grace + 1 ))
      done
      if kill -0 "$claude_pid" 2>/dev/null; then
        kill -KILL "$claude_pid" 2>/dev/null || true
      fi
      watchdog_killed=1
      break
    fi
    slept=0
    while [ "$slept" -lt "$WATCHDOG_INTERVAL" ] && kill -0 "$claude_pid" 2>/dev/null; do
      sleep 1; slept=$(( slept + 1 ))
    done
  done
  wait "$claude_pid" 2>/dev/null || claude_exit=$?
  if [ "$watchdog_killed" -eq 1 ]; then
    echo "[floop-headless] 시간 상한 도달 — 반복 도중 claude 강제 종료(TERM→KILL) 후 중단. 같은 명령으로 재개 가능." >&2
    exit 0
  fi
  if [ "$claude_exit" -ne 0 ]; then
    echo "[floop-headless] iteration $i: claude 비정상 종료(exit=$claude_exit) — 다음 반복에서 재개 프로토콜로 복구." >&2
  fi
done

echo "[floop-headless] max iterations($MAX_ITER) 도달 — 중단. 미완 task 는 tasks.json 참조, 같은 명령으로 재개." >&2
exit 0
