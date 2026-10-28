> **English** · [한국어](README_KO.md)

# go-mux

> Go runtime/performance specialist knowledge (maps, slices, GC, concurrency, net/http, pprof/PGO, database/sql — 78 items) bundled with code generation and API design for Go standard library `net/http` mux (Go 1.22+ ServeMux) backends. Named go-mux, but covers Go in general.

## Overview

go-mux is a plugin for projects that build backends with the Go standard `net/http` ServeMux and `database/sql`, without third-party routers (chi, gin, gorilla). From a single domain model, it scaffolds the entire Model → Repository → Service → Handler → DTO → Test stack in line with the project's existing conventions, designs and implements RESTful APIs, and automatically references a comprehensive guide covering layer discipline, DB access, and testing strategy while writing code.

The core design intent is twofold: "idiomatic Go" and "layer discipline." Before generating, it always analyzes the target project first to extract the package layout, handler patterns, DB driver, and test framework, then follows those conventions exactly, excluding non-idiomatic Java/Python-style patterns. Language-agnostic backend common patterns (e.g. the Context7 docs-lookup convention, DTO design) are not handled by this plugin but delegated to the `backend-shared` plugin — using the two plugins together is the premise.

## Components

### Agents

- `go-mux-developer` — A specialized agent for Go + stdlib `net/http` mux code generation and review. It first checks facts such as the go.mod `go`/`toolchain` lines, build image, and deployment limits, and in review/performance mode reports findings by specialist item ID. It analyzes the project structure and conventions (Discovery → Convention Extraction), then generates the entire Model, Repository, Service, Handler, DTO, and Test stack bottom-up, and verifies with `go build`/`go vet`/`go test`. It applies idiomatic Go idioms (accept interfaces·return structs, `%w` error wrapping, `context.Context` propagation, table-driven tests) and avoids non-idiomatic patterns.

### Commands

- `/go-gen` — Given a domain name, it automatically generates the entire CRUD stack (Model, Repository, Service, Handler, DTO, Test). The `--fields`, `--layers`, `--no-test`, `--db`, `--soft-delete`, `--audit` options control fields, generated layers, DB driver, soft delete, and audit fields.
- `/go-api-design` — From requirements, it designs REST API endpoints and generates Handler·DTO·error handling·middleware code. It proceeds in 3 stages — resource identification → specification design → code generation — and provides the `--version`, `--auth`, `--pagination` (cursor/offset), `--middleware` (logging/recovery/cors/auth) options along with an API specification table output.

### Skills

- `go-mux-guide` — Go runtime/performance specialist triage plus stdlib mux guide. Symptom → item-ID tables (OOMKill, GC CPU, goroutine growth, TIME_WAIT, pool waits, ...) route to only the needed reference. Each item has applicability, signal, mechanism, prescription, counter-case, verification, and sources (official docs/source); `workflow:project-rules` can select items per project.
  - Specialist: `maps.md` (GO-MAP), `slices-strings.md` (GO-SLC), `gc-memory.md` (GO-GC), `concurrency.md` (GO-CON), `net-http.md` (GO-HTTP), `observability.md` (GO-OBS), `database-sql.md` (GO-DB), `toolchain-versions.md` (GO-VER)
  - Scaffolding conventions: `layer-patterns.md`, `db-patterns.md`, `testing-patterns.md`

## Usage

- CRUD scaffolding: `/go-gen Order` or `/go-gen Product --fields "Name:string, Price:float64, Stock:int"` — generates the domain's entire stack. If only specific layers are needed, `/go-gen Payment --layers "model,repo,service"`.
- API design: `/go-api-design 주문 관리` or `/go-api-design 사용자 관리 --middleware logging,recovery,auth` — creates the endpoint design along with Handler/DTO/error/middleware code.
- `/go-gen` and `/go-api-design` are user-invoked generators (`disable-model-invocation: true` — the model does not fire them on its own). Natural-language requests ("Order 핸들러 만들어줘") are handled by the `go-mux-developer` agent and the `go-mux-guide` skill.
- Performance/memory review: requests like "check GC pressure in this handler" or "goroutines keep growing" go triage table → item → verification method (pprof/trace/benchstat).
- At points that require business logic, it does not implement arbitrarily but leaves a `// TODO(human)` marker. It does not modify existing files without an explicit request, and adding `go.mod` dependencies also goes through separate confirmation.

## Dependencies

- `requires` / `dependencies`: `backend-shared`. Since it handles language-agnostic backend common patterns, install and use it together.
- Version-sensitive APIs (Go 1.22+ ServeMux pattern matching, etc.) are generated after looking up documentation via Context7 MCP per the `backend-shared:context7-docs-guide` convention. When Context7 is not installed, that step is skipped.

## Notes

- The target stack is the Go standard `net/http` ServeMux (Go 1.22+ method-based routing) and `database/sql`. Projects using third-party routers such as chi·gin·gorilla are not the target (except when a project is already using one), and a different agent is suitable when needed.
- DB driver, migration tool, and Go version are never assumed — they are detected from the project (go.mod, existing code, CI image). Supports `database/sql`, `pgx`, and `sqlx`.
- Numbers and defaults in the specialist items were checked against Go 1.27.3 source and the 1.22–1.27 release notes (2026-10).
- Generated code always goes through verification (build/vet/test), but since responsibility for final compilation·test passing depends on the actual project environment, check and reflect the results.
