#!/usr/bin/env bash
# unit-cost_test.sh -- unit-cost.sh, the teardown pass's cost capture, over
# fixture archives, the gh and koto stand-ins, and the real record scripts.
#
# Covers: the example unit (testdata/unit-cost/archive, a single-pr plan with
# two /work-on children and one pull request of three heads, one of them
# failing on an attempt a rerun passed; its claude-projects/ holds the
# instance's own project directory, with the worker's main transcript, a
# subagent and a second job's transcript, and a worktree's, with two more of
# the worker's subagents and a relocated copy; pr-link records credit two
# more pull requests) captured end to end: the posted
# comment is a summary line, a blank line and one fenced json block,
# committed as example-comment.md, whose object is example-entry.json, the
# archive's unit-cost.json is the same object, and RESULT, MANIFEST and
# README are byte-identical before and after; every baseline figure and
# per-session figure of the example and of a single-issue unit
# (testdata/unit-cost/issue-archive) equal to the hand-computed
# expected-plan.json and expected-issue.json; per-state seconds summing to
# each session's span, and a session with no done running to its last event;
# an in_progress run on the green head bounding green and the figures from it;
# compute printing one compact object with every field of the entry, each
# figure not taken listed in `missing` with a reason from the closed list;
# plan shape for each /deliver mode, each /execute template, each /work-on
# mode, none of them, a /deliver with no plan_execution_mode, a coordinated
# /deliver with plan_backed children, and a session whose header can't be
# read; the milestone for each Unit form, a discipline record, a failed
# run-facts or Holdings read, a missing row and a Unit outside the safety
# pattern; dispatch from the request, from the job, from the transcripts'
# first events (the earliest wins, the request a tie, dispatch.jobs counting
# the main session transcripts), and none of them; the token rows by message
# id (a nested transcript, an id written three times with usage rising then
# falling, a non-string id, a line that isn't JSON, a relocated copy whose
# repeats of the worker's ids count once, an archive made before
# claude-projects/); two pull requests in two repositories, and one the
# verdict doesn't name; credit from pr-link records (each condition, the
# 120-second window both ways, a sibling branch, an unreadable pull request,
# no dispatch, more than 100, a private repository on a public host, a
# budget spent mid-way, and hostile links and branches that no read names);
# niwa's dispatch id from teardown.json, or, when it holds none, from the
# removal record for the archive's instance path (not another path's, not a
# removals directory that isn't mode 0700); a pull request file naming none,
# credit's owner then the record repository's and green, merge and failing
# heads read over the credited pull requests; one
# entry per key (twice posts once, another key's entry doesn't stop a post, a
# failed list posts anyway); missing transcripts, a failing `gh run list`, a
# failing `gh pr view` and a spent budget still posting an entry with
# complete false; an entry over 50,000 bytes posted without its states maps;
# hostile input (a request id with ../, a verdict repository and a head
# branch starting with -, a line that isn't JSON in a state log, planted
# key-shaped strings, prompt text and home paths, symlinks in the archive);
# a public host never naming a repository it doesn't read as public; the
# GitHub wrapper's admitted and refused calls; no GitHub write across the
# suite but one comment POST per captured unit, on the unit's pull request;
# and the scripts that read record entries (state-stored-set.sh, through
# state-entry.sh --list, is the one) giving the same output with a cost
# entry on the record. The record is the run's session's: the entries are its
# keys, and a cost entry is posted on the sealed verdict's first pull request
# (#21), the holding naming none.
#
# UNIT_COST_REGEN=1 rewrites example-entry.json and example-comment.md from
# the example's capture before the suite compares them.
#
# Usage: bash skills/coordinate/scripts/unit-cost_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
# Its own HOME and koto home, inside the suite's scratch directory, so suites
# run side by side share no path.
export HOME="$T/home" KOTO_SESSIONS_BASE="$T/koto-home"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
UC="$HERE/unit-cost.sh"
RA="$HERE/state-entry.sh"
FX="$HERE/testdata/unit-cost"
KEY=2026-10-01-feat-x-0a1b2c3d
YKEY=2026-10-02-fix-y-0e0f1a2b
MERGE=5555555555555555555555555555555555555555
MERGE2=6666666666666666666666666666666666666666
MERGEY=3434343434343434343434343434343434343434
export KOTO_REQUESTS="$FX/requests" UNIT_COST_NOW=2026-10-01T12:00:00Z UNIT_COST_FETCH_SECS=5
# acme/widgets is public, so its pull request gets the entry only while it
# opts in: the opt-in reader's stand-in says it does. unit-cost-on_test.sh
# covers a repository that doesn't.
printf '#!/usr/bin/env bash\necho include\n' >"$T/reader"
export UNIT_COST_PR_CONTENT_READER="$T/reader"
S=coordinate-roadmap-x-20261001T080000Z
REASONS='["no source","read failed","time limit","entry size","invalid input"]'
POSTED=0
: >"$T/allcalls"

# seed [unit] [pull request cell]: the record (ROADMAP-x on acme/widgets), in
# the run's session, holding feat-x with that Unit and that Pull request cell
# (none by default), no entries yet; GitHub's side of the fixtures
# (testdata/unit-cost/github.json: the pull requests, their heads and the runs
# on them), and acme/widgets's CLAUDE.md, which opts in to workflow content.
seed() {
    cat "$GH_DB.calls" >>"$T/allcalls" 2>/dev/null
    db_init
    local rec
    rec=$(record_json roadmap x | jq -c --argjson h "$(holding feat-x "$(jq -nc --arg u "${1:-Feature 4: Example feature}" --arg p "${2:-}" '{unit: $u, pull_request: $p}')")" '.holdings = [$h]')
    seed_session "$S" "$rec" 2026-10-01T08:00:00Z
    db '.files["acme/widgets"]["main:CLAUDE.md"] = "# widgets\n\n## PR Workflow Content: include"'
    db '.prs += $g[0].prs | .pr_commits = $g[0].pr_commits | .runs = $g[0].runs' --slurpfile g "$FX/github.json"
}
fresh() { rm -rf "$T/a"; mkdir -p "$T/a"; cp -R "$FX/archive/$KEY" "$T/a/"; A="$T/a/$KEY"; }
prs() { printf '%s\n' "$@" >"$T/prs"; }
compute() { bash "$UC" compute --archive "$A" --topic feat-x --prs-file "$T/prs" "$@" 2>"$T/err"; }
capture() { bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"; }
# posted: the bodies of the cost entries on the verdict's pull request, #21,
# as a JSON array.
cost_bodies() { jq -c '[.comments // [] | .[] | select(.number == 21) | .body | select(startswith("<!-- coordinator-record-entry v1 kind=cost -->"))]' "$GH_DB"; }
last_entry() { cost_bodies | jq -c '.[-1] | split("\n") | .[6] | fromjson'; }
block() { sed -n '/^```json$/,/^```$/p' | sed '1d;$d'; }
q() { printf '%s' "$1" | jq -r "$2"; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi; }
fig() { q "$1" ".figures.$2 | \"\\(.value) \\(.state)\""; }
# same_as <entry> <expected file>: "same" when the entry's figures and
# sessions equal the expected file's on every field it names (numbers compared
# as numbers), else the entry's projection, for the failure message.
same_as() {
    printf '%s' "$1" | jq -c -r --slurpfile x "$2" '
        $x[0] as $x
        | {figures: (.figures | with_entries(.key as $k | .value |= with_entries(select(.key as $q | $x.figures[$k] | has($q))))),
           sessions: [.sessions[] | {index, template, unit_session, done, span_s, states,
                                     figures: (.figures | map_values({value, state, source}))}]} as $p
        | if $p == $x then "same" else $p end'
}

found_session "$S" "$(roadmap_vars x)"
export RS_SESSION=$S

echo "== the example unit, captured =="
seed; fresh; prs "acme/widgets#21 $MERGE"
BEFORE="$(sha "$A/RESULT") $(sha "$A/MANIFEST") $(sha "$A/README.md")"
capture; eq "the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... one cost entry" 1 "$(cost_bodies | jq length)"
BODY=$(cost_bodies | jq -r '.[0]')
norm() { sed '2s/^\*\*[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z\*\*/**STAMP**/'; }
if [ "${UNIT_COST_REGEN:-}" = 1 ]; then
    printf '%s\n' "$BODY" | sed '2s/^\*\*[0-9TZ:-]*\*\*/**2026-10-01T12:00:00Z**/' >"$FX/example-comment.md"
    jq . "$A/unit-cost.json" >"$FX/example-entry.json"
    echo "regenerated example-entry.json and example-comment.md"
fi
eq "RESULT, MANIFEST and README are byte-identical after the capture" "$BEFORE" "$(sha "$A/RESULT") $(sha "$A/MANIFEST") $(sha "$A/README.md")"
eq "the posted object is example-entry.json" "$(jq -S . "$FX/example-entry.json")" "$(printf '%s\n' "$BODY" | block | jq -S . 2>&1)"
eq "the archive's unit-cost.json is the same object" "$(jq -S . "$FX/example-entry.json")" "$(jq -S . "$A/unit-cost.json" 2>&1)"
eq "the posted comment is example-comment.md, but for the host-clock stamp" "$(norm <"$FX/example-comment.md")" "$(printf '%s\n' "$BODY" | norm)"
eq "example-comment.md's json block is example-entry.json" "$(jq -S . "$FX/example-entry.json")" "$(block <"$FX/example-comment.md" | jq -S . 2>&1)"
eq "example-entry.json holds the hand-computed figures (expected-plan.json)" same "$(same_as "$(jq -c . "$FX/example-entry.json")" "$FX/expected-plan.json")"
TEXT=$(printf '%s\n' "$BODY" | sed '1,3d')
eq "the text is a summary line, a blank line and one fenced json block" "Cost|blank|fence|{|fence|5" \
    "$(printf '%s\n' "$TEXT" | awk 'NR==1{a=substr($0,1,4)} NR==2{b=($0==""?"blank":$0)} NR==3{c=($0=="```json"?"fence":$0)} NR==4{d=substr($0,1,1)} NR==5{e=($0=="```"?"fence":$0)} END{print a"|"b"|"c"|"d"|"e"|"NR}')"
eq "  ... the summary line" "Cost of feat-x ($KEY): 5 sessions, 110 output tokens, dispatch to merge 150.0 min." "$(head -n 1 <<<"$TEXT")"
printf '%s\n' "$TEXT" | sed -n 4p | jq -e 'type == "object"' >/dev/null && ok "  ... the json line is one compact object" || bad "  ... the json line is one compact object" "$TEXT"
E=$(jq -c . "$A/unit-cost.json")
eq "the record's facts and the Unit's tag" '{"scope":"roadmap","name":"x","repo":"acme/widgets","ref":""}|Feature 4' "$(q "$E" '"\(.record | tojson)|\(.unit)"')"
eq "  ... the milestone" '{"value":{"roadmap":"ROADMAP-x","tag":"Feature 4"},"state":"measured","source":"record"}' "$(q "$E" '.milestone | tojson')"
eq "  ... complete, nothing missing" "true|0" "$(q "$E" '"\(.complete)|\(.missing | length)"')"

echo "== the figures, against the hand-computed expected files =="
seed; fresh; prs "acme/widgets#21 $MERGE"
OUT=$(compute)
eq "the plan unit: every figure and per-session figure as expected-plan.json" same "$(same_as "$OUT" "$FX/expected-plan.json")"
eq "  ... two unit sessions, both work-on children" "false false true true false" "$(q "$OUT" '[.sessions[].unit_session | tostring] | join(" ")')"
eq "  ... each session's states sum exactly to its span" true "$(q "$OUT" '[.sessions[] | (.states | add) == .span_s] | all')"
rm -rf "$T/y"; mkdir -p "$T/y"; cp -R "$FX/issue-archive/$YKEY" "$T/y/"
printf 'acme/widgets#31 %s\n' "$MERGEY" >"$T/prs-y"
OUTY=$(bash "$UC" compute --archive "$T/y/$YKEY" --topic fix-y --prs-file "$T/prs-y" 2>"$T/err")
eq "the single-issue unit: every figure and per-session figure as expected-issue.json" same "$(same_as "$OUTY" "$FX/expected-issue.json")"
eq "  ... an archive made before claude-projects/: its dispatch is the job's, earlier than the request" \
    "2026-10-02T08:59:30.000Z job-state 0" "$(q "$OUTY" '"\(.dispatch.value) \(.dispatch.source) \(.dispatch.jobs)"')"
eq "  ... the worker read from transcript/ as before, nested not recoverable, no source" \
    "1 4 12 30 60 measured|not recoverable|no source" \
    "$(q "$OUTY" '"\(.tokens.worker | "\(.messages) \(.input) \(.output) \(.cache_creation) \(.cache_read) \(.state)")|\(.tokens.nested.state)|\([.missing[] | select(.figure == "tokens.nested") | .reason][0])"')"
eq "  ... its plan shape is issue and minutes_per_unit not applicable" "issue|not applicable" \
    "$(q "$OUTY" '"\(.plan_shape.value)|\(.figures.minutes_per_unit.state)"')"
eq "  ... every other figure is measured" true "$(q "$OUTY" '[.figures | to_entries[] | select(.key != "minutes_per_unit") | .value.state == "measured"] | all')"
eq "  ... the states sum to the span" true "$(q "$OUTY" '[.sessions[] | (.states | add) == .span_s] | all')"
eq "a share keeps its unrounded value as raw" "68.8 68.84615384615384" "$(q "$OUT" '"\(.figures.outside_share_pct.value) \(.figures.outside_share_pct.raw)"')"

echo "== state time =="
fresh
# The second child without its done: it runs to its last event (an
# analysis entered at 11:05), so review lasts to 11:05 and nothing follows.
grep -v '"seq":10,' "$A/koto/execute-x.o-issue-2/koto-execute-x.o-issue-2.state.jsonl" >"$T/s2"
cp "$T/s2" "$A/koto/execute-x.o-issue-2/koto-execute-x.o-issue-2.state.jsonl"
OUT=$(compute)
eq "a session with no done is counted in sessions_without_done" "1 measured" "$(fig "$OUT" sessions_without_done)"
eq "  ... and runs to its last event" 'false|2670|{"analysis":570,"entry":0,"implementation":1230,"review":600,"scrutiny":270}' \
    "$(q "$OUT" '.sessions[3] | "\(.done)|\(.span_s)|\(.states | tojson)"')"
eq "  ... its states still sum exactly to its span" true "$(q "$OUT" '[.sessions[] | (.states | add) == .span_s] | all')"
eq "  ... and the summed span takes it: (3585 + 2670) / 60" "104.3 measured" "$(fig "$OUT" summed_session_span_min)"
fresh
# Millisecond timestamps: the states still sum to the span exactly.
jq -c 'if .type == "transitioned" and .seq == 5 then .timestamp = "2026-10-01T09:40:00.125Z"
       elif .type == "transitioned" and .seq == 6 then .timestamp = "2026-10-01T10:00:00.333Z" else . end' \
    "$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl" >"$T/s1"
cp "$T/s1" "$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl"
OUT=$(compute)
eq "with millisecond timestamps the states are kept to the millisecond" '1185.125|1200.208|599.667' \
    "$(q "$OUT" '.sessions[2].states | "\(.analysis)|\(.implementation)|\(.scrutiny)"')"
eq "  ... and sum to the span in milliseconds" true "$(q "$OUT" '[.sessions[] | ((.states | map(. * 1000 | round) | add) == (.span_s * 1000 | round))] | all')"

echo "== a run still in progress on the green head =="
seed; fresh; prs "acme/widgets#21 $MERGE"
db '(.runs[] | select(.databaseId == 104)) |= (.status = "in_progress" | .conclusion = "")'
OUT=$(compute)
eq "dispatch_to_green_min is bound, at the latest finish so far" "130 bound" "$(fig "$OUT" dispatch_to_green_min)"
eq "  ... outside_share_pct and review_share_pct are bound" "bound bound" "$(q "$OUT" '"\(.figures.outside_share_pct.state) \(.figures.review_share_pct.state)"')"
eq "  ... dispatch_to_merge_min stays measured" "150 measured" "$(fig "$OUT" dispatch_to_merge_min)"
eq "  ... failing_heads counts up to that head, a lower bound" "2 bound" "$(fig "$OUT" failing_heads)"
eq "  ... and no bound figure is listed as missing" "" "$(q "$OUT" '[.missing[] | select(.figure | test("green|share|failing"))] | map(.figure) | join(",")')"
db '(.runs[] | select(.databaseId == 104)) |= (.status = "completed" | .conclusion = "failure")'
OUT=$(compute)
eq "a green head that turns red leaves no green" "null not recoverable" "$(fig "$OUT" dispatch_to_green_min)"
eq "  ... and every failing head counts" "3 measured" "$(fig "$OUT" failing_heads)"

echo "== compute: the entry's fields =="
seed; fresh; prs "acme/widgets#21 $MERGE"
OUT=$(compute); eq "compute exits 0" 0 $?
eq "one line of output" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
eq "every field of the entry, in order" "schema key captured_at topic record unit milestone plan_shape pulls opened dispatch niwa.dispatch.id figures sessions tokens complete missing" \
    "$(q "$OUT" 'keys_unsorted | join(" ")')"
eq "schema" "unit-cost/1" "$(q "$OUT" .schema)"
eq "every baseline figure" "dispatch_to_green_min dispatch_to_merge_min writing_code_min review_min outside_share_pct review_share_pct panel_rounds failing_heads sessions_without_done summed_session_span_min minutes_per_unit" \
    "$(q "$OUT" '.figures | keys_unsorted | join(" ")')"
eq "each figure is {value, raw, state, source}" true "$(q "$OUT" '[.figures[] | keys_unsorted == ["value", "raw", "state", "source"]] | all')"
eq "each per-session entry carries its fields and no name" true \
    "$(q "$OUT" '[.sessions[] | keys_unsorted == ["index", "template", "unit_session", "done", "span_s", "states", "figures"]] | all')"
eq "  ... and each per-session figure is {value, raw, state, source}" true \
    "$(q "$OUT" '[.sessions[].figures[] | keys_unsorted == ["value", "raw", "state", "source"]] | all')"
eq "  ... in byte order of the names: deliver, execute, two work-on children, scope" "deliver execute work-on work-on scope|false false true true false" \
    "$(q "$OUT" '"\([.sessions[].template] | join(" "))|\([.sessions[].unit_session | tostring] | join(" "))"')"
eq "every state and source is from its closed set" true "$(q "$OUT" '[.figures[], .sessions[].figures[]
    | (.state | IN("measured", "bound", "not recoverable", "not applicable"))
      and (.source | IN("koto-request", "job-state", "koto-state", "verdict-ledger", "transcripts", "github-pr", "github-runs", "derived"))] | all')"
eq "a value is null unless measured or bound" true "$(q "$OUT" '[.figures[], .sessions[].figures[] | (.value == null) or (.state == "measured" or .state == "bound")] | all')"
eq "complete is false while any figure is missing" false "$(q "$OUT" .complete)"
eq "without the record's facts the milestone is not recoverable" "null|not recoverable|no source" \
    "$(q "$OUT" '"\(.record)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"')"
grep -q 'execute-x\|deliver-x\|scope-x\|issue-1\|/work/inst\|work-inst\|r_dispatch_x\|0a1b2c3d-77aa\|0f9e8d7c\|5b6c7d8e\|feat/x' <<<"$OUT" \
    && bad "no session name, request id, session id, branch or path is in the entry" "$OUT" || ok "no session name, request id, session id, branch or path is in the entry"
printf 'acme/widgets#21 %s\n' "$MERGE" >"$T/prs"
bash "$UC" compute --archive "$A" --topic feat-y --prs-file "$T/prs" >/dev/null 2>&1; eq "an archive not named for the topic is refused" 65 $?
bash "$UC" compute --archive "$A" --topic 'Feat X' --prs-file "$T/prs" >/dev/null 2>&1; eq "a topic outside the grammar is a usage error" 64 $?
bash "$UC" capture --archive "$A" --topic feat-x --prs-file "$T/prs" >/dev/null 2>&1; eq "capture without a session is a usage error" 64 $?

echo "== figures not taken =="
fresh; prs "acme/widgets#21 $MERGE"
OUT=$(KOTO_REQUESTS="$T/none" compute)
eq "with the request gone, dispatch comes from the job and green moves with it" "130 measured" "$(fig "$OUT" dispatch_to_green_min)"
rm -rf "$A/job/state.json" "$A/claude-projects"
OUT=$(KOTO_REQUESTS="$T/none" compute)
eq "with no dispatch, both dispatch figures and both shares are not recoverable" "not recoverable not recoverable not recoverable not recoverable" \
    "$(q "$OUT" '[.figures.dispatch_to_green_min, .figures.dispatch_to_merge_min, .figures.outside_share_pct, .figures.review_share_pct] | map(.state) | join(" ")')"
eq "  ... each listed, no source" "dispatch:no source,dispatch_to_green_min:no source,dispatch_to_merge_min:no source,outside_share_pct:no source,review_share_pct:no source" \
    "$(q "$OUT" '[.missing[] | select(.figure | test("^dispatch|share")) | "\(.figure):\(.reason)"] | join(",")')"
eq "  ... and the koto figures are still measured" "40.5 measured" "$(fig "$OUT" writing_code_min)"
eq "every figure not taken is listed with a closed-list reason" true \
    "$(printf '%s' "$OUT" | jq --argjson r "$REASONS" '. as $e | [.figures | to_entries[] | select(.value.state == "not recoverable") | .key as $k
        | any($e.missing[]; .figure == $k and (.reason as $x | $r | index([$x]) != null))] | all')"
eq "every missing reason is from the closed list" true "$(printf '%s' "$OUT" | jq --argjson r "$REASONS" '[.missing[].reason as $x | $r | index([$x]) != null] | all')"
fresh
rm -f "$A/koto/execute-x.o-issue-1/ctx/verdict_ledger.json" "$A/koto/execute-x.o-issue-2/ctx/verdict_ledger.json"
eq "with no ledger in any unit session, panel_rounds is not recoverable" "null not recoverable|no source" \
    "$(compute | jq -r '"\(.figures.panel_rounds.value) \(.figures.panel_rounds.state)|\([.missing[] | select(.figure == "panel_rounds") | .reason][0])"')"
fresh
rm -rf "$A/koto/execute-x.o-issue-1" "$A/koto/execute-x.o-issue-2"
OUT=$(compute)
eq "with no unit session, the session figures are not applicable" "not applicable" \
    "$(q "$OUT" '[.figures.writing_code_min, .figures.review_min, .figures.outside_share_pct, .figures.review_share_pct, .figures.panel_rounds,
                  .figures.sessions_without_done, .figures.summed_session_span_min, .figures.minutes_per_unit] | map(.state) | unique | join(" ")')"
eq "  ... and the GitHub figures still measured" "130 measured|2 measured" "$(fig "$OUT" dispatch_to_green_min)|$(fig "$OUT" failing_heads)"

echo "== plan shape =="
# mkarch: an archive with a job and no sessions; mksess <name> <template>
# <source file> [mode] [plan]: one session in it.
mkarch() { rm -rf "$T/p"; A="$T/p/$KEY"; mkdir -p "$A/job" "$A/koto"; printf '{"createdAt":"2026-10-01T08:59:58.000Z"}\n' >"$A/job/state.json"; }
mksess() {
    local d="$A/koto/$1"
    mkdir -p "$d/ctx"
    jq -nc --arg w "$1" --arg t "$2" --arg f "$3" '{schema_version: 1, workflow: $w, template_name: $t, template_source_file: $f}' >"$d/koto-$1.state.jsonl"
    printf '{"seq":1,"timestamp":"2026-10-01T09:00:00.000Z","type":"transitioned","payload":{"from":null,"to":"entry"}}\n' >>"$d/koto-$1.state.jsonl"
    [ -z "${4:-}" ] || jq -nc --arg m "$4" '{seq: 2, timestamp: "2026-10-01T09:00:01.000Z", type: "evidence_submitted", payload: {state: "entry", fields: {mode: $m}}}' >>"$d/koto-$1.state.jsonl"
    [ -z "${5:-}" ] || printf '%s' "$5" >"$d/ctx/plan_execution_mode"
}
shape() { compute | jq -r '"\(.plan_shape.value // "null") \(.plan_shape.state)"'; }
prs "acme/widgets#21 $MERGE"
for m in single-pr multi-pr coordinated; do
    mkarch; mksess deliver-x deliver deliver.md "" "$m"; mksess scope-x scope scope.md
    eq "a /deliver unit in $m mode" "$m measured" "$(shape)"
done
mkarch; mksess execute-x execute-coordinated execute-coordinated.md
eq "an /execute unit from execute-coordinated.md" "coordinated measured" "$(shape)"
mkarch; mksess execute-x execute execute.md; mksess execute-x.o-a work-on work-on.md plan_backed
eq "an /execute unit from execute.md" "single-pr measured" "$(shape)"
mkarch; mksess task_x work-on work-on.md plan_backed
eq "a /work-on unit in plan_backed mode" "multi-pr measured" "$(shape)"
mkarch; mksess issue_12 work-on work-on.md issue_backed
eq "a /work-on unit in issue_backed mode" "issue measured" "$(shape)"
eq "  ... and minutes_per_unit is not applicable" "not applicable" "$(compute | jq -r '.figures.minutes_per_unit.state')"
mkarch; mksess task_y work-on work-on.md free_form
eq "a /work-on unit in free_form mode" "issue measured" "$(shape)"
mkarch; mksess release-x release release.md
eq "a unit with none of those sessions" "none measured" "$(shape)"
mkarch
eq "a unit with no sessions at all" "none measured" "$(shape)"
mkarch; mksess deliver-x deliver deliver.md; mksess execute-x execute execute.md
eq "a /deliver session with no plan_execution_mode" "null not recoverable" "$(shape)"
eq "  ... listed as missing, no source" "no source" "$(compute | jq -r '[.missing[] | select(.figure == "plan_shape") | .reason][0]')"
eq "  ... and minutes_per_unit is not recoverable with it" "not recoverable" "$(compute | jq -r '.figures.minutes_per_unit.state')"
mkarch; mksess deliver-x deliver deliver.md "" weekly
eq "a /deliver session whose value is outside the set" "null not recoverable" "$(shape)"
mkarch; mksess deliver-x deliver deliver.md "" coordinated
mksess deliver-x.o-a work-on work-on.md plan_backed; mksess deliver-x.o-b work-on work-on.md plan_backed
eq "a coordinated /deliver with plan_backed /work-on children" "coordinated measured" "$(shape)"
mkarch; mksess deliver-x deliver deliver.md "" single-pr
printf 'this header was cut off\n' >"$T/hdr"; sed 1d "$A/koto/deliver-x/koto-deliver-x.state.jsonl" >>"$T/hdr"
cp "$T/hdr" "$A/koto/deliver-x/koto-deliver-x.state.jsonl"
eq "a session whose header can't be read (it may be the /deliver)" "null not recoverable" "$(shape)"
eq "  ... invalid input" "invalid input" "$(compute | jq -r '[.missing[] | select(.figure == "plan_shape") | .reason][0]')"
mkarch; mksess execute-x execute execute.md
mkdir -p "$A/koto/deliver-x"
printf '{"schema_version":1,"workflow":"deliver-x","template_name":7}\n' >"$A/koto/deliver-x/koto-deliver-x.state.jsonl"
eq "  ... and one whose template_name isn't a string" "null not recoverable" "$(shape)"

echo "== milestone =="
fresh
ms() { # ms <unit-json>: "<unit>|<milestone value>|<state>|<reason>"
    printf '%s' "$1" >"$T/unit.json"
    compute --unit-json "$T/unit.json" | jq -c -r '"\(.unit)|\(.milestone.value | tojson)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone" or .figure == "record" or .figure == "unit") | "\(.figure):\(.reason)"] | join(","))"'
}
# rj <unit> [reason]: the roadmap record's facts with that Unit (null when
# empty) and the reason it wasn't read.
rj() {
    jq -nc --arg u "$1" --arg r "${2:-}" '{scope: "roadmap", name: "x", repo: "acme/widgets",
        unit: (if $u == "" then null else $u end)} + (if $r == "" then {} else {unit_reason: $r} end)'
}
eq "Unit Feature 4" 'Feature 4|{"roadmap":"ROADMAP-x","tag":"Feature 4"}|measured|' "$(ms "$(rj 'Feature 4')")"
eq "Unit Feature 4: Title" 'Feature 4|{"roadmap":"ROADMAP-x","tag":"Feature 4"}|measured|' "$(ms "$(rj 'Feature 4: Title')")"
eq "Unit Spike: x" 'Spike|{"roadmap":"ROADMAP-x","tag":"Spike"}|measured|' "$(ms "$(rj 'Spike: x')")"
eq "Unit acme/gadgets#12" 'acme/gadgets#12|"none"|measured|' "$(ms "$(rj 'acme/gadgets#12')")"
eq "Unit #12" '#12|"none"|measured|' "$(ms "$(rj '#12')")"
eq "a discipline record" 'Feature 4|"none"|measured|' "$(ms '{"scope":"discipline","name":"ci","repo":"acme/widgets","unit":"Feature 4"}')"
eq "a failed run-facts read" 'null|null|not recoverable|record:read failed,milestone:read failed' "$(ms '{"unit_reason":"read failed"}')"
eq "a failed Holdings read" 'null|null|not recoverable|milestone:read failed' "$(ms "$(rj '' 'read failed')")"
eq "a Holdings read with no row for the topic" 'null|null|not recoverable|milestone:no source' "$(ms "$(rj '' 'no source')")"
eq "a Unit outside the safety pattern" 'null|null|not recoverable|milestone:invalid input' "$(ms "$(rj 'Feature 4; rm -rf x')")"
eq "  ... a backtick" 'null|null|not recoverable|milestone:invalid input' "$(ms "$(rj 'Feat`ure')")"
eq "  ... one over 64 characters" 'null|null|not recoverable|milestone:invalid input' \
    "$(ms "$(rj 'F1234567890123456789012345678901234567890123456789012345678901234')")"
eq "record facts that aren't facts" 'null|null|not recoverable|record:invalid input,milestone:invalid input' "$(ms '{"scope":"roadmap","name":"../x","repo":"acme/widgets","unit":"Feature 4"}')"

echo "== milestone, through the capture's own reads =="
fresh; prs "acme/widgets#21 $MERGE"
seed; R2=$(record_json roadmap x | jq -c --argjson h "$(holding other-topic '{"unit": "Feature 9"}')" '.holdings = [$h]')
seed_session "$S" "$R2" 2026-10-01T08:00:00Z
capture; eq "a record with no row for the topic still posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... the milestone not recoverable, no source" "not recoverable|no source" \
    "$(jq -r '"\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
seed; fresh
export KOTO_NO_LIST_PREFIX=1
capture; eq "a failed Holdings read (and so a failed post) exits 1" 1 $?
unset KOTO_NO_LIST_PREFIX
eq "  ... the archive copy says read failed" "not recoverable|read failed" \
    "$(jq -r '"\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
eq "  ... and the last stderr line is a fixed string" "unit-cost: the post failed (state-entry exit 2)" "$(tail -n 1 "$T/cap.err")"
seed; fresh
NOREC=coordinate-roadmap-x-20261001T090000Z
log_new "$NOREC" "$(roadmap_vars x)"
bash "$UC" capture --session "$NOREC" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "a failed run-facts read (no found record) exits 1" 1 $?
eq "  ... the archive copy has no record and the milestone read failed" "null|not recoverable|read failed" \
    "$(jq -r '"\(.record)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
rm -rf "${KOTO_STORE:?}/sessions/$NOREC"

echo "== dispatch =="
seed; fresh; prs "acme/widgets#21 $MERGE"
disp() { compute | jq -r '"\(.dispatch.value) \(.dispatch.state) \(.dispatch.source)"'; }
eq "from the request no archived session asked for" "2026-10-01T09:00:00.000Z measured koto-request" "$(disp)"
eq "  ... reading three main session transcripts, the relocated copy one of them" 3 "$(compute | jq -r .dispatch.jobs)"
eq "with no request on the host, from the job" "2026-10-01T09:00:02.000Z measured job-state" "$(KOTO_REQUESTS="$T/none" disp)"
mkdir -p "$T/nested-only"; cp -R "$FX/requests/r_nested_x" "$T/nested-only/"
eq "a request an archived session asked for is not the dispatch" "2026-10-01T09:00:02.000Z measured job-state" "$(KOTO_REQUESTS="$T/nested-only" disp)"
rm -f "$A/job/state.json"
eq "with no job record either, from the earliest main session transcript's first event" "2026-10-01T09:00:05.000Z measured job-state" "$(KOTO_REQUESTS="$T/none" disp)"
rm -rf "$A/claude-projects"
eq "with none of the three, not recoverable" "null not recoverable koto-request" "$(KOTO_REQUESTS="$T/none" disp)"
eq "  ... and listed" "no source" "$(KOTO_REQUESTS="$T/none" compute | jq -r '[.missing[] | select(.figure == "dispatch") | .reason][0]')"
# mkjobs <request created_at>: a unit that ran as two jobs. Its koto session
# names request r_jobs (made by the coordinator at that time), the torn-down
# job's record says 14:21, and two main session transcripts start at 08:12
# and 14:21.
mkjobs() {
    rm -rf "$T/j" "$T/jreq"
    A="$T/j/$KEY"
    mkdir -p "$A/job" "$A/koto/w" "$A/claude-projects/-w-inst-j" "$T/jreq/r_jobs"
    printf '{"createdAt":"2026-10-01T14:21:00.000Z","sessionId":"0a1b2c3d-0002"}\n' >"$A/job/state.json"
    printf '{"schema_version":1,"workflow":"w","template_name":"work-on","template_source_file":"work-on.md"}\n' >"$A/koto/w/koto-w.state.jsonl"
    printf 'request_id = "r_jobs"\n' >"$A/koto/w/request-leg.toml"
    printf '{"created_at":"%s","requested_by":"coordinator"}\n' "$1" >"$T/jreq/r_jobs/request.jsonl"
    printf '{"type":"summary"}\n{"type":"user","timestamp":"2026-10-01T08:12:00.000Z"}\n' >"$A/claude-projects/-w-inst-j/0a1b2c3d-0001.jsonl"
    printf '{"type":"user","timestamp":"2026-10-01T14:21:00.000Z"}\n' >"$A/claude-projects/-w-inst-j/0a1b2c3d-0002.jsonl"
}
jdisp() { KOTO_REQUESTS="$T/jreq" compute | jq -r '"\(.dispatch.value) \(.dispatch.source) \(.dispatch.jobs)"'; }
mkjobs 2026-10-01T14:20:00.000Z
eq "two jobs, transcripts from 08:12 and 14:21, job record 14:21, request 14:20: the earliest job" "2026-10-01T08:12:00.000Z job-state 2" "$(jdisp)"
mkjobs 2026-10-01T08:00:00.000Z
eq "  ... with the request at 08:00 instead, the request" "2026-10-01T08:00:00.000Z koto-request 2" "$(jdisp)"
mkjobs 2026-10-01T08:12:00Z
eq "  ... a request tied with the earliest transcript wins the tie, whatever its fraction" "2026-10-01T08:12:00Z koto-request 2" "$(jdisp)"
mkjobs 2026-10-01T14:20:00.000Z
printf '{"type":"user","timestamp":"2026-10-01T08:11:59.5Z"}\n' >>"$A/claude-projects/-w-inst-j/0a1b2c3d-0002.jsonl"
eq "  ... a transcript's first event is its earliest timestamp, not its first line's" "2026-10-01T08:11:59.5Z job-state 2" "$(jdisp)"

echo "== tokens =="
fresh
PD="$A/claude-projects/-work-inst-feat-x"
tok() { compute | jq -c -r ".tokens.$1 | \"\(.messages) \(.input) \(.output) \(.cache_creation) \(.cache_read) \(.state)\""; }
eq "the worker row: its main transcript and subagents/ in both directories, by message id" "5 23 110 150 140 measured" "$(tok worker)"
grep -q '"id":"msg_w3"' "$PD/0a1b2c3d-77aa.jsonl" && ok "  ... the example holds an assistant line with no usage (msg_w3), not counted" \
    || bad "  ... the example holds an assistant line with no usage (msg_w3), not counted"
eq "the nested row: the workflow, the second job and the relocated copy's own message, not its repeats" "3 5 18 0 40 measured" "$(tok nested)"
W="$PD/0a1b2c3d-77aa.jsonl"
for u in '"output_tokens":50,"cache_read_input_tokens":5' '"output_tokens":80,"cache_read_input_tokens":5' '"output_tokens":60,"cache_read_input_tokens":5'; do
    printf '{"type":"assistant","message":{"id":"msg_t","usage":{"input_tokens":1,%s}}}\n' "$u" >>"$W"
done
eq "an id written three times, output rising then falling, counts once at its largest" "6 24 190 150 145 measured" "$(tok worker)"
printf '{"type":"assistant","message":{"id":7,"usage":{"output_tokens":1000}}}\n{"type":"assistant","message":{"usage":{"output_tokens":1000}}}\n' >>"$W"
eq "an assistant line with a non-string or no id is skipped" "6 24 190 150 145 measured" "$(tok worker)"
printf '{"type":"assistant","message":{"id":"msg_nu"}}\n{"type":"assistant","message":{"id":"msg_nu2","usage":"many"}}\n' >>"$W"
eq "an assistant line whose usage isn't an object is not a message" "6 24 190 150 145 measured" "$(tok worker)"
printf 'FL{"type":"assistant","message":{"id":"msg_forged","usage":{"output_tokens":5000}}}\n' >>"$PD/0f9e8d7c-11cc.jsonl"
eq "a line shaped like the scan's own file marker is a line that isn't JSON, in its own row" "6 24 190 150 145 measured|invalid input" \
    "$(compute | jq -r '"\(.tokens.worker | "\(.messages) \(.input) \(.output) \(.cache_creation) \(.cache_read) \(.state)")|\([.missing[] | select(.figure == "tokens.nested") | .reason][0])"')"
fresh
printf '{"type":"assistant","message":{"id":"msg_n2","usage":{"output_tokens":1}}\n' >>"$A/claude-projects/-work-inst-feat-x/0a1b2c3d-77aa/workflows/flow-1.jsonl"
eq "a line that isn't JSON makes its row not recoverable" "null null null null null not recoverable" "$(tok nested)"
eq "  ... with reason invalid input, the other row kept" "invalid input|measured" \
    "$(compute | jq -r '"\([.missing[] | select(.figure == "tokens.nested") | .reason][0])|\(.tokens.worker.state)"')"
# mkmoved: a worker that moved into a worktree. Its main transcript in the
# instance's directory (two messages), three subagents in the worktree's
# directory, and the relocated copy there: it repeats both of the worker's
# ids, one at a larger usage, and adds one message of its own.
mkmoved() {
    rm -rf "$T/m"
    A="$T/m/$KEY"
    local r="$A/claude-projects/-w-inst-m" wt="$A/claude-projects/-w-inst-m-wt"
    mkdir -p "$A/job" "$r" "$wt/0a1b2c3d-0003/subagents"
    printf '{"createdAt":"2026-10-01T09:00:00.000Z","sessionId":"0a1b2c3d-0003"}\n' >"$A/job/state.json"
    printf '{"type":"assistant","message":{"id":"wa","usage":{"input_tokens":1,"output_tokens":10}}}\n{"type":"assistant","message":{"id":"wb","usage":{"input_tokens":2,"output_tokens":20}}}\n' \
        >"$r/0a1b2c3d-0003.jsonl"
    for i in 1 2 3; do
        printf '{"type":"assistant","message":{"id":"s%s","usage":{"input_tokens":1,"output_tokens":%s}}}\n' "$i" "$i" >"$wt/0a1b2c3d-0003/subagents/agent-$i.jsonl"
    done
    printf '{"type":"relocated"}\n{"type":"assistant","message":{"id":"wa","usage":{"input_tokens":1,"output_tokens":99}}}\n{"type":"assistant","message":{"id":"wb","usage":{"input_tokens":2,"output_tokens":20}}}\n{"type":"assistant","message":{"id":"rc","usage":{"input_tokens":4,"output_tokens":40}}}\n' \
        >"$wt/0a1b2c3d-0004.jsonl"
}
mkmoved
eq "a moved worker: its main transcript and three subagents in the worktree's directory" "5 6 36 0 0 measured" "$(tok worker)"
eq "  ... nested is only the relocated copy's own message: a repeated id counts once, in the worker row" "1 4 40 0 0 measured" "$(tok nested)"

echo "== pull requests =="
fresh; seed
prs "acme/widgets#21 $MERGE" "acme/gadgets#5 $MERGE2"
OUT=$(compute)
eq "a verdict naming two pull requests in two repositories records both, in its order, via holding" \
    '[{"repo":"acme/widgets","number":21,"merge_commit":"'"$MERGE"'","merged_at":"2026-10-01T11:30:00Z","via":"holding"},{"repo":"acme/gadgets","number":5,"merge_commit":"'"$MERGE2"'","merged_at":"2026-10-01T11:20:00Z","via":"holding"}]' \
    "$(q "$OUT" '.pulls[0:2] | tojson')"
eq "  ... then the example's two credited pull requests, by merge time, via session" \
    '[{"repo":"acme/widgets","number":23,"merge_commit":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","merged_at":"2026-10-01T11:10:00Z","via":"session"},{"repo":"acme/gadgets","number":7,"merge_commit":"4545454545454545454545454545454545454545","merged_at":"2026-10-01T11:25:00Z","via":"session"}]' \
    "$(q "$OUT" '.pulls[2:] | tojson')"
eq "  ... each carrying the unit's one plan shape" "single-pr measured" "$(q "$OUT" '"\(.plan_shape.value) \(.plan_shape.state)"')"
eq "  ... merge is the later of the two" "150 measured" "$(fig "$OUT" dispatch_to_merge_min)"
eq "  ... and green waits on both: the second has no green head" "null not recoverable" "$(fig "$OUT" dispatch_to_green_min)"
eq "a pull request the verdict doesn't name is absent" 0 "$(q "$OUT" '[.pulls[] | select(.number == 22)] | length')"
prs "acme/widgets#21 $MERGE" "acme/widgets#0 $MERGE"
OUT=$(compute)
eq "a verdict line outside the shapes is left out, invalid input" "3|invalid input" \
    "$(q "$OUT" '"\(.pulls | length)|\([.missing[] | select(.figure == "pulls") | .reason][0])"')"
eq "  ... and the GitHub figures, over an incomplete set, are invalid input" "invalid input invalid input invalid input" \
    "$(q "$OUT" '[.missing[] | select(.figure == "dispatch_to_green_min" or .figure == "dispatch_to_merge_min" or .figure == "failing_heads") | .reason] | join(" ")')"

echo "== hostile input =="
seed; fresh; prs "acme/widgets#21 $MERGE"
printf 'request_id = "../../etc"\n' >"$A/koto/deliver-x/request-leg.toml"
eq "a request id with ../ builds no path: dispatch is not recoverable" "null not recoverable koto-request|invalid input" \
    "$(compute | jq -r '"\(.dispatch.value) \(.dispatch.state) \(.dispatch.source)|\([.missing[] | select(.figure == "dispatch") | .reason][0])"')"
fresh; prs "acme/widgets#21 $MERGE" "-x/y#3 $MERGE"
eq "a verdict repository starting with -" "3|invalid input|invalid input" \
    "$(compute | jq -r '"\(.pulls | length)|\([.missing[] | select(.figure == "pulls") | .reason][0])|\([.missing[] | select(.figure == "failing_heads") | .reason][0])"')"
prs "acme/widgets#21 $MERGE"
db '(.prs[] | select(.number == 21)).headRefName = "-x"'
OUT=$(compute)
eq "a head branch starting with -: green and failing heads are invalid input" "invalid input|invalid input|150 measured" \
    "$(q "$OUT" '"\([.missing[] | select(.figure == "dispatch_to_green_min") | .reason][0])|\([.missing[] | select(.figure == "failing_heads") | .reason][0])|\(.figures.dispatch_to_merge_min.value) \(.figures.dispatch_to_merge_min.state)"')"
grep -q -- 'run list .*--branch -x' "$GH_DB.calls" && bad "  ... and no run list is made for it" || ok "  ... and no run list is made for it"
seed; fresh
# The second head's page of runs comes back outside its shape: the first head
# (one failing run) is counted, and the count is a floor naming the reason.
db '.runs_page_bad = {"8888888888888888888888888888888888888888": 1}'
eq "a head whose runs come back outside their shape: a floor over the heads read, invalid input" "1 bound|invalid input" \
    "$(compute | jq -r '"\(.figures.failing_heads.value) \(.figures.failing_heads.state)|\([.missing[] | select(.figure == "failing_heads") | .reason][0])"')"
seed; fresh
printf '{"seq":12,"timestamp":"2026-10-01T10:2\n' >>"$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl"
OUT=$(compute)
eq "a state log line that isn't JSON: the koto figures are invalid input" "invalid input|invalid input|invalid input" \
    "$(q "$OUT" '"\([.missing[] | select(.figure == "writing_code_min") | .reason][0])|\([.missing[] | select(.figure == "outside_share_pct") | .reason][0])|\([.missing[] | select(.figure == "sessions") | .reason][0])"')"
eq "  ... that session's states are not kept, the others are" "null|9290" "$(q "$OUT" '"\(.sessions[2].states)|\(.sessions[0].span_s)"')"
eq "  ... and the GitHub figures are still measured" "130 measured" "$(fig "$OUT" dispatch_to_green_min)"
fresh
jq -c 'if .seq == 6 then .payload.to = "Scrutiny; rm -rf x" else . end' "$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl" >"$T/s1"
cp "$T/s1" "$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl"
eq "a state name outside its shape: invalid input" "invalid input" "$(compute | jq -r '[.missing[] | select(.figure == "review_min") | .reason][0]')"
fresh
printf '{"history":[{"panel":"Review; x","round":1}]}\n' >"$A/koto/execute-x.o-issue-1/ctx/verdict_ledger.json"
eq "a ledger panel outside its shape: panel_rounds invalid input" "null not recoverable|invalid input" \
    "$(compute | jq -r '"\(.figures.panel_rounds.value) \(.figures.panel_rounds.state)|\([.missing[] | select(.figure == "panel_rounds") | .reason][0])"')"

echo "== planted secrets, prompt text and paths =="
seed; fresh; prs "acme/widgets#21 $MERGE"
# Built at run time, so this file holds none of the shapes it plants.
KEYLIKE="gh""p_$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30)"
APIKEY="sk-""ant-$(printf 'z%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
HOMEP="/ho""me/someone/notes.md"
PROMPT="PLANTED PROMPT: summarise the secret roadmap"
jq -nc --arg k "$KEYLIKE" --arg h "$HOMEP" --arg p "$PROMPT" '{type: "user", message: {role: "user", content: "\($p) \($k) \($h)"}, cwd: $h, gitBranch: $k}' \
    >>"$A/claude-projects/-work-inst-feat-x/0a1b2c3d-77aa.jsonl"
jq -nc --arg k "$APIKEY" --arg h "$HOMEP" '{type: "assistant", message: {id: "msg_p1", content: [{type: "text", text: "\($k) \($h)"}], usage: {output_tokens: 1}}}' \
    >>"$A/claude-projects/-work-inst-feat-x/0a1b2c3d-77aa/subagents/agent-a1.jsonl"
jq -nc --arg k "$KEYLIKE" --arg h "$HOMEP" --arg p "$PROMPT" '{seq: 9, timestamp: "2026-10-01T09:20:15.000Z", type: "evidence_submitted",
    payload: {state: "analysis", fields: {note: "\($p) \($k) \($h)"}}}' >>"$A/koto/execute-x.o-issue-1/koto-execute-x.o-issue-1.state.jsonl"
printf '%s\n%s\n%s\n' "$PROMPT" "$KEYLIKE" "$HOMEP" >"$A/koto/execute-x.o-issue-1/ctx/notes.md"
OUT=$(compute)
for s in "$KEYLIKE" "$APIKEY" "$HOMEP" "PLANTED PROMPT" "someone" "notes.md"; do
    case "$OUT" in *"$s"*) bad "no planted string is in the entry" "$s" ;; *) ok "no planted string is in the entry (${s%"${s#??????}"}...)" ;; esac
done
eq "  ... the planted lines change no figure" same "$(same_as "$OUT" "$FX/expected-plan.json")"

echo "== symlinks in the archive =="
seed; fresh
printf '{"type":"assistant","message":{"id":"msg_far","usage":{"output_tokens":5000}}}\n' >"$T/far.jsonl"
ln -s "$T/far.jsonl" "$A/claude-projects/-work-inst-feat-x/linked.jsonl"
ln -s "$T/far.jsonl" "$A/claude-projects/-work-inst-feat-x/0a1b2c3d-77aa/subagents/agent-linked.jsonl"
ln -s "$T/far.jsonl" "$A/claude-projects/-work-inst-feat-x/0a1b2c3d-1234.jsonl"
mkdir -p "$T/fardir"; cp "$T/far.jsonl" "$T/fardir/0a1b2c3d-77aa.jsonl"
ln -s "$T/fardir" "$A/claude-projects/-work-inst-feat-x-far"
eq "a symlink in claude-projects/, a linked file or a linked directory, is skipped" "5 110|3 18|3" \
    "$(compute | jq -r '"\(.tokens.worker.messages) \(.tokens.worker.output)|\(.tokens.nested.messages) \(.tokens.nested.output)|\(.dispatch.jobs)"')"
mkdir -p "$T/elsewhere-session"; cp "$A/koto/scope-x/koto-scope-x.state.jsonl" "$T/elsewhere-session/koto-zz.state.jsonl"
ln -s "$T/elsewhere-session" "$A/koto/zz"
eq "a symlinked session directory is skipped" 5 "$(compute | jq '.sessions | length')"
rm "$A/koto/zz"; mv "$A/koto/scope-x/koto-scope-x.state.jsonl" "$T/scope.jsonl"; ln -s "$T/scope.jsonl" "$A/koto/scope-x/koto-scope-x.state.jsonl"
eq "a symlinked state log is skipped" 4 "$(compute | jq '.sessions | length')"

echo "== a public host =="
seed; fresh
db '.prs += [{repo: "acme/secret", number: 9, title: "x", body: "", state: "MERGED", isDraft: false, isCrossRepository: false, baseRefName: "main",
      headRefName: "feat/x", headRefOid: $m, author: "alice", editor: null, mergedAt: "2026-10-01T11:00:00Z", mergeCommit: $m},
    {repo: "acme/hidden", number: 4, title: "x", body: "", state: "MERGED", isDraft: false, isCrossRepository: false, baseRefName: "main",
      headRefName: "feat/x", headRefOid: $m, author: "alice", editor: null, mergedAt: "2026-10-01T11:00:00Z", mergeCommit: $m}]' --arg m "$MERGE2"
prs "acme/widgets#21 $MERGE" "acme/secret#9 $MERGE2" "acme/hidden#4 $MERGE2" "acme/gadgets#5 $MERGE2"
db '.fail = [{match: "repos/acme/gadgets --jq .private", rc: 1, stderr: "HTTP 502"}]'
printf '%s' "$(rj 'acme/secret#12')" >"$T/unit.json"
OUT=$(compute --unit-json "$T/unit.json")
eq "a private repository's pull request, an unreadable one's and a failed lookup's are written as not public, credited or not" \
    '[{"repo":"acme/widgets","number":21},{"repo":"not public"},{"repo":"not public"},{"repo":"not public"},{"repo":"acme/widgets","number":23},{"repo":"not public"}]' \
    "$(q "$OUT" '[.pulls[] | {repo, number} | with_entries(select(.value != null))] | tojson')"
eq "  ... a not-public pull request carries its repo alone, no via" true "$(q "$OUT" '[.pulls[] | select(.repo == "not public") | keys == ["repo"]] | all')"
eq "  ... a Unit naming a private repository is not public" '"not public"|"none"' "$(q "$OUT" '"\(.unit | tojson)|\(.milestone.value | tojson)"')"
case "$OUT" in *secret* | *hidden* | *gadgets*) bad "  ... and no such repository is named anywhere" "$OUT" ;; *) ok "  ... and no such repository is named anywhere" ;; esac
eq "  ... their figures kept: merge is the latest of all four" "150 measured" "$(fig "$OUT" dispatch_to_merge_min)"
db '.fail = []'
printf '%s' "$(rj 'acme/gadgets#12')" >"$T/unit.json"
eq "a Unit naming a public repository is kept" "acme/gadgets#12" "$(compute --unit-json "$T/unit.json" | jq -r .unit)"
jq -nc '{scope: "roadmap", name: "x", repo: "acme/secret", unit: "acme/secret#12"}' >"$T/unit.json"
OUT=$(compute --unit-json "$T/unit.json")
eq "on a private host every pull request and the Unit are kept" "acme/widgets acme/secret acme/hidden acme/gadgets acme/widgets acme/gadgets|acme/secret#12" \
    "$(q "$OUT" '"\([.pulls[].repo] | join(" "))|\(.unit)"')"
reset_calls
compute --unit-json "$T/unit.json" >/dev/null
eq "  ... with no lookup but the host's" "api --method GET repos/acme/secret --jq .private" "$(grep -- '--jq .private' "$GH_DB.calls")"
reset_calls
prs "acme/widgets#21 $MERGE"
compute >/dev/null
eq "with no record known, the host counts as public: each repository is looked up, the credited ones' too" \
    "api --method GET repos/acme/widgets --jq .private|api --method GET repos/acme/gadgets --jq .private" \
    "$(grep -- '--jq .private' "$GH_DB.calls" | tr '\n' '|' | sed 's/|$//')"

echo "== failing heads over every head =="
# A pull request with 65 heads (#40): every odd head has a failing run and
# every even one a cancelled run (neither failing nor green), head 30 holds 250
# runs over three pages of 100 with one failure among them, and head 65 is
# green. A 66th head after it has a failing run nobody reads.
seed; fresh
hsha() { printf '%040x' "$((0xabc000 + $1))"; }
HEADS40=$(for ((k = 1; k <= 66; k++)); do hsha "$k"; echo; done | jq -R . | jq -s -c .)
RUNS40=$(jq -n -c --argjson hs "$HEADS40" '
    [range(0; 66) as $i | ($i + 1) as $k | $hs[$i] as $h
     | if $k == 30 then (range(0; 250) as $j | {databaseId: (40000 + $j), headSha: $h, conclusion: (if $j == 7 then "failure" else "success" end)})
       elif $k == 65 then {databaseId: (41000 + $k), headSha: $h, conclusion: "success"}
       elif $k == 66 then {databaseId: (41000 + $k), headSha: $h, conclusion: "failure"}
       elif ($k % 2) == 1 then {databaseId: (41000 + $k), headSha: $h, conclusion: "failure"}
       else {databaseId: (41000 + $k), headSha: $h, conclusion: "cancelled"} end]
    | map(. + {repo: "acme/widgets", headBranch: "feat/forty", attempt: 1, status: "completed",
               updatedAt: "2026-10-01T10:30:00Z", attempts: []})')
db '(.prs[] | select(.repo == "acme/widgets" and .number == 21)) as $p
    | .prs += [$p | .number = 40 | .headRefName = "feat/forty"]
    | .pr_commits["acme/widgets#40"] = $h | .runs += $r' --argjson h "$HEADS40" --argjson r "$RUNS40"
prs "acme/widgets#40 $MERGE"
reset_calls
OUT=$(compute)
# Failing heads up to the green 65th: the 32 odd heads before it, and head 30.
eq "65 heads, one of them with 250 runs over three pages: every failing head counted, measured" "33 measured" "$(fig "$OUT" failing_heads)"
eq "  ... nothing missing for it" "" "$(q "$OUT" '[.missing[] | select(.figure == "failing_heads")] | length | if . == 0 then "" else tostring end')"
eq "  ... head 30's three pages each read" "1 2 3" \
    "$(grep -- "head_sha=$(hsha 30)&per_page=100&page=" "$GH_DB.calls" | sed 's/.*&page=\([0-9]*\).*/\1/' | tr '\n' ' ' | sed 's/ $//')"
eq "  ... the reads stop at the green head: none for the head after it" "" "$(grep -- "head_sha=$(hsha 66)" "$GH_DB.calls")"
eq "  ... and no run list is made" "" "$(grep -- '^run list' "$GH_DB.calls")"
# With the budget out at head 30 (the read answers as uc_gh does when it is
# spent), the count is a floor over the 29 heads read, naming time limit.
db '.fail = [{match: $m, rc: 125, stderr: "budget"}]' --arg m "head_sha=$(hsha 30)"
OUT=$(compute)
eq "the budget spent at head 30: a floor over the heads read, time limit" "15 bound|time limit" \
    "$(q "$OUT" '"\(.figures.failing_heads.value) \(.figures.failing_heads.state)|\([.missing[] | select(.figure == "failing_heads") | .reason][0])"')"
eq "  ... and green not recoverable, time limit" "null not recoverable|time limit" \
    "$(q "$OUT" '"\(.figures.dispatch_to_green_min.value) \(.figures.dispatch_to_green_min.state)|\([.missing[] | select(.figure == "dispatch_to_green_min") | .reason][0])"')"
db '.fail = [{match: $m, rc: 1, stderr: "HTTP 502"}]' --arg m "head_sha=$(hsha 30)&per_page=100&page=2"
eq "a failed page read at head 30: a floor over the heads read, read failed" "15 bound|read failed" \
    "$(compute | jq -r '"\(.figures.failing_heads.value) \(.figures.failing_heads.state)|\([.missing[] | select(.figure == "failing_heads") | .reason][0])"')"
db '.fail = []'
# No green head: every head is read and green is not recoverable.
db '(.runs[] | select(.headSha == $g)).conclusion = "failure"' --arg g "$(hsha 65)"
reset_calls
OUT=$(compute)
eq "no green head: every head read, each failing one counted" "35 measured" "$(fig "$OUT" failing_heads)"
eq "  ... the 66th head read too" 1 "$(grep -c -- "head_sha=$(hsha 66)" "$GH_DB.calls")"
eq "  ... and green not recoverable" "null not recoverable" "$(fig "$OUT" dispatch_to_green_min)"

echo "== the milestone from the dispatch's leg key =="
# No Holdings row names the topic (the unit retired, or removed before its
# pass): the Unit comes from the leg key its dispatch wrote in the requesting
# coordinator's session, found through the unit's own koto request.
seed_noholding() {
    cat "$GH_DB.calls" >>"$T/allcalls" 2>/dev/null
    db_init
    seed_session "$S" "$(record_json roadmap x | jq -c '.holdings = []')" 2026-10-01T08:00:00Z
    db '.prs += $g[0].prs | .pr_commits = $g[0].pr_commits | .runs = $g[0].runs' --slurpfile g "$FX/github.json"
    db '.files["acme/widgets"]["main:CLAUDE.md"] = "# widgets\n\n## PR Workflow Content: include"'
}
LREQ="$T/legreqs"
rm -rf "$LREQ"; cp -R "$FX/requests" "$LREQ"
jq -c --arg s "$S" 'if .request_id == "r_dispatch_x" and has("requested_by") then .requested_by = $s else . end' \
    "$FX/requests/r_dispatch_x/request.jsonl" >"$LREQ/r_dispatch_x/request.jsonl"
seed_noholding; fresh; prs "acme/widgets#21 $MERGE"
legunit() { KOTO_REQUESTS="$LREQ" capture >/dev/null; last_entry | jq -r '"\(.milestone.value | tojson) \(.milestone.state)"'; }
printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken","unit":"Feature 4: Example feature"}' \
    | koto context add "$S" legs/r_dispatch_x/deliver
eq "no Holdings row, the leg key holding the Unit: its milestone, measured" \
    '{"roadmap":"ROADMAP-x","tag":"Feature 4"} measured' "$(legunit)"
POSTED=$((POSTED + 1))
seed_noholding; fresh
printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken"}' \
    | koto context add "$S" legs/r_dispatch_x/deliver
eq "a leg key with no Unit (a dispatch from before it was recorded): not recoverable" \
    'null not recoverable' "$(legunit)"
POSTED=$((POSTED + 1))
seed_noholding; fresh
printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken","unit":"$(x)"}' \
    | koto context add "$S" legs/r_dispatch_x/deliver
eq "a leg key whose Unit is outside the pattern: not recoverable" 'null not recoverable' "$(legunit)"
POSTED=$((POSTED + 1))
koto context remove "$S" legs/r_dispatch_x/deliver >/dev/null 2>&1
seed "Feature 9: The row's own"; fresh
printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken","unit":"Feature 4: Example feature"}' \
    | koto context add "$S" legs/r_dispatch_x/deliver
eq "a Holdings row and a leg key that differ: the row's" '{"roadmap":"ROADMAP-x","tag":"Feature 9"} measured' "$(legunit)"
POSTED=$((POSTED + 1))
koto context remove "$S" legs/r_dispatch_x/deliver >/dev/null 2>&1

echo "== one entry per key =="
seed; fresh; prs "acme/widgets#21 $MERGE"
capture; eq "a first capture posts" 0 $?
POSTED=$((POSTED + 1))
capture; eq "a second capture of the same unit exits 0" 0 $?
eq "  ... having posted nothing" 1 "$(cost_bodies | jq length)"
eq "  ... and says so" "unit-cost: the record already holds this unit's cost entry" "$(tail -n 1 "$T/cap.err")"
# The same unit archived on another day: another key, the same dispatch id.
mkdir -p "$T/b"; rm -rf "$T/b/2026-10-02-feat-x-0a1b2c3d"; cp -R "$A" "$T/b/2026-10-02-feat-x-0a1b2c3d"
bash "$UC" capture --session "$S" --archive "$T/b/2026-10-02-feat-x-0a1b2c3d" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "another key with the same dispatch id posts nothing" "0 1" "$? $(cost_bodies | jq length)"
eq "  ... and says the record already holds the unit's entry" "unit-cost: the record already holds this unit's cost entry" "$(tail -n 1 "$T/cap.err")"
# With no dispatch id on either side, another key is another unit.
NOID="$T/b/2026-10-03-feat-x-0a1b2c3d"
rm -rf "$NOID"; cp -R "$A" "$NOID"
jq -c '.niwa = {dispatch_id: null, reason: "no source"}' "$NOID/teardown.json" >"$T/td" && cp "$T/td" "$NOID/teardown.json"
bash "$UC" capture --session "$S" --archive "$NOID" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "a capture with no dispatch id and another key still gets its entry" "0 2" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
bash "$UC" capture --session "$S" --archive "$NOID" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "  ... and the same key with no dispatch id is still one entry" "0 2" "$? $(cost_bodies | jq length)"
# An entry key that isn't JSON fails the list; the post still finds its number.
printf 'not json' | koto context add "$S" record/entries/000090
capture; eq "a failed list posts anyway" "0 3" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
eq "  ... a second entry for the key, which readers report as a repeat" 2 \
    "$(cost_bodies | jq --arg k "$KEY" '[.[] | split("\n") | .[6] | fromjson | select(.key == $k)] | length')"

echo "== the post lock =="
# The list and the post run under .post-lock in the removals directory (under
# HOME here, XDG_STATE_HOME being unset). Two captures of one unit with the
# same dispatch id and different keys meet at a barrier on the session's entry
# list, which state-entry.sh reads (koto context list --prefix
# record/entries/) only inside the lock: a koto ahead of the stand-in on PATH
# holds every such call until $T/go exists and notes each one in $T/listing.
# With the lock, one capture is at the barrier and the other waits for the
# lock; without it both would list an empty record there and both would post.
PL="$HOME/.local/state/shirabe/removals/.post-lock"
seed; fresh; prs "acme/widgets#21 $MERGE"
rm -rf "$T/c" "$T/barrier" "$T/go" "$T/listing"; mkdir -p "$T/c" "$T/barrier"; cp -R "$A" "$T/c/2026-10-04-feat-x-0a1b2c3d"
cat >"$T/barrier/koto" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *"context list --prefix record/entries/"*)
        echo \$\$ >>'$T/listing'
        i=0
        while [ ! -e '$T/go' ] && [ "\$i" -lt 600 ]; do sleep 0.1; i=\$((i + 1)); done ;;
esac
exec '$HERE/testdata/koto' "\$@"
EOF
chmod +x "$T/barrier/koto"
PATH="$T/barrier:$PATH" UNIT_COST_LIST_SECS=40 UNIT_COST_POST_SECS=20 \
    bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap1.err" &
P1=$!
PATH="$T/barrier:$PATH" UNIT_COST_LIST_SECS=40 UNIT_COST_POST_SECS=20 \
    bash "$UC" capture --session "$S" --archive "$T/c/2026-10-04-feat-x-0a1b2c3d" --topic feat-x --prs-file "$T/prs" 2>"$T/cap2.err" &
P2=$!
i=0
until [ -s "$T/listing" ] || [ "$i" -ge 600 ]; do sleep 0.1; i=$((i + 1)); done
# Time for the other capture to reach the lock, or, without one, the barrier.
sleep 3
eq "two captures of one unit: one is at the barrier inside the lock, the other held out of it" 1 "$(grep -c . "$T/listing")"
touch "$T/go"
wait "$P1"; wait "$P2"
POSTED=$((POSTED + 1))
eq "  ... released, they leave one entry" 1 "$(cost_bodies | jq length)"
eq "  ... one posts, and the other, listing after it, says the record already holds the entry" \
    "unit-cost: posted the cost entry on acme/widgets#21|unit-cost: the record already holds this unit's cost entry" \
    "$({ tail -n 1 "$T/cap1.err"; tail -n 1 "$T/cap2.err"; } | LC_ALL=C sort | tr '\n' '|' | sed 's/|$//')"
eq "  ... the lock is released after them" no "$([ -e "$PL" ] && echo yes || echo no)"
# A lock left by a process that is gone is taken over.
seed; fresh
mkdir -p "$PL"; printf '%s %s\n' 999999 "$(date +%s)" >"$PL/owner"
capture; eq "a lock whose holder is gone is taken over, and the capture posts" "0 1" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
# A lock with no owner may be one its holder hasn't written yet: it is waited
# on for two seconds, and then, still ownerless, taken over.
seed; fresh
mkdir -p "$PL"
S0=$(date +%s)
capture; eq "a lock with no owner is waited on, then taken over, and the capture posts" "0 1 yes" \
    "$? $(cost_bodies | jq length) $([ $(($(date +%s) - S0)) -ge 2 ] && echo yes || echo no)"
POSTED=$((POSTED + 1))
# A lock a live process holds is waited for inside the list and post bounds,
# then the capture lists and posts without it, saying so.
seed; fresh
# The holder is this suite's own shell, which outlives the capture.
LIVE=$$
mkdir -p "$PL"; printf '%s %s\n' "$LIVE" "$(date +%s)" >"$PL/owner"
UNIT_COST_LIST_SECS=2 UNIT_COST_POST_SECS=10 bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "a lock a live process holds is waited out, then the capture posts without it" "0 1" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
case "$(cat "$T/cap.err")" in *"the post lock is held"*) ok "  ... saying so" ;; *) bad "  ... saying so" "$(cat "$T/cap.err")" ;; esac
eq "  ... and leaves the live process's lock in place" "$LIVE" "$(cut -d' ' -f1 "$PL/owner")"
rm -rf "$PL"

echo "== partial entries =="
seed; fresh; prs "acme/widgets#21 $MERGE"
rm -rf "$A/claude-projects"
capture; eq "with the transcripts missing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, naming the token rows" "false|tokens.worker:no source,tokens.nested:no source" \
    "$(last_entry | jq -r '"\(.complete)|\([.missing[] | select(.figure | startswith("tokens")) | "\(.figure):\(.reason)"] | join(","))"')"
seed; fresh
db '.fail = [{match: "actions/runs?head_sha", rc: 1, stderr: "HTTP 502"}]'
capture; eq "with the runs read failing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, the run figures read failed, the rest kept" "false|dispatch_to_green_min:read failed,outside_share_pct:read failed,review_share_pct:read failed,failing_heads:read failed|150 measured|40.5 measured" \
    "$(last_entry | jq -r '"\(.complete)|\([.missing[] | select(.figure | test("green|share|failing")) | "\(.figure):\(.reason)"] | join(","))|\(.figures.dispatch_to_merge_min.value) \(.figures.dispatch_to_merge_min.state)|\(.figures.writing_code_min.value) \(.figures.writing_code_min.state)"')"
seed; fresh
db '.fail = [{match: "pr view 21", rc: 1, stderr: "HTTP 502"}]'
capture; eq "with gh pr view failing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, the merge time read failed, the pull request kept" "false|read failed|21|null|read failed" \
    "$(last_entry | jq -r '"\(.complete)|\([.missing[] | select(.figure == "pulls.merged_at") | .reason][0])|\(.pulls[0].number)|\(.pulls[0].merged_at)|\([.missing[] | select(.figure == "dispatch_to_merge_min") | .reason][0])"')"
seed; fresh
db '.fail = [{match: "attempts/1", rc: 1, stderr: "HTTP 502"}]'
capture; eq "with an attempt read failing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... green and failing heads read failed" "read failed|read failed" \
    "$(last_entry | jq -r '"\([.missing[] | select(.figure == "dispatch_to_green_min") | .reason][0])|\([.missing[] | select(.figure == "failing_heads") | .reason][0])"')"
seed; fresh
UNIT_COST_BUDGET_SECS=0 bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "with the budget spent, the capture still posts" "0 1" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
SPENT=$(last_entry)
eq "  ... what it could not take is time limit" "false|time limit|time limit|time limit|time limit|time limit|time limit" \
    "$(q "$SPENT" '"\(.complete)|\([.missing[] | select(.figure == "milestone") | .reason][0])|\([.missing[] | select(.figure == "pulls.merged_at") | .reason][0])|\([.missing[] | select(.figure == "dispatch_to_green_min") | .reason][0])|\([.missing[] | select(.figure == "dispatch_to_merge_min") | .reason][0])|\([.missing[] | select(.figure == "failing_heads") | .reason][0])|\([.missing[] | select(.figure == "tokens.worker") | .reason][0])"')"
eq "  ... the figures already computed are kept" "40.5 measured|29.5 measured|3 measured|99.3 measured" \
    "$(q "$SPENT" '[.figures.writing_code_min, .figures.review_min, .figures.panel_rounds, .figures.summed_session_span_min] | map("\(.value) \(.state)") | join("|")')"
eq "  ... and a repository it could not look up is not public" '[{"repo":"not public"}]' "$(q "$SPENT" '.pulls | tojson')"

echo "== an entry over 50,000 bytes =="
seed; fresh; prs "acme/widgets#21 $MERGE"
# A long session: 1,200 distinct states, its map alone past the limit.
mkdir -p "$A/koto/zz-long"
{
    printf '{"schema_version":1,"workflow":"zz-long","template_name":"scope","template_source_file":"scope.md"}\n'
    jq -nc 'range(0; 1200) as $i | {seq: ($i + 1), timestamp: "2026-10-01T09:00:00.000Z" , type: "transitioned",
        payload: {to: ("state_with_a_long_name_for_the_size_test_\($i)")}}'
    printf '{"seq":1201,"timestamp":"2026-10-01T09:30:00.000Z","type":"transitioned","payload":{"to":"done"}}\n'
} >"$A/koto/zz-long/koto-zz-long.state.jsonl"
capture; eq "the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... the archive copy is over the limit and keeps every states map" "true|true" \
    "$(jq -r '"\(tojson | length > 50000)|\([.sessions[].states | type == "object"] | all)"' "$A/unit-cost.json")"
L=$(last_entry)
eq "  ... the posted copy drops the per-session states maps" "true|0" "$(q "$L" '"\([.sessions[].states] | all(. == null))|\(tojson | length > 50000 | if . then 1 else 0 end)"')"
eq "  ... records entry size and complete false" "sessions.states:entry size|false" \
    "$(q "$L" '"\([.missing[] | select(.reason == "entry size") | "\(.figure):\(.reason)"] | join(","))|\(.complete)"')"
eq "  ... and keeps every figure" "$(jq -c .figures "$A/unit-cost.json")" "$(q "$L" '.figures | tojson')"

echo "== the archive copy =="
seed; fresh
ln -s "$T/elsewhere" "$A/unit-cost.json"
capture >/dev/null; POSTED=$((POSTED + 1))
[ ! -L "$A/unit-cost.json" ] && [ -f "$A/unit-cost.json" ] && [ ! -e "$T/elsewhere" ] \
    && ok "a symlink at unit-cost.json is replaced, never written through" || bad "a symlink at unit-cost.json is replaced, never written through"
LEFT=""
for f in "$A"/.unit-cost*; do [ -e "$f" ] && LEFT="$LEFT ${f##*/}"; done
eq "  ... and no temporary file is left" "" "$LEFT"

echo "== credit =="
# mkcredit [notime]: a unit with a job record (09:00) and the worker's main
# transcript in claude-projects/, on gitBranch feat/own, its first event at
# 09:00, and no koto session: dispatch is 09:00:00. With notime there is no
# job record and no timestamp, so dispatch is not recoverable.
mkcredit() {
    rm -rf "$T/c"
    A="$T/c/$KEY"
    CW="$A/claude-projects/-w-inst-c/0a1b2c3d-0c0c.jsonl"
    mkdir -p "$A/job" "$A/claude-projects/-w-inst-c"
    if [ "${1:-}" = notime ]; then
        printf '{"type":"user","cwd":"/w/inst/c","gitBranch":"feat/own"}\n' >"$CW"
    else
        printf '{"createdAt":"2026-10-01T09:00:00.000Z","sessionId":"0a1b2c3d-0c0c"}\n' >"$A/job/state.json"
        printf '{"type":"user","cwd":"/w/inst/c","gitBranch":"feat/own","timestamp":"2026-10-01T09:00:00.000Z"}\n' >"$CW"
    fi
}
# link <repo> <number as JSON> <timestamp>: a pr-link record in the worker's transcript.
link() {
    jq -nc --arg r "$1" --argjson n "$2" --arg t "$3" \
        '{type: "pr-link", sessionId: "0a1b2c3d-0c0c", prNumber: $n, prUrl: "https://github.com/\($r)/pull/\($n)", prRepository: $r, timestamp: $t}' >>"$CW"
}
# ghpr <repo> <n> <created> <state> <head> <merged at> [head owner]: one
# pull request on GitHub's side.
ghpr() {
    db '.prs += [{repo: $r, number: ($n | tonumber), title: "x", body: "", state: $s, isDraft: false, isCrossRepository: ($o != ""),
            baseRefName: "main", headRefName: $h, headRefOid: $m, author: "alice", editor: null, createdAt: $c}
        + (if $s == "MERGED" then {mergedAt: $at, mergeCommit: $m} else {} end)
        + (if $o == "" then {} else {headOwner: $o} end)]' \
        --arg r "$1" --arg n "$2" --arg c "$3" --arg s "$4" --arg h "$5" --arg at "$6" --arg o "${7:-}" --arg m "$MERGE2"
}
via() { q "$1" '[.pulls[] | if .repo == "not public" then "not public" else "\(.repo)#\(.number) \(.via)" end] | join("|")'; }
pmiss() { q "$1" '[.missing[] | select(.figure == "pulls") | .reason] | join(",")'; }
seed; mkcredit; prs "acme/widgets#21 $MERGE"
db '.repos["other/widgets"] = {private: false, default_branch: "main"}'
ghpr acme/widgets 41 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:30:00Z
link acme/widgets 41 2026-10-01T12:00:00.000Z
ghpr acme/widgets 42 2026-10-01T10:10:00Z MERGED impl/plan-node-2 2026-10-01T10:40:00Z
link acme/widgets 42 2026-10-01T10:10:30.000Z
ghpr acme/widgets 43 2026-10-01T10:20:00Z MERGED feat/other 2026-10-01T10:50:00Z
link acme/widgets 43 2026-10-01T11:20:00.000Z
ghpr acme/widgets 44 2026-10-01T08:00:00Z MERGED feat/own 2026-10-01T08:30:00Z
link acme/widgets 44 2026-10-01T11:00:00.000Z
ghpr acme/widgets 45 2026-10-01T10:30:00Z MERGED feat/own 2026-10-01T10:45:00Z forker
link acme/widgets 45 2026-10-01T10:30:10.000Z
ghpr other/widgets 46 2026-10-01T10:30:00Z MERGED feat/own 2026-10-01T10:45:00Z
link other/widgets 46 2026-10-01T10:30:10.000Z
ghpr acme/widgets 47 2026-10-01T10:30:00Z OPEN feat/own ""
link acme/widgets 47 2026-10-01T10:30:10.000Z
link acme/widgets 21 2026-10-01T09:30:00.000Z
reset_calls
OUT=$(compute)
eq "own branch, linked 30 s after creation, viewed an hour later, created before dispatch, a fork, another owner, unmerged: the first two credited after the holding's" \
    "acme/widgets#21 holding|acme/widgets#41 session|acme/widgets#42 session" "$(via "$OUT")"
eq "  ... credited with the merge commit and time GitHub reads" \
    "$MERGE2 2026-10-01T10:30:00Z|$MERGE2 2026-10-01T10:40:00Z" "$(q "$OUT" '[.pulls[1:][] | "\(.merge_commit) \(.merged_at)"] | join("|")')"
eq "  ... the holding's own link is no second entry" 1 "$(q "$OUT" '[.pulls[] | select(.number == 21)] | length')"
eq "  ... nothing left out, nothing missing for pulls" "" "$(pmiss "$OUT")"
eq "  ... one read per candidate under the holding's owner, none for another owner's" "41 42 43 44 45 47" \
    "$(grep -- '--json state,createdAt' "$GH_DB.calls" | awk '{print $3}' | sort -n | tr '\n' ' ' | sed 's/ $//')"
eq "  ... and credit moves no figure: merge is still the holding's" "150 measured|130 measured" "$(fig "$OUT" dispatch_to_merge_min)|$(fig "$OUT" dispatch_to_green_min)"
case "$(via "$OUT")" in *"#43"*) bad "a merged, same-owner pull request created after dispatch on no gitBranch of the unit, linked only more than 120 s after its creation, is not credited (viewed)" "$(via "$OUT")" ;;
    *) ok "a merged, same-owner pull request created after dispatch on no gitBranch of the unit, linked only more than 120 s after its creation, is not credited (viewed)" ;; esac
eq "a pull request the unit opened on a sibling node branch, absent from every gitBranch, linked within 120 s of its creation: credited via session" \
    "acme/widgets#42 session" "$(q "$OUT" '[.pulls[] | select(.number == 42) | "\(.repo)#\(.number) \(.via)"][0]')"
case " $(q "$OUT" '.pulls | tojson') " in *impl/plan-node-2* | *feat/own* | *feat/other*) bad "  ... no branch name enters the entry" "$OUT" ;; *) ok "  ... no branch name enters the entry" ;; esac
eq "  ... and open pull request 47, out of pulls, is in opened" "acme/widgets#47 session" \
    "$(q "$OUT" '[.opened[] | "\(.repo)#\(.number) \(.via)"] | join("|")')"
# The window is 120 seconds either way, inclusive.
seed; mkcredit
ghpr acme/widgets 51 2026-10-01T10:00:00Z MERGED b/51 2026-10-01T10:31:00Z
link acme/widgets 51 2026-10-01T10:02:00.000Z
ghpr acme/widgets 52 2026-10-01T10:00:00Z MERGED b/52 2026-10-01T10:32:00Z
link acme/widgets 52 2026-10-01T09:58:00.000Z
ghpr acme/widgets 53 2026-10-01T10:00:00Z MERGED b/53 2026-10-01T10:33:00Z
link acme/widgets 53 2026-10-01T10:02:00.001Z
ghpr acme/widgets 54 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:34:00Z
ghpr acme/widgets 55 2026-10-01T10:00:00Z MERGED main 2026-10-01T10:35:00Z
link acme/widgets 54 2026-10-01T12:00:00.000Z
link acme/widgets 55 2026-10-01T12:00:00.000Z
printf '{"type":"user","gitBranch":"main"}\n' >>"$CW"
OUT=$(compute)
eq "linked 120 s after or before creation is credited, 120.001 s is not; a gitBranch head is, a head that is its own base is not" \
    "acme/widgets#21 holding|acme/widgets#51 session|acme/widgets#52 session|acme/widgets#54 session" "$(via "$OUT")"
eq "no open pull request: opened is empty and missing names nothing for it" "[]|" \
    "$(q "$OUT" '.opened | tojson')|$(q "$OUT" '[.missing[] | select(.figure == "opened")] | length | if . == 0 then "" else . end')"
# An unreadable linked pull request: left out, and credit never gates.
seed; mkcredit
ghpr acme/widgets 41 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:30:00Z
link acme/widgets 41 2026-10-01T10:00:10.000Z
ghpr acme/widgets 42 2026-10-01T10:10:00Z MERGED feat/own 2026-10-01T10:40:00Z
link acme/widgets 42 2026-10-01T10:10:10.000Z
db '.fail = [{match: "pr view 41 --repo acme/widgets --json state", rc: 1, stderr: "HTTP 502"}]'
OUT=$(compute)
eq "an unreadable linked pull request is left out, the others credited" "acme/widgets#21 holding|acme/widgets#42 session" "$(via "$OUT")"
eq "  ... missing names pulls once, read failed" "read failed" "$(pmiss "$OUT")"
db '.fail = []'
# No dispatch: created at or after dispatch can't be judged.
seed; mkcredit notime
ghpr acme/widgets 41 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:30:00Z
link acme/widgets 41 none
reset_calls
OUT=$(KOTO_REQUESTS="$T/none" compute)
eq "dispatch not recoverable: only the holding's pull request, pulls no source" "not recoverable|acme/widgets#21 holding|no source" \
    "$(q "$OUT" .dispatch.state)|$(via "$OUT")|$(pmiss "$OUT")"
eq "  ... and no credit read is made" "" "$(grep -- '--json state,createdAt' "$GH_DB.calls")"
# More than 100: the holding's first, then by merge time and number.
seed; mkcredit
db '.prs += [range(101; 202) as $i | {repo: "acme/widgets", number: $i, title: "x", body: "", state: "MERGED", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "b/\($i)", headRefOid: $m, author: "alice", editor: null,
        createdAt: "2026-10-01T10:00:00Z", mergedAt: (if $i % 2 == 0 then "2026-10-01T10:20:00Z" else "2026-10-01T10:30:00Z" end),
        mergeCommit: $m}]' --arg m "$MERGE2"
jq -nc 'range(101; 202) as $i | {type: "pr-link", prNumber: $i, prRepository: "acme/widgets", timestamp: "2026-10-01T10:00:30.000Z"}' >>"$CW"
OUT=$(compute)
eq "101 creditable pull requests: 100 objects, the holding's first, then by merge time and number" \
    "100|acme/widgets#21 holding|102 104 200 101 103|197|entry size" \
    "$(q "$OUT" '"\(.pulls | length)|\(.pulls[0] | "\(.repo)#\(.number) \(.via)")|\([.pulls[1], .pulls[2], .pulls[50], .pulls[51], .pulls[52]] | map(.number | tostring) | join(" "))|\(.pulls[99].number)"')|$(pmiss "$OUT")"
seed; mkcredit
ghpr acme/secret 9 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:30:00Z
link acme/secret 9 2026-10-01T10:00:10.000Z
OUT=$(compute)
eq "a private credited pull request on a public host is {repo: not public} alone" '[{"repo":"acme/widgets","via":"holding"},{"repo":"not public"}]' \
    "$(q "$OUT" '[.pulls[] | if .repo == "not public" then . else {repo, via} end] | tojson')"
echo "== opened: pull requests still open at capture =="
opn() { q "$1" '[.opened[] | if .repo == "not public" then "not public" else "\(.repo)#\(.number) \(.via)" end] | join("|")'; }
omiss() { q "$1" '[.missing[] | select(.figure == "opened") | .reason] | join(",")'; }
seed; mkcredit; prs "acme/widgets#21 $MERGE"
ghpr acme/widgets 61 2026-10-01T10:00:00Z MERGED feat/own 2026-10-01T10:30:00Z
link acme/widgets 61 2026-10-01T10:00:10.000Z
ghpr acme/widgets 62 2026-10-01T10:00:00Z OPEN feat/own ""
link acme/widgets 62 2026-10-01T10:00:10.000Z
ghpr acme/widgets 63 2026-10-01T10:00:00Z OPEN feat/own ""
db '(.prs[] | select(.number == 63)).isDraft = true'
link acme/widgets 63 2026-10-01T10:00:10.000Z
ghpr acme/widgets 64 2026-10-01T10:00:00Z CLOSED feat/own ""
link acme/widgets 64 2026-10-01T10:00:10.000Z
ghpr acme/widgets 65 2026-10-01T08:00:00Z OPEN feat/own ""
link acme/widgets 65 2026-10-01T10:00:10.000Z
OUT=$(compute)
eq "merged in pulls; open and draft in opened; closed unmerged, and open but created before dispatch, in neither" \
    "acme/widgets#21 holding|acme/widgets#61 session / acme/widgets#62 session|acme/widgets#63 session" "$(via "$OUT") / $(opn "$OUT")"
eq "  ... nothing missing for opened or pulls" "|" "$(omiss "$OUT")|$(pmiss "$OUT")"
eq "  ... an opened object is repo, number and via alone" true "$(q "$OUT" '[.opened[] | keys == ["number", "repo", "via"]] | all')"
# More than 100 open: the lowest 100 numbers, and missing names opened.
seed; mkcredit; prs "acme/widgets#21 $MERGE"
db '.prs += [range(101; 202) as $i | {repo: "acme/widgets", number: $i, title: "x", body: "", state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "b/\($i)", headRefOid: $m, author: "alice", editor: null,
        createdAt: "2026-10-01T10:00:00Z"}]' --arg m "$MERGE2"
jq -nc 'range(201; 100; -1) as $i | {type: "pr-link", prNumber: $i, prRepository: "acme/widgets", timestamp: "2026-10-01T10:00:30.000Z"}' >>"$CW"
OUT=$(compute)
eq "101 open pull requests: 100 in opened, by number, missing naming opened entry size, pulls untouched" \
    "100|101|200|entry size||1" \
    "$(q "$OUT" '"\(.opened | length)|\(.opened[0].number)|\(.opened[99].number)"')|$(omiss "$OUT")|$(pmiss "$OUT")|$(q "$OUT" '.pulls | length')"
seed; mkcredit; prs "acme/widgets#21 $MERGE"
ghpr acme/secret 9 2026-10-01T10:00:00Z OPEN feat/own ""
link acme/secret 9 2026-10-01T10:00:10.000Z
OUT=$(compute)
eq "an open pull request in a private repository on a public host is {repo: not public} alone" '[{"repo":"not public"}]' "$(q "$OUT" '.opened | tojson')"
# A failed read: in neither list, both name the reason.
seed; mkcredit; prs "acme/widgets#21 $MERGE"
ghpr acme/widgets 62 2026-10-01T10:00:00Z OPEN feat/own ""
link acme/widgets 62 2026-10-01T10:00:10.000Z
db '.fail = [{match: "pr view 62 --repo acme/widgets --json state", rc: 1, stderr: "HTTP 502"}]'
OUT=$(compute)
eq "an unreadable open pull request is in neither list; missing names opened and pulls, read failed" \
    "|acme/widgets#21 holding|read failed|read failed" "$(opn "$OUT")|$(via "$OUT")|$(omiss "$OUT")|$(pmiss "$OUT")"
db '.fail = []'
# The holding's own Pull request cell, read by a capture.
seed "Feature 4: Example feature" "[#62](https://github.com/acme/widgets/pull/62)"; mkcredit; prs "acme/widgets#21 $MERGE"
ghpr acme/widgets 62 2026-10-01T10:00:00Z OPEN feat/own ""
link acme/widgets 62 2026-10-01T10:00:10.000Z
reset_calls
UNIT_COST_PR_CONTENT_READER="$T/absent.sh" capture >/dev/null
eq "the holding's Pull request cell reading open: in opened via holding, never also via session" \
    "acme/widgets#62 holding" "$(opn "$(cat "$A/unit-cost.json")")"
eq "  ... read once" 1 "$(grep -c -- 'pr view 62 --repo acme/widgets --json state' "$GH_DB.calls")"
seed "Feature 4: Example feature" "[#64](https://github.com/acme/widgets/pull/64)"; mkcredit; prs "acme/widgets#21 $MERGE"
ghpr acme/widgets 64 2026-10-01T10:00:00Z CLOSED feat/own ""
UNIT_COST_PR_CONTENT_READER="$T/absent.sh" capture >/dev/null
eq "a holding cell reading closed is not in opened, and nothing is missing for it" "|" \
    "$(opn "$(cat "$A/unit-cost.json")")|$(omiss "$(cat "$A/unit-cost.json")")"
# A budget spent after the first credit read: what was read is kept.
seed; mkcredit
db '.prs += [range(61; 76) as $i | {repo: "acme/widgets", number: $i, title: "x", body: "", state: "MERGED", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "b/\($i)", headRefOid: $m, author: "alice", editor: null,
        createdAt: "2026-10-01T10:\($i - 50):00Z", mergedAt: "2026-10-01T11:\($i - 50):00Z", mergeCommit: $m}]' --arg m "$MERGE2"
for i in 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75; do link acme/widgets "$i" "2026-10-01T10:$((i - 50)):30.000Z"; done
printf '#!/usr/bin/env bash\ncase "$*" in "pr view "*"--json state,createdAt"*) echo x >>"%s/slow.n"; sleep 2 ;; esac\nexec gh "$@"\n' "$T" >"$T/slowgh"
chmod +x "$T/slowgh"
: >"$T/slow.n"
OUT=$(GH="$T/slowgh" UNIT_COST_BUDGET_SECS=20 compute)
NC=$(q "$OUT" '[.pulls[] | select(.via == "session")] | length')
[ "$NC" -ge 1 ] && [ "$NC" -lt 15 ] && ok "a budget spent mid-way keeps the credit read before it ($NC of 15)" || bad "a budget spent mid-way keeps the credit read before it" "$NC: $OUT"
eq "  ... the earliest-linked first, in order" "$(awk -v n="$NC" 'BEGIN { for (i = 61; i <= 60 + n; i++) printf "%s%d", (i > 61 ? " " : ""), i }')" "$(q "$OUT" '[.pulls[] | select(.via == "session") | .number | tostring] | join(" ")')"
eq "  ... and missing names pulls, time limit" "time limit" "$(pmiss "$OUT")"
# Hostile links and branches: matched to their patterns before any read.
seed; mkcredit
link 'a/b;x' 5 2026-10-01T10:00:10.000Z
link acme/widgets '"1 x"' 2026-10-01T10:00:10.000Z
link '-acme/widgets' 6 2026-10-01T10:00:10.000Z
link 'acme/../widgets' 7 2026-10-01T10:00:10.000Z
link acme/widgets '"0"' 2026-10-01T10:00:10.000Z
link acme/widgets 1.5 2026-10-01T10:00:10.000Z
printf '{"type":"user","gitBranch":"--upload-pack=x"}\n' >>"$CW"
ghpr acme/widgets 8 2026-10-01T10:00:00Z MERGED --upload-pack=x 2026-10-01T10:30:00Z
link acme/widgets 8 2026-10-01T12:00:00.000Z
reset_calls
OUT=$(compute)
eq "pr-link repository a/b;x, number 1 x, gitBranch --upload-pack=x: no GitHub read names them" "" \
    "$(grep -e ';x' -e '1 x' -e 'upload-pack' -e '\.\.' -e 'repo -acme' -e 'pr view 0 ' -e 'pr view 1.5' "$GH_DB.calls")"
eq "  ... the one well-formed link is read, and a head that is no allowed gitBranch credits nothing" "acme/widgets#21 holding|8" \
    "$(via "$OUT")|$(grep -- '--json state,createdAt' "$GH_DB.calls" | awk '{print $3}' | tr '\n' ' ' | sed 's/ $//')"

echo "== niwa's dispatch id =="
seed; fresh; prs "acme/widgets#21 $MERGE"
nid() { compute | jq -r '"\(."niwa.dispatch.id" | tojson)|\([.missing[] | select(.figure == "niwa.dispatch.id") | .reason] | join(","))"'; }
eq "teardown.json's dispatch id is the entry's, unchanged" '"dsp-feat-x.1"|' "$(nid)"
jq -c '.niwa = {dispatch_id: null, reason: "no source"}' "$A/teardown.json" >"$T/td" && cp "$T/td" "$A/teardown.json"
eq "a teardown.json with no id: null, no source" 'null|no source' "$(nid)"
jq -c '.niwa = {dispatch_id: null, reason: "invalid input"}' "$A/teardown.json" >"$T/td" && cp "$T/td" "$A/teardown.json"
eq "  ... with the handoff's invalid input: null, invalid input" 'null|invalid input' "$(nid)"
jq -c '.niwa = {dispatch_id: "a b", reason: null}' "$A/teardown.json" >"$T/td" && cp "$T/td" "$A/teardown.json"
eq "an id outside its shape (a b): null, invalid input" 'null|invalid input' "$(nid)"
printf 'not json\n' >"$A/teardown.json"
eq "a teardown.json that isn't JSON: null, invalid input" 'null|invalid input' "$(nid)"
rm -f "$A/teardown.json"
eq "no teardown.json: null, no source" 'null|no source' "$(nid)"
# A removal record (archive-common.sh's removals directory, under
# XDG_STATE_HOME) for the archive's instance path gives the id teardown.json
# lacks; one for another path, or a removals directory not mode 0700, doesn't.
fresh
jq -c '.niwa = {dispatch_id: null, reason: "no source"}' "$A/teardown.json" >"$T/td" && cp "$T/td" "$A/teardown.json"
export XDG_STATE_HOME="$T/xdg"
RMD="$XDG_STATE_HOME/shirabe/removals"
mkdir -p "$RMD"
chmod 700 "$RMD"
removal() { # removal <dispatch id> <instance path>
    jq -n -c --arg d "$1" --arg p "$2" '{schema: "unit-removal/1", dispatch_id: $d, session_id: "0a1b2c3d-77aa",
        instance_path: $p, removed_at: "2026-10-01T12:00:00Z", attempts: 0, last: null}' >"$RMD/$1.json"
}
removal dsp-removed.3 /work/inst/feat-x
eq "a teardown.json with no id takes the removal record's for its instance path" '"dsp-removed.3"|' "$(nid)"
chmod 755 "$RMD"
eq "  ... not from a removals directory that isn't mode 0700" 'null|no source' "$(nid)"
chmod 700 "$RMD"
rm -f "$RMD"/*.json
removal dsp-removed.3 /work/inst/feat-x-2
eq "  ... nor from a record for another instance path" 'null|no source' "$(nid)"
fresh
removal dsp-removed.4 /work/inst/feat-x
eq "teardown.json's own id stands over a removal record's" '"dsp-feat-x.1"|' "$(nid)"
unset XDG_STATE_HOME

echo "== a pull request file naming none: the credited pull requests read =="
# A capture after a removal has no sealed verdict: credit's owner is the
# record repository's, and green, merge and failing heads read the credited
# pull requests. #23 has a failing head then a green one, gadgets#7 one green
# head.
seed; fresh; : >"$T/prs"
H1=a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1 H2=b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2 H3=c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3
db '.pr_commits["acme/widgets#23"] = [$a, $b] | .pr_commits["acme/gadgets#7"] = [$c]
    | .runs += [{repo: "acme/widgets", databaseId: 301, headBranch: "feat/x-docs", headSha: $a, attempt: 1, status: "completed", conclusion: "failure", updatedAt: "2026-10-01T10:40:00Z", attempts: []},
                {repo: "acme/widgets", databaseId: 302, headBranch: "feat/x-docs", headSha: $b, attempt: 1, status: "completed", conclusion: "success", updatedAt: "2026-10-01T11:00:00Z", attempts: []},
                {repo: "acme/gadgets", databaseId: 303, headBranch: "feat/x-gadgets", headSha: $c, attempt: 1, status: "completed", conclusion: "success", updatedAt: "2026-10-01T11:20:00Z", attempts: []}]' \
    --arg a "$H1" --arg b "$H2" --arg c "$H3"
printf '%s' '{"scope":"roadmap","name":"x","repo":"acme/widgets","ref":"7","unit":"Feature 4: Example feature"}' >"$T/unit.json"
OUT=$(compute --unit-json "$T/unit.json")
eq "the credited pull requests are the entry's, via session" "acme/widgets#23 session|acme/gadgets#7 session" "$(via "$OUT")"
eq "  ... merge is the later of their merges" "145 measured" "$(fig "$OUT" dispatch_to_merge_min)"
eq "  ... green the later of their green heads" "140 measured" "$(fig "$OUT" dispatch_to_green_min)"
eq "  ... failing heads counted over their heads" "1 measured" "$(fig "$OUT" failing_heads)"
OUT=$(compute)
eq "with no record known, no owner: nothing credited, the GitHub figures no source" "|null not recoverable" "$(via "$OUT")|$(fig "$OUT" dispatch_to_merge_min)"

echo "== the GitHub wrapper =="
admit() { bash "$UC" gh-check "$@"; eq "admits: $*" 0 $?; }
refuse() { bash "$UC" gh-check "$@"; eq "refuses: $*" 1 $?; }
admit pr view 21 --repo acme/widgets --json mergedAt,headRefName
admit pr view 21 --repo acme/widgets --json state,createdAt,mergedAt,mergeCommit,headRefName,baseRefName,headRepositoryOwner
admit run list --repo acme/widgets --branch feat/x --limit 300 --json databaseId,headSha,attempt,status,conclusion,updatedAt
admit run list --repo acme/widgets --commit "$MERGE"
admit api --method GET repos/acme/widgets/pulls/21/commits --paginate
admit api --method GET repos/acme/widgets/actions/runs/9/attempts/1
admit api --method GET repos/acme/widgets --jq .private
refuse pr edit 21 --repo acme/widgets --body x
refuse pr view 21 --json mergedAt
refuse pr view 21 --repo acme/widgets --json mergedAt --web
refuse pr merge 21 --repo acme/widgets
refuse issue comment 7 --repo acme/widgets --body x
refuse run rerun 9 --repo acme/widgets
refuse run list --branch feat/x
refuse run list --repo acme/widgets --branch -x
refuse run list --repo acme/widgets --status failure
refuse api repos/acme/widgets
refuse api --method POST repos/acme/widgets/issues/7/comments
refuse api --method GET repos/acme/widgets/issues/7/comments --input x.json
refuse api --method GET repos/acme/widgets -f a=b
refuse api -X GET repos/acme/widgets
refuse api --method GET graphql
refuse api --method GET repos/acme/../x
refuse api --method GET user
refuse run list --repo ../x
refuse run list --repo -x/y

echo "== no write but the posts =="
cat "$GH_DB.calls" >>"$T/allcalls"
WRITES=$(grep -E -- '--method (POST|PATCH|PUT|DELETE)|-X |^(issue|pr) (create|edit|close|reopen|ready|merge|comment|review)|^run (rerun|cancel)|graphql' "$T/allcalls")
eq "every write is a comment POST on the verdict's pull request" "" "$(printf '%s\n' "$WRITES" | grep -v '^api --method POST repos/acme/widgets/issues/21/comments --input ' | grep . || true)"
eq "  ... one per captured unit" "$POSTED" "$(printf '%s\n' "$WRITES" | grep -c '^api --method POST repos/acme/widgets/issues/21/comments')"
eq "every read the capture made was one the wrapper admits" "" \
    "$(grep -E '^(pr view [0-9]+ --repo|run list|api --method GET repos/[^ ]+/(pulls/[0-9]+/commits|actions/runs)|api --method GET repos/[^ /]+/[^ /]+ --jq .private)' "$T/allcalls" \
        | sort -u | while IFS= read -r c; do
            # shellcheck disable=SC2086 # the logged call, split as gh received it
            bash "$UC" gh-check $c || printf '%s\n' "$c"
        done)"

echo "== the entries' readers =="
# state-stored-set.sh chooses a Standing id from the entry stream (the one
# script that reads entries, through state-entry.sh --list); a cost entry
# on the record changes nothing it prints or writes.
RM=(--scope roadmap --name x --repo acme/widgets)
standing() {
    seed
    [ "$1" = with ] && { sed '1,3d' "$FX/example-comment.md" >"$T/cost.txt"; bash "$RA" "${RM[@]}" --kind cost --on none --text-file "$T/cost.txt" >/dev/null 2>&1; }
    bash "$HERE/state-stored-set.sh" "${RM[@]}" --skip-session-checks --standing answer --what "panels are the cost" --owner "the human" 2>&1 \
        | grep -v '^record/entries/'
    session_state "$S" | jq -c '.standing | map(del(.set))'
}
WITHOUT=$(standing without)
case "$WITHOUT" in *'"standing":"s1","kind":"answer"'*) ok "state-stored-set.sh writes Standing s1 on a record without one" ;;
    *) bad "state-stored-set.sh writes Standing s1 on a record without one" "$WITHOUT" ;; esac
eq "  ... and the same with a cost entry on the record" "$WITHOUT" "$(standing with)"
seed
sed '1,3d' "$FX/example-comment.md" >"$T/cost.txt"
bash "$RA" "${RM[@]}" --kind cost --on none --text-file "$T/cost.txt" >/dev/null 2>&1; eq "state-entry.sh admits kind cost" 0 $?
eq "  ... and lists it back whole" "cost|$(cat "$T/cost.txt")" "$(bash "$RA" "${RM[@]}" --list | jq -r '.[0] | "\(.kind)|\(.text)"')"

done_tests unit-cost
