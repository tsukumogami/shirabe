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
#       for another head or merge-base; a supervisor-error, lock-wait, dirty-tree, no-map,
#       bad-map or attended result; a result that predates the route (no
#       finished_at, or a record without outcome or check); a not-started or
#       runaway command; a failed check; a budget stop that left commands
#       unstarted; no timed-out check; a timed-out check whose row in the
#       merge-base's map declares no hosted jobs; a missing or bad map at the
#       merge-base; a dirty tree; a diff from the merge-base touching a path
#       that decides what the hosted job runs (vr_closing_paths); a
#       check-skill.tsv edited other than by added rows; a run that is a child
#       of /execute (vr_refuse_execute_child, the one check /execute parity
#       removes).
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
# vr_refuse_execute_child, vr_closing_paths, vr_open_check,
# vr_sanitize_reason, vr_validate_record, vr_body_line, vr_reason_line,
# vr_body_check, vr_pr_object, vr_runs, vr_job. Each sets VR_* globals
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
VR_CAUSES=""
VR_TMP=""

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

# vr_refuse_execute_child <session> <shared-branch>: the ONE /execute refusal.
# Returns 0 and adds the cause when the run is a child of /execute (a
# SHARED_BRANCH run, or a session session-role.sh doesn't answer `root`
# for), 1 otherwise. Until /execute collects children's records, a child's
# record would sit on a pull request nobody reads it for; /execute parity
# removes this function's call, and only it.
vr_refuse_execute_child() {
    local role
    if [ -z "$2" ]; then
        role=$("$VR_HERE/session-role.sh" "$1") || role=""
        [ "$role" = root ] && return 1
    fi
    vr_cause "the run is a child of /execute (SHARED_BRANCH set, or a child session): the route waits for /execute parity"
    return 0
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

# vr_open_check <session> <head> <mb> <result> <shared-branch>: sets
# VR_CAUSES; 0 the route is open, 1 it is closed. Every cause is collected.
vr_open_check() {
    local session=$1 head=$2 mb=$3 result=$4 shared=$5 root="" inv=null runf facts checks dirty
    local changed closing hits tsv c st p add del
    VR_CAUSES=""
    root=$(git rev-parse --show-toplevel) || { vr_cause "not inside a git working tree"; root=""; }

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
                 | if any("supervisor-error", "lock-wait", "dirty-tree", "no-map", "bad-map", "attended"; . == $s)
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
    fi

    vr_refuse_execute_child "$session" "$shared"

    [ -z "$VR_CAUSES" ]
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

    root=$(git rev-parse --show-toplevel) || { vr_cause "not inside a git working tree"; return 1; }
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

# vr_reason_line <record json>: the reason as one line in a code span. The
# backticks are gone (vr_sanitize_reason) and @, #, <, >, [ and ] become _,
# so it mentions nobody, references nothing, links nothing, renders no tag,
# and can't start a `Hosted of record:` line.
vr_reason_line() {
    jq -r '"Reason for the hosted route: `"
           + (.reason | gsub("[[:cntrl:]]"; " ") | gsub("`"; "") | gsub("[@#<>\\[\\]]"; "_")) + "`"' <<<"$1"
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
    koto context exists "$1" pr_url
    rc=$?
    case "$rc" in
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
    local rc
    VR_REC=""
    koto context exists "$1" "$VR_KEY"
    rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;
        *) vr_say "koto context exists $1 $VR_KEY exited $rc"; return 2 ;;
    esac
    VR_REC=$(koto context get "$1" "$VR_KEY") || { vr_say "could not read the $VR_KEY key of $1"; VR_REC=""; return 2; }
    return 0
}

vr_head() {
    git rev-parse --verify -q "HEAD^{commit}"
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

vr_cmd_record() {
    local reason clean rc checks="[]" head root res mb timed child cs ch taken rec
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
        root=$(git rev-parse --show-toplevel) || return 2
        vr_map_at "$root" "$mb" || { vr_say "$VR_MAP_ERR"; return 2; }
        timed=$(vr_timed_out_checks "$res" "$VR_MAP") || return 2
        checks=$(jq -c 'map({id, jobs: (.jobs | map(. + {run_id: null, conclusion: null, attempt: null}))})' <<<"$timed") || return 2
    else
        head=$VR_HEAD_OPT
        root=$(git rev-parse --show-toplevel) || return 2
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
            checks=$(jq -c --argjson c "$checks" --arg s "$cs" --arg h "$ch" \
                '$c + map({id, session: $s, result_head: $h, jobs: (.jobs | map(. + {run_id: null, conclusion: null, attempt: null}))})' <<<"$timed") || return 2
        done <<EOF
$VR_CHILDREN
EOF
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
            printf 'hosted_record: still pending %s minutes after the route was taken: %s at %s\n' \
                "$((VR_WAIT_SECS / 60))" "$pending" "$rhead" | koto context add "$VR_S" failure_reason \
                || { vr_say "could not write failure_reason"; return 2; }
            vr_say "hosted_record: still pending $((VR_WAIT_SECS / 60)) minutes after the route was taken: $pending at $rhead"
            return 3
        fi
        vr_say "hosted_record: waiting on $pending at $rhead ($(( (now - taken) / 60 )) of $((VR_WAIT_SECS / 60)) minutes)"
        return 75
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
        vr_say "not settled: the hosted jobs of record have not been read at $rhead"
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
        1) vr_say "no $VR_KEY key: there is no record to be ready on"; return 1 ;;
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
        1) vr_say "no $VR_KEY key: nothing to mark ready on"; return 1 ;;
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

vr_usage() {
    cat >&2 <<'EOF'
Usage: verification-route.sh --open --session <s> [--shared-branch <v>]
       verification-route.sh --record --session <s> [--reason <text>] [--head <sha> --child <session>@<head>]...
       verification-route.sh --check-record|--read|--settled|--ready|--mark-ready --session <s> [--head <sha>]
       verification-route.sh --lines --session <s>
EOF
}

vr_main() {
    local mode tool tools rc
    [ $# -ge 1 ] || { vr_usage; return 2; }
    mode=$1
    shift
    case "$mode" in
        --open|--record|--check-record|--read|--settled|--ready|--mark-ready|--lines) ;;
        -h|--help) vr_usage; return 0 ;;
        *) vr_usage; return 2 ;;
    esac
    VR_S=""; VR_SHARED=""; VR_REASON=""; VR_REASON_SET=0; VR_HEAD_OPT=""; VR_CHILDREN=""
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
                [ "$mode" = --record ] && [ $# -ge 2 ] || { vr_usage; return 2; }
                VR_CHILDREN="$VR_CHILDREN$2
"
                shift 2 ;;
            --head)
                [ "$mode" != --open ] && [ "$mode" != --lines ] && [ $# -ge 2 ] || { vr_usage; return 2; }
                grep -Eq "$VR_SHA_RE" <<<"$2" || { vr_say "--head [$2] is not a commit id"; return 2; }
                VR_HEAD_OPT=$2; shift 2 ;;
            *) vr_usage; return 2 ;;
        esac
    done
    [ -n "$VR_S" ] || { vr_usage; return 2; }
    grep -Eq "$VR_SESSION_RE" <<<"$VR_S" && [ "$VR_S" != . ] && [ "$VR_S" != .. ] \
        || { vr_say "--session [$VR_S] is not a session name"; return 2; }
    if [ -n "$VR_CHILDREN" ] && [ -z "$VR_HEAD_OPT" ]; then
        vr_say "--child needs --head, the shared or node pull request's head"
        return 2
    fi
    # --open needs no koto of its own: session-role.sh answers child without
    # it, which closes the route.
    tools="git jq"
    [ "$mode" = --open ] || tools="$tools koto"
    case "$mode" in
        --read|--settled|--ready|--mark-ready) tools="$tools gh" ;;
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
    esac
    rc=$?
    return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    trap vr_cleanup EXIT
    vr_main "$@"
    exit $?
fi
