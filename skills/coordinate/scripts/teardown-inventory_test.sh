#!/usr/bin/env bash
# teardown-inventory_test.sh -- the teardown inventory over real repositories.
#
# Builds an instance of clones of a local bare origin, each in one state, with
# a gh stand-in answering the merged-pull-request lookup, and asserts the
# per-repository verdict:
#
#   unique   uncommitted change; untracked file; stash entry; a change a
#            clean filter hides from git status (and the filter never runs);
#            skip-worktree and assume-unchanged edits; a local tag's commit;
#            an unpushed branch whose changed file differs from the default
#            branch; a
#            branch whose remote branch was deleted without merging; a
#            worktree on a detached HEAD with an unpushed commit
#   durable  a clean clone; a pushed branch; a squash-merged branch whose
#            changed file matches the merge commit even though the default
#            branch changed that file again later; an unpushed branch with no
#            merged pull request whose changed file matches the default branch
#   error    a bare repository; an unreadable one; a clone with no
#            github.com origin; a tree read that hangs past its deadline
#
# Submodules and clones nested in an ignored directory are inventoried as
# clones of their own.
#
# plus the exit codes, relative paths, the absence of any write (every ref
# and each clone's index file unchanged), and --seal (sealed through a coord-log.sh stand-in,
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
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$2]" ;; esac; }

# --- stand-ins -------------------------------------------------------------------------

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"
mkdir -p "$ST/ctx" "$ST/merged"

# gh: `pr list --repo R --head B --state merged ...` prints the merge sha
# recorded for branch B, or nothing; `api repos/R/git/trees/<sha>?recursive=1`
# answers from the local bare origin, in GitHub's shape.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = api ]; then
    [ "${GH_HANG:-}" = 1 ] && sleep 30
    sha=${2##*/trees/}; sha=${sha%%\?*}
    git --git-dir="$O" ls-tree -r "$sha" |
        jq -R -s '{truncated: false, tree: [split("\n")[] | select(length > 0) | split("\t") as $f | ($f[0] | split(" ")) as $m | {path: $f[1], type: $m[1], sha: $m[2]}]}'
    exit 0
fi
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
# koto: the session's context, as files under $ST/ctx.
cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "context get" ] || exit 64
[ -f "$ST/ctx/$4" ] || exit 1
cat "$ST/ctx/$4"
EOF
chmod +x "$BIN/gh" "$T/coord-log.sh" "$BIN/koto"
export PATH="$BIN:$PATH"
export DC_COORD_LOG="$T/coord-log.sh"

# --- the origin and the instance ---------------------------------------------------------

export O="$T/origin.git"
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

# Every ref and each index file's bytes before, to show the inventory writes
# nothing at all.
refs() { for d in "$I"/public/*; do git -C "$d" for-each-ref --format='%(refname) %(objectname)'; od -An -tx1 <"$(git -C "$d" rev-parse --absolute-git-dir)/index" | tr -d " \n"; echo; done; }
BEFORE=$(refs)

OUT=$(bash "$S" --topic plugin-api --instance "$I" 2>&1); RC=$?
line() { printf '%s\n' "$OUT" | grep -E "^[a-z]+ $1( |:)"; }

eq  "exit: 1 when anything is unique" 1 "$RC"
has "clean: durable"                          "$(line public/clean)" "durable public/clean"
has "dirty: unique"                           "$(line public/dirty)" "unique public/dirty: uncommitted changes"
has "untracked: unique"                       "$(line public/untracked)" "unique public/untracked: untracked files"
has "stash: unique"                           "$(line public/stash)" "stash entries"
has "unpushed branch: unique vs default"      "$(line public/unpushed)" "feat changed a.txt unlike its target (vs default main)"
has "pushed branch: durable"                  "$(line public/pushed)" "durable public/pushed"
has "remote branch deleted unmerged: unique"  "$(line public/deleted)" "unique public/deleted: gone changed a.txt"
has "squash-merged, main moved on: durable vs the merge commit" "$(line public/squashed)" "durable public/squashed (vs merge $MERGE)"
has "no PR, same content on main: durable vs default" "$(line public/matches)" "durable public/matches (vs default main)"
has "detached worktree commit: unique"        "$(line public/wt/.claude/worktrees/w1)" "HEAD changed a.txt"
case "$OUT" in *"$T"*) bad "paths: relative to the instance" "$OUT" ;; *) ok "paths: relative to the instance" ;; esac
eq  "no writes: every ref and index unchanged" "$BEFORE" "$(refs)"

# Only durable repositories: exit 0.
I2="$T/inst2"
mkdir -p "$I2/public"
git clone -q "$GHURL" "$I2/public/clean"
bash "$S" --topic plugin-api --instance "$I2" >/dev/null 2>&1; eq "exit: 0 when every repository is durable" 0 "$?"

# A failed pull-request lookup is an error, never durable.
GH_FAIL=1 bash "$S" --topic plugin-api --instance "$I" >/dev/null 2>&1; eq "a failed gh lookup is exit 2" 2 "$?"

# A submodule is inventoried as a clone of its own; the superproject's
# staged submodule addition is its own change.
I3="$T/inst3"
mkdir -p "$I3"
git clone -q "$GHURL" "$I3/super"
git -C "$I3/super" submodule add -q "$GHURL" sub >"$T/sub.log" 2>&1
OUT3=$(bash "$S" --topic plugin-api --instance "$I3" 2>&1); RC=$?
eq  "submodule: exit 1 for the staged addition" 1 "$RC"
has "submodule: inventoried as a clone" "$OUT3" "durable super/sub"
has "submodule: the superproject's staged change" "$OUT3" "unique super: staged changes"

# A clone with no github.com origin can't be compared: an error.
I9="$T/inst9"
mkdir -p "$I9"
git clone -q "$O" "$I9/local"
OUT9=$(bash "$S" --topic plugin-api --instance "$I9" 2>&1); RC=$?
eq  "no github.com origin: exit 2" 2 "$RC"
has "no github.com origin: named" "$OUT9" "error local: no github.com origin to compare against"

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

# A tree read that hangs past its deadline makes that repository an error.
I6="$T/inst6"
mkdir -p "$I6"
git clone -q "$GHURL" "$I6/slow"
START=$(date +%s)
OUT6=$(GH_HANG=1 TEARDOWN_FETCH_SECS=1 bash "$S" --topic plugin-api --instance "$I6" 2>&1); RC=$?
eq  "hung read: exit 2" 2 "$RC"
has "hung read: named" "$OUT6" "error slow: the default branch's tree could not be read"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "hung read: stops at the deadline"; else bad "hung read: stops at the deadline" ""; fi

# What git status can't see. A clean filter that maps any content back to the
# committed bytes hides an edit from status; the inventory hashes the bytes
# itself and never runs the filter.
I10="$T/inst10"
mkdir -p "$I10"
for r in filt skip assume tagged nest; do git clone -q "$GHURL" "$I10/$r"; done
printf 'a.txt filter=hide\n' >"$I10/filt/.git/info/attributes"
git -C "$I10/filt" config filter.hide.clean "touch $T/filter-ran; printf 'a\\n'"
printf 'hidden edit\n' >>"$I10/filt/a.txt"
git -C "$I10/filt" update-index --refresh >/dev/null 2>&1
rm -f "$T/filter-ran"
git -C "$I10/skip" update-index --skip-worktree a.txt
printf 'skipped edit\n' >>"$I10/skip/a.txt"
git -C "$I10/assume" update-index --assume-unchanged a.txt
printf 'assumed edit\n' >>"$I10/assume/a.txt"
git -C "$I10/tagged" checkout -q -b tmp
printf 'tagged\n' >"$I10/tagged/a.txt"
git -C "$I10/tagged" commit -q -am tagged
git -C "$I10/tagged" tag t1
git -C "$I10/tagged" checkout -q main
git -C "$I10/tagged" branch -q -D tmp
printf 'vendor/\n' >>"$I10/nest/.git/info/exclude"
git clone -q "$GHURL" "$I10/nest/vendor/inner"
printf 'x\n' >>"$I10/nest/vendor/inner/a.txt"
git clone -q "$GHURL" "$I10/twice"
git -C "$I10/twice" checkout -q -b once
printf 'once\n' >"$I10/twice/a.txt"
git -C "$I10/twice" commit -q -am once
git -C "$I10/twice" checkout -q main
printf '.claude/\n' >>"$I10/twice/.git/info/exclude"
git -C "$I10/twice" worktree add -q "$I10/twice/.claude/worktrees/w" once
OUT10=$(bash "$S" --topic plugin-api --instance "$I10" 2>&1)
eq  "a branch shared with a linked worktree is listed once" 1 "$(printf '%s\n' "$OUT10" | grep -c 'once changed a.txt')"
has "a clean filter hides nothing" "$OUT10" "unique filt: uncommitted changes"
if [ -e "$T/filter-ran" ]; then bad "the clone's filter never runs" ""; else ok "the clone's filter never runs"; fi
has "a skip-worktree edit: unique" "$OUT10" "unique skip: uncommitted changes"
has "an assume-unchanged edit: unique" "$OUT10" "unique assume: uncommitted changes"
has "a local tag's commit: unique" "$OUT10" "tag t1 changed a.txt"
has "a clone in an ignored directory: inventoried" "$OUT10" "unique nest/vendor/inner: uncommitted changes"
has "that ignored directory isn't the outer clone's change" "$OUT10" "durable nest"

# The scan's overall budget: a repository it doesn't reach is an error.
OUT7=$(TEARDOWN_TOTAL_SECS=0 bash "$S" --topic plugin-api --instance "$I2" 2>&1); RC=$?
eq  "budget spent: exit 2" 2 "$RC"
has "budget spent: named" "$OUT7" "not inventoried; the scan ran out of its 0s budget"

# Only origin's refs vouch for a commit: a stale ref under another remote
# doesn't make unpushed work durable.
I8="$T/inst8"
mkdir -p "$I8"
git clone -q "$GHURL" "$I8/other"
git -C "$I8/other" checkout -q -b mine
printf 'mine\n' >"$I8/other/a.txt"
git -C "$I8/other" commit -q -am mine
git -C "$I8/other" remote add mirror "$O"
git -C "$I8/other" update-ref refs/remotes/mirror/mine "$(git -C "$I8/other" rev-parse HEAD)"
git -C "$I8/other" checkout -q main
OUT8=$(bash "$S" --topic plugin-api --instance "$I8" 2>&1); RC=$?
eq  "another remote's ref: still unique" 1 "$RC"
has "another remote's ref: named" "$OUT8" "unique other: mine changed a.txt"

bash "$S" --topic plugin-api --instance "$T/nowhere" >/dev/null 2>&1; eq "no instance: exit 2" 2 "$?"
bash "$S" --topic ../x --instance "$I" >/dev/null 2>&1; eq "a bad topic: exit 2" 2 "$?"

# A clone configured as a partial clone whose promisor remote is a command,
# with the command's protocol allowed in its own config: a read of a missing
# object would lazily fetch through it. origin then moves on, so its live head
# is a commit the clone doesn't have.
I11="$T/inst11"
mkdir -p "$I11"
git clone -q "$GHURL" "$I11/lazy"
git -C "$I11/lazy" config core.repositoryformatversion 1
git -C "$I11/lazy" config extensions.partialClone evil
git -C "$I11/lazy" config remote.evil.promisor true
git -C "$I11/lazy" config remote.evil.url "ext::sh -c touch% $T/lazy-ran"
git -C "$I11/lazy" config protocol.ext.allow always
main_commit a.txt "moved on" "origin moves on" >/dev/null
rm -f "$T/lazy-ran"
bash "$S" --topic plugin-api --instance "$I11" >/dev/null 2>&1
if [ -e "$T/lazy-ran" ]; then bad "a partial clone's promisor command never runs" ""; else ok "a partial clone's promisor command never runs"; fi

# A commit held only by a remote-tracking ref for a branch origin no longer
# has: unique when it never landed, durable against its merge commit when it
# was squash-merged.
I12="$T/inst12"
mkdir -p "$I12"
for r in lost landed; do git clone -q "$GHURL" "$I12/$r"; done
git -C "$I12/lost" checkout -q -b lostb
printf 'lost\n' >"$I12/lost/c.txt"
git -C "$I12/lost" commit -q -am lost
git -C "$I12/lost" push -q origin lostb
git -C "$I12/lost" checkout -q main
git -C "$I12/lost" branch -q -D lostb
git --git-dir="$O" update-ref -d refs/heads/lostb
git -C "$I12/landed" checkout -q -b landb
printf 'landed\n' >"$I12/landed/c.txt"
git -C "$I12/landed" commit -q -am landed
git -C "$I12/landed" push -q origin landb
git -C "$I12/landed" checkout -q main
git -C "$I12/landed" branch -q -D landb
MERGE12=$(main_commit c.txt "landed" "squash: landb")
printf '%s\n' "$MERGE12" >"$ST/merged/landb"
git --git-dir="$O" update-ref -d refs/heads/landb
# Someone else's branch, fetched by this clone and later deleted from origin
# unmerged: its tracking ref isn't the worker's, so the clone stays durable.
git -C "$SEED" checkout -q -b others
printf 'theirs\n' >"$SEED/b.txt"
git -C "$SEED" commit -q -am theirs
git -C "$SEED" push -q origin others
git -C "$SEED" checkout -q main
git clone -q "$GHURL" "$I12/bystander"
git clone -q "$GHURL" "$I12/advanced"
# Someone else's branch advancing on origin after this clone's last fetch.
git -C "$SEED" checkout -q others
printf 'theirs again\n' >"$SEED/b.txt"
git -C "$SEED" commit -q -am "theirs again"
git -C "$SEED" push -q origin others
git -C "$SEED" checkout -q main
git --git-dir="$O" update-ref -d refs/heads/others
# Ref logging off: a pushed branch can't be told from someone else's.
git clone -q "$GHURL" "$I12/nolog"
git -C "$I12/nolog" config core.logAllRefUpdates false
OUT12=$(bash "$S" --topic plugin-api --instance "$I12" 2>&1)
has "someone else's deleted branch doesn't make a clean clone unique" "$OUT12" "durable bystander"
has "someone else's branch moving on origin doesn't either" "$OUT12" "durable advanced"
has "ref logging off is an error, never durable" "$OUT12" "error nolog: ref logging is off"
has "a commit only a stale remote-tracking ref holds: unique" "$OUT12" "unique lost: remote-tracking origin/lostb changed c.txt"
has "a squash-merged branch's stale remote-tracking ref: durable" "$OUT12" "durable landed (vs "
has "that ref is judged against its merge commit" "$OUT12" "merge $MERGE12)"

# --- what it calls ------------------------------------------------------------------------------
#
# Every niwa, gh, koto and git call is logged by a stand-in in front of the
# real tool, over a run that finds the instance through niwa (no --instance)
# and one over the instance with every kind of finding. None may destroy,
# stop or delete anything, or change a repository.
LOGBIN="$T/logbin"
mkdir -p "$LOGBIN"
export CALLS="$T/calls.log"
: >"$CALLS"
REALGIT=$(command -v git)
for tool in niwa gh koto git; do
    real="$BIN/$tool"
    [ "$tool" = git ] && real="$REALGIT"
    [ "$tool" = niwa ] && real="$T/niwa-real"
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >>"$CALLS"\nexec "%s" "$@"\n' "$tool" "$real" >"$LOGBIN/$tool"
    chmod +x "$LOGBIN/$tool"
done
# niwa list --json names the worker's session and instance.
printf '#!/usr/bin/env bash\n[ "$1" = list ] || exit 64\nprintf '"'"'[{"name":"w","path":"%s","session_name":"plugin_api-1a2b3c4d"}]\\n'"'"'\n' "$I" >"$T/niwa-real"
chmod +x "$T/niwa-real"
WS="$T/ws"
mkdir -p "$WS/.niwa"
: >"$WS/.niwa/workspace.toml"
: >"$WS/.niwa/instance.json"
(cd "$WS" && PATH="$LOGBIN:$PATH" bash "$S" --topic plugin-api >/dev/null 2>&1)
has "calls: the instance is found through niwa" "$(cat "$CALLS")" "niwa list"
PATH="$LOGBIN:$PATH" bash "$S" --topic plugin-api --instance "$I10" >/dev/null 2>&1
BAD=$(grep -Ei '^niwa (destroy|reap|stop|remove|rm)|^gh (pr (close|merge)|issue close|api .*-X (DELETE|PATCH|POST|PUT)|repo delete)|^koto (next|cancel|session|context (add|remove))|^git .* (fetch|push|pull|reset|clean|checkout|switch|worktree (add|remove|prune)|branch -[dDmM]|stash (drop|clear|pop|push)|gc|prune|update-ref|update-index|commit|merge|rebase|tag -d|config --(add|unset|replace))( |$)' "$CALLS")
if [ -z "$BAD" ]; then ok "calls: nothing destroyed, stopped, deleted or changed"; else bad "calls: nothing destroyed, stopped, deleted or changed" "$BAD"; fi

# --- --seal and teardown-verdict.sh ----------------------------------------------------------

printf 'plugin-api' >"$ST/ctx/teardown_topic"
bash "$S" --topic plugin-api --seal --session coord --instance "$I2" >/dev/null 2>&1
eq  "seal: --topic with --seal is refused (the topic comes from context)" 2 "$?"
TOK=$(bash "$S" --seal --session coord --instance "$I2" 2>"$T/seal.err"); RC=$?
eq  "seal: exit 0" 0 "$RC"
case "$TOK" in sealed:7:*) ok "seal: prints the bare token, as every sealed capture is" ;; *) bad "seal: prints the bare token, as every sealed capture is" "$TOK" ;; esac
has "seal: the verdict's word goes to stderr" "$(cat "$T/seal.err")" "durable"
# The state captures this line, and koto admits only these characters in a
# capture.
if printf '%s' "$TOK" | grep -Eq '^[A-Za-z0-9 :/_.@-]*$'; then ok "seal: the captured line is capture-safe"; else bad "seal: the captured line is capture-safe" "$TOK"; fi
printf '%s\n' "$TOK" >"$ST/capture"
eq  "verdict gate: a durable sealed verdict passes" 0 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"
READ=$(bash "$V" read --session coord 2>/dev/null)
has "verdict read: prints it" "$READ" "durable public/clean"
has "verdict read: names the one instance inventoried" "$READ" "instance $I2"
has "verdict read: names its topic" "$READ" "topic plugin-api"
printf 'another-worker' >"$ST/ctx/teardown_topic"
eq  "verdict gate: teardown_topic rewritten after the seal is refused" 3 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"
printf 'plugin-api' >"$ST/ctx/teardown_topic"
printf 'durable forged\n' >>"$ST/ctx/teardown_verdict"
eq  "verdict gate: an edited verdict fails its seal" 3 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

TOK=$(bash "$S" --seal --session coord --instance "$I" 2>/dev/null); RC=$?
eq  "seal: exit 0 for a unique verdict too (a default action)" 0 "$RC"
printf '%s\n' "$TOK" >"$ST/capture"
eq  "verdict gate: unique is 1" 1 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

bash "$S" --seal --session coord --instance "$I2" >"$ST/capture" 2>/dev/null
printf 'directed_transition teardown -> destroy\n' >"$ST/directed"
eq  "verdict gate: a directed transition doesn't change the gate" 0 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"
eq  "verdict read: a directed transition refuses the destroy" 4 "$(bash "$V" read --session coord >/dev/null 2>&1; echo $?)"
rm -f "$ST/directed"
printf 'nothing sealed\n' >"$ST/capture"
eq  "verdict gate: no seal in the capture is 3" 3 "$(bash "$V" gate --session coord >/dev/null 2>&1; echo $?)"

DC_COORD_LOG="$T/absent.sh" bash "$S" --seal --session coord --instance "$I2" >/dev/null 2>&1
eq  "seal: no coord-log.sh is exit 2" 2 "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
