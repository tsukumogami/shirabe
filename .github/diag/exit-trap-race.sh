#!/usr/bin/env bash
# Does a just-forked subshell that gets TERM run its parent's EXIT trap?
# The parent's EXIT trap appends the pid that ran it to a file; any line other
# than the parent's own pid is a child running the parent's trap.
out=$(mktemp "${TMPDIR:-/tmp}/exit-trap-race.XXXXXX") || exit 2
trap 'echo "$BASHPID" >>"$out"' EXIT
i=0
while [ "$i" -lt "${1:-500}" ]; do
    ( trap 'exit 0' TERM; sleep 5 & wait $! ) &
    kill -TERM $! 2>/dev/null
    wait $! 2>/dev/null
    i=$((i + 1))
done
children=$(grep -cv "^$$\$" "$out")
echo "bash $BASH_VERSION: $children of ${1:-500} forked subshells ran the parent's EXIT trap"
rm -f "$out"
