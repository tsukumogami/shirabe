#!/usr/bin/env bash
# alignment-read_test.sh -- alignment-read.sh: a director's calls, the merges
# owed one and their review, recommendations, holds, open lane pull requests,
# refusals and lineage gaps, read without writing anything
# (docs/designs/DESIGN-director-alignment-review.md, Decision 4).
#
# Covers, on one planted director record and its lineage: the seven keys and
# nothing else; every alignment entry listed oldest first with its fields and
# its lists split on `; `, two calls on one pull request and head both listed
# with only the later standing, and a call on an older head standing for that
# head only; open lane pull requests at their live head with the standing
# call or `none`, one moved to a new head with no call yet listed `none`
# while held; the lane set from calls, Holdings links, holds and the events'
# pull request, message links and unit=, open= and worker= lines, a merged
# pull request found only through a predecessor's progress message link
# included and an event's pull request in another repository never read,
# listed by repository and number; unit= lines finishing a unit while a report saying so in its text,
# a status outside the three and a pull request not in owner/repo#n form
# finish nothing; manager-authored pull requests by an event's pull request
# under a holding's topic and by a Holdings row's Verified head with its Pull
# request cell cleared, each `unreviewed` with no call; a worker= pull
# request `manager-reviewed` under both of those signals; finished units by a
# unit= line (`after merge`), a milestone verdict branch, a milestone-done
# Side effects row, a roadmap change (`reviewed`) and a strategy change;
# recommendations; every align- hold state (lifted, merged while held, closed
# while held, releasable, standing with and without needs_re_read) with its
# diverges call's reason, and a standing hold's latest report naming it as a
# whole word or `unconfirmed`; the refusal count, a look-alike entry left
# out; --since keeping calls, merges, recommendations and refusals to the
# window, holds and open whole, and a merge in the window whose call came
# before it still `reviewed`; an unreadable lineage session in gaps with exit
# 0 and its events left out; a pull request GitHub can't read failing the
# read (2, nothing on stdout); refusals of usage and of a run with no found
# record; the record's keys and every log byte-identical around every run,
# with no GitHub write; and the calls' five fields read by a jq filter kept
# outside the skill.
#
# Every script runs on the koto stand-in (testdata/koto) and one scratch
# store. GitHub is testdata/gh behind a wrapper in the suite's own directory
# that answers each pull request's changed files from the DB's pr_files.
#
# Usage: bash skills/coordinate/scripts/alignment-read_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
export KOTO_BIN="$HERE/testdata/koto"
AR="$HERE/alignment-read.sh"

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
r=${p#repos/}; n=${r#*/pulls/}; n=${n%%/*}; n=${n%%\?*}; r=${r%%/pulls/*}
out=$(jq -c --arg k "$r#$n" '[(.pr_files // {}) | to_entries[] | select((.key | ascii_downcase) == ($k | ascii_downcase)) | .value][0] // []' "$GH_DB")
out=$(printf '%s' "$out" | jq -c 'map({filename: .})')
if [ -n "$jqf" ]; then printf '%s\n' "$out" | jq -r "$jqf"; else printf '%s\n' "$out"; fi
EOF
} > "$T/bin/gh"
chmod +x "$T/bin/gh" || exit 1
PATH="$T/bin:$PATH"
export PATH

SD=coordinate-roadmap-direction-20260926T080000Z
SP=coordinate-roadmap-direction-20260925T080000Z
SQ=coordinate-roadmap-direction-20260924T080000Z
SINCE=2026-09-26T12:00:00Z
U=https://github.com/acme/widgets/pull
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
link() { printf '[#%s](%s/%s)' "$1" "$U" "$1"; }
# sha <n> <k>: a 40-hex head, the pull request's number and the head's index.
sha() { local u s=; u=$(printf '%04x%04x' "$1" "$2"); for _ in 1 2 3 4 5; do s=$s$u; done; printf '%s' "$s"; }
O() { sha "$1" 1; }   # the head a call or hold was placed on
L() { sha "$1" 2; }   # the live, or merged, head

# ---- GitHub ------------------------------------------------------------------
db_init
# pr <n> <state> <head> [mergedAt] [branch]
pr() {
    db '.prs += [{repo: "acme/widgets", number: $n, title: "t", body: "", state: $s, isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: $b, headRefOid: $h, author: "alice", editor: null}
        + (if $m == "" then {} else {mergedAt: $m} end)]' \
        --argjson n "$1" --arg s "$2" --arg h "$3" --arg m "${4:-}" --arg b "${5:-feat/pr-$1}"
}
pr 20 OPEN "$(L 20)"; pr 21 OPEN "$(L 21)"; pr 22 OPEN "$(L 22)"; pr 23 OPEN "$(L 23)"
pr 24 MERGED "$(O 24)" 2026-09-26T11:50:00Z; pr 25 CLOSED "$(O 25)"; pr 26 OPEN "$(L 26)"; pr 44 OPEN "$(L 44)"
pr 100 OPEN "$(L 100)"
pr 30 MERGED "$(L 30)" 2026-09-26T11:00:00Z
pr 31 MERGED "$(L 31)" 2026-09-26T12:30:00Z
pr 32 MERGED "$(L 32)" 2026-09-26T12:40:00Z
pr 33 MERGED "$(L 33)" 2026-09-26T12:50:00Z
pr 34 MERGED "$(L 34)" 2026-09-26T12:55:00Z
pr 35 MERGED "$(L 35)" 2026-09-26T13:00:00Z
pr 36 MERGED "$(L 36)" 2026-09-26T13:10:00Z
pr 37 MERGED "$(L 37)" 2026-09-26T13:15:00Z
pr 38 MERGED "$(L 38)" 2026-09-26T13:16:00Z
pr 39 MERGED "$(L 39)" 2026-09-26T13:17:00Z
pr 40 MERGED "$(L 40)" 2026-09-26T13:30:00.000Z coordinate/roadmap-verdict-mv1-20260926T130000Z
pr 41 MERGED "$(L 41)" 2026-09-26T13:32:00Z
pr 42 MERGED "$(L 42)" 2026-09-26T13:45:00Z
pr 43 MERGED "$(L 43)" 2026-09-26T13:50:00Z
pr 45 MERGED "$(L 45)" 2026-09-26T13:55:00Z
db '.pr_files = {"acme/widgets#42": ["docs/roadmaps/ROADMAP-direction.md"],
    "acme/widgets#43": ["docs/strategies/STRATEGY-direction.md", "README.md"],
    "acme/widgets#37": ["src/list.go"], "acme/widgets#31": ["src/cache.go"]}'

# ---- the director's record ---------------------------------------------------
# Four lane rows: mgr-a and mgr-b link their own pull requests #30 and #31 at
# the verified head; mgr-c's #32 and mgr-d's #35 merged, the Pull request cell
# cleared and the Verified head kept. Five align- holds, one per state.
run_row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "alice", set: "2026-09-26T08:00Z"}'; }
hold_row() { # hold_row <n> [lifted]
    jq -nc --arg h "align-widgets-$1-$(O "$1")" --arg on "acme/widgets#$1" --arg l "${2:-}" \
        '{hold: $h, on: $on, until: "lifted", set_by: "director at director-a, receiver manager at mgr-a", set: "2026-09-26T09:00Z", lifted: $l}'
}
lane() { # lane <worker> <pull request cell> <verified head>: a Holdings row
    holding "$1" "$(jq -nc --arg p "$2" --arg v "$3" '{pull_request: $p, verified_head: $v}')"
}
REC=$(record_json roadmap direction | jq -c \
    --argjson a "$(lane mgr-a "$(link 30)" "$(L 30)")" --argjson b "$(lane mgr-b "$(link 31)" "$(L 31)")" \
    --argjson c "$(lane mgr-c "" "$(L 32)")" --argjson d "$(lane mgr-d "" "$(L 35)")" \
    --argjson h20 "$(hold_row 20)" --argjson h22 "$(hold_row 22)" \
    --argjson h23 "$(hold_row 23 "2026-09-26T11:00Z by director at director-a, fits at $(L 23)")" \
    --argjson h24 "$(hold_row 24)" --argjson h25 "$(hold_row 25)" --argjson h26 "$(hold_row 26)" \
    --argjson rc "$(run_row coordinator director-a)" --argjson rr "$(run_row role director)" \
    --arg se "MV2 $(link 41)" --arg sh "$(L 41)" \
    '.holdings = [$a, $b, $c, $d] | .holds = [$h20, $h22, $h23, $h24, $h25, $h26] | .run = [$rc, $rr]
     | .side_effects = [{action: "milestone-done", target: $se, verified_head: $sh, attempted: "2026-09-26T13:00Z",
                          how_to_confirm: "roadmap-status.sh --confirm"}]')
found_session "$SD" "$(roadmap_vars direction)"
seed_session "$SD" "$REC" || { echo "FAIL: the director's record didn't seed"; exit 1; }

# entry <n> <stamp> <kind> <text>: a planted account entry, as state-entry.sh writes one.
entry() {
    jq -nc --argjson n "$1" --arg s "$2" --arg k "$3" --arg t "$4" '{n: $n, stamp: $s, kind: $k, text: $t}' \
        | koto context add "$SD" "record/entries/$(printf '%06d' "$1")"
}
# call <n> <stamp> <pr> <head> <call> <action> [sources] [evidence] [follow-ups]
call() {
    entry "$1" "$2" alignment "$(printf 'Alignment: acme/widgets#%s at %s -- %s\nRead: full\nSources: %s\nReason: reason %s\nEvidence: %s\nFollow-ups: %s\nAction: %s' \
        "$3" "$4" "$5" "${7:-standing s1}" "$1" "${8:-none}" "${9:-none}" "$6")"
}
call 1 2026-09-26T09:00:00Z 20 "$(O 20)" diverges hold
call 2 2026-09-26T09:10:00Z 20 "$(O 20)" diverges hold "standing s1; decision 3"
call 3 2026-09-26T09:15:00Z 21 "$(O 21)" fits none none
call 4 2026-09-26T09:20:00Z 21 "$(L 21)" fits recommend none
call 5 2026-09-26T09:30:00Z 22 "$(O 22)" diverges hold
call 6 2026-09-26T09:40:00Z 23 "$(O 23)" diverges hold
call 7 2026-09-26T09:50:00Z 24 "$(O 24)" diverges hold
call 8 2026-09-26T09:55:00Z 25 "$(O 25)" diverges hold
call 9 2026-09-26T09:58:00Z 26 "$(O 26)" diverges hold
entry 10 2026-09-26T10:00:00Z entry "Refused: no-alignment-call acme/widgets#34 at $(L 34)"
call 11 2026-09-26T10:20:00Z 26 "$(L 26)" diverges hold
call 12 2026-09-26T10:30:00Z 30 "$(L 30)" fits merge none
call 13 2026-09-26T11:30:00Z 31 "$(L 31)" "fits with follow-ups" merge "roadmap docs/roadmaps/ROADMAP-direction.md at $(L 1) MV1 clause 1" \
    "1 met; 2 not met" "new: cache the list; new: page the output"
entry 14 2026-09-26T11:40:00Z entry "Refused: no alignment call was needed for the docs change"
call 15 2026-09-26T12:10:00Z 22 "$(L 22)" fits none none
entry 16 2026-09-26T12:15:00Z entry "Refused: no-alignment-call acme/widgets#32 at $(L 32)"
entry 17 2026-09-26T12:45:00Z entry "Refused: no-alignment-call acme/widgets#40 at $(L 40)"
call 18 2026-09-26T13:20:00Z 36 "$(L 36)" fits none none
call 19 2026-09-26T13:40:00Z 42 "$(L 42)" fits recommend none

# ---- the events: this run's, its predecessor's and the one before ------------
# block <line>...: a report's text, then its result block.
block() {
    local t=$1; shift
    printf '%s\n\n=== RESULT ===\nsession=w\n' "$t"
    for l in "$@"; do printf '  %s\n' "$l"; done
    printf '=== END RESULT ===\n'
}
ev() { # ev <session> <timestamp> <fields-json>
    log_evidence "$1" wait "$3" "$2"
    log_to "$1" wait take_report "$2"
}
ev "$SD" 2026-09-26T10:00:00.000Z "$(jq -nc --arg r "$(block 'Worker f33 landed.' worker=acme/widgets#33 open=acme/widgets#21 open=acme/widgets#44 \
    open=acme/widgets#100 open=acme/gadgets#5)" \
    --arg p "$U/33" '{event: "report", unit: "mgr-a", pull_request: $p, report: $r}')"
ev "$SD" 2026-09-26T10:05:00.000Z "$(jq -nc --arg r "$(block "Landed acme/widgets#34 myself; also $U/38 and $U/39." \
    'unit=mgr-b finished acme/widgets#38' "unit=mgr-b done $U/39")" '{event: "report", unit: "mgr-b", pull_request: "acme/widgets#34", report: $r}')"
HOLD20="align-widgets-20-$(O 20)"
ev "$SD" 2026-09-26T10:10:00.000Z "$(jq -nc --arg r "$(block "Holding #20 as $HOLD20. Landed $U/35 for the worker." worker=acme/widgets#35)" \
    '{event: "progress", unit: "mgr-a", report: $r}')"
ev "$SD" 2026-09-26T10:15:00.000Z "$(jq -nc --arg r "$(block "unit=mgr-b done acme/widgets#37 -- the unit is done with $U/37." pr=acme/widgets#37)" \
    '{event: "report", unit: "mgr-b", report: $r}')"
ev "$SD" 2026-09-26T10:20:00.000Z "$(jq -nc --arg r "$(block "Verdict $U/40, $U/41 and strategy $U/43." 'unit=mgr-a done acme/widgets#36' open=acme/widgets#42)" \
    '{event: "report", unit: "mgr-a", report: $r}')"
ev "$SD" 2026-09-26T10:25:00.000Z "$(jq -nc --arg r "Re-sent ${HOLD20}-2 by mistake." '{event: "progress", unit: "mgr-a", report: $r}')"
HOLD20_SEQ=$(bash "$HERE/coord-log.sh" evidence --session "$SD" --state wait --where 'event=progress' --before 999 | jq -r .seq)
HOLD20_SEQ=$(bash "$HERE/coord-log.sh" evidence --session "$SD" --state wait --where 'event=progress' --before "$HOLD20_SEQ" | jq -r .seq)

log_new "$SP" "$(roadmap_vars direction)"
ev "$SP" 2026-09-25T10:00:00.000Z "$(jq -nc --arg r "Merged on the cleared row: $U/32" '{event: "progress", unit: "mgr-c", report: $r}')"
log_new "$SQ" "$(roadmap_vars direction)"
ev "$SQ" 2026-09-24T10:00:00.000Z "$(jq -nc --arg r "My own." '{event: "report", unit: "mgr-a", pull_request: "acme/widgets#45", report: $r}')"
printf '{}' | koto context add "$SD" "koto/links/continues/$SP"
printf '{}' | koto context add "$SP" "koto/links/continues/$SQ"

# ---- what the read leaves alone ---------------------------------------------
logs() { for s in "$SD" "$SP" "$SQ"; do f="$KOTO_STORE/sessions/$s/koto-$s.state.jsonl"; [ -f "$f" ] && od -An -tx1 < "$f" | tr -d ' \n'; echo; done; }
SNAP=$(session_snapshot "$SD")
LOGS=$(logs)
reset_calls
untouched() { # untouched <case>
    eq "$1: the record's keys are byte-identical" "$SNAP" "$(session_snapshot "$SD")"
    eq "$1: every log is byte-identical" "$LOGS" "$(logs)"
    eq "$1: nothing written to GitHub" "" "$(gh_writes)"
}
read_() { bash "$AR" --session "$SD" "$@" > "$T/out.json" 2> "$T/err"; }
q() { jq -c "$1" "$T/out.json"; }
merge_of() { q "[.merges[] | select(.pull_request == \"acme/widgets#$1\") | .review]"; }

# ---- the whole run -----------------------------------------------------------
read_; rc=$?
eq "the read exits 0" 0 "$rc"
[ "$rc" = 0 ] || cat "$T/err"
eq "one object, with exactly the seven keys" '["calls","gaps","holds","merges","open","recommendations","refusals"]' "$(q 'keys')"
untouched "the whole run"
eq "an event's pull request outside the host and the Holdings repositories is never read" "" "$(grep -i 'gadgets' "$GH_DB.calls")"

eq "every alignment entry, oldest first" '[1,2,3,4,5,6,7,8,9,11,12,13,15,18,19]' "$(q '[.calls[].entry]')"
eq "each call carries the twelve fields" \
    '["action","call","entry","evidence","follow_ups","head","pull_request","read","reason","sources","stamp","standing"]' \
    "$(q '.calls[0] | keys')"
eq "a call's first line, stamp and lines" \
    "$(jq -nc --arg h "$(O 20)" '{entry: 2, stamp: "2026-09-26T09:10:00Z", pull_request: "acme/widgets#20", head: $h, call: "diverges",
        read: "full", sources: ["standing s1", "decision 3"], reason: "reason 2", evidence: [], follow_ups: [], action: "hold", standing: true}')" \
    "$(q '.calls[1]')"
eq "Evidence and Follow-ups split on '; '" '[["1 met","2 not met"],["new: cache the list","new: page the output"]]' \
    "$(q '[.calls[] | select(.entry == 13) | .evidence, .follow_ups]')"
eq "a none Sources is an empty list" '[]' "$(q '[.calls[] | select(.entry == 3) | .sources[]]')"
eq "two calls on one pull request and head: only the later stands" '[false,true]' \
    "$(q '[.calls[] | select(.pull_request == "acme/widgets#20") | .standing]')"
eq "a call on an older head stands for that head only" '[true,true]' \
    "$(q '[.calls[] | select(.pull_request == "acme/widgets#21") | .standing]')"

eq "open: every open lane pull request at its live head, with the standing call or none" \
    "$(jq -nc --arg a "$(L 20)" --arg b "$(L 21)" --arg c "$(L 22)" --arg d "$(L 23)" --arg e "$(L 26)" --arg f "$(L 44)" --arg g "$(L 100)" '[
        {pull_request: "acme/widgets#20", head: $a, call: "none"}, {pull_request: "acme/widgets#21", head: $b, call: "fits"},
        {pull_request: "acme/widgets#22", head: $c, call: "fits"}, {pull_request: "acme/widgets#23", head: $d, call: "none"},
        {pull_request: "acme/widgets#26", head: $e, call: "diverges"}, {pull_request: "acme/widgets#44", head: $f, call: "none"},
        {pull_request: "acme/widgets#100", head: $g, call: "none"}]')" \
    "$(q '.open')"

eq "merges: each merged lane pull request owed a call, and each worker= one, by merge time" \
    '["acme/widgets#30","acme/widgets#31","acme/widgets#32","acme/widgets#33","acme/widgets#34","acme/widgets#35","acme/widgets#36","acme/widgets#40","acme/widgets#41","acme/widgets#42","acme/widgets#43","acme/widgets#45"]' \
    "$(q '[.merges[].pull_request]')"
eq "a merge carries pull_request, merged_head, merged_at, call and review" \
    "$(jq -nc --arg h "$(L 31)" '{pull_request: "acme/widgets#31", merged_head: $h, merged_at: "2026-09-26T12:30:00Z", call: "fits with follow-ups", review: "reviewed"}')" \
    "$(q '.merges[1]')"
eq "a Holdings-linked manager pull request called before its merge is reviewed" '["reviewed"]' "$(merge_of 30)"
eq "a cleared row's merge, found only through a predecessor's progress link, is unreviewed" '["unreviewed"]' "$(merge_of 32)"
eq "an event's pull request under a holding's topic, named by worker=, is manager-reviewed" '["manager-reviewed"]' "$(merge_of 33)"
eq "the same with no worker= line is manager-authored and unreviewed" '["unreviewed"]' "$(merge_of 34)"
eq "a worker= pull request whose merged head a row's Verified head equals is manager-reviewed" '["manager-reviewed"]' "$(merge_of 35)"
eq "a unit= done line's pull request, called only after it merged, is after merge" '["after merge"]' "$(merge_of 36)"
eq "  ... and its call is the latest call for the merged head" '["fits"]' "$(q '[.merges[] | select(.pull_request == "acme/widgets#36") | .call]')"
eq "a report saying a unit is done in its text, with no unit= line, finishes nothing" '[]' "$(merge_of 37)"
eq "a unit= line with a status outside the three finishes nothing" '[]' "$(merge_of 38)"
eq "a unit= line whose pull request isn't owner/repo#n finishes nothing" '[]' "$(merge_of 39)"
eq "a milestone verdict branch's merge is owed a call, and unreviewed with none" '["unreviewed"]' "$(merge_of 40)"
eq "  ... its merge time without GitHub's fraction" '["2026-09-26T13:30:00Z"]' "$(q '[.merges[] | select(.pull_request == "acme/widgets#40") | .merged_at]')"
eq "a milestone-done Side effects row's pull request is owed a call" '["unreviewed"]' "$(merge_of 41)"
eq "a roadmap change called before its merge is reviewed" '["reviewed"]' "$(merge_of 42)"
eq "a strategy change with no call is unreviewed, call none" '[{"call":"none","review":"unreviewed"}]' \
    "$(q '[.merges[] | select(.pull_request == "acme/widgets#43") | {call, review}]')"
eq "a held pull request that merged owes nothing here" '[]' "$(merge_of 24)"

eq "recommendations: each call whose Action is recommend, as listed" '[4,19]' "$(q '[.recommendations[].entry]')"
eq "  ... the call itself" "$(q '[.calls[] | select(.entry == 4)][0]')" "$(q '.recommendations[0]')"

eq "holds: every align- hold, with its state" \
    '[["acme/widgets#20","standing",true],["acme/widgets#22","releasable",false],["acme/widgets#23","lifted",false],["acme/widgets#24","merged while held",false],["acme/widgets#25","closed while held",false],["acme/widgets#26","standing",false]]' \
    "$(q '[.holds[] | [.pull_request, .state, .needs_re_read]]')"
eq "a hold carries the latest diverges call at its head, and that call's reason" \
    "$(jq -nc --arg n "$HOLD20" --arg h "$(O 20)" '{hold: $n, placed_head: $h, call_entry: 2, reason: "reason 2"}')" \
    "$(q '.holds[0] | {hold, placed_head, call_entry, reason}')"
eq "a standing hold carries the latest report naming it as a whole word" \
    "$(jq -nc --arg s "$SD" --argjson q "$HOLD20_SEQ" '{session: $s, seq: $q, timestamp: "2026-09-26T10:10:00.000Z", unit: "mgr-a"}')" \
    "$(q '.holds[0].report')"
eq "a hold no report named is unconfirmed; a lifted or ended one has none" '["unconfirmed",null,null,null,"unconfirmed"]' \
    "$(q '[.holds[1:][] | .report]')"

eq "refusals: the refusal entries, a look-alike left out" 3 "$(q '.refusals')"
eq "gaps: none while every lineage log reads" '[]' "$(q '.gaps')"

# R16: the calls' five fields read by a jq filter kept outside the skill.
printf '%s\n' '.calls[] | select(.entry == 13) | [.pull_request, .head, .call, (.sources | join("; ")), .reason] | @tsv' > "$T/r16.jq"
eq "a jq filter outside the skill reads a call's five fields" \
    "$(printf 'acme/widgets#31\t%s\tfits with follow-ups\troadmap docs/roadmaps/ROADMAP-direction.md at %s MV1 clause 1\treason 13' "$(L 31)" "$(L 1)")" \
    "$(jq -r -f "$T/r16.jq" "$T/out.json")"

# ---- --since -----------------------------------------------------------------
read_ --since "$SINCE"; rc=$?
eq "--since: exits 0" 0 "$rc"
untouched "--since"
eq "--since: the calls stamped after it" '[15,18,19]' "$(q '[.calls[].entry]')"
eq "--since: standing is still judged against every call" '[true,true,true]' "$(q '[.calls[].standing]')"
eq "--since: the merges after it" \
    '["acme/widgets#31","acme/widgets#32","acme/widgets#33","acme/widgets#34","acme/widgets#35","acme/widgets#36","acme/widgets#40","acme/widgets#41","acme/widgets#42","acme/widgets#43","acme/widgets#45"]' \
    "$(q '[.merges[].pull_request]')"
eq "--since: a merge after it whose only call came before it is still reviewed" '["reviewed"]' "$(merge_of 31)"
eq "--since: the recommendations after it" '[19]' "$(q '[.recommendations[].entry]')"
eq "--since: the refusals after it" 2 "$(q '.refusals')"
eq "--since: holds stay whole" 6 "$(q '.holds | length')"
eq "--since: open stays whole" 7 "$(q '.open | length')"

# ---- a lineage gap -----------------------------------------------------------
mv "$KOTO_STORE/sessions/$SQ" "$T/sq-aside"
LOGS_GAP=$(logs)
read_; rc=$?
eq "a gap: the read still exits 0" 0 "$rc"
eq "a gap: the unreadable session is named" "[\"$SQ\"]" "$(q '.gaps')"
eq "a gap: what only it named is left out" '[]' "$(merge_of 45)"
eq "a gap: the rest is read" '["unreviewed"]' "$(merge_of 32)"
eq "a gap: the record's keys are byte-identical" "$SNAP" "$(session_snapshot "$SD")"
eq "a gap: every log is byte-identical" "$LOGS_GAP" "$(logs)"
mv "$T/sq-aside" "$KOTO_STORE/sessions/$SQ"

# ---- failures and refusals ---------------------------------------------------
db '.fail = [{match: "pr view 21 ", rc: 1, stderr: "gh: HTTP 502"}]'
read_; rc=$?
eq "a lane pull request GitHub can't read fails the read" 2 "$rc"
eq "  ... with nothing on stdout" "" "$(cat "$T/out.json")"
eq "  ... naming it" 1 "$(grep -c 'acme/widgets#21' "$T/err")"
db '.fail = []'
bash "$AR" --session "$SD" --since 2026-09-26 > "$T/out.json" 2> "$T/err"
eq "--since that isn't a stamp is usage" 64 $?
bash "$AR" > /dev/null 2>&1
eq "no --session is usage" 64 $?
SN=coordinate-roadmap-direction-20260927T080000Z
log_new "$SN" "$(roadmap_vars direction)"
bash "$AR" --session "$SN" > "$T/out.json" 2> "$T/err"
eq "a run with no found record is refused" 10 $?
untouched "the failures"

done_tests alignment-read_test.sh
