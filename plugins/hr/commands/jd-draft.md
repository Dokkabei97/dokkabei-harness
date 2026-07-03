---
name: jd-draft
description: "직무기술서(JD) 초안 작성. 역할·책임·요건을 구조화하고 차별 표현 검사를 수행한다."
category: hr
complexity: basic
mcp-servers: []
personas: [recruiting-advisor]
---

# /jd-draft - 직무기술서 초안 작성

## Triggers
- 신규/결원 포지션의 채용 공고를 작성할 때
- 기존 JD를 구조화·현대화하거나 차별 표현을 점검할 때
- "JD 써줘", "채용 공고 초안", "직무기술서 만들어줘"

## Usage
```
/jd-draft [직무명 또는 직무 설명]

Options:
  --level junior|mid|senior|lead   대상 연차 레벨 (기본: 대화로 확인)
  --check-only                     기존 JD의 차별 표현 검사만 수행
  --benchmark                      동일 직군 시장 JD 벤치마크 포함
  --output <경로>                  저장 경로 override (기본: .planning/hr/jd/{직무명}.md)
```

## Behavioral Flow

### Phase 1: 직무 파악
- 직무명, 채용 배경(결원/신설), 6~12개월 후 기대 성과를 확인
- 기존 JD·조직 문서가 있으면 읽어서 맥락 반영
- 부족한 정보는 질문 (최대 3개) — 필수/우대 요건 경계를 반드시 확정

### Phase 2: 초안 작성 (recruiting-advisor 위임)
- recruiting-advisor 에이전트에 직무 사실관계를 전달하여 초안 생성
- 구조: 제목 → 팀/미션 → 핵심 책임(5±2) → 필수 요건 → 우대 요건 → 채용 절차 → 성장 제안
- `--benchmark` 시 동일 직군 시장 JD를 웹 조사하여 요건 수준 보정

### Phase 3: 차별 표현 검사
- 연령(나이 제한·"젊은 조직에 어울리는"), 성별(성별 지정 표현), 용모·신체조건, 출신지·특정 학교 우대, 혼인·임신 관련 표현을 휴리스틱으로 플래그
- 플래그 항목마다 중립 대체 표현을 제안하고 초안에 반영
- **적법성 확정 판단은 하지 않음** — 판단이 필요한 항목은 ⚠ 표시 후 `legal:labor-ip-counsel` 위임을 안내 (hiring-guide의 에스컬레이션 규약)

### Phase 4: 저장 및 후속 안내
- 최종 초안을 `.planning/hr/jd/{직무명}.md`에 저장 (`--check-only`면 검사 보고만 출력)
- 남은 ⚠ 항목과 다음 단계(`/interview-kit`으로 면접 설계 연계)를 안내

## Tool Coordination
- **Task(recruiting-advisor)**: JD 구조 설계·차별 표현 스크리닝 (read-only 자문)
- **WebSearch**: 시장 JD 벤치마크, 직군별 요건 수준 조사 (--benchmark)
- **Read**: 기존 JD·조직 문서 수집 (--check-only 대상 포함)
- **Write**: 최종 초안을 `.planning/hr/jd/`에 저장 (메인 세션에서 수행 — 에이전트는 쓰기 도구 없음)

## Examples

### 기본 사용
```
/jd-draft 백엔드 개발자 (Kotlin/Spring, 검색 플랫폼팀)
```

### 기존 JD 차별 표현 검사만
```
/jd-draft --check-only docs/jd/marketing-manager.md
```

### 시장 벤치마크 포함 시니어 포지션
```
/jd-draft --level senior --benchmark 프로덕트 디자이너
```

## Boundaries

**Will:**
- 구조화된 JD 초안 작성 및 필수/우대 요건 분리
- 차별 표현 휴리스틱 검사와 중립 대체 표현 반영
- 시장 벤치마크 기반 요건 수준 보정
- `.planning/hr/jd/`에 저장하여 면접 킷 설계로 연계

**Will Not:**
- 채용 공고·전형 기준의 노동법 적법성 확정 판단 — 법률 쟁점은 legal:labor-ip-counsel에 위임
- 처우(연봉·계약 형태) 조건의 법적 유효성 판단
- 채용 플랫폼 게시 대행
