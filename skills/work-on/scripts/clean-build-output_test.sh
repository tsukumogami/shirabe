#!/usr/bin/env bash
# clean-build-output_test.sh -- clean-build-output.sh removes a repository's
# declared build output only when a workspace turned the cleanup on, only at
# the pinned base's declaration, and only for paths that pass every check.
#
# Covers: the switch (absent, off, trimmed and any-case `on`, a misspelled or
# wrongly cased name, a duplicate, an unreadable, tracked or symlinked
# CLAUDE.local.md, the committed CLAUDE.md never read) and --switch-root; the
# records directory (a symlink, a file) and pre-existing names for the call's
# stamp; two calls in one second; an empty declaration with and without an
# ended record to reap; the base's ancestry, an unreadable base or map, and
# the declaration read only at the base; every refusal word and their order;
# malformed entries, normalization, nesting and literal paths; the walk
# budget; the trash's place in a linked worktree and a plain clone, and its
# numbered entries; the device check and the swap re-checks; the record's
# fields and status; the group kill; atomic record writes, a symlinked record
# or log, and unparsable records; a live removal left alone and ended ones
# reaped; a 9 GiB tree; exit 0 throughout and no telemetry.
#
# Usage: bash skills/work-on/scripts/clean-build-output_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/clean-build-output.sh"
for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not on PATH"; exit 0; }
done
# shellcheck source=build-output-lib.sh
. "$HERE/build-output-lib.sh"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has_line() { if printf '%s\n' "$3" | grep -qxF -- "$2"; then ok "$1"; else bad "$1" "no line [$2] in [$3]"; fi; }
no_match() { if printf '%s\n' "$3" | grep -qE -- "$2"; then bad "$1" "[$2] matched in [$3]"; else ok "$1"; fi; }
exists() { if [ -e "$2" ] || [ -L "$2" ]; then ok "$1"; else bad "$1" "[$2] is gone"; fi; }
missing() { if [ -e "$2" ] || [ -L "$2" ]; then bad "$1" "[$2] is still there"; else ok "$1"; fi; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
W=$(cd "$W" && pwd -P)
cleanup() {
    chmod -R u+rwx "$W" 2>/dev/null
    rm -rf "$W"
}
trap cleanup EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset SHIRABE_BUILD_OUTPUT_TEST_STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE \
    SHIRABE_BUILD_OUTPUT_TEST_ROOT_DEV SHIRABE_BUILD_OUTPUT_TEST_TRASH_DEV KOTO_TICK_SESSION

ROOT_USER=0
[ "$(id -u)" -eq 0 ] && ROOT_USER=1

GITIGNORE='target/
target1/
out/
old/
ignored/
a/
b/
big/
nest/
mnt/
link-dir
lnk/
CLAUDE.md
.env
.env.local
CLAUDE.local.md
'

# mkrepo <dir> <build_output JSON, or "none">: a repository with one commit
# carrying the map and the .gitignore, CLAUDE.local.md switched on, and a
# target/ tree. Prints the commit.
mkrepo() {
    local d="$1" bo="$2" map
    git init -q -b main "$d"
    mkdir -p "$d/.claude/shirabe-extensions"
    if [ "$bo" = none ]; then
        map='{"schema": "shirabe-verification-map/v1", "commands": {}, "entries": []}'
    else
        map="{\"schema\": \"shirabe-verification-map/v1\", \"commands\": {}, \"entries\": [], \"build_output\": $bo}"
    fi
    printf '%s\n' "$map" > "$d/.claude/shirabe-extensions/verification-map.json"
    printf '%s' "$GITIGNORE" > "$d/.gitignore"
    printf 'tracked\n' > "$d/README"
    git -C "$d" add .gitignore README .claude
    git -C "$d" commit -q -m base
    printf '## Build Output Cleanup: on\n' > "$d/CLAUDE.local.md"
    mkdir -p "$d/target/debug"
    printf 'built\n' > "$d/target/debug/app"
    git -C "$d" rev-parse HEAD
}

# cbo <dir> <args...>: run the script from <dir>; OUT and RC are its stdout and
# exit status. Every outcome must exit 0.
cbo() {
    local d="$1"
    shift
    OUT=$(cd "$d" && bash "$SCRIPT" "$@" 2>"$W/stderr")
    RC=$?
    if [ "$RC" -ne 0 ]; then
        bad "exit 0 for [$*]" "exit $RC, stderr: $(cat "$W/stderr")"
    fi
}

# record_of <output>: the record path the output names, or nothing.
record_of() { printf '%s\n' "$1" | sed -n 's/^build-output: removal recorded at //p'; }

# wait_status <record>: waits (up to 30 s) for the record to leave `running`,
# then prints its status.
wait_status() {
    local i=0 s=""
    [ -n "$1" ] && [ -e "$1" ] || { echo none; return; }
    while [ "$i" -lt 300 ]; do
        s=$(jq -r '.status' "$1" 2>/dev/null)
        [ -n "$s" ] && [ "$s" != running ] && { printf '%s\n' "$s"; return; }
        sleep 0.1
        i=$((i + 1))
    done
    printf '%s\n' "${s:-unreadable}"
}

# wait_file <path>: waits (up to 30 s) for a file to appear.
wait_file() {
    local i=0
    while [ ! -e "$1" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
}

# a pid that is certainly dead
dead_pid() {
    local p
    sleep 0 &
    p=$!
    wait "$p" 2>/dev/null
    printf '%s\n' "$p"
}

# fake_record <bo dir> <stamp> <status> <pid>: an earlier call's record.
fake_record() {
    jq -n --arg s "$3" --argjson pid "$4" \
        '{schema: "shirabe-build-output-removal/v1", started_at: "2026-01-01T00:00:00Z",
          pid: $pid, paths: {"1": "target/"}, reaped: [], status: $s}' > "$1/removal-$2.json"
}

# --- 1. the switch ------------------------------------------------------------------

R="$W/switch"
B=$(mkrepo "$R" '["target/"]')
rm "$R/CLAUDE.local.md"
cbo "$R" --base "$B"
eq "no CLAUDE.local.md: one cleanup-off line" "build-output: cleanup off" "$OUT"
exists "no CLAUDE.local.md: target stays" "$R/target/debug/app"
missing "cleanup off makes no records directory" "$R/.git/shirabe-build-output"

switch_case() {
    printf "$2" > "$R/CLAUDE.local.md"
    cbo "$R" --base "$B"
    eq "$1: one line" "$3" "$OUT"
    exists "$1: target stays" "$R/target/debug/app"
}
switch_case "value off" '## Build Output Cleanup: off\n' "build-output: cleanup off"
switch_case "a misspelled header" '## Build Output Clean: on\n' "build-output: cleanup off"
switch_case "a wrongly cased name" '## build output cleanup: on\n' "build-output: cleanup off"
switch_case "a duplicate header" '## Build Output Cleanup: on\n## Build Output Cleanup: on\n' \
    "build-output: cleanup off (CLAUDE.local.md declares the header more than once)"
switch_case "a header only inside a fence" '```\n## Build Output Cleanup: on\n```\n' "build-output: cleanup off"

if [ "$ROOT_USER" -eq 0 ]; then
    printf '## Build Output Cleanup: on\n' > "$R/CLAUDE.local.md"
    chmod 000 "$R/CLAUDE.local.md"
    cbo "$R" --base "$B"
    eq "an unreadable CLAUDE.local.md: off, named" "build-output: cleanup off (CLAUDE.local.md is unreadable)" "$OUT"
    chmod 644 "$R/CLAUDE.local.md"
fi

printf '## Build Output Cleanup: on\n' > "$W/elsewhere.md"
rm -f "$R/CLAUDE.local.md"
ln -s "$W/elsewhere.md" "$R/CLAUDE.local.md"
cbo "$R" --base "$B"
eq "a symlinked CLAUDE.local.md: off, named" "build-output: cleanup off (CLAUDE.local.md is a symlink)" "$OUT"
rm "$R/CLAUDE.local.md"
ln -s "$W/nowhere.md" "$R/CLAUDE.local.md"
cbo "$R" --base "$B"
eq "a dangling symlink: off, named" "build-output: cleanup off (CLAUDE.local.md is a symlink)" "$OUT"
rm "$R/CLAUDE.local.md"
exists "a symlinked switch: target stays" "$R/target/debug/app"

printf '## Build Output Cleanup: on\n' > "$R/CLAUDE.local.md"
git -C "$R" add -f CLAUDE.local.md
cbo "$R" --base "$B"
eq "a tracked CLAUDE.local.md: off, named" "build-output: cleanup off (CLAUDE.local.md is tracked)" "$OUT"
exists "a tracked switch: target stays" "$R/target/debug/app"
git -C "$R" rm -q --cached CLAUDE.local.md
rm "$R/CLAUDE.local.md"

printf '## Build Output Cleanup: on\n' > "$R/CLAUDE.md"
cbo "$R" --base "$B"
eq "on only in CLAUDE.md: off" "build-output: cleanup off" "$OUT"
exists "on only in CLAUDE.md: target stays" "$R/target/debug/app"
rm "$R/CLAUDE.md"

printf '# local\n\n## Build Output Cleanup:  ON \n' > "$R/CLAUDE.local.md"
cbo "$R" --base "$B"
has_line "a trimmed, upper-case ON turns it on" "target/ removed" "$OUT"
missing "on: target is gone from its path" "$R/target"
REC=$(record_of "$OUT")
eq "on: the record's status" "done" "$(wait_status "$REC")"

# --- 1b. --switch-root -------------------------------------------------------------

R="$W/split"
B=$(mkrepo "$R" '["target/"]')
git -C "$R" worktree add -q "$W/split-wt" -b node
mkdir -p "$W/split-wt/target"
printf 'x\n' > "$W/split-wt/target/f"
cbo "$W" --base "$B" --root "$W/split-wt" --switch-root "$R"
has_line "switch on at --switch-root: the linked worktree's path is removed" "target/ removed" "$OUT"
missing "switch on at --switch-root: target gone" "$W/split-wt/target"
WT_GITDIR=$(git -C "$W/split-wt" rev-parse --absolute-git-dir)
REC=$(record_of "$OUT")
case "$REC" in
    "$WT_GITDIR"/shirabe-build-output/removal-*.json) ok "a linked worktree's records sit in its own git directory" ;;
    *) bad "a linked worktree's records sit in its own git directory" "record at [$REC], git dir [$WT_GITDIR]" ;;
esac
wait_status "$REC" >/dev/null

mkdir -p "$W/split-wt/target"
printf '## Build Output Cleanup: on\n' > "$W/split-wt/CLAUDE.local.md"
printf '## Build Output Cleanup: off\n' > "$R/CLAUDE.local.md"
cbo "$W" --base "$B" --root "$W/split-wt" --switch-root "$R"
eq "switch off at --switch-root, on at --root: off" "build-output: cleanup off" "$OUT"
exists "switch off at --switch-root: target stays" "$W/split-wt/target"
rm "$W/split-wt/CLAUDE.local.md"

rm "$R/CLAUDE.local.md"
ln -s "$W/elsewhere.md" "$R/CLAUDE.local.md"
cbo "$W" --base "$B" --root "$W/split-wt" --switch-root "$R"
eq "a symlinked CLAUDE.local.md at --switch-root: off" "build-output: cleanup off (CLAUDE.local.md is a symlink)" "$OUT"
rm "$R/CLAUDE.local.md"
printf '## Build Output Cleanup: on\n' > "$R/CLAUDE.local.md"
git -C "$R" add -f CLAUDE.local.md
cbo "$W" --base "$B" --root "$W/split-wt" --switch-root "$R"
eq "a tracked CLAUDE.local.md at --switch-root: off" "build-output: cleanup off (CLAUDE.local.md is tracked)" "$OUT"
exists "a tracked switch at --switch-root: target stays" "$W/split-wt/target"

# --- 2. the records directory and the stamp -----------------------------------------

R="$W/bodir"
B=$(mkrepo "$R" '["target/"]')
mkdir "$W/bo-elsewhere"
ln -s "$W/bo-elsewhere" "$R/.git/shirabe-build-output"
cbo "$R" --base "$B"
eq "a symlinked records directory: one failed line" "build-output: $R/.git/shirabe-build-output failed" "$OUT"
exists "a symlinked records directory: target stays" "$R/target/debug/app"
eq "a symlinked records directory: nothing written through it" "" "$(ls -A "$W/bo-elsewhere")"
rm "$R/.git/shirabe-build-output"
printf 'x' > "$R/.git/shirabe-build-output"
cbo "$R" --base "$B"
eq "a records directory that is a file: one failed line" "build-output: $R/.git/shirabe-build-output failed" "$OUT"
exists "a records directory that is a file: target stays" "$R/target/debug/app"
rm "$R/.git/shirabe-build-output"

STAMP=20260101T000000Z-4242
mkdir "$R/.git/shirabe-build-output"
BO="$R/.git/shirabe-build-output"
fake_record "$BO" 20250101T000000Z-1 running "$(dead_pid)"
mkdir "$BO/trash-20250101T000000Z-1"
for name in "removal-$STAMP.json" "removal-$STAMP.log" "trash-$STAMP"; do
    for form in file dir symlink; do
        case "$form" in
            file) printf 'x' > "$BO/$name" ;;
            dir) mkdir "$BO/$name" ;;
            symlink) ln -s "$W/bo-elsewhere" "$BO/$name" ;;
        esac
        OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP bash "$SCRIPT" --base "$B")
        eq "an existing $name ($form): one failed line" "build-output: $name failed" "$OUT"
        rm -rf "$BO/$name"
    done
done
exists "an existing stamp name: target stays" "$R/target/debug/app"
eq "an existing stamp name: nothing reaped" "running" "$(jq -r .status "$BO/removal-20250101T000000Z-1.json")"
exists "an existing stamp name: the ended record's trash stays" "$BO/trash-20250101T000000Z-1"

# A log or record name made a symlink after that check: the no-clobber link
# fails, every entry goes back, and the link's target is untouched.
symlink_after_check() {
    local what="$1" name="$2" P="$W/pause-$1"
    mkdir "$P"
    : > "$P/record.wait"
    printf 'victim\n' > "$W/victim-$what"
    rm -rf "$R/target"; mkdir -p "$R/target"; printf 'keep\n' > "$R/target/f"
    (cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P \
        bash "$SCRIPT" --base "$B" > "$W/out-$what" 2>&1) &
    local pid=$!
    wait_file "$P/record.reached"
    ln -s "$W/victim-$what" "$BO/$name"
    : > "$P/record.go"
    wait "$pid"
    eq "a $what made a symlink after the check: exit 0" 0 $?
    OUT=$(cat "$W/out-$what")
    has_line "a $what made a symlink: one failed line" "build-output: $name failed" "$OUT"
    has_line "a $what made a symlink: the path reads failed" "target/ failed" "$OUT"
    eq "a $what made a symlink: the entry is back in place" "keep" "$(cat "$R/target/f" 2>/dev/null)"
    eq "a $what made a symlink: the link's target is untouched" "victim" "$(cat "$W/victim-$what")"
    missing "a $what made a symlink: the trash is gone" "$BO/trash-$STAMP"
    sleep 1
    eq "a $what made a symlink: no deleter removed anything" "keep" "$(cat "$R/target/f" 2>/dev/null)"
    no_match "a $what made a symlink: no record line" "removal recorded" "$OUT"
    rm -f "$BO/$name" "$BO/removal-$STAMP.log" "$BO/removal-$STAMP.json"
}
rm -rf "$BO/removal-20250101T000000Z-1.json" "$BO/trash-20250101T000000Z-1"
symlink_after_check log "removal-$STAMP.log"
symlink_after_check record "removal-$STAMP.json"

# --- 2b. two calls in the same second -------------------------------------------------

R="$W/twice"
B=$(mkrepo "$R" '[]')
BO="$R/.git/shirabe-build-output"
mkdir "$BO"
for s in 20250101T000000Z-11 20250101T000000Z-12; do
    fake_record "$BO" "$s" running "$(dead_pid)"
    mkdir "$BO/trash-$s"
done
(cd "$R" && bash "$SCRIPT" --base "$B" > "$W/twice-1" 2>&1) &
p1=$!
(cd "$R" && bash "$SCRIPT" --base "$B" > "$W/twice-2" 2>&1) &
p2=$!
wait "$p1"; wait "$p2"
O1=$(cat "$W/twice-1"); O2=$(cat "$W/twice-2")
no_match "two calls at once: no stamp collision" "(removal-|trash-).* failed" "$O1
$O2"
R1=$(record_of "$O1"); R2=$(record_of "$O2")
if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" != "$R2" ]; then ok "two calls at once: two records, two stamps"
else bad "two calls at once: two records, two stamps" "[$R1] [$R2]"; fi
for f in "$R1" "$R2"; do
    s=$(bo_record_stamp "$f")
    if printf '%s\n' "$s" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-[0-9]+$'; then ok "a stamp is <UTC time>-<pid>"; else bad "a stamp is <UTC time>-<pid>" "[$s]"; fi
    wait_status "$f" >/dev/null
done

# --- 3. an empty declaration, and reaping ------------------------------------------------

for decl in none '[]'; do
    R="$W/empty-$( [ "$decl" = none ] && echo none || echo list )"
    B=$(mkrepo "$R" "$decl")
    cbo "$R" --base "$B"
    eq "declaration $decl: prints nothing" "" "$OUT"
    exists "declaration $decl: target stays" "$R/target/debug/app"
    eq "declaration $decl: no record, no trash" "" "$(ls -A "$R/.git/shirabe-build-output")"
done

R="$W/nomap"
mkrepo "$R" '["target/"]' >/dev/null
git -C "$R" rm -q -r .claude
git -C "$R" commit -q -m no-map
B=$(git -C "$R" rev-parse HEAD)
cbo "$R" --base "$B"
eq "no map at the base: declares nothing, prints nothing" "" "$OUT"
exists "no map at the base: target stays" "$R/target/debug/app"

R="$W/reap"
B=$(mkrepo "$R" '[]')
BO="$R/.git/shirabe-build-output"
mkdir "$BO"
OLD=20250101T000000Z-21
fake_record "$BO" "$OLD" running "$(dead_pid)"
mkdir -p "$BO/trash-$OLD/1"
printf 'old\n' > "$BO/trash-$OLD/1/f"
sleep 30 &
SLEEPER=$!
OTHER=20250101T000000Z-22
fake_record "$BO" "$OTHER" running "$SLEEPER"
mkdir -p "$BO/trash-$OTHER/1"
# A record that names a path inside it never steers the reaper.
mkdir "$W/victim-dir"
printf 'keep\n' > "$W/victim-dir/f"
jq --arg v "$W/victim-dir" '.reaped = [$v, "../../victim-dir"] | .paths = {"1": $v}' "$BO/removal-$OLD.json" > "$W/tmp.json"
mv "$W/tmp.json" "$BO/removal-$OLD.json"
cbo "$R" --base "$B"
REC=$(record_of "$OUT")
if [ -n "$REC" ]; then ok "an ended record: this call writes a record"; else bad "an ended record: this call writes a record" "$OUT"; fi
eq "an ended record: the new record's paths are empty" "{}" "$(jq -c .paths "$REC")"
eq "an ended record: reaped names both trashes" '["trash-20250101T000000Z-21","trash-20250101T000000Z-22"]' "$(jq -c '.reaped | sort' "$REC")"
eq "an ended record is marked failed" "failed" "$(jq -r .status "$BO/removal-$OLD.json")"
eq "a live pid running another program reads ended and is marked failed" "failed" "$(jq -r .status "$BO/removal-$OTHER.json")"
eq "the reaping call's deleter ends done" "done" "$(wait_status "$REC")"
missing "the reaped trash is deleted" "$BO/trash-$OLD"
missing "the second reaped trash is deleted" "$BO/trash-$OTHER"
eq "a path inside a reaped record is never deleted" "keep" "$(cat "$W/victim-dir/f")"
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null

# A live removal: a process whose command line is the deleter's for that stamp.
mkdir "$W/fake"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$W/fake/clean-build-output.sh"
LIVE=20250101T000000Z-23
bash "$W/fake/clean-build-output.sh" --delete "$LIVE" &
LIVEPID=$!
sleep 0.3
fake_record "$BO" "$LIVE" running "$LIVEPID"
mkdir -p "$BO/trash-$LIVE/1"
if bo_record_live "$BO/removal-$LIVE.json"; then ok "bo_record_live reads a matching deleter live"; else bad "bo_record_live reads a matching deleter live"; fi
cbo "$R" --base "$B"
eq "a live removal: a second call says nothing and writes nothing" "" "$OUT"
eq "a live removal: its record is left alone" "running" "$(jq -r .status "$BO/removal-$LIVE.json")"
exists "a live removal: its trash is left alone" "$BO/trash-$LIVE/1"
kill "$LIVEPID" 2>/dev/null; wait "$LIVEPID" 2>/dev/null
if bo_record_live "$BO/removal-$LIVE.json"; then bad "a dead deleter reads ended"; else ok "a dead deleter reads ended"; fi

# Unparsable records: named, and neither they nor their trash touched.
BAD1=20250101T000000Z-31
BAD2=20250101T000000Z-32
printf 'not json' > "$BO/removal-$BAD1.json"
printf '{"status": "running", "pid": "x"}' > "$BO/removal-$BAD2.json"
mkdir -p "$BO/trash-$BAD1/1" "$BO/trash-$BAD2/1"
cbo "$R" --base "$B"
has_line "an unparsable record is named" "build-output: removal-$BAD1.json unreadable, left in place" "$OUT"
has_line "a running record with no pid is named" "build-output: removal-$BAD2.json unreadable, left in place" "$OUT"
eq "an unparsable record is untouched" "not json" "$(cat "$BO/removal-$BAD1.json")"
exists "an unparsable record's trash is untouched" "$BO/trash-$BAD1/1"
exists "a pid-less record's trash is untouched" "$BO/trash-$BAD2/1"
if bo_record_live "$BO/removal-$BAD1.json"; then bad "bo_record_live reads an unparsable record ended"; else ok "bo_record_live reads an unparsable record ended"; fi

# --- 4. the base -----------------------------------------------------------------------------

R="$W/base"
B=$(mkrepo "$R" '["target/"]')
git -C "$R" checkout -q -b side
printf 'side\n' > "$R/side"
git -C "$R" add side
git -C "$R" commit -q -m side
SIDE=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q main
cbo "$R" --base "$SIDE"
eq "a base that isn't an ancestor of HEAD: unreadable" "build-output: base unreadable, removed nothing" "$OUT"
cbo "$R" --base 0123456789abcdef0123456789abcdef01234567
eq "a base that names no commit: unreadable" "build-output: base unreadable, removed nothing" "$OUT"
cbo "$R" --base 'HEAD~0'
eq "a base that isn't a sha: unreadable" "build-output: base unreadable, removed nothing" "$OUT"
printf 'not json\n' > "$R/.claude/shirabe-extensions/verification-map.json"
git -C "$R" commit -q -am broken
BROKEN=$(git -C "$R" rev-parse HEAD)
cbo "$R" --base "$BROKEN"
eq "an unparsable map at the base: unreadable" "build-output: base unreadable, removed nothing" "$OUT"
exists "an unreadable base: target stays" "$R/target/debug/app"
eq "an unreadable base: no record" "" "$(ls -A "$R/.git/shirabe-build-output")"

# With an origin: the base must also be an ancestor of, or equal to, the
# default branch's remote ref.
git init -q -b main --bare "$W/origin.git"
O=$(mkrepo "$W/seed" '["target/"]')
git -C "$W/seed" push -q "$W/origin.git" main
git clone -q "$W/origin.git" "$W/clone"
printf '## Build Output Cleanup: on\n' > "$W/clone/CLAUDE.local.md"
mkdir -p "$W/clone/target"
printf 'local\n' > "$W/clone/local"
git -C "$W/clone" add local
git -C "$W/clone" commit -q -m local
AHEAD=$(git -C "$W/clone" rev-parse HEAD)
cbo "$W/clone" --base "$AHEAD"
eq "a base ahead of origin/HEAD: unreadable" "build-output: base unreadable, removed nothing" "$OUT"
exists "a base ahead of origin/HEAD: target stays" "$W/clone/target"
cbo "$W" --base "$O" --root "$W/clone"
has_line "a base equal to origin/HEAD, called from outside the clone: removed" "target/ removed" "$OUT"
REC=$(record_of "$OUT")
case "$REC" in
    "$W/clone/.git/shirabe-build-output/removal-"*.json) ok "a plain clone's records sit in <root>/.git" ;;
    *) bad "a plain clone's records sit in <root>/.git" "[$REC]" ;;
esac
wait_status "$REC" >/dev/null

# The declaration is read only at the base.
R="$W/atbase"
B=$(mkrepo "$R" '["target/", "old/"]')
jq '.build_output = ["target/", "out/"]' "$R/.claude/shirabe-extensions/verification-map.json" > "$W/m.json"
mv "$W/m.json" "$R/.claude/shirabe-extensions/verification-map.json"
git -C "$R" commit -q -am widen
mkdir -p "$R/out" "$R/old"
cbo "$R" --base "$B"
has_line "at the base: target/ removed" "target/ removed" "$OUT"
has_line "at the base: old/, which the branch dropped, still removed" "old/ removed" "$OUT"
exists "at the base: out/, which the branch added, stays" "$R/out"
no_match "at the base: no line for out/" "^out/" "$OUT"
wait_status "$(record_of "$OUT")" >/dev/null

# --- 5. each path's checks ----------------------------------------------------------------

R="$W/words"
B=$(mkrepo "$R" '["/abs", "../x", "a/../../x", ".", "link-dir", "lnk/inner", "README", "ignored/", "plain/", ".git", "nest/", "CLAUDE.md", "CLAUDE.local.md", ".env", ".env.local", "missing/", "target/"]')
mkdir -p "$W/link-target" "$W/lnk-target/inner"
printf 'keep\n' > "$W/link-target/f"
printf 'keep\n' > "$W/lnk-target/inner/f"
ln -s "$W/link-target" "$R/link-dir"
ln -s "$W/lnk-target" "$R/lnk"
mkdir -p "$R/ignored"
printf 'tracked inside\n' > "$R/ignored/held"
git -C "$R" add -f ignored/held
git -C "$R" commit -q -m held
mkdir -p "$R/plain" "$R/nest/inner"
git init -q "$R/nest/inner"
printf 'local\n' > "$R/CLAUDE.md"
printf 'secret\n' > "$R/.env"
printf 'secret\n' > "$R/.env.local"
cbo "$R" --base "$B"
has_line "absolute" "/abs absolute" "$OUT"
has_line "outside: ../x" "../x outside" "$OUT"
has_line "outside: a/../../x" "a/../../x outside" "$OUT"
has_line "outside: ." ". outside" "$OUT"
has_line "symlink: a symlinked path" "link-dir symlink" "$OUT"
has_line "symlink: a path under a symlinked directory" "lnk/inner symlink" "$OUT"
has_line "tracked: a tracked file" "README tracked" "$OUT"
has_line "tracked: an ignored directory holding one tracked file" "ignored/ tracked" "$OUT"
has_line "not-ignored: an untracked path git doesn't ignore" "plain/ not-ignored" "$OUT"
has_line "not-ignored: a declared .git" ".git not-ignored" "$OUT"
has_line "protected: an ignored directory holding a nested .git" "nest/ protected" "$OUT"
has_line "protected: CLAUDE.md" "CLAUDE.md protected" "$OUT"
has_line "protected: CLAUDE.local.md" "CLAUDE.local.md protected" "$OUT"
has_line "protected: .env" ".env protected" "$OUT"
has_line "protected: .env.local" ".env.local protected" "$OUT"
has_line "gone: a missing path" "missing/ gone" "$OUT"
has_line "a valid path beside them is removed" "target/ removed" "$OUT"
eq "the link targets are unchanged" "keep keep" "$(cat "$W/link-target/f") $(cat "$W/lnk-target/inner/f")"
for p in link-dir lnk README ignored/held plain nest/inner/.git CLAUDE.md CLAUDE.local.md .env .env.local .git; do
    exists "a refused path is untouched: $p" "$R/$p"
done
wait_status "$(record_of "$OUT")" >/dev/null

# .claude untracked and ignored: protected; tracked: tracked. The map is read
# at the base, where .claude was still tracked.
R="$W/dotclaude"
B=$(mkrepo "$R" '[".claude", "CLAUDE.md"]')
printf 'tracked\n' > "$R/CLAUDE.md"
git -C "$R" add -f CLAUDE.md
git -C "$R" commit -q -m claude-md
B=$(git -C "$R" rev-parse HEAD)
cbo "$R" --base "$B"
has_line "a tracked .claude reports tracked" ".claude tracked" "$OUT"
has_line "a tracked CLAUDE.md reports tracked" "CLAUDE.md tracked" "$OUT"
git -C "$R" rm -r -q --cached .claude
printf '.claude/\n' >> "$R/.gitignore"
git -C "$R" commit -q -am untrack
cbo "$R" --base "$B"
has_line "an untracked, ignored .claude is protected" ".claude protected" "$OUT"
exists "a protected .claude is untouched" "$R/.claude/shirabe-extensions/verification-map.json"

# A mount: a directory on a device other than the work tree's.
R="$W/mount"
B=$(mkrepo "$R" '["mnt/"]')
mkdir -p "$R/mnt/sub"
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_ROOT_DEV=999999 bash "$SCRIPT" --base "$B")
has_line "protected: an ignored mount" "mnt/ protected" "$OUT"
exists "a protected mount is untouched" "$R/mnt/sub"

# Case-folded tracking: Target/ against a tracked target/ with core.ignorecase.
R="$W/case"
B=$(mkrepo "$R" '["Target/"]')
rm -rf "$R/target"
mkdir "$R/target"
printf 'tracked\n' > "$R/target/f"
git -C "$R" add -f target/f
git -C "$R" commit -q -m tracked-target
git -C "$R" config core.ignorecase true
printf 'Target/\n' >> "$R/.git/info/exclude"
[ -e "$R/Target" ] || { mkdir "$R/Target"; printf 'x\n' > "$R/Target/g"; }
cbo "$R" --base "$B"
has_line "Target/ against a tracked target/ with core.ignorecase: tracked" "Target/ tracked" "$OUT"
exists "a case-folded tracked path is untouched" "$R/target/f"

# The order: a path failing two checks reports only the first.
R="$W/order"
B=$(mkrepo "$R" '["/abs/..", "missing/../../x", "README-link", "README"]')
ln -s README "$R/README-link"
git -C "$R" add README-link
git -C "$R" commit -q -m link
cbo "$R" --base "$B"
has_line "absolute before outside" "/abs/.. absolute" "$OUT"
has_line "outside before gone" "missing/../../x outside" "$OUT"
has_line "symlink before tracked" "README-link symlink" "$OUT"
has_line "tracked before not-ignored" "README tracked" "$OUT"
eq "one line per path" 4 "$(printf '%s\n' "$OUT" | grep -c .)"

# --- 5b. malformed entries, normalization and nesting --------------------------------

R="$W/malformed"
B=$(mkrepo "$R" '"target/"')
cbo "$R" --base "$B"
eq "a non-list: one malformed line" "build-output: build_output malformed, removed nothing" "$OUT"
exists "a non-list: target stays" "$R/target/debug/app"

R="$W/entries"
B=$(mkrepo "$R" '[1, "", "a\nb", "a\u0001b", "target/"]')
cbo "$R" --base "$B"
has_line "a number is malformed" "1 malformed" "$OUT"
has_line "an empty string is malformed" '"" malformed' "$OUT"
has_line "a newline is malformed" '"a\nb" malformed' "$OUT"
has_line "another control character is malformed" '"a\u0001b" malformed' "$OUT"
has_line "target/ beside them is still removed" "target/ removed" "$OUT"
wait_status "$(record_of "$OUT")" >/dev/null

R="$W/dup"
B=$(mkrepo "$R" '["target", "./target/"]')
cbo "$R" --base "$B"
eq "target and ./target/: one removed line" "target removed" "$(printf '%s\n' "$OUT" | grep -v '^build-output:')"
wait_status "$(record_of "$OUT")" >/dev/null

R="$W/nested"
B=$(mkrepo "$R" '["target/debug", "target"]')
cbo "$R" --base "$B"
eq "target and target/debug: one line, for target" "target removed" "$(printf '%s\n' "$OUT" | grep -v '^build-output:')"
missing "target and target/debug: target gone" "$R/target"
wait_status "$(record_of "$OUT")" >/dev/null

R="$W/slashes"
B=$(mkrepo "$R" '[".//target", "././target/"]')
cbo "$R" --base "$B"
has_line "a leading .// leaves an absolute-looking path: outside" ".//target outside" "$OUT"
has_line "a repeated leading ./ is dropped" "././target/ removed" "$OUT"
wait_status "$(record_of "$OUT")" >/dev/null

R="$W/glob"
B=$(mkrepo "$R" '["target*"]')
mkdir -p "$R/target1"
cbo "$R" --base "$B"
has_line "target* is literal: gone" "target* gone" "$OUT"
exists "target* removes nothing named target1" "$R/target1"
exists "target* removes nothing named target" "$R/target"

R="$W/mixed"
B=$(mkrepo "$R" '["README", "target/"]')
cbo "$R" --base "$B"
has_line "a tracked path beside a valid one: tracked" "README tracked" "$OUT"
has_line "a tracked path beside a valid one: target removed" "target/ removed" "$OUT"
exists "the tracked path is kept" "$R/README"
wait_status "$(record_of "$OUT")" >/dev/null

# --- 5c. the walk budget ---------------------------------------------------------------

R="$W/walk"
B=$(mkrepo "$R" '["target/"]')
P="$W/pause-walk"
mkdir "$P"
: > "$P/walk-1.wait"
START=$SECONDS
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B" --walk-budget 1)
ELAPSED=$((SECONDS - START))
has_line "a walk past its share: failed" "target/ failed" "$OUT"
exists "a walk past its share: kept" "$R/target/debug/app"
if [ "$ELAPSED" -le 6 ]; then ok "a walk past its share returns inside the budget plus overhead (${ELAPSED}s)"
else bad "a walk past its share returns inside the budget plus overhead" "${ELAPSED}s"; fi
rm -f "$P"/*
: > "$P/walk-1.wait"
(sleep 3; : > "$P/walk-1.go") &
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B")
wait
has_line "with no --walk-budget, a 3 s walk finishes inside the 20 s default" "target/ removed" "$OUT"
wait_status "$(record_of "$OUT")" >/dev/null
if grep -q 'WALK_BUDGET_DEFAULT=20$' "$SCRIPT"; then ok "the default walk budget is 20 s"; else bad "the default walk budget is 20 s"; fi
if grep -Eq "(^|[;&|(]|then|do)[[:space:]]*timeout[[:space:]]" "$SCRIPT"; then bad "no timeout command"; else ok "no timeout command"; fi
if grep -qF "stat -f '%d:%i'" "$SCRIPT" && grep -qF "stat -c '%d:%i'" "$SCRIPT"; then ok "dev:inode in both stat dialects"
else bad "dev:inode in both stat dialects"; fi

# --- 6. the trash's numbered entries, the device check and the swaps --------------

R="$W/numbered"
B=$(mkrepo "$R" '["a/target", "b/target"]')
mkdir -p "$R/a/target" "$R/b/target"
printf 'A\n' > "$R/a/target/f"
printf 'B\n' > "$R/b/target/f"
P="$W/pause-numbered"
mkdir "$P"
: > "$P/delete.wait"
STAMP=20260101T000000Z-5151
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B")
BO="$R/.git/shirabe-build-output"
wait_file "$P/delete.reached"
eq "the first declared path is trash/1" "A" "$(cat "$BO/trash-$STAMP/1/f" 2>/dev/null)"
eq "the second declared path is trash/2" "B" "$(cat "$BO/trash-$STAMP/2/f" 2>/dev/null)"
has_line "a removed path's line" "a/target removed" "$OUT"
REC="$BO/removal-$STAMP.json"
eq "the record has exactly the design's fields while running" "paths,pid,reaped,schema,started_at,status" \
    "$(jq -r 'keys | join(",")' "$REC")"
eq "the record's schema" "shirabe-build-output-removal/v1" "$(jq -r .schema "$REC")"
eq "the record's status while running" "running" "$(jq -r .status "$REC")"
eq "the record's paths map n to the path as written" '{"1":"a/target","2":"b/target"}' "$(jq -c .paths "$REC")"
if jq -r .started_at "$REC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then ok "started_at is UTC ISO-8601 with Z"
else bad "started_at is UTC ISO-8601 with Z" "$(jq -r .started_at "$REC")"; fi
DPID=$(jq -r .pid "$REC")
case "$(ps -p "$DPID" -o command= 2>/dev/null)" in
    *"clean-build-output.sh --delete $STAMP"*) ok "the record's pid is the deleter's" ;;
    *) bad "the record's pid is the deleter's" "$(ps -p "$DPID" -o command= 2>/dev/null)" ;;
esac
if bo_record_live "$REC"; then ok "bo_record_live reads the running deleter live"; else bad "bo_record_live reads the running deleter live"; fi
eq "one record line" 1 "$(printf '%s\n' "$OUT" | grep -c 'removal recorded at')"
# A reader polling the record while the deleter rewrites it always parses it.
(
    n=0 f=0
    while [ "$n" -lt 600 ]; do
        s=$(jq -r .status "$REC" 2>/dev/null) || f=$((f + 1))
        [ "$s" = done ] && break
        n=$((n + 1))
        sleep 0.05
    done
    [ "$s" = done ] || f=$((f + 1000))
    echo "$f" > "$W/parse-failures"
) &
POLLER=$!
: > "$P/delete.go"
eq "the deleter ends done" "done" "$(wait_status "$REC")"
wait "$POLLER"
eq "a reader polling the record never failed to parse it" 0 "$(cat "$W/parse-failures")"
if jq -r .ended_at "$REC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then ok "ended_at is UTC ISO-8601 with Z"
else bad "ended_at is UTC ISO-8601 with Z" "$(jq -r .ended_at "$REC")"; fi
missing "done: the trash is gone" "$BO/trash-$STAMP"
exists "done: the log is there" "$BO/removal-$STAMP.log"

# A removal made to fail records failed.
if [ "$ROOT_USER" -eq 0 ]; then
    R="$W/rmfail"
    B=$(mkrepo "$R" '["target/"]')
    P="$W/pause-rmfail"
    mkdir "$P"
    : > "$P/delete.wait"
    STAMP=20260101T000000Z-6161
    OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B")
    BO="$R/.git/shirabe-build-output"
    wait_file "$P/delete.reached"
    chmod 000 "$BO/trash-$STAMP/1/debug"
    : > "$P/delete.go"
    eq "a removal that fails records failed" "failed" "$(wait_status "$BO/removal-$STAMP.json")"
    chmod 755 "$BO/trash-$STAMP/1/debug"
fi

# The device check: a path on another device than the trash is failed, kept.
R="$W/xdev"
B=$(mkrepo "$R" '["target/"]')
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_TRASH_DEV=999999 bash "$SCRIPT" --base "$B")
has_line "a cross-device path: failed" "target/ failed" "$OUT"
exists "a cross-device path: kept" "$R/target/debug/app"
eq "a cross-device path: no record" "" "$(record_of "$OUT")"

# swap <point> <how> <label>: at a pause point, change target/ under the script.
swap() {
    local point="$1" how="$2" label="$3" P pid
    R="$W/swap-$label"
    B=$(mkrepo "$R" '["target/"]')
    P="$W/pause-swap-$label"
    mkdir "$P"
    : > "$P/$point.wait"
    (cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B" > "$W/out-swap-$label" 2>&1) &
    pid=$!
    wait_file "$P/$point.reached"
    mv "$R/target" "$R/target.orig"
    case "$how" in
        symlink) mkdir "$W/swap-elsewhere-$label"; ln -s "$W/swap-elsewhere-$label" "$R/target" ;;
        newdir) mkdir "$R/target"; printf 'new\n' > "$R/target/new" ;;
    esac
    : > "$P/$point.go"
    wait "$pid"
    OUT=$(cat "$W/out-swap-$label")
    has_line "$label: failed" "target/ failed" "$OUT"
    exists "$label: the original stays" "$R/target.orig/debug/app"
    exists "$label: what sits at the path stays" "$R/target"
    eq "$label: no record" "" "$(record_of "$OUT")"
}
swap recheck-1 symlink "a symlink at the re-check"
swap recheck-1 newdir "a dev:inode change at the re-check"
swap rename-1 newdir "a dev:inode mismatch after the rename"
exists "a mismatch after the rename is renamed back" "$W/swap-a dev:inode mismatch after the rename/target/new"

# --- 7. the deleter survives the caller's group, and atomic rewrites ------------------

R="$W/group"
B=$(mkrepo "$R" '["target/"]')
P="$W/pause-group"
mkdir "$P"
: > "$P/delete.wait"
STAMP=20260101T000000Z-7171
set -m
(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B" > "$W/out-group" 2>&1) &
GPID=$!
set +m
wait "$GPID"
kill -KILL -- "-$GPID" 2>/dev/null
BO="$R/.git/shirabe-build-output"
wait_file "$P/delete.reached"
: > "$P/delete.go"
eq "a killed caller group: the record still reaches done" "done" "$(wait_status "$BO/removal-$STAMP.json")"
missing "a killed caller group: the trash is gone" "$BO/trash-$STAMP"

R="$W/relink"
B=$(mkrepo "$R" '["target/"]')
P="$W/pause-relink"
mkdir "$P"
: > "$P/delete.wait"
STAMP=20260101T000000Z-8181
OUT=$(cd "$R" && SHIRABE_BUILD_OUTPUT_TEST_STAMP=$STAMP SHIRABE_BUILD_OUTPUT_TEST_PAUSE=$P bash "$SCRIPT" --base "$B")
BO="$R/.git/shirabe-build-output"
wait_file "$P/delete.reached"
printf 'victim\n' > "$W/record-victim"
rm "$BO/removal-$STAMP.json"
ln -s "$W/record-victim" "$BO/removal-$STAMP.json"
: > "$P/delete.go"
i=0
while [ -e "$BO/trash-$STAMP" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.5
if [ -L "$BO/removal-$STAMP.json" ]; then ok "a record replaced by a symlink is left alone"; else bad "a record replaced by a symlink is left alone"; fi
eq "a symlinked record's target is untouched" "victim" "$(cat "$W/record-victim")"

# --- 8. a 9 GiB tree -----------------------------------------------------------------------

R="$W/big"
B=$(mkrepo "$R" '["big/"]')
mkdir -p "$R/big"
if dd if=/dev/zero of="$R/big/blob" bs=1 count=0 seek=9663676416 2>/dev/null; then
    START=$SECONDS
    cbo "$R" --base "$B"
    ELAPSED=$((SECONDS - START))
    has_line "a 9 GiB tree is removed" "big/ removed" "$OUT"
    if [ "$ELAPSED" -le 30 ]; then ok "a 9 GiB tree returns within 30 s (${ELAPSED}s)"
    else bad "a 9 GiB tree returns within 30 s" "${ELAPSED}s"; fi
    eq "a 9 GiB tree: the record reaches done" "done" "$(wait_status "$(record_of "$OUT")")"
    missing "a 9 GiB tree: the path is gone" "$R/big"
else
    echo "skip: no 9 GiB sparse file on this filesystem"
fi

# --- 9. no telemetry ---------------------------------------------------------------------

if grep -qi telemetry "$SCRIPT" "$HERE/build-output-lib.sh"; then bad "no telemetry"; else ok "no telemetry"; fi

echo
echo "clean-build-output: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
