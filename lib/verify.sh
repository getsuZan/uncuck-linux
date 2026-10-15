# lib/verify.sh - preflight guards + post-run verification.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.

preflight() {
  [[ -f /etc/arch-release ]] || {
    echo "not Arch, abort" >&2
    exit 1
  }
  [[ $EUID -ne 0 ]] || {
    echo "run as user, not root" >&2
    exit 1
  }
  if [[ ! -d "$HOME/.local/share/omarchy" && "${FORCE:-0}" -ne 1 ]]; then
    echo "no omarchy install found (use --force to clean leftovers on vanilla Arch)" >&2
    exit 1
  fi
  command -v pacman >/dev/null || {
    echo "pacman not found" >&2
    exit 1
  }
  if is_dry; then
    log_dry "mkdir -p $BACKUP_DIR; pacman -Qe > $BACKUP_DIR/pkg-list-before.txt"
  else
    mkdir -p "$BACKUP_DIR" || {
      echo "cannot create $BACKUP_DIR" >&2
      exit 1
    }
    pacman -Qe >"$BACKUP_DIR/pkg-list-before.txt"
  fi
  log "backup dir: $BACKUP_DIR"
  if pgrep -x Hyprland >/dev/null; then
    log_warn "running inside Hyprland. TTY (Ctrl+Alt+F3) recommended."
    confirm "Continue anyway?" || exit 1
  fi
}

verify() {
  log "verify"
  if command -v omarchy >/dev/null; then log_warn "omarchy still on PATH"; fi
  if grep -q "^\[omarchy\]" /etc/pacman.conf; then
    log_warn "FAIL: [omarchy] still in pacman.conf"
  else
    log "OK: pacman.conf clean"
  fi
  if grep -Eq 'pkgs\.omarchy\.org|stable-mirror\.omarchy\.org' /etc/pacman.d/mirrorlist; then
    log_warn "mirrorlist still references omarchy"
  else
    log "OK: mirrorlist detached"
  fi
  if grep -rq "^Session=hyprland$" /etc/sddm.conf.d/ /etc/sddm.conf 2>/dev/null; then
    log "OK: sddm Session=hyprland"
  else
    log_warn "FAIL: sddm session"
  fi
  if [[ ! -e /usr/local/share/wayland-sessions/omarchy.desktop ]]; then
    log "OK: omarchy session gone"
  else
    log_warn "FAIL: omarchy.desktop remains"
  fi
  if is_dry; then
    log_dry "pacman -Qe > $BACKUP_DIR/pkg-list-after.txt"
  else
    pacman -Qe >"$BACKUP_DIR/pkg-list-after.txt"
  fi
  log "before/after diff: diff $BACKUP_DIR/pkg-list-before.txt $BACKUP_DIR/pkg-list-after.txt"
  log "personal dirs untouched:"
  local d
  for d in ~/Documents ~/Pictures ~/Projects; do
    if [[ -d "$d" ]]; then
      if is_dry; then log_dry "ls $d"; else ls "$d" 2>&1 | tee -a "$LOG"; fi
    else
      log "missing $d (ok)"
    fi
  done
  log "reboot required. restore: tar -xf $BACKUP_DIR/dotfiles.tar -C ~"
}
