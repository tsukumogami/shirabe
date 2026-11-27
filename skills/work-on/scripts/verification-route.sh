#!/usr/bin/env bash
# verification-route.sh -- the hosted-of-record route: whether a timed-out
# verification may stand on the hosted jobs that run the same suites, the
# record of taking it, and the read that settles that record.
# Part of the work-on skill
#
# A verification check that timed out locally, with no check failed, may be
# settled by the hosted job its map row declares (`hosted`), run at the same
# head on the pull request. This script holds every decision the route makes,
# so the verdict, the gates and the body check share one implementation:
# check-verification.sh sources it for --open's check (in-process, never a
# second process), check-pr-output.sh sources it for the body-line check, and
# the work-on template's gates run its modes.
#
#   --open --session <s> [--shared-branch <v>]
#       0 the route is open for this head's stored result; 1 it is closed,
#       one stderr line per cause (all of them, not the first); 2 usage or a
#       missing tool. A routing gate: no finding. Closed by: no result, or one
#       for another head or merge-base; a supervisor-error, dirty-tree, no-map,
#       bad-map or attended result; a result that predates the route (no
#       finished_at, or a record without outcome or check); a not-started or
#       runaway command; a failed check; a budget stop that left commands
#       unstarted; no timed-out check; a timed-out check whose row in the
#       merge-base's map declares no hosted jobs; a missing or bad map at the
#       merge-base; a dirty tree; a diff from the merge-base touching a path
#       that decides what the hosted job runs (vr_closing_paths), or a
#       check-skill.tsv edited other than by added rows (both vr_diff_check).
#       A child of /execute is not refused: /execute collects its record for
#       the shared or node pull request (--collect). --shared-branch is
#       accepted and no longer read.
#   --record [--reason <text>] [--head <sha> --child <session>@<head>]...
#       Writes the koto key hosted_of_record, replacing any earlier one. The
#       reason is --reason, else the context key hosted_route_reason, cleaned
#       by vr_sanitize_reason; empty is 1. For the run's own result the route
#       must be open (1 with the causes otherwise). With --child (a parent run
#       recording for a shared or node pull request's head, given by --head),
#       each named child's stored result supplies parts that carry `session`
#       and `result_head`; the parent checks the diff itself. koto failing is
#       2.
#   --check-record [--head <sha>]
#       0 the key is valid for <sha> (default HEAD), 1 it isn't
#       (vr_validate_record; causes on stderr), 2 it can't be read (absent, or
#       koto failing).
#   --read [--head <sha>]
#       Reads each recorded job's latest attempt at the record's head from the
#       Actions API. 0 every job concluded success: the key is filled with
#       run_id, conclusion and attempt, and the body's lines are rewritten with
#       run links (gh pr edit --body-file, only when the body changed). 1 a
#       refusal (a job concluded anything else, zero or two jobs of the
#       declared name in a completed run, an unreadable response, the pull
#       request's head is not the record's, a cross-repository pull request,
#       an invalid record), one stderr line per refusing job naming check, job
#       and commit. 75 a job is pending, queued or absent and 120 minutes have
#       not passed since taken_at. 3 the same past 120 minutes: failure_reason
#       is written to koto context naming the jobs and the commit. 2 the key
#       can't be read, or a write failed. The wait is measured from taken_at,
#       so it is not charged to the 7,200 s run budget.
#   --settled [--head <sha>]
#       0 no key; 0 the key validates, every run_id is filled, and each filled
#       run, re-read from the API, is the declared workflow's pull_request run
#       for this pull request at the record's head, at the recorded attempt,
#       holding exactly one job of the declared name concluded success. 1 any
#       of that fails (a hand-filled key fails here, which sends the run to
#       the read). 2 the key or the pull request can't be read. Draft or not
#       doesn't matter.
#   --ready [--head <sha>]
#       0 --settled holds for an existing key, the pull request is no longer a
#       draft and every body line carries its run links; 1 otherwise (no key
#       is 1 here); 2 can't read.
#   --mark-ready [--head <sha>]
#       Re-reads the pull request's head; when it is still the record's and
#       --settled holds, runs `gh pr ready`. 1 otherwise, saying why.
#   --lines
#       Prints one `Hosted of record:` line per recorded check and the reason
#       line, for a key at the current head; 1 when there is none. The agent
#       puts them in the body verbatim; it never types them.
#   --collect --head <sha> [--base <ref>] [--child <session>]...
#       /execute's record for a shared or node pull request at <sha>, built
#       from the children's own hosted_of_record keys (the children named, or
#       every child `koto workflows --children <s>` lists). Each child's key
#       must validate against that child's stored result and map, and the
#       whole diff from the merge-base of <ref> (default origin's default
#       branch) and <sha> must pass vr_diff_check. The key gets the union of
#       the children's checks (each part naming its child), one reason built
#       from the children's (each distinct one once, in the children's
#       order), and taken_at from this clock. A key that already validates at
#       <sha> is kept, so its taken_at goes on measuring the wait. 0 recorded
#       or kept; 4 no child took the route (nothing written); 1 refused
#       (causes on stderr; nothing written); 2 can't read or write.
#   --parent-read --pr <url> [--base <ref>] [--child <session>]...
#       --collect at the pull request's head, then --read over that key. No
#       child took the route: 0, nothing read. Otherwise --collect's 1 or 2,
#       or --read's exit.
#
# Options for every mode but --open: --key <k> names the key
# (hosted_of_record, or run/hosted/<node> for a coordinated node's record);
# --pr <url> names the pull request, in place of context's pr_url or the
# checked-out branch; --work-tree <dir> runs the git reads there (a node's
# worktree; --collect stores it in the key as work_tree, and a later read of
# the key uses it when no --work-tree is given); --child-dir <dir> runs the
# children's koto reads there (a coordinated node's worktree, where its work
# items' sessions were opened). --read --dry-run decides as --read does and
# writes nothing (no key, no body edit, no failure_reason). --ready
# --absent-ok answers 0 when there is no key. --mark-ready --absent-ok --pr
# <url>, with no key, runs `gh pr ready <url>` when no child (as --collect
# finds them) holds hosted_of_record, and refuses (1) while one does: it is a
# parent's ready call, the plain one when nobody took the route. Without them
# every mode behaves as it did before they existed. --parent-read with no
# child record reads nothing from GitHub.
#
# The key hosted_of_record:
#   {"head", "taken_at", "reason",
#    "checks": [{"id", "session"?, "result_head"?,
#                "jobs": [{"workflow", "job", "run_id", "conclusion", "attempt"}]}]}
# `session`/`result_head` are absent for the run's own checks, whose result is
# the run's own at the record's head; a part that has them names a child's
# stored result. run_id, conclusion and attempt are null until --read fills
# them.
#
# Functions (the contract for check-verification.sh, check-pr-output.sh and
# /execute parity): vr_now, vr_locate, vr_map_at, vr_timed_out_checks,
# vr_closing_paths, vr_diff_check, vr_open_check, vr_sanitize_reason,
# vr_validate_record, vr_body_line, vr_neutral, vr_reason_line, vr_body_check,
# vr_pr_object, vr_runs, vr_job, vr_child_checks. Each sets VR_* globals
# rather than printing where a caller needs more than one value; VR_CAUSES is
# a newline list of causes.
#
# Seams: SHIRABE_ROUTE_NOW (epoch seconds; the clock) and
# SHIRABE_ROUTE_MAX_PAGES (default 10; pages of runs or jobs read before the
# answer counts as unreadable). koto's cleared gate environment never carries
# either.
#
# Sourceable: everything is a vr_* function and every global is VR_*; the CLI
# runs only when this file is executed. Written for the bash 3.2 floor,
# without `set -e`; jq values only through --arg and --argjson.

set -u

VR_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VR_MAP_PATH=.claude/shirabe-extensions/verification-map.json
VR_MAP_SCHEMA=shirabe-verification-map/v1
VR_RESULT_SCHEMA=shirabe-verification-result/v1
VR_KEY=hosted_of_record
VR_REASON_KEY=hosted_route_reason
# The hosted wait, from taken_at: past it a pending job ends the run (exit 3).
VR_WAIT_SECS=7200
VR_REASON_MAX=300
VR_LINE_PREFIX='Hosted of record: '
# The paths that decide what the hosted job runs, besides the libraries and
# helpers the merge-base's skill-gate.sh and check-skill.sh name. A trailing
# `/` is a prefix.
VR_CLOSING_FIXED='.github/
scripts/skill-gate.sh
scripts/check-skill.sh
.claude/shirabe-extensions/verification-map.json
skills/work-on/scripts/verification-hosted-coverage_test.sh'
VR_SESSION_RE='^[A-Za-z0-9._][A-Za-z0-9._-]*$'
VR_SHA_RE='^[0-9a-f]{40}$'
VR_KEY_RE='^(hosted_of_record|run/hosted/[a-z][a-z0-9-]*)$'
VR_CAUSES=""
VR_TMP=""
# --work-tree, --child-dir and --pr; empty is the current directory, and the
# pull request pr_url or the branch names.
VR_WT=""
VR_CHILD_DIR=""
VR_PR_OPT=""
VR_BASE_OPT=""
VR_DRY=0
VR_ABSENT_OK=0

# vr_root: the top of the work tree the git reads run in.
vr_root() {
    if [ -n "$VR_WT" ]; then
        git -C "$VR_WT" rev-parse --show-toplevel
    else
        git rev-parse --show-toplevel
    fi
}

# vr_child_koto <koto arguments>...: a koto call for a child's session, run
# in --child-dir when one was given.
vr_child_koto() {
    if [ -n "$VR_CHILD_DIR" ]; then
        (CDPATH='' cd -- "$VR_CHILD_DIR" && exec koto "$@")
    else
        koto "$@"
    fi
}

vr_say() {
    echo "verification-route: $*" >&2
}

# vr_cause <text>: add a cause to VR_CAUSES.
vr_cause() {
    if [ -z "$VR_CAUSES" ]; then
        VR_CAUSES=$1
    else
        VR_CAUSES="$VR_CAUSES
$1"
    fi
}

# vr_print_causes <prefix>: one stderr line per cause.
vr_print_causes() {
    local c
    while IFS= read -r c; do
        [ -n "$c" ] && vr_say "$1$c"
    done <<EOF
$VR_CAUSES
EOF
}

# vr_now: the clock, in epoch seconds.
vr_now() {
    case "${SHIRABE_ROUTE_NOW:-}" in
        ''|*[!0-9]*) date +%s ;;
        *) printf '%s\n' "$SHIRABE_ROUTE_NOW" ;;
    esac
}

# vr_iso <epoch>: UTC ISO-8601, the form fromdateiso8601 reads back.
vr_iso() {
    jq -rn --argjson t "$1" '$t | todate'
}

vr_pr_url_lib() {
    command -v pr_url_parse >/dev/null 2>&1 && return 0
    # shellcheck source=pr-url.sh
    . "$VR_HERE/pr-url.sh" || { vr_say "cannot load $VR_HERE/pr-url.sh"; return 1; }
}

# vr_tmp: a scratch directory for this process, made once. The CLI removes it
# on exit; a sourcing caller that uses a mode needing it calls vr_cleanup.
vr_tmp() {
    [ -n "$VR_TMP" ] && return 0
    VR_TMP=$(mktemp -d "${TMPDIR:-/tmp}/verification-route.XXXXXX") || { VR_TMP=""; vr_say "could not create a temporary directory"; return 1; }
}

vr_cleanup() {
    [ -z "$VR_TMP" ] || rm -rf "$VR_TMP"
    VR_TMP=""
    return 0
}

# --- where things are ------------------------------------------------------------------

# vr_locate <session> [<head>]: sets VR_LOC_HEAD, VR_LOC_MB and VR_LOC_RESULT.
# Without a head, the run's own result through run-verification.sh --locate,
# which owns the path rules. With one (a part of a record: own at the
# record's head, or a child's), the result stored for that session and head;
# VR_LOC_MB is then empty and comes from the result.
vr_locate() {
    local loc state
    VR_LOC_HEAD=""; VR_LOC_MB=""; VR_LOC_RESULT=""
    grep -Eq "$VR_SESSION_RE" <<<"$1" && [ "$1" != . ] && [ "$1" != .. ] || return 1
    if [ $# -ge 2 ] && [ -n "$2" ]; then
        grep -Eq '^[0-9a-f]+$' <<<"$2" || return 1
        state=${XDG_STATE_HOME:-}
        if [ -z "$state" ]; then
            [ -n "${HOME:-}" ] || return 1
            state="$HOME/.local/state"
        fi
        VR_LOC_HEAD=$2
        VR_LOC_RESULT="$state/shirabe/verification/$1/$2/result.json"
        return 0
    fi
    loc=$("$VR_HERE/run-verification.sh" --locate --session "$1") || return 1
    VR_LOC_HEAD=$(sed -n 1p <<<"$loc")
    VR_LOC_MB=$(sed -n 2p <<<"$loc")
    VR_LOC_RESULT=$(sed -n 3p <<<"$loc")
    [ -n "$VR_LOC_RESULT" ]
}

# vr_map_at <root> <mb>: sets VR_MAP to the map at the merge-base, compact;
# returns 1 with VR_MAP_ERR when it is missing or is no map. The declaration
# is read from the merge-base like the rest of the map, so a branch can't
# declare its own hosted coverage.
vr_map_at() {
    local entry
    VR_MAP=""; VR_MAP_ERR=""
    entry=$(git -C "$1" ls-tree "$2" -- "$VR_MAP_PATH") \
        || { VR_MAP_ERR="could not list $VR_MAP_PATH at $2"; return 1; }
    [ -n "$entry" ] || { VR_MAP_ERR="no $VR_MAP_PATH at the merge-base $2"; return 1; }
    VR_MAP=$(git -C "$1" show "$2:$VR_MAP_PATH") \
        || { VR_MAP=""; VR_MAP_ERR="could not read $VR_MAP_PATH at $2"; return 1; }
    if ! jq -se --arg s "$VR_MAP_SCHEMA" \
            'length == 1 and (.[0] | type == "object" and .schema == $s and (.commands | type) == "object")' \
            <<<"$VR_MAP" >/dev/null; then
        VR_MAP=""; VR_MAP_ERR="$VR_MAP_PATH at $2 is not a $VR_MAP_SCHEMA map"
        return 1
    fi
    VR_MAP=$(jq -c . <<<"$VR_MAP") || { VR_MAP=""; VR_MAP_ERR="could not read $VR_MAP_PATH at $2"; return 1; }
}

# vr_timed_out_checks <result file> <map json>: a JSON array, one object per
# timed-out record: {id: its check id, row: its row id, jobs: the row's
# declared [{workflow, job}] ([] when the row declares none)}.
vr_timed_out_checks() {
    jq -c --argjson map "$2" '
        [.commands[] | select(.outcome == "timed-out-limit" or .outcome == "timed-out-inside")
         | {id: .check, row: .id, jobs: (($map.commands[.id].hosted // []) | map({workflow, job}))}]' "$1"
}

# vr_closing_paths <root> <mb>: one path per line (a trailing `/` is a
# prefix): VR_CLOSING_FIXED plus every library or helper the merge-base's
# skill-gate.sh and check-skill.sh name, as a path under scripts/ that exists
# at the merge-base. Read from the merge-base's copies, so a branch that adds
# a new sourced helper and edits it is still closed (it has to edit one of the
# two to source it).
vr_closing_paths() {
    local f present src tokens t p
    local -a cands
    cands=()
    printf '%s\n' "$VR_CLOSING_FIXED"
    for f in scripts/skill-gate.sh scripts/check-skill.sh; do
        present=$(git -C "$1" ls-tree --name-only "$2" -- "$f") || return 1
        [ -n "$present" ] || continue
        src=$(git -C "$1" show "$2:$f") || return 1
        # grep exits 1 on no match, which is no token here.
        tokens=$(grep -oE '(\$\{?(SCRIPT_DIR|HERE)\}?/|scripts/)[A-Za-z0-9_./-]+\.(sh|py)' <<<"$src")
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            # $SCRIPT_DIR and $HERE are scripts/, where both files live.
            case "$t" in
                scripts/*) p=$t ;;
                *) p="scripts/${t#*/}" ;;
            esac
            case "/$p/" in */../*|*/./*|*//*) continue ;; esac
            cands+=("$p")
        done <<EOF
$tokens
EOF
    done
    [ "${#cands[@]}" -gt 0 ] || return 0
    # ls-tree prints the candidates that exist at the merge-base and nothing
    # for the rest.
    git -C "$1" ls-tree --name-only "$2" -- "${cands[@]}" || return 1
}

# vr_open_check <session> <head> <mb> <result> [<shared-branch>]: sets
# VR_CAUSES; 0 the route is open, 1 it is closed. Every cause is collected.
# The shared branch is no longer read: a child of /execute takes the route
# like any run, and /execute collects its record.
vr_open_check() {
    local head=$2 mb=$3 result=$4 root="" inv=null runf facts checks dirty c
    VR_CAUSES=""
    root=$(vr_root) || { vr_cause "not inside a git working tree"; root=""; }

    if [ ! -f "$result" ]; then
        vr_cause "no verification result for $head (looked for $result)"
    else
        runf="$(dirname "$result")/run.json"
        if [ -f "$runf" ]; then
            inv=$(jq '.invocations | length' "$runf") || inv=null
        fi
        if facts=$(jq -r --arg schema "$VR_RESULT_SCHEMA" --arg head "$head" --arg mb "$mb" --argjson inv "$inv" '
            def tout: .outcome == "timed-out-limit" or .outcome == "timed-out-inside";
            if type != "object" or .schema != $schema or (.commands | type) != "array" then
                "the result is not a \($schema) object"
            else
                (if .head != $head then "the result is for head \(.head), not \($head)" else empty end),
                (if .merge_base != $mb then "the result is for merge-base \(.merge_base), not \($mb)" else empty end),
                (.status as $s
                 | if any("supervisor-error", "dirty-tree", "no-map", "bad-map", "attended"; . == $s)
                   then "the result status is \($s): \(.detail // "")" else empty end),
                (if (.finished_at | type) != "string"
                    or any(.commands[]; (.outcome | type) != "string" or (.check | type) != "string")
                 then "the result predates the route (no finished_at, or a record without outcome or check); move it aside and tick to run the checks again"
                 else empty end),
                (.commands[] | select(.not_started == true) | "command \(.check // .id) did not start"),
                (.commands[] | select(.runaway == true) | "command \(.check // .id) grew past its max_procs"),
                (.commands[] | select(.outcome == "failed" and .not_started != true and .runaway != true)
                 | "check \(.check // .id) failed"),
                (if .status == "timed-out" and $inv != null and (.commands | length) < $inv
                 then "\($inv - (.commands | length)) later command(s) were not started" else empty end),
                (if any(.commands[]; tout) then empty else "no check timed out" end)
            end' "$result"); then
            while IFS= read -r c; do
                [ -n "$c" ] && vr_cause "$c"
            done <<EOF
$facts
EOF
        else
            vr_cause "the result $result could not be read"
        fi
    fi

    if [ -n "$root" ]; then
        if ! vr_map_at "$root" "$mb"; then
            vr_cause "missing or bad map: $VR_MAP_ERR"
        elif [ -f "$result" ] && checks=$(vr_timed_out_checks "$result" "$VR_MAP"); then
            while IFS= read -r c; do
                [ -n "$c" ] && vr_cause "$c"
            done <<EOF
$(jq -r '.[] | select((.jobs | length) == 0)
         | "check \(.id) timed out and its row \(.row) declares no hosted jobs in the merge-base map"' <<<"$checks")
EOF
        fi

        if ! dirty=$(git -C "$root" status --porcelain --untracked-files=no); then
            vr_cause "could not read the working tree's status"
        elif [ -n "$dirty" ]; then
            vr_cause "tracked files have uncommitted changes"
        fi

        vr_diff_check "$root" "$mb" "$head"
    fi

    [ -z "$VR_CAUSES" ]
}

# vr_diff_check <root> <mb> <head>: the diff checks every route runs, a
# /work-on run's over its own diff (vr_open_check) and /execute's over a
# shared or node pull request's whole diff (--collect): a path that decides
# what the hosted job runs (vr_closing_paths), and a check-skill.tsv edited
# other than by added rows. Adds one cause per finding to VR_CAUSES (it does
# not clear it); 0 when it added none.
vr_diff_check() {
    local root=$1 mb=$2 head=$3 before=$VR_CAUSES changed closing hits tsv c st p add del
    # Paths only, never renames: a moved file is a deletion and an addition.
    if changed=$(git -C "$root" diff --name-only --no-renames -z "$mb" "$head" \
            | jq -Rsc 'split("\u0000") | map(select(length > 0))'
            s=("${PIPESTATUS[@]}"); [ "${s[0]}" = 0 ] && [ "${s[1]}" = 0 ]) \
        && closing=$(vr_closing_paths "$root" "$mb" | jq -Rsc 'split("\n") | map(select(length > 0))'
            s=("${PIPESTATUS[@]}"); [ "${s[0]}" = 0 ] && [ "${s[1]}" = 0 ]); then
        hits=$(jq -rn --argjson changed "$changed" --argjson closing "$closing" '
            $changed[] | . as $p
            | select(any($closing[]; . as $c | if $c | endswith("/") then $p | startswith($c) else $p == $c end))
            | "the diff from the merge-base touches \($p), which decides what the hosted job runs"')
        while IFS= read -r c; do
            [ -n "$c" ] && vr_cause "$c"
        done <<EOF
$hits
EOF
    else
        vr_cause "could not read the diff from the merge-base $mb, or the paths that close the route"
    fi

    # A check-skill.tsv may only gain rows: an edited or deleted row could
    # change which suites the hosted job runs for the change.
    if tsv=$(git -C "$root" diff --name-status --no-renames "$mb" "$head" -- ':(glob)skills/*/check-skill.tsv'); then
        while IFS="$(printf '\t')" read -r st p; do
            [ -n "$st" ] || continue
            case "$st" in
                A|M) ;;
                *) vr_cause "the diff changes $p (status $st); only added rows keep the route open" ;;
            esac
        done <<EOF
$tsv
EOF
    else
        vr_cause "could not read the check-skill.tsv changes"
    fi
    if tsv=$(git -C "$root" diff --numstat --no-renames "$mb" "$head" -- ':(glob)skills/*/check-skill.tsv'); then
        while IFS="$(printf '\t')" read -r add del p; do
            [ -n "$add" ] || continue
            [ "$del" = 0 ] || vr_cause "the diff edits or deletes rows of $p; only added rows keep the route open"
        done <<EOF
$tsv
EOF
    else
        vr_cause "could not read the check-skill.tsv changes"
    fi
    [ "$VR_CAUSES" = "$before" ]
}

# --- the record ---------------------------------------------------------------------------

# vr_sanitize_reason <text>: the reason as stored: control characters become
# spaces, backticks go, ends are trimmed, and it is capped at VR_REASON_MAX
# characters (then trimmed again, so cleaning a cleaned reason changes
# nothing). jq does it, so the text is never read by a shell.
vr_sanitize_reason() {
    jq -rn --arg r "$1" --argjson max "$VR_REASON_MAX" '
        def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
        $r | gsub("[[:cntrl:]]"; " ") | gsub("`"; "") | trim | .[0:$max] | trim'
}

# vr_validate_record <record json> <head> <session>: sets VR_CAUSES; 0 the
# record is valid for <head>, 1 it isn't.
vr_validate_record() {
    local rec=$1 head=$2 session=$3 shape reason clean now taken groups g gs gh res fin mb part timed out root c
    VR_CAUSES=""
    if ! shape=$(jq -r '
        def pos_or_null: . == null or (type == "number" and . == floor and . > 0);
        if type != "object" then "the record is not a JSON object"
        else
            (if (.head | type) != "string" then "the record has no head" else empty end),
            (if (.taken_at | type) != "string" then "the record has no taken_at" else empty end),
            (if (.reason | type) != "string" then "the record has no reason" else empty end),
            (if (.checks | type) != "array" or (.checks | length) == 0 then "the record lists no checks"
             else (.checks | to_entries[] | .key as $i | .value
                   | if type != "object" or (.id | type) != "string" then "check \($i) of the record has no id"
                     elif (.jobs | type) != "array" or (.jobs | length) == 0 then "check \(.id) lists no jobs"
                     elif (has("session") or has("result_head"))
                          and ((.session | type) != "string" or (.result_head | type) != "string")
                     then "check \(.id) names a session or result_head without the other"
                     else .id as $c | .jobs[]
                       | if type != "object" or (.workflow | type) != "string" or (.job | type) != "string"
                         then "check \($c) has a job without a workflow and a job name"
                         elif (.run_id | pos_or_null | not) then "check \($c), job \(.job): run_id is not null or a positive integer"
                         elif ((.conclusion == null or .conclusion == "success") | not)
                         then "check \($c), job \(.job): conclusion is not null or success"
                         elif (.attempt | pos_or_null | not) then "check \($c), job \(.job): attempt is not null or a positive integer"
                         elif ([.run_id, .conclusion, .attempt] | (all(. == null) or all(. != null)) | not)
                         then "check \($c), job \(.job): run_id, conclusion and attempt are not all null or all set"
                         else empty end
                     end)
             end)
        end' <<<"$rec"); then
        vr_cause "the record is not JSON"
        return 1
    fi
    if [ -n "$shape" ]; then
        while IFS= read -r c; do
            [ -n "$c" ] && vr_cause "$c"
        done <<EOF
$shape
EOF
        return 1
    fi

    reason=$(jq -r '.reason' <<<"$rec")
    clean=$(vr_sanitize_reason "$reason")
    if [ -z "$reason" ]; then
        vr_cause "the record's reason is empty"
    elif [ "$clean" != "$reason" ]; then
        vr_cause "the record's reason holds what --record strips (control characters, backticks, spaces at its ends) or is longer than $VR_REASON_MAX characters"
    fi
    [ "$(jq -r '.head' <<<"$rec")" = "$head" ] \
        || vr_cause "the record is for head $(jq -r '.head' <<<"$rec"), not $head"
    now=$(vr_now)
    if ! taken=$(jq -r '.taken_at | fromdateiso8601 | floor' <<<"$rec") || ! grep -Eq '^[0-9]+$' <<<"$taken"; then
        vr_cause "the record's taken_at [$(jq -r '.taken_at' <<<"$rec")] is not an ISO-8601 time"
        taken=""
    elif [ "$taken" -gt "$now" ]; then
        vr_cause "the record's taken_at is in the future"
    fi

    root=$(vr_root) || { vr_cause "not inside a git working tree"; return 1; }
    # One group per stored result the record's parts come from: the run's own
    # at <head>, and each child's.
    groups=$(jq -r --arg s "$session" --arg h "$head" \
        '[.checks[] | "\(.session // $s) \(.result_head // $h)"] | unique[]' <<<"$rec") \
        || { vr_cause "could not read the record's checks"; return 1; }
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        gs=${g%% *}; gh=${g#* }
        if ! vr_locate "$gs" "$gh"; then
            vr_cause "the record names session [$gs] at [$gh], which is not a session and a head"
            continue
        fi
        res=$VR_LOC_RESULT
        if [ ! -f "$res" ]; then
            vr_cause "no stored verification result for session $gs at $gh"
            continue
        fi
        if ! fin=$(jq -r --arg h "$gh" 'if .head != $h then error("head") else (.finished_at // "" | if . == "" then "" else fromdateiso8601 | tostring end) end' "$res"); then
            vr_cause "the stored result for session $gs at $gh is unreadable or for another head"
            continue
        fi
        if [ -z "$fin" ]; then
            vr_cause "the stored result for session $gs at $gh has no finished_at"
        elif [ -n "$taken" ] && [ "$taken" -lt "$fin" ]; then
            vr_cause "the record's taken_at is before the result for session $gs at $gh finished"
        fi
        # A child's result stands only as /work-on's --open would have let it
        # stand: no check failed, none failed to start or ran away. The run's
        # own result passed --open before it was recorded.
        if [ "$gs" != "$session" ] || [ "$gh" != "$head" ]; then
            out=$(jq -r '.commands[]
                | if .not_started == true then "command \(.check // .id) did not start"
                  elif .runaway == true then "command \(.check // .id) grew past its max_procs"
                  elif .outcome == "failed" then "check \(.check // .id) failed"
                  else empty end' "$res") \
                || { vr_cause "the stored result for session $gs at $gh could not be read"; continue; }
            while IFS= read -r c; do
                [ -n "$c" ] && vr_cause "the result for session $gs at $gh: $c"
            done <<EOF
$out
EOF
        fi
        mb=$(jq -r '.merge_base // ""' "$res")
        if ! vr_map_at "$root" "$mb"; then
            vr_cause "session $gs at $gh: $VR_MAP_ERR"
            continue
        fi
        timed=$(vr_timed_out_checks "$res" "$VR_MAP") || { vr_cause "could not read the result for session $gs at $gh"; continue; }
        part=$(jq -c --arg s "$session" --arg h "$head" --arg gs "$gs" --arg gh "$gh" \
            '[.checks[] | select((.session // $s) == $gs and (.result_head // $h) == $gh)
              | {id, jobs: (.jobs | map({workflow, job}))}]' <<<"$rec")
        out=$(jq -rn --argjson part "$part" --argjson timed "$timed" --arg where "session $gs at $gh" '
            ($part | map(.id)) as $ids | ($timed | map(.id)) as $want
            | ($ids | group_by(.) | map(select(length > 1) | .[0])[] | "the record lists check \(.) twice"),
              ($want - $ids | .[] | "check \(.) timed out in the result for \($where) and is missing from the record"),
              ($ids - $want | .[] | "the record lists check \(.), which did not time out in the result for \($where)"),
              ($part[] | . as $p | ($timed | map(select(.id == $p.id)) | first) as $t
               | select($t != null)
               | if ($t.jobs | length) == 0 then "check \($p.id): its row declares no hosted jobs in the map"
                 elif $p.jobs != $t.jobs then "check \($p.id): the record names jobs \($p.jobs | map(.job) | tojson), the map declares \($t.jobs | map(.job) | tojson)"
                 else empty end)') \
            || { vr_cause "could not compare the record with the result for session $gs at $gh"; continue; }
        while IFS= read -r c; do
            [ -n "$c" ] && vr_cause "$c"
        done <<EOF
$out
EOF
    done <<EOF
$groups
EOF
    [ -z "$VR_CAUSES" ]
}

# vr_runs_base <pr url>: sets VR_BASE to https://<host>/<owner>/<repo>.
vr_runs_base() {
    VR_BASE=""
    [ -n "${1:-}" ] || return 1
    vr_pr_url_lib || return 1
    pr_url_parse "$1" || return 1
    VR_BASE="https://$PR_HOST/$PR_OWNER/$PR_REPO"
}

# vr_body_line <record json> <check id> [<pr url>]: the check's body line.
# A job whose run_id is filled links its run, built from the numeric id and
# the pull request's host and repository; otherwise `(pending)`.
vr_body_line() {
    local base=""
    if [ $# -ge 3 ] && vr_runs_base "$3"; then
        base=$VR_BASE
    fi
    jq -r --arg id "$2" --arg base "$base" --arg prefix "$VR_LINE_PREFIX" '
        . as $r | first(.checks[] | select(.id == $id)) as $c
        | $prefix + "\($c.id) at \($r.head): "
          + ($c.jobs | map(.job + " " + (if .run_id != null and $base != ""
                                         then "\($base)/actions/runs/\(.run_id)" else "(pending)" end))
                     | join("; "))' <<<"$1"
}

# VR_NEUTRAL_JQ: the jq definition `neutral`, which makes a string safe to
# post inside a code span: control characters become spaces, backticks go,
# and @, #, <, >, [ and ] become _, so it mentions nobody, references
# nothing, links nothing and renders no tag. vr_reason_line and
# ci-relevant.sh's pull request comment both use it.
VR_NEUTRAL_JQ='def neutral: gsub("[[:cntrl:]]"; " ") | gsub("`"; "") | gsub("[@#<>\\[\\]]"; "_");'

# vr_neutral <text>: the text, neutral (VR_NEUTRAL_JQ), on one line.
vr_neutral() {
    jq -rn --arg t "$1" "$VR_NEUTRAL_JQ"' $t | neutral'
}

# vr_reason_line <record json>: the reason as one line in a code span,
# neutral (VR_NEUTRAL_JQ), so it can't start a `Hosted of record:` line
# either.
vr_reason_line() {
    jq -r "$VR_NEUTRAL_JQ"' "Reason for the hosted route: `" + (.reason | neutral) + "`"' <<<"$1"
}

# vr_body_check <draft|ready> <body file> <record json> <pr url>: sets
# VR_CAUSES; 0 the body carries exactly one well-formed line per recorded
# check, 1 otherwise. Only lines that start with the prefix count (a CR
# before the newline is dropped), so reason text elsewhere can neither
# satisfy nor forge one; a prefixed line naming another check or head fails.
# In ready mode each job's entry must link its recorded run.
vr_body_check() {
    local base="" out c
    VR_CAUSES=""
    if [ "$1" = ready ]; then
        vr_runs_base "${4:-}" || { vr_cause "the pull request URL [${4:-}] does not parse"; return 1; }
        base=$VR_BASE
    fi
    if ! out=$(jq -rn --rawfile body "$2" --argjson rec "$3" --arg mode "$1" --arg base "$base" --arg prefix "$VR_LINE_PREFIX" '
        ($body | gsub("\r\n?"; "\n") | split("\n") | map(select(startswith($prefix)))) as $lines
        | ($lines | map((capture("^Hosted of record: (?<id>\\S+) at (?<head>[0-9a-f]{40}): (?<rest>.*)$")
                         // {bad: .}))) as $parsed
        | ($rec.checks | map(.id)) as $ids
        | ($parsed[] | select(.bad) | "a body line does not parse as a Hosted of record line: \(.bad)"),
          ($parsed[] | select(.bad | not) | select(.id as $i | $ids | index([$i]) | not)
           | "a body line names check \(.id), which the record does not list"),
          ($parsed[] | select(.bad | not) | select(.head != $rec.head)
           | "the body line for \(.id) names head \(.head), the record is for \($rec.head)"),
          ($rec.checks[] | . as $c
           | [$parsed[] | select((.bad | not) and .id == $c.id and .head == $rec.head)] as $mine
           | if ($mine | length) == 0 then "the body has no Hosted of record line for check \($c.id) at \($rec.head)"
             elif ($mine | length) > 1 then "the body has more than one Hosted of record line for check \($c.id)"
             else ($mine[0].rest | split("; ")) as $entries
               | $c.jobs[] | . as $j
               | (first($entries[] | select(startswith($j.job + " "))) // null) as $e
               | if $e == null then "the line for check \($c.id) does not name job \($j.job)"
                 elif $mode == "ready" and $j.run_id == null then "check \($c.id), job \($j.job) has no recorded run"
                 elif $mode == "ready" and $e != ($j.job + " " + "\($base)/actions/runs/\($j.run_id)")
                 then "the line for check \($c.id) does not link job \($j.job)'"'"'s run \($j.run_id)"
                 else empty end
             end)'); then
        vr_cause "the body or the record could not be read"
        return 1
    fi
    while IFS= read -r c; do
        [ -n "$c" ] && vr_cause "$c"
    done <<EOF
$out
EOF
    [ -z "$VR_CAUSES" ]
}

# --- GitHub -------------------------------------------------------------------------------

# vr_pr_object <session>: sets VR_PR (number, url, headRefOid, isDraft,
# isCrossRepository, body), VR_PR_URL, VR_HOST, VR_REPO and VR_PR_NUMBER;
# returns 1 with VR_PR_ERR. The pull request is the one context's pr_url
# names when it is set, else the checked-out branch's; the repository and
# number come from the object's own URL, never from the branch name.
vr_pr_object() {
    local url="" out rc num
    VR_PR=""; VR_PR_URL=""; VR_HOST=""; VR_REPO=""; VR_PR_NUMBER=""; VR_PR_ERR=""
    vr_pr_url_lib || { VR_PR_ERR="pr-url.sh is missing"; return 1; }
    # --pr names it: a parent run's shared or node pull request, which
    # neither pr_url nor the checked-out branch names.
    if [ -n "$VR_PR_OPT" ]; then
        rc=given
        url=$VR_PR_OPT
    else
        koto context exists "$1" pr_url
        rc=$?
    fi
    case "$rc" in
        given) ;;
        0) url=$(koto context get "$1" pr_url) || { VR_PR_ERR="could not read pr_url from koto context"; return 1; } ;;
        1) out=$(gh pr view --json url) || { VR_PR_ERR="gh pr view could not find the branch's pull request"; return 1; }
           url=$(jq -r '.url // ""' <<<"$out") || { VR_PR_ERR="gh pr view did not return a URL"; return 1; } ;;
        *) VR_PR_ERR="koto context exists $1 pr_url exited $rc"; return 1 ;;
    esac
    pr_url_parse "$url" || { VR_PR_ERR="[$url] is not a pull request URL"; return 1; }
    out=$(gh pr view "$url" --json number,url,headRefOid,isDraft,isCrossRepository,body) \
        || { VR_PR_ERR="gh pr view $url failed"; return 1; }
    jq -e 'type == "object" and (.url | type) == "string" and (.number | type) == "number"
           and (.headRefOid | type) == "string" and (.isDraft | type) == "boolean"
           and (.isCrossRepository | type) == "boolean" and (.body | type) == "string"' <<<"$out" >/dev/null \
        || { VR_PR_ERR="gh pr view $url did not return the pull request's fields"; return 1; }
    VR_PR_URL=$(jq -r .url <<<"$out")
    pr_url_parse "$VR_PR_URL" || { VR_PR_ERR="[$VR_PR_URL] is not a pull request URL"; return 1; }
    num=${VR_PR_URL#*/pull/}
    num=${num%%[/?#]*}
    [ "$(jq -r .number <<<"$out")" = "$num" ] \
        || { VR_PR_ERR="gh pr view returned number $(jq -r .number <<<"$out") for $VR_PR_URL"; return 1; }
    VR_PR=$out
    VR_HOST=$PR_HOST
    VR_REPO="$PR_OWNER/$PR_REPO"
    VR_PR_NUMBER=$num
}

vr_max_pages() {
    case "${SHIRABE_ROUTE_MAX_PAGES:-}" in
        ''|*[!0-9]*|0) echo 10 ;;
        *) printf '%s\n' "$SHIRABE_ROUTE_MAX_PAGES" ;;
    esac
}

# vr_runs <repo> <head> <workflow> <pr number>: sets VR_RUN to the newest run
# (by run_number, then created_at) of <workflow> for the pull_request event on
# pull request <pr number> at <head>, from <repo> with a head repository equal
# to it; `null` when there is none. Pages until a page holds fewer than 100
# runs; returns 1 with VR_GH_ERR for a failed or unreadable page, or when
# SHIRABE_ROUTE_MAX_PAGES pages were full.
vr_runs() {
    local page=1 max all="[]" body count
    VR_RUN=null; VR_GH_ERR=""
    max=$(vr_max_pages)
    while :; do
        if [ "$page" -gt "$max" ]; then
            VR_GH_ERR="more than $max full pages of runs at $2"
            return 1
        fi
        body=$(gh api "repos/$1/actions/runs?head_sha=$2&event=pull_request&per_page=100&page=$page" --hostname "$VR_HOST") \
            || { VR_GH_ERR="gh api could not read page $page of the runs at $2"; return 1; }
        count=$(jq -e 'if type == "object" and (.workflow_runs | type) == "array" then .workflow_runs | length else error("not a runs page") end' <<<"$body") \
            || { VR_GH_ERR="page $page of the runs at $2 is not a runs listing"; return 1; }
        all=$(jq -c --argjson all "$all" --arg repo "$1" --arg head "$2" --arg wf "$3" --argjson pr "$4" '
            ($repo | ascii_downcase) as $r
            | $all + [.workflow_runs[] | select(type == "object"
                and ((.path // "") | split("@")[0]) == $wf
                and .event == "pull_request"
                and .head_sha == $head
                and ((.repository.full_name // "") | ascii_downcase) == $r
                and ((.head_repository.full_name // "") | ascii_downcase) == $r
                and any((.pull_requests // [])[]; .number == $pr))]' <<<"$body") \
            || { VR_GH_ERR="page $page of the runs at $2 could not be read"; return 1; }
        [ "$count" -lt 100 ] && break
        page=$((page + 1))
    done
    VR_RUN=$(jq -c 'if length == 0 then null else max_by([.run_number, .created_at]) end' <<<"$all") \
        || { VR_GH_ERR="the runs at $2 could not be read"; return 1; }
}

# vr_job <repo> <run id> <attempt> <job name>: sets VR_JOBS to the array of
# that attempt's jobs named exactly <job name>; returns 1 with VR_GH_ERR when
# a page can't be read.
vr_job() {
    local page=1 max all="[]" body count
    VR_JOBS="[]"; VR_GH_ERR=""
    max=$(vr_max_pages)
    while :; do
        if [ "$page" -gt "$max" ]; then
            VR_GH_ERR="more than $max full pages of jobs for run $2"
            return 1
        fi
        body=$(gh api "repos/$1/actions/runs/$2/attempts/$3/jobs?per_page=100&page=$page" --hostname "$VR_HOST") \
            || { VR_GH_ERR="gh api could not read the jobs of run $2, attempt $3"; return 1; }
        count=$(jq -e 'if type == "object" and (.jobs | type) == "array" then .jobs | length else error("not a jobs page") end' <<<"$body") \
            || { VR_GH_ERR="the jobs of run $2, attempt $3 are not a jobs listing"; return 1; }
        all=$(jq -c --argjson all "$all" --arg name "$4" '$all + [.jobs[] | select(type == "object" and .name == $name)]' <<<"$body") \
            || { VR_GH_ERR="the jobs of run $2 could not be read"; return 1; }
        [ "$count" -lt 100 ] && break
        page=$((page + 1))
    done
    VR_JOBS=$all
}

# --- the modes ------------------------------------------------------------------------------

# vr_key_read <session>: sets VR_REC; 0 read, 1 absent, 2 koto failed.
vr_key_read() {
    local rc wt
    VR_REC=""
    koto context exists "$1" "$VR_KEY"
    rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;
        *) vr_say "koto context exists $1 $VR_KEY exited $rc"; return 2 ;;
    esac
    VR_REC=$(koto context get "$1" "$VR_KEY") || { vr_say "could not read the $VR_KEY key of $1"; VR_REC=""; return 2; }
    # A node's record names the worktree its git reads ran in; it is used
    # when this call names none and the directory is still there.
    if [ -z "$VR_WT" ]; then
        wt=$(jq -r 'if type == "object" and (.work_tree | type) == "string" then .work_tree else "" end' <<<"$VR_REC") || wt=""
        [ -n "$wt" ] && [ -d "$wt" ] && VR_WT=$wt
    fi
    return 0
}

vr_head() {
    if [ -n "$VR_WT" ]; then
        git -C "$VR_WT" rev-parse --verify -q "HEAD^{commit}"
    else
        git rev-parse --verify -q "HEAD^{commit}"
    fi
}

vr_cmd_open() {
    vr_locate "$VR_S" || { vr_say "could not locate the verification result for $VR_S"; return 2; }
    if vr_open_check "$VR_S" "$VR_LOC_HEAD" "$VR_LOC_MB" "$VR_LOC_RESULT" "$VR_SHARED"; then
        vr_say "the hosted-of-record route is open for $VR_LOC_HEAD"
        return 0
    fi
    vr_print_causes "the hosted-of-record route is closed: "
    return 1
}

# vr_child_checks <children>: sets VR_CHECKS to the record's parts for the
# children, one `<session>@<head>` per line, each part carrying the child's
# session and result head, from that child's stored result and the map at its
# merge-base. 1 (said on stderr) when a child has no stored result, no map,
# no timed-out check or one whose row declares no hosted jobs; 2 for a
# malformed child or a read that failed.
vr_child_checks() {
    local root child cs ch res mb timed
    VR_CHECKS="[]"
    root=$(vr_root) || return 2
    while IFS= read -r child; do
        [ -n "$child" ] || continue
        cs=${child%@*}; ch=${child##*@}
        if [ "$cs" = "$child" ] || ! vr_locate "$cs" "$ch"; then
            vr_say "--child [$child] is not <session>@<head>"
            return 2
        fi
        res=$VR_LOC_RESULT
        [ -f "$res" ] || { vr_say "no stored verification result for $cs at $ch"; return 1; }
        mb=$(jq -r '.merge_base // ""' "$res") || return 2
        vr_map_at "$root" "$mb" || { vr_say "$cs at $ch: $VR_MAP_ERR"; return 1; }
        timed=$(vr_timed_out_checks "$res" "$VR_MAP") || return 2
        if jq -e 'length == 0 or any(.[]; (.jobs | length) == 0)' <<<"$timed" >/dev/null; then
            vr_say "$cs at $ch: no timed-out check, or one whose row declares no hosted jobs"
            return 1
        fi
        VR_CHECKS=$(jq -c --argjson c "$VR_CHECKS" --arg s "$cs" --arg h "$ch" \
            '$c + map({id, session: $s, result_head: $h, jobs: (.jobs | map(. + {run_id: null, conclusion: null, attempt: null}))})' <<<"$timed") || return 2
    done <<EOF
$1
EOF
    return 0
}

vr_cmd_record() {
    local reason clean rc checks="[]" head root res mb timed taken rec
    if [ "$VR_REASON_SET" -eq 1 ]; then
        reason=$VR_REASON
    else
        koto context exists "$VR_S" "$VR_REASON_KEY"
        rc=$?
        case "$rc" in
            0) reason=$(koto context get "$VR_S" "$VR_REASON_KEY") || { vr_say "could not read $VR_REASON_KEY"; return 2; } ;;
            1) reason="" ;;
            *) vr_say "koto context exists $VR_S $VR_REASON_KEY exited $rc"; return 2 ;;
        esac
    fi
    clean=$(vr_sanitize_reason "$reason") || { vr_say "could not clean the reason"; return 2; }
    if [ -z "$clean" ]; then
        vr_say "the route needs a reason: submit hosted_of_record with the reason in detail"
        return 1
    fi
    if [ -z "$VR_CHILDREN" ]; then
        [ -z "$VR_HEAD_OPT" ] || { vr_say "--head goes with --child; the run's own record is at HEAD"; return 2; }
        vr_locate "$VR_S" || { vr_say "could not locate the verification result for $VR_S"; return 2; }
        head=$VR_LOC_HEAD; mb=$VR_LOC_MB; res=$VR_LOC_RESULT
        if ! vr_open_check "$VR_S" "$head" "$mb" "$res" ""; then
            vr_print_causes "the route is closed, so nothing is recorded: "
            return 1
        fi
        root=$(vr_root) || return 2
        vr_map_at "$root" "$mb" || { vr_say "$VR_MAP_ERR"; return 2; }
        timed=$(vr_timed_out_checks "$res" "$VR_MAP") || return 2
        checks=$(jq -c 'map({id, jobs: (.jobs | map(. + {run_id: null, conclusion: null, attempt: null}))})' <<<"$timed") || return 2
    else
        head=$VR_HEAD_OPT
        vr_child_checks "$VR_CHILDREN"
        rc=$?
        [ "$rc" -eq 0 ] || return "$rc"
        checks=$VR_CHECKS
    fi
    taken=$(vr_iso "$(vr_now)") || return 2
    rec=$(jq -cn --arg head "$head" --arg taken "$taken" --arg reason "$clean" --argjson checks "$checks" \
        '{head: $head, taken_at: $taken, reason: $reason, checks: $checks}') || return 2
    printf '%s\n' "$rec" | koto context add "$VR_S" "$VR_KEY" \
        || { vr_say "could not write the $VR_KEY key"; return 2; }
    vr_say "recorded the hosted-of-record route for $head: $(jq -r '[.checks[].id] | join(", ")' <<<"$rec")"
    return 0
}

vr_want_head() {
    if [ -n "$VR_HEAD_OPT" ]; then
        printf '%s\n' "$VR_HEAD_OPT"
    else
        vr_head
    fi
}

vr_cmd_check_record() {
    local head rc
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) ;;
        1) vr_say "there is no $VR_KEY key for $VR_S"; return 2 ;;
        *) return 2 ;;
    esac
    if vr_validate_record "$VR_REC" "$head" "$VR_S"; then
        vr_say "the $VR_KEY key is valid for $head"
        return 0
    fi
    vr_print_causes "the $VR_KEY key is not valid: "
    return 1
}

# vr_cmd_read: see --read in the header.
vr_cmd_read() {
    local head rc rhead n m i j check job wf run attempt status matches jconc
    local fills="[]" refused=0 pending="" taken now new body newbody lines id line
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    [ "$rc" -eq 0 ] || { [ "$rc" -eq 1 ] && vr_say "there is no $VR_KEY key for $VR_S"; return 2; }
    if ! vr_validate_record "$VR_REC" "$head" "$VR_S"; then
        vr_print_causes "hosted_record: the record is not valid: "
        return 1
    fi
    rhead=$(jq -r .head <<<"$VR_REC")
    if ! vr_pr_object "$VR_S"; then
        vr_say "hosted_record: $VR_PR_ERR, at $rhead"
        return 1
    fi
    if [ "$(jq -r .headRefOid <<<"$VR_PR")" != "$rhead" ]; then
        vr_say "hosted_record: the pull request's head is $(jq -r .headRefOid <<<"$VR_PR"), the record is for $rhead: a new commit voids the route"
        return 1
    fi
    if [ "$(jq -r .isCrossRepository <<<"$VR_PR")" = true ]; then
        vr_say "hosted_record: $VR_PR_URL comes from another repository; its runs are not the base repository's"
        return 1
    fi

    n=$(jq '.checks | length' <<<"$VR_REC")
    i=0
    while [ "$i" -lt "$n" ]; do
        check=$(jq -r --argjson i "$i" '.checks[$i].id' <<<"$VR_REC")
        m=$(jq --argjson i "$i" '.checks[$i].jobs | length' <<<"$VR_REC")
        j=0
        while [ "$j" -lt "$m" ]; do
            wf=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].workflow' <<<"$VR_REC")
            job=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].job' <<<"$VR_REC")
            j=$((j + 1))
            if ! vr_runs "$VR_REPO" "$rhead" "$wf" "$VR_PR_NUMBER"; then
                vr_say "hosted_record: check $check, job $job, commit $rhead: refused, unreadable: $VR_GH_ERR"
                refused=$((refused + 1)); continue
            fi
            if [ "$VR_RUN" = null ]; then
                pending="$pending${pending:+, }$check/$job"
                continue
            fi
            run=$(jq -r .id <<<"$VR_RUN")
            attempt=$(jq -r '.run_attempt // 1' <<<"$VR_RUN")
            status=$(jq -r '.status // ""' <<<"$VR_RUN")
            case "$run$attempt" in *[!0-9]*|'')
                vr_say "hosted_record: check $check, job $job, commit $rhead: refused, the run has no numeric id and attempt"
                refused=$((refused + 1)); continue ;;
            esac
            if ! vr_job "$VR_REPO" "$run" "$attempt" "$job"; then
                vr_say "hosted_record: check $check, job $job, commit $rhead: refused, unreadable: $VR_GH_ERR"
                refused=$((refused + 1)); continue
            fi
            matches=$(jq 'length' <<<"$VR_JOBS")
            if [ "$matches" -gt 1 ]; then
                vr_say "hosted_record: check $check, job $job, commit $rhead: refused, run $run attempt $attempt has $matches jobs of that name"
                refused=$((refused + 1)); continue
            fi
            if [ "$matches" -eq 0 ]; then
                if [ "$status" = completed ]; then
                    vr_say "hosted_record: check $check, job $job, commit $rhead: refused, run $run attempt $attempt completed with no job of that name"
                    refused=$((refused + 1))
                else
                    pending="$pending${pending:+, }$check/$job"
                fi
                continue
            fi
            if [ "$(jq -r '.[0].status // ""' <<<"$VR_JOBS")" != completed ]; then
                pending="$pending${pending:+, }$check/$job"
                continue
            fi
            jconc=$(jq -r '.[0].conclusion // "none"' <<<"$VR_JOBS")
            if [ "$jconc" != success ]; then
                vr_say "hosted_record: check $check, job $job, commit $rhead: refused, run $run attempt $attempt concluded $jconc"
                refused=$((refused + 1)); continue
            fi
            fills=$(jq -c --argjson f "$fills" --argjson i "$i" --argjson j "$((j - 1))" --argjson run "$run" --argjson a "$attempt" \
                -n '$f + [{i: $i, j: $j, run_id: $run, attempt: $a}]') || return 2
        done
        i=$((i + 1))
    done

    [ "$refused" -eq 0 ] || return 1
    if [ -n "$pending" ]; then
        taken=$(jq -r '.taken_at | fromdateiso8601' <<<"$VR_REC") || return 2
        now=$(vr_now)
        if [ $((now - taken)) -gt "$VR_WAIT_SECS" ]; then
            # failure_reason is the session's own: written for its own key
            # (a /work-on run's, or a single-pr parent's), never on a dry run
            # or for a node's key, whose caller reports it as an error line.
            if [ "$VR_DRY" -eq 0 ] && [ "$VR_KEY" = hosted_of_record ]; then
                printf 'hosted_record: still pending %s minutes after the route was taken: %s at %s\n' \
                    "$((VR_WAIT_SECS / 60))" "$pending" "$rhead" | koto context add "$VR_S" failure_reason \
                    || { vr_say "could not write failure_reason"; return 2; }
            fi
            vr_say "hosted_record: still pending $((VR_WAIT_SECS / 60)) minutes after the route was taken: $pending at $rhead"
            return 3
        fi
        vr_say "hosted_record: waiting on $pending at $rhead ($(( (now - taken) / 60 )) of $((VR_WAIT_SECS / 60)) minutes)"
        return 75
    fi

    if [ "$VR_DRY" -eq 1 ]; then
        vr_say "hosted_record: every hosted job of record concluded success at $rhead (a dry run: nothing written)"
        return 0
    fi
    new=$(jq -c --argjson f "$fills" \
        'reduce $f[] as $x (.; .checks[$x.i].jobs[$x.j] |= (.run_id = $x.run_id | .conclusion = "success" | .attempt = $x.attempt))' \
        <<<"$VR_REC") || return 2
    printf '%s\n' "$new" | koto context add "$VR_S" "$VR_KEY" \
        || { vr_say "could not write the $VR_KEY key"; return 2; }

    # Each check's line, rebuilt from the filled record; the rest of the body
    # is kept as it is.
    lines="{}"
    for id in $(jq -r '.checks[].id' <<<"$new"); do
        line=$(vr_body_line "$new" "$id" "$VR_PR_URL") || return 2
        lines=$(jq -c --argjson l "$lines" --arg k "$id" --arg v "$line" -n '$l + {($k): $v}') || return 2
    done
    vr_tmp || return 2
    body="$VR_TMP/body.md"
    newbody="$VR_TMP/body.new.md"
    jq -j '.body | gsub("\r\n?"; "\n")' <<<"$VR_PR" > "$body" || return 2
    jq -jn --rawfile b "$body" --argjson lines "$lines" --arg prefix "$VR_LINE_PREFIX" '
        ($b | split("\n")) as $ls
        | ($ls | map(. as $l | (first($lines | to_entries[] | . as $e | select($l | startswith($prefix + $e.key + " at ")) | $e.value) // $l))) as $new
        | ($lines | to_entries | map(.value) | map(select(. as $v | $new | index([$v]) | not))) as $missing
        | if ($missing | length) == 0 then $new | join("\n")
          else ($new | join("\n") | sub("\n+$"; "")) + "\n\n" + ($missing | join("\n")) + "\n" end' > "$newbody" || return 2
    if ! cmp -s "$body" "$newbody"; then
        gh pr edit "$VR_PR_URL" --body-file "$newbody" \
            || { vr_say "gh pr edit $VR_PR_URL failed"; return 2; }
    fi
    vr_say "hosted_record: every hosted job of record concluded success at $rhead"
    return 0
}

# vr_settled_core <head>: --settled for a key already read into VR_REC.
vr_settled_core() {
    local head=$1 rhead n m i j check job wf run attempt rjson
    rhead=$(jq -r '.head // ""' <<<"$VR_REC")
    if [ "$rhead" != "$head" ]; then
        vr_say "not settled: the record is for $rhead, the head is $head"
        return 1
    fi
    if ! vr_validate_record "$VR_REC" "$head" "$VR_S"; then
        vr_print_causes "not settled: "
        return 1
    fi
    if jq -e 'any(.checks[].jobs[]; .run_id == null)' <<<"$VR_REC" >/dev/null; then
        vr_say "not settled: the hosted jobs of record have not been read at $rhead: $(jq -r '[.checks[] | .id as $c | .jobs[] | select(.run_id == null) | "\($c)/\(.job)"] | join(", ")' <<<"$VR_REC")"
        return 1
    fi
    vr_pr_object "$VR_S" || { vr_say "$VR_PR_ERR"; return 2; }
    if [ "$(jq -r .headRefOid <<<"$VR_PR")" != "$rhead" ]; then
        vr_say "not settled: the pull request's head is $(jq -r .headRefOid <<<"$VR_PR"), the record is for $rhead"
        return 1
    fi
    n=$(jq '.checks | length' <<<"$VR_REC")
    i=0
    while [ "$i" -lt "$n" ]; do
        check=$(jq -r --argjson i "$i" '.checks[$i].id' <<<"$VR_REC")
        m=$(jq --argjson i "$i" '.checks[$i].jobs | length' <<<"$VR_REC")
        j=0
        while [ "$j" -lt "$m" ]; do
            wf=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].workflow' <<<"$VR_REC")
            job=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].job' <<<"$VR_REC")
            run=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].run_id' <<<"$VR_REC")
            attempt=$(jq -r --argjson i "$i" --argjson j "$j" '.checks[$i].jobs[$j].attempt' <<<"$VR_REC")
            j=$((j + 1))
            # Every filled run is read again, so a key filled by hand settles
            # nothing.
            if ! rjson=$(gh api "repos/$VR_REPO/actions/runs/$run" --hostname "$VR_HOST"); then
                vr_say "not settled: check $check, job $job: run $run could not be read"
                return 1
            fi
            if ! jq -e --arg wf "$wf" --arg head "$rhead" --arg repo "$VR_REPO" --argjson pr "$VR_PR_NUMBER" --argjson a "$attempt" '
                    ($repo | ascii_downcase) as $r
                    | type == "object"
                    and ((.path // "") | split("@")[0]) == $wf
                    and .event == "pull_request"
                    and .head_sha == $head
                    and ((.repository.full_name // "") | ascii_downcase) == $r
                    and ((.head_repository.full_name // "") | ascii_downcase) == $r
                    and any((.pull_requests // [])[]; .number == $pr)
                    and (.run_attempt // 1) == $a' <<<"$rjson" >/dev/null; then
                vr_say "not settled: check $check, job $job: run $run is not $wf's latest attempt ($attempt) for this pull request at $rhead"
                return 1
            fi
            if ! vr_job "$VR_REPO" "$run" "$attempt" "$job"; then
                vr_say "not settled: check $check, job $job: $VR_GH_ERR"
                return 1
            fi
            if ! jq -e 'length == 1 and .[0].status == "completed" and .[0].conclusion == "success"' <<<"$VR_JOBS" >/dev/null; then
                vr_say "not settled: check $check: run $run attempt $attempt has no single job $job concluded success"
                return 1
            fi
        done
        i=$((i + 1))
    done
    return 0
}

vr_cmd_settled() {
    local head rc
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) ;;
        1) vr_say "no $VR_KEY key: nothing to settle"; return 0 ;;
        *) return 2 ;;
    esac
    vr_settled_core "$head"
    rc=$?
    [ "$rc" -eq 0 ] && vr_say "the hosted jobs of record are settled at $head"
    return "$rc"
}

vr_cmd_ready() {
    local head rc
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) ;;
        1) if [ "$VR_ABSENT_OK" -eq 1 ]; then
               vr_say "no $VR_KEY key: no hosted route to be ready on"
               return 0
           fi
           vr_say "no $VR_KEY key: there is no record to be ready on"; return 1 ;;
        *) return 2 ;;
    esac
    vr_settled_core "$head"
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    if [ "$(jq -r .isDraft <<<"$VR_PR")" = true ]; then
        vr_say "not ready: $VR_PR_URL is still a draft; run verification-route.sh --mark-ready --session $VR_S"
        return 1
    fi
    vr_tmp || return 2
    jq -j '.body' <<<"$VR_PR" > "$VR_TMP/ready-body.md" || return 2
    if ! vr_body_check ready "$VR_TMP/ready-body.md" "$VR_REC" "$VR_PR_URL"; then
        vr_print_causes "not ready: "
        return 1
    fi
    vr_say "ready: $VR_PR_URL is out of draft at $head and every line links its run"
    return 0
}

vr_cmd_mark_ready() {
    local head rc
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) ;;
        1) if [ "$VR_ABSENT_OK" -eq 1 ]; then
               # A parent's ready call: with no child on the route it is the
               # plain gh pr ready; with one, the read settles first.
               vr_any_child_record
               rc=$?
               case "$rc" in
                   0) vr_say "--mark-ready refused: a child took the hosted-of-record route and $VR_KEY is not recorded yet; tick, and mark ready once the hosted read settles"
                      return 1 ;;
                   1) [ -n "$VR_PR_OPT" ] || { vr_say "--mark-ready --absent-ok needs --pr"; return 2; }
                      gh pr ready "$VR_PR_OPT" || { vr_say "gh pr ready $VR_PR_OPT failed"; return 2; }
                      return 0 ;;
                   *) return 2 ;;
               esac
           fi
           vr_say "no $VR_KEY key: nothing to mark ready on"; return 1 ;;
        *) return 2 ;;
    esac
    # vr_settled_core re-reads the pull request, so its head is checked just
    # before gh pr ready.
    vr_settled_core "$head"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        vr_say "--mark-ready refused: the record is not settled for the pull request's current head"
        return 1
    fi
    if [ "$(jq -r .isDraft <<<"$VR_PR")" != true ]; then
        vr_say "$VR_PR_URL is already out of draft"
        return 0
    fi
    gh pr ready "$VR_PR_URL" || { vr_say "gh pr ready $VR_PR_URL failed"; return 2; }
    return 0
}

vr_cmd_lines() {
    local head rc id
    head=$(vr_want_head) || { vr_say "HEAD does not name a commit"; return 2; }
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) ;;
        1) vr_say "no $VR_KEY key: the body needs no Hosted of record line"; return 1 ;;
        *) return 2 ;;
    esac
    if [ "$(jq -r '.head // ""' <<<"$VR_REC")" != "$head" ]; then
        vr_say "the $VR_KEY key is for another head; the body needs no Hosted of record line at $head"
        return 1
    fi
    for id in $(jq -r '.checks[].id' <<<"$VR_REC"); do
        vr_body_line "$VR_REC" "$id" || return 2
    done
    vr_reason_line "$VR_REC" || return 2
}

# --- /execute's records: a shared or node pull request's -------------------------------------

# vr_default_base <root>: origin's default branch as a ref, origin/main when
# refs/remotes/origin/HEAD is absent.
vr_default_base() {
    git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD || echo origin/main
}

# vr_child_names: the children --collect reads, one per line: the --child
# names, else the ones `koto workflows --children <session>` lists.
vr_child_names() {
    local out
    if [ -n "$VR_CHILDREN" ]; then
        printf '%s' "$VR_CHILDREN"
        return 0
    fi
    out=$(koto workflows --children "$VR_S" </dev/null) || { vr_say "koto workflows --children $VR_S failed"; return 2; }
    jq -r 'if type == "array" and all(.[]; (.name | type) == "string") then .[].name else error("not a list") end' <<<"$out" \
        || { vr_say "koto workflows --children $VR_S did not answer a list of sessions"; return 2; }
}

# vr_cmd_collect <head>: see --collect in the header.
vr_cmd_collect() {
    local head=$1 names child rc rec ch reason parts="" reasons="[]" refused=0 root base mb clean taken new
    names=$(vr_child_names) || return 2
    while IFS= read -r child; do
        [ -n "$child" ] || continue
        if ! grep -Eq "$VR_SESSION_RE" <<<"$child" || [ "$child" = . ] || [ "$child" = .. ]; then
            vr_say "--child [$child] is not a session name"
            return 2
        fi
        vr_child_koto context exists "$child" hosted_of_record </dev/null >/dev/null
        rc=$?
        case "$rc" in
            0) ;;
            1) continue ;;
            *) vr_say "koto context exists $child hosted_of_record exited $rc"; return 2 ;;
        esac
        rec=$(vr_child_koto context get "$child" hosted_of_record </dev/null) \
            || { vr_say "could not read $child's hosted_of_record"; return 2; }
        ch=$(jq -r 'if type == "object" and (.head | type) == "string" then .head else "" end' <<<"$rec") || ch=""
        if ! grep -Eq "$VR_SHA_RE" <<<"$ch"; then
            vr_say "$child's hosted_of_record names no head"
            refused=1
            continue
        fi
        # The child's own record, against its own stored result and map.
        if ! vr_validate_record "$rec" "$ch" "$child"; then
            vr_print_causes "$child's hosted_of_record is not valid: "
            refused=1
            continue
        fi
        reason=$(jq -r '.reason' <<<"$rec")
        reasons=$(jq -c --argjson r "$reasons" --arg x "$reason" -n 'if ($r | index([$x])) then $r else $r + [$x] end') || return 2
        parts="$parts$child@$ch
"
    done <<EOF
$names
EOF
    if [ -z "$parts" ] && [ "$refused" -eq 0 ]; then
        vr_say "no child took the hosted-of-record route; nothing recorded"
        return 4
    fi
    [ "$refused" -eq 0 ] || { vr_say "the hosted-of-record route is refused for $head, so nothing is recorded"; return 1; }

    # The children's diffs each passed --open; the pull request's whole diff
    # is what its hosted jobs run on, so it is checked again here.
    root=$(vr_root) || { vr_say "not inside a git working tree"; return 2; }
    base=${VR_BASE_OPT:-$(vr_default_base "$root")}
    mb=$(git -C "$root" merge-base "$base" "$head") || { vr_say "no merge-base of $base and $head"; return 2; }
    VR_CAUSES=""
    if ! vr_diff_check "$root" "$mb" "$head"; then
        vr_print_causes "the hosted-of-record route is closed for $head: "
        return 1
    fi

    vr_child_checks "$parts"
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    clean=$(vr_sanitize_reason "$(jq -r 'join("; ")' <<<"$reasons")") || return 2
    [ -n "$clean" ] || { vr_say "the children's reasons are empty"; return 1; }

    # A key already valid at this head, for the same checks and reason, is
    # kept: its taken_at is when the wait started.
    vr_key_read "$VR_S"
    rc=$?
    case "$rc" in
        0) if jq -e --arg h "$head" --arg r "$clean" --argjson c "$VR_CHECKS" '
                   type == "object" and .head == $h and .reason == $r
                   and ((.checks // []) | map({id, session, result_head, jobs: (.jobs | map({workflow, job}))}))
                       == ($c | map({id, session, result_head, jobs: (.jobs | map({workflow, job}))}))' <<<"$VR_REC" >/dev/null 2>&1 \
               && vr_validate_record "$VR_REC" "$head" "$VR_S"; then
               vr_say "the $VR_KEY key already records the route for $head; kept"
               return 0
           fi ;;
        1) ;;
        *) return 2 ;;
    esac
    taken=$(vr_iso "$(vr_now)") || return 2
    new=$(jq -cn --arg head "$head" --arg taken "$taken" --arg reason "$clean" --argjson checks "$VR_CHECKS" --arg wt "$VR_WT" \
        '{head: $head, taken_at: $taken, reason: $reason, checks: $checks}
         + (if $wt == "" then {} else {work_tree: $wt} end)') || return 2
    # The parent's record is checked as its readers will check it, part by
    # part against each child's stored result and map, before it is written.
    if ! vr_validate_record "$new" "$head" "$VR_S"; then
        vr_print_causes "the hosted-of-record route is refused for $head: "
        return 1
    fi
    printf '%s\n' "$new" | koto context add "$VR_S" "$VR_KEY" \
        || { vr_say "could not write the $VR_KEY key"; return 2; }
    vr_say "recorded the hosted-of-record route for $head as $VR_KEY: $(jq -r '[.checks[] | "\(.id) (\(.session))"] | join(", ")' <<<"$new")"
    return 0
}

# vr_any_child_record: 0 when one of the children holds hosted_of_record, 1
# when none does, 2 when a read failed.
vr_any_child_record() {
    local names child rc
    names=$(vr_child_names) || return 2
    while IFS= read -r child; do
        [ -n "$child" ] || continue
        vr_child_koto context exists "$child" hosted_of_record </dev/null >/dev/null
        rc=$?
        case "$rc" in
            0) return 0 ;;
            1) ;;
            *) vr_say "koto context exists $child hosted_of_record exited $rc"; return 2 ;;
        esac
    done <<EOF
$names
EOF
    return 1
}

# vr_cmd_parent_read: see --parent-read in the header.
vr_cmd_parent_read() {
    local head rc
    # No child took the route: nothing is read from GitHub at all.
    vr_any_child_record
    rc=$?
    case "$rc" in
        0) ;;
        1) vr_say "no child took the hosted-of-record route; nothing to read"; return 0 ;;
        *) return 2 ;;
    esac
    vr_pr_object "$VR_S" || { vr_say "$VR_PR_ERR"; return 2; }
    head=$(jq -r .headRefOid <<<"$VR_PR")
    grep -Eq "$VR_SHA_RE" <<<"$head" || { vr_say "the pull request's head [$head] is not a commit id"; return 2; }
    vr_cmd_collect "$head"
    rc=$?
    case "$rc" in
        0) ;;
        4) return 0 ;;
        *) return "$rc" ;;
    esac
    VR_HEAD_OPT=$head
    vr_cmd_read
}

vr_usage() {
    cat >&2 <<'EOF'
Usage: verification-route.sh --open --session <s> [--shared-branch <v>]
       verification-route.sh --record --session <s> [--reason <text>] [--head <sha> --child <session>@<head>]...
       verification-route.sh --check-record|--read|--settled|--ready|--mark-ready --session <s> [--head <sha>]
       verification-route.sh --lines --session <s>
       verification-route.sh --collect --session <s> --head <sha> [--base <ref>] [--child <session>]...
       verification-route.sh --parent-read --session <s> --pr <url> [--base <ref>] [--child <session>]...
  every mode but --open also takes [--key <k>] [--pr <url>] [--work-tree <dir>] [--child-dir <dir>];
  --read takes [--dry-run], --ready and --mark-ready take [--absent-ok],
  --mark-ready --absent-ok takes [--child <session>]...
EOF
}

vr_main() {
    local mode tool tools rc
    [ $# -ge 1 ] || { vr_usage; return 2; }
    mode=$1
    shift
    case "$mode" in
        --open|--record|--check-record|--read|--settled|--ready|--mark-ready|--lines|--collect|--parent-read) ;;
        -h|--help) vr_usage; return 0 ;;
        *) vr_usage; return 2 ;;
    esac
    VR_S=""; VR_SHARED=""; VR_REASON=""; VR_REASON_SET=0; VR_HEAD_OPT=""; VR_CHILDREN=""
    VR_KEY=hosted_of_record; VR_PR_OPT=""; VR_WT=""; VR_CHILD_DIR=""; VR_BASE_OPT=""; VR_DRY=0; VR_ABSENT_OK=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --session)
                [ $# -ge 2 ] && [ -z "$VR_S" ] || { vr_usage; return 2; }
                VR_S=$2; shift 2 ;;
            --shared-branch)
                [ "$mode" = --open ] && [ $# -ge 2 ] || { vr_usage; return 2; }
                VR_SHARED=$2; shift 2 ;;
            --reason)
                [ "$mode" = --record ] && [ $# -ge 2 ] || { vr_usage; return 2; }
                VR_REASON=$2; VR_REASON_SET=1; shift 2 ;;
            --child)
                case "$mode" in --record|--collect|--parent-read|--mark-ready) ;; *) vr_usage; return 2 ;; esac
                [ $# -ge 2 ] && [ -n "$2" ] || { vr_usage; return 2; }
                VR_CHILDREN="$VR_CHILDREN$2
"
                shift 2 ;;
            --head)
                case "$mode" in --open|--lines|--parent-read) vr_usage; return 2 ;; esac
                [ $# -ge 2 ] || { vr_usage; return 2; }
                grep -Eq "$VR_SHA_RE" <<<"$2" || { vr_say "--head [$2] is not a commit id"; return 2; }
                VR_HEAD_OPT=$2; shift 2 ;;
            --key)
                [ "$mode" != --open ] && [ $# -ge 2 ] || { vr_usage; return 2; }
                grep -Eq "$VR_KEY_RE" <<<"$2" || { vr_say "--key [$2] is not hosted_of_record or run/hosted/<node>"; return 2; }
                VR_KEY=$2; shift 2 ;;
            --pr)
                [ "$mode" != --open ] && [ $# -ge 2 ] && [ -n "$2" ] || { vr_usage; return 2; }
                vr_pr_url_lib || return 2
                pr_url_parse "$2" || { vr_say "--pr [$2] is not a pull request URL"; return 2; }
                VR_PR_OPT=$2; shift 2 ;;
            --work-tree)
                [ "$mode" != --open ] && [ $# -ge 2 ] && [ -d "${2:-}" ] || { vr_say "--work-tree needs a directory"; return 2; }
                VR_WT=$2; shift 2 ;;
            --child-dir)
                [ "$mode" != --open ] && [ $# -ge 2 ] && [ -d "${2:-}" ] || { vr_say "--child-dir needs a directory"; return 2; }
                VR_CHILD_DIR=$2; shift 2 ;;
            --base)
                case "$mode" in --collect|--parent-read) ;; *) vr_usage; return 2 ;; esac
                [ $# -ge 2 ] && [ -n "$2" ] || { vr_usage; return 2; }
                case "$2" in -*) vr_say "--base [$2] is not a ref"; return 2 ;; esac
                VR_BASE_OPT=$2; shift 2 ;;
            --dry-run)
                [ "$mode" = --read ] || { vr_usage; return 2; }
                VR_DRY=1; shift ;;
            --absent-ok)
                case "$mode" in --ready|--mark-ready) ;; *) vr_usage; return 2 ;; esac
                VR_ABSENT_OK=1; shift ;;
            *) vr_usage; return 2 ;;
        esac
    done
    [ -n "$VR_S" ] || { vr_usage; return 2; }
    grep -Eq "$VR_SESSION_RE" <<<"$VR_S" && [ "$VR_S" != . ] && [ "$VR_S" != .. ] \
        || { vr_say "--session [$VR_S] is not a session name"; return 2; }
    if [ "$mode" = --record ] && [ -n "$VR_CHILDREN" ] && [ -z "$VR_HEAD_OPT" ]; then
        vr_say "--child needs --head, the shared or node pull request's head"
        return 2
    fi
    if [ "$mode" = --collect ] && [ -z "$VR_HEAD_OPT" ]; then
        vr_say "--collect needs --head, the shared or node pull request's head"
        return 2
    fi
    if [ "$mode" = --parent-read ] && [ -z "$VR_PR_OPT" ]; then
        vr_say "--parent-read needs --pr, the shared or node pull request"
        return 2
    fi
    tools="git jq"
    [ "$mode" = --open ] || tools="$tools koto"
    case "$mode" in
        --read|--settled|--ready|--mark-ready|--parent-read) tools="$tools gh" ;;
    esac
    for tool in $tools; do
        command -v "$tool" >/dev/null 2>&1 || { vr_say "$tool is not on PATH"; return 2; }
    done
    case "$mode" in
        --open) vr_cmd_open ;;
        --record) vr_cmd_record ;;
        --check-record) vr_cmd_check_record ;;
        --read) vr_cmd_read ;;
        --settled) vr_cmd_settled ;;
        --ready) vr_cmd_ready ;;
        --mark-ready) vr_cmd_mark_ready ;;
        --lines) vr_cmd_lines ;;
        --collect) vr_cmd_collect "$VR_HEAD_OPT" ;;
        --parent-read) vr_cmd_parent_read ;;
    esac
    rc=$?
    return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    trap vr_cleanup EXIT
    vr_main "$@"
    exit $?
fi
