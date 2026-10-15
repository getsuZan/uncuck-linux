# Contributing to unomarchy

Thanks for helping de-Omarchify safely.

## Ground rules

- **Safety first.** Every delete path must go through `safe_rm`. Every destructive step must work under `--dry-run` with zero side effects.
- **Backup before mutate.** No step may overwrite user config without backing it up to `$BACKUP_DIR` first.
- **Personal dirs are sacred.** `~/Documents ~/Downloads ~/Pictures ~/Videos ~/Projects ~/Work ~/Wallpapers ~/Music ~/Desktop ~/.ssh ~/.gnupg` must never be deleted. `safe_rm` refuses them; add a regression test if you touch that code.
- **Deterministic by default.** New behavior must be reproducible: pin refs, log choices, mock network in tests.

## Workflow

1. Pick a task from `PLAN.md` (T1→T9 in order).
2. Add or update `bats` tests in `tests/` first (red), then implement (green).
3. Run before pushing:
   - `bats tests/`
   - `shellcheck -S error unomarchy.sh lib/*.sh tests/helper.bash tests/*.bats`
   - `shfmt -d -i 2 unomarchy.sh lib/*.sh tests/helper.bash tests/*.bats` (2-space indent is the project setting)
   - `./unomarchy.sh --dry-run --help` smoke test
4. One concern per commit, message like `fix: ...`, `feat: ...`, `test: ...`, `chore: ...`.

## What a good PR looks like

- References the PLAN task (e.g. `T2: safe_rm symlink escape`).
- Includes regression test that fails without the fix (mutation-proven).
- Updates `CHANGELOG.md` under `[Unreleased]`.
- No secrets, no tokens, no personal paths in diffs.
