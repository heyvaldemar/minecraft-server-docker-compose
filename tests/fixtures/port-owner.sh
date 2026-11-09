# port-owner.sh <port>: run inside the server's container (sh -s). Prints one
# line per process that owns a TCP socket LISTENING on <port>, "pid uid comm":
# the processes that answer a Server List Ping, which are the ones the
# SIGSTOP plant stops. Chosen by the socket, never by a name: the entrypoint,
# its shell and the JVM all carry "minecraft" somewhere, and stopping the
# wrong one stops nothing that answers. IPv4 and IPv6 sockets both count (a
# JVM listens on [::], which only /proc/net/tcp6 lists). A process is seen
# only by its own user (the container has no CAP_SYS_PTRACE), so the plant
# runs this as every uid it finds in the container until one sees the owners.
h=$(printf '%04X' "$1")
inos=$(awk -v h=":$h" '$2 ~ (h "$") && $4 == "0A" { print $10 }' /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u)
[ -n "$inos" ] || { echo "nothing listens on TCP $1" >&2; exit 1; }
found=0
for d in /proc/[0-9]*; do
  for f in "$d"/fd/*; do
    l=$(readlink "$f" 2>/dev/null) || continue
    for i in $inos; do
      if [ "$l" = "socket:[$i]" ]; then
        echo "${d#/proc/} $(awk '/^Uid:/ { print $2 }' "$d/status" 2>/dev/null) $(cat "$d/comm" 2>/dev/null)"
        found=1
      fi
    done
  done
done
[ "$found" = 1 ] || { echo "no process this user can see owns TCP $1 (socket inodes: $(echo "$inos" | tr "\n" " "))" >&2; exit 1; }
