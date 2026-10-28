---
description: "hard: Go 1.25 컨테이너 GOMAXPROCS 는 CPU limit 만 반영(request 무시) + pgxpool MaxConns 기본 max(4, NumCPU) → GO-GC-03 반례 + GO-DB-07"
tags: [should-fire, hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Go 1.25 부터 GOMAXPROCS 가 컨테이너를 인식한다길래 go.mod 를 `go 1.25` 로 올리고 `go.uber.org/automaxprocs` 를 뺐어. 우리 클러스터 정책은 CPU limit 없이 `requests.cpu: "2"` 만 주는 거고, 노드는 64코어야.

배포하고 나서 HPA 가 최대 20 파드까지 늘어나자 Postgres 가 `FATAL: sorry, too many clients already` 를 뱉기 시작했어. `max_connections` 는 500 이고, DB 접근은 pgx v5 `pgxpool.New(ctx, dsn)` 인데 DSN 에 풀 관련 파라미터는 하나도 안 줬어. 예전엔 레플리카가 적어서 문제가 없었어.

왜 이렇게 된 건지, GOMAXPROCS 와 커넥션 풀 크기를 각각 어떻게 잡아야 하는지 구체적으로 알려줘.
