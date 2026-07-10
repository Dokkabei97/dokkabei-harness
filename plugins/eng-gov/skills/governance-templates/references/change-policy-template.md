# 변경 증적 정책 · evidence.json 스키마

DORA "변경 승인 간소화"(무거운 CAB 대신 위험 비례 통제) + SOC2 CC8.1 / ISMS-P 2.9.1 증적. `/gov-change`가 `change-risk-classifier`로 등급을 매기고 이 스키마로 `evidence.json`을 물화하면 `gate-change-evidence.sh`가 결정론 판정한다.

## evidence.json — `.planning/gov/change/<sha>/evidence.json`

```json
{
  "sha": "<git rev-parse HEAD 결과>",
  "branch": "feature/x",
  "created_at": 1731200000,
  "author": "alice",
  "approver": "bob",
  "risk_tier": "standard | normal | high",
  "risk_reasons": ["auth 코드 터치", "legal 확인 필요"],
  "diff_stat": {"files": 4, "insertions": 120, "deletions": 8},
  "gates": [
    {"gate": "gate-adr", "exit": 0, "ran_at": 1731200010},
    {"gate": "gate-secrets", "exit": 0, "ran_at": 1731200020}
  ],
  "loop_artifacts": {"engine": "feature-loop", "tasks_passed": 5, "baseline_regressions": 0}
}
```

## 게이트 계약 (gate-change-evidence.sh가 강제)

1. `sha == git HEAD` — 다른 커밋의 증적 재사용 차단.
2. `author != approver` (둘 다 비공백) — 자기 승인 금지(4-eyes).
3. `risk_tier ∈ {standard, normal, high}`.
4. `gates[]` 전 항목 `exit == 0` (기록된 게이트 전부 그린).
5. `risk_tier == high` → `gates[]`에 `gate-secrets`·`gate-supply-chain` 기록 필수.

## risk_tier 분류표 (change-risk-classifier 규칙)

| tier | 조건 | 필수 게이트 |
|------|------|-------------|
| standard | 문서·테스트·주석만 | gate-adr(변경 시) |
| normal | 일반 애플리케이션 코드 | 등록된 코어 게이트 |
| high | 개인정보·인증·인가·결제·인프라 터치 OR 500+ 라인 | + gate-secrets, gate-supply-chain (evidence 기록 필수) |

- **개인정보 터치 = 무조건 high**. 애매하면 상향(보수적).
- **법적 판단은 legal 위임** — risk_reasons에 "legal 확인 필요" 플래그만 남기고 판정하지 않는다.

## 루프 산출물 연결 ("루프 = 감사 증적")

floop/mvp 루프 완료 시점의 `/gov-change`는 `loop_artifacts`를 `.planning/tasks.json`(또는 prd.json)·`.planning/baseline.json`에서 채운다 → 자동화 루프의 결과가 그대로 변경 증적이 된다.
