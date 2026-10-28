---
description: "hard: 쓰기 중 인덱스 야간 force merge → LUC-SEG-01 (5GB 초과 세그먼트 일반 머지 제외)"
tags: [hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

주문 인덱스(프라이머리 3개, 샤드당 40GB 정도, 상태 변경 때문에 하루 수백만 건 update)에 디스크 아끼고 검색 빠르게 하려고 매일 새벽 `POST orders/_forcemerge?max_num_segments=1` 크론을 돌리고 있어. 처음 며칠은 좋았는데 몇 주 지나니까 `_cat/indices` 의 docs.deleted 가 계속 늘고 디스크도 처음보다 커졌고 검색도 느려졌어. 크론을 더 자주 돌리면 되나? 왜 이렇게 되는지 메커니즘이랑 어떻게 해야 하는지 알려줘.
