#!/usr/bin/env bash
# teardown-inventory_test.sh -- the teardown inventory over real repositories.
#
# Builds an instance of clones of a local bare origin, each in one state, with
# a gh stand-in answering the merged-pull-request lookup, and asserts the
# per-repository verdict:
#
#   unique   uncommitted change; untracked file; stash entry; an unpushed
#            branch whose changed file differs from the default branch; a
#            branch whose remote branch was deleted without merging; a
#            worktree on a detached HEAD with an unpushed commit
#   durable  a clean clone; a pushed branch; a squash-merged branch whose
#            changed file matches the merge commit even though the default
#            branch changed that file again later; an unpushed branch with no
#            merged pull request whose changed file matches the default branch
#   error    a submodule
#
# plus the exit codes, relative paths, the absence of writes beyond
# remote-tracking refs, and --seal (sealed through a coord-log.sh stand-in,
# exit 0 whatever the verdict) with teardown-verdict.sh reading it back: a
# durable verdict passes, an edited one fails its seal, a directed transition
# since the teardown entry refuses the destroy.
#
# Usage: bash skills/coordinate/scripts/teardown-inventory_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs git and jq. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/teardown-inventory.sh"
V="$HERE/teardown-verdict.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
# Run from inside the scratch directory: the checkout this test sits in may be
# a worktree whose .git points somewhere a container can't see, and git fails
# on a broken .git even for commands that need no repository.
cd "$T" || exit 1
# A test-local HOME carries the git config: every git reads ~/.gitconfig,
# while GIT_CONFIG_GLOBAL is newer than the floor container's git.
export HOME="$T/home"
mkdir -p "$HOME"
GITCFG="$HOME/.gitconfig"
git config --file "$GITCFG" user.email t@example.invalid
git config --file "$GITCFG" user.name t
git config --file "$GITCFG" init.defaultBranch main
git config --file "$GITCFG" protocol.file.allow always

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { if printf '%s' "$2" | grep -Fq -- "$3"; then ok "$1"; else bad "$1" "missing [$3] in [$2]"; fi; }

# --- stand-ins -------------------------------------------------------------------------

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"
mkdir -p "$ST/ctx" "$ST/merged"

# gh: `pr list --repo R --head B --state merged ...` prints the merge sha
# recorded for branch B, or nothing.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr list" ] || exit 64
while [ $# -gt 0 ]; do [ "$1" = --head ] && B="$2"; shift; done
[ "${GH_FAIL:-}" = 1 ] && exit 1
[ -f "$ST/merged/$B" ] && cat "$ST/merged/$B"
exit 0
EOF
# coord-log.sh: seal stores the file under ctx/<key> and prints a token over
# it; check re-hashes; capture and directed-since read files under $ST.
cat >"$T/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
sha() { if command -v sha256sum >/dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
cmd="$1"; shift
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--state|--file|--key|--sealed|--from|--name) eval "A_${1#--}=\"\$2\""; shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$cmd" in
    seal)
        cp "$A_file" "$ST/ctx/$A_key"
        printf 'sealed:7:%s\n' "$(sha <"$A_file")"
        ;;
    check)
        want=${A_sealed##*:}
        [ "$(sha <"$ST/ctx/$A_key")" = "$want" ] || exit 1
        cat "$ST/ctx/$A_key"
        ;;
    capture) cat "$ST/capture" ;;
    directed-since) [ -f "$ST/directed" ] && { cat "$ST/directed"; exit 1; }; exit 0 ;;
esac
EOF
chmod +x "$BIN/gh" "$T/coord-log.sh"
export PATH="$BIN:$PATH"
export DC_COORD_LOG="$T/coord-log.sh"

# --- the origin and the instance ---------------------------------------------------------

O="$T/origin.git"
SEED="$T/seed"
git init -q --bare "$O"
git init -q "$SEED"
printf 'a\n' >"$SEED/a.txt"; printf 'b\n' >"$SEED/b.txt"; printf 'c\n' >"$SEED/c.txt"
git -C "$SEED" add . && git -C "$SEED" commit -q -m init
# An older git ignores init.defaultBranch, so name the branch outright.
git -C "$SEED" branch -M main
git -C "$SEED" remote add origin "$O"
git -C "$SEED" push -q origin main
git --git-dir="$O" symbolic-ref HEAD refs/heads/main

main_commit() {  # main_commit <file> <content> <message>: land a commit on origin's main
    printf '%s\n' "$2" >"$SEED/$1"
    git -C "$SEED" commit -q -am "$3"
    git -C "$SEED" push -q origin main
    git -C "$SEED" rev-parse HEAD
}

# Clones name a GitHub origin, as a worker's do, and git rewrites it to the
# local bare repository; the inventory reads the configured URL for its
# pull-request lookup.
GHURL=https://github.com/acme/widgets
git config --file "$GITCFG" "url.$O.insteadOf" "$GHURL"

I="$T/inst"
mkdir -p "$I/public"
clone() { git clone -q "$GHURL" "$I/public/$1"; git -C "$I/public/$1" remote set-head origin main >/dev/null; }
branch_commit() {  # branch_commit <repo> <branch> <file> <content>
    git -C "$I/public/$1" checkout -q -b "$2"
    printf '%s\n' "$4" >"$I/public/$1/$3"
    git -C "$I/public/$1" commit -q -am "$2"
    git -C "$I/public/$1" checkout -q main
}

clone clean

clone dirty;      printf 'x\n' >>"$I/public/dirty/a.txt"
clone untracked;  printf 'x\n' >"$I/public/untracked/new.txt"
clone stash;      printf 'x\n' >>"$I/public/stash/a.txt"; git -C "$I/public/stash" stash -q
clone unpushed;   branch_commit unpushed feat a.txt "feature work"

clone pushed;     branch_commit pushed topic a.txt "pushed work"; git -C "$I/public/pushed" push -q origin topic

clone deleted;    branch_commit deleted gone a.txt "abandoned work"
git -C "$I/public/deleted" push -q origin gone
git --git-dir="$O" update-ref -d refs/heads/gone

clone squashed;   branch_commit squashed sq b.txt "b from the branch"
MERGE=$(main_commit b.txt "b from the branch" "squash: sq")
main_commit b.txt "b changed again on main" "later work" >/dev/null
printf '%s\n' "$MERGE" >"$ST/merged/sq"

clone matches;    branch_commit matches nopr c.txt "c on main too"
main_commit c.txt "c on main too" "same content, landed another way" >/dev/null

clone wt
git -C "$I/public/wt" worktree add -q --detach "$I/public/wt/.claude/worktrees/w1" main
printf 'x\n' >>"$I/public/wt/.claude/worktrees/w1/a.txt"
git -C "$I/public/wt/.claude/worktrees/w1" commit -q -am "detached work"

# Refs before, to show the inventory writes nothing but remote-tracking refs.
refs() { for d in "$I"/public/*; do git -C "$d" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/stash; git -C "$d" status --porcelain; done; }
BEFORE=$(refs)

OUT=$(bash "$S" --topic plugin-api --instance "$I" 2>&1); RC=$?
line() { printf '%s\n' "$OUT" | grep -E "^[a-z]+ $1( |:)"; }

eq  "exit: 1 when anything is unique" 1 "$RC"
has "clean: durable"                          "$(line public/clean)" "durable public/clean"
has "dirty: unique"                           "$(line public/dirty)" "unique public/dirty: uncommitted or untracked changes"
has "untracked: unique"                       "$(line public/untracked)" "unique public/untracked: uncommitted or untracked changes"
has "stash: unique"                           "$(line public/stash)" "stash entries"
has "unpushed branch: unique vs default"      "$(line public/unpushed)" "feat changed a.txt unlike its target (vs default main)"
has "pushed branch: durable"                  "$(line public/pushed)" "durable public/pushed"
has "remote branch deleted unmerged: unique"  "$(line public/deleted)" "unique public/deleted: gone changed a.txt"
has "squash-merged, main moved on: durable vs the merge commit" "$(line public/squashed)" "durable public/squashed (vs merge $MERGE)"
has "no PR, same content on main: durable vs default" "$(line public/matches)" "durable public/matches (vs default main)"
has "detached worktree commit: unique"        "$(line public/wt/.claude/worktrees/w1)" "HEAD changed a.txt"
case "$OUT" in *"$T"*) bad "paths: relative to the instance" "$OUT" ;; *) ok "paths: relative to the instance" ;; esac
eq  "no writes but remote-tracking refs" "$BEFORE" "$(refs)"

# Only durable repositories: exit 0.
I2="$T/inst2"
mkdir -p "$I2/public"
git clone -q "$O" "$I2/public/clean"
bash "$S" --topic plugin-api --instance "$I2" >/dev/null 2>&1; eq "exit: 0 when every repository is durable" 0 "$?"

# A failed pull-request lookup is an error, never durable.
GH_FAIL=1 bash "$S" --topic plugin-api --instance "$I" >/dev/null 2>&1; eq "a failed gh lookup is exit 2" 2 "$?"

# A submodule is an error, never durable.
I3="$T/inst3"
mkdir -p "$I3"
git clone -q "$O" "$I3/super"
git -C "$I3/super" submodule add -q "$O" sub >/dev/null 2>&1
OUT3=$(bash "$S" --topic plugin-api --instance "$I3" 2>&1); RC=$?
eq  "submodule: exit 2" 2 "$RC"
has "submodule: named" "$OUT3" "error super/sub: a submodule"

# A bare repository, which has no .git to find, is an error, never durable.
I4="$T/inst4"
mkdir -p "$I4"
git init -q --bare "$I4/cache.git"
OUT4=$(bash "$S" --topic plugin-api --instance "$I4" 2>&1); RC=$?
eq  "bare repository: exit 2" 2 "$RC"
has "bare repository: named" "$OUT4" "error cache.git: a bare repository"

# A repository whose .git points nowhere is an error, never durable.
I5="$T/inst5"
mkdir -p "$I5/broken"
printf 'gitdir: %s/missing\n' "$T" >"$I5/broken/.git"
OUT5=$(bash "$S" --topic plugin-api --instance "$I5" 2>&1); RC=$?
eq  "unreadable repository: exit 2" 2 "$RC"
has "unreadable repository: named" "$OUT5" "error broken: not a readable git repository"

# A fetch that hangs past the deadline makes that repository an error. The
# origin is a helper that never answers.
I6="$T/inst6"
mkdir -p "$I6"
git clone -q "$O" "$I6/slow"
cat >"$BIN/git-remote-hang" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$BIN/git-remote-hang"
git -C "$I6/slow" remote set-url origin hang::nowhere
START=$(date +%s)
OUT6=$(TEARDOWN_FETCH_SECS=1 bash "$S" --topic plugin-api --instance "$I6" 2>&1); RC=$?
eq  "hung fetch: exit 2" 2 "$RC"
has "hung fetch: named" "$OUT6" "error slow: git fetch origin failed or timed out"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "hung fetch: stops at the deadline"; else bad "hung fetch: stops at the deadline" ""; fi

bash "$S" --topic plugin-api --instance "$T/nowhere" >/dev/null 2>&1; eq "no instance: exit 2" 2 "$?"
bash "$S" --topic ../x --instance "$I" >/dev/null 2>&1; eq "a bad topic: exit 2" 2 "$?"

# --- --seal and teardown-verdict.sh ----------------------------------------------------------

TOK=$(bash "$S" --topic plugin-api --instance "$I2" --seal --session coord 2>/dev/null); RC=$?
eq  "seal: exit 0" 0 "$RC"
has "seal: prints the verdict word and the token" "$TOK" "durable sealed:7:"
printf '%s\n' "$TOK" >"$ST/capture"
eq  "verdict gate: a durable sealed verdict passes" 0 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"
has "verdict read: prints it" "$(bash "$V" read --session coord 2>/dev/null)" "durable public/clean"
printf 'durable forged\n' >>"$ST/ctx/teardown_verdict"
eq  "verdict gate: an edited verdict fails its seal" 3 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

TOK=$(bash "$S" --topic plugin-api --instance "$I" --seal --session coord 2>/dev/null); RC=$?
eq  "seal: exit 0 for a unique verdict too (a default action)" 0 "$RC"
printf '%s\n' "$TOK" >"$ST/capture"
eq  "verdict gate: unique is 1" 1 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

bash "$S" --topic plugin-api --instance "$I2" --seal --session coord >"$ST/capture" 2>/dev/null
printf 'directed_transition teardown -> destroy\n' >"$ST/directed"
eq  "verdict gate: a directed transition doesn't change the gate" 0 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"
eq  "verdict read: a directed transition refuses the destroy" 4 "$(bash "$V" read --session coord >/dev/null 2>&1; echo $?)"
rm -f "$ST/directed"
printf 'nothing sealed\n' >"$ST/capture"
eq  "verdict gate: no seal in the capture is 3" 3 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

DC_COORD_LOG="$T/absent.sh" bash "$S" --topic plugin-api --instance "$I2" --seal --session coord >/dev/null 2>&1
eq  "seal: no coord-log.sh is exit 2" 2 "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
