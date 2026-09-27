#!/usr/bin/env bash
# Stand-in record-holding.sh for the localized plugin tree. $BT_STATE/holdings
# holds the Holdings rows as a JSON array: --list prints it, --topic T --read
# prints the row whose worker is T (exit 1 when none).
printf '%s\n' "$*" >> "$BT_STATE/holding.calls"
[ -f "$BT_STATE/holding.rc" ] && exit "$(cat "$BT_STATE/holding.rc")"
topic= mode=
while [ $# -gt 0 ]; do
    case "$1" in
        --topic) topic=$2; shift 2 ;;
        --read) mode=read; shift ;;
        --list) mode=list; shift ;;
        *) shift ;;
    esac
done
case "$mode" in
    list) cat "$BT_STATE/holdings" ;;
    read) jq -ce --arg t "$topic" '.[] | select(.worker == $t)' "$BT_STATE/holdings" || exit 1 ;;
    *) exit 64 ;;
esac
