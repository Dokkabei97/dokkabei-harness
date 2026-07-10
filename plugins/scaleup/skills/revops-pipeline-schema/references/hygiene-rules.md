# Pipeline Hygiene Rules — 파이프라인 위생 룰셋

gate-pipeline-hygiene.sh 가 결정론 판정하는 위생 룰의 서술적 정본. enum 은 [pipeline-enums.json](pipeline-enums.json).

## 룰

| # | 룰 | 판정 | 근거 |
|---|-----|------|------|
| 1 | stage ∈ enum | 위반 딜 id 나열 후 실패 | 비표준 단계 = CRM 오염 |
| 2 | forecast_category ∈ enum | 위반 딜 id 나열 후 실패 | 롤업 신뢰성 |
| 3 | amount_krw > 0 (number) | 위반 딜 id 나열 후 실패 | 0원/누락 딜은 포캐스트 왜곡 |
| 4 | open 딜 close_date ≥ TODAY | 위반 딜 id 나열 후 실패 | 마감일 지난 미종결 딜 = slippage 은폐 |
| 5 | open 딜 last_activity 경과 ≤ stale_max_days | 초과 딜 id·경과일 나열 후 실패 | 방치 딜 = 파이프라인 인플레이션 |

- **open 딜 정의**: forecast_category ∉ {closed_won, closed_lost}.
- **stale_max_days**: audit.json 의 값(기본 30). `/pipeline-audit --stale-days N` 로 조정.
- **날짜 산술**: TODAY = `${GATE_TODAY:-$(date +%F)}`. close_date 는 사전식 비교, last_activity 경과는 BSD/GNU date 이중 관용구 epoch 차/86400.

## 왜 이 게이트가 "대표 쇼케이스"인가

파이프라인 위생은 전 하네스에서 **가장 결정론적인** 영역이다 — enum·산술·날짜로 100% 판정 가능하며 의미 판단(checker) 잔여분이 거의 없다. 포캐스트 롤업의 신뢰성이 이 위생에 직결되므로, RevOps 규율의 기준선으로 삼는다.

## 포캐스트 롤업 (참고)

commit(고확신) → best_case(상방) → pipeline(초기) → omitted(제외). 롤업 시 카테고리별 가중은 회사 정책이며 게이트 대상 아님(위생만 검사).
