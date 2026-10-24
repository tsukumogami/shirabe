#!/usr/bin/env bash
# record-store_test.sh -- scripts/lib/record-store.sh, the one file that knows
# the run record's shared address and koto's read-only --workspace option.
#
# Every case runs against the stand-in koto, scripts/testdata/record-koto/koto,
# which keys a session by workspace the way koto's cloud backend does and
# models koto#455's option in both its modes:
#
#   names        the index name and the shared directory, lowercased; owners,
#                repositories and numbers outside their grammar refused
#   writes       run koto from the directory, creating it first; never pass
#                --workspace, and refuse a caller that tries
#   the probe    reads koto's help once per process, whatever the read count
#   reads        option absent: from the addressed directory, no --workspace
#                anywhere, 69 for a directory that isn't here; option present:
#                --workspace=<dir> after the verb words, from any directory;
#                a session the addressed workspace doesn't hold is "not
#                found" (68, nothing printed), and any other failure passes
#                koto's exit and output through
#   the patterns the session and step patterns, their bounds included
#   moved names a root's candidates (<name>, then _r1 to _r10, each within
#                the session pattern), and a name renamed by koto's
#                move-aside rule: the root and its `.` children take the new
#                prefix, anything else keeps its name, and a result outside
#                the pattern is refused
#   the forms    a write from the shared directory lands at one of the two
#                forms a reader tries
#   plan roots   plan.<owner>.<repo>.<topic>.<sha12>, lowercased; every part
#                outside its pattern refused; the owner decoded back from a
#                plan root's name, and nothing from any other name
#   the override SHIRABE_RUN_RECORD_TEST_ROOT moves the shared root; unset,
#                it is /tmp/shirabe-run-record; a relative value, a `..`
#                component or a control character makes the address refuse
#   no real dir  every suite that writes through record-store.sh sets the
#                override (a scan of the suites), and this suite leaves the
#                real /tmp/shirabe-run-record as it found it (a listing before
#                and after)
#
# The shared address is a directory under this suite's temp directory,
# through the test-only override; only the default-value cases read the real
# path, and they write nothing. Before the first case the suite checks that
# the koto on PATH is the stand-in, and stops when it isn't.
#
# Usage: record-store_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
LIB="$SCRIPT_DIR/lib/record-store.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/record-store-test.XXXXXX") || exit 1
WORK=$(cd "$WORK" && pwd -P) || exit 1
OWNER="rstest-$$-$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
trap 'rm -rf "$WORK"' EXIT
REAL_ROOT=/tmp/shirabe-run-record
# real_listing: the real shared root's entries, or a line saying it is absent.
real_listing() {
    if [ -d "$REAL_ROOT" ]; then
        ls -A "$REAL_ROOT"
    else
        echo "absent"
    fi
}
REAL_BEFORE=$(real_listing)
SHARED="$WORK/shared"
export SHIRABE_RUN_RECORD_TEST_ROOT="$SHARED"
export PATH="$STUB_DIR:$PATH"
export RECORD_KOTO_STORE="$WORK/store"
mkdir -p "$WORK/a" "$WORK/b"
TAB=$(printf '\t')

# The koto on PATH must be the stand-in: these cases write sessions, and a
# real koto would write them to a real store.
if [ "$(command -v koto)" != "$STUB_DIR/koto" ] \
    || [ "$(RECORD_KOTO_STORE="$WORK/stub-probe" koto version </dev/null)" != "koto 0.0.0-record-stub" ]; then
    echo "FAIL: the koto on PATH is not the stand-in at $STUB_DIR/koto; no case ran" >&2
    exit 1
fi

# lib <shell commands>: run them in a fresh bash that sourced the library,
# so each case starts with the probe unset.
lib() {
    OUT=$(bash -c '. "$1"; shift; eval "$1"' lib "$LIB" "$1" </dev/null 2>"$WORK/stderr")
    RC=$?
}
# lib_root <value|-> <shell commands>: lib with the override set to the value
# as the library is sourced, or unset with `-`. Only for cases that write
# nothing.
lib_root() {
    if [ "$1" = - ]; then
        OUT=$(bash -c 'unset SHIRABE_RUN_RECORD_TEST_ROOT; . "$1"; shift; eval "$1"' lib "$LIB" "$2" </dev/null 2>"$WORK/stderr")
    else
        OUT=$(SHIRABE_RUN_RECORD_TEST_ROOT=$1 bash -c '. "$1"; shift; eval "$1"' lib "$LIB" "$2" </dev/null 2>"$WORK/stderr")
    fi
    RC=$?
}
calls() { [ -f "$RECORD_KOTO_STORE/calls.log" ] && cat "$RECORD_KOTO_STORE/calls.log"; }
reset_store() { rm -rf "$RECORD_KOTO_STORE"; mkdir -p "$RECORD_KOTO_STORE"; }

# --- names ------------------------------------------------------------------------

lib 'rs_index_name Octo-Cat/My.Repo_1 42'
[ "$RC" -eq 0 ] && [ "$OUT" = "pr.octo-cat.my.repo_1.42" ] \
    && pass "the index name is pr.<owner>.<repo>.<n>, lowercased" \
    || fail "index name: exit $RC, [$OUT]"

for bad in "-o/r 1" "o-/r 1" "o--x/r 1" "o/.. 1" "o/. 1" "o/r 0" "o/r 01" "o/r abc" "o/r/x 1" "o/r%x 1"; do
    lib "rs_index_name $bad"
    [ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "rs_index_name refuses [$bad]" \
        || fail "rs_index_name [$bad]: exit $RC, [$OUT]"
done

lib_root - 'rs_shared_dir Octo'
[ "$OUT" = "/tmp/shirabe-run-record/octo" ] && pass "the shared directory is /tmp/shirabe-run-record/<owner>, lowercased" \
    || fail "shared dir: [$OUT]"
lib_root - 'rs_shared_forms Octo'
[ "$OUT" = "$(printf '/tmp/shirabe-run-record/octo\n/private/tmp/shirabe-run-record/octo')" ] \
    && pass "a reader tries the /tmp form, then the /private/tmp form" \
    || fail "forms: [$OUT]"
lib 'rs_shared_dir ../x'
[ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "rs_shared_dir refuses an owner outside the grammar" \
    || fail "shared dir of ../x: exit $RC, [$OUT]"

# --- the override ---------------------------------------------------------------

lib 'rs_shared_dir Octo'
[ "$RC" -eq 0 ] && [ "$OUT" = "$SHARED/octo" ] \
    && pass "with SHIRABE_RUN_RECORD_TEST_ROOT set, the shared directory is <root>/<owner>" \
    || fail "override shared dir: exit $RC, [$OUT]"
lib 'rs_shared_forms Octo'
[ "$RC" -eq 0 ] && [ "$(sed -n 1p <<<"$OUT")" = "$SHARED/octo" ] \
    && pass "with the override, a reader tries the override's directory first" \
    || fail "override forms: exit $RC, [$OUT]"
for bad in "rel/root" "/a/../b" "/a/.."; do
    lib_root "$bad" 'rs_shared_dir octo'
    [ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "an override of [$bad] makes the shared address refuse (64)" \
        || fail "override [$bad]: exit $RC, [$OUT]"
    lib_root "$bad" 'rs_shared_forms octo'
    [ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "an override of [$bad] makes the forms refuse (64)" \
        || fail "override forms [$bad]: exit $RC, [$OUT]"
done
lib_root "$(printf '/a\nb')" 'rs_shared_dir octo'
[ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "an override holding a newline makes the shared address refuse (64)" \
    || fail "newline override: exit $RC, [$OUT]"

# --- plan roots -------------------------------------------------------------------

lib 'rs_plan_root_name Octo-Cat/My.Repo_1 plan-x 0123456789ab'
[ "$RC" -eq 0 ] && [ "$OUT" = "plan.octo-cat.my.repo_1.plan-x.0123456789ab" ] \
    && pass "a plan root is plan.<owner>.<repo>.<topic>.<sha12>, lowercased" \
    || fail "plan root name: exit $RC, [$OUT]"
for bad in "-o/r t 0123456789ab" "o/.. t 0123456789ab" "o/r T 0123456789ab" "o/r t.x 0123456789ab" \
           "o/r t 0123456789a" "o/r t 0123456789abc" "o/r t 0123456789AB" "o/r t xyz456789abc"; do
    lib "rs_plan_root_name $bad"
    [ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "rs_plan_root_name refuses [$bad]" \
        || fail "rs_plan_root_name [$bad]: exit $RC, [$OUT]"
done
LONG_TOPIC=$(printf 't%.0s' $(seq 1 100))
LONG_REPO=$(printf 'r%.0s' $(seq 1 90))
lib "rs_plan_root_name o/$LONG_REPO $LONG_TOPIC 0123456789ab"
[ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "a plan root name past the session pattern's 200 characters is refused" \
    || fail "long plan root: exit $RC, [${OUT:0:40}]"
lib 'rs_plan_root_owner plan.octo-cat.my.repo_1.plan-x.0123456789ab'
[ "$RC" -eq 0 ] && [ "$OUT" = octo-cat ] && pass "a plan root's name decodes to its owner" \
    || fail "plan root owner: exit $RC, [$OUT]"
lib 'rs_plan_root_topic plan.octo-cat.my.repo_1.plan-x.0123456789ab'
[ "$RC" -eq 0 ] && [ "$OUT" = plan-x ] && pass "a plan root's name decodes to its topic" \
    || fail "plan root topic: exit $RC, [$OUT]"
lib 'rs_plan_root_topic execute-plan-x'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && pass "a name that isn't a plan root's has no topic (1)" \
    || fail "topic of execute-plan-x: exit $RC, [$OUT]"
for bad in execute-plan-x pr.o.r.7 plan.o.r.t plan.o.r.t.0123456789abc plan.o.r.T.0123456789ab "plan..r.t.0123456789ab"; do
    lib "rs_plan_root_owner '$bad'"
    [ "$RC" -eq 1 ] && [ -z "$OUT" ] && pass "[$bad] is not a plan root's name (1)" \
        || fail "rs_plan_root_owner [$bad]: exit $RC, [$OUT]"
done

for ws in "/a/b" "/a b/c+d@e"; do
    lib "rs_valid_workspace '$ws'"
    [ "$RC" -eq 0 ] && pass "workspace [$ws] is recordable" || fail "workspace [$ws] refused"
done
for ws in "rel/path" "/a/../b" "/a/.." ""; do
    lib "rs_valid_workspace '$ws'"
    [ "$RC" -ne 0 ] && pass "workspace [$ws] is refused" || fail "workspace [$ws] accepted"
done
lib "rs_valid_workspace \"\$(printf '/a\nb')\""
[ "$RC" -ne 0 ] && pass "a workspace holding a newline is refused" || fail "newline workspace accepted"

# --- writes -----------------------------------------------------------------------

reset_store
DIR="$SHARED/$OWNER"
lib "rs_koto_write '$DIR' init pr.$OWNER.r.1 --template t --attach-live >/dev/null && printf '{}' | rs_koto_write '$DIR' context add pr.$OWNER.r.1 run/x"
CANON=$(cd "$DIR" 2>/dev/null && pwd -P)
if [ "$RC" -eq 0 ] && [ -n "$CANON" ] \
    && [ "$(cut -f1 "$RECORD_KOTO_STORE/calls.log" | LC_ALL=C sort -u)" = "$CANON" ]; then
    pass "a write creates the shared directory and runs koto from it"
else
    fail "write: exit $RC, calls [$(calls)]"
fi
if ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "no write passes --workspace"
else
    fail "a write passed --workspace: [$(calls)]"
fi

reset_store
lib "rs_koto_write '$DIR' context add s k --workspace=/x"
[ "$RC" -eq 64 ] && [ ! -s "$RECORD_KOTO_STORE/calls.log" ] \
    && pass "rs_koto_write refuses a --workspace argument before any koto call" \
    || fail "write with --workspace: exit $RC, calls [$(calls)]"

# The stand-in's contract, which the suites lean on: with the option present
# a write given it is refused, and with it absent any use is.
reset_store
(cd "$WORK/a" && RECORD_KOTO_WORKSPACE_OPTION=present koto init s --template t --workspace=/x >/dev/null 2>"$WORK/stderr")
RC=$?
[ "$RC" -eq 2 ] && grep -q 'workspace' "$WORK/stderr" \
    && pass "the stub, option present: a write given --workspace is refused, naming the option" \
    || fail "stub present-mode write: exit $RC [$(cat "$WORK/stderr")]"
(cd "$WORK/a" && koto context list s --workspace=/x >/dev/null 2>"$WORK/stderr")
RC=$?
[ "$RC" -eq 2 ] && pass "the stub, option absent: --workspace is an unknown argument" \
    || fail "stub absent-mode read: exit $RC"

# --- reads ------------------------------------------------------------------------

reset_store
(cd "$WORK/a" && koto init root --template t >/dev/null && printf 'v' | koto context add root k)
A=$(cd "$WORK/a" && pwd -P)

: > "$RECORD_KOTO_STORE/calls.log"
lib "cd '$WORK/b' && rs_koto_read '$A' context get root k && rs_koto_read '$A' context list root"
if [ "$RC" -eq 0 ] && [ "$OUT" = 'v["k"]' ] \
    && [ "$(grep -v -- '--help' "$RECORD_KOTO_STORE/calls.log" | grep -c "${TAB}context ")" -eq 2 ] \
    && [ "$(grep -v -- '--help' "$RECORD_KOTO_STORE/calls.log" | cut -f1 | LC_ALL=C sort -u)" = "$A" ] \
    && ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "option absent: a read from elsewhere runs from the addressed directory, no --workspace"
else
    fail "absent-mode read: exit $RC, out [$OUT], calls [$(calls)]"
fi
if [ "$(grep -c -- '--help' "$RECORD_KOTO_STORE/calls.log")" -eq 1 ]; then
    pass "the option is probed once per process, from koto's help"
else
    fail "probe count: [$(calls)]"
fi

lib "rs_koto_read '$WORK/nowhere' context get root k"
[ "$RC" -eq 69 ] && pass "option absent: a directory that isn't here is 69" || fail "missing dir: exit $RC"

: > "$RECORD_KOTO_STORE/calls.log"
export RECORD_KOTO_WORKSPACE_OPTION=present
lib "cd '$WORK/b' && rs_koto_read '$A' context get root k && rs_koto_read '$A' status root >/dev/null"
B=$(cd "$WORK/b" && pwd -P)
if [ "$RC" -eq 0 ] && [ "$OUT" = 'v' ] \
    && grep -qF "$(printf '%s\tcontext get --workspace=%s root k' "$B" "$A")" "$RECORD_KOTO_STORE/calls.log" \
    && grep -qF "$(printf '%s\tstatus --workspace=%s root' "$B" "$A")" "$RECORD_KOTO_STORE/calls.log"; then
    pass "option present: --workspace=<dir> after the verb words, from any directory"
else
    fail "present-mode read: exit $RC, out [$OUT], calls [$(calls)]"
fi

# "Not found": a workspace that holds no such session. Each read verb the
# record uses answers 68 and prints nothing.
for read in "context list root --prefix run/" "context get root k" "status root"; do
    lib "rs_koto_read '$WORK/nowhere' $read"
    if [ "$RC" -eq 68 ] && [ -z "$OUT" ]; then
        pass "option present: [$read] in a workspace without the session is not found (68), nothing printed"
    else
        fail "not found [$read]: exit $RC, out [$OUT], stderr [$(cat "$WORK/stderr")]"
    fi
done
# A read that fails for any other reason is not "not found".
lib "RECORD_KOTO_FAIL_READS_IN='$A' rs_koto_read '$A' context get root k"
if [ "$RC" -eq 1 ] && grep -q 'could not be read' "$WORK/stderr"; then
    pass "option present: an unreadable workspace passes koto's exit (1) and its message through, not 68"
else
    fail "unreadable: exit $RC, stderr [$(cat "$WORK/stderr")]"
fi
# A key the session doesn't hold is koto's own failure, not "not found".
lib "rs_koto_read '$A' context get root nokey"
[ "$RC" -ne 0 ] && [ "$RC" -ne 68 ] && pass "option present: a missing key in a held session is a failed read (exit $RC), not 68" \
    || fail "missing key: exit $RC"
unset RECORD_KOTO_WORKSPACE_OPTION

lib "cd '$WORK/b' && rs_koto_read '$A' context get root k > '$WORK/bytes'"
printf 'v' | cmp -s - "$WORK/bytes" && pass "a read's output passes through byte for byte (no newline added)" \
    || fail "read bytes: [$(od -c "$WORK/bytes" | head -2)]"

# --- the patterns -------------------------------------------------------------------

S_MAX=$(printf 'a%.0s' $(seq 1 200))
S_OVER=$(printf 'a%.0s' $(seq 1 201))
for ok in "execute-topic" "execute-x.step-2" "a" "$S_MAX"; do
    lib "rs_valid_session '$ok'"
    [ "$RC" -eq 0 ] && pass "session name [${ok:0:20}] is accepted" || fail "session [${ok:0:20}] refused"
done
for bad in "-x" ".x" "a/b" "a b" "$S_OVER" ""; do
    lib "rs_valid_session '$bad'"
    [ "$RC" -ne 0 ] && pass "session name [${bad:0:20}] (${#bad} chars) is refused" || fail "session [${bad:0:20}] accepted"
done
for ok in "step-1" "issue-12" "task_slug" "step-2.b"; do
    lib "rs_valid_step '$ok'"
    [ "$RC" -eq 0 ] && pass "step id [$ok] is accepted" || fail "step [$ok] refused"
done
for bad in "../x" "step/2" "-s" "$(printf 'a%.0s' $(seq 1 101))" ""; do
    lib "rs_valid_step '$bad'"
    [ "$RC" -ne 0 ] && pass "step id [${bad:0:20}] is refused" || fail "step [${bad:0:20}] accepted"
done

# --- the moved-aside names --------------------------------------------------------

lib 'rs_moved_candidates execute-x | tr "\n" " "'
[ "$RC" -eq 0 ] && [ "$OUT" = "execute-x execute-x_r1 execute-x_r2 execute-x_r3 execute-x_r4 execute-x_r5 execute-x_r6 execute-x_r7 execute-x_r8 execute-x_r9 execute-x_r10 " ] \
    && pass "a root is looked for under its name, then _r1 to _r10, in that order" \
    || fail "candidates: exit $RC, [$OUT]"
LONG=$(printf 'a%.0s' $(seq 1 197))
lib "rs_moved_candidates $LONG | tr '\n' ' '"
[ "$RC" -eq 0 ] && [ "$OUT" = "$LONG ${LONG}_r1 ${LONG}_r2 ${LONG}_r3 ${LONG}_r4 ${LONG}_r5 ${LONG}_r6 ${LONG}_r7 ${LONG}_r8 ${LONG}_r9 " ] \
    && pass "a candidate past the session pattern's 200 characters is left out" \
    || fail "long candidates: exit $RC, [$OUT]"
for c in "execute-x execute-x_r2 execute-x execute-x_r2" \
         "execute-x execute-x_r2 execute-x.step-1 execute-x_r2.step-1" \
         "execute-x execute-x_r2 execute-xy execute-xy" \
         "execute-x execute-x_r2 work-on-x-core-1 work-on-x-core-1" \
         "execute-x execute-x execute-x.step-1 execute-x.step-1"; do
    set -- $c
    lib "rs_moved_name $1 $2 $3"
    [ "$RC" -eq 0 ] && [ "$OUT" = "$4" ] \
        && pass "moved from $1 to $2, [$3] is [$4]" \
        || fail "rs_moved_name $1 $2 $3: exit $RC, [$OUT], want [$4]"
done
lib "rs_moved_name a ${LONG}xyz a.b"
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && pass "a moved name past the session pattern is refused (1), never printed" \
    || fail "long moved name: exit $RC, [$OUT]"

# --- the forms ------------------------------------------------------------------

reset_store
lib "rs_koto_write \"\$(rs_shared_dir $OWNER)\" init x --template t >/dev/null && printf '{}' | rs_koto_write \"\$(rs_shared_dir $OWNER)\" context add x k"
WROTE=$(cut -f1 "$RECORD_KOTO_STORE/calls.log" | tail -1)
lib "rs_shared_forms $OWNER"
case "
$OUT
" in
    *"
$WROTE
"*) pass "a write from the shared directory lands at one of the forms a reader tries ($WROTE)" ;;
    *) fail "write landed at [$WROTE], forms [$OUT]" ;;
esac
case "$WROTE" in
    "$SHARED"/*) pass "with the override set, the write landed under the override's directory" ;;
    *) fail "the write landed at [$WROTE], outside [$SHARED]" ;;
esac

# --- no suite writes under the real shared root ------------------------------------

# Every suite that runs a script reaching record-store.sh (the library
# itself, run-trail.sh, the lookup, or a script that records through them,
# named by a path built from a variable, as a suite names what it runs) sets
# the override, or sources the coordinated helpers that do. A suite that
# only names one in its text, or reads or writes one as a file, is not a
# writer.
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
# A new script that records through run-trail.sh joins this list.
WRITERS='"\$[A-Za-z_{}]+/[^" ]*(lib/record-store|run-trail|run-record-lookup|multi-pr-item-record|adopt-or-create-pr|record-coord-setup|node-push)\.sh"'
UNSET=""
for f in "$REPO_ROOT"/scripts/*_test.sh "$REPO_ROOT"/skills/*/scripts/*_test.sh "$REPO_ROOT"/skills/*/scripts/*-helpers.sh; do
    [ -f "$f" ] || continue
    RUNS=$(grep -vE '^[[:space:]]*#|(cat|cp|diff|grep|>)[^|]*'"$WRITERS" "$f")
    grep -qE "$WRITERS" <<<"$RUNS" || continue
    grep -q 'SHIRABE_RUN_RECORD_TEST_ROOT' "$f" && continue
    grep -q 'coord-test-helpers\.sh' "$f" && continue
    UNSET="$UNSET ${f#"$REPO_ROOT"/}"
done
[ -z "$UNSET" ] && pass "every suite that writes through record-store.sh sets SHIRABE_RUN_RECORD_TEST_ROOT" \
    || fail "suites that reach the run record without the override:$UNSET"

if [ "$(real_listing)" = "$REAL_BEFORE" ]; then
    pass "the real $REAL_ROOT is as this suite found it"
else
    fail "the real $REAL_ROOT changed: before [$REAL_BEFORE], after [$(real_listing)]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
