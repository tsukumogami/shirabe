#!/usr/bin/env bash
# deliver-open_test.sh -- /deliver's koto entry against a real koto.
#
# Usage: bash skills/deliver/scripts/deliver-open_test.sh
#
# Every case writes the invocation's raw tokens to an args file in a private
# directory, runs deliver-open.sh from a fixture repository, and asserts on
# what koto did: the exit code, the printed lines, whether and in which state
# a `deliver-<topic>` session exists afterwards, whether an earlier session was
# replaced or left alone, and that the args file is gone. A pass-through koto
# wrapper (KOTO_BIN, which koto-open.sh honours) keeps a byte copy of the last
# vars file it was handed, so the pairs the tokens became are asserted too.
#
# Cases (the four the entry's contract names first):
#   - a same-named session from another worktree: a collision, refused with
#     origin_mismatch, and that session is unchanged (same state, same context)
#   - a same-origin live session, and a same-origin terminal one: each is
#     replaced by a fresh session at `open_request`
#   - no session: a new one
# and then a session built from another template (template_mismatch, left
# alone), the mode from the flags and from the `## Execution Mode:` header,
# MERGE true unless --no-merge, the forwarded flags (the review-level bound
# among them, whose absence leaves exactly the pairs a run had before it
# existed, and --store), koto's refusals of bad or repeated values, a token with shell metacharacters, and the args file's
# removal on every path. Under --koto-leg: a malformed value refused with no
# koto call; an accepted run bound to the leg, ticked to a terminal, and its
# result read back off the leg; koto's refusals (an invalid topic, a collision
# the probe stops, a leg pinning another topic) recorded on the leg.
#
# The removal (shirabe#1278): a first run, with no session by the name, makes
# no probe and runs no `koto session cleanup`, even under an anchor whose
# hierarchy holds a live session, so koto prints no retention warning. A run
# that does remove a session prints removed= and removed_predates=, yes for
# an earlier live session, no for the session the probe itself made (a
# terminal one's replacement, or a name that was listed but gone by the
# probe). An unreadable session listing falls back to the probe.
#
# koto admits a --var value only inside ^[a-zA-Z0-9._/:@ \-]*$, and
# PLUGIN_ROOT is such a value. When this checkout's path falls outside it,
# PLUGIN_ROOT is a clean symlink under TMPDIR; when TMPDIR is outside it too,
# the suite runs in LOCALIZED mode: PLUGIN_ROOT is a clean placeholder and the
# wrapper hands koto a copy of deliver.md with {{PLUGIN_ROOT}} written out as
# this checkout (still named deliver.md, so koto's template check is the real
# one). CI runs with a clean TMPDIR and so runs the shipped template.
#
# Exit 0 when every case passed; SKIP (exit 0) when koto or jq is absent.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
OPEN="$HERE/deliver-open.sh"
KOTO_OPEN="$REPO/scripts/koto-open.sh"
TEMPLATE="$REPO/skills/deliver/koto-templates/deliver.md"

for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- no case ran"; exit 0; }
done
REAL_KOTO=$(command -v koto)
if ! "$REAL_KOTO" init --help 2>/dev/null | grep -q -- '--vars-file'; then
    echo "SKIP: this koto predates --vars-file -- no case ran"
    exit 0
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/deliver-open-test.XXXXXX")" || exit 1
T="$(cd -P "$T" && pwd -P)" || exit 1
trap 'case "$T" in */deliver-open-test.*) rm -rf "$T" ;; esac' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$2] not in [$3]" ;; esac; }

clean() { case "$1" in *[!a-zA-Z0-9._/:@\ -]*) return 1 ;; esac; return 0; }

LOCAL_TEMPLATE=""
if clean "$REPO"; then
    PLUGIN="$REPO"
elif clean "$T"; then
    ln -s "$REPO" "$T/plugin"
    PLUGIN="$T/plugin"
else
    PLUGIN="/opt/shirabe-plugin-placeholder"
    mkdir -p "$T/localized"
    LOCAL_TEMPLATE="$T/localized/deliver.md"
    sed "s#{{PLUGIN_ROOT}}#$REPO#g" "$TEMPLATE" >"$LOCAL_TEMPLATE"
    echo "NOTE: LOCALIZED mode -- this checkout and TMPDIR both hold a character koto"
    echo "      refuses in a --var value; the wrapper substitutes a template copy."
fi

WRAP="$T/bin/koto"
mkdir -p "$T/bin"
cat >"$WRAP" <<'WRAPPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DELIVER_TEST_LOG/koto.argv"
# DELIVER_TEST_LIST stands in for koto's session listing: `fail` makes the
# listing fail, anything else is printed as the listing.
if [ "${1-} ${2-}" = "session list" ] && [ -n "${DELIVER_TEST_LIST:-}" ]; then
    [ "$DELIVER_TEST_LIST" = fail ] && exit 1
    printf '%s\n' "$DELIVER_TEST_LIST"
    exit 0
fi
out=()
prev=""
for a in "$@"; do
    orig="$a"
    if [ "$prev" = "--vars-file" ]; then cp "$a" "$DELIVER_TEST_LOG/vars.last" 2>/dev/null; fi
    if [ "$prev" = "--template" ] && [ -n "${DELIVER_TEST_TEMPLATE:-}" ]; then a="$DELIVER_TEST_TEMPLATE"; fi
    out+=("$a")
    prev="$orig"
done
exec "$DELIVER_TEST_REAL_KOTO" "${out[@]}"
WRAPPER
chmod +x "$WRAP"
export DELIVER_TEST_LOG="$T" DELIVER_TEST_REAL_KOTO="$REAL_KOTO" DELIVER_TEST_TEMPLATE="$LOCAL_TEMPLATE"
export HOME="$T/home"
mkdir -p "$HOME"

mkrepo() { # mkrepo <dir> [CLAUDE.md text]
    mkdir -p "$1"
    git -C "$1" init -q
    printf '%s\n' "${2:-# r}" >"$1/CLAUDE.md"
    git -C "$1" add CLAUDE.md
    git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -q -m fixture
}
R="$T/repo"
mkrepo "$R" "# r

## Repo Visibility: Public"
OTHER="$T/other"
mkrepo "$OTHER"

k() { (cd "${KDIR:-$R}" && "$REAL_KOTO" "$@"); }
state_of() { k status "deliver-$1" 2>/dev/null | jq -r '.current_state // "none"'; }
ctx_get() { local v; v=$(k context get "deliver-$1" "$2" 2>/dev/null) && printf "%s" "$v"; }
tpl() { if [ -n "$LOCAL_TEMPLATE" ]; then printf '%s' "$LOCAL_TEMPLATE"; else printf '%s' "$TEMPLATE"; fi; }
# to_terminal <topic> -- tick the run once (it opens its own request and waits
# on the scope leg), abandon that request, and tick again: done_error.
to_terminal() {
    local own
    k next "deliver-$1" --no-cleanup >/dev/null 2>&1
    own=$(k request list --coordinator-of-record "deliver-$1" --state open | jq -r '.requests[0].request_id // ""')
    [ -n "$own" ] && k request abandon-request "$own" --rationale test >/dev/null 2>&1
    k next "deliver-$1" --no-cleanup >/dev/null 2>&1
}

RC=0; STDOUT=""; STDERR=""; ARGS=""; ARGS_DIR=""
open_deliver() { # open_deliver <tokens-json> [dir]
    ARGS_DIR=$(bash "$KOTO_OPEN" --alloc-dir)
    ARGS="$ARGS_DIR/args.json"
    printf '%s' "$1" >"$ARGS"
    : >"$T/koto.argv"
    rm -f "$T/vars.last"
    (cd "${2:-$R}" && KOTO_BIN="$WRAP" bash "$OPEN" --plugin-root "$PLUGIN" "$ARGS" >"$T/out" 2>"$T/err")
    RC=$?
    STDOUT=$(cat "$T/out")
    STDERR=$(cat "$T/err")
}
vars() { jq -c "${1:-.}" "$T/vars.last" 2>/dev/null; }
var() { vars "[.[] | select(.[0] == \"$1\") | .[1]]"; }
args_gone() {
    if [ -e "$ARGS" ] || [ -e "$ARGS_DIR" ]; then bad "$1: the args file is removed" "$ARGS"; else ok "$1: the args file is removed"; fi
}
refused() { # refused <label>
    eq "$1: exit 2" 2 "$RC"
    has "$1: prints outcome=error" "outcome=error" "$STDOUT"
    has "$1: prints step=deliver:refused" "step=deliver:refused" "$STDOUT"
    args_gone "$1"
}

echo "== no session =="
open_deliver '["t-new"]'
eq "exit 0" 0 "$RC"
has "prints opened=new" "opened=new" "$STDOUT"
has "prints session=deliver-t-new" "session=deliver-t-new" "$STDOUT"
if [[ "$(k context get deliver-t-new run_id 2>/dev/null)" =~ ^[0-9a-f]{32}$ ]]; then
    ok "the opened session carries a run identity (run_id, minted at the open)"
else
    bad "the opened session carries a run identity" "[$(k context get deliver-t-new run_id 2>&1)]"
fi
eq "a fresh session at open_request" open_request "$(state_of t-new)"
eq "MODE interactive with no flag and no header" '["interactive"]' "$(var MODE)"
eq "MERGE true without --no-merge" '["true"]' "$(var MERGE)"
eq "TOPIC" '["t-new"]' "$(var TOPIC)"
eq "PLUGIN_ROOT" "[\"$PLUGIN\"]" "$(var PLUGIN_ROOT)"
eq "no COORDINATION, UPSTREAM or MAX_ROUNDS pair" '[]' "$(vars '[.[] | select(.[0] == "COORDINATION" or .[0] == "UPSTREAM" or .[0] == "MAX_ROUNDS")]')"
eq "no flags: exactly the pairs a run had before the review-level bound existed" \
    '["TOPIC","MODE","MERGE","PLUGIN_ROOT"]' "$(vars 'map(.[0])')"
args_gone "no session"
if grep -q "session cleanup" "$T/koto.argv"; then bad "no session: no koto session cleanup ran" "$(cat "$T/koto.argv")"; else ok "no session: no koto session cleanup ran"; fi
if grep -q -- "--attach-live" "$T/koto.argv"; then bad "no session: no probe was made" "$(cat "$T/koto.argv")"; else ok "no session: no probe was made"; fi
case "$STDOUT" in *removed=*) bad "no session: no removed= line" "$STDOUT" ;; *) ok "no session: no removed= line" ;; esac

echo "== a first run under an anchor with a live session in its hierarchy =="
# The probe used to open deliver-<topic> on a first run, and the cleanup that
# followed removed it and warned that the retention rule would have kept it,
# naming every live session in the caller's hierarchy. A first run now makes
# no probe and removes nothing.
if k session anchor open --harness-session t-first-run --source startup >/dev/null 2>&1; then
    export KOTO_ANCHOR=anchor-t-first-run
    k init deliver-t-peer --template "$(tpl)" --var TOPIC=t-peer --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
    open_deliver '["t-first","--auto"]'
    eq "a first run: exit 0" 0 "$RC"
    has "a first run: prints session=deliver-t-first" "session=deliver-t-first" "$STDOUT"
    eq "a first run: the fresh session is at open_request" open_request "$(state_of t-first)"
    eq "a first run: the fresh session carries this invocation's MODE" '["auto"]' "$(var MODE)"
    if grep -q "session cleanup" "$T/koto.argv"; then bad "a first run: no koto session cleanup ran" "$(cat "$T/koto.argv")"; else ok "a first run: no koto session cleanup ran"; fi
    case "$STDERR" in *"retention rule"*) bad "a first run: no retention warning" "$STDERR" ;; *) ok "a first run: no retention warning" ;; esac
    case "$STDOUT" in *removed=*) bad "a first run: no removed= line" "$STDOUT" ;; *) ok "a first run: no removed= line" ;; esac
    eq "a first run: the live session in the hierarchy is untouched" open_request "$(state_of t-peer)"

    # The name was listed but gone by the probe: the probe makes the session,
    # and removing it says so, without koto's retention warning about it.
    export DELIVER_TEST_LIST='[{"id":"deliver-t-race"}]'
    open_deliver '["t-race"]'
    unset DELIVER_TEST_LIST
    eq "a probe that made the session: exit 0" 0 "$RC"
    has "a probe that made the session: removed= names it" "removed=deliver-t-race" "$STDOUT"
    has "a probe that made the session: it does not predate this invocation" "removed_predates=no" "$STDOUT"
    case "$STDERR" in *"retention rule"*) bad "a probe that made the session: no retention warning" "$STDERR" ;; *) ok "a probe that made the session: no retention warning" ;; esac
    eq "a probe that made the session: session= is the last line" "session=deliver-t-race" "$(printf '%s\n' "$STDOUT" | tail -1)"
    eq "a probe that made the session: the fresh session is at open_request" open_request "$(state_of t-race)"
    unset KOTO_ANCHOR
else
    echo "SKIP: this koto has no session anchors -- the first-run hierarchy cases did not run"
fi

echo "== the session listing cannot be read =="
# Without the listing the probe runs as before: it makes the session, and the
# removal says the session is this invocation's.
export DELIVER_TEST_LIST=fail
open_deliver '["t-nolist"]'
unset DELIVER_TEST_LIST
eq "an unreadable listing: exit 0" 0 "$RC"
has "an unreadable listing: the probe ran" "--attach-live" "$(cat "$T/koto.argv")"
has "an unreadable listing: removed_predates=no" "removed_predates=no" "$STDOUT"
eq "an unreadable listing: the fresh session is at open_request" open_request "$(state_of t-nolist)"

echo "== a same-origin live session =="
k init deliver-t-live --template "$(tpl)" --var TOPIC=t-live --var PLUGIN_ROOT="$PLUGIN" --var MERGE=false >/dev/null 2>&1
printf 'old' | k context add deliver-t-live marker >/dev/null
open_deliver '["t-live","--auto"]'
eq "exit 0" 0 "$RC"
has "prints opened=new (a fresh session)" "opened=new" "$STDOUT"
eq "the fresh session is at open_request" open_request "$(state_of t-live)"
if [ -z "$(ctx_get t-live marker)" ]; then ok "the earlier session's context is gone"; else bad "the earlier session's context is gone"; fi
eq "this invocation's MERGE, not the earlier one's" '["true"]' "$(var MERGE)"
eq "this invocation's MODE" '["auto"]' "$(var MODE)"
has "a live session: the cleanup ran" "session cleanup deliver-t-live" "$(cat "$T/koto.argv")"
has "a live session: removed= names it" "removed=deliver-t-live" "$STDOUT"
has "a live session: it predates this invocation" "removed_predates=yes" "$STDOUT"
eq "a live session: session= is the last line" "session=deliver-t-live" "$(printf '%s\n' "$STDOUT" | tail -1)"

echo "== a same-origin terminal session =="
k init deliver-t-done --template "$(tpl)" --var TOPIC=t-done --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
# Drive it to a terminal: abandon the request its first tick opened.
to_terminal t-done
eq "precondition: the earlier run is terminal" done_error "$(state_of t-done)"
open_deliver '["t-done"]'
eq "exit 0" 0 "$RC"
eq "replaced by a fresh session at open_request" open_request "$(state_of t-done)"
if k status deliver-t-done | jq -e '.result == null' >/dev/null; then ok "the fresh session carries no result"; else bad "the fresh session carries no result"; fi
# koto's replace already took the finished run; what the cleanup removes is
# the replacement the probe made.
has "a terminal session: removed= names the name" "removed=deliver-t-done" "$STDOUT"
has "a terminal session: the removed replacement does not predate this invocation" "removed_predates=no" "$STDOUT"

echo "== a same-origin terminal session its hierarchy holds =="
# From koto 0.23.0 a finished session another live session names is kept, and
# the probe's --replace-terminal moves it aside or refuses. The floor job's
# older koto has neither, so the cases run only where koto does.
if KOTO_BIN="$REAL_KOTO" KOTO_FLOOR=0.23.0 bash "$REPO/scripts/assert-koto-floor.sh" >/dev/null 2>&1; then
    cat >"$T/peer.md" <<'PEER'
---
name: peer
version: "1.0"
description: A session that stays live.
initial_state: wait
states:
  wait:
    accepts:
      go:
        type: enum
        values: [now]
        required: true
    transitions:
      - target: over
        when:
          go: now
  over:
    terminal: true
---

## wait

Wait.

## over

Over.
PEER
    k init hold-peer --template "$T/peer.md" >/dev/null 2>&1
    k init deliver-t-held --template "$(tpl)" --var TOPIC=t-held --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
    k session link deliver-t-held --dispatched-by hold-peer >/dev/null 2>&1
    to_terminal t-held
    eq "precondition: the held run is terminal" done_error "$(state_of t-held)"
    open_deliver '["t-held"]'
    eq "a held finished run: exit 0" 0 "$RC"
    has "a held finished run: prints opened=new for the fresh session" "opened=new" "$STDOUT"
    has "a held finished run: the probe's moved_to is printed" "moved_to=deliver-t-held_r1" "$STDOUT"
    has "a held finished run: the probe's moved_reason is printed" "moved_reason=" "$STDOUT"
    eq "a held finished run: session= is still the last line" "session=deliver-t-held" "$(printf '%s\n' "$STDOUT" | tail -1)"
    eq "a held finished run: the fresh session is at open_request" open_request "$(state_of t-held)"
    eq "a held finished run: the moved run keeps its terminal" done_error \
        "$(k status deliver-t-held_r1 2>/dev/null | jq -r '.current_state // "none"')"

    k init deliver-t-busy --template "$(tpl)" --var TOPIC=t-busy --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
    k session link deliver-t-busy --dispatched-by hold-peer >/dev/null 2>&1
    k init deliver-t-busy.k --template "$T/peer.md" --parent deliver-t-busy >/dev/null 2>&1
    to_terminal t-busy
    open_deliver '["t-busy"]'
    eq "a held run with live work under it: exit 75" 75 "$RC"
    has "a held run with live work under it: refused=replace_held_live" "refused=replace_held_live" "$STDOUT"
    has "a held run with live work under it: the live session is listed" 'live=["deliver-t-busy.k"]' "$STDOUT"
    has "a held run with live work under it: outcome=error" "outcome=error" "$STDOUT"
    has "a held run with live work under it: step=deliver:refused" "step=deliver:refused" "$STDOUT"
    has "a held run with live work under it: /deliver's wording" "/deliver did not replace it" "$STDERR"
    eq "a held run with live work under it: the finished run is untouched" done_error "$(state_of t-busy)"
    if grep -q "session cleanup" "$T/koto.argv"; then bad "a held run with live work under it: no cleanup was attempted" "$(cat "$T/koto.argv")"; else ok "a held run with live work under it: no cleanup was attempted"; fi
    args_gone "a held run with live work under it"
else
    echo "SKIP: this koto predates hierarchy retention (0.23.0) -- the held-run cases did not run"
fi

echo "== a same-named session from another worktree =="
KDIR="$OTHER" k init deliver-t-away --template "$(tpl)" --var TOPIC=t-away --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
printf 'theirs' | KDIR="$OTHER" k context add deliver-t-away marker >/dev/null
open_deliver '["t-away"]'
refused "another worktree"
has "prints refused=origin_mismatch" "refused=origin_mismatch" "$STDOUT"
has "the wording names the other worktree" "another worktree" "$STDERR"
eq "that session is still at open_request" open_request "$(state_of t-away)"
eq "and its context is untouched" theirs "$(KDIR="$OTHER" ctx_get t-away marker)"
if grep -q "session cleanup" "$T/koto.argv"; then bad "no cleanup was attempted" "$(cat "$T/koto.argv")"; else ok "no cleanup was attempted"; fi

echo "== a session from another template =="
mkdir -p "$T/tpl"
cat >"$T/tpl/other.md" <<'TPL'
---
name: other
version: "1.0"
description: another template under a deliver-* name
initial_state: work
variables:
  TOPIC:
    required: true
  PLUGIN_ROOT:
    required: true
states:
  work:
    accepts:
      go:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: done
        when:
          go: "yes"
  done:
    terminal: true
---
## work
w
## done
d
TPL
k init deliver-t-tpl --template "$T/tpl/other.md" --var TOPIC=t-tpl --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
open_deliver '["t-tpl"]'
refused "another template"
has "prints refused=template_mismatch" "refused=template_mismatch" "$STDOUT"
eq "that session is left alone" work "$(state_of t-tpl)"

echo "== the mode and the merge setting =="
printf '# r\n\n## Repo Visibility: Public\n\n## Execution Mode: auto\n' >"$T/claude-auto.md"
cp "$R/CLAUDE.md" "$T/claude-orig.md"
cp "$T/claude-auto.md" "$R/CLAUDE.md"
open_deliver '["t-hdr"]'
eq "no flag with ## Execution Mode: auto: MODE auto" '["auto"]' "$(var MODE)"
open_deliver '["t-hdr","--interactive"]'
eq "--interactive wins over the header" '["interactive"]' "$(var MODE)"
cp "$T/claude-orig.md" "$R/CLAUDE.md"
open_deliver '["t-flags","--no-merge","--coordinated","--max-rounds=7","--upstream","docs/roadmaps/ROADMAP-x.md"]'
eq "exit 0" 0 "$RC"
eq "--no-merge: MERGE false" '["false"]' "$(var MERGE)"
eq "--coordinated" '["coordinated"]' "$(var COORDINATION)"
eq "--max-rounds=7" '["7"]' "$(var MAX_ROUNDS)"
eq "--upstream <path>" '["docs/roadmaps/ROADMAP-x.md"]' "$(var UPSTREAM)"
open_deliver '["t-bound","--review-floor=standard","--review-ceiling=full"]'
eq "the review-level bound: exit 0" 0 "$RC"
eq "--review-floor=standard" '["standard"]' "$(var REVIEW_FLOOR)"
eq "--review-ceiling=full" '["full"]' "$(var REVIEW_CEILING)"
eq "the bound session is at open_request" open_request "$(state_of t-bound)"
open_deliver '["t-store","--store","session"]'
eq "--store session: exit 0" 0 "$RC"
eq "--store session reaches the session as STORE" '["session"]' "$(var STORE)"
eq "the --store session is at open_request" open_request "$(state_of t-store)"
open_deliver '["t-store2","--store=github"]'
eq "--store=github: STORE github" '["github"]' "$(var STORE)"

echo "== koto's refusals =="
open_deliver '["t-dup","--auto","--interactive"]'
refused "--auto --interactive"
has "refused=duplicate_var" "refused=duplicate_var" "$STDOUT"
has "the wording names both flags" "--interactive" "$STDERR"
eq "no session" none "$(state_of t-dup)"

open_deliver '["t-dup2","--no-merge","--no-merge"]'
refused "--no-merge twice"
eq "no session" none "$(state_of t-dup2)"

open_deliver '["t-rounds","--max-rounds=0"]'
refused "--max-rounds=0"
has "names the flag" "--max-rounds" "$STDERR"

open_deliver '["t-up","--upstream"]'
refused "a bare --upstream"

open_deliver '["t-floor","--review-floor=medium"]'
refused "--review-floor=medium"
has "refused=invalid_var" "refused=invalid_var" "$STDOUT"
has "names the flag" "--review-floor" "$STDERR"
eq "no session" none "$(state_of t-floor)"

open_deliver '["t-ceil","--review-ceiling=light","--review-ceiling=full"]'
refused "--review-ceiling twice"
has "refused=duplicate_var" "refused=duplicate_var" "$STDOUT"
has "names the flag" "--review-ceiling" "$STDERR"

open_deliver '["t-barefloor","--review-floor"]'
refused "a bare --review-floor"

open_deliver '["t-storebad","--store","bogus"]'
refused "--store bogus"
has "refused=invalid_var" "refused=invalid_var" "$STDOUT"
has "names the flag" "--store" "$STDERR"
eq "no session" none "$(state_of t-storebad)"

open_deliver '["t-storedup","--store=github","--store","session"]'
refused "--store twice"
has "refused=duplicate_var" "refused=duplicate_var" "$STDOUT"
has "names the flag" "--store" "$STDERR"

open_deliver '["t-barestore","--store"]'
refused "a bare --store"

open_deliver '["Upper"]'
refused "an uppercase topic"
has "the slug wording" "does not match the required pattern" "$STDERR"

open_deliver '["t-two","words"]'
refused "a second positional word"

open_deliver '["t-meta","--upstream=docs/roadmaps/ROADMAP-$(touch PWNED).md;touch PWNED2"]'
refused "a token with shell metacharacters"
if [ -e "$R/PWNED" ] || [ -e "$R/PWNED2" ]; then bad "the metacharacter token was executed"; else ok "the metacharacter token was not executed"; fi

echo "== --koto-leg =="
# leg <req> <jq path> -- a field of the request's `deliver` leg.
leg() { k request get "$1" 2>/dev/null | jq -c ".legs.deliver$2"; }
new_request() { # new_request <topic> -- a request with one `deliver` leg
    k request create --with-data "$(jq -nc --arg t "$1" '{legs: [{name: "deliver", role: "deliver", template: "deliver.md", inputs: {TOPIC: $t}}]}')" \
        --requested-by test --coordinator-of-record test | jq -r '.request_id'
}

# A malformed --koto-leg is this script's own refusal: exit 64, no koto call.
for tok in '"--koto-leg=abc"' '"--koto-leg=req1:scope"' '"--koto-leg=:deliver"' '"--koto-leg=BAD:deliver"' \
           '"--koto-leg"' '"--koto-leg","--auto"' '"--koto-leg=r1:deliver","--koto-leg","r2:deliver"'; do
    open_deliver "[\"t-bad\",$tok]"
    eq "--koto-leg [$tok]: usage exit 64" 64 "$RC"
    has "--koto-leg [$tok]: prints outcome=error" "outcome=error" "$STDOUT"
    if [ -s "$T/koto.argv" ]; then bad "--koto-leg [$tok]: no koto call" "$(cat "$T/koto.argv")"; else ok "--koto-leg [$tok]: no koto call"; fi
    args_gone "--koto-leg [$tok]"
done
eq "no session was opened by a malformed --koto-leg" none "$(state_of t-bad)"

# Accepted: the fresh session is bound to the leg, and the leg value never
# reaches TOPIC. Run from a repository with no visibility header, which
# /deliver runs in like any other; its own request is then abandoned, so the
# run ends at done_error and the terminal result is promoted onto the leg.
REQ=$(new_request t-leg)
open_deliver "[\"t-leg\",\"--auto\",\"--koto-leg\",\"$REQ:deliver\"]" "$OTHER"
eq "under --koto-leg: exit 0" 0 "$RC"
has "under --koto-leg: prints session=" "session=deliver-t-leg" "$STDOUT"
eq "the leg value is not part of TOPIC" '["t-leg"]' "$(var TOPIC)"
has "the open carried --koto-leg" "--koto-leg $REQ:deliver" "$(grep '^init ' "$T/koto.argv" | tail -1)"
eq "a first run under --koto-leg: one koto init, the open" 1 "$(grep -c '^init ' "$T/koto.argv")"
eq "the leg is bound to deliver-t-leg" '"deliver-t-leg"' "$(leg "$REQ" .bound_child)"
if grep -q "session cleanup" "$T/koto.argv"; then bad "a first run under --koto-leg: no koto session cleanup ran" "$(cat "$T/koto.argv")"; else ok "a first run under --koto-leg: no koto session cleanup ran"; fi
KDIR="$OTHER" to_terminal t-leg
eq "the run ends at done_error" done_error "$(KDIR="$OTHER" state_of t-leg)"
eq "the leg's result was promoted" '"promoted"' "$(leg "$REQ" .result_source)"
eq "the leg records the terminal state" '"done_error"' "$(leg "$REQ" .result_final_state)"
eq "the leg's payload outcome is error" '"error"' "$(leg "$REQ" .result.payload.outcome)"
eq "the leg carries step=deliver:request-abandoned" '"deliver:request-abandoned"' "$(leg "$REQ" .result.payload.step)"

# koto's refusal of this invocation is recorded on the leg.
REQ=$(new_request t-leg2)
open_deliver "[\"Upper\",\"--koto-leg=$REQ:deliver\"]"
refused "an invalid topic under --koto-leg"
eq "the leg records a refusal" '"refused"' "$(leg "$REQ" .result_source)"
eq "the refusal's reason" '"invalid-var:TOPIC"' "$(leg "$REQ" .result.payload.reason)"

# A collision the probe stops is still recorded on the leg, and the other
# session is left alone.
REQ=$(new_request t-tpl)
open_deliver "[\"t-tpl\",\"--koto-leg=$REQ:deliver\"]"
refused "another template under --koto-leg"
has "prints the probe's refused=template_mismatch" "refused=template_mismatch" "$STDOUT"
if grep -m1 '^init ' "$T/koto.argv" | grep -q -- '--koto-leg'; then bad "the probe carries no leg" "$(cat "$T/koto.argv")"; else ok "the probe carries no leg"; fi
eq "the leg records a refusal for the collision" '"refused"' "$(leg "$REQ" .result_source)"
eq "the collision's recorded reason matches the printed code" '"template-mismatch"' "$(leg "$REQ" .result.payload.reason)"
eq "that session is still left alone" work "$(state_of t-tpl)"

# The same for a session from another worktree: origin_mismatch on both.
REQ=$(new_request t-away)
open_deliver "[\"t-away\",\"--koto-leg=$REQ:deliver\"]"
refused "another worktree's session under --koto-leg"
has "prints the probe's refused=origin_mismatch" "refused=origin_mismatch" "$STDOUT"
eq "the leg records the same refusal" '"origin-mismatch"' "$(leg "$REQ" .result.payload.reason)"
eq "that session is still at open_request" open_request "$(KDIR="$OTHER" state_of t-away)"

# A leg that pins another topic: koto's input check refuses the open.
REQ=$(new_request some-other-topic)
open_deliver "[\"t-mis\",\"--koto-leg=$REQ:deliver\"]"
refused "a leg pinning another TOPIC"
eq "the input mismatch is recorded on the leg" '"refused"' "$(leg "$REQ" .result_source)"
eq "no session was left behind" none "$(state_of t-mis)"

echo "== usage =="
(cd "$R" && bash "$OPEN" >/dev/null 2>&1)
eq "no args file is a usage error" 64 "$?"
(cd "$R" && bash "$OPEN" "$T/nope.json" >/dev/null 2>&1)
eq "a missing args file is a usage error" 64 "$?"
ARGS_DIR=$(bash "$KOTO_OPEN" --alloc-dir); ARGS="$ARGS_DIR/args.json"
printf '{"not":"an array"}' >"$ARGS"
(cd "$R" && bash "$OPEN" --plugin-root "$PLUGIN" "$ARGS" >/dev/null 2>&1)
eq "a non-array args file is a usage error" 64 "$?"
args_gone "a non-array args file"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
