#!/usr/bin/env bash
# session-store_engine_test.sh -- a roadmap record on the session store, the
# record's only store, the shipped coordinate.md driven through real koto
# against the testdata/gh stand-in (docs/designs/DESIGN-coordinator-session-record.md,
# Decision 4; docs/designs/current/DESIGN-coordinator-record-teardown.md, "The
# start").
#
# Proves, one line per case:
#   1. a start names no store (the run has no STORE variable): with no record
#      it stops at record_open, state-open.sh builds the empty record into the
#      run's record/ keys and opens nothing on GitHub, the next find reaches
#      reconcile, and coord/source.json reads session;
#   2. writes through state-write.sh and state-stored-set.sh land in the keys and
#      not on GitHub, the crash set's reports-to row among them with no store
#      row, and the run passes reconcile on them;
#   2b. a second start on the same host resumes the run (PRD R12): it prints
#      the first run's name with resumed=1, opens and cancels nothing, and the
#      run goes on where it stood;
#   3. each refusal the write guarantees name leaves every record/ key
#      byte-identical: a non-owner's change (65), a state edited from an older
#      written time (12), a run moved with `koto next --to` (10), and a write
#      from a run that is no longer the scope's live one (10); there is no size
#      budget, so a state over 60,000 bytes is written (0); that run, which can't be resumed, is carried: the
#      next start opens a new run holding every record/ key of the old one;
#   4. a changed template carries the live run's record/ and legs/ keys into a
#      new run and keeps the old log readable;
#   5. on a host where no session holds the record there is nothing on GitHub
#      to find either: the start is a new scope's, and the find stops at
#      record_open.
#
# On a koto without the session store's features (`context list --prefix`,
# `session import`) it proves only that the start is refused as
# store-unsupported, opening no session.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/session-store_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh: the GitHub DB helpers, state_json and the counters. It
# puts testdata/ first on PATH, the koto stand-in included; this suite needs
# the real koto, so PATH is rebuilt with only the gh stand-in in front.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
. "$HERE/testdata/engine-session.sh"
mkdir -p "$T/bin"
ln -sf "$HERE/testdata/gh" "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"

# A clone-shaped working directory in a niwa instance that permits every
# finishing step, so the posture reads `readable`.
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
# open_run: a start of the scope from coordinate-open.sh, which takes its args
# file away; sets S, and OPEN_OUT to the opener's output.
open_run() { # open_run [plugin-root]
    local root=${1:-$PR}
    printf '["docs/roadmaps/ROADMAP-store.md"]' > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$root/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$root" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
has_line() { grep -qx -- "$1" <<< "$OPEN_OUT"; }
write() { # write <script> <args...>: a write script, run from $WD as the agent runs it, on session $S
    local s=$1; shift
    (cd "$WD" && bash "$PS/$s" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err")
}
# keys <session>: every record/ key of the session, its name and its content,
# read through real koto (run-tests.sh's PATH has no cksum, so no digest).
keys() {
    local k
    (cd "$WD" && koto context list "$1" --prefix record/) | jq -r '.[]' | LC_ALL=C sort | while IFS= read -r k; do
        printf '%s %s\n' "$k" "$(cd "$WD" && koto context get "$1" "$k")"
    done
}
# gh_writes: the write calls the gh stand-in recorded.
gh_writes() { grep -E '^(issue|pr) (create|edit|close|ready|comment)|^api (--method|-X) (POST|PATCH|PUT|DELETE)' "$GH_DB.calls"; }
# current: the state as the session holds it, in $T/cur.json, and its written
# time in CURW, for a state edited from it.
current() { (cd "$WD" && session_record "$S") > "$T/cur.json"; CURW=$(jq -r .written "$T/cur.json"); }
edited() { # edited <jq program> <out>: the current state changed by the program, in normal form at CURW
    state_json "$(jq -c "$1" "$T/cur.json")" "$CURW" > "$2"
}

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-store.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n')"

# A koto older than the session store's features stops the start before any
# session opens, naming what it lacks (PRD R2). The branch is on what koto
# offers, never on the outcome.
if ! koto_store_ready; then
    BEFORE=$(koto session list 2>/dev/null | jq -r '[.[].id] | sort | join(" ")')
    if open_run; then
        bad "a koto without the session store's features refuses the start" "it opened $S"
    else
        case "$OPEN_OUT $(cat "$T/open.err")" in
            *store-unsupported*) ok "a koto without the session store's features refuses the start as store-unsupported" ;;
            *) bad "a koto without the session store's features refuses the start as store-unsupported" "$OPEN_OUT $(cat "$T/open.err")" ;;
        esac
    fi
    eq "  ... opening no session" "$BEFORE" "$(koto session list 2>/dev/null | jq -r '[.[].id] | sort | join(" ")')"
    echo "koto lacks the session store's features; the store's own cases need a newer koto"
    done_tests session-store-engine
    exit $?
fi

echo "== 1. a start names no store =="
open_run || { bad "the session opens" "$(cat "$T/open.err")"; done_tests session-store-engine; exit 1; }
ok "the session opens"
eq "  ... with no STORE variable" "" "$(cd "$WD" && bash "$PS/coord-log.sh" vars --session "$S" | jq -r '.STORE // ""')"
eq "with no record it stops at record_open" record_open "$(at)"
reset_calls
write state-open.sh; eq "state-open.sh opens the record" 0 $?
(cd "$WD" && koto context exists "$S" record/meta) && ok "  ... in the run's record/meta" || bad "  ... in the run's record/meta" "$(cat "$T/w.err")"
eq "  ... opening nothing on GitHub" "" "$(gh_writes)"
eq "the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
eq "  ... and coord/source.json reads session" session "$( (cd "$WD" && koto context get "$S" coord/source.json) | jq -r '.source // empty')"

echo "== 2. writes land in the keys =="
current
edited '.deferrals = [{deferral: "a", reason: "r", raised: "2026-09-25T10:00Z", disposition: ""}]' "$T/w1.md"
reset_calls
write state-write.sh --state-file "$T/w1.md"; eq "state-write.sh writes the record" 0 $?
eq "  ... into record/deferrals" a "$(cd "$WD" && koto context get "$S" record/deferrals | jq -r '.[0].deferral')"
write state-stored-set.sh --run arguments "docs/roadmaps/ROADMAP-store.md" --by "the human" \
    && write state-stored-set.sh --run cap 2 --by "the human" \
    && write state-stored-set.sh --run coordinator coord-test --by coord-test \
    && write state-stored-set.sh --run reports-to "the human" --by "the human"
eq "state-stored-set.sh writes the stored set, reports-to included" 0 $?
eq "  ... with no store row" "" "$(cd "$WD" && koto context get "$S" record/run | jq -r '[.[] | select(.key == "store")] | length | select(. > 0)')"
eq "  ... neither touching GitHub" "" "$(gh_writes)"
eq "the run passes reconcile on the keys" pick "$(at --with-data '{"reconciled":"reported"}')"

echo "== 2b. a second start on this host resumes the run (PRD R12) =="
FIRST=$S
SESSIONS=$(koto session list | jq -r '[.[].id] | sort | join(" ")')
sleep 1
open_run; eq "a second start prints the first run's name" "$FIRST" "$S"
has_line resumed=1 && ok "  ... as resumed" || bad "  ... as resumed" "$OPEN_OUT"
grep -q '^cancelled=' <<< "$OPEN_OUT" && bad "  ... cancelling nothing" "$OPEN_OUT" || ok "  ... cancelling nothing"
eq "  ... opening no session" "$SESSIONS" "$(koto session list | jq -r '[.[].id] | sort | join(" ")')"
eq "  ... and the run goes on where it stood" pick "$(cd "$WD" && koto status "$S" | jq -r .current_state)"

echo "== 3. each refusal leaves every key as it was =="
current
SNAP=$(keys "$S")
[ -n "$SNAP" ] && ok "the snapshot reads the keys" || bad "the snapshot reads the keys" ""
edited '.run |= map(if .key == "cap" then .value = "3" else . end)' "$T/nonowner.md"
[ "$(jq -r '.run[] | select(.key == "cap") | .value' "$T/nonowner.md")" = 3 ] && ok "the non-owner's state changes the cap" || bad "the non-owner's state changes the cap" "$(jq -c .run "$T/nonowner.md")"
write state-write.sh --state-file "$T/nonowner.md"; eq "a non-owner changing record/run is refused" 65 $?
eq "  ... and changes no key" "$SNAP" "$(keys "$S")"
write state-write.sh --state-file "$T/w1.md"; eq "a state edited from an older written time is refused" 12 $?
eq "  ... and changes no key" "$SNAP" "$(keys "$S")"
# No size budget: a state past 60,000 bytes is written, so this case moves the
# keys on and takes a fresh snapshot for the refusals after it.
state_json "$(jq -c --arg r "$(head -c 61000 /dev/zero | tr '\0' 'x')" '.deferrals[0].reason = $r' "$T/cur.json")" "$CURW" > "$T/big.md"
[ "$(wc -c < "$T/big.md")" -gt 60000 ] && ok "the big state is past 60,000 bytes" || bad "the big state is past 60,000 bytes" "$(wc -c < "$T/big.md")"
write state-write.sh --state-file "$T/big.md"; eq "a state over 60,000 bytes is written" 0 $?
eq "  ... into record/deferrals" 61000 "$(cd "$WD" && koto context get "$S" record/deferrals | jq -r '.[0].reason | length')"
current
SNAP=$(keys "$S")
edited '.deferrals += [{deferral: "b", reason: "r", raised: "2026-09-25T10:00Z", disposition: ""}]' "$T/w2.md"
eq "koto next --to moves the run" ask_up "$(at --to ask_up)"
write state-write.sh --state-file "$T/w2.md"; eq "a write after koto next --to is refused" 10 $?
grep -q 'directed transition' "$T/w.err" && ok "  ... as a directed transition" || bad "  ... as a directed transition" "$(cat "$T/w.err")"
eq "  ... and changes no key" "$SNAP" "$(keys "$S")"
# The run with a directed transition can't be resumed (every write from it is
# refused), so the next start carries its keys into a new run (PRD R12).
OLD=$S
sleep 1
open_run && [ "$S" != "$OLD" ] && ok "a later run of the scope opens" || bad "a later run of the scope opens" "$(cat "$T/open.err")"
has_line "carried=$OLD" && has_line "cancelled=$OLD" && ok "  ... carrying the old run's record and cancelling it" \
    || bad "  ... carrying the old run's record and cancelling it" "$OPEN_OUT $(cat "$T/open.err")"
eq "  ... the new run holding every record/ key the old one did, byte for byte" "$(keys "$OLD")" "$(keys "$S")"
eq "  ... and its find reaching reconcile on the session store" reconcile "$(at)"
NEW=$S
SNAP=$(keys "$OLD")
S=$OLD
write state-write.sh --state-file "$T/w2.md"; eq "a write from the run that is no longer live is refused" 10 $?
grep -q 'is not the live' "$T/w.err" && ok "  ... as not the live run" || bad "  ... as not the live run" "$(cat "$T/w.err")"
eq "  ... and changes no key" "$SNAP" "$(keys "$OLD")"
S=$NEW

echo "== 4. a changed template carries the record into a new run (PRD R12) =="
# The plugin with a changed template whose compat table no longer lists the
# old one at its compat number: the live run, compiled from the old one, isn't
# resumed. Its record/ and legs/ keys are carried, and its log stays readable.
# No writer makes a legs/ key yet, so the case writes one itself.
mkdir -p "$T/plugin2"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin2/"
printf '\n<!-- a change to the template, for the carry case -->\n' >> "$T/plugin2/skills/coordinate/koto-templates/coordinate.md"
COMPAT2=$T/plugin2/skills/coordinate/koto-templates/coordinate.compat.json
jq '.compat += 1' "$COMPAT2" > "$T/compat2.json" && mv "$T/compat2.json" "$COMPAT2"
printf '{"request":"req-1","leg":"deliver"}' | (cd "$WD" && koto context add "$S" legs/req-1/deliver)
OLD=$S
sleep 1
open_run "$T/plugin2" && [ "$S" != "$OLD" ] && ok "a start with a changed template opens a new run" || bad "a start with a changed template opens a new run" "$(cat "$T/open.err")"
has_line "carried=$OLD" && ok "  ... carrying the old one's record" || bad "  ... carrying the old one's record" "$OPEN_OUT $(cat "$T/open.err")"
grep -q "compat table doesn't list" "$T/open.err" && ok "  ... because its compat table doesn't list the run's template" || bad "  ... because its compat table doesn't list the run's template" "$(cat "$T/open.err")"
eq "  ... with every record/ key" "$(keys "$OLD")" "$(keys "$S")"
eq "  ... and its legs/ key" '{"request":"req-1","leg":"deliver"}' "$(cd "$WD" && koto context get "$S" legs/req-1/deliver)"
[ -r "$(koto session dir "$OLD")/koto-$OLD.state.jsonl" ] && ok "  ... the old run's log kept readable" || bad "  ... the old run's log kept readable" ""

echo "== 5. a host where no session holds the record (PRD R12) =="
# Another HOME is another koto session store: nothing here holds the record,
# and with no record on GitHub to point at it, the start is a new scope's.
mkdir -p "$T/home2"
HOME_SAVED=$HOME; export HOME="$T/home2"
open_run && ok "a start on another host opens a run" || bad "a start on another host opens a run" "$(cat "$T/open.err")"
grep -qx 'resumed=1' <<< "$OPEN_OUT" && bad "  ... resuming nothing" "$OPEN_OUT" || ok "  ... resuming nothing"
eq "  ... whose find stops at record_open" record_open "$(at)"
export HOME="$HOME_SAVED"

done_tests session-store-engine
