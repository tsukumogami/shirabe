# record-store.sh -- sourced, never run: where the run record lives in the koto
# store, and how a koto call reaches it.
#
# The run record is a set of ordinary koto sessions: the record root
# (`execute-<topic>`) in the workspace the run opened it in, and one index
# session per PR, `pr.<owner>.<repo>.<n>`, at a shared address one per
# repository owner. This file is the only one that knows what that shared
# address is and how a read reaches another workspace; scripts/run-trail.sh
# writes through it and scripts/run-record-lookup.sh reads through it.
#
# The shared address. koto files a cloud session under a prefix derived from
# the canonical working directory it runs in, so the shared address is a
# fixed directory, /tmp/shirabe-run-record/<owner>, and every write to it is
# an ordinary koto call run from there, in a subshell. No write passes an
# address option. The directory canonicalizes to /tmp/... on Linux and to
# /private/tmp/... on macOS, so there is one shared address per operating
# system family, and a reader tries both forms. The directory is an interim:
# it ties the address to how koto canonicalizes a working directory, which is
# koto's detail rather than its contract. A named, writable workspace for the
# index is proposed to koto as tsukumogami/koto#456; when it lands this file
# switches to it and the directory goes, and nothing outside this file and its
# test changes. The directory is created before each write, since /tmp may be
# cleared between runs.
#
# SHIRABE_RUN_RECORD_TEST_ROOT is test-only: when it is set, the shared
# address's root directory is that path instead of /tmp/shirabe-run-record,
# so a suite keeps its index and plan-root sessions in a temp directory of its
# own and never touches the real one, where concurrent suites collided. It
# must be an absolute path with no `..` component and no control character;
# any other value makes every function that builds the address refuse (64).
# Nothing outside a test sets it.
#
# Reading another workspace. koto#455 proposes a read-only `--workspace <id>`
# option that koto's read verbs accept and its write verbs refuse. A read here
# probes, once per process, whether the installed koto's help for a read verb
# names the option -- never a version table. When it does, the read passes
# `--workspace=<address>` right after the verb words. When it doesn't, the
# read runs koto from the address's own directory, which reaches the same
# prefix on the host that wrote it. Either way a read writes nothing.
#
# Functions:
#   rs_valid_owner <owner>        0 when it is a GitHub owner name
#   rs_valid_repo <repo>          0 when it is a repository name (not . or ..)
#   rs_valid_workspace <path>     0 when it can be a recorded workspace
#   rs_valid_session <name>       0 when it is a koto session name
#   rs_valid_step <id>            0 when it is a step id
#   rs_lower <value>              the value lowercased, on stdout
#   rs_shared_dir <owner>         the shared address's directory, on stdout
#   rs_shared_forms <owner>       both canonical forms of it, one per line
#   rs_index_name <owner/repo> <n>
#                                 the PR's index session name, on stdout
#   rs_plan_root_name <owner/repo> <topic> <sha12>
#                                 a multi-pr plan's record root,
#                                 plan.<owner>.<repo>.<topic>.<sha12>, on
#                                 stdout; 64 when a part or the whole fails
#                                 its pattern
#   rs_plan_root_owner <name>     the owner a plan root's name encodes, on
#                                 stdout; 1 when the name is not a plan root's
#   rs_plan_root_topic <name>     the PLAN topic a plan root's name encodes,
#                                 on stdout; 1 when the name is not a plan
#                                 root's
#   rs_moved_candidates <name>    the names a root may hold after re-runs,
#                                 one per line: <name>, then <name>_r1 to
#                                 <name>_r$RS_MAX_MOVED, each in the session
#                                 pattern
#   rs_moved_name <from> <to> <name>
#                                 the name <name> has once the root <from>
#                                 moved to <to>, on stdout; 1 when it fails
#                                 the session pattern
#   rs_koto_write <dir> <koto args...>
#                                 a koto write run from <dir>, created first;
#                                 refuses (64) any --workspace argument
#   rs_has_workspace_option       0 when the installed koto's reads take
#                                 --workspace (probed once per process)
#   rs_koto_read <dir> <koto args...>
#                                 a koto read of <dir>'s workspace; 69 when
#                                 the option is absent and <dir> is not a
#                                 directory here, 68 when koto answers that
#                                 the session or the workspace is not found
#
# The value patterns. Every value the record writes, and every value a reader
# takes back, is held to one of these, defined here and nowhere else, so the
# writer and the reader can't drift apart:
#   RS_RE_OWNER       a GitHub owner name (39 characters at most)
#   RS_RE_REPO        a repository name (not . or .., 100 characters at most)
#   RS_RE_NUMBER      a PR number
#   RS_RE_WORKSPACE   a recorded workspace (no `..` component either)
#   RS_RE_SESSION     a koto session name, 200 characters at most
#   RS_RE_STEP        a step id: the task name plan-to-tasks.sh gives a step
#                     (`step-<N>`, `issue-<N>`), or a /work-on run's
#                     ARTIFACT_PREFIX; 100 characters at most
#   RS_RE_RUN_ID      a run identity (skills/execute/scripts/run-id.sh)
#   RS_RE_SESSION_ID  koto's id for a session, from its session list
#   RS_RE_TOPIC       a PLAN topic
#   RS_RE_AT          a writer's UTC timestamp
#   RS_RE_SHA         a commit id, SHA-1 or SHA-256
#   RS_RE_PLAN_ROOT   a multi-pr plan root's name: plan.<owner>.<repo>.
#                     <topic>.<sha12>. The owner has no dot and the topic
#                     and sha12 none either, so the repository is what lies
#                     between and the name decodes one way.
#
# The moved-aside names. A re-run of the same topic (`koto init
# --replace-terminal`) moves the finished root aside as `<name>_r<N>`, N the
# lowest free value from 1, and every session named `<name>.<rest>` or
# `<name>~<rest>` moves with it as `<name>_r<N>.<rest>` (or `~<rest>`); the new
# run takes `<name>`. A reader looks for a root under `<name>` and
# `<name>_r1` to `<name>_r10` (RS_MAX_MOVED), and renames a name it recorded
# under the old root by the same rule. This rule is koto's, written down once
# here so no reader keeps its own copy.
#
# "Not found" is koto's answer about an address, not a failure to read it.
# With the workspace option, the canonical form of the shared address this
# host's writers never used is a workspace koto holds nothing in, and koto is
# expected to say so. rs_koto_read returns 68 for a nonzero exit whose output
# says `workflow '<name>' not found` (or session or workspace), so a reader
# goes on to the next form; every other nonzero
# exit is passed through, with koto's output, as a read that failed.
#
# The callers check every value before it reaches these functions; a
# function here checks only what it adds (the owner it builds a path from).
#
# Requires: bash 3.2+, koto.

RS_SHARED_ROOT=${SHIRABE_RUN_RECORD_TEST_ROOT:-/tmp/shirabe-run-record}
RS_RE_OWNER='^[A-Za-z0-9](-?[A-Za-z0-9])*$'
RS_RE_REPO='^[A-Za-z0-9._-]+$'
RS_RE_NUMBER='^[1-9][0-9]{0,9}$'
RS_RE_WORKSPACE='^/[^[:cntrl:]]*$'
RS_RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$'
RS_RE_STEP='^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
RS_RE_RUN_ID='^[0-9a-f]{32}$'
RS_RE_SESSION_ID='^[A-Za-z0-9-]{1,64}$'
RS_RE_TOPIC='^[a-z0-9-]{1,100}$'
RS_RE_AT='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
RS_RE_SHA='^[0-9a-f]{40}([0-9a-f]{24})?$'
RS_RE_PLAN_ROOT='^plan\.([a-z0-9](-?[a-z0-9])*)\.([a-z0-9._-]+)\.([a-z0-9-]{1,100})\.([0-9a-f]{12})$'

rs_valid_owner() {
    [[ $1 =~ $RS_RE_OWNER ]] && [ "${#1}" -le 39 ]
}

rs_valid_repo() {
    [[ $1 =~ $RS_RE_REPO ]] || return 1
    [ "${#1}" -le 100 ] || return 1
    case "$1" in .|..) return 1 ;; esac
    return 0
}

# A workspace is the canonical directory a session was created in, kept as an
# opaque identifier: absolute, no control characters, no `..` component.
rs_valid_workspace() {
    [[ $1 =~ $RS_RE_WORKSPACE ]] || return 1
    [ "${#1}" -le 4096 ] || return 1
    case "$1/" in */../*) return 1 ;; esac
    return 0
}

rs_valid_session() {
    [[ $1 =~ $RS_RE_SESSION ]]
}

rs_valid_step() {
    [[ $1 =~ $RS_RE_STEP ]]
}

rs_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

rs_shared_dir() {
    rs_valid_owner "$1" || return 64
    rs_valid_workspace "$RS_SHARED_ROOT" || return 64
    printf '%s/%s\n' "$RS_SHARED_ROOT" "$(rs_lower "$1")"
}

# The /tmp form first, then the /private/tmp form a macOS writer's working
# directory canonicalized to.
rs_shared_forms() {
    local d
    d=$(rs_shared_dir "$1") || return 64
    printf '%s\n' "$d" "/private$d"
}

rs_index_name() {
    local owner repo
    owner=${1%%/*}
    repo=${1#*/}
    rs_valid_owner "$owner" || return 64
    rs_valid_repo "$repo" || return 64
    [[ $2 =~ $RS_RE_NUMBER ]] || return 64
    printf 'pr.%s.%s.%s\n' "$(rs_lower "$owner")" "$(rs_lower "$repo")" "$2"
}

rs_plan_root_name() {
    local owner repo name
    owner=${1%%/*}
    repo=${1#*/}
    rs_valid_owner "$owner" || return 64
    rs_valid_repo "$repo" || return 64
    [[ $2 =~ $RS_RE_TOPIC ]] || return 64
    [[ $3 =~ ^[0-9a-f]{12}$ ]] || return 64
    name="plan.$(rs_lower "$owner").$(rs_lower "$repo").$2.$3"
    rs_valid_session "$name" || return 64
    [[ $name =~ $RS_RE_PLAN_ROOT ]] || return 64
    printf '%s\n' "$name"
}

rs_plan_root_owner() {
    local owner repo
    rs_valid_session "$1" || return 1
    [[ $1 =~ $RS_RE_PLAN_ROOT ]] || return 1
    # Copied out first: the checks below match again and reset BASH_REMATCH.
    owner=${BASH_REMATCH[1]}
    repo=${BASH_REMATCH[3]}
    rs_valid_owner "$owner" || return 1
    rs_valid_repo "$repo" || return 1
    printf '%s\n' "$owner"
}

rs_plan_root_topic() {
    local topic
    rs_plan_root_owner "$1" >/dev/null || return 1
    [[ $1 =~ $RS_RE_PLAN_ROOT ]] || return 1
    topic=${BASH_REMATCH[4]}
    printf '%s\n' "$topic"
}

RS_MAX_MOVED=10

rs_moved_candidates() {
    local i=1
    rs_valid_session "$1" && printf '%s\n' "$1"
    while [ "$i" -le "$RS_MAX_MOVED" ]; do
        rs_valid_session "${1}_r$i" && printf '%s\n' "${1}_r$i"
        i=$((i + 1))
    done
    return 0
}

rs_moved_name() {
    local from=$1 to=$2 n=$3
    if [ "$from" != "$to" ]; then
        case "$n" in
            "$from") n=$to ;;
            "$from".*|"$from"~*) n="$to${n#"$from"}" ;;
        esac
    fi
    rs_valid_session "$n" || return 1
    printf '%s\n' "$n"
}

rs_koto_write() {
    local dir=$1 a
    shift
    for a in "$@"; do
        case "$a" in
            --workspace|--workspace=*)
                echo "record-store: a write never passes --workspace" >&2
                return 64
                ;;
        esac
    done
    mkdir -p -- "$dir" || return 70
    (cd -- "$dir" && koto "$@")
}

# RS_WORKSPACE_OPTION caches the probe: empty until the first read, then yes
# or no for the rest of the process. The help text is captured whole before
# it is matched, so no reader closes the pipe on koto early.
RS_WORKSPACE_OPTION=""
rs_has_workspace_option() {
    local help
    if [ -z "$RS_WORKSPACE_OPTION" ]; then
        help=$(koto context get --help </dev/null 2>&1) || help=""
        case "$help" in
            *--workspace*) RS_WORKSPACE_OPTION=yes ;;
            *) RS_WORKSPACE_OPTION=no ;;
        esac
    fi
    [ "$RS_WORKSPACE_OPTION" = yes ]
}

# rs_koto_read <dir> <verb words> <rest>: `context` and `session` take a
# second verb word, so the option goes after both; every other verb has one.
# koto's output is held in a private directory until its exit is known: a
# "not found" answer (68) prints nothing, and every other answer passes
# through byte for byte, stdout and stderr each to its own stream.
rs_koto_read() {
    local dir=$1 tmp rc
    shift
    if rs_has_workspace_option; then
        case "$1" in
            context|session) set -- "$1" "$2" "--workspace=$dir" "${@:3}" ;;
            *) set -- "$1" "--workspace=$dir" "${@:2}" ;;
        esac
    else
        [ -d "$dir" ] || return 69
    fi
    # The probe above has set RS_WORKSPACE_OPTION for the branch below.
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/record-store.XXXXXX") || {
        echo "record-store: mktemp failed" >&2
        return 70
    }
    if [ "$RS_WORKSPACE_OPTION" = yes ]; then
        koto "$@" >"$tmp/out" 2>"$tmp/err"
    else
        (cd -- "$dir" && koto "$@") >"$tmp/out" 2>"$tmp/err"
    fi
    rc=$?
    # koto names what it didn't find: `workflow '<name>' not found` for a
    # session it doesn't hold. A missing key reads "failed to read context
    # key", a plain failure, and stays one.
    if [ "$rc" -ne 0 ] && grep -qiE "(workflow|session|workspace) '[^']*' not found" "$tmp/out" "$tmp/err"; then
        rm -rf -- "$tmp"
        return 68
    fi
    cat -- "$tmp/out"
    cat -- "$tmp/err" >&2
    rm -rf -- "$tmp"
    return "$rc"
}
