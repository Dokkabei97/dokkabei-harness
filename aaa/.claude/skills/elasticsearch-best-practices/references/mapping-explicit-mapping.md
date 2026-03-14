---
title: Always Define Explicit Mappings Instead of Dynamic
impact: CRITICAL
impactDescription: Prevents mapping explosion and wrong type inference on production indices
tags: mapping, dynamic-mapping, schema-design
---

## Always Define Explicit Mappings Instead of Dynamic

Dynamic mapping guesses field types from the first document indexed. Strings become both `text` and `keyword` (doubling storage), numbers may be `long` when `integer` suffices, and unknown fields silently create new mappings that can lead to mapping explosion (1000+ fields crashing the cluster).

**Incorrect (relying on dynamic mapping):**

```json
// No predefined mapping → ES guesses types from first document
// "price": "29.99" (string) → mapped as text+keyword instead of double
// Every new field in future documents creates a new mapping entry
POST /products/_doc
{
  "name": "Wireless Headphones",
  "price": "29.99",
  "status": "active",
  "metadata": {
    "color": "black",
    "weight_g": 250
  }
}
```

**Correct (explicit mapping with dynamic: strict):**

```json
// Define all fields upfront → correct types, no surprises
// dynamic: strict → rejects documents with unmapped fields
PUT /products
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "name": { "type": "text" },
      "price": { "type": "double" },
      "status": { "type": "keyword" },
      "category": { "type": "keyword" },
      "description": { "type": "text" },
      "created_at": { "type": "date", "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis" },
      "metadata": {
        "type": "object",
        "properties": {
          "color": { "type": "keyword" },
          "weight_g": { "type": "integer" }
        }
      }
    }
  }
}
```

**Dynamic mapping options for production:**

| Setting | Behavior | Use Case |
|---------|----------|----------|
| `"strict"` | Reject unknown fields (400 error) | Production indices — safest |
| `false` | Accept but don't index unknown fields | Logging with passthrough fields |
| `true` (default) | Auto-create mappings | Development/exploration only |
| `"runtime"` | Create runtime fields for unknowns | Flexible schema with no index cost |

**검색팀이 색인을 완전히 통제하는 경우:**

검색 전담 팀이 Elasticsearch 클러스터를 운영하고, 색인 파이프라인의 모든 데이터 소스와 스키마 변경을 직접 관리하는 환경에서는 `dynamic: "strict"` 대신 `dynamic: false`를 선택할 수 있다. 이 경우 알 수 없는 필드가 색인되지 않을 뿐 문서 자체는 거부되지 않으므로, 배포 순서(매핑 업데이트 → 애플리케이션 배포)에 대한 운영 부담이 줄어든다.

| 조건 | 권고 설정 |
|------|-----------|
| 다수 팀/시스템이 색인하는 인덱스 | `"strict"` — 스키마 불일치를 즉시 감지 |
| 검색팀 단독 관리 + 색인 파이프라인 통제 | `false` 허용 — 문서 유실 방지, 미매핑 필드는 무시 |
| 스키마 변경이 잦은 탐색/로깅 인덱스 | `"runtime"` — 유연한 스키마, 색인 비용 없음 |

> **주의:** `dynamic: false`를 사용하더라도 명시적 매핑 정의는 반드시 선행되어야 한다. `false`는 "매핑 없이 운영해도 된다"는 의미가 아니라, "매핑에 정의되지 않은 필드가 들어와도 거부하지 않겠다"는 의미이다.

For indices that receive data from multiple sources, always set `dynamic: "strict"` to catch schema mismatches early rather than silently creating wrong mappings.

Reference: [Dynamic mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/dynamic-mapping.html)
