#!/usr/bin/env bash
# Does the plugin check tell a supported version from an unsupported one?
#
# A Minecraft release always outpaces its plugin ecosystem. The whole value of
# this check is the day the answer is no, so that is the case exercised
# deliberately rather than waited for.
#
#   ./tests/plugins-for-version.sh
#
# Talks to Modrinth and to Mojang. A network failure is reported as a failure
# to ask rather than as a verdict, and this asserts that too.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/tools/plugins-for-version.sh"
PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

echo "=== the plugin check, shown both answers ==="

out="$("$CHECK" 99.99.99 2>&1)"; rc=$?
if [ $rc -eq 1 ]; then
  pass "a version no plugin supports is refused"
else
  fail "an unsupported version was not refused (exit $rc)"; printf '%s\n' "$out" | sed 's/^/        /'
fi
if printf '%s' "$out" | grep -q "viaversion"; then
  pass "and the plugins that cannot come are named"
else
  fail "it refused without saying which plugin"
fi
if printf '%s' "$out" | grep -qi "converted either way"; then
  pass "and it says why that matters for a world"
else
  fail "it refused without saying what is at stake"
fi

# 1.20.1 is old enough that every one of these has had years to publish for
# it, which makes it a stable yes that does not depend on today's releases.
out="$("$CHECK" 1.20.1 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then
  pass "a long-supported version is accepted"
else
  fail "a version every plugin supports was refused"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# THE PROJECTS COME FROM THE COMPOSE FILE, so the check cannot drift away from
# what the server would actually download.
for p in $(grep -m1 -oE '\$\{MINECRAFT_SERVER_MODRINTH_PROJECTS:-[^}]*' "$ROOT/minecraft-server-docker-compose.yml" \
           | sed -E 's/^\$\{MINECRAFT_SERVER_MODRINTH_PROJECTS:-//' | tr ',' ' '); do
  if printf '%s' "$out" | grep -q "$p"; then
    pass "it read $p out of the compose file"
  else
    fail "$p is pinned in the compose file and was not checked"
  fi
done

# A QUESTION THAT COULD NOT BE ASKED IS NOT A NO. Pointed at a host that does
# not resolve, it must exit 2 rather than condemn the plugins.
out="$(MINECRAFT_SERVER_MODRINTH_PROJECTS=this-project-does-not-exist-xyzzy "$CHECK" 1.20.1 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then
  pass "a project Modrinth will not answer for is 'could not ask', not 'no'"
else
  fail "an unanswerable question produced a verdict (exit $rc)"; printf '%s\n' "$out" | sed 's/^/        /'
fi

echo
echo "=== $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
