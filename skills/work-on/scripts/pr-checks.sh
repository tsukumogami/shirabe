#!/usr/bin/env bash
# pr-checks.sh -- `gh pr checks`, read from the Actions runs and the commit's
# statuses when the token can't read checks.
# Part of the work-on skill
#
# Under a fine-grained personal access token, GitHub refuses every check
# read on some repositories (seen on private ones): `gh pr checks`, the REST
# check-runs API and GraphQL `statusCheckRollup` answer 403, "Resource not
# accessible by personal access token". Actions runs and jobs, the commit's
# combined status, pull request views and branch rules still answer. This
# script stands in for `gh pr checks` in every gate that reads a pull
# request's checks (work-on.md's ci_passing, execute.md's owned_ci_passing,
# ci-cancel-after-merge.sh, ci-none-declared.sh and merge-verdict.sh), so
# those gates read CI on whatever the session's token can reach. It never
# changes or drops the token.
#
# Usage: pr-checks.sh [<number> | <url> | <branch>] [--repo <owner/repo>]
#                     [--json <fields>] [--jq <filter>]
#
# 1. It runs `gh pr checks` with its arguments as given. Unless gh's stderr
#    says the read was refused (`Resource not accessible`), gh's stdout,
#    stderr and exit status are passed through unchanged: where the token can
#    read checks, nothing differs from calling gh directly, whatever the
#    arguments.
# 2. On a refusal it reads, with `gh api` on the pull request's own host:
#      gh pr view [<selector>] [--repo R] --json url,headRefOid,headRefName,baseRefName
#      repos/R/actions/runs?head_sha=H           every run at the head
#      repos/R/actions/runs/<id>/jobs            each run's jobs, latest attempt
#      repos/R/commits/H/status                  the combined status
#      repos/R/branches/<base>                   classic required checks
#      repos/R/rules/branches/<base>             required checks from rulesets,
#                                                the organisation's included
#    and prints the list `gh pr checks --json` would: one entry per job (its
#    check run carries the job's name) and one per commit status. It adds one
#    entry per workflow run as well, for the run's own status and
#    conclusion: a run still going may not have listed every job it will run
#    (a later `needs` stage, a dynamic matrix), and a run can end cancelled or
#    failed with every listed job green, so the run reads pending or red
#    whatever its jobs say. A queued run with no job yet reads pending.
#
#    The entries carry gh's fields: name, workflow, link, state, bucket,
#    description, event, startedAt, completedAt. bucket folds the state as gh
#    does: pass (SUCCESS), skipping (SKIPPED, NEUTRAL), fail (FAILURE, ERROR,
#    TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE), cancel (CANCELLED) and
#    pending (anything else), and `unreadable` below. A later run of the same
#    workflow (by its id) on the same event supersedes an earlier finished
#    one by coordinate's board-verdict.sh rule: while the later run is still
#    going, or by a job of the same name that ran (not skipped or neutral);
#    an earlier run still going is never superseded, and a run's own entry
#    drops only when every one of its jobs is. A run that listed no jobs
#    drops only behind a later run that finished success. A skipped later
#    run supersedes nothing. A run for another head is never read, a re-run's earlier
#    attempts are not either, and a run of another workflow or on another
#    event never hides one. A run without a workflow id, event or creation
#    time can't be keyed, so it fails the read, as it does on the board.
#
#    What the token can't read stays visible. A required check (branch
#    protection or a ruleset) that no job and no status answers is listed
#    pending (state EXPECTED, as gh lists a required check not reported yet)
#    while any run is still going, and once every run has finished with state
#    UNREADABLE and bucket `unreadable`: it may exist only as a check run from
#    another app, which this read can't see, so it is never green. A required
#    check pinned to an app other than GitHub Actions can only be such a check
#    run, and so can a ruleset's `workflows` or `code_scanning` rule; each is
#    listed unreadable at once. Every gate counts any bucket but pass and
#    skipping as not green. A check run that isn't required and comes from
#    another app is not seen at all.
#
#    A refused statuses read fails the whole read, where coordinate's board
#    reads on without them: these gates count every check, required or not,
#    so a failed status nobody requires would otherwise read green here while
#    gh reads it red.
#
#    With nothing to list, it answers as gh does for a head with no checks:
#    `no checks reported on the '<branch>' branch` on stderr and exit 1. A
#    read that fails, or a refusal of one of these reads, is exit 1 with the
#    reason on stderr: never an empty or a green list.
#
# With --json, the entries carry the fields named (one of those above); with
# --jq, the filter is applied as gh applies it (raw strings). Without --json
# the list is printed one check per line: name, bucket, workflow, link,
# tab-separated. A note on stderr names the fallback whenever it is taken.
#
# Exit codes: gh's own on the passthrough; on the fallback 0 a list printed,
# 1 no checks or a failed read, 2 usage.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

PROG=pr-checks
# The GitHub Actions app's id on github.com: every check run a workflow job
# reports comes from it.
ACTIONS_APP=15368
FIELDS_OK=" name workflow link state bucket description event startedAt completedAt "

usage() { echo "$PROG: $*" >&2; echo "usage: pr-checks.sh [<number> | <url> | <branch>] [--repo <owner/repo>] [--json <fields>] [--jq <filter>]" >&2; exit 2; }

# The arguments are read for the fallback only. Whatever they are, gh gets
# them first, as given: a flag the fallback can't serve (--watch, --required,
# --web) still works wherever the token can read checks, and is refused only
# when the fallback would have to answer it.
SELECTOR="" REPO_ARG="" FIELDS="" JQF="" HAVE_JSON=0 HAVE_JQ=0 BADARG=""
ARGS=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        --repo|-R) [ $# -ge 2 ] || { BADARG="$1 needs a value"; break; }; REPO_ARG=$2; shift 2 ;;
        --json) [ $# -ge 2 ] || { BADARG="--json needs a value"; break; }; FIELDS=$2; HAVE_JSON=1; shift 2 ;;
        --jq|-q) [ $# -ge 2 ] || { BADARG="$1 needs a value"; break; }; JQF=$2; HAVE_JQ=1; shift 2 ;;
        -*) BADARG="the flag [$1] can't be served from the Actions runs"; break ;;
        *) [ -z "$SELECTOR" ] || { BADARG="a second selector [$1]"; break; }; SELECTOR=$1; shift ;;
    esac
done
[ -n "$BADARG" ] || [ "$HAVE_JQ" = 0 ] || [ "$HAVE_JSON" = 1 ] || BADARG="--jq needs --json"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pr-checks.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---- 1. the check read itself ---------------------------------------------
# Only GitHub's refusal of the check read falls back: "Resource not
# accessible" is in both the GraphQL and the REST wording. Any other failure,
# a 403 for a rate limit included, passes through as gh's own.
gh pr checks ${ARGS[@]+"${ARGS[@]}"} </dev/null >"$TMP/out" 2>"$TMP/err"
RC=$?
if [ "$RC" -eq 0 ] || ! grep -q 'Resource not accessible' "$TMP/err"; then
    cat "$TMP/out"
    cat "$TMP/err" >&2
    exit "$RC"
fi
[ -z "$BADARG" ] || usage "the check read was refused, and $BADARG"

# ---- 2. the fallback --------------------------------------------------------
no() { echo "$PROG: $*" >&2; exit 1; }
echo "$PROG: the check read was refused ($(head -n 1 "$TMP/err" | cut -c1-160)); reading the Actions runs and the commit's statuses instead" >&2

if [ "$HAVE_JSON" = 1 ]; then
    for f in $(printf '%s' "$FIELDS" | tr ',' ' '); do
        case "$FIELDS_OK" in *" $f "*) ;; *) no "field [$f] can't be read from the Actions runs" ;; esac
    done
fi

HERE=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
# shellcheck source=pr-url.sh
. "$HERE/pr-url.sh" || no "pr-url.sh not found at $HERE/pr-url.sh"

# read_api <out> <path> [--paginate]: one GET on the pull request's host; a
# failure, a refusal included, ends the read.
read_api() {
    local out=$1 path=$2
    shift 2
    gh api --method GET "$path" --hostname "$HOST" "$@" </dev/null >"$out" 2>"$out.err" \
        || no "could not read $path: $(head -n 1 "$out.err")"
}

gh pr view ${SELECTOR:+"$SELECTOR"} ${REPO_ARG:+--repo "$REPO_ARG"} --json url,headRefOid,headRefName,baseRefName \
    </dev/null >"$TMP/pr" 2>"$TMP/pr.err" || no "could not read the pull request: $(head -n 1 "$TMP/pr.err")"
IFS=$'\t' read -r URL HEAD BRANCH BASE <<<"$(jq -r '[.url, .headRefOid, .headRefName, .baseRefName] | map(. // "" | tostring) | @tsv' "$TMP/pr")"
pr_url_parse "$URL" || no "could not read the pull request's URL: gh answered [$URL]"
HOST=$PR_HOST
REPO="$PR_OWNER/$PR_REPO"
[[ $HEAD =~ ^[0-9a-f]{40}$ ]] || no "the pull request's head [$HEAD] is not a sha"
[[ $BASE =~ ^[A-Za-z0-9._/-]+$ ]] && case "$BASE" in *..*) false ;; *) true ;; esac \
    || no "the pull request's base [$BASE] is not a branch name"

# Runs at the head. Paginated pages are slurped; the count must reach
# total_count, and a run for another head is dropped.
read_api "$TMP/runs.raw" "repos/$REPO/actions/runs?head_sha=$HEAD&per_page=100" --paginate
jq -sc --arg h "$HEAD" '
    (.[0].total_count) as $t | [ .[].workflow_runs[]? ] as $all
    | if ($t | type) != "number" or ($all | length) != $t then error("\($all | length) runs of \($t)")
      elif any($all[]; (.id | type) != "number" or (.status | type) != "string" or (.workflow_id | type) != "number"
                       or (.event | type) != "string" or (.created_at | type) != "string") then error("a run outside its pattern")
      else [ $all[] | select(.head_sha == $h) ] end' "$TMP/runs.raw" >"$TMP/runs.json" 2>"$TMP/runs.jqerr" \
    || no "the runs at $HEAD could not be read: $(head -n 1 "$TMP/runs.jqerr")"

# Each run's jobs: the default filter, the latest attempt only.
echo '[]' >"$TMP/jobs.json"
for id in $(jq -r '.[].id' "$TMP/runs.json"); do
    read_api "$TMP/jobs-$id.raw" "repos/$REPO/actions/runs/$id/jobs?per_page=100" --paginate
    jq -sc --argjson id "$id" --slurpfile runs "$TMP/runs.json" --slurpfile acc "$TMP/jobs.json" '
        (.[0].total_count) as $t | [ .[].jobs[]? ] as $all
        | ($runs[0][] | select(.id == $id)) as $r
        | if ($t | type) != "number" or ($all | length) != $t then error("\($all | length) jobs of \($t)")
          elif any($all[]; (.id | type) != "number" or (.status | type) != "string" or (.name | type) != "string") then error("a job outside its pattern")
          else $acc[0] + [ $all[] | . + {run: $r} ] end' "$TMP/jobs-$id.raw" >"$TMP/jobs.next" 2>"$TMP/jobs.jqerr" \
        || no "the jobs of run $id could not be read: $(head -n 1 "$TMP/jobs.jqerr")"
    mv "$TMP/jobs.next" "$TMP/jobs.json"
done

# The commit's combined status: the latest status per context.
read_api "$TMP/status.raw" "repos/$REPO/commits/$HEAD/status?per_page=100" --paginate
jq -sc '(.[0].total_count) as $t | [ .[].statuses[]? ] as $all
    | if ($t | type) != "number" or ($all | length) != $t then error("\($all | length) statuses of \($t)")
      elif any($all[]; (.context | type) != "string") then error("a status without a context")
      else $all end' "$TMP/status.raw" >"$TMP/status.json" 2>"$TMP/status.jqerr" \
    || no "the statuses of $HEAD could not be read: $(head -n 1 "$TMP/status.jqerr")"

# The required set: classic protection and the branch rules, both required
# to read. A source that can't be read is a failed read, never "requires
# nothing".
read_api "$TMP/branch.raw" "repos/$REPO/branches/$BASE"
jq -c '
    if .protected == true then
      if (.protection | type) != "object" then error("protected with no readable protection")
      elif .protection.enabled == false or (.protection.required_status_checks // null) == null then []
      else .protection.required_status_checks as $r
        | [ ($r.contexts // [])[] | {name: ., app: null} ]
          + [ ($r.checks // [])[] | {name: .context, app: (.app_id // null)} ] end
    elif .protected == false then []
    else error("no protected flag") end' "$TMP/branch.raw" >"$TMP/req.classic" 2>"$TMP/req.jqerr" \
    || no "the protection of $BASE could not be read: $(head -n 1 "$TMP/req.jqerr")"
# A private repository on a plan without rulesets answers the rules read with
# a 403 that says so ("Upgrade to GitHub Pro or make this repository public to
# enable this feature"): no ruleset can apply to it, so its rules are none.
# Any other failure still ends the read. A `workflows` or `code_scanning` rule
# requires checks it doesn't name; each becomes one required entry pinned to
# app -1, an id no check carries, so it always lists unreadable.
# coordinate's board-verdict.sh makes the same fallback; keep the two in step.
if ! gh api --method GET "repos/$REPO/rules/branches/$BASE" --hostname "$HOST" --paginate </dev/null >"$TMP/rules.raw" 2>"$TMP/rules.raw.err"; then
    grep -q 'Upgrade to GitHub Pro or make this repository public to enable this feature' "$TMP/rules.raw.err" \
        || no "could not read repos/$REPO/rules/branches/$BASE: $(head -n 1 "$TMP/rules.raw.err")"
    echo '[]' >"$TMP/rules.raw"
fi
jq -sc '
    if length == 0 then [] elif all(.[]; type == "array") then add else error("not a list") end
    | [ .[] | select(.type == "required_status_checks") | (.parameters.required_status_checks // [])[]
        | {name: .context, app: (.integration_id // null)} ]
      + [ .[] | select(.type == "workflows" or .type == "code_scanning") | {name: "the ruleset rule \(.type)", app: -1} ]' \
    "$TMP/rules.raw" >"$TMP/req.rules" 2>"$TMP/req.jqerr" \
    || no "the branch rules of $BASE could not be read: $(head -n 1 "$TMP/req.jqerr")"
jq -sc 'add | if any(.[]; (.name | type) != "string") then error("a required check without a name") else unique end' \
    "$TMP/req.classic" "$TMP/req.rules" >"$TMP/req.json" 2>"$TMP/req.jqerr" \
    || no "the required checks of $BASE could not be read: $(head -n 1 "$TMP/req.jqerr")"

# The list, as gh builds it from the rollup.
jq -nc --argjson app "$ACTIONS_APP" --slurpfile runs "$TMP/runs.json" --slurpfile jobs "$TMP/jobs.json" \
    --slurpfile st "$TMP/status.json" --slurpfile req "$TMP/req.json" '
    def bucket: if . == "SUCCESS" then "pass"
        elif . == "SKIPPED" or . == "NEUTRAL" then "skipping"
        elif . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE" then "fail"
        elif . == "CANCELLED" then "cancel"
        elif . == "UNREADABLE" then "unreadable"
        else "pending" end;
    def state_of: (if .status == "completed" then (.conclusion // "") else .status end) | ascii_upcase;
    # Supersession, as board-verdict.sh in coordinate reads it. Runs are keyed
    # by workflow id and event, and ordered by creation, then id. A job of a
    # finished run is superseded when a later run of its key that was not
    # skipped is still going (its own entry reads pending), or has a job of the
    # same name that ran: finished, not skipped or neutral (both of which this
    # list counts green), and not a job GitHub never started (red with no
    # step). A run still going is never superseded: it may yet run a job the
    # later one does not. The entry for a run itself drops only when every one
    # of its jobs is superseded. (No apostrophes in this program: it is a
    # single-quoted shell string.)
    def ran: .status == "completed" and ((.conclusion // "") | IN("skipped", "neutral") | not)
        and ((((.conclusion // "") | IN("failure", "cancelled", "timed_out")) and ((.steps // []) | length) == 0) | not);
    $runs[0] as $R | $jobs[0] as $J
    | [ $R[] | . as $r | select(.status == "completed")
        | [ $R[] | select(.workflow_id == $r.workflow_id and .event == $r.event
                          and ([.created_at, .id] > [$r.created_at, $r.id])
                          and ((.status == "completed" and .conclusion == "skipped") | not)) ] as $later
        | select(($later | length) > 0)
        | [ $J[] | select(.run.id == $r.id) ] as $mine
        | [ $mine[] | . as $j
            | select(any($later[]; .status != "completed"
                         or (.id as $lid | any($J[]; .run.id == $lid and .name == $j.name and ran))))
            | .id ] as $gone
        # A run with no jobs (a startup failure, say) has nothing a later job
        # could answer for, so only a later run that finished success
        # supersedes it: a neutral or cancelled one would hide its red.
        | {run: $r.id, jobs: $gone,
           whole: (if ($mine | length) == 0
                   then any($later[]; .status == "completed" and .conclusion == "success")
                   else ($gone | length) == ($mine | length) end)} ] as $sup
    | [ $sup[].jobs[] ] as $sjobs | [ $sup[] | select(.whole) | .run ] as $sruns
    | ([ $J[] | select(.id as $i | $sjobs | index($i) | not)
         | {name, workflow: (.run.name // ""), link: (.html_url // ""), state: state_of,
            description: "", event: (.run.event // ""), startedAt: (.started_at // ""),
            completedAt: (.completed_at // ""), kind: "job"} ]
       + [ $R[] | select(.id as $i | $sruns | index($i) | not)
         | {name: (.name // ""), workflow: (.name // ""), link: (.html_url // ""), state: state_of,
            description: "the workflow run", event: (.event // ""), startedAt: (.run_started_at // .created_at // ""),
            completedAt: "", kind: "run"} ])
    as $actions
    | [ $st[0][] | {name: .context, workflow: "", link: (.target_url // ""), state: ((.state // "pending") | ascii_upcase),
          description: (.description // ""), event: "", startedAt: (.created_at // ""), completedAt: "", kind: "status"} ] as $statuses
    | ($actions + $statuses) as $seen
    | any($actions[]; .state | IN("QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "PENDING")) as $running
    # A required check is answered by a job of its name, or, when no app is
    # pinned, by a status of its name. A run with no job yet answers nothing.
    # While a run is still going, a check it may yet report is EXPECTED, as
    # gh lists a required check not reported yet (pending); once every run
    # has finished it is UNREADABLE. A check pinned to another app can never
    # be answered here, so it is UNREADABLE at once.
    | [ $req[0][] | . as $q
        | ($q.app == null or $q.app == $app) as $visible
        | [ $seen[] | select(.name == $q.name and (.kind == "job" or (.kind == "status" and $q.app == null))) ] as $answers
        | select(($visible | not) or ($answers | length) == 0)
        | if $visible and $running then
            {name: $q.name, workflow: "", link: "", state: "EXPECTED",
             description: "required, and not reported yet by the runs still going",
             event: "", startedAt: "", completedAt: "", kind: "required"}
          else
            {name: $q.name, workflow: "", link: "", state: "UNREADABLE",
             description: "required, and no Actions job or commit status reports it; the token cannot read check runs",
             event: "", startedAt: "", completedAt: "", kind: "required"}
          end ] as $unseen
    | [ ($seen + $unseen)[] | . + {bucket: (.state | bucket)} | del(.kind) ]' >"$TMP/list.json" \
    || no "internal: the list could not be built"

if [ "$(jq length "$TMP/list.json")" = 0 ]; then
    echo "no checks reported on the '$BRANCH' branch" >&2
    exit 1
fi

if [ "$HAVE_JSON" = 0 ]; then
    jq -r '.[] | [.name, .bucket, .workflow, .link] | @tsv' "$TMP/list.json"
    exit 0
fi
jq -c --arg f "$FIELDS" '[ .[] | with_entries(select(.key as $k | $f | split(",") | index($k))) ]' "$TMP/list.json" >"$TMP/sel.json" \
    || no "internal: the fields could not be selected"
if [ "$HAVE_JQ" = 1 ]; then
    jq -r "$JQF" "$TMP/sel.json" || exit 1
else
    cat "$TMP/sel.json"
fi
exit 0
