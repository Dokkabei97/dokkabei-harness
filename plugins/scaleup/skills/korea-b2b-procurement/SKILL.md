---
name: korea-b2b-procurement
description: |
  한국 B2B·공공 조달 컨텍스트 가이드 — CSAP(클라우드 보안인증 4~6개월), 나라장터·디지털서비스마켓, BMT(벤치마크테스트) 의무화, 협상에 의한 계약(기술 90:가격 10)·85% 컷, 20억 미만 대기업참여제한을 딜 자격 검증과 파이프라인 마일스톤에 반영한다. 공공 딜 MAP 의 CSAP/BMT 마일스톤 근거.
  Use when: 공공·대기업 B2B 딜 검토, CSAP/BMT 일정 반영, 나라장터 입찰 조건 확인, 공공 딜 MEDDPICC paper_process 작성 시.
  Korean B2B/public procurement context guide covering CSAP, the g2b/digital-service marketplaces, mandatory BMT, negotiated-contract scoring (tech 90:price 10) with the 85% cut, and the sub-2bn KRW large-enterprise participation limit.
  Use when: reviewing public/enterprise Korean deals, or scheduling CSAP/BMT milestones.
metadata:
  version: 1.0.0
  category: scaleup
---

# Korea B2B Procurement — 한국 B2B·공공 조달

한국 엔터프라이즈·공공 딜 특유의 조달 관문을 MEDDPICC(특히 decision_process·paper_process)와 파이프라인 마일스톤에 반영한다.

## 공공 클라우드 관문

| 관문 | 내용 | 딜 영향 |
|------|------|---------|
| **CSAP**(클라우드 보안인증) | 하·중·상 등급, 취득 **4~6개월** 소요 | 공공 SaaS 딜의 선결 마일스톤 — close_date 를 CSAP 완료 이후로 |
| **BMT**(벤치마크테스트) | 다수 공공 발주에서 **의무화** — 성능·기능 실증 | paper_process 에 BMT 일정·통과 기준 명시 |
| **나라장터·디지털서비스 전문계약** | 공공 조달 창구. 디지털서비스마켓 등록 경로 | 등록 여부가 딜 진입 조건 |

## 협상에 의한 계약 (기술 중심)

- 다수 공공/대기업 SW 사업은 **협상에 의한 계약**: 기술평가 **90 : 가격 10** 비중.
- **85% 컷**: 기술평가 85% 미만 탈락(협상 대상 제외)이 흔함 — 기술 제안서 품질이 승패.
- 시사점: 가격 경쟁보다 **기술 차별화·레퍼런스**가 딜 자격의 핵심(competition·metrics 요소).

## 대기업참여제한

- 공공 SW 사업 중 **사업금액 20억 미만**은 대기업(상호출자제한기업집단) 참여 제한 — 중견·중소에 기회. ICP 판단 시 참고.

## MEDDPICC 반영 지점

| 요소 | 한국 공공 딜 반영 |
|------|------------------|
| `decision_process` | 나라장터 공고→제안→기술협상→계약 단계 |
| `paper_process` | CSAP·BMT·계약심사·보안성 검토 경로 |
| `decision_criteria` | 기술 90:가격 10, 85% 컷 |
| `competition` | 대기업참여제한 구간 여부·레퍼런스 경쟁 |

> **법 판단 위임**: 입찰 자격·계약 조건·하도급 등 법적 해석은 **legal 위임**. 이 스킬은 조달 컨텍스트·마일스톤 근거만 제공한다.

## Boundaries

**Will:** CSAP/BMT/나라장터·협상계약 조달 컨텍스트를 딜 마일스톤·MEDDPICC 에 반영.
**Will Not:** 입찰·계약·하도급 법 판단(→legal), 가격·원가 산정(→finance), 제안서 콘텐츠 실집필(→startup).
