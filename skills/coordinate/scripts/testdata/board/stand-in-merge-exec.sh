#!/usr/bin/env bash
# Stand-in merge-exec.sh (MERGE_EXEC points here): logs its arguments to
# $BT_STATE/merge-exec.calls and prints merge-called at the sha it was given,
# or $BT_STATE/merge-exec.out with exit $BT_STATE/merge-exec.rc when present.
printf '%s\n' "$*" >> "$BT_STATE/merge-exec.calls"
if [ -f "$BT_STATE/merge-exec.out" ]; then
    cat "$BT_STATE/merge-exec.out"
    exit "$(cat "$BT_STATE/merge-exec.rc" 2>/dev/null || echo 0)"
fi
echo "merge-called:squash:$3"
