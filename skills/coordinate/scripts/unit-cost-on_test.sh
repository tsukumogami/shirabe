#!/usr/bin/env bash
# unit-cost-on_test.sh -- unit-cost.sh capture, which posts the cost entry
# on the item it is about
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2),
# over the example archive, the gh and koto stand-ins and the real record
# scripts. unit-cost_test.sh covers the entry itself.
#
# Covers: a unit whose holding names its pull request posted there with
# today's marker line, its URL kept in the session; a holding with no Pull
# request cell posted on the sealed verdict's first pull request; a unit that
# is an issue (`#n: ...`) posted on that issue of the host; a unit with
# neither kept in the session, posted nowhere, the output saying so, and a
# second capture of it finding the session's entry and adding none; nothing
# ever posted on an issue the unit isn't.
#
# Usage: bash skills/coordinate/scripts/unit-cost-on_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
# Its own HOME and koto home, inside the suite's scratch directory.
export HOME="$T/home" KOTO_SESSIONS_BASE="$T/koto-home"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
UC="$HERE/unit-cost.sh"
FX="$HERE/testdata/unit-cost"
KEY=2026-10-01-feat-x-0a1b2c3d
MERGE=5555555555555555555555555555555555555555
# The Holdings row is read through the session store's seam, which renders and
# parses the record: on a loaded host that can pass unit-cost_test.sh's
# five-second bound, and a timed-out read would hide the row this suite is about.
export KOTO_REQUESTS="$FX/requests" UNIT_COST_NOW=2026-10-01T12:00:00Z UNIT_COST_FETCH_SECS=60 UNIT_COST_BUDGET_SECS=300
S=coordinate-roadmap-x-20261001T080000Z

# seed <holding-json>: the record (ROADMAP-x on acme/widgets) in its run's
# session, whose find sealed `found`, holding feat-x as given; GitHub's side of
# the example's fixtures, issue 5, and an ordinary issue 7 no entry is ever
# posted on.
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: "the plugin tracker", body: "", state: "open", author: "alice", editor: null},
                    {repo: "acme/widgets", number: 5, title: "fix it", body: "", state: "open", author: "alice", editor: null}]'
    db '.prs += $g[0].prs | .pr_commits = $g[0].pr_commits | .runs = $g[0].runs' --slurpfile g "$FX/github.json"
    rm -rf "$KOTO_STORE/context/$S" "$KOTO_STORE/sessions/$S"
    found_session "$S" "$(roadmap_vars x)"
    record_json roadmap x | jq -c --argjson h "$1" '.holdings = [$h] | .written = "2026-10-01T08:00:00Z"' > "$T/rec.json"
    session_keys "$S" "$T/rec.json"
}
fresh() { rm -rf "$T/a"; mkdir -p "$T/a"; cp -R "$FX/archive/$KEY" "$T/a/"; A="$T/a/$KEY"; }
prs() { printf '%s\n' "$@" >"$T/prs"; }
capture() { bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"; }
cost_on() { jq -c --argjson n "$1" '[.comments // [] | .[] | select(.repo == "acme/widgets" and .number == $n) | .body
    | select(startswith("<!-- coordinator-record-entry v1 kind=cost -->"))]' "$GH_DB"; }
ncomments() { jq '.comments // [] | length' "$GH_DB"; }
costs() { # the session's cost entries
    koto context list --prefix record/entries/ "$S" | jq -r '.[]' | while read -r k; do koto context get "$S" "$k"; echo; done \
        | jq -s -c '[.[] | select(.kind == "cost")]'
}

echo "== the holding's pull request =="
seed "$(holding feat-x '{"unit": "Feature 4: Example feature", "pull_request": "[#22](https://github.com/acme/widgets/pull/22)"}')"
fresh; prs "acme/widgets#21 $MERGE"
capture; eq "a capture posts" 0 $?
eq "  ... on the holding's pull request" 1 "$(cost_on 22 | jq length)"
eq "  ... saying so" "unit-cost: posted the cost entry on acme/widgets#22" "$(tail -n 1 "$T/cap.err")"
eq "  ... with today's marker and stamp lines" "<!-- coordinator-record-entry v1 kind=cost -->|cost" \
    "$(cost_on 22 | jq -r '.[0] | split("\n") | "\(.[0])|\(.[1] | sub("^\\*\\*[0-9TZ:-]+\\*\\* \\(host clock\\) "; ""))"')"
eq "  ... and the entry the archive keeps" "$(jq -r .key "$A/unit-cost.json")" "$(cost_on 22 | jq -r '.[0] | split("\n") | .[6] | fromjson | .key')"
eq "  ... its URL kept in the session" "https://github.com/acme/widgets/pull/22#issuecomment-1001" \
    "$(koto context get "$S" "record/posted/$(printf '%06d' "$(costs | jq -r '.[0].n')")")"
eq "  ... and nothing on any other issue" "[]" "$(cost_on 7)"

echo "== the sealed verdict's pull request =="
seed "$(holding feat-x '{"unit": "Feature 4: Example feature", "pull_request": ""}')"
fresh; prs "acme/widgets#21 $MERGE"
capture; eq "a holding with no Pull request cell posts" 0 $?
eq "  ... on the verdict's first pull request" "1 unit-cost: posted the cost entry on acme/widgets#21" "$(cost_on 21 | jq length) $(tail -n 1 "$T/cap.err")"

echo "== the unit's issue =="
seed "$(holding feat-x '{"unit": "#5: fix it", "pull_request": ""}')"
fresh; : >"$T/prs"
capture; eq "a unit that is an issue posts" 0 $?
eq "  ... on that issue" "1 unit-cost: posted the cost entry on acme/widgets#5" "$(cost_on 5 | jq length) $(tail -n 1 "$T/cap.err")"

echo "== neither =="
seed "$(holding feat-x '{"unit": "Feature 4: Example feature", "pull_request": ""}')"
fresh; : >"$T/prs"
capture; eq "a unit with neither exits 0" 0 $?
eq "  ... posted nowhere" 0 "$(ncomments)"
eq "  ... and says so" "unit-cost: kept the cost entry in the session: the unit has no pull request or issue, so it is posted nowhere" "$(tail -n 1 "$T/cap.err")"
eq "  ... the session holds it" "$(jq -r .key "$A/unit-cost.json")" "$(costs | jq -r '.[0].text | split("\n") | .[3] | fromjson | .key')"
capture; eq "a second capture exits 0" 0 $?
eq "  ... finding the session's entry and adding none" "1 unit-cost: the record already holds this unit's cost entry" "$(costs | jq length) $(tail -n 1 "$T/cap.err")"

done_tests unit-cost-on_test
