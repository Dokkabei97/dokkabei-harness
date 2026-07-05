---
name: pitch-deck
description: |
  피치덱 구조 설계. 투자자 관점에서 스토리라인을 구성하고 슬라이드별 핵심 메시지를 정의한다.
  Designs a pitch deck structure from an investor's perspective, building the storyline and defining the core message of each slide. Use when: creating a pitch deck outline, preparing an IR presentation, structuring an investor story, or defining slide-by-slide key messages.
category: fundraising
complexity: advanced
---

# /pitch-deck - 피치덱 설계

## Triggers
- 투자 유치를 위한 IR 자료가 필요할 때
- 피치 발표 구조를 잡고 싶을 때
- "피치덱 만들어줘", "IR 자료 구조 잡아줘", "투자자 발표자료"

## Usage
```
/pitch-deck [회사/제품 설명]

Options:
  --stage pre-seed|seed|series-a     투자 라운드 (기본: seed)
  --format sequoia|yc|custom         피치덱 형식 (기본: sequoia)
  --slides [슬라이드수]               슬라이드 수 (기본: 12)
  --focus story|data|product         강조 방향
  --export md|pptx                   내보내기 파일 형식 (기본: md)

※ --format은 덱 구성 형식(스토리 골격), --export는 산출 파일 형식 — 서로 다른 옵션
```

## Behavioral Flow

### Phase 1: 정보 수집
- 회사/제품 핵심 정보를 파악
- 기존 린 캔버스, 시장조사, 재무 모델 파일이 있으면 참조
- 부족한 정보 확인 (최대 5개 질문)

### Phase 2: 스토리라인 설계
- 투자자의 사고 흐름에 맞춘 내러티브 구성:
  1. **Hook** — 왜 지금 이 이야기를 들어야 하는가?
  2. **Problem** — 세상에 어떤 문제가 있는가?
  3. **Insight** — 왜 기존 방식으로는 안 되는가?
  4. **Solution** — 어떻게 해결하는가?
  5. **Proof** — 실제로 작동하는가?
  6. **Scale** — 얼마나 큰 기회인가?
  7. **Ask** — 무엇이 필요하고, 무엇을 돌려줄 수 있는가?

### Phase 3: 슬라이드별 구성 (Sequoia Format)
| 순서 | 슬라이드 | 핵심 질문 | 시간 |
|------|---------|----------|------|
| 1 | Title | 한 문장으로 무엇인가? | 15초 |
| 2 | Problem | 어떤 문제를 해결하는가? | 1분 |
| 3 | Solution | 어떻게 해결하는가? | 1분 |
| 4 | Why Now | 왜 지금인가? | 30초 |
| 5 | Market | 시장은 얼마나 큰가? | 1분 |
| 6 | Product | 제품은 어떻게 작동하는가? | 1.5분 |
| 7 | Traction | 현재까지의 성과는? | 1분 |
| 8 | Business Model | 어떻게 돈을 버는가? | 1분 |
| 9 | Competition | 경쟁 우위는 무엇인가? | 30초 |
| 10 | Team | 왜 이 팀인가? | 1분 |
| 11 | Financials | 재무 전망은? | 1분 |
| 12 | Ask | 얼마가 필요하고 어떻게 쓸 것인가? | 30초 |

### Phase 4: 슬라이드별 콘텐츠 작성
- 각 슬라이드의:
  - **핵심 메시지** (1문장)
  - **Supporting Data** (수치/차트 제안)
  - **스피커 노트** (발표 시 말할 내용)
  - **시각 요소 제안** (차트 유형, 이미지 방향)

### Phase 5: 라운드별 강조점 조정
- **Pre-Seed**: 팀 + 문제 + 비전 (트랙션 없어도 됨)
- **Seed**: 문제 + MVP + 초기 트랙션 (PMF 신호)
- **Series A**: 트랙션 + 유닛이코노믹스 + 스케일 계획

### Phase 6: 피치 연습 가이드
- Q&A 예상 질문 10개 + 모범 답변
- 피치 타이밍 가이드 (10분 / 15분 / 20분)
- 흔한 실수와 회피 전략

### Phase 7: 내보내기(선택)
- `--export pptx` 시 공식 `pptx` 스킬(document-skills)에 위임 — 슬라이드 구조+스피커 노트를 pptx로 변환
- 공식 문서 스킬 미설치 시 md 산출로 폴백하고 설치 안내 1줄 출력: `/plugin marketplace add anthropics/skills` 후 `/plugin install document-skills@anthropic-agent-skills`

## Tool Coordination
- **WebSearch**: 투자 트렌드, 유사 기업 밸류에이션, 벤치마크 조사
- **Read**: 기존 린 캔버스/시장조사/재무 모델 파일 참조
- **Write**: 피치덱 구조 마크다운 파일 생성
- **WebFetch**: 경쟁사/시장 데이터 수집
- **Skill**: 공식 `pptx` 스킬(document-skills) — 구조+스피커 노트→pptx 변환 위임(설치 시)

## Examples

### 기본 피치덱
```
/pitch-deck AI 기반 법률 문서 자동 검토 SaaS
```

### Pre-Seed 라운드
```
/pitch-deck --stage pre-seed --focus story 시니어 디지털 헬스케어 플랫폼
```

### YC 형식
```
/pitch-deck --format yc --slides 10 개발자 도구 스타트업
```

### pptx 내보내기
```
/pitch-deck --export pptx --stage seed 물류 최적화 B2B SaaS
```

## Boundaries

**Will:**
- 슬라이드별 구조와 핵심 메시지 설계
- 스피커 노트 작성
- Q&A 예상 질문 및 답변 준비
- 라운드별 강조점 조정
- pptx 내보내기(공식 pptx 스킬 설치 시)

**Will Not:**
- Keynote/Figma 파일 생성 — pptx 내보내기는 공식 pptx 스킬 설치 시 지원, 비주얼 디자인(레이아웃·그래픽 작업) 자체는 여전히 범위 밖
- 비주얼 디자인 (구조와 콘텐츠만)
- 법률적 투자 조건 자문
- 특정 투자자 추천
