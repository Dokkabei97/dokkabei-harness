# SLO · 에러버짓 템플릿

Google SRE Workbook 3종(SLI/SLO/에러버짓) 형식. `/gov-slo` 산출물. **SLI 실측 수집기는 자체 구현하지 않는다** — observe 플러그인·infra/otel 스택 연계 또는 수동 폴백으로 `budget.json`을 채운다.

## 1. SLO 문서 — `.planning/gov/slo/slo.md`

```markdown
# SLO: <서비스명>

## SLI 정의
- 가용성: 성공 요청 / 전체 요청 (5xx·타임아웃 제외)
- 지연: p99 latency < <N>ms 인 요청 비율

## SLO 목표 (측정 창)
| SLI | 목표 | 창 |
|-----|------|-----|
| 가용성 | 99.9% | 28일 롤링 |
| 지연 p99 | 99.0% < 300ms | 28일 롤링 |

## 에러버짓 정책
- 월간 에러버짓 = (1 - SLO) × 총 요청. 예: 99.9% → 0.1%.
- 소진 시 정책: 신규 기능 릴리즈 **동결**, 안정화 작업 우선(gate-error-budget가 릴리즈 계열 차단).
- 잔량 임계: `error_budget_min_pct` 미만이면 게이트 red.
```

## 2. 임계값 — `.planning/gov/slo/thresholds.yaml`  (게이트 입력, **플랫 형식 필수**)

```yaml
# gate-error-budget.sh가 grep/sed로 파싱 — 중첩 금지, yq 미사용
error_budget_min_pct: 20
availability_slo_pct: 99.9
latency_p99_ms: 300
```

> `error_budget_min_pct`: 에러버짓 잔량이 이 % 미만이면 릴리즈 차단. "20"이면 버짓의 20%까지 소진 허용.

## 3. 잔량 — `.planning/gov/slo/budget.json`  (observe/infra-otel 또는 수동)

```json
{"error_budget_remaining_pct": 62.5, "window": "28d", "measured_at": "YYYY-MM-DD", "source": "otel|manual"}
```

- **observe 연계**: `.claude/skill-trace.jsonl` 또는 Grafana/OTel 쿼리 결과로 잔량을 계산해 이 파일에 기록.
- **수동 폴백**: 인시던트 다운타임을 SLO 대비 수기 계산해 기입(source: manual 명시).
- 파일 부재 = 미측정 → 게이트 exit 2(소진과 구분).

## 4. 판정 3분기 (gate-error-budget)

| 조건 | exit | 의미 |
|------|------|------|
| remaining ≥ min | 0 | 통과 |
| remaining < min | 1 | 소진 — 릴리즈 차단 |
| budget.json 부재 | 2 | 미측정 — 측정 먼저 |
