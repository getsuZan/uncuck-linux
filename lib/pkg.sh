# lib/pkg.sh - interactive package triage (keep-list driven).
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.

prompt_group() { # $1=label $2=default(Y/N) $3...=pkgs -> echoes selected pkgs
  local label="$1" def="$2"
  shift 2
  if is_dry; then
    # Deterministic preview: pinned default, no prompt.
    if [[ "$def" =~ ^[Yy]$ ]]; then echo "$*"; else echo ""; fi
    return 0
  fi
  local ans
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then ans="$def"; else
    read -rp "Remove $label? [$*] (y/N, default $def) " ans || return 1
    ans="${ans:-$def}"
  fi
  if [[ "$ans" =~ ^[Yy]$ ]]; then echo "$*"; else echo ""; fi
}

handle_packages() {
  log "package triage (interactive keep-list)"
  local ALWAYS_REMOVE=(omarchy-chromium omarchy-nvim omarchy-walker omarchy-keyring aether cliamp tobi-try usage)
  # never touch: vanilla hyprland core + audio + net + base
  local ALWAYS_KEEP=(hyprland hypridle hyprlock hyprsunset hyprland-guiutils hyprland-preview-share-picker waybar swaybg mako uwsm sddm pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber gst-plugin-pipewire libpulse iwd wireless-regdb base base-devel linux linux-firmware sudo git yay kitty alacritty ghostty foot)
  local REMOVE=() _parts=()
  local p
  for p in "${ALWAYS_REMOVE[@]}"; do
    if pacman -Q "$p" >/dev/null 2>&1; then REMOVE+=("$p"); fi
  done

  # groups: default N = keep, default Y = remove. tune freely.
  local sel
  sel=$(prompt_group "browsers+chat (chromium firefox-bin signal-desktop spotify)" N chromium firefox-bin signal-desktop spotify)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi
  sel=$(prompt_group "media (mpv imv kdenlive obs-studio pinta satty gpu-screen-recorder)" N mpv imv kdenlive obs-studio pinta satty gpu-screen-recorder)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi
  sel=$(prompt_group "office (libreoffice-fresh evince typora obsidian xournalpp gnome-calculator)" N libreoffice-fresh evince typora obsidian xournalpp gnome-calculator)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi
  sel=$(prompt_group "docker+db (docker docker-buildx docker-compose lazydocker)" N docker docker-buildx docker-compose lazydocker)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi
  sel=$(prompt_group "omarchy helpers (walker elephant impala swayosd wl-clipboard satty grim slurp hyprpicker)" Y walker elephant impala swayosd wl-clipboard satty grim slurp hyprpicker)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi
  sel=$(prompt_group "webapps+tuis (chromium webapps, tui meta)" Y)
  : # placeholder; webapps are .desktop files, handled in strip_configs
  sel=$(prompt_group "1password/claude TUIs (1password-beta 1password-cli claude-code)" N 1password-beta 1password-cli claude-code)
  if [[ -n "$sel" ]]; then
    read -r -a _parts <<<"$sel"
    REMOVE+=("${_parts[@]}")
  fi

  # filter ALWAYS_KEEP out
  local final=() keep k
  for p in "${REMOVE[@]}"; do
    keep=0
    for k in "${ALWAYS_KEEP[@]}"; do [[ "$p" == "$k" ]] && keep=1; done
    if [[ $keep -eq 0 ]] && pacman -Q "$p" >/dev/null 2>&1; then final+=("$p"); fi
  done
  log "removing: ${final[*]:-(none)}"
  [[ ${#final[@]} -gt 0 ]] || return 0
  confirm "Proceed with pacman -Rns ${final[*]}?" || return 0
  local core=() opt=() iscore
  for p in "${final[@]}"; do
    iscore=0
    for k in "${ALWAYS_REMOVE[@]}"; do [[ "$p" == "$k" ]] && iscore=1; done
    if [[ $iscore -eq 1 ]]; then core+=("$p"); else opt+=("$p"); fi
  done
  if [[ ${#core[@]} -gt 0 ]]; then
    if ! run_cmd sudo pacman -Rns --noconfirm "${core[@]}"; then
      log_warn "core bulk remove failed (deps). retry per-package."
      local q
      for q in "${core[@]}"; do run_cmd sudo pacman -Rns --noconfirm "$q" || log_warn "keep $q (dep)"; done
    fi
  fi
  if [[ ${#opt[@]} -gt 0 ]]; then
    if ! run_cmd sudo pacman -Rns --noconfirm "${opt[@]}"; then
      log_warn "optional bulk remove failed (deps). retry per-package."
      local r
      for r in "${opt[@]}"; do run_cmd sudo pacman -Rns --noconfirm "$r" || log_warn "keep $r (dep)"; done
    fi
  fi
  # reinstall stock chromium if omarchy-chromium removed but user wants browser
  local want_chromium=0 f
  for f in "${final[@]}"; do [[ "$f" == "omarchy-chromium" ]] && want_chromium=1; done
  if [[ $want_chromium -eq 1 ]] && confirm "Install stock extra/chromium to replace omarchy-chromium?"; then
    run_cmd sudo pacman -S --noconfirm chromium
  fi
  run_cmd sudo pacman -Syu --noconfirm
}
