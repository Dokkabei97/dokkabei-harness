# Maintenance and Automation -- Inverted Index Guide

Scripts, CI checks, and processes to keep the CLAUDE.md inverted index accurate over time.
The hybrid approach is recommended: auto-generate paths, manually curate descriptions.

## Auto-Generation Scripts by Build System

### Gradle (Kotlin/Java)

```bash
#!/bin/bash
# generate-claude-index-gradle.sh
# Extracts module structure from settings.gradle.kts

echo "## Module Structure (auto-generated $(date +%Y-%m-%d))"
echo ""

SETTINGS="settings.gradle.kts"
if [ ! -f "$SETTINGS" ]; then
  echo "Error: $SETTINGS not found" >&2
  exit 1
fi

grep 'include(' "$SETTINGS" | sed 's/include("//;s/")//' | sort | while read -r module; do
  echo "### $module"
  src="$module/src/main/kotlin"
  if [ -d "$src" ]; then
    # Show package directories (2 levels deep from source root)
    find "$src" -mindepth 3 -maxdepth 5 -type d | \
      sed "s|$src/||" | sort | sed 's/^/- /'
  fi
  echo ""
done
```

### uv / pip (Python)

```bash
#!/bin/bash
# generate-claude-index-python.sh
# Extracts package structure from uv workspace

echo "## Package Structure (auto-generated $(date +%Y-%m-%d))"
echo ""

for pkg_toml in packages/*/pyproject.toml; do
  pkg_dir=$(dirname "$pkg_toml")
  pkg_name=$(basename "$pkg_dir")
  src_dir="$pkg_dir/src/$pkg_name"

  echo "### $pkg_name"
  if [ -d "$src_dir" ]; then
    find "$src_dir" -type d -maxdepth 2 | tail -n +2 | \
      sed "s|$src_dir/||" | sort | sed 's/^/- /'
  fi
  echo ""
done
```

### pnpm / Turborepo (TypeScript)

```bash
#!/bin/bash
# generate-claude-index-pnpm.sh
# Extracts workspace package structure

echo "## Workspace Packages (auto-generated $(date +%Y-%m-%d))"
echo ""

# Parse pnpm-workspace.yaml
for pkg in $(cat pnpm-workspace.yaml | grep "  - " | sed 's/  - //'); do
  # Expand glob patterns
  for dir in $pkg; do
    if [ -f "$dir/package.json" ]; then
      name=$(node -e "console.log(require('./$dir/package.json').name)")
      echo "### $name ($dir)"
      if [ -d "$dir/src" ]; then
        find "$dir/src" -type d -maxdepth 2 | tail -n +2 | \
          sed "s|$dir/src/||" | sort | sed 's/^/- /'
      fi
      echo ""
    fi
  done
done
```

### Cargo (Rust)

```bash
#!/bin/bash
# generate-claude-index-cargo.sh
# Extracts crate structure from Cargo workspace

echo "## Crate Structure (auto-generated $(date +%Y-%m-%d))"
echo ""

cargo metadata --no-deps --format-version 1 2>/dev/null | \
  jq -r '.packages[] | "\(.name) \(.manifest_path)"' | \
  while read -r name manifest; do
    crate_dir=$(dirname "$manifest")
    rel_dir=${crate_dir#$(pwd)/}
    echo "### $name ($rel_dir)"
    if [ -d "$crate_dir/src" ]; then
      find "$crate_dir/src" -name "*.rs" -maxdepth 2 | \
        sed "s|$crate_dir/src/||" | sort | sed 's/^/- /'
    fi
    echo ""
  done
```

### Go modules

```bash
#!/bin/bash
# generate-claude-index-go.sh
# Extracts package structure from Go project

echo "## Package Structure (auto-generated $(date +%Y-%m-%d))"
echo ""

MODULE=$(head -1 go.mod | awk '{print $2}')
echo "Module: $MODULE"
echo ""

# List internal packages
echo "### internal/"
go list ./internal/... 2>/dev/null | sed "s|$MODULE/||" | sort | sed 's/^/- /'
echo ""

# List cmd entry points
echo "### Entry Points (cmd/)"
find cmd -name main.go -type f 2>/dev/null | sort | sed 's/^/- /'
echo ""

# List interfaces
echo "### Interfaces (internal/port/)"
grep -rn "type .* interface" internal/port/ 2>/dev/null | \
  sed 's/.*type //;s/ interface.*//' | sort | sed 's/^/- /'
```

## Technology Scanning via Annotations/Decorators

Scan for technology usage based on language-specific markers:

```bash
#!/bin/bash
# scan-tech-usage.sh
# Detects technology usage from annotations, decorators, and imports

echo "## Technology Usage (auto-scanned $(date +%Y-%m-%d))"
echo ""

# Kotlin/Java: Spring annotations
echo "### Kafka"
echo "Consumers:"
grep -rl "@KafkaListener" --include="*.kt" --include="*.java" | sed 's/^/  - /'
echo "Producers:"
grep -rl "KafkaTemplate" --include="*.kt" --include="*.java" | sed 's/^/  - /'

echo ""
echo "### JPA"
echo "Entities:"
grep -rl "@Entity" --include="*.kt" --include="*.java" | sed 's/^/  - /'
echo "Repositories:"
grep -rl "JpaRepository\|CrudRepository" --include="*.kt" --include="*.java" | sed 's/^/  - /'

echo ""
echo "### Redis"
grep -rl "@Cacheable\|RedisTemplate\|ReactiveRedisTemplate" --include="*.kt" --include="*.java" | sed 's/^/  - /'

echo ""
echo "### gRPC"
grep -rl "GrpcService\|@GrpcClient" --include="*.kt" --include="*.java" | sed 's/^/  - /'

# Python: decorators and imports
echo ""
echo "### FastAPI Routes"
grep -rl "@router\.\|@app\." --include="*.py" | sed 's/^/  - /'

echo ""
echo "### SQLAlchemy Models"
grep -rl "class.*Base\)\|DeclarativeBase" --include="*.py" | sed 's/^/  - /'

echo ""
echo "### Celery Tasks"
grep -rl "@celery_app.task\|@shared_task" --include="*.py" | sed 's/^/  - /'

# TypeScript: decorators and imports
echo ""
echo "### NestJS Controllers"
grep -rl "@Controller\|@Injectable" --include="*.ts" | sed 's/^/  - /'
```

## Pre-commit Hook for Path Validation

Validates that all paths referenced in CLAUDE.md and `.claude/rules/*.md` actually exist:

```bash
#!/bin/bash
# .git/hooks/pre-commit (or .husky/pre-commit)
# Validates paths in CLAUDE.md and .claude/rules/*.md still exist

CACHED_FILES=$(git diff --cached --name-only)

# Check if CLAUDE.md or any .claude/rules/*.md is being committed
TARGETS=""
if echo "$CACHED_FILES" | grep -q "CLAUDE.md"; then
  TARGETS="CLAUDE.md"
fi
for rule_file in $(echo "$CACHED_FILES" | grep -E '^\.claude/rules/.*\.md$'); do
  TARGETS="$TARGETS $rule_file"
done

if [ -z "$TARGETS" ]; then
  exit 0  # No relevant files being committed, skip
fi

echo "Validating paths in: $TARGETS"
errors=0

for target in $TARGETS; do
  # Extract paths (lines containing / that look like file paths)
  grep -oE '[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.*{}-]+)+/?' "$target" | \
    grep -v 'http' | \
    grep -v 'node_modules' | \
    sort -u | while read -r path; do
      # Strip trailing wildcard or glob
      clean_path=$(echo "$path" | sed 's/\*.*//;s/{.*//;s/\.\.\.$//')
      if [ -n "$clean_path" ] && [ ! -e "$clean_path" ]; then
        echo "  WARNING: Path not found in $target: $path"
        errors=$((errors + 1))
      fi
    done
done

if [ $errors -gt 0 ]; then
  echo "Found $errors broken paths in CLAUDE.md / .claude/rules/*.md"
  echo "Update paths or use 'git commit --no-verify' to skip"
  exit 1
fi

echo "All paths validated (CLAUDE.md + .claude/rules/*.md)."
```

## CI Workflow for Freshness Check

```yaml
# .github/workflows/claude-md-check.yml
name: CLAUDE.md Freshness Check

on:
  pull_request:
    paths-ignore:
      - 'CLAUDE.md'
      - '.claude/**'

jobs:
  check-freshness:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check if CLAUDE.md or rules need update
        run: |
          # Get list of changed files
          CHANGED=$(git diff --name-only origin/main...HEAD)

          # Check if structural changes occurred
          STRUCTURAL_CHANGES=false

          # New modules/packages added?
          if echo "$CHANGED" | grep -qE 'settings\.gradle\.kts|Cargo\.toml|pyproject\.toml|package\.json'; then
            STRUCTURAL_CHANGES=true
          fi

          # New directories created in key locations?
          for dir in src/modules src/app packages/ crates/ services/ internal/; do
            if echo "$CHANGED" | grep -q "^$dir.*/" ; then
              STRUCTURAL_CHANGES=true
            fi
          done

          if [ "$STRUCTURAL_CHANGES" = true ]; then
            # Check if CLAUDE.md or .claude/rules/ was also updated
            if ! echo "$CHANGED" | grep -qE 'CLAUDE\.md|\.claude/rules/'; then
              echo "::warning::Structural changes detected but CLAUDE.md and .claude/rules/ were not updated."
              echo "Consider updating the inverted index in CLAUDE.md and relevant .claude/rules/*.md files."
              # Use warning, not error -- non-blocking
            fi
          fi

      - name: Validate paths in CLAUDE.md and .claude/rules/
        run: |
          # Collect all target files
          TARGETS=""
          if [ -f CLAUDE.md ]; then
            TARGETS="CLAUDE.md"
          fi
          for rule_file in .claude/rules/*.md; do
            if [ -f "$rule_file" ]; then
              TARGETS="$TARGETS $rule_file"
            fi
          done

          errors=0
          for target in $TARGETS; do
            grep -oE '[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.*{}-]+)+/?' "$target" | \
              grep -v 'http' | grep -v 'node_modules' | \
              sort -u | while read -r path; do
                clean=$(echo "$path" | sed 's/\*.*//;s/{.*//;s/\.\.\.$//')
                if [ -n "$clean" ] && [ ! -e "$clean" ]; then
                  echo "::warning::Broken path in $target: $path"
                  errors=$((errors + 1))
                fi
              done
          done
```

## Hybrid Approach: Auto-Generate Paths + Manual Descriptions

The recommended workflow combines automation with human/agent curation.
Scripts update both the Root CLAUDE.md (project-wide index) and `.claude/rules/*.md` (context-specific rules):

```
1. Run auto-generation script -> raw paths extracted
2. Agent or human adds descriptions and groups by technology
3. Script updates Root CLAUDE.md (top-level structure & tech map)
4. Script generates .claude/rules/*.md (domain-specific rules per module/layer)

Workflow:
  make generate-index   # Step 1: raw extraction -> Root CLAUDE.md
  make generate-rules   # Step 2: generate .claude/rules/*.md per module
  # Human/agent review  # Step 3: curate descriptions in both locations
  make validate-index   # Step 4: verify all paths exist
```

Sample Makefile targets:

```makefile
.PHONY: generate-index generate-rules validate-index

generate-index:
	@bash scripts/generate-claude-index.sh > .claude/generated-index.md
	@echo "Generated raw index at .claude/generated-index.md"
	@echo "Review and merge relevant changes into CLAUDE.md"

generate-rules:
	@mkdir -p .claude/rules
	@bash scripts/generate-claude-rules.sh
	@echo "Generated rule files in .claude/rules/"
	@echo "Review: ls .claude/rules/*.md"

validate-index:
	@bash scripts/validate-claude-paths.sh CLAUDE.md
	@bash scripts/validate-claude-paths.sh .claude/rules/*.md
	@echo "Validated paths in CLAUDE.md and .claude/rules/*.md"
```

## CODEOWNERS for CLAUDE.md

Ensure CLAUDE.md changes are reviewed by the right people:

```
# .github/CODEOWNERS
CLAUDE.md                @team-lead @platform-team
.claude/                 @team-lead @platform-team
**/CLAUDE.md             @team-lead
```

## PR Template Checklist

Add to `.github/pull_request_template.md`:

```markdown
## CLAUDE.md Impact

- [ ] No structural changes (skip remaining checks)
- [ ] New module/package added -- CLAUDE.md updated
- [ ] Technology added/removed -- Tech Map updated
- [ ] New entry point added -- Entry Points updated
- [ ] New generated files -- DO NOT MODIFY list updated
- [ ] Path aliases changed -- Alias table updated
- [ ] Ran `make validate-index` -- all paths valid
```

## Staleness Risk by Granularity Level

Different granularity levels go stale at different rates. Choose your level wisely:

```
Granularity Level      | Staleness Risk | Update Frequency | Recommendation
-----------------------|----------------|------------------|-----------------
Module names           | Very Low       | Quarterly        | Always include
Package/directory paths| Low            | Monthly          | Always include
Config file names      | Low            | Monthly          | Include (few files)
Technology groupings   | Low            | Quarterly        | Always include
Port/Interface names   | Medium         | Bi-weekly        | Include if stable
Entry point files      | Medium         | Monthly          | Always include
Individual class files | High           | Weekly           | Avoid
Test file names        | Very High      | Daily            | Never include
DTO/VO class names     | Very High      | Daily            | Never include
```

Rule of thumb: If a path changes more than once per sprint, it is too granular for the index.

## Semantic Staleness Detection

Path existence checks only catch deleted paths. Semantic staleness -- where paths exist but
no longer represent the mapped concept -- requires deeper detection.

### Review Freshness Check

Validates `last_reviewed` metadata in `.claude/rules/*.md` frontmatter:

```bash
#!/bin/bash
# check-review-freshness.sh
# Warns when rule files haven't been reviewed within their staleness window

for rule_file in .claude/rules/*.md; do
  [ -f "$rule_file" ] || continue

  reviewed=$(grep 'last_reviewed:' "$rule_file" | sed 's/.*: *"//;s/"//')
  window=$(grep 'staleness_window:' "$rule_file" | sed 's/.*: *//')
  owner=$(grep 'owner:' "$rule_file" | sed 's/.*: *"//;s/"//')

  # Default staleness window: 90 days
  window=${window:-90}

  if [ -n "$reviewed" ]; then
    reviewed_ts=$(date -j -f "%Y-%m-%d" "$reviewed" +%s 2>/dev/null || \
                  date -d "$reviewed" +%s 2>/dev/null)
    today_ts=$(date +%s)
    days=$(( (today_ts - reviewed_ts) / 86400 ))

    if [ "$days" -gt "$window" ]; then
      echo "::warning::$rule_file last reviewed $days days ago (limit: ${window}d, owner: ${owner:-unassigned})"
    fi
  else
    echo "::warning::$rule_file has no last_reviewed metadata"
  fi
done
```

### Technology Marker Drift Detection

Detects when technology-specific annotations/decorators appear OUTSIDE indexed paths,
indicating the index may be stale:

```bash
#!/bin/bash
# detect-semantic-drift.sh
# Run in CI on PRs to catch technology markers migrating outside indexed paths

CHANGED=$(git diff --name-only origin/main...HEAD)
DRIFT_FOUND=false

# Define: technology marker -> expected indexed path pattern
# Format: "MARKER_REGEX|INDEXED_PATH_PATTERN|RULE_FILE"
TECH_MARKERS=(
  "@KafkaListener|KafkaTemplate|inbound-consumer|outbound-event|kafka.md"
  "@Entity|JpaRepository|CrudRepository|outbound-persistence|jpa.md"
  "@Cacheable|RedisTemplate|ReactiveRedisTemplate|outbound-cache|redis.md"
  "@GrpcService|@GrpcClient|outbound-client|grpc.md"
  "@Controller|@RequestMapping|inbound-api|api.md"
  "@router\\.|@app\\.|src/app|routes.md"
  "class.*Base\\)|DeclarativeBase|models|db.md"
)

for entry in "${TECH_MARKERS[@]}"; do
  IFS='|' read -r marker indexed rule <<< "$entry"

  # Find changed files with this marker that are OUTSIDE the indexed path
  outside=$(echo "$CHANGED" | grep -v -E "$indexed" | \
    xargs grep -l "$marker" 2>/dev/null)

  if [ -n "$outside" ]; then
    DRIFT_FOUND=true
    echo "::warning::Tech marker '$marker' found OUTSIDE indexed path '$indexed':"
    echo "$outside" | sed 's/^/  - /'
    echo "  → Consider updating .claude/rules/$rule"
  fi
done

if [ "$DRIFT_FOUND" = false ]; then
  echo "No semantic drift detected."
fi
```

### Mass Change Detection in Indexed Paths

Warns when many files change within an indexed path, suggesting structural refactoring:

```bash
#!/bin/bash
# detect-mass-changes.sh
# Warns when indexed paths have unusually high churn in a PR

CHANGED=$(git diff --name-only origin/main...HEAD)
THRESHOLD=10

for rule_file in .claude/rules/*.md; do
  [ -f "$rule_file" ] || continue

  # Extract path patterns from frontmatter
  patterns=$(sed -n '/^paths:/,/^[^- ]/p' "$rule_file" | \
    grep -oE '"[^"]*"' | tr -d '"' | sed 's/\*\*\///')

  for pattern in $patterns; do
    clean=$(echo "$pattern" | sed 's/\*\*//g;s/\*//g')
    [ -z "$clean" ] && continue

    count=$(echo "$CHANGED" | grep -c "$clean" 2>/dev/null)
    if [ "$count" -gt "$THRESHOLD" ]; then
      echo "::warning::$rule_file: $count files changed matching '$clean' (threshold: $THRESHOLD)"
      echo "  → High churn may indicate structural refactoring. Review index freshness."
    fi
  done
done
```

### Agent Self-Verification Template

Add this section to any `.claude/rules/*.md` file to enable runtime staleness detection:

```markdown
## Self-Verification

When you arrive at an indexed path from the inverted index:
1. Confirm the actual business logic exists at this location
2. If you find only a thin wrapper, delegate, or deprecated code:
   - Search for the real implementation location
   - Complete your task using the correct location
   - After task completion, suggest updating the relevant index entry
3. If the path is accurate, proceed normally -- no extra verification needed
```

### CI Workflow for Semantic Staleness

Add these steps to the existing `.github/workflows/claude-md-check.yml`:

```yaml
      - name: Check review freshness
        run: bash scripts/check-review-freshness.sh

      - name: Detect technology marker drift
        run: bash scripts/detect-semantic-drift.sh

      - name: Detect mass changes in indexed paths
        run: bash scripts/detect-mass-changes.sh
```

## Recommended Maintenance Cadence

```
Weekly:   Run validate-index (CI does this on every PR)
          - Covers both CLAUDE.md and .claude/rules/*.md paths
          - Includes semantic drift detection on changed files
Monthly:  Run generate-index + generate-rules, diff with current files, update if needed
          - CLAUDE.md: top-level structure and tech map
          - .claude/rules/*.md: domain-specific rules per module/layer
          - Update last_reviewed timestamps on reviewed rule files
Quarter:  Review technology groupings, add new techs, remove deprecated ones
          - Audit .claude/rules/ for orphaned rules (deleted modules)
          - Verify rule file naming conventions remain consistent
          - Full semantic review: run detect-semantic-drift.sh across entire codebase
On Event: New module/service added -> update CLAUDE.md + create .claude/rules/<module>.md
On Event: Major refactor -> regenerate entire index and all rules
On Event: Technology migration (e.g., Redis → Memcached) -> update rule file + owner review
```
