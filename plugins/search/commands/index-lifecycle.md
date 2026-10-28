---
name: index-lifecycle
description: |
  인덱스 수명주기·색인 경로 점검 — 샤드 산정, ILM, 무중단 재색인 런북, Kafka/Spark→ES 색인 정합성(ES-SHD/ES-IDX/ES-ING). 구 /index-pipeline-check 통합.
  Shard sizing, ILM, reindex runbook, and ingestion-path checks. Use when: running /index-lifecycle.
disable-model-invocation: true
---

# /index-lifecycle

## Usage
```
/index-lifecycle [path] [--sizing] [--ilm] [--reindex-plan] [--pipeline]
```
- `--sizing`: 프라이머리/레플리카 수 산정 (ES-SHD-01~05)
- `--ilm`: rollover 조건·단계 설계 (시계열/append-only 인덱스만)
- `--reindex-plan`: 무중단 재색인 절차 + 서비스 코드 변경점 (ES-ING-04, ES-IDX-02, ES-MAP-13)
- `--pipeline`: 색인 경로 점검 — 컨슈머 설정·리스너·bulk 코드 (ES-ING-01~06, ES-CLI-04/05) — 구 `/index-pipeline-check`
- 옵션 없음: 대상에서 감지된 영역 전부

## Flow
1. **사실 확인** — 현재 문서 수·프라이머리 용량·증가율(없으면 사용자에게 `_cat/indices?bytes=gb` 결과 요청), ES 버전·배포 형태, 인덱스 성격(시계열 vs 갱신형 카탈로그), alias 사용 여부, 색인 소스와 커밋 방식, 이벤트의 단조 버전 필드.
2. **판정** — `es-deep-patterns` 의 `references/shards-indexing.md`, `ingest-pipeline.md`, `client-kotlin.md`, `segments-lucene.md`(LUC-SEG-01: force merge 는 읽기 전용만). 각 지적에 항목 ID·신호(파일:라인)·반례.
3. **산출** — 산정표/ILM JSON/재색인 런북/코드 변경점. 수치는 출발점이며 Rally·스테이징 측정으로 확정한다고 명시.

## Output
```
## Index Lifecycle Review — [path]
가정: [...]
### 샤드 산정: 입력(용량·증가율) → 프라이머리 N, 레플리카 M, 근거 ID
### ILM: rollover 조건, 단계 전이(읽기 전용 이후 force merge)
### 재색인 런북: 단계 / 명령 / 확인 지표 / 롤백
### 색인 경로: | 위치 | 항목 ID | 신호 | Severity | 처방 | 장애 주입 검증 |
```

## Boundaries
- 클러스터에 정책·설정을 적용하지 않는다. Kafka 일반 튜닝은 팀 컨벤션을 따르고 ES 와 맞물리는 지점만 판정한다.
