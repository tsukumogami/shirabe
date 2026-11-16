# shellcheck shell=bash
# build-output-lib.sh -- where build-output removals are recorded, and whether
# one is still running.
# Part of the work-on skill
#
# Sourced, never run. clean-build-output.sh writes one record per removal,
# `removal-<stamp>.json`, beside the trash it removes, in a directory inside
# the worktree's own git directory. Anything that has to know whether a removal
# is still running reads the record through bo_record_live, so a record can't
# read ended to one reader and live to another.
#
#   bo_dir <root>
#       Prints the absolute path of the records directory for the work tree at
#       <root>: the path `git -C <root> rev-parse --git-path
#       shirabe-build-output` names, made absolute against <root>'s physical
#       path. In a linked worktree that is inside the worktree's own git
#       directory, in a plain clone inside <root>/.git. It's the same
#       directory `--path-format=absolute` names, but that option resolves
#       symlinks, so a symlink planted at the directory's own name would read
#       as its target and pass a symlink check; this keeps the name as it is.
#       Returns 1 and prints nothing when git can't answer.
#
#   bo_record_parses <record>
#       Returns 0 when <record> is a regular file (not a symlink) holding one
#       JSON object with a string `status`, and, when that status is
#       `running`, a positive integer `pid`. Returns 1 otherwise.
#
#   bo_record_live <record>
#       Returns 0 only when the record parses, says `status: running`, its
#       `pid` answers `kill -0`, and `ps -p <pid> -o command=` names
#       `clean-build-output.sh --delete <stamp>` for the stamp in the record's
#       own file name. Returns 1 otherwise: an ended record, an unparsable one,
#       a dead pid, and a recycled pid now running another program all read
#       ended.
#
#   bo_record_stamp <record>
#       Prints the stamp in a record's file name (`removal-<stamp>.json`), or
#       returns 1 when the name isn't one a removal writes.
#
# A stamp is `<UTC time to the second>-<pid>`, as `20261116T080412Z-48213`.
#
# Written for the bash 3.2 floor.

BO_STAMP_RE='^[0-9]{8}T[0-9]{6}Z-[0-9]+$'

bo_dir() {
    local root="$1" d r
    [ -n "$root" ] || return 1
    d=$(git -C "$root" rev-parse --git-path shirabe-build-output 2>/dev/null) || return 1
    [ -n "$d" ] || return 1
    case "$d" in
        /*) ;;
        *)
            r=$(cd "$root" 2>/dev/null && pwd -P) || return 1
            d="$r/$d"
            ;;
    esac
    printf '%s\n' "$d"
}

bo_record_stamp() {
    local base stamp
    base=${1##*/}
    case "$base" in
        removal-*.json) ;;
        *) return 1 ;;
    esac
    stamp=${base#removal-}
    stamp=${stamp%.json}
    printf '%s\n' "$stamp" | grep -Eq "$BO_STAMP_RE" || return 1
    printf '%s\n' "$stamp"
}

bo_record_parses() {
    local rec="$1"
    [ -f "$rec" ] && [ ! -L "$rec" ] || return 1
    jq -se 'length == 1 and (.[0] | type == "object"
        and (.status | type == "string")
        and (if .status == "running"
             then (.pid | type == "number" and . > 0 and . == floor)
             else true end))' "$rec" >/dev/null 2>&1
}

bo_record_live() {
    local rec="$1" stamp status pid cmd
    stamp=$(bo_record_stamp "$rec") || return 1
    bo_record_parses "$rec" || return 1
    status=$(jq -r '.status' "$rec" 2>/dev/null) || return 1
    [ "$status" = running ] || return 1
    pid=$(jq -r '.pid' "$rec" 2>/dev/null) || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    cmd=$(ps -p "$pid" -o command= 2>/dev/null) || return 1
    case " $cmd " in
        *"clean-build-output.sh --delete $stamp "*) return 0 ;;
    esac
    return 1
}
