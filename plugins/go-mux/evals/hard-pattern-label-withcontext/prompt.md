---
description: "hard: ServeMux 는 받은 *Request 의 Pattern 을 제자리에서 채움 + 중간 미들웨어의 r.WithContext 복제 → 바깥 r.Pattern 빈 값 → GO-HTTP-08"
tags: [should-fire, hard, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

stdlib ServeMux(툴체인 Go 1.24, go.mod `go 1.24`)로 라우팅하는 API 에서 Prometheus 메트릭의 path 라벨 카디널리티가 터져서, 라벨을 `r.URL.Path` 대신 `r.Pattern` 으로 바꿨어. 그런데 배포하고 보니 라벨이 전부 빈 문자열이야. 코드는 이래:

```go
func Metrics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		reqDuration.WithLabelValues(r.Method, r.Pattern, strconv.Itoa(sw.status)).
			Observe(time.Since(start).Seconds())
	})
}

func Auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, err := authenticate(r)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey{}, u)))
	})
}

// main
handler := Metrics(Auth(mux))
```

왜 빈 값이 나오고, 어떻게 고쳐야 해?
