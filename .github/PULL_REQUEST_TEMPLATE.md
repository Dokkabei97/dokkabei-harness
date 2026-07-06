<!-- Thanks for contributing! Fill in the sections below. Delete any that don't apply. -->

## What & why

<!-- What does this change do, and what problem does it solve? Link related issues (e.g. Closes #12). -->

## Type of change

- [ ] New plugin (distinct domain — names the domain in "What & why")
- [ ] New / changed component (skill · command · agent) inside an existing plugin
- [ ] Hook / loop-engine change
- [ ] Docs / landing page / tooling
- [ ] Bug fix

## How verified

<!-- Show it works — don't just assert it. -->

- [ ] `bats tests/hooks` green locally
- [ ] `jq . plugins/*/hooks/hooks.json` clean
- [ ] `shellcheck --severity=error plugins/**/{hooks,bin}/**/*.sh` clean
- [ ] `/verify-flow` reports no Critical/High findings (for component changes)

```
# paste the relevant command output (bats summary, verify-flow score, …)
```

## Convention checklist

- [ ] Branched from `main` (not committing directly to `main`)
- [ ] Conventional Commit messages with a Korean body (`feat(scope): …`)
- [ ] If a hook changed, its `tests/hooks/*.bats` was updated in this PR
- [ ] If a plugin version changed, `plugin.json` **and** `marketplace.json` are synced
- [ ] Bilingual component descriptions (Korean original + English `Use when:` clause)
- [ ] Paired README updated if user-facing (`README.md` + `README_KO.md`)
