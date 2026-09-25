#!/usr/bin/env bash
# run-intake_test.sh -- /scope's intake default action, alone and in the engine.
#
# Usage: bash skills/scope/scripts/run-intake_test.sh
#
# Two groups:
#
#   stand-in cases, which need bash, git and jq but no koto. A koto stand-in
#   on PATH stores each context key as a file, so every verdict, reason and
#   recorded value run-intake.sh can write is read back byte for byte, along
#   with what it clears and what it prints for koto to capture.
#
#   engine cases, which drive the shipped scope.md through real koto sessions:
#   `intake` routes to done_refused once per refusal reason, and the recorded
#   result carries that reason (and, for an intent mismatch, the recorded and
#   requested intents). koto admits a --var value only inside
#   ^[a-zA-Z0-9._/:@ \-]*$, so PLUGIN_ROOT is reached through a symlink under
#   TMPDIR when the checkout's own path falls outside it; when the symlink's
#   path does too, the engine cases SKIP with a message naming the character.
#   The CI job runs with a clean TMPDIR and asserts koto is present first.
#
# Exit 0 when every case that ran passed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
S="$HERE/run-intake.sh"
TEMPLATE="$REPO/skills/scope/koto-templates/scope.md"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/run-intake-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# --- the koto stand-in -------------------------------------------------------------

SHIM="$T/shim"
STORE="$T/store"
mkdir -p "$SHIM" "$STORE"
cat >"$SHIM/koto" <<'STUB'
#!/usr/bin/env bash
# koto stand-in: `context add|remove|get <session> <key>` over $STORE/<session>/<key>.
[ "$1" = context ] || { echo "stand-in: unsupported: $*" >&2; exit 2; }
[ -n "${STUB_FAIL:-}" ] && [ "$2" = "$STUB_FAIL" ] && { echo "stand-in: failing $2" >&2; exit 9; }
d="$STORE/$3"
case "$2" in
    add) mkdir -p "$d"; cat >"$d/$4" ;;
    remove) rm -f "$d/$4" ;;
    get) cat "$d/$4" 2>/dev/null || exit 1 ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$SHIM/koto"
export STORE

key()    { cat "$STORE/$1/$2" 2>/dev/null; }
has()    { [ -f "$STORE/$1/$2" ]; }

# A repository to run in: a tracked roadmap and one of each upstream defect.
R="$T/repo"
mkdir -p "$R/docs/roadmaps" "$R/wip" "$T/elsewhere"
git -C "$R" init -q
printf 'r\n' >"$R/docs/roadmaps/ROADMAP-good.md"
printf 'r\n' >"$R/docs/roadmaps/notes.md"
printf 'r\n' >"$R/wip/ROADMAP-scratch.md"
printf 'r\n' >"$T/elsewhere/ROADMAP-far.md"
ln -s ../../wip/ROADMAP-scratch.md "$R/docs/roadmaps/ROADMAP-intowip.md"
ln -s notes.md "$R/docs/roadmaps/ROADMAP-renamed.md"
ln -s "$T/elsewhere/ROADMAP-far.md" "$R/docs/roadmaps/ROADMAP-away.md"
git -C "$R" add docs wip
printf 'r\n' >"$R/docs/roadmaps/ROADMAP-untracked.md"

state_file() { # state_file <topic> <content>
    printf '%s' "$2" >"$R/wip/scope_$1_state.md"
}

# run <session> <topic> <flag> <upstream> -- sets OUT and RC.
OUT=""
RC=0
run() {
    OUT=$(cd "$R" && PATH="$SHIM:$PATH" bash "$S" --session "$1" --topic "$2" --intent-flag "$3" --upstream "$4" 2>"$T/err")
    RC=$?
}

# verdict <session> <want-verdict> <want-reason> <want-recorded> <label>
verdict() {
    local s="$1" v="$2" r="$3" rec="$4" label="$5" got
    got="$(key "$s" intake_verdict)|$(key "$s" reason)|$(key "$s" recorded)"
    eq "$label: verdict|reason|recorded" "$v|$r|$rec" "$got"
    if [ -z "$r" ] && has "$s" reason; then bad "$label: no reason key" "reason was written"; fi
    if [ -z "$rec" ] && has "$s" recorded; then bad "$label: no recorded key" "recorded was written"; fi
}

echo "== ok, and the effective intent koto captures =="

run s-none none-topic "" ""
eq "no flag, no state file: RUN_INTENT none" "none" "$OUT"
eq "it exits 0" "0" "$RC"
verdict s-none ok "" "" "no flag"

run s-flag flag-topic stop ""
eq "an explicit stop with no state file: RUN_INTENT stop" "stop" "$OUT"
verdict s-flag ok "" "" "explicit stop"

state_file equal 'topic: equal
intent: stop
'
run s-equal equal stop ""
eq "an explicit intent equal to the recorded one proceeds" "stop" "$OUT"
verdict s-equal ok "" "" "equal explicit intent"

run s-bare equal "" ""
eq "a bare invocation resumes under the recorded intent" "stop" "$OUT"
verdict s-bare ok "" "" "bare invocation"

state_file pre 'topic: pre
phase_pointer: phase-1
exit: UNSET
'
run s-pre pre "" ""
eq "a pre-change state file (no intent: field) reads as none" "none" "$OUT"
verdict s-pre ok "" "" "pre-change state file"

run s-up-ok up-ok "" docs/roadmaps/ROADMAP-good.md
verdict s-up-ok ok "" "" "a tracked roadmap upstream"

eq "stdout is exactly one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

echo "== refused, with the reason and the recorded intent =="

state_file mismatch 'topic: mismatch
intent: stop
'
run s-mm mismatch continue ""
eq "an intent mismatch still captures the explicit intent" "continue" "$OUT"
verdict s-mm refused intent-mismatch stop "continue against a recorded stop"
eq "the state file is unchanged by a refusal" "topic: mismatch
intent: stop" "$(cat "$R/wip/scope_mismatch_state.md")"

run s-mm-pre pre continue ""
verdict s-mm-pre refused intent-mismatch none "an explicit intent against a pre-change state file"

run s-wip up "" docs/roadmaps/ROADMAP-intowip.md
verdict s-wip refused upstream-wip "" "an upstream resolving into wip/"
run s-untracked up "" docs/roadmaps/ROADMAP-untracked.md
verdict s-untracked refused upstream-untracked "" "an untracked upstream"
run s-outside up "" docs/roadmaps/ROADMAP-away.md
verdict s-outside refused upstream-outside "" "an upstream leaving the repository"
run s-basename up "" docs/roadmaps/ROADMAP-renamed.md
verdict s-basename refused upstream-basename "" "an upstream that is not a roadmap"

echo "== error =="

state_file corrupt 'intent: sometimes
'
run s-corrupt corrupt "" ""
eq "an unresolvable recorded intent still prints a capturable line" "none" "$OUT"
eq "and exits 0: the verdict carries the failure" "0" "$RC"
verdict s-corrupt error "" "" "a recorded intent outside the enum"

run s-corrupt2 corrupt stop ""
eq "with an explicit flag, the flag is the capturable line" "stop" "$OUT"
verdict s-corrupt2 error "" "" "an explicit flag against a corrupt record"

run s-topic "Bad Topic" "" ""
verdict s-topic error "" "" "a topic no state path can be composed from"

mkdir -p "$T/notrepo"
OUT=$(cd "$T/notrepo" && PATH="$SHIM:$PATH" bash "$S" --session s-norepo --topic t --intent-flag "" --upstream docs/roadmaps/ROADMAP-good.md 2>/dev/null)
verdict s-norepo error "" "" "an upstream check that cannot find the repository"

echo "== stale keys from an earlier entry are cleared =="

mkdir -p "$STORE/s-stale"
printf 'refused' >"$STORE/s-stale/intake_verdict"
printf 'upstream-wip' >"$STORE/s-stale/reason"
printf 'continue' >"$STORE/s-stale/recorded"
run s-stale stale-topic "" ""
verdict s-stale ok "" "" "stale refused keys, then an ok entry"

mkdir -p "$STORE/s-stale2"
printf 'ok' >"$STORE/s-stale2/intake_verdict"
printf 'stop' >"$STORE/s-stale2/recorded"
run s-stale2 up "" docs/roadmaps/ROADMAP-untracked.md
verdict s-stale2 refused upstream-untracked "" "a stale recorded key does not survive an upstream refusal"

echo "== a reason or recorded value outside the closed set is not written =="

ALT="$T/alt"
mkdir -p "$ALT"
cp "$S" "$HERE/resolve-intent.sh" "$HERE/check-recorded-intent.sh" "$ALT/"
printf '#!/usr/bin/env bash\necho upstream-evil\nexit 1\n' >"$ALT/check-upstream.sh"
OUT=$(cd "$R" && PATH="$SHIM:$PATH" bash "$ALT/run-intake.sh" --session s-evil --topic t --intent-flag "" --upstream "" 2>/dev/null)
verdict s-evil error "" "" "an upstream reason outside the closed set"

cp "$HERE/check-upstream.sh" "$ALT/check-upstream.sh"
printf '#!/usr/bin/env bash\necho intent-mismatch\necho recorded=maybe\nexit 1\n' >"$ALT/check-recorded-intent.sh"
OUT=$(cd "$R" && PATH="$SHIM:$PATH" bash "$ALT/run-intake.sh" --session s-evil2 --topic t --intent-flag stop --upstream "" 2>/dev/null)
verdict s-evil2 error "" "" "a recorded value outside the closed set"

printf '#!/usr/bin/env bash\necho upstream-wip\nexit 1\n' >"$ALT/check-recorded-intent.sh"
OUT=$(cd "$R" && PATH="$SHIM:$PATH" bash "$ALT/run-intake.sh" --session s-evil3 --topic t --intent-flag stop --upstream "" 2>/dev/null)
verdict s-evil3 error "" "" "an upstream reason from the intent check"

echo "== the session, and failures of koto itself =="

OUT=$(cd "$R" && PATH="$SHIM:$PATH" KOTO_TICK_SESSION=s-tick bash "$S" --session s-arg --topic t --intent-flag "" --upstream "" 2>/dev/null)
eq "koto's own KOTO_TICK_SESSION wins over --session" "ok" "$(key s-tick intake_verdict)"
if has s-arg intake_verdict; then bad "nothing is written to the --session name when koto names the session"; else ok "nothing is written to the --session name when koto names the session"; fi

OUT=$(cd "$R" && PATH="$SHIM:$PATH" STUB_FAIL=add bash "$S" --session s-addfail --topic t --intent-flag "" --upstream "" 2>/dev/null); RC=$?
eq "a failed context add exits 66" "66" "$RC"
OUT=$(cd "$R" && PATH="$SHIM:$PATH" STUB_FAIL=remove bash "$S" --session s-rmfail --topic t --intent-flag "" --upstream "" 2>/dev/null); RC=$?
eq "a failed context remove exits 66" "66" "$RC"
if has s-rmfail intake_verdict; then bad "no verdict after a failed clear"; else ok "no verdict after a failed clear"; fi

OUT=$(cd "$R" && PATH="$SHIM:$PATH" bash "$S" --session s-usage --topic t 2>/dev/null); RC=$?
eq "a usage error exits 64" "64" "$RC"
if [ -d "$STORE/s-usage" ]; then bad "a usage error writes nothing"; else ok "a usage error writes nothing"; fi

# --- engine cases ------------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo "passed: $PASS   failed: $FAIL"
    [ "$FAIL" -eq 0 ]
    exit
fi

PLUGIN_ROOT="$REPO"
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$REPO" "$T/plugin"
        PLUGIN_ROOT="$T/plugin" ;;
esac
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        echo
        echo "SKIP: the engine cases need a plugin root koto admits as a --var value"
        echo "      (^[a-zA-Z0-9._/:@ \\-]*\$), and both the checkout and TMPDIR hold a"
        echo "      character outside it: $PLUGIN_ROOT"
        echo "passed: $PASS   failed: $FAIL"
        [ "$FAIL" -eq 0 ]
        exit ;;
esac

echo
echo "== engine: intake routes each verdict ($(koto version 2>/dev/null | head -1)) =="

EH="$T/koto-home"
mkdir -p "$EH"
git -C "$R" -c user.email=t@example.invalid -c user.name=t commit -q -m fixture
git -C "$R" checkout -q -b scope-fixture

# engine <topic> <state-file-content-or-empty> <var...> -- a fresh session,
# one tick; sets EST (current state) and ERES (the result payload, compact).
EST=""
ERES=""
engine() {
    local topic="$1" content="$2"
    shift 2
    rm -f "$R/wip/scope_${topic}_state.md"
    [ -n "$content" ] && printf '%s' "$content" >"$R/wip/scope_${topic}_state.md"
    (cd "$R" && HOME="$EH" koto init "scope-$topic" --template "$TEMPLATE" \
        --var TOPIC="$topic" --var PLUGIN_ROOT="$PLUGIN_ROOT" \
        --var PLUGIN_ROOT_PLACEMENT=outside "$@" >/dev/null 2>"$T/init.err") \
        || { bad "engine init for $topic" "$(cat "$T/init.err")"; EST=""; ERES=""; return; }
    (cd "$R" && HOME="$EH" koto next "scope-$topic" --no-cleanup >/dev/null 2>&1)
    local st
    st=$(cd "$R" && HOME="$EH" koto status "scope-$topic" 2>/dev/null)
    EST=$(printf '%s' "$st" | jq -r '.current_state // ""')
    ERES=$(printf '%s' "$st" | jq -c '.result.payload // {}')
}
field() { printf '%s' "$ERES" | jq -r --arg k "$1" '.[$k] // ""'; }

engine eok "" --var UPSTREAM=docs/roadmaps/ROADMAP-good.md
eq "an ok verdict routes past intake to setup" "setup" "$EST"

for pair in upstream-wip:ROADMAP-intowip upstream-untracked:ROADMAP-untracked \
            upstream-outside:ROADMAP-away upstream-basename:ROADMAP-renamed; do
    reason="${pair%%:*}"
    file="${pair#*:}"
    engine "e-$reason" "" --var UPSTREAM="docs/roadmaps/$file.md"
    eq "$reason ends at done_refused" "done_refused" "$EST"
    eq "$reason: the result's reason" "$reason" "$(field reason)"
    eq "$reason: outcome is refused, a payload value" "refused" "$(field outcome)"
    eq "$reason: step is scope:refused" "scope:refused" "$(field step)"
done

engine e-mismatch 'topic: e-mismatch
intent: stop
' --var INTENT_FLAG=continue
eq "intent-mismatch ends at done_refused" "done_refused" "$EST"
eq "intent-mismatch: the result's reason" "intent-mismatch" "$(field reason)"
eq "intent-mismatch: recorded is non-empty and is the state file's" "stop" "$(field recorded)"
eq "intent-mismatch: requested is non-empty and is the flag" "continue" "$(field requested)"
eq "intent-mismatch: intent is the effective intent" "continue" "$(field intent)"
eq "the state file is unchanged" "topic: e-mismatch
intent: stop" "$(cat "$R/wip/scope_e-mismatch_state.md")"

engine e-error 'intent: sometimes
'
eq "an error verdict ends at done_error" "done_error" "$EST"
eq "done_error's step is scope:intake" "scope:intake" "$(field step)"
eq "done_error's outcome is error" "error" "$(field outcome)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
