#!/usr/bin/env bash
# build-output-end_test.sh — /execute's build-output cleanup: the per-worktree
# pin and the successful end that cleans against it
# Part of the execute skill
#
# build-output-pin.sh pins a base per recorded worktree as run/cleanup/<id>,
# written once through run-record.sh pin; build-output-end.sh, from the merged
# and ready_awaiting_merge directives, reads each worktree's own CI and hands
# the green ones to work-on's clean-build-output.sh with that pin. Both run on
# the koto context stub from coord-test-helpers.sh and real git. The end runs
# from a stand-in plugin tree whose CI scripts are stubs (owned-pr.sh,
# pr-checks.sh, ci-cancel-after-merge.sh, ci-none-declared.sh) answering from
# per-case files, and whose clean-build-output.sh logs its call and, for the
# cases that need it, runs the real script.
#
# Cases:
#   pin        a fresh branch pins merge-base(HEAD, origin/main) and the work
#              tree's root, printing nothing on stdout; a second call after the
#              default branch moved and merged in keeps the first value; a head
#              already on the default branch, a clone with no default-branch
#              remote ref, a recovered run and a failing koto write pin nothing,
#              print nothing on stdout and exit 0; --fetch in a clone whose
#              default is master fetches it first and pins against
#              origin/master
#   single     green CI, and a repository declaring no hosted CI, each call the
#              cleanup exactly once with the pin as --base, the root and the
#              switch root, and no walk budget; pending CI (whatever route
#              reached the terminal) and a CI read that fails call nothing; a
#              missing cleanup script, a missing pin, a worktree on another
#              branch and a path that is gone each print their line; every
#              call exits 0 and writes build_output_cleanup once and nothing
#              else
#   coordinated  two green nodes are each cleaned once in their own worktree;
#              a pending node keeps its tree while the green one is cleaned; a
#              node with run/node and no run/cleanup, and every node of a
#              recovered run, print `base unreadable`; a node in home_repo
#              whose only non-green checks are cancelled floor runs is cleaned,
#              the same node in another repository is not; with no hosted CI
#              both nodes are cleaned
#   real       with the real clean-build-output.sh: node worktrees holding no
#              CLAUDE.local.md lose their declared tree when the parent
#              checkout's switch is on (a node with several commits and the
#              default branch merged in after its pin among them) and keep it
#              when it is off; after the branch's PR merged and the default
#              branch was fetched, a path the branch added to the declaration
#              stays while the base's is removed; the removal-recorded line
#              reaches build_output_cleanup
#
# Usage: build-output-end_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
WORKON_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../../work-on/scripts" && pwd)
LIB_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../../../scripts/lib" && pwd)
PIN="$SCRIPT_DIR/build-output-pin.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"
T="$CT_WORK/bo"
mkdir -p "$T"
S=execute-t

# --- fixtures ---------------------------------------------------------------------

# mk_origin <name> <default branch> -- a bare origin whose default branch holds a
# verification map declaring target/, and a .gitignore for target/ and dist/.
mk_origin() {
    local seed="$T/seed-$1"
    rm -rf "$seed" "$T/origin-$1.git"
    git init -q "$seed"
    git -C "$seed" symbolic-ref HEAD "refs/heads/$2"
    mkdir -p "$seed/.claude/shirabe-extensions"
    printf '%s\n' '{"schema":"shirabe-verification-map/v1","commands":{},"entries":[],"default":[],"build_output":["target/"]}' \
        > "$seed/.claude/shirabe-extensions/verification-map.json"
    printf 'target/\ndist/\n' > "$seed/.gitignore"
    git -C "$seed" add -A
    git -C "$seed" commit -q -m init
    git clone -q --bare "$seed" "$T/origin-$1.git"
}

# advance <name> <default branch> -- one more commit on the origin's default
# branch, pushed from its seed.
advance() {
    local seed="$T/seed-$1"
    git -C "$seed" pull -q "$T/origin-$1.git" "$2" 2>/dev/null
    printf '%s\n' "$RANDOM" >> "$seed/later.txt"
    git -C "$seed" add later.txt
    git -C "$seed" commit -q -m later
    git -C "$seed" push -q "$T/origin-$1.git" "HEAD:$2"
}

# mk_clone <origin> <dir> <branch> -- a clone on <branch>, one commit ahead of
# the default branch, with its declared target/ (and dist/) built.
mk_clone() {
    rm -rf "$2"
    git clone -q "$T/origin-$1.git" "$2"
    git -C "$2" checkout -q -b "$3"
    printf 'x\n' > "$2/work.txt"
    git -C "$2" add work.txt
    git -C "$2" commit -q -m work
    build "$2"
}
build() {
    mkdir -p "$1/target/debug" "$1/dist"
    printf 'bin' > "$1/target/debug/app"
    printf 'pkg' > "$1/dist/pkg.tgz"
}
real() { (CDPATH='' cd -- "$1" && pwd -P); }
sha() { git -C "$1" rev-parse --verify "$2^{commit}"; }

# pin <id> <dir> [--fetch] -- build-output-pin.sh; sets OUT and RC.
pin() {
    local id="$1" dir="$2"
    shift 2
    OUT=$(bash "$PIN" --session "$S" --id "$id" --worktree "$dir" "$@" 2>"$CASE/pin-stderr")
    RC=$?
}
held() { jq -cS . "$CASE/ctx/$S/run/cleanup/$1" 2>/dev/null; }
want_pin() { jq -cnS --arg p "$(real "$2")" --arg s "$3" '{path: $p, pin: $s}'; }

# The stand-in plugin tree: the scripts under test linked in, the CI scripts
# and the cleanup stubbed. Every stub logs its call to $FX/calls.log.
P="$T/plugin"
mkdir -p "$P/skills/execute/scripts" "$P/skills/work-on/scripts"
for f in build-output-end.sh run-record-lib.sh run-id.sh; do
    ln -s "$SCRIPT_DIR/$f" "$P/skills/execute/scripts/$f"
done
cat > "$P/skills/execute/scripts/owned-pr.sh" <<'STUB'
#!/usr/bin/env bash
printf 'owned-pr %s\n' "$*" >> "$FX/calls.log"
repo=""; head=""
while [ $# -gt 0 ]; do
    case "$1" in --repo) repo="$2"; shift 2 ;; --head) head="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "${FX_OWNED_FAIL:-}" ] && exit 1
f="$FX/prs/$(printf '%s %s' "$repo" "$head" | tr '/ ' '__')"
[ -f "$f" ] && cat "$f"
exit 0
STUB
cat > "$P/skills/work-on/scripts/pr-checks.sh" <<'STUB'
#!/usr/bin/env bash
printf 'pr-checks %s\n' "$*" >> "$FX/calls.log"
f="$FX/checks/$(printf '%s' "$1" | tr '/:' '__')"
[ -f "$f" ] || exit 1
cat "$f"
STUB
for s in ci-cancel-after-merge ci-none-declared; do
    cat > "$P/skills/work-on/scripts/$s.sh" <<STUB
#!/usr/bin/env bash
printf '$s %s\n' "\$*" >> "\$FX/calls.log"
repo=""
while [ \$# -gt 0 ]; do case "\$1" in --repo) repo="\$2"; shift 2 ;; *) shift ;; esac; done
[ -f "\$FX/$s/\$(printf '%s' "\$repo" | tr '/' '_')" ]
STUB
done
cat > "$P/skills/work-on/scripts/clean-build-output.sh" <<STUB
#!/usr/bin/env bash
printf 'clean %s\n' "\$*" >> "\$FX/calls.log"
[ -n "\${FX_REAL_CLEAN:-}" ] && exec bash "$WORKON_DIR/clean-build-output.sh" "\$@"
printf 'build-output: target removed\n'
STUB
chmod +x "$P/skills/execute/scripts/owned-pr.sh" "$P"/skills/work-on/scripts/*.sh
END="$P/skills/execute/scripts/build-output-end.sh"

# bo_case <name> -- ct_case, plus the case's CI answers under $FX.
bo_case() {
    ct_case "$1"
    export FX="$CASE/fx"
    rm -rf "$FX"
    mkdir -p "$FX/prs" "$FX/checks" "$FX/ci-cancel-after-merge" "$FX/ci-none-declared"
    : > "$FX/calls.log"
    unset FX_OWNED_FAIL FX_REAL_CLEAN
}
# ci <repo> <branch> <pr url> <true|false|absent> -- the PR the run owns on
# <branch> and what its checks read (absent: pr-checks fails).
ci() {
    printf '%s\n' "$3" > "$FX/prs/$(printf '%s %s' "$1" "$2" | tr '/ ' '__')"
    [ "$4" = absent ] || printf '%s\n' "$4" > "$FX/checks/$(printf '%s' "$3" | tr '/:' '__')"
}
cancel_ok() { : > "$FX/ci-cancel-after-merge/$(printf '%s' "$1" | tr '/' '_')"; }
none_declared() { : > "$FX/ci-none-declared/$(printf '%s' "$1" | tr '/' '_')"; }
ctx_put() { printf '%s' "$2" > "$CASE/ctx/$S/$1"; }

# end_run <cwd> -- build-output-end.sh from <cwd>; sets OUT, RC. The koto and
# CI call logs start empty, so the setup's own writes aren't counted.
end_run() {
    : > "$CASE/koto-calls.log"
    : > "$FX/calls.log"
    OUT=$(cd "$1" && bash "$END" --session "$S" 2>"$CASE/end-stderr")
    RC=$?
}
cleans() { grep -c '^clean ' "$FX/calls.log"; }
clean_line() { grep '^clean ' "$FX/calls.log" | sed -n "${1}p"; }
key_writes() { grep -c "^context add $S build_output_cleanup\$" "$CASE/koto-calls.log"; }
other_writes() { ct_ctx_writes | grep -v "^context add $S build_output_cleanup\$" | grep -c .; }
# recorded -- build_output_cleanup holds exactly what the call printed.
recorded() { [ "$(cat "$CASE/ctx/$S/build_output_cleanup" 2>/dev/null)" = "$OUT" ]; }
# once_and_only -- exit 0, the key written once with every line, no other write.
once_and_only() {
    if [ "$RC" -eq 0 ] && [ "$(key_writes)" = 1 ] && recorded && [ "$(other_writes)" = 0 ]; then
        pass "$1: exit 0, build_output_cleanup written once with every line, nothing else written"
    else
        fail "$1: exit $RC, key writes $(key_writes), other writes $(other_writes), out [$OUT]"
    fi
}

mk_origin r main
mk_origin m master

# --- pin ----------------------------------------------------------------------------

bo_case pin-fresh
mk_clone r "$T/pin-fresh" impl/t
MAIN=$(sha "$T/pin-fresh" refs/remotes/origin/main)
pin single "$T/pin-fresh"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$(held single)" = "$(want_pin single "$T/pin-fresh" "$MAIN")" ]; then
    pass "a fresh branch pins merge-base(HEAD, origin/main) and the work tree's root, nothing on stdout"
else
    fail "pin-fresh: exit $RC, out [$OUT], held [$(held single)]; $(cat "$CASE/pin-stderr")"
fi
advance r main
git -C "$T/pin-fresh" fetch -q origin
git -C "$T/pin-fresh" merge -q --no-edit origin/main
pin single "$T/pin-fresh"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$(held single)" = "$(want_pin single "$T/pin-fresh" "$MAIN")" ] \
    && grep -q 'kept=run/cleanup/single' "$CASE/pin-stderr"; then
    pass "a second pin after the default branch moved and merged in keeps the first value"
else
    fail "pin-kept: out [$OUT], held [$(held single)]; $(cat "$CASE/pin-stderr")"
fi

bo_case pin-on-default
rm -rf "$T/pin-default"
git clone -q "$T/origin-r.git" "$T/pin-default"
pin single "$T/pin-default"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$(held single)" ] \
    && pass "a head already on the default branch pins nothing" \
    || fail "pin-on-default: exit $RC, out [$OUT], held [$(held single)]"

bo_case pin-noref
mk_clone r "$T/pin-noref" impl/t
git -C "$T/pin-noref" symbolic-ref -d refs/remotes/origin/HEAD
git -C "$T/pin-noref" update-ref -d refs/remotes/origin/main
pin single "$T/pin-noref"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$(held single)" ] \
    && pass "a clone with neither origin/HEAD nor origin/main pins nothing, nothing on stdout" \
    || fail "pin-noref: exit $RC, out [$OUT], held [$(held single)]"

bo_case pin-recovered
mk_clone r "$T/pin-rec" impl/t-a
mkdir -p "$CASE/ctx/$S/run"
ctx_put run/recovered '{"pr":"https://github.com/acme/r/pull/10","source":"carried"}'
pin a "$T/pin-rec"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$(held a)" ] \
    && pass "a recovered run pins nothing" \
    || fail "pin-recovered: exit $RC, out [$OUT], held [$(held a)]"

bo_case pin-koto-fails
mk_clone r "$T/pin-kf" impl/t
export KOTO_FAIL_ADD=run/cleanup/single
pin single "$T/pin-kf"
unset KOTO_FAIL_ADD
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$(held single)" ] \
    && pass "a pin whose koto write fails prints nothing on stdout and exits 0" \
    || fail "pin-koto-fails: exit $RC, out [$OUT]"

bo_case pin-master
mk_clone m "$T/pin-master" impl/t-a
OLD_MASTER=$(sha "$T/pin-master" refs/remotes/origin/master)
advance m master
NEW_MASTER=$(git -C "$T/origin-m.git" rev-parse master)
pin a "$T/pin-master" --fetch
if [ "$RC" -eq 0 ] && [ "$(sha "$T/pin-master" refs/remotes/origin/master)" = "$NEW_MASTER" ] \
    && [ "$(held a)" = "$(want_pin a "$T/pin-master" "$OLD_MASTER")" ]; then
    pass "--fetch in a clone whose default is master fetches it first and pins against origin/master"
else
    fail "pin-master: origin/master [$(sha "$T/pin-master" refs/remotes/origin/master)], held [$(held a)]; $(cat "$CASE/pin-stderr")"
fi

# --- single-pr ------------------------------------------------------------------------

URL1=https://github.com/acme/r/pull/1
# single_setup <case> -- a single-pr run in $T/s-<case> on impl/t, pinned.
single_setup() {
    bo_case "single-$1"
    mk_clone r "$T/s-$1" impl/t
    ctx_put repos acme/r
    ctx_put settled_branch impl/t
    pin single "$T/s-$1"
    SPIN=$(sha "$T/s-$1" refs/remotes/origin/main)
    SROOT=$(real "$T/s-$1")
}

single_setup green
ci acme/r impl/t "$URL1" true
end_run "$T/s-green"
if [ "$(cleans)" = 1 ] && [ "$(clean_line 1)" = "clean --base $SPIN --root $SROOT --switch-root $SROOT" ] \
    && grep -qx "build-output: single cleaning $SROOT" <<<"$OUT"; then
    pass "single-pr, CI green: the cleanup runs once with the pin, the root and the switch root, and no walk budget"
else
    fail "single green: calls [$(grep '^clean' "$FX/calls.log")], out [$OUT]"
fi
once_and_only "single-pr, CI green"
grep -q -- "--run-id 00112233445566778899aabbccddeeff" "$FX/calls.log" \
    && pass "the CI read carries the run's identity" || fail "no --run-id on the CI read: [$(cat "$FX/calls.log")]"

single_setup nohosted
ci acme/r impl/t "$URL1" false
none_declared acme/r
end_run "$T/s-nohosted"
[ "$(cleans)" = 1 ] && pass "single-pr, a repository declaring no hosted CI: the cleanup runs once" \
    || fail "single no hosted: [$(cat "$FX/calls.log")], out [$OUT]"
once_and_only "single-pr, no hosted CI"

single_setup pending
ci acme/r impl/t "$URL1" false
end_run "$T/s-pending"
if [ "$(cleans)" = 0 ] && grep -qx 'build-output: single CI not green, removed nothing' <<<"$OUT" \
    && [ -d "$T/s-pending/target" ]; then
    pass "single-pr, CI pending (a ready_awaiting_merge reached on DIRTY or on pending CI): reads CI itself, cleans nothing"
else
    fail "single pending: [$(cat "$FX/calls.log")], out [$OUT]"
fi
once_and_only "single-pr, CI pending"

single_setup ci-fails
ci acme/r impl/t "$URL1" true
export FX_OWNED_FAIL=1
end_run "$T/s-ci-fails"
unset FX_OWNED_FAIL
[ "$(cleans)" = 0 ] && grep -qx 'build-output: single CI not green, removed nothing' <<<"$OUT" \
    && pass "single-pr, a CI read that fails: cleans nothing" || fail "single ci-fails: out [$OUT]"
once_and_only "single-pr, a failed CI read"

single_setup no-script
ci acme/r impl/t "$URL1" true
mv "$P/skills/work-on/scripts/clean-build-output.sh" "$T/clean.aside"
end_run "$T/s-no-script"
mv "$T/clean.aside" "$P/skills/work-on/scripts/clean-build-output.sh"
grep -qx 'build-output: single cleanup unavailable, removed nothing' <<<"$OUT" \
    && pass "single-pr, the cleanup script missing: one line" || fail "single no-script: out [$OUT]"
once_and_only "single-pr, no cleanup script"

single_setup no-pin
rm -f "$CASE/ctx/$S/run/cleanup/single"
ci acme/r impl/t "$URL1" true
end_run "$T/s-no-pin"
[ "$(cleans)" = 0 ] && [ "$OUT" = 'build-output: single base unreadable, removed nothing' ] \
    && pass "single-pr with no run/cleanup/single: base unreadable, nothing called" || fail "single no-pin: out [$OUT]"

single_setup branch
ci acme/r impl/t "$URL1" true
git -C "$T/s-branch" checkout -q -b someone-else
end_run "$T/s-branch"
[ "$(cleans)" = 0 ] && [ "$OUT" = 'build-output: single worktree unverified, removed nothing' ] \
    && pass "single-pr, the recorded path on another branch: worktree unverified" || fail "single branch: out [$OUT]"

single_setup gone
ci acme/r impl/t "$URL1" true
cp -R "$T/s-gone" "$T/s-gone-here"
rm -rf "$T/s-gone"
end_run "$T/s-gone-here"
[ "$(cleans)" = 0 ] && [ "$OUT" = 'build-output: single worktree unverified, removed nothing' ] \
    && pass "single-pr, the recorded path gone: worktree unverified" || fail "single gone: out [$OUT]"

# --- coordinated ------------------------------------------------------------------------

NODES2='[{"name":"a","kind":"pr","repo":"acme/r","waits_on":[]},{"name":"b","kind":"pr","repo":"acme/r","waits_on":[]}]'
URLA=https://github.com/acme/r/pull/11
URLB=https://github.com/acme/r/pull/12
# coord_setup <case> [pin b: yes|no] -- a coordinated run, coordination
# checkout $T/c-<case>/coord, node clones .../a and .../b on impl/t-a and
# impl/t-b, both recorded, a always pinned.
coord_setup() {
    bo_case "coord-$1"
    local d="$T/c-$1"
    rm -rf "$d"
    mkdir -p "$d"
    git clone -q "$T/origin-r.git" "$d/coord"
    mk_clone r "$d/a" impl/t-a
    mk_clone r "$d/b" impl/t-b
    ct_record_setup github 10 "$NODES2"
    ct_record_node a acme/r 11
    ct_record_node b acme/r 12
    ctx_put home_repo acme/r
    pin a "$d/a"
    [ "${2:-yes}" = no ] || pin b "$d/b"
    CPIN=$(sha "$d/a" refs/remotes/origin/main)
    COORD=$(real "$d/coord")
}

coord_setup green
ci acme/r impl/t-a "$URLA" true
ci acme/r impl/t-b "$URLB" true
end_run "$T/c-green/coord"
if [ "$(cleans)" = 2 ] \
    && [ "$(clean_line 1)" = "clean --base $CPIN --root $(real "$T/c-green/a") --switch-root $COORD" ] \
    && [ "$(clean_line 2)" = "clean --base $CPIN --root $(real "$T/c-green/b") --switch-root $COORD" ]; then
    pass "coordinated, two green node PRs: each worktree cleaned once, the coordination checkout as switch root, default walk budget"
else
    fail "coord green: [$(grep '^clean' "$FX/calls.log")], out [$OUT]"
fi
if grep -qx "build-output: a cleaning $(real "$T/c-green/a")" <<<"$OUT" \
    && grep -qx "build-output: b cleaning $(real "$T/c-green/b")" <<<"$OUT"; then
    pass "coordinated: each block is led by build-output: <node>"
else
    fail "coord green lines: [$OUT]"
fi
once_and_only "coordinated, two green nodes"

coord_setup pending
ci acme/r impl/t-a "$URLA" true
ci acme/r impl/t-b "$URLB" false
end_run "$T/c-pending/coord"
if [ "$(cleans)" = 1 ] && grep -q -- "--root $(real "$T/c-pending/a") " "$FX/calls.log" \
    && grep -qx 'build-output: b CI not green, removed nothing' <<<"$OUT"; then
    pass "coordinated, one node's CI still pending: that node keeps its tree, the green one is cleaned"
else
    fail "coord pending: [$(cat "$FX/calls.log")], out [$OUT]"
fi

coord_setup unpinned no
ci acme/r impl/t-a "$URLA" true
ci acme/r impl/t-b "$URLB" true
end_run "$T/c-unpinned/coord"
[ "$(cleans)" = 1 ] && grep -qx 'build-output: b base unreadable, removed nothing' <<<"$OUT" \
    && pass "coordinated, a node with run/node and no run/cleanup: base unreadable for it" \
    || fail "coord unpinned: out [$OUT]"

coord_setup recovered no
rm -f "$CASE/ctx/$S/run/cleanup/a"
ctx_put run/recovered '{"pr":"https://github.com/acme/r/pull/10","source":"carried"}'
ci acme/r impl/t-a "$URLA" true
ci acme/r impl/t-b "$URLB" true
end_run "$T/c-recovered/coord"
if [ "$(cleans)" = 0 ] && [ "$OUT" = 'build-output: a base unreadable, removed nothing
build-output: b base unreadable, removed nothing' ] && [ -d "$T/c-recovered/a/target" ]; then
    pass "a recovered coordinated run: base unreadable per node, nothing called, every tree kept"
else
    fail "coord recovered: out [$OUT]"
fi

coord_setup cancel
# Node b's PR lives in another repository than the coordination checkout's.
ctx_put run/node/b "{\"head\":\"$CT_HEAD\",\"pr\":12,\"repo\":\"acme/other\"}"
ci acme/r impl/t-a "$URLA" false
ci acme/other impl/t-b https://github.com/acme/other/pull/12 false
cancel_ok acme/r
cancel_ok acme/other
end_run "$T/c-cancel/coord"
if [ "$(cleans)" = 1 ] && grep -q -- "--root $(real "$T/c-cancel/a") " "$FX/calls.log" \
    && grep -qx 'build-output: b CI not green, removed nothing' <<<"$OUT" \
    && [ "$(grep -c '^ci-cancel-after-merge .*--repo acme/other' "$FX/calls.log")" = 0 ]; then
    pass "a node in home_repo whose only non-green checks are cancelled floor runs is cleaned; the same node in another repository keeps its tree"
else
    fail "coord cancel: [$(cat "$FX/calls.log")], out [$OUT]"
fi

coord_setup nohosted
ci acme/r impl/t-a "$URLA" false
ci acme/r impl/t-b "$URLB" false
none_declared acme/r
end_run "$T/c-nohosted/coord"
[ "$(cleans)" = 2 ] && pass "coordinated, a repository with no hosted checks: each recorded worktree cleaned once" \
    || fail "coord no hosted: [$(cat "$FX/calls.log")]"

# --- with the real cleanup ------------------------------------------------------------

coord_setup real
export FX_REAL_CLEAN=1
# Node a: an adopted branch with commits of its own, and the default branch
# merged in after its pin, as worktree_sync's override would leave it.
printf 'y\n' > "$T/c-real/a/more.txt"
git -C "$T/c-real/a" add more.txt
git -C "$T/c-real/a" commit -q -m more
advance r main
git -C "$T/c-real/a" fetch -q origin
git -C "$T/c-real/a" merge -q --no-edit origin/main
ci acme/r impl/t-a "$URLA" true
ci acme/r impl/t-b "$URLB" true
end_run "$T/c-real/coord"
if [ -d "$T/c-real/a/target" ] && [ -d "$T/c-real/b/target" ] && grep -q 'cleanup off' <<<"$OUT"; then
    pass "the switch off in the coordination checkout: every node tree stays"
else
    fail "real, switch off: out [$OUT]"
fi
printf '## Build Output Cleanup: on\n' > "$T/c-real/coord/CLAUDE.local.md"
rm -f "$CASE/ctx/$S/build_output_cleanup"
end_run "$T/c-real/coord"
if [ ! -e "$T/c-real/a/target" ] && [ ! -e "$T/c-real/b/target" ] && [ -d "$T/c-real/a/dist" ] \
    && [ ! -e "$T/c-real/a/CLAUDE.local.md" ] && [ ! -e "$T/c-real/b/CLAUDE.local.md" ]; then
    pass "the switch on in the coordination checkout: node worktrees with no CLAUDE.local.md lose their declared tree"
else
    fail "real, switch on: out [$OUT]"
fi
[ "$(grep -c '^build-output: removal recorded at ' "$CASE/ctx/$S/build_output_cleanup")" = 2 ] \
    && pass "build_output_cleanup carries each removal-recorded line" \
    || fail "real: build_output_cleanup [$(cat "$CASE/ctx/$S/build_output_cleanup")]"
unset FX_REAL_CLEAN

# R2: the branch widens its own declaration, its PR merges, the default branch
# is fetched; the pin taken before still reads the base's declaration.
single_setup widened
export FX_REAL_CLEAN=1
rm -f "$CASE/ctx/$S/run/cleanup/single"
printf '%s\n' '{"schema":"shirabe-verification-map/v1","commands":{},"entries":[],"default":[],"build_output":["target/","dist/"]}' \
    > "$T/s-widened/.claude/shirabe-extensions/verification-map.json"
git -C "$T/s-widened" commit -q -am "widen the declaration"
pin single "$T/s-widened"
git -C "$T/s-widened" push -q origin HEAD:main
git -C "$T/s-widened" fetch -q origin
printf '## Build Output Cleanup: on\n' > "$T/s-widened/CLAUDE.local.md"
ci acme/r impl/t "$URL1" true
end_run "$T/s-widened"
if [ ! -e "$T/s-widened/target" ] && [ -d "$T/s-widened/dist" ]; then
    pass "after the PR merged and main was fetched, a path the branch added to the declaration stays and the base's is removed"
else
    fail "widened: out [$OUT]"
fi
unset FX_REAL_CLEAN

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
