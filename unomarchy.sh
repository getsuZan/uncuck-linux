#!/usr/bin/env bash
# unomarchy.sh - strip Omarchy, keep vanilla Hyprland + clean Arch, preserve personal files.
# GPL-3.0. See LICENSE.
# Usage: ./unomarchy.sh [--dry-run] [--yes] [--backup-dir DIR] [--only-step STEPS] [--force]
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
BACKUP_DIR="$HOME/unomarchy-backup-$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/unomarchy.log"
ONLY_STEP=""
FORCE=0
KB_OVERRIDE=""
TERM_OVERRIDE=""
NO_REFLECTOR=0
IMPORT_RICE=""
RICE_REF=""
RICE_DIR="$HOME/.local/share/rice"
RICE_EXEC=""
TUI_MODE=""
TUI_BACKEND="auto"

print_help() {
  cat <<EOF
Usage: $0 [options]

  --dry-run                 preview only, no changes, never prompts
  --yes                     non-interactive, use pinned defaults
  --backup-dir=DIR          backup destination (also: --backup-dir DIR)
  --only-step=STEPS         comma list: preflight,backup,pacman,sddm,pkgs,configs,verify
  --force                   rerun allowed; bypass omarchy-presence check (vanilla Arch cleanup)
  --kb=LAYOUT               keyboard layout override (also: --kb LAYOUT)
  --term=TERM                terminal override for skeleton (also: --term TERM)
  --no-reflector            skip reflector mirror refresh
  --import-rice URL         install plain-dotfiles rice after uninstall (also: --import-rice=URL)
  --rice-ref REF            pinned git ref for rice (also: --rice-ref REF)
  --rice-dir DIR            rice checkout dir (default: ~/.local/share/rice)
  --rice-exec FILE          run one root-level rice .sh (explicit opt-in)
  --tui[=gum|whiptail|select]  lightweight TUI, toolkit priority gum > whiptail > bash select
  --version                 print version
  -h, --help                this help
EOF
}

print_version() {
  local vfile
  vfile="$(dirname "${BASH_SOURCE[0]}")/VERSION"
  if [[ -f "$vfile" ]]; then cat "$vfile"; else echo "0.1.0"; fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --yes)
    ASSUME_YES=1
    shift
    ;;
  --backup-dir=*)
    BACKUP_DIR="${1#*=}"
    shift
    ;;
  --backup-dir)
    BACKUP_DIR="${2:?--backup-dir needs a value}"
    shift 2
    ;;
  --only-step=*)
    ONLY_STEP="${1#*=}"
    shift
    ;;
  --only-step)
    ONLY_STEP="${2:?--only-step needs a value}"
    shift 2
    ;;
  --force)
    FORCE=1
    shift
    ;;
  --kb=*)
    KB_OVERRIDE="${1#*=}"
    shift
    ;;
  --kb)
    KB_OVERRIDE="${2:?--kb needs a value}"
    shift 2
    ;;
  --term=*)
    TERM_OVERRIDE="${1#*=}"
    shift
    ;;
  --term)
    TERM_OVERRIDE="${2:?--term needs a value}"
    shift 2
    ;;
  --no-reflector)
    NO_REFLECTOR=1
    shift
    ;;
  --import-rice=*)
    IMPORT_RICE="${1#*=}"
    shift
    ;;
  --import-rice)
    IMPORT_RICE="${2:?--import-rice needs a value}"
    shift 2
    ;;
  --rice-ref=*)
    RICE_REF="${1#*=}"
    shift
    ;;
  --rice-ref)
    RICE_REF="${2:?--rice-ref needs a value}"
    shift 2
    ;;
  --rice-dir=*)
    RICE_DIR="${1#*=}"
    shift
    ;;
  --rice-dir)
    RICE_DIR="${2:?--rice-dir needs a value}"
    shift 2
    ;;
  --rice-exec=*)
    RICE_EXEC="${1#*=}"
    shift
    ;;
  --rice-exec)
    RICE_EXEC="${2:?--rice-exec needs a value}"
    shift 2
    ;;
  --tui=*)
    TUI_MODE=1
    TUI_BACKEND="${1#*=}"
    shift
    ;;
  --tui)
    TUI_MODE=1
    if [[ "${2:-}" =~ ^(gum|whiptail|select)$ ]]; then
      TUI_BACKEND="$2"
      shift 2
    else shift; fi
    ;;
  --version)
    print_version
    exit 0
    ;;
  -h | --help)
    print_help
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "unknown arg: $1" >&2
    exit 1
    ;;
  esac
done

# Per-run log (T5). --dry-run never touches disk: logs go to stdout only.
if [[ $DRY_RUN -eq 1 ]]; then
  LOG="/dev/null"
else
  LOG="$BACKUP_DIR/unomarchy.log"
fi
trap 'echo "[unomarchy] ERROR at line $LINENO: $BASH_COMMAND" >> "${LOG:-/dev/null}" 2>/dev/null || true' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/safe.sh
source "$SCRIPT_DIR/lib/safe.sh"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"
# shellcheck source=lib/pacman.sh
source "$SCRIPT_DIR/lib/pacman.sh"
# shellcheck source=lib/sddm.sh
source "$SCRIPT_DIR/lib/sddm.sh"
# shellcheck source=lib/pkg.sh
source "$SCRIPT_DIR/lib/pkg.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"

case "$TUI_BACKEND" in
auto | gum | whiptail | select) ;;
*)
  echo "unknown --tui backend: $TUI_BACKEND (want gum|whiptail|select)" >&2
  exit 1
  ;;
esac

step_fn() {
  case "$1" in
  preflight) echo preflight ;;
  backup) echo do_backup ;;
  pacman) echo restore_pacman ;;
  sddm) echo restore_sddm ;;
  pkgs) echo handle_packages ;;
  configs) echo strip_configs ;;
  verify) echo verify ;;
  *)
    echo "unknown step: $1 (want preflight,backup,pacman,sddm,pkgs,configs,verify)" >&2
    exit 1
    ;;
  esac
}

main() {
  if [[ -n "$TUI_MODE" ]]; then
    echo "TUI not yet implemented (PLAN T9). Run without --tui." >&2
    exit 1
  fi
  if [[ -n "$IMPORT_RICE" ]]; then
    if [[ -z "$RICE_REF" ]]; then
      echo "--import-rice requires --rice-ref (pinned ref, PLAN T8)" >&2
      exit 1
    fi
    echo "rice import not yet implemented (PLAN T8). Uninstall steps still available without --import-rice." >&2
    exit 1
  fi
  local steps=(preflight backup pacman sddm pkgs configs verify)
  if [[ -n "$ONLY_STEP" ]]; then
    IFS=',' read -r -a steps <<<"$ONLY_STEP"
  fi
  # Non-dry subsets (e.g. --only-step=verify) still need a writable log dir.
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$BACKUP_DIR" || {
      echo "cannot create $BACKUP_DIR" >&2
      exit 1
    }
  fi
  local s fn
  for s in "${steps[@]}"; do
    fn=$(step_fn "$s")
    "$fn"
  done
}
main
