# lib/rice.sh - install a plain-dotfiles rice after the uninstall.
# shellcheck shell=bash
# Sourced by unomarchy.sh. Requires lib/safe.sh helpers.
# GPL-3.0.
#
# Rice = plain dotfiles dir (+ optional packages.txt) at a pinned git ref.
# Only allowlisted ~/.config entries are ever copied. Root-level *.sh files
# are NEVER executed unless explicitly chosen (see below).

# Config dirs (rice/<name>/ -> ~/.config/<name>/) and top-level files allowed.
RICE_ALLOW_DIRS=(hypr waybar walker mako kitty foot ghostty alacritty btop fastfetch nvim starship uwsm fontconfig)
RICE_ALLOW_FILES=(starship.toml)

import_rice() {
  local url="${IMPORT_RICE:?--import-rice needs a value}"
  local ref="${RICE_REF:?--import-rice requires --rice-ref (pinned ref)}"
  local dest="${RICE_DIR:-$HOME/.local/share/rice}"

  case "$url" in
  https://github.com/*) ;;
  *)
    if [[ "${FORCE:-0}" -ne 1 ]]; then
      echo "refusing non-GitHub rice URL without --force: $url" >&2
      return 1
    fi
    log_warn "non-GitHub rice URL accepted via --force: $url"
    ;;
  esac
  command -v git >/dev/null || {
    echo "git not found (needed for --import-rice)" >&2
    return 1
  }

  if is_dry; then
    log_dry "git clone $url $dest && git -C $dest checkout $ref"
    log_dry "copy allowlisted entries (${RICE_ALLOW_DIRS[*]} ${RICE_ALLOW_FILES[*]}) to ~/.config (backup overwritten to \$BACKUP_DIR/rice-prev/)"
    log_dry "pacman -S --needed from $dest/packages.txt (if present)"
    log_dry "root-level *.sh detection + Run/Copy/Abort prompt happens at run time, never in dry-run"
    return 0
  fi

  if [[ -e "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    echo "rice dir not empty, abort (remove or pick --rice-dir): $dest" >&2
    return 1
  fi
  log "cloning rice $url @ $ref"
  git clone "$url" "$dest" || return 1
  git -C "$dest" checkout "$ref" || return 1
  local sha
  sha="$(git -C "$dest" rev-parse HEAD)"
  {
    echo "url=$url"
    echo "ref=$ref"
    echo "sha=$sha"
  } >"$BACKUP_DIR/rice.log"
  log "rice pinned at $sha"

  rice_run_hook_or_skip "$dest" || return 1
  rice_copy_dotfiles "$dest" || return 1
  rice_install_packages "$dest" || return 1
  systemctl --user daemon-reload 2>/dev/null || log_warn "systemctl --user daemon-reload failed"
  log "rice done from $sha"
}

# Root-level *.sh only (scripts/*.sh ignored + logged). Returns 0 to continue
# with copy-only, 1 to abort the whole import.
rice_run_hook_or_skip() {
  local dest="$1"
  # Collect in current shell (not a pipeline) so return really returns.
  local scripts=() line
  while IFS= read -r line; do scripts+=("$line"); done < <(
    shopt -s nullglob
    local s=("$dest"/*.sh)
    [[ ${#s[@]} -gt 0 ]] && printf '%s\n' "${s[@]}"
  )
  if [[ ${#scripts[@]} -eq 0 ]]; then
    log "no root-level .sh in rice, copy-only mode"
    return 0
  fi
  log "rice ships script(s):"
  printf '  %s\n' "${scripts[@]}" | tee -a "$LOG"
  if [[ -n "${RICE_EXEC:-}" ]]; then
    rice_exec_script "$dest" "$RICE_EXEC"
    return $?
  fi
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    log "copy-only mode (--yes never auto-runs rice scripts; use --rice-exec to opt in)"
    return 0
  fi
  local ans
  read -rp "Rice ships script(s). [R]un one / [C]opy dotfiles+deps only (default) / [A]bort? " ans || return 1
  ans="${ans:-C}"
  case "$ans" in
  [Rr]*)
    local pick
    read -rp "Which script (basename or path inside rice)? " pick || return 1
    rice_exec_script "$dest" "$pick"
    return $?
    ;;
  [Aa]*)
    echo "aborted by user" >&2
    return 1
    ;;
  *)
    log "copy-only mode (rice scripts ignored)"
    return 0
    ;;
  esac
}

# Run one root-level rice script with double confirmation. Logs everything.
rice_exec_script() {
  local dest="$1" pick="$2"
  local script
  script="$(realpath -m -- "$dest/$pick")"
  local dest_real
  dest_real="$(realpath -m -- "$dest")"
  case "$script" in
  "$dest_real"/*.sh) ;;
  *)
    echo "refusing rice script outside repo root or not .sh: $pick" >&2
    return 1
    ;;
  esac
  [[ -f "$script" ]] || {
    echo "rice script not found: $pick" >&2
    return 1
  }
  if [[ "$(dirname -- "$script")" != "$dest_real" ]]; then
    echo "only root-level rice scripts allowed (scripts/ ignored): $pick" >&2
    return 1
  fi
  log "rice script: $script"
  sha256sum "$script" | tee -a "$LOG"
  if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then
    echo "--- first 20 lines ---"
    head -20 -- "$script"
    echo "----------------------"
    confirm "Run $pick?" || return 1
  fi
  log "executing rice script $pick (output -> \$BACKUP_DIR/rice-exec.log)"
  bash -- "$script" 2>&1 | tee -a "$BACKUP_DIR/rice-exec.log"
}

# Copy allowlisted entries. Existing targets are backed up first.
rice_copy_dotfiles() {
  local dest="$1" name src target
  local prev="$BACKUP_DIR/rice-prev"
  mkdir -p "$prev"
  for name in "${RICE_ALLOW_DIRS[@]}"; do
    src="$dest/$name"
    [[ -d "$src" ]] || continue
    target="$HOME/.config/$name"
    if [[ -e "$target" ]]; then
      cp -a "$target" "$prev/$name" || return 1
      log "backed up $target -> $prev/$name"
    fi
    mkdir -p "$target" || return 1
    cp -a "$src/." "$target/" || return 1
    log "rice: $name/ -> ~/.config/$name/"
  done
  for name in "${RICE_ALLOW_FILES[@]}"; do
    src="$dest/$name"
    [[ -f "$src" ]] || continue
    target="$HOME/.config/$name"
    if [[ -e "$target" ]]; then
      cp -a "$target" "$prev/$name" || return 1
      log "backed up $target -> $prev/$name"
    fi
    cp -a "$src" "$target" || return 1
    log "rice: $name -> ~/.config/$name"
  done
  log "non-allowlisted rice entries skipped (see $dest)"
}

# Install packages.txt (one repo/pkg or pkg per line, # comments allowed)
# in a single pacman transaction so deps resolve together or nothing lands.
rice_install_packages() {
  local dest="$1"
  if [[ ! -f "$dest/packages.txt" ]]; then
    log "no packages.txt in rice, configs only"
    return 0
  fi
  local pkgs=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^[a-zA-Z0-9@._+-]+(/[a-zA-Z0-9@._+-]+)?$ ]]; then
      echo "bad packages.txt entry, abort: $line" >&2
      return 1
    fi
    pkgs+=("$line")
  done <"$dest/packages.txt"
  [[ ${#pkgs[@]} -eq 0 ]] && {
    log "packages.txt empty, configs only"
    return 0
  }
  log "installing rice packages: ${pkgs[*]}"
  run_cmd sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}
