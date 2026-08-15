#!/usr/bin/env bash
# preflight-probe_test.sh -- test harness for scripts/lib/preflight-probe.sh.
#
# Usage: bash scripts/lib/preflight-probe_test.sh
#        /bin/bash scripts/lib/preflight-probe_test.sh    # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# Two kinds of case, and the split matters.
#
#   Unit cases source the helper into this shell and call the extractor and the
#   memo directly. They are how the clap-layout contract is pinned against
#   fixtures captured from real `--help` output.
#
#   End-to-end cases run scripts/skill-preflight.sh as a separate process
#   against a throwaway plugin root, with PATH pointing at counting shims. They
#   are how the call count, the never-run-a-declared-subcommand invariant, and
#   the zero-bytes-when-satisfied rule are held over the real wiring rather than
#   over the helper in isolation.
#
# Three named cases exist because a plausible implementation passes without
# them:
#
#   preflight_probe_returns_at_call_speed. A watchdog that inherits the capture
#   pipe holds it open for the whole budget, so every probe costs the budget
#   even against a binary that answers in 3ms. Measured on this host with the
#   defect present: 2.017s for one `shirabe --help`. A test that only asks
#   whether a hung binary times out passes with that defect, because the defect
#   makes everything time out. This one asserts the fast path is fast.
#
#   preflight_probe_kills_a_hung_binary. The other half: the budget is real,
#   the report says inconclusive rather than naming a missing surface, and
#   nothing survives the run. The fixture forks, because a fixture that does
#   not cannot tell a process-group kill from a process kill -- and with a
#   process kill the parent stays blocked on the pipe its grandchild still
#   holds, measured at 30.019s.
#
#   preflight_probe_extracts_both_short_and_long. clap renders `-h, --help` on
#   one line, so a literal first-token reading yields `-h,` and drops `--help`,
#   which is the form every declaration names.

set -uo pipefail

# The entry point runs under LC_ALL=C and the helper's character classes are
# byte ranges, so the harness runs there too. A unit case under the developer's
# UTF-8 locale would be testing collation semantics the check never sees.
LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)
ENTRY="$REPO/scripts/skill-preflight.sh"

BASH_BIN=$(command -v "${PREFLIGHT_TEST_BASH:-${BASH:-bash}}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

TMPS=()
cleanup() {
    local d
    for d in ${TMPS[@]+"${TMPS[@]}"}; do
        [ -n "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

mktmp() {
    local d
    d=$(mktemp -d)
    TMPS[${#TMPS[@]}]="$d"
    printf '%s' "$d"
}

# A millisecond clock. bash 3.2 has no EPOCHREALTIME and macOS `date` has no
# %N, so python3 is used when it is there -- both CI legs have it -- and the
# coarse integer fallback keeps the case meaningful when it is not.
PY=$(command -v python3 2>/dev/null || true)
now_ms() {
    if [ -n "$PY" ]; then
        "$PY" -c 'import time; print(int(time.time()*1000))'
    else
        printf '%s' "$(( SECONDS * 1000 ))"
    fi
}

assert_eq() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        pass "$name"
    else
        fail "$name: expected [$want], got [$got]"
    fi
}

assert_has() {
    local name="$1" hay="$2" needle="$3"
    case "$hay" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name: expected to find '$needle' in: $hay" ;;
    esac
}

assert_lacks() {
    local name="$1" hay="$2" needle="$3"
    case "$hay" in
        *"$needle"*) fail "$name: '$needle' must not appear in: $hay" ;;
        *) pass "$name" ;;
    esac
}

# Report prose is wrapped on word boundaries once the entry point's wrapper is
# in play, so a sentence assertion has to be made against the unwrapped text or
# it tests the wrap width instead of the wording. Line structure that carries
# meaning -- the indented list line, the blank line between blocks -- is
# asserted against the raw form.
prose() {
    local s
    s=$(printf '%s' "$1" | tr '\n\t' '  ')
    while :; do
        case "$s" in
            *'  '*) s="${s//  / }" ;;
            *) break ;;
        esac
    done
    printf '%s' "$s"
}

assert_token() {
    local name="$1" list="$2" tok="$3"
    case " $list " in
        *" $tok "*) pass "$name" ;;
        *) fail "$name: expected token '$tok' among: $list" ;;
    esac
}

assert_no_token() {
    local name="$1" list="$2" tok="$3"
    case " $list " in
        *" $tok "*) fail "$name: token '$tok' must not be extracted; got: $list" ;;
        *) pass "$name" ;;
    esac
}

# ---------------------------------------------------------------------------
# Fixtures, captured from real help output.
#
# HELP_ROADMAP is `shirabe roadmap --help` verbatim: one Commands entry whose
# description names two flags the level does not accept, which is the measured
# false positive a loose grep produces.
#
# HELP_POPULATE is the wrapped-long-flag layout `shirabe roadmap populate`
# renders: the flag at 6 spaces, its description at 10 on the next line.
#
# HELP_CONTEXT_ADD is the inline layout with a value placeholder,
# `koto context add`.
# ---------------------------------------------------------------------------

help_roadmap() {
    cat <<'EOF'
Roadmap-scoped subcommands

Usage: shirabe roadmap <COMMAND>

Commands:
  populate  Populate a roadmap's reserved sections. Renders issuelessly by default. Pass `--issues` to create one GitHub issue per feature; `--no-issues` names the default explicitly
  help      Print this message or the help of the given subcommand(s)

Options:
  -h, --help  Print help
EOF
}

help_populate() {
    cat <<'EOF'
Populate a roadmap's reserved sections

Usage: shirabe roadmap populate [OPTIONS] <ROADMAP_PATH>

Arguments:
  <ROADMAP_PATH>  Path to the roadmap document to populate

Options:
      --milestone <MILESTONE>
          Milestone name to assign to all created issues [default: ""]
      --dry-run
          Skip `gh` invocations
      --issues
          Issue-creating mode. Mutually exclusive with `--no-issues`
      --no-issues
          Issueless render mode, and the default. Mutually exclusive with `--issues`
  -h, --help
          Print help
EOF
}

help_context_add() {
    cat <<'EOF'
Store content under a key (reads from stdin or --from-file)

Usage: koto context add [OPTIONS] <SESSION> <KEY>

Arguments:
  <SESSION>  Session name
  <KEY>      Context key

Options:
      --from-file <FROM_FILE>  Read content from file instead of stdin
  -h, --help                   Print help
EOF
}

# ---------------------------------------------------------------------------
# Unit cases
# ---------------------------------------------------------------------------

# shellcheck source=scripts/lib/preflight-read.sh
. "$REPO/scripts/lib/preflight-read.sh"
# shellcheck source=scripts/lib/preflight-resolve.sh
. "$REPO/scripts/lib/preflight-resolve.sh"
# shellcheck source=scripts/lib/preflight-probe.sh
. "$REPO/scripts/lib/preflight-probe.sh"

echo "--- extraction ---"

# preflight_probe_extracts_both_short_and_long
preflight_probe_extract "$(help_context_add)"
INLINE="$PREFLIGHT_PROBE_TOKENS"
assert_token "preflight_probe_extracts_both_short_and_long: -h from the inline layout" \
    "$INLINE" "-h"
assert_token "preflight_probe_extracts_both_short_and_long: --help from the inline layout" \
    "$INLINE" "--help"
assert_token "preflight_probe_extracts_both_short_and_long: --from-file, the long form a declaration names" \
    "$INLINE" "--from-file"
assert_no_token "preflight_probe_extracts_both_short_and_long: the value placeholder is dropped, not sanitized" \
    "$INLINE" "<FROM_FILE>"
assert_no_token "preflight_probe_extracts_both_short_and_long: the trailing comma form is never emitted" \
    "$INLINE" "-h,"

preflight_probe_extract "$(help_populate)"
WRAPPED="$PREFLIGHT_PROBE_TOKENS"
assert_token "preflight_probe_extracts_both_short_and_long: --no-issues from the wrapped layout" \
    "$WRAPPED" "--no-issues"
assert_token "preflight_probe_extracts_both_short_and_long: -h from the wrapped layout" \
    "$WRAPPED" "-h"
assert_token "preflight_probe_extracts_both_short_and_long: --help from the wrapped layout" \
    "$WRAPPED" "--help"
assert_token "the wrapped layout still yields --milestone" "$WRAPPED" "--milestone"
assert_no_token "a wrapped description line contributes nothing" "$WRAPPED" "Milestone"
assert_no_token "a wrapped description line's flag mention contributes nothing" \
    "$WRAPPED" "--issues\`"

# Position-anchored extraction, the measured false positive a loose grep makes.
preflight_probe_extract "$(help_roadmap)"
ROADMAP="$PREFLIGHT_PROBE_TOKENS"
assert_token "the Commands region yields the subcommand name" "$ROADMAP" "populate"
assert_token "the Options region yields --help at this level" "$ROADMAP" "--help"
assert_no_token "a flag named only in a description is not advertised by this level (--issues)" \
    "$ROADMAP" "--issues"
assert_no_token "a flag named only in a description is not advertised by this level (--no-issues)" \
    "$ROADMAP" "--no-issues"
if help_roadmap | grep -q -- '--no-issues'; then
    pass "the control holds: a loose grep does match --no-issues here, which is why the extractor is anchored"
else
    fail "the control fixture no longer reproduces the loose-grep false positive"
fi
assert_no_token "a token inside Usage: is not extracted" "$ROADMAP" "shirabe"
assert_no_token "a token inside Arguments: is not extracted" \
    "$(preflight_probe_extract "$(help_populate)"; printf '%s' "$PREFLIGHT_PROBE_TOKENS")" "<ROADMAP_PATH>"

# Control and escape handling: the source line is stripped before any token is
# read, so an escape sequence cannot survive inside a conforming token.
ANSI_TEXT=$(printf 'Options:\n  -h, --help  Print \033[31mhelp\033[0m\n  --\033[1mbold\033[0m-flag  desc\n')
preflight_probe_extract "$ANSI_TEXT"
assert_token "an ANSI-decorated option line still yields --help" "$PREFLIGHT_PROBE_TOKENS" "--help"
assert_token "an escape sequence inside a flag is stripped before the allowlist runs" \
    "$PREFLIGHT_PROBE_TOKENS" "--bold-flag"
assert_lacks "no escape byte reaches the extracted list" \
    "$PREFLIGHT_PROBE_TOKENS" "$(printf '\033')"

LONG=$(printf 'Options:\n  --%s  desc\n' "$(printf 'a%.0s' $(seq 1 70))")
preflight_probe_extract "$LONG"
assert_eq "a token longer than 64 bytes is dropped" "" "$PREFLIGHT_PROBE_TOKENS"

echo
echo "--- memoization ---"

PROBE_KEYS=""
PROBE_DATA=""
MEMO_DIR=$(mktmp)
MEMO_COUNT="$MEMO_DIR/count"
: >"$MEMO_COUNT"
{
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >> %s\n' "$MEMO_COUNT"
    printf 'printf "Commands:\\n  add  Store\\n  get  Retrieve\\n\\nOptions:\\n  -h, --help  Print help\\n"\n'
} >"$MEMO_DIR/tool"
chmod +x "$MEMO_DIR/tool"

preflight_probe_level "koto context" "$MEMO_DIR/tool" context
FIRST="$PREFLIGHT_LEVEL_TOKENS"
preflight_probe_level "koto context" "$MEMO_DIR/tool" context
SECOND="$PREFLIGHT_LEVEL_TOKENS"
MEMO_CALLS=$(wc -l <"$MEMO_COUNT" | tr -d ' ')
assert_eq "a second visit to a level costs no invocation" "1" "$MEMO_CALLS"
assert_eq "a memoized level returns the same tokens" "$FIRST" "$SECOND"
assert_token "the memoized level carries its subcommands" "$SECOND" "add"
assert_token "the memoized level carries its flags" "$SECOND" "--help"
assert_has "the memo key is stored bracketed by newlines" "$PROBE_KEYS" "koto context"
assert_has "the memo value is stored key<TAB>tokens" "$PROBE_DATA" "koto context$(printf '\t')"

echo
echo "--- the bounded probe ---"

FIX=$(mktmp)

# A fast, well-behaved clap-shaped binary.
{
    printf '#!/bin/bash\n'
    printf 'printf "Commands:\\n  add  Store\\n\\nOptions:\\n  -h, --help  Print help\\n"\n'
} >"$FIX/fast"
chmod +x "$FIX/fast"

# A binary that hangs, and forks while doing it: the `sleep` is a child, so a
# TERM to the fixture alone leaves it holding the capture pipe.
{
    printf '#!/bin/bash\n'
    printf 'sleep 3733 &\n'
    printf 'wait\n'
} >"$FIX/hang"
chmod +x "$FIX/hang"

# A binary that writes without stopping.
{
    printf '#!/bin/bash\n'
    printf 'exec yes "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n'
} >"$FIX/flood"
chmod +x "$FIX/flood"

# A binary whose stderr names a flag its stdout does not advertise.
{
    printf '#!/bin/bash\n'
    printf 'printf "Options:\\n  --stderr-only  Print help\\n" >&2\n'
    printf 'printf "Options:\\n  -h, --help  Print help\\n"\n'
} >"$FIX/noisy"
chmod +x "$FIX/noisy"

# A binary that reads stdin. With the probe's stdin closed it sees EOF at once
# and prints; with the harness's stdin inherited it would block until the budget
# expired, which is the never-block promise failing quietly.
{
    printf '#!/bin/bash\n'
    printf 'cat\n'
    printf 'printf "Options:\\n  -h, --help  Print help\\n"\n'
} >"$FIX/reader"
chmod +x "$FIX/reader"

PROBE_KEYS=""
PROBE_DATA=""
preflight_probe_capture "$FIX/reader"
assert_eq "a probe that reads stdin sees EOF instead of blocking" "ok" "$PREFLIGHT_PROBE_OUTCOME"

# preflight_probe_returns_at_call_speed
#
# Two assertions over the same property, because neither alone is both precise
# and portable. The millisecond one is the AC's 250ms bound on one probe. The
# coarse one runs eight probes and asserts the whole batch inside a second,
# which with the inherited-descriptor defect would take sixteen.
PROBE_KEYS=""
PROBE_DATA=""
T0=$(now_ms)
preflight_probe_capture "$FIX/fast"
T1=$(now_ms)
FAST_MS=$(( T1 - T0 ))
assert_eq "preflight_probe_returns_at_call_speed: the fast probe is usable" "ok" "$PREFLIGHT_PROBE_OUTCOME"
if [ -n "$PY" ]; then
    if [ "$FAST_MS" -lt 250 ]; then
        pass "preflight_probe_returns_at_call_speed: one probe of a fast binary took ${FAST_MS}ms, under the 250ms bound"
    else
        fail "preflight_probe_returns_at_call_speed: one probe of a fast binary took ${FAST_MS}ms; the watchdog is holding the capture descriptors for the whole budget"
    fi
fi

BATCH_START=$SECONDS
I=0
while [ "$I" -lt 8 ]; do
    preflight_probe_capture "$FIX/fast"
    I=$(( I + 1 ))
done
BATCH=$(( SECONDS - BATCH_START ))
if [ "$BATCH" -le 1 ]; then
    pass "preflight_probe_returns_at_call_speed: eight probes finished in ${BATCH}s, so no probe waited on the budget"
else
    fail "preflight_probe_returns_at_call_speed: eight probes took ${BATCH}s; with the budget inherited that is sixteen, which is the defect"
fi

# preflight_probe_kills_a_hung_binary
PROBE_KEYS=""
PROBE_DATA=""
SHIRABE_PREFLIGHT_BUDGET=1
export SHIRABE_PREFLIGHT_BUDGET
PREFLIGHT_PROBE_BUDGET=1
HANG_START=$SECONDS
preflight_probe_capture "$FIX/hang"
HANG=$(( SECONDS - HANG_START ))
assert_eq "preflight_probe_kills_a_hung_binary: the outcome is a timeout" "timeout" "$PREFLIGHT_PROBE_OUTCOME"
if [ "$HANG" -le 3 ]; then
    pass "preflight_probe_kills_a_hung_binary: bounded at ${HANG}s against a 1s budget"
else
    fail "preflight_probe_kills_a_hung_binary: took ${HANG}s against a 1s budget; a descendant is still holding the capture pipe"
fi
if command -v pgrep >/dev/null 2>&1; then
    sleep 1
    if pgrep -f "sleep 3733" >/dev/null 2>&1; then
        fail "preflight_probe_kills_a_hung_binary: a child of the probe survived the run"
        pkill -f "sleep 3733" >/dev/null 2>&1 || true
    else
        pass "preflight_probe_kills_a_hung_binary: no child of the probe survived the run"
    fi
fi

# The byte cap, and that hitting it is inconclusive rather than empty output
# that could be read as a level advertising nothing.
PROBE_KEYS=""
PROBE_DATA=""
FLOOD_START=$SECONDS
preflight_probe_capture "$FIX/flood"
FLOOD=$(( SECONDS - FLOOD_START ))
assert_eq "a probe that writes past the cap is inconclusive" "overcap" "$PREFLIGHT_PROBE_OUTCOME"
assert_eq "an over-cap read keeps no text, so nothing can be extracted from it" "" "$PREFLIGHT_PROBE_TEXT"
if [ "$FLOOD" -le 3 ]; then
    pass "the byte cap bounds a runaway writer at ${FLOOD}s"
else
    fail "the byte cap did not bound a runaway writer: ${FLOOD}s"
fi

unset SHIRABE_PREFLIGHT_BUDGET
PREFLIGHT_PROBE_BUDGET=2

echo
echo "--- inconclusive is not a finding ---"

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
PREFLIGHT_PROBE_BUDGET=1
OUT=$(preflight_check_surface "work-on" "koto" "context add" "-" "$FIX/hang" 2>&1)
assert_has "the inconclusive block says the probe did not complete" "$OUT" "did not complete"
assert_has "the inconclusive block names the tool" "$OUT" "koto"
assert_lacks "an inconclusive probe never reports a missing subcommand" \
    "$OUT" "does not have the subcommand"
assert_lacks "an inconclusive probe never reports a missing flag" \
    "$OUT" "does not advertise the flag"
assert_has "the inconclusive block says no surface claim is made" "$OUT" "makes no claim"
PREFLIGHT_PROBE_BUDGET=2

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
OUT=$(preflight_check_surface "work-on" "koto" "-" "--stderr-only" "$FIX/noisy" 2>&1)
assert_has "preflight_probe_never_reads_stderr: a flag advertised only on stderr is reported missing" \
    "$OUT" "does not advertise the flag --stderr-only"
assert_lacks "preflight_probe_never_reads_stderr: no stderr text is echoed into the report" \
    "$OUT" "Print help"

echo
echo "--- surface gaps ---"

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
{
    printf '#!/bin/bash\n'
    printf 'case "$*" in\n'
    printf '  "--help") printf "Commands:\\n  context  Content context\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "context --help") printf "Commands:\\n  add  Store\\n  get  Retrieve\\n  exists  Check\\n  list  List\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "context add --help") printf "Options:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  *) printf "error: unrecognized subcommand\\n" >&2; exit 2 ;;\n'
    printf 'esac\n'
} >"$FIX/koto"
chmod +x "$FIX/koto"

OUT=$(preflight_check_surface "work-on" "koto" "context remove" "-" "$FIX/koto" 2>&1)
assert_has "a missing subcommand is named as such" "$OUT" "does not have the subcommand"
assert_has "the missing subcommand block names the declared path" "$OUT" "koto context remove"
assert_has "the missing subcommand block lists what the level does advertise" "$OUT" "advertises:"
assert_has "the advertised list carries the level's real subcommands" "$OUT" "add, get, exists, list"
assert_has "the block closes on the bound a surface probe has" \
    "$(prose "$OUT")" "cannot tell you whether any released koto has \`koto context remove\`"
assert_lacks "the advertised list carries no flags" "$OUT" "--help,"

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
OUT=$(preflight_check_surface "work-on" "koto" "context add" "-" "$FIX/koto" 2>&1)
assert_eq "a satisfied subcommand path emits nothing" "" "$OUT"

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
OUT=$(preflight_check_surface "work-on" "koto" "context add" "--from-file" "$FIX/koto" 2>&1)
assert_has "a missing flag is named as such" "$OUT" "does not advertise the flag --from-file"
assert_has "the missing flag block names the level that does exist" "$OUT" "koto context add"

PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
OUT=$(preflight_check_surface "roadmap" "shirabe" "-" "-" "$FIX/koto" 2>&1)
assert_eq "a tool-only record probes nothing and says nothing" "" "$OUT"

# A tool whose --help is not in clap's layout advertises nothing this extractor
# can read, and an empty extraction must not become a missing-flag finding.
{
    printf '#!/bin/bash\n'
    printf 'printf "usage: notclap [--arg value]\\n\\nA hand-rolled help page. Use --arg to pass a value.\\n"\n'
} >"$FIX/notclap"
chmod +x "$FIX/notclap"
PROBE_KEYS=""
PROBE_DATA=""
PROBE_EMITTED=""
OUT=$(preflight_check_surface "explore" "jq" "-" "--arg" "$FIX/notclap" 2>&1)
assert_lacks "a non-clap help page never produces a missing-flag finding" \
    "$(prose "$OUT")" "does not advertise the flag"
assert_has "a non-clap help page is reported as unreadable, not as absent surface" \
    "$(prose "$OUT")" "cannot read"

echo
echo "--- end to end ---"

# new_root -- a throwaway plugin root carrying the real scripts under test.
new_root() {
    local root
    root=$(mktmp)
    mkdir -p "$root/.claude-plugin" "$root/scripts/lib" "$root/skills"
    printf '{"name":"shirabe","version":"0.0.0-test"}\n' >"$root/.claude-plugin/plugin.json"
    cp "$ENTRY" "$root/scripts/skill-preflight.sh"
    cp "$REPO/scripts/lib/preflight-read.sh" "$root/scripts/lib/preflight-read.sh"
    cp "$REPO/scripts/lib/preflight-resolve.sh" "$root/scripts/lib/preflight-resolve.sh"
    cp "$REPO/scripts/lib/preflight-probe.sh" "$root/scripts/lib/preflight-probe.sh"
    cp "$REPO/scripts/lib/tool-routes.tsv" "$root/scripts/lib/tool-routes.tsv"
    printf '%s' "$root"
}

# write_decl <root> <skill> <record>...
#
# Records are written through `printf '%b'`, so `\t` in an argument becomes a
# real tab. Writing tabs any other way is how a declaration fixture silently
# stops testing the format it claims to. The schema line is written here rather
# than passed by every caller, because a fixture that forgets it fails at the
# reader and every surface assertion downstream becomes vacuous.
write_decl() {
    local root="$1" skill="$2"
    shift 2
    mkdir -p "$root/skills/$skill"
    printf '#schema\tskill-requires/v1\n' >"$root/skills/$skill/requires.tsv"
    local line
    for line in "$@"; do
        printf '%b\n' "$line" >>"$root/skills/$skill/requires.tsv"
    done
}

# The counting shims. Each records its full argv, one invocation per line, so a
# case can count calls and assert that every one of them ended in --help.
BIN=$(mktmp)
CALLS="$BIN/calls"
: >"$CALLS"

{
    printf '#!/bin/bash\n'
    printf 'printf "koto %%s\\n" "$*" >> %s\n' "$CALLS"
    printf 'case "$*" in\n'
    printf '  "--help") printf "Commands:\\n  init  Init\\n  next  Next\\n  context  Context\\n  decisions  Decisions\\n  overrides  Overrides\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "init --help") printf "Options:\\n      --template <TEMPLATE>  Template\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "next --help") printf "Options:\\n      --json  JSON\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "context --help") printf "Commands:\\n  add  Store\\n  get  Get\\n  exists  Exists\\n  list  List\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "decisions --help") printf "Commands:\\n  record  Record\\n  list  List\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "decisions record --help") printf "Options:\\n      --rationale <R>  Why\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "overrides --help") printf "Commands:\\n  record  Record\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  *) printf "error: unrecognized subcommand\\n" >&2; exit 2 ;;\n'
    printf 'esac\n'
} >"$BIN/koto"
chmod +x "$BIN/koto"

{
    printf '#!/bin/bash\n'
    printf 'printf "shirabe %%s\\n" "$*" >> %s\n' "$CALLS"
    printf 'case "$*" in\n'
    printf '  "--help") printf "Commands:\\n  validate  Validate\\n  roadmap  Roadmap\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "validate --help") printf "Options:\\n      --lifecycle-chain <DOC>\\n          Chain-targeted\\n      --mode <MODE>\\n          Posture\\n  -h, --help\\n          Print help\\n" ;;\n'
    printf '  "roadmap --help") printf "Commands:\\n  populate  Populate. Pass \\140--issues\\140 to create issues; \\140--no-issues\\140 names the default\\n\\nOptions:\\n  -h, --help  Print help\\n" ;;\n'
    printf '  "roadmap populate --help") printf "Options:\\n      --issues\\n          Issue-creating mode\\n      --no-issues\\n          Issueless mode\\n  -h, --help\\n          Print help\\n" ;;\n'
    printf '  *) printf "error: unrecognized subcommand\\n" >&2; exit 2 ;;\n'
    printf 'esac\n'
} >"$BIN/shirabe"
chmod +x "$BIN/shirabe"

for T in gh git jq; do
    {
        printf '#!/bin/bash\n'
        printf 'printf "%s %%s\\n" "$*" >> %s\n' "$T" "$CALLS"
        printf 'printf "usage\\n"\n'
    } >"$BIN/$T"
    chmod +x "$BIN/$T"
done

RUN_OUT=""
RUN_BYTES=0
RUN_RC=0
run_preflight() {
    local root="$1" skill="$2" capture
    capture=$(mktmp)/capture
    RUN_RC=0
    (
        cd "$REPO" || exit 111
        PATH="$BIN:/usr/bin:/bin"
        export PATH
        SHIRABE_PREFLIGHT_ROOTS="/nonexistent"
        export SHIRABE_PREFLIGHT_ROOTS
        CLAUDE_PLUGIN_ROOT="$root"
        export CLAUDE_PLUGIN_ROOT
        "$BASH_BIN" "$root/scripts/skill-preflight.sh" "$skill"
    ) >"$capture" 2>&1 || RUN_RC=$?
    RUN_BYTES=$(wc -c <"$capture" | tr -d ' ')
    RUN_OUT=$(cat "$capture")
    if [ "$RUN_RC" -ne 0 ]; then
        fail "$skill: the check exited $RUN_RC; it must exit 0 on every path"
    fi
}

# A /work-on-shaped declaration: ten distinct levels, nine --help calls.
ROOT=$(new_root)
write_decl "$ROOT" "work-on" \
    'koto\tinit\t--template\talways' \
    'koto\tnext\t--json\talways' \
    'koto\tcontext add\t-\talways' \
    'koto\tcontext get\t-\talways' \
    'koto\tcontext exists\t-\talways' \
    'koto\tdecisions record\t--rationale\talways' \
    'koto\toverrides record\t-\talways' \
    'shirabe\tvalidate\t--lifecycle-chain,--mode\talways' \
    'gh\t-\t-\talways' \
    'git\t-\t-\talways' \
    'jq\t-\t-\talways'

: >"$CALLS"
run_preflight "$ROOT" "work-on"
WORK_ON_CALLS=$(wc -l <"$CALLS" | tr -d ' ')
assert_eq "a /work-on-shaped declaration is silent on a satisfied host" "0" "$RUN_BYTES"
assert_eq "a /work-on-shaped declaration costs nine --help calls" "9" "$WORK_ON_CALLS"
assert_has "the memoized path probes koto context once" "$(cat "$CALLS")" "koto context --help"
assert_lacks "a leaf with no declared flag is never probed" "$(cat "$CALLS")" "koto context add --help"

NON_HELP=$(grep -v -- '--help$' <"$CALLS" || true)
assert_eq "the probe only ever appends --help, and never runs a declared subcommand" "" "$NON_HELP"

# A /scope-shaped declaration: three calls.
ROOT=$(new_root)
write_decl "$ROOT" "scope" \
    'shirabe\tvalidate\t--mode\talways' \
    'koto\tnext\t-\talways'
: >"$CALLS"
run_preflight "$ROOT" "scope"
SCOPE_CALLS=$(wc -l <"$CALLS" | tr -d ' ')
assert_eq "a /scope-shaped declaration is silent on a satisfied host" "0" "$RUN_BYTES"
assert_eq "a /scope-shaped declaration costs three --help calls" "3" "$SCOPE_CALLS"

# The regression fixtures, end to end: a known-present flag in each clap layout
# passes, and a known-absent one is reported. A help-rendering change fails here
# loudly instead of under-reporting.
ROOT=$(new_root)
write_decl "$ROOT" "roadmap" \
    'shirabe\troadmap populate\t--no-issues,--issues\talways'
: >"$CALLS"
run_preflight "$ROOT" "roadmap"
assert_eq "a known-present flag in the wrapped layout is satisfied" "0" "$RUN_BYTES"

ROOT=$(new_root)
write_decl "$ROOT" "roadmap" \
    'shirabe\troadmap\t--no-issues\talways'
: >"$CALLS"
run_preflight "$ROOT" "roadmap"
assert_has "a flag named only in a description is reported absent at that level" \
    "$(prose "$RUN_OUT")" "does not advertise the flag --no-issues"

ROOT=$(new_root)
write_decl "$ROOT" "work-on" \
    'koto\tcontext remove\t-\talways'
: >"$CALLS"
run_preflight "$ROOT" "work-on"
assert_has "a missing subcommand is reported end to end" "$RUN_OUT" "does not have the subcommand"
assert_has "the end-to-end block names the skill" "$RUN_OUT" "shirabe /work-on"
assert_has "the end-to-end block lists what the level advertises" "$RUN_OUT" "advertises:"

# A hung tool named by several records produces one block, not one per record.
ROOT=$(new_root)
cp "$FIX/hang" "$BIN/koto.hang"
HANGBIN=$(mktmp)
cp "$FIX/hang" "$HANGBIN/koto"
write_decl "$ROOT" "work-on" \
    'koto\tinit\t-\talways' \
    'koto\tnext\t-\talways' \
    'koto\tcontext add\t-\talways'
: >"$CALLS"
RUN_RC=0
CAPTURE=$(mktmp)/capture
(
    cd "$REPO" || exit 111
    PATH="$HANGBIN:/usr/bin:/bin"
    export PATH
    SHIRABE_PREFLIGHT_ROOTS="/nonexistent"
    export SHIRABE_PREFLIGHT_ROOTS
    SHIRABE_PREFLIGHT_BUDGET=1
    export SHIRABE_PREFLIGHT_BUDGET
    CLAUDE_PLUGIN_ROOT="$ROOT"
    export CLAUDE_PLUGIN_ROOT
    "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh" "work-on"
) >"$CAPTURE" 2>&1 || RUN_RC=$?
RUN_OUT=$(cat "$CAPTURE")
if [ "$RUN_RC" -ne 0 ]; then
    fail "hung tool: the check exited $RUN_RC; it must exit 0 on every path"
fi
BLOCKS=$(grep -c "could not be checked" <"$CAPTURE" || true)
assert_eq "a hung tool named by three records produces one block" "1" "$BLOCKS"
assert_lacks "a hung tool never produces a missing-subcommand finding" \
    "$RUN_OUT" "does not have the subcommand"
if command -v pkill >/dev/null 2>&1; then
    pkill -f "sleep 3733" >/dev/null 2>&1 || true
fi

echo
echo "preflight-probe_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
