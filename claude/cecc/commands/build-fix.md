# Build and Fix

Incrementally fix build errors across TypeScript, Kotlin, and Python projects.

## Build Commands by Language

| Language | Build Command | Alternative |
|----------|---------------|-------------|
| TypeScript/JS | `npm run build` | `pnpm build`, `yarn build` |
| Kotlin/Java | `./gradlew build` | `./mvnw package` |
| Python | `python -m build` | `poetry build`, `pip install -e .` |

## Workflow

1. **Detect Project Type** and run appropriate build:
   - `package.json` → `npm run build`
   - `build.gradle.kts` / `build.gradle` → `./gradlew build`
   - `pom.xml` → `./mvnw package`
   - `pyproject.toml` → `python -m build` or `poetry build`

2. **Parse error output**:
   - Group by file
   - Sort by severity

3. **For each error**:
   - Show error context (5 lines before/after)
   - Explain the issue
   - Propose fix
   - Apply fix
   - Re-run build
   - Verify error resolved

4. **Stop if**:
   - Fix introduces new errors
   - Same error persists after 3 attempts
   - User requests pause

5. **Show summary**:
   - Errors fixed
   - Errors remaining
   - New errors introduced

## Language-Specific Error Types

### TypeScript/JavaScript
| Error Type | Quick Fix |
|------------|-----------|
| Type mismatch | Fix type annotation or cast |
| Module not found | Install dependency or fix import path |
| Missing property | Add property or mark optional |

### Kotlin/Java
| Error Type | Quick Fix |
|------------|-----------|
| Unresolved reference | Add import or dependency |
| Null safety violation | Add `?.`, `?:`, or `!!` |
| Type mismatch | Convert type or fix annotation |
| kapt/ksp error | Check annotation processor config |

### Python
| Error Type | Quick Fix |
|------------|-----------|
| ImportError | Install package or fix import path |
| SyntaxError | Fix Python syntax |
| Type error (mypy) | Add type annotation or cast |
| Missing dependency | Add to pyproject.toml/requirements.txt |

## Related Commands

- `/gradle-fix` - Specialized Gradle/Kotlin build fixer
- `/pytest` - Run Python tests with detailed output

Fix one error at a time for safety!
