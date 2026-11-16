#!/usr/bin/env bash
# clean-build-output.sh -- remove the build output a repository declares, once a
# workspace has turned the cleanup on.
# Part of the work-on skill
#
#   clean-build-output.sh --base <sha> [--root <dir>] [--switch-root <dir>]
#                         [--walk-budget <seconds>]
#   clean-build-output.sh --delete <stamp> [--root <dir>] [--reaped <stamp>]...
#                         (the deleter; started only by this script)
#
# A repository declares its build output as the `build_output` list in its
# verification map (skills/work-on/references/verification-map.md has the
# field, its normalization and the words below). This script removes the
# declared paths from one work tree, in order:
#
#   1. The switch. `## Build Output Cleanup: on` in `<switch-root>/CLAUDE.local.md`
#      turns the cleanup on. The file is checked before the header is read: a
#      symlink (dangling or not), a file git tracks, and an unreadable file
#      each leave the cleanup off and say which; so does a header declared
#      twice. The name must be written exactly `Build Output Cleanup`; the value
#      `on`, trimmed and in any case, is the one value that turns it on. The
#      committed CLAUDE.md is never read for it. Off prints one
#      `build-output: cleanup off` line and exits.
#   2. The records directory, `bo_dir <root>` (build-output-lib.sh), inside
#      the work tree's git directory. A symlink there, or anything but a
#      directory the current user owns, is `failed` and nothing is removed; a
#      missing one is made with plain `mkdir` (no `-p`) under umask 077, so
#      only its owner can read it. Then the call's stamp,
#      `<UTC time to the second>-<pid>`: a `removal-<stamp>.json`,
#      `removal-<stamp>.log` or `trash-<stamp>` already there, in any form, is
#      `failed` and nothing is reaped or removed.
#   3. Reaping. A record that says `running` but that bo_record_live reads
#      ended has its trash (`trash-<stamp>`, from the record's file name, never
#      from inside it) handed to this call's deleter, and is marked `failed` in
#      step 7. A record that doesn't parse is named `unreadable, left in
#      place`, and neither it nor its trash is touched.
#   4. The base. --base must be an ancestor of HEAD and, when
#      default_remote_ref resolves a ref, an ancestor of or equal to it. The
#      declaration is read only at the base, with `git show`, so a branch can't
#      widen what its own run removes. A base that fails, or an unreadable
#      base or map, prints `build-output: base unreadable, removed nothing`. A
#      map with no `build_output`, or an empty list, removes nothing and says
#      nothing; a non-list prints one `malformed` line.
#   5. Each path. An entry that isn't a non-empty string, or holds a control
#      character, is `malformed` and skipped. A leading `./` and a trailing `/`
#      are dropped; nothing else is rewritten, so an interior `//` stays as
#      written. Duplicates collapse, and a path under another declared path is
#      handled with it and gets no line. Then the checks, stopping at the
#      first that refuses: `absolute`, `outside` (a `..`, `.` itself, or any
#      other route out of the root), `gone` (missing; checked no further),
#      `symlink` (the path or a directory on the way), `tracked` (git tracks
#      something at or under its on-disk spelling, or, with core.ignorecase,
#      under its case-folded spelling), `not-ignored`, and `protected` (the
#      git directory, the common git directory or the records directory, at
#      or under the path; a `.git` entry at any depth; a
#      directory on another device; or a name in `.git`, `.claude`,
#      `CLAUDE.md`, `CLAUDE.local.md`, `.env`, `.env.*`). The `protected` walk
#      shares --walk-budget (20 s by default) across the paths that reach it;
#      one that can't finish in its share is `failed` and kept. The limit is a
#      polling one, since the macOS floor has no `timeout` command.
#   6. Renaming. Each path that passed is renamed, in declaration order, to
#      `trash-<stamp>/<n>` (n from 1). Before each rename: the path must be on
#      the trash's device, and a re-check finds no symlink on the way and the
#      dev:inode recorded at the symlink check. After it, the entry's
#      dev:inode is compared again, and a mismatch renames it back. Any of
#      these failing prints `<path> failed` and leaves the path in place.
#      When something already sits at the path again, so the entry can't go
#      back, it is moved to `kept-<stamp>-<n>` in the records directory, and
#      if even that fails the whole trash becomes `kept-<stamp>`. Nothing
#      deletes a `kept-*` entry: it isn't known to be build output, so it
#      waits for a person.
#   7. The record. A call that renamed nothing and reaped nothing writes no
#      record and starts no deleter. Otherwise it links `removal-<stamp>.log`
#      into place, starts the deleter (`--delete <stamp>`) as a `set -m` job
#      with stdin from /dev/null, output to the log and KOTO_TICK_SESSION
#      unset, so koto's group kill of the calling action never reaches it, and
#      links the record into place:
#
#        {"schema": "shirabe-build-output-removal/v1",
#         "started_at": "<UTC, ISO-8601, Z>", "pid": <the deleter's pid>,
#         "paths": {"1": "<path as written>"}, "reaped": ["trash-<stamp>"],
#         "status": "running"}
#
#      The log and the record are each written to a mktemp file in the same
#      directory and hard-linked to their name, which fails on a name that
#      exists in any form, a symlink included, and never follows one. A
#      failed link stops the deleter, renames this call's entries back (each
#      reads `failed`) and leaves the reaped records as they were. Otherwise
#      the reaped records are marked `failed` and the call prints
#      `build-output: removal recorded at <absolute path of the record>`.
#
# The deleter waits until the record names its pid (up to 10 s, then exits
# removing nothing), removes this call's trash and the reaped trash, and
# rewrites the record with `status` `done` or `failed` and `ended_at`. Every
# rewrite is a temp file renamed over the record, and only while the record is
# still a regular file and not a symlink.
#
# Output: one line per declared path, `<path as written> <word>`, in
# declaration order, where the word is one of the refusals above, `removed`,
# `malformed` or `failed`; lines about the switch, the base and the script's
# own files start with `build-output:`. Every outcome exits 0: the caller runs
# it as `test -x <script> && <script> ...; true`, and the cleanup never changes
# a run's outcome. A usage error exits 2. Nothing is sent anywhere.
#
# Test hooks, read only from the environment, which koto's fixed environment
# never carries. The stamp and the pause points can't widen what is removed.
# The two device ids can: a forged value equal to the real one would pass a
# path that sits on another device. Only the tests set them, to a value that
# differs, so the refusal they guard is exercised without a second filesystem:
#   SHIRABE_BUILD_OUTPUT_TEST_STAMP     use this stamp (it must have a stamp's
#                                       shape) instead of the time and pid
#   SHIRABE_BUILD_OUTPUT_TEST_PAUSE     a directory: at a point <p> the test
#                                       armed with `<p>.wait`, touch
#                                       `<p>.reached` and wait (up to 30 s) for
#                                       `<p>.go`. Points: walk-<k>, recheck-<n>,
#                                       rename-<n>, record, delete
#   SHIRABE_BUILD_OUTPUT_TEST_ROOT_DEV  the work tree's device id, as the
#                                       `protected` walk compares it
#   SHIRABE_BUILD_OUTPUT_TEST_TRASH_DEV the trash directory's device id, as the
#                                       rename's device check compares it
#
# Written for the bash 3.2 floor, without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SELF="$HERE/$(basename "$0")"
LIB="$HERE/../../../scripts/lib"
MAP_PATH=.claude/shirabe-extensions/verification-map.json
RECORD_SCHEMA=shirabe-build-output-removal/v1
SWITCH_NAME="Build Output Cleanup"
WALK_BUDGET_DEFAULT=20
DELETER_WAIT_TICKS=100

say() { printf 'build-output: %s\n' "$*"; }

usage() {
    cat >&2 <<'EOF'
Usage: clean-build-output.sh --base <sha> [--root <dir>] [--switch-root <dir>] [--walk-budget <seconds>]
       clean-build-output.sh --delete <stamp> [--root <dir>] [--reaped <stamp>]...
EOF
}

# shellcheck source=build-output-lib.sh
. "$HERE/build-output-lib.sh" || { say "build-output-lib.sh failed to load, removed nothing"; exit 0; }
# shellcheck source=../../../scripts/lib/claude-md-header.sh
. "$LIB/claude-md-header.sh" || { say "claude-md-header.sh failed to load, removed nothing"; exit 0; }
# shellcheck source=../../../scripts/lib/default-remote-ref.sh
. "$LIB/default-remote-ref.sh" || { say "default-remote-ref.sh failed to load, removed nothing"; exit 0; }

# A caller's git environment must not point these git calls at another
# repository, and every declared path is a literal, never a pathspec pattern.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NAMESPACE
export GIT_LITERAL_PATHSPECS=1

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

is_stamp() { printf '%s\n' "$1" | grep -Eq "$BO_STAMP_RE"; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# stat in its two dialects: GNU's -c on Linux, BSD's -f on macOS.
if stat -c '%d' / >/dev/null 2>&1; then STAT_DIALECT=gnu; else STAT_DIALECT=bsd; fi
devino() {
    if [ "$STAT_DIALECT" = gnu ]; then stat -c '%d:%i' -- "$1" 2>/dev/null
    else stat -f '%d:%i' -- "$1" 2>/dev/null; fi
}
devof() {
    if [ "$STAT_DIALECT" = gnu ]; then stat -c '%d' -- "$1" 2>/dev/null
    else stat -f '%d' -- "$1" 2>/dev/null; fi
}

test_pause() {
    local d=${SHIRABE_BUILD_OUTPUT_TEST_PAUSE:-} i=0
    [ -n "$d" ] && [ -d "$d" ] && [ -e "$d/$1.wait" ] || return 0
    : > "$d/$1.reached"
    while [ ! -e "$d/$1.go" ] && [ "$i" -lt 300 ]; do
        sleep 0.1
        i=$((i + 1))
    done
}

# phys_root <dir>: the physical path of a work tree root, or nothing when <dir>
# isn't one.
phys_root() {
    local p top
    p=$(cd "$1" 2>/dev/null && pwd -P) || return 1
    top=$(git -C "$p" rev-parse --show-toplevel 2>/dev/null) || return 1
    top=$(cd "$top" 2>/dev/null && pwd -P) || return 1
    [ "$top" = "$p" ] || return 1
    printf '%s\n' "$p"
}

# rewrite_record <record> <status>: status and ended_at, by a temp file renamed
# over the record, only while the record is a regular file and not a symlink.
rewrite_record() {
    local rec="$1" status="$2" dir tmp
    dir=${rec%/*}
    [ -f "$rec" ] && [ ! -L "$rec" ] || return 1
    tmp=$(mktemp "$dir/.tmp.XXXXXX") || return 1
    if ! jq -c --arg s "$status" --arg e "$(now_utc)" '.status = $s | .ended_at = $e' "$rec" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    if [ -f "$rec" ] && [ ! -L "$rec" ]; then
        mv -f "$tmp" "$rec" 2>/dev/null && return 0
    fi
    rm -f "$tmp"
    return 1
}

# link_new <tmp> <name>: give the file <tmp> the name <name>, failing when the
# name exists in any form. A hard link never follows a symlink and fails on an
# existing name; a name that is a directory would take the link inside it, so
# the result is checked to be <tmp> itself.
link_new() {
    local tmp="$1" name="$2"
    if [ -e "$name" ] || [ -L "$name" ]; then return 1; fi
    if ! ln -n "$tmp" "$name" 2>/dev/null; then return 1; fi
    if [ -L "$name" ] || [ ! "$name" -ef "$tmp" ]; then
        if [ -d "$name" ] && [ ! -L "$name" ]; then rm -f "$name/${tmp##*/}"; fi
        return 1
    fi
    return 0
}

# --- the deleter ---------------------------------------------------------------------

run_deleter() {
    local stamp="$1" root="$2" reaped="$3" bo rec i=0 pid s t
    local status="done"
    bo=$(bo_dir "$root") || exit 0
    [ -d "$bo" ] && [ ! -L "$bo" ] || exit 0
    rec="$bo/removal-$stamp.json"
    # Nothing is removed until the record names this process.
    while [ "$i" -lt "$DELETER_WAIT_TICKS" ]; do
        if bo_record_parses "$rec"; then
            pid=$(jq -r '.pid' "$rec" 2>/dev/null)
            [ "$pid" = "$$" ] && break
        fi
        sleep 0.1
        i=$((i + 1))
    done
    if [ "$i" -ge "$DELETER_WAIT_TICKS" ]; then
        echo "deleter $stamp: the record never named pid $$; removed nothing"
        exit 0
    fi
    test_pause delete
    for s in "$stamp" $reaped; do
        t="$bo/trash-$s"
        case "$t" in "$bo"/trash-?*) ;; *) continue ;; esac
        if [ -L "$t" ]; then status=failed; continue; fi
        [ -d "$t" ] || continue
        rm -rf -- "$t" || status=failed
        if [ -e "$t" ] || [ -L "$t" ]; then status=failed; fi
    done
    echo "deleter $stamp: $status"
    rewrite_record "$rec" "$status" || echo "deleter $stamp: the record was not rewritten"
    exit 0
}

# --- arguments -------------------------------------------------------------------------

[ $# -ge 1 ] || { usage; exit 2; }

if [ "$1" = --delete ]; then
    [ $# -ge 2 ] || { usage; exit 2; }
    D_STAMP=$2
    shift 2
    is_stamp "$D_STAMP" || { usage; exit 2; }
    D_ROOT="" D_REAPED=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root)
                [ $# -ge 2 ] && [ -z "$D_ROOT" ] || { usage; exit 2; }
                D_ROOT=$2; shift 2 ;;
            --reaped)
                [ $# -ge 2 ] && is_stamp "$2" || { usage; exit 2; }
                D_REAPED="$D_REAPED $2"; shift 2 ;;
            *) usage; exit 2 ;;
        esac
    done
    if [ -z "$D_ROOT" ]; then
        D_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    fi
    run_deleter "$D_STAMP" "$D_ROOT" "$D_REAPED"
fi

BASE="" ROOT="" SWITCH_ROOT="" WALK_BUDGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base)
            [ $# -ge 2 ] && [ -z "$BASE" ] || { usage; exit 2; }
            BASE=$2; shift 2 ;;
        --root)
            [ $# -ge 2 ] && [ -z "$ROOT" ] || { usage; exit 2; }
            ROOT=$2; shift 2 ;;
        --switch-root)
            [ $# -ge 2 ] && [ -z "$SWITCH_ROOT" ] || { usage; exit 2; }
            SWITCH_ROOT=$2; shift 2 ;;
        --walk-budget)
            [ $# -ge 2 ] && [ -z "$WALK_BUDGET" ] || { usage; exit 2; }
            WALK_BUDGET=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$BASE" ] || { usage; exit 2; }
WALK_BUDGET=${WALK_BUDGET:-$WALK_BUDGET_DEFAULT}
case "$WALK_BUDGET" in ''|*[!0-9]*|0) usage; exit 2 ;; esac

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { say "not in a work tree, removed nothing"; exit 0; }
fi
ROOT_GIVEN=$ROOT
ROOT=$(phys_root "$ROOT_GIVEN") || { say "$ROOT_GIVEN is not a work tree root, removed nothing"; exit 0; }
SWITCH_ROOT=${SWITCH_ROOT:-$ROOT}

WORK=$(mktemp -d) || { say "no temporary directory, removed nothing"; exit 0; }
trap 'rm -rf "$WORK"' EXIT

# --- 1. the switch -----------------------------------------------------------------------

switch_on() {
    local root f out rc name value tab
    root=$(phys_root "$SWITCH_ROOT") || { say "cleanup off ($SWITCH_ROOT is not a work tree root)"; return 1; }
    f="$root/CLAUDE.local.md"
    if [ -L "$f" ]; then say "cleanup off (CLAUDE.local.md is a symlink)"; return 1; fi
    if [ ! -e "$f" ]; then say "cleanup off"; return 1; fi
    if git -C "$root" ls-files --error-unmatch -- CLAUDE.local.md >/dev/null 2>&1; then
        say "cleanup off (CLAUDE.local.md is tracked)"; return 1
    fi
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then say "cleanup off (CLAUDE.local.md is unreadable)"; return 1; fi
    out=$(claude_md_header_named "$SWITCH_NAME" "$f" 2>/dev/null)
    rc=$?
    case "$rc" in
        0) ;;
        1) say "cleanup off"; return 1 ;;
        *) say "cleanup off (CLAUDE.local.md declares the header more than once)"; return 1 ;;
    esac
    tab=$(printf '\t')
    name=${out%%"$tab"*}
    value=${out#*"$tab"}
    if [ "$name" != "$SWITCH_NAME" ] || [ "$(lower "$value")" != on ]; then
        say "cleanup off"; return 1
    fi
    return 0
}
switch_on || exit 0

# --- 2. the records directory and this call's stamp -------------------------------------

BO=$(bo_dir "$ROOT") || { say "shirabe-build-output failed"; exit 0; }
if [ -L "$BO" ]; then
    say "$BO failed"; exit 0
elif [ -e "$BO" ]; then
    if [ ! -d "$BO" ] || [ ! -O "$BO" ]; then say "$BO failed"; exit 0; fi
elif ! (umask 077 && mkdir "$BO") 2>/dev/null; then
    # Another call may have made it a moment ago; it must still pass the
    # checks above.
    if [ -L "$BO" ] || [ ! -d "$BO" ] || [ ! -O "$BO" ]; then say "$BO failed"; exit 0; fi
fi

if [ -n "${SHIRABE_BUILD_OUTPUT_TEST_STAMP:-}" ]; then
    is_stamp "$SHIRABE_BUILD_OUTPUT_TEST_STAMP" || { usage; exit 2; }
    STAMP=$SHIRABE_BUILD_OUTPUT_TEST_STAMP
else
    STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
REC="$BO/removal-$STAMP.json"
LOG="$BO/removal-$STAMP.log"
TRASH="$BO/trash-$STAMP"
for f in "$REC" "$LOG" "$TRASH"; do
    if [ -e "$f" ] || [ -L "$f" ]; then say "${f##*/} failed"; exit 0; fi
done

# --- 3. reap ended removals ---------------------------------------------------------------

REAP_RECORDS=""   # stamps of records to mark failed
REAP_TRASH=""     # stamps whose trash this call's deleter takes
for rec in "$BO"/removal-*.json; do
    [ -e "$rec" ] || [ -L "$rec" ] || continue
    s=$(bo_record_stamp "$rec") || continue
    if ! bo_record_parses "$rec"; then
        say "${rec##*/} unreadable, left in place"
        continue
    fi
    [ "$(jq -r '.status' "$rec" 2>/dev/null)" = running ] || continue
    bo_record_live "$rec" && continue
    REAP_RECORDS="$REAP_RECORDS $s"
    t="$BO/trash-$s"
    if [ -d "$t" ] && [ ! -L "$t" ]; then REAP_TRASH="$REAP_TRASH $s"; fi
done

# --- 4. the base and the declaration --------------------------------------------------

ENTRY_COUNT=0
DECL=""   # empty, or a JSON array of the declaration's entries

read_declaration() {
    local sha head ref entry json kind
    case "$BASE" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
    [ "${#BASE}" -ge 4 ] || return 1
    sha=$(git -C "$ROOT" rev-parse --verify -q "$BASE^{commit}" 2>/dev/null) || return 1
    head=$(git -C "$ROOT" rev-parse --verify -q HEAD 2>/dev/null) || return 1
    git -C "$ROOT" merge-base --is-ancestor "$sha" "$head" 2>/dev/null || return 1
    if ref=$(default_remote_ref "$ROOT"); then
        git -C "$ROOT" merge-base --is-ancestor "$sha" "$ref" 2>/dev/null || return 1
    fi
    entry=$(git -C "$ROOT" ls-tree "$sha" -- "$MAP_PATH" 2>/dev/null) || return 1
    # A repository with no map at the base has declared nothing: that's a
    # healthy base, not an unreadable one, so it reads like a map without
    # build_output and says nothing.
    [ -n "$entry" ] || return 0
    json=$(git -C "$ROOT" show "$sha:$MAP_PATH" 2>/dev/null) || return 1
    printf '%s' "$json" | jq -se 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 || return 1
    kind=$(printf '%s' "$json" | jq -r 'if has("build_output") then (.build_output | type) else "absent" end')
    case "$kind" in
        absent) ;;
        array) DECL=$(printf '%s' "$json" | jq -c '.build_output') || return 1 ;;
        *) say "build_output malformed, removed nothing" ;;
    esac
    return 0
}
if ! read_declaration; then
    say "base unreadable, removed nothing"
    DECL=""
fi

# --- 5. each path ---------------------------------------------------------------------------

# Per entry, by index: the text printed for it, its normalized path, its
# on-disk spelling, its result word ("" while it is still a candidate, "-"
# for a path handled with another), and its dev:inode.
E_SHOW=() E_NORM=() E_DISK=() E_WORD=() E_DEVINO=()

if [ -n "$DECL" ]; then
    # One record per entry: a tag, then the value, NUL-terminated. "s" is a
    # usable string; "x" is anything else, shown as JSON.
    while IFS= read -r -d '' item; do
        tag=${item:0:1}
        val=${item:1}
        i=$ENTRY_COUNT
        E_DISK[$i]="" E_DEVINO[$i]=""
        if [ "$tag" = s ]; then
            E_SHOW[$i]=$val
            if [ "${val#/}" != "$val" ]; then
                E_NORM[$i]=$val
                E_WORD[$i]=absolute
            else
                # Only a leading `./` (repeated, as in `././x`) and a trailing
                # `/` are dropped. `.//x` leaves `/x`, which the outside check
                # refuses rather than rewriting the interior `//`.
                p=$val
                while [ "${p#./}" != "$p" ]; do p=${p#./}; done
                while [ "${p%/}" != "$p" ]; do p=${p%/}; done
                E_NORM[$i]=$p
                E_WORD[$i]=""
            fi
        else
            E_SHOW[$i]=$val
            E_NORM[$i]=""
            E_WORD[$i]=malformed
        fi
        ENTRY_COUNT=$((ENTRY_COUNT + 1))
    done < <(printf '%s' "$DECL" | jq -j '.[] |
        if type == "string" and length > 0
           and ((explode | map(select(. < 32 or . == 127 or (. >= 128 and . < 160))) | length) == 0)
        then "s", .
        else "x", tojson end, "\u0000"')
fi

# Duplicates and nesting: a path equal to an earlier one, or under any other
# declared path, is handled with that path and gets no line.
i=0
while [ "$i" -lt "$ENTRY_COUNT" ]; do
    if [ "${E_WORD[$i]}" = "" ] || [ "${E_WORD[$i]}" = absolute ]; then
        j=0
        while [ "$j" -lt "$ENTRY_COUNT" ]; do
            if [ "$j" -ne "$i" ] && { [ "${E_WORD[$j]}" = "" ] || [ "${E_WORD[$j]}" = absolute ] || [ "${E_WORD[$j]}" = "-" ]; } \
                && [ -n "${E_NORM[$j]}" ]; then
                if { [ "$j" -lt "$i" ] && [ "${E_NORM[$j]}" = "${E_NORM[$i]}" ]; } \
                    || [ "${E_NORM[$i]#"${E_NORM[$j]}/"}" != "${E_NORM[$i]}" ]; then
                    E_WORD[$i]="-"
                    break
                fi
            fi
            j=$((j + 1))
        done
    fi
    i=$((i + 1))
done

# has_symlink <relative path>: the path or a directory on the way is a symlink.
has_symlink() {
    local acc="" part
    local -a parts
    IFS=/ read -r -a parts <<<"$1"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        acc="${acc:+$acc/}$part"
        [ -L "$ROOT/$acc" ] && return 0
    done
    return 1
}

# ondisk <relative path>: the path as the directory entries spell it, matched
# exactly where an entry matches and case-insensitively otherwise. A component
# with no single match keeps its spelling.
ondisk() {
    local acc="" part e b lp hit n
    local -a parts
    IFS=/ read -r -a parts <<<"$1"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        hit="" n=0
        for e in "$ROOT${acc:+/$acc}"/* "$ROOT${acc:+/$acc}"/.*; do
            b=${e##*/}
            if [ "$b" = "$part" ]; then hit=$b; n=1; break; fi
        done
        if [ -z "$hit" ]; then
            lp=$(lower "$part")
            for e in "$ROOT${acc:+/$acc}"/* "$ROOT${acc:+/$acc}"/.*; do
                b=${e##*/}
                [ "${#b}" -eq "${#part}" ] || continue
                if [ "$(lower "$b")" = "$lp" ]; then hit=$b; n=$((n + 1)); fi
            done
            [ "$n" -eq 1 ] || hit=$part
        fi
        acc="${acc:+$acc/}$hit"
    done
    printf '%s\n' "$acc"
}

IGNORECASE=$(git -C "$ROOT" config --bool core.ignorecase 2>/dev/null)

is_tracked() {
    local q out lq
    for q in "$1" "$2"; do
        out=$(git -C "$ROOT" ls-files -- "$q" 2>/dev/null) || return 0
        [ -z "$out" ] || return 0
    done
    if [ "$IGNORECASE" = true ]; then
        lq=$(lower "$1")
        git -C "$ROOT" ls-files -z 2>/dev/null | tr '\0' '\n' | tr '[:upper:]' '[:lower:]' \
            | Q="$lq" awk 'BEGIN { q = ENVIRON["Q"]; f = 0 }
                $0 == q || index($0, q "/") == 1 { f = 1; exit }
                END { exit !f }' && return 0
    fi
    return 1
}

GIT_DIR_P=$(cd "$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" 2>/dev/null && pwd -P)
COMMON_DIR_P=$(cd "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
BO_P=$(cd "$BO" && pwd -P)
ROOT_DEV=${SHIRABE_BUILD_OUTPUT_TEST_ROOT_DEV:-$(devof "$ROOT")}

# protected_name <relative path>: the path is one of the fixed local files, or
# holds the git directory, the common git directory or the records directory.
protected_name() {
    local b phys g
    b=$(lower "${1##*/}")
    case "$b" in
        .git|.claude|claude.md|claude.local.md|.env|.env.*) return 0 ;;
    esac
    if [ -d "$ROOT/$1" ]; then
        phys=$(cd "$ROOT/$1" 2>/dev/null && pwd -P) || return 0
    else
        phys=$(cd "$(dirname "$ROOT/$1")" 2>/dev/null && pwd -P) || return 0
        phys="$phys/${1##*/}"
    fi
    for g in "$GIT_DIR_P" "$COMMON_DIR_P" "$BO_P"; do
        [ -n "$g" ] || return 0
        [ "$g" = "$phys" ] && return 0
        case "$g" in "$phys"/*) return 0 ;; esac
    done
    return 1
}

# walk <relative path> <ticks> <point>: sets WALK_RESULT to clear, protected
# or failed, and adds the tenths of a second it took to WALK_USED. Lists the
# path and every directory or `.git` entry under it with its device; a `.git`
# entry, another device, a line it can't read, a walk that reported an error
# and a walk that didn't finish in <ticks> tenths of a second all keep the path.
walk() {
    local path="$ROOT/$1" ticks="$2" point="$3" out wpid t=0 rc
    out="$WORK/walk.out"
    : > "$out"
    # Job control puts the walk in its own process group, so running out of
    # its share stops find and the stat calls it started in one kill.
    set -m
    if [ "$STAT_DIALECT" = gnu ]; then
        ( test_pause "$point"; exec find "$path" \( -type d -o -name .git \) -exec stat -c '%d %n' {} + ) >"$out" 2>/dev/null &
    else
        ( test_pause "$point"; exec find "$path" \( -type d -o -name .git \) -exec stat -f '%d %N' {} + ) >"$out" 2>/dev/null &
    fi
    wpid=$!
    set +m
    while kill -0 "$wpid" 2>/dev/null; do
        if [ "$t" -ge "$ticks" ]; then
            kill -TERM -- "-$wpid" 2>/dev/null || kill -TERM "$wpid" 2>/dev/null
            sleep 0.1
            kill -KILL -- "-$wpid" 2>/dev/null || kill -KILL "$wpid" 2>/dev/null
            wait "$wpid" 2>/dev/null
            WALK_USED=$((WALK_USED + t + 1))
            WALK_RESULT=failed
            return
        fi
        sleep 0.1
        t=$((t + 1))
    done
    wait "$wpid" 2>/dev/null
    rc=$?
    WALK_USED=$((WALK_USED + t))
    if [ "$rc" -ne 0 ]; then WALK_RESULT=failed; return; fi
    if D="$ROOT_DEV" awk 'BEGIN { d = ENVIRON["D"]; hit = 0 }
        {
            if (match($0, /^[0-9]+ /) == 0) { hit = 1; exit }
            dev = substr($0, 1, RLENGTH - 1)
            name = substr($0, RLENGTH + 1)
            n = split(name, parts, "/")
            if (dev != d || parts[n] == ".git") { hit = 1; exit }
        }
        END { exit hit }' "$out"; then
        WALK_RESULT=clear
    else
        WALK_RESULT=protected
    fi
}

# The checks up to not-ignored, entry by entry.
WALKERS=""
i=0
while [ "$i" -lt "$ENTRY_COUNT" ]; do
    if [ "${E_WORD[$i]}" = "" ]; then
        p=${E_NORM[$i]}
        word=""
        case "/$p/" in
            //|/./) word=outside ;;
            */../*) word=outside ;;
        esac
        [ -z "$word" ] && [ "${p#/}" != "$p" ] && word=outside
        if [ -z "$word" ] && [ ! -e "$ROOT/$p" ] && [ ! -L "$ROOT/$p" ]; then word=gone; fi
        if [ -z "$word" ]; then
            if has_symlink "$p"; then
                word=symlink
            else
                E_DEVINO[$i]=$(devino "$ROOT/$p")
                [ -n "${E_DEVINO[$i]}" ] || word=failed
            fi
        fi
        if [ -z "$word" ]; then
            disk=$(ondisk "$p")
            E_DISK[$i]=$disk
            if is_tracked "$disk" "$p"; then
                word=tracked
            # check-ignore takes paths, not pathspecs, and refuses the
            # literal-pathspec setting; its arguments are never globbed.
            elif ! GIT_LITERAL_PATHSPECS=0 git -C "$ROOT" check-ignore -q -- "$disk" 2>/dev/null; then
                word=not-ignored
            elif protected_name "$disk"; then
                word=protected
            else
                WALKERS="$WALKERS $i"
            fi
        fi
        E_WORD[$i]=$word
    fi
    i=$((i + 1))
done

# The protected walk, sharing the budget across the paths that reach it.
WALK_USED=0
WALK_RESULT=""
left_paths=0
for i in $WALKERS; do left_paths=$((left_paths + 1)); done
k=0
for i in $WALKERS; do
    k=$((k + 1))
    left=$((WALK_BUDGET * 10 - WALK_USED))
    if [ "$left" -le 0 ]; then
        E_WORD[$i]=failed
    else
        share=$((left / left_paths))
        [ "$share" -ge 1 ] || share=1
        walk "${E_DISK[$i]}" "$share" "walk-$k"
        case "$WALK_RESULT" in
            clear) E_WORD[$i]="" ;;
            protected) E_WORD[$i]=protected ;;
            *) E_WORD[$i]=failed ;;
        esac
    fi
    left_paths=$((left_paths - 1))
done

# --- 6. rename into the trash ---------------------------------------------------------------

RENAMED=""   # "n:i" pairs, in order
TRASH_MADE=0
CANDIDATES=0
i=0
while [ "$i" -lt "$ENTRY_COUNT" ]; do
    if [ "${E_WORD[$i]}" = "" ]; then CANDIDATES=$((CANDIDATES + 1)); fi
    i=$((i + 1))
done

# put_back <n> <i>: return a renamed entry to its path, or, when something
# now sits at the path, to a kept name the deleter never takes.
put_back() {
    local n="$1" i="$2" src="$ROOT/${E_DISK[$2]}"
    if [ ! -e "$src" ] && [ ! -L "$src" ] && mv -- "$TRASH/$n" "$src" 2>/dev/null; then return 0; fi
    mv -- "$TRASH/$n" "$BO/kept-$STAMP-$n" 2>/dev/null && return 0
    TRASH_TAINTED=1
    return 1
}
TRASH_TAINTED=0

if [ "$CANDIDATES" -gt 0 ]; then
    if (umask 077 && mkdir "$TRASH") 2>/dev/null; then
        TRASH_MADE=1
    else
        say "trash-$STAMP failed"
        i=0
        while [ "$i" -lt "$ENTRY_COUNT" ]; do
            [ "${E_WORD[$i]}" = "" ] && E_WORD[$i]=failed
            i=$((i + 1))
        done
    fi
fi

if [ "$TRASH_MADE" -eq 1 ]; then
    TRASH_DEV=${SHIRABE_BUILD_OUTPUT_TEST_TRASH_DEV:-$(devof "$TRASH")}
    n=0
    i=0
    while [ "$i" -lt "$ENTRY_COUNT" ]; do
        if [ "${E_WORD[$i]}" = "" ]; then
            n=$((n + 1))
            src="$ROOT/${E_DISK[$i]}"
            word=failed
            if [ "$(devof "$src")" = "$TRASH_DEV" ]; then
                test_pause "recheck-$n"
                if ! has_symlink "${E_DISK[$i]}" && [ "$(devino "$src")" = "${E_DEVINO[$i]}" ]; then
                    test_pause "rename-$n"
                    if mv -- "$src" "$TRASH/$n" 2>/dev/null; then
                        if [ ! -L "$TRASH/$n" ] && [ "$(devino "$TRASH/$n")" = "${E_DEVINO[$i]}" ]; then
                            word=removed
                            RENAMED="$RENAMED $n:$i"
                        else
                            put_back "$n" "$i"
                        fi
                    fi
                fi
            fi
            E_WORD[$i]=$word
        fi
        i=$((i + 1))
    done
fi

print_lines() {
    local i=0
    while [ "$i" -lt "$ENTRY_COUNT" ]; do
        case "${E_WORD[$i]}" in
            -|"") ;;
            *) printf '%s %s\n' "${E_SHOW[$i]}" "${E_WORD[$i]}" ;;
        esac
        i=$((i + 1))
    done
}

# --- 7. the record and the deleter ---------------------------------------------------------

if [ "$TRASH_TAINTED" -eq 1 ]; then
    # An entry that isn't ours couldn't be moved out of the trash: keep the
    # whole trash out of the deleter's reach.
    mv -- "$TRASH" "$BO/kept-$STAMP" 2>/dev/null
fi
if [ "$TRASH_MADE" -eq 1 ] && [ -z "$RENAMED" ]; then
    rmdir "$TRASH" 2>/dev/null
fi

if [ -z "$RENAMED" ] && [ -z "$REAP_RECORDS" ]; then
    print_lines
    exit 0
fi

DPID=""
# write_failed <name>: a log or record that couldn't be written. Stop the
# deleter, return this call's entries to their paths and leave the reaped
# records as they were.
write_failed() {
    local pair n i
    say "$1 failed"
    if [ -n "$DPID" ]; then
        kill -TERM "$DPID" 2>/dev/null
        wait "$DPID" 2>/dev/null
    fi
    for pair in $RENAMED; do
        n=${pair%%:*}
        i=${pair#*:}
        put_back "$n" "$i"
        E_WORD[$i]=failed
    done
    if [ "$TRASH_TAINTED" -eq 1 ]; then
        mv -- "$TRASH" "$BO/kept-$STAMP" 2>/dev/null
    else
        rmdir "$TRASH" 2>/dev/null
    fi
    print_lines
    exit 0
}

test_pause record

LOG_TMP=$(mktemp "$BO/.tmp.XXXXXX") || write_failed "removal-$STAMP.log"
if ! link_new "$LOG_TMP" "$LOG"; then
    rm -f "$LOG_TMP"
    write_failed "removal-$STAMP.log"
fi
exec 3>>"$LOG_TMP"
rm -f "$LOG_TMP"

REAPED_ARGS=""
for s in $REAP_TRASH; do REAPED_ARGS="$REAPED_ARGS --reaped $s"; done
# `set -m` gives the deleter its own process group, so koto's group kill of
# the calling action never reaches it. The `exec` keeps one process, so `$!`
# is the deleter's own pid: the record names it, the deleter waits to see it
# there, and bo_record_live matches its command line.
set -m
(
    unset KOTO_TICK_SESSION
    # shellcheck disable=SC2086 # stamps are checked tokens
    exec "$SELF" --delete "$STAMP" --root "$ROOT" $REAPED_ARGS
) </dev/null >&3 2>&3 &
DPID=$!
set +m
exec 3>&-

PATHS_JSON='{}'
for pair in $RENAMED; do
    n=${pair%%:*}
    i=${pair#*:}
    PATHS_JSON=$(jq -c --arg k "$n" --arg v "${E_SHOW[$i]}" '. + {($k): $v}' <<<"$PATHS_JSON")
done
REAPED_JSON='[]'
for s in $REAP_TRASH; do
    REAPED_JSON=$(jq -c --arg v "trash-$s" '. + [$v]' <<<"$REAPED_JSON")
done

REC_TMP=$(mktemp "$BO/.tmp.XXXXXX") || write_failed "removal-$STAMP.json"
if ! jq -n --arg schema "$RECORD_SCHEMA" --arg started "$(now_utc)" --argjson pid "$DPID" \
        --argjson paths "$PATHS_JSON" --argjson reaped "$REAPED_JSON" \
        '{schema: $schema, started_at: $started, pid: $pid, paths: $paths, reaped: $reaped, status: "running"}' \
        > "$REC_TMP"; then
    rm -f "$REC_TMP"
    write_failed "removal-$STAMP.json"
fi
if ! link_new "$REC_TMP" "$REC"; then
    rm -f "$REC_TMP"
    write_failed "removal-$STAMP.json"
fi
rm -f "$REC_TMP"

for s in $REAP_RECORDS; do
    rewrite_record "$BO/removal-$s.json" failed
done

print_lines
say "removal recorded at $REC"
exit 0
