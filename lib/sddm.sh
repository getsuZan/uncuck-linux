# lib/sddm.sh - restore SDDM to a vanilla hyprland session.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.
#
# Order matters: reinstall sddm FIRST (restores /etc/pam.d/sddm keyring
# lines clobbered by omarchy), THEN patch session config.

restore_sddm() {
  log "restoring SDDM to vanilla hyprland session"
  # Plain /usr/share/wayland-sessions/hyprland.desktop (Exec=/usr/bin/start-hyprland, no uwsm dep).
  if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    echo "hyprland.desktop missing, abort" >&2
    return 1
  fi
  run_cmd sudo pacman -S --noconfirm --needed sddm
  run_cmd sudo mkdir -p /etc/sddm.conf.d
  if is_dry; then
    log_dry "sudo rm -f /usr/local/share/wayland-sessions/omarchy.desktop"
    log_dry "sudo rm -rf /usr/share/sddm/themes/omarchy"
  else
    sudo rm -f /usr/local/share/wayland-sessions/omarchy.desktop
    sudo rm -rf /usr/share/sddm/themes/omarchy
  fi
  # Session= may live in /etc/sddm.conf or any sddm.conf.d/*.conf; patch all hits, create fallback if none.
  # No nullglob needed: a non-matching glob is not a file, [[ -f ]] skips it.
  local f found=0
  for f in /etc/sddm.conf.d/*.conf /etc/sddm.conf; do
    [[ -f "$f" ]] || continue
    if grep -q "^Session=" "$f" 2>/dev/null; then
      if is_dry; then
        log_dry "sudo sed -i 's/^Session=.*/Session=hyprland/' $f"
      else
        sudo sed -i 's/^Session=.*/Session=hyprland/' "$f"
      fi
      found=1
    fi
    if grep -q "^Current=" "$f" 2>/dev/null; then
      if is_dry; then
        log_dry "sudo sed -i 's/^Current=.*/Current=/' $f"
      else
        sudo sed -i 's/^Current=.*/Current=/' "$f"
      fi
    fi
  done
  if [[ $found -eq 0 ]]; then
    if is_dry; then
      log_dry "printf Autologin/$USER/Session=hyprland | sudo tee /etc/sddm.conf.d/autologin.conf"
    else
      # $USER may be unset under set -u (e.g. minimal env); fall back to id.
      printf '[Autologin]\nUser=%s\nSession=hyprland\n' "${USER:-$(id -un)}" | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
    fi
  fi
  # keep 10-wayland.conf greeter (CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.conf), harmless
  run_cmd sudo systemctl enable sddm.service
  # plymouth: drop omarchy theme if set
  if command -v plymouth-set-default-theme >/dev/null && plymouth-set-default-theme 2>/dev/null | grep -qi omarchy; then
    run_cmd sudo plymouth-set-default-theme -R bgrt
  fi
  log "sddm done. Session=hyprland, Theme=default"
}
