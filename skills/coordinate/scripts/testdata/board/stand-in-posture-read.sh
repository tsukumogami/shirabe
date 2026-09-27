#!/usr/bin/env bash
# Stand-in posture-read.sh, copied beside the scripts under test in a
# localized plugin tree. Prints $BT_STATE/posture (a posture token) and exits
# with $BT_STATE/posture.rc; logs its arguments to $BT_STATE/posture.calls.
printf '%s\n' "$*" >> "$BT_STATE/posture.calls"
[ -f "$BT_STATE/posture.rc" ] && exit "$(cat "$BT_STATE/posture.rc")"
cat "$BT_STATE/posture"
