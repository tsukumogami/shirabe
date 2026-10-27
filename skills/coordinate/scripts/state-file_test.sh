#!/usr/bin/env bash
# state-file_test.sh -- the state file a writer hands the write core: mode 0600,
# inside the writer's own private directory (mode 0700) under TMPDIR, while
# the write runs, and gone once it is done.
#
# A koto shim first on PATH records, at the write's first section key, every
# state file under the writer's TMPDIR with the mode it has, then runs the koto
# stand-in. Covers: an in-process writer (state-hold.sh --add) and the
# command-line path (state-holding.sh, which hands state-write.sh
# --state-file); each write lands, the file it handed was 0600 in a 0700
# directory of its own, every state file under TMPDIR then (the write core's
# own scratch copies included) sat in a 0700 directory, and nothing either
# made is left under TMPDIR afterwards.
#
# Usage: bash skills/coordinate/scripts/state-file_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
export RS_SESSION=$SR
W_RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)

# The shim: at a `context add` of a record/ section key, the state files
# under the writer's TMPDIR, as `<mode-ok> <dir-ok> <path>` lines, into
# $T/seen. find's exact -perm tells 0600 and 0700 apart on GNU and BSD alike.
mkdir -p "$T/shim" "$T/wtmp"
STUB=$(command -v koto)
cat > "$T/shim/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-}" = "context add" ] && case "\${4:-}" in record/meta|record/entries/*) false ;; record/*) true ;; *) false ;; esac; then
    find "$T/wtmp" -type f -name '*.json' | while read -r f; do
        m=no; d=no
        [ -n "\$(find "\$f" -perm 600)" ] && m=yes
        [ -n "\$(find "\$(dirname "\$f")" -maxdepth 0 -perm 700)" ] && d=yes
        printf '%s %s %s\n' "\$m" "\$d" "\${f#$T/wtmp/}" >> "$T/seen"
    done
fi
exec "$STUB" "\$@"
EOF
chmod +x "$T/shim/koto"
# run_writer <script> <args...>: the writer with the shim first on PATH and its
# own TMPDIR, emptied first.
run_writer() {
    rm -rf "$T/wtmp"; mkdir -p "$T/wtmp"; : > "$T/seen"
    PATH="$T/shim:$PATH" TMPDIR="$T/wtmp" bash "$@"
}

echo "== an in-process writer: state-hold.sh =="
db_init; seed_session "$SR" "$(record_json roadmap plugin-system)"
jq -nc '{hold: "after-346", on: "acme/widgets#12", until: "merged acme/gadgets#346", set_by: "the workspace coordinator", set: "2026-09-26T09:00Z"}' > "$T/h1.json"
run_writer "$HERE/state-hold.sh" "${W_RM[@]}" --add --row-file "$T/h1.json" > /dev/null 2> "$T/err"
eq "the hold is written" "0 after-346" "$? $(koto context get "$SR" record/holds | jq -r '.[0].hold')"
eq "the state file it handed was mode 0600, in a mode 0700 directory of its own" "yes yes" \
    "$(grep -E '^[a-z]+ [a-z]+ state-hold\.[^/]+/next\.json$' "$T/seen" | head -1 | cut -d' ' -f1-2)"
eq "  ... and every state file seen then sat in a mode 0700 directory" "" "$(grep -v "^[a-z]* yes " "$T/seen")"
eq "nothing the writer made is left under its TMPDIR" "" "$(find "$T/wtmp" -mindepth 1 | sed "s|^$T/wtmp/||")"

echo "== the command-line path: state-holding.sh to state-write.sh --state-file =="
db_init; seed_session "$SR" "$(record_json roadmap plugin-system)"
holding feature-2 > "$T/row.json"
run_writer "$HERE/state-holding.sh" "${W_RM[@]}" --topic feature-2 --row-file "$T/row.json" > /dev/null 2> "$T/err"
eq "the holding is written" "0 feature-2" "$? $(koto context get "$SR" record/holdings | jq -r '.[0].worker')"
eq "the state file handed to state-write.sh was mode 0600, in a mode 0700 directory of its own" "yes yes" \
    "$(grep -E '^[a-z]+ [a-z]+ state-holding\.[^/]+/next\.json$' "$T/seen" | head -1 | cut -d' ' -f1-2)"
eq "  ... and every state file seen then sat in a mode 0700 directory" "" "$(grep -v "^[a-z]* yes " "$T/seen")"
eq "nothing either script made is left under TMPDIR" "" "$(find "$T/wtmp" -mindepth 1 | sed "s|^$T/wtmp/||")"

done_tests state-file_test
