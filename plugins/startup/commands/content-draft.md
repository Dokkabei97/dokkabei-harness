---
name: content-draft
description: |
  브랜드 보이스 기반 콘텐츠 초안 생성. blog/sns/pr/email 유형별 템플릿으로 초안을 작성하며, 첫 실행 시 5문항 인터뷰로 .planning/business/brand-voice.md를 물화하고 이후 모든 콘텐츠가 이 파일을 참조한다.
  Generates brand-voice-based content drafts using per-type templates (blog/sns/pr/email); on first run it materializes .planning/business/brand-voice.md via a 5-question interview, and all later content references that file. Use when: drafting a blog post, SNS copy, press release, or newsletter in a consistent brand voice.
category: marketing
complexity: standard
mcp-servers: []
personas: [growth-marketer]
---

# /content-draft - 브랜드 보이스 기반 콘텐츠 초안

`.planning/business/brand-voice.md`를 단일 기준으로 삼아 blog/sns/pr/email 콘텐츠 초안을 생성한다.
브랜드 보이스 파일이 없으면 5문항 인터뷰로 먼저 물화한다 — 톤 일관성은 세션 기억이 아니라
파일이 보장한다('상태는 파일에'). 초안 작성은 `growth-marketer` 에이전트에 위임하고,
유형별 구조와 brand-voice.md 스키마는 `content-guide` 스킬을 따른다.

## Triggers
- 블로그 글·SNS 포스트·보도자료·이메일(뉴스레터) 초안이 필요할 때
- 콘텐츠마다 톤이 달라져 브랜드 보이스를 파일로 고정하고 싶을 때
- 출시·투자 유치·기능 업데이트 소식을 여러 채널용 콘텐츠로 만들 때
- "블로그 초안 써줘", "SNS 홍보 문구 만들어줘", "보도자료 작성해줘", "뉴스레터 초안"

## Usage
```
/content-draft --type blog|sns|pr|email [주제/소재]

Options:
  --type blog|sns|pr|email   콘텐츠 유형 (필수, 누락 시 질문)
  --platform [플랫폼]         sns 세부 플랫폼 (linkedin|x|instagram|threads, 기본: linkedin)
  --length short|standard|long  분량 (기본: standard)
  --revoice                   brand-voice.md 5문항 재인터뷰로 갱신 후 진행
  --output [파일경로]          저장 경로 (기본: .planning/business/content/{날짜}-{type}-{슬러그}.md)
```

## Behavioral Flow

### Phase 0: 브랜드 보이스 확인·물화
- `.planning/business/brand-voice.md`를 Read. **존재하면 인터뷰 없이** 다음 Phase로.
- 부재 시(또는 `--revoice`) 5문항 인터뷰를 진행해 파일을 생성한다:
  1. **톤** — 문체(해요체/합니다체)와 브랜드 성격 형용사 2~3개
  2. **금지 표현** — 쓰면 안 되는 단어·표현 (과장 표현, 경쟁사 비방, 내부 용어 등)
  3. **타깃 독자** — 주 독자와 사전 지식 수준
  4. **핵심 메시지** — 모든 콘텐츠가 반복해야 할 1~3개 메시지
  5. **근거 자산** — 주장을 뒷받침할 수치·고객 사례·인증 (없으면 "없음"으로 기록 → 무근거 주장 금지가 강화됨)
- `.planning/business/`에 `lean-canvas.md`(UVP·고객 세그먼트)·`market-research.md`(세그먼트·차별점)가
  있으면 인터뷰 기본값으로 제안해 왕복을 줄인다. 스키마는 `content-guide` 스킬 §brand-voice.md 준수.

### Phase 1: 유형·소재 확정
- `--type` 확인(누락 시 질문), 주제/소재와 콘텐츠 목적(인지·전환·발표) 정리
- 기존 `.planning/business/` 산출물에서 소재로 쓸 근거(시장 데이터, 지표)를 수집

### Phase 2: 초안 작성 (growth-marketer 위임)
- `content-guide` 스킬의 유형별 템플릿(`references/{type}-template.md`) 구조를 따라 작성
- brand-voice.md의 톤·핵심 메시지를 적용하고, 금지 표현을 사용하지 않는다
- **근거 자산에 없는 수치·주장은 창작하지 않고 `[근거 필요]`로 표기**한다

### Phase 3: 브랜드·리스크 검수
- 금지 표현 잔존 여부를 Grep으로 확인, 발견 시 치환
- 과장 광고·표시광고법 리스크 표현(절대적 표현 "최고/유일", 보장성 표현 "100% 보장",
  근거 없는 비교 우위 단정, 효능·효과 단정 등)을 감지하면 결과 보고에 **1줄 안내**를 남긴다:
  > 표시광고법 리스크 표현 N건 감지 — `legal` 플러그인 `/compliance-check --regulation ecommerce` 검토 권장
- 자동 호출하지 않는다 — 문서 수준 협업 규약으로 안내만 하고, 판정은 legal 플러그인 몫

### Phase 4: 산출
- 초안을 `.planning/business/content/{YYYYMMDD}-{type}-{슬러그}.md`에 저장 (`--output`으로 override)
- 적용한 brand-voice 항목(톤·핵심 메시지)과 `[근거 필요]` 잔존 수를 1줄로 보고

## Tool Coordination
- **Agent**: growth-marketer 위임 (초안 작성·검수)
- **Read**: `.planning/business/brand-voice.md` 및 기존 비즈니스 산출물 참조
- **Write**: brand-voice.md(최초 1회/`--revoice`), 콘텐츠 초안 파일 생성
- **Grep**: 금지 표현·리스크 표현 잔존 검사
- **Skill**: content-guide — brand-voice.md 스키마, 유형별 템플릿(references/)

## Examples

### 블로그 초안 (첫 실행 — 인터뷰 포함)
```
/content-draft --type blog 개발팀을 위한 검색 인프라 자동화 도구 출시 소식
```

### 플랫폼 지정 SNS 포스트
```
/content-draft --type sns --platform linkedin 시드 투자 유치 발표
```

### 브랜드 보이스 갱신 후 보도자료
```
/content-draft --type pr --revoice 시리즈 A 투자 유치 보도자료
```

## Boundaries

**Will:**
- brand-voice.md 물화(5문항 인터뷰) 및 모든 초안의 파일 기준 참조
- blog/sns/pr/email 유형별 템플릿 기반 초안 생성
- 금지 표현·표시광고법 리스크 표현 감지 및 legal 연계 1줄 안내
- 근거 없는 주장을 `[근거 필요]`로 투명하게 표기

**Will Not:**
- 표시광고법·전자상거래법 적합성 확정 판정 (→ legal `/compliance-check`)
- 실제 발행·게시·광고 집행 대행
- 근거 자산에 없는 수치·고객 사례 창작
- brand-voice.md를 무시한 임의 톤 적용 (톤 변경 요청은 파일 갱신을 먼저 제안)
