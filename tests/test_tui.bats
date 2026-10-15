# bats tests for TUI (T9). select backend driven via stdin; gum/whiptail stubbed.
# shellcheck shell=bash
load helper

setup() {
  fixture_home
  # shellcheck source=../lib/tui.sh
  source "$REPO_ROOT/lib/tui.sh"
}

@test "backend auto-detect priority: gum > whiptail > select" {
  local stub="$BATS_TEST_TMPDIR/detectbin"
  mkdir -p "$stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$stub/gum"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$stub/whiptail"
  chmod +x "$stub"/gum "$stub"/whiptail
  # Sourcing needs real coreutils; symlink them in (detection stays hermetic).
  ln -s "$(command -v realpath)" "$stub/realpath"
  ln -s "$(command -v tee)" "$stub/tee"
  local probe="source '$REPO_ROOT/lib/safe.sh'; source '$REPO_ROOT/lib/tui.sh'; export DRY_RUN=0 LOG=/dev/null BACKUP_DIR=/tmp/x TUI_BACKEND=auto; tui_detect_backend >/dev/null 2>&1; echo \$TUI_BACKEND"
  # NOTE: PATH=stub only (hermetic: host ships real gum+whiptail). Invoke bash by absolute path.
  PATH="$stub" run "$BASH" -c "$probe"
  [ "$status" -eq 0 ]
  [ "$output" = "gum" ]
  rm "$stub/gum"
  PATH="$stub" run "$BASH" -c "$probe"
  [ "$output" = "whiptail" ]
  rm "$stub/whiptail"
  PATH="$stub" run "$BASH" -c "$probe"
  [ "$output" = "select" ]
}

@test "explicit missing backend fails" {
  mkdir -p "$BATS_TEST_TMPDIR/emptybin"
  TUI_BACKEND=gum PATH="$BATS_TEST_TMPDIR/emptybin" run tui_detect_backend
  [ "$status" -ne 0 ]
}

@test "select questionnaire collects groups, skips rice, writes flags, arms engine" {
  export TUI_BACKEND=select ASSUME_YES=0
  printf '\n\n\n\n\n\n\n\ny\n' >"$BATS_TEST_TMPDIR/in"
  run_tui <"$BATS_TEST_TMPDIR/in" >"$BATS_TEST_TMPDIR/out" 2>&1
  status=$?
  [ "$status" -eq 0 ]
  [ "$TUI_G_HELPERS" = "Y" ]
  [ "$TUI_G_BROWSERS" = "N" ]
  [ "$ASSUME_YES" = "1" ]
  grep -q -- "--group helpers=Y" "$BACKUP_DIR/tui-flags.log"
  grep -q -- "--group browsers=N" "$BACKUP_DIR/tui-flags.log"
  [ -z "${IMPORT_RICE:-}" ]
}

@test "select questionnaire abort at proceed leaves engine disarmed" {
  export TUI_BACKEND=select ASSUME_YES=0
  printf '\n\n\n\n\n\n\n\n\n' >"$BATS_TEST_TMPDIR/in"
  run_tui <"$BATS_TEST_TMPDIR/in" >/dev/null 2>&1 || status=$?
  [ "$status" -ne 0 ]
  [ "$ASSUME_YES" = "0" ]
}

@test "prompt_group honors TUI var over defaults" {
  # shellcheck source=../lib/pkg.sh
  source "$REPO_ROOT/lib/pkg.sh"
  export TUI_MODE=1 TUI_G_BROWSERS=Y DRY_RUN=1
  run prompt_group "browsers" N TUI_G_BROWSERS chromium firefox
  [ "$status" -eq 0 ]
  [ "$output" = "chromium firefox" ]
  export TUI_G_BROWSERS=N
  run prompt_group "browsers" Y TUI_G_BROWSERS chromium firefox
  [ "$output" = "" ]
}

@test "whiptail stub: checklist parsed, flags written" {
  local stub="$BATS_TEST_TMPDIR/wtbin"
  mkdir -p "$stub"
  cat >"$stub/whiptail" <<'EOF'
#!/usr/bin/env bash
# Mimic real whiptail fd behavior: UI on stderr, result on stderr too
# (caller swaps fds so the result lands on stdout).
for a in "$@"; do
  case "$a" in
  --checklist) echo '"helpers" "tuis"' >&2; exit 0 ;;
  --yesno) exit 0 ;;
  --inputbox) exit 0 ;;
  esac
done
exit 0
EOF
  chmod +x "$stub/whiptail"
  export PATH="$stub:$PATH" TUI_BACKEND=whiptail ASSUME_YES=0
  run_tui >/dev/null 2>&1
  status=$?
  [ "$status" -eq 0 ]
  [ "$TUI_G_HELPERS" = "Y" ]
  [ "$TUI_G_TUIS" = "Y" ]
  [ "$TUI_G_BROWSERS" = "N" ]
  grep -q -- "--group tuis=Y" "$BACKUP_DIR/tui-flags.log"
}

@test "--tui with closed stdin aborts non-zero with zero side effects" {
  local bk="$BATS_TEST_TMPDIR/nobk"
  run bash "$REPO_ROOT/unomarchy.sh" --tui=select --force --only-step=verify --dry-run "--backup-dir=$bk" </dev/null
  [ "$status" -ne 0 ]
  [ ! -e "$bk" ]
}
