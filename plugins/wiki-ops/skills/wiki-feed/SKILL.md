---
name: wiki-feed
description: |
  문서를 llm-wiki vault에 투입(ingest)한다 — 파일·디렉토리를 받아 md/txt/pdf를 순차 ingest하고 파일별 결과(source_id·claims·모순·commit/skipped)를 리포트. 소량(≤5)은 메인 세션이 직접, 대량은 wiki-curator 1회 디스패치. 락·dirty·Ollama 다운 에러 프로토콜은 도구 계약을 따른다. Use when: "이 문서들 위키에 넣어줘", "vault에 컴파일해줘", 지식 소스 일괄 투입 시.
  Feed documents into an llm-wiki vault: sequential ingest of md/txt/pdf with a per-file report (source_id, claims, contradictions, commit/skipped). Use when: adding or compiling documents into the knowledge vault.
---

# /wiki-feed — 문서 투입

얇은 진입점이다 — 실행 로직은 `wiki-ops-orchestrator` 스킬의 Stage 0~1이 수행한다
(커맨드에 로직을 중복 기술하지 않는다).

## When to Apply

- 문서 파일·디렉토리를 vault에 투입할 때 ("이 문서들 위키에 넣어줘")
- 갱신된 소스의 재컴파일이 필요할 때 (동일 내용은 skipped 멱등)
- 파이프라인 검증 목적의 dry-run이 필요할 때 (`--provider fake`)

## Usage

```
/wiki-feed <path...> [--vault <dir>] [--provider fake] [--allow-dirty]
```

| 인자 | 의미 |
|------|------|
| `<path...>` | 파일·디렉토리 (md/markdown/txt/pdf만 — 그 외는 목록에서 제외하고 보고) |
| `--vault` | vault 경로 (생략 시 `$LLMWIKI_VAULT` → 사용자 질문 1회) |
| `--provider fake` | 결정론 dry-run (구조·인용 검증 전용, 요약 품질 무의미) |
| `--allow-dirty` | dirty tree 게이트 우회 (원인 파악 후에만 — 기본은 원인 커밋 권장) |

## Flow

1. 오케스트레이터 Stage 0 (vault 준비·LLMWIKI_BIN 결정 — 최초 1회)
2. Stage 1 실행: 파일별 `ingest --json` 순차 (≤5개 메인 세션 / 6개 이상 wiki-curator 디스패치)
3. `.planning/wiki-feed-report.md` 갱신 + 모순 발생 건 하이라이트 보고

## Boundaries

Will: 로컬 문서 투입, 실패 건 안전 재시도, 파일별 결과 리포트
Will Not: 웹 수집(→ `/wiki-ask --research`의 --allow-network는 사용자 명시 요청 시만),
raw/ 직접 조작, 병렬 ingest (단일 작성자 락 — 순차가 정답)
