# bats regression tests for safe_rm (T2).
# shellcheck shell=bash
load helper

setup() { fixture_home; }

@test "refuses HOME, .config, .local/share, /etc tree, /usr tree, empty" {
  run safe_rm "$HOME"
  [ "$status" -ne 0 ]
  run safe_rm "$HOME/"
  [ "$status" -ne 0 ]
  run safe_rm "$HOME/.config"
  [ "$status" -ne 0 ]
  run safe_rm "$HOME/.local/share"
  [ "$status" -ne 0 ]
  run safe_rm /etc
  [ "$status" -ne 0 ]
  run safe_rm /etc/pacman.conf
  [ "$status" -ne 0 ]
  run safe_rm /usr
  [ "$status" -ne 0 ]
  run safe_rm /usr/bin/ls
  [ "$status" -ne 0 ]
  run safe_rm ""
  [ "$status" -ne 0 ]
}

@test "refuses personal dirs" {
  for d in Documents Downloads Pictures Videos Projects Work Wallpapers Music Desktop .ssh .gnupg; do
    run safe_rm "$HOME/$d/x"
    [ "$status" -ne 0 ]
  done
}

@test "refuses symlink and dotdot escapes into personal dirs" {
  mkdir -p "$HOME/Documents"
  ln -s "$HOME/Documents" "$BATS_TEST_TMPDIR/evil"
  run safe_rm "$BATS_TEST_TMPDIR/evil/secret"
  [ "$status" -ne 0 ]
  run safe_rm "$BATS_TEST_TMPDIR/evil/../Documents/x"
  [ "$status" -ne 0 ]
}

@test "allows omarchy config path (dry-run preview, no delete)" {
  export DRY_RUN=1
  mkdir -p "$HOME/.config/hypr"
  touch "$HOME/.config/hypr/a.conf"
  run safe_rm "$HOME/.config/hypr"
  [ "$status" -eq 0 ]
  [[ "$output" == DRY* ]]
  [ -f "$HOME/.config/hypr/a.conf" ]
}
