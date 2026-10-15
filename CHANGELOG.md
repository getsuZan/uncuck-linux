# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Rice import (`--import-rice URL --rice-ref REF [--rice-dir] [--rice-exec]`): clones pinned ref, records SHA in `$BACKUP_DIR/rice.log`, copies allowlisted entries (overwritten targets backed up to `$BACKUP_DIR/rice-prev/`), installs `packages.txt` in one pacman transaction, root-level `.sh` only via Run/Copy/Abort prompt (`--yes` = copy-only, `--rice-exec` opts in non-interactively), non-GitHub URLs need `--force`, `--dry-run` previews without cloning.
- `tests/test_rice.bats`: 7 tests (allowlist, hook opt-in, nested refusal, URL guard, dry-run purity, non-empty abort, bad-entry abort).

## [0.1.0] - 2026-10-15
### Added
- `lib/` split (`safe backup pacman sddm pkg config verify`) + thin dispatcher with `--only-step`, `--force` (vanilla-Arch leftover cleanup), `--kb/--term/--no-reflector`.
- Per-run log `$BACKUP_DIR/unomarchy.log` (`/dev/null` under `--dry-run`, zero disk writes), ERR trap.
- `tests/*.bats` regression suite (safe_rm escapes, tar-create backup, awk strip, bashrc set-e, CLI surface, dry-run determinism).
- CI (shellcheck + shfmt + bats + Arch container dry-run), issue/PR templates.
### Fixed
- Review audit: pacman strip uses `mktemp` + validates non-empty/header-bearing output before `mv` (never clobbers `/etc/pacman.conf` with broken output).
- Review audit: `.bashrc` and hyprland skeleton write tmp + `mv` (no in-place truncation); `$USER` falls back to `id -un` under `set -u`; `localectl` pipeline has `|| true` for non-systemd.
- Review audit: `.desktop`/wrapper-bin deletes go through `safe_rm` (+ prefix assert before `sudo rm`); `safe_rm` also denies `/etc/*`, `/usr/*` and hard-fails on unresolvable paths.
- Review audit: `read -r -a` everywhere, `read ... || return 1` on prompts, array-membership test replaces `" ${final[*]} "` string match, literal dots use `grep -Fq`/`grep -Eq`, WARN/FAIL lines go to stderr via `log_warn`, dry previews show exact `sudo` commands.
### Changed
- `--dry-run` never prompts (confirm auto-yes preview) and never writes disk.
- `handle_packages` word-splitting hardened, `ALWAYS_KEEP` filter intact.

## [0.1.0] - 2026-10-15
### Added
- T1 repo scaffold: LICENSE (GPL-3.0), README, CONTRIBUTING, CHANGELOG, VERSION.
- Full CLI flag surface documented in `--help` (`--dry-run --yes --backup-dir --only-step --force --kb --term --no-reflector --import-rice --rice-ref --rice-dir --rice-exec --tui --version`).
- Space and `=` forms for value flags (`--backup-dir DIR` and `--backup-dir=DIR`).
