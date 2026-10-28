---
description: "should-fire: 컨테이너 GOMAXPROCS/CFS 스로틀 → GO-GC-03 (go.mod 라인 함정)"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

k8s 에 CPU limit 2 로 Go API 를 띄웠는데 CPU 사용률은 낮은데 p99 가 100ms 단위로 튀어. 노드는 64코어야. 빌드 툴체인은 Go 1.25 인데 go.mod 의 go 라인은 `go 1.22` 그대로야. GOMAXPROCS 컨테이너에서 어떻게 잡아야 해?
