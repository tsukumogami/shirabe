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
#    says the read was refused (`HTTP 403` or `Resource not accessible`), gh's
#    stdout, stderr and exit status are passed through unchanged: where the
#    token can read checks, nothing differs from calling gh directly.
# 2. On a refusal it reads, with `gh api` on the pull request's own host:
#      gh pr view [<selector>] [--repo R] --json url,headRefOid,headRefName,baseRefName
#      repos/R/actions/runs?head_sha=H           every run at the head
#      repos/R/actions/runs/<id>/jobs            each run's jobs, latest attempt
#      repos/R/commits/H/status                  the combined status
#      repos/R/branches/<base>                   classic required checks
#      repos/R/rules/branches/<base>             required checks from rulesets,
#                                                the organisation's included
#    and prints the list `gh pr checks --json` would: one entry per job (its
#    check run carries the job's name), one per commit status, and one per
#    run that has no job yet, so a queued run reads pending.
#
#    The entries carry gh's fields: name, workflow, link, state, bucket,
#    description, event, startedAt, completedAt. bucket folds the state as gh
#    does: pass (SUCCESS), skipping (SKIPPED, NEUTRAL), fail (FAILURE, ERROR,
#    TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE), cancel (CANCELLED) and
#    pending (anything else). As gh does, a later check of the same name and
#    workflow hides an earlier one: a new run of a workflow at the same head
#    answers for it. A run for another head is never read, and a re-run's
#    earlier attempts are not either.
#
#    What the token can't read stays visible. A required check (branch
#    protection or a ruleset) that no job and no status answers is listed
#    with state UNREADABLE and bucket `unreadable`: it may exist only as a
#    check run from another app, which this read can't see, so it is never
#    green. A required check pinned to an app other than GitHub Actions can
#    only be such a check run, and so can a ruleset's `workflows` or
#    `code_scanning` rule; each is listed unreadable too. Every gate counts
#    any bucket but pass and skipping as not green. A check run that isn't
#    required and comes from another app is not seen at all.
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

SELECTOR="" REPO_ARG="" FIELDS="" JQF="" HAVE_JSON=0 HAVE_JQ=0
ARGS=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        --repo|-R) [ $# -ge 2 ] || usage "$1 needs a value"; REPO_ARG=$2; shift 2 ;;
        --json) [ $# -ge 2 ] || usage "--json needs a value"; FIELDS=$2; HAVE_JSON=1; shift 2 ;;
        --jq|-q) [ $# -ge 2 ] || usage "$1 needs a value"; JQF=$2; HAVE_JQ=1; shift 2 ;;
        -*) usage "unknown flag [$1]" ;;
        *) [ -z "$SELECTOR" ] || usage "a second selector [$1]"; SELECTOR=$1; shift ;;
    esac
done
[ "$HAVE_JQ" = 0 ] || [ "$HAVE_JSON" = 1 ] || usage "--jq needs --json"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pr-checks.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---- 1. the check read itself ---------------------------------------------
gh pr checks ${ARGS[@]+"${ARGS[@]}"} </dev/null >"$TMP/out" 2>"$TMP/err"
RC=$?
if [ "$RC" -eq 0 ] || ! grep -Eq 'HTTP 403|Resource not accessible' "$TMP/err"; then
    cat "$TMP/out"
    cat "$TMP/err" >&2
    exit "$RC"
fi

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
      elif any($all[]; (.id | type) != "number" or (.status | type) != "string") then error("a run outside its pattern")
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
# Any other failure still ends the read.
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
    ([ $jobs[0][] | {name, workflow: (.run.name // ""), link: (.html_url // ""),
        state: ((if .status == "completed" then (.conclusion // "") else .status end) | ascii_upcase),
        description: "", event: (.run.event // ""), startedAt: (.started_at // ""),
        completedAt: (.completed_at // ""), kind: "job"} ]
     + [ $runs[0][] | . as $r | select(all($jobs[0][]; .run.id != $r.id))
         | {name: (.name // ""), workflow: (.name // ""), link: (.html_url // ""),
            state: ((if .status == "completed" then (.conclusion // "") else .status end) | ascii_upcase),
            description: "", event: (.event // ""), startedAt: (.run_started_at // .created_at // ""),
            completedAt: "", kind: "run"} ]
     # gh keeps the latest check of each name in each workflow.
     | group_by([.workflow, .name]) | map(max_by([.startedAt, .link])))
    as $actions
    | [ $st[0][] | {name: .context, workflow: "", link: (.target_url // ""), state: ((.state // "pending") | ascii_upcase),
          description: (.description // ""), event: "", startedAt: (.created_at // ""), completedAt: "", kind: "status"} ] as $statuses
    | ($actions + $statuses) as $seen
    # A required check is answered by a job of its name, or, when no app is
    # pinned, by a status of its name. A run with no job yet answers nothing.
    | [ $req[0][] | . as $q
        | ($q.app == null or $q.app == $app) as $visible
        | [ $seen[] | select(.name == $q.name and (.kind == "job" or (.kind == "status" and $q.app == null))) ] as $answers
        | select(($visible | not) or ($answers | length) == 0)
        | {name: $q.name, workflow: "", link: "", state: "UNREADABLE",
           description: "required, and no Actions job or commit status reports it; the token cannot read check runs",
           event: "", startedAt: "", completedAt: "", kind: "required"} ] as $unseen
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
