---
name: onboarding-doc
description: "온보딩 문서 생성. 입사 전~첫 주 체크리스트와 30-60-90 램프업 플랜을 작성한다."
category: hr
complexity: basic
mcp-servers: []
personas: [people-ops-advisor]
---

# /onboarding-doc - 온보딩 문서 생성

## Triggers
- 신규 입사자를 위한 온보딩 체크리스트/플랜이 필요할 때
- 팀의 온보딩을 "알아서 적응"에서 구조화된 램프업으로 바꿀 때
- "온보딩 문서 만들어줘", "30-60-90 플랜", "입사자 체크리스트"

## Usage
```
/onboarding-doc [직무명 또는 입사자 정보]

Options:
  --format checklist|30-60-90|full   문서 형식 (기본: full — 체크리스트+플랜)
  --team <팀명>                      팀 맥락(온콜·회의체·도구) 반영
  --buddy                            버디/멘토 운영 구조 포함
  --output <경로>                    저장 경로 override (기본: .planning/hr/onboarding/{직무명}.md)
```

## Behavioral Flow

### Phase 1: 맥락 파악
- 직무, 팀, 근무 형태(상주/원격/하이브리드), 조직 규모를 확인
- 기존 온보딩 자료·팀 핸드북·CLAUDE.md 등 조직 문서가 있으면 읽어서 반영
- 부족한 정보는 질문 (최대 3개) — 30/60/90일 시점의 기대 수준을 반드시 확정

### Phase 2: 체크리스트 작성 (people-ops-advisor 위임)
- **입사 전(D-7)**: 계정·장비·좌석, 첫 주 일정 예약, 팀 공지
- **첫날**: 오리엔테이션, 필수 계정 확인, 버디 소개(`--buddy`)
- **첫 주**: 도구·코드베이스/업무 도메인 투어, 1:1 일정, 첫 소과제 배정
- 각 항목에 담당자(입사자/매니저/피플팀)를 지정

### Phase 3: 30-60-90 플랜 작성
- **30일(학습)**: 도메인·시스템 이해, 첫 기여 완료 — 측정 가능한 완료 기준 부여
- **60일(기여)**: 독립적 과제 수행, 팀 프로세스 내 역할 확립
- **90일(자립)**: 자기 영역 오너십, 개선 제안 1건 이상
- 각 마일스톤에 매니저 체크인(1:1) 어젠다 포함

### Phase 4: 법령 접점 플래그 및 저장
- 문서에 수습 기간·평가 연계 조치, 연차 부여, 근로시간 안내가 포함되면 ⚠ 표시하고 **확정 서술 대신** `legal:labor-ip-counsel` 위임을 안내 (hiring-guide의 에스컬레이션 규약)
- 최종 문서를 `.planning/hr/onboarding/{직무명}.md`에 저장하고 갱신 주기·소유자를 명시

## Tool Coordination
- **Task(people-ops-advisor)**: 체크리스트·30-60-90 플랜 설계 (read-only 자문)
- **Read**: 기존 온보딩 자료·팀 핸드북·조직 문서 인테이크
- **WebSearch**: 직군별 온보딩 사례·램프업 기준 벤치마크
- **Write**: 온보딩 문서를 `.planning/hr/onboarding/`에 저장 (메인 세션에서 수행)

## Examples

### 기본 사용
```
/onboarding-doc 백엔드 개발자 (검색플랫폼팀 신규 입사)
```

### 체크리스트만 + 버디 구조
```
/onboarding-doc --format checklist --buddy 콘텐츠 마케터
```

### 팀 맥락 반영 풀 문서
```
/onboarding-doc --team 검색플랫폼팀 --format full 데이터 엔지니어
```

## Boundaries

**Will:**
- 입사 전~첫 주 체크리스트와 30-60-90 램프업 플랜 작성
- 담당자 지정·측정 가능한 완료 기준·매니저 체크인 어젠다 포함
- 수습·연차 등 법령 접점 항목 플래그

**Will Not:**
- 수습 해지·연차/수당·근로계약 조항의 노동법 확정 판단 — 법률 쟁점은 legal:labor-ip-counsel에 위임
- 근로계약서·취업규칙 자체의 작성 (legal 하네스 `/draft-legal-doc` 영역)
- 4대보험 신고 등 행정 절차 대행
