---
name: interview-kit
description: |
  역량 기반 면접 킷 생성. 역량 모델, 행동 질문(STAR), 4단계 앵커 평가 루브릭을 설계한다.
  Generates a competency-based interview kit: derives a competency model, writes behavioral (STAR) questions, and designs a 4-level anchored evaluation rubric. Use when: creating interview questions for a position, standardizing interviewer scoring with a rubric, building an interview scorecard, or designing a structured interview process.
category: hr
complexity: intermediate
mcp-servers: []
personas: [recruiting-advisor]
---

# /interview-kit - 역량 기반 면접 킷 생성

## Triggers
- 특정 포지션의 면접 질문과 평가 기준을 설계할 때
- 면접관마다 다른 "감 평가"를 표준화된 루브릭으로 바꿀 때
- "면접 질문 만들어줘", "면접 평가표", "인터뷰 킷"

## Usage
```
/interview-kit [직무명 또는 JD 파일 경로]

Options:
  --stages <n>            면접 단계 수 (기본: 2 — 직무 면접 + 컬처/협업 면접)
  --competencies <목록>   역량 모델 직접 지정 (기본: JD에서 도출)
  --with-assignment       실무 과제 설계 포함
  --output <경로>         저장 경로 override (기본: .planning/hr/interview/{직무명}.md)
```

## Behavioral Flow

### Phase 1: 역량 모델 도출
- `.planning/hr/jd/`의 JD가 있으면 자동 탐지하여 인테이크 (`/jd-draft` 산출물 승계)
- JD가 없으면 직무 설명에서 핵심 역량 4~6개를 도출하고 사용자와 확정
- 각 역량에 "왜 이 직무에 필수인지" 근거를 1줄로 부여 — 근거 없는 역량은 제외

### Phase 2: 질문 설계 (recruiting-advisor 위임)
- 역량별 행동 질문(STAR 유도형) 2개 + 후속 심화 질문(deep-dive) 설계
- 상황 질문·실무 과제(`--with-assignment`)를 역량과 1:1 매핑
- 단계별 측정 역량을 분담하여 단계 간 중복 질문 제거
- **금지 질문 목록 동봉**: 혼인·임신·출산 계획, 가족 배경, 나이, 출신지 등 — 직무 무관 개인사 질문은 차별 리스크로 플래그

### Phase 3: 평가 루브릭 설계
- 역량 × 4단계 앵커 루브릭 작성 — 각 단계는 관찰 가능한 행동·답변 특징으로 기술
- 종합 판정 규칙(예: 필수 역량 2점 미만 시 불합격)과 면접관 캘리브레이션 방법 제안
- 점수 근거를 답변 인용으로 남기는 기록 양식 포함

### Phase 4: 저장 및 후속 안내
- 면접 킷(질문지 + 루브릭 + 면접관 가이드)을 `.planning/hr/interview/{직무명}.md`에 저장
- ⚠ 법률 판단 필요 항목(예: 전형 단계에서의 조건부 오퍼 문구)이 있으면 `legal:labor-ip-counsel` 위임 안내

## Tool Coordination
- **Task(recruiting-advisor)**: 역량 모델·질문·루브릭 설계 (read-only 자문)
- **Read**: `.planning/hr/jd/` 산출물 또는 지정 JD 파일 인테이크
- **WebSearch**: 직군별 검증된 면접 질문 패턴·과제 사례 조사
- **Write**: 면접 킷을 `.planning/hr/interview/`에 저장 (메인 세션에서 수행)

## Examples

### JD 산출물 승계
```
/interview-kit .planning/hr/jd/backend-engineer.md
```

### 3단계 전형 + 실무 과제 포함
```
/interview-kit --stages 3 --with-assignment 데이터 분석가
```

### 역량 모델 직접 지정
```
/interview-kit --competencies "문제 정의, 실행력, 협업, 학습 민첩성" 프로덕트 매니저
```

## Boundaries

**Will:**
- 역량 모델 기반 질문지·4단계 앵커 루브릭·면접관 가이드 생성
- 금지 질문 목록 동봉 및 차별 리스크 질문 플래그
- JD 산출물(`/jd-draft`) 자동 승계

**Will Not:**
- 면접 질문·전형 기준의 노동법 적법성 확정 판단 — 법률 쟁점은 legal:labor-ip-counsel에 위임
- 실제 면접 진행·후보자 평가 대행
- 채용/탈락 결정
