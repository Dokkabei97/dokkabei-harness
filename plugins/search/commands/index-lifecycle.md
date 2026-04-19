---
name: index-lifecycle
description: "Elasticsearch index lifecycle management with ILM policy design, reindexing plans, and shard sizing"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /index-lifecycle - Index Lifecycle Management

## Triggers
- ILM policy design or review for time-series or append-only indices
- Zero-downtime reindexing planning for mapping changes or version upgrades
- Alias configuration review and strategy design
- Shard sizing estimation for new or growing indices

## Usage
```
/index-lifecycle [target] [options]

Options:
  --design-ilm          Design ILM policy with phase transitions and rollover conditions
  --reindex-plan        Generate zero-downtime reindexing plan with Kotlin service changes
  --alias-strategy      Review and design alias configurations
```

## Behavioral Flow

### Standard Flow
1. **Assess**: Analyze current index configuration, data volume, growth rate, and access patterns
2. **Design**: Create lifecycle strategy covering ILM, aliases, shard sizing, or reindexing as needed
3. **Generate**: Produce actionable artifacts — ILM policy JSON, reindex scripts, Kotlin code changes
4. **Validate**: Cross-check design against ES best practices and operational constraints

### ILM Phase Design (--design-ilm)
| Phase | Purpose | Typical Actions |
|---|---|---|
| Hot | Active indexing and search | Rollover by size/age/doc count, priority 100 |
| Warm | Search-only, reduced resources | Force merge to 1 segment, shrink replicas, read-only, priority 50 |
| Cold | Infrequent access, archival | Freeze index, searchable snapshot, priority 0 |
| Delete | Data retention expiry | Delete index after retention period |

### Rollover Conditions
| Condition | Recommended Default | Rationale |
|---|---|---|
| max_primary_shard_size | 50GB | Keep shards in 10-50GB optimal range |
| max_age | 30d | Time-based partitioning for predictable lifecycle |
| max_docs | 200,000,000 | Prevent excessive doc count per shard |

### Shard Sizing Guidelines
| Data Volume | Recommended Shards | Shard Size Target |
|---|---|---|
| < 10GB | 1 primary | Single shard sufficient |
| 10-50GB | 1 primary | Within optimal range |
| 50-200GB | 2-4 primaries | 25-50GB per shard |
| 200GB-1TB | 5-20 primaries | 20-50GB per shard |
| > 1TB | Calculate: total / 40GB | 30-50GB per shard target |

### Zero-Downtime Reindex Strategy (--reindex-plan)
1. **Prepare**: Create new index with updated mapping, verify settings
2. **Alias Setup**: Ensure read/write aliases point to current index
3. **Dual-Write**: Modify Kotlin service to write to both old and new indices
4. **Backfill**: Reindex existing data from old to new index (background task)
5. **Verify**: Compare document counts and spot-check data integrity
6. **Switch**: Atomically swap read alias to new index
7. **Cleanup**: Remove dual-write code, delete old index after confirmation period

## Tool Coordination
- **Glob**: Discover index configuration files, ILM policies, and index templates
- **Grep**: Locate index/alias references in Kotlin services and configuration
- **Read**: Examine existing ILM policies, index templates, and service code
- **Write**: Generate ILM policy JSON, reindex scripts, and updated configurations

## Key Patterns
- **Phase Transition Planning**: Match phase durations to business data access patterns (hot queries vs archival)
- **Alias Abstraction**: Always use aliases for application access — never reference concrete index names in code
- **Rollover Estimation**: Calculate rollover triggers from observed ingestion rate and shard size targets
- **Dual-Write Safety**: Kotlin service changes must handle partial failures during dual-write window

## Examples

### Design ILM policy for log indices
```
/index-lifecycle mappings/access-log-template.json --design-ilm
# Analyzes data volume and access patterns
# Generates ILM policy with hot/warm/cold/delete phases
```

### Plan zero-downtime reindexing
```
/index-lifecycle src/main/kotlin/com/example/search/ --reindex-plan
# Identifies index references and alias usage in code
# Generates step-by-step reindex plan with Kotlin code changes
```

### Review alias strategy
```
/index-lifecycle config/elasticsearch/ --alias-strategy
# Reviews current alias configurations
# Recommends read/write alias separation and naming conventions
```

### Full lifecycle assessment
```
/index-lifecycle mappings/product-index.json
# Comprehensive lifecycle assessment: ILM, sharding, aliases
# Produces complete operational blueprint
```

## Output Format

### Standard Output
```
## Index Lifecycle Assessment
- Target: [path]
- Index Pattern: [index name/pattern]
- Estimated Data Volume: [current size]
- Estimated Growth Rate: [per day/month]

## Current Configuration
- Shards: [primary] x [replica]
- ILM Policy: [attached policy or none]
- Aliases: [alias list]

## Recommendations
1. [Priority] [Recommendation description]
```

### With --design-ilm
```
## ILM Policy Design

### Policy: [policy-name]
#### Phase Transitions
| Phase | Min Age | Actions |
|---|---|---|
| Hot | 0 | Rollover (max_size: 50GB, max_age: 30d), priority: 100 |
| Warm | 30d | Force merge (1 segment), shrink (1 replica), read-only, priority: 50 |
| Cold | 90d | Freeze, priority: 0 |
| Delete | 365d | Delete |

#### ILM Policy JSON
```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "30d"
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": { ... },
      "cold": { ... },
      "delete": { ... }
    }
  }
}
```

#### Index Template
```json
{
  "index_patterns": ["[pattern]-*"],
  "settings": {
    "index.lifecycle.name": "[policy-name]",
    "index.lifecycle.rollover_alias": "[alias-name]"
  }
}
```
```

### With --reindex-plan
```
## Reindex Plan

### Prerequisites
- New index: [index-name-v2] with updated mapping
- Current index: [index-name-v1]
- Estimated reindex duration: [time] (based on [doc count] docs, [size])

### Step-by-Step

#### Step 1: Create New Index
```json
PUT /index-name-v2
{ "mappings": { ... }, "settings": { ... } }
```

#### Step 2: Dual-Write Service Changes
```kotlin
// ProductSearchService.kt
// Add dual-write to both v1 and v2 indices
```

#### Step 3: Backfill
```json
POST /_reindex
{
  "source": { "index": "index-name-v1" },
  "dest": { "index": "index-name-v2" }
}
```

#### Step 4: Alias Switch
```json
POST /_aliases
{
  "actions": [
    { "remove": { "index": "index-name-v1", "alias": "index-name" }},
    { "add": { "index": "index-name-v2", "alias": "index-name" }}
  ]
}
```

#### Step 5: Cleanup Checklist
- [ ] Remove dual-write code from Kotlin service
- [ ] Verify query results on new index
- [ ] Delete old index after [retention period]
```

### With --alias-strategy
```
## Alias Strategy

### Current State
| Alias | Index | Is Write Index |
|---|---|---|
| product-search | product-v1 | Yes |

### Recommended Configuration
| Alias | Purpose | Index Pattern |
|---|---|---|
| product-search-read | Application reads | Current + rollover indices |
| product-search-write | Application writes | Latest rollover index only |

### Naming Convention
- Read alias: `{domain}-{purpose}-read`
- Write alias: `{domain}-{purpose}-write`
- Concrete index: `{domain}-{purpose}-{version|date}`
```

### Shard Sizing Output
```
## Shard Sizing

### Input
- Current data size: [size]
- Daily growth: [size/day]
- Retention: [days]
- Projected total: [size]

### Recommendation
- Primary shards: [count]
- Replica shards: [count]
- Estimated shard size: [size] (target: 10-50GB)
- Total shards: [count] (primaries + replicas)
```

## Boundaries

**Will:**
- Design ILM policies with phase transitions and rollover conditions
- Plan zero-downtime reindexing with alias swaps and Kotlin service changes
- Review and design alias configurations and naming conventions
- Calculate shard sizing based on data volume and growth projections
- Generate ready-to-use ILM policy JSON and index templates

**Will Not:**
- Execute ILM policies, reindex operations, or alias changes on a live cluster
- Modify Kotlin service code without explicit user consent
- Make decisions about data retention periods (requires business input)
- Manage cluster-level settings (node allocation, circuit breakers)
