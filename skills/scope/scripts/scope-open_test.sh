#!/usr/bin/env bash
# scope-open_test.sh -- /scope's koto entry against a real koto at the floor.
#
# Usage: bash skills/scope/scripts/scope-open_test.sh
#
# Every case writes the invocation's raw tokens to an args file in a private
# directory, runs scope-open.sh from a fixture repository, and asserts on what
# koto did: the exit code, the rendered refusal, the result lines, whether a
# `scope-<topic>` session or a state file exists afterwards, what a request leg
# recorded, and that the args file is gone. A pass-through koto wrapper (set as
# KOTO_BIN, which koto-open.sh honours) keeps a byte copy of each vars file it
# was handed, so the pairs the tokens became are asserted too, and then execs
# the real koto.
#
# koto admits a --var value only inside ^[a-zA-Z0-9._/:@ \-]*$, and PLUGIN_ROOT
# is such a value. When this checkout's path falls outside it, PLUGIN_ROOT is a
# clean symlink under TMPDIR. When TMPDIR is outside it too, the suite runs in
# LOCALIZED mode: PLUGIN_ROOT is a clean placeholder, and the wrapper hands
# koto a copy of scope.md with {{PLUGIN_ROOT}} already written out as this
# checkout. Everything about the entry is still exercised; the one case that
# needs a fixture path koto admits (a plugin root inside the work tree) is
# skipped with a message.
# CI runs with a clean TMPDIR and so runs the shipped template unmodified.
#
# Exit 0 when every case that ran passed; SKIP (exit 0) when koto or jq is
# absent. The CI job asserts koto is present first.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
OPEN="$HERE/scope-open.sh"
KOTO_OPEN="$REPO/scripts/koto-open.sh"
TEMPLATE="$REPO/skills/scope/koto-templates/scope.md"

for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- no case ran"; exit 0; }
done
REAL_KOTO=$(command -v koto)
if ! "$REAL_KOTO" init --help 2>/dev/null | grep -q -- '--vars-file'; then
    echo "SKIP: this koto predates --vars-file -- no case ran"
    exit 0
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/scope-open-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$2] not in [$3]" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "[$2] found in [$3]" ;; *) ok "$1" ;; esac; }

clean() { case "$1" in *[!a-zA-Z0-9._/:@\ -]*) return 1 ;; esac; return 0; }

LOCALIZED=0
LOCAL_TEMPLATE=""
if clean "$REPO"; then
    PLUGIN="$REPO"
elif clean "$T"; then
    ln -s "$REPO" "$T/plugin"
    PLUGIN="$T/plugin"
else
    LOCALIZED=1
    PLUGIN="/opt/shirabe-plugin-placeholder"
    LOCAL_TEMPLATE="$T/scope.md"
    sed "s#{{PLUGIN_ROOT}}#$REPO#g" "$TEMPLATE" >"$LOCAL_TEMPLATE"
    echo "NOTE: LOCALIZED mode -- this checkout and TMPDIR both hold a character koto"
    echo "      refuses in a --var value; the wrapper substitutes a template copy."
fi

# The pass-through wrapper.
WRAP="$T/bin/koto"
mkdir -p "$T/bin"
cat >"$WRAP" <<'WRAPPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SCOPE_TEST_LOG/koto.argv"
set -- "$@"
out=()
prev=""
for a in "$@"; do
    orig="$a"
    if [ "$prev" = "--vars-file" ]; then cp "$a" "$SCOPE_TEST_LOG/vars.last" 2>/dev/null; fi
    if [ "$prev" = "--template" ] && [ -n "${SCOPE_TEST_TEMPLATE:-}" ]; then a="$SCOPE_TEST_TEMPLATE"; fi
    out+=("$a")
    prev="$orig"
done
exec "$SCOPE_TEST_REAL_KOTO" "${out[@]}"
WRAPPER
chmod +x "$WRAP"
export SCOPE_TEST_LOG="$T" SCOPE_TEST_REAL_KOTO="$REAL_KOTO" SCOPE_TEST_TEMPLATE="$LOCAL_TEMPLATE"

KH="$T/koto-home"
mkdir -p "$KH"
R="$T/repo"
mkdir -p "$R/docs/roadmaps"
git -C "$R" init -q
printf 'r\n' >"$R/docs/roadmaps/ROADMAP-good.md"
git -C "$R" add docs
git -C "$R" -c user.email=t@example.invalid -c user.name=t commit -q -m fixture
git -C "$R" checkout -q -b scope-fixture

k() { (cd "$R" && HOME="$KH" "$REAL_KOTO" "$@"); }

# open_scope <tokens-json> [scope-open options...] -- one invocation from $R.
# Sets RC, STDOUT, STDERR, ARGS_DIR, ARGS.
RC=0; STDOUT=""; STDERR=""; ARGS=""; ARGS_DIR=""
open_scope() {
    local tokens="$1"; shift
    ARGS_DIR=$(bash "$KOTO_OPEN" --alloc-dir)
    ARGS="$ARGS_DIR/args.json"
    printf '%s' "$tokens" >"$ARGS"
    : >"$T/koto.argv"
    rm -f "$T/vars.last"
    (cd "$R" && HOME="$KH" KOTO_BIN="$WRAP" bash "$OPEN" --plugin-root "${PLUGIN_ARG:-$PLUGIN}" "$@" "$ARGS" >"$T/out" 2>"$T/err")
    RC=$?
    STDOUT=$(cat "$T/out")
    STDERR=$(cat "$T/err")
}

vars() { jq -c "${1:-.}" "$T/vars.last" 2>/dev/null; }
no_session() { ! k status "scope-$1" >/dev/null 2>&1; }
new_request() {
    k request create --with-data '{"legs":[{"name":"scope","role":"scope","template":"scope.md","inputs":{}}]}' \
        --requested-by scope-open-test --coordinator-of-record scope-open-test 2>/dev/null | jq -r '.request_id'
}
leg() { k request get "$1" 2>/dev/null | jq -c "$2"; }

# refused_case <label> <topic> -- the shared assertions for a koto refusal.
refused_case() {
    local label="$1" topic="$2"
    eq "$label: koto exits 2" "2" "$RC"
    has "$label: prints outcome=error" "outcome=error" "$STDOUT"
    has "$label: prints step=scope:refused" "step=scope:refused" "$STDOUT"
    if printf '%s\n' "$STDOUT" | grep -qx 'outcome=refused'; then
        bad "$label: never prints outcome=refused" "$STDOUT"
    else
        ok "$label: never prints outcome=refused"
    fi
    if no_session "$topic"; then ok "$label: no scope-$topic session"; else bad "$label: no scope-$topic session" "a session exists"; fi
    if [ -e "$R/wip/scope_${topic}_state.md" ]; then bad "$label: no state file"; else ok "$label: no state file"; fi
    if [ -e "$ARGS" ] || [ -e "$ARGS_DIR" ]; then bad "$label: the args file is removed" "$ARGS"; else ok "$label: the args file is removed"; fi
}

echo "== --intent refusals =="

open_scope '["t-bogus","--intent=bogus"]'
refused_case "--intent=bogus" t-bogus
has "--intent=bogus: the error names --intent" "--intent" "$STDERR"
eq "--intent=bogus: koto's code" "refused=invalid_var" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
BOGUS_ERR="$STDERR"

open_scope '["t-absent","--intent=absent"]'
refused_case "--intent=absent" t-absent
has "--intent=absent: the error names --intent" "--intent" "$STDERR"

for v in none unset; do
    open_scope "[\"t-$v\",\"--intent=$v\"]"
    refused_case "--intent=$v" "t-$v"
    eq "--intent=$v: stderr is --intent=bogus's apart from the value" "${BOGUS_ERR//bogus/VALUE}" "${STDERR//$v/VALUE}"
    REQ=$(new_request)
    open_scope "[\"t-$v\",\"--intent=$v\",\"--koto-leg=$REQ:scope\"]"
    eq "--intent=$v under --koto-leg: the leg records a refusal" "refused" "$(leg "$REQ" '.legs.scope.result_source' | tr -d '"')"
    eq "--intent=$v under --koto-leg: payload outcome refused" '"refused"' "$(leg "$REQ" '.legs.scope.result.payload.outcome')"
    eq "--intent=$v under --koto-leg: reason" '"invalid-var:INTENT_FLAG"' "$(leg "$REQ" '.legs.scope.result.payload.reason')"
done

REQ=$(new_request)
open_scope "[\"t-bare\",\"--intent\",\"--koto-leg=$REQ:scope\"]"
refused_case "bare --intent" t-bare
has "bare --intent: the error names --intent" "--intent" "$STDERR"
eq "bare --intent: one INTENT_FLAG pair carrying the literal token" '[["INTENT_FLAG","--intent"]]' \
    "$(vars '[.[] | select(.[0] == "INTENT_FLAG")]')"
eq "bare --intent: the leg records invalid-var:INTENT_FLAG" '"invalid-var:INTENT_FLAG"' "$(leg "$REQ" '.legs.scope.result.payload.reason')"

open_scope '["t-twice","--intent=stop","--intent=continue"]'
refused_case "--intent=stop --intent=continue" t-twice
has "a repeated --intent: the error names --intent" "--intent" "$STDERR"
eq "a repeated --intent: koto's code" "refused=duplicate_var" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"

REQ=$(new_request)
open_scope "[\"t-stopempty\",\"--intent=stop\",\"--intent=\",\"--koto-leg=$REQ:scope\"]"
refused_case "--intent=stop --intent=" t-stopempty
has "--intent=stop --intent=: the error names --intent" "--intent" "$STDERR"
eq "--intent=stop --intent=: two INTENT_FLAG pairs" '[["INTENT_FLAG","stop"],["INTENT_FLAG",""]]' \
    "$(vars '[.[] | select(.[0] == "INTENT_FLAG")]')"
eq "--intent=stop --intent=: the leg records duplicate-var:INTENT_FLAG" '"duplicate-var:INTENT_FLAG"' \
    "$(leg "$REQ" '.legs.scope.result.payload.reason')"

echo "== the other variables =="

open_scope '["-lead"]'
refused_case "a leading-dash topic" lead
has "a leading-dash topic: today's slug-refusal text" 'Topic slug `-lead` does not match the required pattern `^[a-z0-9-]+$`.' "$STDERR"

open_scope '["Upper"]'
refused_case "an uppercase topic" Upper
has "an uppercase topic: today's slug-refusal text" 'Topic slug `Upper` does not match the required pattern' "$STDERR"

open_scope '["t-rounds","--max-rounds=0"]'
refused_case "--max-rounds=0" t-rounds
has "--max-rounds=0 names the flag" "--max-rounds" "$STDERR"
open_scope '["t-rounds","--max-rounds=51"]'
refused_case "--max-rounds=51" t-rounds

open_scope '["t-up","--upstream","docs/roadmaps/../roadmaps/ROADMAP-good.md"]'
refused_case "an --upstream with .." t-up
has "an --upstream with ..: names the flag" "--upstream" "$STDERR"

open_scope '["t-up","--upstream"]'
refused_case "a bare --upstream" t-up
eq "a bare --upstream reaches koto as the literal token" '[["UPSTREAM","--upstream"]]' "$(vars '[.[] | select(.[0] == "UPSTREAM")]')"

open_scope '["t-mode","--auto","--interactive"]'
refused_case "--auto --interactive" t-mode
eq "--auto --interactive: koto's code" "refused=duplicate_var" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
has "--auto --interactive: names both flags" "--interactive" "$STDERR"

open_scope '["t-coord","--coordinated","--no-coordinated"]'
refused_case "--coordinated --no-coordinated" t-coord
has "--coordinated --no-coordinated: names both flags" "--no-coordinated" "$STDERR"

open_scope '["t-meta","--upstream=docs/roadmaps/ROADMAP-$(touch PWNED).md;touch PWNED2"]'
refused_case "a token with shell metacharacters" t-meta
eq "the metacharacter token reaches koto as a literal value" \
    '"docs/roadmaps/ROADMAP-$(touch PWNED).md;touch PWNED2"' "$(vars '[.[] | select(.[0] == "UPSTREAM")][0][1]')"
if [ -e "$R/PWNED" ] || [ -e "$R/PWNED2" ] || [ -e "$T/PWNED" ]; then bad "the metacharacter token was executed"; else ok "the metacharacter token was not executed"; fi

open_scope '["t-root"]'
eq "a clean invocation passes PLUGIN_ROOT_PLACEMENT=outside" '"outside"' "$(vars '[.[] | select(.[0] == "PLUGIN_ROOT_PLACEMENT")][0][1]')"
k session cleanup scope-t-root >/dev/null 2>&1

DOTDOT="$PLUGIN/skills/.."
PLUGIN_ARG="$DOTDOT" open_scope '["t-dotdot"]'
refused_case "a PLUGIN_ROOT with a .. segment" t-dotdot
has "a PLUGIN_ROOT with ..: names the plugin root" "plugin root" "$STDERR"

if [ "$LOCALIZED" -eq 1 ]; then
    echo "SKIP (LOCALIZED): a PLUGIN_ROOT inside the work tree needs a fixture path koto admits"
else
    mkdir -p "$R/vendor/shirabe/skills/scope/koto-templates"
    cp "$TEMPLATE" "$R/vendor/shirabe/skills/scope/koto-templates/scope.md"
    REQ=$(new_request)
    PLUGIN_ARG="$R/vendor/shirabe" open_scope "[\"t-inside\",\"--koto-leg=$REQ:scope\"]"
    refused_case "a PLUGIN_ROOT inside the work tree" t-inside
    eq "inside the work tree: the vars file carries inside-worktree" '"inside-worktree"' \
        "$(vars '[.[] | select(.[0] == "PLUGIN_ROOT_PLACEMENT")][0][1]')"
    eq "inside the work tree: koto refused it (invalid_var), not the script" "refused=invalid_var" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
    has "inside the work tree: the wording says so" "inside the repository being scoped" "$STDERR"
    eq "inside the work tree: the leg records invalid-var:PLUGIN_ROOT_PLACEMENT" '"invalid-var:PLUGIN_ROOT_PLACEMENT"' \
        "$(leg "$REQ" '.legs.scope.result.payload.reason')"
fi

echo "== an explicitly empty --intent= is a missing flag =="

open_scope '["t-empty","--intent="]'
eq "--intent= alone: koto exits 0" "0" "$RC"
eq "--intent= alone: opened=new" "opened=new" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
has "--intent= alone: names the session" "session=scope-t-empty" "$STDOUT"
eq "--intent= alone: no INTENT_FLAG pair" "[]" "$(vars '[.[] | select(.[0] == "INTENT_FLAG")]')"
if [ -e "$ARGS" ] || [ -e "$ARGS_DIR" ]; then bad "--intent= alone: the args file is removed after success"; else ok "--intent= alone: the args file is removed after success"; fi
NEXT=$(k next scope-t-empty --no-cleanup 2>/dev/null)
eq "--intent= alone: intake routes it to setup" "setup" "$(printf '%s' "$NEXT" | jq -r '.state')"
has "--intent= alone: RUN_INTENT resolves to none, as with no --intent" "intent: none" "$(printf '%s' "$NEXT" | jq -r '.directive')"

echo "== a live session recorded with INTENT_FLAG=stop =="

open_scope '["t-live","--intent=stop"]'
eq "a stop run opens" "opened=new" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
k next scope-t-live --no-cleanup >/dev/null 2>&1
BEFORE_STATE=$(k status scope-t-live | jq -r '.current_state')

REQ=$(new_request)
open_scope "[\"t-live\",\"--intent=continue\",\"--koto-leg=$REQ:scope\"]"
eq "--intent=continue against it: refused=var_mismatch" "refused=var_mismatch" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
eq "--intent=continue against it: exit 2" "2" "$RC"
has "--intent=continue against it: the error names --intent" "--intent" "$STDERR"
has "--intent=continue against it: outcome=error" "outcome=error" "$STDOUT"
eq "the session is unchanged" "$BEFORE_STATE" "$(k status scope-t-live | jq -r '.current_state')"
eq "the leg carries the mismatch" \
    '{"outcome":"refused","reason":"var-mismatch:INTENT_FLAG","var":"INTENT_FLAG","recorded":"stop","requested":"continue"}' \
    "$(leg "$REQ" '.legs.scope.result.payload | {outcome, reason, var, recorded, requested}')"

open_scope '["t-live","--auto"]'
eq "a bare re-invocation attaches" "opened=attached" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
has "the rebind variables take this invocation's values" '"EXEC_MODE"' "$STDOUT"

open_scope '["t-live","--intent="]'
eq "a lone --intent= attaches exactly as a bare call does" "opened=attached" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"

open_scope '["t-live","--intent=stop"]'
eq "the same explicit intent attaches" "opened=attached" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"

echo "== a finished session is replaced, never ticked (R31) =="

# Drive a session to a terminal the cheap way: intake refuses an explicit
# --intent that differs from the one an unfinished run recorded.
mkdir -p "$R/wip"
finish_topic() { # finish_topic <topic> -- leaves scope-<topic> at done_refused
    printf 'topic: %s\nintent: stop\n' "$1" >"$R/wip/scope_$1_state.md"
    open_scope "[\"$1\",\"--intent=continue\"]"
    k next "scope-$1" --no-cleanup >/dev/null 2>&1
    rm -f "$R/wip/scope_$1_state.md"
}

finish_topic t-fin
eq "the first run reached a terminal" "done_refused|true" \
    "$(k status scope-t-fin | jq -r '"\(.current_state)|\(.is_terminal)"')"
open_scope '["t-fin"]'
eq "no intent: a second /scope <topic> replaces the finished session" "opened=replaced" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
has "no intent: the old run's final state is reported" "replaced_state=done_refused" "$STDOUT"
has "no intent: the session is named as usual" "session=scope-t-fin" "$STDOUT"
eq "no intent: the fresh session is not terminal" "intake|false" \
    "$(k status scope-t-fin | jq -r '"\(.current_state)|\(.is_terminal)"')"
NEXT=$(k next scope-t-fin --no-cleanup 2>/dev/null)
eq "no intent: the fresh session walks intake and resume_route to setup" "setup" "$(printf '%s' "$NEXT" | jq -r '.state')"
has "no intent: under the effective intent none" "intent: none" "$(printf '%s' "$NEXT" | jq -r '.directive')"

finish_topic t-fin2
open_scope '["t-fin2","--intent=continue"]'
eq "intent: a second /scope <topic> --intent=continue replaces the finished session" "opened=replaced" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
NEXT=$(k next scope-t-fin2 --no-cleanup 2>/dev/null)
eq "intent: the fresh session reaches setup" "setup" "$(printf '%s' "$NEXT" | jq -r '.state')"
has "intent: under the effective intent continue" "intent: continue" "$(printf '%s' "$NEXT" | jq -r '.directive')"

open_scope '["t-fin2"]'
eq "a live session is attached, never replaced" "opened=attached" "$(printf '%s\n' "$STDOUT" | sed -n 1p)"
has "every call passes --replace-terminal" "--replace-terminal" "$(cat "$T/koto.argv")"

echo "== the few refusals scope-open.sh makes itself =="

for badleg in "--koto-leg=BAD:scope" "--koto-leg=req1:execute" "--koto-leg=req1" "--koto-leg"; do
    open_scope "[\"t-leg\",\"$badleg\"]"
    eq "a malformed $badleg: usage exit 64" "64" "$RC"
    has "a malformed $badleg: outcome=error" "outcome=error" "$STDOUT"
    has "a malformed $badleg: step=scope:refused" "step=scope:refused" "$STDOUT"
    if [ -s "$T/koto.argv" ]; then bad "a malformed $badleg: no koto call" "$(cat "$T/koto.argv")"; else ok "a malformed $badleg: no koto call"; fi
    if [ -e "$ARGS" ] || [ -e "$ARGS_DIR" ]; then bad "a malformed $badleg: the args file is removed"; else ok "a malformed $badleg: the args file is removed"; fi
done
open_scope '["t-leg","--koto-leg=a:scope","--koto-leg=b:scope"]'
eq "--koto-leg twice: usage exit 64" "64" "$RC"

mkdir -p "$R/inside"
printf '["t-in"]' >"$R/inside/args.json"
(cd "$R" && HOME="$KH" KOTO_BIN="$WRAP" bash "$OPEN" --plugin-root "$PLUGIN" "$R/inside/args.json" >"$T/out" 2>"$T/err"); RC=$?
eq "an args file inside the work tree: refused by koto-open.sh" "refused=args_file_in_work_tree" "$(sed -n 1p "$T/out")"
has "an args file inside the work tree: step=scope:refused" "step=scope:refused" "$(cat "$T/out")"
if ls "$R/inside" | grep -q .; then bad "an args file inside the work tree: nothing is left behind" "$(ls "$R/inside")"; else ok "an args file inside the work tree: nothing is left behind"; fi

ARGS_DIR=$(bash "$KOTO_OPEN" --alloc-dir); ARGS="$ARGS_DIR/args.json"; printf '["t-nokoto"]' >"$ARGS"
(cd "$R" && HOME="$KH" KOTO_BIN="$T/no-such-koto" bash "$OPEN" --plugin-root "$PLUGIN" "$ARGS" >"$T/out" 2>"$T/err"); RC=$?
eq "no koto binary: exit 127" "127" "$RC"
has "no koto binary: failed=koto_missing" "failed=koto_missing" "$(cat "$T/out")"
has "no koto binary: step=scope:refused" "step=scope:refused" "$(cat "$T/out")"
if [ -e "$ARGS" ]; then bad "no koto binary: the args file is removed"; else ok "no koto binary: the args file is removed"; fi

printf 'not json' >"$T/garbage.json"
(cd "$R" && HOME="$KH" KOTO_BIN="$WRAP" bash "$OPEN" --plugin-root "$PLUGIN" "$T/garbage.json" >"$T/out" 2>"$T/err"); RC=$?
eq "an args file that is not a JSON array: usage exit 64" "64" "$RC"
if [ -e "$T/garbage.json" ]; then bad "a malformed args file is removed too"; else ok "a malformed args file is removed too"; fi

if grep -n 'eval' "$OPEN" | grep -v '^[0-9]*:[[:space:]]*#' | grep -q .; then
    bad "scope-open.sh uses eval" "$(grep -n eval "$OPEN")"
else
    ok "scope-open.sh has no eval"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
