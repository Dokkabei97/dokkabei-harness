> **English** · [한국어](README_KO.md)

# go-mux

> A specialized plugin bundling code generation, API design, and development guidance for backends based on the Go standard library `net/http` mux (Go 1.22+ ServeMux).

## Overview

go-mux is a plugin for projects that build backends with the Go standard `net/http` ServeMux and `database/sql`, without third-party routers (chi, gin, gorilla). From a single domain model, it scaffolds the entire Model → Repository → Service → Handler → DTO → Test stack in line with the project's existing conventions, designs and implements RESTful APIs, and automatically references a comprehensive guide covering layer discipline, DB access, and testing strategy while writing code.

The core design intent is twofold: "idiomatic Go" and "layer discipline." Before generating, it always analyzes the target project first to extract the package layout, handler patterns, DB driver, and test framework, then follows those conventions exactly, excluding non-idiomatic Java/Python-style patterns. Language-agnostic backend common patterns (API contract principles, DB migrations, hexagonal architecture, observability/security, etc.) are not handled by this plugin but delegated to the `backend-shared` plugin — using the two plugins together is the premise.

## Components

### Agents

- `go-mux-developer` — A specialized agent for Go + stdlib `net/http` mux code generation. It first analyzes the project structure and conventions (Discovery → Convention Extraction), then generates the entire Model, Repository, Service, Handler, DTO, and Test stack bottom-up, and verifies with `go build`/`go vet`/`go test`. It applies idiomatic Go idioms (accept interfaces·return structs, `%w` error wrapping, `context.Context` propagation, table-driven tests) and avoids non-idiomatic patterns.

### Commands

- `/go-gen` — Given a domain name, it automatically generates the entire CRUD stack (Model, Repository, Service, Handler, DTO, Test). The `--fields`, `--layers`, `--no-test`, `--db`, `--soft-delete`, `--audit` options control fields, generated layers, DB driver, soft delete, and audit fields.
- `/go-api-design` — From requirements, it designs REST API endpoints and generates Handler·DTO·error handling·middleware code. It proceeds in 3 stages — resource identification → specification design → code generation — and provides the `--version`, `--auth`, `--pagination` (cursor/offset), `--middleware` (logging/recovery/cors/auth) options along with an API specification table output.

### Skills

- `go-mux-guide` — A comprehensive guide for Go + stdlib `net/http` mux development. Automatically referenced while writing code, it provides idiomatic Go principles·layer discipline (dependency direction top→bottom)·3-stage error-handling defense·context propagation, and selection criteria for architecture/layout/DB driver/test framework. As detailed references it includes per-layer patterns (`references/layer-patterns.md`), DB patterns (`references/db-patterns.md`), and testing patterns (`references/testing-patterns.md`).

## Usage

- CRUD scaffolding: `/go-gen Order` or `/go-gen Product --fields "Name:string, Price:float64, Stock:int"` — generates the domain's entire stack. If only specific layers are needed, `/go-gen Payment --layers "model,repo,service"`.
- API design: `/go-api-design 주문 관리` or `/go-api-design 사용자 관리 --middleware logging,recovery,auth` — creates the endpoint design along with Handler/DTO/error/middleware code.
- The commands internally leverage the `go-mux-developer` agent and the `go-mux-guide` skill. They are also triggered by natural-language requests like "Order 핸들러 만들어줘" or "결제 API 설계해줘", and operate when the target is a Go stdlib mux project.
- At points that require business logic, it does not implement arbitrarily but leaves a `// TODO(human)` marker. It does not modify existing files without an explicit request, and adding `go.mod` dependencies also goes through separate confirmation.

## Dependencies

- `requires` / `dependencies`: `backend-shared`. Since it handles language-agnostic backend common patterns, install and use it together.
- Version-sensitive APIs (Go 1.22+ ServeMux pattern matching, etc.) are generated after looking up documentation via Context7 MCP per the `backend-shared:context7-docs-guide` convention. When Context7 is not installed, that step is skipped.

## Notes

- The target stack is the Go standard `net/http` ServeMux (Go 1.22+ method-based routing) and `database/sql`. Projects using third-party routers such as chi·gin·gorilla are not the target (except when a project is already using one), and a different agent is suitable when needed.
- The DB driver defaults to project detection and supports `database/sql`, `pgx`, and `sqlx`.
- Generated code always goes through verification (build/vet/test), but since responsibility for final compilation·test passing depends on the actual project environment, check and reflect the results.
