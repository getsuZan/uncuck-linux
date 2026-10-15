# lib/tui.sh - lightweight questionnaire driving the same engine.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.
#
# --tui collects answers, injects them (TUI_G_* vars, IMPORT_RICE/RICE_REF/
# RICE_EXEC, ASSUME_YES=1) and lets the normal steps run untouched.
# Without --tui nothing here is ever called. ESC/EOF anywhere aborts
# before any mutation (except an already-logged early rice clone).
#
# Backend priority: gum > whiptail > bash select. Override: --tui=NAME.

# tag|prompt|default(Y/N)|varname — defaults mirror handle_packages groups.
TUI_GROUPS=(
  "browsers|Remove browsers+chat (chromium firefox-bin signal-desktop spotify)?|N|TUI_G_BROWSERS"
  "media|Remove media (mpv imv kdenlive obs-studio pinta satty gpu-screen-recorder)?|N|TUI_G_MEDIA"
  "office|Remove office (libreoffice-fresh evince typora obsidian xournalpp gnome-calculator)?|N|TUI_G_OFFICE"
  "docker|Remove docker+db (docker docker-buildx docker-compose lazydocker)?|N|TUI_G_DOCKER"
  "helpers|Remove omarchy helpers (walker elephant impala swayosd wl-clipboard satty grim slurp hyprpicker)?|Y|TUI_G_HELPERS"
  "tuis|Remove 1password/claude TUIs (1password-beta 1password-cli claude-code)?|N|TUI_G_TUIS"
)

tui_detect_backend() {
  case "${TUI_BACKEND:-auto}" in
  gum)
    command -v gum >/dev/null || {
      echo "gum not found" >&2
      return 1
    }
    ;;
  whiptail)
    command -v whiptail >/dev/null || {
      echo "whiptail not found" >&2
      return 1
    }
    ;;
  select) ;;
  auto)
    if command -v gum >/dev/null 2>&1; then
      TUI_BACKEND=gum
    elif command -v whiptail >/dev/null 2>&1; then
      TUI_BACKEND=whiptail
    else
      TUI_BACKEND=select
    fi
    ;;
  esac
  log "tui backend: $TUI_BACKEND"
}

# tui_yesno "prompt" Y|N -> 0 yes / 1 no / 2 abort(ESC,EOF)
tui_yesno() {
  local prompt="$1" def="${2:-N}" st
  case "$TUI_BACKEND" in
  gum)
    local choice
    choice="$(gum choose --header "$prompt (default $def)" Yes No 2>/dev/null)" || return 2
    [[ "$choice" == "Yes" ]] && return 0 || return 1
    ;;
  whiptail)
    whiptail --yesno "$prompt" 12 70
    st=$?
    case $st in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
    ;;
  *)
    local ans opts="Yes/No"
    [[ "$def" =~ ^[Yy]$ ]] && opts="Yes/no" || opts="y/No"
    printf '%s [%s]: ' "$prompt" "$opts" >&2
    if ! IFS= read -r ans; then
      echo >&2
      return 2
    fi
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy] ]] && return 0 || return 1
    ;;
  esac
}

# tui_input "prompt" "default" -> echoes value; exit 2 on abort. Empty = default.
tui_input() {
  local prompt="$1" def="${2:-}" v
  case "$TUI_BACKEND" in
  gum)
    v="$(gum input --header "$prompt" --placeholder "$def" --value "$def" 2>/dev/null)" || return 2
    echo "$v"
    ;;
  whiptail)
    v="$(whiptail --inputbox "$prompt" 10 70 "$def" 3>&1 1>&2 2>&3)" || return 2
    echo "${v:-$def}"
    ;;
  *)
    printf '%s [%s]: ' "$prompt" "$def" >&2
    IFS= read -r v || {
      echo >&2
      return 2
    }
    echo "${v:-$def}"
    ;;
  esac
}

tui_ask_groups() {
  local entry tag prompt def var ans st out
  if [[ "$TUI_BACKEND" == "whiptail" ]]; then
    local args=()
    for entry in "${TUI_GROUPS[@]}"; do
      IFS='|' read -r tag prompt def var <<<"$entry"
      if [[ "$def" =~ ^[Yy]$ ]]; then st=ON; else st=OFF; fi
      args+=("$tag" "$prompt" "$st")
    done
    out="$(whiptail --checklist "Packages to REMOVE (space toggles):" 20 78 6 "${args[@]}" 3>&1 1>&2 2>&3)" || return 2
    for entry in "${TUI_GROUPS[@]}"; do
      IFS='|' read -r tag prompt def var <<<"$entry"
      if [[ "$out" == *"\"$tag\""* ]]; then printf -v "$var" Y; else printf -v "$var" N; fi
    done
    return 0
  fi
  for entry in "${TUI_GROUPS[@]}"; do
    IFS='|' read -r tag prompt def var <<<"$entry"
    tui_yesno "$prompt" "$def"
    st=$?
    case $st in
    0) printf -v "$var" Y ;;
    1) printf -v "$var" N ;;
    *) return 2 ;;
    esac
  done
}

# Rice screen: URL+ref, early clone to list real .sh files, Run(file)/Copy/Skip/Abort.
tui_ask_rice() {
  local url ref
  url="$(tui_input "Rice git URL (empty = skip rice)" "")" || return 2
  [[ -z "$url" ]] && {
    IMPORT_RICE=""
    return 0
  }
  ref="$(tui_input "Rice pinned ref (tag/SHA, required)" "")" || return 2
  [[ -z "$ref" ]] && {
    echo "rice ref required" >&2
    return 1
  }
  IMPORT_RICE="$url"
  RICE_REF="$ref"
  case "$url" in
  https://github.com/*) ;;
  *)
    [[ "${FORCE:-0}" -ne 1 ]] && {
      echo "non-GitHub rice URL needs --force" >&2
      return 1
    }
    ;;
  esac
  if is_dry; then
    log_dry "tui: rice hook choice deferred (no clone in dry-run), copy-only default"
    return 0
  fi
  command -v git >/dev/null || {
    echo "git not found" >&2
    return 1
  }
  if [[ -e "${RICE_DIR:-$HOME/.local/share/rice}" ]] && [[ -n "$(ls -A "${RICE_DIR:-$HOME/.local/share/rice}" 2>/dev/null)" ]]; then
    echo "rice dir not empty: ${RICE_DIR:-$HOME/.local/share/rice}" >&2
    return 1
  fi
  git clone "$url" "${RICE_DIR:-$HOME/.local/share/rice}" || return 1
  git -C "${RICE_DIR:-$HOME/.local/share/rice}" checkout "$ref" || return 1
  local dest_real
  dest_real="$(realpath -m -- "${RICE_DIR:-$HOME/.local/share/rice}")"
  local scripts=() s
  shopt -s nullglob
  for s in "$dest_real"/*.sh; do scripts+=("$(basename -- "$s")"); done
  shopt -u nullglob
  [[ ${#scripts[@]} -eq 0 ]] && {
    log "tui: no root .sh in rice, copy-only"
    return 0
  }
  log "tui: rice ships: ${scripts[*]}"
  local pick
  if [[ "$TUI_BACKEND" == "gum" ]]; then
    pick="$(gum choose --header "Rice ships scripts" "Copy-only (safe default)" "Skip rice" "Abort everything" "${scripts[@]}" 2>/dev/null)" || return 2
    case "$pick" in
    "Copy-only (safe default)") return 0 ;;
    "Skip rice")
      IMPORT_RICE=""
      rm -rf "${RICE_DIR:-$HOME/.local/share/rice}"
      return 0
      ;;
    "Abort everything") return 1 ;;
    *) RICE_EXEC="$pick" && return 0 ;;
    esac
    return 0
  fi
  if [[ "$TUI_BACKEND" == "whiptail" ]]; then
    local rargs=("copy" "Copy-only, ignore scripts" ON "skip" "Skip rice entirely" OFF)
    local s2
    for s2 in "${scripts[@]}"; do rargs+=("run:$s2" "Run $s2" OFF); done
    rargs+=("abort" "Abort everything" OFF)
    pick="$(whiptail --radiolist "Rice ships scripts:" 18 70 6 "${rargs[@]}" 3>&1 1>&2 2>&3)" || return 2
    case "$pick" in
    copy) return 0 ;;
    skip)
      IMPORT_RICE=""
      rm -rf "${RICE_DIR:-$HOME/.local/share/rice}"
      return 0
      ;;
    abort) return 1 ;;
    run:*) RICE_EXEC="${pick#run:}" && return 0 ;;
    *) return 2 ;;
    esac
  fi
  local i=1
  {
    echo "Rice ships scripts:"
    echo "  0) Copy-only (safe default)"
    echo "  -1) Skip rice"
    for s in "${scripts[@]}"; do
      echo "  $i) Run $s"
      i=$((i + 1))
    done
  } >&2
  local sel
  printf 'Pick [0]: ' >&2
  IFS= read -r sel || return 2
  sel="${sel:-0}"
  case "$sel" in
  0) return 0 ;;
  -1)
    IMPORT_RICE=""
    rm -rf "${RICE_DIR:-$HOME/.local/share/rice}"
    return 0
    ;;
  *)
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -ge 1 && $sel -le ${#scripts[@]} ]]; then
      RICE_EXEC="${scripts[$((sel - 1))]}"
      return 0
    fi
    echo "aborted" >&2
    return 1
    ;;
  esac
}

run_tui() {
  tui_detect_backend || return 1
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    log "tui: --yes given, using defaults (rice hook needs --rice-exec)"
    tui_write_flags
    return 0
  fi
  local bd
  bd="$(tui_input "Backup dir" "$BACKUP_DIR")" || return 1
  BACKUP_DIR="$bd"
  tui_ask_groups || return 1
  tui_ask_rice || return 1
  tui_write_flags
  tui_yesno "Proceed with uninstall? (backup -> $BACKUP_DIR)" N
  case $? in 0) ;; *) return 1 ;; esac
  ASSUME_YES=1
}

# Log the equivalent CLI flags for reproducibility.
tui_write_flags() {
  local entry tag prompt def var val
  if is_dry; then
    log_dry "tui flags: --yes --backup-dir=$BACKUP_DIR ${IMPORT_RICE:+--import-rice $IMPORT_RICE --rice-ref $RICE_REF} ${RICE_EXEC:+--rice-exec $RICE_EXEC}"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  {
    echo "# equivalent CLI (collected via --tui=$TUI_BACKEND)"
    echo "--yes"
    echo "--backup-dir=$BACKUP_DIR"
    for entry in "${TUI_GROUPS[@]}"; do
      IFS='|' read -r tag prompt def var <<<"$entry"
      val="${!var:-$def}"
      echo "--group $tag=$val"
    done
    [[ -n "${IMPORT_RICE:-}" ]] && echo "--import-rice $IMPORT_RICE --rice-ref $RICE_REF"
    [[ -n "${RICE_EXEC:-}" ]] && echo "--rice-exec $RICE_EXEC"
  } >"$BACKUP_DIR/tui-flags.log"
  log "tui flags -> $BACKUP_DIR/tui-flags.log"
}
