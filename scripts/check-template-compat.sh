#!/usr/bin/env bash
# check-template-compat.sh -- keep a koto template's compat table honest.
#
# A coordinate run is resumed or imported by another plugin version, or from
# another plugin root, when the compat table shipped beside its template
# (`<template>.compat.json`, e.g. coordinate.compat.json) lists the structure
# of the template the run was compiled from at the table's compat number
# (coord-log.sh provenance). That is only safe while the number moves whenever
# what a run does changes, and this check is what makes it move:
#
#   - the template's structure, its fingerprint, is listed in `fingerprints`
#     at `compat`. The fingerprint is the sha256 of the compiled template run
#     through template-fingerprint.jq (beside the skill's scripts): the
#     initial state, the variables and every state's accepts, gates, actions
#     and transitions, with every description, directive and details text and
#     a variable's `rebind` flag left out, since none of them changes what a
#     run does. It doesn't depend on the bytes koto writes, so the table holds
#     across koto versions;
#   - `gate_scripts` is the digest of every script the template's gates and
#     actions invoke and everything those scripts source or run through
#     `$HERE`, so a script whose meaning may have changed without the template
#     changing (a gate's exit 1 meaning something new) can't land unnoticed;
#   - against the base branch's table (--base-table), compat never goes down,
#     and a structure the base doesn't list comes with a compat number above
#     the base's.
#
# Recording a new `gate_scripts` digest at the same compat number is the
# author's statement that the scripts' change keeps their meaning. A run is
# told apart by its structure alone, so raising `compat` over a structure the
# base already lists would admit the base's runs just the same, and is
# refused (`raise-needs-structure`): a script change that alters what a run
# does changes how the template invokes it too (a new flag, a new script
# name), and that new structure is listed at the raised number.
#
# Usage:
#   check-template-compat.sh --template T [--base-table F] [--compiled J]
#   check-template-compat.sh --template T --print [--compiled J]
#
# --compiled is the compiled template JSON (koto template compile's output);
# without it the template is compiled with koto. --print prints the computed
# {"fingerprint","gate_scripts"} for an author to record.
#
# Exit 0 the table holds; 1 a rule fails (one `check-template-compat: <rule>:`
# line per failure on stderr); 2 the check couldn't decide (no koto, an
# unreadable template, table or base table); 64 usage.
set -uo pipefail

PROG=check-template-compat
usage() { sed -n '/^# Usage:/,/^# Exit/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die2() { echo "$PROG: $*" >&2; exit 2; }

TEMPLATE= BASE= COMPILED= PRINT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --template) [ $# -ge 2 ] || usage; TEMPLATE=$2; shift 2 ;;
        --base-table) [ $# -ge 2 ] || usage; BASE=$2; shift 2 ;;
        --compiled) [ $# -ge 2 ] || usage; COMPILED=$2; shift 2 ;;
        --print) PRINT=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$TEMPLATE" ] || usage
[ -r "$TEMPLATE" ] || die2 "can't read $TEMPLATE"

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
    else shasum -a 256 | cut -d' ' -f1; fi
}

SCRIPTS_DIR=$(cd "$(dirname "$TEMPLATE")/../scripts" 2>/dev/null && pwd) || die2 "no scripts directory beside $TEMPLATE"
FP_PROGRAM=$SCRIPTS_DIR/template-fingerprint.jq
[ -r "$FP_PROGRAM" ] || die2 "no template-fingerprint.jq in $SCRIPTS_DIR"

if [ -z "$COMPILED" ]; then
    command -v "${KOTO_BIN:-koto}" >/dev/null 2>&1 || die2 "koto isn't installed, so $TEMPLATE can't be compiled"
    COMPILED=$("${KOTO_BIN:-koto}" template compile "$TEMPLATE" </dev/null) || die2 "$TEMPLATE doesn't compile"
fi
[ -r "$COMPILED" ] || die2 "can't read the compiled template $COMPILED"

STRUCTURE=$(jq -S -c -f "$FP_PROGRAM" "$COMPILED") || die2 "can't read the compiled template $COMPILED"
# The fingerprint comes from the same script coord-log.sh hashes a run's copy
# with, so the table CI records is the one a resume compares against.
FINGERPRINT=$(bash "$SCRIPTS_DIR/template-fingerprint.sh" "$COMPILED") || die2 "can't fingerprint the compiled template $COMPILED"

# The scripts the structure invokes by name, then everything they reach
# through $HERE, until nothing new turns up. A path is kept relative to the
# scripts directory beside the template's skill.
LIST=$(printf '%s' "$STRUCTURE" | jq -r '[.. | strings | scan("/scripts/([A-Za-z0-9_][A-Za-z0-9_./-]*\\.sh)") | .[0]] | unique | .[]')
NL='
'
SEEN=
while [ -n "$LIST" ]; do
    NEXT=
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        # A membership test with no pipe: `printf | grep -q` under pipefail can
        # read a match as a miss when grep stops first and printf takes SIGPIPE.
        case "$NL$SEEN$NL" in *"$NL$rel$NL"*) continue ;; esac
        [ -f "$SCRIPTS_DIR/$rel" ] || continue
        SEEN="$SEEN$NL$rel"
        NEXT=$(printf '%s\n%s' "$NEXT" "$(grep -oE '\$HERE/[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sh|jq|tsv)' "$SCRIPTS_DIR/$rel" | sed 's|^\$HERE/||' | sort -u)")
    done <<EOF
$LIST
EOF
    LIST=$NEXT
done
GATE_SCRIPTS=$(printf '%s\n' "$SEEN" | grep -v '^$' | LC_ALL=C sort | while IFS= read -r rel; do
    printf '%s %s\n' "$rel" "$(sha256 < "$SCRIPTS_DIR/$rel")"
done | sha256)

if [ "$PRINT" = 1 ]; then
    jq -nc --arg f "$FINGERPRINT" --arg g "$GATE_SCRIPTS" '{fingerprint: $f, gate_scripts: $g}'
    exit 0
fi

TABLE=${TEMPLATE%.md}.compat.json
[ -r "$TABLE" ] || die2 "no compat table at $TABLE"
WELL_FORMED='type == "object"
    and (.compat | type == "number" and . >= 1 and . == floor)
    and (.gate_scripts | type == "string" and test("^[0-9a-f]{64}$"))
    and (.fingerprints | type == "object" and length > 0
         and all(to_entries[]; (.key | test("^[0-9a-f]{64}$")) and (.value | type == "number" and . >= 1 and . == floor)))'
jq -e "$WELL_FORMED" "$TABLE" >/dev/null 2>&1 || die2 "$TABLE isn't a compat table (compat, fingerprints, gate_scripts)"

FAILS=0
fail() { echo "$PROG: $1: $2" >&2; FAILS=$((FAILS + 1)); }
COMPAT=$(jq -r '.compat' "$TABLE")
LISTED=$(jq -r --arg f "$FINGERPRINT" '.fingerprints[$f] // empty' "$TABLE")
[ "$LISTED" = "$COMPAT" ] \
    || fail fingerprint "the template's structure is $FINGERPRINT; list it in fingerprints at compat $COMPAT, raising compat first when a run's behaviour changed"
jq -e '.compat >= ([.fingerprints[]] | max)' "$TABLE" >/dev/null 2>&1 \
    || fail compat-below "a fingerprint is listed above compat $COMPAT"
[ "$(jq -r '.gate_scripts' "$TABLE")" = "$GATE_SCRIPTS" ] \
    || fail gate-scripts "a script the template's gates or actions reach changed (digest $GATE_SCRIPTS); record the digest as gate_scripts, and if what the script means to a run changed, change how the template invokes it and list that structure at a raised compat"

if [ -n "$BASE" ]; then
    [ -r "$BASE" ] || die2 "can't read the base table $BASE"
    jq -e "$WELL_FORMED" "$BASE" >/dev/null 2>&1 || die2 "the base table $BASE isn't a compat table"
    BASE_COMPAT=$(jq -r '.compat' "$BASE")
    [ "$COMPAT" -ge "$BASE_COMPAT" ] || fail compat-down "compat went from $BASE_COMPAT down to $COMPAT"
    if [ -z "$(jq -r --arg f "$FINGERPRINT" '.fingerprints[$f] // empty' "$BASE")" ]; then
        [ "$COMPAT" -gt "$BASE_COMPAT" ] \
            || fail structure "the template's structure is one the base doesn't list, so a run compiled from the base can't be driven the same way; raise compat above $BASE_COMPAT"
    elif [ "$COMPAT" -gt "$BASE_COMPAT" ]; then
        fail raise-needs-structure "compat went from $BASE_COMPAT to $COMPAT over a structure the base already lists; runs are told apart by structure, so the base's runs would still be admitted. Change how the template invokes what changed (a new flag or script name) and list that structure at $COMPAT, or keep compat at $BASE_COMPAT"
    fi
    jq -e --slurpfile b "$BASE" '. as $t | all($b[0].fingerprints | to_entries[]; . as $e | $t.fingerprints[$e.key] == null or $t.fingerprints[$e.key] == $e.value)' "$TABLE" >/dev/null 2>&1 \
        || fail renumbered "a fingerprint the base lists changed its compat number; a structure keeps the number it shipped with"
fi
[ "$FAILS" -eq 0 ] || exit 1
echo "$PROG: $TABLE holds: structure $FINGERPRINT at compat $COMPAT"
