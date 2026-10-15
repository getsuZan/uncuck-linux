# unomarchy

Strip Omarchy, keep vanilla Hyprland + clean Arch. Preserve personal files.

`unomarchy.sh` detaches your system from the Omarchy pacman repo, restores stock
Arch mirrors, resets SDDM to a plain `hyprland` session, removes Omarchy
packages/configs (with your confirmation), and leaves you on a minimal working
Hyprland setup. Optionally it can then install a plain-dotfiles rice on top.

> **Warning:** this script deletes configs and removes packages. Always run
> `--dry-run` first, check the backup dir, and only then run for real.

## Requirements

- Arch Linux (`/etc/arch-release` must exist)
- An Omarchy install (`~/.local/share/omarchy` present, unless `--force`)
- Run as your user, **not** root (the script calls `sudo` itself when needed)
- `pacman`, `git`, `sudo`

## Quickstart

```bash
./unomarchy.sh --dry-run          # preview, no changes, no prompts hang
./unomarchy.sh --dry-run --yes    # preview with pinned defaults
./unomarchy.sh                    # interactive run
./unomarchy.sh --yes              # non-interactive, pinned defaults
```

Backups land in `~/unomarchy-backup-<timestamp>/` (override with
`--backup-dir`). Restore dotfiles with:

```bash
tar -xf ~/unomarchy-backup-<timestamp>/dotfiles.tar -C ~
```

## What it deletes vs keeps

Deletes (after backup + confirm):

- `[omarchy]` repo section in `/etc/pacman.conf`, omarchy pacman keys
- Omarchy packages: `omarchy-chromium omarchy-nvim omarchy-walker omarchy-keyring aether cliamp tobi-try usage`
- Optional groups you confirm: browsers/chat, media, office, docker, helpers (`walker elephant impala swayosd ...`), 1password/claude TUIs
- Omarchy configs: `~/.config/{hypr,waybar,walker,elephant,swayosd,uwsm,mako,omarchy}`, `~/.local/share/omarchy`, omarchy `.desktop` entries, `omarchy*` binaries
- SDDM omarchy session + theme, omarchy plymouth theme

Keeps (never touched):

- `~/Documents ~/Downloads ~/Pictures ~/Videos ~/Projects ~/Work ~/Wallpapers ~/Music ~/Desktop ~/.ssh ~/.gnupg`
- Vanilla core: `hyprland waybar sddm pipewire wireplumber iwd base git` etc. (`ALWAYS_KEEP` in code)

After stripping it writes a minimal `~/.config/hypr/hyprland.conf` skeleton (existing file kept).

## Flags

```
./unomarchy.sh [options]

  --dry-run                 preview only, no changes, never prompts
  --yes                     non-interactive, use pinned defaults
  --backup-dir=DIR          backup destination (also: --backup-dir DIR)
  --only-step=STEPS         comma list: preflight,backup,pacman,sddm,pkgs,configs,verify
  --force                   rerun allowed; bypass omarchy-presence check (vanilla Arch cleanup)
  --kb=LAYOUT               keyboard layout override (default: autodetect, fallback us)
  --term=TERM                terminal override for skeleton (default: first of kitty,alacritty,ghostty,foot)
  --no-reflector            skip reflector mirror refresh
  --import-rice URL         install plain-dotfiles rice after uninstall (T8)
  --rice-ref REF            pinned git ref for rice (required with --import-rice)
  --rice-dir DIR            rice checkout dir (default: ~/.local/share/rice)
  --rice-exec FILE          run one root-level rice .sh (explicit opt-in; --yes alone never runs scripts)
  --tui[=gum|whiptail|select]  lightweight TUI, toolkit priority gum > whiptail > bash select (T9)
  --version                 print version
  -h, --help                this help
```

## Rice import (T8, deferred)

```bash
./unomarchy.sh --import-rice https://github.com/you/rice --rice-ref v1.0.0
```

Rice = plain dotfiles dir + optional `packages.txt` (one `repo/pkg` per line).
Only allowlisted config dirs are copied; root-level `*.sh` triggers a
Run / Copy-only / Abort prompt (copy-only is the default; `--yes` never
auto-runs scripts).

## TUI (T9, deferred)

```bash
./unomarchy.sh --tui              # auto: gum > whiptail > select
./unomarchy.sh --tui=whiptail     # force backend
```

## Safety model

- All deletes go through `safe_rm` (canonicalizes with `realpath -m`, refuses `$HOME`, `~/.config`, personal dirs, symlinks escaping to them).
- Per-run log: `$BACKUP_DIR/unomarchy.log`; `pkg-list-before/after.txt` diff recorded.
- Idempotent: second run reports `already clean` instead of aborting (use `--force` on vanilla Arch).
- Tests: `bats tests/` — every known destructive bug has a regression test (see `PLAN.md` T2/T6).

## License

GPL-3.0 — see `LICENSE`.
