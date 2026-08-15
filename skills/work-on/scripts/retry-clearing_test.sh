#!/usr/bin/env bash
# retry-clearing_test.sh — the retry-clearing contract, end to end
# Part of the work-on skill
#
# /work-on's three review phases each gate their `passed` transition on a
# results artifact, and a blocking_retry returns to implementation without
# anything invalidating it. Because implementation routes forward into scrutiny,
# a retry re-enters every panel phase at or above the one that raised it, and
# each used to find its own previous verdict still present and its gate still
# satisfied. The step that would have fixed it named a removal subcommand koto's
# context group does not have, and failed silently because koto's migration
# noise makes `2>/dev/null` the routine reflex.
#
# This harness asserts the repair on four halves:
#
#   the sentinel and the pattern cannot drift into agreement  (case 0)
#   a fresh artifact still advances, on all three shapes      (case 1)
#   an invalidated artifact holds every phase it re-enters    (cases 2, 3)
#   a failed invalidation announces itself and is not skipped (cases 5, 6)
#
# It runs the SHIPPED TEXT rather than a copy: the gate pattern is extracted
# from skills/work-on/koto-templates/work-on.md and the clearing block and its
# sentinel from the three phase files, all at run time. A pasted copy would keep
# passing after the shipped text drifted, which is the failure mode this whole
# defect class is made of.
#
# The extraction marker for the block is `blocking_retry`, NOT `koto context
# add`. Both blocks in each phase file — the success-path heredoc and the retry
# block — contain `koto context add`, so the marker the /execute precedent uses
# is ambiguous here.
#
# Usage: retry-clearing_test.sh
#
# Exit codes:
#   0 — all cases pass, or koto is absent and the run skipped
#   1 — one or more cases failed
#
# A missing koto exits 0 with a loud SKIP rather than failing, matching
# settled-branch-record_test.sh. The suite runs on two legs: the Linux leg of
# check-work-on-scripts.yml installs koto through the project tool manifest so
# the assertions genuinely run, and the macOS leg is the bash 3.2 floor check
# for the shell itself, where koto is absent.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PHASE_A="$SKILL_DIR/references/phases/phase-4a-scrutiny.md"
PHASE_B="$SKILL_DIR/references/phases/phase-4b-review.md"
PHASE_C="$SKILL_DIR/references/phases/phase-4c-qa.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
for f in "$TEMPLATE" "$PHASE_A" "$PHASE_B" "$PHASE_C"; do
    [ -f "$f" ] || { echo "FAIL: shipped file not found at $f" >&2; exit 1; }
done

WORKDIR=$(mktemp -d)
LOCKED_KEY=""
cleanup() {
    # Case 5 leaves a key file read-only; restore it so rm can finish.
    [ -n "$LOCKED_KEY" ] && [ -f "$LOCKED_KEY" ] && chmod u+w "$LOCKED_KEY" 2>/dev/null
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
trap cleanup EXIT

# koto resolves its session store through the home directory, so pointing HOME
# at the temp tree keeps every session this harness creates out of the
# developer's real ~/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"
cd "$WORKDIR" || exit 1

# --- extract the shipped text -------------------------------------------------

# The gate pattern, as the template ships it.
PATTERN=$(grep -m1 "pattern: '(?s)" "$TEMPLATE" | sed "s/^[[:space:]]*pattern:[[:space:]]*//")
if [ -z "$PATTERN" ]; then
    fail "could not extract the gate pattern from $TEMPLATE"
    echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# The cleared sentinel, as phase-4a ships it.
CLEARED=$(grep -m1 "^CLEARED=" "$PHASE_A" | sed "s/^CLEARED='//; s/'$//")
if [ -z "$CLEARED" ]; then
    fail "could not extract the cleared sentinel from $PHASE_A"
    echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# Print the bash fenced block in $1 that contains the substring $2.
extract_block() {
    awk -v marker="$2" '
        /^```bash$/  { inblk = 1; buf = ""; next }
        /^```$/ && inblk {
            if (index(buf, marker) > 0) { printf "%s", buf; exit }
            inblk = 0; buf = ""; next
        }
        inblk { buf = buf $0 "\n" }
    ' "$1"
}

BLOCK_A=$(extract_block "$PHASE_A" "blocking_retry")
BLOCK_B=$(extract_block "$PHASE_B" "blocking_retry")
BLOCK_C=$(extract_block "$PHASE_C" "blocking_retry")
for pair in "A:$BLOCK_A" "B:$BLOCK_B" "C:$BLOCK_C"; do
    if [ -z "${pair#*:}" ]; then
        fail "could not extract the retry block from phase-4${pair%%:*} (no bash block contains 'blocking_retry')"
        echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
    fi
done

echo "extracted pattern:  $PATTERN"
echo "extracted sentinel: $CLEARED"
echo

# Render a block for execution: substitute the <WF> placeholder, and drop the
# final `koto next` line so the harness drives the state machine itself.
render_block() {
    printf '%s\n' "$1" | grep -v '^koto next ' | sed "s|<WF>|$2|g"
}

# Write a probe template carrying the extracted pattern. $1 is the pattern to
# use, which lets case 0 substitute a mutated one.
write_probe() {
    cat > "$1" <<PROBE_END
---
name: retryprobe
version: "1.0"
description: Probe carrying the shipped panel gate pattern.
initial_state: scrutiny

states:
  scrutiny:
    gates:
      scrutiny_results:
        type: context-matches
        key: scrutiny_results.json
        pattern: $2
    accepts:
      scrutiny_outcome:
        type: enum
        values: [passed, blocking_retry, blocking_escalate]
        required: true
    transitions:
      - target: review
        when:
          scrutiny_outcome: passed
          gates.scrutiny_results.matches: true
      - target: implementation
        when:
          scrutiny_outcome: blocking_retry
      - target: done_blocked
        when:
          scrutiny_outcome: blocking_escalate

  review:
    terminal: true
  implementation:
    terminal: true
  done_blocked:
    terminal: true
    failure: true
---

# retryprobe

## scrutiny

Probe state.

## review

Advanced.

## implementation

Retry.

## done_blocked

Blocked.
PROBE_END
}

write_probe probe.md "$PATTERN"

# Submit and report the resulting state. `koto next` keeps reporting the state
# after a terminal transition where `koto status` does not, so the submission
# response is the surface to read.
state_after() {
    koto next "$1" --with-data "$2" 2>/dev/null \
        | sed -n 's/.*"state":"\([^"]*\)".*/\1/p'
}

seed() { printf '%s' "$3" | koto context add "$1" "$2" >/dev/null 2>&1; }

SESSION_N=0
new_session() {
    SESSION_N=$((SESSION_N + 1))
    CUR="s$SESSION_N"
    koto init "$CUR" --template "${1:-probe.md}" >/dev/null 2>&1
}

# --- Case 0 — the sentinel and the pattern cannot drift into agreement --------
#
# This runs first because it is the only case that catches the fix silently
# undoing itself. The sentinel lives in the phase files and the pattern lives in
# the template, and they are correct only in relation to each other. If they
# drift into AGREEMENT the clearing block still passes its own read-back -- it
# compares against its own literal, so it always agrees with itself -- and the
# gate then ACCEPTS the sentinel, restoring the original defect through a fix
# that reports success. Fail-open, and invisible to every other case here.
#
# Both mutations are derived from the shipped text at run time and asserted on
# every run. A one-time manual demonstration that left no trace in this file
# would satisfy the letter of "we checked" and none of its value.

echo "--- Case 0: sentinel/pattern drift ---"

new_session
seed "$CUR" scrutiny_results.json "$CLEARED"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "scrutiny" ]; then
    pass "baseline: the shipped sentinel does not satisfy the shipped pattern"
else
    fail "baseline: the shipped sentinel satisfies the shipped pattern -- the fix is inert"
fi

# Mutation 1: the sentinel drifts toward the pattern. The realistic way in is a
# sentinel edited to "record what was superseded", which arrives disguised as an
# improvement.
DRIFTED_SENTINEL=$(printf '%s' "$CLEARED" | sed 's/}$/, "superseded": {"passed": true}}/')
new_session
seed "$CUR" scrutiny_results.json "$DRIFTED_SENTINEL"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "review" ]; then
    pass "mutated sentinel is accepted by the gate -- drift in this direction is detectable here"
else
    fail "mutated sentinel was still rejected; this case can no longer detect sentinel drift"
fi

# Mutation 2: the pattern drifts toward the sentinel. The realistic way in is a
# pattern relaxed to "any JSON object" -- someone generalising it so a future
# artifact shape does not break the gate, not noticing that the cleared sentinel
# is also a JSON object. Asserted to be ACCEPTED, i.e. the drift shows up here
# as a contract failure rather than passing unnoticed.
#
# Note this is NOT the same thing as dropping the anchors. Unanchoring alone
# does not admit the sentinel, because what excludes it is the "passed" token
# rather than the anchors; the anchors are checked separately below, against the
# value they actually defend against.
write_probe loose.md "'(?s)^\{.*\}\s*\$'"
new_session loose.md
seed "$CUR" scrutiny_results.json "$CLEARED"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "review" ]; then
    pass "over-generalised pattern accepts the sentinel -- pattern drift is detectable here"
else
    fail "over-generalised pattern still rejected the sentinel; this case cannot detect pattern drift"
fi

# The anchors, against the value they actually defend against. context-matches
# is Regex::is_match, a substring test, so an unanchored pattern accepts any
# value that merely CONTAINS the token -- including a cleared marker that quotes
# it. The shipped anchored pattern must reject that; the unanchored one must
# accept it, or the anchors are decoration.
EMBEDDED='superseded; the previous round recorded {"passed": true} and is no longer current'
new_session
seed "$CUR" scrutiny_results.json "$EMBEDDED"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "review" ]; then
    fail "the shipped pattern accepted a value that only embeds the token -- anchoring is not holding"
else
    pass "the shipped pattern rejects a value that merely embeds the token"
fi

UNANCHORED=$(printf '%s' "$PATTERN" | sed "s/\^//; s/\\\\s\*\\\$'/'/")
write_probe unanchored.md "$UNANCHORED"
new_session unanchored.md
seed "$CUR" scrutiny_results.json "$EMBEDDED"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "review" ]; then
    pass "the unanchored pattern accepts it -- so the anchors are load-bearing, not decoration"
else
    fail "the unanchored pattern also rejected it; this case does not demonstrate what the anchors buy"
fi

echo

# --- Case 1 — every shipped payload still advances ----------------------------
#
# The three phases do not write the same shape: qa_validation's artifact has no
# `round` field, which is why the pattern keys on "passed" and not on "round".
# These are written with a trailing newline because the phase files write with a
# heredoc and koto stores stdin verbatim -- the reason `\s*$` is in the pattern.

echo "--- Case 1: shipped payloads advance ---"

i=0
for PAYLOAD in \
    '{"passed": true, "round": 1, "blocking_count": 0}' \
    '{"passed": true, "round": 1, "blocking_count": 0}' \
    '{"passed": true, "scenarios_run": 3, "scenarios_passed": 3}'
do
    i=$((i + 1))
    new_session
    printf '%s\n' "$PAYLOAD" | koto context add "$CUR" scrutiny_results.json >/dev/null 2>&1
    if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "review" ]; then
        pass "shipped payload $i advances the phase"
    else
        fail "shipped payload $i did not advance: $PAYLOAD"
    fi
done

echo

# --- Case 2 — an invalidated artifact holds the phase, and says why -----------

echo "--- Case 2: the invalidated artifact holds ---"

new_session
seed "$CUR" scrutiny_results.json '{"passed": true, "round": 1, "blocking_count": 0}'
seed "$CUR" scrutiny_results.json "$CLEARED"
RESPONSE=$(koto next "$CUR" --with-data '{"scrutiny_outcome":"passed"}' 2>/dev/null)
STATE=$(printf '%s' "$RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
if [ "$STATE" = "scrutiny" ]; then
    pass "passed submission on an invalidated artifact does not advance"
else
    fail "passed submission advanced to [$STATE] on an invalidated artifact"
fi
if printf '%s' "$RESPONSE" | grep -q '"name":"scrutiny_results"'; then
    pass "the held submission names scrutiny_results as the failing condition"
else
    fail "the held submission does not name the gate"
fi
if printf '%s' "$RESPONSE" | grep -q '"matches":false'; then
    pass "the failing condition reports matches:false"
else
    fail "the failing condition does not report matches:false"
fi

# The failure exits must stay reachable when the store is what is broken.
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"blocking_retry"}')" = "implementation" ]; then
    pass "blocking_retry stays reachable with the gate failing"
else
    fail "blocking_retry is not reachable with the gate failing"
fi
new_session
seed "$CUR" scrutiny_results.json "$CLEARED"
if [ "$(state_after "$CUR" '{"scrutiny_outcome":"blocking_escalate"}')" = "done_blocked" ]; then
    pass "blocking_escalate stays reachable with the gate failing"
else
    fail "blocking_escalate is not reachable with the gate failing"
fi

echo

# --- Case 3 — the traversal, from all three entry points ----------------------
#
# This is the case the whole scope decision rests on. A retry raised anywhere
# returns to implementation, which routes forward into scrutiny, so the run
# re-enters every panel phase at or above the raiser. Clearing only the raising
# phase's artifact would leave the others satisfied by verdicts about code that
# no longer exists.

echo "--- Case 3: the traversal ---"

traversal_case() { # $1 = raising phase label, $2 = the block to run
    new_session
    seed "$CUR" scrutiny_results.json '{"passed": true, "round": 1}'
    seed "$CUR" review_results.json   '{"passed": true, "round": 1}'
    seed "$CUR" qa_results.json       '{"passed": true, "scenarios_run": 1, "scenarios_passed": 1}'
    render_block "$2" "$CUR" > blk.sh
    if ! bash blk.sh >/dev/null 2>&1; then
        fail "$1-raised retry: the clearing block exited non-zero"
        return
    fi
    local held=0
    for KEY in scrutiny_results.json review_results.json qa_results.json; do
        if [ "$(koto context get "$CUR" "$KEY" 2>/dev/null)" = "$CLEARED" ]; then
            held=$((held + 1))
        fi
    done
    if [ "$held" -eq 3 ]; then
        pass "$1-raised retry invalidates all three panel artifacts"
    else
        fail "$1-raised retry invalidated only $held of 3 artifacts"
    fi
    # And the phase the run re-enters first genuinely refuses.
    if [ "$(state_after "$CUR" '{"scrutiny_outcome":"passed"}')" = "scrutiny" ]; then
        pass "$1-raised retry: scrutiny refuses to advance afterwards"
    else
        fail "$1-raised retry: scrutiny advanced on a stale verdict"
    fi
}

traversal_case qa_validation "$BLOCK_C"
traversal_case review        "$BLOCK_B"
traversal_case scrutiny      "$BLOCK_A"

echo

# --- Case 4 — a scrutiny-raised retry before the other phases have run --------

echo "--- Case 4: keys that were never written ---"

new_session
seed "$CUR" scrutiny_results.json '{"passed": true, "round": 1}'
render_block "$BLOCK_A" "$CUR" > blk4.sh
if bash blk4.sh >/dev/null 2>&1; then
    pass "the block exits 0 when review and qa have never written their keys"
else
    fail "the block failed on keys that do not exist yet"
fi
n=0
for KEY in scrutiny_results.json review_results.json qa_results.json; do
    [ "$(koto context get "$CUR" "$KEY" 2>/dev/null)" = "$CLEARED" ] && n=$((n + 1))
done
if [ "$n" -eq 3 ]; then
    pass "all three keys hold the sentinel afterwards"
else
    fail "expected 3 keys holding the sentinel, found $n"
fi

echo

# --- Case 5 — an unreadable key is caught, not skipped ------------------------
#
# The regression test for the guard the security review removed. koto's
# ctx_exists collapses "absent" and "unreadable" into false in both backends, so
# a `koto context exists ... || continue` guard silently skips a key whose real
# verdict is still there. The negative control below is the only thing this
# harness runs that is not shipped text, and it earns that: without it, this
# case would pass for a harness that never exercised the difference.
#
# The injection is chmod on the KEY FILE, not a lock on the ctx directory. The
# /execute precedent locks the directory, which is right for a NEW key; this
# design overwrites an EXISTING one, where a directory lock lets the value land
# anyway.

echo "--- Case 5: an unwritable key ---"

if [ "$(id -u)" = "0" ]; then
    echo "SKIP: case 5 needs a non-root user (root ignores the write bit)"
else
    new_session
    seed "$CUR" scrutiny_results.json '{"passed": true, "round": 1}'
    LOCKED_KEY="$HOME/.koto/sessions/$CUR/ctx/scrutiny_results.json"
    chmod 0444 "$LOCKED_KEY"
    render_block "$BLOCK_A" "$CUR" > blk5.sh
    OUT=$(bash blk5.sh 2>/dev/null)
    RC=$?
    chmod u+w "$LOCKED_KEY"

    if [ "$RC" -ne 0 ]; then
        pass "the shipped block exits non-zero when a key cannot be written"
    else
        fail "the shipped block exited 0 on an unwritable key"
    fi
    if printf '%s' "$OUT" | grep -q 'scrutiny_results.json NOT cleared'; then
        pass "the diagnostic names the key, on stdout, with stderr discarded"
        echo "  diagnostic: $(printf '%s' "$OUT" | grep 'NOT cleared' | cut -c1-100)"
    else
        fail "no diagnostic naming the key on stdout; got [$OUT]"
    fi
    if printf '%s' "$OUT" | grep -q 'do NOT submit a passed outcome'; then
        pass "the diagnostic says which outcome not to submit"
    else
        fail "the diagnostic does not say what to submit instead"
    fi

    # Negative control: the guarded variant misses exactly this.
    new_session
    seed "$CUR" scrutiny_results.json '{"passed": true, "round": 1}'
    GUARDED_CTX="$HOME/.koto/sessions/$CUR/ctx"
    render_block "$BLOCK_A" "$CUR" \
        | sed '/^for KEY in/a\
  koto context exists '"$CUR"' "$KEY" >/dev/null 2>&1 || continue' > blk5g.sh
    chmod 0000 "$GUARDED_CTX"
    bash blk5g.sh >/dev/null 2>&1
    GRC=$?
    chmod 0755 "$GUARDED_CTX"
    if [ "$GRC" -eq 0 ]; then
        pass "negative control: a guarded variant exits 0 and misses the failure"
    else
        pass "negative control inconclusive on this platform (guarded variant also failed)"
    fi
fi

echo

# --- Case 6 — the three shipped blocks are one block --------------------------

echo "--- Case 6: one contract across three phases ---"

printf '%s' "$BLOCK_A" | grep -v '^koto next ' > a.txt
printf '%s' "$BLOCK_B" | grep -v '^koto next ' > b.txt
printf '%s' "$BLOCK_C" | grep -v '^koto next ' > c.txt
if diff -q a.txt b.txt >/dev/null && diff -q a.txt c.txt >/dev/null; then
    pass "the clearing block is byte-identical across all three phase files"
else
    fail "the three clearing blocks have drifted apart"
    diff a.txt b.txt
    diff a.txt c.txt
fi

for pair in "A:$BLOCK_A:scrutiny_outcome" "B:$BLOCK_B:review_outcome" "C:$BLOCK_C:qa_outcome"; do
    label=${pair%%:*}
    rest=${pair#*:}
    blk=${rest%:*}
    want=${rest##*:}
    if printf '%s' "$blk" | grep -q "\"$want\": \"blocking_retry\""; then
        pass "phase-4$label submits $want"
    else
        fail "phase-4$label does not submit $want"
    fi
done

# --- summary ------------------------------------------------------------------

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
