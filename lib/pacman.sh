# lib/pacman.sh - detach from omarchy repos, restore stock Arch mirrors.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.

# Awk program that drops the [omarchy] section up to the next [header].
# Single-quoted at use; single backslash escapes. Kept in a var so tests
# can reference the exact program instead of a duplicated copy.
PACMAN_STRIP_AWK='BEGIN{f=1} /^\[omarchy\]/{f=0;next} /^\[/{f=1} f'

restore_pacman() {
  log "detaching from omarchy repos, restoring stock Arch mirrors"
  if grep -q "^\[omarchy\]" /etc/pacman.conf; then
    if is_dry; then
      log_dry "sudo cp /etc/pacman.conf $BACKUP_DIR/pacman.conf.pre-strip"
      log_dry "sudo awk '<strip [omarchy] section>' /etc/pacman.conf > <mktemp> && sudo mv <mktemp> /etc/pacman.conf"
    else
      run_cmd sudo cp /etc/pacman.conf "$BACKUP_DIR/pacman.conf.pre-strip"
      # Drop the [omarchy] section up to the next [header]. No eval anywhere,
      # so the single backslashes in $PACMAN_STRIP_AWK reach awk intact.
      # mktemp (not a predictable /tmp name) + validate-before-mv: a broken
      # awk output must never clobber /etc/pacman.conf.
      local tmp
      tmp="$(mktemp /tmp/pacman.conf.XXXXXX)"
      sudo awk "$PACMAN_STRIP_AWK" \
        /etc/pacman.conf >"$tmp"
      if [[ ! -s "$tmp" ]] || ! grep -q '^\[' "$tmp"; then
        echo "strip produced invalid pacman.conf, abort (see $BACKUP_DIR/pacman.conf.pre-strip)" >&2
        rm -f "$tmp"
        return 1
      fi
      sudo mv "$tmp" /etc/pacman.conf
    fi
  else
    log "no [omarchy] section, nothing to strip"
  fi
  if ! is_dry && grep -q "^\[omarchy\]" /etc/pacman.conf; then
    echo "strip failed" >&2
    return 1
  fi
  if ! command -v reflector >/dev/null 2>&1; then
    if [[ -f /etc/pacman.d/mirrorlist.pacnew ]]; then
      run_cmd sudo cp /etc/pacman.d/mirrorlist.pacnew /etc/pacman.d/mirrorlist
      if is_dry; then
        log_dry "sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist"
      else
        sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
      fi
    elif ! grep -Fq "geo.mirror.pkgbuild.com" /etc/pacman.d/mirrorlist; then
      if is_dry; then
        log_dry "prepend geo.mirror.pkgbuild.com to /etc/pacman.d/mirrorlist"
      else
        sudo sed -i '1i Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' /etc/pacman.d/mirrorlist
      fi
    fi
    run_cmd sudo pacman -Syy --noconfirm --needed reflector
  fi
  if [[ "${NO_REFLECTOR:-0}" -eq 1 ]]; then
    log "skipping reflector (--no-reflector)"
  else
    run_cmd sudo reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  fi
  run_cmd sudo pacman -Syy
  log "pacman detached. verify: pacman -Si hyprland should show Repository: extra"
}
