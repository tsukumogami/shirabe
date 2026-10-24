#!/usr/bin/env bash
# legacy-records_engine_test.sh -- coordinator records left on GitHub from
# before the record's removal are never closed, edited or deleted, the shipped
# coordinate.md driven through real koto against the testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The legacy
# importer" and "What stays on GitHub"). The setup and helpers are the
# coordinate engine suites' (testdata/coordinate-engine-lib.sh).
#
# The stand-in is set up with three existing records, each under the title or
# branch the legacy importer looks for (read from the importer itself):
#   moved     an open roadmap record issue in the moved shape, its state long
#             since on a session, with a person's comment on it;
#   unmoved   an open roadmap record issue still holding its state tables (one
#             holding and its stored set);
#   rotation  a discipline's open draft rotation pull request from its record
#             branch, which exists, into the default branch.
#
# Proves, one line per case:
#   1. a fresh start of the moved record's scope finds no record to import,
#      stops at record_open, opens its record in its session and runs on to
#      wait;
#   2. a fresh start of the unmoved record's scope imports it: the run's
#      session holds its holding, the run reaches pick on it, and the one
#      GitHub write is the importer's note on the record;
#   3. a fresh start of the rotation's discipline imports it the same way, its
#      window from the title, and reaches reconcile;
#   4. across the three runs the stand-in recorded no close, edit, reopen or
#      delete of any of those issues, their comments, the pull request or its
#      branch: no `gh issue` or `gh pr` write, no PATCH, PUT or DELETE through
#      the API, both issues still open with their bodies as set up, the person's
#      comment as it was, the pull request open, draft and as set up, and its
#      branch where it was; the only writes are one note on each imported
#      record and none on the moved one.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/legacy-records_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# The title and branch the importer looks for, read from the importer, their
# one definition.
IMPORTER="$REPO_ROOT/skills/coordinate/legacy-import/import.sh"
TITLE_PREFIX=$(sed -n 's/^TITLE="\(.*\)\$NAME"$/\1/p' "$IMPORTER")
BRANCH_PREFIX=$(sed -n 's/^BRANCH="\(.*\)\$NAME"$/\1/p' "$IMPORTER")
[ -n "$TITLE_PREFIX" ] && [ -n "$BRANCH_PREFIX" ] && ok "the importer's record title and branch are read" \
    || { bad "the importer's record title and branch are read" "[$TITLE_PREFIX] [$BRANCH_PREFIX]"; done_tests legacy-records-engine; exit 1; }
day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
ROT_TITLE="docs(coordinate): legacyops rotation $(day 0) to $(day 6)"
ROT_SHA=5555555555555555555555555555555555555555

# ---- the records already on GitHub ---------------------------------------------------
seed_roadmap moved
seed_roadmap unmoved
MOVED_BODY=$(render "$(record_json roadmap moved | jq -c '.run = [{key: "store", value: "session", set_by: "the invocation (--store session)", set: "2026-10-01T10:00Z"}]')" issue)
UNMOVED_BODY=$(render "$(stored "$(record_json roadmap unmoved | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')")" issue)
ROT_BODY=$(render "$(record_json discipline legacyops)" pr)
db '.issues += [{repo: "acme/widgets", number: 50, title: ($p + "moved"), body: $m, state: "open", author: "coord", editor: null},
                {repo: "acme/widgets", number: 60, title: ($p + "unmoved"), body: $u, state: "open", author: "coord", editor: null}]
    | .comments = [{repo: "acme/widgets", number: 50, id: 9001, body: "The state moved to a session on the old release.", user: "alice",
                    created_at: "2026-10-01T10:05:00Z", updated_at: "2026-10-01T10:05:00Z"}]
    | .prs += [{repo: "acme/widgets", number: 70, title: $rt, body: $r, state: "OPEN", isDraft: true, isCrossRepository: false,
                baseRefName: "main", headRefName: ($bp + "legacyops"), headRefOid: $rs, author: "coord", editor: null}]
    | .branches["acme/widgets"][$bp + "legacyops"] = $rs' \
    --arg p "$TITLE_PREFIX" --arg bp "$BRANCH_PREFIX" --arg m "$MOVED_BODY" --arg u "$UNMOVED_BODY" --arg r "$ROT_BODY" --arg rt "$ROT_TITLE" --arg rs "$ROT_SHA"
# What each record looks like now, to compare with after the runs.
records() {
    jq -cS '{issues: [.issues[] | select(.number == 50 or .number == 60) | {number, title, body, state, author, editor}],
             comments: [(.comments // [])[] | select(.id == 9001)],
             prs: [.prs[] | select(.number == 70) | {number, title, body, state, isDraft, headRefName, headRefOid, editor}],
             branch: .branches["acme/widgets"]}' "$GH_DB"
}
BEFORE=$(records)
reset_calls
posts() { grep -c "^api --method POST repos/acme/widgets/issues/$1/comments" "$GH_DB.calls"; } # posts <n>: comments posted on #n

# ---- 1. the moved record's scope -----------------------------------------------------
echo "== 1. the scope whose record moved =="
if open_run moved; then
    eq "1: no record to import: the run stops at record_open" record_open "$(at)"
    eq "1:   ... with nothing posted on the moved record" 0 "$(posts 50)"
    render "$(record_json roadmap moved)" issue > "$T/open.md"
    write_as_agent record-open.sh --body-file "$T/open.md"
    eq "1: record-open.sh (agent-run) opens the record in the session" 0 $?
    eq "1: the run reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
    write_as_agent record-state.sh --run arguments "docs/roadmaps/ROADMAP-moved.md" --by "the human" \
        && write_as_agent record-state.sh --run cap 2 --by "the human" \
        && write_as_agent record-state.sh --run coordinator coord-test --by coord-test \
        && write_as_agent record-state.sh --run reports-to "the human" --by "the human"
    eq "1: the stored set is written" 0 $?
    eq "1: the run reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
    eq "1: and holds into wait" wait "$(at --with-data '{"choice":"hold"}')"
else
    bad "1: the run opens" "$(cat "$T/open.err")"
fi

# ---- 2. the unmoved record's scope ---------------------------------------------------
echo "== 2. the scope whose record is still on GitHub =="
if open_run unmoved; then
    eq "2: the importer posted one note on the record" 1 "$(posts 60)"
    eq "2: the run's session holds the record's holding" feat-1 "$(live_body | jq -r '[.holdings[].worker] | join(" ")')"
    eq "2: the run reaches reconcile" reconcile "$(at)"
    eq "2: and pick, on the imported stored set" pick "$(at --with-data '{"reconciled":"reported"}')"
    eq "2: and holds into wait" wait "$(at --with-data '{"choice":"hold"}')"
else
    bad "2: the run opens" "$(cat "$T/open.err")"
fi

# ---- 3. the rotation's discipline ----------------------------------------------------
echo "== 3. the discipline whose rotation is still on GitHub =="
printf '["--discipline", "legacyops", "--host", "acme/widgets"]' > "$T/args.json"
OPEN_OUT=$(cd "$T/work" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p') WD=$T/work
if [ -n "$S" ]; then
    eq "3: the importer posted one note on the pull request" 1 "$(posts 70)"
    eq "3: the run's session holds the rotation's window from the title" "$(day 0) $(day 6)" \
        "$( (cd "$WD" && koto context get "$S" record/rotation 2>/dev/null) | jq -r '"\(.start) \(.end)"')"
    eq "3: the run reaches reconcile" reconcile "$(at)"
else
    bad "3: the run opens" "$(cat "$T/open.err")"
fi

# ---- 4. nothing set up as a record was closed, edited or deleted ---------------------
echo "== 4. the records as they were set up =="
eq "4: no gh issue or gh pr write" "" "$(grep -E '^(issue|pr) (create|edit|close|reopen|delete|ready|merge|lock|comment)' "$GH_DB.calls")"
eq "4: no PATCH, PUT or DELETE through the API" "" "$(grep -E '^api (--method|-X) (PATCH|PUT|DELETE)' "$GH_DB.calls")"
eq "4: no ref written" "" "$(grep -E 'git/refs' "$GH_DB.calls" | grep -v -- '--method GET')"
eq "4: both issues, the person's comment, the pull request and its branch are as they were" "$BEFORE" "$(records)"
eq "4: the only writes are a note on each imported record" "60 70" \
    "$(grep -E '^api --method (POST|PATCH|PUT|DELETE)' "$GH_DB.calls" | sed -n 's|^api --method POST repos/acme/widgets/issues/\([0-9]*\)/comments.*|\1|p' | sort | tr '\n' ' ' | sed 's/ $//')"
eq "4:   ... and every write is one of those" 2 "$(grep -cE '^api --method (POST|PATCH|PUT|DELETE)' "$GH_DB.calls")"

done_tests legacy-records-engine
