#!/usr/bin/env bash
# review-events_test.sh -- does review-events.sh record a jury's rounds, its
# seats' per-rule verdicts and the decisions, drop what it should, and stay
# best effort?
#
# The stand-ins are doc-check_test.sh's (scripts/lib/doc-check-testlib.sh): a
# stub koto that keeps sessions as directories and logs every `review record`
# call with the --file contents. The seat outputs are recorded files under
# scripts/fixtures/review-events/. When the koto on PATH carries `koto review
# record`, the contract case also feeds a recorded batch to it.
#
# Usage: review-events_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
EVENTS="$SCRIPT_DIR/review-events.sh"
FIX="$SCRIPT_DIR/fixtures/review-events"
LEAK=zq7xLEAKzq7x

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$EVENTS" ] || { echo "$EVENTS is missing or not executable" >&2; exit 2; }

REAL_KOTO=$(command -v koto 2>/dev/null || true)

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/review-events-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */review-events-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
LOG="$STUB_KOTO_DIR/review.log"
RC=0
ev() { (cd "$REPO" && "$EVENTS" "$@") > "$OUT" 2> "$ERR"; RC=$?; }
show() { printf 'rc=%s out=[%s] err=[%s]' "$RC" "$(tr '\n' '|' < "$OUT")" "$(head -c 600 "$ERR" | tr '\n' '|')"; }
# batches: every recorded verdicts batch, one entry per line.
batches() { sed -n 's/^file://p' "$LOG" | jq -c '.[]'; }
seatdir() { # <fixture dir>: a fresh copy, since ingest would remove the real one
    rm -rf "$WORKDIR/v"
    mkdir -p "$WORKDIR/v"
    cp "$FIX/$1"/*.md "$WORKDIR/v/"
}
doc_for() {
    case "$1" in
        brief) echo docs/briefs/BRIEF-t.md ;;
        prd) echo docs/prds/PRD-t.md ;;
        design) echo docs/designs/DESIGN-t.md ;;
        plan) echo docs/plans/PLAN-t.md ;;
    esac
}
write_doc() { # <skill> <schema>
    local d
    d=$(doc_for "$1")
    mkdir -p "$REPO/$(dirname "$d")"
    printf -- '---\nschema: %s\nstatus: Draft\n---\n\n# Doc\n' "$2" > "$REPO/$d"
}

# --- R7: a well-formed block per jury -------------------------------------------

for skill in brief prd design plan; do
    dct_repo "$skill"
    dct_session "$skill-t"
    write_doc "$skill" "$skill/v1"
    doc=$(doc_for "$skill")
    seats=$(ls "$FIX/$skill" | wc -l | tr -d ' ')
    ev round-started --skill "$skill" --topic t --doc "$doc" --seat-count "$seats"
    seatdir "$skill"
    ev verdicts --skill "$skill" --topic t --doc "$doc" --dir "$WORKDIR/v"
    want=$(cat "$FIX/$skill"/*.md | awk '/^```review-verdicts/ { f = 1; next } /^```/ { f = 0 } f' \
        | jq -s -c 'add | map({rule_id, section, verdict}) | sort')
    got=$(batches | jq -s -c 'map({rule_id, section, verdict}) | sort')
    if [ "$RC" -eq 0 ] && [ "$got" = "$want" ] && [ ! -s "$ERR" ]; then
        pass "R7 $skill: one verdict per entry of every seat's block"
    else
        fail "R7 $skill: got=$got want=$want $(show)"
    fi
    calls=$(grep -c "^$skill-t verdicts --file " "$LOG")
    [ "$calls" -eq "$seats" ] && pass "R7 $skill: one verdicts call per seat" \
        || fail "R7 $skill: $calls verdicts calls for $seats seats"
    bad=$(batches | jq -c --arg s "$skill" --argjson round 1 \
        'select(.round != $round or .doc_type != $s or .schema != ($s + "/v1") or (.seat | type) != "string")')
    [ -z "$bad" ] && pass "R7 $skill: each entry carries its seat, round 1, doc type and schema" \
        || fail "R7 $skill: entries off [$bad]"
    unreg=$(batches | jq -r '.rule_id' | sort -u | while IFS= read -r id; do
        "$REPO_ROOT/scripts/rule-registry.sh" resolve "$id" >/dev/null 2>&1 || echo "$id"; done)
    [ -z "$unreg" ] && pass "R7 $skill: every recorded rule id resolves in the registry" \
        || fail "R7 $skill: unregistered [$unreg]"
done

# Seat names come from the seat list, matched to the pinned file names.
dct_repo seatnames
dct_session design-t
ev round-started --skill design --topic t --doc docs/designs/DESIGN-t.md --seat-count 3
seatdir design
ev verdicts --skill design --topic t --doc docs/designs/DESIGN-t.md --dir "$WORKDIR/v"
got=$(batches | jq -r '"\(.seat) \(.rule_id)"' | sort -u | tr '\n' ' ')
case "$got" in
    *"architecture rs-047 "*"security rs-051 "*"structural-format rs-055 "*) pass "R7: a seat's name follows its pinned file" ;;
    *) fail "R7: seat names [$got]" ;;
esac

# --- R7: what is dropped, remapped or replaced ------------------------------------

dct_repo bad
dct_session brief-t
write_doc brief brief/v1
ev round-started --skill brief --topic t --doc docs/briefs/BRIEF-t.md --seat-count 2
seatdir bad
ev verdicts --skill brief --topic t --doc docs/briefs/BRIEF-t.md --dir "$WORKDIR/v"
cq=$(batches | jq -c 'select(.seat == "content-quality") | [.rule_id, .section, .verdict]' | tr '\n' ' ')
want='["rs-021","problem-statement","PASS"] ["rs-024","document","FAIL"] '
[ "$cq" = "$want" ] && pass "R7: an unregistered id, a bad verdict, a non-string field and a non-object are dropped; an off-list section becomes document" \
    || fail "R7: content-quality entries [$cq] $(show)"
sf=$(batches | jq -c 'select(.seat == "structural-format") | [.rule_id, .section, .verdict]' | tr '\n' ' ')
[ "$sf" = '["rs-verdict-missing","document","FAIL"] ' ] && pass "R7: an unparseable block records one rs-verdict-missing FAIL" \
    || fail "R7: structural-format entries [$sf]"
for want in "entry 2: rule_id is not a registered rule" "entry 3: verdict is not PASS or FAIL" \
    "entry 4: section is not on the brief list" "entry 5: rule_id is not a registered rule" \
    "entry 6: section is missing or not a string" "entry 7: entry is missing or not a string" \
    "seat structural-format: the review-verdicts block is not a JSON array"; do
    grep -qF -- "$want" "$ERR" && pass "R7: stderr names [$want]" || fail "R7: stderr lacks [$want] $(show)"
done
if grep -qF "$LEAK" "$OUT" "$ERR" "$LOG"; then
    fail "R7: the seat's text reached the output or the record"
else
    pass "R7: no text a seat wrote is echoed or recorded"
fi

# A seat with no file, or a file with no block, records the one FAIL.
dct_repo missing
dct_session prd-t
ev round-started --skill prd --topic t --doc docs/prds/PRD-t.md --seat-count 3
rm -rf "$WORKDIR/v"; mkdir -p "$WORKDIR/v"
printf '# Clarity Review\n\n## Verdict: PASS\nno block here\n' > "$WORKDIR/v/phase4_clarity.md"
ev verdicts --skill prd --topic t --doc docs/prds/PRD-t.md --dir "$WORKDIR/v"
got=$(batches | jq -r '"\(.seat) \(.rule_id) \(.verdict)"' | sort | tr '\n' '|')
[ "$got" = "clarity rs-verdict-missing FAIL|completeness rs-verdict-missing FAIL|testability rs-verdict-missing FAIL|" ] \
    && pass "R7: a seat with no file or no block records rs-verdict-missing" || fail "R7: missing seats [$got] $(show)"
grep -q '"schema"' "$LOG" && fail "R7: a document with no schema recorded one" \
    || pass "R7: a missing document records no schema"

# More than 200 valid entries: the first 200 are recorded.
dct_repo cap
dct_session plan-t
ev round-started --skill plan --topic t --doc docs/plans/PLAN-t.md --seat-count 5
rm -rf "$WORKDIR/v"; mkdir -p "$WORKDIR/v"
{ echo '```review-verdicts'; jq -n -c '[range(0; 205) | {rule_id: "rs-059", section: "document", verdict: "PASS"}]'; echo '```'; } \
    > "$WORKDIR/v/category-a.md"
ev verdicts --skill plan --topic t --doc docs/plans/PLAN-t.md --dir "$WORKDIR/v"
n=$(batches | jq -c 'select(.seat == "scope-gate")' | wc -l | tr -d ' ')
[ "$n" -eq 200 ] && grep -q 'only the first 200' "$ERR" && pass "R7: a seat's batch stops at 200 entries" \
    || fail "R7: cap n=$n $(show)"

# --- R8: rounds ------------------------------------------------------------------

dct_repo rounds
dct_session design-t
write_doc design design/v1
ev round-started --skill design --topic t --doc docs/designs/DESIGN-t.md --seat-count 3
ev round-started --skill design --topic t --doc docs/designs/DESIGN-t.md --seat-count 3 --fallback
got=$(grep ' round-started ' "$LOG" | sed 's/.*--round \([0-9]*\).*/\1/' | tr '\n' ' ')
[ "$got" = "1 2 " ] && pass "R8: two rounds record rounds 1 and 2" || fail "R8: rounds [$got]"
[ "$(dct_key design-t review/round | tr -d '[:space:]')" = 2 ] && pass "R8: review/round holds 2" \
    || fail "R8: review/round [$(dct_key design-t review/round)]"
first=$(grep -c -- '--seat-count 3 --fallback$' "$LOG")
[ "$first" -eq 1 ] && grep -q -- '--doc-type design --schema design/v1 --round 1 --seat-count 3$' "$LOG" \
    && pass "R8: round-started carries doc type, schema, seat count and the fallback flag" || fail "R8: [$(cat "$LOG")]"
seatdir design
ev verdicts --skill design --topic t --doc docs/designs/DESIGN-t.md --dir "$WORKDIR/v"
order=$(awk '/ round-started / { print "r" } / verdicts / { print "v" }' "$LOG" | tr -d '\n')
[ "$order" = rrvvv ] && pass "R8: round-started is recorded before the round's verdicts" || fail "R8: order [$order]"
[ "$(batches | jq -r '.round' | sort -u)" = 2 ] && pass "R8: verdicts carry the current round" \
    || fail "R8: verdict rounds [$(batches | jq -r '.round' | sort -u | tr '\n' ' ')]"

# Each jury reference records the round before it spawns a seat, and the
# verdicts before ingest removes the directory.
order_in() { # <file> <earlier pattern> <later pattern>
    local a b
    a=$(grep -nF -- "$2" "$REPO_ROOT/$1" | head -n 1 | cut -d: -f1)
    b=$(grep -nF -- "$3" "$REPO_ROOT/$1" | head -n 1 | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
check_ref() { # <file> <skill> <spawn line>
    if order_in "$1" "review-events.sh\" round-started --skill $2 " "$3"; then
        pass "R8: $1 records round-started before the seats are spawned"
    else
        fail "R8: $1 has no round-started before [$3]"
    fi
}
check_ref skills/brief/references/phases/phase-4-validate.md brief "Spawn both agents in parallel"
check_ref skills/prd/references/phases/phase-4-validate.md prd "Launch all 3 agents in parallel"
check_ref skills/design/references/phases/phase-6-final-review.md design "Launch three review agents in parallel"
for f in skills/brief/references/phases/phase-4-validate.md skills/prd/references/phases/phase-4-validate.md \
    skills/design/references/phases/phase-6-final-review.md; do
    order_in "$f" 'review-events.sh" verdicts ' 'skill-session.sh" ingest ' \
        && pass "verdicts are recorded before ingest in $f" || fail "no verdicts call before ingest in $f"
done
grep -qF 'review-events.sh" round-started --skill plan ' "$REPO_ROOT/skills/review-plan/references/phases/phase-0-setup.md" \
    && pass "R8: /review-plan records round-started in Phase 0, before any category runs" \
    || fail "R8: phase-0-setup.md has no round-started"

# --- R9: decisions -----------------------------------------------------------------

dct_repo decisions
dct_session prd-t
ev decision --skill prd --topic t --doc docs/prds/PRD-t.md --decision proceed
[ "$RC" -eq 0 ] && [ ! -s "$LOG" ] && grep -q 'no round-started' "$ERR" \
    && pass "R9: a decision with no round recorded records nothing" || fail "R9: no round $(show)"
ev round-started --skill prd --topic t --doc docs/prds/PRD-t.md --seat-count 3
for d in rerun fix_and_proceed loop_back proceed stop; do
    ev decision --skill prd --topic t --doc docs/prds/PRD-t.md --decision "$d"
    grep -q -- "^prd-t decision --doc-type prd --schema  --round 1 --decision $d\$" "$LOG" \
        && pass "R9: decision $d reaches koto with round 1" || fail "R9: $d [$(tail -n 1 "$LOG")]"
done
ev decision --skill prd --topic t --doc docs/prds/PRD-t.md --decision maybe
[ "$RC" -eq 2 ] && pass "R9: a decision outside the five is refused" || fail "R9: maybe $(show)"

# --- session routing ---------------------------------------------------------------

dct_repo routing
dct_session brief-t
dct_session scope-t
printf 'main' | dct_put scope-t session/branch
printf 'child: brief\nsuppress_status_aware_prompt: false\nrationale: fresh-chain\n' | dct_put scope-t chain/dispatch
ev round-started --skill brief --topic t --doc docs/briefs/BRIEF-t.md --seat-count 2
grep -q '^scope-t round-started ' "$LOG" && pass "a jury dispatched by /scope records on the scope session" \
    || fail "routing: [$(cat "$LOG")]"
[ "$(dct_key brief-t review/round | tr -d '[:space:]')" = 1 ] && pass "the round counter stays in the skill's own session" \
    || fail "routing: counter [$(dct_key brief-t review/round)]"

# --- best effort -------------------------------------------------------------------

for mode in missing refuse; do
    dct_repo "koto-$mode"
    dct_session brief-t
    printf '1\n' | dct_put brief-t review/round
    seatdir brief
    export STUB_KOTO_REVIEW=$mode
    ev round-started --skill brief --topic t --doc docs/briefs/BRIEF-t.md --seat-count 2
    rc1=$RC; n1=$(grep -c 'notice: telemetry for round' "$ERR")
    ev verdicts --skill brief --topic t --doc docs/briefs/BRIEF-t.md --dir "$WORKDIR/v"
    rc2=$RC; n2=$(grep -c "notice: telemetry for seat" "$ERR")
    ev decision --skill brief --topic t --doc docs/briefs/BRIEF-t.md --decision proceed
    rc3=$RC; n3=$(grep -c 'notice: telemetry for the round' "$ERR")
    unset STUB_KOTO_REVIEW
    if [ "$rc1$rc2$rc3" = 000 ] && [ "$n1" -eq 1 ] && [ "$n2" -eq 2 ] && [ "$n3" -eq 1 ]; then
        pass "a stub koto in mode $mode leaves every call exiting 0 with one stderr line each"
    else
        fail "best effort $mode: rc=$rc1$rc2$rc3 notices=$n1/$n2/$n3"
    fi
done

ev verdicts --skill vision --topic t --doc x --dir "$WORKDIR"
[ "$RC" -eq 2 ] && pass "a skill outside the four is refused" || fail "skill $(show)"
ev round-started --skill brief --topic t --doc x --seat-count 0
[ "$RC" -eq 2 ] && pass "a seat count of 0 is refused" || fail "seat count $(show)"

# --- template vocabulary -----------------------------------------------------------

seats_listed=$(sed -n '/^seats_of() {/,/^}/p' "$EVENTS" | grep -o '[a-z-]* phase[0-9]_[a-z-]*\.md\|[a-z-]* category-[a-e]\.md' | awk '{ print $1 }' | sort -u)
slugs=$(jq -r '.formats | (.brief, .prd, .design, .plan) | .required_sections[]' "$REPO_ROOT/references/doc-check-phases.json" \
    | while IFS= read -r s; do printf '%s' "$s" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//'; echo; done; printf 'frontmatter\ndocument\n')
for t in skills/scope/koto-templates/scope.md koto-templates/skill-session.md; do
    vocab=$(awk '/^review_vocabulary:/ { f = 1; next } f && /^[a-z_]+:/ { exit } f' "$REPO_ROOT/$t" | tr -d '[],' | tr ' ' '\n')
    missing=""
    for v in $seats_listed $slugs; do
        printf '%s\n' "$vocab" | grep -qxF -- "$v" || missing="$missing $v"
    done
    [ -z "$missing" ] && pass "$t declares every seat and section slug review-events.sh records" \
        || fail "$t lacks [$missing]"
done

# --- contract: a recorded batch against a real koto --------------------------------

if [ -n "$REAL_KOTO" ] && "$REAL_KOTO" review record --help >/dev/null 2>&1; then
    dct_repo contract
    dct_session brief-t
    write_doc brief brief/v1
    ev round-started --skill brief --topic t --doc docs/briefs/BRIEF-t.md --seat-count 2
    seatdir brief
    ev verdicts --skill brief --topic t --doc docs/briefs/BRIEF-t.md --dir "$WORKDIR/v"
    sed -n 's/^file://p' "$LOG" | head -n 1 > "$WORKDIR/batch.json"
    KS="$WORKDIR/ksess"
    mkdir -p "$KS"
    if (cd "$REPO" && KOTO_SESSIONS_BASE="$KS" "$REAL_KOTO" init brief-t --template "$REPO_ROOT/koto-templates/skill-session.md") >/dev/null 2>&1 \
        && (cd "$REPO" && KOTO_SESSIONS_BASE="$KS" "$REAL_KOTO" review record brief-t verdicts --file "$WORKDIR/batch.json") > "$WORKDIR/k.out" 2>&1; then
        n=$(jq -r '.count // empty' "$WORKDIR/k.out" 2>/dev/null)
        want=$(jq 'length' "$WORKDIR/batch.json")
        [ "$n" = "$want" ] && pass "contract: koto review record accepts a batch review-events.sh wrote ($n entries)" \
            || fail "contract: koto answered [$(head -c 300 "$WORKDIR/k.out")]"
    else
        fail "contract: koto refused the batch [$(head -c 300 "$WORKDIR/k.out" 2>/dev/null)]"
    fi
else
    # The documented entry shape, when no koto with the verb is at hand.
    dct_repo contract-shape
    dct_session brief-t
    write_doc brief brief/v1
    ev round-started --skill brief --topic t --doc docs/briefs/BRIEF-t.md --seat-count 2
    seatdir brief
    ev verdicts --skill brief --topic t --doc docs/briefs/BRIEF-t.md --dir "$WORKDIR/v"
    bad=$(batches | jq -c 'select((keys - ["doc_type","round","rule_id","schema","seat","section","verdict"]) != []
        or (.verdict | IN("PASS","FAIL") | not) or (.round | type) != "number" or .round < 1
        or (.doc_type | IN("brief","prd","design","plan") | not))')
    [ -z "$bad" ] && pass "contract: every entry has koto's documented verdicts shape (no koto with the verb on PATH)" \
        || fail "contract: [$bad]"
fi

echo
echo "review-events_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
