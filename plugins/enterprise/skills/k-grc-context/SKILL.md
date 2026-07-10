---
name: k-grc-context
description: |
  한국 GRC 법정 컨텍스트 가이드 — 상법 지배구조 자산구간 의무(감사위 2조·상근감사 1천억·준법지원인 5천억), 외감법·K-SOX 3단 준거규정, ISMS-P 101항목(16 관리체계+64 보호대책+21 개인정보)과 2026 대개편·2027.7 의무화, 중대재해처벌법의 '형식 문서가 아닌 실질 운영 증적' 원칙, KSSB ESG 로드맵 '미확정, 갱신 필요' 스탬프를 정리한다. 자산구간 의무 트리거 정본은 references/obligation-triggers.json, ISMS-P 항목 정본은 references/isms-p-items.json(게이트 참조). 법적 판단 자체는 legal, 재무 수치는 finance 위임.
  Korean GRC statutory-context guide: asset-tier duties under the Commercial Act (audit committee/standing auditor/compliance officer), External Audit Act & K-SOX, the 101-item ISMS-P set with the 2026 overhaul, and the Serious Accidents Act's substance-over-form evidence principle; canonical data lives in references/obligation-triggers.json and isms-p-items.json. Use when: mapping Korean legal obligations, cert-gap, or compliance calendars — legal judgment delegated to legal.
metadata:
  version: 1.0.0
  category: enterprise
---

# K-GRC Context — 한국 거버넌스 법정 맥락

> 본 스킬은 **1차 매핑용 참조**다. 조문 해석·적용 여부의 법적 판단은 **legal**, 재무제표·세무·실적 수치는 **finance** 위임.
> 규제 수치의 정본은 references/*.json 이며, 아래 표는 요약이다. 값이 갱신되면 JSON 을 먼저 고친다.

## When to Apply
- `/grc-intake` 회사 프로파일 → 법정 의무 룰 매핑 시
- `/cert-gap`(ISMS-P)·`/comp-calendar`(정기 의무) 설계 시
- K-SOX·중대재해·개인정보 관련 통제 골격을 잡을 때

## 상법 지배구조 자산구간 의무 (정본: references/obligation-triggers.json)
| 의무 | 근거 | 임계 | 위임 |
|------|------|------|------|
| 감사위원회 | 상법 §542-11 | 자산 2조 이상 상장사 | legal |
| 상근감사 | 상법 §542-10 | 자산 1천억 이상(감사위 미설치) | legal |
| 준법지원인 | 상법 §542-13 | 자산 5천억 이상 상장사 | legal |
| 외부감사 | 외감법 시행령 §5 | 자산·매출 500억 등 4지표 중 2 (감사인 45일 선임) | finance |
| 내부회계(K-SOX) | 외감법 §8 | 자산 1천억↑(5천억↑ 감사인 감사) | finance |
| 중대재해법 | 중대재해법 §3~4 | 상시근로자 5인↑ | legal |

## K-SOX 3단 준거 + 최신 흐름
- 3단: **설계(RCM) → 운영 → 평가·보고**. `/control-matrix` 의 RCM 골격과 정합.
- 자금부정통제 공시(2025)·감사기준서 1100(2026) 반영 — 숫자 검증은 finance.

## ISMS-P (정본: references/isms-p-items.json — "2026 개편 기준, 갱신 필요" 스탬프)
- **101항목 = 16 관리체계 + 64 보호대책 + 21 개인정보**, 각 항목 {id, part, title, core}.
- status 4단: `n/a → planned → implemented → evidenced`(증적 경로 필수). 2026 대개편은 **증적 중심 전환**.
- core==true 항목은 planned/n·a 로 남기면 안 됨(gate-cert-readiness 실패). 2027.7 의무화 대비.
- ISO27001/SOC2 크로스맵은 순서론(ISMS-P 우선)으로 정리.

## 중대재해처벌법 — 실질 증적 원칙
- **형식 문서가 아니라 실질 운영 증적**(위험성평가·교육·점검 이력)이 유·무죄를 가른다.
- `/comp-calendar` 는 증적 주기 항목으로 관리하고, gate-calendar 는 done→evidence_path 비공백을 강제한다.

## KSSB ESG — 미확정
- KSSB(한국 지속가능성 공시기준) 로드맵은 **미확정** — 본 스킬·산출물에 '갱신 필요' 스탬프를 유지하고 확정 수치를 넣지 않는다.

## References
- references/obligation-triggers.json (자산구간 의무 트리거 정본)
- references/isms-p-items.json (ISMS-P 101항목 정본, core 플래그)
