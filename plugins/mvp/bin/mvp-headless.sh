#!/usr/bin/env bash
# =============================================================================
# mvp-headless.sh — MVP Stage 4 무인 루프 러너 (컨텍스트 리셋형 Ralph 패턴)
# mvp-orchestrator/references/headless-recipe.md 원형 스크립트의 동봉 승격판.
# 외부 while 루프가 매 반복 `claude -p`를 새로 띄운다(매 반복 컨텍스트 리셋).
# Stop훅 엔진(mvp-loop-stop-hook.sh)의 보조 엔진 — 동일 .planning·동일 게이트 공유.
#   - exit 0 : 완료(정지조건 충족) / 가드레일 도달(max-iter·no-progress·시간 상한)
#              — 어느 경우든 같은 명령 재실행으로 재개 가능
#   - exit 1 : 시작 거부 (loop-active·headless-active 락 / 전제조건 미충족),
#              또는 반복 중 loop-active 출현(Stop훅 엔진 활성) 감지 시 충돌 방지 중단
#
# recipe 원형 대비 개선점:
#   (a) LOOP_CLAUDE_BIN — claude 바이너리 주입(기본 claude). 래퍼·테스트 스텁 대체용.
#   (b) 전제조건 검증 강화 — jq·claude 바이너리·.planning/prd.json·gate-cmd 부재 시
#       명확한 에러와 함께 exit 1 (판정 불가 상태로 헛도는 루프 방지)
#   (c) verified 마커 재검사 — 정지조건에 passes:true 각 id 의
#       .planning/verified/{id} 존재 확인 추가 (Stop훅 ② 최종 방어선과 등가)
#   (d) 게이트 판정 규약 통일 — exit code 우선 + has_failure_marker 보정(Stop훅과
#       공유 규약): exit 0 이어도 출력에 실패 표지가 있으면 보수적으로 레드.
#   (e) 반복당 gate-cmd 1회 실행 — 같은 출력·exit 를 정지 판정과 no-progress
#       시그니처 산출에 재사용한다 (무거운 스위트의 배치 시간 2배 방지).
#   (f) 이중 가동 방어 강화 — 매 반복 시작 시 loop-active 재검사(가동 중 Stop훅
#       루프가 켜지면 즉시 중단) + headless-active 락으로 러너끼리 중첩 실행 거부.
#   (g) 워치독 — claude -p 를 백그라운드로 띄우고 폴링(기본 30초,
#       LOOP_WATCHDOG_INTERVAL env)으로 전역 시간 상한을 반복 도중에도 발동시킨다.
#       행(hang) 시 TERM→(최대 5초 대기)→KILL 후 시간 상한 종료 경로로 합류.
#   (+) no-progress 시그니처는 단위 게이트 또는 E2E 가 레드일 때만 산출 — Stop훅과
#       동일 규약(E2E 출력 'E2E:' 접두 결합 + grep -Ei 'fail|error' + 숫자 토큰 제거
#       + sort + md5)으로 비교하며, 그린 게이트의 정상 진행은 오탐하지 않는다.
#
# 정지조건 (판정 주체 = 본 러너의 외부 루프, 모델 아님 — Stop훅과 판정 규약 동일):
#   ① 결정론 게이트: gate-cmd 실행 exit 0 + has_failure_marker 보정
#      AND jq -e '[.stories[].passes]|all' .planning/prd.json
#   ② verified 마커: passes==true 각 id 의 .planning/verified/{id} 존재
#   ②ᴱ E2E 수용 게이트(선택): e2e-gate-cmd(또는 LOOP_E2E_CMD env) 있으면 all-passes
#      도달 시에만 실행(Stop훅과 동일 규약) — exit 0 + has_failure_marker 보정.
#      부재 시 미적용(통과 간주)으로 기존 동작과 100% 호환.
#   ③ completion promise: progress.md 의 정확 문자열 일치 (grep -qF, 정규식 금지)
#   완료 = ① ∧ ② ∧ ②ᴱ ∧ ③ — 모델이 promise 를 성급히 기록해도 게이트 레드면 계속.
# 가드레일: max iterations(기본 24) · no-progress(md5 시그니처 연속 동일) · 시간 상한(기본 120분)
#   기본값(24회/120분)은 하드 기본값 — 비용 상한이 곧 안전장치($3600/day 과금 사고 대응).
# 이중 가동 금지:
#   - .planning/loop-active 존재 시 시작 거부(exit 1) + 매 반복 시작 시 재검사 —
#     러너 가동 중 /mvp-run 으로 Stop훅 루프를 켜면 다음 반복에서 감지해 중단한다.
#     headless 는 loop-active 를 생성하지 않는다 — Stop훅 안전핀(loop-active 부재 시
#     무동작)이 내부 세션의 정상 종료를 보장하고, 반복은 외부 while 이 전담한다.
#   - .planning/headless-active 락(PID 기록): 기록 PID 생존 시 시작 거부(크론 중첩
#     방지), 사망(스테일) 시 제거 후 진행. 자기 PID 기록 + EXIT trap 정리.
# 사용: 프로젝트 루트에서  bash "<플러그인 루트>/bin/mvp-headless.sh"
#       (경로 안내·백그라운드 구문은 /mvp-run --headless 참조)
# =============================================================================
set -euo pipefail

PLAN=".planning"
MAX_ITER="${LOOP_MAX_ITER:-24}"          # 반복 상한 (권장: 스토리 수×3)
MAX_MINUTES="${LOOP_MAX_MINUTES:-120}"   # 시간 상한(분)
PROMISE="${LOOP_PROMISE:-<promise>MVP_COMPLETE</promise>}"  # promise 전체 문자열(Stop훅과 동일 규약)
CLAUDE_BIN="${LOOP_CLAUDE_BIN:-claude}"  # (a) claude 바이너리 주입 지점

# 숫자 방어 — 비정상 값이면 하드 기본값으로 복원 (set -e 환경에서 -ge 오류 방지)
case "$MAX_ITER" in (''|*[!0-9]*) MAX_ITER=24;; esac
case "$MAX_MINUTES" in (''|*[!0-9]*) MAX_MINUTES=120;; esac

# (g) 시간 상한(초)·워치독 폴링 주기 — LOOP_MAX_SECONDS 는 테스트용 내부 override
# (기본 MAX_MINUTES*60. 워치독·시간 상한 경로를 수 초 단위로 검증하기 위한 것 —
#  운영에서는 LOOP_MAX_MINUTES 를 사용하라).
MAX_SECONDS="${LOOP_MAX_SECONDS:-$(( MAX_MINUTES * 60 ))}"
WATCHDOG_INTERVAL="${LOOP_WATCHDOG_INTERVAL:-30}"
case "$MAX_SECONDS" in (''|*[!0-9]*) MAX_SECONDS=$(( MAX_MINUTES * 60 ));; esac
case "$WATCHDOG_INTERVAL" in (''|0|*[!0-9]*) WATCHDOG_INTERVAL=30;; esac

# 이중 가동 금지: Stop훅 엔진이 살아 있으면 시작 거부
if [ -f "$PLAN/loop-active" ]; then
  echo "[mvp-headless] loop-active 존재 — Stop훅 엔진 가동 중. /mvp-stop 후 재시도하라." >&2
  exit 1
fi

# (b) 전제조건 검증 — 부재 시 명확한 에러로 시작 거부. Stop훅과 달리 세션 종료를
# 방해할 일이 없으므로 graceful degrade(exit 0)가 아니라 명시적 거부(exit 1)가 안전하다.
if ! command -v jq >/dev/null 2>&1; then
  echo "[mvp-headless] 전제조건 미충족: jq 미설치 — 정지조건(all-passes) 판정 불가. jq 설치 후 재실행하라." >&2
  exit 1
fi
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "[mvp-headless] 전제조건 미충족: claude 바이너리 없음($CLAUDE_BIN) — claude CLI 를 설치하거나 LOOP_CLAUDE_BIN 으로 경로를 지정하라." >&2
  exit 1
fi
if [ ! -f "$PLAN/prd.json" ]; then
  echo "[mvp-headless] 전제조건 미충족: $PLAN/prd.json 부재 — /mvp-new 로 Stage 0~3 을 먼저 완료하라." >&2
  exit 1
fi

# 게이트 명령 동적 로드 — LOOP_TEST_CMD env 우선, 없으면 .planning/gate-cmd 1행 (Stop훅과 동일)
GATE_CMD="${LOOP_TEST_CMD:-}"
if [ -z "$GATE_CMD" ] && [ -s "$PLAN/gate-cmd" ]; then
  GATE_CMD="$(head -n 1 "$PLAN/gate-cmd" | tr -d '\r')"
fi
if [ -z "$GATE_CMD" ]; then
  echo "[mvp-headless] 전제조건 미충족: 게이트 명령 없음($PLAN/gate-cmd 비어있음, LOOP_TEST_CMD 미지정) — /mvp-gate 로 점검 후 재실행하라." >&2
  exit 1
fi

# E2E 수용 게이트(선택) — env 우선, 없으면 e2e-gate-cmd 1행, 그것도 없으면 미적용
E2E_CMD="${LOOP_E2E_CMD:-}"
if [ -z "$E2E_CMD" ] && [ -s "$PLAN/e2e-gate-cmd" ]; then
  E2E_CMD="$(head -n 1 "$PLAN/e2e-gate-cmd" | tr -d '\r')"
fi

# (f) headless-active 락 — 러너끼리의 중첩 실행(크론 겹침) 방지. 기록된 PID 가
# 살아 있으면 시작 거부, 죽어 있으면(스테일 락) 제거 후 진행한다.
# 자기 PID 를 기록하고 EXIT trap 으로 정리한다 (bash 3.2 호환).
LOCK_FILE="$PLAN/headless-active"
if [ -f "$LOCK_FILE" ]; then
  lock_pid="$(head -n 1 "$LOCK_FILE" 2>/dev/null | tr -d '[:space:]')"
  case "$lock_pid" in (''|*[!0-9]*) lock_pid="";; esac
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "[mvp-headless] headless-active 락 존재(PID $lock_pid 가동 중) — 중첩 실행 방지로 시작 거부. 기존 러너 종료 후 재시도하라." >&2
    exit 1
  fi
  echo "[mvp-headless] 스테일 headless-active 락 감지(PID ${lock_pid:-판독 불가} 사망) — 제거 후 진행." >&2
  rm -f "$LOCK_FILE"
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# 반복 프롬프트 — mvp-loop-protocol 규율 고정 문구. read -d '' 로 heredoc 를 변수에
# 담는다(macOS bash 3.2 의 "$(cat <<EOF)" 파싱 결함 회피). EOF 도달 시 read 가 1을
# 반환하므로 || true 필수.
read -r -d '' ITER_PROMPT <<'PROMPT' || true
MVP Stage 4 개발 루프의 1회 반복을 수행하라. mvp-loop-protocol 스킬의 재개 프로토콜을 따른다:
1) .planning/mvp-*.md 마스터와 git log --oneline -10 으로 현재 상태를 파악한다.
2) .planning/prd.json 에서 passes:false 인 최우선 스토리 1개만 선택한다.
3) 테스트 먼저 작성 → 최소 구현 → .planning/gate-cmd 의 명령이 그린(exit 0)이 될 때까지 수정한다.
4) mvp-verifier 에이전트를 디스패치해 해당 스토리 AC를 반증시킨다. 반증 실패 시에만
   .planning/verified/{story-id} 마커가 생성되며, 마커가 생긴 뒤에만 passes:true 로 마킹한다.
5) feat(mvp): S-xx 형식으로 커밋하고 .planning/progress.md 에 1줄을 추가한다.
6) 모든 스토리가 passes:true 이고 단위 게이트가 그린이면, .planning/e2e-gate-cmd 가 있을 경우
   그 명령을 실행해 E2E 그린까지 확인한 뒤에만 progress.md 에 <promise>MVP_COMPLETE</promise> 를
   정확히 기록한다. E2E 레드면 promise 를 적지 말고 깨진 플로우를 보완한다.
규칙: 이번 세션에서는 스토리 1개만 처리하고 종료한다. 테스트 삭제·약화 금지.
진행 불가 시 .planning/BLOCKED.md 에 시도·원인·권장 다음 행동을 기록하고 종료한다.
PROMPT

hash_text() {  # no-progress 시그니처 (macOS/Linux 이식성 폴백)
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# (d) 출력의 명백한 실패 표지 판정 — exit 0이어도 출력에 실패 카운트가 있으면 보수적으로
# 레드. "0 failed" 류 오탐 방지: 행두 FAIL 또는 1 이상 카운트가 붙은 실패 표지만 매칭.
# ※ Stop훅(mvp-loop-stop-hook.sh has_failure_marker)과 공유 규약 — 정규식 변경 시 두 곳을 함께 갱신할 것.
has_failure_marker() { printf '%s\n' "$1" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; }

# (c) verified 마커 재검사 — passes:true 각 id 의 .planning/verified/{id} 존재 확인.
# prd-guard 는 Edit|Write 만 포착하고 Bash 리다이렉션 우회가 가능하므로 러너도
# Stop훅과 동일하게 최종 방어선을 세운다.
markers_ok() {
  local sid
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    [ -f "$PLAN/verified/$sid" ] || return 1
  done < <(jq -r '.stories[]? | select(.passes == true) | .id' "$PLAN/prd.json" 2>/dev/null || true)
  return 0
}

started_at="$(date +%s)"
last_sig=""
i=0
while [ "$i" -lt "$MAX_ITER" ]; do
  # 가드 0 (f): 매 반복 시작 시 loop-active 재검사 — 러너 가동 중 /mvp-run 으로
  # Stop훅 루프가 켜지면 두 엔진 동시 가동이 되므로 즉시 중단한다.
  if [ -f "$PLAN/loop-active" ]; then
    echo "[mvp-headless] Stop훅 엔진 활성 감지(loop-active 출현) — 충돌 방지 위해 중단. /mvp-stop 으로 해제 후 재실행하라." >&2
    exit 1
  fi

  # 가드 1: 시간 상한 (반복 사이 검사 — 반복 도중의 행(hang)은 워치독(g)이 담당)
  elapsed_sec=$(( $(date +%s) - started_at ))
  if [ "$elapsed_sec" -ge "$MAX_SECONDS" ]; then
    echo "[mvp-headless] 시간 상한 도달(경과 ${elapsed_sec}초 >= ${MAX_SECONDS}초) — 중단. 같은 명령으로 재개 가능." >&2
    exit 0
  fi

  # ── 판정 1회 (e): gate-cmd 를 반복당 1회만 실행 — 같은 출력·exit 를 정지 판정과
  #    no-progress 시그니처 산출에 재사용한다 ──
  gate_exit=0
  gate_out="$(bash -c "$GATE_CMD" 2>&1)" || gate_exit=$?

  # ① 게이트 그린 — exit code 우선 + has_failure_marker 보정 (Stop훅과 동일 규약)
  tests_pass=false
  if [ "$gate_exit" -eq 0 ]; then
    tests_pass=true
    has_failure_marker "$gate_out" && tests_pass=false
  fi

  # ① AND 결합: 전 스토리 passes
  all_passes=false
  if jq -e '[.stories[].passes] | all' "$PLAN/prd.json" >/dev/null 2>&1; then
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

  # 정지 판정 — Stop훅과 동일 결합: 게이트 그린 ∧ all-passes ∧ verified 마커 ∧
  # E2E 그린(있을 때) ∧ promise
  if [ "$tests_pass" = true ] && [ "$all_passes" = true ] && [ "$m_ok" = true ] && [ "$e2e_pass" = true ] && [ "$promise_found" = true ]; then
    e2e_note=""
    [ "$e2e_required" = true ] && e2e_note=" + E2E 그린"
    echo "[mvp-headless] 정지조건 충족(게이트 그린 + all-passes + verified 마커${e2e_note} + promise) — MVP 완료 (iteration $i)." >&2
    exit 0
  fi

  # 가드 2: no-progress — 단위 게이트 또는 E2E 레드의 실패 시그니처가 직전 반복과
  # 동일하면 중단. 시그니처 산출(E2E 출력 'E2E:' 접두 결합 + grep -Ei 'fail|error'
  # + 숫자 토큰 제거 + sort + md5)은 Stop훅과 동일 규약.
  sig=""
  if [ "$tests_pass" = false ] || [ "$e2e_pass" = false ]; then
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
        echo "- 권장 다음 행동: 실패 원인 분석 후 같은 명령으로 재개. 스코프 재협상은 product-strategist, 구조 재설계는 tech-architect 에스컬레이션."
      } >> "$PLAN/BLOCKED.md"
      echo "[mvp-headless] no-progress 감지(동일 실패 시그니처 연속) — 중단. $PLAN/BLOCKED.md 참조." >&2
      exit 0
    fi
    last_sig="$sig"
  fi

  i=$((i + 1))
  # /mvp-status 가시성을 위해 loop-state.json 갱신 (Stop훅과 동일 필드)
  jq -n --argjson it "$i" --arg sig "$last_sig" --argjson st "$started_at" \
    --argjson mi "$MAX_ITER" --argjson mm "$MAX_MINUTES" \
    '{iteration:$it, last_fail_sig:$sig, started_at:$st, max_iter:$mi, max_minutes:$mm}' > "$PLAN/loop-state.json"

  # 1 반복 = 1 스토리 — 매 회 새 세션(컨텍스트 리셋). (g) claude 는 백그라운드로
  # 띄우고 워치독이 LOOP_WATCHDOG_INTERVAL(기본 30초) 주기로 전역 시간 상한을
  # 검사한다 — 초과 시 TERM → 최대 5초 대기 → 생존 시 KILL 후 시간 상한 종료
  # 경로로 합류(claude -p 행(hang) 대응). 생존 확인은 1초 단위로 수행해 정상
  # 종료 후 잔여 대기를 최소화한다.
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
    echo "[mvp-headless] 시간 상한 도달 — 반복 도중 claude 강제 종료(TERM→KILL) 후 중단. 같은 명령으로 재개 가능." >&2
    exit 0
  fi
  if [ "$claude_exit" -ne 0 ]; then
    echo "[mvp-headless] iteration $i: claude 비정상 종료(exit=$claude_exit) — 다음 반복에서 재개 프로토콜로 복구." >&2
  fi
done

echo "[mvp-headless] max iterations($MAX_ITER) 도달 — 중단. 미완 스토리는 prd.json 참조, 같은 명령으로 재개." >&2
exit 0
