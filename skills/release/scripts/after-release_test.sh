#!/usr/bin/env bash
# after-release_test.sh -- test harness for after-release.sh, /release's
# Phase 7: the installs a repository declares under `## After release`.
#
# Usage: bash skills/release/scripts/after-release_test.sh
#        /bin/bash skills/release/scripts/after-release_test.sh   # bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# Every outside call goes to a stub: koto is a stand-in that keeps the
# session's keys as files, gh answers `release view` from a script of
# answers, and niwa answers the grant lookup as a holder or not. The installs
# themselves are commands the fixture declares, which log what they saw. No
# real koto, gh, niwa or tsuku runs, and nothing outside one mktemp -d
# directory is touched.
#
# Needs bash 3.2+, git and jq. bash 3.2 floor: no associative arrays, no
# namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
AR="$SCRIPT_DIR/after-release.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  expected: %s\n  actual:   %s\n' "$2" "$3"; fi
}
assert_contains() {
    case "$3" in *"$2"*) pass "$1" ;; *) fail "$1"; printf '  missing: %s\n  in: %s\n' "$2" "$3" ;; esac
}
assert_lacks() {
    case "$3" in *"$2"*) fail "$1"; printf '  unexpected: %s\n  in: %s\n' "$2" "$3" ;; *) pass "$1" ;; esac
}

[ -f "$AR" ] || { echo "FAIL: after-release.sh not found at $AR" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/after-release-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */after-release-test.*) rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT
export TMPDIR="$T/tmp"
mkdir -p "$TMPDIR"
export GIT_CEILING_DIRECTORIES="$T"
export HOME="$T/home"
mkdir -p "$HOME"

# --- stubs ----------------------------------------------------------------------------
STUB="$T/stub"
mkdir -p "$STUB"
export STORE="$T/store" GH_LOG="$T/gh.log" GH_ANSWERS="$T/gh.answers" NIWA_LOG="$T/niwa.log" INSTALL_LOG="$T/install.log"

# koto: `context exists|get|add|remove <session> <key>`, kept under $STORE.
cat >"$STUB/koto" <<'EOF'
#!/bin/bash
[ "$1" = context ] || exit 9
f="$STORE/$3/$4"
case "$2" in
    exists) [ -f "$f" ] ;;
    get) [ -f "$f" ] && cat "$f" ;;
    add) [ "$5" = --from-file ] && mkdir -p "${f%/*}" && cp "$6" "$f" ;;
    remove) rm -f "$f" ;;
    *) exit 9 ;;
esac
EOF
# gh: `release view` prints the next line of $GH_ANSWERS ("fail" exits 1);
# the last line repeats once the answers run out.
cat >"$STUB/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
[ "$1 $2" = "release view" ] || exit 1
n=$(grep -c . "$GH_LOG")
a=$(sed -n "${n}p" "$GH_ANSWERS")
[ -n "$a" ] || a=$(tail -1 "$GH_ANSWERS")
[ "$a" = fail ] && { echo "HTTP 404" >&2; exit 1; }
printf '%s\n' "$a"
EOF
# niwa: the grant lookup, as a holder of cut-release or (NIWA_STUB=not-held)
# without it.
cat >"$STUB/niwa" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NIWA_LOG"
grant='[{"authority":"cut-release","sources":["dispatch"]}]'
[ "${NIWA_STUB:-}" = not-held ] && grant='[{"authority":"merge-pr","sources":["dispatch"]}]'
printf '{"schema":"niwa.authority.check/v1","state":"bound","dispatch_id":"%s","grant":%s,"level":"autonomous","points":[{"point":"cut-release","decider":"session","author_exclusion":"off"}]}\n' "$GO_ID" "$grant"
EOF
chmod +x "$STUB/koto" "$STUB/gh" "$STUB/niwa"
# Ids are built at run time: a committed id-shaped literal reads as a real session id.
GO_ID=$(printf "%s-%s-%s-%s-%s" 3c803591 4c01 486f a927 f96ec399d6a7)
GO_SID=$(printf "%s-%s-%s-%s-%s" 0f1e2d3c 4b5a 4968 8776 a5b4c3d2e1f0)
export GO_ID

# --- the fixture: a workspace, an instance in it, a repository in that ----------------
WS="$T/ws"
INST="$WS/inst"
REPO="$INST/repo"
mkdir -p "$WS/.niwa" "$INST/.niwa" "$REPO/.claude/shirabe-extensions"
: >"$WS/.niwa/workspace.toml"
echo '{}' >"$INST/.niwa/instance.json"
# The repository commits a workspace.toml of its own, as dot-niwa does: the
# workspace root is searched for strictly above the repository.
mkdir -p "$REPO/.niwa"
: >"$REPO/.niwa/workspace.toml"
gg() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid "$@"; }
gg init -q
EXT="$REPO/.claude/shirabe-extensions/release.md"
LOCAL="$REPO/.claude/shirabe-extensions/release.local.md"
inst() { # inst <tag> -- a command that logs what it saw
    printf "echo \"%s v=\$RELEASE_VERSION dir=\$PWD ws=\$RELEASE_WORKSPACE_ROOT dry=\$RELEASE_DRY_RUN\" >>\"\$INSTALL_LOG\"" "$1"
}
commit_ext() { # commit_ext <file contents>
    printf '%s\n' "$1" >"$EXT"
    gg add -A
    gg commit -q -m "ext"
}
TOPIC=t-repo
S="$STORE/release-$TOPIC"
# session <dispatched> <concluded> -- the keys Phases 1, 5 and 6 leave; an
# empty value leaves its key out.
session() {
    rm -rf "$STORE" "$GH_LOG" "$NIWA_LOG" "$INSTALL_LOG"
    mkdir -p "$S/work"
    git -C "$REPO" rev-parse HEAD >"$S/work/head"
    [ -z "$1" ] || printf '%s\n' "$1" >"$S/work/dispatched"
    [ -z "$2" ] || printf '%s\n' "$2" >"$S/work/concluded"
    : >"$GH_LOG"
    : >"$NIWA_LOG"
    : >"$INSTALL_LOG"
}
answers() { printf '%s\n' "$@" >"$GH_ANSWERS"; }
DRAFT='{"isDraft":true,"tagName":"v0.3.0"}'
PUBLISHED='{"isDraft":false,"tagName":"v0.3.0"}'

ar() { # ar <args...> -- run after-release.sh from the repository
    RC=0
    (cd "$REPO" && unset NIWA_BIN NIWA_LOOKUP_SECONDS && KOTO_BIN="$STUB/koto" \
        CLAUDE_CODE_SESSION_ID="$GO_SID" PATH="$STUB:$SYS_PATH" \
        RELEASE_AFTER_WAIT_SECONDS="${WAIT:-5}" RELEASE_AFTER_POLL_SECONDS=0 \
        "$BASH_BIN" "$AR" "$@") >"$T/out" 2>"$T/err" || RC=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}
SYS_PATH=/usr/bin:/bin
for tool in jq git; do
    d=$(dirname "$(command -v "$tool")")
    case ":$SYS_PATH:" in *":$d:"*) ;; *) SYS_PATH="$SYS_PATH:$d" ;; esac
done
lines() { grep -c . "$1" 2>/dev/null || true; }

ONE=$(inst one)
TWO=$(inst two)
THREE=$(inst three)
commit_ext "# release extension

## Release checks

- \`scripts/a-check.sh\`

## After release

- \`$ONE\`
- \`$TWO\`
- \`$THREE\`

## Something else

- \`echo never >>\"\$INSTALL_LOG\"\`"

echo "== a holder's installs =="
session 0.3.0 success
answers "$DRAFT" "$DRAFT" "$PUBLISHED"
ar plan "$TOPIC"
assert_eq "plan exits 0 once published" "0" "$RC"
assert_contains "plan says the release is published" "published=v0.3.0" "$OUT"
assert_contains "plan reads the grant again" "go=grant dispatch=$GO_ID" "$OUT"
assert_eq "gh release view was polled until published" "3" "$(lines "$GH_LOG")"
assert_contains "it asked about this run's tag" "release view v0.3.0 --json isDraft,tagName" "$(cat "$GH_LOG")"
assert_eq "niwa was asked once, after the wait" "1" "$(lines "$NIWA_LOG")"
assert_contains "the lookup is for cut-release from the instance root" "--session $GO_SID -C $INST --point cut-release" "$(cat "$NIWA_LOG")"
assert_eq "plan lists the three tracked commands" "3" "$(printf '%s\n' "$OUT" | grep -c '^install tracked ')"
assert_lacks "a bullet under another heading isn't an install" "never" "$OUT"
assert_eq "plan runs nothing" "0" "$(lines "$INSTALL_LOG")"
: >"$GH_LOG"
ar run "$TOPIC"
assert_eq "run exits 0" "0" "$RC"
assert_eq "a holder's run runs each command once, in order, without a question" \
    "one v=0.3.0 dir=$REPO ws=$WS dry=0
two v=0.3.0 dir=$REPO ws=$WS dry=0
three v=0.3.0 dir=$REPO ws=$WS dry=0" "$(cat "$INSTALL_LOG")"
assert_contains "the report lists the first as passed" "result passed tracked 1 $ONE" "$OUT"
assert_contains "the report lists the third as passed" "result passed tracked 3 $THREE" "$OUT"
assert_eq "run makes no gh call" "0" "$(lines "$GH_LOG")"

echo "== the committed extension, not the working copy =="
session 0.3.0 success
answers "$PUBLISHED"
# shellcheck disable=SC2016 # literal backticks
printf -- '- `%s`\n' "$(inst added)" >>"$EXT"
ar plan "$TOPIC"
assert_lacks "a bullet added to the working copy after the release commit isn't listed" "added" "$OUT"
ar run "$TOPIC"
assert_lacks "and doesn't run" "added" "$(cat "$INSTALL_LOG")"
gg checkout -q -- "$EXT"

echo "== the bullet parser =="
commit_ext "## After release

- \`$ONE\`
- reinstall by hand, no command here
- \`$TWO\` and \`echo second-span >>\"\$INSTALL_LOG\"\`

\`\`\`
- \`echo fenced >>\"\$INSTALL_LOG\"\`
\`\`\`"
session 0.3.0 success
answers "$PUBLISHED"
ar plan "$TOPIC"
assert_eq "two commands listed" "2" "$(printf '%s\n' "$OUT" | grep -c '^install tracked ')"
assert_contains "a bullet with no backtick span is skipped with a warning naming it" "reinstall by hand, no command here" "$ERR"
ar run "$TOPIC"
assert_eq "the first backtick span is the command; a fenced bullet is not" \
    "one v=0.3.0 dir=$REPO ws=$WS dry=0
two v=0.3.0 dir=$REPO ws=$WS dry=0" "$(cat "$INSTALL_LOG")"

commit_ext "# release extension

## Release checks

- \`scripts/a-check.sh\`"
session 0.3.0 success
answers "$PUBLISHED"
ar plan "$TOPIC"
assert_eq "no After release heading: plan exits 0" "0" "$RC"
assert_eq "no After release heading: nothing printed about installs" "" "$OUT$ERR"
assert_eq "no After release heading: no wait" "0" "$(lines "$GH_LOG")"
assert_eq "no After release heading: no grant lookup" "0" "$(lines "$NIWA_LOG")"

commit_ext "## After release

- \`$ONE\`
- \`exit 1\`
- \`$THREE\`"

echo "== a session without the grant =="
session 0.3.0 success
answers "$PUBLISHED"
NIWA_STUB=not-held ar plan "$TOPIC"
assert_contains "the grant read before the installs says not held" "go=person reason=not-held" "$OUT"
ar run "$TOPIC"
assert_eq "with no yes nothing runs" "0" "$(lines "$INSTALL_LOG")"
assert_eq "each tracked command is reported declined" "3" "$(printf '%s\n' "$OUT" | grep -c '^result declined tracked ')"
assert_eq "declining is not a failure" "0" "$RC"
commit_ext "## After release

- \`$ONE\`
- \`$TWO\`"
session 0.3.0 success
answers "$PUBLISHED"
NIWA_STUB=not-held ar plan "$TOPIC"
ar run "$TOPIC" --tracked-approved
assert_eq "on a yes each runs" "2" "$(lines "$INSTALL_LOG")"

echo "== a failure stops the list =="
commit_ext "## After release

- \`$ONE\`
- \`echo reinstall-broke; exit 1\`
- \`$THREE\`"
session 0.3.0 success
answers "$PUBLISHED"
ar plan "$TOPIC"
: >"$GH_LOG"
ar run "$TOPIC"
assert_eq "run exits 1 on a failed command" "1" "$RC"
assert_contains "the failure names its command" "result failed tracked 2 echo reinstall-broke; exit 1" "$OUT"
assert_contains "and repeats its last output lines" "  | reinstall-broke" "$OUT"
assert_contains "the command after it is reported not run" "result not-run tracked 3 $THREE" "$OUT"
assert_eq "the command after it didn't run" "one v=0.3.0 dir=$REPO ws=$WS dry=0" "$(cat "$INSTALL_LOG")"
assert_eq "nothing touched the release" "0" "$(lines "$GH_LOG")"

echo "== installs that aren't this run's to make =="
commit_ext "## After release

- \`$ONE\`
- \`$TWO\`"
session "" ""
answers "$PUBLISHED"
ar plan "$TOPIC"
assert_eq "no dispatch recorded (a dry run, a refused or failed dispatch): refused" "2" "$RC"
assert_contains "it says so" "refused=not-dispatched" "$OUT"
assert_contains "and names each install not run" "not-run tracked 2 $TWO" "$OUT"
assert_eq "no wait" "0" "$(lines "$GH_LOG")"
ar run "$TOPIC"
assert_eq "run after a refused plan has nothing stored to run" "1" "$RC"
assert_eq "and runs nothing" "0" "$(lines "$INSTALL_LOG")"
session 0.3.0 failure
ar plan "$TOPIC"
assert_eq "a failed workflow: refused" "2" "$RC"
assert_contains "it names the conclusion" "refused=workflow-failure" "$OUT"
session 0.3.0 ""
ar plan "$TOPIC"
assert_contains "a workflow whose end wasn't seen: refused" "refused=workflow-unknown" "$OUT"

echo "== the wait =="
session 0.3.0 success
answers "$DRAFT"
WAIT=0 ar plan "$TOPIC"
assert_eq "a release still a draft past the wait: exit 3" "3" "$RC"
assert_contains "it says the release isn't published" "published=no reason=wait-ran-out" "$OUT"
assert_contains "the message says it isn't published yet" "isn't published yet" "$ERR"
assert_contains "and names each install not run" "not-run tracked 1 $ONE" "$OUT"
assert_eq "no grant lookup" "0" "$(lines "$NIWA_LOG")"
assert_eq "nothing stored to run" "1" "$(ar run "$TOPIC"; echo "$RC")"
session 0.3.0 success
answers fail
ar plan "$TOPIC"
assert_eq "gh release view failing: exit 3" "3" "$RC"
assert_contains "it says the view failed" "published=no reason=view-failed" "$OUT"
session 0.3.0 success
answers '{"isDraft":false,"tagName":"v0.2.9"}'
ar plan "$TOPIC"
assert_contains "an answer naming another tag isn't this release" "published=no reason=view-failed" "$OUT"
assert_eq "nothing ran" "0" "$(lines "$INSTALL_LOG")"

echo "== local commands =="
# shellcheck disable=SC2016 # literal backticks
printf '## After release\n\n- `%s`\n- `%s`\n' "$(inst local-a)" "$(inst local-b)" >"$LOCAL"
session 0.3.0 success
answers "$PUBLISHED"
ar plan "$TOPIC"
assert_contains "a local command is listed for its own question" "install local 1 $(inst local-a)" "$OUT"
ar run "$TOPIC"
assert_contains "a holder still doesn't run a local command it wasn't told yes to" "result declined local 1" "$OUT"
assert_eq "a holder's tracked commands run; the locals don't" "2" "$(lines "$INSTALL_LOG")"
session 0.3.0 success
answers "$PUBLISHED"
NIWA_STUB=not-held ar plan "$TOPIC"
ar run "$TOPIC" --local-approved 1
assert_contains "without a holder, the local answered yes runs" "local-a" "$(cat "$INSTALL_LOG")"
assert_lacks "the one answered no doesn't" "local-b" "$(cat "$INSTALL_LOG")"
assert_contains "and is reported declined" "result declined local 2" "$OUT"
rm -f "$LOCAL"

echo "== this repository's own installs =="
OWN="$SCRIPT_DIR/../../../.claude/shirabe-extensions/release.md"
cp "$OWN" "$EXT"
gg add -A
gg commit -q -m "own ext"
session 0.3.0 success
answers "$PUBLISHED"
ar plan "$TOPIC"
assert_eq "shirabe declares a reinstall, a version check and a workspace apply, in that order" \
    "install tracked 1 tsuku install \"tsukumogami/shirabe@v\$RELEASE_VERSION\"
install tracked 2 test \"\$(shirabe --version)\" = \"shirabe v\$RELEASE_VERSION\"
install tracked 3 cd \"\${RELEASE_WORKSPACE_ROOT:?not in a niwa workspace}\" && niwa apply" \
    "$(printf '%s\n' "$OUT" | grep '^install ')"

echo "== usage =="
ar plan
assert_eq "plan with no topic is a usage error" "64" "$RC"
ar plan "Bad_Topic"
assert_eq "a bad topic is a usage error" "64" "$RC"
ar run "$TOPIC" --local-approved x
assert_eq "--local-approved takes a number" "64" "$RC"
ar frobnicate
assert_eq "an unknown subcommand is a usage error" "64" "$RC"
session 0.3.0 success
rm -f "$S/work/head"
ar plan "$TOPIC"
assert_eq "plan without Phase 1's head exits 1" "1" "$RC"
assert_contains "naming the key" "work/head" "$ERR"

echo
echo "after-release_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
