---
name: operating-cadence
description: |
  스케일업 운영 케이던스 가이드 — OKR(Doerr)·EOS Scorecard·4DX 를 비교하고 하나의 미팅 리듬(분기 플랜→주간 체크인→분기말 스코어링)으로 통합한다. KR 규격('X→Y by when', objectives 1~5·KR 1~4), 스코어카드 지표(5~15개), 4DX '주간 세션 생략 시 2사이클 내 붕괴' 경고를 포함. gate-okr·gate-cadence 계약의 서술적 정본.
  Use when: OKR 규격 확인, 주간 체크인 리듬 설계, 스코어카드 지표 선정, /okr-plan·/okr-checkin·/okr-score 작성 시.
  Operating-cadence guide that compares OKR/EOS/4DX and unifies them into one meeting rhythm (quarterly plan -> weekly check-in -> end-of-quarter scoring), with KR spec and the 4DX "skip a weekly session -> cadence collapses within 2 cycles" warning.
  Use when: writing OKRs, designing the weekly check-in rhythm, or selecting scorecard metrics.
metadata:
  version: 1.0.0
  category: scaleup
---

# Operating Cadence — 스케일업 운영 리듬

OKR·EOS·4DX 는 경쟁 프레임워크가 아니라 **한 리듬의 다른 이름**이다. 과잉 분리(3개를 따로 운영)를 막고 하나의 케이던스로 통합한다.

## 프레임워크 비교

| 프레임워크 | 핵심 | scaleup 통합 위치 |
|-----------|------|------------------|
| **OKR**(Doerr) | Objective + Key Results, 분기 리듬, 0.6~0.7 건강 | `/okr-plan`·`/okr-score` |
| **EOS Scorecard** | 5~15개 주간 선행지표, 목표 대비 red/green | `/okr-checkin` `## 스코어카드` |
| **4DX** | WIG·선행지표·스코어보드·책무 케이던스 | 주간 체크인 리듬 자체 |

## KR 규격 (gate-okr 계약)

- objectives **1~5개**, 각 objective 의 KR **1~4개**.
- 각 KR = **`X → Y by when`**: `baseline`(X, number) → `target`(Y, number) `unit`, `due`(YYYY-MM-DD), `owner`, `confidence`(0~1).
- **outcome ≠ activity**: "기능 3개 출시"(활동/output)가 아니라 "NRR 98%→110%"(결과/outcome). KR 52% 가 task 위장 output(실측) — okr-checker 가 반증.
- id 규약: objective `O1`, KR `O1-KR1`. 전역 유일.

## 주간 체크인 리듬 (gate-cadence 계약)

- 고정 요일 주간 세션. frontmatter `date: YYYY-MM-DD` — TODAY 기준 **7일 이내**여야 통과.
- `## 스코어카드`: 5~15개 선행지표를 표로. 목표 이탈 지표는 이슈 전환.
- KR별 confidence 갱신 + 블로커 + 차주 커밋 1~2개.

> **4DX 경고**: 주간 세션을 한 번 생략하면 책무 케이던스가 무너지고 **2사이클(약 2주) 내에 스코어보드가 방치**된다. 리듬 유지가 프레임워크 선택보다 중요하다.

## 분기말 스코어링

- 각 KR `score` 0.0~1.0. **0.6~0.7 이 건강** — 1.0 은 목표가 너무 쉬웠다는 신호(sandbagging).
- 회고(`score/*-retro.md`)는 차기 `/okr-plan --from-score` 입력.

## 미팅 리듬 요약

| 주기 | 세션 | 산출물 |
|------|------|--------|
| 분기초 | 플래닝 워크숍 | okr-*.json + 의존성 로그 |
| 매주 | 체크인 | checkins/YYYY-Www.md |
| 분기말 | 스코어링·회고 | score/*-retro.md |

## Boundaries

**Will:** OKR/EOS/4DX 규격·리듬 안내, gate-okr·gate-cadence 계약의 서술적 정본 제공.
**Will Not:** OKR 자동 확정(okr-checker+사람 승인), 유닛이코노믹스 지표 정의(→startup), 재무 실적 검증(→finance).
