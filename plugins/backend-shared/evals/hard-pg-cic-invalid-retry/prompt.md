---
description: "hard: CIC 취소 후 IF NOT EXISTS 재실행 → INVALID 인덱스 잔존 (PG-MIG-07)"
tags: [hard, should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

PostgreSQL 16, Flyway 야. users 테이블(5천만 행, 쓰기 많음)에 아래 한 줄짜리 마이그레이션 파일을 넣었어.

```sql
-- V57__users_email_idx.sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON users (email);
```

첫 배포 때 이 마이그레이션이 statement_timeout 에 걸려 취소되면서 실패했어. flyway repair 하고 다시 배포했더니 이번엔 바로 성공으로 끝났고 flyway_schema_history 에도 success 로 찍혀 있어.
그런데 `WHERE email = ?` 조회의 EXPLAIN 은 여전히 Seq Scan 이고, 그 뒤로 users INSERT/UPDATE 지연도 조금 늘었어. 뭐가 일어난 건지, 지금 상태를 어떻게 확인하고 정리해야 하는지, 앞으로 이 마이그레이션 패턴은 어떻게 고쳐야 하는지 알려줘.
