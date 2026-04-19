---
name: search-quality
description: "Search quality evaluation with relevance test case design, metric frameworks, and A/B test specifications"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /search-quality - Search Quality Evaluation

## Triggers
- Search relevance improvement planning and validation
- New search feature quality assessment before release
- Ranking algorithm changes requiring before/after measurement
- A/B test design for search experience experiments

## Usage
```
/search-quality [target] [options]

Options:
  --design-test-cases    Generate query-document relevance pairs with graded judgments
  --evaluate-results     Analyze search results against relevance criteria and compute metrics
```

## Behavioral Flow

### Standard Flow
1. **Analyze**: Examine search domain — index mappings, query logic, business context, and user intent patterns
2. **Design**: Create relevance test cases with query-document pairs and graded judgments
3. **Evaluate**: Apply evaluation metrics (NDCG, MAP, MRR) to assess ranking quality
4. **Recommend**: Identify relevance gaps and propose concrete improvements

### Graded Relevance Levels
| Grade | Score | Definition | Example |
|---|---|---|---|
| Perfect | 4 | Exact match to user intent, ideal result | Query "아이폰 15 프로" → iPhone 15 Pro product page |
| Excellent | 3 | Highly relevant, satisfies the query well | Query "아이폰 15 프로" → iPhone 15 Pro case/accessory |
| Good | 2 | Relevant but not ideal, partially satisfies intent | Query "아이폰 15 프로" → iPhone 15 (non-Pro) product page |
| Fair | 1 | Marginally relevant, tangentially related | Query "아이폰 15 프로" → iPhone 14 Pro product page |
| Bad | 0 | Irrelevant or harmful to search experience | Query "아이폰 15 프로" → Android phone product page |

### Evaluation Metrics
| Metric | Purpose | Interpretation |
|---|---|---|
| NDCG@k | Measures ranking quality with graded relevance | 1.0 = perfect ranking; considers position and grade |
| MAP@k | Mean Average Precision across queries | 1.0 = all relevant docs ranked at top positions |
| MRR | Mean Reciprocal Rank of first relevant result | 1.0 = relevant result always at position 1 |
| Precision@k | Fraction of top-k results that are relevant | Higher = fewer irrelevant results in top positions |
| Recall@k | Fraction of relevant docs found in top-k | Higher = fewer relevant results missing from top |

### Test Case Design Principles
- **Query Distribution**: Cover head queries (high frequency), torso queries (medium), and tail queries (low frequency/long-tail)
- **Intent Coverage**: Navigational (specific item), informational (browsing/exploring), transactional (ready to act)
- **Edge Cases**: Typos, synonyms, Korean/English mixed queries, zero-result queries
- **Seasonal Awareness**: Time-sensitive queries that shift relevance (e.g., seasonal products)

## Tool Coordination
- **Glob**: Discover mapping files, query configurations, and existing test data
- **Grep**: Locate query construction logic, boosting configurations, and analyzer settings
- **Read**: Examine search service code, ranking logic, and synonym dictionaries
- **Write**: Generate test case files and evaluation report documents

## Key Patterns
- **Query Taxonomy**: Classify queries by intent type and frequency tier for balanced test coverage
- **Judgment Calibration**: Define clear relevance criteria per domain to ensure consistent grading
- **Metric Selection**: Choose metrics aligned with business goals (e.g., MRR for navigational, NDCG for exploratory)
- **Regression Detection**: Compare metrics across versions to catch quality degradation

## Examples

### Design test cases for product search
```
/search-quality src/main/kotlin/com/example/search/ --design-test-cases
# Analyzes search domain and query patterns
# Generates query-document relevance pairs with graded judgments
```

### Evaluate search result quality
```
/search-quality test/search-results/ --evaluate-results
# Computes NDCG, MAP, MRR from result data
# Identifies queries with poor ranking and suggests improvements
```

### Full quality assessment
```
/search-quality src/main/kotlin/com/example/search/
# End-to-end analysis: domain understanding → test design → evaluation framework
# Produces comprehensive quality report with improvement roadmap
```

## Output Format

### Standard Output
```
## Search Quality Assessment
- Domain: [e.g., product search, content search]
- Query Corpus: [count] test queries
- Metric Focus: [primary metrics]

## Domain Analysis
- Search Fields: [fields used in queries]
- Boosting: [field boost configuration]
- Analyzers: [analyzer chain summary]
- Intent Distribution: Navigational [%] / Informational [%] / Transactional [%]
```

### With --design-test-cases
```
## Test Cases

### Head Queries (High Frequency)
| Query | Document | Grade | Rationale |
|---|---|---|---|
| 아이폰 15 | iPhone 15 128GB | Perfect (4) | Exact product match |
| 아이폰 15 | iPhone 15 Case | Good (2) | Related accessory |
| 아이폰 15 | Galaxy S24 | Bad (0) | Competitor product |

### Torso Queries (Medium Frequency)
...

### Tail Queries (Long-tail)
...

### Edge Cases
| Query | Type | Expected Behavior |
|---|---|---|
| 아이폰15 (no space) | Spacing variation | Same results as "아이폰 15" |
| iphon 15 | Typo | Suggest "iphone 15", show results |
| "" (empty) | Empty query | Popular/trending results |
```

### With --evaluate-results
```
## Evaluation Results

### Overall Metrics
| Metric | Score | Benchmark | Status |
|---|---|---|---|
| NDCG@10 | 0.72 | 0.80 | ⚠ Below target |
| MAP@10 | 0.65 | 0.70 | ⚠ Below target |
| MRR | 0.85 | 0.80 | ✓ On target |

### Per-Query Analysis
| Query | NDCG@10 | Top Issue |
|---|---|---|
| 나이키 운동화 | 0.45 | Irrelevant color variants ranked above exact matches |
| 무선 이어폰 | 0.38 | Wired earphones appearing in top 5 |

### Improvement Recommendations
1. [HIGH] Add `product_type` filter boost to separate accessories from main products
2. [MEDIUM] Implement synonym mapping: "운동화" → "러닝화, 스니커즈"
3. [LOW] Adjust `name` field boost from 2.0 to 3.0 for exact match preference
```

### A/B Test Specification
```
## A/B Test Design
- Hypothesis: [change description] will improve [metric] by [target]%
- Control: Current ranking algorithm
- Variant: [modified ranking description]
- Traffic Split: [percentage]
- Duration: [recommended days]
- Primary Metric: [metric]
- Guardrail Metrics: [metrics that must not degrade]
- Minimum Detectable Effect: [percentage]
- Sample Size: [estimated queries needed]
```

## Boundaries

**Will:**
- Design search quality test cases with graded relevance judgments
- Define evaluation frameworks using standard IR metrics (NDCG, MAP, MRR)
- Analyze search result ordering and identify relevance issues
- Design A/B test specifications for search experiments
- Provide improvement recommendations tied to specific metrics

**Will Not:**
- Execute search queries against a live Elasticsearch cluster
- Collect real user click/engagement data for evaluation
- Implement ranking changes in source code without explicit consent
- Perform statistical significance testing on live A/B test results
