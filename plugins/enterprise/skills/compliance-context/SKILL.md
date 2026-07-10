---
name: compliance-context
description: |
  국제 컴플라이언스 컨텍스트 가이드 — 어떤 프레임워크·규제를 채택할지 선택하는 지도(ISO/IEC 27001:2022 Annex A 93개 통제, SOC 2 Trust Services Criteria, GDPR 포인터)와 ISO vs SOC 2 인증 순서론, 증적 규율을 제공한다. cert-gap 산출물의 통제 상태(status)·증적(evidence) 계약을 규정하며, ISO 27001 Annex A 93개 통제 정본은 references/iso27001-annex-a.json(gate-cert-readiness.sh 가 무결성 참조)에 있다. 규제 적용·법적 판단 자체는 legal, 재무 수치는 finance 위임.
  International compliance-context guide: how to choose which frameworks/regulations to adopt (ISO/IEC 27001:2022 Annex A's 93 controls, SOC 2 Trust Services Criteria, GDPR pointers), ISO-vs-SOC 2 certification sequencing, and evidence discipline; the authoritative 93-control set lives in references/iso27001-annex-a.json (integrity-checked by gate-cert-readiness.sh). Use when: selecting frameworks, running a cert gap, or planning certification evidence — legal applicability judged by legal.
metadata:
  version: 1.0.0
  category: enterprise
---

# Compliance Context — 국제 프레임워크 선택·증적 규율

> 본 스킬은 **프레임워크 선택·증적 준비 참조**다. 규제의 적용 여부·법적 해석은 **legal**, 재무 수치는 **finance** 위임.
> 통제 세트의 정본은 references/*.json 이며, 아래는 선택 가이드다. 값이 갱신되면 JSON 을 먼저 고친다.

## When to Apply
- `/grc-intake` 에서 채택할 프레임워크·규제를 선언할 때
- `/cert-gap`(ISO 27001 Annex A 갭 + SOC 2 크로스맵) 설계 시
- 통제 증적(evidence) 규율을 잡을 때

## 프레임워크 선택 지도
| 프레임워크 | 성격 | 언제 채택 | 산출물 |
|-----------|------|----------|--------|
| **ISO/IEC 27001:2022** | 인증형 정보보안 관리 표준(Annex A 93개 통제) | 국제 인증·B2B 신뢰, 통제 세트 정립 | Statement of Applicability + 증적 |
| **SOC 2 (AICPA)** | 감사형 보증 리포트(Trust Services Criteria) | 북미 고객·벤더 실사, 기간 감사 | Type I(시점)/Type II(기간) 리포트 |
| **GDPR** | 개인정보 규제(EU) | EU 데이터 주체 처리 시 | 처리활동기록·DPIA·DPA (법 판단 legal) |

## SOC 2 Trust Services Criteria (TSC)
- **Security(공통 기준, 필수)** + 선택: Availability, Confidentiality, Processing Integrity, Privacy.
- Type I = 특정 시점 설계, Type II = 일정 기간(보통 3~12개월) 운영 효과성. 기간 감사는 증적 연속성이 관건.

## ISO 27001 vs SOC 2 — 순서론
- 통제 세트를 먼저 **정립**하려면 ISO 27001(Annex A 93) 우선 — SoA 로 적용/미적용을 선언.
- 특정 고객(북미)이 SOC 2 리포트를 요구하면 SOC 2 를 먼저/병행. 두 표준은 통제가 크게 겹치므로 크로스맵으로 재사용.
- 권장 경로: ISO 27001 로 통제·증적 골격 → SOC 2 로 감사형 보증 확장(중복 최소화).

## ISO 27001:2022 Annex A (정본: references/iso27001-annex-a.json)
- **93개 통제 = A.5 Organizational 37 + A.6 People 8 + A.7 Physical 14 + A.8 Technological 34**, 각 {id, part, title, core}.
- cert-gap status 4단: `n/a → planned → implemented → evidenced`(증적 경로 필수).
- core==true 우선 통제(정책·접근통제·사고대응·인식교육·특권접근·암호화·백업·로깅·변경관리 등)는 planned/n·a 로 남기면 안 됨(gate-cert-readiness 실패).
- SOC 2 크로스맵은 통제별로 대응 TSC 를 태깅해 증적을 재사용한다.

## 증적(evidence) 규율
- **형식 문서가 아니라 실질 운영 증적**(로그·티켓·리뷰 이력·스크린샷)이 감사를 통과시킨다.
- status==evidenced 는 evidence_path 파일이 실재해야 한다(gate-cert-readiness 강제).
- SOC 2 Type II 는 **증적의 기간 연속성**이 핵심 — 주기 운영 증적을 `/comp-calendar` 로 관리한다.

## References
- references/iso27001-annex-a.json (ISO 27001:2022 Annex A 93개 통제 정본, core 플래그, "갱신 필요" 스탬프)
- ISO/IEC 27001:2022; AICPA SOC 2 Trust Services Criteria; EU GDPR (적용 판단 legal)
