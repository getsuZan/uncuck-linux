# lib/safe.sh - logging, dry-run, confirm, safe_rm.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires: DRY_RUN, ASSUME_YES, LOG.
# GPL-3.0.

HOME_REAL="$(realpath -m -- "${HOME:?HOME is unset}")"

is_dry() { [[ "${DRY_RUN:-0}" -eq 1 ]]; }

log() { echo "[unomarchy] $*" | tee -a "$LOG"; }

log_dry() { echo "DRY: $*" | tee -a "$LOG"; }

# WARN/FAIL go to stderr (still recorded in $LOG). Plain log() stays stdout.
log_warn() { echo "[unomarchy] WARN: $*" | tee -a "$LOG" >&2; }

# Run a simple command (argv, no shell parsing). Preview under --dry-run.
run_cmd() {
  if is_dry; then
    log_dry "$*"
    return 0
  fi
  "$@"
}

confirm() {
  if is_dry; then
    log_dry "confirm: $1 -> yes (dry-run preview)"
    return 0
  fi
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
  local r
  read -rp "$1 [y/N] " r || return 1
  [[ "$r" =~ ^[Yy]$ ]]
}

# Guard: never delete personal data or system roots. Wrapper for all rm -rf.
# Canonicalizes with realpath -m so symlinks, .., // cannot escape the blocklist.
safe_rm() {
  local p canon
  for p in "$@"; do
    if [[ -z "${p:-}" ]]; then
      echo "REFUSED: empty path" >&2
      return 1
    fi
    canon="$(realpath -m -- "$p")" || {
      echo "REFUSED: cannot resolve $p" >&2
      return 1
    }
    case "$canon" in
    "$HOME_REAL" | "$HOME_REAL/.config" | "$HOME_REAL/.local" | "$HOME_REAL/.local/share" | /etc | /etc/* | /usr | /usr/*)
      echo "REFUSED: $p" >&2
      return 1
      ;;
    esac
    case "$canon" in
    "$HOME_REAL"/Documents* | "$HOME_REAL"/Downloads* | "$HOME_REAL"/Pictures* | "$HOME_REAL"/Videos* | "$HOME_REAL"/Projects* | "$HOME_REAL"/Work* | "$HOME_REAL"/Wallpapers* | "$HOME_REAL"/Music* | "$HOME_REAL"/Desktop* | "$HOME_REAL"/.ssh* | "$HOME_REAL"/.gnupg*)
      echo "REFUSED personal: $p" >&2
      return 1
      ;;
    esac
  done
  if is_dry; then
    log_dry "rm -rf $*"
    return 0
  fi
  rm -rf -- "$@"
}
