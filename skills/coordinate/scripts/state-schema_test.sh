#!/usr/bin/env bash
# state-schema_test.sh -- state-schema.jq checks the coordinator state as JSON,
# and the write core runs it on the next state before anything is written.
#
# Covers: each refusal case fed as the state's JSON to check_record, and
# refused with its message (a disallowed top-level field, a control character,
# an empty required column, a recomputable column, an unknown column, a
# malformed worker, each column grammar, a malformed pull request link, a
# malformed hold or an illegal hold change, an unknown Run key, stored-set rows
# breaking their rules, an illegal Decisions state, transition or stamp, a
# private repository name, a home-directory path and a token-shaped string);
# the legacy `store session` Run row accepted, a `store github` row and any
# other value refused, and the crash-set rows allowed with no store row; the
# scan over every string in the state (scan_strings): each string path of a
# full state found, a field added at any depth found, a string no column check
# reads refused through check_record, a rotation's reasoning scanned; a valid
# state accepted and given back normalized; the module holding no markdown
# encoding, renderer or record parser (only the reader of a GitHub record's
# archived Decisions rows). Through state-write.sh and the core: a next state
# naming a private repository is refused from its JSON, and a refused schema
# rule, a stale read and a section owned by another writer flag each leave
# every key as it was.
#
# Needs bash and jq only.
# Usage: bash skills/coordinate/scripts/state-schema_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
W=2026-09-26T12:00:00Z
SHA40=0123456789abcdef0123456789abcdef01234567
# The shapes the checks refuse, put together at run time: the repository's
# public-content check refuses an added line that spells one out.
FX_UUID="w-6f1c2e3a-1b2c-4d5e-8f90-""123456789abc"
FX_INSTANCE="tsuku+topic-""43e4a66f"
FX_HOME_A="/ho""me/someone/notes"
FX_HOME_B="/Us""ers/bob/x"
FX_TOKEN="gh""p_abcdefghijklmnopqrstuvwxyz0123"

# check <json> [private-repos]: check_record over the JSON. Prints the
# refusal's message, from "refused: " on, or "ok" when it passes.
check() {
    printf '%s' "$1" > "$T/s.json"
    if jq -n -L "$HERE" --slurpfile s "$T/s.json" --arg private "${2-}" 'include "state-schema";
            $s[0] | check_record($private | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))) | empty' \
            2> "$T/s.err" < /dev/null; then
        echo ok
    else
        sed -n 's/.*\(refused: \)/\1/p' "$T/s.err" | sed -n 1p
    fi
}
# same <label> <json> <expected substring> [private-repos]: the JSON is refused
# by check_record with a message holding the substring.
same() {
    local got
    got=$(check "$2" "${4-}")
    case "$got" in
        "refused: "*"$3"*) ok "$1" ;;
        *) bad "$1" "want a refusal holding [$3], got [$got]" ;;
    esac
}
# passes <label> <json>: check_record accepts it.
passes() {
    local got
    got=$(check "$2")
    if [ "$got" = ok ]; then ok "$1"; else bad "$1" "schema [$got]"; fi
}

full_record() {
    jq -nc --arg sha "$SHA40" '{
      scope: {kind: "roadmap", name: "plugin-system"},
      holdings: [{unit: "Feature 2", entry_point: "/shirabe:deliver", mode: "--auto", phase: "executing",
                  dispatch_status: "dispatched", return_path: "message", worker: "plugin-registry", repo: "acme/widgets",
                  branch: "feat/x", verified_head: $sha, dispatched: "2026-09-26",
                  pull_request: "[#12](https://github.com/acme/widgets/pull/12)"}],
      deferrals: [{deferral: "flaky test", reason: "not now", raised: "2026-09-25T10:00Z", disposition: ""}],
      side_effects: [{action: "merge", target: "#12", verified_head: $sha, attempted: "2026-09-26T11:02Z", how_to_confirm: "compare blobs on main"}],
      reversals: [{date: "2026-09-26T09:15Z", reversed: "merge on green", now: "hold for release", reason: "release freeze", from: "the human"}]}'
}
with() { full_record | jq -c "$@"; }

echo "== the module's shape =="
# The module holds no markdown encoding, renderer or record parser. Its one
# reader of markdown is the archived Decisions rows a GitHub record's body put
# in `decisions` entries (d_archive_rows, with parse_drow, dec and dec_d), which
# state-decision.sh restores an archived entry from.
defs() { sed -nE 's/^def ([a-z_]+)(\(([^)]*)\))?:.*/\1(\3)/p' "$1"; }
SCHEMA_DEFS=$(defs "$HERE/state-schema.jq")
eq "state-schema.jq holds no encoding, renderer, record parser or handoff" "" \
    "$(printf '%s\n' "$SCHEMA_DEFS" | grep -E '^(enc|enc_d|normalized|split_cells|declaration|pr_prefix|scope_text)\(|^(render_|predecessor_)|^parse_' | grep -v '^parse_drow(')"
eq "its one error() is refuse()'s, so every refusal starts refused: " \
    'def refuse($m): error("refused: " + $m);' "$(grep -v '^ *#' "$HERE/state-schema.jq" | grep 'error(')"

echo "== a valid state =="
passes "a full record passes" "$(full_record)"
passes "an empty record passes" "$(record_json roadmap x)"
passes "a discipline record passes" "$(with '.scope = {kind: "discipline", name: "ci-health"}')"
eq "a missing optional column comes back empty and a blank Wakes as 0" '"" 0' \
    "$(jq -n -L "$HERE" --argjson s "$(with 'del(.holdings[0].mode) | .work = [{item: "x", kind: "local-agent", who: "me", next: "do it", wakes: "", updated: "2026-09-26T10:00Z"}]')" \
        'include "state-schema"; $s | check_record([]) | "\(.holdings[0].mode | tojson) \(.work[0].wakes)"' -r)"
eq "an absent optional section stays absent" '["deferrals","holdings","reversals","scope","side_effects"]' \
    "$(jq -nc -L "$HERE" --argjson s "$(full_record)" 'include "state-schema"; $s | check_record([]) | keys')"
eq "the written time is carried as it is" '"2026-09-26T09:00:00Z"' \
    "$(jq -nc -L "$HERE" --argjson s "$(with '.written = "2026-09-26T09:00:00Z"')" 'include "state-schema"; $s | check_record([]) | .written')"

echo "== top-level fields and scope =="
same "a disallowed top-level field" "$(with '.notes = "x"')" "notes: not a field"
same "a missing scope" "$(with 'del(.scope)')" "scope: missing"
same "a scope of another kind" "$(with '.scope.kind = "team"')" "scope.kind: not roadmap or discipline"
same "a scope name that isn't a name" "$(with '.scope.name = "a b"')" "scope.name: not a name"
same "a section that isn't a list" "$(with '.deferrals = {}')" "deferrals: not a list"

echo "== cells =="
same "a control character" "$(with '.deferrals[0].reason = "a\u0007b"')" "reason: a control character"
same "a control character in a text field" "$(with '.deferrals[0].reason = "a\u001fb"')" "control character"
same "an empty required column" "$(with '.holdings[0].unit = ""')" "unit: empty"
same "a cell that isn't a string" "$(with '.holdings[0].unit = 3')" "unit: not a string"
same "a status column, recomputable" "$(with '.holdings[0].status = "open"')" "read from GitHub, never recorded"
same "a CI column, recomputable" "$(with '.holdings[0].CI = "green"')" "read from GitHub, never recorded"
same "a merge-state column, recomputable" "$(with '.side_effects[0].merge_state = "CLEAN"')" "read from GitHub, never recorded"
same "an unknown column" "$(with '.deferrals[0].owner = "x"')" "deferrals.owner: not a column of this section"
same "a row that isn't an object" "$(with '.reversals = ["x"]')" "a row that isn't an object"
same "a bad phase" "$(with '.holdings[0].phase = "planning"')" "phase: not scoping"
same "a bad dispatch status" "$(with '.holdings[0].dispatch_status = "sent"')" "dispatch_status"
same "a bad return path" "$(with '.holdings[0].return_path = "leg"')" "return_path"
same "a short verified head" "$(with '.holdings[0].verified_head = "0123abc"')" "verified_head: not a full sha"
same "a repo that isn't owner/repo" "$(with '.holdings[0].repo = "widgets"')" "repo: not owner/repo"
same "a branch that isn't a branch name" "$(with '.holdings[0].branch = "a b"')" "branch: not a branch name"
same "a dispatched that isn't a date" "$(with '.holdings[0].dispatched = "today"')" "dispatched: not YYYY-MM-DD"
same "a date-only raised" "$(with '.deferrals[0].raised = "2026-09-25"')" "raised: not YYYY-MM-DDTHH:MMZ"
same "a date-only reversal date" "$(with '.reversals[0].date = "2026-09-25"')" "date: not YYYY-MM-DDTHH:MMZ"
same "filed without a number" "$(with '.deferrals[0].disposition = "filed"')" "disposition"
same "a carry without a time" "$(with '.deferrals[0].disposition = "carried: later"')" "disposition"
same "a decide-by that isn't a time" "$(with '.deferrals[0].disposition = "carried 2026-09-26T08:30Z until Friday: waits"')" "disposition"
passes "a carry with a decide-by passes" "$(with '.deferrals[0].disposition = "carried 2026-09-26T08:30Z until 2026-10-01T00:00Z: waits on infra"')"
same "an unknown milestone- Action" "$(with '.side_effects[0].action = "milestone-reopened"')" "is not one of the milestone roadmap edits"

echo "== workers =="
same "a worker path" "$(with '.holdings[0].worker = "instances/foo"')" "shape of a path"
same "a worker UUID" "$(with ".holdings[0].worker = \"$FX_UUID\"")" "instance or session id"
same "a worker session_ id" "$(with '.holdings[0].worker = "session_01ABCdef"')" "session id"
same "a worker instance name" "$(with ".holdings[0].worker = \"$FX_INSTANCE\"")" "instance name"
same "a worker job id" "$(with '.holdings[0].worker = "123456"')" "job id"
same "a worker that isn't a topic" "$(with '.holdings[0].worker = "_lead"')" "not a dispatch topic"
passes "a dispatch topic passes as a worker" "$(with '.holdings[0].worker = "coordinate-dispatch-path.v2_a"')"

echo "== pull request links =="
same "a malformed pull request link" "$(with '.holdings[0].pull_request = "#12"')" "pull_request: not [#n]"
same "  ... or one on another host" "$(with '.holdings[0].pull_request = "[#12](https://example.com/acme/widgets/pull/12)"')" "pull_request"
passes "an empty pull request link (none yet) passes" "$(with '.holdings[0].pull_request = "" | .holdings[0].branch = "" | .holdings[0].verified_head = ""')"

echo "== Holds =="
HOLD_A='{"hold":"after-346","on":"acme/widgets#12","until":"merged acme/gadgets#346","set_by":"the workspace coordinator","set":"2026-09-26T09:00Z","lifted":""}'
HOLD_C='{"hold":"go","on":"acme/widgets#14","until":"lifted","set_by":"the human","set":"2026-09-26T09:10Z","lifted":"2026-09-26T10:00Z by the human"}'
hold() { full_record | jq -c --argjson a "$HOLD_A" --argjson c "$HOLD_C" "$1"; }
passes "holds of a merge and a lifted condition pass" "$(hold '.holds = [$a, $c]')"
same "a malformed Until" "$(hold '.holds = [$a | .until = "until Monday"]')" "holds.until"
same "On that isn't owner/repo#n" "$(hold '.holds = [$a | .on = "#12"]')" "holds.on"
same "a lift that isn't a time and who" "$(hold '.holds = [$c | .lifted = "yesterday"]')" "holds.lifted"
same "a lifted cell on a merged condition, an illegal change" "$(hold '.holds = [$a | .lifted = "2026-09-26T10:00Z by me"]')" "only a \`lifted\` hold is lifted by hand"
same "two holds of one name" "$(hold '.holds = [$a, $a]')" "a hold name is used twice"
same "a column outside the section" "$(hold '.holds = [$a + {state: "met"}]')" "holds.state: not a column"
same "a hold with a line break" "$(hold '.holds = [$a | .set_by = "one\ntwo"]')" "holds.set_by: a line break"
same "holds that aren't a list" "$(hold '.holds = {}')" "holds: not a list"

echo "== the stored set =="
RR() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "alice", set: "2026-10-13T10:00Z"}'; }
RUNS() { full_record | jq -c --argjson r "[$1]" '.run = $r'; }
SHA64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
STORE=$(RR store session)
same "an unknown Run key" "$(RUNS "$(RR colour blue)")" "run.key: not one of"
same "a cap that isn't 1 to 99" "$(RUNS "$(RR cap 100)")" "a cap is a number from 1 to 99"
same "a coordinator address shaped like a path" "$(RUNS "$(RR coordinator a/b)")" "shape of a path"
same "a party told twice" "$(RUNS "$(RR told lead), $(RR told lead)")" "a party is told twice"
same "a key other than told used twice" "$(RUNS "$(RR cap 3), $(RR cap 4)")" "a key other than told, pending, rules and briefs is used twice"
same "a store row reading github is refused" "$(RUNS "$(RR store github)")" "the store is the session; a store row reads session, never github"
passes "the legacy store row reading session an existing session holds passes" "$(RUNS "$STORE")"
same "a store row reading anything else" "$(RUNS "$(RR store gitlab)")" "the store is the session; a store row reads session, never gitlab"
same "  ... or one used twice" "$(RUNS "$STORE, $(RR store session)")" "the store row is used twice"
passes "the crash set passes with no store row" \
    "$(RUNS "$(RR rules "skill-rules sha256:$SHA64"), $(RR briefs "brief sha256:$SHA64"), $(RR friction friction-log), $(RR reports-to "the lead at ws-lead")")"
passes "  ... and beside the legacy store session row" \
    "$(RUNS "$STORE, $(RR rules "skill-rules sha256:$SHA64"), $(RR friction friction-log)")"
for k in rules briefs friction reports-to; do
    v="a sha256:$SHA64"; [ "$k" = friction ] && v=a; [ "$k" = reports-to ] && v="the human"
    passes "a $k row alone passes" "$(RUNS "$(RR "$k" "$v")")"
done
same "two friction rows" "$(RUNS "$STORE, $(RR friction a), $(RR friction b)")" "used twice"
same "a reports-to address shaped like a path" "$(RUNS "$STORE, $(RR reports-to "the lead at /tmp/x")")" "shape of a path"
same "a rules digest that isn't sha256 hex" "$(RUNS "$STORE, $(RR rules "a sha256:abc")")" "<label> sha256:<64 hex>"
same "a rules label used twice" "$(RUNS "$STORE, $(RR rules "a sha256:$SHA64"), $(RR rules "a sha256:$SHA64")")" "label is used twice"
same "a friction row that isn't a label" "$(RUNS "$STORE, $(RR friction "a b")")" "a friction row is a label"
same "a reports-to address that is two words" "$(RUNS "$STORE, $(RR reports-to "the lead at ws lead")")" "is \`<role>\` or \`<role> at <address>\`"
ST() { jq -nc --arg k "$1" --arg on "$2" --arg u "$3" '{standing: "s1", kind: $k, on: $on, until: $u, what: "hold the merges", owner: "the human", relayed_by: "", set: "2026-10-13T10:00Z"}'; }
STS() { full_record | jq -c --argjson s "[$1]" '.standing = $s'; }
passes "a pause until a time passes" "$(STS "$(ST pause all "time 2026-10-14T00:00Z")")"
same "a pause with no Until" "$(STS "$(ST pause all "")")" "a pause names its On and its Until"
same "a pause-until that isn't a condition" "$(STS "$(ST pause all "tomorrow")")" "standing.until: not \`lifted\`"
same "a go-ahead with an Until" "$(STS "$(ST go-ahead "Feature 2" lifted)")" "a go-ahead has no Until"
same "a go-ahead for all" "$(STS "$(ST go-ahead all "")")" "a go-ahead names one unit"
same "an assignment whose On isn't an issue or release" "$(STS "$(ST assignment "Feature 2" "")")" "an assignment's On is an issue"
same "an approval with an On" "$(STS "$(ST approval "Feature 2" "")")" "only a pause, a go-ahead or an assignment has an On"
same "an unknown Standing kind" "$(STS "$(ST veto "" "")")" "standing.kind: not one of"
same "a Standing id that isn't s<n>" "$(STS "$(ST approval "" "" | jq -c '.standing = "x1"')")" "standing.standing: not s<n>"

echo "== rule rows and the Source column =="
SD=$HERE/testdata/standing-rules
SESS=coordinate-roadmap-rules-20261001T100000Z
# RULE <source>: a rule row, s3, with that Source.
RULE() { jq -nc --arg s "$1" '{standing: "s3", kind: "rule", on: "", until: "", what: "Read a CI run'"'"'s status at most once a minute.", owner: "", relayed_by: "", set: "2026-10-20T09:00Z", source: $s}'; }
for src in "decision $SESS 000000000007" "skill acme/widgets skills/coordinate/SKILL.md $SHA40" \
    "doc acme/widgets docs/designs/DESIGN-x.md $SHA40" "pinned charter sha256:$SHA64" "inferred" "inferred brief worker sha256:$SHA64"; do
    passes "a rule row with a ${src%% *} Source passes${src#inferred}" "$(STS "$(RULE "$src")")"
done
passes "an event row may carry a Source" "$(STS "$(ST approval "" "" | jq -c --arg s "skill acme/widgets skills/coordinate/SKILL.md $SHA40" '.source = $s')")"
passes "the fixture's four rule rows pass beside an event row" "$(full_record | jq -c --slurpfile r "$SD/rule-rows.json" --argjson e "$(ST approval "" "")" '.standing = [$e] + $r[0]')"
# Each malformed fixture is refused naming its row, s7.
for f in owner:"a rule row's Owner is blank" relayed-by:"a rule row's Relayed by is blank" no-source:"a rule row names its Source" \
    empty-source:"a rule row names its Source" on:"a rule row has no On and no Until" \
    decision-11-digits:"the Source names a decision id that isn't 12 digits" decision-dash-session:"the Source names a session that isn't a session name" \
    skill-dotdot:"the Source names a path that isn't relative, or that has a \`.\` or \`..\` segment" skill-39-hex:"the Source names a commit that isn't 40 hex"; do
    same "a rule row: ${f%%:*} is refused, naming standing.s7" "$(full_record | jq -c --slurpfile r "$SD/bad-${f%%:*}.json" '.standing = $r[0]')" "standing.s7: ${f#*:}"
done
same "a rule row with an Until" "$(STS "$(RULE inferred | jq -c '.until = "lifted"')")" "standing.s3: a rule row has no On and no Until"
same "a Source in no form" "$(STS "$(RULE "memo from the lead")")" "standing.s3: the Source is not one of"
same "a decision Source with a word missing" "$(STS "$(RULE "decision 000000000007")")" "is not \`decision <session> <12-digit id>\`"
same "a skill Source with an absolute path" "$(STS "$(RULE "skill acme/widgets /etc/x $SHA40")")" "names a path that isn't relative"
same "a doc Source naming a repository that isn't owner/repo" "$(STS "$(RULE "doc acme docs/x.md $SHA40")")" "names a repository that isn't owner/repo"
same "a pinned Source with a short digest" "$(STS "$(RULE "pinned charter sha256:abc")")" "names a digest that isn't sha256:<64 hex>"
same "an inferred Source with a stray word" "$(STS "$(RULE "inferred maybe")")" "is not \`inferred\` or \`inferred brief"
same "an inferred brief with a label that isn't one" "$(STS "$(RULE "inferred brief a/b sha256:$SHA64")")" "names a label that isn't"
same "an event row's Source is held to the same forms" "$(STS "$(ST approval "" "" | jq -c '.source = "decision s 7"')")" "standing.s1: the Source"
same "a Source naming a repository that isn't public" "$(STS "$(RULE "skill acme/secret skills/x/SKILL.md $SHA40")")" "standing.s3: the Source names acme/secret" acme/secret
same "an event row's empty Owner is still refused" "$(STS "$(ST approval "" "" | jq -c '.owner = ""')")" "standing.owner: empty"
# normal <standing-json>: the Standing rows normalize_state gives back.
normal() { full_record | jq -c --argjson s "$1" '.standing = $s' | jq -c -L "$HERE" 'include "state-schema"; normalize_state([]) | .standing'; }
eq "an empty Source is left out of the normal form" "$(jq -c '[.[0] | del(.source)] + [.[1]]' "$SD/standing-empty-source.json")" \
    "$(normal "$(cat "$SD/standing-empty-source.json")")"
eq "  ... and a row written before the column comes back as it was, byte for byte" "$(cat "$SD/standing-today.json")" \
    "$(normal "$(cat "$SD/standing-today.json")")"
eq "  ... and a rule row keeps its columns in the normal form's order" "$(cat "$SD/rule-rows.json")" "$(normal "$(cat "$SD/rule-rows.json")")"
# rule_class and rule_view, over the fixture's rows and an event row.
view() { jq -r -L "$HERE" --arg s "$SESS" --argjson e "${2:-[]}" 'include "state-schema"; .[] | rule_view($s; $e) | [.class, .status, .confirm, .owner, .said, .words, .reversal, (.pointer | tostring)] | map(tostring) | join("|")' <<< "$1"; }
D64=sha256:1111111111111111111111111111111111111111111111111111111111111111
eq "an inferred brief rule reads inferred, unconfirmed, to confirm, with its brief's label and digest" \
    "inferred|unconfirmed|true|null|2026-10-20T09:00Z|null|null|{\"brief\":\"worker\",\"digest\":\"$D64\"}" "$(view "$(jq -c '[.[0]]' "$SD/rule-rows.json")")"
eq "a skill rule reads skill-says, in force, with its repository, path and commit" \
    'skill-says|in-force|false|null|2026-10-20T09:01Z|null|null|{"repo":"acme/widgets","path":"skills/coordinate/SKILL.md","commit":"0123456789abcdef0123456789abcdef01234567"}' \
    "$(view "$(jq -c '[.[1]]' "$SD/rule-rows.json")")"
eq "a pinned rule reads charter, with its label and digest" \
    'charter|in-force|false|null|2026-10-20T09:02Z|null|null|{"pinned":"charter","digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}' \
    "$(view "$(jq -c '[.[2]]' "$SD/rule-rows.json")")"
eq "a decision rule reads unreadable twice over, with the session and id, and no owner or time" \
    "unreadable|unreadable|false|null|null|null|null|{\"decision\":\"$SESS 000000000007\"}" "$(view "$(jq -c '[.[3]]' "$SD/rule-rows.json")")"
eq "a doc rule reads charter, as a pinned one does, pointing at its repository, path and commit" \
    "charter|in-force|{\"repo\":\"acme/widgets\",\"path\":\"docs/x.md\",\"commit\":\"$SHA40\"}" \
    "$(view "$(jq -nc --arg s "doc acme/widgets docs/x.md $SHA40" '[{standing: "s4", kind: "rule", what: "x", set: "2026-10-20T09:00Z", source: $s}]')" | cut -d'|' -f1,2,8)"
eq "the class order --rules --counts prints" "relayed owner-said dispatcher-said inferred skill-says charter unreadable" \
    "$(jq -nr -L "$HERE" 'include "state-schema"; rule_classes | join(" ")')"
eq "rule_counts counts each row by its class, a class no row reads with 0" \
    "relayed 1|owner-said 0|dispatcher-said 0|inferred 1|skill-says 1|charter 2|unreadable 1" \
    "$(jq -r -L "$HERE" --arg d "doc acme/widgets docs/x.md $SHA40" 'include "state-schema"; . + [{source: $d}, {source: ""}] | rule_counts' "$SD/rule-rows.json" | tr '\n' '|' | sed 's/|$//')"
eq "a bare inferred rule points at its own row" "inferred|{\"row\":\"$SESS record/standing s4\"}" \
    "$(view '[{"standing":"s4","kind":"rule","what":"x","set":"2026-10-20T09:00Z","source":"inferred"}]' | cut -d'|' -f1,8)"
ENT='[{"id":1,"kind":"pause","text":"s1 (pause on Feature 1, until lifted): hold. Owner: the human."},{"id":2,"kind":"answer","text":"s2 (answer): panels. Owner: the human."},{"id":3,"kind":"end","text":"s1 (pause: hold) ended by the human."}]'
eq "a relayed row reads relayed, in force, its Owner, its Set, and the entry its own write made" \
    "relayed|in-force|false|the human|2026-10-07T10:00Z|null|null|{\"entry\":\"$SESS record/entries/000001\"}" \
    "$(view "$(jq -c '[.[0]]' "$SD/standing-today.json")" "$ENT")"
eq "  ... the second row its own entry, not the newest" "{\"entry\":\"$SESS record/entries/000002\"}" \
    "$(view "$(jq -c '[.[1]]' "$SD/standing-today.json")" "$ENT" | cut -d'|' -f8)"
eq "  ... and a row no entry matches points at itself" "{\"row\":\"$SESS record/standing s2\"}" \
    "$(view "$(jq -c '[.[1]]' "$SD/standing-today.json")" '[]' | cut -d'|' -f8)"
eq "no rule_view object has a grants key" false "$(jq -c -L "$HERE" --arg s "$SESS" 'include "state-schema"; [.[] | rule_view($s; [])] | any(has("grants"))' "$SD/rule-rows.json")"
WK() { jq -nc --arg i "$1" --arg k "$2" --arg w "$3" --arg n "$4" '{item: $i, kind: $k, who: $w, next: $n, wakes: "0", updated: "2026-10-09T10:00Z"}'; }
WKS() { full_record | jq -c --argjson w "[$1]" '.work = $w'; }
same "an unknown Work kind" "$(WKS "$(WK x verdict-due me go)")" "work.kind: not holding"
same "a Wakes that isn't a count" "$(WKS "$(WK x local-agent me go | jq -c '.wakes = "many"')")" "work.wakes: not a count"
same "a holding row whose Who isn't a topic" "$(WKS "$(WK x holding a/b go)")" "shape of a path"
same "a decision row whose Item isn't a unit" "$(WKS "$(WK "Feature 03" decision "decision 1" go)")" "Item is a unit as pick lists it"
same "a decision row whose Who isn't decision <n>" "$(WKS "$(WK "Feature 3" decision "entry 1" go)")" "a decision row's Who is \`decision <n>\`"
same "a follow-up row whose Who isn't owner/repo#n" "$(WKS "$(WK "Feature 3" follow-up "#3" go)")" "a follow-up row's Who is the pull request"
same "a verdict-owed row whose Item isn't a heading tag" "$(WKS "$(WK "the list" verdict-owed none "verdict owed since 2026-10-09")")" "a verdict-owed row's Item is a milestone's heading tag"
same "a verdict-owed row whose Next step isn't its date" "$(WKS "$(WK MV1 verdict-owed none "judge it")")" "verdict owed since YYYY-MM-DD"
same "a rework text over 600 bytes" "$(WKS "$(WK MV2 rework "verdict 1001" "x" | jq -c '.next = ("Changes needed: " + ("x" * 585))')")" "over 600 bytes"
same "a rework text with a URL" "$(WKS "$(WK MV2 rework "verdict 1001" "see https://example.com/x")")" "a URL"
same "  ... or a bare www. address" "$(WKS "$(WK MV2 rework "verdict 1001" "see www.example.com")")" "a URL"
same "  ... or another scheme" "$(WKS "$(WK MV2 rework "verdict 1001" "fetch ftp://host/x")")" "a URL"
same "a rework text with a markdown link" "$(WKS "$(WK MV2 rework "verdict 1001" "read [the notes](notes.md)")")" "a markdown link"
same "  ... or a reference link" "$(WKS "$(WK MV2 rework "verdict 1001" "read [the notes][1]")")" "a markdown link"
same "a rework text with a control character" "$(WKS "$(WK MV2 rework "verdict 1001" "$(printf 'one\001two')")")" "a control character"
same "a rework row whose Item isn't a heading tag" "$(WKS "$(WK "the host" rework "verdict 1001" go)")" "a rework row's Item is a milestone's heading tag"
same "a rework row whose Who isn't verdict or failure <id>" "$(WKS "$(WK MV2 rework "failed 1002" go)")" "a rework row's Who is"
same "  ... or failure with no id" "$(WKS "$(WK MV2 rework "failure x" go)")" "a rework row's Who is"
same "a verdict-owed row whose Who isn't a topic" "$(WKS "$(WK MV1 verdict-owed a/b "verdict owed since 2026-10-09")")" "worker: contains '/'"
for u in "Milestone 03" "milestone 3" "feature 3"; do
    same "a decision row whose Item is $u" "$(WKS "$(WK "$u" decision "decision 1" go)")" "Item is a unit as pick lists it"
done
same "a verdict-owed row whose Item is milestone 3" "$(WKS "$(WK "milestone 3" verdict-owed none "verdict owed since 2026-10-09")")" "a verdict-owed row's Item is a milestone's heading tag"
passes "a decision row whose Item is Milestone 3 passes" "$(WKS "$(WK "Milestone 3" decision "decision 1" go)")"
same "an item listed twice under one kind" "$(WKS "$(WK x local-agent me go), $(WK x local-agent me again)")" "work: an item is listed twice under one kind"
same "a stored-set cell with a line break" "$(WKS "$(WK x local-agent me "one
two")")" "work.next: a line break"

echo "== Decisions =="
RUN=20260927T233505Z
entry() { # entry <n> <state> [jq merge]
    local extra=${3-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg n "$1" --arg s "$2" --arg run "$RUN" '{
      decision: $n, round: "0", question: "Ship with the mixed check result?",
      options: "keep option d and ship\nswitch to option c", state: $s,
      source: "worker ci-pin [\($run) report 40.1]", verdict: "", recommendation: "",
      reason: "", context: "", problem: "", grounds: "", target: "", owed: "",
      asked: "", evidence: "", outcome: "", decided_by: "", updated: "2026-09-27T23:40Z"}' | jq -c ". + ($extra)"
}
ESC='{options: "keep option d and ship -- d stands\nswitch to option c -- versions pin", round: "1", verdict: "escalate", recommendation: "keep option d and ship", reason: "the flip did not happen", context: "Option d was approved.", problem: "Dropping it changes the scope.", grounds: "scope", target: "a person", owed: "escalation"}'
dec() { full_record | jq -c --argjson e "$1" '.decisions = {next: 9, entries: [$e]}'; }
passes "an escalated entry passes" "$(dec "$(entry 1 escalated "$ESC")")"
same "an illegal Decisions state" "$(dec "$(entry 1 open)")" "decisions.state: not proposed"
same "a proposed entry with a verdict, an illegal transition" "$(dec "$(entry 1 proposed '{verdict: "settle"}')")" "a proposed entry has no verdict yet"
same "a held verdict on an escalated entry, an illegal transition" "$(dec "$(entry 1 escalated "$ESC + {verdict: \"hold\"}")")" "only an entry awaiting a verdict can be held"
same "a held entry missing what it waits on" "$(dec "$(entry 1 coordinator-verdict '{verdict: "hold"}')")" "reason is empty"
same "a settled entry missing its outcome" "$(dec "$(entry 1 settled '{decided_by: "a person"}')")" "outcome is empty"
same "a settled entry missing who decided" "$(dec "$(entry 1 settled '{outcome: "ship"}')")" "decided_by is empty"
for k in options recommendation reason context problem grounds target; do
    same "an escalated entry missing its $k" "$(dec "$(entry 1 escalated "$ESC + {$k: \"\"}")")" "$k is empty"
done
same "a Decisions target in the Side effects grammar" "$(dec "$(entry 1 escalated "$ESC + {target: \"pull request 12 on the widgets repo\"}")")" "decisions.target"
same "a stamp that doesn't parse" "$(dec "$(entry 1 proposed '{source: "worker ci-pin [report 40.1]"}')")" "decisions.source"
same "an evidence line without a stamp" "$(dec "$(entry 1 coordinator-verdict '{evidence: "2026-09-27T23:41Z dispatcher: mixed"}')")" "decisions.evidence"
same "a non-integer identifier" "$(dec "$(entry x proposed)")" "decisions.decision"
same "a ground outside the four" "$(dec "$(entry 1 escalated "$ESC + {grounds: \"urgency\"}")")" "decisions.grounds"
same "a line break inside a single item" "$(dec "$(entry 1 proposed '{question: "one\ntwo"}')")" "line break inside a single item"
same "an unknown Decisions column" "$(dec "$(entry 1 proposed '{priority: "high"}')")" "not a column of this section"
same "an identifier at Next decision" "$(full_record | jq -c --argjson e "$(entry 9 proposed)" '.decisions = {next: 9, entries: [$e]}')" "at or above Next decision"
same "an identifier used twice" "$(full_record | jq -c --argjson e "$(entry 2 proposed)" '.decisions = {next: 9, entries: [$e, $e]}')" "an identifier is used twice"
same "a next over a million" "$(with '.decisions = {next: 1000000, entries: []}')" "decisions.next"
same "a field outside the section" "$(with '.decisions = {next: 2, entries: [], notes: "x"}')" "decisions.notes: not a field of this section"
same "an archived identifier the section still holds" "$(full_record | jq -c --argjson e "$(entry 2 proposed)" '.decisions = {next: 9, entries: [$e], archived: [2]}')" "an identifier the section still holds"
same "a kept stamp that isn't {run, stamps}" "$(with '.decisions = {next: 9, entries: [], archived: [1], kept: {run: "x", stamps: []}}')" "decisions.kept"

echo "== private repositories, home paths and tokens =="
same "a private repository in Repo" "$(with '.holdings[0].repo = "acme/secret"')" "repo: names acme/secret, a repository that isn't public" acme/secret
same "  ... named case-insensitively" "$(with '.holdings[0].repo = "ACME/Secret"')" "isn't public" acme/secret
same "  ... from a list with spaces" "$(with '.holdings[0].repo = "acme/secret"')" "isn't public" "x/y, acme/secret"
same "a private repository in Pull request" "$(with '.holdings[0].pull_request = "[#1](https://github.com/acme/secret/pull/1)"')" "pull_request: names acme/secret" acme/secret
same "a private repository in Target" "$(with '.side_effects[0].target = "acme/secret#3"')" "target: names acme/secret" acme/secret
same "  ... as a .git URL" "$(with '.side_effects[0].target = "https://github.com/acme/secret.git"')" "isn't public" acme/secret
same "  ... ending a sentence" "$(with '.side_effects[0].target = "see acme/secret."')" "isn't public" acme/secret
same "a private repository in a hold" "$(hold '.holds = [$a]')" "holds.until: names acme/gadgets" acme/gadgets
same "a private repository in a pause" "$(STS "$(ST pause all "merged acme/secret#3")")" "standing.until: names acme/secret" acme/secret
same "a private repository in a Decisions text cell" "$(dec "$(entry 1 proposed '{question: "does acme/secret ship?"}')")" "decisions.question: names acme/secret" acme/secret
same "a private repository in a stored-set text cell" "$(WKS "$(WK x local-agent me "land github.com/acme/secret first")")" "work.next: names acme/secret" acme/secret
passes "a public repository whose name extends a private one passes" "$(with '.holdings[0].repo = "acme/secret-public"')"
same "a home-directory path in a Decisions cell" "$(dec "$(entry 1 proposed "{question: \"see $FX_HOME_A\"}")")" "a home-directory path"
same "  ... or in a stored-set cell" "$(STS "$(ST approval "" "" | jq -c --arg w "read ($FX_HOME_B)" '.what = $w')")" "standing.what: a home-directory path"
same "a token-shaped string in a Decisions cell" "$(dec "$(entry 1 proposed "{question: \"use $FX_TOKEN\"}")")" "a token-shaped string"
same "  ... or in a stored-set cell" "$(RUNS "$(RR arguments "sk-abcdefghijklmnopqrstuvwxyz0123")")" "run.value: a token-shaped string"

echo "== the scan walks every string =="
# scan <json> [private-repos]: scan_strings over the value; the refusal from
# "refused: " on, or "ok".
scan() {
    printf '%s' "$1" > "$T/sc.json"
    if jq -n -L "$HERE" --slurpfile s "$T/sc.json" --arg private "${2-}" 'include "state-schema";
            $s[0] | scan_strings($private | split(",") | map(select(. != ""))) | empty' 2> "$T/sc.err" < /dev/null; then
        echo ok
    else
        sed -n 's/.*\(refused: \)/\1/p' "$T/sc.err" | sed -n 1p
    fi
}
# Every string of a state holding every section, each replaced in turn by a
# token-shaped string, is refused, naming its path: the scan reads the value,
# not a list of columns.
FULL=$(with '.holds = [{hold: "h1", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]
    | .run = [{key: "cap", value: "3", set_by: "the human", set: "2026-09-28T11:27Z"}]
    | .standing = [{standing: "s1", kind: "answer", on: "", until: "", what: "panels first", owner: "alice", relayed_by: "", set: "2026-09-29T17:42Z"}]
    | .work = [{item: "audit", kind: "local-agent", who: "me", next: "finish", wakes: "0", updated: "2026-09-29T17:42Z"}]
    | .decisions = {next: 2, entries: [{decision: "1", round: "0", question: "which?", options: "a\nb", state: "proposed", source: "self [20260927T233505Z raise 41]", updated: "2026-09-27T23:40Z"}]}
    | .written = "2026-09-26T09:00:00Z"')
eq "a full state passes the scan" ok "$(scan "$FULL")"
printf '%s' "$FULL" | jq -c '[paths(strings)]' > "$T/paths.json"
NP=$(jq length "$T/paths.json")
MISSED=
i=0
while [ "$i" -lt "$NP" ]; do
    P=$(jq -c --argjson i "$i" '.[$i]' "$T/paths.json")
    NAME=$(printf '%s' "$P" | jq -r 'map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".")')
    GOT=$(scan "$(printf '%s' "$FULL" | jq -c --argjson p "$P" --arg t "$FX_TOKEN" 'setpath($p; "use " + $t)')")
    [ "$GOT" = "refused: $NAME: a token-shaped string" ] || MISSED="$MISSED $NAME[$GOT]"
    i=$((i + 1))
done
[ "$NP" -ge 50 ] && [ -z "$MISSED" ] && ok "every string of a full state is scanned, naming its path ($NP paths)" \
    || bad "every string of a full state is scanned, naming its path ($NP paths)" "$MISSED"
# A field no check knows yet, at any depth, is scanned without being named:
# a scan over a list of columns would miss it.
eq "a new top-level field's string is scanned" "refused: notes: a home-directory path" "$(scan "$(with --arg h "$FX_HOME_A" '.notes = $h')")"
eq "  ... and one nested in a new object and list" "refused: holdings[0].extra.more[1]: a token-shaped string" \
    "$(scan "$(with --arg t "$FX_TOKEN" '.holdings[0].extra = {more: ["fine", $t]}')")"
eq "  ... and a private repository in it" "refused: holdings[0].extra.note: names acme/secret, a repository that isn't public" \
    "$(scan "$(with '.holdings[0].extra = {note: "after acme/secret#3"}')" acme/secret)"
eq "a string value itself is scanned (record/reasoning)" "refused: value: a home-directory path" "$(scan "$(jq -nc --arg h "$FX_HOME_B" '"see " + $h')")"
eq "  ... and a rotation's fields (record/rotation)" "refused: predecessor: a token-shaped string" \
    "$(scan "$(jq -nc --arg t "$FX_TOKEN" '{start: "2026-10-01", end: "2026-10-07", host_repo: "acme/widgets", predecessor: $t}')")"
# check_record runs it last, over strings no column check reads.
eq "check_record refuses a token in a How to confirm, which no column check reads" "refused: side_effects[0].how_to_confirm: a token-shaped string" \
    "$(check "$(with --arg t "$FX_TOKEN" '.side_effects[0].how_to_confirm = "use " + $t')")"
eq "  ... a home path in a deferral's reason" "refused: deferrals[0].reason: a home-directory path" \
    "$(check "$(with --arg h "$FX_HOME_A" '.deferrals[0].reason = "see " + $h')")"
eq "  ... and a private repository in a reversal" "refused: reversals[0].reason: names acme/secret, a repository that isn't public" \
    "$(check "$(with '.reversals[0].reason = "waits on acme/secret#3"')" acme/secret)"
eq "  ... while a column's own check still speaks first" "refused: repo: names acme/secret, a repository that isn't public" \
    "$(check "$(with '.holdings[0].repo = "acme/secret"')" acme/secret)"

echo "== through state-write.sh and the core =="
# A roadmap record in the session, written through the real write script with
# the GitHub and koto stand-ins.
WR="$HERE/state-write.sh"
SW=coordinate-roadmap-plugin-system-20260926T140000Z
export RS_SESSION=$SW
RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
NEWJ=$(record_json roadmap plugin-system | jq -c --argjson h "$(holding feature-2)" '.holdings = [$h]')
seed_rm() { db_init; seed_session "$SW" "$(record_json roadmap plugin-system)"; }
# A state that names a private repository passes every check that needs no
# visibility read, so only the core's check against the host's private list
# can refuse it.
state_json "$(printf '%s' "$NEWJ" | jq -c '.holdings[0].repo = "acme/secret"')" > "$T/priv.json"

seed_rm
SNAP=$(session_snapshot "$SW")
[ "$SNAP" != none ] && ok "the session holds the record's keys" || bad "the session holds the record's keys" ""
bash "$WR" "${RM[@]}" --state-file "$T/priv.json" > /dev/null 2> "$T/err"; rc=$?
eq "a state naming a private repository is refused before any key is written" 65 "$rc"
grep -q 'state-write: refused: repo: names acme/secret, a repository that isn.t public' "$T/err" \
    && ok "  ... with the module's message" || bad "  ... with the module's message" "$(cat "$T/err")"
eq "  ... and no key changed" "$SNAP" "$(session_snapshot "$SW")"
state_json "$NEWJ" > "$T/new.json"
jq -c '.holdings[0].worker = "session_feature-2"' "$T/new.json" > "$T/worker.json"
bash "$WR" "${RM[@]}" --state-file "$T/worker.json" > /dev/null 2> "$T/err"; rc=$?
eq "a worker shaped like a session id is refused" 65 "$rc"
grep -q 'refused: worker: the shape of a session id' "$T/err" && ok "  ... with its refused: message" || bad "  ... with its refused: message" "$(cat "$T/err")"
eq "  ... and no key changed" "$SNAP" "$(session_snapshot "$SW")"
# A write the core accepts, then one built from the read before it.
bash "$WR" "${RM[@]}" --state-file "$T/new.json" > /dev/null 2> "$T/err"; rc=$?
eq "a valid state is written to the session" 0 "$rc"
SNAP=$(session_snapshot "$SW")
bash "$WR" "${RM[@]}" --state-file "$T/new.json" > /dev/null 2> "$T/err"; rc=$?
eq "a write built from a stale read is refused as record-changed" 12 "$rc"
grep -q 'record-changed' "$T/err" && ok "  ... naming record-changed" || bad "  ... naming record-changed" "$(cat "$T/err")"
eq "  ... and no key changed" "$SNAP" "$(session_snapshot "$SW")"
# A write that changes a section another writer flag owns: Holds, through
# state-write.sh, which never opens HOLDS_WRITER.
session_state "$SW" | jq -c '.holdings |= map(del(.pushed_head))
    | .holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]' > "$T/hold.json"
bash "$WR" "${RM[@]}" --state-file "$T/hold.json" > /dev/null 2> "$T/err"; rc=$?
eq "a write changing a section another writer owns is refused" 65 "$rc"
grep -q 'Holds section changes only through state-hold.sh' "$T/err" && ok "  ... by the owner check" || bad "  ... by the owner check" "$(cat "$T/err")"
eq "  ... and no key changed" "$SNAP" "$(session_snapshot "$SW")"

done_tests state-schema
