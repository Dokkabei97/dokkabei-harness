---
name: require-formatting
enabled: true
event: stop
pattern: .*
---

## Before Completing - Run Formatting

You must run code formatting before finishing your task.

**Detect project type and run appropriate formatter:**

1. **Check for project type indicators:**
   - `build.gradle` or `build.gradle.kts` → Kotlin/Java project
   - `package.json` → JavaScript/TypeScript project
   - `pyproject.toml` or `setup.py` → Python project
   - `go.mod` → Go project
   - `Cargo.toml` → Rust project

2. **Run the appropriate formatter:**

   | Project Type | Command |
   |--------------|---------|
   | Kotlin (Gradle) | `./gradlew ktlintFormat` |
   | JavaScript/TypeScript | `npx prettier --write .` or `npm run format` |
   | Python | `black .` or `ruff format .` |
   | Go | `gofmt -w .` or `go fmt ./...` |
   | Rust | `cargo fmt` |

3. **If multiple project types exist**, run all applicable formatters.

4. **If no formatter is configured**, inform the user and suggest setting one up.

**Example workflow:**
```bash
# For a TypeScript project
npx prettier --write "src/**/*.{ts,tsx,js,jsx}"

# For a Kotlin project
./gradlew ktlintFormat

# For a Python project
black .
```

Do NOT skip formatting unless the user explicitly asks to skip it.
