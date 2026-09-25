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
#     replaced by a fresh session at `preflight`
#   - no session: a new one
# and then a session built from another template (template_mismatch, left
# alone), the mode from the flags and from the `## Execution Mode:` header,
# MERGE true unless --no-merge, the forwarded flags, koto's refusals of bad or
# repeated values, a token with shell metacharacters, and the args file's
# removal on every path.
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

T="$(mktemp -d "${TMPDIR:-/tmp}/deliver-open-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
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
eq "a fresh session at preflight" preflight "$(state_of t-new)"
eq "MODE interactive with no flag and no header" '["interactive"]' "$(var MODE)"
eq "MERGE true without --no-merge" '["true"]' "$(var MERGE)"
eq "TOPIC" '["t-new"]' "$(var TOPIC)"
eq "PLUGIN_ROOT" "[\"$PLUGIN\"]" "$(var PLUGIN_ROOT)"
eq "no COORDINATION, UPSTREAM or MAX_ROUNDS pair" '[]' "$(vars '[.[] | select(.[0] == "COORDINATION" or .[0] == "UPSTREAM" or .[0] == "MAX_ROUNDS")]')"
args_gone "no session"

echo "== a same-origin live session =="
k init deliver-t-live --template "$(tpl)" --var TOPIC=t-live --var PLUGIN_ROOT="$PLUGIN" --var MERGE=false >/dev/null 2>&1
printf 'old' | k context add deliver-t-live marker >/dev/null
open_deliver '["t-live","--auto"]'
eq "exit 0" 0 "$RC"
has "prints opened=new (a fresh session)" "opened=new" "$STDOUT"
eq "the fresh session is at preflight" preflight "$(state_of t-live)"
if [ -z "$(ctx_get t-live marker)" ]; then ok "the earlier session's context is gone"; else bad "the earlier session's context is gone"; fi
eq "this invocation's MERGE, not the earlier one's" '["true"]' "$(var MERGE)"
eq "this invocation's MODE" '["auto"]' "$(var MODE)"

echo "== a same-origin terminal session =="
k init deliver-t-done --template "$(tpl)" --var TOPIC=t-done --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
# Drive it to a terminal: its repository is private, so preflight refuses.
(cd "$R" && git -c user.email=t@example.invalid -c user.name=t mv CLAUDE.md CLAUDE.keep >/dev/null)
k next deliver-t-done --no-cleanup >/dev/null 2>&1
(cd "$R" && git mv CLAUDE.keep CLAUDE.md >/dev/null)
eq "precondition: the earlier run is terminal" done_refused "$(state_of t-done)"
open_deliver '["t-done"]'
eq "exit 0" 0 "$RC"
eq "replaced by a fresh session at preflight" preflight "$(state_of t-done)"
if k status deliver-t-done | jq -e '.result == null' >/dev/null; then ok "the fresh session carries no result"; else bad "the fresh session carries no result"; fi

echo "== a same-named session from another worktree =="
KDIR="$OTHER" k init deliver-t-away --template "$(tpl)" --var TOPIC=t-away --var PLUGIN_ROOT="$PLUGIN" >/dev/null 2>&1
printf 'theirs' | KDIR="$OTHER" k context add deliver-t-away marker >/dev/null
open_deliver '["t-away"]'
refused "another worktree"
has "prints refused=origin_mismatch" "refused=origin_mismatch" "$STDOUT"
has "the wording names the other worktree" "another worktree" "$STDERR"
eq "that session is still at preflight" preflight "$(state_of t-away)"
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

open_deliver '["Upper"]'
refused "an uppercase topic"
has "the slug wording" "does not match the required pattern" "$STDERR"

open_deliver '["t-two","words"]'
refused "a second positional word"

open_deliver '["t-meta","--upstream=docs/roadmaps/ROADMAP-$(touch PWNED).md;touch PWNED2"]'
refused "a token with shell metacharacters"
if [ -e "$R/PWNED" ] || [ -e "$R/PWNED2" ]; then bad "the metacharacter token was executed"; else ok "the metacharacter token was not executed"; fi

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
