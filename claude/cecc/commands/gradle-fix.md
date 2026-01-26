---
name: gradle-fix
description: Fix Gradle/Kotlin build errors automatically. Runs build, analyzes errors, and applies minimal fixes.
allowed_tools: ["Bash", "Read", "Edit", "Grep", "Glob"]
---

# Gradle Build Fix Command

Fix Kotlin/Gradle build errors with minimal changes.

## Workflow

1. **Run Build and Capture Errors**
   ```bash
   ./gradlew build 2>&1 | head -100
   ```

2. **Analyze Error Types**
   - Kotlin compile errors → Fix type/null safety issues
   - Dependency errors → Update build.gradle.kts
   - ktlint violations → Run `./gradlew ktlintFormat`
   - Configuration errors → Fix gradle config files

3. **Apply Minimal Fixes**
   - Fix ONE error at a time
   - Verify each fix with `./gradlew compileKotlin`
   - Track progress

4. **Run ktlint Format**
   ```bash
   ./gradlew ktlintFormat
   ```

5. **Verify Full Build**
   ```bash
   ./gradlew build
   ```

## Error Priority

1. 🔴 **Compile Errors** - Fix first (blocks everything)
2. 🟡 **Dependency Issues** - Fix missing/conflicting deps
3. 🟢 **ktlint Violations** - Auto-fix with ktlintFormat
4. ⚪ **Warnings** - Address if time permits

## Common Fixes

| Error Type | Quick Fix |
|------------|-----------|
| Unresolved reference | Add import or dependency |
| Null safety | Add `?.` or `?:` or `!!` |
| Type mismatch | Convert type or fix annotation |
| kapt/ksp error | Check annotation processor config |
| JVM target mismatch | Align in kotlin {} block |

## Success Criteria

- `./gradlew build` completes without errors
- `./gradlew ktlintCheck` passes
- No new warnings introduced
- Minimal lines changed

## Report Format

After fixing, provide a summary:
- Total errors fixed
- Files modified
- Build status (PASSING/FAILING)
