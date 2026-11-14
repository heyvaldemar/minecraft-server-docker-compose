#!/bin/bash
# secret-probe.sh - no secret this template passes reaches a log or a command line.
#
#   tests/secret-probe.sh plant           before the first start: a random value
#                                         for every secret-named variable
#   tests/secret-probe.sh check <label>   with the stack running: look for every
#                                         planted value, exit 1 on any
#   tests/secret-probe.sh selftest        prove check sees a value planted in a
#                                         log and on a command line
#   tests/secret-probe.sh during <label> <command...>
#                                         run a helper (an rcon client, a
#                                         backup) and watch the host's ps and
#                                         every container's command lines the
#                                         whole time: a value handed to a
#                                         helper as an argument lives only
#                                         while it runs
#
# WHAT COUNTS AS A SECRET. Every variable the compose file interpolates whose
# name has PASS, PWD, SECRET, TOKEN, KEY or CRED in it. plant gives each one a
# value of its own, random, and writes it into .env and into a values file
# (mode 600) that only this script reads.
#
# WHERE IT LOOKS, the places a value leaks to in practice:
#   - `docker compose logs --no-color` of every service, since it started
#     (what a user pastes into an issue);
#   - the game's own log files that the template knows (PROBE_GAME_LOGS),
#     which users paste too;
#   - the command line of every process in every container of the project,
#     read as root from /proc/*/cmdline (what `ps` shows on the host, and
#     what any process in the container can read);
#   - `ps` on the host running the stack.
# A match prints the variable's name and the place, never the value.
#
# VALUES NEVER ON A COMMAND LINE HERE EITHER. Each value is written to a file
# and searched with grep -F -f, and .env is edited by awk through its
# environment, so the probe itself cannot be the leak it reports.
#
# Settings (environment):
#   PROBE_PROJECT  the compose project            (required)
#   PROBE_COMPOSE  the compose file               (default: the one *-docker-compose.yml)
#   PROBE_ENV      the env file compose reads     (default: .env)
#   PROBE_VALUES   the values file                (default: $RUNNER_TEMP or /tmp, secret-probe.values)
#   PROBE_EXPECT   names that must be among the secret-named variables found;
#                  a refactor that hides one from the probe fails instead
#   PROBE_KEEP     names whose value in the env file is kept, not replaced:
#                  a real token from a repository secret, which the game must
#                  log on with. Kept values are probed like the others.
#   PROBE_GAME_LOGS  the game's own log files, as service:glob, separated by
#                  spaces (for example vein-server:/home/steam/vein/Vein/Saved/Logs/*.log)
#   PROBE_ARGV_OK  names the README says are visible on the game's command
#                  line, because the game reads them nowhere else (measured,
#                  optional, empty by default). On a command line in a
#                  container or in host ps their value is reported as
#                  documented, not as a failure.
#   PROBE_GAMELOG_OK  names the README says are in the game's own log, because
#                  the engine writes its command line there. In the game logs
#                  their value is reported as documented.
#   No exception covers `docker compose logs`. Every name in either list must
#   appear in README.md, or the probe is red.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
umask 077

mode="${1:-}"
PROJECT="${PROBE_PROJECT:?set PROBE_PROJECT to the compose project}"
COMPOSE="${PROBE_COMPOSE:-}"
if [ -z "$COMPOSE" ]; then for f in ./*-docker-compose.yml; do COMPOSE="$f"; break; done; fi
ENVF="${PROBE_ENV:-.env}"
VALUES="${PROBE_VALUES:-${RUNNER_TEMP:-/tmp}/secret-probe.values}"
KEEP=" ${PROBE_KEEP:-} "
ARGV_OK=" ${PROBE_ARGV_OK:-} "
GAMELOG_OK=" ${PROBE_GAMELOG_OK:-} "
[ -f "$COMPOSE" ] || { echo "secret-probe: no compose file ($COMPOSE)" >&2; exit 2; }

# Every variable the compose file interpolates, from Compose itself where it
# can say (config --variables) and from the text, ${NAME} and $NAME, either
# way; the secret-named ones.
names() {
  {
    docker compose -f "$COMPOSE" config --variables 2>/dev/null | awk 'NR > 1 { print $1 }'
    grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*|(^|[^$])\$[A-Za-z_][A-Za-z0-9_]*' "$COMPOSE" | sed -E 's/^[^$]*\$\{?//'
  } | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u | grep -E 'PASS|PWD|SECRET|TOKEN|KEY|CRED'
}

# set_env NAME (value in $V): every line for NAME, commented or not, replaced by one.
set_env() {
  touch "$ENVF"
  N="$1" V="$V" awk 'BEGIN { n = ENVIRON["N"] } $0 !~ "^#? *" n "=" { print } END { print n "=" ENVIRON["V"] }' "$ENVF" >"$ENVF.probe" \
    && cat "$ENVF.probe" >"$ENVF" && rm -f "$ENVF.probe"
}
get_env() {  # NAME -> the value in the env file, last one wins
  N="$1" awk 'BEGIN { n = ENVIRON["N"] } index($0, n "=") == 1 { v = substr($0, length(n) + 2) } END { print v }' "$ENVF"
}

# found VALUE-FILE: the places this value appears; nothing when none.
found() {
  local f="$1" where=""
  grep -F -q -f "$f" "$WORK/logs" && where+=" compose-logs"
  grep -F -q -f "$f" "$WORK/cmdlines" && where+=" container-cmdline"
  grep -F -q -f "$f" "$WORK/hostps" && where+=" host-ps"
  grep -F -q -f "$f" "$WORK/gamelogs" && where+=" game-logs"
  printf '%s' "$where"
}

collect() {  # every place, into $WORK; fails closed: a place it cannot read is a failure
  docker compose -p "$PROJECT" -f "$COMPOSE" logs --no-color >"$WORK/logs" 2>&1 \
    || { echo "secret-probe: cannot read docker compose logs" >&2; return 1; }
  : >"$WORK/cmdlines"
  local cid unread=""
  for cid in $(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q 2>/dev/null); do
    docker exec -u 0 "$cid" sh -c 'for p in /proc/[0-9]*; do [ -r "$p/cmdline" ] && tr "\0" " " <"$p/cmdline" && echo; done' \
      >>"$WORK/cmdlines" 2>/dev/null || unread+=" $(docker inspect -f '{{.Name}}' "$cid")"
  done
  ps -eo args >"$WORK/hostps" || { echo "secret-probe: cannot read the host's ps" >&2; return 1; }
  : >"$WORK/gamelogs"
  local spec svc glob gcid
  for spec in ${PROBE_GAME_LOGS:-}; do
    svc="${spec%%:*}"; glob="${spec#*:}"
    gcid="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q "$svc" 2>/dev/null)"
    [ -n "$gcid" ] || { unread+=" $svc (game logs)"; continue; }
    # Fails, like any place it cannot read, when the glob matches no file.
    docker exec -u 0 "$gcid" sh -c 'n=0; for f in '"$glob"'; do [ -f "$f" ] || continue; n=1; cat "$f"; done; [ "$n" = 1 ]' >>"$WORK/gamelogs" 2>/dev/null \
      || unread+=" $svc (game logs: $glob)"
  done
  if [ -n "$unread" ]; then
    echo "secret-probe: cannot read the processes in:$unread" >&2
    return 1
  fi
  local f
  local places="logs cmdlines hostps"
  [ -n "${PROBE_GAME_LOGS:-}" ] && places+=" gamelogs"
  for f in $places; do
    [ -s "$WORK/$f" ] || { echo "secret-probe: nothing read from $f; a place with nothing in it proves nothing" >&2; return 1; }
  done
}

case "$mode" in
  plant)
    [ -L "$VALUES" ] && { echo "secret-probe: $VALUES is a symbolic link; refusing" >&2; exit 2; }
    rm -f "$VALUES" && : >"$VALUES" || exit 2
    found_names=" $(names | tr '\n' ' ') "
    for n in ${PROBE_EXPECT:-}; do
      [[ $found_names == *" $n "* ]] || { echo "secret-probe: $n is expected among the secret-named variables, and the compose file does not pass it" >&2; exit 2; }
    done
    planted=""; kept=""
    for n in $(names); do
      if [[ $KEEP == *" $n "* ]]; then
        V="$(get_env "$n")"
        [ -n "$V" ] || { echo "secret-probe: $n is to be kept, but $ENVF has no value for it" >&2; exit 2; }
        kept+=" $n"
      else
        V="p$(openssl rand -hex 10)"
        set_env "$n"
        # In GitHub Actions, the runner masks it in this job's log as well.
        [ "${GITHUB_ACTIONS:-}" = true ] && printf '::add-mask::%s\n' "$V"
        planted+=" $n"
      fi
      printf '%s\t%s\n' "$n" "$V" >>"$VALUES"
    done
    echo "secret-probe: planted${planted:- nothing}; kept${kept:- nothing}"
    ;;
  check)
    label="${2:-check}"
    [ -s "$VALUES" ] || { echo "secret-probe: no values file; run plant before the stack starts" >&2; exit 2; }
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    collect || exit 1
    bad=0; n_all=0
    for n in $(echo "$ARGV_OK $GAMELOG_OK" | tr ' ' '\n' | sort -u); do
      grep -F -q "$n" README.md || { echo "::error::secret-probe ($label): $n is excepted as visible, but README.md does not name it"; bad=1; }
    done
    while IFS=$'\t' read -r n v; do
      n_all=$((n_all + 1))
      printf '%s\n' "$v" >"$WORK/value"
      where="$(found "$WORK/value")"
      # What is left once every documented place is taken out is a leak.
      left="$where"
      [[ $ARGV_OK == *" $n "* ]] && { left="${left// container-cmdline/}"; left="${left// host-ps/}"; }
      [[ $GAMELOG_OK == *" $n "* ]] && left="${left// game-logs/}"
      if [ -n "$left" ]; then
        echo "::error::secret-probe ($label): the value of $n is in:$left"
        # The lines that hold it, every planted value in them replaced by its
        # name, so the line says what printed it and no value is shown.
        for src in logs gamelogs; do
          [[ $left == *" $([ "$src" = logs ] && echo compose-logs || echo game-logs)"* ]] || continue
          grep -F -f "$WORK/value" "$WORK/$src" | head -3 | awk -v vf="$VALUES" '
            BEGIN { while ((getline l < vf) > 0) { t = index(l, "\t"); name[++k] = substr(l, 1, t - 1); val[k] = substr(l, t + 1) } }
            { for (i = 1; i <= k; i++) { while ((p = index($0, val[i])) > 0) $0 = substr($0, 1, p - 1) "<" name[i] ">" substr($0, p + length(val[i])) } print "  in " src ": " substr($0, 1, 300) }' src="$src"
        done
        bad=1
      elif [ -n "$where" ]; then
        echo "secret-probe ($label): $n is only where the README says it is visible:$where"
      fi
    done <"$VALUES"
    [ "$bad" = 0 ] || exit 1
    if [ -n "${PROBE_GAME_LOGS:-}" ]; then gl="the game's logs ($(wc -l <"$WORK/gamelogs") lines)"; else gl="the game's logs (none configured: PROBE_GAME_LOGS is empty)"; fi
    echo "secret-probe ($label): $n_all values; none in docker compose logs ($(wc -l <"$WORK/logs") lines), and none outside what the README documents in $gl, the containers' command lines ($(wc -l <"$WORK/cmdlines") processes) or the host's ps"
    ;;
  during)
    label="${2:-during}"; shift 2 || { echo "usage: $0 during <label> <command...>" >&2; exit 2; }
    [ "$#" -gt 0 ] || { echo "usage: $0 during <label> <command...>" >&2; exit 2; }
    [ -s "$VALUES" ] || { echo "secret-probe: no values file; run plant before the stack starts" >&2; exit 2; }
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    : >"$WORK/samples"
    cids="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q 2>/dev/null)"
    # Sampling until the helper is done: the host's ps every tenth of a
    # second, each container's command lines as often as docker exec allows.
    (
      while [ ! -e "$WORK/done" ]; do
        ps -eo args >>"$WORK/samples"
        for c in $cids; do
          docker exec -u 0 "$c" sh -c 'for p in /proc/[0-9]*; do [ -r "$p/cmdline" ] && tr "\0" " " <"$p/cmdline" && echo; done' >>"$WORK/samples" 2>/dev/null &
        done
        sleep 0.1
      done
    ) &
    sampler=$!
    sleep 0.3
    rc=0; "$@" >"$WORK/out" 2>&1 || rc=$?
    sleep 0.3
    touch "$WORK/done"; wait "$sampler" 2>/dev/null; wait 2>/dev/null
    bad=0; n_all=0
    while IFS=$'\t' read -r n v; do
      n_all=$((n_all + 1))
      printf '%s\n' "$v" >"$WORK/value"
      if grep -F -q -f "$WORK/value" "$WORK/samples"; then
        echo "::error::secret-probe ($label): the value of $n was on a command line while the helper ran"
        bad=1
      fi
    done <"$VALUES"
    echo "secret-probe ($label): the helper exited $rc; $(wc -l <"$WORK/samples") process lines sampled while it ran; $([ "$bad" = 0 ] && echo "none of $n_all values among them")"
    [ "$bad" = 0 ] && [ "$rc" = 0 ]
    ;;
  selftest)
    # A canary, not a planted value: written to the first container's log,
    # held on the command line of a process inside it (both from inside the
    # container), and on the command line of a process on the host. All three
    # places must find it.
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    cid="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q | head -1)"
    [ -n "$cid" ] || { echo "secret-probe: nothing is running" >&2; exit 2; }
    CANARY="c$(openssl rand -hex 10)"
    printf '%s\n' "$CANARY" >"$WORK/value"
    # As PID 1's own user: root in a container has no CAP_SYS_PTRACE, and
    # without it cannot open another user's /proc/1/fd/1.
    u1="$(docker exec "$cid" sh -c "awk '/^Uid:/ { print \$2 }' /proc/1/status")"
    CANARY="$CANARY" docker exec -d -u "${u1:-0}" -e CANARY "$cid" sh -c 'echo "secret-probe canary $CANARY" >/proc/1/fd/1; exec sh -c "sleep 20; :" canary "$CANARY"'
    bash -c 'sleep 20; :' canary "$(cat "$WORK/value")" &
    host=$!
    sleep 2
    collect || exit 1
    where="$(found "$WORK/value")"
    kill "$host" 2>/dev/null
    if [[ $where == *compose-logs* && $where == *container-cmdline* && $where == *host-ps* ]]; then
      echo "secret-probe selftest: a canary planted in all three places was found in:$where"
    else
      echo "::error::secret-probe selftest: the canary was found in:${where:- nowhere}; expected compose-logs, container-cmdline and host-ps"
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 plant | check <label> | selftest | during <label> <command...>" >&2
    exit 2
    ;;
esac
