---
title: "<% tp.system.prompt('MOC topic name? (e.g., Frontend, Backend, DevOps)') || 'Untitled' %> MOC"
created: "<% tp.date.now('YYYY-MM-DD') %>"
tags:
  - moc
category: "moc"
status: "growing"
moc-topic: "<% tp.system.prompt('MOC topic tag? (e.g., frontend, backend, devops)') || 'untagged' %>"
related: []
---

# <% tp.file.title %>

> [!abstract] About This MOC
> <% tp.file.cursor(1) %>

---

## 1. Learning Roadmap

### Beginner
- [[]] -
- [[]] -

### Intermediate
- [[]] -
- [[]] -

### Advanced
- [[]] -
- [[]] -

---

## 2. Concept Notes

```dataview
TABLE
  status AS "Status",
  difficulty AS "Difficulty",
  created AS "Created"
FROM ""
WHERE category = "concept"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 3. Lab Notes

```dataview
TABLE
  status AS "Status",
  difficulty AS "Difficulty",
  created AS "Created"
FROM ""
WHERE category = "lab"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 4. Comparative Analysis

```dataview
TABLE
  status AS "Status",
  created AS "Created"
FROM ""
WHERE category = "comparison"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 5. Troubleshooting

```dataview
TABLE
  status AS "Status",
  created AS "Created"
FROM ""
WHERE category = "troubleshooting"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 6. Architecture / Patterns

```dataview
TABLE
  status AS "Status",
  difficulty AS "Difficulty"
FROM ""
WHERE category = "pattern"
  AND contains(tags, this.moc-topic)
SORT created DESC
```

---

## 7. Recent TIL (30 Days)

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

## 8. Study Progress Statistics

### Distribution by Status

```dataview
TABLE WITHOUT ID
  status AS "Status",
  length(rows) AS "Count"
FROM ""
WHERE contains(tags, this.moc-topic)
  AND category != null
GROUP BY status
```

### Distribution by Category

```dataview
TABLE WITHOUT ID
  category AS "Category",
  length(rows) AS "Count"
FROM ""
WHERE contains(tags, this.moc-topic)
  AND category != null
GROUP BY category
```

---

## 9. Related MOCs

- [[]] -
- [[]] -

---

## 10. Study Goals

### Short-term (1 Month)
- [ ]
- [ ]

### Mid-term (3 Months)
- [ ]

### Long-term (6 Months+)
- [ ]
