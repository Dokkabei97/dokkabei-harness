---
title: "<% tp.system.prompt('MOC 주제명? (예: Frontend, Backend, DevOps)') || 'Untitled' %> MOC"
created: "<% tp.date.now('YYYY-MM-DD') %>"
tags:
  - moc
category: "moc"
status: "growing"
moc-topic: "<% tp.system.prompt('MOC 주제 태그? (예: frontend, backend, devops)') || 'untagged' %>"
related: []
---

# <% tp.file.title %>

> [!abstract] 이 MOC에 대하여
> <% tp.file.cursor(1) %>

---

## 1. 학습 로드맵

### 입문 (Beginner)
- [[]] -
- [[]] -

### 중급 (Intermediate)
- [[]] -
- [[]] -

### 고급 (Advanced)
- [[]] -
- [[]] -

---

## 2. 개념 노트

```dataview
TABLE
  status AS "상태",
  difficulty AS "난이도",
  created AS "작성일"
FROM ""
WHERE category = "concept"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 3. 실습 노트

```dataview
TABLE
  status AS "상태",
  difficulty AS "난이도",
  created AS "작성일"
FROM ""
WHERE category = "lab"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 4. 비교 분석

```dataview
TABLE
  status AS "상태",
  created AS "작성일"
FROM ""
WHERE category = "comparison"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 5. 트러블슈팅

```dataview
TABLE
  status AS "상태",
  created AS "작성일"
FROM ""
WHERE category = "troubleshooting"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 6. 아키텍처 / 패턴

```dataview
TABLE
  status AS "상태",
  difficulty AS "난이도"
FROM ""
WHERE category = "pattern"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 7. 최근 TIL (30일)

```dataview
LIST
FROM ""
WHERE category = "til"
  AND contains(tags, this.moc-topic)
  AND date(created) >= date(today) - dur(30 days)
SORT created DESC
LIMIT 10
```

---

## 8. 학습 진행 통계

### 상태별 분포

```dataview
TABLE WITHOUT ID
  status AS "상태",
  length(rows) AS "개수"
FROM ""
WHERE contains(tags, this.moc-topic)
  AND category != null
GROUP BY status
```

### 카테고리별 분포

```dataview
TABLE WITHOUT ID
  category AS "카테고리",
  length(rows) AS "개수"
FROM ""
WHERE contains(tags, this.moc-topic)
  AND category != null
GROUP BY category
```

---

## 9. 관련 MOC

- [[]] -
- [[]] -

---

## 10. 학습 목표

### 단기 (1개월)
- [ ]
- [ ]

### 중기 (3개월)
- [ ]

### 장기 (6개월+)
- [ ]
