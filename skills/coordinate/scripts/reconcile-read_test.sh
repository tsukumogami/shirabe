#!/usr/bin/env bash
# reconcile-read_test.sh -- reconcile-read.sh reads the run's record, and at
# discipline scope the previous rotation's handoff, through the record
# feature's parser, and refuses with a distinct exit for no record, a body that
# isn't a record of this scope, and a failed read.
#
# The script runs from a copy of the tree in a temp directory. gh and the
# record feature's coord-log.sh and record-parse.sh are keyed stand-ins: each
# call is appended to the case's log and served from <case>/<key>.out.<N>
# (the Nth call to that key), with an optional .rc.<N> exit status, .err.<N>
# stderr and .sleep.<N> delay. record-parse.sh is keyed by its format, plus
# "-nc" for a --no-canonical call.
#
# The contract cases run the record feature's real record-parse.sh, when it is
# beside this script (or in RECORD_FEATURE_SCRIPTS), on bodies its own
# record-render.sh produced, so the keys this script reads are the parser's.
#
# Usage: bash skills/coordinate/scripts/reconcile-read_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-read-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/tree/skills/coordinate/scripts" "$T/tree/skills/execute/scripts" "$T/bin"
cp "$HERE"/reconcile-read.sh "$HERE"/reconcile-deps.sh "$HERE"/reconcile-salvage.jq "$T/tree/skills/coordinate/scripts/"
cp "$HERE/../../execute/scripts/coord-common.sh" "$T/tree/skills/execute/scripts/"
S="$T/tree/skills/coordinate/scripts/reconcile-read.sh"
# A stand-in codec with the one definition the stubbed cases reach: the
# record feature's fixed not-recorded sentence.
cat > "$T/tree/skills/coordinate/scripts/record-codec.jq" <<'CODEC'
def predecessor_sentence: "The outgoing rotation's reasoning was not recorded.";
CODEC

cat > "$T/bin/stub" <<'STUB'
#!/usr/bin/env bash
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$STUB_LOG"
case "$name:$1:$*" in
    gh:issue:*) key=issue-view ;;
    gh:pr:*) key=pr-view ;;
    gh:api:*/contents/*) key=handoff ;;
    gh:api:*) key=repo ;;
    coord-log.sh:run-facts:*) key=facts ;;
    record-parse.sh:*)
        key=parse-record
        case " $* " in *" --format handoff "*) key=parse-handoff ;; esac
        case " $* " in *" --no-canonical "*) key=$key-nc ;; esac ;;
    *) echo "stub: unexpected call: $name $*" >&2; exit 99 ;;
esac
n_file="$STUB_DIR/.n.$key"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
[ -f "$STUB_DIR/$key.sleep.$n" ] && sleep "$(cat "$STUB_DIR/$key.sleep.$n")"
[ -f "$STUB_DIR/$key.err.$n" ] && cat "$STUB_DIR/$key.err.$n" >&2
rc=$(cat "$STUB_DIR/$key.rc.$n" 2>/dev/null || echo 0)
jqexpr=""
prev=""
for a in "$@"; do [ "$prev" = --jq ] && jqexpr=$a; prev=$a; done
if [ -f "$STUB_DIR/$key.out.$n" ]; then
    if [ "$name" = gh ] && [ -n "$jqexpr" ] && [ "$rc" = 0 ]; then
        jq -r "$jqexpr" < "$STUB_DIR/$key.out.$n" || exit 1
    else
        cat "$STUB_DIR/$key.out.$n"
    fi
fi
exit "$rc"
STUB
chmod +x "$T/bin/stub"
ln -s stub "$T/bin/gh"
for n in coord-log.sh record-parse.sh; do ln -s "$T/bin/stub" "$T/tree/skills/coordinate/scripts/$n"; done

CASE=""
CASES=0
new_case() {
    CASES=$((CASES + 1))
    CASE="$T/case-$CASES-$1"
    mkdir -p "$CASE"
    : > "$CASE/log"
}
serve() { printf '%s' "$3" > "$CASE/$1.out.$2"; }
fail_with() { echo "$3" > "$CASE/$1.rc.$2"; [ -n "${4-}" ] && printf '%s' "$4" > "$CASE/$1.err.$2"; return 0; }
run() {
    STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$T/bin:$PATH" \
      RECONCILE_READ_DEADLINE="${DL:-5}" "$BASH" "$S" "$@"
}
RC=0
capture() { OUT=$(run "$@"); RC=$?; }
expect() {  # expect <label> <jq predicate> [exit]
    if [ "$RC" = "${3:-0}" ] && printf '%s' "$OUT" | jq -e "$2" >/dev/null 2>&1; then ok "$1"
    else bad "$1" "exit $RC: $OUT | log: $(cat "$CASE/log")"; fi
}

R=acme/widgets
SHA=0123456789abcdef0123456789abcdef01234567
HOLD="{\"unit\":\"Feature 2\",\"entry_point\":\"/shirabe:deliver\",\"mode\":\"--auto\",\"phase\":\"executing\",\"dispatch_status\":\"dispatched\",\"return_path\":\"message\",\"worker\":\"plugin-registry\",\"repo\":\"$R\",\"branch\":\"feat/x\",\"verified_head\":\"$SHA\",\"dispatched\":\"2026-09-26\",\"pull_request\":\"[#12](https://github.com/$R/pull/12)\"}"
DEF='{"deferral":"flaky test","reason":"not now","raised":"2026-09-25T10:00Z","disposition":""}'
SIDE="{\"action\":\"merge\",\"target\":\"#12\",\"verified_head\":\"$SHA\",\"attempted\":\"2026-09-26T11:02Z\",\"how_to_confirm\":\"compare blobs on main\"}"
ROADMAP_JSON="{\"scope\":{\"kind\":\"roadmap\",\"name\":\"plugin-system\"},\"written\":\"2026-09-26T12:00:00Z\",\"holdings\":[$HOLD],\"deferrals\":[$DEF],\"side_effects\":[$SIDE],\"reversals\":[]}"
DISC_JSON=$(printf '%s' "$ROADMAP_JSON" | jq -c '.scope = {kind: "discipline", name: "ci-health"}')
HANDOFF_JSON=$(printf '%s' "$DISC_JSON" | jq -c 'del(.written) | .holdings[0].worker = "flaky-fix" | .deferrals[0].deferral = "old gap" | .side_effects = [] | .rotation = {start: "2026-09-20", end: "2026-09-23", date: "2026-09-23", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/77"} | .reasoning = "The flaky job is timing."')
OPEN='{"state":"OPEN","body":"a record body"}'
FACTS_RM="{\"scope\":\"roadmap\",\"name\":\"plugin-system\",\"repo\":\"$R\",\"ref\":\"40\"}"
FACTS_DS="{\"scope\":\"discipline\",\"name\":\"ci-health\",\"repo\":\"$R\",\"ref\":\"77\"}"
ROADMAP_ARGS="--scope roadmap --name plugin-system --repo $R --ref 40"
DISC_ARGS="--scope discipline --name ci-health --repo $R --ref 77"

echo "== the run's record =="
new_case found-roadmap
serve facts 1 "$FACTS_RM"; serve issue-view 1 "$OPEN"; serve parse-record 1 "$ROADMAP_JSON"
capture --session coordinate-plugin-system-20260926T120000Z
expect "a roadmap record is read from its issue, with each row sourced to the record" \
    '.status == "found" and .scope == {kind: "roadmap", name: "plugin-system", repo: "acme/widgets"} and .record.written == "2026-09-26T12:00:00Z" and .record.source == "record" and .record.handoff_date == null and (.holdings | length) == 1 and .holdings[0].source == "record" and .holdings[0].row.verified_head == "'$SHA'" and .deferrals[0].row.deferral == "flaky test" and .deferrals[0].source == "record" and .side_effects[0].row.action == "merge" and .unparseable == [] and .reasoning == null'
grep -q "issue view 40 --repo $R --json state,body" "$CASE/log" && ok "the body is read live from the issue the run found" || bad "the body is read live from the issue the run found" "$(cat "$CASE/log")"
grep -q -- "--container issue --expect-scope roadmap:plugin-system" "$CASE/log" && ok "the parser is told the container and the scope it must match" || bad "the parser is told the container and the scope it must match" "$(cat "$CASE/log")"

new_case no-record
serve facts 1 ""; fail_with facts 1 1
capture --session s1
expect "a run that found no record is refused as none" '.status == "none"' 3

new_case facts-fail
fail_with facts 1 2 "coord-log: no readable log"
capture --session s1
expect "an unreadable session log is a failed read" '.status == "failed"' 5

new_case facts-bad-repo
serve facts 1 '{"scope":"roadmap","name":"x","repo":"not a repo","ref":"40"}'
capture --session s1
expect "a host the facts name badly is refused before any GitHub call" '.status == "failed"' 5
grep -q '^gh ' "$CASE/log" && bad "no GitHub call on bad facts" "$(cat "$CASE/log")" || ok "no GitHub call on bad facts"

new_case facts-bad-scope
serve facts 1 '{"scope":"project","name":"x","repo":"acme/widgets","ref":"40"}'
capture --session s1
expect "a scope other than roadmap or discipline is refused" '.status == "failed"' 5

new_case closed
serve issue-view 1 '{"state":"CLOSED","body":"a record body"}'
capture $ROADMAP_ARGS
expect "a record that is no longer open is unreadable" '.status == "unreadable"' 4

new_case view-fail
fail_with issue-view 1 1 "HTTP 502"
capture $ROADMAP_ARGS
expect "a failed body read is a failed read" '.status == "failed"' 5

new_case view-late
serve issue-view 1 "$OPEN"; echo 3 > "$CASE/issue-view.sleep.1"
OUT=$(DL=1 run $ROADMAP_ARGS); RC=$?
expect "a body read past the deadline is a failed read" '.status == "failed" and (.reason | test("timed out"))' 5

new_case view-garbled
serve issue-view 1 '{"state":"OPEN"}'
capture $ROADMAP_ARGS
expect "a response without a body is a failed read" '.status == "failed"' 5

new_case wrong-scope
serve issue-view 1 "$OPEN"; fail_with parse-record 1 65 "record-parse: refused: the record is for roadmap:plugin-system-v2, not roadmap:plugin-system"
capture $ROADMAP_ARGS
expect "a body the parser refuses (another scope, malformed) is unreadable" '.status == "unreadable"' 4

new_case parser-broken
serve issue-view 1 "$OPEN"; fail_with parse-record 1 1
capture $ROADMAP_ARGS
expect "an internal parser failure is a failed read, not an unreadable record" '.status == "failed"' 5

new_case too-large
serve issue-view 1 "$OPEN"; fail_with parse-record 1 65 "record-parse: refused: body is 70000 bytes, over GitHub's 65536"
capture $ROADMAP_ARGS
expect "a body over GitHub's size limit is unreadable, not salvaged" '.status == "unreadable"' 4

echo "== discipline scope and the handoff =="
new_case disc-handoff
serve facts 1 "$FACTS_DS"; serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"
serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "the handoff file"; serve parse-handoff 1 "$HANDOFF_JSON"
capture --session coordinate-ci-health-20260926T120000Z --reasoning-out "$CASE/reasoning.txt"
expect "a discipline record is read with the previous rotation's handoff, the record's rows first" \
    '.status == "found" and .scope.kind == "discipline" and .record.source == "record and handoff" and .record.handoff_date == "2026-09-23" and ([.holdings[].source] == ["record", "handoff"]) and .holdings[1].row.worker == "flaky-fix" and ([.deferrals[] | .row.deferral + "/" + .source] == ["flaky test/record", "old gap/handoff"]) and (.side_effects | length) == 1 and .reasoning == "present"'
[ "$(cat "$CASE/reasoning.txt" 2>/dev/null)" = "The flaky job is timing." ] && ok "the predecessor's reasoning is written verbatim to the file named" || bad "the predecessor's reasoning is written verbatim to the file named" "$(cat "$CASE/reasoning.txt" 2>&1)"
grep -q "pr view 77 --repo $R --json state,body" "$CASE/log" && ok "the discipline record is read from its pull request" || bad "the discipline record is read from its pull request" "$(cat "$CASE/log")"
grep -q "contents/docs/disciplines/ci-health.md?ref=main" "$CASE/log" && ok "the handoff is read from the host's default branch" || bad "the handoff is read from the host's default branch" "$(cat "$CASE/log")"
grep -q -- "--format handoff --container pr --expect-scope discipline:ci-health" "$CASE/log" && ok "the handoff is parsed as a handoff for this discipline" || bad "the handoff is parsed as a handoff for this discipline" "$(cat "$CASE/log")"

new_case disc-first-rotation
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'
fail_with handoff 1 1 "gh: Not Found (HTTP 404)"
capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
expect "no handoff file is a first rotation: reasoning absent, the record's rows only" \
    '.status == "found" and .reasoning == "absent" and .record.source == "record" and .record.handoff_date == null and ([.holdings[].source] == ["record"])'
[ -e "$CASE/reasoning.txt" ] && bad "no reasoning file is written for a first rotation" || ok "no reasoning file is written for a first rotation"

new_case disc-predecessor-copy
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "the handoff file"
serve parse-handoff 1 "$(printf '%s' "$HANDOFF_JSON" | jq -c 'del(.reasoning) | .predecessor_copy = {written: "2026-09-23T17:00:00Z"}')"
capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
expect "a predecessor copy is reasoning not recorded" '.status == "found" and .reasoning == "not_recorded"'
[ -e "$CASE/reasoning.txt" ] && bad "nothing is written on the predecessor's behalf" "$(cat "$CASE/reasoning.txt")" || ok "nothing is written on the predecessor's behalf"

new_case disc-handoff-wrong
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "not a handoff"
fail_with parse-handoff 1 65 "record-parse: refused: no handoff heading"
capture $DISC_ARGS
expect "a handoff file that isn't a handoff is unreadable" '.status == "unreadable" and (.reason | test("handoff"))' 4

new_case disc-handoff-fail
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'
fail_with handoff 1 1 "HTTP 502"
capture $DISC_ARGS
expect "a failed handoff read is a failed read, not a first rotation" '.status == "failed"' 5

new_case disc-handoff-late
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
echo 3 > "$CASE/handoff.sleep.1"
OUT=$(DL=1 run $DISC_ARGS); RC=$?
expect "a handoff read past the deadline is a failed read" '.status == "failed" and (.reason | test("timed out"))' 5

new_case disc-repo-fail
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; fail_with repo 1 1
capture $DISC_ARGS
expect "an unreadable default branch is a failed read" '.status == "failed"' 5
grep -q contents "$CASE/log" && bad "no handoff read without a default branch" || ok "no handoff read without a default branch"

new_case disc-sentence
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
serve parse-handoff 1 "$(printf '%s' "$HANDOFF_JSON" | jq -c '.reasoning = "The outgoing rotation\u0027s reasoning was not recorded.\n"')"
echo stale > "$CASE/reasoning.txt"
capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
expect "the fixed not-recorded sentence without its copy line is still not recorded" '.status == "found" and .reasoning == "not_recorded"'
[ -e "$CASE/reasoning.txt" ] && bad "a reasoning file from an earlier read is not left behind" "$(cat "$CASE/reasoning.txt")" || ok "a reasoning file from an earlier read is not left behind"

new_case disc-other-host
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
serve parse-handoff 1 "$(printf '%s' "$HANDOFF_JSON" | jq -c '.rotation.host_repo = "evil/other"')"
capture $DISC_ARGS
expect "a handoff naming another host repository is unreadable" '.status == "unreadable" and (.reason | test("another host"))' 4

new_case disc-dedupe
serve pr-view 1 "$OPEN"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
serve parse-record 1 "$DISC_JSON"
serve parse-handoff 1 "$(printf '%s' "$DISC_JSON" | jq -c --argjson h "$HANDOFF_JSON" 'del(.written) | .rotation = $h.rotation | .reasoning = "r" | .side_effects += [{action: "close", target: "#3", verified_head: "", attempted: "2026-09-22T10:00Z", how_to_confirm: "read it"}]')"
capture $DISC_ARGS
expect "rows the record already carries are not listed again from the handoff" \
    '([.holdings[].source] == ["record"]) and ([.deferrals[].source] == ["record"]) and ([.side_effects[] | .row.action + "/" + .source] == ["merge/record", "close/handoff"])'

new_case disc-del-date
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
serve parse-handoff 1 "$(printf '%s' "$HANDOFF_JSON" | jq -c '.rotation.date = "2026-09-23\u007f"')"
capture $DISC_ARGS
expect "a heading date carrying a control character is not carried as a date" \
    '.status == "found" and .record.handoff_date == null and (.unparseable | any(.reason | test("heading date")))'

new_case disc-bad-date
serve pr-view 1 "$OPEN"; serve parse-record 1 "$DISC_JSON"; serve repo 1 '{"default_branch":"main"}'; serve handoff 1 "x"
serve parse-handoff 1 "$(printf '%s' "$HANDOFF_JSON" | jq -c '.rotation.date = "<b>soon</b>"')"
capture $DISC_ARGS
expect "a handoff heading date that isn't a date is not carried, and is listed" \
    '.status == "found" and .record.handoff_date == null and (.unparseable | any(.reason | test("heading date")))'

echo "== usage =="
new_case usage
usage_is() { local label=$1; shift; run "$@" >/dev/null 2>&1; [ $? = 64 ] && ok "$label" || bad "$label"; }
usage_is "no arguments is a usage error"
usage_is "a partial override is a usage error" --scope roadmap --name x
usage_is "a session with overrides is a usage error" --session s1 $ROADMAP_ARGS
usage_is "a flag without its value is a usage error" --session

echo "== contract: the record feature's own parser =="
REAL=""
for d in "${RECORD_FEATURE_SCRIPTS:-}" "$HERE"; do
    [ -n "$d" ] && [ -f "$d/record-parse.sh" ] && [ -f "$d/record-render.sh" ] && [ -f "$d/record-codec.jq" ] && { REAL=$d; break; }
done
if [ -z "$REAL" ]; then
    echo "skip contract cases: the record feature's parser is not beside this script"
else
    C="$T/real/skills/coordinate/scripts"
    mkdir -p "$C" "$T/real/skills/execute/scripts"
    cp "$HERE"/reconcile-read.sh "$HERE"/reconcile-deps.sh "$HERE"/reconcile-salvage.jq "$C/"
    cp "$HERE/../../execute/scripts/coord-common.sh" "$T/real/skills/execute/scripts/"
    for f in "$REAL"/record-*.sh "$REAL"/record-codec.jq; do cp "$f" "$C/"; done
    ln -s "$T/bin/stub" "$C/coord-log.sh"
    S="$C/reconcile-read.sh"
    body() { jq -Rs '{state: "OPEN", body: .}' "$1"; }

    new_case real-roadmap
    printf '%s' "$ROADMAP_JSON" | jq 'del(.written)' | bash "$C/record-render.sh" --written 2026-09-26T12:00:00Z > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    if [ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | jq -c '[.holdings[0].row, .deferrals[0].row, .side_effects[0].row, .record.written, .unparseable]')" = "$(jq -nc --argjson h "$HOLD" --argjson d "$DEF" --argjson s "$SIDE" '[$h, $d, $s, "2026-09-26T12:00:00Z", []]')" ]; then
        ok "the real parser: a rendered roadmap record reads back row for row"
    else bad "the real parser: a rendered roadmap record reads back row for row" "exit $RC: $OUT"; fi

    new_case real-edited
    sed 's/plugin-registry/plugin-registry (hand edit)/' "$CASE/../case-$((CASES - 1))-real-roadmap/body.md" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a row whose cell breaks the grammar is set aside with its line; the rest is read" \
        '.status == "found" and (.holdings | length) == 0 and (.deferrals | length) == 1 and (.unparseable | length) == 1 and (.unparseable[0].raw | test("hand edit")) and (.unparseable[0].reason | test("^worker: "))'
    case "$OUT" in *"$C"*) bad "the real parser: no path of the parser in the output" "$OUT" ;; *) ok "the real parser: no path of the parser in the output" ;; esac
    RB="$T/real-roadmap-body.md"
    cp "$CASE/../case-$((CASES - 1))-real-roadmap/body.md" "$RB"

    new_case real-extra-cell
    sed 's/| flaky test | not now |/| flaky test | extra | not now |/' "$RB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a row with an extra cell is set aside; every other row is still read" \
        '.status == "found" and (.holdings | length) == 1 and (.deferrals | length) == 0 and (.side_effects | length) == 1 and (.unparseable[0].raw | test("extra")) and (.unparseable[0].reason | test("Deferrals"))'

    new_case real-phrase
    sed 's/| flaky test | not now |/| the record is for later, 5 bytes, over | x | not now |/' "$RB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a hand edit quoting the parser's refusal words is still read row by row" \
        '.status == "found" and (.holdings | length) == 1 and (.unparseable | length) == 1'

    new_case real-spacing
    sed 's/^Written: /Written:  /' "$RB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a body that parses but differs from its rendering lists the differing line" \
        '.status == "found" and (.holdings | length) == 1 and (.unparseable | any(.reason | test("^not canonical")))'
    expect "the real parser: the Written: time is read without the stray space" '.record.written == "2026-09-26T12:00:00Z"'

    new_case real-control
    sed "s/^Written: \(.*\)$/Written: \1$(printf '\033')[31m/; s/| not now |/| not$(printf '\r')now |/" "$RB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    case "$OUT" in *'\u001b'*|*'\r'*|*'\u000d'*) bad "the real parser: no control character reaches the output" "$OUT" ;; *) ok "the real parser: no control character reaches the output" ;; esac

    new_case real-multiline
    printf '%s' "$ROADMAP_JSON" | jq 'del(.written) | .deferrals[0].reason = "line one\nline two\tafter tab"' \
        | bash "$C/record-render.sh" --written 2026-09-26T12:00:00Z > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a newline and a tab inside a cell survive the read" \
        '.deferrals[0].row.reason == "line one\nline two\tafter tab" and .unparseable == []'

    new_case real-bad-written
    sed 's/^Written: .*$/Written: whenever <b>x<\/b>/' "$RB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a Written: line that isn't a time is not carried, and is listed" \
        '.status == "found" and .record.written == null and (.unparseable | any(.reason | test("Written")))'

    # The record feature's `held` phase (3891bf4): once its codec accepts the
    # value, a held row reads back as a row, not as unparseable.
    if grep -q 'held' "$C/record-codec.jq"; then
        new_case real-held
        printf '%s' "$ROADMAP_JSON" | jq 'del(.written) | .holdings[0].phase = "held"' \
            | bash "$C/record-render.sh" --written 2026-09-26T12:00:00Z > "$CASE/body.md"
        serve issue-view 1 "$(body "$CASE/body.md")"
        capture $ROADMAP_ARGS
        expect "the real parser: a held row reads back with its phase and verified head" \
            '.status == "found" and .holdings[0].row.phase == "held" and (.holdings[0].row.verified_head | length) == 40 and .unparseable == []'
    else
        echo "skip held-row contract case: this codec predates the record feature's held phase (3891bf4)"
    fi

    new_case real-other-scope
    serve issue-view 1 "$(body "$RB")"
    capture --scope roadmap --name plugin --repo $R --ref 40
    expect "the real parser: a record for another roadmap is unreadable" '.status == "unreadable"' 4

    # A record carrying a Decisions section: read whole when canonical, and
    # salvaged row by row when not, with a Decisions section it can't read set
    # aside as one item.
    DEC_E='{"decision":"1","round":"0","question":"Ship first?","options":"ship -- now\nwait -- later","state":"proposed","source":"self [20260926T080000Z raise 3]","updated":"2026-09-26T07:00Z"}'
    new_case real-decisions
    printf '%s' "$ROADMAP_JSON" | jq --argjson e "$DEC_E" 'del(.written) | .decisions = {next: 2, entries: [$e]}' \
        | bash "$C/record-render.sh" --written 2026-09-26T12:00:00Z > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a record with a Decisions section is read" '.status == "found" and (.holdings | length) == 1 and .unparseable == []'
    expect "a proposed entry isn't among the decisions the report shows a person" '.decisions == []'
    RDB="$T/real-decisions-body.md"; cp "$CASE/body.md" "$RDB"
    new_case real-decisions-escalated
    DEC_X=$(jq -nc --argjson e "$DEC_E" '$e + {round: "1", state: "escalated", verdict: "escalate", recommendation: "wait", reason: "r", context: "c", problem: "p", grounds: "scope", target: "a person"}')
    printf '%s' "$ROADMAP_JSON" | jq --argjson e "$DEC_X" 'del(.written) | .decisions = {next: 2, entries: [$e]}' \
        | bash "$C/record-render.sh" --written 2026-09-26T12:00:00Z > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "an escalated entry is carried with its question, recommendation, reason and target" \
        '.decisions == [{"decision":"1","question":"Ship first?","recommendation":"wait","reason":"r","target":"a person"}]'
    new_case real-decisions-bad-row
    sed 's/plugin-registry/plugin-registry (hand edit)/' "$RDB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a record with a Decisions section and one bad row is salvaged, not unreadable" \
        '.status == "found" and (.holdings | length) == 0 and (.deferrals | length) == 1 and (.unparseable | length) == 1 and (.unparseable[0].raw | test("hand edit"))'
    new_case real-decisions-bad-decision
    sed 's/| proposed |/| maybe |/' "$RDB" > "$CASE/body.md"
    serve issue-view 1 "$(body "$CASE/body.md")"
    capture $ROADMAP_ARGS
    expect "the real parser: a Decisions section it can't read is one unparseable item; every other row is read" \
        '.status == "found" and (.holdings | length) == 1 and (.deferrals | length) == 1 and (.unparseable | any(.raw == "## Decisions"))'

    new_case real-discipline
    printf '%s' "$DISC_JSON" | jq 'del(.written)' | bash "$C/record-render.sh" --container pr --written 2026-09-26T12:00:00Z > "$CASE/body.md"
    printf '%s' "$HANDOFF_JSON" | bash "$C/record-render.sh" --format handoff > "$CASE/handoff.md"
    serve pr-view 1 "$(body "$CASE/body.md")"; serve repo 1 '{"default_branch":"main"}'; cp "$CASE/handoff.md" "$CASE/handoff.out.1"
    capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
    expect "the real parser: a discipline record and its handoff read back, rotation date and reasoning included" \
        '.status == "found" and .record.handoff_date == "2026-09-23" and ([.holdings[].row.worker] == ["plugin-registry", "flaky-fix"]) and .reasoning == "present" and .unparseable == []'
    [ "$(cat "$CASE/reasoning.txt" 2>/dev/null)" = "The flaky job is timing." ] && ok "the real parser: the reasoning comes back verbatim" || bad "the real parser: the reasoning comes back verbatim" "$(cat "$CASE/reasoning.txt" 2>&1)"
    DB="$T/real-disc-body.md"; cp "$CASE/body.md" "$DB"; cp "$CASE/handoff.md" "$DB.handoff"

    # handoff_case SED: the rendered handoff edited by SED, read as the
    # previous rotation's file.
    handoff_case() {
        new_case real-handoff
        sed "$1" "$DB.handoff" > "$CASE/handoff.out.1"
        serve pr-view 1 "$(body "$DB")"; serve repo 1 '{"default_branch":"main"}'
        capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
    }
    handoff_case '/^## Reasoning for the next rotation$/,$d'
    expect "the real parser: a handoff without its reasoning section is read, reasoning not recorded" \
        '.status == "found" and .reasoning == "not_recorded" and ([.holdings[].source] == ["record", "handoff"])'
    handoff_case '/^The flaky job is timing\.$/d'
    expect "the real parser: a handoff with an empty reasoning section is read, reasoning not recorded" \
        '.status == "found" and .reasoning == "not_recorded"'
    [ -e "$CASE/reasoning.txt" ] && bad "the real parser: nothing is written for an empty reasoning" || ok "the real parser: nothing is written for an empty reasoning"
    # A handoff carrying unsettled decisions, canonical and with one bad row.
    printf '%s' "$HANDOFF_JSON" | jq --argjson e "$DEC_E" '.decisions = {next: 2, entries: [$e]}' \
        | bash "$C/record-render.sh" --format handoff > "$DB.handoff-d"
    new_case real-handoff-decisions
    cp "$DB.handoff-d" "$CASE/handoff.out.1"
    serve pr-view 1 "$(body "$DB")"; serve repo 1 '{"default_branch":"main"}'
    capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
    expect "the real parser: a handoff with a Decisions section is read, reasoning included" \
        '.status == "found" and .reasoning == "present" and ([.holdings[].source] == ["record", "handoff"]) and .unparseable == []'
    new_case real-handoff-decisions-bad-row
    sed 's/flaky-fix/flaky-fix (hand edit)/' "$DB.handoff-d" > "$CASE/handoff.out.1"
    serve pr-view 1 "$(body "$DB")"; serve repo 1 '{"default_branch":"main"}'
    capture $DISC_ARGS --reasoning-out "$CASE/reasoning.txt"
    expect "the real parser: a handoff with a Decisions section and one bad row is salvaged" \
        '.status == "found" and .reasoning == "present" and ([.holdings[].source] == ["record"]) and (.unparseable | any(.raw | test("hand edit")))'
    handoff_case "s/^The flaky job is timing\\.\$/The outgoing rotation's reasoning was not recorded./"
    expect "the real parser: the fixed sentence without its copy line is not recorded" '.status == "found" and .reasoning == "not_recorded"'
    [ -e "$CASE/reasoning.txt" ] && bad "the real parser: the fixed sentence is never written as reasoning" "$(cat "$CASE/reasoning.txt")" || ok "the real parser: the fixed sentence is never written as reasoning"
    handoff_case 's/| old gap | not now |/| old gap | x | not now |/'
    expect "the real parser: a bad handoff row is set aside, labelled as the handoff's" \
        '.status == "found" and (.unparseable | length) == 1 and (.unparseable[0].reason | test("^handoff: Deferrals"))'
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
