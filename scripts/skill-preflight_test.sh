#!/usr/bin/env bash
# skill-preflight_test.sh -- test harness for scripts/skill-preflight.sh and the
# two helpers it sources, scripts/lib/preflight-read.sh and
# scripts/lib/preflight-resolve.sh.
#
# Usage: bash scripts/skill-preflight_test.sh
#        /bin/bash scripts/skill-preflight_test.sh     # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# Every case runs the entry point as a separate process against a throwaway
# plugin root built by new_root, with PATH and SHIRABE_PREFLIGHT_ROOTS under the
# test's control. The interpreter used for that inner run is the one running
# this file, so invoking the suite with /bin/bash tests the script on the bash
# 3.2 floor rather than only the harness.
#
# Two properties are asserted mechanically rather than by eye:
#
#   Exit status. run_preflight fails the case itself if the script exits
#   non-zero, on every path, because a non-zero exit from the injected command
#   aborts the whole skill invocation. There is no path where this script may
#   refuse a skill.
#
#   Byte count. The satisfied path is asserted with `wc -c` over a combined
#   stdout-and-stderr capture. "Prints nothing" is otherwise unfalsifiable, and
#   an empty-looking terminal is not evidence.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
ENTRY="$SCRIPT_DIR/skill-preflight.sh"

# The interpreter under test. Resolved to an absolute path because the runs
# below scrub PATH.
BASH_BIN=$(command -v "${PREFLIGHT_TEST_BASH:-${BASH:-bash}}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; ((PASS_COUNT++)) || true; }
fail() { echo -e "${RED}FAIL${NC}: $*"; ((FAIL_COUNT++)) || true; }

TMPS=()
# The expansion is `${arr[@]+"${arr[@]}"}` rather than `"${arr[@]:-}"`, and the
# reason is the suite's own exit status. Every call site takes a directory
# through a command substitution, so the append inside mktmp runs in a subshell
# and this array is empty in the parent. `"${TMPS[@]:-}"` then yields one empty
# element, `[[ -n "" ]]` is false, and the loop -- the last command the EXIT
# trap runs -- returns 1. On bash 3.2 that status becomes the script's, so a
# suite reporting "0 failed" exited 1 anyway, which is a green run reported red
# on every macOS leg.
cleanup() { for d in ${TMPS[@]+"${TMPS[@]}"}; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

mktmp() {
    local d
    d=$(mktemp -d)
    TMPS+=("$d")
    printf '%s' "$d"
}

# new_root -- a throwaway plugin root carrying the real scripts under test.
new_root() {
    local root
    root=$(mktmp)
    mkdir -p "$root/.claude-plugin" "$root/scripts/lib" "$root/skills"
    printf '{"name":"shirabe","version":"0.0.0-test"}\n' >"$root/.claude-plugin/plugin.json"
    cp "$ENTRY" "$root/scripts/skill-preflight.sh"
    cp "$REPO/scripts/lib/preflight-read.sh" "$root/scripts/lib/preflight-read.sh"
    cp "$REPO/scripts/lib/preflight-resolve.sh" "$root/scripts/lib/preflight-resolve.sh"
    cp "$REPO/scripts/lib/tool-routes.tsv" "$root/scripts/lib/tool-routes.tsv"
    printf '%s' "$root"
}

# write_decl <root> <skill> <line>...
#
# Lines are written through `printf '%b'`, so `\t` in an argument becomes a real
# tab. Writing tabs any other way is how a declaration fixture silently stops
# testing the format it claims to.
write_decl() {
    local root="$1" skill="$2"
    shift 2
    mkdir -p "$root/skills/$skill"
    : >"$root/skills/$skill/requires.tsv"
    local line
    for line in "$@"; do
        printf '%b\n' "$line" >>"$root/skills/$skill/requires.tsv"
    done
}

# fake_bin <dir> <name> [marker]
#
# An executable that records the fact it was run, so a case can assert that a
# binary the check refused was never executed.
fake_bin() {
    local dir="$1" name="$2" marker="${3-}"
    mkdir -p "$dir"
    {
        printf '#!/bin/sh\n'
        if [ -n "$marker" ]; then
            printf 'printf ran > %s\n' "$marker"
        fi
        printf 'printf "usage\\n"\n'
    } >"$dir/$name"
    chmod +x "$dir/$name"
}

# Run configuration, reset before each case by run_reset.
RUN_PATH=""
RUN_ROOTS_MODE="set"
RUN_ROOTS=""
RUN_CWD=""

RUN_HOME=""

# The kill switch, SHIRABE_PREFLIGHT_DISABLE. Carried as a mode plus a value
# rather than as one string, because "unset" and "set to the empty string" are
# different inputs to the `case` that reads it and both have to be reachable
# from a case.
RUN_DISABLE_MODE="unset"
RUN_DISABLE=""

run_reset() {
    RUN_PATH=""
    RUN_ROOTS_MODE="set"
    RUN_ROOTS="/nonexistent"
    RUN_CWD="$REPO"
    RUN_HOME="${HOME-}"
    RUN_DISABLE_MODE="unset"
    RUN_DISABLE=""
}

OUT=""
OUT_BYTES=0
RC=0

# run_preflight <root> <skill> [<case-name>] [<extra-arg>...]
#
# Captures stdout and stderr together into a file, the way the injected line's
# `2>&1` merges them, so the byte count is over the same string a reader sees.
#
# Arguments past the case name are appended to the inner invocation verbatim,
# which is how the `--mode <name>` cases reach the entry point. They go through
# the same process boundary as everything else: a mode run is the same script
# with one more pair of arguments, not a second code path a fixture could stub.
run_preflight() {
    local root="$1" skill="$2" name="${3-run}"
    shift 3 2>/dev/null || shift $#
    local capture
    capture=$(mktmp)/capture
    RC=0
    (
        cd "$RUN_CWD" || exit 111
        PATH="$RUN_PATH"
        export PATH
        if [ "$RUN_ROOTS_MODE" = "unset" ]; then
            unset SHIRABE_PREFLIGHT_ROOTS
        else
            SHIRABE_PREFLIGHT_ROOTS="$RUN_ROOTS"
            export SHIRABE_PREFLIGHT_ROOTS
        fi
        HOME="$RUN_HOME"
        export HOME
        if [ "$RUN_DISABLE_MODE" = "unset" ]; then
            unset SHIRABE_PREFLIGHT_DISABLE
        else
            SHIRABE_PREFLIGHT_DISABLE="$RUN_DISABLE"
            export SHIRABE_PREFLIGHT_DISABLE
        fi
        CLAUDE_PLUGIN_ROOT="$root"
        export CLAUDE_PLUGIN_ROOT
        "$BASH_BIN" "$root/scripts/skill-preflight.sh" "$skill" "$@"
    ) >"$capture" 2>&1 || RC=$?
    OUT_BYTES=$(wc -c <"$capture" | tr -d ' ')
    OUT=$(cat "$capture")
    if [ "$RC" -ne 0 ]; then
        fail "$name: the check exited $RC; it must exit 0 on every path"
    fi
}

assert_contains() {
    local name="$1" needle="$2"
    case "$OUT" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name: expected output to contain '$needle'; got: $OUT" ;;
    esac
}

assert_not_contains() {
    local name="$1" needle="$2"
    case "$OUT" in
        *"$needle"*) fail "$name: output must not contain '$needle'; got: $OUT" ;;
        *) pass "$name" ;;
    esac
}

# Report prose is wrapped on word boundaries, so a sentence assertion has to be
# made against the unwrapped text or it tests the wrap width instead of the
# wording. Line structure that carries meaning -- the indented command line, the
# blank line between blocks -- is asserted with the raw form above.
prose() {
    local s
    s=$(printf '%s' "$OUT" | tr '\n\t' '  ')
    while :; do
        case "$s" in
            *'  '*) s="${s//  / }" ;;
            *) break ;;
        esac
    done
    printf '%s' "$s"
}

assert_prose_contains() {
    local name="$1" needle="$2" hay
    hay=$(prose)
    case "$hay" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name: expected unwrapped output to contain '$needle'; got: $OUT" ;;
    esac
}

assert_prose_not_contains() {
    local name="$1" needle="$2" hay
    hay=$(prose)
    case "$hay" in
        *"$needle"*) fail "$name: output must not contain '$needle'; got: $OUT" ;;
        *) pass "$name" ;;
    esac
}

assert_zero_bytes() {
    local name="$1"
    if [ "$OUT_BYTES" -eq 0 ]; then
        pass "$name"
    else
        fail "$name: expected 0 bytes on stdout and stderr combined, got $OUT_BYTES: $OUT"
    fi
}

echo "skill-preflight_test.sh: running under $BASH_BIN ($("$BASH_BIN" -c 'echo $BASH_VERSION'))"
echo

# ---------------------------------------------------------------------------
# preflight_empty_roots_does_not_abort
#
# `IFS=: read -r -a PREFLIGHT_ROOTS <<<""` yields an empty array, and expanding
# "${arr[@]}" on an empty array aborts under `set -u` on bash 3.2. The abort is
# swallowed by the script's own exit-0 discipline and again by the injected
# line's `|| true`, so it looks like success while the report disappears.
#
# Asserting exit 0 is therefore not sufficient. This case asserts the content of
# the absent-tool block, which is the thing an abort would silently delete.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "empty-roots" '#schema\tskill-requires/v1' 'gh\t-\t-\talways'
RUN_ROOTS=""
run_preflight "$ROOT" "empty-roots" "preflight_empty_roots_does_not_abort"
assert_prose_contains "preflight_empty_roots_does_not_abort emits the absent block" \
    "gh is not installed on this host"
assert_prose_contains "preflight_empty_roots_does_not_abort names the skill and posture" \
    "shirabe /empty-roots: prerequisite not met."
assert_prose_contains "preflight_empty_roots_does_not_abort names the declared impact" \
    "/empty-roots declares gh."
# The block above is rendered from inside a command substitution, and a subshell
# that aborts on the same unbound expansion takes its own output with it while
# the parent carries on -- the block still appears and the case still passes.
# The abort message is the only trace, so it gets its own assertion.
assert_prose_not_contains "preflight_empty_roots_does_not_abort leaves no aborted subshell behind" \
    "unbound variable"

# ---------------------------------------------------------------------------
# The satisfied path is zero bytes, over a combined capture.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
BINDIR=$(mktmp)
fake_bin "$BINDIR" "koto"
fake_bin "$BINDIR" "shirabe"
write_decl "$ROOT" "satisfied" \
    '#schema\tskill-requires/v1' \
    'koto\tcontext add\t-\talways' \
    'shirabe\troadmap populate\t--no-issues,--issues\talways'
RUN_PATH="$BINDIR"
run_preflight "$ROOT" "satisfied" "satisfied path"
assert_zero_bytes "a fully satisfied declaration emits zero bytes (wc -c, combined)"

# A two-word subcommand survives the read. Under the default IFS `roadmap
# populate` splits and the record fails the four-field check, which would show
# up here as a malformed-record report rather than silence.
assert_prose_not_contains "a two-word subcommand does not trip the four-field check" \
    "expected exactly 4 tab-separated fields"

# ---------------------------------------------------------------------------
# Off PATH: found under a root, with no install offered.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
TOOLROOT=$(mktmp)
fake_bin "$TOOLROOT" "koto"
write_decl "$ROOT" "offpath" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_ROOTS="$TOOLROOT"
run_preflight "$ROOT" "offpath" "off-PATH"
assert_prose_contains "off-PATH opens by saying nothing needs installing" \
    "prerequisite not met, and nothing needs installing."
assert_contains "off-PATH names the path it was found at" "$TOOLROOT/koto"
assert_prose_contains "off-PATH names the roots it checked" "Checked PATH first, then $TOOLROOT."
assert_contains "off-PATH offers the PATH remedy on its own indented line" \
    "  . ~/.tsuku/env"
assert_prose_contains "off-PATH closes by saying so again" "Do not reinstall koto. It is already here."
assert_not_contains "off-PATH never offers an install command" "tsuku install"

# ---------------------------------------------------------------------------
# The root override governs the absent-versus-off-PATH distinction (R28).
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "absent" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_ROOTS="/nonexistent"
run_preflight "$ROOT" "absent" "absent"
assert_prose_contains "a root list pointing nowhere reports absent" "koto is not installed on this host."
assert_prose_contains "the absent block enumerates the roots it checked" "Checked PATH, then /nonexistent."
assert_prose_not_contains "the absent block is not the off-PATH block" "nothing needs installing"

# Off-PATH sorts ahead of absent, and one block is emitted per tool rather than
# per record: ten koto records must not print ten identical blocks. The failure
# the ordering prevents is an agent that reads top-down and reinstalls a tool it
# already has.
run_reset
ROOT=$(new_root)
TOOLROOT=$(mktmp)
fake_bin "$TOOLROOT" "koto"
write_decl "$ROOT" "ordering" \
    '#schema\tskill-requires/v1' \
    'gh\t-\t-\talways' \
    'koto\tcontext add\t-\talways' \
    'koto\tcontext get\t-\talways' \
    'koto\tversion\t-\talways'
RUN_ROOTS="$TOOLROOT"
run_preflight "$ROOT" "ordering" "block ordering"
FIRST_LINE=$(printf '%s\n' "$OUT" | head -1)
if [ "$FIRST_LINE" = "shirabe /ordering: prerequisite not met, and nothing needs installing." ]; then
    pass "the off-PATH block sorts ahead of the absent block"
else
    fail "the off-PATH block must sort first; the report opened with: $FIRST_LINE"
fi
KOTO_BLOCKS=$(printf '%s\n' "$OUT" | grep -c "Do not reinstall koto" || true)
if [ "$KOTO_BLOCKS" -eq 1 ]; then
    pass "three koto records produce one block, not three"
else
    fail "expected one koto block, got $KOTO_BLOCKS"
fi

# Unset means the documented default list, not an empty one. Pointed at a fake
# HOME, the ~/.tsuku/tools/current entry of that default is what makes the
# off-PATH determination, which is the case a host without tsuku could not
# otherwise exercise.
run_reset
ROOT=$(new_root)
FAKEHOME=$(mktmp)
fake_bin "$FAKEHOME/.tsuku/tools/current" "koto"
write_decl "$ROOT" "defaultroots" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_ROOTS_MODE="unset"
RUN_HOME="$FAKEHOME"
run_preflight "$ROOT" "defaultroots" "default root list"
assert_prose_contains "an unset root list falls back to ~/.tsuku/tools/current and friends" \
    "prerequisite not met, and nothing needs installing."
assert_prose_contains "the default list names the tsuku root first" \
    "Checked PATH first, then $FAKEHOME/.tsuku/tools/current,"
assert_prose_contains "the default list carries the shirabe and local roots" \
    "$FAKEHOME/.shirabe/bin, and $FAKEHOME/.local/bin."

# A root entry that fails the path allowlist is not rendered.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "badroot" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_ROOTS="/tmp/not absolute enough:relative/root"
run_preflight "$ROOT" "badroot" "non-conforming root"
assert_not_contains "a root carrying a space is not rendered into report text" \
    "not absolute enough"
assert_not_contains "a relative root is not rendered into report text" "relative/root"

# ---------------------------------------------------------------------------
# Resolution refused: a binary that resolves under the working directory.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
WORKDIR=$(mktmp)
MARKER="$WORKDIR/it-ran"
fake_bin "$WORKDIR/bin" "koto" "$MARKER"
write_decl "$ROOT" "refused" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_PATH="$WORKDIR/bin"
RUN_CWD="$WORKDIR"
run_preflight "$ROOT" "refused" "resolution refused"
assert_prose_contains "a binary resolving under the working directory is refused" \
    "resolves to a path inside the working directory and was not probed"
assert_prose_contains "the refused block makes no surface claim" \
    "makes no claim about the surface koto advertises"
if [ -e "$MARKER" ]; then
    fail "a refused binary must never be executed, but the marker exists"
else
    pass "a refused binary is never executed"
fi

# ---------------------------------------------------------------------------
# The kill switch, SHIRABE_PREFLIGHT_DISABLE.
#
# The scenario is the one that motivated it: a harness that prepends a fixture
# `bin` directory under the working directory to PATH, so every declared tool
# resolves under $PWD and the resolver correctly refuses it. That is a correct
# refusal and it is not being weakened here -- the case above asserts it still
# fires. What the seam changes is whether the check runs at all.
#
# The pair below is the whole contract: same declaration, same PATH, same
# working directory, one variable apart. Set, the run is zero bytes; unset, the
# run reports. Asserting only the silent half would pass against a script that
# had stopped checking anything.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
WORKDIR=$(mktmp)
MARKER="$WORKDIR/it-ran"
fake_bin "$WORKDIR/bin" "koto" "$MARKER"
write_decl "$ROOT" "killswitch" '#schema\tskill-requires/v1' 'koto\tversion\t-\talways'
RUN_PATH="$WORKDIR/bin"
RUN_CWD="$WORKDIR"
run_preflight "$ROOT" "killswitch" "kill switch unset still reports"
assert_prose_contains "with the seam unset the fixture-bin refusal is reported" \
    "resolves to a path inside the working directory and was not probed"

run_reset
RUN_PATH="$WORKDIR/bin"
RUN_CWD="$WORKDIR"
RUN_DISABLE_MODE="set"
RUN_DISABLE="1"
run_preflight "$ROOT" "killswitch" "kill switch set is silent"
assert_zero_bytes "SHIRABE_PREFLIGHT_DISABLE=1 short-circuits to zero bytes"

# The three values that do NOT disable. `0` and `false` are the spellings an
# operator reaches for to turn the switch back off, and an implementation that
# treated "set to anything" as disabled would silence the check for everyone
# who wrote `SHIRABE_PREFLIGHT_DISABLE=0` believing they had enabled it.
for _off in "0" "false" ""; do
    run_reset
    RUN_PATH="$WORKDIR/bin"
    RUN_CWD="$WORKDIR"
    RUN_DISABLE_MODE="set"
    RUN_DISABLE="$_off"
    run_preflight "$ROOT" "killswitch" "kill switch off-value '$_off'"
    assert_prose_contains "SHIRABE_PREFLIGHT_DISABLE='$_off' does not disable the check" \
        "resolves to a path inside the working directory and was not probed"
done

# An arbitrary truthy value disables too, so the switch is not an exact-match
# `1` test that an operator's `SHIRABE_PREFLIGHT_DISABLE=true` would miss.
run_reset
RUN_PATH="$WORKDIR/bin"
RUN_CWD="$WORKDIR"
RUN_DISABLE_MODE="set"
RUN_DISABLE="true"
run_preflight "$ROOT" "killswitch" "kill switch truthy value"
assert_zero_bytes "SHIRABE_PREFLIGHT_DISABLE=true short-circuits to zero bytes"

# A disabled run never reaches the plugin root, so it cannot emit the
# could-not-locate note either: an invalid root plus the switch is silent, and
# the same invalid root without it speaks. This is what "reads the variable
# before anything is resolved or sourced" means, asserted rather than reviewed.
run_reset
RUN_DISABLE_MODE="set"
RUN_DISABLE="1"
RC=0
DISABLED_CAPTURE=$(mktmp)/disabled
(
    cd "$REPO" || exit 111
    SHIRABE_PREFLIGHT_DISABLE=1
    export SHIRABE_PREFLIGHT_DISABLE
    CLAUDE_PLUGIN_ROOT="relative/root" "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh" "killswitch"
) >"$DISABLED_CAPTURE" 2>&1 || RC=$?
OUT=$(cat "$DISABLED_CAPTURE")
OUT_BYTES=$(wc -c <"$DISABLED_CAPTURE" | tr -d ' ')
if [ "$RC" -ne 0 ]; then
    fail "kill switch with an invalid root: the check exited $RC; it must exit 0 on every path"
fi
assert_zero_bytes "the kill switch is read before the plugin root is resolved"

# ---------------------------------------------------------------------------
# Malformed records are skipped and reported, with the line number and field.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "malformed" \
    '#schema\tskill-requires/v1' \
    '# a comment, which is a legal line kind' \
    'koto\tversion\t-' \
    '' \
    'koto\t-\t-\tsometimes' \
    'gh\t-\t-\talways'
RUN_ROOTS="/nonexistent"
run_preflight "$ROOT" "malformed" "malformed records"
assert_contains "a three-field record is reported with its line number" \
    "skipping requires.tsv line 3: expected exactly 4 tab-separated fields (3 tabs), found 3."
assert_contains "a bad fourth field is reported with its line number and field" \
    "skipping requires.tsv line 5, field 4 (when): expected \`always\` or \`mode:<name>\`"
assert_prose_contains "a skipped record does not stop the records after it" \
    "gh is not installed on this host."

# The rejected value itself is never echoed back into the report.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "dashfields" \
    '#schema\tskill-requires/v1' \
    '-rf\t-\t-\talways' \
    'koto\t--version\t-\talways'
run_preflight "$ROOT" "dashfields" "leading-dash rejection"
assert_contains "a leading dash in field one is rejected" \
    "line 2, field 1 (tool): expected [A-Za-z0-9._-]+ with no leading dash."
assert_contains "a leading dash in field two is rejected" \
    "line 3, field 2 (subcommand): expected \`-\` or space-separated tokens"
assert_not_contains "a rejected field value is not echoed into the report" "--version"
assert_not_contains "a rejected field value is not echoed into the report (field one)" "-rf"

# ---------------------------------------------------------------------------
# Field one is checked against the route table's tool column.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "unrouted" '#schema\tskill-requires/v1' 'curl\t-\t-\talways'
run_preflight "$ROOT" "unrouted" "unrouted tool"
assert_contains "a tool absent from tool-routes.tsv is rejected by the script, not only by CI" \
    "does not appear in scripts/lib/tool-routes.tsv"
assert_prose_not_contains "an unrouted tool is never resolved or reported as absent" \
    "is not installed on this host"

# ---------------------------------------------------------------------------
# The schema line is required, must be first, and its version is literal.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "badschema" '#schema\tskill-requires/v2' 'gh\t-\t-\talways'
run_preflight "$ROOT" "badschema" "wrong schema version"
assert_contains "a wrong schema version is a hard error naming the skill" \
    "shirabe /badschema: requires.tsv does not open with"
assert_prose_not_contains "a wrong schema version reads no record" "is not installed on this host"

run_reset
ROOT=$(new_root)
write_decl "$ROOT" "lateschema" 'gh\t-\t-\talways' '#schema\tskill-requires/v1'
run_preflight "$ROOT" "lateschema" "schema line not first"
assert_contains "a schema line that is not first is a hard error" \
    "shirabe /lateschema: requires.tsv does not open with"

# ---------------------------------------------------------------------------
# Silence where silence is the contract.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "emptydecl" '#schema\tskill-requires/v1'
run_preflight "$ROOT" "emptydecl" "explicit empty declaration"
assert_zero_bytes "a declaration carrying only the schema line emits nothing"

run_reset
ROOT=$(new_root)
run_preflight "$ROOT" "nosidecar" "absent sidecar"
assert_zero_bytes "an absent sidecar emits nothing and exits 0"

run_reset
ROOT=$(new_root)
write_decl "$ROOT" "modeonly" \
    '#schema\tskill-requires/v1' \
    'gh\t-\t-\tmode:issues'
run_preflight "$ROOT" "modeonly" "mode-scoped records"
assert_zero_bytes "a mode-scoped record emits nothing at load, not even a deferral marker"

# ---------------------------------------------------------------------------
# The mode entry point
#
# R11. The load-time run defers a `mode:` record; this is where the record is
# actually verified. Every case below runs the same script with two more
# arguments -- there is no second entry point and no fixture standing in for
# one.
# ---------------------------------------------------------------------------

# The same declaration, the same absent tool, seen from both sides. This is the
# pair that makes R10 and R11 falsifiable together: silence at load is only
# honest if the record is checked somewhere, and a `--mode` report is only
# meaningful if the load stayed quiet about the same record.
run_reset
ROOT=$(new_root)
BINDIR=$(mktmp)
fake_bin "$BINDIR" "shirabe"
write_decl "$ROOT" "twosided" \
    '#schema\tskill-requires/v1' \
    'shirabe\ttransition\t-\talways' \
    'gh\t-\t-\tmode:issues'
RUN_PATH="$BINDIR"
run_preflight "$ROOT" "twosided" "load with gh absent"
assert_zero_bytes "a load says nothing about a mode record even with that tool absent"

run_preflight "$ROOT" "twosided" "--mode issues with gh absent" --mode issues
assert_prose_contains "the mode run reports the deferred record" \
    "gh is not installed on this host."
assert_prose_contains "the mode run names the skill and posture" \
    "shirabe /twosided: prerequisite not met."
assert_prose_contains "the mode run names the declared impact" "/twosided declares gh."

# The always records were evaluated at load. Re-reporting them mid-workflow
# would put a second copy of an already-seen block in front of the model, which
# is the same dedup argument the zero-byte rule rests on.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "noreplay" \
    '#schema\tskill-requires/v1' \
    'koto\tversion\t-\talways' \
    'gh\t-\t-\tmode:issues'
RUN_ROOTS="/nonexistent"
run_preflight "$ROOT" "noreplay" "--mode does not replay always records" --mode issues
assert_prose_contains "the mode run reports its own record" "gh is not installed on this host."
assert_prose_not_contains "the mode run does not re-report an unsatisfied always record" \
    "koto is not installed on this host"

# Zero bytes when every matching record is satisfied, asserted with wc -c for
# the same reason the load-time rule is.
run_reset
ROOT=$(new_root)
BINDIR=$(mktmp)
fake_bin "$BINDIR" "gh"
write_decl "$ROOT" "modesat" \
    '#schema\tskill-requires/v1' \
    'gh\t-\t-\tmode:issues'
RUN_PATH="$BINDIR"
run_preflight "$ROOT" "modesat" "satisfied mode run" --mode issues
assert_zero_bytes "a satisfied mode run emits zero bytes (wc -c, combined)"

# One mode's records are not another's.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "twomodes" \
    '#schema\tskill-requires/v1' \
    'gh\t-\t-\tmode:issues' \
    'jq\t-\t-\tmode:coordinated'
RUN_ROOTS="/nonexistent"
run_preflight "$ROOT" "twomodes" "one mode at a time" --mode coordinated
assert_prose_contains "the named mode's record is evaluated" "jq is not installed on this host."
assert_prose_not_contains "another mode's record is not" "gh is not installed on this host"

# An unknown mode, and a declaration with no mode record at all, are silent and
# exit 0. Neither is a finding this check can make: an unknown mode name is
# indistinguishable here from a mode whose records are all satisfied, and the
# scan that can tell them apart is scripts/check-skill-requires.sh.
run_preflight "$ROOT" "twomodes" "unknown mode name" --mode nosuchmode
assert_zero_bytes "an unknown mode name emits nothing and exits 0"

run_reset
ROOT=$(new_root)
write_decl "$ROOT" "allalways" \
    '#schema\tskill-requires/v1' \
    'gh\t-\t-\talways'
RUN_ROOTS="/nonexistent"
run_preflight "$ROOT" "allalways" "mode run against an all-always declaration" --mode multi-pr
assert_zero_bytes "a mode with no matching record emits nothing and exits 0"

# The off-PATH posture, and therefore the whole block-shape set, is shared. The
# mode run is the same renderer with a different filter.
run_reset
ROOT=$(new_root)
TOOLROOT=$(mktmp)
fake_bin "$TOOLROOT" "koto"
write_decl "$ROOT" "modeoffpath" \
    '#schema\tskill-requires/v1' \
    'koto\tversion\t-\tmode:coordinated'
RUN_ROOTS="$TOOLROOT"
run_preflight "$ROOT" "modeoffpath" "off-PATH under --mode" --mode coordinated
assert_prose_contains "a mode run renders the off-PATH block unchanged" \
    "prerequisite not met, and nothing needs installing."
assert_prose_contains "a mode run's off-PATH block still refuses to offer an install" \
    "Do not reinstall koto. It is already here."

# Argument shapes. A malformed mode name is a malformed invocation and is
# reported as one; that is a different thing from an unknown mode, which is
# silent, and the two must not collapse into each other.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "modeargs" '#schema\tskill-requires/v1' 'gh\t-\t-\tmode:issues'
run_preflight "$ROOT" "modeargs" "path-shaped mode name" --mode ../etc
assert_contains "a mode name outside [a-z0-9-]+ is refused" \
    "the mode name must match [a-z0-9-]+"
assert_not_contains "a refused mode name is not echoed into the report" "../etc"

run_preflight "$ROOT" "modeargs" "wrong second argument" --node issues
assert_contains "a second argument other than --mode is refused" \
    "the only second argument is \`--mode\`"

run_preflight "$ROOT" "modeargs" "dangling --mode" --mode
assert_contains "a --mode with no value is refused, not fatal" \
    "expected a skill name, optionally followed by"

# ---------------------------------------------------------------------------
# The real tree: /roadmap's mode:issues records, from both sides.
#
# skills/roadmap/requires.tsv is the first consumer of the mode entry point, so
# the committed declaration is exercised rather than only a fixture. PATH is
# scrubbed and the root list points nowhere, so `gh` is genuinely unresolvable
# for the duration of both runs.
# ---------------------------------------------------------------------------
run_reset
RC=0
ROADMAP_LOAD=$(mktmp)/roadmap-load
(
    cd "$REPO" || exit 111
    PATH=""
    export PATH
    SHIRABE_PREFLIGHT_ROOTS="/nonexistent"
    export SHIRABE_PREFLIGHT_ROOTS
    CLAUDE_PLUGIN_ROOT="$REPO" "$BASH_BIN" "$REPO/scripts/skill-preflight.sh" "roadmap"
) >"$ROADMAP_LOAD" 2>&1 || RC=$?
OUT=$(cat "$ROADMAP_LOAD")
OUT_BYTES=$(wc -c <"$ROADMAP_LOAD" | tr -d ' ')
if [ "$RC" -ne 0 ]; then
    fail "roadmap load: the check exited $RC; it must exit 0 on every path"
fi
assert_prose_not_contains "a /roadmap load says nothing about gh, which it declares mode:issues" \
    "gh is not installed on this host"

RC=0
ROADMAP_MODE=$(mktmp)/roadmap-mode
(
    cd "$REPO" || exit 111
    PATH=""
    export PATH
    SHIRABE_PREFLIGHT_ROOTS="/nonexistent"
    export SHIRABE_PREFLIGHT_ROOTS
    CLAUDE_PLUGIN_ROOT="$REPO" "$BASH_BIN" "$REPO/scripts/skill-preflight.sh" "roadmap" --mode issues
) >"$ROADMAP_MODE" 2>&1 || RC=$?
OUT=$(cat "$ROADMAP_MODE")
if [ "$RC" -ne 0 ]; then
    fail "roadmap --mode issues: the check exited $RC; it must exit 0 on every path"
fi
assert_prose_contains "/roadmap --mode issues reports the gh the load deferred" \
    "gh is not installed on this host."

# ---------------------------------------------------------------------------
# Plugin root validation runs before anything is sourced.
# ---------------------------------------------------------------------------
run_reset
BADROOT=$(mktmp)
mkdir -p "$BADROOT/scripts/lib"
cp "$ENTRY" "$BADROOT/scripts/skill-preflight.sh"
printf 'echo SOURCED-A-LIB\n' >"$BADROOT/scripts/lib/preflight-read.sh"
printf 'echo SOURCED-A-LIB\n' >"$BADROOT/scripts/lib/preflight-resolve.sh"
run_preflight "$BADROOT" "anything" "root without plugin.json"
assert_contains "a root with no plugin.json reports that it could not locate the plugin root" \
    "could not locate the plugin root"
assert_not_contains "a root that fails validation sources nothing" "SOURCED-A-LIB"

run_reset
ROOT=$(new_root)
RELROOT="scripts"
OUT_CAPTURE=$(mktmp)/relative
RC=0
(
    cd "$REPO" || exit 111
    PATH=""
    export PATH
    CLAUDE_PLUGIN_ROOT="$RELROOT"
    export CLAUDE_PLUGIN_ROOT
    SHIRABE_PREFLIGHT_ROOTS=""
    export SHIRABE_PREFLIGHT_ROOTS
    "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh" "anything"
) >"$OUT_CAPTURE" 2>&1 || RC=$?
OUT=$(cat "$OUT_CAPTURE")
OUT_BYTES=$(wc -c <"$OUT_CAPTURE" | tr -d ' ')
if [ "$RC" -ne 0 ]; then
    fail "relative plugin root: the check exited $RC; it must exit 0 on every path"
fi
assert_contains "a relative plugin root is refused before anything is sourced" \
    "could not locate the plugin root"

# ---------------------------------------------------------------------------
# The route table itself.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
rm -f "$ROOT/scripts/lib/tool-routes.tsv"
write_decl "$ROOT" "noroutes" '#schema\tskill-requires/v1' 'gh\t-\t-\talways'
run_preflight "$ROOT" "noroutes" "missing route table"
assert_contains "a missing route table is reported once, not once per record" \
    "scripts/lib/tool-routes.tsv is missing"

run_reset
ROOT=$(new_root)
{
    printf '#schema\ttool-routes/v1\n'
    printf 'gh\ttsuku\tlinux\tnever\t-\t-\n'
    printf 'gh\thomebrew\tdarwin\tbrew -\tbrew install gh\t-\n'
} >"$ROOT/scripts/lib/tool-routes.tsv"
write_decl "$ROOT" "badroute" '#schema\tskill-requires/v1' 'gh\t-\t-\talways'
run_preflight "$ROOT" "badroute" "never route without a citation"
assert_contains "a never route with no citation is skipped and reported" \
    "tool-routes.tsv line 2, field 6 (citation): mandatory and non-dash"
assert_prose_contains "the remaining route record still supplies the tool name" \
    "gh is not installed on this host."

# The shipped seed parses and carries the documented exclusion.
run_reset
ROOT=$(new_root)
write_decl "$ROOT" "seed" '#schema\tskill-requires/v1' 'shirabe\ttransition\t-\talways'
run_preflight "$ROOT" "seed" "shipped route table"
assert_not_contains "the shipped tool-routes.tsv parses without a skip report" \
    "skipping tool-routes.tsv"

# ---------------------------------------------------------------------------
# Argument handling.
# ---------------------------------------------------------------------------
run_reset
ROOT=$(new_root)
RC=0
ARG_CAPTURE=$(mktmp)/args
(
    cd "$REPO" || exit 111
    CLAUDE_PLUGIN_ROOT="$ROOT" "$BASH_BIN" "$ROOT/scripts/skill-preflight.sh"
) >"$ARG_CAPTURE" 2>&1 || RC=$?
OUT=$(cat "$ARG_CAPTURE")
if [ "$RC" -ne 0 ]; then
    fail "no argument: the check exited $RC; it must exit 0 on every path"
fi
assert_contains "invoking with no skill name is reported, not fatal" \
    "expected a skill name, optionally followed by"

run_reset
ROOT=$(new_root)
run_preflight "$ROOT" "../etc" "path-shaped skill name"
assert_contains "a skill name outside [a-z0-9-]+ is refused" \
    "the skill name must match [a-z0-9-]+"

# ---------------------------------------------------------------------------
# The real tree: the entry point runs against this checkout without speaking.
# ---------------------------------------------------------------------------
run_reset
RC=0
REAL_CAPTURE=$(mktmp)/real
(
    cd "$REPO" || exit 111
    CLAUDE_PLUGIN_ROOT="$REPO" "$BASH_BIN" "$REPO/scripts/skill-preflight.sh" "decision"
) >"$REAL_CAPTURE" 2>&1 || RC=$?
OUT=$(cat "$REAL_CAPTURE")
OUT_BYTES=$(wc -c <"$REAL_CAPTURE" | tr -d ' ')
if [ "$RC" -ne 0 ]; then
    fail "real checkout: the check exited $RC; it must exit 0 on every path"
fi
assert_zero_bytes "the entry point is silent against this checkout"

# ---------------------------------------------------------------------------
# The injection path, not the script.
#
# Every case above invokes the entry point directly. None of them would notice
# if the text inside a skill's `!`-prefixed line stopped working: a typo in the
# path, a lost `2>&1`, an unexpanded ${CLAUDE_PLUGIN_ROOT}, all give the same
# zero bytes a satisfied host gives, and the `|| true` swallows the 127.
#
# So these cases take the line out of a SKILL.md and run it. The fixture plugin
# under skills/inflight/evals/fixtures/preflight-liveness carries two skills
# whose bodies open with the canonical injected line -- one declaring a tool no
# host ships, one declaring `sh` -- and its scripts/ is symlinked into this
# tree, so the line under test resolves to the code under test.
#
# This is the deterministic half of the liveness check and it runs on every
# pull request. The other half is the eval in skills/inflight/evals/evals.json,
# which loads the same fixture through a real skill invocation and asserts the
# report reaches a model; that one needs an API key and runs on the eval
# schedule. Neither replaces the other: this suite proves the line executes,
# the eval proves the model receives what it printed.
# ---------------------------------------------------------------------------

LIVENESS_ROOT="$REPO/skills/inflight/evals/fixtures/preflight-liveness"

# extract_injected_line <skill-md>
#
# Prints the command inside the file's first `!`...`` line: the text the
# harness runs, taken from the file rather than retyped here. A test that
# retyped it would pass against a SKILL.md whose line had rotted.
extract_injected_line() {
    local file="$1" line body
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '!`'*)
                body="${line#!\`}"
                printf '%s' "${body%%\`*}"
                return 0
                ;;
        esac
    done <"$file"
    return 1
}

# run_injected <root> <command> <case-name> [<disable-value>]
#
# Runs the extracted line through `eval`, which is how the harness runs it: it
# is a shell command line, complete with the `2>&1` and the `|| true`, not an
# argv the test assembles.
run_injected() {
    local root="$1" cmd="$2" name="$3" disable="${4-}"
    local capture
    capture=$(mktmp)/injected
    RC=0
    (
        cd "$REPO" || exit 111
        CLAUDE_PLUGIN_ROOT="$root"
        export CLAUDE_PLUGIN_ROOT
        if [ -n "$disable" ]; then
            SHIRABE_PREFLIGHT_DISABLE="$disable"
            export SHIRABE_PREFLIGHT_DISABLE
        else
            unset SHIRABE_PREFLIGHT_DISABLE
        fi
        eval "$cmd"
    ) >"$capture" 2>&1 || RC=$?
    OUT_BYTES=$(wc -c <"$capture" | tr -d ' ')
    OUT=$(cat "$capture")
    if [ "$RC" -ne 0 ]; then
        fail "$name: the injected line exited $RC; it must exit 0 on every path"
    fi
}

if [ ! -d "$LIVENESS_ROOT" ]; then
    fail "the liveness fixture is missing from $LIVENESS_ROOT"
else
    UNSAT_MD="$LIVENESS_ROOT/skills/preflight-liveness-unsat/SKILL.md"
    SAT_MD="$LIVENESS_ROOT/skills/preflight-liveness-sat/SKILL.md"

    UNSAT_CMD=$(extract_injected_line "$UNSAT_MD") || UNSAT_CMD=""
    SAT_CMD=$(extract_injected_line "$SAT_MD") || SAT_CMD=""

    # The shape is asserted before the behaviour. A fixture whose line had
    # drifted from the twenty shipped ones would still be a live injection, and
    # it would stop being evidence about them.
    if [ "$UNSAT_CMD" = 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh preflight-liveness-unsat 2>&1 || true' ]; then
        pass "the unsatisfiable fixture carries the canonical injected line"
    else
        fail "the unsatisfiable fixture's injected line has drifted: $UNSAT_CMD"
    fi
    if [ "$SAT_CMD" = 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh preflight-liveness-sat 2>&1 || true' ]; then
        pass "the satisfied fixture carries the canonical injected line"
    else
        fail "the satisfied fixture's injected line has drifted: $SAT_CMD"
    fi

    # The liveness assertion. A non-empty report here is the one signal that
    # separates "the check ran and found nothing" from "the check never ran".
    run_injected "$LIVENESS_ROOT" "$UNSAT_CMD" "unsatisfiable fixture through the injected line"
    if [ "$OUT_BYTES" -gt 0 ]; then
        pass "the injected line produces a non-empty report for an unsatisfiable declaration"
    else
        fail "the injected line produced 0 bytes for an unsatisfiable declaration; the injection path is dead"
    fi
    assert_prose_contains "the injected line's report names the fixture skill" \
        "shirabe /preflight-liveness-unsat: prerequisite not met."
    assert_prose_contains "the injected line's report names the undeclarable tool" \
        "preflight-absent-tool is not installed on this host."

    # The control. Same plugin, same line, a declaration every host meets.
    run_injected "$LIVENESS_ROOT" "$SAT_CMD" "satisfied fixture through the injected line"
    assert_zero_bytes "the injected line is silent for a satisfied declaration"

    # The kill switch reaches the injection path too, which is why the eval
    # that owns the liveness assertion must run with it cleared. Asserting it
    # here keeps that requirement from living only in a comment.
    run_injected "$LIVENESS_ROOT" "$UNSAT_CMD" "unsatisfiable fixture with the kill switch set" "1"
    assert_zero_bytes "SHIRABE_PREFLIGHT_DISABLE=1 silences the injected line as well"
fi

echo
echo "skill-preflight_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
