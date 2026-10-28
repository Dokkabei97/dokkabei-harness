---
description: "hard: 단일 호스트 고동시성 TIME_WAIT + 유휴 후 POST 만 EOF → GO-HTTP-02(MaxIdleConnsPerHost 기본 2) + GO-HTTP-04(IdleConnTimeout 90s vs ALB 60s, 재전송 가능 요청만 자동 재시도)"
tags: [should-fire, hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Go 서비스가 AWS ALB(유휴 타임아웃 기본값 그대로) 뒤의 사내 결제 API 하나를 피크 때 동시 150 정도로 호출해. 패키지 전역 `var client = &http.Client{Timeout: 5 * time.Second}` 하나를 재사용하고 있고, 응답 Body 도 끝까지 읽고 닫아.

그런데 두 가지가 이상해.
1. 피크 때 `netstat` 에 TIME_WAIT 이 수만 개고, CPU 프로파일에 TLS 핸드셰이크가 상위야. 클라이언트는 재사용하고 있는데 왜?
2. 새벽에 한참 조용하다가 들어온 첫 요청들에서 간헐적으로 `EOF` / `connection reset by peer` 가 나. 이상하게 같은 API 의 GET 조회는 한 번도 안 터지고 `POST /payments` 만 에러로 올라와.

원인을 구체적으로 설명하고, 어떤 설정을 어떤 값으로 바꿔야 하는지 알려줘.
