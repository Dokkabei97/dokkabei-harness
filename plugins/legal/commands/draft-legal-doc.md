---
name: draft-legal-doc
description: "법률 문서 초안 작성. 계약서·내용증명·합의서·통지서 등을 한국법 기준 표준 구조로 초안화하고 핵심 조항의 선택지를 제시한다."
category: legal
complexity: standard
---

# /draft-legal-doc - 법률 문서 초안

## Triggers
- 계약서·내용증명·합의서·통지서 등의 초안이 필요할 때
- 표준 구조 기반으로 빠르게 1차 문서를 만들고 싶을 때
- "계약서 초안", "내용증명 써줘", "합의서 만들어줘"

## Usage
```
/draft-legal-doc [문서 유형 + 핵심 내용]

Options:
  --type contract|demand-letter|settlement|notice|nda  문서 유형
  --role 갑|을|발신|수신  작성자 입장
  --format md|txt|docx  출력 형식(기본: md)
```

## Behavioral Flow

### Phase 1: 문서 요건 수집
- 문서 유형·당사자·핵심 거래/요구 사항 확정
- 필수 기재사항 체크리스트 도출(유형별 상이)
- 작성자 입장에 유리한 방향 확인

### Phase 2: 표준 구조 초안
- 유형별 표준 골격으로 초안 작성
  - 계약서: 목적·정의·권리의무·대금·기간·해지·분쟁해결
  - 내용증명: 발신/수신·사실관계·요구사항·기한·법적 조치 예고
  - 합의서: 합의 내용·이행 조건·부제소특약·비밀유지
- 관련 전문 에이전트(contract-counsel 등) 위임 가능

### Phase 3: 핵심 조항 선택지
- 협상 여지가 있는 조항은 보수적/중립/공격적 버전 제시
- 작성자 입장에 따른 권장안 표시

### Phase 4: 주의사항·면책
- 공증·내용증명 발송·등기 등 절차 안내
- 변호사 검토 권장 지점 명시

### Phase 5: 오피스 내보내기(선택)
- `--format docx` 시 공식 `docx` 스킬(document-skills)에 위임해 md 초안을 docx로 변환
- 전제조건: 공식 문서 스킬 설치 + python3 — 미충족 시 md 산출로 폴백(graceful degrade)
- 폴백 시 설치 안내 1줄 출력: `/plugin marketplace add anthropics/skills` 후 `/plugin install document-skills@anthropic-agent-skills`

## Tool Coordination
- **Agent**: contract-counsel/dispute-risk-counsel 위임(유형별)
- **Read**: 기존 계약/사실관계 자료 참조
- **WebSearch**: 표준계약서 양식·법정 요건 확인
- **Write**: 초안 문서 파일 생성
- **Skill**: 공식 `docx` 스킬(document-skills) — md 초안→docx 변환 위임(설치 시)

## Examples

### 용역계약서 초안(을 입장)
```
/draft-legal-doc --type contract --role 을 프리랜서 개발 용역계약
```

### 내용증명(미지급 대금 청구)
```
/draft-legal-doc --type demand-letter --role 발신 미지급 용역대금 500만원 청구
```

### NDA 초안(docx 내보내기)
```
/draft-legal-doc --type nda --role 갑 --format docx 외주 개발사와의 비밀유지계약
```

## Boundaries

**Will:**
- 표준 구조 기반 초안 작성
- 핵심 조항 선택지 및 권장안 제시
- 절차 안내
- docx 내보내기(공식 문서 스킬 설치 시)

**Will Not:**
- 공증·내용증명 발송·등기 실무 대행
- 분쟁 중 문서의 법적 효력 보증
- **중요 문서는 변호사 검토 권고 — 자문을 대체하지 않음**
