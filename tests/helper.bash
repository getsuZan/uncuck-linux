# Run with: bats tests/  (needs bats; CI installs it)
# Shared fixture: isolated HOME + BACKUP_DIR, libs sourced.
# shellcheck shell=bash

REPO_ROOT="$(cd -- "$(dirname -- "${BATS_TEST_FILENAME:-$0}")/.." && pwd)"

fixture_home() {
  FIXTURE_HOME="$(mktemp -d)"
  export HOME="$FIXTURE_HOME"
  export BACKUP_DIR="$(mktemp -d)/backup"
  export DRY_RUN=0 ASSUME_YES=0 LOG=/dev/null
  mkdir -p "$BACKUP_DIR"
  # shellcheck source=../lib/safe.sh
  source "$REPO_ROOT/lib/safe.sh"
}

teardown() {
  rm -rf "${FIXTURE_HOME:-}" 2>/dev/null || true
}
