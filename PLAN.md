# Unomarchy — Open-Source Readiness Plan

Goal: make `unomarchy.sh` trusted, modular, deterministic, safe for strangers to run to "unomarchyfy" an Omarchy box back to vanilla Hyprland + stock Arch.

Current state: single `unomarchy.sh` (285 lines, 7 functions: `preflight, do_backup, restore_pacman, restore_sddm, handle_packages, strip_configs, verify`). Functional prototype, not yet trustworthy for other users.

Decisions: `LICENSE` = GPL-3.0, test runner = `bats`.

How to use this doc: implement T1 → T9 in order. Each task lists actions plus verifiable tests. A task is done only when all its checks pass.

---

## T1 — Repo scaffold

Actions:
- Add `LICENSE` (GPL-3.0), `README.md`, `CONTRIBUTING.md`, `.gitignore`, `CHANGELOG.md`, `VERSION`.
- Fix `-h/--help` to document all flags: `--dry-run --yes --backup-dir=DIR --only-step= --force --version --import-rice --rice-ref --rice-exec --tui`.
- Support both `--backup-dir=DIR` and `--backup-dir DIR` forms.
- README must contain: what it does, what it deletes vs keeps, backup/restore procedure, quickstart (`--dry-run` first), requirements (Arch, Omarchy present, run as user not root).

Verifiable tests:
- [ ] `ls LICENSE README.md CONTRIBUTING.md .gitignore CHANGELOG.md VERSION` — all exist.
- [ ] `./unomarchy.sh --help` prints all flags including `--only-step`, `--force`, `--version`.
- [ ] `./unomarchy.sh --backup-dir /tmp/b1 --dry-run --help` and `./unomarchy.sh --backup-dir=/tmp/b1 --dry-run` both accepted (no `unknown arg`).
- [ ] `shellcheck` reports no errors on help/arg-parsing code.

## T2 — Safety hardening (trust)

Bugs to fix (refs to current `unomarchy.sh`):
- `unomarchy.sh:72` — `tar -rf` on missing archive fails, backup ends up empty. Fix: create with `tar -cf` if archive missing, then append; fail loudly if backup empty.
- `unomarchy.sh:87` — awk `/^\\[omarchy\\]/` double-escaped, strip misses. Fix: single backslash in awk source, no `eval` mangling.
- `unomarchy.sh:216` — `grep -v ... > .bashrc` + `set -e` aborts when result empty. Fix: append `|| true` handling or use `grep -v ... || test $? -eq 1`.
- `unomarchy.sh:266` — `grep -q ... /etc/sddm.conf.d/` without `-r` false-FAILs on directory. Fix: `grep -rq`.
- `unomarchy.sh:22` — `run() eval` quoting/injection fragile. Fix: drop `eval`, use arrays / `bash -c` with proper quoting or direct function calls.
- `unomarchy.sh:31` — `safe_rm` bypass via symlink / `..` / `//` / trailing variants; personal list incomplete. Fix: canonicalize with `realpath -m`, blocklist + allowlist, resolve symlinks before delete.
- Order bug: SDDM config patched then `pacman -S sddm` reinstalls over it. Fix: reinstall first, then patch, then verify.

Verifiable tests (each maps to `tests/` in T6):
- [ ] Backup: delete `dotfiles.tar`, run backup on fixture HOME, `tar -tf dotfiles.tar` lists every expected item; empty-backup case exits non-zero.
- [ ] Pacman strip: fixture `pacman.conf` containing `[omarchy]` section, run strip, `grep -c "^\[omarchy\]"` returns 0 and other sections intact.
- [ ] Bashrc: fixture with only the omarchy line, script exits 0 and `.bashrc` does not abort the run.
- [ ] Verify SDDM: fixture `sddm.conf.d/` with `Session=hyprland`, `verify` logs `OK: sddm Session=hyprland` (not FAIL).
- [ ] `safe_rm`: attempts against `$HOME`, `$HOME/`, `$HOME/.config`, `$HOME/Documents/x`, symlink pointing at `$HOME`, path containing `..` → all print `REFUSED`, exit 1, nothing deleted.
- [ ] `shellcheck -S error unomarchy.sh lib/*.sh` passes; `grep -rn "eval " --include="*.sh" .` returns nothing.

## T3 — Modularity + idempotency

Actions:
- Split into `lib/safe.sh lib/backup.sh lib/pacman.sh lib/sddm.sh lib/pkg.sh lib/config.sh`, thin `unomarchy.sh` dispatcher with `main()`.
- Add `--only-step=preflight,backup,pacman,sddm,pkgs,configs,verify` and `--force` (rerun allowed after strip; second run reports `already clean` instead of aborting in `preflight`). `--force` also bypasses the `~/.local/share/omarchy` presence check so the script can run on vanilla Arch to clean leftovers — it skips only that one guard, all deletes still go via `safe_rm` with backup + log.
- `confirm` auto-skips under `--dry-run` (log intent, do not prompt) unless `--yes` given.
- Per-run log: `LOG="$BACKUP_DIR/unomarchy.log"` plus `trap` on ERR recording failing command.

Verifiable tests:
- [ ] `find lib -name "*.sh" | wc -l` >= 5; `unomarchy.sh` sources them, no duplicated function bodies.
- [ ] `./unomarchy.sh --dry-run --only-step=verify` runs only verify (log proves other steps skipped), no filesystem change (`git status --porcelain` clean on fixtures / `find` mtime unchanged).
- [ ] Run twice with `--force` on fixture: second exit 0, log contains `already clean`.
- [ ] Vanilla fixture without `~/.local/share/omarchy`: without `--force` exits 1 (`no omarchy install found`); with `--force` exits 0 and removes only omarchy-tagged bits.
- [ ] `--dry-run` never prompts: `timeout 10 ./unomarchy.sh --dry-run < /dev/null` exits without hanging on `read`.

## T4 — Determinism

Actions:
- `--yes` (or `--yes=Y/N` semantics) implies zero prompts with pinned defaults; document defaults per package group.
- Add `--kb=` and `--term=` overrides; `localectl` / terminal autodetect becomes fallback only; log chosen values.
- Add `--no-reflector` flag; when reflector runs, record chosen mirrors + args in `$BACKUP_DIR`; default mirror path deterministic in `--dry-run`.
- No network / no `reflector --sort rate` variance in tests (mock it).

Verifiable tests:
- [ ] `printf 'n\n' | ./unomarchy.sh --dry-run` output equals `./unomarchy.sh --dry-run --yes=N` output (modulo timestamps).
- [ ] `--kb=us --term=kitty --dry-run` skeleton contains `kb_layout = us` and `exec,kitty`.
- [ ] Two consecutive `--dry-run` runs produce identical output after normalizing timestamps (`diff <(run1 | sed timestamps) <(run2 | sed timestamps)` empty).

## T5 — Backup / restore + logging

Actions:
- Backup set: hypr/waybar/walker/omarchy/mako/swayosd/uwsm/elephant/starship/terminals/btop/fastfetch/lazygit/mimeapps/nvim/bashrc/XCompose/profile + `/etc/pacman.conf`, `mirrorlist`, `sddm.conf.d/`, `limine.conf` (best-effort).
- Save `pkg-list-before.txt` / `pkg-list-after.txt` + unified diff in log; document restore as `tar -xf $BACKUP_DIR/dotfiles.tar -C ~`.
- `cp` of `/etc/*` and `/boot/*` must handle permission via `sudo cat` or pre-check readability; never silently skip without log WARN.

Verifiable tests:
- [ ] After full `--dry-run`-off fixture run: `ls $BACKUP_DIR/dotfiles.tar pkg-list-before.txt unomarchy.log` all exist; `tar -tf dotfiles.tar` non-empty.
- [ ] `pkg-list-before.txt` vs `pkg-list-after.txt` diff logged and non-empty when packages removed.
- [ ] Restore drill on temp HOME: `tar -xf dotfiles.tar -C $TMPHOME` restores byte-identical dotfiles (`diff -r` clean).
- [ ] Unreadable-source simulation (chmod 000 fixture): script logs WARN, does not abort silently.

## T6 — Test suite

Actions:
- Add `tests/` using `bats`: unit tests `safe_rm`, arg parsing, awk strip fixture, tar create/append, sddm patch fixture, verify fixture; integration test: Arch container (`docker run archlinux`) executing `--dry-run --yes`.
- Enforce `shellcheck` + `shfmt -d` in test run. Every T2 bug gets a named regression test (e.g. `test_safe_rm_refuses_home`, `test_pacman_strip`, `test_tar_creates_archive`, `test_verify_sddm_recursive`).

Verifiable tests:
- [ ] `bats tests/` — all green (output `N passed, 0 failed`).
- [ ] `shellcheck unomarchy.sh lib/*.sh` — green.
- [ ] `shfmt -d unomarchy.sh lib/*.sh tests/` — empty diff.
- [ ] Mutation check: reintroduce each T2 bug on a branch → corresponding test fails (proves regression coverage).

## T7 — CI + release

Actions:
- `git init` (if needed), `.github/workflows/ci.yml` running shellcheck + bats + containerized `--dry-run`.
- Add issue/PR templates. Tag `v0.1.0`. README quickstart + demo (optional asciinema).
- Publish via `gh repo create unomarchy` (public), push, open release notes.

Verifiable tests:
- [ ] `gh workflow view` / Actions tab green on push.
- [ ] Fresh clone in temp dir + `./unomarchy.sh --dry-run --help` works with no extra setup.
- [ ] `git log --oneline -5` shows atomic commits per task (T1..T6), no secrets (`git log -p | grep -i "token\|secret\|password"` empty, `gitleaks` clean if available).

---

## T8 — Rice import via `--import-rice` (deferred, after T7 green)

Decisions: rice = plain dotfiles dir. Packages autoinstall only when `--import-rice` is passed. Root-level `*.sh` only — `scripts/*.sh` ignored + logged.

Actions:
- Flags: `--import-rice <git-url> --rice-ref <sha/tag, required> [--rice-dir DIR] [--rice-exec <file>]`.
- Flow (runs after `verify` clean): `git clone --depth 1 --rev-parse pinned ref` → record URL + resolved SHA in `$BACKUP_DIR/rice.log` → backup copy targets first → copy allowlisted dirs only (`hypr waybar walker mako kitty foot ghostty alacritty btop fastfetch nvim starship uwsm fontconfig`) → `pacman -S --needed` from `packages.txt` (one `repo/pkg` per line, pacman resolves deps; unknown entries abort with clear error) → `systemctl --user daemon-reload`.
- URL guard: `https://github.com/*` by default; non-GitHub needs `--force`. Refuse `..` / symlink escape out of `$HOME/.config`.
- `.sh` handling: if root-level `*.sh` present (`install.sh setup.sh bootstrap.sh` or any root `*.sh`), prompt `Rice ships script(s): [list]. [R]un script / [C]opy dotfiles+deps only (default) / [A]bort?`
  - `R`: print path + `sha256sum`, second confirm `Run <file>?`, log stdout/stderr to `$BACKUP_DIR/rice-exec.log`. Non-interactive `R` requires explicit `--rice-exec <file>` (file must be inside rice repo); `--yes` alone defaults to `C`.
  - `C`: ignore all `.sh`, copy + packages only.
  - `--dry-run`: never executes; shows script list + `head -20` + would-copy `diff -r` + would-install pkg list.
- Rollback: restore `dotfiles.tar -C ~`, log exact reverse steps.

Verifiable tests:
- [ ] `bats tests/test_rice.bats` green: fixture rice with dotfiles + `packages.txt` (mock `pacman`), assert allowlisted dirs copied, non-allowlisted skipped + logged.
- [ ] Missing `--rice-ref` exits non-zero (`ref required for determinism`).
- [ ] Rice with root `install.sh`: interactive fixture picks `C` → script not executed, marker file absent; with `--rice-exec install.sh` → executed, output in `rice-exec.log`.
- [ ] `scripts/nested.sh` in fixture ignored + logged (`nested script ignored` in log).
- [ ] `--dry-run --import-rice <fixture>` changes nothing (`git status --porcelain` / fixture `diff -r` clean) but prints diff + pkg list.
- [ ] Restore drill: after rice import on temp HOME, `tar -xf dotfiles.tar -C $TMPHOME` restores pre-rice state (`diff -r` clean).

## T9 — Lightweight TUI via `--tui` (deferred, after T8)

Actions:
- `--tui` wraps the same engine — no parallel logic path. Without the flag CLI behavior unchanged.
- Toolkit priority (inside `--tui` only): `gum` first if installed → else `whiptail` → else pure-bash `select` (no hard dependency, Arch ISO / minimal safe). Optional override `--tui=gum|whiptail|select`; bare `--tui` means auto-detect in that order.
- Screens: 1) preflight + backup confirm 2) package-group checkboxes (defaults = current N/Y) 3) sddm/pacman summary 4) rice URL + ref input; `.sh` found → Run/Copy/Abort radio 5) dry-run preview tail 6) final `Proceed?` + log path.
- Rules: `--tui` implies interactive (ignores `--yes` unless `--rice-exec` also given); every TUI choice logs equivalent CLI flags to `$BACKUP_DIR/tui-flags.log` for reproducibility; `ESC`/cancel aborts safely before any delete.

Verifiable tests:
- [ ] `bats` with mocked `gum`/`whiptail`: checkbox parsing maps to correct `--only-step` / package flags. Priority test: `gum` present → `gum` used; `gum` absent + `whiptail` present → `whiptail` used; neither → `select` fallback.
- [ ] `timeout 10 ./unomarchy.sh --tui < /dev/null` exits non-zero with no side effects (no delete, no backup dir mutation beyond log).
- [ ] Flag-equivalence: TUI selection sequence N produces identical engine call as documented CLI flags (`diff` of `tui-flags.log` vs expected).
- [ ] `shellcheck` clean on `lib/tui.sh`; `--help` documents `--tui`.

---

## Suggested commit order

1. `chore: scaffold repo docs and help` (T1)
2. `fix: backup, pacman strip, bashrc, verify, safe_rm, drop eval` (T2)
3. `refactor: split lib/, only-step, force, idempotency` (T3)
4. `feat: deterministic flags kb term no-reflector` (T4)
5. `feat: per-run logging and restore drill` (T5)
6. `test: bats suite + regression tests` (T6)
7. `ci: github actions + v0.1.0 release` (T7)
8. `feat: rice import --import-rice` (T8)
9. `feat: lightweight TUI --tui (gum>whiptail>select)` (T9)
