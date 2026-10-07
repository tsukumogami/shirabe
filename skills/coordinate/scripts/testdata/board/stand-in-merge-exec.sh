#!/usr/bin/env bash
# Stand-in merge-exec.sh (bt_setup copies it to the localized plugin tree's
# skills/execute/scripts/merge-exec.sh): logs its first three arguments to
# $BT_STATE/merge-exec.calls, copies the message file (the fourth) to
# $BT_STATE/merge-exec.msg, and prints merge-called at the sha it was given,
# or $BT_STATE/merge-exec.out with exit $BT_STATE/merge-exec.rc when present.
printf '%s %s %s\n' "$1" "$2" "$3" >> "$BT_STATE/merge-exec.calls"
if [ -n "${4-}" ]; then cp "$4" "$BT_STATE/merge-exec.msg"; else rm -f "$BT_STATE/merge-exec.msg"; fi
if [ -f "$BT_STATE/merge-exec.out" ]; then
    cat "$BT_STATE/merge-exec.out"
    exit "$(cat "$BT_STATE/merge-exec.rc" 2>/dev/null || echo 0)"
fi
echo "merge-called:squash:$3"
