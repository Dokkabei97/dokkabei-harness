---
description: "hard: terms 집계 shard_size 기본식 + _count asc 무한 오차 → ES-AGG-01"
tags: [hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

판매 로그 인덱스(프라이머리 12개, 상품 약 20만 종)에서 `terms` 집계로 대시보드 두 개를 만들었어.
- "가장 많이 팔린 상품 10개": `"terms": {"field": "product_id", "size": 10}`
- "가장 적게 팔린 상품 10개": `"terms": {"field": "product_id", "size": 10, "order": {"_count": "asc"}}`

정산팀 엑셀(정확한 값)과 비교하면 많이 팔린 쪽은 순위가 가끔 한두 개 다르고, 적게 팔린 쪽은 완전히 엉망이야. size 10 이면 각 샤드는 실제로 상품 몇 개씩을 코디네이터에 보내는 거야? 왜 이렇게 되는지와 각각 어떻게 고쳐야 하는지 알려줘.
