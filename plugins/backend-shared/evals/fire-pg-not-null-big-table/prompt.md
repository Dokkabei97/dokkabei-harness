---
description: "should-fire: 대형 테이블 NOT NULL 컬럼 추가 → PG-MIG-01/03/04/15"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

PG 큰 테이블에 NOT NULL 컬럼 추가해야 해. orders 테이블이 3억 행에 쓰기도 많아. Flyway 마이그레이션으로 shipping_address text NOT NULL 컬럼을 넣으려는데 어떻게 짜야 서비스 안 멈추고 안전해? PostgreSQL 15야.
