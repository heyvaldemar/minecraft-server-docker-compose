#!/bin/bash
# End-to-end tests for the Minecraft world backup and restore flow.
#
# Requires: docker, docker compose. Assumes the stack is already up with a
# short backup interval in .env (CI uses INITIAL_DELAY=15s, INTERVAL=60s).
#
# Run from the repository root:
#   ./tests/e2e-backup-restore.sh
#
# WHAT THIS IS FOR. `itzg/mc-backup` writes archives on a schedule and nothing
# in this repository checked that one of them contains a world, let alone that
# a world comes back out. A backup nobody has restored is a hypothesis, and a
# world is the one thing players notice losing.
#
# The scenario that matters most is the third. Before each archive the sidecar
# tells the server over RCON to stop writing and flush what it has.
#
# What happens when that instruction does not land was measured rather than
# assumed, by running a second sidecar against the same world with a
# deliberately wrong password. itzg/mc-backup behaves well: it retries five
# times, never archives without a successful flush, and then exits 2. Under
# `restart: unless-stopped` that becomes a restart loop.
#
# So the failure is not a torn archive. It is no archive at all — and the only
# outward sign is a container whose restart count climbs while everything else
# in `docker compose ps` looks ordinary. Nobody watches a restart count.
#
# Hence the two assertions below: that the flush actually ran, and that the
# log carries no RCON error. Both were confirmed to fire against the broken
# sidecar before being trusted, which is the only reason to believe them.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-minecraft-server}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-minecraft-server-docker-compose.yml}"
BACKUPS_DIR="${BACKUPS_DIR:-minecraft-server-data-backups}"
DATA_DIR="${DATA_DIR:-minecraft-server-data}"
CYCLE_WAIT="${CYCLE_WAIT:-180}"

WORK="$(mktemp -d)"
PASSED=0; FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

dc() { docker compose -f "$DOCKER_COMPOSE_FILE" -p "$COMPOSE_PROJECT_NAME" "$@"; }

BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
SERVER_CONTAINER="$(dc ps -aq minecraft-server | head -n 1)"
[ -n "$BACKUPS_CONTAINER" ] || { echo "error: backup container not found — is the stack up?" >&2; exit 1; }
[ -n "$SERVER_CONTAINER" ] || { echo "error: server container not found — is the stack up?" >&2; exit 1; }

# LOG-DRIVEN, not newest-by-mtime.
#
# The newest file on disk is very often the one currently being written, and a
# half-written gzip is readable by `tar -tzf` for as far as it goes. The first
# version of this picked by mtime and reported a world with no level.dat in it
# and an archive that would not unpack — both true of the file it was handed,
# and both nothing to do with the backups.
#
# The sidecar logs `Backing up content in /data to <path>` when it STARTS and
# `save-on` when it has finished. An archive named by a line that has a save-on
# after it is complete by definition.
completed_archive() {
  docker logs "$BACKUPS_CONTAINER" 2>&1 | awk '
    /Backing up content in .* to / { sub(/.* to /, ""); f=$1; next }
    /save-on/ && f != "" { done_f = f; f = "" }
    END { if (done_f != "") print done_f }'
}

# The path inside the container maps to $BACKUPS_DIR on the host.
host_path() { printf '%s/%s' "$BACKUPS_DIR" "${1##*/}"; }

newest() {
  local c
  c="$(completed_archive)"
  [ -n "$c" ] || return 0
  printf '%s' "$(host_path "$c")"
}

echo "=== minecraft: does a world come back out? ==="
echo "  project=$COMPOSE_PROJECT_NAME backups=$BACKUPS_DIR"
echo

# 1. an archive at all
echo "=== test_backup_created ==="
deadline=$(( $(date +%s) + CYCLE_WAIT ))
while [ -z "$(newest)" ] && [ "$(date +%s)" -lt "$deadline" ]; do sleep 5; done
ARCHIVE="$(newest)"
if [ -n "$ARCHIVE" ]; then
  pass "an archive was produced ($ARCHIVE, $(wc -c < "$ARCHIVE" | tr -d ' ') bytes)"
else
  fail "no archive after ${CYCLE_WAIT}s"
  echo; echo "passed: $PASSED   failed: $FAILED"; exit 1
fi

# 2. it is a readable archive containing a world
echo "=== test_archive_valid ==="
if tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
  pass "the archive is readable"
else
  fail "tar could not read the archive"
fi
if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q 'level\.dat$'; then
  pass "it contains a level.dat, so it is a world and not an empty directory tree"
else
  fail "no level.dat in the archive"
  tar -tzf "$ARCHIVE" 2>/dev/null | head -5 | sed 's/^/        /'
fi

# 3. THE ONE THAT MATTERS: the world was flushed before it was read.
echo "=== test_world_was_flushed_first ==="
logs="$(docker logs "$BACKUPS_CONTAINER" 2>&1)"
if printf '%s' "$logs" | grep -qF 'save-off' && printf '%s' "$logs" | grep -qF 'save-all flush'; then
  pass "the sidecar told the server to stop writing and flush before archiving"
else
  fail "no save-off / save-all flush in the sidecar log — the archive was taken of a live world"
  printf '%s' "$logs" | tail -8 | sed 's/^/        /'
fi
if printf '%s' "$logs" | grep -qF 'save-on'; then
  pass "and told it to resume afterwards"
else
  fail "no save-on — the server may have been left with saving disabled"
fi
# A failed rcon command is logged and the backup continues regardless, which is
# exactly how this goes wrong quietly.
if printf '%s' "$logs" | grep -qiE 'rcon.*(failed|error|refused|unable)'; then
  fail "the sidecar reported an RCON problem: $(printf '%s' "$logs" | grep -iE 'rcon.*(failed|error|refused|unable)' | tail -1)"
else
  pass "no RCON failures reported"
fi

# 4. a change made now reaches the NEXT archive
echo "=== test_new_content_reaches_the_next_archive ==="
marker="e2e-marker-$$"
if docker exec "$SERVER_CONTAINER" sh -c "printf 'x' > /data/$marker" 2>/dev/null; then
  before="$ARCHIVE"
  deadline=$(( $(date +%s) + CYCLE_WAIT ))
  while [ "$(newest)" = "$before" ] && [ "$(date +%s)" -lt "$deadline" ]; do sleep 5; done
  next="$(newest)"
  if [ "$next" = "$before" ]; then
    fail "no new archive within ${CYCLE_WAIT}s, so this could not be checked"
  elif tar -tzf "$next" 2>/dev/null | grep -q "$marker"; then
    pass "a file written after the last archive is in the next one"
  else
    fail "the next archive does not contain a file that existed before it was taken"
  fi
  docker exec "$SERVER_CONTAINER" sh -c "rm -f /data/$marker" 2>/dev/null
else
  fail "could not write a marker into the world directory"
fi

# 5. the archive restores
echo "=== test_restore_roundtrip ==="
ARCHIVE="$(newest)"
mkdir -p "$WORK/restore"
if tar -xzf "$ARCHIVE" -C "$WORK/restore" 2>/dev/null; then
  if find "$WORK/restore" -name 'level.dat' -print -quit | grep -q .; then
    n=$(find "$WORK/restore" -type f | wc -l | tr -d ' ')
    pass "the archive unpacks into a world ($n files, level.dat present)"
  else
    fail "the archive unpacked but has no level.dat"
  fi
else
  fail "the archive would not unpack"
fi

# 6. pruning is actually configured, not merely intended
echo "=== test_prune_configured ==="
if printf '%s' "$logs" | grep -qF 'Pruning backup files older than'; then
  pass "the sidecar prunes old archives: $(printf '%s' "$logs" | grep -F 'Pruning backup files older than' | tail -1 | sed 's/.*INFO //')"
else
  fail "no pruning line in the log — archives will accumulate until the disk fills"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
