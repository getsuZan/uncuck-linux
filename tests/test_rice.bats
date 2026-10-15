# bats tests for rice import (T8). sudo/pacman/systemctl stubbed; git is real (local repos).
# shellcheck shell=bash
load helper

setup() {
  fixture_home
  # shellcheck source=../lib/rice.sh
  source "$REPO_ROOT/lib/rice.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$STUB_BIN"
  printf '#!/usr/bin/env bash\nexec "$@"\n' >"$STUB_BIN/sudo"
  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$STUB_PACMAN_LOG"\nexit 0\n' >"$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN"/sudo "$STUB_BIN"/pacman "$STUB_BIN"/systemctl
  export PATH="$STUB_BIN:$PATH"
  export STUB_PACMAN_LOG="$BATS_TEST_TMPDIR/pacman.log"
  export FORCE=1 ASSUME_YES=1
  SRC="$BATS_TEST_TMPDIR/ricerepo"
  mkdir -p "$SRC/hypr" "$SRC/waybar" "$SRC/notallowed" "$SRC/scripts"
  echo "rice-hypr" >"$SRC/hypr/hyprland.conf"
  echo "rice-waybar" >"$SRC/waybar/config"
  echo "nope" >"$SRC/notallowed/evil.conf"
  printf 'extra/foo\n# comment\n\nextra/bar\n' >"$SRC/packages.txt"
  printf '#!/usr/bin/env bash\ntouch "$RICE_MARKER"\n' >"$SRC/install.sh"
  chmod +x "$SRC/install.sh"
  printf '#!/usr/bin/env bash\ntouch "$BATS_TEST_TMPDIR/nested-ran"\n' >"$SRC/scripts/nested.sh"
  chmod +x "$SRC/scripts/nested.sh"
  git -C "$SRC" init -q
  git -C "$SRC" -c user.email=t@t -c user.name=t add -A
  git -C "$SRC" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$SRC" tag v1
  export RICE_MARKER="$BATS_TEST_TMPDIR/hook-ran"
  export IMPORT_RICE="$SRC" RICE_REF="v1" RICE_DIR="$BATS_TEST_TMPDIR/riceout"
  mkdir -p "$HOME/.config/hypr"
  echo "old" >"$HOME/.config/hypr/old.conf"
}

@test "copy-only: allowlist copied, rest skipped, hook not run, pkgs installed, prev backed up" {
  run import_rice
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/hypr/hyprland.conf")" = "rice-hypr" ]
  [ "$(cat "$HOME/.config/waybar/config")" = "rice-waybar" ]
  [ ! -e "$HOME/.config/notallowed" ]
  [ ! -e "$RICE_MARKER" ]
  grep -q "extra/foo" "$STUB_PACMAN_LOG"
  grep -q "extra/bar" "$STUB_PACMAN_LOG"
  [ -f "$BACKUP_DIR/rice-prev/hypr/old.conf" ]
  grep -q "^sha=" "$BACKUP_DIR/rice.log"
}

@test "rice-exec runs root script and logs output" {
  export RICE_EXEC="install.sh"
  run import_rice
  [ "$status" -eq 0 ]
  [ -f "$RICE_MARKER" ]
  [ -f "$BACKUP_DIR/rice-exec.log" ]
}

@test "rice-exec refuses nested scripts" {
  export RICE_EXEC="scripts/nested.sh"
  run import_rice
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/nested-ran" ]
}

@test "non-github URL refused without --force" {
  export FORCE=0 IMPORT_RICE="https://example.com/x/y"
  run import_rice
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing non-GitHub"* ]]
}

@test "dry-run clones nothing and never executes" {
  export DRY_RUN=1
  run import_rice
  [ "$status" -eq 0 ]
  [ ! -e "$RICE_DIR" ]
  [ ! -e "$RICE_MARKER" ]
  [[ "$output" == *"DRY"* ]]
}

@test "non-empty rice dir aborts" {
  mkdir -p "$RICE_DIR"
  touch "$RICE_DIR/junk"
  run import_rice
  [ "$status" -ne 0 ]
  [[ "$output" == *"not empty"* ]]
}

@test "bad packages.txt entry aborts, nothing installed" {
  printf 'extra/ok!!!\n' >"$SRC/packages.txt"
  git -C "$SRC" -c user.email=t@t -c user.name=t commit -qam bad
  git -C "$SRC" tag -f v1
  run import_rice
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad packages.txt entry"* ]]
  [ ! -f "$STUB_PACMAN_LOG" ]
}
