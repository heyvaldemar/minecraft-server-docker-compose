#!/usr/bin/env bash
# plugins-for-version.sh — do the plugins this server pins exist for the
# Minecraft version it is about to run?
#
#   tools/plugins-for-version.sh [version]     (default: what LATEST resolves to)
#
#   exit 0  every project has a build for that version
#   exit 1  at least one does not, and it is named
#   exit 2  the question could not be asked, which is not an answer
#
# WHY THIS EXISTS. A Minecraft release always outpaces its plugin ecosystem.
# The server takes the new version the moment it appears, tries to resolve
# plugins that have no build for it yet, and exits during resolution — in a
# loop, with its version already bumped and its backup already taken. Nothing
# in the stack asks the one question that would have stopped it, because the
# answer lives at Modrinth and not in any container.
#
# It is a question about the FUTURE of a world, so it is asked before anything
# is touched rather than after the first restart.
set -uo pipefail

API="https://api.modrinth.com/v2"
MANIFEST="https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
COMPOSE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/minecraft-server-docker-compose.yml"

# The projects and the loader come from the compose file's own defaults, so
# this cannot drift away from what the server would actually download. A list
# written here by hand would fall behind the file it describes.
default_of() {  # <VAR> -> the ${VAR:-default} value in the compose file
  grep -m1 -oE "\\\$\\{$1:-[^}]*" "$COMPOSE" | sed -E "s/^\\\$\\{$1:-//"
}
PROJECTS="${MINECRAFT_SERVER_MODRINTH_PROJECTS:-$(default_of MINECRAFT_SERVER_MODRINTH_PROJECTS)}"
LOADER="$(default_of MINECRAFT_SERVER_TYPE)"
LOADER="$(printf '%s' "${LOADER:-PAPER}" | tr '[:upper:]' '[:lower:]')"

VERSION="${1:-}"
if [ -z "$VERSION" ] || [ "$VERSION" = LATEST ]; then
  VERSION="$(curl -fsS --retry 3 "$MANIFEST" 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["latest"]["release"])' 2>/dev/null)"
  [ -n "$VERSION" ] || { echo "could not ask Mojang which release is latest; nothing was judged" >&2; exit 2; }
fi

[ -n "$PROJECTS" ] || { echo "no MODRINTH_PROJECTS default found in $COMPOSE — this check is reading a pin that does not exist" >&2; exit 2; }

echo "Minecraft $VERSION, loader $LOADER"
missing=""
for p in ${PROJECTS//,/ }; do
  body="$(curl -fsS --retry 3 \
      "$API/project/$p/version?game_versions=%5B%22$VERSION%22%5D&loaders=%5B%22$LOADER%22%5D" 2>/dev/null)" || {
    echo "  ?  $p — Modrinth did not answer; this says nothing about the plugin" >&2
    exit 2
  }
  n="$(printf '%s' "$body" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null)" || {
    echo "  ?  $p — Modrinth answered with something that is not a version list" >&2
    exit 2
  }
  if [ "$n" -gt 0 ]; then
    echo "  ok $p ($n build(s))"
  else
    echo "  NO $p has no build for $VERSION on $LOADER"
    missing="$missing $p"
  fi
done

if [ -n "$missing" ]; then
  echo
  echo "Do not move to $VERSION yet:$missing" >&2
  echo "A world converted to a version its plugins cannot load is converted either way." >&2
  exit 1
fi
echo "every pinned plugin has a build for $VERSION"
