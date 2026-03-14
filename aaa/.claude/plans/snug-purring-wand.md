# Data-Layer 학습노트 디렉토리 재구성 계획

## Context
`📚학습노트/Data-Layer/`에 22개 파일이 플랫하게 존재. 파일명 접두사(P=PostgreSQL, M=MongoDB, H=Hybrid)와 frontmatter `part` 필드 기반으로 3개 디렉토리로 정리.
LLM-RAG와 마찬가지로 **파일명 변경 없음, wikilink 업데이트 불필요**. 디렉토리 이동만 수행.

## LLM-RAG와의 비교

| 항목 | LLM-RAG | Data-Layer |
|------|---------|------------|
| 파일 수 | 41개 → 5개 디렉토리 | **22개 → 3개 디렉토리** |
| 분류 기준 | Phase 1~5 (학습 순서) | **Part A/B/C (기술 영역)** |
| 파일명 변경 | 불필요 | **불필요** |
| wikilink 업데이트 | 불필요 | **불필요** |
| MOC 헤더 변경 | Phase→장 (5건) | **불필요** (이미 Part A/B/C) |
| MOC 다이어그램 변경 | Phase→장 | **불필요** (이미 Part A/B/C) |

## 최종 디렉토리 구조

```
📚학습노트/Data-Layer/
├── Part A PostgreSQL 심화/      (11 files: P1-1 ~ P7-2)
├── Part B MongoDB 심화/         (10 files: M1 ~ M10)
└── Part C 하이브리드 통합/       (1 file: H1)
```

## 링크 안전성
- 파일명 변경 없음 → Obsidian wikilink 안전
- 22개 파일 간 내부 참조 70건 → 모두 안전
- MOC 내 wikilink (별칭 포함) → 변경 불필요
- DataView 쿼리 `FROM "📚학습노트/Data-Layer"` → 하위 폴더 포함 검색이므로 정상 작동
- 크로스 레퍼런스 매트릭스의 별칭 링크 → 파일명 불변이므로 안전

## 실행 단계

### Step 1: 디렉토리 생성
```bash
BASE="/Users/admin/Documents/Obsidian Vault/📚학습노트/Data-Layer"
mkdir -p "$BASE/Part A PostgreSQL 심화" \
         "$BASE/Part B MongoDB 심화" \
         "$BASE/Part C 하이브리드 통합"
```

### Step 2: 파일 이동 (22건, 파일명 변경 없음)
```bash
# Part A: PostgreSQL 심화 (11 files)
mv "$BASE/P1-1 PostgreSQL 프로세스 모델과 메모리 구조.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P1-2 MVCC와 VACUUM.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P2-1 Window Functions 심화.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P2-2 CTE Recursive CTE LATERAL JOIN.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P2-3 GROUPING SETS와 JSONB.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P3 고급 인덱스 전략.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P4 트랜잭션과 동시성 제어.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P5 실행 계획 심화 분석.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P6 파티셔닝.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P7-1 커넥션 풀링.md" "$BASE/Part A PostgreSQL 심화/"
mv "$BASE/P7-2 모니터링과 운영.md" "$BASE/Part A PostgreSQL 심화/"

# Part B: MongoDB 심화 (10 files)
mv "$BASE/M1 MongoDB 아키텍처 심화.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M2 고급 문서 모델링 패턴.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M3 Aggregation Pipeline 심화.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M4 인덱스 심화 전략.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M5 트랜잭션 심화.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M6 Replica Set과 읽기 분산.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M7 Sharding 이해.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M8 Change Streams 심화.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M9 Spring Data MongoDB와 Kotlin 패턴.md" "$BASE/Part B MongoDB 심화/"
mv "$BASE/M10 성능 모니터링과 진단.md" "$BASE/Part B MongoDB 심화/"

# Part C: 하이브리드 통합 (1 file)
mv "$BASE/H1 하이브리드 아키텍처 설계.md" "$BASE/Part C 하이브리드 통합/"
```

### Step 3: MOC 업데이트
**변경 불필요** — MOC의 섹션 헤더(`## Part A:`, `## Part B:`, `## Part C:`)와 아키텍처 다이어그램이 이미 Part 기반 네이밍을 사용 중. 파일명 불변이므로 wikilink도 수정 불필요.

## 검증
```bash
BASE="/Users/admin/Documents/Obsidian Vault/📚학습노트/Data-Layer"

# 1. 루트에 .md 잔존 확인 (없어야 함)
find "$BASE" -maxdepth 1 -name "*.md"

# 2. 총 파일 수 확인 (22개여야 함)
find "$BASE" -name "*.md" | wc -l

# 3. 각 파트별 파일 수 확인
for dir in "$BASE"/*/; do
  count=$(find "$dir" -name "*.md" | wc -l | tr -d ' ')
  echo "$(basename "$dir"): ${count}개"
done
# 기대: Part A(11), Part B(10), Part C(1)
```

## 수정 대상 파일
- `📚학습노트/Data-Layer/` 내 22개 .md 파일 (이동만)
- `🧭학습로드맵/Data-Layer-MOC.md` — **변경 없음**
