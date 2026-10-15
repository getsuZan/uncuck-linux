## PLAN task (e.g. T2)

## What changed

## Regression proof
- [ ] New/updated `bats` test fails without the fix (mutation-checked)
- [ ] `bats tests/` green
- [ ] `shellcheck -S error` green, `shfmt` clean

## Safety
- [ ] All deletes via `safe_rm`
- [ ] Backup-before-mutate preserved
- [ ] `--dry-run` output attached for new behavior

## Docs
- [ ] `CHANGELOG.md` updated
