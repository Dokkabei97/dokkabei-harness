---
name: init
description: "Project initialization and AGENTS.md/CLAUDE.md context file generation (supports monorepo)"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /init - Project Initialization and Context Generation

## Triggers
- New project onboarding requiring AI agent context setup
- Codebase documentation needs for AI-assisted development
- Cross-agent compatibility requirements (Claude, Gemini, Copilot)
- Team onboarding to establish shared project understanding
- Project structure documentation refresh after major changes

## Usage
```
/init
```
No options - designed for simplicity like Claude Code's built-in `/init` command.
Analyzes the project and generates AGENTS.md automatically.

## Behavioral Flow

### 1. Project Root Detection
Identify project root by scanning for marker files:
- `.git` directory
- `package.json`, `pom.xml`, `build.gradle`, `go.mod`
- `pyproject.toml`, `requirements.txt`, `Cargo.toml`
- `Gemfile`, `composer.json`

Check for existing AGENTS.md file and determine if update or creation is needed.

### 1.5 Monorepo Detection (Branch Point)

**Monorepo Detection Criteria:**

Check for workspace configuration files in the following order:

| File/Config | Tool | Detection Method |
|-------------|------|------------------|
| `pnpm-workspace.yaml` | pnpm | File existence |
| `package.json` → `workspaces` | npm/yarn | JSON field check |
| `lerna.json` | Lerna | File existence |
| `nx.json` | Nx | File existence |
| `turbo.json` | Turborepo | File existence |
| Multiple `package.json`/`go.mod`/`pom.xml` | Generic | Subdirectory scan |

**Branching Logic:**
```
IF monorepo detected:
  → Execute monorepo-init skill workflow
  → Generate root CLAUDE.md with service links
  → Generate individual CLAUDE.md for each service
  → Skip to output summary
ELSE:
  → Continue with standard single-project flow (Steps 2-5)
```

**Monorepo Flow:**
See `monorepo-init` skill for detailed workflow including:
- Service discovery from workspace globs
- Root CLAUDE.md with service navigation table
- Service selection guide generation
- Per-service CLAUDE.md with back-links

### 2. Directory Structure Mapping
Scan project structure to identify:
- Source directories (`src`, `lib`, `app`, `pkg`)
- Test directories (`test`, `tests`, `__tests__`, `spec`)
- Configuration directories (`config`, `.config`)
- Documentation directories (`docs`, `doc`)
- Build output directories (`dist`, `build`, `out`, `target`)

### 3. Technology Stack Detection

#### Language Detection
| Indicator Files | Language |
|-----------------|----------|
| `package.json`, `*.js`, `*.ts` | JavaScript/TypeScript |
| `tsconfig.json` | TypeScript |
| `pom.xml`, `build.gradle`, `*.java` | Java |
| `build.gradle.kts`, `*.kt` | Kotlin |
| `go.mod`, `*.go` | Go |
| `pyproject.toml`, `requirements.txt`, `*.py` | Python |
| `Cargo.toml`, `*.rs` | Rust |
| `Gemfile`, `*.rb` | Ruby |
| `composer.json`, `*.php` | PHP |
| `*.swift`, `Package.swift` | Swift |
| `*.cs`, `*.csproj` | C# |

#### Framework Detection
| Indicator | Framework |
|-----------|-----------|
| `next.config.*` | Next.js |
| `nuxt.config.*` | Nuxt.js |
| `vite.config.*` | Vite |
| `angular.json` | Angular |
| `svelte.config.*` | Svelte/SvelteKit |
| `remix.config.*` | Remix |
| `astro.config.*` | Astro |
| `django`, `manage.py` | Django |
| `flask` in requirements | Flask |
| `fastapi` in requirements | FastAPI |
| `spring` in dependencies | Spring Boot |
| `gin`, `echo`, `fiber` in go.mod | Go Web Frameworks |
| `rails` in Gemfile | Ruby on Rails |

#### Build/Test Tool Detection
| Indicator | Tool |
|-----------|------|
| `jest.config.*` | Jest |
| `vitest.config.*` | Vitest |
| `playwright.config.*` | Playwright |
| `cypress.config.*` | Cypress |
| `pytest.ini`, `pyproject.toml` with pytest | pytest |
| `Makefile` | Make |
| `webpack.config.*` | Webpack |
| `rollup.config.*` | Rollup |
| `esbuild` in dependencies | esbuild |
| `docker-compose.*` | Docker Compose |
| `.github/workflows` | GitHub Actions |
| `.gitlab-ci.yml` | GitLab CI |

### 4. Command Discovery

#### npm/yarn/pnpm Scripts
Parse `package.json` scripts section for:
- Development: `dev`, `start`, `serve`
- Build: `build`, `compile`
- Test: `test`, `test:unit`, `test:e2e`, `test:coverage`
- Lint: `lint`, `format`, `check`

#### Makefile Targets
Parse `Makefile` for common targets:
- `make build`, `make test`, `make run`
- `make lint`, `make clean`

#### Other Package Managers
- Go: `go build`, `go test`, `go run`
- Python: Poetry/pip commands from pyproject.toml
- Rust: `cargo build`, `cargo test`, `cargo run`
- Gradle: `./gradlew build`, `./gradlew test`
- Maven: `mvn package`, `mvn test`

### 5. AGENTS.md Generation

Generate comprehensive context file in project root:

```markdown
# Project: {{project-name}}

## Overview
- **Type**: {{project-type}}
- **Language**: {{primary-language}}
- **Framework**: {{framework}}
- **Description**: {{brief-description}}

## Tech Stack

### Languages
{{language-list}}

### Frameworks & Libraries
{{framework-list}}

### Build Tools
{{build-tools}}

### Testing Tools
{{test-tools}}

## Project Structure

### Key Directories
```
{{directory-tree}}
```

### Important Files
{{important-files-description}}

## Commands

### Development
```bash
{{dev-commands}}
```

### Build
```bash
{{build-commands}}
```

### Test
```bash
{{test-commands}}
```

### Lint & Format
```bash
{{lint-commands}}
```

## Code Conventions

### Naming Conventions
{{naming-conventions}}

### File Organization
{{file-organization}}

### Style Guide
{{style-guide-reference}}

## Architecture

### Patterns Used
{{architecture-patterns}}

### Key Components
{{key-components}}

## Testing

### Test Structure
{{test-structure}}

### Running Tests
{{test-instructions}}

## CI/CD

### Pipeline Overview
{{cicd-overview}}

### Deployment
{{deployment-info}}

## Dependencies

### Key Dependencies
{{key-dependencies}}

### Dependency Management
{{dependency-management}}

## Notes

### Getting Started
{{getting-started}}

### Common Issues
{{common-issues}}

### Additional Resources
{{additional-resources}}
```

## Tool Coordination
- **Glob**: File pattern matching for structure discovery
- **Grep**: Pattern searching in configuration files
- **Read**: Configuration file content analysis
- **Bash**: Git commands, package manager queries (`npm ls`, `go list`)
- **Write**: AGENTS.md file creation

## Key Patterns
- **Marker File Detection**: Identify project boundaries via common indicator files
- **Convention over Configuration**: Use standard directory names when detection fails
- **Progressive Discovery**: Start broad, refine based on findings
- **Cross-Agent Compatibility**: Generate format usable by Claude, Gemini, Copilot

## Examples

### Basic Initialization
```
/init
# Analyzes current project
# Generates AGENTS.md in project root
```

### Typical Output (Single Project)
```
## Project Initialization Complete

### Analysis Summary
- **Project**: my-app
- **Type**: Web Application
- **Language**: TypeScript
- **Framework**: Next.js 14

### Generated File
- `AGENTS.md` created in project root

### Detected Commands
- Development: `npm run dev`
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`

### Next Steps
1. Review generated AGENTS.md for accuracy
2. Add project-specific notes and conventions
3. Commit AGENTS.md to version control
```

### Monorepo Output
```
## 모노레포 초기화 완료

### 감지된 워크스페이스
- **Tool**: pnpm workspaces
- **Services**: 5개

### 생성된 파일
- `/CLAUDE.md` (루트 - 서비스 링크 포함)
- `/packages/api/CLAUDE.md`
- `/packages/web/CLAUDE.md`
- `/packages/shared/CLAUDE.md`
- `/apps/admin/CLAUDE.md`
- `/apps/mobile/CLAUDE.md`

### 루트 컨텍스트 내용
- 5개 서비스 네비게이션 테이블
- 서비스 선택 가이드
- 글로벌 명령어 (pnpm install/build/test)

### 다음 단계
1. 생성된 CLAUDE.md 파일들 검토
2. 필요시 서비스별 설명 보완
3. AGENTS.md 필요시 `agents-md-copy` 스킬 실행
4. 변경사항 커밋
```

## Output Format

### Success Output
```
## /init - Project Initialization Complete

### Project Analysis
- **Name**: {{project-name}}
- **Root**: {{project-root}}
- **Language**: {{primary-language}}
- **Framework**: {{framework}}

### Generated Files
- AGENTS.md ({{file-size}})

### Key Discoveries
- {{discovery-1}}
- {{discovery-2}}
- {{discovery-3}}

### Recommendations
1. Review and customize AGENTS.md sections
2. Add team-specific conventions
3. Document any missing architectural decisions
```

### Existing File Warning
```
## /init - Existing AGENTS.md Detected

An AGENTS.md file already exists at {{path}}.

Options:
1. **Overwrite**: Replace with fresh analysis
2. **Merge**: Add new discoveries to existing file
3. **Cancel**: Keep existing file unchanged

[Prompt user for choice]
```

## Boundaries

**Will:**
- Detect project root and technology stack automatically
- Scan directory structure and identify key components
- Parse configuration files for command discovery
- Generate comprehensive AGENTS.md context file
- Detect existing AGENTS.md and prompt for action
- **Detect monorepo projects** (pnpm, yarn/npm workspaces, lerna, nx, turbo)
- **Generate hierarchical CLAUDE.md** for monorepo (root + each service)
- **Create service navigation links** and selection guides for monorepos

**Will Not:**
- Modify source code or existing configuration files
- Install dependencies or run build commands
- Make assumptions about proprietary frameworks without indicators
- Generate sensitive information (API keys, credentials)
- Override existing AGENTS.md/CLAUDE.md without user confirmation
- Analyze binary files or compiled outputs
- Generate AGENTS.md directly for monorepo (use `agents-md-copy` skill)
