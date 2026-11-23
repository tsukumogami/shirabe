#!/usr/bin/env bash
# test-change.sh -- for /work-on: hold a pass that came with an edited test or
# an observation pair until the review panels have judged each one at its
# content now, and read the record back from the session. Nothing here writes
# to a pull request, and nothing here judges a test.
#
# references/red-first.md says what the hold means for a run. The judgments
# are the panels': panel-scope.sh --record keeps them in the session's
# verdict_ledger.json, and panel-scope.sh --due-items names every item that is
# due for a panel or carries an open adverse finding. This script lists the
# unit's items and asks it. Its own ledger, the context key
# `test_change_ledger.jsonl`, is written only here, under a lock, and holds
# the header, the run's notes and relocate lines; apart from the header no
# line in it changes whether the unit counts.
#
# Usage:
#   test-change.sh init     <session> [--entry] [--shared-branch <name>]
#   test-change.sh classify <session>
#   test-change.sh note     <session> --file <path> --reason <text>
#   test-change.sh status   <session>
#   test-change.sh covered  <session> <item>...
#   test-change.sh record   <session>
#
#   init      writes the ledger's header: the author (agent:<session>),
#             impl_base, the work tree, the repository (owner/name from
#             origin, or empty) and a run nonce. Refused (exit 1) when a
#             header is already written or the ledger already holds lines,
#             and when impl_base is not where the unit started: HEAD itself,
#             the merge-base of HEAD with the remote default branch (or local
#             main), or, with a non-empty --shared-branch, the shared branch's
#             remote tip. With --entry (fix_determination's action, which
#             re-runs on every entry) an existing header is left alone and the
#             exit is 0.
#   classify  the unit's test files, one `<label>\t<path>\t<digest>` row each
#             (scripts/lib/test-classify.sh over impl_base..HEAD with the rules
#             copy review_level_choice stored): `added` (new, or only gaining
#             lines), `edited` (losing a line, deleted, binary, or a rename
#             that changed a line) or `unchanged`. For a fix with a red, a
#             reproducing test or harness file whose blob differs from the one
#             the red ran is `edited` too.
#   note      records why the run edited a test, while implementing; the
#             panels' packets carry it beside the test's hunks.
#   status    pass_counting's, pr_precheck's and ci_pass_counting's gate.
#             The items are the unit's edited tests and, when red_first.json
#             holds one, its observation pair. Exit 0 when none is held; exit
#             1 holding, one `held: <reason>` line each, then finding
#             test-change/held: no header, uncommitted changes, `<path> due
#             for <panel>` (no judgment of the panel at its content now),
#             `<path> weakens: an open finding of <panel>`, `observation due
#             for <panel>`, `observation not shown: an open finding of
#             <panel>`, and, while no panel has recorded a seat for the unit,
#             `<item> due: no panel has judged it`. Exit 3 when an item is
#             held and panel-retry-budget.sh --remaining reports no retry
#             left, so no further panel round can clear it, or when no panel
#             has recorded and koto's log shows the run already submitted
#             `counting_status: declined` once (a unit routed as docs or
#             task that went back and still reached no panel); the template
#             routes that to done_blocked. Exit 2 when the verdict record,
#             the retry record or koto's log can't be read, or --due-items
#             can't decide.
#   covered   read-only: exit 0 when no named item is held. red-first.sh
#             check-green asks it for an observation pair
#             (`observation:before`, `observation:after`), which is held with
#             the lines status prints for `observation`; a named test path is
#             held with its own lines. A named item the unit doesn't have is
#             held as not recorded.
#   record    read-only, for a person or a coordinator: the fix source, the
#             red and green (or the observations), each test file as added or
#             edited, the notes and relocations with their times, and the
#             unit's state as status reads it from the panels. Seat, accept,
#             decline, refuse and overrule lines a run wrote before the panels
#             took over are listed as legacy history; nothing counts them. It
#             works while the unit is held and after the run finished, and
#             reports the state as undecided when the run's work tree is gone.
#             Control characters are shown escaped.
#
# A moved work tree. The run's work tree is the latest relocate line's `to`,
# else the header's. Every call that reads the work tree to decide (classify,
# status and covered) first asks `koto session list` where the run's session
# is bound, once per call. When the session's execution_dir is in another
# work tree than the ledger's, that tree is the run's, whether or not the old
# one still exists: when it is the same work (its origin names the header's
# repository, when the header records one, and its HEAD has impl_base as an
# ancestor) it is followed, and when it isn't the call exits 2 naming both
# trees. A listing that fails or doesn't parse exits 2 too; nothing falls back
# to the ledger's tree then. Only when the listing gives the session no
# directory, or its directory is gone, does the older rule apply: when the
# run's work tree is gone and the current directory's is the same work, that
# one is followed; otherwise it is the gone work tree (exit 2) it always was.
# status uses a followed tree and the first time appends a relocate line
# naming both paths and the HEAD moved to, under the lock (it takes the lock
# only for that), and says so on stderr; classify and covered use it for that
# call and write nothing. record never lists or follows the current
# directory: it reads the relocate lines alone, lists each one with its HEAD,
# and reports the state as undecided while the latest work tree is gone. init
# and note don't read the work tree to decide, and don't follow it.
#
# Ledger lines (JSON, one per line). The header comes first. Then `note`
# (identity, file, reason) and `relocate` (from, to, head). Every line has ts,
# event, source (`session`) and rule (`interim`). A ledger from a run started
# before the panels took over may also hold `seat`, `accept`, `decline`,
# `refuse` and `overrule` lines; status and covered never read them, and
# record lists them as legacy history.
#
# Session names match [A-Za-z0-9._-], 1 to 128 characters, not starting with
# - or . and holding no `..`: a child of /execute is named <parent>.<task>.
# Paths are repository-relative with no `..` segment and no leading - or /.
# Reasons and paths have control characters stripped, and every line is built
# with jq.
#
# Writers (init, note, and status while it records a moved work tree) hold a
# lock file, created with bash's noclobber, named for the session in a
# per-user state directory (mode 0700, owner checked), record their pid and
# its start time in it, break it only when that process is gone, exit 75 when
# it stays held past TEST_CHANGE_LOCK_WAIT seconds (default 10), and read the
# ledger back after writing. They need at least the koto minimum
# scripts/assert-koto-floor.sh defines, which addresses a session by name from
# any directory and keeps accepting context writes on a retained session.
#
# Environment:
#   SHIRABE_STATE_DIR      where `locks/` (the directory the lock files go in)
#                          lives; default ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe
#   TEST_CHANGE_LOCK_WAIT  seconds a writer waits for the lock (tests)
#
# Exit codes:
#   0   recorded, or the gate passes
#   1   refused (a `refused:` line), or the gate holds (`held:` lines, then a
#       finding)
#   2   could not decide: no impl_base, no rules copy, no work tree, a ledger,
#       record or verdict record that doesn't parse, a --due-items or retry
#       budget that can't decide, a koto older than the floor, a session
#       listing that fails or doesn't parse, or a session bound to a work tree
#       that isn't the run's work
#   3   status only: an item is held and no further lap can clear it (the
#       panel retry budget is spent, or the run went back once and still no
#       panel has recorded)
#   64  usage
#   66  a koto context read or write failed
#   75  the lock is held by a live writer; retry
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT_SELF=$(cd "$HERE/../../.." && pwd)
RULE_IDS="test-change/held"
SCHEMA=shirabe-test-change/v1
LEDGER=test_change_ledger.jsonl
RECORD_KEY=red_first.json
KIND_KEY=fix_kind.jsonl
RULES_KEY=review_level_rules.tsv
TEXT_MAX=300

show_errlog() {
    if [ -n "${ERRLOG:-}" ] && [ -s "$ERRLOG" ]; then
        echo "test-change: the tools' last diagnostics:" >&2
        tail -n 5 "$ERRLOG" >&2
    fi
}

undecided() {
    echo "test-change: $*" >&2
    show_errlog
    exit 2
}

usage() {
    echo "test-change: $1" >&2
    cat >&2 <<'EOF'
usage: test-change.sh init     <session> [--entry] [--shared-branch <name>]
       test-change.sh classify <session>
       test-change.sh note     <session> --file <path> --reason <text>
       test-change.sh status   <session>
       test-change.sh covered  <session> <item>...
       test-change.sh record   <session>
EOF
    exit 64
}

die66() {
    echo "test-change: $1" >&2
    show_errlog
    exit 66
}

refuse() {
    echo "refused: $1"
    exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-change.XXXXXX") || { echo "test-change: could not create a temporary directory" >&2; exit 2; }
ERRLOG="$TMP/tool-stderr.log"
: > "$ERRLOG"
LOCK=""
cleanup() {
    [ -z "$LOCK" ] || rm -rf "$LOCK"
    rm -rf "$TMP"
}
trap cleanup EXIT

# shellcheck source=../../../scripts/lib/test-classify.sh
. "$PLUGIN_ROOT_SELF/scripts/lib/test-classify.sh" || undecided "cannot load scripts/lib/test-classify.sh"

valid_session() {
    [ "${#1}" -le 128 ] || return 1
    case "$1" in
        ""|-*|.*|*..*|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

valid_repo() {
    case "$1" in
        -*|/*|*/|*/*/*|*..*|*[!A-Za-z0-9_./-]*) return 1 ;;
        */*) return 0 ;;
    esac
    return 1
}

# repo_of_url <url>: the owner/name an origin URL names, or nothing.
repo_of_url() {
    local repo
    repo=$(printf '%s' "$1" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')
    valid_repo "$repo" && printf '%s\n' "$repo"
    return 0
}

# safe_path <path>: repository-relative, no `..` segment, no leading `-` or `/`.
safe_path() {
    case "$1" in
        ""|-*|/*|..|../*|*/..|*/../*) return 1 ;;
    esac
    return 0
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# clean <text>: control characters (newlines included) become spaces, capped.
clean() {
    printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c "1-$TEXT_MAX"
}

# ctx_has <session> <key>: 0 when the key is present, 1 when koto answers that
# it is absent, 2 when the read failed. koto's `context exists` answers an
# absent key with exit 1 and nothing on stdout; a refusal (a session bound to
# another workspace, say) prints its JSON on stdout and exits 2. An exit 1
# that prints anything is a failed read too, never an absent key. What koto
# prints goes to $ERRLOG, never to stdout.
ctx_has() {
    local rc=0
    koto context exists "$1" "$2" > "$TMP/exists.out" 2>>"$ERRLOG" || rc=$?
    cat "$TMP/exists.out" >> "$ERRLOG"
    case "$rc" in
        0) return 0 ;;
        1) [ -s "$TMP/exists.out" ] || return 1 ;;
    esac
    echo "koto context exists $1 $2 exited $rc" >> "$ERRLOG"
    return 2
}

# ctx_get <session> <key> <file>: the key's content into <file>, empty when the
# key is absent. Returns 1 when the read failed, with <file> empty.
ctx_get() {
    : > "$3"
    ctx_has "$1" "$2"
    case $? in
        0) ;;
        1) return 0 ;;
        *) return 1 ;;
    esac
    koto context get "$1" "$2" > "$3" 2>>"$ERRLOG" && return 0
    : > "$3"
    return 1
}

ctx_put() {
    koto context add "$1" "$2" < "$3" >/dev/null 2>>"$ERRLOG" || return 1
    koto context get "$1" "$2" > "$TMP/readback" 2>>"$ERRLOG" || return 1
    cmp -s "$3" "$TMP/readback"
}

# koto_floor: undecided unless koto is at least shirabe's minimum, the one
# scripts/assert-koto-floor.sh defines. That release addresses a session by
# name from any directory and keeps accepting context writes on a retained
# session, which the ledger relies on. KOTO_FLOOR is dropped from the
# environment, since the assertion honours it as a test override.
koto_floor() {
    env -u KOTO_FLOOR "$PLUGIN_ROOT_SELF/scripts/assert-koto-floor.sh" > "$TMP/floor.out" 2>&1 \
        || undecided "koto is below shirabe's minimum, which the ledger needs (a session addressed by name from any directory, context writes on a retained session): $(tail -n 1 "$TMP/floor.out")"
}

# -------------------------------------------------------- state directory ----

state_base() {
    printf '%s\n' "${SHIRABE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shirabe}"
}

# private_dir <dir>: created with mode 0700 and owned by this user, or undecided.
private_dir() {
    ( umask 077; mkdir -p "$1" ) 2>>"$ERRLOG" || undecided "could not create $1"
    [ -O "$1" ] || undecided "$1 is not owned by this user"
    chmod 700 "$1" 2>>"$ERRLOG" || undecided "could not make $1 private"
}

# ------------------------------------------------------------------- lock ----

proc_start() {
    ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'
}

take_lock() {
    local s="$1" base dir wait_s start opid ostart own
    base=$(state_base)
    dir="$base/locks"
    private_dir "$base"
    private_dir "$dir"
    wait_s="${TEST_CHANGE_LOCK_WAIT:-10}"
    case "$wait_s" in ""|*[!0-9]*) wait_s=10 ;; esac
    start=$(date +%s)
    while :; do
        # One open with O_EXCL, made by bash itself: not mkdir, which on
        # Ubuntu 26.04 (uutils) can report success to two racing callers.
        if (set -C && printf '%s\t%s\n' "$$" "$(proc_start "$$")" > "$dir/test-change.$s.lock") 2>/dev/null; then
            LOCK="$dir/test-change.$s.lock"
            return 0
        fi
        opid="" ostart="" own="$dir/test-change.$s.lock"
        # A lock directory an earlier version left holds its owner in `owner`.
        [ -d "$own" ] && own="$own/owner"
        if [ -f "$own" ]; then
            IFS="$(printf '\t')" read -r opid ostart < "$own"
        fi
        if [ -n "$opid" ]; then
            if ! kill -0 "$opid" 2>/dev/null || [ "$(proc_start "$opid")" != "$ostart" ]; then
                # The owner is gone (or its pid was reused): break the lock.
                rm -rf "$dir/test-change.$s.lock"
                continue
            fi
        fi
        if [ $(( $(date +%s) - start )) -ge "$wait_s" ]; then
            echo "test-change: the ledger lock for $s is held by pid ${opid:-unknown}; try again" >&2
            exit 75
        fi
        sleep 0.2
    done
}

drop_lock() {
    [ -z "$LOCK" ] || rm -rf "$LOCK"
    LOCK=""
}

# ----------------------------------------------------------------- ledger ----


# load_ledger <session>: the ledger into $TMP/ledger.
load_ledger() {
    ctx_get "$1" "$LEDGER" "$TMP/ledger" || die66 "could not read $LEDGER"
}

# load_header: 0 with the H_* values set when the ledger starts with a header.
# The work tree is the latest relocate line's `to`, else the header's.
load_header() {
    local h moved
    h=$(head -n 1 "$TMP/ledger" | jq -c 'select(type == "object" and .event == "header")' 2>>"$ERRLOG")
    [ -n "$h" ] || return 1
    H_AUTHOR=$(printf '%s' "$h" | jq -r '.author // ""')
    H_BASE=$(printf '%s' "$h" | jq -r '.impl_base // ""')
    H_WORKTREE=$(printf '%s' "$h" | jq -r '.worktree // ""')
    H_REPO=$(printf '%s' "$h" | jq -r '.repo // ""')
    [ -n "$H_AUTHOR" ] && [ -n "$H_BASE" ] && [ -n "$H_WORKTREE" ] || return 1
    moved=$(jq -Rr 'fromjson? | select(type == "object" and .event == "relocate") | .to // empty' "$TMP/ledger" 2>>"$ERRLOG" | tail -n 1)
    [ -z "$moved" ] || H_WORKTREE=$moved
    return 0
}

# append <session> <line-file>: the ledger plus one line, read back.
append() {
    cat "$TMP/ledger" "$2" > "$TMP/ledger.next"
    ctx_put "$1" "$LEDGER" "$TMP/ledger.next" || die66 "could not write $LEDGER (or it didn't read back as written)"
    cp "$TMP/ledger.next" "$TMP/ledger"
}

# same_work <top>: 0 when the work tree at <top> is clearly the run's work:
# its origin names the header's repository (when the header records one) and
# its HEAD has impl_base as an ancestor. A header records no repository when
# init's origin named no owner/name; impl_base's ancestry alone decides then,
# since there is no repository to compare.
same_work() {
    local url repo
    if [ -n "$H_REPO" ]; then
        url=$(git -C "$1" remote get-url origin 2>>"$ERRLOG") || return 1
        repo=$(repo_of_url "$url")
        [ "$repo" = "$H_REPO" ] || return 1
    fi
    git -C "$1" merge-base --is-ancestor "$H_BASE" HEAD 2>>"$ERRLOG"
}

# moved_here: prints the current directory's work tree when the run's work
# tree is gone and this one is the same work (same_work). Prints nothing
# otherwise.
moved_here() {
    local top
    [ ! -d "$H_WORKTREE" ] || return 0
    top=$(git rev-parse --show-toplevel 2>>"$ERRLOG") || return 0
    [ -n "$top" ] && [ "$top" != "$H_WORKTREE" ] || return 0
    same_work "$top" || return 0
    printf '%s\n' "$top"
}

# bound_tree <session>: sets BOUND to the top of the work tree koto has the
# session bound to (its execution_dir in `koto session list`), or to nothing
# when the listing gives the session no directory or the directory is gone.
# The listing is read once per call and reused, so the re-check under the
# lock sees the same answer. A listing that fails or doesn't parse, or a bound
# directory outside any git work tree, is undecided (exit 2): the run's tree
# is unknown, and nothing falls back to the ledger's.
BOUND="" LISTED=0
bound_tree() {
    local dir
    BOUND=""
    if [ "$LISTED" -eq 0 ]; then
        koto session list > "$TMP/listing" 2>>"$ERRLOG" \
            || undecided "koto session list failed, so the directory the run's session is bound to is unknown"
        jq -e 'type == "array"' "$TMP/listing" >/dev/null 2>>"$ERRLOG" \
            || undecided "koto session list printed something that doesn't parse, so the directory the run's session is bound to is unknown"
        LISTED=1
    fi
    dir=$(jq -r --arg s "$1" 'map(select(type == "object" and .id == $s)) | first | .execution_dir // empty' "$TMP/listing" 2>>"$ERRLOG")
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    BOUND=$(git -C "$dir" rev-parse --show-toplevel 2>>"$ERRLOG") && [ -n "$BOUND" ] \
        || undecided "the run's session is bound to [$dir], which is not in a git work tree"
}

# move_target <session>: sets MOVE_TO to the work tree the run is in when it
# isn't the ledger's (H_WORKTREE), and MOVE_WHY to `bound` or `gone`; both
# empty otherwise. The session's bound directory decides first, whether or
# not the ledger's work tree still exists: one that differs and is the same
# work is followed, one that differs and isn't is undecided (exit 2), naming
# both. With no bound directory, the gone work tree's rule (moved_here) is
# unchanged.
MOVE_TO="" MOVE_WHY=""
move_target() {
    MOVE_TO="" MOVE_WHY=""
    bound_tree "$1"
    if [ -n "$BOUND" ]; then
        [ "$BOUND" != "$H_WORKTREE" ] || return 0
        same_work "$BOUND" \
            || undecided "the run's session is bound to [$BOUND], which is not the same work as the ledger's work tree [$H_WORKTREE]: another repository, or impl_base is not in its history"
        MOVE_TO=$BOUND MOVE_WHY=bound
        return 0
    fi
    MOVE_TO=$(moved_here)
    [ -z "$MOVE_TO" ] || MOVE_WHY=gone
}

# follow_move <session> write|read: when the run is in another work tree than
# the ledger's (move_target), use it. `write` records the move as one relocate
# line, with the HEAD it moved to, under the lock (taking it when the caller
# doesn't hold it, and reading the ledger again once it does) and names it on
# stderr; `read` uses it for this call only. Otherwise nothing changes, and
# compute_items reports a gone work tree as before. A refuse, undecided or
# die66 while it holds the lock exits through the EXIT trap, which removes
# the lock.
follow_move() {
    local s="$1" mode="$2" from head locked_here=0
    move_target "$s"
    [ -n "$MOVE_TO" ] || return 0
    if [ "$mode" = read ]; then
        H_WORKTREE=$MOVE_TO
        return 0
    fi
    if [ -z "$LOCK" ]; then
        take_lock "$s"
        locked_here=1
        load_ledger "$s"
        load_header || refuse "the ledger has no header; test-change.sh init writes it at fix_determination"
        move_target "$s"
        if [ -z "$MOVE_TO" ]; then
            drop_lock
            return 0
        fi
    fi
    from=$H_WORKTREE
    head=$(git -C "$MOVE_TO" rev-parse -q --verify "HEAD^{commit}" 2>>"$ERRLOG") \
        || undecided "HEAD names no commit in $MOVE_TO"
    jq -nc --arg ts "$(now)" --arg from "$from" --arg to "$MOVE_TO" --arg head "$head" '
        {ts: $ts, event: "relocate", from: $from, to: $to, head: $head, source: "session", rule: "interim"}' > "$TMP/relocate.line"
    append "$s" "$TMP/relocate.line"
    H_WORKTREE=$MOVE_TO
    if [ "$MOVE_WHY" = gone ]; then
        echo "test-change: the run's work tree [$from] is gone; following it to [$MOVE_TO], the same repository with impl_base in its history (recorded)" >&2
    else
        echo "test-change: the run's session is bound to [$MOVE_TO], not the ledger's work tree [$from]; following it there, the same repository with impl_base in its history (recorded)" >&2
    fi
    [ "$locked_here" -eq 0 ] || drop_lock
}

G() { git -C "$H_WORKTREE" "$@"; }

# ------------------------------------------------------------------ items ----

# compute_items <session>: $TMP/classified (the test rows) and $TMP/items
# (<item>\t<digest> for every edited test and recorded observation).
compute_items() {
    local s="$1" head tab label path digest
    tab=$(printf '\t')
    [ -d "$H_WORKTREE" ] || undecided "the run's work tree [$H_WORKTREE] is gone"
    head=$(G rev-parse -q --verify "HEAD^{commit}" 2>>"$ERRLOG") || undecided "HEAD names no commit in $H_WORKTREE"
    ctx_get "$s" "$RULES_KEY" "$TMP/rules" || die66 "could not read $RULES_KEY"
    [ -s "$TMP/rules" ] || undecided "no rules copy ($RULES_KEY) is stored; review_level_choice stores it"

    # The test rows, with a fix's reproducing tests and harness files changed
    # since the red ran labelled edited too (test_classify_unit).
    ctx_get "$s" "$RECORD_KEY" "$TMP/record" || die66 "could not read $RECORD_KEY"
    if [ -s "$TMP/record" ]; then
        jq -e 'type == "object"' "$TMP/record" >/dev/null 2>>"$ERRLOG" || undecided "$RECORD_KEY does not parse"
    fi
    ( cd "$H_WORKTREE" && test_classify_unit "$H_BASE" "$head" "$TMP/rules" "$TMP/record" ) > "$TMP/classified" 2>"$TMP/classify.err" \
        || undecided "could not classify the unit's test files: $(head -c 300 "$TMP/classify.err")"

    : > "$TMP/items"
    while IFS="$tab" read -r label path digest; do
        [ "$label" = edited ] || continue
        printf '%s\t%s\n' "$(clean "$path")" "$digest" >> "$TMP/items"
    done < "$TMP/classified"
    if [ -s "$TMP/record" ]; then
        jq -r '(.observations // {}) | to_entries[] | select(.value.digest != null) | "observation:\(.key)\t\(.value.digest)"' \
            "$TMP/record" >> "$TMP/items" 2>>"$ERRLOG" || undecided "could not read the observations from $RECORD_KEY"
    fi
}

# uncommitted: prints a reason when the work tree has changes to tracked files
# or untracked files under a test-class path, which a count would miss.
uncommitted() {
    local globs f
    if ! G diff --quiet HEAD -- 2>>"$ERRLOG"; then
        echo "uncommitted changes to tracked files; commit them so they are classified"
        return 0
    fi
    globs=$(awk -F '\t' '$1 == "class" && $2 == "test" && $3 != "" { print $3 }' "$TMP/rules")
    G ls-files --others --exclude-standard -z 2>>"$ERRLOG" | tr '\0' '\n' > "$TMP/untracked"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if _tc_is_test "$f" "$globs"; then
            echo "uncommitted changes: the untracked test file $(clean "$f")"
            return 0
        fi
    done < "$TMP/untracked"
}

# escaped <file>: control characters other than newline shown as ^X, so a
# crafted path or line can't rewrite what the terminal shows.
escaped() { LC_ALL=C cat -v "$1"; }

# ------------------------------------------------------------------- init ----

cmd_init() {
    [ $# -ge 1 ] || usage "init takes <session>"
    local s="$1" entry=0 shared=""
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --entry) entry=1; shift ;;
            --shared-branch) [ $# -ge 2 ] || usage "--shared-branch needs a value"; shared="$2"; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    case "$shared" in -*|*..*|*[!A-Za-z0-9._/-]*) usage "--shared-branch [$shared] is not a branch name" ;; esac
    koto_floor
    take_lock "$s"
    load_ledger "$s"
    if load_header; then
        if [ "$entry" -eq 1 ]; then
            echo "unchanged: the ledger's header is already written (author $H_AUTHOR, base $H_BASE)"
            exit 0
        fi
        refuse "the ledger's header is already written; init runs once per run"
    fi
    [ ! -s "$TMP/ledger" ] || refuse "$LEDGER already holds lines but no header; a header can only be the first line"

    local base head top
    ctx_get "$s" impl_base "$TMP/base" || die66 "could not read impl_base"
    base=$(tr -d '[:space:]' < "$TMP/base")
    [ -n "$base" ] || undecided "no impl_base is recorded; analysis records it"
    git cat-file -e "$base^{commit}" 2>>"$ERRLOG" || undecided "impl_base [$base] names no commit"
    base=$(git rev-parse "$base^{commit}")
    head=$(git rev-parse -q --verify "HEAD^{commit}") || undecided "HEAD names no commit"
    top=$(git rev-parse --show-toplevel 2>>"$ERRLOG") || undecided "not inside a git work tree"
    ctx_get "$s" "$RULES_KEY" "$TMP/rules" || die66 "could not read $RULES_KEY"
    [ -s "$TMP/rules" ] || undecided "no rules copy ($RULES_KEY) is stored; review_level_choice stores it"

    # Where the unit started: impl_base must be one of these, so neither a
    # later nor an older base narrows the test class. HEAD counts because
    # this runs at fix_determination, before implementation: analysis
    # recorded impl_base as HEAD on a shared branch or in a fix round, so the
    # two still agree unless the base was rewritten by hand. Off a shared
    # branch analysis recorded the merge-base with the default branch, which
    # is a candidate here too; with the shared branch's remote tip it also
    # covers a commit made between the two states.
    git merge-base --is-ancestor "$base" "$head" 2>>"$ERRLOG" \
        || refuse "impl_base $base is not an ancestor of HEAD; it is not where this unit started"
    local cands="$head" ref mb
    if [ -n "$shared" ]; then
        ref=$(git rev-parse -q --verify "refs/remotes/origin/$shared^{commit}" 2>>"$ERRLOG") && cands="$cands $ref"
    else
        ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>>"$ERRLOG")
        [ -n "$ref" ] || { git rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>>"$ERRLOG" && ref=origin/main; }
        if [ -n "$ref" ] && mb=$(git merge-base HEAD "$ref" 2>>"$ERRLOG"); then cands="$cands $mb"; fi
        if mb=$(git merge-base HEAD refs/heads/main 2>>"$ERRLOG"); then cands="$cands $mb"; fi
    fi
    case " $cands " in
        *" $base "*) ;;
        *) refuse "impl_base $base is neither HEAD, the merge-base with the default branch, nor the shared branch's remote tip; it is not where this unit started" ;;
    esac


    local url repo=""
    url=$(git remote get-url origin 2>>"$ERRLOG") || url=""
    [ -z "$url" ] || repo=$(repo_of_url "$url")
    local nonce
    nonce=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    jq -nc --arg ts "$(now)" --arg schema "$SCHEMA" --arg author "agent:$s" --arg session "$s" \
        --arg base "$base" --arg wt "$top" --arg repo "$repo" --arg nonce "$nonce" \
        --arg shared "$shared" '
        {ts: $ts, event: "header", schema: $schema, author: $author, session: $session,
         impl_base: $base, worktree: $wt, repo: $repo, shared_branch: $shared, nonce: $nonce,
         source: "session", rule: "interim"}' > "$TMP/line"
    append "$s" "$TMP/line"
    echo "recorded: header (author agent:$s, base $base)"
    exit 0
}

# --------------------------------------------------------------- classify ----

cmd_classify() {
    [ $# -eq 1 ] || usage "classify takes <session>"
    local s="$1"
    valid_session "$s" || usage "bad session name [$s]"
    load_ledger "$s"
    load_header || refuse "the ledger has no header; test-change.sh init writes it at fix_determination"
    follow_move "$s" read
    compute_items "$s"
    cat "$TMP/classified"
    exit 0
}

# ------------------------------------------------------------------- note ----

cmd_note() {
    [ $# -ge 1 ] || usage "note takes <session>"
    local s="$1" file="" reason="" has_reason=0
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --file) [ $# -ge 2 ] || usage "--file needs a path"; file="$2"; shift 2 ;;
            --reason) [ $# -ge 2 ] || usage "--reason needs a value"; reason="$2"; has_reason=1; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    safe_path "$file" || usage "--file [$file] is not a repository-relative path"
    [ "$has_reason" -eq 1 ] || usage "note needs --reason"
    reason=$(clean "$reason")
    [ -n "$(printf '%s' "$reason" | tr -d ' ')" ] || usage "--reason is empty"
    koto_floor
    take_lock "$s"
    load_ledger "$s"
    load_header || refuse "the ledger has no header; test-change.sh init writes it at fix_determination"
    jq -nc --arg ts "$(now)" --arg id "$H_AUTHOR" --arg file "$(clean "$file")" --arg reason "$reason" '
        {ts: $ts, event: "note", identity: $id, file: $file, reason: $reason, source: "session", rule: "interim"}' > "$TMP/line"
    append "$s" "$TMP/line"
    echo "recorded: note on $file"
    exit 0
}

# ----------------------------------------------------------------- judged ----

# judge_items <session>: what holds the unit's items ($TMP/items: edited tests,
# and `observation:before` / `observation:after`), read from the panels'
# record, into $TMP/item_held as `<key>\t<reason>` lines, where <key> is the
# test's path or `observation`. Once a review panel has recorded a seat for
# the unit (verdict_ledger.json holds a seat entry), panel-scope.sh
# --due-items names each item due for a panel (no judgment of the panel at its
# content now) or carrying an open adverse finding. Before any panel has
# recorded, every item is due: no panel has judged it. Undecided when the
# verdict record can't be read or --due-items can't decide.
judge_items() {
    local s="$1" rc tab path why panel digest
    tab=$(printf '\t')
    : > "$TMP/item_held"
    [ -s "$TMP/items" ] || return 0
    ctx_get "$s" verdict_ledger.json "$TMP/verdicts" || undecided "could not read verdict_ledger.json"
    if [ -s "$TMP/verdicts" ]; then
        jq -e 'type == "object"' "$TMP/verdicts" >/dev/null 2>>"$ERRLOG" || undecided "verdict_ledger.json does not parse"
    fi
    if [ ! -s "$TMP/verdicts" ] || ! jq -e '((.seats // {}) | length) > 0' "$TMP/verdicts" >/dev/null 2>>"$ERRLOG"; then
        # No panel has judged anything yet: every item waits for one.
        while IFS="$tab" read -r path digest; do
            case "$path" in
                observation:*) path=observation ;;
            esac
            printf '%s\t%s due: no panel has judged it\n' "$path" "$path"
        done < "$TMP/items" | LC_ALL=C sort -u > "$TMP/item_held"
        NO_PANEL=1
        return 0
    fi
    rc=0
    ( cd "$H_WORKTREE" && "$PLUGIN_ROOT_SELF/skills/work-on/scripts/panel-scope.sh" --due-items "$s" ) \
        > "$TMP/due" 2>>"$ERRLOG" || rc=$?
    case "$rc" in
        0|1) ;;
        *) undecided "panel-scope.sh --due-items could not read the panels' record (exit $rc)" ;;
    esac
    [ "$rc" = 0 ] || [ -s "$TMP/due" ] || undecided "panel-scope.sh --due-items held with nothing named"
    while IFS="$tab" read -r path why panel; do
        [ -n "$path" ] || continue
        path=$(clean "$path")
        case "$why" in
            due) printf '%s\t%s due for %s\n' "$path" "$path" "$panel" ;;
            weakens) printf '%s\t%s weakens: an open finding of %s\n' "$path" "$path" "$panel" ;;
            "not shown") printf '%s\t%s not shown: an open finding of %s\n' "$path" "$path" "$panel" ;;
            *) printf '%s\t%s %s for %s\n' "$path" "$path" "$(clean "$why")" "$panel" ;;
        esac
    done < "$TMP/due" > "$TMP/item_held"
}

NO_PANEL=""

# went_back_unjudged <session>: 0 when the run has already submitted
# `counting_status: declined` at pass_counting or ci_pass_counting while no
# panel had recorded. A unit routed as docs or task that edits a test reaches
# no panel, and going back once is its chance to route as code; a second hold
# with still no panel on record means it didn't, and no lap on that route can
# clear the items, so status ends the run (exit 3) rather than loop. The
# count comes from koto's own log of the session (`koto session dir`); a log
# that isn't there counts none, and one that can't be read is undecided.
went_back_unjudged() {
    local dir log n
    dir=$(koto session dir "$1" 2>>"$ERRLOG") || undecided "koto session dir $1 failed, so the run's earlier counting laps can't be read"
    log="$dir/koto-$1.state.jsonl"
    [ -f "$log" ] || return 1
    # A lap counts once it has left: a `declined` submission at a counting
    # state followed by the transition out of that state. The submission
    # this gate is being evaluated for has no transition yet, so it never
    # counts against itself.
    n=$(jq -Rn 'reduce (inputs | fromjson? | select(type == "object")) as $e ({pending: {}, n: 0};
            if $e.type == "evidence_submitted"
               and (($e.payload.state // "") == "pass_counting" or ($e.payload.state // "") == "ci_pass_counting")
            then .pending[$e.payload.state] = (($e.payload.fields.counting_status // "") == "declined")
            elif $e.type == "transitioned" and (.pending[$e.payload.from // ""] // false)
            then .n += 1 | .pending[$e.payload.from] = false
            else . end) | .n' "$log" 2>>"$ERRLOG") \
        || undecided "koto's log of $1 could not be read"
    [ "${n:-0}" -ge 1 ]
}

# budget_spent <session>: 0 when panel-retry-budget.sh --remaining reports no
# retry left, 1 when one is. Undecided when it can't answer.
budget_spent() {
    local out rc=0 left
    out=$("$HERE/panel-retry-budget.sh" --remaining "$1" 2>>"$ERRLOG") || rc=$?
    [ "$rc" = 0 ] || undecided "panel-retry-budget.sh --remaining could not read the retry record (exit $rc)"
    left=$(sed -n 's/^remaining=\([0-9][0-9]*\) .*/\1/p' <<< "$out")
    left=${left%%$'\n'*}
    [ -n "$left" ] || undecided "panel-retry-budget.sh --remaining printed no count: [$(clean "$out")]"
    [ "$left" -eq 0 ]
}

# ----------------------------------------------------------------- status ----

cmd_status() {
    [ $# -eq 1 ] || usage "status takes <session>"
    local s="$1"
    valid_session "$s" || usage "bad session name [$s]"
    # shellcheck source=../../../scripts/lib/rule-findings.sh
    . "$PLUGIN_ROOT_SELF/scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
    rf_require test-change/held
    load_ledger "$s"
    : > "$TMP/held"
    : > "$TMP/items"
    : > "$TMP/item_held"
    if ! load_header; then
        echo "no header: the ledger has no header line, so nothing it holds can count (test-change.sh init writes it at fix_determination)" > "$TMP/held"
    else
        follow_move "$s" write
        compute_items "$s"
        uncommitted >> "$TMP/held"
        judge_items "$s"
        cut -f 2- "$TMP/item_held" >> "$TMP/held"
    fi
    if [ ! -s "$TMP/held" ]; then
        if [ -s "$TMP/items" ]; then
            echo "counted: the panels judged every edited test and the observation pair at their content now"
        else
            echo "counted: no edited test or observation needs a panel's judgment"
        fi
        exit 0
    fi
    local spent=0
    if [ -s "$TMP/item_held" ]; then
        if budget_spent "$s"; then
            spent=1
            echo "budget spent: panel-retry-budget.sh --remaining reports no retry left, so no further panel round can clear these items" >> "$TMP/held"
        elif [ -n "$NO_PANEL" ] && went_back_unjudged "$s"; then
            spent=1
            echo "no panel reached: the run already went back once with these items held and still no panel has recorded, so its route reaches no panel that can clear them" >> "$TMP/held"
        fi
    fi
    sed 's/^/held: /' "$TMP/held"
    rf_finding test-change/held "$(paste -sd ';' "$TMP/held" | sed 's/;/; /g')"
    if [ "$spent" -eq 1 ]; then
        rf_dispute_hint
        rf_deliver
        exit 3
    fi
    if [ "$RF_COUNTED" -eq 1 ]; then
        rf_dispute_hint
        rf_deliver
        exit 1
    fi
    rf_deliver
    exit 0
}

# ---------------------------------------------------------------- covered ----

cmd_covered() {
    [ $# -ge 2 ] || usage "covered takes <session> <item>..."
    local s="$1" item digest key tab
    tab=$(printf '\t')
    shift
    valid_session "$s" || usage "bad session name [$s]"
    load_ledger "$s"
    load_header || { echo "held: no header"; exit 1; }
    follow_move "$s" read
    compute_items "$s"
    : > "$TMP/keys"
    for item in "$@"; do
        digest=$(awk -F '\t' -v p="$item" '$1 == p { print $2; exit }' "$TMP/items")
        [ -n "$digest" ] || { echo "held: $item is not recorded"; exit 1; }
        case "$item" in
            observation:*) key=observation ;;
            *) key=$(clean "$item") ;;
        esac
        printf '%s\n' "$key" >> "$TMP/keys"
    done
    judge_items "$s"
    : > "$TMP/held"
    while IFS="$tab" read -r key item; do
        grep -Fxq -- "$key" "$TMP/keys" && printf '%s\n' "$item" >> "$TMP/held"
    done < "$TMP/item_held"
    if [ -s "$TMP/held" ]; then
        sed 's/^/held: /' "$TMP/held"
        exit 1
    fi
    echo "covered: $*"
    exit 0
}

# ----------------------------------------------------------------- record ----

# unit_view <session>: what record shows about the unit now, from the panels'
# record as status reads it. Sets VIEW_STATE (counted, held or undecided) and
# VIEW_REASONS, and leaves $TMP/classified, $TMP/items and $TMP/record.
# Committed state only: the work tree's uncommitted changes are status's
# concern.
VIEW_STATE="" VIEW_REASONS=""
unit_view() {
    local s="$1"
    : > "$TMP/classified"
    : > "$TMP/items"
    ctx_get "$s" "$RECORD_KEY" "$TMP/record" || die66 "could not read $RECORD_KEY"
    if [ ! -d "$H_WORKTREE" ] || ! G rev-parse -q --verify "HEAD^{commit}" >/dev/null 2>&1; then
        VIEW_STATE=undecided
        VIEW_REASONS="the run's work tree is gone, so its test files can't be classified now"
        return 0
    fi
    compute_items "$s"
    judge_items "$s"
    if [ -s "$TMP/item_held" ]; then
        VIEW_STATE=held
        VIEW_REASONS=$(cut -f 2- "$TMP/item_held" | paste -sd ';' - | sed 's/;/; /g')
    else
        VIEW_STATE=counted
        VIEW_REASONS=""
    fi
}

# kind_of <session>: KIND_LINE, the unit's kind and the source behind it.
KIND_LINE=""
kind_of() {
    ctx_get "$1" "$KIND_KEY" "$TMP/kind" || die66 "could not read $KIND_KEY"
    local fixsrc lastk
    fixsrc=$(jq -Rr 'fromjson? | select(type == "object" and (.event == "determine" or .event == "declare") and .kind == "fix") | .source // ""' "$TMP/kind" | sed -n 1p)
    lastk=$(jq -Rr 'fromjson? | select(type == "object" and (.event == "determine" or .event == "declare")) | .kind // ""' "$TMP/kind" | tail -n 1)
    if [ -n "$fixsrc" ]; then
        KIND_LINE="fix (source $fixsrc)"
    elif [ -n "$lastk" ]; then
        KIND_LINE="$lastk (not a fix)"
    else
        KIND_LINE="not determined"
    fi
}

# history_rows: one tab-separated row per ledger event for record:
# ts, event, identity, kind, authority, items, rule, reason, id, target.
# Seat, accept, decline, refuse and overrule lines are a run's from before the
# panels took over; record lists them as legacy history, and nothing counts
# them.
# A relocate line carries its from path as items, its to path as target and
# the HEAD it moved to as id (`-` on a line written before relocate recorded
# one).
history_rows() {
    jq -Rr 'fromjson? | select(type == "object" and .event != "header")
        | [(.ts // ""), (.event // ""), (.identity // ""), (.kind // ""), (.authority // ""),
           (if .event == "note" then (.file // "") elif .event == "relocate" then (.from // "")
            elif .event == "seat" then ((.cut // []) | map(tostring) | join(","))
            else ([(.files // [])[] | select(type == "object") | .path] | join(",")) end),
           (if .event == "refuse" then "\(.action // "") refused, rule \(.rule_id // "")" else (.rule // "") end),
           (.reason // ""), (if .event == "relocate" then (.head // "") else (.id // "") end),
           (if .event == "relocate" then (.to // "")
            elif .event == "accept" or .event == "decline" then ((.read_whole // []) | map(tostring) | join(","))
            else (.target // "") end)]
        | map(tostring | gsub("[\t\n\r]"; " ") | if . == "" then "-" else . end) | join("\t")' "$TMP/ledger"
}

cmd_record() {
    [ $# -eq 1 ] || usage "record takes <session>"
    local s="$1" tab
    tab=$(printf '\t')
    valid_session "$s" || usage "bad session name [$s]"
    load_ledger "$s"
    load_header || refuse "the ledger has no header; test-change.sh init writes it at fix_determination"
    kind_of "$s"
    unit_view "$s"
    {
        echo "test-change record for $s (the panels judge; identities are recorded claims)"
        echo "author: $H_AUTHOR   base: $H_BASE   repository: ${H_REPO:-unknown}"
        echo "unit: $KIND_LINE"
        if [ -s "$TMP/record" ] && jq -e '.red != null' "$TMP/record" >/dev/null 2>>"$ERRLOG"; then
            jq -r '.red | "red: \(.command | join(" ")) on base \(.base) exited \(.exit) at \(.ran_at)\n  reproducing tests: \([(.tests // [])[] | "\(.path) (\(.blob))"] | join(", "))\n  marker: \(.marker)\n  report passage (\(.report_source // "report")): \(.passage)\n  output around the marker:\n\(.marker_context | split("\n") | map("    " + .) | join("\n"))"' "$TMP/record"
        else
            echo "red: none recorded"
        fi
        if [ -s "$TMP/record" ] && jq -e '.green != null' "$TMP/record" >/dev/null 2>>"$ERRLOG"; then
            jq -r '.green | "green: \(.command | join(" ")) at \(.head) exited \(.exit) at \(.ran_at)"' "$TMP/record"
        else
            echo "green: none recorded"
        fi
        if [ -s "$TMP/record" ] && jq -e '(.observations // {}) | length > 0' "$TMP/record" >/dev/null 2>>"$ERRLOG"; then
            jq -r '(.observations // {}) | to_entries[] | "observation \(.key) (digest \(.value.digest), at \(.value.recorded_at)):\n\(.value.text // "" | split("\n") | map("    " + .) | join("\n"))"' "$TMP/record"
        fi
        echo "test files:"
        if [ -s "$TMP/classified" ]; then
            awk -F '\t' '{ printf "  %s %s (%s)\n", $1, $2, $3 }' "$TMP/classified"
        elif [ "$VIEW_STATE" = undecided ]; then
            echo "  (not classified: the work tree is gone)"
        else
            echo "  (none)"
        fi
        echo "history:"
        history_rows > "$TMP/hist"
        if [ -s "$TMP/hist" ]; then
            local ts ev who kind auth items rule reason id target
            while IFS="$tab" read -r ts ev who kind auth items rule reason id target; do
                case "$ev" in
                    seat)
                        if [ "$items" = - ]; then
                            printf '  %s legacy, ignored: seat %s minted\n' "$ts" "$who"
                        else
                            printf '  %s legacy, ignored: seat %s minted, its brief cut %s\n' "$ts" "$who" "$items"
                        fi ;;
                    relocate)
                        if [ "$id" = - ]; then
                            printf '  %s relocate: the work tree [%s] moved to [%s]\n' "$ts" "$items" "$target"
                        else
                            printf '  %s relocate: the work tree [%s] moved to [%s] at %s\n' "$ts" "$items" "$target" "$id"
                        fi ;;
                    note) printf '  %s note by %s on %s: %s\n' "$ts" "$who" "$items" "$reason" ;;
                    overrule) printf '  %s legacy, ignored: %s %s by %s (%s at %s) of %s [%s]: %s\n' "$ts" "$ev" "$id" "$who" "$kind" "$auth" "$target" "$items" "$reason" ;;
                    refuse) printf '  %s legacy, ignored: refuse: %s by %s (%s at %s) of %s: %s\n' "$ts" "$rule" "$who" "$kind" "$auth" "$items" "$reason" ;;
                    accept|decline)
                        printf '  %s legacy, ignored: %s %s by %s (%s at %s) of %s: %s' "$ts" "$ev" "$id" "$who" "$kind" "$auth" "$items" "$reason"
                        [ "$target" = - ] || printf ' (read whole: %s)' "$target"
                        echo ;;
                    *) printf '  %s %s by %s: %s\n' "$ts" "$ev" "$who" "$reason" ;;
                esac
            done < "$TMP/hist"
        else
            echo "  (nothing recorded)"
        fi
        if [ -n "$VIEW_REASONS" ]; then
            echo "state: $VIEW_STATE: $VIEW_REASONS"
        else
            echo "state: $VIEW_STATE"
        fi
    } > "$TMP/record.out"
    escaped "$TMP/record.out"
    exit 0
}

command -v jq >/dev/null || undecided "jq is not on PATH"
command -v git >/dev/null || undecided "git is not on PATH"
[ $# -ge 1 ] || usage "no subcommand"
sub="$1"
shift
case "$sub" in
    init)     cmd_init "$@" ;;
    classify) cmd_classify "$@" ;;
    note)     cmd_note "$@" ;;
    status)   cmd_status "$@" ;;
    covered)  cmd_covered "$@" ;;
    record)   cmd_record "$@" ;;
    *) usage "unknown subcommand [$sub]" ;;
esac
