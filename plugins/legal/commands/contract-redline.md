---
name: contract-redline
description: "계약 왕복 협상(레드라인) 분석. 상대방 수정안과 원안을 조항 단위로 diff 정렬하고, 변경별 수용/수정/거부 권고와 3버전 대안 문구, 협상 우선순위를 제시한다."
category: legal
complexity: standard
mcp-servers: []
personas: [contract-counsel]
---

# /contract-redline - 계약 레드라인(왕복 협상) 분석

## Triggers
- 상대방이 수정해서 돌려보낸 계약서(카운터 초안)를 원안과 비교하고 싶을 때
- 변경된 조항별로 수용/수정/거부를 판단하고 회신용 대안 문구가 필요할 때
- 여러 회차 협상에서 어떤 조항을 관철하고 어떤 조항을 양보할지 정리하고 싶을 때
- "상대방 수정안 비교해줘", "레드라인 분석", "바뀐 조항 뭐가 불리해?"

## Usage
```
/contract-redline [원안 파일] [상대방 수정안 파일]
/contract-redline [변경 추적 docx 파일]   # 공식 docx 스킬 설치 시

Options:
  --role 갑|을    의뢰인 입장(기본: 을)
  --round N       협상 회차(맥락 기록용, 선택)
```

## Behavioral Flow

### Phase 1: 입력 정규화
- 입력 형태 판별: 파일 2개(원안 + 상대방 수정안) 또는 변경 추적 docx 1개
- 변경 추적 docx는 공식 `docx` 스킬(document-skills) 설치 시 삽입/삭제/코멘트를 추출해 읽음
- 미설치 시 md/텍스트 2개 파일 입력으로 폴백하고 설치 안내 1줄 출력:
  `/plugin marketplace add anthropics/skills` 후 `/plugin install document-skills@anthropic-agent-skills`
- `--role`로 의뢰인 입장(갑/을)을 확정하고 계약 유형·협상 맥락 파악

### Phase 2: 조항 단위 diff 정렬
- 조항 번호·제목 기준으로 원안과 수정안을 정렬(조항 신설·삭제·재배치 추적)
- 변경 유형 분류: 신설 / 삭제 / 문구 수정 / 수치 변경(금액·기간·비율·한도)
- 실질 변경이 없는 표현 정리(cosmetic)는 별도 표기해 분석 노이즈 제거

### Phase 3: 변경별 유불리 분석
- `contract-counsel` 에이전트에 위임 — 신규 에이전트 없이 기존 전문가 활용
- 변경 조항마다 분석 표 작성: 의뢰인 유불리 방향 + 리스크 등급(High/Medium/Low) + **수용/수정/거부** 권고
- 수정 권고 조항은 **보수적/중립/공격적 3버전 대안 문구** 제시(draft-legal-doc 관례 재사용)하고 협상력에 따른 권장안 표시

### Phase 4: Escalation Policy 트리거 검사
- `legal-team-orchestrator`의 Escalation Policy **8트리거를 그대로** 검사
  (특히 #4 비가역·고액 거래 1억원 이상, #6 중액·장기 구속 1천만원~1억원 또는 1년 초과 구속)
- 강제 트리거 해당 시 보고서 **최상단**에 `⚠️ 반드시 변호사 상담`과 사유 표시
- 강제·권고가 동시 해당하면 강제 우선, 모호하면 상향(보수적) 적용

### Phase 5: 협상 우선순위 요약
- 반드시 관철 / 협상 카드 / 양보 가능 3분류로 회신 전략 정리
- 상대방 변경 의도 추정(리스크 전가·책임 축소·해지권 확대 패턴)과 다음 회차 예상 쟁점 표시
- 변호사 검토가 권장되는 지점 명시

## Tool Coordination
- **Read**: 원안·상대방 수정안 파일 로드(md/텍스트)
- **Skill**: 공식 `docx` 스킬(document-skills) — 변경 추적 docx 읽기 위임(설치 시)
- **Agent**: contract-counsel 위임 — 변경별 유불리 분석·대안 문구 작성
- **WebSearch**: 약관규제법·위약금 감액(민법 §398) 등 쟁점 판례 확인
- **Write**: 레드라인 분석 보고서 및 회신용 문구 생성

## Examples

### 기본 왕복 비교(을 입장)
```
/contract-redline ./contracts/용역계약_원안.md ./contracts/용역계약_상대방수정안.md
```

### 변경 추적 docx 분석(갑 입장, 2회차)
```
/contract-redline --role 갑 --round 2 ./contracts/공급계약_v2_redline.docx
```

## Boundaries

**Will:**
- 조항 단위 diff 정렬 및 변경별 수용/수정/거부 권고
- 보수적/중립/공격적 3버전 대안 문구 제시
- Escalation Policy 8트리거 검사 및 협상 우선순위 요약

**Will Not:**
- 체결 가부·수정안 수락 여부의 확정적 판단 (변호사 영역)
- 고액·비가역 거래에서 변호사 검토 권고 생략
- **변호사 자문을 대체하지 않음** — 서명 전 중대 계약은 반드시 변호사 검토
