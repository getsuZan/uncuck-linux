# bats regression tests for pacman strip program + sddm verify pattern (T2).
# shellcheck shell=bash
load helper

setup() {
  fixture_home
  # shellcheck source=../lib/pacman.sh
  source "$REPO_ROOT/lib/pacman.sh"
}

@test "strip program removes [omarchy] section, keeps neighbors" {
  cat >"$BATS_TEST_TMPDIR/pacman.conf" <<'EOF'
[options]
HoldPkg = pacman
[omarchy]
Server = https://pkgs.omarchy.org/$arch
SigLevel = Never
[extra]
Include = /etc/pacman.d/mirrorlist
EOF
  run awk "$PACMAN_STRIP_AWK" "$BATS_TEST_TMPDIR/pacman.conf"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[omarchy]"* ]]
  [[ "$output" != *"pkgs.omarchy.org"* ]]
  [[ "$output" == *"[options]"* ]]
  [[ "$output" == *"[extra]"* ]]
}

@test "strip program is no-op without [omarchy]" {
  printf '[options]\nHoldPkg = pacman\n' >"$BATS_TEST_TMPDIR/plain.conf"
  run awk "$PACMAN_STRIP_AWK" "$BATS_TEST_TMPDIR/plain.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[options]"* ]]
}

@test "sddm session check is recursive (matches conf.d files)" {
  mkdir -p "$BATS_TEST_TMPDIR/sddm.conf.d"
  printf '[Autologin]\nSession=hyprland\n' >"$BATS_TEST_TMPDIR/sddm.conf.d/autologin.conf"
  run grep -rq "^Session=hyprland$" "$BATS_TEST_TMPDIR/sddm.conf.d/"
  [ "$status" -eq 0 ]
}
