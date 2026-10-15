# lib/backup.sh - back up configs + system files before any mutation.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.

do_backup() {
  log "backing up configs + system files"
  local items=(
    "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/walker"
    "$HOME/.config/omarchy" "$HOME/.config/mako" "$HOME/.config/swayosd"
    "$HOME/.config/uwsm" "$HOME/.config/elephant" "$HOME/.config/starship.toml"
    "$HOME/.config/alacritty" "$HOME/.config/foot" "$HOME/.config/kitty"
    "$HOME/.config/ghostty" "$HOME/.config/btop" "$HOME/.config/fastfetch"
    "$HOME/.config/lazygit" "$HOME/.config/mimeapps.list" "$HOME/.config/nvim"
    "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.XCompose" "$HOME/.profile"
  )
  local existing=() p rel
  for p in "${items[@]}"; do
    if [[ -e "$p" ]]; then
      rel="${p#"$HOME"/}"
      existing+=("$rel")
    fi
  done
  if [[ ${#existing[@]} -gt 0 ]]; then
    if is_dry; then
      log_dry "tar -cf $BACKUP_DIR/dotfiles.tar -C $HOME ${existing[*]}"
    else
      tar -cf "$BACKUP_DIR/dotfiles.tar" -C "$HOME" "${existing[@]}"
    fi
  else
    log "nothing to back up in dotfiles set"
  fi
  backup_file /etc/pacman.conf "$BACKUP_DIR/pacman.conf.bak"
  backup_file /etc/pacman.d/mirrorlist "$BACKUP_DIR/mirrorlist.bak"
  backup_file_best_effort /etc/sddm.conf.d "$BACKUP_DIR/"
  backup_file_best_effort /boot/limine.conf "$BACKUP_DIR/"
  log "backup done"
}

# Copy a single file if present, warn (don't abort) otherwise.
backup_file() {
  if [[ -e "$1" ]]; then
    if is_dry; then log_dry "cp -a $1 $2"; else cp -a "$1" "$2"; fi
  else
    log "skip missing $1"
  fi
}

# Best-effort copy (may need root or not exist): never abort.
backup_file_best_effort() {
  if is_dry; then
    log_dry "cp -a $1 $2 (best-effort)"
    return 0
  fi
  cp -a "$1" "$2" 2>/dev/null || log "WARN: cannot back up $1"
}
