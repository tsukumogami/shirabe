#!/usr/bin/env bash
# alignment-sources_test.sh -- alignment-sources.sh: a lane pull request's
# plan sources, read without writing anything
# (docs/designs/DESIGN-director-alignment-review.md, Decision 3).
#
# Covers, on a planted roadmap/v2 roadmap and strategy in the gh stand-in and a
# director record with two lane Holdings rows (Work rows naming a document and
# a directory, three Standing rows and a settled decision) and its report and
# progress events, whose result blocks carry unit= and open= lines: the nine
# keys; the unit from the lane's Holdings row, from --unit, and none when the
# lane names no roadmap item or no lane claims the pull request; each unit's
# clauses and Evidence by number with the commit they were read at; the
# strategy from upstream: (a path in the host, another repository's, none);
# the other lane's open work from its latest report's open= lines only (a
# pull request named only in the text, one named by an older report and one
# outside the lane set left out, the last never read), with the units and
# paths its rows name; a trigger for each condition (a unit= line, a milestone
# verdict pull request, a roadmap change, a strategy change, a file another
# lane's open pull request changes, a path another lane's rows name, the
# roadmap another lane has a unit on) and none for a pull request with none of
# them; the candidate owner decisions; each repository source unreadable, by
# an unreadable repository and by a missing file, naming it with `repository`
# or `file` and printing nothing; an unreadable record, exit 2 naming the
# record; refusals; the record's keys and log byte-identical around every
# run, with no GitHub write; and, last since they write entries, calls built
# from the output with alignment-call.sh and accepted by state-entry.sh's
# alignment_check: the milestone verdict pull request's, its Sources naming
# each roadmap clause at the commit and its Evidence line every Evidence
# number met or not met, and each other-lane trigger's, its Sources `lane
# <lane> <item>` for each item of the open work.
#
# Every script runs on the koto stand-in (testdata/koto) and one scratch
# store. GitHub is testdata/gh behind a wrapper in the suite's own directory
# that answers each pull request's changed files from the DB's pr_files.
#
# Usage: bash skills/coordinate/scripts/alignment-sources_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
export KOTO_BIN="$HERE/testdata/koto"
AS="$HERE/alignment-sources.sh"

# The changed-files read (GET repos/R/pulls/N/files) from .pr_files["R#n"],
# with the DB's fail rules and the caller's --jq; anything else goes on to
# testdata/gh.
mkdir -p "$T/bin" || exit 1
{
    printf '#!/usr/bin/env bash\n'
    printf 'STANDIN=%q\n' "$HERE/testdata/gh"
    cat <<'EOF'
p= jqf= prev=
for a in "$@"; do
    [ "$prev" = --jq ] && jqf=$a
    case "$a" in repos/*/pulls/*/files*) p=$a ;; esac
    prev=$a
done
[ "${1:-}" = api ] && [ -n "$p" ] || exec "$STANDIN" "$@"
printf '%s\n' "$*" >> "$GH_DB.calls"
rule=$(jq -r --arg a "$*" '[(.fail // [])[] | select(. as $f | $a | contains($f.match))][0] // empty | "\(.rc)\t\(.stderr // "gh: failed")"' "$GH_DB")
if [ -n "$rule" ]; then printf '%s\n' "${rule#*	}" >&2; exit "${rule%%	*}"; fi
r=${p#repos/}; n=${r#*/pulls/}; n=${n%%/*}; r=${r%%/pulls/*}
out=$(jq -c --arg k "$r#$n" '[(.pr_files // {}) | to_entries[] | select((.key | ascii_downcase) == ($k | ascii_downcase)) | .value][0] // empty' "$GH_DB")
[ -n "$out" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
out=$(printf '%s' "$out" | jq -c 'map({filename: .})')
if [ -n "$jqf" ]; then printf '%s\n' "$out" | jq -r "$jqf"; else printf '%s\n' "$out"; fi
EOF
} > "$T/bin/gh"
chmod +x "$T/bin/gh" || exit 1
PATH="$T/bin:$PATH"
export PATH

SD=coordinate-roadmap-direction-20260926T080000Z
RM=docs/roadmaps/ROADMAP-direction.md
ST=docs/strategies/STRATEGY-direction.md
link() { printf '[#%s](https://github.com/acme/widgets/pull/%s)' "$1" "$1"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }

roadmap() { # roadmap <upstream line or empty>: the roadmap's text
    printf -- '---\nschema: roadmap/v2\nstatus: Active\n%s---\n\n# ROADMAP: Direction\n\n## Features\n\n' "${1:+$1
}"
    cat <<'EOF'
### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer runs `widgets list` and sees the three names.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Dependencies:** None
**Status:** In progress

### MV2: the host serves

**Outcome:** The host answers
  on its public name.

**Evidence:**
- An operator curls the host's public name and gets a 200.

**Left open:** None

**Dependencies:** None
**Status:** In progress

### MV3: the cache

**Outcome:** Lists come from a cache.

**Dependencies:** None
**Status:** Not started

## Progress

- 2026-10-01: MV1 and MV2 started
EOF
}
set_roadmap() { db '.files["acme/widgets"]["main:" + $p] = $t' --arg p "$RM" --arg t "$(roadmap "$1")"; }

db_init
db '.files["acme/widgets"]["main:" + $s] = "# STRATEGY: Direction\n\n## Plugins first\n"
    | .repos["acme/gadgets"].default_branch = "main" | .branches["acme/gadgets"] = {main: $o}
    | .files["acme/gadgets"] = {"main:docs/strategies/STRATEGY-gadgets.md": "# STRATEGY: Gadgets\n"}' \
    --arg s "$ST" --arg o "$SHA_OTHER"
set_roadmap "upstream: $ST"
# pr <n> <head branch> <changed file>...: an open pull request on acme/widgets.
pr() {
    local n=$1 h=$2
    shift 2
    db '.prs += [{repo: "acme/widgets", number: $n, title: "x", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
            baseRefName: "main", headRefName: $h, headRefOid: $s, author: "alice", editor: null}]
        | .pr_files["acme/widgets#\($n)"] = $f' \
        --argjson n "$n" --arg h "$h" --arg s "$SHA_HEAD" --argjson f "$(jq -nc '$ARGS.positional' --args "$@")"
}
pr 12 feat/list src/list.go
pr 14 feat/cache src/cache.go
pr 15 coordinate/roadmap-verdict-mv1-20261001120000 "$RM"
pr 16 feat/strategy "$ST"
pr 17 feat/serve-fix src/serve.go
pr 18 feat/guide docs/guides/plugins.md
pr 19 feat/roadmap-wording "$RM"
pr 20 feat/skill skills/widgets/SKILL.md
pr 21 feat/serve src/serve.go
pr 22 feat/other src/serve.go
pr 23 feat/older src/serve.go
pr 25 feat/readme README.md

# The director record: lane A (mgr-a, MV1, its own pull request #12) and lane
# B (mgr-b, MV2), whose Work row names a document and a directory; Standing
# rows naming the unit, a changed path, and neither; a settled decision.
WORK='[{"item": "MV2", "kind": "holding", "who": "mgr-b", "next": "rewrite docs/guides/plugins.md and skills/widgets/", "wakes": "0", "updated": "2026-09-26T08:00Z"}]'
STANDING='[{"standing": "s1", "kind": "go-ahead", "on": "MV1", "until": "", "what": "ship the list as it is", "owner": "alice", "relayed_by": "", "set": "2026-09-26T08:00Z"},
  {"standing": "s2", "kind": "answer", "on": "", "until": "", "what": "keep `src/list.go` output stable", "owner": "alice", "relayed_by": "", "set": "2026-09-26T08:00Z"},
  {"standing": "s3", "kind": "pause", "on": "MV3", "until": "lifted", "what": "wait for the cache design", "owner": "alice", "relayed_by": "", "set": "2026-09-26T08:00Z"}]'
DECISION=$(jq -nc '{decision: "1", round: "0", question: "Should MV1 name skipped manifests?", options: "yes\nno", state: "settled",
    outcome: "yes; reason: the owner asked", decided_by: "a person", source: "self [20260926T080000Z raise 1]", updated: "2026-09-26T08:00Z"}')
record() { # record <lane A unit>
    local a
    a=$(jq -nc --arg u "$1" --arg p "$(link 12)" '{unit: $u, pull_request: $p}')
    record_json roadmap direction | jq -c --argjson a "$(holding mgr-a "$a")" \
        --argjson b "$(holding mgr-b '{"unit": "MV2", "pull_request": "", "branch": "", "phase": "executing"}')" \
        --argjson w "$WORK" --argjson s "$STANDING" --argjson d "$DECISION" \
        '.holdings = [$a, $b] | .work = $w | .standing = $s | .decisions = {next: 2, entries: [$d]}'
}
found_session "$SD" "$(roadmap_vars direction)"
seed_session "$SD" "$(record MV1)" || { echo "FAIL the record fixture didn't seed"; exit 1; }
log_to "$SD" reconcile wait
block() { printf 'Done.\n=== RESULT ===\n%s\n=== END RESULT ===\n' "$1"; }
ev() { # ev <event> <unit> <pull request> <report text>
    log_evidence "$SD" wait "$(jq -nc --arg e "$1" --arg u "$2" --arg p "$3" --arg r "$4" '{event: $e, unit: $u, pull_request: $p, report: $r}')"
}
ev progress mgr-b acme/widgets#23 "$(block 'open=acme/widgets#23')"
ev report mgr-a acme/widgets#14 "$(block "$(printf 'unit=worker-f14 done acme/widgets#14\nopen=acme/widgets#15\nopen=acme/widgets#16\nopen=acme/widgets#17\nopen=acme/widgets#18\nopen=acme/widgets#19\nopen=acme/widgets#20')")"
ev report mgr-b acme/widgets#21 "Also acme/widgets#22 is waiting on review.
$(block "$(printf 'open=acme/widgets#21\nopen=acme/elsewhere#5')")"
LAST_B=$(bash "$HERE/coord-log.sh" count --session "$SD")
LOG="$KOTO_STORE/sessions/$SD/koto-$SD.state.jsonl"

# run <args...>: the helper, with the record's keys and the log compared
# byte for byte around it. RC, $T/out and $T/err hold what it did.
run() {
    session_snapshot "$SD" > "$T/snap.before"
    cp "$LOG" "$T/log.before"
    bash "$AS" --session "$SD" "$@" > "$T/out" 2> "$T/err"
    RC=$?
    session_snapshot "$SD" > "$T/snap.after"
    if cmp -s "$T/snap.before" "$T/snap.after" && cmp -s "$T/log.before" "$LOG"; then ok "  ... the record and log are unchanged"
    else bad "  ... the record and log are unchanged" "they changed"; fi
}
out() { jq -c "$1" "$T/out"; }
last_err() { tail -1 "$T/err"; }

echo "== a pull request in a lane naming a unit =="
run --on acme/widgets#12
eq "it prints" 0 "$RC"
eq "the nine keys" '["candidates","changed_files","clauses","commit","evidence","other_lanes","strategy","triggers","unit"]' "$(out 'keys')"
eq "the unit is the lane's" '"MV1"' "$(out .unit)"
eq "its clauses by number" '[{"n":1,"field":"Outcome","text":"A maintainer lists the plugins they installed."},{"n":2,"field":"Left open","text":"the output layout."}]' "$(out .clauses)"
eq "its Evidence by number" '[1,2]' "$(out '[.evidence[].n]')"
eq "  ... with its text" '"The same reviewer removes one manifest and sees it named as skipped."' "$(out '.evidence[1].text')"
eq "the commit read at" "\"$SHA_MAIN\"" "$(out .commit)"
eq "the strategy from upstream:" "{\"path\":\"$ST\",\"repo\":\"acme/widgets\",\"commit\":\"$SHA_MAIN\"}" "$(out .strategy)"
eq "the changed files" '["src/list.go"]' "$(out .changed_files)"

echo "== no trigger =="
eq "a pull request with none of the conditions has no trigger" '[]' "$(out .triggers)"

echo "== the other lane's open work =="
eq "only the other lane, never the own" '["mgr-b"]' "$(out '[.other_lanes[].lane]')"
eq "its latest report" "$LAST_B" "$(out '.other_lanes[0].report')"
eq "only the open= pull request, with its files" '[{"pull_request":"acme/widgets#21","changed_files":["src/serve.go"]}]' "$(out '.other_lanes[0].open')"
eq "the units its rows name" '["MV2"]' "$(out '.other_lanes[0].units')"
eq "the document and directory its rows name" '["docs/guides/plugins.md","skills/widgets/"]' "$(out '.other_lanes[0].paths')"
grep -Eq 'pulls/2[23]/' "$GH_DB.calls" && bad "a pull request named only in text, or by an older report, isn't read" "$(grep 'pulls/2[23]/' "$GH_DB.calls")" \
    || ok "a pull request named only in text, or by an older report, isn't read"

echo "== an open= line outside the lane set =="
eq "it is listed out of scope" '["acme/elsewhere#5"]' "$(out '.other_lanes[0].out_of_scope')"
grep -q 'acme/elsewhere' "$GH_DB.calls" && bad "  ... and never read" "$(grep acme/elsewhere "$GH_DB.calls")" || ok "  ... and never read"

echo "== candidate owner decisions =="
eq "the Standing rows and decision naming the unit or a changed path" '["standing s1","standing s2","decision 1"]' "$(out '[.candidates[].source]')"
eq "  ... with what each names" '[["unit"],["src/list.go"],["unit"]]' "$(out '[.candidates[].matched]')"
eq "  ... a Standing row's fields" '{"kind":"go-ahead","on":"MV1","owner":"alice"}' "$(out '.candidates[0] | {kind, on, owner}')"

echo "== unit= finishes the unit =="
run --on acme/widgets#14
eq "it prints" 0 "$RC"
eq "the lane a unit= line names it under gives the unit" '"MV1"' "$(out .unit)"
eq "a unit-finished trigger" '[{"reason":"unit-finished","status":"done","topic":"worker-f14"}]' "$(out '[.triggers[] | del(.event)]')"

echo "== a milestone verdict pull request =="
run --on acme/widgets#15
eq "it prints" 0 "$RC"
eq "its reasons" '["milestone-verdict","roadmap-change","other-lane"]' "$(out '[.triggers[].reason]')"
eq "every Evidence clause of its milestone by number" '[1,2]' "$(out '[.evidence[].n]')"
eq "  ... at the commit" "\"$SHA_MAIN\"" "$(out .commit)"

echo "== a strategy change =="
run --on acme/widgets#16
eq "a strategy-change trigger" "[{\"reason\":\"strategy-change\",\"path\":\"$ST\"}]" "$(out .triggers)"

echo "== a file the other lane's open pull request changes =="
run --on acme/widgets#17
eq "an other-lane trigger naming the lane and the open pull request" \
    '[{"reason":"other-lane","lane":"mgr-b","open_work":["acme/widgets#21"],"files":["src/serve.go"]}]' "$(out .triggers)"

echo "== a path the other lane's rows name =="
run --on acme/widgets#18
eq "the document" '[{"reason":"other-lane","lane":"mgr-b","open_work":["docs/guides/plugins.md"],"files":["docs/guides/plugins.md"]}]' "$(out .triggers)"
run --on acme/widgets#20
eq "a file under the directory" '[{"reason":"other-lane","lane":"mgr-b","open_work":["skills/widgets/"],"files":["skills/widgets/SKILL.md"]}]' "$(out .triggers)"

echo "== a roadmap the other lane has a unit on =="
run --on acme/widgets#19
eq "a roadmap change, and the lane cited by the roadmap's path" \
    "[{\"reason\":\"roadmap-change\",\"path\":\"$RM\"},{\"reason\":\"other-lane\",\"lane\":\"mgr-b\",\"open_work\":[\"$RM\"],\"files\":[\"$RM\"]}]" "$(out .triggers)"

echo "== --unit names the unit =="
run --on acme/widgets#25
eq "a pull request no lane claims has unit none" '{"unit":"none","clauses":[],"evidence":[]}' "$(out '{unit, clauses, evidence}')"
eq "  ... and every lane is another lane" '["mgr-a","mgr-b"]' "$(out '[.other_lanes[].lane]')"
run --on acme/widgets#25 --unit MV2
eq "it prints" 0 "$RC"
eq "the unit is --unit" '"MV2"' "$(out .unit)"
eq "its clauses, a wrapped paragraph joined" '[{"n":1,"field":"Outcome","text":"The host answers on its public name."},{"n":2,"field":"Left open","text":"None"}]' "$(out .clauses)"
eq "its Evidence" '[{"n":1,"text":"An operator curls the host'"'"'s public name and gets a 200."}]' "$(out .evidence)"

echo "== a lane naming no unit =="
seed_session "$SD" "$(record '#40')"
run --on acme/widgets#12
eq "it prints" 0 "$RC"
eq "unit none, no clauses, no Evidence" '{"unit":"none","clauses":[],"evidence":[]}' "$(out '{unit, clauses, evidence}')"
eq "  ... the commit still read" "\"$SHA_MAIN\"" "$(out .commit)"
seed_session "$SD" "$(record MV1)"

echo "== the strategy =="
set_roadmap ""
run --on acme/widgets#12
eq "no upstream: is none" '"none"' "$(out .strategy)"
set_roadmap "upstream: acme/gadgets:docs/strategies/STRATEGY-gadgets.md"
run --on acme/widgets#12
eq "another repository's, at its own head" "{\"path\":\"docs/strategies/STRATEGY-gadgets.md\",\"repo\":\"acme/gadgets\",\"commit\":\"$SHA_OTHER\"}" "$(out .strategy)"
set_roadmap "upstream:
  - $ST"
run --on acme/widgets#12
eq "a one-entry sequence" "\"$ST\"" "$(out .strategy.path)"

echo "== a repository source can't be read =="
# unreadable <label> <want line>: exit 3, nothing on stdout, the line last on stderr.
unreadable() {
    eq "$1: exit 3" 3 "$RC"
    eq "  ... names it" "alignment-sources: cannot read $2" "$(last_err)"
    eq "  ... prints nothing" 0 "$(wc -c < "$T/out" | tr -d ' ')"
}
set_roadmap "upstream: $ST"
db '.fail = [{match: "repos/acme/widgets --jq .default_branch", rc: 1, stderr: "gh: HTTP 502"}]'
run --on acme/widgets#12
unreadable "the roadmap's repository" "acme/widgets $RM repository"
db '.fail = [{match: "git/ref/heads/main", rc: 1, stderr: "gh: HTTP 502"}]'
run --on acme/widgets#12
unreadable "the roadmap's default branch head" "acme/widgets $RM repository"
db '.fail = []'
db 'del(.files["acme/widgets"]["main:" + $p])' --arg p "$RM"
run --on acme/widgets#12
unreadable "the roadmap file missing" "acme/widgets $RM file"
set_roadmap "upstream: $ST"
run --on acme/widgets#12 --unit MV4
unreadable "a unit the roadmap lacks" "acme/widgets $RM file"
run --on acme/widgets#12 --unit MV3
unreadable "the milestone's Evidence missing" "acme/widgets $RM file"
set_roadmap "upstream: acme/vision:docs/strategies/STRATEGY-vision.md"
run --on acme/widgets#12
unreadable "the strategy's repository" "acme/vision docs/strategies/STRATEGY-vision.md repository"
set_roadmap "upstream: docs/strategies/STRATEGY-missing.md"
run --on acme/widgets#12
unreadable "the strategy file missing" "acme/widgets docs/strategies/STRATEGY-missing.md file"
set_roadmap "upstream: [$ST, docs/strategies/STRATEGY-other.md]"
run --on acme/widgets#12
unreadable "an upstream: naming two strategies" "acme/widgets $RM file"
set_roadmap "upstream: $ST"

echo "== the record can't be read =="
printf 'not json' > "$KOTO_STORE/context/$SD/record/holdings"
run --on acme/widgets#12
eq "exit 2" 2 "$RC"
grep -q "cannot read the record in session $SD" "$T/err" && ok "  ... naming the record" || bad "  ... naming the record" "$(cat "$T/err")"
eq "  ... prints nothing" 0 "$(wc -c < "$T/out" | tr -d ' ')"
seed_session "$SD" "$(record MV1)"

echo "== refusals =="
run --on acme/elsewhere#1
eq "a pull request outside the lane set is refused" 65 "$RC"
run --on 'acme/widgets 12'
eq "--on that isn't owner/repo#n is usage" 64 "$RC"
run --on acme/widgets#12 --unit none
eq "--unit none is usage" 64 "$RC"
eq "nothing it ran wrote to GitHub" "" "$(gh_writes)"

# The calls below write entries, so they run after every case above that
# compares the record's bytes. Each is a `fits` call, which places no hold.
entries() { koto context list --prefix record/entries/ "$SD" | jq length; }
last_entry() { koto context get "$SD" "record/entries/$(printf '%06d' "$(entries)")"; }
# call <pr> <Sources> <Evidence>: a fits call on <pr> at its head, written
# with alignment-call.sh from $T/call.txt. RC holds its exit.
call() {
    printf 'Alignment: %s at %s -- fits\nRead: full\nSources: %s\nReason: %s\nEvidence: %s\nFollow-ups: none\nAction: recommend\n' \
        "$1" "$SHA_HEAD" "$2" "it does what the sources it names ask" "$3" > "$T/call.txt"
    bash "$HERE/alignment-call.sh" --session "$SD" --on "$1" --text-file "$T/call.txt" > "$T/call.out" 2> "$T/call.err"
    RC=$?
}
# written <label>: the call exited 0 and the newest entry is an alignment
# entry holding its text.
written() {
    eq "$1: accepted" 0 "$RC"
    [ "$RC" = 0 ] || printf '     %s\n' "$(cat "$T/call.err")"
    eq "  ... written as an alignment entry holding the call" "alignment|$(cat "$T/call.txt")" "$(last_entry | jq -r '"\(.kind)|\(.text)"')"
}

echo "== a milestone verdict call cites its Evidence =="
run --on acme/widgets#15
# The roadmap's path is the run's own, which the director knows from its scope.
SRC=$(jq -r --arg rm "$RM" '[.unit as $u | .commit as $c | .clauses[] | "roadmap \($rm) at \($c) \($u) clause \(.n)"] | join("; ")' "$T/out")
EVD=$(jq -r '[.evidence | to_entries[] | "\(.value.n) \(if .key == 0 then "met" else "not met" end)"] | join("; ")' "$T/out")
eq "the Sources name each roadmap clause at the commit" "roadmap $RM at $SHA_MAIN MV1 clause 1; roadmap $RM at $SHA_MAIN MV1 clause 2" "$SRC"
eq "the Evidence line gives every Evidence number met or not met" "1 met; 2 not met" "$EVD"
call acme/widgets#15 "$SRC" "$EVD"
written "the verdict call"

echo "== an other-lane trigger cited as lane sources =="
# lane_call <n> <want Sources>: the call on #n whose Sources are `lane <lane>
# <item>` for each other-lane trigger's open work, joined with `; `.
lane_call() {
    run --on "acme/widgets#$1"
    SRC=$(jq -r '[.triggers[] | select(.reason == "other-lane") | .lane as $l | .open_work[] | "lane \($l) \(.)"] | join("; ")' "$T/out")
    eq "#$1's Sources from its other-lane trigger" "$2" "$SRC"
    call "acme/widgets#$1" "$SRC" none
    written "#$1's call"
}
lane_call 17 "lane mgr-b acme/widgets#21"
lane_call 18 "lane mgr-b docs/guides/plugins.md"
lane_call 19 "lane mgr-b $RM"
lane_call 20 "lane mgr-b skills/widgets/"
eq "nothing a call wrote reached GitHub" "" "$(gh_writes)"

done_tests alignment-sources_test.sh
