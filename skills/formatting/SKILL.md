---
name: formatting
description: Automatically detect project type and run appropriate code formatting tools after completing tasks. Use when user asks to format code, after code changes, or when explicitly requested. Supports Kotlin (ktlint), Java (spotless, google-java-format), JavaScript/TypeScript (ESLint, Prettier, Biome), Python (black, ruff, isort), Go (gofmt, goimports), Rust (rustfmt), and more.
---

# Code Formatting Skill

Automatically detect the project type and execute the appropriate formatting command after completing code changes.

## Detection Priority

Check for configuration files and tools in the following order:

### 1. Kotlin Projects
**Detection**: `build.gradle.kts`, `build.gradle` with kotlin plugin, `*.kt` files

| Tool | Config File | Command |
|------|-------------|---------|
| ktlint (Gradle Plugin) | `build.gradle.kts` with ktlint | `./gradlew ktlintFormat` |
| ktlint (Standalone) | `.editorconfig`, `ktlint` binary | `ktlint -F "**/*.kt"` |
| detekt | `detekt.yml` | `./gradlew detekt` (lint only) |

### 2. Java Projects
**Detection**: `build.gradle`, `pom.xml`, `*.java` files

| Tool | Config File | Command |
|------|-------------|---------|
| Spotless (Gradle) | `build.gradle` with spotless | `./gradlew spotlessApply` |
| Spotless (Maven) | `pom.xml` with spotless | `./mvnw spotless:apply` |
| google-java-format | standalone | `google-java-format -i **/*.java` |

### 3. JavaScript/TypeScript Projects
**Detection**: `package.json`, `*.js`, `*.ts`, `*.jsx`, `*.tsx` files

| Tool | Config File | Command |
|------|-------------|---------|
| Biome | `biome.json`, `biome.jsonc` | `npx @biomejs/biome format --write .` or `npx @biomejs/biome check --fix .` |
| ESLint + Prettier | `.eslintrc.*`, `.prettierrc.*` | `npx eslint --fix . && npx prettier --write .` |
| ESLint only | `.eslintrc.*` | `npx eslint --fix .` |
| Prettier only | `.prettierrc.*` | `npx prettier --write .` |
| dprint | `dprint.json` | `dprint fmt` |

**Check package.json scripts first:**
```bash
# If scripts exist, prefer them
npm run lint:fix    # or yarn lint:fix, pnpm lint:fix
npm run format      # or yarn format, pnpm format
```

### 4. Python Projects
**Detection**: `pyproject.toml`, `setup.py`, `requirements.txt`, `*.py` files

| Tool | Config File | Command |
|------|-------------|---------|
| Ruff | `pyproject.toml` with ruff, `ruff.toml` | `ruff check --fix . && ruff format .` |
| Black + isort | `pyproject.toml` with black | `black . && isort .` |
| Black only | `pyproject.toml` with black | `black .` |
| autopep8 | `setup.cfg`, `.autopep8` | `autopep8 --in-place --recursive .` |
| yapf | `.style.yapf`, `pyproject.toml` | `yapf -i -r .` |

### 5. Go Projects
**Detection**: `go.mod`, `*.go` files

| Tool | Config File | Command |
|------|-------------|---------|
| gofmt | built-in | `gofmt -w .` |
| goimports | installed | `goimports -w .` |
| golangci-lint | `.golangci.yml` | `golangci-lint run --fix` |

### 6. Rust Projects
**Detection**: `Cargo.toml`, `*.rs` files

| Tool | Config File | Command |
|------|-------------|---------|
| rustfmt | `rustfmt.toml`, `.rustfmt.toml` | `cargo fmt` |
| clippy | built-in | `cargo clippy --fix --allow-dirty` |

### 7. C/C++ Projects
**Detection**: `CMakeLists.txt`, `Makefile`, `*.c`, `*.cpp`, `*.h` files

| Tool | Config File | Command |
|------|-------------|---------|
| clang-format | `.clang-format` | `find . -name "*.cpp" -o -name "*.c" -o -name "*.h" \| xargs clang-format -i` |

### 8. Swift Projects
**Detection**: `Package.swift`, `*.swift` files

| Tool | Config File | Command |
|------|-------------|---------|
| swift-format | `.swift-format` | `swift-format -i -r .` |
| SwiftLint | `.swiftlint.yml` | `swiftlint --fix` |

### 9. Ruby Projects
**Detection**: `Gemfile`, `*.rb` files

| Tool | Config File | Command |
|------|-------------|---------|
| RuboCop | `.rubocop.yml` | `rubocop -A` |

### 10. PHP Projects
**Detection**: `composer.json`, `*.php` files

| Tool | Config File | Command |
|------|-------------|---------|
| PHP-CS-Fixer | `.php-cs-fixer.php` | `./vendor/bin/php-cs-fixer fix` |
| Laravel Pint | `pint.json` | `./vendor/bin/pint` |

## Execution Workflow

```
1. Identify project root (look for .git, package.json, build.gradle, etc.)
2. Detect project type(s) - a project may be multi-language
3. Check for existing formatter configurations
4. Check package manager scripts (npm scripts, gradle tasks, etc.)
5. Execute the most specific/project-configured formatter
6. Report results to user
```

## Multi-language Projects (Monorepo)

For monorepos or multi-language projects:
1. Detect all languages present
2. Run formatters in order: backend languages first, then frontend
3. Use workspace-level scripts if available (e.g., `npm run format` at root)

## Error Handling

- If formatter is not installed, suggest installation command
- If configuration is missing, suggest creating one
- If formatting fails, show the error and suggest fixes
- Always show which files were modified

## Example Usage

User: "format the code" or "run formatting" or after completing code changes

Agent Response:
1. Detect: "Found Kotlin project with ktlint gradle plugin"
2. Execute: `./gradlew ktlintFormat`
3. Report: "Formatted 5 files successfully"

## Notes

- Always run from project root directory
- Respect `.gitignore` and tool-specific ignore files
- For large projects, consider running on changed files only
- Some tools have `--check` mode for CI - use `--fix` or `--write` for actual formatting
