#!/usr/bin/env bash
# preflight-resolve.sh -- decide whether a declared tool is present, installed
# but off PATH, absent from the host, or resolution-refused.
#
# Sourced by scripts/skill-preflight.sh after the plugin root has been
# validated. Resolution runs before any probe and is nearly free: `command -v`
# is a shell builtin and spawns nothing.
#
# The order is fixed and it is the reason the report can say "nothing needs
# installing":
#
#   1. `command -v <tool>`. Resolves -> the tool is present.
#   2. Otherwise `-x` against each SHIRABE_PREFLIGHT_ROOTS entry. A hit means
#      installed but off PATH, and the remedy is `. ~/.tsuku/env` with no
#      install offered.
#   3. Only on a miss everywhere is the tool absent, and only then is an
#      install route resolved at all.
#
# Two invariants this file exists to hold.
#
#   A `command -v` result that is relative, or absolute but under the current
#   working directory, is resolution-refused: the binary is never executed and
#   the report says so. `command -v` honours whatever PATH the session carries,
#   including a `.` entry, and the working directory at skill load may be a
#   branch that arrived from a pull request.
#
#   Roots are only ever tested with `-x`, and a root-resolved path is never
#   executed. SHIRABE_PREFLIGHT_ROOTS is input, not only a test affordance --
#   anything that sets session environment can set it, including a repo's own
#   .claude/settings.json. A later revision that wants to probe a root-resolved
#   binary has to change that sentence first.
#
# bash 3.2 throughout. The empty-array expansion trap is handled explicitly and
# has a named test; see preflight_split_roots.

if [ "${PREFLIGHT_RESOLVE_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_RESOLVE_SOURCED=1

# Defined by preflight-read.sh, which is sourced first. Defaulted here so this
# file does not silently depend on that order.
: "${PREFLIGHT_TAB:=$(printf '\t')}"
: "${PREFLIGHT_NL:=
}"

# Set by preflight_resolve_tool.
PREFLIGHT_STATUS=""
PREFLIGHT_PATH=""

# Filled by preflight_split_roots.
PREFLIGHT_ROOTS=()

# Memo, in the two-string form bash 3.2 forces. Keys are tool names that have
# already passed the character allowlist, so no glob metacharacter can enter
# the `case` pattern below.
PREFLIGHT_RESOLVE_KEYS=""
PREFLIGHT_RESOLVE_DATA=""

# preflight_split_roots
#
# Splits SHIRABE_PREFLIGHT_ROOTS into PREFLIGHT_ROOTS, once, before any record
# is read. The IFS assignment is scoped to the `read` builtin, so this split and
# the tab split in preflight-read.sh cannot interfere -- the alternative,
# assigning IFS globally and restoring it, is the version that breaks the day
# someone adds an early return.
#
# The default applies when the variable is *unset*, not when it is empty:
# `${VAR-default}`, not `${VAR:-default}`. An explicitly empty value means an
# empty root list, and it has to reach the empty-array path rather than being
# quietly replaced by the default -- otherwise the guard below is untested and
# the abort it prevents ships.
#
# The trap: `IFS=: read -r -a PREFLIGHT_ROOTS <<<""` yields an empty array, and
# on bash 3.2 expanding `"${arr[@]}"` on an empty array under `set -u` aborts
# with "unbound variable". The abort is then swallowed by the injected line's
# `|| true`, so it looks like success while the report silently disappears.
# Every expansion of this array therefore uses the `${arr[@]+"${arr[@]}"}` form,
# and preflight_empty_roots_does_not_abort covers it.
preflight_split_roots() {
    local home="${HOME-}" raw fallback=""

    if [ -n "$home" ]; then
        fallback="$home/.tsuku/tools/current:$home/.shirabe/bin:$home/.local/bin"
    fi
    raw="${SHIRABE_PREFLIGHT_ROOTS-$fallback}"

    PREFLIGHT_ROOTS=()
    IFS=: read -r -a PREFLIGHT_ROOTS <<<"$raw"
}

# preflight_valid_path <path>
#
# The path allowlist applied to anything path-shaped before it is rendered:
# absolute, [A-Za-z0-9._/-]+, within 4096 bytes. It governs both the
# `command -v` result and every root entry echoed into the "Checked PATH, then
# ..." line, because root entries are input too.
preflight_valid_path() {
    local p="${1-}"
    [ -n "$p" ] || return 1
    [ "${#p}" -le 4096 ] || return 1
    case "$p" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$p" in
        *[!A-Za-z0-9._/-]*) return 1 ;;
    esac
    return 0
}

# preflight_path_under_cwd <path>
#
# True when the path lies under the current working directory. A binary that
# resolves there is never executed: at skill load the working directory may be
# a branch under review.
#
# When PWD is `/` every absolute path is under it, and refusing everything
# would turn one unusual working directory into a total outage. The check is
# skipped there; the case it defends against is a repository checkout, and a
# repository checkout is never the filesystem root.
preflight_path_under_cwd() {
    local p="${1-}" cwd="${PWD-}"
    [ -n "$cwd" ] || return 1
    [ "$cwd" = "/" ] && return 1
    case "$p" in
        "$cwd"/*) return 0 ;;
    esac
    return 1
}

# preflight_resolve_tool <tool>
#
# Sets PREFLIGHT_STATUS to one of:
#
#   present   resolved on PATH, absolute, outside the working directory
#   offpath   not on PATH, found with -x under one of the roots
#   absent    not on PATH and not under any root
#   refused   resolved on PATH to a relative path, or to one under $PWD
#
# and PREFLIGHT_PATH to the resolved path where there is one. Results are
# memoized per tool: /work-on declares ten koto records and one resolution
# answers all ten.
#
# The caller must have run the character allowlist on the tool name first.
preflight_resolve_tool() {
    local tool="$1" cv root k s p

    case "$PREFLIGHT_RESOLVE_KEYS" in
        *"$PREFLIGHT_NL$tool$PREFLIGHT_NL"*)
            while IFS="$PREFLIGHT_TAB" read -r k s p; do
                if [ "$k" = "$tool" ]; then
                    PREFLIGHT_STATUS="$s"
                    PREFLIGHT_PATH="$p"
                    return 0
                fi
            done <<<"$PREFLIGHT_RESOLVE_DATA"
            ;;
    esac

    PREFLIGHT_STATUS="absent"
    PREFLIGHT_PATH=""

    cv=$(command -v "$tool" 2>/dev/null) || cv=""

    if [ -n "$cv" ]; then
        case "$cv" in
            /*)
                if preflight_path_under_cwd "$cv"; then
                    PREFLIGHT_STATUS="refused"
                    PREFLIGHT_PATH="$cv"
                elif [ -x "$cv" ]; then
                    PREFLIGHT_STATUS="present"
                    PREFLIGHT_PATH="$cv"
                fi
                ;;
            *)
                # A relative result, or a shell builtin or function answering to
                # the name. Either way it is not an absolute path outside the
                # working directory, so it is not run.
                PREFLIGHT_STATUS="refused"
                PREFLIGHT_PATH="$cv"
                ;;
        esac
    fi

    if [ "$PREFLIGHT_STATUS" = "absent" ]; then
        for root in ${PREFLIGHT_ROOTS[@]+"${PREFLIGHT_ROOTS[@]}"}; do
            # A relative root would be tested against the working directory,
            # which is the thing the refusal rule above exists to avoid.
            case "$root" in
                /*) ;;
                *) continue ;;
            esac
            if [ -x "$root/$tool" ]; then
                PREFLIGHT_STATUS="offpath"
                PREFLIGHT_PATH="$root/$tool"
                break
            fi
        done
    fi

    PREFLIGHT_RESOLVE_KEYS="$PREFLIGHT_RESOLVE_KEYS$PREFLIGHT_NL$tool$PREFLIGHT_NL"
    PREFLIGHT_RESOLVE_DATA="$PREFLIGHT_RESOLVE_DATA$tool$PREFLIGHT_TAB$PREFLIGHT_STATUS$PREFLIGHT_TAB$PREFLIGHT_PATH$PREFLIGHT_NL"
    return 0
}

# preflight_rendered_roots
#
# Prints the roots that pass the path allowlist, joined for prose: "A", "A and
# B", "A, B, and C". Prints nothing when no root renders. A non-conforming
# entry is dropped rather than sanitized.
preflight_rendered_roots() {
    local root out="" count=0 i=0

    for root in ${PREFLIGHT_ROOTS[@]+"${PREFLIGHT_ROOTS[@]}"}; do
        preflight_valid_path "$root" || continue
        count=$(( count + 1 ))
    done

    [ "$count" -gt 0 ] || return 0

    for root in ${PREFLIGHT_ROOTS[@]+"${PREFLIGHT_ROOTS[@]}"}; do
        preflight_valid_path "$root" || continue
        i=$(( i + 1 ))
        if [ "$i" -eq 1 ]; then
            out="$root"
        elif [ "$i" -eq "$count" ] && [ "$count" -eq 2 ]; then
            out="$out and $root"
        elif [ "$i" -eq "$count" ]; then
            out="$out, and $root"
        else
            out="$out, $root"
        fi
    done

    printf '%s' "$out"
    return 0
}
