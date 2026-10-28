---
type: llm
focus: last_message
---

All three of the following are required for PASS:
(a) Explains that ServeMux.ServeHTTP fills in `Pattern` by mutating the `*http.Request` value it is handed (in place, during routing) — it is not something present on the request beforehand nor propagated back up the chain.
(b) Identifies the actual cause: `r.WithContext(...)` in the Auth middleware returns a shallow *copy* of the request, so the mux sets `Pattern` on that copy; the outer Metrics middleware still holds the original `r`, whose `Pattern` stays empty even though it is read after `next.ServeHTTP`.
(c) Gives a working fix that does not depend on the outer `r`: e.g. record the label inside the mux (wrap each handler at registration / use an innermost middleware), or have the outer middleware place a mutable holder (pointer) in the context that an inner wrapper fills with `r.Pattern`, or resolve the pattern explicitly with `mux.Handler(r)` (which returns the matched pattern without serving), or move Metrics inside Auth only if it then reads Pattern from the request the mux actually received. Using an empty-pattern fallback label such as "unmatched" is welcome but not required.
FAIL if it blames the Go version (r.Pattern exists since Go 1.23, so 1.24 is fine) or GODEBUG httpmuxgo121 as the primary cause (mentioning httpmuxgo121 as a secondary thing to check is fine), if it suggests reading the outer `r.Pattern` field before calling next (calling `mux.Handler(r)` up front is a different, valid approach), if it suggests going back to `r.URL.Path` or `r.URL.Path`-based normalization as the fix, or if it does not identify the WithContext copy as the reason the outer request never sees the pattern.
