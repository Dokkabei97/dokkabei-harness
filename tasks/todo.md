# 통합 로드맵 구현 — P0 전체 + P1/P2 전체 (2026-07-02~03)

리서치 보고서 로드맵 승인분. P0 5건 → P1 9건 → P2 8건(-skill-eval 보류).

## Wave 1 — 병렬
- [ ] ④ 루프 엔진 bats 회귀 테스트 + GitHub Actions CI
  - tests/hooks/*.bats: mvp/floop Stop훅 정지조건·가드레일 전 케이스, capture-baseline, 게이트/가드 훅
  - .github/workflows/loop-engine-ci.yml (ubuntu+macos 매트릭스, md5 폴백 검증)
- [ ] ② 공식 document-skills 연계 (커맨드 2개 diff)
  - legal:/draft-legal-doc --format에 docx 추가 + 내보내기 Phase + md 폴백
  - startup:/pitch-deck --export pptx 신설(--format은 덱 형식으로 이미 사용 중) + Boundaries 조정
- [ ] ⑤ Context7 조회 규약화
  - backend-shared에 context7-docs-guide 스킬 1곳 신설 (분업 원칙 준수)
  - 스택 4종(kotlin-spring/python-fastapi/go-mux/nextjs) guide·gen에 참조 1줄씩

## Wave 2 — 병렬 (Wave 1의 테스트 구조 준수)
- [ ] ① base 보안 경고 훅 warn-security.js
  - 고신호 취약점 패턴 10~15종, 경고 전용(비차단), _lib/hook-stdin 컨벤션
  - hooks.json 등록(Edit|Write) + bats 테스트
- [ ] ③ headless 러너 물화
  - plugins/mvp/bin/mvp-headless.sh (recipe 승격 + verified 마커 재검사 강화)
  - plugins/feature-loop/bin/floop-headless.sh (신규 설계: ②ᴿ baseline 회귀 게이트 포함)
  - /mvp-run·/floop-run --headless 안내 분기, recipe 문서는 러너 참조로 개정
  - LOOP_CLAUDE_BIN 주입으로 테스트 가능화 + bats 테스트

## Wave 3 — P0 검증 (완료)
- [x] bats 전체 스위트 로컬 그린 확인 (79/79)
- [x] 컨벤션 검증(flow-validation 룰) + 반증 코드 리뷰
- [x] P0 결함 수정 (보안 훅 축): warn-security ReDoS(43.5s→0.039s)·readFileSync 가드·placeholder 정밀화 / hooks.json matcher 2분리·.env.* / CI bin 경로 / GATE_SCAFFOLD 상수
- [x] P0 결함 수정 (러너 축): 등가성(has_failure_marker 4개 엔진 바이트 동일)·headless-active PID 락·매 반복 loop-active 재검사·워치독(TERM→KILL) — 재검증 99/99 그린 + 실측 프로브 5종 통과. 잔여 low 2건: 워치독 kill이 자식 프로세스 미정리(고아 잔존), stderr 잡 컨트롤 노이즈

## P1/P2 Wave A — P0와 파일 비중첩 8건
- [x] P1-7 legal /contract-redline (85줄) + 오케스트레이터 라우팅 1행
- [x] P1-2 workflow /retro (138줄) + retro-compound 스킬 (191줄)
- [x] P1-4 review-mr confidence 규약 + analyze 3종 선택 디스패치 (+106줄)
- [x] P2-3 신규 finance 플러그인 (agents 2 · commands 3 · skills 2)
- [x] P2-8 신규 hr 플러그인 축소판
- [x] P2-7 startup /content-draft + brand-voice + /feedback-synthesis (+content-guide 스킬, 템플릿 4종)
- [x] P1-8 Task Master/beads 스파이크 — 판정: 4건 전부 기각. 재고 트리거 = Stage C 병렬 레인 실도입 시 depends_on+ready 페어 일괄 도입 (tasks/spikes/task-graph-spike.md)
- [x] P2-4 doc-coauthoring 얇은 연계 (workflow:doc-collab-guide, 87줄 — 공식 스킬은 example-skills 소속으로 확인)

## P1/P2 Wave B — 루프 엔진·harness 클러스터 (전건 완료)
- [x] P1-5 PreCompact 재개 앵커 훅 (mvp/floop 공유 스크립트, 5줄 상한, jq degrade)
- [x] P1-5 workflow HANDOFF 자동 스냅샷 훅 (PreCompact/SessionEnd, 마커 섹션 교체, loop-active 상호 배타)
- [x] P1-6 SubagentStop verifier 집행 훅 + verify-round 규약 + 차단 2회 자가치유(F2 수정)
- [x] P1-6 오케스트레이터 verify-round 규약 명문화 + verifier 에이전트 refuted 계약(F3 수정)
- [x] P2-6 교차 모델 반증 --cross-check (verifier 턴 내부·마커 생성 전 — SubagentStop 집행과 양립하는 유일 배치) + 커맨드 옵션 등록(F7)
- [x] P2-2 harness /loop-run·/loop-stop + engine=generic 스코프 Stop훅 + 3중 루프 경계 표 + CRLF 방어(F5)
- [x] P2-5 verify-flow LOOP 룰셋(10룰, 10번째 룰셋) + loop-stop-hook 템플릿 역이식(옵션 블록 4종 + eval→bash -c·오탐 정규식 교체)
- [x] P1-3 create-flow --from-lessons 모드 (retro의 #가드-훅-후보 소비) + XRF-016 드리프트 룰
- [x] P1-1 nextjs ↔ frontend-design 연계(설치 구문 웹 실검증) + nextjs-guide 경계 문단 + mvp ux-designer Will Not 1줄
- [x] P2-1 floop --worktree stage① (종료 절차 remove --force 교정, F1) + worktree-lanes.md 로드맵(스파이크 재고 트리거 연결)

## 최종 — 검증·통합 (완료)
- [x] 전체 bats 151/151 그린 + 정적 검사(셸 22·JS 16·hooks.json 5·CI YAML) + 계약 정합 + 반증 리뷰 F1~F8 전건 수정/판정
- [x] marketplace.json 통합: finance/hr 등록, 스택 3종 requires:["backend-shared"]+dependencies 이중 표기(P1-9), base category 정규화(develop)·description 교정(analyze 복붙 해소), 버전 범프 12건
- [x] workflow 스킬 4종(sync-claude-md·document-latest·issue-tracker·post-merge) 설치 캐시→저장소 복원 (git 이력에 없던 드리프트 해소)
- [x] 보류 기록: /skill-eval (공식 skill-creator eval과 경계 미정의 — 재구현 리스크)

## Review (2026-07-03 완료)
- 규모: 47개 기존 파일 수정(+746/-212) + 신규 디렉토리 25건(테스트 12파일 151케이스, 신규 플러그인 2종, CI, 러너 2종, 훅 5종 등)
- 검증: bats 151/151, shellcheck --severity=error 22/22 클린, 반증 리뷰 발견 F1~F8 전건 조치(F6 레거시 이중 소유는 기존 동작·잔존 리스크로 문서화만, F8은 marketplace 등록으로 해소)
- 남긴 백로그: 워치독 kill의 자식 프로세스 미정리(low), stderr 잡 컨트롤 노이즈(cosmetic), mvp/floop loop-state 직접 기록의 원자성(LOOP-008 레거시 예외로 문서화), PreCompact stdout 주입 실효가 클라이언트 버전 의존(무해), 기존 base 훅들의 readFileSync 미가드(기존 버그 — 별도 결정 필요)
- 교훈: (1) 워크플로우 resume은 prefix 캐시라 병렬 블록 중간 실패 시 블록 전체 재실행 — 대량 실패 시 잔여분만 담은 신규 워크플로우가 경제적 (2) 세션 한도 실패도 산출물은 트리에 남는 경우가 많음 — 재실행 전 트리 실측이 먼저 (3) 에이전트 간 공유 상태(loop-active, verify-round)는 계약을 프롬프트에 명문화하고 별도 정합 검증자를 두는 것이 유효했음

## 원칙
- 커밋은 사용자 요청 시에만. marketplace.json/plugin.json은 통합 패스에서만 수정.
- 훅 버그 발견 시 무단 수정 금지 — 플래그 후 별도 결정.

## Review
(완료 후 기록)

---

# 하네스 분석 (2026-07-03)

## Plan
- [x] 저장소 구조와 플러그인/하네스 엔트리포인트 파악
- [x] 실제 에이전트·스킬·커맨드 파일과 등록 문서 대조
- [x] 오케스트레이터/검증/루프 하네스 핵심 계약 점검
- [x] 주요 리스크와 개선 우선순위 정리

## Review
- 구조: 18개 플러그인, 72개 스킬, 42개 에이전트 파일, 71개 커맨드. marketplace 등록명과 plugins 디렉터리는 일치.
- 검증: `bats tests/hooks` 151/151 통과. hooks.json 5개 모두 jq 파싱 성공.
- 주요 리스크: `claude/CLAUDE.md` 하네스 등록 포인터 부재, `product-strategist` 에이전트명 중복, 19개 SKILL.md가 500줄 규약 초과, 일부 레거시 커맨드가 CMD 필수 섹션/frontmatter 미충족.
- 권장 순서: 등록면 정합화 -> 에이전트명 충돌 해소/디스패치 네임스페이스 확정 -> 장문 스킬 references 분리 -> 레거시 커맨드 구조 보강.

---

# 하네스 평가·보완·추가 (2026-07-04)

리서치 워크플로우(7클러스터 감사 + 반증검증 ∥ 5축 외부 리서치)로 60+ findings·40+ 후보 도출.
세션 한도로 판정·합성 단계는 실패 — 완료 산출물 실측 후 핵심 high findings를 직접 검증해 범위 확정.

## 보완(수정) — 완료

- [x] **base warn-security 회귀 복구(high)** — 간판 보안 훅 2엔트리만 표현식 matcher(`tool == ...`)라 실측상 미발화 = 완전히 죽어 있었음(bff01ca에서 고친 컨벤션을 5507ba7이 재도입한 회귀). hooks.json matcher를 `Edit`/`Write` tool명으로 전환 + 확장자 필터를 스크립트 내부(CODE_EXT)로 이관.
- [x] **check-py-compile RCE 수정(high, 보안)** — 파일명을 execSync 문자열에 JSON.stringify 보간 → `$()`/백틱 명령 치환 가능(PoC 확인). execFileSync 인자배열로 전환(format-prettier 패턴). 회귀 가드 bats 추가.
- [x] **block-md-creation ↔ workflow 충돌 해소(high)** — `/handoff`(HANDOFF.md)·`/retro`(tasks/lessons.md)·`/release-notes`(CHANGELOG.md) 산출물이 차단됨. ALLOWED에 HANDOFF/CHANGELOG 추가 + `tasks/` 경로 예외.
- [x] **permissionMode 위반 제거(high)** — 플러그인 배포 에이전트 4종(spring/fastapi/go-mux/nextjs-developer)이 AGT-020d(보안상 금지) 위반. `permissionMode: plan` 제거.
- [x] **tdd.md 유령 참조 교정(high)** — 존재하지 않는 tdd-guide 에이전트 5회 참조 → 실제 `test:tdd-workflow` 스킬로 교정, 없는 커맨드 참조 정리.
- [x] **search-pipeline-reranking §1 사실 오류 정정(high)** — §1 전체가 OpenSearch 전용 API(`_search/pipeline`, request/response_processors)를 ES 8.x로 오기. ES 실제 대안(filtered alias/애플리케이션 filter/rescore/retriever)으로 대체 + 경고 콜아웃 + description 정정.
- [x] **guards.bats 테스트-구현 드리프트 해소** — prd-guard/tasks-guard 테스트가 file_path 없이 호출해 경로 필터에서 조기 종료 → 핵심 집행 로직(마커 없는 passes 원복+차단)을 검증 못 하고 있었음(거짓 통과/실패). file_path 이벤트 주입으로 실제 계약 검증.
- [x] **warn-console-log/println/print 크래시 방지** — existsSync 통과 후 read 실패(EACCES/TOCTOU)에 무방비 → try/catch passthrough 가드(warn-security 패턴).
- [x] **문서 드리프트** — README(구 agents/gemini/hooks 구조 → plugins/ 19종·설치법·테스트), claude/CLAUDE.md(하네스/마켓플레이스 등록 포인터 신설).

## 추가(신규) — 완료

- [x] **workflow `/release-notes` 커맨드** — glab MR 머지 이력 → conventional 분류 → 한국어 체인지로그 → semver 판단 → 태그/Release 안내. post-merge(이슈/문서)·review-mr(리뷰)와 경계 명시. CMD 6필드+8섹션 준수.
- [x] **tests/hooks/hooks-registration.bats(신규 lint)** — 모든 plugin hooks.json의 matcher가 tool명 regex인지(표현식 미발화 회귀 클래스 검출)·참조 스크립트 실재를 검사. warn-security류 등록면 결함을 CI에서 결정론적으로 잡는 안전망.

## 기각(중복/과의존)

- pipeline-triage 스킬 — search의 index-pipeline-check 커맨드 + search-data-pipeline(lag 모니터링 포함) + search-diagnostics와 중복.
- daily-brief — glab+Plane+Slack 3중 외부 의존으로 유지보수 렌즈 감점.
- devops/incident-response 신규 플러그인 — 규모 과대(large), 이번 범위 밖.

## 검증

- bats 177/177 그린(151→177, +26 신규 케이스). JS 6종 `node --check` 클린, hooks.json/marketplace jq 파싱, 신규 커맨드 CMD 구조 충족.
- 자가 반증 리뷰: CODE_EXT 오탐 경계(.environment 미매칭), TASKS 정규식 경계(mytasks/ 미매칭), execFileSync stderr 캡처, block-md 과허용 특성(기존 README와 동일) 확인.

## 플래그 — 별도 결정(무단 수정 금지 원칙 준수)

- **버전 범프 필요(통합/릴리즈 시)**: base·workflow·kotlin-spring·python-fastapi·go-mux·nextjs·test·search plugin.json + marketplace. 이번엔 파일 변경만, 버전은 미변경.
- **test 플러그인 버전 드리프트**: marketplace 1.0.0 vs plugin.json 1.1.0.
- **훅 no-op/오도(로직 수정 필요)**: log-pr-mr.js가 없는 필드 `tool_output.output` 참조(→ tool_response), notify-build-async가 '분석' 없이 메시지만 출력.
- **미수정 findings(규모/전문성)**: search 에이전트 6종 AGT-009/007/011 미충족, search-code-reviewer 참조 계약 6건 깨짐, post-merge↔issue-tracker v2.0 드리프트, backend-shared 분업 위반(api-design/dto-design가 Kotlin 전용), SKILL 500줄 초과 19+종, HK-005 룰 vs base 중복 matcher 상충, product-strategist 에이전트명 중복(mvp/startup), etc/startup 마켓플레이스 메타 빈약.
- **claude/settings.json 레거시 스냅샷**: 인라인 node -e 훅 15건이 표현식 matcher(미발화) + base와 이중 소유 — 별도 정리 필요.

## 원칙(유지)
- 커밋은 사용자 요청 시에만. marketplace.json/plugin.json은 통합 패스에서만.
- 훅 로직 버그는 무단 수정 금지 — 플래그 후 별도 결정(단, 죽은 기능 복원·RCE·명백한 플러그인 충돌은 저장소 자체 컨벤션 복원으로 수정).

---

# observe 고도화 — 계측 기반 하네스 개선 루프 (2026-07-04)

방향: hermes(사용 패턴→스킬 생성, 생성형)와 대비되는 **평가형 루프** — 기존 하네스(스킬 72·커맨드 72·에이전트 42·훅 34)가 잘 호출·사용되는지 계측하고 그 결과로 개선을 제안한다. 비용/토큰은 내장 OTel 위임 원칙 유지, hook 전용 영역(미발화·why 상관·세션 경계)에 집중. 발화율 사전 벤치마크는 skill-creator eval 경계 밖(재구현 금지 — /skill-eval 보류 결정 준수).

## Plan
- [x] W0 기준선: 기존 2훅(trace-prompt/trace-skill) bats 회귀 테스트 신설 (tests/hooks/observe-trace.bats) — 실트레이스 0건·테스트 전무 상태이므로 확장 전 현행 스키마 검증이 선행
- [x] W1 수집 확장 (additive, OBSERVE_TRACE 게이트·stdout 무출력·항상 exit 0 계약 상속):
  - [x] turn-context 추출을 _lib/turn-context.js로 분리 (trace-skill 동작 불변)
  - [x] trace-skill.js: +tool_use_id, +prompt_id, +turn_command(이미 파싱되고 버려지던 provenance), +부모 에이전트(agent_id/agent_type)
  - [x] trace-prompt.js: +prompt_id, +is_command
  - [x] 신규 trace-agent.js — PreToolUse(Agent|Task): type:'agent' 레코드(subagent_type, description·prompt 절단, why, 부모 에이전트)
  - [x] 신규 trace-result.js — PostToolUse(Skill|Agent|Task): type:'result' 레코드(tool_use_id join 키, response_bytes) → duration/완료 여부 사후 계산
  - [x] 신규 trace-session.js — SessionStart/SessionEnd: 세션 경계 레코드(reason, plugin_root — 인벤토리 join 루트 근거)
  - [x] hooks.json 4엔트리 추가 (matcher는 tool명 regex만 — hooks-registration.bats 자동 커버)
- [x] W2 분석·개선 레이어:
  - [x] bin/observe-report.js — 의존성 없는 결정론 집계기 (--json/--trace/--plugins-dir/--window/--candidates)
  - [x] tests/hooks/observe-report.bats — 픽스처 트레이스+가짜 플러그인 트리로 집계 검증
  - [x] commands/observe-report.md — /observe-report: 수집 상태 점검→집계→LLM 해석(미발화 judge·user-only 스킬·사장 자산)→개선 제안 라우팅(retro (c)형 제안서까지만, 파일 수정 금지)
- [x] W3 통합: README observe 문단, plugin.json 1.1.0 + marketplace.json observe 엔트리 정합, bats 전체 그린, 반증 리뷰

## Review (2026-07-05 완료)
- 규모: observe 훅 2→6종(+_lib/turn-context.js 분리), 집계기 1종, 커맨드 1종, bats 신규 57케이스(트레이스 35 + 집계 22). 전체 스위트 234/234 그린(기존 177 유지).
- 검증: bats + node --check + jq + 실트리 라이브 프로브(인벤토리 19플러그인·72스킬·73커맨드·42에이전트 정합) + 훅→트레이스→집계 엔드투엔드 프로브.
- 반증 리뷰(4관점 finder → 발견별 반증, 26에이전트): 발견 22건 중 확정 19건(관점 간 중복 3건 포함) 전건 조치:
  - 훅: local-command-stdout 레코드의 턴 경계 오염(trigger/why/turn_command 소실) 수정, is_command 절대경로("/Users/…") 오탐 수정
  - 집계기: 프롬프트 확장 전용 커맨드의 사용 크레딧 누락(HIGH — 매일 써도 미사용 표시) 수정, tail 매칭의 동명 자산 오폭(mvp/startup product-strategist 실충돌) → 네임스페이스 정확 일치 + bare 이름만 tail 허용, result join 근사 폴백(세션+target) 구현, null 라인 크래시·candidates 0 무제한·CRLF frontmatter·깨진 plugin.json 플러그인 전체 탈락·윈도우 밖 plugin_root 소실 수정
  - 문서: CMD-012 Related 섹션 추가, README 트레이스 경로 표기 교정
- 남긴 플래그(무단 수정 금지 원칙 — 별도 결정): _lib/trace.js 10MB 로테이션이 락 없는 statSync→renameSync 2단계라 동시 훅 실행 시 이론상 .1 덮어쓰기 경합(v1.0.0 기존 설계, best-effort 관측이라 영향 한정). 로컬 커맨드(/model 등)의 command-name 래퍼 레코드가 턴 경계로 채택되는 기존 동작은 유지(v1.0.0 의미 보존).
- 활성화 안내: 수집은 OBSERVE_TRACE=1 opt-in — 도그푸딩하려면 셸 프로필 또는 settings.json env 설정 필요(자동 활성화 안 함: 프롬프트 원문이 기록되므로 사용자 결정).

## 원칙(유지)
- 커밋은 사용자 요청 시에만. 훅 로직 버그 발견 시 플래그 후 별도 결정.
- 트레이스 스키마는 type 판별자 additive 확장만 — 기존 필드(trigger 의미, why null 규약) 재정의 금지, 소비자는 tolerant reader.

---

# wiki-ops 플러그인 신설 — llm-wiki 지식 운영 하네스 (2026-07-06)

방향: llm-wiki(../llm-wiki)를 **개발하는** 하네스가 아니라 llmwiki CLI를 **도구로 구동해**
지식 vault를 운영하는 하네스 (사용자 선택 확정). team-harness 7 Phase 준수.

## Plan
- [x] Phase 0~1: llm-wiki 실태 감사 + 3축 병렬 도메인 분석 (플러그인 컨벤션 / llmwiki 도구 표면 실측 / 루프엔진 재사용성·verify 룰)
- [x] Phase 2: 설계 — Pipeline+Producer-Reviewer, harness generic 루프 재사용(자체 훅 0줄·bats 의무 없음), 게이트 = lint 3종(LLM-0) 사슬, semantic은 감사 전용
- [x] Phase 3: 생성 — skills 6종(orchestrator+얇은 진입점 5) + references 2종 + agents 3종(curator maker / auditor checker Edit 미보유 / librarian) + README 쌍 + plugin.json. block-md-creation 훅은 doc-collab-guide 규약(.planning/docs 스테이징→mv)으로 우회
- [x] Phase 4: marketplace.json 등록 (20번째, requires:["harness"], 버전 2곳 1.0.0 동기 + XRF-016 3소스 일치 검증)
- [x] Phase 5: 검증 — (a) 실측 스모크: fake provider 임시 vault에서 게이트 red(exit 1)→큐레이터 규율 편집(quote 무접촉)→그린(exit 0) 수렴 증명 (b) 4렌즈 반증 워크플로우(SKL·ORC/AGT/XRF·SEC·QUA/정합성): critical 0·high 3·medium 4·low 14 → 20건 수정(28 edits), 회귀 재검증 그린

## Review
- 핵심 반증 수확: ① 디스패치 계약 드리프트(에이전트 3요소 hard-fail vs 오케스트레이터 부분 명시 → 헛루프 경로) ② auditor/librarian description의 "도구 수준 차단" 과장(Write+Bash 우회 실재 → 정직 서술로 교정) ③ ORC-003/004 Stage I/O 사슬 미폐합
- 실측 확보 함정(참조 문서에 물화): vault 내 .planning/ 미추적 파일이 ingest dirty 가드 exit 3 유발(Stage 0 .gitignore 선등록으로 예방), query 히트 0도 exit 0(citations로 판정), 단일 작성자 락(병렬 ingest 무의미), LLMWIKI_AIRGAP env는 MCP 전용(CLI는 --airgap 플래그만)
- 보류·플래그: ORC-008(claude/CLAUDE.md 팀 등록)은 레포 전체 사문화 룰 — 어떤 팀도 미등록, 룰 개정 or 일괄 등록은 별도 결정 / flow-validation Quick Reference의 "## How to Use" 필수 표기는 번호 룰(SKL-001~021)과 불일치 — 룰 원문 간 정합화 별도 결정
- 커밋 33a7557 푸시 완료 (sync-claude-md로 CLAUDE/README 쌍 19→20 동기 포함). 전파는 /plugin update (다음 세션부터 유효)

---

# hermes 학습 루프 리서치 — observe 고도화 사전 조사 (2026-07-06)

- [x] 정체 확정: NousResearch/hermes-agent (소스 clone 실측). Claude Code #57830 NOT_PLANNED → 플러그인 레이어 구현이 정답(observe 전제 확인)
- [x] 메커니즘 실측: 3중 액터(포그라운드 지시+nudge 10iter / 매턴 배경 리뷰 포크 / 유휴 curator 7d·30/90d 전이·삭제 금지) + 품질 게이트 4종(update-over-create 4단·provenance·read-before-write·do-NOT-capture)
- [x] 산출물: .planning/hermes-research.md — observe 이식안 7건(라이프사이클 제안 승격, 4단 강등 규칙, 가드 4종, 교정 신호 분류 등) + 결합 수위 권고(평가형 유지, 생성형은 3단 옵트인)
- 비고: deep-research 검증 단계는 세션 한도로 중단 → 1차 소스 실측으로 대체 (미검증 주장 5건 중 4건 소스로 확인)

---

# observe 고도화 — hermes 이식안 구현 (2026-07-06)

리서치(.planning/hermes-research.md) 이식안 7건 중 6건 구현, 1건(매턴 LLM 포크) 비권장 판정대로 제외.

## Plan → Review
- [x] 이식안 1 (라이프사이클): observe-report.js에 사용 자산의 stale(≥30d)/archive(≥90d) 후보 집계 추가 — `inventory.lifecycle`, `--stale-days/--archive-days`, 판정 시각 `--now` 주입(테스트 결정론), `meta.coverage`로 관측 기간 부족 캐비앳. 미사용-전체는 unused_* 버킷과 분리(관측 개시 전 이력과 구분 불가)
- [x] 이식안 5 (교정 신호): `followups` 수집 — 스킬/에이전트 호출 직후 평문 프롬프트 쌍(커맨드 프롬프트는 쌍 없이 소거, session_end 소거). candidates와 동일한 "결정론 수집 → LLM 판정" 분리. 커맨드 Phase 3에 교정 판정 절 신설
- [x] 이식안 2+4 (4단 강등·read-before-write): observe-report.md Phase 4에 "제안 공통 규율" 3종 명문화 (read-before-write / update-over-create 4단+세션 아티팩트명 기각 / 부정 주장 금지)
- [x] 이식안 3 (do-NOT-capture): workflow retro-compound §5에 6번 원칙 추가 — 환경 의존 실패·부정 주장·해소된 일시 오류·"고치는 방법으로만 기록" 4종 가드
- [x] 이식안 7 (생성형 결합 전제): observe README 쌍에 v1.3.0 문단 — agent-created 격리 + 삭제 금지 + read-before-write 전까지 평가형 유지
- [x] 검증: bats 264/264 그린(신규 6케이스 — lifecycle 3·coverage 1·followups 2), node --check, jq, llm-wiki 실트레이스 스모크(20플러그인 인벤토리 정합·빈 lifecycle/followups 정상)
- [x] 버전: observe 1.2.0→1.3.0, workflow 1.3.0→1.4.0 (plugin.json ↔ marketplace 2곳 동기)
- 미커밋 — 커밋은 사용자 요청 시에만
