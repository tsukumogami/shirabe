#!/usr/bin/env bash
# archive-common.sh -- what the teardown pass, the capture after a removal and
# the cost capture share: the archive's collection, the removals directory and
# the dispatch request.
#
# Sourced, never run. Every function returns a status and leaves the reason
# for a failure in AC_WHY; none exits and none prints what a caller reads, so
# each caller maps a failure its own way: teardown-pass.sh to `refused`,
# unit-removed.sh's sweep to a record it keeps. The caller sets umask 077
# before it collects. bash 3.2.
#
# Collection, into an archive directory <arch>, with the caller's scratch
# directory <s> holding the lists below. The caller empties <s>/copies once
# per archive before the first copy (ac_copy_file only appends), and sources
# dispatch-common.sh first or lets this file do it (DC_RE_REQ and DC_RE_LEG
# come from there):
#   ac_copy_file <arch> <s> <src> <rel>
#       One file into <arch>/<rel>, listed in <s>/copies (`<rel>\t<src>`)
#       for ac_manifest's check.
#   ac_copy_tree <arch> <s> <src dir> <rel dir>
#       Every regular file under <src dir>, found with `find -type f`.
#   ac_projects <arch> <s> <claude home> <instance path>
#       The Claude Code project directories of the instance, by the rule
#       teardown-pass.sh's header gives (the directory named for the instance
#       path always, a `-`-suffixed sibling only when its .jsonl lines' cwd
#       values are all at or under the instance, a directory that is itself a
#       link never, no link followed inside one), each copied whole into
#       claude-projects/<name>/. Writes <s>/taken (one name per line),
#       <s>/skipped (`<name>\t<reason>`) and <s>/links (one archive path per
#       line) for the README; AC_PPROJ is the physical projects directory,
#       empty when there is none.
#   ac_koto_find <s> <sessions dir> <root>...
#       Every koto session directory whose state log's header carries an
#       execution_dir at or under one of the roots, one per line in
#       <s>/koto.dirs. Never fails.
#   ac_koto_copy <arch> <s>
#       Each directory ac_koto_find listed, into koto/<name>/; AC_NK the count.
#   ac_manifest <arch> <s>
#       Each copy in <s>/copies checked against its source's hash, then
#       MANIFEST (`<sha256> <bytes> <path>` per file) and MANIFEST.sha256
#       (the MANIFEST's own digest, `<sha256>  MANIFEST`).
#   ac_readme <arch> <s> <head file> [<trees file>]
#       README.md: the head file as the caller wrote it, then the project
#       directories taken and skipped, the links skipped, the build trees
#       left out of job/tmp/ when a non-empty <trees file> lists them
#       (teardown-pass.sh's SKIPPED source), and what each archive file is.
#
# The removals directory, R = ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals:
#   ac_dir_private <dir>
#       0 when <dir> is a directory, not a symbolic link, owned by the user
#       and mode 0700 (read from `ls -ld`, since stat isn't on the suites'
#       PATH).
#   ac_removals_dir [--create]
#       AC_R is R; 0 when ac_dir_private passes on it. With --create a
#       missing R is made first, and set to mode 0700 whatever the umask.
#   ac_removal_for_path <instance path>
#       AC_REMOVAL_ID is the dispatch id of the removal record (R/<id>.json,
#       schema unit-removal/1, the id in the reap-key shape) whose
#       instance_path is the given path; the latest removed_at when several
#       are. 1 when R or such a record is missing.
#   ac_lock <lock dir> <max age secs> <wait secs>, ac_unlock <lock dir>
#       A lock that is a directory made with mkdir and holding `owner`
#       (`<pid> <epoch secs>`): waited for while a live holder younger than
#       <max age> keeps it, taken over from a holder that is gone or older;
#       released only by the process that holds it. The capture's list and
#       post run under R/.post-lock.
#
# The dispatch request:
#   ac_dispatch_request <session dir>...
#       Of the requests the sessions' request-leg.toml files name, the
#       earliest by created_at whose requested_by is a coordinator run
#       (^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$), read from
#       KOTO_REQUESTS (default $HOME/.koto/requests)/<id>/request.jsonl's
#       header. Sets AC_REQ (its id), AC_LEG (the leg the first session
#       naming it is bound to), AC_BY (requested_by) and AC_COR
#       (coordinator_of_record, unchecked: the caller matches it before any
#       use). A request id or leg outside koto's grammar is never read.

AC_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -z "${DC_HERE:-}" ]; then
    # shellcheck source=dispatch-common.sh
    . "$AC_HERE/dispatch-common.sh"
fi
AC_WHY=""
# niwa's reap key with a leading alphanumeric, so it never reads as an option.
AC_RE_REAP='^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
# A Claude Code session id, as the handoff and the capture match it.
# shellcheck disable=SC2034 # read by the scripts that source this
AC_RE_SID='^[0-9a-f][0-9a-f-]{7,63}$'
# A coordinator run's session name: coordinate-<scope slug>-<UTC stamp>.
AC_RE_COORD='^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$'

ac_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# ---------------------------------------------------------------------------
# Collection.

ac_copy_file() {
    mkdir -p "$1/$(dirname "$4")" && cp -p "$3" "$1/$4" || { AC_WHY="cannot copy $3"; return 1; }
    printf '%s\t%s\n' "$4" "$3" >>"$2/copies"
}

ac_copy_tree() {
    local f
    (cd "$3" && find . -type f) >"$2/tree" 2>/dev/null || { AC_WHY="cannot list $3"; return 1; }
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        ac_copy_file "$1" "$2" "$3/${f#./}" "$4/${f#./}" || return 1
    done <"$2/tree"
}

# ac_cwd_inside <s> <physical dir> <instance path>: 0 when at least one line
# of a .jsonl file in the directory carries a cwd at or under the instance
# path and none carries one outside it; 1 when not; 2 when it can't be read.
ac_cwd_inside() {
    local f c inside=1
    (cd -P -- "$2" && find . -type f -name '*.jsonl') >"$1/jl" 2>"$1/find.err" || return 2
    : >"$1/cwds"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        jq -R -r 'fromjson? | objects | .cwd | strings' "$2/${f#./}" >>"$1/cwds" 2>"$1/jq.err" || return 2
    done <"$1/jl"
    while IFS= read -r c; do
        case "$c" in
            "$3" | "$3"/*) inside=0 ;;
            *) return 1 ;;
        esac
    done <"$1/cwds"
    return "$inside"
}

# ac_copy_project <arch> <s> <physical dir> <name>: every regular file in it,
# no link followed; the links it holds are listed for the README.
ac_copy_project() {
    local f
    (cd -P -- "$3" && [ "$(pwd -P)" = "$3" ] && find . -type f) >"$2/tree" 2>"$2/find.err" \
        || { AC_WHY="cannot list the project directory $4"; return 1; }
    (cd -P -- "$3" && find . -type l) >"$2/tree.links" 2>"$2/find.err" \
        || { AC_WHY="cannot list the project directory $4"; return 1; }
    while IFS= read -r f; do
        [ -n "$f" ] && printf 'claude-projects/%s/%s\n' "$4" "${f#./}" >>"$2/links"
    done <"$2/tree.links"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        ac_copy_file "$1" "$2" "$3/${f#./}" "claude-projects/$4/${f#./}" || return 1
    done <"$2/tree"
}

ac_projects() {
    local arch=$1 s=$2 proj="$3/projects" ip=$4 enc d name phys
    # Names start with `-`, so every command gets one only inside an
    # absolute path.
    enc=$(printf '%s' "$ip" | sed 's/[^A-Za-z0-9]/-/g')
    : >"$s/taken"
    : >"$s/skipped"
    : >"$s/links"
    AC_PPROJ=""
    if [ -d "$proj" ]; then
        AC_PPROJ=$(cd -P -- "$proj" 2>"$s/cd.err" && pwd -P) || { AC_PPROJ=""; AC_WHY="cannot enter $proj"; return 1; }
    fi
    [ -n "$AC_PPROJ" ] || return 0
    for d in "$AC_PPROJ/$enc" "$AC_PPROJ/$enc"-*; do
        name=${d##*/}
        if [ -L "$d" ]; then
            printf '%s\tsymbolic link\n' "$name" >>"$s/skipped"
            continue
        fi
        [ -d "$d" ] || continue
        phys=$(cd -P -- "$d" 2>"$s/cd.err" && pwd -P) || { AC_WHY="cannot enter the project directory $name"; return 1; }
        [ "$phys" = "$AC_PPROJ/$name" ] || { AC_WHY="the project directory $name is not where its name says"; return 1; }
        if [ "$name" != "$enc" ]; then
            ac_cwd_inside "$s" "$phys" "$ip"
            case $? in
                0) ;;
                1) printf '%s\tcwd outside the instance\n' "$name" >>"$s/skipped"; continue ;;
                *) AC_WHY="cannot read the project directory $name"; return 1 ;;
            esac
        fi
        ac_copy_project "$arch" "$s" "$phys" "$name" || return 1
        printf '%s\n' "$name" >>"$s/taken"
    done
}

ac_koto_find() {
    local s=$1 kdir=$2 d f ed r hit
    shift 2
    : >"$s/koto.dirs"
    for d in "$kdir"/*/; do
        [ -d "$d" ] || continue
        for f in "$d"koto-*.state.jsonl; do
            [ -f "$f" ] || continue
            ed=$(head -1 "$f" | jq -r '.execution_dir // ""') || ed=""
            hit=0
            for r in "$@"; do
                case "$ed/" in "$r"/*) hit=1 ;; esac
            done
            if [ "$hit" = 1 ]; then
                printf '%s\n' "${d%/}" >>"$s/koto.dirs"
                break
            fi
        done
    done
    return 0
}

ac_koto_copy() {
    local d
    AC_NK=0
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        ac_copy_tree "$1" "$2" "$d" "koto/$(basename "$d")" || return 1
        AC_NK=$((AC_NK + 1))
    done <"$2/koto.dirs"
}

ac_manifest() {
    local rel src h
    : >"$1/MANIFEST.new"
    while IFS='	' read -r rel src; do
        h=$(ac_sha256 <"$1/$rel") || { AC_WHY="cannot hash $rel"; return 1; }
        [ "$(ac_sha256 <"$src")" = "$h" ] || { AC_WHY="$rel doesn't match its source"; return 1; }
        printf '%s %s %s\n' "$h" "$(wc -c <"$1/$rel" | tr -d ' ')" "$rel" >>"$1/MANIFEST.new"
    done <"$2/copies"
    mv "$1/MANIFEST.new" "$1/MANIFEST"
    # Its digest, recorded once every copy matched: the pass's confirm reads
    # it in place of hashing the archive again.
    h=$(ac_sha256 <"$1/MANIFEST") && printf '%s  MANIFEST\n' "$h" >"$1/MANIFEST.sha256" \
        || { AC_WHY="cannot record the MANIFEST's digest"; return 1; }
}

ac_readme() {
    local s=$2 trees=${4:-}
    [ -n "$trees" ] && [ -s "$trees" ] || trees=""
    {
        cat "$3"
        # shellcheck disable=SC2016 # the backticks are Markdown
        printf '`claude-projects/` holds the Claude Code project directories of the instance, each copied whole without following a symbolic link:\n\n'
        sed 's/^/- Project directory taken: /' "$s/taken"
        awk -F'\t' '{ printf "- Project directory skipped (%s): %s\n", $2, $1 }' "$s/skipped"
        sed 's/^/- Symbolic link skipped: /' "$s/links"
        printf '\n'
        if [ -n "$trees" ]; then
            # shellcheck disable=SC2016 # the backticks are Markdown
            printf '`job/tmp/` is copied without the build trees a worker left in it:\n\n'
            awk '{ p = substr($0, length($1) + length($2) + 3); printf "- Build tree skipped (%s, %s bytes): %s\n", $2, $1, p }' "$trees"
            printf '\n'
        fi
        printf 'MANIFEST lists every copied file as `<sha256> <bytes> <path>`; each was checked against its source.\n'
        # shellcheck disable=SC2016 # the backticks are Markdown
        printf '`MANIFEST.sha256` holds the MANIFEST'"'"'s own sha256, recorded once every copy matched; the confirm check reads it.\n'
        # shellcheck disable=SC2016 # the backticks are Markdown
        printf '`teardown.json`, in the MANIFEST, records what the pass acted on: the topic, the instance, the job and session, whether the unit was removed outside the pass, and niwa'"'"'s dispatch id.\n'
        # shellcheck disable=SC2016 # the backticks are Markdown
        [ -n "$trees" ] && printf '`SKIPPED`, in the MANIFEST, lists each build tree left out of `job/tmp/` as `<bytes> <marker> <path>`: a directory holding cargo'"'"'s CACHEDIR.TAG, .rustc_info.json or .cargo-lock, a cargo home'"'"'s .package-cache, or a node_modules directory. None of their files is in the archive.\n'
        # shellcheck disable=SC2016 # the backticks are Markdown
        printf '`unit-cost.json`, when present, is the cost capture'"'"'s derived summary and is not in the MANIFEST.\n'
    } >"$1/README.md"
}

# ---------------------------------------------------------------------------
# The removals directory.

ac_dir_private() {
    local m
    if [ -L "$1" ]; then AC_WHY="$1 is a symbolic link"; return 1; fi
    [ -d "$1" ] || { AC_WHY="$1 is not a directory"; return 1; }
    [ -O "$1" ] || { AC_WHY="$1 is not the user's"; return 1; }
    m=$(ls -ld -- "$1" 2>/dev/null) || { AC_WHY="$1 can't be read"; return 1; }
    # macOS adds `@` for extended attributes and SELinux hosts `.` for a
    # security context, neither of which grants access; `+` (an ACL) is
    # refused, since it can grant what the mode doesn't.
    case "${m%% *}" in
        drwx------ | drwx------@ | drwx------.) ;;
        *) AC_WHY="$1 is not mode 0700"; return 1 ;;
    esac
}

ac_removals_dir() {
    AC_R="${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals"
    if [ ! -e "$AC_R" ] && [ ! -L "$AC_R" ]; then
        [ "${1:-}" = --create ] || { AC_WHY="there is no removals directory"; return 1; }
        # AC_R is always absolute, so no `--` is needed (BSD chmod takes none).
        mkdir -p -- "$AC_R" 2>/dev/null && chmod 700 "$AC_R" 2>/dev/null \
            || { AC_WHY="cannot create the removals directory $AC_R"; return 1; }
    fi
    ac_dir_private "$AC_R"
}

ac_removal_for_path() {
    local f rows=""
    AC_REMOVAL_ID=""
    ac_removals_dir || return 1
    for f in "$AC_R"/*.json; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        rows="$rows$(jq -c --arg p "$1" --arg re "$AC_RE_REAP" --arg n "${f##*/}" '
            select(type == "object" and .schema == "unit-removal/1" and .instance_path == $p
                   and (.dispatch_id | type) == "string" and (.dispatch_id | test($re)) and $n == .dispatch_id + ".json")
            | {d: .dispatch_id, at: (.removed_at | if type == "string" then . else "" end)}' "$f" 2>/dev/null)
"
    done
    # The rows are jq's own compact output above, so this read can't meet
    # input it can't parse; a failure still leaves the id empty.
    AC_REMOVAL_ID=$(jq -s -r 'sort_by(.at) | last | .d // empty' <<<"$rows") || AC_REMOVAL_ID=""
    [ -n "$AC_REMOVAL_ID" ] || { AC_WHY="no removal record names the instance path"; return 1; }
}

# ac_lock <lock dir> <max age secs> <wait secs>: take a lock that is a
# directory holding `owner` (`<pid> <epoch secs>`), made with mkdir, which is
# atomic. One held by a live process younger than <max age> is waited for, one
# second at a time, for at most <wait> seconds. One whose holder is gone, or
# that is older, is taken over: renamed aside, its owner read again from the
# renamed copy, and removed only when that is still the owner judged stale (a
# copy that changed, because another process took the lock meanwhile, is moved
# back). A lock with no owner yet may be one its holder has just made and not
# yet written, so it is judged stale only once it has stayed ownerless for two
# seconds. Returns 0 holding the lock, 1 when it is still held at
# the end of the wait (AC_WHY says so).
ac_lock() {
    local d=$1 max=$2 wait=$3 own pid at now waited=0 side blank=0
    while :; do
        if mkdir -- "$d" 2>/dev/null; then
            printf '%s %s\n' "$$" "$(date +%s)" >"$d/owner" || { rm -rf -- "$d"; AC_WHY="cannot write $d/owner"; return 1; }
            return 0
        fi
        own=$(cat -- "$d/owner" 2>&1) || own=""
        pid=${own%% *} at=${own##* }
        now=$(date +%s)
        case "$pid$at" in '' | *[!0-9]*) pid="" at=0 ;; esac
        if [ -z "$pid" ] && [ "$blank" -lt 2 ]; then
            blank=$((blank + 1))
            sleep 1
            continue
        fi
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || [ $((now - at)) -gt "$max" ]; then
            side="$d.stale.$$"
            if mv -- "$d" "$side" 2>/dev/null; then
                if [ "$(cat -- "$side/owner" 2>&1)" = "$own" ]; then
                    rm -rf -- "$side"
                else
                    mv -- "$side" "$d" 2>/dev/null || rm -rf -- "$side"
                fi
            fi
            continue
        fi
        [ "$waited" -lt "$wait" ] || { AC_WHY="$d is held by process $pid"; return 1; }
        sleep 1
        waited=$((waited + 1))
    done
}

# ac_unlock <lock dir>: release a lock this process holds; one another process
# holds is left alone.
ac_unlock() {
    case "$(cat -- "$1/owner" 2>&1)" in "$$ "*) rm -rf -- "$1" ;; esac
    return 0
}

# ---------------------------------------------------------------------------
# The dispatch request.

ac_dispatch_request() {
    local d f req leg rows="" pick
    local reqs="${KOTO_REQUESTS:-$HOME/.koto/requests}"
    AC_REQ="" AC_LEG="" AC_BY="" AC_COR=""
    for d in "$@"; do
        f="$d/request-leg.toml"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        req=$(sed -n 's/^request_id[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$f" | head -n 1)
        leg=$(sed -n 's/^leg_name[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$f" | head -n 1)
        [[ $req =~ $DC_RE_REQ ]] && [[ $leg =~ $DC_RE_LEG ]] || continue
        f="$reqs/$req/request.jsonl"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        rows="$rows$(head -n 1 "$f" | jq -R -c --arg q "$req" --arg l "$leg" --arg re "$AC_RE_COORD" '
            fromjson? | objects
            | select((.requested_by | type) == "string" and (.requested_by | test($re))
                     and (.created_at | type) == "string"
                     and (.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$"))
                     and (.coordinator_of_record | type) == "string")
            | {q: $q, l: $l, by: .requested_by, cor: .coordinator_of_record, at: .created_at}' 2>/dev/null)
"
    done
    # The earliest; a request several sessions name keeps the first one's leg.
    pick=$(printf '%s' "$rows" | jq -s -r '
        def key: if length > 20 then .[0:19] + "." + ((.[20:-1] + "000000000")[0:9]) else .[0:19] + ".000000000" end;
        map(select(type == "object")) | sort_by(.at | key) | first // empty | [.q, .l, .by, .cor] | @tsv' 2>/dev/null)
    # shellcheck disable=SC2034 # read by the caller
    [ -n "$pick" ] || { AC_WHY="no coordinator request"; return 1; }
    # shellcheck disable=SC2034 # read by the caller
    IFS='	' read -r AC_REQ AC_LEG AC_BY AC_COR <<<"$pick"
}
