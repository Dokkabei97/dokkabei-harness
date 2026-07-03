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
