#!/usr/bin/env bash
# board-verdict.sh -- read the CI board at a pull request's head (or at a sha)
# and judge whether it really ran. Read-only: it writes nothing to GitHub or
# koto, reads nothing from stdin or koto context, and takes no value from the
# coordinator but the repository and the number.
#
# Usage:
#   board-verdict.sh --repo <owner/repo> --pr <n> [--head-only]
#   board-verdict.sh --repo <owner/repo> --sha <40-hex> --base <branch>
#
# The reads, in order, every one `gh api --method GET` or a GraphQL query,
# each at most two attempts 1 s apart, all inside a 24-second deadline:
#   1. snapshot: one paginated GraphQL query for the pull request's state,
#      head, head branch and repository, base, merge state and every check
#      context at the head commit with isRequired. The commit's oid and every
#      page must agree on the head H; the contexts collected must equal their
#      totalCount. A merge state of UNKNOWN is re-read once after 2 s.
#   2. runs:  repos/R/actions/runs?head_sha=H (every event and branch); the
#      count must equal total_count; runs for another sha are ignored.
#   3. jobs:  repos/R/actions/runs/<id>/jobs, the default latest-attempt
#      filter, six reads at a time, for every completed run that isn't
#      skipped or startup_failure.
#   4. the required set: the union of classic branch protection
#      (repos/R/branches/<base>), the branch rules (repos/R/rules/branches/
#      <base>) and every rollup entry with isRequired. An unreadable source is
#      an error, never "requires nothing". A name that protection or a ruleset
#      pins to an app matches only check runs from that app.
#   5. files:  repos/R/pulls/N/files, for the workflows-changed note.
#   6. the remote ref last: repos/<head repo>/git/ref/heads/<head branch> must
#      still be H, so a push during the read shows as a moved head.
# When the token can't read checks (GitHub refuses the snapshot's rollup, or
# the commit's check runs, with a 403 or "Resource not accessible"), the
# snapshot is read again without the rollup and the check contexts are the
# Actions jobs from reads 2 and 3: each job is a check run named for it, from
# the GitHub Actions app. `source` says which was read (`checks` or
# `actions`), and a `checks-refused` note says what was refused. Only a
# refusal falls back; any other failed read is still an error. With the jobs
# as checks, a required check that only another app or a commit status
# reports reads missing: never a pass.
# With --sha, there is no pull request: the head is the sha, the required set
# comes from <base>'s protection and rules, and the rollup is the commit's
# check runs and statuses (repos/R/commits/S/check-runs and .../status); no
# merge state, files or ref are read. --head-only reads the snapshot without
# the rollup and the ref, and prints {"verdict":"head","head":H} when both
# agree, else {"verdict":"error:head-moved","head":H,"ref":<ref sha>} or
# another error form.
#
# Output (exit 0): one compact JSON object on stdout, diagnostics on stderr:
#   {"verdict", "head", "source", "pr_state", "merge_state", "reasons":
#    [{code, run?, job?, name?, detail?}], "skipped", "superseded",
#    "required": [{name, source, result}], "counts": {runs, jobs, jobs_ran,
#    required}, "notes": [{code: "workflows-changed", paths} | {code:
#    "checks-refused" | "statuses-refused", detail}]}
# pr_state is the pull request's state (OPEN, MERGED, CLOSED) when the
# snapshot was read, else null.
# verdict: verified | pending | unverified | error:board-read |
# error:pr-state | error:deadline (and head | error:head-moved with
# --head-only). Precedence: any read failure or the deadline is an error;
# else any definite failure is unverified; else anything still running is
# pending; else verified, which is printed only with no reasons and a 40-hex
# head. Reason codes (class): board-empty, run-startup-failure,
# run-conclusion, job-conclusion, job-no-runner, job-no-succeeded-step,
# merge-state-dirty (unverified); run-pending, job-pending, required-pending,
# merge-state-unknown, head-moved (pending); required-missing (pending while
# a run is pending, else unverified); required-conclusion (unverified,
# skipped included); read-failed, required-set-unreadable, deadline (error).
# `notes` never changes the verdict: a change under .github/workflows/ or
# .github/actions/ is named there, because holding such a pull request would
# be a permission rule of the skill's own.
#
# Exit codes: 0 JSON printed; 2 usage (nothing read); 1 internal failure
# (nothing printed).
set -uo pipefail

PROG=board-verdict
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { echo "$PROG: $*" >&2; sed -n '/^# Usage:/,/^#   board-verdict.sh --repo <owner\/repo> --sha/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

REPO= PR= SHA= BASE= HEAD_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) [ $# -ge 2 ] && [ -z "$REPO" ] || usage "bad --repo"; REPO=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] && [ -z "$PR" ] || usage "bad --pr"; PR=$2; shift 2 ;;
        --sha) [ $# -ge 2 ] && [ -z "$SHA" ] || usage "bad --sha"; SHA=$2; shift 2 ;;
        --base) [ $# -ge 2 ] && [ -z "$BASE" ] || usage "bad --base"; BASE=$2; shift 2 ;;
        --head-only) [ "$HEAD_ONLY" = 0 ] || usage "--head-only twice"; HEAD_ONLY=1; shift ;;
        *) usage "unknown argument [$1]" ;;
    esac
done
bl_repo_ok "$REPO" || usage "--repo [$REPO] is not owner/repo"
if [ -n "$PR" ]; then
    [ -z "$SHA$BASE" ] || usage "--pr excludes --sha and --base"
    bl_pr_ok "$PR" || usage "--pr [$PR] is not a number"
    MODE=pr
else
    [ -n "$SHA" ] && [ -n "$BASE" ] || usage "give --pr, or --sha with --base"
    [ "$HEAD_ONLY" = 0 ] || usage "--head-only needs --pr"
    bl_sha_ok "$SHA" || usage "--sha [$SHA] is not a 40-character lowercase sha"
    bl_branch_ok "$BASE" || usage "--base [$BASE] is not a branch name"
    MODE=sha
fi
OWNER=${REPO%%/*}
NAME=${REPO#*/}

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/board-verdict.XXXXXX") || exit 1
trap 'rm -rf "$TMPD"' EXIT
: > "$TMPD/reasons.jsonl"
STOPPED=

# reason <code> [detail]: a finding from the reads themselves.
reason() { jq -nc --arg c "$1" --arg d "${2-}" '{code: $c} + (if $d == "" then {} else {detail: $d} end)' >> "$TMPD/reasons.jsonl"; }
# checks_refused <what>: the token can't read that check source, so the check
# contexts come from the Actions jobs instead (SOURCE=actions); a note names it.
SOURCE=checks
: > "$TMPD/notes.jsonl"
checks_refused() {
    SOURCE=actions
    jq -nc --arg d "$1" '{code: "checks-refused", detail: "\($d) was refused; the checks are the Actions jobs at the head"}' >> "$TMPD/notes.jsonl"
}
# actions_contexts [status contexts]: the check contexts as the Actions jobs
# read at the head (a job's check run carries the job's name and is GitHub
# Actions'), plus the status contexts in the given file, into
# $TMPD/snap.json. A run still going had no jobs read, so a required check it
# would report reads missing: pending while it runs, unverified once every run
# is done. A pin to another app (a GitHub Enterprise Server's Actions app has
# its own id) reads missing too: never a pass.
ACTIONS_APP=15368
actions_contexts() {
    local st=${1:-/dev/null} base=$TMPD/snap.json
    [ -f "$base" ] || { echo '{"head": null, "merge_state": null}' > "$TMPD/snap.base"; base=$TMPD/snap.base; }
    jq -c --slurpfile j "$TMPD/jobs.json" --slurpfile st "$st" --argjson app "$ACTIONS_APP" '
        .contexts = ([ ($j[0] // {}) | to_entries[] | .value[]
            | {kind: "check", name, done: (.status == "completed"),
               result: ((if .status == "completed" then (.conclusion // "none") else .status end) | ascii_upcase),
               required: false, app: $app} ]
          + ($st[0] // []))' "$base" > "$TMPD/snap.ctx" || return 1
    mv "$TMPD/snap.ctx" "$TMPD/snap.json"
}
# read_failed <out> <what>: record why a bl_gh read failed.
read_failed() {
    if [ "$(cat "$1.fail" 2>/dev/null)" = deadline ]; then reason deadline "$2"
    else reason read-failed "$2"; fi
}

# ---- the judgement --------------------------------------------------------
# Inputs are files in $TMPD; an absent file means the read didn't happen.
read -r -d '' JUDGE <<'JQ'
def slurp1($f): if ($f | length) > 0 then $f[0] else null end;
def cls: {"board-empty":"u", "run-startup-failure":"u", "run-conclusion":"u",
  "job-conclusion":"u", "job-no-runner":"u", "job-no-succeeded-step":"u",
  "merge-state-dirty":"u", "required-conclusion":"u",
  "run-pending":"p", "job-pending":"p", "required-pending":"p",
  "merge-state-unknown":"p", "head-moved":"p",
  "read-failed":"e", "required-set-unreadable":"e", "deadline":"e"};
slurp1($snap) as $s | slurp1($runs) as $runs | slurp1($jobs) as $jobs
| slurp1($req) as $req | slurp1($ref) as $ref | slurp1($files) as $files
| $cnotes as $cnotes
| $reads as $early
| (if $mode == "sha" then $sha else ($s.head // null) end) as $H
# runs
| ($runs // []) as $R
| [ $R[] | select(.status != "completed")
    | {code: "run-pending", run: .id, name: .name, detail: .status} ] as $rp
| [ $R[] | select(.status == "completed" and .conclusion == "startup_failure")
    | {code: "run-startup-failure", run: .id, name: .name} ] as $rsf
| [ $R[] | select(.status == "completed" and ((.conclusion // "null") | IN("success", "skipped", "startup_failure") | not))
    | {code: "run-conclusion", run: .id, name: .name, detail: (.conclusion // "null")} ] as $rc
| [ $R[] | select(.status == "completed" and .conclusion == "skipped") | {run: .id, name: .name} ] as $rskip
# jobs, for the runs whose jobs were read
| [ ($jobs // {}) | to_entries[] | .key as $rid | .value[] | . + {run: ($rid | tonumber)} ] as $J
| [ $J[] | select(.status != "completed") | {code: "job-pending", run, job: .id, name, detail: .status} ] as $jp
| [ $J[] | select(.status == "completed" and .conclusion == "skipped") | {run, job: .id, name} ] as $jskip
| [ $J[] | select(.status == "completed" and .conclusion != "skipped") ] as $ran
| [ $ran[] | select(.conclusion != "success") | {code: "job-conclusion", run, job: .id, name, detail: (.conclusion // "null")} ] as $jc
| [ $ran[] | select((.runner_name // "") == "") | {code: "job-no-runner", run, job: .id, name} ] as $jnr
| [ $ran[] | ((.steps // []) | length) as $n | select(([(.steps // [])[] | select(.conclusion == "success")] | length) == 0)
    | {code: "job-no-succeeded-step", run, job: .id, name, detail: "0 of \($n) steps succeeded"} ] as $jns
| (($rp + $jp) | length > 0) as $running
| (if $runs == null then []
   elif ($R | length) == 0 then [{code: "board-empty", detail: "no workflow run at the head"}]
   elif ($ran | length) == 0 and ($running | not) then [{code: "board-empty", detail: "every job at the head was skipped"}]
   else [] end) as $empty
# the required set
| ($s.contexts // []) as $ctx
| (if $req == null then [] else
    ($req + [ $ctx[] | select(.required) | {name, source: "rollup", app: null} ])
    | group_by(.name)
    | map({name: .[0].name, source: ([.[].source] | unique), apps: ([.[].app | select(. != null)] | unique)})
   end) as $reqset
| [ $reqset[] | . as $q
    | [ $ctx[] | select(.name == $q.name)
        | select(($q.apps | length) == 0 or (.kind == "check" and (.app as $a | $q.apps | index($a)) != null)) ] as $c
    | [ $c[] | select(.done | not) ] as $pend
    | [ $c[] | select(.done and .result != "SUCCESS") ] as $bad
    | if ($c | length) == 0 then
        {name: $q.name, source: $q.source, result: "MISSING",
         reason: {code: "required-missing", name: $q.name, detail: (if $running then "not reported yet" else "not reported and every run finished" end), cls: (if $running then "p" else "u" end)}}
      elif ($bad | length) > 0 then
        {name: $q.name, source: $q.source, result: $bad[0].result,
         reason: {code: "required-conclusion", name: $q.name, detail: ([$bad[].result] | unique | join(","))}}
      elif ($pend | length) > 0 then
        {name: $q.name, source: $q.source, result: "PENDING",
         reason: {code: "required-pending", name: $q.name, detail: ([$pend[].result] | unique | join(","))}}
      else {name: $q.name, source: $q.source, result: "SUCCESS", reason: null} end ] as $reqj
| [ $reqj[] | .reason | select(. != null) ] as $rr
# merge state and the ref
| ($s.merge_state // null) as $ms
| (if $ms == "DIRTY" then [{code: "merge-state-dirty", detail: "DIRTY"}]
   elif $ms == "UNKNOWN" then [{code: "merge-state-unknown", detail: "UNKNOWN after a re-read"}]
   else [] end) as $msr
| (if $ref != null and $H != null and $ref != $H then [{code: "head-moved", detail: "the remote ref is \($ref)"}] else [] end) as $hm
| ($early + $rp + $rsf + $rc + $jp + $jc + $jnr + $jns + $empty + $rr + $msr + $hm) as $all
| [ $all[] | . + {cls: (.cls // cls[.code] // "e")} ] as $allc
| (if $stopped == "pr-state" then "error:pr-state"
   elif any($allc[]; .code == "deadline") then "error:deadline"
   elif any($allc[]; .cls == "e") then "error:board-read"
   elif any($allc[]; .cls == "u") then "unverified"
   elif any($allc[]; .cls == "p") then "pending"
   elif ($H | type) == "string" and ($H | test("^[0-9a-f]{40}$")) then "verified"
   else "error:board-read" end) as $verdict
| [ ($files // [])[] | select(test("^\\.github/(workflows|actions)/")) ] as $wf
| {verdict: $verdict,
   head: $H,
   source: $source,
   pr_state: ($s.state // null),
   merge_state: $ms,
   reasons: [ $allc[] | del(.cls) ],
   skipped: ($rskip + $jskip),
   superseded: [ $R[] | select((.run_attempt // 1) > 1) | {run: .id, name, latest_attempt: .run_attempt, earlier: [range(1; .run_attempt)]} ],
   required: [ $reqj[] | {name, source, result} ],
   counts: {runs: ($R | length), jobs: ($J | length), jobs_ran: ($ran | length), required: ($reqj | length)},
   notes: ((if ($wf | length) > 0 then [{code: "workflows-changed", paths: ($wf | unique)}] else [] end) + $cnotes)}
JQ

emit() {
    local f
    for f in snap runs jobs req ref files; do [ -f "$TMPD/$f.json" ] || : > "$TMPD/$f.json"; done
    jq -nc --arg mode "$MODE" --arg sha "$SHA" --arg stopped "$STOPPED" --arg source "$SOURCE" \
        --slurpfile cnotes "$TMPD/notes.jsonl" \
        --slurpfile snap "$TMPD/snap.json" --slurpfile runs "$TMPD/runs.json" \
        --slurpfile jobs "$TMPD/jobs.json" --slurpfile req "$TMPD/req.json" \
        --slurpfile ref "$TMPD/ref.json" --slurpfile files "$TMPD/files.json" \
        --slurpfile reads "$TMPD/reasons.jsonl" "$JUDGE" || { echo "$PROG: internal: the judgement failed" >&2; exit 1; }
    exit 0
}

# ---- 1. the snapshot ------------------------------------------------------
read -r -d '' Q_FULL <<'GQL'
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      state isDraft headRefOid headRefName headRepository { nameWithOwner } baseRefName mergeStateStatus
      commits(last: 1) { nodes { commit { oid statusCheckRollup { contexts(first: 100, after: $endCursor) {
        totalCount pageInfo { hasNextPage endCursor }
        nodes { __typename
          ... on CheckRun { name status conclusion isRequired(pullRequestNumber: $number) checkSuite { app { databaseId } } }
          ... on StatusContext { context state isRequired(pullRequestNumber: $number) } } } } } } }
    }
  }
}
GQL
read -r -d '' Q_HEAD <<'GQL'
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      state headRefOid headRefName headRepository { nameWithOwner } baseRefName mergeStateStatus
      commits(last: 1) { nodes { commit { oid } } }
    }
  }
}
GQL

# The normalised snapshot, or {"problem": ...}. Every value that later
# builds a path or a JSON field is held to its pattern here.
read -r -d '' NORM_SNAP <<'JQ'
def pr: .data.repository.pullRequest;
def norm:
  if .__typename == "CheckRun" then
    {kind: "check", name, done: (.status == "COMPLETED"),
     result: (if .status == "COMPLETED" then (.conclusion // "NONE") else (.status // "NONE") end),
     required: (.isRequired == true), app: (.checkSuite.app.databaseId // null)}
  elif .__typename == "StatusContext" then
    {kind: "status", name: .context, done: ((.state // "PENDING") | IN("PENDING", "EXPECTED") | not),
     result: (.state // "PENDING"), required: (.isRequired == true), app: null}
  else {kind: "other", name: null} end;
. as $pages
| if length == 0 or any(.[]; (.errors // null) != null or ((pr // null) == null)) then {problem: "no pull request in the response"}
  else ($pages[0] | pr) as $p
  | ($p.commits.nodes[0].commit.statusCheckRollup.contexts.totalCount // 0) as $total
  | [ $pages[] | pr.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // [] | .[] | norm ] as $ctx
  | {state: $p.state, head: $p.headRefOid, head_ref: $p.headRefName,
     head_repo: ($p.headRepository.nameWithOwner // null), base: $p.baseRefName,
     merge_state: $p.mergeStateStatus, contexts: $ctx}
  | if ([ $pages[] | pr.headRefOid ] | unique | length) != 1 then {problem: "pages disagree on the head"}
    elif any($pages[]; (pr.commits.nodes[0].commit.oid // "") != $p.headRefOid) then {problem: "the commit node is not the head"}
    elif (.head | type) != "string" or (.head | test("^[0-9a-f]{40}$") | not) then {problem: "the head is not a sha"}
    elif (.merge_state | type) != "string" or (.merge_state | test("^[A-Z_]+$") | not) then {problem: "the merge state is outside its pattern"}
    elif (.state | type) != "string" then {problem: "no state"}
    elif $full and ($ctx | length) != $total then {problem: "\($ctx | length) contexts of \($total)"}
    elif any($ctx[]; (.name | type) != "string" or (.result | type) != "string") then {problem: "a context without a name"}
    else . end
  end
JQ

snapshot() { # snapshot <full 0|1> [fallback]: read and normalise into $TMPD/snap.json
    # Returns 0 read; 1 failed (a reason recorded); 3, only when asked for
    # with `fallback`, the full read was refused and no reason is recorded, so
    # the caller can read the pull request without the rollup.
    local q=$Q_HEAD pag=
    if [ "$1" = 1 ]; then q=$Q_FULL; pag=--paginate; fi
    if ! bl_gh "$TMPD/snap.raw" api graphql $pag -F "owner=$OWNER" -F "name=$NAME" -F "number=$PR" -f "query=$q"; then
        if [ "${2-}" = fallback ] && [ "$(cat "$TMPD/snap.raw.fail" 2>/dev/null)" = refused ]; then return 3; fi
        read_failed "$TMPD/snap.raw" "snapshot"; return 1
    fi
    if ! jq -sc --argjson full "$([ "$1" = 1 ] && echo true || echo false)" "$NORM_SNAP" "$TMPD/snap.raw" > "$TMPD/snap.n"; then
        reason read-failed "snapshot: not JSON"; return 1
    fi
    if jq -e 'has("problem")' "$TMPD/snap.n" >/dev/null; then
        reason read-failed "snapshot: $(jq -r .problem "$TMPD/snap.n")"; return 1
    fi
    mv "$TMPD/snap.n" "$TMPD/snap.json"
}

# ---- 6. the ref (read last) -----------------------------------------------
read_ref() {
    local hr hb
    hr=$(jq -r '.head_repo // ""' "$TMPD/snap.json")
    hb=$(jq -r '.head_ref // ""' "$TMPD/snap.json")
    bl_repo_ok "$hr" && bl_branch_ok "$hb" || { reason read-failed "head repository or branch outside its pattern"; return 1; }
    if ! bl_gh "$TMPD/ref.raw" api --method GET "repos/$hr/git/ref/heads/$hb"; then
        read_failed "$TMPD/ref.raw" "ref"; return 1
    fi
    jq -c '.object.sha // "" | select(test("^[0-9a-f]{40}$"))' "$TMPD/ref.raw" > "$TMPD/ref.json"
    [ -s "$TMPD/ref.json" ] || { rm -f "$TMPD/ref.json"; reason read-failed "ref: no sha"; return 1; }
}

if [ "$MODE" = pr ]; then
    if [ "$HEAD_ONLY" = 1 ]; then
        snapshot 0 || { jq -nc '{verdict: "error:board-read", head: null}'; exit 0; }
        H=$(jq -r .head "$TMPD/snap.json")
        if [ "$(jq -r .state "$TMPD/snap.json")" != OPEN ]; then
            jq -nc --arg h "$H" '{verdict: "error:pr-state", head: $h}'; exit 0
        fi
        read_ref || { V=error:board-read; grep -q '"deadline"' "$TMPD/reasons.jsonl" && V=error:deadline
                      jq -nc --arg v "$V" --arg h "$H" '{verdict: $v, head: $h}'; exit 0; }
        R=$(jq -r . "$TMPD/ref.json")
        if [ "$R" = "$H" ]; then jq -nc --arg h "$H" '{verdict: "head", head: $h}'
        else jq -nc --arg h "$H" --arg r "$R" '{verdict: "error:head-moved", head: $h, ref: $r}'; fi
        exit 0
    fi
    FULL=1
    snapshot 1 fallback; rc=$?
    if [ $rc -eq 3 ]; then
        # The token can't read the check rollup: read the pull request
        # without it, and judge the checks from the Actions jobs instead.
        echo "$PROG: the check rollup was refused; reading the checks from the Actions runs" >&2
        checks_refused "the pull request's check rollup"
        FULL=0
        snapshot 0 || emit
    elif [ $rc -ne 0 ]; then
        emit
    fi
    if [ "$(jq -r .state "$TMPD/snap.json")" != OPEN ]; then
        echo "$PROG: pull request #$PR is $(jq -r .state "$TMPD/snap.json")" >&2
        STOPPED=pr-state; emit
    fi
    if [ "$(jq -r .merge_state "$TMPD/snap.json")" = UNKNOWN ]; then
        # GitHub computes the merge state lazily; give it one more look.
        [ "$(bl_left)" -gt 2 ] && sleep 2
        snapshot $FULL || emit
        [ "$(jq -r .state "$TMPD/snap.json")" = OPEN ] || { STOPPED=pr-state; emit; }
    fi
    H=$(jq -r .head "$TMPD/snap.json")
    BASEB=$(jq -r '.base // ""' "$TMPD/snap.json")
    bl_branch_ok "$BASEB" || { reason read-failed "base branch outside its pattern"; emit; }
else
    H=$SHA
    BASEB=$BASE
fi

# ---- 2. runs at H -----------------------------------------------------------
if ! bl_gh "$TMPD/runs.raw" api --method GET "repos/$REPO/actions/runs?head_sha=$H&per_page=100" --paginate; then
    read_failed "$TMPD/runs.raw" "runs"; emit
fi
if ! jq -sc --arg h "$H" '
    if length == 0 then error("empty") else . end
    | (.[0].total_count) as $t | [ .[].workflow_runs[]? ] as $all
    | if ($t | type) != "number" or ($all | length) != $t then error("\($all | length) runs of \($t)")
      elif any($all[]; (.id | type) != "number" or (.status | type) != "string" or ((.run_attempt // 1) | type) != "number") then error("a run outside its pattern")
      else [ $all[] | select(.head_sha == $h) | {id, name: (.name // "" | tostring), status, conclusion, run_attempt: (.run_attempt // 1)} ] end' \
    "$TMPD/runs.raw" > "$TMPD/runs.json" 2>"$TMPD/runs.jqerr"; then
    rm -f "$TMPD/runs.json"
    reason read-failed "runs: $(sed 's/^jq: error.*): //' "$TMPD/runs.jqerr" | head -1)"; emit
fi

# ---- 3. jobs per run, latest attempt, six at a time --------------------------
IDS=$(jq -r '.[] | select(.status == "completed" and ((.conclusion // "") | IN("startup_failure", "skipped") | not)) | .id' "$TMPD/runs.json")
n=0
for id in $IDS; do
    ( bl_gh "$TMPD/jobs-$id.raw" api --method GET "repos/$REPO/actions/runs/$id/jobs?per_page=100" --paginate ) &
    n=$((n + 1))
    [ $((n % 6)) -eq 0 ] && wait
done
wait
echo '{}' > "$TMPD/jobs.acc"
for id in $IDS; do
    if [ -f "$TMPD/jobs-$id.raw.fail" ]; then
        read_failed "$TMPD/jobs-$id.raw" "jobs of run $id"; emit
    fi
    if ! jq -sc '
        if length == 0 then error("empty") else . end
        | (.[0].total_count) as $t | [ .[].jobs[]? ] as $all
        | if ($t | type) != "number" or ($all | length) != $t then error("\($all | length) jobs of \($t)")
          elif any($all[]; (.id | type) != "number" or (.status | type) != "string") then error("a job outside its pattern")
          else [ $all[] | {id, name: (.name // "" | tostring), status, conclusion, runner_name, steps: [ (.steps // [])[] | {conclusion} ]} ] end' \
        "$TMPD/jobs-$id.raw" > "$TMPD/jobs-$id.json" 2>"$TMPD/jobs.jqerr"; then
        reason read-failed "jobs of run $id: $(sed 's/^jq: error.*): //' "$TMPD/jobs.jqerr" | head -1)"; emit
    fi
    jq -c --arg id "$id" --slurpfile j "$TMPD/jobs-$id.json" '. + {($id): $j[0]}' "$TMPD/jobs.acc" > "$TMPD/jobs.tmp" && mv "$TMPD/jobs.tmp" "$TMPD/jobs.acc"
done
mv "$TMPD/jobs.acc" "$TMPD/jobs.json"
if [ "$MODE" = pr ] && [ "$SOURCE" = actions ]; then
    actions_contexts || { reason read-failed "the Actions jobs as checks"; emit; }
fi

# ---- 4. the required set -----------------------------------------------------
if ! bl_gh "$TMPD/branch.raw" api --method GET "repos/$REPO/branches/$BASEB"; then
    if [ "$(cat "$TMPD/branch.raw.fail")" = deadline ]; then reason deadline "branch"
    else reason required-set-unreadable "branch protection of $BASEB"; fi
    emit
fi
if ! jq -ce '
    if .protected == true then
      if (.protection | type) != "object" then error("protected with no readable protection")
      elif .protection.enabled == false or (.protection.required_status_checks // null) == null then []
      else .protection.required_status_checks as $r
        | [ ($r.contexts // [])[] | {name: ., source: "classic", app: null} ]
          + [ ($r.checks // [])[] | {name: .context, source: "classic", app: (.app_id // null)} ] end
    elif .protected == false then []
    else error("no protected flag") end
    | if any(.[]; (.name | type) != "string") then error("a required context without a name") else . end' \
    "$TMPD/branch.raw" > "$TMPD/req.classic" 2>/dev/null; then
    reason required-set-unreadable "branch protection of $BASEB"; emit
fi
if ! bl_gh "$TMPD/rules.raw" api --method GET "repos/$REPO/rules/branches/$BASEB" --paginate; then
    if [ "$(cat "$TMPD/rules.raw.fail")" = deadline ]; then reason deadline "rules"
    else reason required-set-unreadable "branch rules of $BASEB"; fi
    emit
fi
if ! jq -sce '
    if length == 0 then [] else . end
    | if all(.[]; type == "array") then add // [] else error("not a list") end
    | [ .[] | select(.type == "required_status_checks") | (.parameters.required_status_checks // [])[]
        | {name: .context, source: "ruleset", app: (.integration_id // null)} ]
    | if any(.[]; (.name | type) != "string") then error("a rule without a context") else . end' \
    "$TMPD/rules.raw" > "$TMPD/req.rules" 2>/dev/null; then
    reason required-set-unreadable "branch rules of $BASEB"; emit
fi
jq -sc 'add' "$TMPD/req.classic" "$TMPD/req.rules" > "$TMPD/req.json"

if [ "$MODE" = sha ]; then
    # The commit's own rollup: its check runs and its statuses. A refused
    # read of either is no source rather than a failed board: refused check
    # runs are read as the Actions jobs, refused statuses add no context (so a
    # required status reads missing, never a pass).
    if ! bl_gh "$TMPD/cr.raw" api --method GET "repos/$REPO/commits/$SHA/check-runs?per_page=100" --paginate; then
        if [ "$(cat "$TMPD/cr.raw.fail")" = refused ]; then
            checks_refused "the commit's check runs"
            echo '{"total_count": 0, "check_runs": []}' > "$TMPD/cr.raw"
        else
            read_failed "$TMPD/cr.raw" "check runs"; emit
        fi
    fi
    if ! bl_gh "$TMPD/st.raw" api --method GET "repos/$REPO/commits/$SHA/status?per_page=100" --paginate; then
        if [ "$(cat "$TMPD/st.raw.fail")" = refused ]; then
            jq -nc '{code: "statuses-refused", detail: "the commit statuses were refused; a required status reads missing"}' >> "$TMPD/notes.jsonl"
            echo '{"total_count": 0, "statuses": []}' > "$TMPD/st.raw"
        else
            read_failed "$TMPD/st.raw" "statuses"; emit
        fi
    fi
    if ! jq -nc --slurpfile cr "$TMPD/cr.raw" --slurpfile st "$TMPD/st.raw" '
        ($cr[0].total_count) as $ct | [ $cr[].check_runs[]? ] as $c
        | ($st[0].total_count) as $stt | [ $st[].statuses[]? ] as $s
        | if ($ct | type) != "number" or ($c | length) != $ct then error("check runs short")
          elif ($stt | type) != "number" or ($s | length) != $stt then error("statuses short")
          else {head: null, merge_state: null, contexts: (
            [ $c[] | {kind: "check", name, done: (.status == "completed"),
                      result: ((if .status == "completed" then (.conclusion // "none") else (.status // "none") end) | ascii_upcase),
                      required: false, app: (.app.id // null)} ]
            + [ $s[] | {kind: "status", name: .context, done: ((.state // "pending") != "pending"),
                        result: ((.state // "pending") | ascii_upcase), required: false, app: null} ])} end
        | if any(.contexts[]; (.name | type) != "string") then error("a context without a name") else . end' \
        > "$TMPD/snap.json" 2>/dev/null; then
        rm -f "$TMPD/snap.json"
        reason read-failed "the commit's check runs or statuses"; emit
    fi
    if [ "$SOURCE" = actions ]; then
        jq -c '[.contexts[] | select(.kind == "status")]' "$TMPD/snap.json" > "$TMPD/st.ctx"
        rm -f "$TMPD/snap.json"
        actions_contexts "$TMPD/st.ctx" || { reason read-failed "the Actions jobs as checks"; emit; }
    fi
    emit
fi

# ---- 5. files, for the workflows-changed note ---------------------------------
if ! bl_gh "$TMPD/files.raw" api --method GET "repos/$REPO/pulls/$PR/files?per_page=100" --paginate; then
    read_failed "$TMPD/files.raw" "files"; emit
fi
if ! jq -sc 'if all(.[]; type == "array") then [ (add // [])[] | .filename, (.previous_filename // empty) | strings ] else error("not a list") end' \
    "$TMPD/files.raw" > "$TMPD/files.json" 2>/dev/null; then
    rm -f "$TMPD/files.json"; reason read-failed "files"; emit
fi

# ---- 6. the remote ref, last -----------------------------------------------
read_ref || emit
emit
