#!/bin/bash
# clean-stop.sh <service> <save line|-> - does `docker compose stop` end the game the way a stop should?
#
# Docker sends SIGTERM to the container's process 1 and, when the grace
# period (stop_grace_period) runs out, SIGKILL. A server whose process 1
# ignores SIGTERM, or never passes it on, is killed every time: nothing it
# holds in memory is saved. This stops the running service, times the stop,
# reads the exit code from Docker's die event, and looks in the service's log,
# from the moment of the stop, for the line the game writes when it saves its
# world or exits cleanly (an extended regular expression, matched without
# regard to case).
#
#   clean      stopped before the grace period ran out, exit code 0 or 143,
#              and the save line is there
#   not clean  anything else: exit 1, with what was seen
#   -          a game with no world to save: the line is printed, measured,
#              and the stop is not judged (exit 0)
#
# One line on stdout, always:
#   clean-stop: <service> stopped in <s>s of a <g>s grace period, exit <code>, save line: yes|no|not asked
#
# Settings (environment):
#   CLEAN_STOP_PROJECT  the compose project            (required)
#   CLEAN_STOP_COMPOSE  the compose file               (default: the one *-docker-compose.yml)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
svc="${1:?usage: clean-stop.sh <service> <save line regex | ->}"
want="${2:?usage: clean-stop.sh <service> <save line regex | ->}"
PROJECT="${CLEAN_STOP_PROJECT:?set CLEAN_STOP_PROJECT to the compose project}"
COMPOSE="${CLEAN_STOP_COMPOSE:-}"
if [ -z "$COMPOSE" ]; then for f in ./*-docker-compose.yml; do COMPOSE="$f"; break; done; fi
cid="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q "$svc" 2>/dev/null)"
[ -n "$cid" ] || { echo "clean-stop: $svc is not running" >&2; exit 2; }
grace="$(docker inspect "$cid" --format '{{.Config.StopTimeout}}' 2>/dev/null)"
[[ $grace =~ ^[0-9]+$ ]] || grace=10

ev="$(mktemp)"; trap 'rm -f "$ev"' EXIT
since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker events --filter "container=$cid" --filter event=die --filter event=kill \
  --format '{{.Action}} {{index .Actor.Attributes "signal"}}{{index .Actor.Attributes "exitCode"}}' \
  --since "$(date +%s)" > "$ev" 2>/dev/null &
evp=$!
sleep 1
t0=$SECONDS
docker compose -p "$PROJECT" -f "$COMPOSE" stop "$svc" >/dev/null 2>&1
secs=$((SECONDS - t0))
sleep 2
kill "$evp" 2>/dev/null; wait "$evp" 2>/dev/null

code="$(sed -n 's/^die //p' "$ev" | tail -1)"
[ -n "$code" ] || code="$(docker inspect "$cid" --format '{{.State.ExitCode}}')"
# Docker's own kill at the end of the grace period: a kill event with signal 9.
sigkill=no; grep -qx 'kill 9' "$ev" && sigkill=yes

if [ "$want" = - ]; then
  saved="not asked"
else
  line="$(docker logs --since "$since" "$cid" 2>&1 | grep -a -i -E -- "$want" | tail -1)"
  if [ -n "$line" ]; then saved=yes; else saved=no; fi
fi
echo "clean-stop: $svc stopped in ${secs}s of a ${grace}s grace period, exit $code, save line: $saved$([ "$sigkill" = yes ] && echo ", Docker sent SIGKILL")"
[ -n "${line:-}" ] && echo "  the line: $(sed -E 's/7656[0-9]{13}/<steamid>/g; s/([0-9]{1,3}[.]){3}[0-9]{1,3}/<ip>/g' <<<"$line" | cut -c1-200)"
[ "$want" = - ] && exit 0
if [ "$sigkill" = no ] && [ "$secs" -lt "$grace" ] && { [ "$code" = 0 ] || [ "$code" = 143 ]; } && [ "$saved" = yes ]; then
  exit 0
fi
echo "::error::clean-stop: $svc did not stop cleanly (killed: $sigkill, ${secs}s of ${grace}s, exit $code, save line: $saved)"
exit 1
