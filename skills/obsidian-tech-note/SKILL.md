---
name: obsidian-tech-note
description: |
  An Obsidian note template system for developer technical learning.
  Supports systematic learning records by leveraging installed plugins
  such as Templater, DataView, Tasks, Excalidraw, and Advanced Table.
  Provides 7 template types: tech concept, code lab, comparison analysis,
  troubleshooting, architecture pattern, TIL, and MOC index.
---

# Obsidian Developer Technical Learning Note System

A template system for systematically managing the entire process of learning new technologies, practicing, performing comparative analysis, solving problems, and reflecting -- all within Obsidian.

---

## 1. Document Type Detection

Analyzes keywords from user requests to automatically select the appropriate template from 7 categories.

### Detection Priority

| Priority | Category | Detection Keywords | Template |
|----------|---------|------------|--------|
| 1 | troubleshooting | error, bug, fix, debug, resolve | [troubleshooting](templates/troubleshooting.md) |
| 2 | comparison | vs, compare, difference, alternative, choose | [comparison](templates/comparison.md) |
| 3 | pattern | pattern, architecture, design | [architecture-pattern](templates/architecture-pattern.md) |
| 4 | lab | lab, tutorial, hands-on, practice, walkthrough | [code-lab](templates/code-lab.md) |
| 5 | til | TIL, today, reflection | [til](templates/til.md) |
| 6 | moc | MOC, index, list, roadmap, organize | [moc-index](templates/moc-index.md) |
| 7 | concept | concept, understand, learn, principle, how it works (default) | [tech-concept](templates/tech-concept.md) |

### Detection Rules

1. Keyword matching: Check whether the request contains detection keywords
2. Priority application: If multiple types match, select the type with the highest priority
3. Ambiguous cases: If determination is difficult, ask the user about the document type
4. Default: If no keywords match, select concept

---

## 2. Template List

### Core Templates (4 types)
The essential templates used most frequently in daily practice.

| # | Template File | Purpose | Category | tp.system.prompt |
|---|-----------|------|---------|-----------------|
| 1 | [tech-concept.md](templates/tech-concept.md) | Learning new technical concepts | concept | 1 (tech stack) |
| 2 | [code-lab.md](templates/code-lab.md) | Code practice / tutorial walkthrough | lab | 1 (tech stack) |
| 3 | [troubleshooting.md](templates/troubleshooting.md) | Error resolution / debugging records | troubleshooting | 0 |
| 4 | [til.md](templates/til.md) | TIL / daily learning records | til | 0 |

### Extended Templates (3 types)
Extended templates used in specific situations.

| # | Template File | Purpose | Category | tp.system.prompt |
|---|-----------|------|---------|-----------------|
| 5 | [comparison.md](templates/comparison.md) | Library / framework comparison analysis | comparison | 2 (comparison targets A, B) |
| 6 | [architecture-pattern.md](templates/architecture-pattern.md) | Design pattern / architecture learning | pattern | 1 (pattern name) |
| 7 | [moc-index.md](templates/moc-index.md) | Topic-based note collection index | moc | 1 (topic name) |

---

## 3. Plugin Dependencies

### Required
Plugins that must be installed for this template system to function.

| Plugin | Role | Used In Templates |
|---------|------|-----------|
| **Templater** | Automatic date/filename insertion, user input prompts, template automation | All |
| **DataView** | Dynamic queries based on YAML frontmatter, automatic list/table generation | MOC Index, TIL |

### Recommended
Plugins that significantly enhance the learning experience.

| Plugin | Role | Used In Templates |
|---------|------|-----------|
| **Tasks** | Learning checklists, review schedules, progress tracking | Tech Concept, Code Lab, Pattern |
| **Advanced Table** | Comparison table editing/sorting, Tab key cell navigation | Comparison Analysis |
| **Excalidraw** | Architecture diagrams, system structure diagrams | Architecture Pattern |

### Optional
Additional plugins useful for specific workflows.

| Plugin | Role | Used In Templates |
|---------|------|-----------|
| **Kanban** | Learning progress board (To Do / In Progress / Done) | External board integration |
| **Outliner** | Hierarchical outline editing, fold/unfold | Tech Concept, Pattern |
| **Calendar** | TIL date-based navigation | TIL |

---

## 4. Vault Folder Structure

```
Vault/
├── _templates/           # Templater template folder (specified in Templater settings)
├── 00-MOC/               # MOC index pages
├── 01-Concepts/          # Tech concept notes
├── 02-Labs/              # Code lab notes
├── 03-References/        # Comparison analysis, troubleshooting, pattern notes
├── 04-TIL/               # TIL / daily learning records
│   └── 2026/
│       └── 02/
└── Assets/               # Images, Excalidraw files
    └── Excalidraw/
```

---

## 5. Unified YAML Frontmatter Schema

The YAML frontmatter superset shared by all templates.

### Required Fields (5)

| Field | Type | Description | Example |
|------|------|------|------|
| `title` | string | Note title | `"Understanding React Hooks"` |
| `created` | string | Creation date (YYYY-MM-DD) | `"2026-02-15"` |
| `tags` | list | Classification tags | `[concept, react]` |
| `category` | string | Category (one of 7 types) | `"concept"` |
| `status` | string | Learning status | `"seedling"` |

### Optional Fields

| Field | Type | Description | Used In Templates |
|------|------|------|-----------|
| `difficulty` | string | Difficulty (beginner/intermediate/advanced) | concept, lab, comparison, pattern |
| `tech-stack` | list | Related tech stack | concept, lab, comparison, pattern |
| `related` | list | Related note links | All |
| `moc-topic` | string | MOC topic (for DataView queries) | moc-index |

### Status Flow

```
seedling  -->  growing  -->  evergreen
(draft)       (refining)    (complete/stable)
```

---

## 6. Gradual Adoption Strategy

### Phase 1: Getting Started (Week 1)
- Install only Templater and DataView plugins
- Use only the 4 Core templates (concept, lab, troubleshooting, til)
- Copy Core templates to the `_templates/` folder
- Focus on building the TIL habit

### Phase 2: Expansion (Weeks 2-3)
- Add Tasks and Advanced Table plugins
- Add 3 Extended templates (comparison, pattern, moc)
- Organize existing notes with MOC index
- Start using review checklists

### Phase 3: Optimization (Week 4+)
- Introduce Optional plugins like Excalidraw, Kanban
- Customize DataView queries
- Set up Templater shortcuts (Alt+1~7)
- Establish your own workflow

---

## 7. Templater Configuration Guide

### Template Folder Location
Obsidian Settings > Templater > Template Folder Location: `_templates/`

### Auto-Insertion Variables

| Templater Syntax | Description |
|---------------|------|
| `<% tp.date.now("YYYY-MM-DD") %>` | Today's date |
| `<% tp.date.now("YYYY-MM-DD", 7) %>` | Date 7 days later (review schedule) |
| `<% tp.file.title %>` | Current file name |
| `<% tp.system.prompt("Question") %>` | User input prompt |
| `<% tp.file.cursor(1) %>` | Cursor position designation |

### tp.system.prompt Rules
- Core templates: Maximum 1-2 (prioritize quick note creation)
- Extended templates: As many as needed
- All prompts must have defaults: `tp.system.prompt("Question") || "untagged"`

### Recommended Shortcuts

| Shortcut | Template |
|--------|-------|
| Alt+1 | tech-concept.md |
| Alt+2 | code-lab.md |
| Alt+3 | troubleshooting.md |
| Alt+4 | til.md |
| Alt+5 | comparison.md |
| Alt+6 | architecture-pattern.md |
| Alt+7 | moc-index.md |

---

## 8. DataView Query Patterns

### Recent Learning Notes (7 days)

```dataview
TABLE category AS "Type", status AS "Status", tech-stack AS "Tech"
FROM ""
WHERE category != null
  AND date(created) >= date(today) - dur(7 days)
SORT created DESC
LIMIT 10
```

### Seedling Status Notes (Review Needed)

```dataview
TABLE category AS "Type", created AS "Created", tech-stack AS "Tech"
FROM ""
WHERE status = "seedling"
SORT created ASC
```

### Notes by Tech Stack

```dataview
TABLE category AS "Type", status AS "Status", difficulty AS "Difficulty"
FROM ""
WHERE contains(tech-stack, "React")
SORT created DESC
```

### Note Count by Category

```dataview
TABLE WITHOUT ID
  category AS "Category",
  length(rows) AS "Count"
FROM ""
WHERE category != null
GROUP BY category
SORT length(rows) DESC
```

---

## 9. Tasks Usage Patterns

### Basic Learning Checklist

```markdown
- [ ] Concept understanding complete
- [ ] Code practice complete
- [ ] Summary and link connections
- [ ] Review in 1 week [scheduled:: 2026-02-22]
```

### Query All Incomplete Tasks

```tasks
not done
group by filename
sort by scheduled
```

### Reviews Scheduled This Week

```tasks
not done
scheduled before next week
sort by scheduled
```

---

## 10. Workflow

### New Note Creation Flow

```
1. Ctrl+N or Templater shortcut (Alt+1~7)
   |
2. Select template (template matching the category)
   |
3. Enter basic information via Templater prompts (Core: 0-1, Extended: 1-2)
   |
4. YAML frontmatter + body structure auto-generated
   |
5. Write body content (required sections first, optional sections as needed)
   |
6. Connect related note links ([[links]])
   |
7. Automatically reflected in MOC index (DataView queries)
```

### Review Cycle

```
Created (seedling) --> Review after 1 week --> Re-review after 1 month --> Transition to evergreen
                            |                       |                            |
                     Supplement content        Add examples              Update status
```

---

## 11. Important Notes

1. **Frontmatter consistency**: All notes must include YAML frontmatter (DataView queries depend on it)
2. **Unified category values**: Use only the 7 types: `concept`, `lab`, `comparison`, `troubleshooting`, `pattern`, `til`, `moc`
3. **Tag conventions**: Combine category tags (`#concept`, `#lab`, etc.) + tech tags (`#react`, `#kubernetes`, etc.)
4. **Use links**: Actively use `[[note name]]` wiki-links to connect notes
5. **Update status**: Update seedling -> growing -> evergreen as learning progresses
6. **Excalidraw file path**: Save to the `Assets/Excalidraw/` folder
