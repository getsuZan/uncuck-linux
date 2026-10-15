# bats regression tests for do_backup (T2: tar -cf creates archive).
# shellcheck shell=bash
load helper

setup() {
  fixture_home
  # shellcheck source=../lib/backup.sh
  source "$REPO_ROOT/lib/backup.sh"
}

@test "creates dotfiles.tar from scratch with expected items" {
  mkdir -p "$HOME/.config/hypr"
  echo x >"$HOME/.config/hypr/hyprland.conf"
  echo y >"$HOME/.bashrc"
  run do_backup
  [ "$status" -eq 0 ]
  [ -f "$BACKUP_DIR/dotfiles.tar" ]
  run tar -tf "$BACKUP_DIR/dotfiles.tar"
  [[ "$output" == *".config/hypr/hyprland.conf"* ]]
  [[ "$output" == *".bashrc"* ]]
}

@test "empty dotfiles set warns instead of writing empty archive" {
  run do_backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to back up"* ]]
  [ ! -f "$BACKUP_DIR/dotfiles.tar" ]
}
