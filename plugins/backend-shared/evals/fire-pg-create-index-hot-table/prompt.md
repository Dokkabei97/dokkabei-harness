---
description: "should-fire: 운영 테이블 인덱스 추가 → PG-MIG-07/08/01"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

운영 중인 PostgreSQL users 테이블(5천만 행)에 email 컬럼 인덱스를 추가하는 마이그레이션을 짜야 해. 배포 중에 서비스가 멈추면 안 돼. 도구는 Flyway 야. 주의할 점이랑 마이그레이션 SQL 알려줘.
