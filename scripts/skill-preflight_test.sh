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

run_reset() {
    RUN_PATH=""
    RUN_ROOTS_MODE="set"
    RUN_ROOTS="/nonexistent"
    RUN_CWD="$REPO"
    RUN_HOME="${HOME-}"
}

OUT=""
OUT_BYTES=0
RC=0

# run_preflight <root> <skill> [<case-name>]
#
# Captures stdout and stderr together into a file, the way the injected line's
# `2>&1` merges them, so the byte count is over the same string a reader sees.
run_preflight() {
    local root="$1" skill="$2" name="${3-run}"
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
        CLAUDE_PLUGIN_ROOT="$root"
        export CLAUDE_PLUGIN_ROOT
        "$BASH_BIN" "$root/scripts/skill-preflight.sh" "$skill"
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
    "expected exactly one argument"

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

echo
echo "skill-preflight_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
