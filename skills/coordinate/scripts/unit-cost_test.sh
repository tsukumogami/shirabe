#!/usr/bin/env bash
# unit-cost_test.sh -- unit-cost.sh, the teardown pass's cost capture, over
# fixture archives, the gh and koto stand-ins, and the real record scripts.
#
# Covers: the example unit (testdata/unit-cost/archive) captured end to end:
# the posted comment is a summary line, a blank line and one fenced json
# block, committed as example-comment.md, whose object is example-entry.json,
# the archive's unit-cost.json is the same object, and RESULT, MANIFEST and
# README are byte-identical before and after; compute printing one compact
# object with every field of the entry, each figure not taken listed in
# `missing` with a reason from the closed list; plan shape for each /deliver
# mode, each /execute template, each /work-on mode, none of them, a /deliver
# with no plan_execution_mode, and a coordinated /deliver with plan_backed
# children; the milestone for each Unit form, a discipline record, a failed
# run-facts or Holdings read, a missing row and a Unit outside the safety
# pattern; dispatch from the request, from the job, and neither; the token
# rows by message id (a nested transcript, an id written three times with
# usage rising then falling, a non-string id, a line that isn't JSON);
# two pull requests in two repositories, and one the verdict doesn't name;
# one entry per key (twice posts once, another key's entry doesn't stop a
# post, a failed list posts anyway); missing transcripts, a failing `gh run
# list`, a failing `gh pr view` and a spent budget still posting an entry with
# complete false; the GitHub wrapper's admitted and refused calls; no GitHub
# write across the suite but one comment POST per captured unit; and the
# scripts that read record entries (record-state.sh, through
# record-append.sh --list, is the one) giving the same output with a cost
# entry on the record.
#
# Usage: bash skills/coordinate/scripts/unit-cost_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
UC="$HERE/unit-cost.sh"
RA="$HERE/record-append.sh"
FX="$HERE/testdata/unit-cost"
KEY=2026-10-01-feat-x-0a1b2c3d
MERGE=5555555555555555555555555555555555555555
MERGE2=6666666666666666666666666666666666666666
export KOTO_REQUESTS="$FX/requests" UNIT_COST_NOW=2026-10-01T12:00:00Z UNIT_COST_FETCH_SECS=5
TITLE="Coordinator record: ROADMAP-x"
S=coordinate-roadmap-x-20261001T080000Z
REASONS='["no source","read failed","time limit","entry size","invalid input"]'
POSTED=0
: >"$T/allcalls"

# seed [unit]: the record (#7, ROADMAP-x on acme/widgets) holding feat-x with
# that Unit, and the merged pull requests the fixtures name.
seed() {
    cat "$GH_DB.calls" >>"$T/allcalls" 2>/dev/null
    db_init
    local rec
    rec=$(record_json roadmap x | jq -c --argjson h "$(holding feat-x "$(jq -nc --arg u "${1:-Feature 4: Example feature}" '{unit: $u}')")" '.holdings = [$h]')
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$rec" issue 2026-10-01T08:00:00Z)"
    db '.prs += [
        {repo: "acme/widgets", number: 21, title: "feat: x", body: "", state: "MERGED", isDraft: false, isCrossRepository: false,
         baseRefName: "main", headRefName: "feat/x", headRefOid: $m, author: "alice", editor: null, mergedAt: "2026-10-01T11:30:00Z", mergeCommit: $m},
        {repo: "acme/widgets", number: 22, title: "feat: x again", body: "", state: "MERGED", isDraft: false, isCrossRepository: false,
         baseRefName: "main", headRefName: "feat/x", headRefOid: $n, author: "alice", editor: null, mergedAt: "2026-10-01T11:31:00Z", mergeCommit: $n},
        {repo: "acme/gadgets", number: 5, title: "feat: x", body: "", state: "MERGED", isDraft: false, isCrossRepository: false,
         baseRefName: "main", headRefName: "feat/x", headRefOid: $n, author: "alice", editor: null, mergedAt: "2026-10-01T11:20:00Z", mergeCommit: $n}]' \
        --arg m "$MERGE" --arg n "$MERGE2"
}
fresh() { rm -rf "$T/a"; mkdir -p "$T/a"; cp -R "$FX/archive/$KEY" "$T/a/"; A="$T/a/$KEY"; }
prs() { printf '%s\n' "$@" >"$T/prs"; }
compute() { bash "$UC" compute --archive "$A" --topic feat-x --prs-file "$T/prs" "$@" 2>"$T/err"; }
capture() { bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"; }
# posted: the bodies of the cost entries on #7, as a JSON array.
cost_bodies() { jq -c '[.comments // [] | .[] | select(.number == 7) | .body | select(startswith("<!-- coordinator-record-entry v1 kind=cost -->"))]' "$GH_DB"; }
block() { sed -n '/^```json$/,/^```$/p' | sed '1d;$d'; }
q() { printf '%s' "$1" | jq -r "$2"; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi; }

found_session "$S" "$(roadmap_vars x)" 7

echo "== the example unit, captured =="
seed; fresh; prs "acme/widgets#21 $MERGE"
BEFORE="$(sha "$A/RESULT") $(sha "$A/MANIFEST") $(sha "$A/README.md")"
capture; eq "the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... one cost entry" 1 "$(cost_bodies | jq length)"
BODY=$(cost_bodies | jq -r '.[0]')
eq "RESULT, MANIFEST and README are byte-identical after the capture" "$BEFORE" "$(sha "$A/RESULT") $(sha "$A/MANIFEST") $(sha "$A/README.md")"
eq "the posted object is example-entry.json" "$(jq -S . "$FX/example-entry.json")" "$(printf '%s\n' "$BODY" | block | jq -S . 2>&1)"
eq "the archive's unit-cost.json is the same object" "$(jq -S . "$FX/example-entry.json")" "$(jq -S . "$A/unit-cost.json" 2>&1)"
norm() { sed '2s/^\*\*[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z\*\*/**STAMP**/'; }
eq "the posted comment is example-comment.md, but for the host-clock stamp" "$(norm <"$FX/example-comment.md")" "$(printf '%s\n' "$BODY" | norm)"
eq "example-comment.md's json block is example-entry.json" "$(jq -S . "$FX/example-entry.json")" "$(block <"$FX/example-comment.md" | jq -S . 2>&1)"
TEXT=$(printf '%s\n' "$BODY" | sed '1,3d')
eq "the text is a summary line, a blank line and one fenced json block" "Cost|blank|fence|{|fence|5" \
    "$(printf '%s\n' "$TEXT" | awk 'NR==1{a=substr($0,1,4)} NR==2{b=($0==""?"blank":$0)} NR==3{c=($0=="```json"?"fence":$0)} NR==4{d=substr($0,1,1)} NR==5{e=($0=="```"?"fence":$0)} END{print a"|"b"|"c"|"d"|"e"|"NR}')"
eq "  ... the summary line" "Cost of feat-x ($KEY): 5 sessions, 90 output tokens, dispatch to merge not recoverable." "$(printf '%s\n' "$TEXT" | head -n 1)"
printf '%s\n' "$TEXT" | sed -n 4p | jq -e 'type == "object"' >/dev/null && ok "  ... the json line is one compact object" || bad "  ... the json line is one compact object" "$TEXT"
E=$(jq -c . "$A/unit-cost.json")
eq "the record's facts and the Unit's tag" '{"scope":"roadmap","name":"x","repo":"acme/widgets","ref":"7"}|Feature 4' "$(q "$E" '"\(.record | tojson)|\(.unit)"')"
eq "  ... the milestone" '{"value":{"roadmap":"ROADMAP-x","tag":"Feature 4"},"state":"measured","source":"record"}' "$(q "$E" '.milestone | tojson')"

echo "== compute: the entry's fields =="
fresh; prs "acme/widgets#21 $MERGE"
OUT=$(compute); eq "compute exits 0" 0 $?
eq "one line of output" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
eq "every field of the entry, in order" "schema key captured_at topic record unit milestone plan_shape pulls dispatch figures sessions tokens complete missing" \
    "$(q "$OUT" 'keys_unsorted | join(" ")')"
eq "schema" "unit-cost/1" "$(q "$OUT" .schema)"
eq "every baseline figure" "dispatch_to_green_min dispatch_to_merge_min writing_code_min review_min outside_share_pct review_share_pct panel_rounds failing_heads sessions_without_done summed_session_span_min minutes_per_unit" \
    "$(q "$OUT" '.figures | keys_unsorted | join(" ")')"
eq "each figure is {value, raw, state, source}" true "$(q "$OUT" '[.figures[] | keys_unsorted == ["value", "raw", "state", "source"]] | all')"
eq "each per-session entry carries its fields and no name" true \
    "$(q "$OUT" '[.sessions[] | keys_unsorted == ["index", "template", "unit_session", "done", "span_s", "states", "figures"]] | all')"
eq "  ... in byte order of the names: deliver, execute, two work-on children, scope" "deliver execute work-on work-on scope|false false true true false" \
    "$(q "$OUT" '"\([.sessions[].template] | join(" "))|\([.sessions[].unit_session | tostring] | join(" "))"')"
eq "every figure not taken is not recoverable and listed with a closed-list reason" true \
    "$(printf '%s' "$OUT" | jq --argjson r "$REASONS" '. as $e | [.figures | to_entries[] | select(.value.state == "not recoverable") | .key as $k
        | any($e.missing[]; .figure == $k and (.reason as $x | $r | index([$x]) != null))] | all')"
eq "every missing reason is from the closed list" true "$(printf '%s' "$OUT" | jq --argjson r "$REASONS" '[.missing[].reason as $x | $r | index([$x]) != null] | all')"
eq "complete is false while any figure is missing" false "$(q "$OUT" .complete)"
eq "without the record's facts the milestone is not recoverable" "null|not recoverable|no source" \
    "$(q "$OUT" '"\(.record)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"')"
printf '%s' "$OUT" | grep -q 'execute-x\|deliver-x\|scope-x\|/work/inst\|r_dispatch_x\|0a1b2c3d-77aa' \
    && bad "no session name, request id, session id or path is in the entry" "$OUT" || ok "no session name, request id, session id or path is in the entry"
printf 'acme/widgets#21 %s\n' "$MERGE" >"$T/prs"
bash "$UC" compute --archive "$A" --topic feat-y --prs-file "$T/prs" >/dev/null 2>&1; eq "an archive not named for the topic is refused" 65 $?
bash "$UC" compute --archive "$A" --topic 'Feat X' --prs-file "$T/prs" >/dev/null 2>&1; eq "a topic outside the grammar is a usage error" 64 $?
bash "$UC" capture --archive "$A" --topic feat-x --prs-file "$T/prs" >/dev/null 2>&1; eq "capture without a session is a usage error" 64 $?

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
mkarch; mksess deliver-x deliver deliver.md "" weekly
eq "a /deliver session whose value is outside the set" "null not recoverable" "$(shape)"
mkarch; mksess deliver-x deliver deliver.md "" coordinated
mksess deliver-x.o-a work-on work-on.md plan_backed; mksess deliver-x.o-b work-on work-on.md plan_backed
eq "a coordinated /deliver with plan_backed /work-on children" "coordinated measured" "$(shape)"

echo "== milestone =="
fresh
ms() { # ms <unit-json>: "<unit>|<milestone value>|<state>|<reason>"
    printf '%s' "$1" >"$T/unit.json"
    compute --unit-json "$T/unit.json" | jq -c -r '"\(.unit)|\(.milestone.value | tojson)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone" or .figure == "record" or .figure == "unit") | "\(.figure):\(.reason)"] | join(","))"'
}
# rj <unit> [reason]: the roadmap record's facts with that Unit (null when
# empty) and the reason it wasn't read.
rj() {
    jq -nc --arg u "$1" --arg r "${2:-}" '{scope: "roadmap", name: "x", repo: "acme/widgets", ref: "7",
        unit: (if $u == "" then null else $u end)} + (if $r == "" then {} else {unit_reason: $r} end)'
}
eq "Unit Feature 4" 'Feature 4|{"roadmap":"ROADMAP-x","tag":"Feature 4"}|measured|' "$(ms "$(rj 'Feature 4')")"
eq "Unit Feature 4: Title" 'Feature 4|{"roadmap":"ROADMAP-x","tag":"Feature 4"}|measured|' "$(ms "$(rj 'Feature 4: Title')")"
eq "Unit Spike: x" 'Spike|{"roadmap":"ROADMAP-x","tag":"Spike"}|measured|' "$(ms "$(rj 'Spike: x')")"
eq "Unit owner/repo#12" 'owner/repo#12|"none"|measured|' "$(ms "$(rj 'owner/repo#12')")"
eq "Unit #12" '#12|"none"|measured|' "$(ms "$(rj '#12')")"
eq "a discipline record" 'Feature 4|"none"|measured|' "$(ms '{"scope":"discipline","name":"ci","repo":"acme/widgets","ref":"22","unit":"Feature 4"}')"
eq "a failed run-facts read" 'null|null|not recoverable|record:read failed,milestone:read failed' "$(ms '{"unit_reason":"read failed"}')"
eq "a failed Holdings read" 'null|null|not recoverable|milestone:read failed' "$(ms "$(rj '' 'read failed')")"
eq "a Holdings read with no row for the topic" 'null|null|not recoverable|milestone:no source' "$(ms "$(rj '' 'no source')")"
eq "a Unit outside the safety pattern" 'null|null|not recoverable|milestone:invalid input' "$(ms "$(rj 'Feature 4; rm -rf x')")"
eq "  ... a backtick" 'null|null|not recoverable|milestone:invalid input' "$(ms "$(rj 'Feat`ure')")"
eq "  ... one over 64 characters" 'null|null|not recoverable|milestone:invalid input' \
    "$(ms "$(rj 'F1234567890123456789012345678901234567890123456789012345678901234')")"
eq "record facts that aren't facts" 'null|null|not recoverable|record:invalid input,milestone:invalid input' "$(ms '{"scope":"roadmap","name":"../x","repo":"acme/widgets","ref":"7","unit":"Feature 4"}')"

echo "== milestone, through the capture's own reads =="
fresh; prs "acme/widgets#21 $MERGE"
seed; R2=$(record_json roadmap x | jq -c --argjson h "$(holding other-topic '{"unit": "Feature 9"}')" '.holdings = [$h]')
db '.issues[0].body = $b' --arg b "$(render "$R2" issue 2026-10-01T08:00:00Z)"
capture; eq "a record with no row for the topic still posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... the milestone not recoverable, no source" "not recoverable|no source" \
    "$(jq -r '"\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
seed; fresh
db '.fail = [{match: "issue view 7", rc: 1, stderr: "HTTP 502"}]'
capture; eq "a failed Holdings read (and so a failed post) exits 1" 1 $?
eq "  ... the archive copy says read failed" "not recoverable|read failed" \
    "$(jq -r '"\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
eq "  ... and the last stderr line is a fixed string" "unit-cost: the post failed (record-append exit 2)" "$(tail -n 1 "$T/cap.err")"
seed; fresh
NOREC=coordinate-roadmap-x-20261001T090000Z
log_new "$NOREC" "$(roadmap_vars x)"
bash "$UC" capture --session "$NOREC" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "a failed run-facts read (no found record) exits 1" 1 $?
eq "  ... the archive copy has no record and the milestone read failed" "null|not recoverable|read failed" \
    "$(jq -r '"\(.record)|\(.milestone.state)|\([.missing[] | select(.figure == "milestone") | .reason][0])"' "$A/unit-cost.json")"
rm -rf "${KOTO_STORE:?}/sessions/$NOREC"

echo "== dispatch =="
fresh; prs "acme/widgets#21 $MERGE"
disp() { compute | jq -r '"\(.dispatch.value) \(.dispatch.state) \(.dispatch.source)"'; }
eq "from the request no archived session asked for" "2026-10-01T09:00:00.000Z measured koto-request" "$(disp)"
eq "with no request on the host, from the job" "2026-10-01T08:59:58.000Z measured job-state" "$(KOTO_REQUESTS="$T/none" disp)"
mkdir -p "$T/nested-only"; cp -R "$FX/requests/r_nested_x" "$T/nested-only/"
eq "a request an archived session asked for is not the dispatch" "2026-10-01T08:59:58.000Z measured job-state" "$(KOTO_REQUESTS="$T/nested-only" disp)"
rm -f "$A/job/state.json"
eq "with neither, not recoverable" "null not recoverable koto-request" "$(KOTO_REQUESTS="$T/none" disp)"
eq "  ... and listed" "no source" "$(KOTO_REQUESTS="$T/none" compute | jq -r '[.missing[] | select(.figure == "dispatch") | .reason][0]')"
fresh
printf 'request_id = "../../etc"\n' >"$A/koto/deliver-x/request-leg.toml"
eq "a request id outside koto's grammar builds no path" "2026-10-01T08:59:58.000Z measured job-state" "$(KOTO_REQUESTS="$T/nested-only" disp)"

echo "== tokens =="
fresh
tok() { compute | jq -c -r ".tokens.$1 | \"\(.messages) \(.input) \(.output) \(.cache_creation) \(.cache_read) \(.state)\""; }
eq "the worker row: its transcript and subagents/, by message id" "3 20 90 150 120 measured" "$(tok worker)"
eq "the nested row: the other transcript only" "1 2 8 0 40 measured" "$(tok nested)"
W="$A/transcript/0a1b2c3d-77aa.jsonl"
for u in '"output_tokens":50,"cache_read_input_tokens":5' '"output_tokens":80,"cache_read_input_tokens":5' '"output_tokens":60,"cache_read_input_tokens":5'; do
    printf '{"type":"assistant","message":{"id":"msg_t","usage":{"input_tokens":1,%s}}}\n' "$u" >>"$W"
done
eq "an id written three times, output rising then falling, counts once at its largest" "4 21 170 150 125 measured" "$(tok worker)"
printf '{"type":"assistant","message":{"id":7,"usage":{"output_tokens":1000}}}\n{"type":"assistant","message":{"usage":{"output_tokens":1000}}}\n' >>"$W"
eq "an assistant line with a non-string or no id is skipped" "4 21 170 150 125 measured" "$(tok worker)"
printf '{"type":"assistant","message":{"id":"msg_n2","usage":{"output_tokens":1}}\n' >>"$A/transcript/0a1b2c3d-77aa/workflows/flow-1.jsonl"
eq "a line that isn't JSON makes its row not recoverable" "null null null null null not recoverable" "$(tok nested)"
eq "  ... with reason invalid input, the other row kept" "invalid input|measured" \
    "$(compute | jq -r '"\([.missing[] | select(.figure == "tokens.nested") | .reason][0])|\(.tokens.worker.state)"')"

echo "== pull requests =="
fresh; seed
prs "acme/widgets#21 $MERGE" "acme/gadgets#5 $MERGE2"
OUT=$(compute)
eq "a verdict naming two pull requests in two repositories records both" \
    '[{"repo":"acme/widgets","number":21,"merge_commit":"'"$MERGE"'","merged_at":"2026-10-01T11:30:00Z"},{"repo":"acme/gadgets","number":5,"merge_commit":"'"$MERGE2"'","merged_at":"2026-10-01T11:20:00Z"}]' \
    "$(q "$OUT" '.pulls | tojson')"
eq "  ... each carrying the unit's one plan shape" "single-pr measured" "$(q "$OUT" '"\(.plan_shape.value) \(.plan_shape.state)"')"
eq "a pull request the verdict doesn't name is absent" 0 "$(q "$OUT" '[.pulls[] | select(.number == 22)] | length')"
prs "acme/widgets#21 $MERGE" "-x/y#3 $MERGE" "acme/widgets#0 $MERGE"
eq "a verdict line outside the shapes is left out, invalid input" "1|invalid input" \
    "$(compute | jq -r '"\(.pulls | length)|\([.missing[] | select(.figure == "pulls") | .reason][0])"')"

echo "== one entry per key =="
seed; fresh; prs "acme/widgets#21 $MERGE"
capture; eq "a first capture posts" 0 $?
POSTED=$((POSTED + 1))
capture; eq "a second capture of the same unit exits 0" 0 $?
eq "  ... having posted nothing" 1 "$(cost_bodies | jq length)"
eq "  ... and says so" "unit-cost: the record already holds this unit's cost entry" "$(tail -n 1 "$T/cap.err")"
mkdir -p "$T/b"; rm -rf "$T/b/2026-10-02-feat-x-0a1b2c3d"; cp -R "$A" "$T/b/2026-10-02-feat-x-0a1b2c3d"
bash "$UC" capture --session "$S" --archive "$T/b/2026-10-02-feat-x-0a1b2c3d" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "a record holding a cost entry for another key still gets this one" "0 2" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
db '.fail = [{match: "issues/7/comments?per_page", rc: 1, stderr: "HTTP 502"}]'
capture; eq "a failed list posts anyway" "0 3" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
db '.fail = []'
eq "  ... a second entry for the key, which readers report as a repeat" 2 \
    "$(cost_bodies | jq --arg k "$KEY" '[.[] | split("\n") | .[6] | fromjson | select(.key == $k)] | length')"

echo "== partial entries =="
seed; fresh; prs "acme/widgets#21 $MERGE"
rm -rf "$A/transcript"
capture; eq "with the transcripts missing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, naming the token rows" "false|tokens.worker:no source,tokens.nested:no source" \
    "$(cost_bodies | jq -r '.[-1] | split("\n") | .[6] | fromjson | "\(.complete)|\([.missing[] | select(.figure | startswith("tokens")) | "\(.figure):\(.reason)"] | join(","))"')"
# A failing `gh run list` alone. The run-derived figures (failing_heads,
# green) are not measured yet, so this pins only that the capture posts and
# names them; once they are, the same case shows the read's own failure.
seed; fresh
db '.fail = [{match: "run list", rc: 1, stderr: "HTTP 502"}]'
capture; eq "with gh run list failing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, naming the run figures" "false|failing_heads,dispatch_to_green_min" \
    "$(cost_bodies | jq -r '.[-1] | split("\n") | .[6] | fromjson | "\(.complete)|\([.missing[] | select(.figure == "failing_heads" or .figure == "dispatch_to_green_min") | .figure] | sort_by(. != "failing_heads") | join(","))"')"
seed; fresh
db '.fail = [{match: "pr view 21", rc: 1, stderr: "HTTP 502"}]'
capture; eq "with gh pr view failing, the capture posts" 0 $?
POSTED=$((POSTED + 1))
eq "  ... complete false, the merge time read failed, the pull request kept" "false|read failed|21|null" \
    "$(cost_bodies | jq -r '.[-1] | split("\n") | .[6] | fromjson | "\(.complete)|\([.missing[] | select(.figure == "pulls.merged_at") | .reason][0])|\(.pulls[0].number)|\(.pulls[0].merged_at)"')"
seed; fresh
UNIT_COST_BUDGET_SECS=0 bash "$UC" capture --session "$S" --archive "$A" --topic feat-x --prs-file "$T/prs" 2>"$T/cap.err"
eq "with the budget spent, the capture still posts" "0 1" "$? $(cost_bodies | jq length)"
POSTED=$((POSTED + 1))
eq "  ... what it could not take is time limit" "false|time limit|time limit|time limit" \
    "$(cost_bodies | jq -r '.[-1] | split("\n") | .[6] | fromjson | "\(.complete)|\([.missing[] | select(.figure == "milestone") | .reason][0])|\([.missing[] | select(.figure == "pulls.merged_at") | .reason][0])|\([.missing[] | select(.figure == "tokens.worker") | .reason][0])"')"

echo "== the archive copy =="
seed; fresh
ln -s "$T/elsewhere" "$A/unit-cost.json"
capture >/dev/null; POSTED=$((POSTED + 1))
[ ! -L "$A/unit-cost.json" ] && [ -f "$A/unit-cost.json" ] && [ ! -e "$T/elsewhere" ] \
    && ok "a symlink at unit-cost.json is replaced, never written through" || bad "a symlink at unit-cost.json is replaced, never written through"
LEFT=""
for f in "$A"/.unit-cost*; do [ -e "$f" ] && LEFT="$LEFT ${f##*/}"; done
eq "  ... and no temporary file is left" "" "$LEFT"

echo "== the GitHub wrapper =="
admit() { bash "$UC" gh-check "$@"; eq "admits: $*" 0 $?; }
refuse() { bash "$UC" gh-check "$@"; eq "refuses: $*" 1 $?; }
admit pr view 21 --repo acme/widgets --json mergedAt
admit run list --repo acme/widgets --branch feat/x --json databaseId,headSha,status,conclusion --limit 100
admit run list --repo acme/widgets --commit "$MERGE"
admit api --method GET repos/acme/widgets/pulls/21/commits --paginate
admit api --method GET repos/acme/widgets/actions/runs/9/attempts/1 --jq .conclusion
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

echo "== no write but the posts =="
cat "$GH_DB.calls" >>"$T/allcalls"
WRITES=$(grep -E -- '--method (POST|PATCH|PUT|DELETE)|-X |^(issue|pr) (create|edit|close|reopen|ready|merge|comment|review)|^run (rerun|cancel)|graphql' "$T/allcalls")
eq "every write is a comment POST on the record" "" "$(printf '%s\n' "$WRITES" | grep -v '^api --method POST repos/acme/widgets/issues/7/comments --input ' | grep . || true)"
eq "  ... one per captured unit" "$POSTED" "$(printf '%s\n' "$WRITES" | grep -c '^api --method POST repos/acme/widgets/issues/7/comments')"

echo "== the entries' readers =="
# record-state.sh chooses a Standing id from the entry stream (the one
# script that reads entries, through record-append.sh --list); a cost entry
# on the record changes nothing it prints or writes.
RM=(--scope roadmap --name x --repo acme/widgets --ref 7)
standing() {
    seed
    [ "$1" = with ] && { sed '1,3d' "$FX/example-comment.md" >"$T/cost.txt"; bash "$RA" "${RM[@]}" --kind cost --text-file "$T/cost.txt" >/dev/null 2>&1; }
    bash "$HERE/record-state.sh" "${RM[@]}" --skip-session-checks --standing answer --what "panels are the cost" --owner "the human" 2>&1 | sed 's/#issuecomment-[0-9]*//'
    jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh" | jq -c '.standing | map(del(.set))'
}
WITHOUT=$(standing without)
case "$WITHOUT" in *'"standing":"s1","kind":"answer"'*) ok "record-state.sh writes Standing s1 on a record without one" ;;
    *) bad "record-state.sh writes Standing s1 on a record without one" "$WITHOUT" ;; esac
eq "  ... and the same with a cost entry on the record" "$WITHOUT" "$(standing with)"
seed
sed '1,3d' "$FX/example-comment.md" >"$T/cost.txt"
bash "$RA" "${RM[@]}" --kind cost --text-file "$T/cost.txt" >/dev/null 2>&1; eq "record-append.sh admits kind cost" 0 $?
eq "  ... and lists it back whole" "cost|$(cat "$T/cost.txt")" "$(bash "$RA" "${RM[@]}" --list | jq -r '.[0] | "\(.kind)|\(.text)"')"

done_tests unit-cost
