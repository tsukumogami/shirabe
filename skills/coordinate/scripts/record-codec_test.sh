#!/usr/bin/env bash
# record-codec_test.sh -- the record codec renders and parses the coordinator
# record and the discipline handoff file with a byte-exact round trip, and
# refuses what the record must never hold.
#
# Covers: the round trip for both formats and both containers; two renders
# differing only in Written:; cell encoding of pipes, newlines, backtick runs,
# fence openers, HTML and edge whitespace; every refusal the renderer makes
# (recomputable columns, worker shapes, structured grammars, private
# repositories, predecessor reasoning); and the parser's canonical check on
# hand-damaged bodies, the wrong scope, and an oversized body. The Decisions
# section: a record with an entry in each state (one held, one compacted)
# round-trips; a body main's codec wrote (testdata/record/pre-decisions.md)
# parses to no decisions and renders back byte for byte; a section holding only
# `Next decision: 1` isn't canonical; each malformed entry is refused; the
# section's own grammars leave the other sections' same-named columns alone; `@`
# is encoded; the shared escalation validator and compaction; and the handoff
# carrying only unsettled entries, a predecessor copy carrying all.
#
# Needs bash and jq only.
# Usage: bash skills/coordinate/scripts/record-codec_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
R="$HERE/record-render.sh"
P="$HERE/record-parse.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/record-codec-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }

W=2026-09-26T12:00:00Z
SHA=0123456789abcdef0123456789abcdef01234567

holding() { # holding <worker> [extra jq merge]
    local extra=${2-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg w "$1" --arg sha "$SHA" "{unit: \"Feature 2\", entry_point: \"/shirabe:deliver\", mode: \"--auto\", phase: \"executing\", dispatch_status: \"dispatched\", return_path: \"message\", worker: \$w, repo: \"acme/widgets\", branch: \"feat/x\", verified_head: \$sha, dispatched: \"2026-09-26\", pull_request: \"[#12](https://github.com/acme/widgets/pull/12)\"} + ($extra)"
}

full_record() {
    jq -nc --argjson h "$(holding plugin-registry)" '{
      scope: {kind: "roadmap", name: "plugin-system"},
      holdings: [$h, ($h + {worker: "sandbox", phase: "scoping-ahead", branch: "", verified_head: "", pull_request: "", return_path: "leg req-1:execute", dispatch_status: "dispatching"})],
      deferrals: [{deferral: "flaky test", reason: "not now", raised: "2026-09-25T10:00Z", disposition: ""},
                  {deferral: "docs gap", reason: "later", raised: "2026-09-24T08:30Z", disposition: "filed #40"}],
      side_effects: [{action: "merge", target: "#12", verified_head: "0123456789abcdef0123456789abcdef01234567", attempted: "2026-09-26T11:02Z", how_to_confirm: "compare blobs on main"}],
      reversals: [{date: "2026-09-26T09:15Z", reversed: "merge on green", now: "hold for release", reason: "release freeze", from: "the human"}]}'
}

roundtrip() { # roundtrip <label> <json> [render args...]
    local label=$1 json=$2; shift 2
    printf '%s' "$json" > "$T/in.json"
    if ! bash "$R" --written "$W" "$@" "$T/in.json" > "$T/body.md" 2> "$T/err"; then
        bad "$label (render)" "$(cat "$T/err")"; return
    fi
    local cont=issue
    case " $* " in *" --container pr "*) cont=pr ;; esac
    if ! bash "$P" --container "$cont" "$T/body.md" > "$T/out.json" 2> "$T/err"; then
        bad "$label (parse)" "$(cat "$T/err")"; return
    fi
    if [ "$(jq -S 'del(.written)' "$T/out.json")" = "$(jq -S --argjson i "$json" -n '$i | .holdings //= [] | .deferrals //= [] | .side_effects //= [] | .reversals //= [] | .holdings |= map(. ) ')" ] \
       && [ "$(jq -r .written "$T/out.json")" = "$W" ]; then
        ok "$label"
    else
        bad "$label" "$(diff <(jq -S 'del(.written)' "$T/out.json") <(printf '%s' "$json" | jq -S .))"
    fi
}

refuse() { # refuse <label> <json> <expected stderr substring> [render args...]
    local label=$1 json=$2 want=$3; shift 3
    printf '%s' "$json" > "$T/in.json"
    bash "$R" --written "$W" "$@" "$T/in.json" > "$T/body.md" 2> "$T/err"
    local rc=$?
    if [ $rc -eq 65 ] && grep -qF -- "$want" "$T/err"; then ok "$label"
    else bad "$label" "rc=$rc stderr=$(cat "$T/err")"; fi
}

echo "== round trip =="
roundtrip "full roadmap record round-trips" "$(full_record)"
roundtrip "empty sections render None. and round-trip" '{"scope":{"kind":"roadmap","name":"x"},"holdings":[],"deferrals":[],"side_effects":[],"reversals":[]}'
roundtrip "discipline record in a pull request round-trips" "$(full_record | jq -c '.scope = {kind: "discipline", name: "ci-health"}')" --container pr

bash "$R" --written "$W" <(full_record) > "$T/a.md"
bash "$R" --written 2026-09-27T00:00:00Z <(full_record) > "$T/b.md"
if [ "$(grep -v '^Written: ' "$T/a.md")" = "$(grep -v '^Written: ' "$T/b.md")" ] \
   && [ "$(grep -c '^Written: ' "$T/a.md")" = 1 ] && ! cmp -s "$T/a.md" "$T/b.md"; then
    ok "two renders differ only in Written:"
else bad "two renders differ only in Written:" "$(diff "$T/a.md" "$T/b.md")"; fi

head -1 "$T/a.md" | grep -qx '> This is a \*\*coordinator record\*\* for ROADMAP-plugin-system\.' \
    && sed -n 3p "$T/a.md" | grep -qx "Written: $W" \
    && ok "the body opens with the declaration line and Written:" \
    || bad "the body opens with the declaration line and Written:" "$(head -3 "$T/a.md")"

echo "== cell encoding =="
for v in 'a | b' 'line one
line two' '``` fence' '````' 'x `code | pipe` y' '<!-- c -->' '<br> literal' '&amp; &#32;' ' edge ' '	tab' 'back\slash \| mixed' 'trailing	'; do
    j=$(full_record | jq -c --arg v "$v" '.deferrals[0].deferral = $v | .reversals[0].reason = $v')
    printf '%s' "$j" > "$T/in.json"
    bash "$R" --written "$W" "$T/in.json" > "$T/body.md"
    got=$(bash "$P" "$T/body.md" | jq -r '.deferrals[0].deferral')
    cols=$(grep -c '^| ' "$T/body.md")
    rows_ok=$(awk -F' \\| ' '/^## Deferrals/{s=1} /^## Side/{s=0} s && /^\| / { gsub(/\\\|/, "X"); n = gsub(/ \| /, "&"); print n }' "$T/body.md" | sort -u | tr '\n' ' ')
    if [ "$got" = "$v" ] && [ "$rows_ok" = "3 " ]; then ok "cell round-trips and keeps its columns: $(printf '%q' "$v")"
    else bad "cell round-trips and keeps its columns: $(printf '%q' "$v")" "got=$(printf '%q' "$got") separators=$rows_ok"; fi
done

echo "== refusals =="
refuse "a status column is refused as recomputable" "$(full_record | jq -c '.holdings[0].status = "open"')" "read from GitHub, never recorded"
refuse "a CI column is refused as recomputable" "$(full_record | jq -c '.holdings[0].CI = "green"')" "read from GitHub, never recorded"
refuse "a merge-state column is refused as recomputable" "$(full_record | jq -c '.side_effects[0].merge_state = "CLEAN"')" "read from GitHub, never recorded"
refuse "an unknown column is refused" "$(full_record | jq -c '.deferrals[0].owner = "x"')" "not a column of this section"
refuse "a worker path is refused" "$(full_record | jq -c '.holdings[0].worker = "instances/foo"')" "shape of a path"
refuse "a worker UUID is refused" "$(full_record | jq -c '.holdings[0].worker = "w-6f1c2e3a-1b2c-4d5e-8f90-123456789abc"')" "instance or session id"
refuse "a worker session_ id is refused" "$(full_record | jq -c '.holdings[0].worker = "session_01ABCdef"')" "session id"
refuse "a worker instance name is refused" "$(full_record | jq -c '.holdings[0].worker = "tsuku+topic-43e4a66f"')" "instance name"
refuse "a worker job id is refused" "$(full_record | jq -c '.holdings[0].worker = "123456"')" "job id"
roundtrip "a held phase round-trips" "$(full_record | jq -c '.holdings[0].phase = "held"')"
refuse "a bad phase is refused" "$(full_record | jq -c '.holdings[0].phase = "planning"')" "phase"
refuse "a bad dispatch status is refused" "$(full_record | jq -c '.holdings[0].dispatch_status = "sent"')" "dispatch_status"
refuse "a bad return path is refused" "$(full_record | jq -c '.holdings[0].return_path = "leg"')" "return_path"
refuse "a short verified head is refused" "$(full_record | jq -c '.holdings[0].verified_head = "0123abc"')" "verified_head"
refuse "a date-only raised is refused" "$(full_record | jq -c '.deferrals[0].raised = "2026-09-25"')" "raised"
refuse "a date-only reversal date is refused" "$(full_record | jq -c '.reversals[0].date = "2026-09-25"')" "date"
refuse "filed without a number is refused" "$(full_record | jq -c '.deferrals[0].disposition = "filed"')" "disposition"
refuse "a carry without a time is refused" "$(full_record | jq -c '.deferrals[0].disposition = "carried: later"')" "disposition"
refuse "a malformed pull request link is refused" "$(full_record | jq -c '.holdings[0].pull_request = "#12"')" "pull_request"
refuse "an empty required cell is refused" "$(full_record | jq -c '.holdings[0].unit = ""')" "unit: empty"
refuse "a control character is refused" "$(full_record | jq -c '.deferrals[0].reason = "a\u0007b"')" "control character"
refuse "the parser's placeholder character is refused" "$(full_record | jq -c '.deferrals[0].reason = "a\u001fb"')" "control character"
refuse "a private repository in Repo is refused" "$(full_record | jq -c '.holdings[0].repo = "acme/secret"')" "isn't public" --private-repos acme/secret
refuse "a private repository in Pull request is refused" "$(full_record | jq -c '.holdings[0].pull_request = "[#1](https://github.com/acme/secret/pull/1)"')" "isn't public" --private-repos acme/secret
refuse "a private repository in Target is refused" "$(full_record | jq -c '.side_effects[0].target = "acme/secret#3"')" "isn't public" --private-repos acme/secret
refuse "a roadmap record in a pull request is refused" "$(full_record)" "only a discipline record" --container pr
refuse "an unknown top-level field is refused" "$(full_record | jq -c '.notes = "x"')" "not a field"

holding sandbox > /dev/null && printf '%s' "$(full_record | jq -c '.holdings[0].branch = "" | .holdings[0].pull_request = "" | .holdings[0].verified_head = ""')" > "$T/in.json" \
    && bash "$R" --written "$W" "$T/in.json" > /dev/null 2>&1 && ok "an empty Branch (not yet known) is accepted" || bad "an empty Branch (not yet known) is accepted"
printf '%s' "$(full_record | jq -c '.holdings[0].worker = "coordinate-dispatch-path.v2_a"')" > "$T/in.json"
bash "$R" --written "$W" "$T/in.json" > /dev/null 2>&1 && ok "a dispatch topic is accepted as a worker" || bad "a dispatch topic is accepted as a worker"

echo "== handoff =="
handoff() {
    full_record | jq -c '.scope = {kind: "discipline", name: "ci-health"} | .rotation = {start: "2026-09-20", end: "2026-09-23", date: "2026-09-23", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/77"} | .reasoning = "The flaky job is timing.\n\n## A heading inside the prose\n\nStill reasoning."'
}
printf '%s' "$(handoff)" > "$T/h.json"
if bash "$R" --format handoff "$T/h.json" > "$T/h.md" 2> "$T/err" \
   && bash "$P" --format handoff "$T/h.md" > "$T/h.out" 2> "$T/err" \
   && [ "$(jq -S . "$T/h.out")" = "$(jq -S . "$T/h.json")" ]; then ok "a handoff round-trips, reasoning headings and all"
else bad "a handoff round-trips, reasoning headings and all" "$(cat "$T/err"; diff <(jq -S . "$T/h.out" 2>/dev/null) <(jq -S . "$T/h.json"))"; fi
grep -q 'coordinator record' "$T/h.md" && bad "a handoff carries no declaration line" || ok "a handoff carries no declaration line"
grep -q '^Written:' "$T/h.md" && bad "a handoff carries no Written: line" || ok "a handoff carries no Written: line"

printf '%s' "$(handoff | jq -c 'del(.reasoning) | .predecessor_copy = {written: "2026-09-23T17:00:00Z"}')" > "$T/p.json"
if bash "$R" --format handoff "$T/p.json" > "$T/p.md" 2> "$T/err" \
   && grep -qx 'As written by the previous rotation at 2026-09-23T17:00:00Z; not re-checked.' "$T/p.md" \
   && grep -qx "The outgoing rotation's reasoning was not recorded." "$T/p.md" \
   && [ "$(bash "$P" --format handoff "$T/p.md" | jq -S .)" = "$(jq -S . "$T/p.json")" ]; then ok "a predecessor copy carries the not-re-checked line and the fixed sentence"
else bad "a predecessor copy carries the not-re-checked line and the fixed sentence" "$(cat "$T/err" "$T/p.md")"; fi
refuse "a predecessor's reasoning is never written on its behalf" "$(handoff | jq -c '.predecessor_copy = {written: "2026-09-23T17:00:00Z"}')" "never written on its behalf" --format handoff
refuse "an empty reasoning is refused" "$(handoff | jq -c '.reasoning = "  "')" "reasoning: empty" --format handoff
refuse "a roadmap has no handoff" "$(handoff | jq -c '.scope.kind = "roadmap"')" "only a discipline" --format handoff

echo "== canonical check =="
bash "$R" --written "$W" <(full_record) > "$T/c.md"
not_canonical() { # not_canonical <label> <sed expr>
    sed "$2" "$T/c.md" > "$T/d.md"
    bash "$P" "$T/d.md" > /dev/null 2> "$T/err"
    local rc=$?
    if [ $rc -eq 3 ] || [ $rc -eq 65 ]; then ok "$1"; else bad "$1" "rc=$rc $(cat "$T/err")"; fi
}
not_canonical "a hand-edited separator is not canonical" 's/^|---|---|---|---|$/|--|---|---|---|/'
not_canonical "a note between tables is not canonical" 's/^## Deferrals$/a note\n\n## Deferrals/'
not_canonical "a missing section is refused" '/^## Reversals$/,$d'
not_canonical "an extra column is not canonical" 's/^| Deferral | Reason | Raised | Disposition |$/| Deferral | Reason | Raised | Disposition | Status |/'
not_canonical "a reordered section is refused" 's/^## Deferrals$/## Reversals/'
bash "$P" "$T/c.md" > /dev/null && ok "the rendered body is canonical" || bad "the rendered body is canonical"
tr -d '\r' < "$T/c.md" | sed 's/$/\r/' > "$T/crlf.md"
bash "$P" "$T/crlf.md" > /dev/null 2> "$T/err" && ok "a body edited on the web (CRLF) is still canonical" || bad "a body edited on the web (CRLF) is still canonical" "$(cat "$T/err")"
bash "$P" --expect-scope roadmap:plugin-system "$T/c.md" > /dev/null && ok "the expected scope is accepted" || bad "the expected scope is accepted"
bash "$P" --expect-scope roadmap:plugin "$T/c.md" > /dev/null 2>&1; [ $? -eq 65 ] && ok "another scope is refused" || bad "another scope is refused"
sed 's/ROADMAP-plugin-system/ROADMAP-plugin-system-v2/' "$T/c.md" > "$T/v2.md"
bash "$P" --expect-scope roadmap:plugin-system "$T/v2.md" > /dev/null 2>&1; [ $? -eq 65 ] && ok "a -v2 record is never read as its prefix" || bad "a -v2 record is never read as its prefix"
bash "$P" --container pr "$T/c.md" > /dev/null 2>&1; [ $? -ne 0 ] && ok "an issue body is not a canonical pull request body" || bad "an issue body is not a canonical pull request body"
{ cat "$T/c.md"; head -c 70000 /dev/zero | tr '\0' 'x'; } > "$T/big.md"
bash "$P" "$T/big.md" > /dev/null 2> "$T/err"; [ $? -eq 65 ] && grep -q "over GitHub" "$T/err" && ok "a body over GitHub's size limit is refused before parsing" || bad "a body over GitHub's size limit is refused before parsing"

printf '' | bash "$R" --written "$W" > /dev/null 2>&1; [ $? -eq 65 ] && ok "empty input is refused" || bad "empty input is refused"
printf '  \n' | bash "$R" --written "$W" > /dev/null 2>&1; [ $? -eq 65 ] && ok "whitespace-only input is refused" || bad "whitespace-only input is refused"
{ full_record; full_record; } | bash "$R" --written "$W" > /dev/null 2>&1; [ $? -eq 65 ] && ok "two JSON documents are refused" || bad "two JSON documents are refused"
printf '%s' "$(full_record | jq -c '.holdings[0].repo = "acme/secret-public" | .holdings[0].pull_request = "[#1](https://github.com/acme/secret-public/pull/1)" | .side_effects[0].target = "xacme/secret#2"')" > "$T/in.json"
bash "$R" --written "$W" --private-repos acme/secret "$T/in.json" > /dev/null 2>&1 && ok "a public repository whose name extends a private one is accepted" || bad "a public repository whose name extends a private one is accepted"
refuse "a private repository ending a sentence is refused" "$(full_record | jq -c '.side_effects[0].target = "see acme/secret."')" "isn't public" --private-repos acme/secret
refuse "a private repository as a .git URL is refused" "$(full_record | jq -c '.side_effects[0].target = "https://github.com/acme/secret.git"')" "isn't public" --private-repos acme/secret
refuse "a private-repository list with spaces is trimmed" "$(full_record | jq -c '.holdings[0].repo = "acme/secret"')" "isn't public" --private-repos "x/y, acme/secret"
refuse "a private repository named case-insensitively is refused" "$(full_record | jq -c '.holdings[0].repo = "ACME/Secret"')" "isn't public" --private-repos acme/secret

echo "== decisions =="
RUN=20260927T233505Z
entry() { # entry <n> <state> [jq merge]: one Decisions entry
    local extra=${3-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg n "$1" --arg s "$2" --arg run "$RUN" '{
      decision: $n, round: "0", question: "Ship with the mixed check result?",
      options: "keep option d and ship\nswitch to option c", state: $s,
      source: "worker ci-pin [\($run) report 40.1]", verdict: "", recommendation: "",
      reason: "", context: "", problem: "", grounds: "", target: "", owed: "",
      asked: "", evidence: "", outcome: "", decided_by: "", updated: "2026-09-27T23:40Z"}' | jq -c ". + ($extra)"
}
ESC='{options: "keep option d and ship -- the flip condition did not happen, so d stands\nswitch to option c -- the per-project installs would pin their versions", round: "1", verdict: "escalate", recommendation: "keep option d and ship", reason: "the flip condition did not happen", context: "Option d was approved; a check came back mixed.", problem: "Dropping the feature changes the scope.", grounds: "scope", target: "a person", owed: "escalation"}'
decisions_record() {
    jq -nc --argjson a "$(entry 1 proposed)" --argjson b "$(entry 2 coordinator-verdict '{verdict: "hold", reason: "waiting on the cache benchmark"}')" \
        --argjson c "$(entry 3 escalated "$ESC")" \
        --argjson d "$(entry 4 settled '{verdict: "settle", outcome: "keep option d: the flip condition did not happen", decided_by: "coordinator plugin-system", owed: "reply", evidence: "2026-09-27T23:41Z dispatcher [20260927T233505Z wait 52]: the check came back mixed"}')" \
        --argjson e "$(entry 5 settled '{outcome: "ship it", decided_by: "a person", options: "", source: "self [20260927T233505Z raise 60]"}')" \
        --argjson r "$(full_record)" '$r + {decisions: {next: 6, entries: [$a, $b, $c, $d, $e]}}'
}
roundtrip "a record with an entry in each state, one held and one compacted, round-trips" "$(decisions_record)"
bash "$R" --written "$W" <(decisions_record) > "$T/d.md"
grep -qx 'Next decision: 6' "$T/d.md" && grep -q '^## Decisions$' "$T/d.md" && [ "$(sed -n '/^## Decisions$/,$p' "$T/d.md" | grep -c '^| ')" = 6 ] \
    && ok "the section has its Next decision line, a header and five rows" || bad "the section has its Next decision line, a header and five rows" "$(sed -n '/^## Decisions$/,$p' "$T/d.md" | head -6)"
[ "$(sed -n '/^## Decisions$/,$p' "$T/d.md" | sed -n '5p' | awk -F' [|] ' '{print NF}')" = 19 ] && ok "the table has nineteen columns" || bad "the table has nineteen columns"
roundtrip "a section with no entries and a high-water mark round-trips" "$(full_record | jq -c '.decisions = {next: 4, entries: []}')"

cp "$HERE/testdata/record/pre-decisions.md" "$T/pre.md"
if bash "$P" "$T/pre.md" > "$T/pre.json" && ! jq -e 'has("decisions")' "$T/pre.json" > /dev/null \
   && jq 'del(.written)' "$T/pre.json" | bash "$R" --written "$(jq -r .written "$T/pre.json")" | cmp -s - "$T/pre.md"; then
    ok "a body main's codec wrote parses to no decisions and renders back byte for byte"
else bad "a body main's codec wrote parses to no decisions and renders back byte for byte" "$(cat "$T/pre.json" 2>/dev/null | head -3)"; fi
{ cat "$T/pre.md"; printf '\n## Decisions\n\nNext decision: 1\n\nNone.\n'; } > "$T/toggle.md"
bash "$P" "$T/toggle.md" > /dev/null 2>&1; [ $? -eq 3 ] && ok "a Decisions section holding only Next decision: 1 is not canonical" || bad "a Decisions section holding only Next decision: 1 is not canonical"
bash "$R" --written "$W" <(full_record | jq -c '.decisions = {next: 1, entries: []}') | grep -q '^## Decisions' \
    && bad "next 1 and no entries renders no section" || ok "next 1 and no entries renders no section"

with() { printf '%s' "$(full_record | jq -c --argjson e "$1" '.decisions = {next: 9, entries: [$e]}')"; }
refuse "an unknown state is refused" "$(with "$(entry 1 open)")" "decisions.state"
refuse "a non-integer identifier is refused" "$(with "$(entry x proposed)")" "decisions.decision"
refuse "an identifier at Next decision is refused" "$(full_record | jq -c --argjson e "$(entry 9 proposed)" '.decisions = {next: 9, entries: [$e]}')" "at or above Next decision"
refuse "an identifier used twice is refused" "$(full_record | jq -c --argjson e "$(entry 2 proposed)" '.decisions = {next: 9, entries: [$e, $e]}')" "used twice"
refuse "a ground outside the four is refused" "$(with "$(entry 1 escalated "$ESC + {grounds: \"urgency\"}")")" "decisions.grounds"
for k in options recommendation reason context problem grounds target; do
    refuse "an escalated entry missing $k is refused" "$(with "$(entry 1 escalated "$ESC + {$k: \"\"}")")" "$k is empty"
done
refuse "a settled entry missing its outcome is refused" "$(with "$(entry 1 settled '{decided_by: "a person"}')")" "outcome is empty"
refuse "a settled entry missing who decided is refused" "$(with "$(entry 1 settled '{outcome: "ship"}')")" "decided_by is empty"
refuse "a held entry missing what it waits on is refused" "$(with "$(entry 1 coordinator-verdict '{verdict: "hold"}')")" "reason is empty"
refuse "a stamp that doesn't parse is refused" "$(with "$(entry 1 proposed '{source: "worker ci-pin [report 40.1]"}')")" "decisions.source"
refuse "an evidence line without a stamp is refused" "$(with "$(entry 1 coordinator-verdict '{evidence: "2026-09-27T23:41Z dispatcher: mixed"}')")" "decisions.evidence"
refuse "a line break inside a single item is refused" "$(with "$(entry 1 proposed '{question: "one\ntwo"}')")" "line break inside a single item"
refuse "a private repository in a Decisions text cell is refused" "$(with "$(entry 1 proposed '{question: "does acme/secret ship?"}')")" "isn't public" --private-repos acme/secret
refuse "a home-directory path is refused" "$(with "$(entry 1 proposed '{question: "see /home/someone/notes"}')")" "home-directory path"
refuse "a token-shaped string is refused" "$(with "$(entry 1 proposed '{question: "use ghp_abcdefghijklmnopqrstuvwxyz0123"}')")" "token-shaped"
refuse "an unknown Decisions column is refused" "$(with "$(entry 1 proposed '{priority: "high"}')")" "not a column of this section"
roundtrip "a Decisions column named state takes no recomputable-column refusal" "$(with "$(entry 1 proposed)")"
# The same free text the Side effects target and Reversals reason accept is
# refused as a Decisions target, and a Decisions reason left empty on a held
# entry is refused while Reversals demands its own: each column keeps its
# section's grammar.
roundtrip "a Side effects target the Decisions grammar would refuse is accepted there" \
    "$(full_record | jq -c --argjson e "$(entry 1 escalated "$ESC")" '.decisions = {next: 2, entries: [$e]} | .side_effects[0].target = "pull request 12 on the widgets repo"')"
refuse "the same text as a Decisions target is refused" "$(with "$(entry 1 escalated "$ESC + {target: \"pull request 12 on the widgets repo\"}")")" "decisions.target"
refuse "a Reversals reason stays required though a proposed entry's reason may be empty" \
    "$(full_record | jq -c --argjson e "$(entry 1 proposed)" '.decisions = {next: 2, entries: [$e]} | .reversals[0].reason = ""')" "reason: empty"
roundtrip "a Next decision written 7.0 renders as 7 and round-trips" "$(full_record | jq -c '.decisions = {next: 7, entries: []}')"
printf '%s' "$(full_record | jq -c '.decisions = {next: 7, entries: []}' | sed 's/"next":7/"next":7.0/')" > "$T/in.json"
bash "$R" --written "$W" "$T/in.json" > "$T/n.md" && grep -qx 'Next decision: 7' "$T/n.md" && bash "$P" "$T/n.md" > /dev/null \
    && ok "a next of 7.0 renders as 7 and parses back" || bad "a next of 7.0 renders as 7 and parses back" "$(grep '^Next' "$T/n.md")"
refuse "a next over a million is refused" "$(full_record | jq -c '.decisions = {next: 1000000, entries: []}')" "decisions.next"
printf '%s' "$(with "$(entry 1 proposed '{question: "literal &#64; and <br> in text"}')")" > "$T/in.json"
bash "$R" --written "$W" "$T/in.json" > "$T/lit.md"
[ "$(bash "$P" "$T/lit.md" | jq -r '.decisions.entries[0].question')" = "literal &#64; and <br> in text" ] \
    && ok "a literal &#64; and <br> in a Decisions cell round-trip" || bad "a literal &#64; and <br> in a Decisions cell round-trip"
printf '%s' "$(with "$(entry 1 proposed '{question: "ask @someone about the pin | now?"}')")" > "$T/in.json"
bash "$R" --written "$W" "$T/in.json" > "$T/at.md"
grep -q '&#64;someone' "$T/at.md" && ! grep -q '@someone' "$T/at.md" && [ "$(bash "$P" "$T/at.md" | jq -r '.decisions.entries[0].question')" = "ask @someone about the pin | now?" ] \
    && ok "@ and a pipe in a Decisions cell render encoded and parse back" || bad "@ and a pipe in a Decisions cell render encoded and parse back"

VAL() { jq -n -L "$HERE" --argjson e "$1" --arg t "$2" 'include "record-codec"; $e | escalation_problems($t)'; }
[ "$(VAL "$(entry 1 escalated "$ESC")" "a person")" = "[]" ] && ok "the validator passes a complete verdict" || bad "the validator passes a complete verdict"
[ "$(VAL "$(entry 1 escalated "$ESC + {grounds: \"outside-scope\"}")" "a person")" = "[]" ] && ok "outside-scope alone is a ground" || bad "outside-scope alone is a ground"
for c in 'recommendation: "neither"' 'reason: "  "' 'context: ""' 'problem: ""' 'grounds: ""'; do
    [ "$(VAL "$(entry 1 escalated "$ESC + {$c}")" "a person" | jq length)" = 1 ] && ok "the validator refuses {$c}" || bad "the validator refuses {$c}"
done
[ "$(VAL "$(entry 1 escalated "$ESC")" "coordinator ws" | jq length)" = 1 ] && ok "the validator refuses a target other than the run's" || bad "the validator refuses a target other than the run's"
[ "$(VAL "$(entry 1 escalated "$ESC + {options: \"keep option d and ship -- d stands\\nswitch to option c\"}")" "a person" | jq -c .)" = '["an option has no explanation"]' ] \
    && ok "the validator refuses an option without its explanation" || bad "the validator refuses an option without its explanation"
[ "$(VAL "$(entry 1 escalated "$ESC + {options: \"keep option d and ship --  \\nswitch to option c -- why\"}")" "a person" | jq -c .)" = '["an option has no explanation"]' ] \
    && ok "the validator refuses a blank explanation" || bad "the validator refuses a blank explanation"
# The merge is built in a variable first: bash 3.2 brace-expands a `{...}`
# holding a comma inside a nested command substitution.
WHOLE='{recommendation: "keep option d and ship -- the flip condition did not happen, so d stands"}'
[ "$(VAL "$(entry 1 escalated "$ESC + $WHOLE")" "a person" | jq -r '.[0]')" = "the recommendation is not one of the options" ] \
    && ok "the recommendation names an option, not its explanation" || bad "the recommendation names an option, not its explanation"
CMP=$(jq -nc -L "$HERE" --argjson e "$(entry 4 settled '{verdict: "settle", outcome: "ship", decided_by: "a person", evidence: "2026-09-27T23:41Z dispatcher [20260927T233505Z wait 52]: mixed\n2026-09-27T23:42Z this coordinator [20260927T233505Z redirect 40]: redirect sent"}')" 'include "record-codec"; $e | compact_settled')
[ "$(printf '%s' "$CMP" | jq -r '.verdict')" = "" ] && [ "$(printf '%s' "$CMP" | jq -r .outcome)" = ship ] \
    && [ "$(printf '%s' "$CMP" | jq -r .options)" = "$(printf 'keep option d and ship\nswitch to option c')" ] \
    && [ "$(printf '%s' "$CMP" | jq -r .evidence)" = "2026-09-27T23:42Z this coordinator [20260927T233505Z redirect 40]: redirect sent" ] \
    && ok "a settled entry that owes nothing compacts, keeping its options and its redirect line" || bad "a settled entry that owes nothing compacts" "$CMP"
TXT() { jq -n -L "$HERE" --arg v "$1" 'include "record-codec"; $v | check_dcell("question"; [])' >/dev/null 2>&1; }
for v in "task-runner-integration-tests" "disk-space-reclamation-policy" "risk-assessment-of-the-new-design" "keep ~/.config as it is" "the /home page" "and/or n/a CI/CD"; do
    TXT "$v" && ok "prose is accepted: $v" || bad "prose is accepted: $v"
done
for v in "see /home/alice/notes" "token sk-abcdefghijklmnopqrstuvwxyz0123" "ghp_abcdefghijklmnopqrstuvwxyz0123456789" "(/Users/bob/x)"; do
    TXT "$v" && bad "refused: $v" || ok "refused: $v"
done
[ "$(jq -nc -L "$HERE" --argjson e "$(entry 4 settled '{outcome: "ship", decided_by: "a person", owed: "reply"}')" 'include "record-codec"; $e | compact_settled | .owed')" = '"reply"' ] \
    && ok "a settled entry that still owes a reply is not compacted" || bad "a settled entry that still owes a reply is not compacted"

HD=$(decisions_record | jq -c '.scope = {kind: "discipline", name: "ci-health"} | del(.written) | .rotation = {start: "2026-09-20", end: "2026-09-23", date: "2026-09-23", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/77"} | .reasoning = "Carry the open decisions."')
printf '%s' "$HD" > "$T/hd.json"
if bash "$R" --format handoff "$T/hd.json" > "$T/hd.md" 2> "$T/err" && bash "$P" --format handoff "$T/hd.md" > "$T/hd.out" 2> "$T/err" \
   && [ "$(jq -c '[.decisions.next, (.decisions.entries | map(.decision))]' "$T/hd.out")" = '[6,["1","2","3"]]' ] \
   && [ "$(jq -r .reasoning "$T/hd.out")" = "Carry the open decisions." ]; then
    ok "a handoff carries only the unsettled entries, with the same Next decision, before the reasoning"
else bad "a handoff carries only the unsettled entries" "$(cat "$T/err"; jq -c .decisions "$T/hd.out" 2>/dev/null)"; fi
printf '%s' "$(printf '%s' "$HD" | jq -c 'del(.reasoning) | .predecessor_copy = {written: "2026-09-23T17:00:00Z"}')" > "$T/hp.json"
bash "$R" --format handoff "$T/hp.json" | bash "$P" --format handoff | jq -e '.decisions.entries | length == 5' > /dev/null \
    && ok "a predecessor copy keeps the section as it stands, settled entries too" || bad "a predecessor copy keeps the section as it stands"

echo "== usage =="
bash "$R" --format nope < /dev/null > /dev/null 2>&1; [ $? -eq 64 ] && ok "render usage error exits 64" || bad "render usage error exits 64"
bash "$P" --expect-scope bogus < /dev/null > /dev/null 2>&1; [ $? -eq 64 ] && ok "parse usage error exits 64" || bad "parse usage error exits 64"
printf 'not json' | bash "$R" --written "$W" > /dev/null 2>&1; [ $? -eq 65 ] && ok "non-JSON input is refused" || bad "non-JSON input is refused"

echo
echo "record-codec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
