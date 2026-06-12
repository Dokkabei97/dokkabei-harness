---
name: mvp-from-startup
description: "startup 플러그인 산출물(.planning/business/)을 MVP 하네스 인테이크로 승계하는 브릿지 — 린 캔버스·검증 가설·시장조사를 읽어 Stage 0 인테이크 질문을 미리 채운 뒤 mvp-orchestrator를 Stage 1(기획 PRD)로 진입시킨다. 그린필드 전용. startup으로 사업 가설을 세운 뒤 코드까지 이어갈 때 사용."
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /mvp-from-startup - 비즈니스 가설 → MVP 브릿지

`startup` 플러그인(`/lean-canvas`·`/validate-idea`·`/market-research`)이 `.planning/business/`에 남긴 산출물을
MVP 하네스의 **Stage 0 인테이크 입력으로 승계**해, `mvp-orchestrator`를 인테이크 질문 없이(또는 최소 질문으로)
Stage 1(기획 PRD)부터 진입시킨다. `/mvp-new`가 "빈 아이디어 한 줄"에서 출발한다면, 이 커맨드는
"이미 검증된 사업 가설"에서 출발한다 — 그만큼 인테이크 왕복을 줄이는 게 목적이다.

> Stage 로직 전체는 `mvp-orchestrator`가 수행한다. 이 커맨드는 **비즈니스 산출물 → 인테이크 매핑**과
> 진입만 담당하며, PRD/디자인/스캐폴딩/루프 로직을 중복 기술하지 않는다.

## Triggers
- `/lean-canvas`·`/validate-idea`로 사업 가설을 세운 뒤 "이제 실제로 만들어보자"로 넘어갈 때
- `.planning/business/`에 비즈니스 산출물이 있는 그린필드에서 MVP를 시작할 때
- "린 캔버스대로 MVP 만들어줘", "검증한 가설로 프로토타입 시작" 요청

## Usage
```
/mvp-from-startup [옵션]

Options:
  --auto              사용자 게이트 2개(★G1 스코프·★G2 스택)를 추천안으로 자동 채택 (해커톤/실험용)
  --stack <preset>    스택 사전 지정으로 ★G2 생략 — kotlin-spring | python-fastapi | react-next | go-mux
  --stories-max <n>   prd.json 스토리 수 상한 (기본 10, 게이트 허용 범위 3~10)
```
(옵션은 `/mvp-new`와 동일하게 `mvp-orchestrator`에 전달된다. `--auto`와 함께 쓰면 인테이크부터 G2까지 무중단으로 골격이 선다.)

## Behavioral Flow

### Phase 0: 사전 점검
1. **그린필드 확인**: 기존 소스 트리·빌드 파일 위에서 호출되면 중단하고 스택별 플러그인(kotlin-spring·python-fastapi·go-mux·nextjs·search)을 안내
2. **비즈니스 산출물 존재 확인**: `.planning/business/` 하위 파일을 점검한다.
   - `lean-canvas.md`가 **없으면** 중단하고 `/lean-canvas <아이디어>` 선행을 안내 (이 브릿지는 비즈니스 입력이 전제)
   - 있으면 다음 단계로. `hypotheses.md`·`market-research.md`는 있으면 함께 읽고, 없으면 건너뛴다(선택 입력)
3. **기존 MVP 감지**: `.planning/mvp-*.md`가 이미 있으면(레포당 MVP 1개 전제) `/mvp-run` 재개 또는 `/mvp-status`를 안내

### Phase 1: 비즈니스 산출물 → 인테이크 매핑
`.planning/business/`의 산출물을 읽어 `product-strategist`가 Stage 0에서 던질 인테이크 질문(최대 3개: ①페르소나 ②코어 가치 루프 ③명시적 제약)의 **답을 미리 채운다**. 매핑 규칙:

| 비즈니스 산출물 블록 | → mvp 인테이크/PRD 입력 |
|----------------------|--------------------------|
| 린 캔버스 `Customer Segments`(얼리어답터) | 인테이크 ① 페르소나 → `## 페르소나` |
| 린 캔버스 `Problem` / `Existing Alternatives` | `## 문제 정의` |
| 린 캔버스 `Solution` / `Unique Value Proposition` | 인테이크 ② 코어 가치 루프 → `## 범위`(`### In` 후보) |
| 린 캔버스 `Channels`·`Revenue`·`Cost` | 보조 컨텍스트(가치 제안·가정) — 스코프 컷 판단 참고 |
| `validate-idea`의 리스크 큰 가설 Top 3 | 인테이크 ③ 제약 + **스코프 컷 우선순위**(가장 리스크 큰 가설을 검증하는 스토리를 In 우선) |
| `market-research`의 세그먼트·경쟁 | 유사 서비스 1-pass 조사 대체/보강 — 차별점·디폴트 기대치 |

**경계**: 매핑은 product-strategist에게 줄 **컨텍스트(질문 사전 답변)일 뿐** 자동 PRD 생성이 아니다.
- 린 캔버스는 서술형, prd.json은 검증형(Given-When-Then AC)이다 — **변환 작성은 product-strategist의 몫**이며, 비즈니스 문장을 "이 액션 후 이 결과가 일어나는가"로 재구성한다.
- 비즈니스 산출물에 없는 정보(예: 명시적 기한)는 여전히 인테이크 질문으로 사용자에게 묻는다. **모든 질문이 채워지지 않을 수 있다** — 빈 칸만 추려 최소 질문을 남긴다.
- maker/checker 분리는 그대로다: 채워진 입력으로 작성한 PRD도 Stage 1에서 `mvp-verifier`의 반증을 동일하게 받는다.

### Phase 2: mvp-orchestrator 진입 (Stage 1부터)
매핑 결과를 Stage 0 인테이크 답변으로 주입한 상태로 `mvp-orchestrator`를 진입시킨다. 이후는 표준 파이프라인:
- **Stage 1**: `product-strategist` PRD 작성 → `mvp-verifier` 반증 → 결정론 게이트 → ★G1 스코프 승인
- **Stage 2~3**: 디자인 스펙 → 스택 추천(★G2) → 스캐폴딩
- **Phase 종료**: Stage 0~3 산출 요약 후 `/mvp-run`(Stage 4 개발 루프) 가동 여부 확인

비즈니스 입력 덕분에 Stage 0 왕복이 사라지거나 1~2개 질문으로 축소되는 것이 정상 동작이다. 매핑에서 채운 항목과 여전히 사용자에게 물은 항목을 **1줄로 구분 보고**한다(예: "페르소나·코어 루프는 린 캔버스에서 승계, 기한만 질문").

## Boundaries

**Will:**
- `.planning/business/` 산출물을 읽어 인테이크 질문을 사전 충전
- 채운 항목/물을 항목을 투명하게 구분 보고
- 표준 mvp 파이프라인(게이트·반증·루프)을 그대로 적용

**Will Not:**
- 비즈니스 산출물 없이 동작 (→ `/lean-canvas` 또는 `/mvp-new` 안내)
- 린 캔버스를 prd.json으로 자동 1:1 변환 (검증형 AC 작성은 product-strategist가 수행)
- 기존 코드베이스 위 작업 (→ 스택별 플러그인)
- maker/checker 분리·게이트 우회 (승계 입력도 동일하게 반증·검증 대상)
