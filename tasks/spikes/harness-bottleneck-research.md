# "모델이 좋아져서 하네스가 병목" 주장 조사 — 판정 스파이크

- **성격**: 외부 담론 검증 + 레포 실측 대조 (분석 전용, 코드 변경 없음)
- **조사일**: 2026-09-20
- **질문**: 모델 성능 향상으로 하네스(플러그인·훅·스킬·서브에이전트·루프)가 성능/작업의 병목이 되었는가?
- **판정**: **절반만 사실.** 비판은 *조언 계층*(모델 능력을 대리하려는 스캐폴드)에 유효하고,
  *집행 계층*(도구 권한·exit code로 강제되는 게이트)에는 무효다. 이 레포는 두 계층의 비율이
  **13 : ~240**이며, 병목은 후자에 있다.

---

## (a) 외부 담론 — 주장 계보와 범위 한정

| 날짜 | 출처 | 요지 |
|---|---|---|
| 2024-12-19 | Anthropic `building-effective-agents` | "가장 단순한 해법부터, 필요할 때만 복잡도 증가". workflow vs agent 구분 원전 |
| 2025-06-12 | Cognition (Walden Yan) `Don't Build Multi-Agents` | 병렬 서브에이전트는 암묵적 결정이 충돌. **측정치 0건, 순수 논증** |
| 2025-06-13 | Anthropic `multi-agent-research-system` | 정반대: 멀티에이전트가 단일 Opus 4 대비 **+90.2%**(내부 eval, N 비공개) |
| 2025-07-14 | Chroma `Context Rot` | **18개 모델 전부** 입력 길이 증가 시 성능 하락 |
| 2025-07-30 | Lance Martin (LangChain) `Learning the Bitter Lesson` | "내가 부과한 구조가 개선을 활용하지 못하게 막았다". 단 **저수준 추상화(node/edge)는 괜찮다고 명시** |
| 2026-01-16 | Gregor Zunic (browser-use) `Bitter Lesson of Agent Frameworks` | 최강경 "모든 추상화는 부채". **근거는 가장 빈약(의견)** |
| 2026-04-19 | Addy Osmani (반대편) | "모델이 할 수 있는 것과 실제로 하는 것의 격차는 대체로 하네스 격차" |
| 2026-04-22 | **Walden Yan 자기 수정** `Multi-Agents: What's Actually Working` | 입장 번복 — "모델이 훨씬 자연스럽게 agentic해졌다". 현재 입장 = **쓰기는 단일 스레드, 읽기/판단은 멀티** |
| 2026-04-30 | Cursor `continually-improving-agent-harness` | 하네스는 지속 엔지니어링 대상. 툴콜 에러를 한 자릿수 차수 감소 |
| 2026-05-08 | Han Lee `Hidden Technical Debt: Agent Harness` | 핵심 정식화: **"가진 컴퓨트 수준에 맞게 구조를 추가하고, 그다음 제거하라 — 그 구조가 다음 컴퓨트 수준의 병목이 되기 때문"** |
| 2026-09-02 | arXiv 2609.03141 (Patel·Stoica·Zaharia 등) | "모델 한계를 보완하려 설계된 시스템 계층은 점점 모델에 흡수된다" — 단 *persistent semantic context* 계층은 **존속** |

### 범위 한정 (결정적)
**"모든 하네스를 짓지 마라"고 말한 1차 출처는 browser-use 한 곳뿐이며, 그곳이 근거가 가장 빈약하다.**
- Cognition → *병렬 쓰기* 멀티에이전트만. 10개월 뒤 저자 본인이 수정
- Lance Martin → *고정 워크플로우 그래프 + 강제 병렬 출력*만
- Han Lee / arXiv → "짓지 마라"가 아니라 **"제거 가능하게 지어라(removable)"**
- Anthropic → 2024년부터 일관되게 "단순함부터"이지 "프레임워크 금지"가 아님

→ 비판 대상 = **모델 능력을 대리하려는 스캐폴드**(플래닝 모듈, 출력 파서, 검증 레이어, 병렬 쓰기 오케스트레이션).
→ 비판 대상 **아님** = 도구/샌드박스/권한 경계, 결정론적 게이트, 컨텍스트 저장·압축, 관측성.

### ⚠️ 인용 금지 (조작 확인)
- **"같은 모델이 한 하네스에서 46%, 다른 하네스에서 80%"** — 널리 인용되지만 Cursor 공식 블로그 원문에
  **해당 수치가 존재하지 않음**(직접 열어 확인). 출처는 마케팅 블로그뿐.

---

## (b) 정량 실측 — 병목 6범주별 근거 유무

| 범주 | 실측 | 근거 |
|---|---|---|
| 토큰/컨텍스트 오염 | ✅ | Chroma 18모델. **단 측정 대상은 "컨텍스트 길이"이지 "하네스"가 아님** — 하네스 비판에 전용된 것 |
| 툴/스킬 공간 비대 | ✅ | BFCL 370툴 × **Claude Sonnet 4.6**: 고정 상위5 노출 **87.1%** vs 적응형 K=2.2 노출 **93.1%**(중난도 60.9%→**76.8%**) `arXiv:2605.24660` |
| 모델 자율 억제 | ❌ | ablation 0건. 전부 의견 |
| 유지보수 부채 | ❌ | 서술적 주장만 |
| **scaffold rot** | ⚠️ 프롬프트 계층만 | Prompting Inversion(GSM8K 1,317문항): 제약형 프롬프트 gpt-4o **+4pp** / gpt-5 **−2.36pp** `arXiv:2510.22251`. CFA: CoT가 GPT-4 **+7.6~14.2pp** / Gemini 3.0 Pro **−0.6~−1.5pp** `arXiv:2512.08270`. **에이전트 하네스 세대 A/B는 여전히 0건** |
| 멀티에이전트 분절 | ⚠️ 역방향 | 유일한 정량 증거가 *찬성* 쪽(Anthropic +90.2%). MAST(1,600 트레이스, κ=0.88)는 "인기 벤치마크에서 이득이 종종 미미" |
| 지연/비용 | ✅ | Anthropic: 에이전트는 챗 대비 **~4×** 토큰, 멀티에이전트 **~15×**. BrowseComp에서 **토큰량 단독이 성능 분산 80% 설명** |

### 하네스가 이긴 실측
- **AlphaCodium**(테스트 기반 반복 플로우): CodeContests GPT-4 pass@5 **19% → 44%** `arXiv:2401.08500`
- Self-consistency: GSM8K **+17.9pp** `arXiv:2203.11171`
- Anthropic: 툴 설명 개선만으로 후속 태스크 완료시간 **40% 단축**
- mini-swe-agent: 에이전트 클래스 **100줄**로 SWE-bench Verified **>74%** — 단 *동일 모델 × 두꺼운 프레임워크* 대조는 미공개

### 갈림선
- **하네스가 손해**: 의존성 많고 단일 컨텍스트 공유가 필요한 태스크(=코딩), 컨텍스트·툴 목록 비대, 신세대 reasoning 모델 + 단답형, **검증 불가능한 목표**
- **하네스가 이득**: **결정론적 검증 게이트가 존재할 때**, 다수결 샘플링 가능할 때, 넓은 병렬 탐색(리서치형), 툴 후보를 좁혀주는 선택기가 있을 때

---

## (c) 벤더 공식 권고 — 조언은 부채, 집행은 권장

전부 `code.claude.com/docs/en/best-practices.md` 원문 직접 확인:

- 전제: *"Claude's context window fills up fast, and performance degrades as it fills… The context window is the most important resource to manage."*
- 조언 계층: *"**Bloated CLAUDE.md files cause Claude to ignore your actual instructions!**"* /
  *"If Claude already does something correctly without the instruction, **delete it or convert it to a hook**."*
- 집행 계층: *"Unlike CLAUDE.md instructions which are advisory, **hooks are deterministic and guarantee the action happens**."*
- 검증 게이트 사다리: prompt → `/goal` → **Stop hook(결정론 게이트)** → verification subagent.
  *"The `/goal` and Stop hook versions are what let an unattended run finish correctly without you."*
- 적대적 리뷰어 경고: *"A reviewer prompted to find gaps will usually report some, even when the work is sound… Chasing every finding leads to over-engineering."*

### ⚠️ 레포에 직접 영향 — Stop 훅 연속 블록 상한 8회
> *"a Stop hook runs your check as a script and blocks the turn from ending until it passes.
> **Claude Code overrides the hook and ends the turn after 8 consecutive blocks.**"*

레포 기본값은 `LOOP_MAX_ITER=24`(mvp·feature-loop) / `12`(generic)이고 문서 권고는 "task 수 × 3":
- `plugins/feature-loop/hooks/floop-loop-stop-hook.sh:55`, `plugins/harness/hooks/generic-loop-stop-hook.sh:59`
- `plugins/feature-loop/skills/floop-loop-protocol/SKILL.md:100,118`, `feature-loop-orchestrator/SKILL.md:105`

→ **실측 확정 (2026-09-20, n=3)**: 격리 디렉터리에 항상 `exit 2` 하는 Stop 훅(자기제한 15회)을 등록하고
`claude -p` 를 3회 실행 → **훅 호출 횟수 9 / 9 / 9 (편차 0)**. 즉 연속 블록 8회까지만 유효하고
**9번째 `exit 2` 는 무시되며 턴이 강제 종료**된다. 공식 문서 기술과 일치하며 결정론적이다.
따라서 `LOOP_MAX_ITER=24` 는 **세션 내에서 도달 불가**이고 실효 천장은 8이다.
헤드리스 경로(`bin/floop-headless.sh:212`, `while` 로 `claude -p` 반복)는 매 호출이 새 턴이라 무관하다.

**미해결 (설계 결정 필요)**: 엔진은 이 상한을 감지하지 못해 **핸드오프 기록 없이 조용히 종료**된다.
단순히 `iter >= 8` 로 자기제한하면 **헤드리스 경로가 8에서 잘못 끊긴다** — `iter` 는 loop-state.json 의
*누적* 카운터이지 턴 내 연속 블록 수가 아니기 때문이다. 올바른 수정은 훅 payload 의 `stop_hook_active`
플래그로 **턴 단위 연속 블록 카운터**를 따로 유지하는 것이며(false 면 리셋), 엔진 3벌 + bats 회귀 테스트
동반 변경이 필요하다.

### 네이티브가 흡수한 것 (원문 확인)
- `/goal` — completion condition 설정, 매 턴 후 small fast model 이 Not yet met / Met / Impossible 판정.
  **단 판정 주체가 모델**이므로, 이 레포의 명제("완료 판정은 모델이 아니라 하네스가 한다")를 대체하지 **못한다**.
- `/batch` — git 레포에서 변경을 **5~30개 서브에이전트**로 분할, 각자 worktree + PR.
  → `graph-engineering-verdict` 가 "미보유"로 기록한 **fan-out-fan-in 을 플랫폼이 네이티브로 제공**.
  Stage C 병렬 레인의 재고 트리거는 이제 *스키마 확장*이 아니라 `/batch` 평가로 대체 가능.

---

## (d) 레포 실측 — 비용과 발동

### 세션 고정비
| 구분 | 레포 전체 | 설치분(17/23) |
|---|---|---|
| skill | 92개 / 47,436자 | 69개 / 31,535자 |
| agent | 59개 / 37,705자 | 36개 / 20,333자 |
| command | 102개 / 43,632자 | 61개 / 22,377자 |
| **합계** | **253개 / 128,773자** | **166개 / 74,245자 (~29.7k tok)** |

토큰은 문자÷2.5 **추정치**(한/영 혼용). 미설치 6개(eng-gov·enterprise·finance·hr·legal·scaleup)
= 87컴포넌트 / 54,528자 → **세션 비용 0의 사장 자산**(desc 최장 상위 10 전부 여기 소속).
부가: CLAUDE.md 3,900B + 글로벌 2,717B + MEMORY 1,268B ≈ ~2.6k tok. 훅 등록 22건.

발동 시: SKILL.md 92개 합계 **1,165,316B**(중위 7,657 / max 62,454 = search/lucene-internals),
references/ 55개 448,770B. 루프 프로토콜 스킬 4종만 **67KB**.

### 집행 13개 vs 조언 ~240개
**(A) 모델이 우회 불가 = 13개**, 4개 플러그인에 집중
- exit 2 차단 11건 — 대표: `{mvp,feature-loop}/hooks/prd-guard.sh:62`·`tasks-guard.sh:62`
  (**verified 마커 없는 `passes:true` 를 jq로 false 원복** — 유일하게 모델 출력을 되돌리는 장치),
  `test-guard.sh:37`(테스트 삭제 차단), Stop 루프 3종, `subagent-stop-verify.sh:84`×2,
  `base/bin/hooks/block-dev-server.js:15`, `workflow/hooks/remind-claude-md-sync.js:75`
- Edit 박탈 checker = `mvp-verifier`·`feature-verifier`·`wiki-auditor` **3개뿐**
- ⚠️ **구멍**: `test-guard.sh:23-26` — jq 미설치 시 `exit 0` **fail-open**

**(B) 조언일 뿐**
- **`gate-*.sh` 27개 중 22개가 어떤 hooks.json 에도 미등록**(eng-gov 8·enterprise 8·scaleup 6 —
  해당 플러그인에 hooks.json 자체가 없음) → 모델이 "실행하기로 결심"해야만 도는 = 조언
- base 훅 16건 중 **14건이 exit 0 비차단**(warn-*/check-*/format-*/notify-*)
- SKILL.md 본문 1.11MB + references 438KB 전량, NO-EDIT 에이전트 46개 중 43개

### 실사용 텔레메트리 (전 프로젝트 합산)
`.claude/skill-trace.jsonl` **10개 파일** = **601 이벤트 / 121 세션 / 352 프롬프트,
2026-07-05 ~ 09-20**. 트레이스 경로는 `$CLAUDE_PROJECT_DIR/.claude/`(프로젝트 로컬, `OBSERVE_TRACE=1` opt-in).

- **스킬 발동 13회 (전체)** → 레포 스킬은 **3종 9회**뿐: `workflow:sync-claude-md`×7,
  `observe:observe-report`×1, `harness:team-harness`×1.
  나머지 4회는 네이티브(update-config·deep-research·claude-in-chrome·artifact-design)
- **에이전트 발동 20회 전부 네이티브**: Explore×10, general-purpose×4, Plan×3, claude-code-guide×3
  → **레포 에이전트 36개 설치 / 발동 0회**
- 13회 전부 `trigger=model` — 구간 내 사용자의 레포 커맨드 직접 호출 기록 0
- 즉 **352 프롬프트 중 레포 스킬 발동 9회(2.6%), 레포 에이전트 0회**
- **결정적 패턴**: 유일하게 반복 발동한 `sync-claude-md`(7/9)는 **exit 2 훅
  (`workflow/hooks/remind-claude-md-sync.js:75`)이 뒤를 받치는 스킬**이다.
  집행이 붙은 조언만 실제로 발동했다.

**구간 분해 (중요)**
| 구간 | 세션 | 프롬프트 | 스킬 | 에이전트 |
|---|---|---|---|---|
| 8 프로젝트 + 홈 (07-05~09-20) | 54 | 107 | 13 (레포 9) | 20 (레포 0) |
| `.buzz` 주 업무 레포 (09-06~08, 사흘) | 67 | 245 | **0** | **0** |

`.buzz` 는 사흘에 67세션(세션당 3.7프롬프트)으로 **헤드리스/단발 세션 패턴**이며, 해당 구간엔
`result`·`session_end` 이벤트도 0이다. 따라서 이 구간의 0회는 "스킬이 무시됐다"가 아니라
**"그 작업 방식에서는 스킬/에이전트 계층이 아예 관여하지 않는다"**로 읽어야 한다
(네이티브 에이전트조차 0회이므로 레포 자산만의 문제가 아니다). 부분 훅 커버리지 가능성도 배제 못 함.

계측 타당성: 동일 훅이 네이티브 에이전트 20회를 정상 기록했으므로 주 구간의 "레포 에이전트 0회"는
계측 실패가 아니다. 발동률도 하락하지 않았다(7월 25/90=28%, 9월 8/22=36%, `.buzz` 제외).
**한계**: OBSERVE_TRACE opt-in 이라 100% 커버리지는 증명 불가. 트레이스가 프로젝트 로컬이므로
누락 레포가 더 있을 수 있다(실제로 1차 스캔에서 `.buzz` 312줄을 놓쳤다 — 홈 전체 find 로 정정).

### 반증 — 루프 엔진은 실제로 값을 냈다
| 프로젝트 | 결과 | verified 마커 |
|---|---|---|
| `mvp/classify-review` | prd.json **7/7 passes**, gate 42 passed, 회귀 0 | 8건 |
| `mvp/findining` | tasks.json **8/8 passes**, next build 13페이지 | 8건 |
| `mvp/roast` | T-36까지 진행, 적대적 리뷰가 **실결함 3건 적발·수정** | **34건** |

즉 하네스의 가장 정교한 부분(집행 계층 + 루프)은 3개 실프로젝트를 완주시켰고,
가장 방대한 부분(조언 계층 ~240 컴포넌트 / 1.6MB)은 발동 기록이 없다.
단 이 루프 작업들은 대부분 2026-06 ~ 07-10 으로 **트레이스 구간과 거의 겹치지 않는다** —
따라서 "루프가 한 번도 발동되지 않았다"는 결론은 **성립하지 않는다**(집계 구간 밖).

---

## (e) 판정

1. **병목론은 조언 계층에 대해 사실이다.** 이 레포는 매 세션 ~30k tok(추정) 고정비를 내고,
   그 대가로 2.5개월 121세션·352프롬프트에서 레포 스킬 3종 9회·에이전트 0회를 얻었다. 공식 문서가 경고하는
   "bloated → Claude ignores your actual instructions"의 교과서적 사례다.
2. **집행 계층에 대해서는 거짓이다.** 모델이 좋아져도 *자기 검증을 우회하지 못하게 도구 권한에서 막는*
   문제는 모델 능력으로 해결되지 않는다(`prd-guard`/`tasks-guard` 의 passes 원복이 정확히 그것).
   공식 문서도 hooks/Stop hook 을 "advisory 와 달리 결정론적"이라며 권장한다.
3. **scaffold rot 은 프롬프트 계층에서만 실측됐다.** 에이전트 하네스의 세대 A/B 데이터는 아직 0건이므로,
   "모델이 올라가면 하네스가 손해"는 *유추*이지 측정된 법칙이 아니다.
4. **멀티에이전트 비판의 정량 증거는 오히려 반대편에 있다.** 이 레포의 maker/checker 분리는
   "쓰기는 단일 스레드, 읽기/판단은 멀티"라는 Cognition 의 *수정된* 입장과 이미 일치한다.

### 축소 후보 (근거 순)
1. **세션 비용을 실제로 줄이는 유일한 레버** = 설치 플러그인 축소. 미설치 6개 제거는 세션비 0 절감이므로
   우선순위가 낮다(유지보수 부채로만 유효). 실사용 0인 도메인 플러그인을 **프로젝트별 설치로 전환**해야 ~30k 가 내려간다.
2. **base warn-*/check-*/format- 14개 훅**(exit 0) — 공식 권고의 역방향(훅이 조언 역할). 린터로 이관.
3. **NO-EDIT 조언 에이전트 43개** — 실측 20/20 이 네이티브 Explore/general-purpose/Plan 로 갔다.
4. **대형 SKILL.md**(search 4종 210KB) — references/ 강등.
5. **Stop훅 루프 엔진 3벌 복제**(249+295+199행 + 프로토콜 67KB) — 엔진 1개 + 게이트 어댑터로 축약.
   **3벌 모두 동일한 8블록 상한에 걸린다**(위 실측) — 같은 결함을 3곳에 고쳐야 하므로 축약 근거가 하나 더 붙는다.

### 고쳐서 강화할 것 (축소 아님)
- `test-guard.sh:23-26` fail-open 제거 (집행 계층의 구멍)
- `LOOP_MAX_ITER` 기본값·문서 — 8블록 상한 실측 후 정정
- `gate-*.sh` 22개 훅 미등록 — 등록하거나 삭제(현 상태는 집행을 자칭하는 조언)

---

## (f) 증거 품질 자기고지
- 외부: 1차 원문 확인 **26건**(WebFetch 24 + PDF 전문 2), 인용 금지 판정 1건(Cursor 46/80), 미확인 다수 표기
- 레포: 전부 파일/명령 실측. 토큰 수치만 추정(문자÷2.5)
- **여전한 증거 비대칭**: 레포는 실측, 외부 에이전트 하네스 ablation 은 0건.
  `graph-engineering-verdict` 가 기록한 함정("레포가 유리하게 나온다")이 이 조사에도 그대로 적용된다.
- 미해결: Stop훅 8블록의 정확한 정의(연속 카운트 단위·리셋 조건·헤드리스 적용)는 **실측 필요**

---

## (g) 부수 발견 (조치 아님 — 분석만)

### 고아 에이전트 9건
디스패치 경로(스킬·커맨드·훅) 참조 **0건** + 실측 발동 0회 + 자기 플러그인 README 등재만인 에이전트:
backend-shared 3(`api-designer`·`migration-advisor`·`infra-integration-guide`) · kotlin-spring 2(`spring-developer`·`spring-boot-guide`)
· go-mux·nextjs·python-fastapi 각 1(`*-developer`) · search 1(`search-code-reviewer`).
**삭제 효과는 ~1.3k tok/세션(3,308자, 전체 29.7k 의 4.5%)뿐**이라 우선순위가 낮다 — 큰 레버는 설치 플러그인 축소다.
(2026-09-20 세션에서 실제로 삭제했다가 범위 오판으로 **전량 롤백**함. 분석 결과만 남긴다.)

### README 허구 기술 2건 (현존 — 에이전트 존치 여부와 무관하게 틀림)
- `plugins/kotlin-spring/README.md:9,48` — *"`spring-developer` 가 `/spring-gen` 의 실제 생성 엔진"*
- `plugins/go-mux/README.md:28` — *"커맨드가 내부적으로 `go-mux-developer` 에이전트를 활용"*

**실측 반증**: `*-gen` 커맨드 4개(`spring-gen`·`go-gen`·`fastapi-gen`·`nextjs-gen`) 전수에 `agent`/`developer` 언급이
**0건**이다. 커맨드가 직접 수행하며, README 만 존재하지 않는 위임 관계를 주장한다.

### `.gitignore` 함정 (조사 산출물 유실의 근본 원인)
`.gitignore:21-22` 가 `tasks` 와 `.planning` 을 **둘 다** 무시한다. 과거 `.planning/hermes-research.md`·
`.planning/graph-engineering-research.md` 가 "미커밋 유실"로 기록된 것은 부주의가 아니라 **구조적으로 커밋 불가**였기 때문이다.
이 리포트도 `git add -f` 로 강제 스테이징해야 했다. `tasks/spikes/task-graph-spike.md` 가 과거 커밋될 수 있었던 건
이 규칙 추가 이전이기 때문이며, 해당 파일은 `git show 575716d:tasks/spikes/task-graph-spike.md` 로 복구 가능하다.
