#!/usr/bin/env bash
# dispatch-common_test.sh -- the dispatch helpers: topic validation, niwa's
# session-name slug and exact match, the guarded workspace-root lookup, and
# the entry-point table reader, a repository's visibility read, and the
# invocation and mode builders with a review-level bound.
#
# The workspace-root cases build real directory layouts: a root, an instance
# under it, a clone inside the instance carrying its own .niwa/workspace.toml
# (a workspace's config clone does), the root itself (which carries
# .niwa/instance.json too), and a directory outside any workspace.
#
# Usage: bash skills/coordinate/scripts/dispatch-common_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-common-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
yes() { if "${@:2}"; then ok "$1"; else bad "$1" "expected success"; fi; }
no()  { if "${@:2}"; then bad "$1" "expected failure"; else ok "$1"; fi; }

# a_times <n>: n letter a's, without seq (not on run-tests.sh's PATH).
a_times() { local i=0 out=""; while [ "$i" -lt "$1" ]; do out="${out}a"; i=$((i + 1)); done; printf '%s' "$out"; }

# --- topics -----------------------------------------------------------------------

yes "topic: plain"               dc_valid_topic coordinate-dispatch-path
yes "topic: digits"              dc_valid_topic f3-2
no  "topic: empty"               dc_valid_topic ""
no  "topic: leading dash"        dc_valid_topic -x
no  "topic: uppercase"           dc_valid_topic Foo
no  "topic: underscore"          dc_valid_topic foo_bar
no  "topic: slash"               dc_valid_topic ../x
no  "topic: dot"                 dc_valid_topic a.b
no  "topic: 65 characters"       dc_valid_topic "$(a_times 65)"

# --- niwa's slug and the exact session match ---------------------------------------

eq  "slug: dashes to underscores" coordinate_dispatch_path "$(dc_niwa_slug coordinate-dispatch-path)"
eq  "slug: runs collapse"         a_b "$(dc_niwa_slug 'a--b')"
eq  "slug: capped at 40"          "$(a_times 40)" "$(dc_niwa_slug "$(a_times 45)")"
eq  "slug: cap re-trims _"        "$(a_times 39)" "$(dc_niwa_slug "$(a_times 39)-bbb")"

yes "match: slug and token"       dc_session_matches api api-1a2b3c4d
yes "match: dashed topic"         dc_session_matches api-v2 api_v2-1a2b3c4d
no  "match: never a prefix"       dc_session_matches api api_v2-1a2b3c4d
no  "match: token too short"      dc_session_matches api api-1a2b3c4
no  "match: token not hex"        dc_session_matches api api-1a2b3c4z
no  "match: token uppercase"      dc_session_matches api api-1A2B3C4D
no  "match: trailing text"        dc_session_matches api api-1a2b3c4d-x

# --- the workspace root -------------------------------------------------------------

W="$T/ws"
mkdir -p "$W/.niwa" "$W/inst/.niwa" "$W/inst/public/config/.niwa" "$W/inst/public/app/src" "$T/elsewhere"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
: >"$W/inst/.niwa/instance.json"
: >"$W/inst/public/config/.niwa/workspace.toml"

eq  "root: from inside an instance"     "$W" "$(dc_workspace_root "$W/inst/public/app/src")"
eq  "root: from the instance itself"    "$W" "$(dc_workspace_root "$W/inst")"
eq  "root: a clone's workspace.toml is never taken" "$W" "$(dc_workspace_root "$W/inst/public/config")"
eq  "root: at the root, which also has instance.json" "$W" "$(dc_workspace_root "$W")"
no  "root: outside any workspace"       dc_workspace_root "$T/elsewhere"

O="$T/orphan"
mkdir -p "$O/inst/.niwa"
: >"$O/inst/.niwa/instance.json"
no  "root: an instance whose parent isn't a root" dc_workspace_root "$O/inst"

N="$T/noinst"
mkdir -p "$N/.niwa" "$N/sub"
: >"$N/.niwa/workspace.toml"
eq  "root: a root with no instance marker, from itself" "$N" "$(dc_workspace_root "$N")"
no  "root: below a markerless root, no walk-up to a lone workspace.toml" dc_workspace_root "$N/sub"

# --- the entry-point table -----------------------------------------------------------

eq  "entry: scope's leg"            scope "$(dc_entry_field scope 2)"
eq  "entry: execute's templates"    execute.md,execute-coordinated.md "$(dc_entry_field execute 3)"
eq  "entry: deliver answers its leg" deliver "$(dc_entry_field deliver 2)"
eq  "entry: work-on pins nothing" - "$(dc_entry_field work-on 4)"
eq  "entry: explore has no leg" - "$(dc_entry_field explore 2)"
no  "entry: unknown skill"          dc_entry_row nope
yes "flag: exact"                   dc_flag_allowed deliver --no-merge
yes "flag: wildcard value"          dc_flag_allowed scope --max-rounds=3
no  "flag: wildcard needs a value"  dc_flag_allowed scope --max-rounds=
no  "flag: not listed"              dc_flag_allowed deliver --merge
no  "flag: --koto-leg never listed" dc_flag_allowed scope --koto-leg=r:scope
no  "flag: --upstream never listed" dc_flag_allowed scope --upstream
no  "flag: coordinate allows none"  dc_flag_allowed coordinate --auto
no  "flag: with whitespace"         dc_flag_allowed deliver '--auto x'

# The target visibility an entry point requires, from a stand-in table: a
# row without the field reads as any, and a value outside the three is an
# error rather than a pass.
VT="$T/vis-entry-points.tsv"
printf 'a\t-\t-\t-\t-\n' >"$VT"
printf 'b\t-\t-\t-\t-\tpublic\twork-on\n' >>"$VT"
printf 'c\t-\t-\t-\t-\tsecret\t-\n' >>"$VT"
SAVED="$DC_ENTRY_POINTS"
DC_ENTRY_POINTS="$VT"
eq  "visibility: a row without the field is any" any "$(dc_entry_target_visibility a)"
eq  "visibility: a restricted row reads its value" public "$(dc_entry_target_visibility b)"
eq  "visibility: the alternative is field 7" work-on "$(dc_entry_field b "$DC_F_INSTEAD")"
dc_entry_target_visibility c >/dev/null; eq "visibility: an unknown value is an error (2)" 2 "$?"
dc_entry_target_visibility nope >/dev/null; eq "visibility: no row is 1" 1 "$?"
DC_ENTRY_POINTS="$SAVED"

# dc_repo_visibility reads gh api repos/<r>, through a gh stand-in.
GHB="$T/ghvis"
mkdir -p "$GHB"
cat >"$GHB/gh" <<'EOF'
#!/usr/bin/env bash
case "${@: -1}" in
    repos/o/pub) printf '{"visibility":"public"}\n' ;;
    repos/o/priv) printf '{"visibility":"private"}\n' ;;
    repos/o/int) printf '{"visibility":"internal"}\n' ;;
    repos/o/none) printf '{}\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$GHB/gh"
eq  "repo visibility: public" public "$(PATH="$GHB:$PATH" dc_repo_visibility o/pub)"
eq  "repo visibility: private" private "$(PATH="$GHB:$PATH" dc_repo_visibility o/priv)"
eq  "repo visibility: internal reads as private" private "$(PATH="$GHB:$PATH" dc_repo_visibility o/int)"
OUT=$(PATH="$GHB:$PATH" dc_repo_visibility o/none); RC=$?
eq  "repo visibility: no visibility field is 2, nothing printed" "2:" "$RC:$OUT"
OUT=$(PATH="$GHB:$PATH" dc_repo_visibility o/gone); RC=$?
eq  "repo visibility: a failed read is 2, nothing printed" "2:" "$RC:$OUT"

# --- the deadline ----------------------------------------------------------------------

dc_with_deadline 5 true; eq "deadline: a quick command's status" 0 "$?"
dc_with_deadline 5 false; eq "deadline: a failing command's status" 1 "$?"
START=$(date +%s)
dc_with_deadline 1 sleep 20; RC=$?
eq  "deadline: a command past it is 124" 124 "$RC"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "deadline: returns at the deadline"; else bad "deadline: returns at the deadline" ""; fi
# No watcher sleep outlives a quick command: its sleep length is unique to
# this run, so any process still running it afterwards is this run's leak.
LEN=$(( 40000 + $$ % 10000 ))
dc_with_deadline "$LEN" true
sleep 1
if ! command -v ps >/dev/null 2>&1; then
    ok "deadline: no watcher left behind (not checked: ps isn't on this PATH)"
elif ps -eo args | grep -q "^sleep $LEN\$"; then
    bad "deadline: no watcher left behind" "$(ps -eo pid,args | grep "sleep $LEN")"
else
    ok "deadline: no watcher left behind"
fi
OUT=$(dc_with_deadline 30 echo hi); eq "deadline: output passes through a \$(...) promptly" hi "$OUT"

# --- the invocation and the holding's mode ---------------------------------------------
#
# A review_level adds its flags after the entry flags and before --koto-leg;
# the mode cell leaves them out, so a re-brief that rebuilds run_mode from it
# and keeps review_level doesn't give them twice.

printf '%s' '{"entry_point":"work-on","entry_args":["#12"],"run_mode":"--auto"}' >"$T/inv.json"
eq  "invocation: without a review level" "/shirabe:work-on #12 --auto" "$(dc_invocation "$T/inv.json")"
eq  "invocation: with a leg" "/shirabe:work-on #12 --auto --koto-leg=r_1:work-on" "$(dc_invocation "$T/inv.json" r_1:work-on)"
jq -c '.review_level = {"ceiling": "standard", "floor": "light"}' "$T/inv.json" >"$T/inv-rl.json"
eq  "invocation: the bound, floor first, before the leg" \
    "/shirabe:work-on #12 --auto --review-floor=light --review-ceiling=standard --koto-leg=r_1:work-on" \
    "$(dc_invocation "$T/inv-rl.json" r_1:work-on)"
jq -c '.review_level = {"ceiling": "standard"}' "$T/inv.json" >"$T/inv-c.json"
eq  "invocation: a ceiling alone" "/shirabe:work-on #12 --auto --review-ceiling=standard" "$(dc_invocation "$T/inv-c.json")"
eq  "mode: leaves the bound out" "--auto" "$(dc_mode "$T/inv-rl.json")"
jq -c --arg m "$(dc_mode "$T/inv-rl.json")" '.run_mode = $m | .entry_args = [.entry_args[0]]' "$T/inv-rl.json" >"$T/inv-re.json"
eq  "mode: a re-brief from the mode cell gives the bound once" \
    "/shirabe:work-on #12 --auto --review-floor=light --review-ceiling=standard" "$(dc_invocation "$T/inv-re.json")"

# The table against the skills it names: every skill exists, every template a
# leg admits exists and declares each pinned variable, and every flag's stem
# is one the skill's own SKILL.md mentions. A skill that renames a flag or a
# template shows up here, not at a worker's attach.
SKILLS="$HERE/../.."
while IFS='	' read -r skill leg tpls pinned flags vis instead; do
    case "$skill" in '' | '#'*) continue ;; esac
    [ -f "$SKILLS/$skill/SKILL.md" ] && ok "table: $skill exists" || bad "table: $skill exists" ""
    case "$vis" in
        any | public | private) [ -n "$instead" ] && ok "table: $skill's target visibility is any, public or private" ||
            bad "table: $skill's row has seven fields" "" ;;
        *) bad "table: $skill's target visibility is any, public or private" "[$vis]" ;;
    esac
    # Every shipped row carries all seven fields: a row cut short would read as
    # unrestricted, so the table itself is held to its full shape.
    if [ "$instead" = - ] || dc_entry_row "$instead" >/dev/null; then
        ok "table: $skill's alternative is - or an entry point"
    else
        bad "table: $skill's alternative is - or an entry point" "[$instead]"
    fi
    if [ "$tpls" != - ]; then
        IFS=, read -r -a TS <<EOF
$tpls
EOF
        for t in "${TS[@]}"; do
            f="$SKILLS/$skill/koto-templates/$t"
            [ -f "$f" ] && ok "table: $skill admits $t, which exists" || bad "table: $skill admits $t, which exists" "$f"
            if [ "$pinned" != - ]; then
                IFS=, read -r -a PS <<EOF
$pinned
EOF
                for p in "${PS[@]}"; do
                    grep -Eq "^  ${p%%=*}:" "$f" && ok "table: $t declares ${p%%=*}" || bad "table: $t declares ${p%%=*}" ""
                done
            fi
        done
    fi
    if [ "$flags" != - ]; then
        IFS=, read -r -a FS <<EOF
$flags
EOF
        for fl in "${FS[@]}"; do
            stem=${fl%%=*}
            grep -Fq -- "$stem" "$SKILLS/$skill/SKILL.md" && ok "table: $skill documents $stem" || bad "table: $skill documents $stem" ""
        done
    fi
done <"$DC_ENTRY_POINTS"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
