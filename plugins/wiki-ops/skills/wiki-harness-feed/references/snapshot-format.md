# 하네스 건강 스냅샷 렌더 형식 규약

`plugins/observe/bin/observe-export.js`(생산)와 `wiki-harness-feed` 스킬(소비)이 공유하는
형식 계약이다. 렌더러를 수정하면 이 문서와 `tests/hooks/observe-export.bats` 를 함께 갱신한다.

## 형식 규칙 (llmwiki ingest 동작 실측 근거)

1. **산문 1줄 = claim 1개.** llmwiki 의 claim 추출은 100% 코드다 — 헤딩이 아닌 비어있지 않은
   모든 줄이 claim 이 되고, quote 는 그 줄 원문 verbatim 이다. 따라서 표·pretty JSON 이 아니라
   자립형 산문 줄로 렌더한다 (JSON 직접 ingest 는 exit 2 로 거부됨 — md 렌더가 필수인 이유).
2. **자산명은 전 occurrence `[[위키링크]]`.** 위키링크 언급은 entity 자동 upsert 를 일으켜
   `wiki/entities/<자산>.md` 에 derived_from 이력이 컴파운딩된다 — 스킬별 건강 시계열의 축이다.
   `**bold**` 는 entity 만 만들고 교차링크를 못 만들어 missing_crossref lint 를 구조적으로
   유발한다(E2E 실측 8건) — bold·평문 자산명 언급 금지. 자산 id(`plugin:name`)는 ASCII 그대로
   둔다 (FTS 회수 앵커, slug 에서는 `:` 가 탈락해 `pluginname` 형태가 된다).
3. **`attr:` 줄 절대 금지.** 주기마다 변하는 메트릭을 `attr: <entity> | <key> = <value>` 로 넣으면
   결정론 contradiction 이 발화해 entity 가 review_status: conflict 로 오염된다
   (completion_rate 0.83→0.61 재투입 실측). 시계열 수치는 반드시 본문 산문으로만 기술한다.
4. **모든 수치 claim 에 `<env> <ISO주차>` 스탬프 내장.** 인용(citation)은 줄 단위로 뽑히므로,
   각 claim 이 문서 맥락 없이도 "언제·어느 환경" 인지 자립해야 주차 간 비교 질의가 성립한다.
5. **표본 표지 의무.** 레코드·세션·관측 구간 claim 을 항상 포함하고, 세션 5개 미만이면
   "경향 참고용" 경고 claim 을 넣는다 — 저품질 표본이 고신뢰 사실처럼 축적되는 것을 막는다.
6. **계측 경계 명기.** 헤드리스 user-slash 미계측 등 커버리지 한계를 claim 으로 남긴다.
7. **절대경로 0.** 홈 경로 준식별자는 렌더러(자기 검사 exit 2)와 feed-gate.sh 가 이중 차단한다.
8. **절단은 침묵하지 않는다.** 상위 N 캡을 적용하면 "외 N종 생략" claim 을 반드시 남긴다.

## 파일명 슬롯

`.planning/observe-export/<env>-<ISO주차>.md` (예: `personal-2026-W28.md`).
주차는 **지난 완결 ISO 주**다 — 슬롯 타임스탬프(직전 일요일 23:59:59Z)를 집계(`--now`)와
렌더(`--now`) 양쪽에 고정 주입해야 한다. 이 고정이 없으면 `idle_days`·coverage 등 벽시계
파생값이 실행 시각마다 변해 "동일 주차 재실행 = 동일 바이트" 멱등이 성립하지 않는다
(리뷰 확정 소견). 지난 완결 주의 트레이스는 append-only 특성상 불변이므로, 고정 슬롯 하에서
주중 재실행은 `skipped:true`(정상 멱등)로 끝난다. 내용이 실제로 바뀌면(예: 트레이스 로테이션
소실) **새 source_id 페이지가 추가**된다(llmwiki 에 supersede 없음) — 이 누적이 부채
카운터(SKILL.md Phase 5)의 존재 이유다.

## stale 미발화 전제 (설계 승계)

주차별 신규 파일명 구조에서는 llmwiki 의 stale lint 가 구조적으로 발화하지 않는다
(stale 은 동일 경로 파일의 재변경에만 반응). 구 스냅샷 정리는 lint 신호가 아니라
결정론 부채 카운터 → `/wiki-curate` 명시 트리거로만 수행한다.
