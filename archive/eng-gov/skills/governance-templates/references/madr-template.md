# MADR ADR 템플릿

Markdown Any Decision Record. **파일명**: `docs/decisions/NNNN-<kebab-slug>.md` (NNNN = 4자리 0패딩, 예 `0007-adopt-hexagonal-architecture.md`). `gate-adr.sh`가 파일명·status·supersede 링크를 결정론 검사한다.

---

```markdown
# NNNN. <결정 제목>

status: accepted
date: YYYY-MM-DD
deciders: <이름/역할>
superseded-by:            # status가 superseded일 때만 NNNN 기입 (실재 ADR)

## Context and Problem Statement

<어떤 힘/제약 아래 무엇을 결정해야 하는가. 1~2문단.>

## Decision Drivers

- <드라이버 1 — 예: 팀 역량, 운영 비용, 규제>
- <드라이버 2>

## Considered Options

- <옵션 A>
- <옵션 B>
- <옵션 C>

## Decision Outcome

선택: **<옵션 A>**. 근거: <왜 이 옵션이 드라이버를 가장 잘 만족하나>.

### Consequences

- 좋음: <긍정 결과>
- 나쁨: <감수하는 트레이드오프>

## Fitness Function 변환 후보  (fitness-function-guide 연계)

이 결정을 **강제 가능한 규칙**으로 변환:
- 예: "domain은 infra를 import하지 않는다" → `.dependency-cruiser.js` forbidden 룰 / `.importlinter` contract
- 변환 불가(사회적 규약뿐)면 그 사실을 명시 → adr-checker가 "선언뿐"으로 FIX 권고
```

---

## status 값 (gate-adr enum — 정확히 이 4개)

| status | 의미 |
|--------|------|
| `proposed` | 제안됨(아직 미승인) |
| `accepted` | 승인·유효 |
| `superseded` | 후속 결정으로 대체됨 → `superseded-by: NNNN` 필수 |
| `deprecated` | 폐기(대체 없이 더 이상 유효하지 않음) |

## supersede 규약

결정을 바꿀 때 **기존 ADR을 편집하지 않는다**. 새 ADR을 만들고, 옛 ADR의 status를 `superseded`로 바꾸고 `superseded-by: <새 번호>`를 기입한다. 새 ADR의 Context에 "supersedes NNNN"을 적는다. 이렇게 결정 이력이 append-only로 보존된다.
