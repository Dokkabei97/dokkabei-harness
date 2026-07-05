---
name: contract-review
description: |
  계약서 독소조항 검토. 조항별 리스크 등급과 수정 문구(redline)를 제시하고 누락 조항을 식별한다.
  Reviews a contract for toxic clauses under Korean law, grading risk per clause, proposing redline wording, and identifying missing clauses. Use when: contract review, checking an NDA or service agreement for unfair terms, spotting missing protective clauses before signing.
category: legal
complexity: standard
---

# /contract-review - 계약서 검토

## Triggers
- 계약서·NDA·용역계약·투자계약 등의 리스크를 검토하고 싶을 때
- 체결 전 독소조항을 찾아내고 수정안을 받고 싶을 때
- "이 계약서 봐줘", "독소조항 있어?", "계약 검토"

## Usage
```
/contract-review [계약서 파일 경로 또는 계약 내용]

Options:
  --role 갑|을         의뢰인 입장(기본: 을)
  --type nda|service|investment|license|employment|lease  계약 유형
  --redline true|false  수정 문구 제안 포함(기본: true)
```

## Behavioral Flow

### Phase 1: 계약 파악
- 계약서를 읽고 유형·당사자·의뢰인 입장 확정
- 강행규정 적용 여부와 협상력 비대칭 식별

### Phase 2: 조항별 리스크 스캔
- `contract-counsel` 에이전트에 위임 또는 직접 분석
- 책임·배상, 해지·존속, 금전, 지재권, 비밀·경업, 분쟁해결 축으로 스캔
- 각 조항을 High/Medium/Low로 등급화

### Phase 3: 누락 조항 점검
- 유형별 필수 조항 체크리스트 대비 누락 식별
- (준거법·관할·하자담보·지체상금·불가항력 등)

### Phase 4: Redline 제안
- High 조항마다 「현재 문구 → 수정 제안 → 근거」 제시
- 협상 우선순위(관철/카드/양보) 표시

### Phase 5: 변호사 확인 표시
- 강행규정·최신 판례·고액 거래 쟁점은 변호사 검토 권고

## Tool Coordination
- **Read**: 계약서 파일 로드
- **Agent**: contract-counsel 위임(복합 계약 시)
- **WebSearch**: 약관규제법·위약금 관련 최신 판례 확인
- **Write**: 검토 보고서 및 redline 문서 생성

## Examples

### 기본 검토(을 입장)
```
/contract-review ./contracts/용역계약서.pdf
```

### 투자계약 갑 입장 검토
```
/contract-review --role 갑 --type investment ./term_sheet.md
```

## Boundaries

**Will:**
- 조항별 리스크 진단 및 수정 문구 제안
- 누락 조항 식별, 협상 우선순위 제시

**Will Not:**
- 체결 가부의 확정적 판단 (변호사 영역)
- 고액·복잡 거래에서 변호사 검토 권고 생략
- **변호사 자문을 대체하지 않음**
