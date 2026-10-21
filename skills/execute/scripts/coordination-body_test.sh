#!/usr/bin/env bash
# coordination-body_test.sh — scripts/lib/coordination-body.sh, the codec of
# the coordination PR's body: cb_render, cb_part1, cb_parse.
#
# Pure: jq and awk over files, no gh, no koto. Covers:
#   - three record documents (nodes open, merged and closed; zero, one and
#     two follow-ups and a removed one; a live Part 1 and the composed one)
#     rendered byte for byte against testdata/rendered-body-*.md
#   - each render: exactly one top-level `---`; the marker and every run line
#     below it; no line naming the coordination PR's number; the merge-last
#     gate's ref filter (scripts/coordination-gate-refs.sh) listing exactly
#     the nodes and follow-ups; the real `shirabe validate
#     --coordination-body` finding nothing (reported SKIP when no real binary
#     is at hand; crates/shirabe/tests/coordination_body.rs covers it in CI)
#   - a merged node shows its merged_head; a state the document lacks renders
#     unknown; the merge-order section is testdata/merge-order-gated.txt
#   - Part 1: a body with none gets exactly the composed sentence; one with a
#     list, a fence holding `---`, and \r\n line endings is kept byte for
#     byte; a re-render of a render is byte-identical
#   - refusals: a private node or follow-up under a public home (3, the node
#     named, the repository not, nothing printed); a render over 60,000 bytes
#     (4); an invalid document and an indexed repository with no visibility
#     under a public home (2)
#   - cb_parse: a render read back (no heads returned; its run, store and
#     run lines), an older body's self row and self ref dropped, /scope's
#     body has no index, the pre-render index grammar parsed whole (a pin),
#     the region rule (nothing above the first top-level `---` is read, a
#     fenced `---` is not the separator, a body without one has no run), the
#     first well-formed run line of each key, and the over-cap,
#     malformed-entry, `..` path and duplicate-node refusals
#
# Usage: coordination-body_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
TD="$SCRIPT_DIR/testdata"
GATE_REFS="$REPO_ROOT/scripts/coordination-gate-refs.sh"
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }
PROG=coordination-body-test
# shellcheck source=../../../scripts/lib/coordination-body.sh
. "$REPO_ROOT/scripts/lib/coordination-body.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/coordination-body-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; return 0; }
same_file() { # same_file <name> <want-file> <got-file>
    if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "$(diff "$2" "$3" | head -10)"; fi
}

H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
M1=3333333333333333333333333333333333333333
M2=4444444444444444444444444444444444444444
RUN=00112233445566778899aabbccddeeff

# The documents. open: two nodes open in one repository, no follow-ups, a
# person's Part 1. mixed: the gated PLAN's three nodes, core merged (two
# live follow-ups, one open and one merged, and a removed one), cli closed in
# a second repository with one follow-up, one follow-up's state unread.
# composed: /scope's body (no Part 1 yet), its run lines, one node pushed.
NODES2='[{"name":"pr-repo-a-core","kind":"pr","repo":"acme/repo-a","waits_on":[]},{"name":"pr-repo-a-cli","kind":"pr","repo":"acme/repo-a","waits_on":["pr-repo-a-core"]}]'
NODES3='[{"name":"pr-repo-a-core","kind":"pr","repo":"acme/repo-a","waits_on":[]},{"name":"gate-publish-core","kind":"gate","repo":"","waits_on":["pr-repo-a-core"]},{"name":"pr-repo-a-cli","kind":"pr","repo":"acme/repo-b","waits_on":["pr-repo-a-core","gate-publish-core"]}]'
HOME_PUB='{"repo":"acme/repo-a","pr":10,"visibility":"public"}'

doc() { # doc <out> <part1-json> <nodes> <records> <follow-ups> <states> <visibility> [run-lines] [store]
    local rl="${8:-}"
    [ -n "$rl" ] || rl='{}'
    jq -n --argjson p1 "$2" --argjson nodes "$3" --argjson rec "$4" --argjson fu "$5" \
        --argjson st "$6" --argjson vis "$7" --argjson rl "$rl" --arg store "${9:-github}" \
        --arg run "$RUN" --argjson home "$HOME_PUB" '
        {topic: "t", part1: $p1, run_lines: $rl, store: $store, run: $run, nodes: $nodes,
         records: $rec, follow_ups: $fu, states: $st, home: $home, visibility: $vis}' > "$1"
}

doc "$T/open.json" '"Ships the parser and its CLI.\n\n"' "$NODES2" \
    "{\"pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$H1\"},\"pr-repo-a-cli\":{\"repo\":\"acme/repo-a\",\"pr\":12,\"head\":\"$H2\"}}" \
    '{}' '{"acme/repo-a#11":"open","acme/repo-a#12":"open"}' '{}' '{"topic":"t","mode":"coordinated"}'
doc "$T/mixed.json" '"Two repositories, one gate.\n\n"' "$NODES3" \
    "{\"pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$H1\",\"merged_head\":\"$M1\"},\"pr-repo-a-cli\":{\"repo\":\"acme/repo-b\",\"pr\":5,\"head\":\"$H2\"}}" \
    "{\"pr-repo-a-core\":[{\"repo\":\"acme/repo-a\",\"pr\":22,\"head\":\"$H2\",\"merged_head\":\"$M2\"},{\"repo\":\"acme/repo-a\",\"pr\":21,\"head\":\"$H1\"},{\"repo\":\"acme/repo-a\",\"pr\":23,\"head\":\"$H1\",\"removed\":true}],\"pr-repo-a-cli\":[{\"repo\":\"acme/repo-b\",\"pr\":7,\"head\":\"$H2\"}]}" \
    '{"acme/repo-a#11":"merged","acme/repo-a#21":"open","acme/repo-a#22":"merged","acme/repo-b#5":"closed"}' \
    '{"acme/repo-b":"public"}' '{"topic":"t","exit":"published","outcome":"planned","intent":"ship","mode":"coordinated"}'
doc "$T/composed.json" null "$NODES2" \
    "{\"pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$H1\"}}" \
    '{}' '{"acme/repo-a#11":"open"}' '{}' '{"topic":"t","exit":"published","mode":"coordinated"}' session

# --- the three renders, byte for byte ---
for f in open mixed composed; do
    cb_render "$T/$f.json" > "$T/$f.md" 2> "$T/$f.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then pass "$f: renders (exit 0)"; else fail "$f: renders (exit 0)" "exit $rc: $(cat "$T/$f.err")"; fi
    same_file "$f: byte-equal to testdata/rendered-body-$f.md" "$TD/rendered-body-$f.md" "$T/$f.md"
done

# top_level_seps <file> -- the number of `---` lines outside a ``` fence.
top_level_seps() {
    awk '/^[ \t]*```/ { f = !f; next } !f && /^[ \t]*---[ \t\r]*$/ { n++ } END { print n + 0 }' "$1"
}
# below_sep <file> <line> -- the line sits after the first top-level `---`.
below_sep() {
    awk -v want="$2" '/^[ \t]*```/ { f = !f } !f && !sep && /^[ \t]*---[ \t\r]*$/ { sep = 1; next }
        sep && $0 == want { found = 1 } END { exit !found }' "$1"
}

# A real shirabe, never the tests' stub: SHIRABE_BIN, a cargo build in this
# checkout, or one on PATH.
REAL_SHIRABE=""
for c in "${SHIRABE_BIN:-}" "$REPO_ROOT/target/release/shirabe" "$REPO_ROOT/target/debug/shirabe" "$(command -v shirabe || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if "$c" validate --help </dev/null 2>&1 | grep -q -- '--coordination-body'; then REAL_SHIRABE="$c"; break; fi
done

for f in open mixed composed; do
    B="$T/$f.md"
    n=$(top_level_seps "$B")
    if [ "$n" = 1 ]; then pass "$f: exactly one top-level ---"; else fail "$f: exactly one top-level ---" "found $n"; fi
    ok=1
    for l in "> This is a **coordination PR** for a coordinated effort. It is docs-only and" "store=$(jq -r .store "$T/$f.json")" "run=$RUN" \
             $(jq -r '.run_lines | to_entries[] | "\(.key)=\(.value)"' "$T/$f.json"); do
        below_sep "$B" "$l" || { ok=0; fail "$f: [$l] sits below the ---"; }
    done
    [ "$ok" -eq 1 ] && pass "$f: the marker and every run line sit below the ---"
    if grep -Eq '#10([^0-9]|$)|/pull/10([^0-9]|$)' "$B"; then
        fail "$f: no line names the coordination PR's number" "$(grep -En '#10([^0-9]|$)|/pull/10([^0-9]|$)' "$B")"
    else
        pass "$f: no line names the coordination PR's number"
    fi
    want=$(jq -r '. as $d | [$d.nodes[] | select(.kind == "pr") | .name as $n | select($d.records | has($n))
        | ($d.records[$n] | "\(.repo):docs/plans/PLAN-t.md#\(.pr)"),
          (($d.follow_ups[$n] // [])[] | select((.removed // false) | not) | "\(.repo):docs/plans/PLAN-t.md#\(.pr)")]
        | sort | unique | .[]' "$T/$f.json")
    got=$(bash "$GATE_REFS" acme/repo-a 10 < "$B")
    if [ "$got" = "$want" ]; then pass "$f: coordination-gate-refs.sh lists exactly the nodes and follow-ups"
    else fail "$f: coordination-gate-refs.sh lists exactly the nodes and follow-ups" "want [$want] got [$got]"; fi
    if [ -n "$REAL_SHIRABE" ]; then
        if out=$("$REAL_SHIRABE" validate --coordination-body "$B" 2>&1); then
            pass "$f: shirabe validate --coordination-body finds nothing"
        else
            fail "$f: shirabe validate --coordination-body finds nothing" "$out"
        fi
    else
        printf 'SKIP %s: no real shirabe binary (crates/shirabe/tests/coordination_body.rs covers it)\n' "$f"
    fi
done

# --- the fields ---
if grep -qxF -- "- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | merged | head=$M1" "$T/mixed.md"; then
    pass "a merged node shows its merged_head"
else fail "a merged node shows its merged_head" "$(grep 'pr-repo-a-core |' "$T/mixed.md")"; fi
if grep -qxF -- "- pr-repo-a-cli/follow-up-7 | acme/repo-b:docs/plans/PLAN-t.md#7 | unknown | head=$H2" "$T/mixed.md"; then
    pass "a state the document lacks renders unknown"
else fail "a state the document lacks renders unknown"; fi
if grep -q 'follow-up-23' "$T/mixed.md"; then fail "a removed follow-up is left out"; else pass "a removed follow-up is left out"; fi
idx=$(awk '/^## PR Index/ { s = 1; next } /^## / { s = 0 } s && /^- / { sub(/ \|.*/, ""); print }' "$T/mixed.md" | tr '\n' ' ')
if [ "$idx" = "- pr-repo-a-core - pr-repo-a-core/follow-up-21 - pr-repo-a-core/follow-up-22 - pr-repo-a-cli - pr-repo-a-cli/follow-up-7 " ]; then
    pass "index order: nodes in setup order, each followed by its follow-ups by number"
else fail "index order: nodes in setup order, each followed by its follow-ups by number" "[$idx]"; fi
sed -n '/^## Merge Order/,$p' "$T/mixed.md" > "$T/mixed-order.md"
same_file "the merge-order section is testdata/merge-order-gated.txt" "$TD/merge-order-gated.txt" "$T/mixed-order.md"

# --- Part 1 ---
WANT_P1="Coordination pull request for t. It carries the planning documents for 2 node pull requests and merges after all of them.

---"
if [ "$(head -3 "$T/composed.md")" = "$WANT_P1" ]; then pass "no Part 1: exactly the composed sentence"
else fail "no Part 1: exactly the composed sentence" "$(head -3 "$T/composed.md")"; fi

printf 'Summary line.\r\n\r\n- one\r\n- two\r\n\r\n```\r\n---\r\n```\r\n\r\n---\r\nreviewer context\r\n' > "$T/live-crlf.md"
cb_part1 "$T/live-crlf.md" > "$T/p1.md"; rc=$?
printf 'Summary line.\r\n\r\n- one\r\n- two\r\n\r\n```\r\n---\r\n```\r\n\r\n' > "$T/p1-want.md"
[ "$rc" -eq 0 ] && pass "cb_part1: a body with a top-level --- returns 0" || fail "cb_part1: a body with a top-level --- returns 0" "exit $rc"
same_file "cb_part1: a list, a fenced ---, and \\r\\n endings kept byte for byte" "$T/p1-want.md" "$T/p1.md"
jq --rawfile p "$T/p1.md" '.part1 = $p' "$T/open.json" > "$T/list.json"
cb_render "$T/list.json" > "$T/list.md"
head -c "$(wc -c < "$T/p1.md")" "$T/list.md" > "$T/list-head.md"
same_file "a render keeps that Part 1 byte for byte" "$T/p1-want.md" "$T/list-head.md"
printf '# Coordination PR: t\n\n> This is a **coordination PR**\n\n## PR Index\n' > "$T/scope.md"
cb_part1 "$T/scope.md" > "$T/none.md"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$T/none.md" ]; then pass "cb_part1: no top-level --- returns 1 and prints nothing"
else fail "cb_part1: no top-level --- returns 1 and prints nothing" "exit $rc"; fi

for f in open mixed composed list; do
    cb_part1 "$T/$f.md" > "$T/$f.p1"
    jq --rawfile p "$T/$f.p1" '.part1 = $p' "$T/$f.json" > "$T/$f.again.json"
    cb_render "$T/$f.again.json" > "$T/$f.again.md"
    same_file "$f: a re-render of its own output is byte-identical" "$T/$f.md" "$T/$f.again.md"
done

# --- refusals ---
jq '.records["pr-repo-a-cli"].repo = "acme/secret" | .follow_ups = {} | .visibility = {"acme/secret": "private"}' "$T/open.json" > "$T/private.json"
cb_render "$T/private.json" > "$T/private.out" 2> "$T/private.err"; rc=$?
if [ "$rc" -eq 3 ] && [ ! -s "$T/private.out" ] && grep -q 'pr-repo-a-cli' "$T/private.err" && ! grep -q 'secret' "$T/private.err"; then
    pass "a private node under a public home: 3, the node named, the repository not, nothing printed"
else fail "a private node under a public home: 3, the node named, the repository not, nothing printed" "exit $rc: $(cat "$T/private.err")"; fi
jq '.follow_ups = {"pr-repo-a-core": [{"repo": "acme/secret", "pr": 9, "head": "'"$H1"'"}]} | .visibility = {"acme/secret": "private"}' "$T/open.json" > "$T/private-fu.json"
cb_render "$T/private-fu.json" > "$T/private-fu.out" 2> "$T/private-fu.err"; rc=$?
if [ "$rc" -eq 3 ] && [ ! -s "$T/private-fu.out" ] && grep -q 'pr-repo-a-core/follow-up-9' "$T/private-fu.err" && ! grep -q 'secret' "$T/private-fu.err"; then
    pass "a private follow-up under a public home: 3, named by its node, the repository not"
else fail "a private follow-up under a public home: 3, named by its node, the repository not" "exit $rc: $(cat "$T/private-fu.err")"; fi
jq '.home.visibility = "private" | .records["pr-repo-a-cli"].repo = "acme/secret" | .visibility = {"acme/secret": "private"}' "$T/open.json" > "$T/private-home.json"
cb_render "$T/private-home.json" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "a private home may index a private node" || fail "a private home may index a private node" "exit $rc"
jq '.records["pr-repo-a-cli"].repo = "acme/repo-b" | .visibility = {}' "$T/open.json" > "$T/novis.json"
cb_render "$T/novis.json" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass "an indexed repository with no visibility under a public home: 2" || fail "an indexed repository with no visibility under a public home: 2" "exit $rc"
jq '.records["pr-repo-a-cli"].head = "nothex"' "$T/open.json" > "$T/bad.json"
cb_render "$T/bad.json" > "$T/bad.out" 2>/dev/null; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$T/bad.out" ]; then pass "an invalid document: 2, nothing printed"; else fail "an invalid document: 2, nothing printed" "exit $rc"; fi

# A Part 1 sized so the body is exactly one byte over the cap.
BASE_BYTES=$(wc -c < "$T/composed.md")
COMPOSED_P1_BYTES=$(head -2 "$T/composed.md" | wc -c)
REST=$((BASE_BYTES - COMPOSED_P1_BYTES))
FILL=$((CB_MAX_BYTES + 1 - REST - 1))
awk -v n="$FILL" 'BEGIN { s = ""; while (length(s) < n) s = s "x"; printf "%s\n", s }' > "$T/big.p1"
jq --rawfile p "$T/big.p1" '.part1 = $p' "$T/composed.json" > "$T/big.json"
cb_render "$T/big.json" > "$T/big.out" 2> "$T/big.err"; rc=$?
if [ "$rc" -eq 4 ] && [ ! -s "$T/big.out" ]; then pass "a 60,001-byte render: 4, nothing printed"
else fail "a 60,001-byte render: 4, nothing printed" "exit $rc: $(cat "$T/big.err")"; fi
awk -v n="$((FILL - 1))" 'BEGIN { s = ""; while (length(s) < n) s = s "x"; printf "%s\n", s }' > "$T/cap.p1"
jq --rawfile p "$T/cap.p1" '.part1 = $p' "$T/composed.json" > "$T/cap.json"
cb_render "$T/cap.json" > "$T/cap.out" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -c < "$T/cap.out" | tr -d ' ')" = "$CB_MAX_BYTES" ]; then pass "a 60,000-byte render is under the cap"
else fail "a 60,000-byte render is under the cap" "exit $rc, $(wc -c < "$T/cap.out") bytes"; fi

# --- cb_parse ---
out=$(cb_parse "$T/mixed.md" acme/repo-a 10); rc=$?
want='{"follow_ups":{"pr-repo-a-cli":[{"fu":7,"pr":7,"repo":"acme/repo-b","state":"unknown"}],"pr-repo-a-core":[{"fu":21,"pr":21,"repo":"acme/repo-a","state":"open"},{"fu":22,"pr":22,"repo":"acme/repo-a","state":"merged"}]},"index":true,"nodes":{"pr-repo-a-cli":{"pr":5,"repo":"acme/repo-b","state":"closed"},"pr-repo-a-core":{"pr":11,"repo":"acme/repo-a","state":"merged"}},"run":"'"$RUN"'","run_lines":{"exit":"published","intent":"ship","mode":"coordinated","outcome":"planned","topic":"t"},"store":"github"}'
if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then pass "cb_parse reads a render back"; else fail "cb_parse reads a render back" "exit $rc: $out"; fi
case "$out" in *head*|*"$H1"*|*"$M1"*) fail "cb_parse returns no head" ;; *) pass "cb_parse returns no head" ;; esac
# A follow-up line whose id names another number than its ref keeps both, so
# recovery can drop it.
printf '%s\n' '---' '' '## PR Index' '' '- pr-a | acme/repo-a:docs/plans/PLAN-t.md#11 | open' \
    '- pr-a/follow-up-9 | acme/repo-a:docs/plans/PLAN-t.md#8 | open' > "$T/fu-mismatch.md"
out=$(cb_parse "$T/fu-mismatch.md" acme/repo-a 10); rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | jq -c '.follow_ups["pr-a"]')" = '[{"fu":9,"pr":8,"repo":"acme/repo-a","state":"open"}]' ]; then
    pass "cb_parse keeps a follow-up's own number beside its ref's"
else fail "cb_parse keeps a follow-up's own number beside its ref's" "exit $rc: $out"; fi

cat > "$T/old.md" <<EOF
# Coordination PR: t

> This is a **coordination PR** for a coordinated effort.

topic=t
run=$RUN

## PR Index

- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | open | head=$H1
- coordination | acme/repo-a:docs/plans/PLAN-t.md#10 | open | head=$H2
- self | ACME/Repo-A:docs/plans/PLAN-t.md#10 | open
Some prose in the section.

## Merge Order
EOF
out=$(cb_parse "$T/old.md" acme/repo-a 10); rc=$?
want='{"follow_ups":{},"index":true,"nodes":{"pr-repo-a-core":{"pr":11,"repo":"acme/repo-a","state":"open"}},"run":null,"run_lines":{"topic":"t"},"store":null}'
if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then pass "cb_parse: an older body's coordination row and a self ref are dropped, and with no separator its run is null"
else fail "cb_parse: an older body's coordination row and a self ref are dropped, and with no separator its run is null" "exit $rc: $out"; fi
printf '# Coordination PR: t\n\n> This is a **coordination PR**\n\ntopic=t\n\n## Artifact Chain\n\n- x\n' > "$T/scope.md"
out=$(cb_parse "$T/scope.md"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = '{"follow_ups":{},"index":false,"nodes":{},"run":null,"run_lines":{"topic":"t"},"store":null}' ]; then pass "cb_parse: /scope's body has no index"
else fail "cb_parse: /scope's body has no index" "exit $rc: $out"; fi

# The body node-push.sh wrote before the render existed: its exact line shape
# (`- <node> | <repo>:docs/plans/PLAN-<slug>.md#<n> | open | head=<sha>`), its
# `- coordination | ... | open` self row with no head, /scope's placeholder
# line, and no top-level `---`. Every line of that grammar parses as an entry.
cat > "$T/pre.md" <<EOF
# Coordination PR: t

> This is a **coordination PR** for a coordinated effort.

topic=t
store=session

## PR Index

No node PR is open yet; /execute adds one line per node PR as it opens it.
- coordination | acme/repo-a:docs/plans/PLAN-t.md#10 | open
- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | open | head=$H1
- pr-repo-a-cli | acme/repo-a:docs/plans/PLAN-t.md#12 | merged
EOF
out=$(cb_parse "$T/pre.md" acme/repo-a 10); rc=$?
want='{"follow_ups":{},"index":true,"nodes":{"pr-repo-a-cli":{"pr":12,"repo":"acme/repo-a","state":"merged"},"pr-repo-a-core":{"pr":11,"repo":"acme/repo-a","state":"open"}},"run":null,"run_lines":{"topic":"t"},"store":"session"}'
if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then pass "cb_parse: the pre-render index grammar parses whole, its self row dropped"
else fail "cb_parse: the pre-render index grammar parses whole, its self row dropped" "exit $rc: $out"; fi

# The region rule: a Part 1 holding its own heading, a run= line, a store=
# line, run lines and a fake `## PR Index` entry is never read; the run lines
# and the index below the first top-level `---` are. A `---` inside a fence
# is not the separator.
cat > "$T/region.md" <<EOF
## Notes

run=ffffffffffffffffffffffffffffffff
store=session
topic=part1
\`\`\`
---
\`\`\`

## PR Index

- fake | acme/repo-a:docs/plans/PLAN-t.md#99 | open
---

> This is a **coordination PR** for a coordinated effort.

topic=t
store=github
run=$RUN

## PR Index

- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | open | head=$H1
EOF
out=$(cb_parse "$T/region.md" acme/repo-a 10); rc=$?
want='{"follow_ups":{},"index":true,"nodes":{"pr-repo-a-core":{"pr":11,"repo":"acme/repo-a","state":"open"}},"run":"'"$RUN"'","run_lines":{"topic":"t"},"store":"github"}'
if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then pass "cb_parse reads only below the first top-level ---: Part 1's heading, run, store, run lines and index are ignored"
else fail "cb_parse reads only below the first top-level ---: Part 1's heading, run, store, run lines and index are ignored" "exit $rc: $out"; fi
# A Part 1 index section alone is no index: the region holds none.
printf -- '## PR Index\n\n- pr-a | acme/repo-a:docs/plans/PLAN-t.md#11 | open\n---\n\n> This is a **coordination PR**\n\nstore=github\n\n## Merge Order\n' > "$T/region2.md"
out=$(cb_parse "$T/region2.md"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = '{"follow_ups":{},"index":false,"nodes":{},"run":null,"run_lines":{},"store":"github"}' ]; then
    pass "cb_parse: a PR Index section in Part 1 is not the region's index"
else fail "cb_parse: a PR Index section in Part 1 is not the region's index" "exit $rc: $out"; fi
# The run lines: the first well-formed one of each key, a value over 64
# characters or a store outside the enum skipped.
LONG=$(printf 'x%.0s' $(seq 1 65))
printf 'topic=%s\ntopic=t\nstore=s3\nstore=session\nintent=a b\nintent=deliver\nexit=x\nexit=y\n\n## PR Index\n' "$LONG" > "$T/lines.md"
out=$(cb_parse "$T/lines.md"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = '{"follow_ups":{},"index":true,"nodes":{},"run":null,"run_lines":{"exit":"x","intent":"deliver","topic":"t"},"store":"session"}' ]; then
    pass "cb_parse: the first well-formed run line of each key, and the first store in the enum"
else fail "cb_parse: the first well-formed run line of each key, and the first store in the enum" "exit $rc: $out"; fi
awk -v n="$CB_MAX_BYTES" 'BEGIN { s = "## PR Index\n"; while (length(s) < n) s = s "x"; printf "%s\n", s }' > "$T/over.md"
cb_parse "$T/over.md" > "$T/over.out" 2>/dev/null; rc=$?
if [ "$rc" -eq 3 ] && [ ! -s "$T/over.out" ]; then pass "cb_parse refuses a body over the cap (3)"; else fail "cb_parse refuses a body over the cap (3)" "exit $rc"; fi
parse_rc() { # parse_rc <entry-line>
    printf '## PR Index\n\n- pr-a | acme/repo-a:docs/plans/PLAN-t.md#11 | open\n%s\n' "$1" > "$T/p.md"
    cb_parse "$T/p.md" > /dev/null 2> "$T/p.err"
}
parse_rc '- pr-b | acme/repo-a:docs/plans/PLAN-t.md#12 | pending'; rc=$?
if [ "$rc" -eq 4 ] && grep -q 'line 4' "$T/p.err"; then pass "cb_parse refuses a malformed entry (4, its line)"; else fail "cb_parse refuses a malformed entry (4, its line)" "exit $rc: $(cat "$T/p.err")"; fi
parse_rc '- pr-b | acme/repo-a:docs/../x.md#12 | open'; rc=$?
[ "$rc" -eq 4 ] && pass "cb_parse refuses a .. path (4)" || fail "cb_parse refuses a .. path (4)" "exit $rc"
parse_rc '- pr-a | acme/repo-a:docs/plans/PLAN-t.md#13 | open'; rc=$?
[ "$rc" -eq 4 ] && pass "cb_parse refuses a node named twice (4)" || fail "cb_parse refuses a node named twice (4)" "exit $rc"
cb_parse "$T/missing.md" > /dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass "cb_parse: an unreadable file is 2" || fail "cb_parse: an unreadable file is 2" "exit $rc"

# --- cb_parse_entry ---
if cb_parse_entry "- pr-a/follow-up-4 | acme/repo-a:docs/plans/PLAN-t.md#4 | merged | head=$H1" \
    && [ "$CB_E_NODE/$CB_E_FU/$CB_E_REPO/$CB_E_NUM/$CB_E_STATE" = "pr-a/4/acme/repo-a/4/merged" ]; then
    pass "cb_parse_entry reads a follow-up line"
else fail "cb_parse_entry reads a follow-up line"; fi
if cb_parse_entry "- pr-a | ./x:docs/a.md#4 | open"; then fail "cb_parse_entry refuses a . repository half"; else pass "cb_parse_entry refuses a . repository half"; fi

echo
echo "coordination-body: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
