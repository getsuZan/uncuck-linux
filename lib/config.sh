# lib/config.sh - strip omarchy configs (backed up already) + write vanilla skeleton.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.

strip_configs() {
  log "stripping omarchy configs (backed up already)"
  safe_rm "$HOME/.local/share/omarchy"
  safe_rm "$HOME/.config/omarchy" "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/walker" "$HOME/.config/elephant" "$HOME/.config/swayosd" "$HOME/.config/uwsm" "$HOME/.config/mako"
  safe_rm "$HOME/.local/share/applications/omarchy" "$HOME/.cache/omarchy" || true
  # webapps installed as ~/.local/share/applications/*.desktop + icons; remove only omarchy-tagged ones.
  # Deleted via safe_rm (not bare rm): a loose grep match must never bypass the guard.
  if is_dry; then
    log_dry "safe_rm omarchy-tagged .desktop files in $HOME/.local/share/applications"
  else
    (
      shopt -s nullglob
      local desk
      for desk in "$HOME"/.local/share/applications/*.desktop; do
        if grep -qi 'omarchy' "$desk" 2>/dev/null; then safe_rm "$desk"; fi
      done
    )
  fi
  # omarchy wrapper binaries: user dir as user, system dir via sudo (nullglob: no match = no-op).
  # System paths are prefix-asserted before sudo rm — sudo never goes through safe_rm by design.
  if is_dry; then
    log_dry "safe_rm $HOME/.local/bin/omarchy*; sudo rm -f /usr/local/bin/omarchy*"
  else
    (
      shopt -s nullglob
      local um=("$HOME"/.local/bin/omarchy*) sm=(/usr/local/bin/omarchy*) f cf
      [[ ${#um[@]} -gt 0 ]] && safe_rm "${um[@]}"
      for f in "${sm[@]}"; do
        cf="$(realpath -m -- "$f")"
        case "$cf" in
        /usr/local/bin/omarchy*) ;;
        *)
          echo "REFUSED: $f" >&2
          return 1
          ;;
        esac
      done
      [[ ${#sm[@]} -gt 0 ]] && sudo rm -f "${sm[@]}"
    )
  fi
  # shell: drop omarchy rc source, keep user block.
  # Write tmp + mv (never redirect straight into .bashrc): grep -v exits 1
  # when every line is filtered out, and a mid-pipeline failure must not
  # leave a truncated .bashrc behind.
  if grep -q "local/share/omarchy/default/bash/rc" "$HOME/.bashrc" 2>/dev/null; then
    if is_dry; then
      log_dry "remove omarchy rc source line from $HOME/.bashrc"
    else
      run_cmd cp "$HOME/.bashrc" "$BACKUP_DIR/bashrc.bak"
      local rc_tmp
      rc_tmp="$(mktemp "$BACKUP_DIR/bashrc.XXXXXX")"
      grep -v 'local/share/omarchy/default/bash/rc' "$BACKUP_DIR/bashrc.bak" >"$rc_tmp" || true
      mv "$rc_tmp" "$HOME/.bashrc"
    fi
  fi
  # nvim wired to omarchy paths: backup done above, strip on confirm
  if confirm "Remove omarchy-wired nvim state (~/.config/nvim ~/.local/share/nvim)?"; then
    safe_rm "$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim" || true
  fi
  # pacman keys
  if is_dry; then
    log_dry "sudo pacman-key --list-keys | grep -i omarchy"
  else
    sudo pacman-key --list-keys 2>/dev/null | grep -i omarchy || true
  fi
  if confirm "Delete omarchy pacman keys?"; then
    if is_dry; then
      log_dry "delete omarchy pacman keys"
    else
      sudo pacman-key --list-keys --with-colons 2>/dev/null |
        awk -F: '/^pub/{key=$5} tolower($0) ~ /omarchy/{if (key != "") {print key; key=""}}' |
        xargs -r sudo pacman-key --delete || log_warn "omarchy key delete failed"
    fi
  fi
  # env/autostart residues: ask only if the unit list is non-empty
  local ulist
  ulist=$(grep -rl -i omarchy "$HOME/.config/systemd/user/" "$HOME/.config/autostart/" 2>/dev/null || true)
  if is_dry; then
    log_dry "grep -rl -i omarchy /etc/environment $HOME/.profile"
  else
    grep -rl -i omarchy /etc/environment "$HOME/.profile" 2>/dev/null || true
  fi
  log "NOTE: /etc/environment hits (if any) need manual edit, never auto-removed."
  if [[ -n "$ulist" ]]; then
    log "omarchy-tagged units:"
    echo "$ulist" | tee -a "$LOG"
    if confirm "Disable + remove user units listed above?"; then
      local uf un
      while IFS= read -r -u 3 uf; do
        [[ -z "$uf" ]] && continue
        un=$(basename "$uf")
        case "$un" in
        *.service | *.timer | *.socket | *.path | *.target)
          if is_dry; then
            log_dry "systemctl --user disable --now $un"
          else
            systemctl --user disable --now "$un" 2>/dev/null || true
          fi
          ;;
        esac
        if is_dry; then log_dry "rm -f $uf"; else rm -f "$uf" || true; fi
      done 3<<<"$ulist"
      if is_dry; then
        log_dry "systemctl --user daemon-reload"
      else
        systemctl --user daemon-reload 2>/dev/null || true
      fi
    fi
  fi
  # mime defaults
  if [[ -f "$HOME/.config/mimeapps.list" ]]; then
    if is_dry; then
      log_dry "cp $HOME/.config/mimeapps.list $BACKUP_DIR/"
    else
      cp "$HOME/.config/mimeapps.list" "$BACKUP_DIR/"
    fi
  fi
  if confirm "Reset mimeapps.list to system defaults?"; then
    safe_rm "$HOME/.config/mimeapps.list" || true
  fi
  write_hypr_skeleton
}

# Minimal vanilla hyprland skeleton. Keeps an existing hyprland.conf.
write_hypr_skeleton() {
  local conf="$HOME/.config/hypr/hyprland.conf"
  if is_dry; then
    if [[ ! -f "$conf" ]]; then log_dry "mkdir -p $HOME/.config/hypr; write $conf (skeleton)"; fi
    return 0
  fi
  mkdir -p "$HOME/.config/hypr"
  if [[ ! -f "$conf" ]]; then
    local term="${TERM_OVERRIDE:-}"
    if [[ -z "$term" ]]; then
      term=kitty
      local t
      for t in kitty alacritty ghostty foot; do
        if command -v "$t" >/dev/null 2>&1; then
          term="$t"
          break
        fi
      done
    fi
    local kb="${KB_OVERRIDE:-}"
    if [[ -z "$kb" ]]; then
      # || true: localectl/awk fail on non-systemd; the :-us fallback below handles it.
      # Without it, pipefail + set -e would abort the assignment.
      kb=$(localectl status 2>/dev/null | awk -F: '/X11 Layout/{gsub(/ /,"",$2); if($2!="" && $2!="(unset)") {print $2; exit}} /VC Keymap/{gsub(/ /,"",$2); if($2!="" && $2!="(unset)") print substr($2,1,2)}' || true)
      kb="${kb:-us}"
    fi
    if ! command -v "$term" >/dev/null 2>&1; then log_warn "no terminal installed, skeleton binds missing $term"; fi
    local skel_tmp
    skel_tmp="$(mktemp "$HOME/.config/hypr/.hyprland.conf.XXXXXX")"
    printf 'monitor=,preferred,auto,1\nexec-once=waybar\ninput {\nkb_layout = %s\n}\nbind=SUPER,Return,exec,%s\nbind=SUPER,Q,killactive\nbind=SUPER,M,exit\n' "$kb" "$term" >"$skel_tmp"
    mv "$skel_tmp" "$conf"
  fi
}
