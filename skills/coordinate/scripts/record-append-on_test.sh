#!/usr/bin/env bash
# record-append-on_test.sh -- record-append.sh --on, a run's
# outward entry posted on the item it concerns
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2).
#
# Covers: a cost entry on a pull request and on an issue, posted with today's
# marker line, stamp line and text, its URL kept in record/posted/<n>, the
# record issue never read; `--on none` writing the session entry and posting
# nothing; the item's repository admitted as the host or a holding's (its Repo
# or its pull request's), without case, and refused otherwise with nothing
# written; a goal-fit entry posted on the pull request its first line names
# and refused, with nothing written, for another one, none, or `--on none`; a
# milestone-verdict or milestone-failure entry refused with --on an item and
# written with `--on none`, its `--repost --on` refused until a roadmap edit
# row names that pull request and the entry, then posted; the text scanned
# against the destination's visibility at post time (a private repository on
# a public destination refused, kept in the session; a private destination
# naming it posted; a destination whose visibility can't be read counted as
# public; a named repository whose visibility can't be read counted as
# private; a home-directory path refused); a private repository named bare or
# in a JSON repo field refused, naming it, as is an unreadable JSON repo field
# and an unreadable bare name under the host's owner, while prose (and/or), a
# schema name, an unreadable bare name of another owner, a public repository
# and a path post, more than 40 bare names are refused, and --repost scans the
# same way; an item whose repository doesn't opt in (a public pull request,
# for cost and goal-fit, and a private repository's issue) getting no
# comment, the entry kept in the session and its key printed, and a verdict's
# --repost on a public roadmap pull request refused, and the entry posting
# once the repository opts in; `@` posted escaped; a failed post
# (14) naming the retry, and the retry: posted once, then nothing; a comment
# by the coordinator's login (any case) at or after the stamp standing in for
# the post; one by another login, an older one or one another entry already
# claimed not standing in; a failed `gh api user` (2) posting nothing; an
# entry posted elsewhere refused; and usage: a malformed --on, --on with
# --list, with a kind that stays in the session, and `--repost --on none`.
# The record is the session's; no record issue exists to read.
#
# Usage: bash skills/coordinate/scripts/record-append-on_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RA="$HERE/record-append.sh"
# The opt-in reader's stand-in: it answers what $T/opt-in holds, else omit.
# The cases below post while the item's repository opts in; the gate's own
# cases opt out.
cat > "$T/reader" <<EOF
#!/usr/bin/env bash
cat "$T/opt-in" 2>/dev/null || echo omit
EOF
export RECORD_APPEND_PR_CONTENT_READER="$T/reader"
opt_in() { echo include > "$T/opt-in"; }
opt_out() { rm -f "$T/opt-in"; }
opt_in

RM=(--scope roadmap --name plugin-system --repo "$REPO")
SE=coordinate-roadmap-plugin-system-20260926T150000Z
SEN=(env RS_SESSION="$SE")
pr() { # pr <repo> <n>: an open pull request
    db '.prs += [{repo: $r, number: $n, title: "x", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/\($n)", headRefOid: "2222222222222222222222222222222222222222", author: "alice", editor: null}]' \
        --arg r "$1" --argjson n "$2"
}
issue() { db '.issues += [{repo: $r, number: $n, title: "x", body: "", state: "open", author: "alice", editor: null}]' --arg r "$1" --argjson n "$2"; }
seed() {
    db_init
    db '.repos["acme/tools"] = {private: false, default_branch: "main"} | .repos["other/place"] = {private: false, default_branch: "main"}'
    pr acme/widgets 12; pr acme/widgets 8; issue acme/widgets 5; issue acme/gadgets 4; pr acme/tools 9; issue acme/secret 3; issue other/place 1
    rm -rf "$KOTO_STORE/context/$SE"
    seed_session "$SE" "$(record_json roadmap plugin-system)"
    # Two holdings: one in acme/gadgets, one whose pull request is in acme/tools.
    jq -nc --argjson a "$(holding feat-a '{"repo": "acme/gadgets"}')" \
        --argjson b "$(holding feat-b '{"pull_request": "[#9](https://github.com/acme/tools/pull/9)"}')" '[$a, $b]' \
        | koto context add "$SE" record/holdings
}
entry() { printf '%s\n' "$1" > "$T/entry.txt"; }
ra() { "${SEN[@]}" bash "$RA" "${RM[@]}" "$@"; }
nentries() { koto context list --prefix record/entries/ "$SE" | jq length; }
ncomments() { jq '.comments // [] | length' "$GH_DB"; }
posted() { koto context get "$SE" "record/posted/$1" 2>/dev/null; }
body_of() { jq -r --argjson i "$1" '.comments[] | select(.id == $i) | .body' "$GH_DB"; }
STAMP_LINE='^\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\*\* \(host clock\) cost$'

echo "== a cost entry on a pull request, on an issue, and nowhere =="
seed
reset_calls
entry "Cost of feat-a: 3 sessions."
O=$(ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a cost entry is posted on the pull request" "0 https://github.com/acme/widgets/pull/12#issuecomment-1001" "$rc $O"
B=$(body_of 1001)
eq "  ... with today's marker line" "<!-- coordinator-record-entry v1 kind=cost -->" "$(printf '%s\n' "$B" | sed -n 1p)"
grep -Eq "$STAMP_LINE" <<<"$(printf '%s\n' "$B" | sed -n 2p)" && ok "  ... today's stamp line" || bad "  ... today's stamp line" "$B"
eq "  ... and the text" "Cost of feat-a: 3 sessions." "$(printf '%s\n' "$B" | sed -n '4,$p')"
eq "  ... on pull request 12" "12" "$(jq -r '.comments[0].number' "$GH_DB")"
eq "  ... its URL kept" "https://github.com/acme/widgets/pull/12#issuecomment-1001" "$(posted 000001)"
eq "  ... and the session entry written" "cost" "$(koto context get "$SE" record/entries/000001 | jq -r .kind)"
grep -qE 'issue view|pr view' "$GH_DB.calls" && bad "  ... no record issue or pull request read" "$(calls)" || ok "  ... no record issue or pull request read"
entry "Cost of an issue unit."
O=$(ra --kind cost --on acme/widgets#5 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a cost entry is posted on an issue" "0 https://github.com/acme/widgets/issues/5#issuecomment-1002" "$rc $O"
entry "Cost of a unit with neither."
O=$(ra --kind cost --on none --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "--on none writes the session entry" "0 record/entries/000003" "$rc $O"
eq "  ... and posts nothing" "2 none" "$(ncomments) $(posted 000003 || echo none)"

echo "== the item's repository =="
seed
entry "Cost on a holding's repository."
O=$(ra --kind cost --on acme/gadgets#4 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a holding's Repo is admitted" "0 https://github.com/acme/gadgets/issues/4#issuecomment-1001" "$rc $O"
O=$(ra --kind cost --on acme/tools#9 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a holding's pull request's repository is admitted" "0 https://github.com/acme/tools/pull/9#issuecomment-1002" "$rc $O"
O=$(ra --kind cost --on ACME/Widgets#12 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "the host named in another case is admitted" "0 https://github.com/acme/widgets/pull/12#issuecomment-1003" "$rc $O"
N0=$(nentries)
ra --kind cost --on other/place#1 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a repository that is neither the host nor a holding's is refused" 65 $?
eq "  ... nothing written or posted" "$N0 3" "$(nentries) $(ncomments)"

echo "== goal-fit =="
seed
printf 'Goal fit: acme/widgets#12 -- MV1\nFit: fits\nClauses: 1\nRationale: it ships the list.\n' > "$T/gf.txt"
O=$(ra --kind goal-fit --on acme/widgets#12 --text-file "$T/gf.txt" 2>"$T/err"); rc=$?
eq "a goal-fit entry is posted on the pull request it names" "0 https://github.com/acme/widgets/pull/12#issuecomment-1001" "$rc $O"
ra --kind goal-fit --on acme/widgets#8 --text-file "$T/gf.txt" >/dev/null 2>"$T/err"; eq "one whose --on differs from the named pull request is refused" 65 $?
grep -q 'names acme/widgets#12, not acme/widgets#8' "$T/err" && ok "  ... naming both" || bad "  ... naming both" "$(cat "$T/err")"
printf 'Goal fit: none -- MV1\nFit: fits\n' > "$T/gf0.txt"
ra --kind goal-fit --on acme/widgets#12 --text-file "$T/gf0.txt" >/dev/null 2>"$T/err"; eq "one that names no pull request is refused" 65 $?
ra --kind goal-fit --on none --text-file "$T/gf.txt" >/dev/null 2>"$T/err"; eq "a goal-fit entry with --on none is refused" 65 $?
eq "  ... each posted nowhere and written nowhere" "1 1" "$(nentries) $(ncomments)"

echo "== milestone entries reach their roadmap pull request only through roadmap-status.sh =="
seed
entry "Verdict: MV1 -- verified"
ra --kind milestone-verdict --on acme/widgets#8 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-verdict entry with --on an item is refused" 65 $?
ra --kind milestone-failure --on acme/widgets#8 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-failure entry with --on an item is refused" 65 $?
eq "  ... posted nowhere, written nowhere" "0 0" "$(nentries) $(ncomments)"
O=$(ra --kind milestone-verdict --on none --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a milestone-verdict entry is written with --on none" "0 record/entries/000001" "$rc $O"
ra --repost 1 --on acme/widgets#8 >/dev/null 2>"$T/err"; eq "its --repost --on is refused with no roadmap edit row" 65 $?
grep -q 'roadmap-status.sh' "$T/err" && ok "  ... naming roadmap-status.sh" || bad "  ... naming roadmap-status.sh" "$(cat "$T/err")"
jq -nc '[{action: "milestone-done", target: "MV1 [#8](https://github.com/acme/widgets/pull/8)", verified_head: "", attempted: "2026-10-12T09:00Z",
    how_to_confirm: "the roadmap on main reads MV1 Done (entry 2)"}]' | koto context add "$SE" record/side-effects
ra --repost 1 --on acme/widgets#8 >/dev/null 2>"$T/err"; eq "  ... and with a row naming another entry" 65 $?
jq -nc '[{action: "milestone-done", target: "MV1 [#8](https://github.com/acme/widgets/pull/8)", verified_head: "", attempted: "2026-10-12T09:00Z",
    how_to_confirm: "the roadmap on main reads MV1 Done (entry 1)"}]' | koto context add "$SE" record/side-effects
ra --repost 1 --on acme/widgets#12 >/dev/null 2>"$T/err"; eq "  ... and on a pull request the row doesn't name" 65 $?
eq "  ... posting nothing" 0 "$(ncomments)"
O=$(ra --repost 1 --on acme/widgets#8 2>"$T/err"); rc=$?
eq "  ... posted once the row names that pull request and the entry" "0 https://github.com/acme/widgets/pull/8#issuecomment-1001" "$rc $O"
entry "Failure: MV1"
ra --kind milestone-failure --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"
ra --repost 2 --on acme/widgets#8 >/dev/null 2>"$T/err"; eq "a failure entry isn't posted on a verdict's row" 65 $?

echo "== the text, scanned against the destination when it is posted =="
seed
entry "Blocked on acme/secret#3 landing."
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "a private repository is refused for a public destination" 65 "$rc"
grep -q 'stays in the session' "$T/err" && ok "  ... saying the entry stays in the session" || bad "  ... saying the entry stays in the session" "$(cat "$T/err")"
eq "  ... which it does, posted nowhere" "cost none 0" "$(koto context get "$SE" record/entries/000001 | jq -r .kind) $(posted 000001 || echo none) $(ncomments)"
jq -nc --argjson a "$(holding feat-s '{"repo": "acme/secret"}')" '[$a]' | koto context add "$SE" record/holdings
O=$(ra --kind cost --on acme/secret#3 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "  ... and posted on a private destination" "0 https://github.com/acme/secret/issues/3#issuecomment-1001" "$rc $O"
db '.fail = [{match: "repos/acme/widgets --jq .private", rc: 1, stderr: "gh: HTTP 502"}]'
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a destination whose visibility can't be read counts as public" 65 $?
db '.fail = [{match: "repos/acme/gadgets --jq .private", rc: 1, stderr: "gh: HTTP 502"}]'
entry "Waiting on acme/gadgets#346."
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a named repository whose visibility can't be read counts as private" 65 $?
db '.fail = []'
O=$(ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "  ... and once it reads public, the entry posts" "0 https://github.com/acme/widgets/pull/12#issuecomment-1002" "$rc $O"
entry "The log is in /ho""me/someone/run.log."
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a home-directory path is refused for a public destination" 65 $?
printf 'Asked @alice & @bob.\n' > "$T/at.txt"
ra --kind cost --on acme/widgets#12 --text-file "$T/at.txt" >/dev/null 2>"$T/err"
eq "an @ is posted escaped" "Asked &#64;alice &amp; &#64;bob." "$(jq -r '.comments[-1].body' "$GH_DB" | sed -n '4,$p')"

echo "== a repository named bare, or in a JSON repo field =="
seed
refused_naming() { # refused_naming <label> <repo> [record-append args...]
    local label=$1 r=$2
    shift 2
    ra "$@" >/dev/null 2>"$T/err"; eq "$label" 65 $?
    grep -q "names $r, a repository that isn't public" "$T/err" && ok "  ... naming $r" || bad "  ... naming $r" "$(cat "$T/err")"
}
entry "Blocked on acme/secret landing."
refused_naming "a private repository named bare is refused for a public destination" acme/secret \
    --kind cost --on acme/widgets#12 --text-file "$T/entry.txt"
entry "Blocked on acme/secret."
refused_naming "  ... and ending a sentence" acme/secret --kind cost --on acme/widgets#12 --text-file "$T/entry.txt"
printf 'Cost of feat-a (k): 3 sessions.\n\n```json\n{"schema":"unit-cost/1","record":{"scope":"roadmap","name":"x","repo":"acme/secret","ref":"12"}}\n```\n' > "$T/json.txt"
refused_naming "a private repository in a JSON repo field is refused" acme/secret --kind cost --on acme/widgets#12 --text-file "$T/json.txt"
printf '{"record": {"repo": "elsewhere/gone", "ref": "3"}}\n' > "$T/json.txt"
refused_naming "  ... and one whose visibility can't be read, whatever its owner" elsewhere/gone \
    --kind cost --on acme/widgets#12 --text-file "$T/json.txt"
entry "Moved to acme/gone."
refused_naming "a bare name under the host's owner whose visibility can't be read is refused" acme/gone \
    --kind cost --on acme/widgets#12 --text-file "$T/entry.txt"
eq "  ... each kept in the session, posted nowhere" "5 0" "$(nentries) $(ncomments)"
entry "and/or, CI/CD, schema unit-cost/1, elsewhere/gone and acme/gadgets, in skills/coordinate/scripts/x.sh"
O=$(ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "prose, a schema name, an unreadable bare name of another owner, a public repository and a path post" \
    "0 https://github.com/acme/widgets/pull/12#issuecomment-1001" "$rc $O"
for i in {1..41}; do printf 'other/r%s ' "$i"; done > "$T/entry.txt"
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "more than 40 bare names are refused" 65 $?
grep -q 'more than 40 owner/repo names' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
entry "Blocked on acme/secret landing."
O=$(ra --kind cost --on none --text-file "$T/entry.txt" 2>"$T/err")
refused_naming "--repost --on scans the same way" acme/secret --repost "${O##*/}" --on acme/widgets#12
eq "  ... posting nothing" 1 "$(ncomments)"

echo "== an item whose repository doesn't opt in =="
seed
opt_out
kept() { # kept <label> <record-append args...>: the entry stays in the session, posted nowhere
    local label=$1 n0
    shift
    n0=$(ncomments)
    O=$(ra "$@" 2>"$T/err"); rc=$?
    case "$rc $O" in "0 record/entries/"[0-9]*) ok "$label" ;; *) bad "$label" "$rc $O $(cat "$T/err")" ;; esac
    eq "  ... posting nothing" "$n0" "$(ncomments)"
    grep -q "doesn't opt in to workflow content" "$T/err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/err")"
}
entry "Cost of feat-a: 3 sessions."
kept "a cost entry on a public pull request is kept in the session" --kind cost --on acme/widgets#12 --text-file "$T/entry.txt"
printf 'Goal fit: acme/widgets#12 -- MV1\nFit: fits\nClauses: 1\nRationale: it ships the list.\n' > "$T/gf.txt"
kept "a goal-fit entry on its public pull request is kept in the session" --kind goal-fit --on acme/widgets#12 --text-file "$T/gf.txt"
eq "  ... its entry written" "goal-fit" "$(koto context get "$SE" record/entries/000002 | jq -r .kind)"
jq -nc --argjson a "$(holding feat-s '{"repo": "acme/secret"}')" '[$a]' | koto context add "$SE" record/holdings
kept "a cost entry on a private repository's issue is kept too" --kind cost --on acme/secret#3 --text-file "$T/entry.txt"
entry "Verdict: MV1 -- verified"
O=$(ra --kind milestone-verdict --on none --text-file "$T/entry.txt" 2>"$T/err")
EN=$((10#${O##*/}))
jq -nc --arg h "the roadmap on main reads MV1 Done (entry $EN)" '[{action: "milestone-done", target: "MV1 [#8](https://github.com/acme/widgets/pull/8)",
    verified_head: "", attempted: "2026-10-12T09:00Z", how_to_confirm: $h}]' | koto context add "$SE" record/side-effects
ra --repost "$EN" --on acme/widgets#8 >/dev/null 2>"$T/err"; eq "a verdict's --repost on a public roadmap pull request is refused" 65 $?
grep -q "stays in the session; it isn't posted on acme/widgets#8" "$T/err" && ok "  ... the entry staying in the session" || bad "  ... the entry staying in the session" "$(cat "$T/err")"
eq "  ... posting nothing" 0 "$(ncomments)"
opt_in
O=$(ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "once the repository opts in, the entry posts" "0 https://github.com/acme/widgets/pull/12#issuecomment-1001" "$rc $O"

echo "== the retry =="
seed
db '.fail = [{match: "POST repos/acme/widgets/issues/12/comments", rc: 1, stderr: "HTTP 502"}]'
entry "Cost of feat-r."
ra --kind cost --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a failed post exits 14" 14 $?
grep -q -- '--repost 1 --on acme/widgets#12' "$T/err" && ok "  ... naming the retry" || bad "  ... naming the retry" "$(cat "$T/err")"
db '.fail = []'
O=$(ra --repost 1 --on acme/widgets#12 2>"$T/err"); rc=$?
eq "--repost --on posts it" "0 https://github.com/acme/widgets/pull/12#issuecomment-1001" "$rc $O"
O=$(ra --repost 1 --on acme/widgets#12 2>"$T/err"); rc=$?
eq "  ... and again posts nothing" "0 https://github.com/acme/widgets/pull/12#issuecomment-1001 1" "$rc $O $(ncomments)"
ra --repost 1 --on acme/widgets#5 >/dev/null 2>"$T/err"; eq "an entry posted on another item is refused" 65 $?
# A post that landed before a crash: the same kind and text on the item.
mke() { jq -nc --argjson n "$1" --arg s "$2" '{n: $n, stamp: $s, kind: "cost", text: "the same cost"}' | koto context add "$SE" "record/entries/$(printf '%06d' "$1")"; }
mkc() { db '.comments += [{repo: "acme/widgets", number: 12, id: $i, user: $u, created_at: $c, updated_at: $c,
    body: "<!-- coordinator-record-entry v1 kind=cost -->\n**2026-10-12T16:00:00Z** (host clock) cost\n\nthe same cost"}]' \
    --argjson i "$1" --arg u "$2" --arg c "$3"; }
mke 2 2026-10-12T16:00:00Z
mkc 1500 COORD 2026-10-12T16:00:02Z
N0=$(ncomments)
O=$(ra --repost 2 --on acme/widgets#12 2>"$T/err"); rc=$?
eq "a comment by the coordinator's login, in any case, at or after the stamp stands in" \
    "0 https://github.com/acme/widgets/pull/12#issuecomment-1500 $N0" "$rc $O $(ncomments)"
eq "  ... its URL kept" "https://github.com/acme/widgets/pull/12#issuecomment-1500" "$(posted 000002)"
mke 3 2026-10-12T16:00:00Z
O=$(ra --repost 3 --on acme/widgets#12 2>"$T/err"); rc=$?
eq "one another entry already claimed doesn't" "0 https://github.com/acme/widgets/pull/12#issuecomment-1501" "$rc $O"
mke 4 2026-10-12T17:00:00Z
mkc 1600 bob 2026-10-12T17:00:05Z
mkc 1601 coord 2026-10-12T16:59:00Z
db '.now = "2026-10-12T17:00:10Z"'
O=$(ra --repost 4 --on acme/widgets#12 2>"$T/err"); rc=$?
eq "one by another login, or older than the stamp, doesn't" "0 https://github.com/acme/widgets/pull/12#issuecomment-1602" "$rc $O"
mke 5 2026-10-12T18:00:00Z
db '.fail = [{match: "api user", rc: 1, stderr: "gh: Resource not accessible by integration (HTTP 403)"}]'
N0=$(ncomments)
ra --repost 5 --on acme/widgets#12 >/dev/null 2>"$T/err"; rc=$?
eq "a login gh api user can't answer exits 2" 2 "$rc"
eq "  ... posting nothing" "$N0 none" "$(ncomments) $(posted 000005 || echo none)"
db '.fail = []'

echo "== usage =="
seed
entry "x"
ra --kind cost --on acme/widgets --text-file "$T/entry.txt" >/dev/null 2>&1; eq "an --on without #n is a usage error" 64 $?
ra --kind cost --on 'acme/widgets#0' --text-file "$T/entry.txt" >/dev/null 2>&1; eq "an --on numbered 0 is a usage error" 64 $?
ra --kind cost --on 'acme/wid gets#3' --text-file "$T/entry.txt" >/dev/null 2>&1; eq "an --on with a space is a usage error" 64 $?
ra --list --on acme/widgets#12 >/dev/null 2>&1; eq "--on with --list is a usage error" 64 $?
ra --kind entry --on acme/widgets#12 --text-file "$T/entry.txt" >/dev/null 2>&1; eq "--on with a kind that stays in the session is a usage error" 64 $?
ra --repost 1 --on none >/dev/null 2>&1; eq "--repost --on none is a usage error" 64 $?
eq "  ... nothing posted" 0 "$(ncomments)"

done_tests record-append-on_test
