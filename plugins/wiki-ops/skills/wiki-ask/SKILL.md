---
name: wiki-ask
description: |
  컴파일된 llm-wiki vault에서 인용 기반으로 답한다 — 단일 질문은 query, 재사용 가치가 있으면 --persist(synthesis 복리), 다면 질문은 --research(하위질문 분해·교차 종합)로 라우팅. citations가 비면 지어내지 않고 "근거 없음 + feed 제안"을 정직 보고(히트 0도 exit 0인 함정 대응). Use when: "위키에서 답해줘", "vault 근거로 조사해줘", 축적된 지식 재사용 시. 웹 심층 리서치 리포트는 deep-research 소관.
  Ask the compiled llm-wiki vault with verbatim-quote citations: routes to query / --persist (compounding syntheses) / research (multi-faceted). Reports "no grounding" honestly when citations are empty. Use when: answering from the vault or running vault-grounded research.
---

# /wiki-ask — 인용 질의응답

얇은 진입점이다 — 라우팅과 검증 규율은 `wiki-ops-orchestrator` Stage 4와
`wiki-librarian` 에이전트가 정의한다.

## When to Apply

- vault에 축적된 지식으로 질문에 답할 때 ("위키에 뭐라고 돼 있어?")
- 팀이 반복해서 물을 질문을 synthesis로 물화할 때 (reuse_count 복리)
- 여러 소스를 교차 종합하는 vault 근거 리서치가 필요할 때

## Usage

```
/wiki-ask "<질문>" [--vault <dir>] [--persist] [--research] [--hybrid]
```

| 인자 | 의미 |
|------|------|
| `--persist` | 답변을 wiki/syntheses/에 물화 (distinct source ≥2일 때만 — 미달 시 명시 보고) |
| `--research` | 하위질문 분해·다중 회수·교차 종합 (research 명령) |
| `--hybrid` | FTS+벡터 RRF 융합 (임베딩 모델 가용 시에만) |

## Flow

1. 경량 단일 질문 → 메인 세션이 직접 `query --json` / 다면·리서치 → wiki-librarian 디스패치
2. `citations[]` 검증 — 0건이면 "근거 없음 + 유사 페이지 + feed 제안" 정직 보고
3. 주장마다 인용 경로(`wiki/sources/<id>.md#claim-NNN`) 병기해 답변

## Boundaries

Will: 인용 병기 답변, synthesis 축적 보고, 근거 부재의 정직 보고
Will Not: 인용 없는 답변 생성, raw/ 열람으로 답변 보강, 웹 리서치 리포트(→ deep-research),
`--allow-network` 임의 사용 (사용자 명시 요청 시에만)
