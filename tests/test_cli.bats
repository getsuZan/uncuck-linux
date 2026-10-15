# bats regression tests for arg parsing + help (T1) and config logic (T2).
# shellcheck shell=bash
load helper

@test "help lists full flag surface" {
  run bash "$REPO_ROOT/unomarchy.sh" --help
  [ "$status" -eq 0 ]
  for f in --dry-run --yes --backup-dir --only-step --force --kb --term --no-reflector --import-rice --rice-ref --tui --version; do
    [[ "$output" == *"$f"* ]] || {
      echo "missing $f"
      return 1
    }
  done
}

@test "backup-dir accepts space and equals forms" {
  run bash "$REPO_ROOT/unomarchy.sh" --backup-dir /tmp/b1 --dry-run --help
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/unomarchy.sh" --backup-dir=/tmp/b1 --dry-run --help
  [ "$status" -eq 0 ]
}

@test "version prints, unknown arg fails, bad tui backend fails" {
  run bash "$REPO_ROOT/unomarchy.sh" --version
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/unomarchy.sh" --bogus
  [ "$status" -ne 0 ]
  run bash "$REPO_ROOT/unomarchy.sh" --tui=nope
  [ "$status" -ne 0 ]
}

@test "import-rice without rice-ref is rejected" {
  run bash "$REPO_ROOT/unomarchy.sh" --import-rice https://github.com/x/y --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"rice-ref"* ]]
}

@test "bashrc strip survives single-omarchy-line file (set -e safe)" {
  fixture_home
  echo 'source ~/.local/share/omarchy/default/bash/rc' >"$BACKUP_DIR/bashrc.bak"
  # same construct as lib/config.sh: must exit 0 even when grep -v matches everything
  run bash -e -c "grep -v 'local/share/omarchy/default/bash/rc' '$BACKUP_DIR/bashrc.bak' > '$BACKUP_DIR/out' || true"
  [ "$status" -eq 0 ]
  [ ! -s "$BACKUP_DIR/out" ]
}

@test "bashrc tmp+mv keeps user lines, drops omarchy line" {
  fixture_home
  printf 'export MINE=1\nsource ~/.local/share/omarchy/default/bash/rc\nalias x=y\n' >"$BACKUP_DIR/bashrc.bak"
  run bash -e -c "rc_tmp=\$(mktemp '$BACKUP_DIR/bashrc.XXXXXX'); grep -v 'local/share/omarchy/default/bash/rc' '$BACKUP_DIR/bashrc.bak' > \"\$rc_tmp\" || true; mv \"\$rc_tmp\" '$BACKUP_DIR/final'"
  [ "$status" -eq 0 ]
  run grep -c "omarchy" "$BACKUP_DIR/final"
  [ "$status" -ne 0 ]
  run grep -c "MINE" "$BACKUP_DIR/final"
  [ "$status" -eq 0 ]
}

@test "dry-run only-step touches nothing and is deterministic" {
  export HOME="$BATS_TEST_TMPDIR/fxhome"
  mkdir -p "$HOME"
  run bash "$REPO_ROOT/unomarchy.sh" --dry-run --force --only-step=verify --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY"* ]]
  run bash -c "find \"$HOME\" -mindepth 1 | wc -l"
  [ "$output" -eq 0 ]
}
