#!/usr/bin/env bash
# rule-dispute_test.sh -- test harness for scripts/rule-dispute.sh.
#
# Usage: bash scripts/rule-dispute_test.sh
#
# No case touches a real koto. Each runs with a stub `koto` first on PATH,
# written into this suite's scratch directory: one that answers
# `koto disputes --help` (a koto with `koto disputes record`) and one that
# refuses it as an unknown subcommand, as koto 0.20.0 does. Both log the
# arguments of a record call, NUL-separated, so a case can compare the words
# koto received byte for byte, and both exit with $STUB_RC on it. The second
# also answers what scripts/run-trail.sh asks on the fallback: `context list`
# with an empty list, and `context add` by keeping the key and its stdin in
# $STUB_TRAIL, so a case can read the trail record the fallback wrote.
#
# The rule ids come from the repository's registry: the first active
# script-checked entry and the first retired one, so the cases don't pin ids a
# registry change could rename.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DISPUTE="$SCRIPT_DIR/rule-dispute.sh"
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/rule-dispute-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

ACTIVE=$(jq -r '[.rules[] | select(.status == "active" and .check.kind == "script")][0].id // empty' "$REPO/references/rule-registry.json")
RETIRED=$(jq -r '[.rules[] | select(.status == "retired")][0].id // empty' "$REPO/references/rule-registry.json")
if [ -n "$ACTIVE" ] && [ -n "$RETIRED" ]; then
    pass "the registry has an active ($ACTIVE) and a retired ($RETIRED) entry to test with"
else
    fail "could not read an active and a retired id from the registry: [$ACTIVE] [$RETIRED]"
fi

# Two stub koto binaries, each in its own directory so PATH picks one.
mkdir -p "$T/with" "$T/without"
LOG="$T/argv"
cat >"$T/with/koto" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = disputes ] && [ "${2:-}" = --help ]; then
    echo "Record a dispute of a rule's finding"
    exit 0
fi
for a in "$@"; do printf '%s\0' "$a"; done >>"$STUB_LOG"
echo '{"status":"recorded"}'
exit "${STUB_RC:-0}"
EOF
cat >"$T/without/koto" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = disputes ]; then
    echo "error: unrecognized subcommand 'disputes'" >&2
    exit 2
fi
case "${1:-} ${2:-}" in
    "context list") echo '[]'; exit 0 ;;
    "context add") { printf '%s\n' "${4:-}"; cat; } >>"$STUB_TRAIL"; exit 0 ;;
esac
for a in "$@"; do printf '%s\0' "$a"; done >>"$STUB_LOG"
echo '{"status":"recorded"}'
exit "${STUB_RC:-0}"
EOF
chmod +x "$T/with/koto" "$T/without/koto"
TRAIL_LOG="$T/trail"

RC=0
OUT=""
ERR=""
# run <with|without> <rc> <args...> -- run the script against a stub koto that
# exits <rc> on a record call; OUT is stdout, ERR stderr, the log is fresh.
run() {
    local kind=$1 rc=$2
    shift 2
    rm -f "$LOG" "$TRAIL_LOG"
    RC=0
    OUT=$(PATH="$T/$kind:$PATH" STUB_LOG="$LOG" STUB_TRAIL="$TRAIL_LOG" STUB_RC="$rc" "$BASH_BIN" "$DISPUTE" "$@" 2>"$T/stderr") || RC=$?
    ERR=$(cat "$T/stderr")
}

expect_rc() { # expect_rc <rc> <label>
    if [ "$RC" -eq "$1" ]; then pass "$2"; else fail "$2 (rc=$RC, out=[$OUT], err=[$ERR])"; fi
}

expect_no_call() { # expect_no_call <label>
    if [ ! -e "$LOG" ]; then pass "$1: koto records nothing"; else fail "$1: koto was called"; fi
}

# expect_argv <label> <word>... -- the logged argv equals the words exactly.
expect_argv() {
    local label=$1
    shift
    printf '%s\0' "$@" >"$T/want"
    if [ -e "$LOG" ] && cmp -s "$T/want" "$LOG"; then
        pass "$label"
    else
        fail "$label: got [$(tr '\0' '|' <"$LOG" 2>/dev/null)] want [$(tr '\0' '|' <"$T/want")]"
    fi
}

# logged_data -- the --with-data value from a logged decisions record call.
logged_data() {
    local prev="" a
    while IFS= read -r -d '' a; do
        if [ "$prev" = --with-data ]; then printf '%s' "$a"; return 0; fi
        prev=$a
    done <"$LOG"
    return 1
}

# ---------------------------------------------------------------------------
# Refusals: exit 2 and no koto call, on either koto.

for kind in with without; do
    run "$kind" 0 --gate g --rule "$ACTIVE" --reason r
    expect_rc 2 "($kind) a missing --session exits 2"; expect_no_call "($kind) missing --session"
    run "$kind" 0 --session s --rule "$ACTIVE" --reason r
    expect_rc 2 "($kind) a missing --gate exits 2"; expect_no_call "($kind) missing --gate"
    run "$kind" 0 --session s --gate g --reason r
    expect_rc 2 "($kind) a missing --rule exits 2"; expect_no_call "($kind) missing --rule"
    run "$kind" 0 --session s --gate g --rule "$ACTIVE"
    expect_rc 2 "($kind) a missing --reason exits 2"; expect_no_call "($kind) missing --reason"
done

run with 0 --session s --gate g --rule "$ACTIVE" --reason ""
expect_rc 2 "an empty --reason exits 2"; expect_no_call "empty --reason"
run with 0 --session s --gate g --rule "$ACTIVE" --reason
expect_rc 2 "--reason with no value exits 2"; expect_no_call "--reason with no value"
run with 0 --session s --gate g --rule "$ACTIVE" --reason r --by robot
expect_rc 2 "--by robot exits 2"; expect_no_call "--by robot"
run with 0 --session s --gate g --rule "$ACTIVE" --reason r --by ""
expect_rc 2 "an empty --by exits 2"; expect_no_call "empty --by"
run without 0 --session s --gate g --rule "$ACTIVE" --reason r --by Agent
expect_rc 2 "--by is case-sensitive (Agent exits 2)"; expect_no_call "--by Agent"
run with 0 --session s --gate g --rule "$ACTIVE" --reason r --state ""
expect_rc 2 "an empty --state exits 2"; expect_no_call "empty --state"
run with 0 --session s --gate g --rule "$ACTIVE" --reason r --verbose
expect_rc 2 "an unknown argument exits 2"; expect_no_call "unknown argument"
run with 0 --session -x --gate g --rule "$ACTIVE" --reason r
expect_rc 2 "a session starting with - exits 2"; expect_no_call "session starting with -"

for kind in with without; do
    run "$kind" 0 --session s --gate g --rule no-such/rule --reason r
    expect_rc 2 "($kind) a rule id with no registry entry exits 2"; expect_no_call "($kind) unknown rule id"
    run "$kind" 0 --session s --gate g --rule "$RETIRED" --reason r
    expect_rc 2 "($kind) a retired rule id exits 2"; expect_no_call "($kind) retired rule id"
    run "$kind" 0 --session s --gate g --rule '../../etc/passwd' --reason r
    expect_rc 2 "($kind) a malformed rule id exits 2"; expect_no_call "($kind) malformed rule id"
done
case "$ERR" in
    *"not an active entry"*) pass "a refused rule id says why on standard error" ;;
    *) fail "no reason given for a refused rule id: [$ERR]" ;;
esac

# ---------------------------------------------------------------------------
# A koto with `koto disputes record`.

run with 0 --session wf.child --gate verdict --rule "$ACTIVE" --reason "quoted path, not a reference"
expect_rc 0 "(journaled) a valid dispute exits 0"
[ "$OUT" = "dispute=journaled" ] && pass "(journaled) stdout is dispute=journaled alone" \
    || fail "(journaled) stdout: [$OUT]"
expect_argv "(journaled) session, gate, rule and reason reach koto as separate words; no --state or --by when not given" \
    disputes record wf.child "--gate=verdict" "--rule=$ACTIVE" "--reason=quoted path, not a reference"
case "$ERR" in *'{"status":"recorded"}'*) pass "(journaled) koto's own output goes to standard error" ;;
    *) fail "(journaled) koto's output not on standard error: [$ERR]" ;; esac

run with 0 --by person --state analysis --reason because --rule "$ACTIVE" --gate verdict --session wf
expect_rc 0 "(journaled) arguments in any order with --state and --by exit 0"
expect_argv "(journaled) --state and --by are passed when given" \
    disputes record wf "--gate=verdict" "--rule=$ACTIVE" "--reason=because" "--state=analysis" "--by=person"

run with 0 --session wf --gate verdict --rule "$ACTIVE" --reason because --by agent
expect_argv "(journaled) --by agent alone is passed" \
    disputes record wf "--gate=verdict" "--rule=$ACTIVE" "--reason=because" "--by=agent"

NASTY='he said "it'"'"'s fine" $(touch '"$T"'/pwned) `touch '"$T"'/pwned2` {"choice":"x","rationale":"y"} \n; rm -rf /'
run with 0 --session wf --gate verdict --rule "$ACTIVE" --reason "$NASTY"
expect_rc 0 "(journaled) a reason with quotes, \$(), backticks and JSON exits 0"
expect_argv "(journaled) that reason reaches koto verbatim" \
    disputes record wf "--gate=verdict" "--rule=$ACTIVE" "--reason=$NASTY"
if [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ]; then pass "(journaled) nothing in the reason ran"; else fail "(journaled) the reason ran a command"; fi

run with 0 --session wf --gate verdict --rule "$ACTIVE" --reason "--by=person"
expect_argv "(journaled) a reason that looks like a flag stays the reason's value" \
    disputes record wf "--gate=verdict" "--rule=$ACTIVE" "--reason=--by=person"

ML=$(printf 'line one\nline two')
run with 0 --session wf --gate verdict --rule "$ACTIVE" --reason "$ML"
expect_argv "(journaled) a multi-line reason reaches koto verbatim" \
    disputes record wf "--gate=verdict" "--rule=$ACTIVE" "--reason=$ML"

for code in 1 2 5; do
    run with "$code" --session wf --gate verdict --rule "$ACTIVE" --reason r
    expect_rc "$code" "(journaled) koto's exit $code passes through"
    [ -z "$OUT" ] && pass "(journaled) nothing on stdout when koto exits $code" \
        || fail "(journaled) stdout when koto failed: [$OUT]"
done

# ---------------------------------------------------------------------------
# A koto without it: a decision in the run's record, through run-trail.sh,
# which also sends it through koto decisions record.

# trail_key, trail_record -- the key and the document the fallback's
# run-trail.sh wrote with context add.
trail_key() { sed -n 1p "$TRAIL_LOG" 2>/dev/null; }
trail_record() { sed -n 2p "$TRAIL_LOG" 2>/dev/null; }

run without 0 --session wf.child --gate verdict --rule "$ACTIVE" --reason "quoted path"
expect_rc 0 "(session-only) a valid dispute exits 0"
[ "$OUT" = "dispute=session-only" ] && pass "(session-only) stdout is dispute=session-only alone" \
    || fail "(session-only) stdout: [$OUT]"
DATA=$(logged_data)
expect_argv "(session-only) koto decisions record <session> --with-data <json>, as separate words" \
    decisions record wf.child --with-data "$DATA"
[ "$(jq -r .choice <<<"$DATA")" = "dispute:$ACTIVE" ] && pass "(session-only) choice is dispute:<rule-id>" \
    || fail "(session-only) choice: [$DATA]"
[ "$(jq -r .rationale <<<"$DATA")" = "gate=verdict state=current: quoted path" ] \
    && pass "(session-only) rationale defaults state to current, and names no actor" \
    || fail "(session-only) rationale: [$DATA]"
[ "$(jq -r 'keys | join(",")' <<<"$DATA")" = "choice,rationale" ] && pass "(session-only) koto's record holds choice and rationale only" \
    || fail "(session-only) keys: [$DATA]"
REC=$(trail_record)
if [ "$(trail_key)" = trail/decision/1.json ] \
    && [ "$(jq -c '{step, actor, choice, rationale}' <<<"$REC")" = "$(jq -nc --arg c "dispute:$ACTIVE" '{step: "wf.child", actor: "agent:wf.child", choice: $c, rationale: "gate=verdict state=current: quoted path"}')" ]; then
    pass "(session-only) the run's record holds the decision with actor agent:<session>, against the session when no --step is given"
else
    fail "(session-only) trail: [$(trail_key)] [$REC]"
fi

run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason because --state analysis --by person --step step-3
DATA=$(logged_data)
[ "$(jq -r .rationale <<<"$DATA")" = "gate=verdict state=analysis: because" ] \
    && pass "(session-only) rationale carries the given state" \
    || fail "(session-only) rationale: [$DATA]"
[ "$(jq -c '{step, actor}' <<<"$(trail_record)")" = '{"step":"step-3","actor":"person"}' ] \
    && pass "(session-only) --by person is the record's actor person, against the given --step" \
    || fail "(session-only) person trail: [$(trail_record)]"

run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason "$NASTY"
expect_rc 0 "(session-only) a reason with quotes, \$(), backticks and JSON exits 0"
DATA=$(logged_data)
if [ "$(jq -r .rationale <<<"$DATA")" = "gate=verdict state=current: $NASTY" ] \
    && [ "$(jq -r .rationale <<<"$(trail_record)")" = "gate=verdict state=current: $NASTY" ]; then
    pass "(session-only) that reason reaches both records verbatim"
else
    fail "(session-only) rationale: [$DATA]"
fi
[ "$(jq -r .choice <<<"$DATA")" = "dispute:$ACTIVE" ] && pass "(session-only) JSON in the reason doesn't change the choice" \
    || fail "(session-only) choice: [$DATA]"
if [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ]; then pass "(session-only) nothing in the reason ran"; else fail "(session-only) the reason ran a command"; fi

run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason "$ML"
DATA=$(logged_data)
[ "$(jq -r .rationale <<<"$DATA")" = "gate=verdict state=current: $ML" ] \
    && pass "(session-only) a multi-line reason reaches the record verbatim" \
    || fail "(session-only) rationale: [$DATA]"

run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason r --step ""
expect_rc 2 "an empty --step exits 2"; expect_no_call "empty --step"
run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason r --step ../x
expect_rc 65 "(session-only) a --step outside the step pattern is run-trail.sh's refusal (65)"
expect_no_call "(session-only) --step ../x"
run without 0 --session wf --gate verdict --rule "$ACTIVE" --reason "token ghp_abcdefghijklmnopqrstuvwxyz0123456789"
expect_rc 65 "(session-only) a reason holding a token is refused (65)"
[ ! -e "$LOG" ] && [ ! -e "$TRAIL_LOG" ] && pass "(session-only) a refused reason records nothing, in koto or the trail" \
    || fail "(session-only) a refused reason was recorded"

for code in 1 2 5; do
    run without "$code" --session wf --gate verdict --rule "$ACTIVE" --reason r
    expect_rc 70 "(session-only) koto decisions record exiting $code is run-trail.sh's 70, passed through"
    [ -z "$OUT" ] && pass "(session-only) nothing on stdout when koto exits $code" \
        || fail "(session-only) stdout when koto failed: [$OUT]"
done

echo
echo "rule-dispute_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
