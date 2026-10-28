---
description: "hard: 업그레이드 후 같은 템플릿인데 재현율·디스크·메모리 변화 → VEC-IDX-01 (8.14 기본 int8_hnsw)"
tags: [hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

ES 클러스터를 8.12 에서 8.17 로 올렸어. 인덱스 템플릿은 그대로야(`"embedding": {"type": "dense_vector", "dims": 1024, "similarity": "cosine"}`, index_options 는 안 적었어). 업그레이드 뒤에 새로 만들어진 월별 인덱스부터 같은 질의셋 기준 recall@10 이 눈에 띄게 떨어졌고, 문서 수 대비 디스크 사용량은 오히려 늘었는데 kNN 할 때 노드 페이지 캐시 사용량은 줄었어. 매핑은 하나도 안 바꿨는데 뭐가 바뀐 거고, 어떻게 대응해야 해?
