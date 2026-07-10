# Enterprise 게이트 정책 · 산출물 스키마 정본

> 모든 커맨드·에이전트·게이트가 참조하는 **단일 진실 원천**. 커맨드 본문은 이 파일을 가리키고
> 판정 기준·스키마를 재기술하지 않는다(60~90행 상한 유지). 게이트는 `plugins/enterprise/hooks/gates/`.
> enum/통제 데이터의 실제 값은 각 스킬 `references/*.json`(iso27001-annex-a·risk-matrix·clap-keys)이 정본.

## 공통 계약

- 게이트: `set -euo pipefail`, `PROJ="${CLAUDE_PROJECT_DIR:-.}"`, stdin 없음, exit 0=통과/1=실패.
- jq 부재 = 사유 남기고 exit 1. 위반은 stderr `[gate-X] 실패: …` 1줄씩 누적. 경고 `[gate-X] 경고: …`는 exit 무영향.
- 날짜: `TODAY="${GATE_TODAY:-$(date +%F)}"`, 기한은 YYYY-MM-DD 사전식 비교, 일수 계산은 BSD/GNU date 이중 관용구.
- 크로스파일(control-matrix↔risk-register, budget↔변형)은 **양쪽 존재 시에만** 실패, 한쪽 부재 시 경고+skip.
- checker verdict 공통: `{"items":[{"id","verdict","reason"}],"coverage":["반증 질문 …"],"riskiest":"1줄"}` — coverage 비공백 배열 필수.

## 결선표 (커맨드 → maker → checker → 게이트)

| 커맨드 | maker | checker | 게이트 |
|--------|-------|---------|--------|
| /grc-intake | 메인 (프레임워크 선택 인터뷰) | — | — |
| /risk-register | risk-assessor | grc-challenger | gate-risk-register.sh --require-verdict |
| /control-matrix | risk-assessor | — | gate-control-matrix.sh |
| /policy-suite | 메인 | grc-challenger(정책 공백) | gate-policy-suite.sh |
| /cert-gap | 메인 (+iso27001-annex-a.json) | — | gate-cert-readiness.sh |
| /comp-calendar | 메인 | — | gate-calendar.sh |
| /strategy-cascade | strategy-analyst | plan-challenger | (게이트 없음) |
| /annual-plan | fpna-planner | plan-challenger | gate-budget.sh |
| /rolling-forecast | fpna-planner | — | gate-variance.sh |
| /biz-screen | strategy-analyst | plan-challenger | gate-screen.sh --require-verdict |

## 산출물 스키마 (게이트가 읽는 최소 필드 = 상한, optional 은 게이트 무시)

### .planning/grc/
- **risk-register.json**: `{appetite,updated,risks:[{id,title,category,likelihood:1-5,impact:1-5,score:l×i,level:5x5매핑,owner,response:{strategy,actions:[],due},next_review}]}`
- **control-matrix.json**: `{controls:[{id,risk_ids:[],name,type:"preventive|detective",line:1|2|3,owner,frequency,status,evidence_path}]}`
- **cert-gap.json**: `{framework:"ISO27001",revision:"2022",items:[{id,part:"Organizational|People|Physical|Technological",title,status:"n/a|planned|implemented|evidenced",evidence_path,owner}]}` — id 집합 == iso27001-annex-a.json(93)
- **policies/** (code-of-conduct.md + whistleblowing-policy.md 필수, 각 frontmatter owner/review_date) + **policy-index.json** `{policies:[basename…]}`
- **compliance-calendar.json**: `{duties:[{id,title,basis,due,owner,recurrence,status:"open|done|waived",evidence_path}]}`
- **verdict.json** (risk-register 용, --require-verdict): 공통 verdict, verdict∈{ACCEPT,REMEDIATE,ESCALATE}

### .planning/enterprise/
- **budget-*.json**: `{fiscal_year,org_total,personnel_total,scenarios:{base,best,worst},clap:{clap-keys.json 5키},departments:[{name,total,personnel,owner}],assumptions:[≥3]}`
- **variance/*.json** + 동명 .md: `{period,threshold_pct,lines:[{item,plan,actual,variance:actual−plan,variance_pct,derp:{describe,explain,respond,prevent}}]}`
- **screen/<target>.json**: `{target,categories:[5×{name,weight(Σ=1.0±0.001),score:1-5}],disqualifiers:[≥1],stop_rule,annual_revenue}` + screen/verdict.json(verdict∈{APPROVE,REBASELINE,REJECT})
- **strategy-cascade.md**, **portfolio.json** (서사·태그 — 게이트 없음)

## 게이트별 판정 기준 (요약 — 상세는 각 .sh 헤더)

- **gate-risk-register** `[--require-verdict]`: 필수 필드·likelihood/impact 1..5 정수·id 중복 0·score==l×i·level==risk-matrix.json 매핑·critical&actions0 실패·next_review 도과 실패. verdict: 전 risk id 커버·coverage 비공백·enum·non-ACCEPT≥1 실패(ESCALATE는 legal 경고).
- **gate-control-matrix**: type/line enum·[크로스]risk_ids 실재·high·critical 무통제 0건·implemented&evidence 파일 부재 실패·2/3선 0건 경고.
- **gate-policy-suite**: 필수 문서 존재·frontmatter owner/review_date·review_date 도과·policy-index↔실파일 diff.
- **gate-cert-readiness**: framework=="ISO27001"·cert-gap id==iso27001-annex-a(93)·status enum·part enum(4)·evidenced&증적 부재 실패·core항목 planned/n·a 실패.
- **gate-calendar**: 필수 필드·status enum·done→evidence 비공백·open&due<TODAY 실패·open&due≤TODAY+14 경고(D-14).
- **gate-budget**: |Σdept−org|/org>0.005 실패·scenarios 3키 number&worst≤base≤best·clap 키==clap-keys.json&값 비공백·assumptions≥3.
- **gate-variance**: plan/actual number·|variance−(actual−plan)|>0.01 실패·|variance_pct|>threshold 라인 DERP 4키 공백 실패.
- **gate-screen** `[--require-verdict]`: categories 길이 5·Σweight∈[0.999,1.001]·score 1..5·disqualifiers≥1·stop_rule 비공백. verdict: enum·coverage·non-APPROVE≥1 실패. (merger-control 검토는 서술 안내로만, 법 판단 legal 위임 — 산술 플래그 없음.)

## 위임 경계 (커맨드 Will Not 에 해당 시 삽입)

법적 판단(corporate/company law·M&A 및 규제 신고·whistleblowing·data privacy)→**legal** | 재무제표·세무·실적 수치→**finance** | JD·온보딩·징계→**hr** | 시장조사·유닛이코노믹스·콘텐츠·브랜드보이스·유닛 레벨 재무(financial-modeler)→**startup**.
