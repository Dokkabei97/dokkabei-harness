---
name: obsidian-tech-note
description: |
  개발자 기술 학습을 위한 Obsidian 노트 템플릿 시스템입니다.
  Templater, DataView, Tasks, Excalidraw, Advanced Table 등
  설치된 플러그인을 활용하여 체계적인 학습 기록을 지원합니다.
  기술 개념, 코드 실습, 비교 분석, 트러블슈팅, 아키텍처 패턴, TIL, MOC 인덱스
  7종의 템플릿을 제공합니다.
---

# Obsidian 개발자 기술 학습 노트 시스템

개발자가 새로운 기술을 학습하고, 실습하고, 비교 분석하고, 문제를 해결하고, 회고하는 전 과정을 Obsidian에서 체계적으로 관리하기 위한 템플릿 시스템입니다.

---

## 1. 문서 유형 감지

사용자 요청에서 키워드를 분석하여 7종 카테고리 중 적절한 템플릿을 자동 선택합니다.

### 감지 우선순위

| 우선순위 | 카테고리 | 감지 키워드 | 템플릿 |
|----------|---------|------------|--------|
| 1 | troubleshooting | 에러, error, 오류, 해결, fix, bug, 디버깅 | [troubleshooting](templates/troubleshooting.md) |
| 2 | comparison | vs, 비교, 차이, 대안, 선택 | [comparison](templates/comparison.md) |
| 3 | pattern | 패턴, pattern, 아키텍처, architecture, 설계 | [architecture-pattern](templates/architecture-pattern.md) |
| 4 | lab | 실습, lab, 튜토리얼, tutorial, hands-on, 따라하기 | [code-lab](templates/code-lab.md) |
| 5 | til | TIL, 오늘, today, 회고 | [til](templates/til.md) |
| 6 | moc | MOC, 인덱스, 목록, 로드맵, 정리 | [moc-index](templates/moc-index.md) |
| 7 | concept | 개념, 이해, 학습, 원리, 동작 (기본값) | [tech-concept](templates/tech-concept.md) |

### 감지 규칙

1. 키워드 매칭: 요청에서 감지 키워드 포함 여부 확인
2. 우선순위 적용: 여러 유형에 해당하면 우선순위가 높은 유형 선택
3. 모호한 경우: 판단이 어려우면 사용자에게 문서 유형 질문
4. 기본값: 아무 키워드도 매칭되지 않으면 concept 선택

---

## 2. 템플릿 목록

### Core 템플릿 (4종)
일상적으로 가장 자주 사용하는 핵심 템플릿입니다.

| # | 템플릿 파일 | 용도 | 카테고리 | tp.system.prompt |
|---|-----------|------|---------|-----------------|
| 1 | [tech-concept.md](templates/tech-concept.md) | 새로운 기술 개념 학습 | concept | 1개 (기술 스택) |
| 2 | [code-lab.md](templates/code-lab.md) | 코드 실습/튜토리얼 따라하기 | lab | 1개 (기술 스택) |
| 3 | [troubleshooting.md](templates/troubleshooting.md) | 에러 해결/디버깅 기록 | troubleshooting | 0개 |
| 4 | [til.md](templates/til.md) | TIL / 일일 학습 기록 | til | 0개 |

### Extended 템플릿 (3종)
특정 상황에서 사용하는 확장 템플릿입니다.

| # | 템플릿 파일 | 용도 | 카테고리 | tp.system.prompt |
|---|-----------|------|---------|-----------------|
| 5 | [comparison.md](templates/comparison.md) | 라이브러리/프레임워크 비교 분석 | comparison | 2개 (비교 대상 A, B) |
| 6 | [architecture-pattern.md](templates/architecture-pattern.md) | 설계 패턴/아키텍처 학습 | pattern | 1개 (패턴명) |
| 7 | [moc-index.md](templates/moc-index.md) | 주제별 노트 모음 인덱스 | moc | 1개 (주제명) |

---

## 3. 플러그인 의존성

### 필수 (Required)
이 템플릿 시스템이 작동하기 위해 반드시 설치해야 하는 플러그인입니다.

| 플러그인 | 역할 | 사용 템플릿 |
|---------|------|-----------|
| **Templater** | 날짜/파일명 자동 삽입, 사용자 입력 프롬프트, 템플릿 자동화 | 전체 |
| **DataView** | YAML 프론트매터 기반 동적 쿼리, 자동 목록/테이블 생성 | MOC 인덱스, TIL |

### 권장 (Recommended)
사용하면 학습 경험이 크게 향상되는 플러그인입니다.

| 플러그인 | 역할 | 사용 템플릿 |
|---------|------|-----------|
| **Tasks** | 학습 체크리스트, 복습 일정, 진행 상태 추적 | 기술 개념, 코드 실습, 패턴 |
| **Advanced Table** | 비교 테이블 편집/정렬, Tab 키 셀 이동 | 비교 분석 |
| **Excalidraw** | 아키텍처 다이어그램, 시스템 구조도 | 아키텍처 패턴 |

### 선택 (Optional)
특정 워크플로우에서 유용한 추가 플러그인입니다.

| 플러그인 | 역할 | 사용 템플릿 |
|---------|------|-----------|
| **Kanban** | 학습 진행 상태 보드 (To Do / In Progress / Done) | 외부 보드 연동 |
| **Outliner** | 계층적 개요 편집, 접기/펼치기 | 기술 개념, 패턴 |
| **Calendar** | TIL 날짜별 탐색 | TIL |

---

## 4. Vault 폴더 구조

```
Vault/
├── _templates/           # Templater 템플릿 폴더 (Templater 설정에서 지정)
├── 00-MOC/               # MOC 인덱스 페이지
├── 01-Concepts/          # 기술 개념 노트
├── 02-Labs/              # 코드 실습 노트
├── 03-References/        # 비교 분석, 트러블슈팅, 패턴 노트
├── 04-TIL/               # TIL / 일일 학습 기록
│   └── 2026/
│       └── 02/
└── Assets/               # 이미지, Excalidraw 파일
    └── Excalidraw/
```

---

## 5. YAML 프론트매터 통일 스키마

모든 템플릿이 공유하는 YAML 프론트매터 슈퍼셋입니다.

### 필수 필드 (5개)

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `title` | string | 노트 제목 | `"React Hooks 이해하기"` |
| `created` | string | 생성일 (YYYY-MM-DD) | `"2026-02-15"` |
| `tags` | list | 분류 태그 | `[concept, react]` |
| `category` | string | 카테고리 (7종 중 1개) | `"concept"` |
| `status` | string | 학습 상태 | `"seedling"` |

### 선택 필드

| 필드 | 타입 | 설명 | 사용 템플릿 |
|------|------|------|-----------|
| `difficulty` | string | 난이도 (beginner/intermediate/advanced) | concept, lab, comparison, pattern |
| `tech-stack` | list | 관련 기술 스택 | concept, lab, comparison, pattern |
| `related` | list | 관련 노트 링크 | 전체 |
| `moc-topic` | string | MOC 주제 (DataView 쿼리용) | moc-index |

### status 상태 흐름

```
seedling  -->  growing  -->  evergreen
(초안 작성)    (보완 중)     (완성/안정)
```

---

## 6. 점진적 채택 전략

### Phase 1: 기본 시작 (1주차)
- Templater, DataView 플러그인만 설치
- Core 템플릿 4종(concept, lab, troubleshooting, til)만 사용
- `_templates/` 폴더에 Core 템플릿 복사
- TIL 습관 형성에 집중

### Phase 2: 확장 (2-3주차)
- Tasks, Advanced Table 플러그인 추가
- Extended 템플릿 3종(comparison, pattern, moc) 추가
- MOC 인덱스로 기존 노트 정리
- 복습 체크리스트 활용 시작

### Phase 3: 최적화 (4주차+)
- Excalidraw, Kanban 등 Optional 플러그인 도입
- DataView 쿼리 커스터마이징
- Templater 단축키 설정 (Alt+1~7)
- 자신만의 워크플로우 확립

---

## 7. Templater 설정 가이드

### 템플릿 폴더 지정
Obsidian 설정 > Templater > Template Folder Location: `_templates/`

### 자동 삽입 변수

| Templater 구문 | 설명 |
|---------------|------|
| `<% tp.date.now("YYYY-MM-DD") %>` | 오늘 날짜 |
| `<% tp.date.now("YYYY-MM-DD", 7) %>` | 7일 후 날짜 (복습 일정) |
| `<% tp.file.title %>` | 현재 파일명 |
| `<% tp.system.prompt("질문") %>` | 사용자 입력 프롬프트 |
| `<% tp.file.cursor(1) %>` | 커서 위치 지정 |

### tp.system.prompt 규칙
- Core 템플릿: 최대 1-2개 (빠른 노트 작성 우선)
- Extended 템플릿: 필요한 만큼 허용
- 모든 prompt에 기본값 필수: `tp.system.prompt("질문") || "untagged"`

### 권장 단축키

| 단축키 | 템플릿 |
|--------|-------|
| Alt+1 | tech-concept.md |
| Alt+2 | code-lab.md |
| Alt+3 | troubleshooting.md |
| Alt+4 | til.md |
| Alt+5 | comparison.md |
| Alt+6 | architecture-pattern.md |
| Alt+7 | moc-index.md |

---

## 8. DataView 쿼리 패턴

### 최근 학습 노트 (7일)

```dataview
TABLE category AS "유형", status AS "상태", tech-stack AS "기술"
FROM ""
WHERE category != null
  AND date(created) >= date(today) - dur(7 days)
SORT created DESC
LIMIT 10
```

### seedling 상태 노트 (복습 필요)

```dataview
TABLE category AS "유형", created AS "작성일", tech-stack AS "기술"
FROM ""
WHERE status = "seedling"
SORT created ASC
```

### 기술 스택별 노트 목록

```dataview
TABLE category AS "유형", status AS "상태", difficulty AS "난이도"
FROM ""
WHERE contains(tech-stack, "React")
SORT created DESC
```

### 카테고리별 노트 수

```dataview
TABLE WITHOUT ID
  category AS "카테고리",
  length(rows) AS "개수"
FROM ""
WHERE category != null
GROUP BY category
SORT length(rows) DESC
```

---

## 9. Tasks 활용 패턴

### 학습 체크리스트 기본형

```markdown
- [ ] 개념 이해 완료
- [ ] 코드 실습 완료
- [ ] 정리 및 링크 연결
- [ ] 1주 후 복습 [scheduled:: 2026-02-22]
```

### 전체 미완료 태스크 조회

```tasks
not done
group by filename
sort by scheduled
```

### 이번 주 복습 예정

```tasks
not done
scheduled before next week
sort by scheduled
```

---

## 10. 워크플로우

### 새 노트 생성 흐름

```
1. Ctrl+N 또는 Templater 단축키 (Alt+1~7)
   |
2. 템플릿 선택 (카테고리에 맞는 템플릿)
   |
3. Templater 프롬프트로 기본 정보 입력 (Core: 0~1개, Extended: 1~2개)
   |
4. YAML 프론트매터 + 본문 구조 자동 생성
   |
5. 본문 작성 (필수 섹션 먼저, 선택 섹션은 필요시)
   |
6. 관련 노트 링크 연결 ([[링크]])
   |
7. MOC 인덱스에 자동 반영 (DataView 쿼리)
```

### 복습 사이클

```
작성 (seedling) --> 1주 후 복습 --> 1개월 후 재복습 --> evergreen 전환
                       |                |                    |
                  내용 보완         예제 추가          status 업데이트
```

---

## 11. 주의사항

1. **프론트매터 일관성**: 모든 노트에 YAML 프론트매터 반드시 포함 (DataView 쿼리가 의존)
2. **category 값 통일**: `concept`, `lab`, `comparison`, `troubleshooting`, `pattern`, `til`, `moc` 7종만 사용
3. **태그 규칙**: 카테고리 태그(`#concept`, `#lab` 등) + 기술 태그(`#react`, `#kubernetes` 등) 조합
4. **링크 활용**: `[[노트명]]` 위키링크를 적극 활용하여 노트 간 연결
5. **status 업데이트**: 학습 진행에 따라 seedling -> growing -> evergreen 갱신
6. **Excalidraw 파일 경로**: `Assets/Excalidraw/` 폴더에 저장
