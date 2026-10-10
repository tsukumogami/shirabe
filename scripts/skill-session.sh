#!/usr/bin/env bash
# skill-session.sh -- the operations the skill-session convention repeats:
# open, read, signal between, and close the root koto session each skill keeps
# its state in, named <skill>-<topic>.
#
# The rules live in references/skill-session-convention.md; this script is
# what a skill calls instead of restating them. Every subcommand checks its
# arguments before any koto call, every session name is composed from a
# checked skill and topic (or checked against the session grammar), and a
# value read back from a key is compared against a closed set, never placed
# on a command line. No `koto init --parent` anywhere: every session is a
# root. Every `koto next` this script issues carries --no-cleanup.
#
# Usage:
#   skill-session.sh name <skill> <topic>
#   skill-session.sh open <skill> <topic>
#   skill-session.sh status <session>
#   skill-session.sh has-work <skill> <topic>
#   skill-session.sh close <session> <done|abandoned>
#   skill-session.sh dispatch write <parent> <topic> <child> <fresh-chain|revise> [--no-suppress]
#   skill-session.sh dispatch read <child> <topic>
#   skill-session.sh dispatch clear <parent> <topic>
#   skill-session.sh adopt <child> <topic>
#   skill-session.sh close-children <parent> <topic> <done|abandoned>
#   skill-session.sh scratch
#   skill-session.sh ingest <session> <area> <dir>
#   skill-session.sh get <session> <key> <dir>
#   skill-session.sh put <session> <key> <file>
#   skill-session.sh reclaimable <session>
#
# Arguments:
#   <skill>     ^[a-z][a-z-]*$ (a skill's directory name).
#   <topic>     ^[a-z0-9][a-z0-9-]*$.
#   <session>   ^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$, the shape `name` prints.
#   <parent>    scope or charter. The parents and their children are a fixed
#               closed set:
#                 scope   -> brief prd design plan
#                 charter -> vision strategy roadmap
#   <child>     for `dispatch write`, one of <parent>'s children; for
#               `dispatch read`, `adopt`, any <skill> (one that is no parent's
#               child never matches).
#   <key>       for get and put: under work/ or research/, at most 255 bytes,
#               each `/`-separated component matching
#               ^[A-Za-z0-9][A-Za-z0-9._-]*$ (koto's key grammar), and no `..`.
#   <area>      for ingest: work, research or handoff, or a sub-area of work/
#               or research/ (work/decision-1, for a skill run inside another
#               skill's session), each component matching the key grammar
#               above, and no `..`.
#   <dir>       for ingest and get: a scratch directory -- a real directory
#               (not a symlink), owned by the caller, with no group or other
#               permission bits (mode 0700, as `scratch` makes it), outside
#               the git work tree of the current directory, and neither / nor
#               $HOME. `put`'s <file> must be a regular, non-symlink file under
#               1 MiB in such a directory.
#
# Subcommands and their output (stdout carries machine-readable lines only;
# messages go to stderr):
#
#   name      prints <skill>-<topic>. No koto call.
#
#   open      checks that koto is on PATH and at the floor
#             (scripts/assert-koto-floor.sh), that HEAD is on a branch, then
#             opens the session from koto-templates/skill-session.md (next to
#             this script's directory, not the cwd) through
#             scripts/koto-open.sh --attach-live --replace-terminal. On a new
#             or replaced session it ticks once and writes key session/branch
#             (the current branch). On an attached session it compares
#             session/branch with the current branch and refuses a mismatch;
#             an attached session with no session/branch (a crash between
#             open and the key write) is ticked and given one. Prints:
#               session=<name>
#               opened=new|attached|replaced
#               replaced_state=<state>, replaced_result=<json>  (replaced only)
#             koto-open.sh's refused=/failed=/error= lines and exit code pass
#             through unchanged; this script's own refusals print
#             refused=branch_mismatch or refused=no_branch, and a koto below
#             the floor prints failed=koto_below_floor.
#
#   status    prints absent, live or finished from `koto status`, which reads
#             only. Nothing is ticked.
#
#   has-work  exit 0 when <skill>-<topic> is live, its session/branch equals
#             the current branch, and it holds a key under work/; exit 1
#             otherwise. Prints nothing.
#
#   close     a live session from the store template gets
#             `koto next <session> --no-cleanup --with-data {"close":<v>}`.
#             Prints closed=<v> and retention=<koto's retention object>. A
#             finished or absent session is left alone: closed=noop and
#             status=finished|absent. A live session from another template
#             is refused (refused=not_store_session).
#
#   dispatch write   stores key chain/dispatch in <parent>-<topic>, which must
#             be live, as exactly three lines:
#               child: <child>
#               suppress_status_aware_prompt: true|false   (false under --no-suppress)
#               rationale: fresh-chain|revise
#             It also writes session/branch into the parent's session when
#             absent (a parent opened from its own template has none), and
#             refuses (refused=branch_mismatch) when it names another branch.
#             Prints dispatched=<child>.
#
#   dispatch read    checks scope-<topic> and charter-<topic>. A parent session
#             that is absent or finished, whose session/branch is missing or
#             differs from the current branch, with no chain/dispatch, or
#             whose value fails re-validation (exactly the three lines above;
#             child in the closed set of children; the other two fields in
#             their sets) or names another child, is no match. On one match:
#               parent=<parent>-<topic>
#               child=<child>
#               suppress_status_aware_prompt=true|false
#               rationale=fresh-chain|revise
#             No match: no output, exit 0. Two matches: no output, exit 3,
#             both session names on stderr.
#
#   dispatch clear   removes chain/dispatch from <parent>-<topic>; idempotent.
#             Prints cleared=<parent>-<topic> (or cleared=absent when there is
#             no such session).
#
#   adopt     a child's first act: runs `dispatch read` for itself and writes
#             chain/parent = the matched parent's session name into
#             <child>-<topic> (which must be live), or removes chain/parent
#             when nothing matched. Prints adopted=<parent session> or
#             adopted=none. Two matches change nothing and exit 3.
#
#   close-children   for each child in <parent>'s fixed list, re-reads
#             <child>-<topic> immediately before acting: it is closed with <v>
#             only when it is live, its chain/parent string-equals
#             <parent>-<topic>, and its session/branch equals the current
#             branch. One line per child:
#               closed=<child session>
#               skipped=<child session> reason=absent|finished|no-parent|other-parent|other-branch
#               failed=<child session>                   (its close tick failed)
#             The caller writes its own exit first and closes itself after.
#
#   scratch   prints a new private directory (mode 0700, outside the work
#             tree, from scripts/koto-open.sh --alloc-dir) for content
#             assembled for a key.
#
#   ingest    adds each entry directly in <dir> as key <area>/<name>, into a
#             live <session>, skipping (one stderr line each) a symlink, a
#             non-regular file, a name not matching
#             ^[A-Za-z0-9][A-Za-z0-9._-]*$, and a file of 1 MiB or more. A
#             file is read through `--from-file` only after it is checked, so a
#             link is never followed. Prints added=<key> per key. <dir> is
#             removed on every exit path once it has passed the scratch
#             checks: success, a failed add, a refused session, a signal.
#
#   get       writes the key's bytes to <dir>/<key below its area> -- work/a.md
#             to <dir>/a.md, work/decision-1/a.md to <dir>/decision-1/a.md, so
#             two keys of one area never share a path -- and prints the path.
#             A missing intermediate directory is created with mode 0700, so
#             the printed path's directory passes put's scratch checks. An
#             intermediate that exists as anything but a real directory, and a
#             target that exists as anything but a regular file, are refused
#             (refused=not_scratch); a directory that cannot be created prints
#             failed=mkdir. The session may be live or finished.
#   put       writes <file>'s bytes to <key> in a live <session>, and prints
#             put=<key>. <file> is left in place.
#
#   reclaimable   prints yes or no. yes only when the session is finished and
#             either holds no chain/parent, or its chain/parent string-equals
#             scope-<topic> or charter-<topic> for the session's own topic and
#             that session is absent or finished. A live or absent session, a
#             malformed chain/parent, or a name whose skill is not one the
#             convention knows is no. The topic is the session name with the
#             skill prefix removed, matched longest first against: review-plan
#             decision strategy charter explore roadmap design vision brief
#             scope plan prd.
#
# Exit codes:
#   0    success; has-work: there is work
#   1    has-work: no work; otherwise a koto operation failed (ingest: at
#        least one add failed; close-children: at least one close failed)
#   2    refused: koto-open.sh's refusal (its exit code passes through),
#        a session not in the state the subcommand needs, a path that fails
#        the scratch checks, a key outside work/ and research/
#   3    dispatch read / adopt: two parent sessions match
#   4    cannot tell: koto answered something other than a session's state
#        (status, has-work, dispatch read, adopt, reclaimable, close-children)
#   5    refused=branch_mismatch: the session belongs to another branch
#   6    refused=no_branch: HEAD is not on a branch, or not in a git work tree
#   64   usage error; no koto call was made
#   69   failed=koto_below_floor: koto is older than shirabe's floor
#   127  koto or jq is not on PATH
#   130/143  interrupted by SIGINT/SIGTERM
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH); also passed
#              to scripts/koto-open.sh and scripts/assert-koto-floor.sh.
#   KOTO_FLOOR passed through to scripts/assert-koto-floor.sh (tests only).
#
# Requires: bash 3.2+, jq, git. No eval, no associative arrays, no mapfile, no
# namerefs.

set -uo pipefail

PROG="skill-session"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
PLUGIN_ROOT=$(cd -P -- "$SCRIPT_DIR/.." && pwd -P)
TEMPLATE="$PLUGIN_ROOT/koto-templates/skill-session.md"
KOTO_OPEN="$SCRIPT_DIR/koto-open.sh"
FLOOR_CHECK="$SCRIPT_DIR/assert-koto-floor.sh"
# The nested scripts run under this same bash, so a run on the bash 3.2 floor
# stays there.
BASH_BIN="${BASH:-bash}"

RE_SKILL='^[a-z][a-z-]*$'
RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_SESSION='^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$'
RE_COMPONENT='^[A-Za-z0-9][A-Za-z0-9._-]*$'

PARENTS="scope charter"
ALL_CHILDREN="brief prd design plan vision strategy roadmap"
# Longest first, so review-plan-x is review-plan's and not plan's.
KNOWN_SKILLS="review-plan decision strategy charter explore roadmap design vision brief scope plan prd"

MAX_BYTES=1048576

KOTO="${KOTO_BIN:-koto}"

# --- cleanup ---------------------------------------------------------------

INGEST_DIR=""

cleanup() {
    if [ -n "$INGEST_DIR" ]; then
        rm -rf -- "$INGEST_DIR"
        INGEST_DIR=""
    fi
    return 0
}

on_signal() {
    cleanup
    trap - EXIT
    exit "$1"
}

trap cleanup EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

# --- small helpers -----------------------------------------------------------

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: skill-session.sh name|open|status|has-work|close|dispatch|adopt|close-children|scratch|ingest|get|put|reclaimable ... (see the header of this script)"
    exit 64
}

check_skill() { [[ "$1" =~ $RE_SKILL ]] || usage "skill name must match $RE_SKILL"; }
check_topic() { [[ "$1" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"; }
check_session() { [[ "$1" =~ $RE_SESSION ]] || usage "session name must match $RE_SESSION"; }

check_parent() {
    case " $PARENTS " in
        *" $1 "*) ;;
        *) usage "parent must be one of: $PARENTS" ;;
    esac
}

# children_of <parent> -- the parent's fixed child list.
children_of() {
    case "$1" in
        scope) printf '%s' "brief prd design plan" ;;
        charter) printf '%s' "vision strategy roadmap" ;;
        *) printf '' ;;
    esac
}

# in_list <word> <list> -- exit 0 when <word> is one of the space-separated
# words in <list>.
in_list() {
    case " $2 " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

need_tools() {
    if ! command -v "$KOTO" >/dev/null 2>&1; then
        printf 'failed=koto_missing\n'
        say "koto is not on PATH; skill sessions need koto (install it with \`tsuku install koto\`)"
        exit 127
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'failed=jq_missing\n'
        say "jq is not on PATH"
        exit 127
    fi
}

# current_branch -- set BRANCH to the checked-out branch; return 1 on a
# detached HEAD or outside a git work tree.
BRANCH=""
current_branch() {
    BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null) || { BRANCH=""; return 1; }
    [ -n "$BRANCH" ] || return 1
    return 0
}

# work_tree -- set TOPLEVEL to the physical path of the current work tree, or
# empty outside one.
TOPLEVEL=""
work_tree() {
    TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || TOPLEVEL=""
    if [ -n "$TOPLEVEL" ]; then
        TOPLEVEL=$(cd -P -- "$TOPLEVEL" 2>/dev/null && pwd -P) || TOPLEVEL=""
    fi
}

# physical_dir <dir> -- print the physical path of an existing directory.
physical_dir() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# inside_work_tree <physical path> -- exit 0 when the path is the work tree,
# lies under it, or is one of its ancestors (removing an ancestor would remove
# the work tree).
inside_work_tree() {
    [ -n "$TOPLEVEL" ] || return 1
    case "$1" in
        "$TOPLEVEL"|"$TOPLEVEL"/*) return 0 ;;
    esac
    case "$TOPLEVEL" in
        "$1"/*) return 0 ;;
    esac
    [ "$1" = "/" ] && return 0
    return 1
}

# file_mode <path> -- print the permission bits in octal (GNU or BSD stat).
file_mode() {
    stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1" 2>/dev/null
}

# scratch_dir <dir> -- exit 0 when <dir> passes the scratch checks; sets
# SCRATCH to its physical path. Prints the reason on stderr otherwise.
SCRATCH=""
scratch_dir() {
    local d="$1" mode home
    SCRATCH=""
    if [ -L "$d" ] || [ ! -d "$d" ]; then
        say "$d is not a directory (a symlink is refused)"
        return 1
    fi
    if [ ! -O "$d" ]; then
        say "$d is not owned by the current user"
        return 1
    fi
    mode=$(file_mode "$d") || mode=""
    case "$mode" in
        700|0700) ;;
        *) say "$d has mode ${mode:-unknown}; a scratch directory is 0700"; return 1 ;;
    esac
    SCRATCH=$(physical_dir "$d") || { say "cannot resolve $d"; return 1; }
    home=""
    [ -n "${HOME:-}" ] && home=$(physical_dir "$HOME")
    if [ "$SCRATCH" = "/" ] || { [ -n "$home" ] && [ "$SCRATCH" = "$home" ]; }; then
        say "$d is not a scratch directory"
        SCRATCH=""
        return 1
    fi
    work_tree
    if inside_work_tree "$SCRATCH"; then
        say "$d lies inside the work tree $TOPLEVEL; scratch content lives outside it"
        SCRATCH=""
        return 1
    fi
    return 0
}

# check_key <key> -- the get/put key rules. Prints the reason on stderr.
check_key() {
    local k="$1" rest comp
    case "$k" in
        work/*|research/*) ;;
        *) say "key must lie under work/ or research/: $k"; return 1 ;;
    esac
    case "$k" in
        *..*) say "key must not contain '..': $k"; return 1 ;;
    esac
    if [ "${#k}" -gt 255 ]; then
        say "key is longer than 255 bytes"
        return 1
    fi
    rest="$k"
    while :; do
        comp="${rest%%/*}"
        [[ "$comp" =~ $RE_COMPONENT ]] || { say "key component '$comp' must match $RE_COMPONENT"; return 1; }
        case "$rest" in
            */*) rest="${rest#*/}" ;;
            *) break ;;
        esac
    done
    return 0
}

# check_area <area> -- the ingest area rules: work, research or handoff, or a
# sub-area below work/ or research/ whose components follow the key grammar.
check_area() {
    local a="$1" rest comp
    case "$a" in
        work|research|handoff) return 0 ;;
        work/*|research/*) ;;
        *) return 1 ;;
    esac
    case "$a" in
        *..*) return 1 ;;
    esac
    [ "${#a}" -le 200 ] || return 1
    rest="${a#*/}"
    while :; do
        comp="${rest%%/*}"
        [[ "$comp" =~ $RE_COMPONENT ]] || return 1
        case "$rest" in
            */*) rest="${rest#*/}" ;;
            *) break ;;
        esac
    done
    return 0
}

# --- koto reads ----------------------------------------------------------------

# session_state <session> -- set SSTATE to absent, live or finished. Returns 4
# when koto's answer is neither a state nor "not found". `koto status` reads
# only; nothing here ticks.
SSTATE=""
session_state() {
    local out rc=0 term
    SSTATE=""
    out=$("$KOTO" status "$1" 2>/dev/null) || rc=$?
    if [ "$rc" -eq 0 ]; then
        term=$(printf '%s' "$out" | jq -r 'if type == "object" and has("is_terminal") then (.is_terminal | tostring) else "" end' 2>/dev/null) || term=""
        case "$term" in
            true) SSTATE=finished; return 0 ;;
            false) SSTATE=live; return 0 ;;
        esac
        return 4
    fi
    if [ "$rc" -eq 2 ]; then
        case "$out" in
            *"not found"*) SSTATE=absent; return 0 ;;
        esac
    fi
    return 4
}

# kget <session> <key> -- set KVAL to the key's exact bytes. Returns 0 when
# read, 1 when the key is absent, 4 when koto's answer is anything else.
KVAL=""
kget() {
    local rc=0 out
    KVAL=""
    "$KOTO" context exists "$1" "$2" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;
        *) return 4 ;;
    esac
    out=$("$KOTO" context get "$1" "$2" 2>/dev/null && printf '.') || return 4
    KVAL="${out%.}"
    return 0
}

# kput <session> <key> <value> -- write a value from a variable, through stdin.
kput() {
    printf '%s' "$3" | "$KOTO" context add "$1" "$2" >/dev/null 2>&1
}

kremove() {
    "$KOTO" context remove "$1" "$2" >/dev/null 2>&1
}

# tick <session> [--with-data <json>] -- the one place this script runs koto
# next; it always carries --no-cleanup. Sets TICK_OUT.
TICK_OUT=""
tick() {
    local s="$1" rc=0
    shift
    TICK_OUT=$("$KOTO" next "$s" --no-cleanup "$@" 2>/dev/null) || rc=$?
    return "$rc"
}

# --- name ------------------------------------------------------------------------

cmd_name() {
    [ "$#" -eq 2 ] || usage "name takes <skill> <topic>"
    check_skill "$1"
    check_topic "$2"
    printf '%s-%s\n' "$1" "$2"
}

# --- open ------------------------------------------------------------------------

cmd_open() {
    local skill topic s dir out rc first line
    [ "$#" -eq 2 ] || usage "open takes <skill> <topic>"
    skill="$1"; topic="$2"
    check_skill "$skill"
    check_topic "$topic"
    s="$skill-$topic"
    need_tools
    if ! KOTO_BIN="$KOTO" "$BASH_BIN" "$FLOOR_CHECK" >&2; then
        printf 'failed=koto_below_floor\n'
        say "koto on PATH does not meet shirabe's koto floor; upgrade koto (tsuku install koto) before opening $s"
        exit 69
    fi
    if ! current_branch; then
        printf 'refused=no_branch\n'
        say "HEAD is not on a branch here; a skill session records the branch it belongs to, so check out a branch first"
        exit 6
    fi
    if [ ! -f "$TEMPLATE" ]; then
        printf 'failed=koto_error\n'
        say "the store template is missing: $TEMPLATE"
        exit 1
    fi

    dir=$("$BASH_BIN" "$KOTO_OPEN" --alloc-dir 2>/dev/null) || dir=""
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        printf 'failed=koto_error\n'
        say "could not allocate a private directory for the args file"
        exit 1
    fi
    printf '[]\n' >"$dir/args.json"
    rc=0
    out=$(KOTO_BIN="$KOTO" "$BASH_BIN" "$KOTO_OPEN" "$s" "$TEMPLATE" "$dir/args.json" --attach-live --replace-terminal) || rc=$?
    # koto-open.sh removes the args file and the directory it allocated; this
    # covers a koto-open that died before its own cleanup ran.
    [ -d "$dir" ] && rm -rf -- "$dir"

    first=$(printf '%s\n' "$out" | head -1)
    case "$first" in
        opened=new|opened=replaced)
            if ! tick "$s" || [ "$(printf '%s' "$TICK_OUT" | jq -r '.state // ""' 2>/dev/null)" != "open" ]; then
                printf 'session=%s\n' "$s"
                printf 'failed=koto_error\n'
                say "the first tick of $s did not stop at open"
                exit 1
            fi
            if ! kput "$s" session/branch "$BRANCH"; then
                printf 'session=%s\n' "$s"
                printf 'failed=koto_error\n'
                say "could not write session/branch into $s"
                exit 1
            fi
            ;;
        opened=attached)
            rc=0
            kget "$s" session/branch || rc=$?
            case "$rc" in
                0)
                    if [ "$KVAL" != "$BRANCH" ]; then
                        printf 'session=%s\n' "$s"
                        printf 'refused=branch_mismatch\n'
                        say "$s belongs to another branch, not $BRANCH; finish it there, or remove it with \`koto session cleanup $s\`"
                        exit 5
                    fi
                    ;;
                1)
                    # A crash between an earlier open and its key write left
                    # an empty live session: finish that open now.
                    if ! tick "$s" || ! kput "$s" session/branch "$BRANCH"; then
                        printf 'session=%s\n' "$s"
                        printf 'failed=koto_error\n'
                        say "could not complete the open of $s"
                        exit 1
                    fi
                    ;;
                *)
                    printf 'session=%s\n' "$s"
                    printf 'failed=koto_error\n'
                    say "could not read session/branch from $s"
                    exit 4
                    ;;
            esac
            ;;
        *)
            # A refusal or failure from koto-open.sh: its lines and its code.
            [ -n "$out" ] && printf '%s\n' "$out"
            [ "$rc" -ne 0 ] || rc=1
            exit "$rc"
            ;;
    esac

    printf 'session=%s\n' "$s"
    printf '%s\n' "$first"
    printf '%s\n' "$out" | while IFS= read -r line; do
        case "$line" in
            replaced_state=*|replaced_result=*) printf '%s\n' "$line" ;;
        esac
    done
    exit 0
}

# --- status ------------------------------------------------------------------------

cmd_status() {
    [ "$#" -eq 1 ] || usage "status takes <session>"
    check_session "$1"
    need_tools
    if ! session_state "$1"; then
        say "cannot tell the state of $1 from koto status"
        exit 4
    fi
    printf '%s\n' "$SSTATE"
}

# --- has-work ----------------------------------------------------------------------

cmd_has_work() {
    local s list rc
    [ "$#" -eq 2 ] || usage "has-work takes <skill> <topic>"
    check_skill "$1"
    check_topic "$2"
    s="$1-$2"
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    [ "$SSTATE" = "live" ] || exit 1
    current_branch || exit 1
    rc=0
    kget "$s" session/branch || rc=$?
    case "$rc" in
        0) [ "$KVAL" = "$BRANCH" ] || exit 1 ;;
        1) exit 1 ;;
        *) say "cannot read session/branch from $s"; exit 4 ;;
    esac
    list=$("$KOTO" context list "$s" 2>/dev/null) || { say "cannot list the keys of $s"; exit 4; }
    rc=0
    printf '%s' "$list" | jq -e 'type == "array" and any(.[]; type == "string" and startswith("work/"))' >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) exit 0 ;;
        1) exit 1 ;;
        *) say "cannot read the key list of $s"; exit 4 ;;
    esac
}

# --- close ---------------------------------------------------------------------------

# close_session <session> <value> -- prints the result lines; returns the exit
# code the caller should use.
close_session() {
    local s="$1" v="$2" ok retention
    session_state "$s" || { say "cannot tell the state of $s"; return 4; }
    case "$SSTATE" in
        absent|finished)
            printf 'closed=noop\nstatus=%s\n' "$SSTATE"
            return 0
            ;;
    esac
    # Only the store template's open state takes close evidence.
    ok=$("$KOTO" status "$s" 2>/dev/null | jq -r 'if .current_state == "open" and (.expects.fields.close.values // []) == ["done","abandoned"] then "yes" else "no" end' 2>/dev/null) || ok=""
    if [ "$ok" != "yes" ]; then
        printf 'refused=not_store_session\n'
        say "$s is not an open session from the store template; close it through its own skill"
        return 2
    fi
    if ! tick "$s" --with-data "$(jq -n -c --arg v "$v" '{close: $v}')"; then
        printf 'failed=koto_error\n'
        say "koto refused the close tick of $s"
        return 1
    fi
    retention=$(printf '%s' "$TICK_OUT" | jq -c '.retention // null' 2>/dev/null) || retention="null"
    if [ "$(printf '%s' "$TICK_OUT" | jq -r '.retention.retained // false' 2>/dev/null)" != "true" ]; then
        printf 'failed=koto_error\nretention=%s\n' "$retention"
        say "koto did not keep $s at its close"
        return 1
    fi
    printf 'closed=%s\nretention=%s\n' "$v" "$retention"
    return 0
}

cmd_close() {
    local rc=0
    [ "$#" -eq 2 ] || usage "close takes <session> <done|abandoned>"
    check_session "$1"
    case "$2" in
        done|abandoned) ;;
        *) usage "close value must be done or abandoned" ;;
    esac
    need_tools
    close_session "$1" "$2" || rc=$?
    exit "$rc"
}

# --- dispatch -------------------------------------------------------------------------

cmd_dispatch_write() {
    local parent topic child rationale suppress=true s rc
    [ "$#" -ge 4 ] && [ "$#" -le 5 ] || usage "dispatch write takes <parent> <topic> <child> <fresh-chain|revise> [--no-suppress]"
    parent="$1"; topic="$2"; child="$3"; rationale="$4"
    if [ "$#" -eq 5 ]; then
        [ "$5" = "--no-suppress" ] || usage "unknown option: $5"
        suppress=false
    fi
    check_parent "$parent"
    check_topic "$topic"
    in_list "$child" "$(children_of "$parent")" || usage "$child is not one of $parent's children: $(children_of "$parent")"
    case "$rationale" in
        fresh-chain|revise) ;;
        *) usage "rationale must be fresh-chain or revise" ;;
    esac
    s="$parent-$topic"
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" != "live" ]; then
        printf 'refused=parent_not_live\n'
        say "$s is $SSTATE; open the parent's session before dispatching"
        exit 2
    fi
    if ! current_branch; then
        printf 'refused=no_branch\n'
        say "HEAD is not on a branch here"
        exit 6
    fi
    rc=0
    kget "$s" session/branch || rc=$?
    case "$rc" in
        0)
            if [ "$KVAL" != "$BRANCH" ]; then
                printf 'refused=branch_mismatch\n'
                say "$s belongs to another branch, not $BRANCH"
                exit 5
            fi
            ;;
        1)
            kput "$s" session/branch "$BRANCH" || { printf 'failed=koto_error\n'; say "could not write session/branch into $s"; exit 1; }
            ;;
        *) say "cannot read session/branch from $s"; exit 4 ;;
    esac
    if ! kput "$s" chain/dispatch "child: $child
suppress_status_aware_prompt: $suppress
rationale: $rationale
"; then
        printf 'failed=koto_error\n'
        say "could not write chain/dispatch into $s"
        exit 1
    fi
    printf 'dispatched=%s\n' "$child"
}

# parse_dispatch <value> -- validate a chain/dispatch value. Sets D_CHILD,
# D_SUPPRESS, D_RATIONALE; returns 1 on anything but exactly the three lines
# with values in their closed sets.
D_CHILD=""; D_SUPPRESS=""; D_RATIONALE=""
parse_dispatch() {
    local v="$1" line n=0 c="" su="" ra=""
    D_CHILD=""; D_SUPPRESS=""; D_RATIONALE=""
    # The value ends in one newline. Drop it, so the here-document below (which
    # adds one back) reads exactly the value's lines; a blank line left over
    # from a second trailing newline fails the case below.
    case "$v" in
        *"
") v="${v%?}" ;;
        *) return 1 ;;
    esac
    while IFS= read -r line; do
        n=$((n + 1))
        case "$line" in
            "child: "*) [ -z "$c" ] || return 1; c="${line#child: }" ;;
            "suppress_status_aware_prompt: "*) [ -z "$su" ] || return 1; su="${line#suppress_status_aware_prompt: }" ;;
            "rationale: "*) [ -z "$ra" ] || return 1; ra="${line#rationale: }" ;;
            *) return 1 ;;
        esac
    done <<EOF
$v
EOF
    [ "$n" -eq 3 ] && [ -n "$c" ] && [ -n "$su" ] && [ -n "$ra" ] || return 1
    in_list "$c" "$ALL_CHILDREN" || return 1
    case "$su" in true|false) ;; *) return 1 ;; esac
    case "$ra" in fresh-chain|revise) ;; *) return 1 ;; esac
    D_CHILD="$c"; D_SUPPRESS="$su"; D_RATIONALE="$ra"
    return 0
}

# dispatch_match <child> <topic> -- check both parents. Sets M_COUNT, M_PARENT
# (the first match), M_OTHER (the second), and the D_* fields of the first
# match. Returns 4 when a parent's state or keys cannot be read.
M_COUNT=0; M_PARENT=""; M_OTHER=""
F_SUPPRESS=""; F_RATIONALE=""
dispatch_match() {
    local child="$1" topic="$2" p s rc have_branch=1
    M_COUNT=0; M_PARENT=""; M_OTHER=""; F_SUPPRESS=""; F_RATIONALE=""
    current_branch || have_branch=0
    for p in $PARENTS; do
        s="$p-$topic"
        session_state "$s" || return 4
        [ "$SSTATE" = "live" ] || continue
        [ "$have_branch" -eq 1 ] || continue
        rc=0; kget "$s" session/branch || rc=$?
        case "$rc" in 0) ;; 1) continue ;; *) return 4 ;; esac
        [ "$KVAL" = "$BRANCH" ] || continue
        rc=0; kget "$s" chain/dispatch || rc=$?
        case "$rc" in 0) ;; 1) continue ;; *) return 4 ;; esac
        parse_dispatch "$KVAL" || continue
        [ "$D_CHILD" = "$child" ] || continue
        M_COUNT=$((M_COUNT + 1))
        if [ "$M_COUNT" -eq 1 ]; then
            M_PARENT="$s"; F_SUPPRESS="$D_SUPPRESS"; F_RATIONALE="$D_RATIONALE"
        else
            M_OTHER="$s"
        fi
    done
    return 0
}

cmd_dispatch_read() {
    local child topic
    [ "$#" -eq 2 ] || usage "dispatch read takes <child> <topic>"
    child="$1"; topic="$2"
    check_skill "$child"
    check_topic "$topic"
    need_tools
    dispatch_match "$child" "$topic" || { say "cannot read the parent sessions for $topic"; exit 4; }
    case "$M_COUNT" in
        0) exit 0 ;;
        1)
            printf 'parent=%s\nchild=%s\nsuppress_status_aware_prompt=%s\nrationale=%s\n' \
                "$M_PARENT" "$child" "$F_SUPPRESS" "$F_RATIONALE"
            exit 0
            ;;
        *)
            say "two parent sessions dispatch $child on $topic: $M_PARENT and $M_OTHER; clear the stale one with \`skill-session.sh dispatch clear <parent> $topic\`"
            exit 3
            ;;
    esac
}

cmd_dispatch_clear() {
    local s
    [ "$#" -eq 2 ] || usage "dispatch clear takes <parent> <topic>"
    check_parent "$1"
    check_topic "$2"
    s="$1-$2"
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" = "absent" ]; then
        printf 'cleared=absent\n'
        exit 0
    fi
    kremove "$s" chain/dispatch || { printf 'failed=koto_error\n'; say "could not remove chain/dispatch from $s"; exit 1; }
    printf 'cleared=%s\n' "$s"
}

cmd_dispatch() {
    [ "$#" -ge 1 ] || usage "dispatch takes write, read or clear"
    local sub="$1"
    shift
    case "$sub" in
        write) cmd_dispatch_write "$@" ;;
        read) cmd_dispatch_read "$@" ;;
        clear) cmd_dispatch_clear "$@" ;;
        *) usage "dispatch takes write, read or clear" ;;
    esac
}

# --- adopt ---------------------------------------------------------------------------

cmd_adopt() {
    local child topic s
    [ "$#" -eq 2 ] || usage "adopt takes <child> <topic>"
    child="$1"; topic="$2"
    check_skill "$child"
    check_topic "$topic"
    s="$child-$topic"
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" != "live" ]; then
        printf 'refused=session_not_live\n'
        say "$s is $SSTATE; open it with \`skill-session.sh open $child $topic\` first"
        exit 2
    fi
    dispatch_match "$child" "$topic" || { say "cannot read the parent sessions for $topic"; exit 4; }
    case "$M_COUNT" in
        0)
            kremove "$s" chain/parent || { printf 'failed=koto_error\n'; say "could not remove chain/parent from $s"; exit 1; }
            printf 'adopted=none\n'
            ;;
        1)
            kput "$s" chain/parent "$M_PARENT" || { printf 'failed=koto_error\n'; say "could not write chain/parent into $s"; exit 1; }
            printf 'adopted=%s\n' "$M_PARENT"
            ;;
        *)
            say "two parent sessions dispatch $child on $topic: $M_PARENT and $M_OTHER; nothing was adopted"
            exit 3
            ;;
    esac
}

# --- close-children ------------------------------------------------------------------

cmd_close_children() {
    local parent topic v ps c cs rc worst=0 lines
    [ "$#" -eq 3 ] || usage "close-children takes <parent> <topic> <done|abandoned>"
    parent="$1"; topic="$2"; v="$3"
    check_parent "$parent"
    check_topic "$topic"
    case "$v" in
        done|abandoned) ;;
        *) usage "close value must be done or abandoned" ;;
    esac
    ps="$parent-$topic"
    need_tools
    if ! current_branch; then
        printf 'refused=no_branch\n'
        say "HEAD is not on a branch here"
        exit 6
    fi
    for c in $(children_of "$parent"); do
        cs="$c-$topic"
        # Re-read the state and both keys immediately before the close.
        if ! session_state "$cs"; then
            say "cannot tell the state of $cs; left alone"
            worst=4
            continue
        fi
        if [ "$SSTATE" != "live" ]; then
            printf 'skipped=%s reason=%s\n' "$cs" "$SSTATE"
            continue
        fi
        rc=0; kget "$cs" chain/parent || rc=$?
        case "$rc" in
            0) ;;
            1) printf 'skipped=%s reason=no-parent\n' "$cs"; continue ;;
            *) say "cannot read chain/parent from $cs; left alone"; worst=4; continue ;;
        esac
        if [ "$KVAL" != "$ps" ]; then
            printf 'skipped=%s reason=other-parent\n' "$cs"
            continue
        fi
        rc=0; kget "$cs" session/branch || rc=$?
        case "$rc" in
            0) ;;
            1) printf 'skipped=%s reason=other-branch\n' "$cs"; continue ;;
            *) say "cannot read session/branch from $cs; left alone"; worst=4; continue ;;
        esac
        if [ "$KVAL" != "$BRANCH" ]; then
            printf 'skipped=%s reason=other-branch\n' "$cs"
            continue
        fi
        rc=0
        lines=$(close_session "$cs" "$v") || rc=$?
        if [ "$rc" -eq 0 ]; then
            case "$lines" in
                closed=noop*) printf 'skipped=%s reason=finished\n' "$cs" ;;
                *) printf 'closed=%s\n' "$cs" ;;
            esac
        else
            printf 'failed=%s\n' "$cs"
            [ "$worst" -ne 0 ] || worst=1
        fi
    done
    exit "$worst"
}

# --- scratch -------------------------------------------------------------------------

cmd_scratch() {
    local d
    [ "$#" -eq 0 ] || usage "scratch takes no argument"
    d=$("$BASH_BIN" "$KOTO_OPEN" --alloc-dir 2>/dev/null) || d=""
    if [ -z "$d" ] || [ ! -d "$d" ]; then
        say "could not allocate a scratch directory"
        exit 1
    fi
    # koto-open.sh marks the directories it allocates for its own args file;
    # a scratch directory holds only what the caller writes.
    rm -f -- "$d/.koto-open-alloc"
    printf '%s\n' "$d"
}

# --- ingest --------------------------------------------------------------------------

cmd_ingest() {
    local s area dir f name size failed=0 added=0
    [ "$#" -eq 3 ] || usage "ingest takes <session> <area> <dir>"
    s="$1"; area="$2"; dir="$3"
    # The directory is checked first: once it passes, it is removed on every
    # exit path from here on, usage errors included. One that fails is never
    # removed.
    if ! scratch_dir "$dir"; then
        printf 'refused=not_scratch\n'
        exit 2
    fi
    INGEST_DIR="$SCRATCH"
    check_session "$s"
    check_area "$area" || usage "area must be work, research or handoff, or a sub-area of work/ or research/"
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" != "live" ]; then
        printf 'refused=session_not_live\n'
        say "$s is $SSTATE; nothing was ingested"
        exit 2
    fi
    for f in "$INGEST_DIR"/* "$INGEST_DIR"/.[!.]* "$INGEST_DIR"/..?*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        name="${f##*/}"
        if [ -L "$f" ]; then
            say "skipped $name: a symlink"
            continue
        fi
        if [ ! -f "$f" ]; then
            say "skipped $name: not a regular file"
            continue
        fi
        if ! [[ "$name" =~ $RE_COMPONENT ]]; then
            say "skipped $name: the name must match $RE_COMPONENT"
            continue
        fi
        size=$(wc -c <"$f" 2>/dev/null | tr -d ' ') || size=""
        case "$size" in
            ''|*[!0-9]*) say "skipped $name: cannot read its size"; continue ;;
        esac
        if [ "$size" -ge "$MAX_BYTES" ]; then
            say "skipped $name: $size bytes, at or over the 1 MiB cap"
            continue
        fi
        if "$KOTO" context add "$s" "$area/$name" --from-file "$f" >/dev/null 2>&1; then
            printf 'added=%s/%s\n' "$area" "$name"
            added=$((added + 1))
        else
            say "failed to add $area/$name to $s"
            failed=1
        fi
    done
    [ "$failed" -eq 0 ] || exit 1
    exit 0
}

# --- get / put -------------------------------------------------------------------------

cmd_get() {
    local s key dir target rc rel sub rest
    [ "$#" -eq 3 ] || usage "get takes <session> <key> <dir>"
    s="$1"; key="$2"; dir="$3"
    check_session "$s"
    check_key "$key" || { printf 'refused=bad_key\n'; exit 2; }
    case "$dir" in
        *..*) printf 'refused=not_scratch\n'; say "the directory must not contain '..'"; exit 2 ;;
    esac
    scratch_dir "$dir" || { printf 'refused=not_scratch\n'; exit 2; }
    # The path below the area, so work/a.md and work/decision-1/a.md land
    # apart. check_key has already held every component to the key grammar.
    rel="${key#*/}"
    sub="$SCRATCH"
    rest="$rel"
    while :; do
        case "$rest" in
            */*) ;;
            *) break ;;
        esac
        sub="$sub/${rest%%/*}"
        rest="${rest#*/}"
        if [ -L "$sub" ] || { [ -e "$sub" ] && [ ! -d "$sub" ]; }; then
            printf 'refused=not_scratch\n'
            say "$sub exists and is not a directory"
            exit 2
        fi
    done
    target="$SCRATCH/$rel"
    if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
        printf 'refused=not_scratch\n'
        say "$target exists and is not a regular file"
        exit 2
    fi
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" = "absent" ]; then
        printf 'refused=session_absent\n'
        say "$s does not exist"
        exit 2
    fi
    rc=0
    "$KOTO" context exists "$s" "$key" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ;;
        1) printf 'refused=key_absent\n'; say "$s holds no key $key"; exit 2 ;;
        *) say "cannot read $key from $s"; exit 4 ;;
    esac
    if [ "$sub" != "$SCRATCH" ] && ! (umask 077 && mkdir -p -- "$sub"); then
        printf 'failed=mkdir\n'
        say "could not create $sub"
        exit 1
    fi
    rm -f -- "$target"
    if ! "$KOTO" context get "$s" "$key" --to-file "$target" >/dev/null 2>&1; then
        printf 'failed=koto_error\n'
        say "could not read $key from $s"
        exit 1
    fi
    printf '%s\n' "$target"
}

cmd_put() {
    local s key file dir size
    [ "$#" -eq 3 ] || usage "put takes <session> <key> <file>"
    s="$1"; key="$2"; file="$3"
    check_session "$s"
    check_key "$key" || { printf 'refused=bad_key\n'; exit 2; }
    case "$file" in
        *..*) printf 'refused=not_scratch\n'; say "the file path must not contain '..'"; exit 2 ;;
    esac
    if [ -L "$file" ] || [ ! -f "$file" ]; then
        printf 'refused=not_scratch\n'
        say "$file is not a regular file (a symlink is refused)"
        exit 2
    fi
    dir=$(dirname -- "$file")
    scratch_dir "$dir" || { printf 'refused=not_scratch\n'; exit 2; }
    size=$(wc -c <"$file" 2>/dev/null | tr -d ' ') || size=""
    case "$size" in
        ''|*[!0-9]*) printf 'refused=not_scratch\n'; say "cannot read the size of $file"; exit 2 ;;
    esac
    if [ "$size" -ge "$MAX_BYTES" ]; then
        printf 'refused=too_large\n'
        say "$file is $size bytes, at or over the 1 MiB cap"
        exit 2
    fi
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" != "live" ]; then
        printf 'refused=session_not_live\n'
        say "$s is $SSTATE"
        exit 2
    fi
    if ! "$KOTO" context add "$s" "$key" --from-file "$SCRATCH/${file##*/}" >/dev/null 2>&1; then
        printf 'failed=koto_error\n'
        say "could not write $key into $s"
        exit 1
    fi
    printf 'put=%s\n' "$key"
}

# --- reclaimable -------------------------------------------------------------------------

cmd_reclaimable() {
    local s sk topic="" rc
    [ "$#" -eq 1 ] || usage "reclaimable takes <session>"
    s="$1"
    check_session "$s"
    for sk in $KNOWN_SKILLS; do
        case "$s" in
            "$sk"-*) topic="${s#"$sk"-}"; break ;;
        esac
    done
    if [ -z "$topic" ] || ! [[ "$topic" =~ $RE_TOPIC ]]; then
        printf 'no\n'
        exit 0
    fi
    need_tools
    session_state "$s" || { say "cannot tell the state of $s"; exit 4; }
    if [ "$SSTATE" != "finished" ]; then
        printf 'no\n'
        exit 0
    fi
    rc=0
    kget "$s" chain/parent || rc=$?
    case "$rc" in
        0) ;;
        1) printf 'yes\n'; exit 0 ;;
        *) say "cannot read chain/parent from $s"; exit 4 ;;
    esac
    # Compared, never interpolated: anything but the two names is malformed.
    if [ "$KVAL" != "scope-$topic" ] && [ "$KVAL" != "charter-$topic" ]; then
        printf 'no\n'
        exit 0
    fi
    session_state "$KVAL" || { say "cannot tell the state of the parent session"; exit 4; }
    case "$SSTATE" in
        absent|finished) printf 'yes\n' ;;
        *) printf 'no\n' ;;
    esac
    exit 0
}

# --- dispatch ------------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "no subcommand"
SUB="$1"
shift
case "$SUB" in
    name) cmd_name "$@" ;;
    open) cmd_open "$@" ;;
    status) cmd_status "$@" ;;
    has-work) cmd_has_work "$@" ;;
    close) cmd_close "$@" ;;
    dispatch) cmd_dispatch "$@" ;;
    adopt) cmd_adopt "$@" ;;
    close-children) cmd_close_children "$@" ;;
    scratch) cmd_scratch "$@" ;;
    ingest) cmd_ingest "$@" ;;
    get) cmd_get "$@" ;;
    put) cmd_put "$@" ;;
    reclaimable) cmd_reclaimable "$@" ;;
    *) usage "unknown subcommand: $SUB" ;;
esac
