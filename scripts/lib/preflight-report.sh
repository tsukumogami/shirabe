#!/usr/bin/env bash
# preflight-report.sh -- route resolution and every block the load-time
# prerequisite check prints.
#
# Sourced by scripts/skill-preflight.sh after the plugin root has been
# validated and after preflight-read.sh, preflight-resolve.sh, and
# preflight-probe.sh. Nothing here runs at source time: a satisfied
# declaration reaches the end of the check without this file executing a single
# statement, which is what keeps R12's zero-byte rule intact.
#
# WHAT THIS FILE OWNS
#
#   1. Route resolution over scripts/lib/tool-routes.tsv. The first record for
#      a tool whose OS matches `uname -s` and whose probe succeeds wins, which
#      is what makes R14's "exactly one command" fall out of the data rather
#      than out of reporter logic. Route availability is probed, never assumed.
#   2. The four unsatisfied blocks R13 requires, kept distinguishable: off
#      PATH, absent from the host, missing subcommand, missing flag on a
#      present subcommand. Plus the two outcomes outside R13's postures --
#      resolution refused and probe inconclusive -- which say explicitly that
#      no claim about the surface is being made.
#   3. The normative filter on tool-derived text, applied at the point of
#      rendering.
#
# WHY THE DEFINITIONS BELOW ARE NOT GUARDED
#
# preflight-probe.sh and the entry point both define fallback renderers under
# `if ! declare -f`, so that each component works before the next one lands.
# Both are sourced ahead of this file, so their fallbacks already exist by the
# time it is read: guarding here would mean the reporter never takes over. It
# therefore defines its renderers unconditionally and is the last word on what
# a block says. That is the intended arrangement -- the earlier definitions
# exist for the configurations where this file is absent, not to win against
# it.
#
# THE FILTER, AND WHY IT IS APPLIED AGAIN HERE
#
# Three things in a block come from a binary on the user's PATH rather than
# from a committed file: the advertised subcommand list, the advertised flag
# list, and the resolved path. Everything else -- the posture sentences, the
# impact sentence, the route lines, the closing bound -- is fixed text, or
# comes from requires.tsv and tool-routes.tsv, both committed and both
# allowlisted at read time.
#
# preflight-probe.sh already allowlists each token as it extracts it. This file
# allowlists them again on the way out, and that is not redundancy for its own
# sake: the extractor's job is to decide what a level advertises, and this
# file's job is to decide what reaches a model's context. A future caller that
# assembles a token list some other way -- a cache, a different extractor, a
# test harness -- inherits the bound because the bound sits at the boundary it
# crosses. The resolved path makes the same argument concretely: it never
# passes through the extractor at all. It comes from `command -v`, or from a
# SHIRABE_PREFLIGHT_ROOTS entry, and the root list is settable by anything that
# sets session environment, including a repository's own .claude/settings.json.
#
# The rules, in the design's order, all of them requirements rather than
# descriptions:
#
#   ANSI CSI sequences and every C0, C1, and DEL code point are stripped from
#   the incoming text first, so an escape sequence cannot survive by hiding
#   inside an otherwise-conforming token. Each remaining token must then match
#   [A-Za-z0-9._-]+ for a subcommand or --?[A-Za-z0-9][A-Za-z0-9-]* for a flag,
#   and must be 64 bytes or shorter. A token that does not match is DROPPED,
#   not sanitized, following the reject-don't-sanitize rule this repo already
#   applies to extracted URLs: a sanitized token would be a claim about a
#   surface that does not exist. Each list is capped at 24 items, with the
#   overflow rendered as a literal `and N more`.
#
#   The resolved path is rendered only if it is absolute and matches
#   [A-Za-z0-9._/-]+ within 4096 bytes. A path that is not is not rendered; the
#   block says the tool resolved to a path this report will not render, and
#   carries on.
#
#   The interpolated region is labelled. An advertised list appears only after
#   the fixed phrase `advertises:` and only on its own line, so a reader and a
#   model both see where committed text stops and binary output starts.
#
# The design's tripwire applies to any change here: after the filter a token
# cannot contain a space, a newline, a quote, a backtick, a colon, or anything
# outside [A-Za-z0-9._-] plus a leading dash, so it cannot form a sentence, an
# imperative, a code fence, or a line break, and there is nothing for a nonce
# fence to protect against. **Any tool-derived text the allowlist does not
# fully constrain must be nonce-fenced before it is rendered.** Loosening the
# alphabet is what makes the fence mandatory.
#
# Raw stderr is never echoed into a block. That is an invariant of the design,
# not a preference, and it is held on the probe side by discarding stderr at
# the source.
#
# bash 3.2 floor throughout: no `declare -A`, no namerefs, no mapfile, no
# `${var^^}`, no `[[ -v ]]`.

if [ "${PREFLIGHT_REPORT_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_REPORT_SOURCED=1

# Byte semantics, not collation semantics: the control-strip below uses glob
# ranges over byte values, and under a UTF-8 locale a range is collation
# ordered instead. The entry point already exports this, so it is a no-op
# there; it is here so the file does not depend on a caller that might not.
LC_ALL=C
export LC_ALL

# Defined by preflight-read.sh, which is sourced first. Defaulted here so this
# file does not silently depend on that order.
: "${PREFLIGHT_TAB:=$(printf '\t')}"
: "${PREFLIGHT_NL:=
}"

# The bounds. Named here rather than shared with preflight-probe.sh, because
# the two are separate promises: one bounds what the extractor believes, the
# other bounds what a reader is shown.
PREFLIGHT_REPORT_TOKEN_MAX=64
PREFLIGHT_REPORT_LIST_MAX=24
PREFLIGHT_REPORT_PATH_MAX=4096
PREFLIGHT_REPORT_COMMAND_MAX=512

# ---------------------------------------------------------------------------
# Wrapping
#
# Delegated to the entry point's wrapper when there is one, so every block
# wraps identically whoever rendered it. Standalone -- in the test harness, or
# under a future caller -- the line is printed as-is rather than growing a
# second wrapping implementation.
# ---------------------------------------------------------------------------

preflight_report_wrap() {
    if declare -f preflight_wrap >/dev/null 2>&1; then
        preflight_wrap "$1"
    else
        printf '%s\n' "$1"
    fi
}

preflight_report_separator() {
    if declare -f preflight_block_separator >/dev/null 2>&1; then
        preflight_block_separator
    fi
}

# preflight_report_checked <lead>
#
# "Checked PATH first, then A, B, and C." -- the root list, filtered through
# the path allowlist by preflight_rendered_roots, because a root entry is input
# and it is echoed into report text.
preflight_report_checked() {
    local lead="$1" roots=""
    if declare -f preflight_checked_sentence >/dev/null 2>&1; then
        preflight_checked_sentence "$lead"
        return 0
    fi
    if declare -f preflight_rendered_roots >/dev/null 2>&1; then
        roots=$(preflight_rendered_roots)
    fi
    if [ -n "$roots" ]; then
        printf 'Checked %s, then %s.' "$lead" "$roots"
    else
        printf 'Checked %s. No additional root was configured for this check.' "$lead"
    fi
}

# ---------------------------------------------------------------------------
# The filter on tool-derived text
# ---------------------------------------------------------------------------

# preflight_report_strip_controls <string>  ->  PREFLIGHT_REPORT_STRIPPED
#
# ANSI CSI sequences first, then every C0, C1, and DEL code point. Text that
# carries none of them -- which is all of it, on the path this check was
# written for -- is returned after a single `case` and is never rewritten.
PREFLIGHT_REPORT_STRIPPED=""
preflight_report_strip_controls() {
    local s="$1" pre rest
    case "$s" in
        *[[:cntrl:]]*|*[$'\200'-$'\237']*) ;;
        *)
            PREFLIGHT_REPORT_STRIPPED="$s"
            return 0
            ;;
    esac
    while :; do
        case "$s" in
            *$'\033['*) ;;
            *) break ;;
        esac
        pre="${s%%$'\033['*}"
        rest="${s#*$'\033['}"
        # Parameter and intermediate bytes are 0x20-0x3f; the final byte is the
        # first character in 0x40-0x7e, so cutting there ends the sequence.
        case "$rest" in
            *[@-~]*) rest="${rest#*[@-~]}" ;;
            *) rest="" ;;
        esac
        s="$pre$rest"
    done
    s="${s//[[:cntrl:]]/}"
    s="${s//[$'\200'-$'\237']/}"
    PREFLIGHT_REPORT_STRIPPED="$s"
    return 0
}

# preflight_report_valid_command <token>
#
# One advertised subcommand name: [A-Za-z0-9._-]+, no leading dash, at most 64
# bytes.
preflight_report_valid_command() {
    local t="${1-}"
    case "$t" in
        ''|-*) return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    [ "${#t}" -le "$PREFLIGHT_REPORT_TOKEN_MAX" ] || return 1
    return 0
}

# preflight_report_valid_flag <token>
#
# One advertised flag: --?[A-Za-z0-9][A-Za-z0-9-]*, at most 64 bytes.
preflight_report_valid_flag() {
    local t="${1-}" rest
    [ -n "$t" ] || return 1
    [ "${#t}" -le "$PREFLIGHT_REPORT_TOKEN_MAX" ] || return 1
    case "$t" in
        --?*) t="${t#--}" ;;
        -?*)  t="${t#-}" ;;
        *) return 1 ;;
    esac
    case "${t:0:1}" in
        [!A-Za-z0-9]) return 1 ;;
    esac
    rest="${t#?}"
    case "$rest" in
        *[!A-Za-z0-9-]*) return 1 ;;
    esac
    return 0
}

# preflight_report_path_ok <path>
#
# Absolute, [A-Za-z0-9._/-]+, within 4096 bytes. The rule is the same one
# preflight-resolve.sh applies, restated rather than borrowed: this is the
# filter on what reaches a reader, and it has to hold even where that file is
# not loaded.
preflight_report_path_ok() {
    local p="${1-}"
    [ -n "$p" ] || return 1
    [ "${#p}" -le "$PREFLIGHT_REPORT_PATH_MAX" ] || return 1
    case "$p" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$p" in
        *[!A-Za-z0-9._/-]*) return 1 ;;
    esac
    return 0
}

# preflight_report_render_list <kind> <token-list>
#
# The advertised list, filtered and bounded. `flags` keeps the dash-led tokens
# and `commands` keeps the rest; each token is stripped, allowlisted, and
# dropped if it does not conform; the list is capped at 24 items with a literal
# `and N more` tail. Prints nothing when nothing of that kind survives, which
# is a case the callers handle rather than printing an empty label.
preflight_report_render_list() {
    local kind="$1" list="$2" tok rest out="" shown=0 extra=0

    preflight_report_strip_controls "$list"
    rest="$PREFLIGHT_REPORT_STRIPPED"

    # Split by hand rather than with an unquoted expansion. The tokens are
    # about to be allowlisted, but an unquoted expansion would glob before that
    # happens, which is the wrong order to do these two things in.
    while [ -n "$rest" ]; do
        tok="${rest%% *}"
        if [ "$tok" = "$rest" ]; then
            rest=""
        else
            rest="${rest#* }"
        fi
        [ -n "$tok" ] || continue
        case "$kind" in
            flags)
                case "$tok" in -*) ;; *) continue ;; esac
                preflight_report_valid_flag "$tok" || continue
                ;;
            commands)
                case "$tok" in -*) continue ;; esac
                preflight_report_valid_command "$tok" || continue
                ;;
            *) continue ;;
        esac
        if [ "$shown" -ge "$PREFLIGHT_REPORT_LIST_MAX" ]; then
            extra=$(( extra + 1 ))
            continue
        fi
        if [ -z "$out" ]; then
            out="$tok"
        else
            out="$out, $tok"
        fi
        shown=$(( shown + 1 ))
    done

    [ "$extra" -gt 0 ] && out="$out, and $extra more"
    printf '%s' "$out"
    return 0
}

# preflight_report_advertises <label> <kind> <token-list>
#
# The labelled region. The list appears only after the fixed phrase
# `advertises:` and only on its own line.
preflight_report_advertises() {
    local label="$1" kind="$2" list="$3" listing
    listing=$(preflight_report_render_list "$kind" "$list")
    if [ -n "$listing" ]; then
        preflight_report_wrap "\`$label\` advertises:"
        printf '  %s\n' "$listing"
    elif [ "$kind" = "flags" ]; then
        preflight_report_wrap "\`$label\` advertises no flag this check can render."
    else
        preflight_report_wrap "\`$label\` advertises no subcommand this check can render."
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Route resolution
#
# Read only after a tool has been found absent, or after a surface gap has been
# established. The satisfied path never opens the file: the entry point's own
# read of tool-routes.tsv is the reader validating field one of every
# declaration against the tool column, and that is a different job from
# resolving a route.
#
# The record that wins is the first one for the tool whose OS matches and whose
# probe succeeds. Every record that does not win is kept with the reason it did
# not, because the no-route enumeration is the thing that tells a reader the
# maintainers did not simply forget a route.
# ---------------------------------------------------------------------------

# The host OS, resolved once, on the report path only. It sets a global rather
# than printing into a command substitution: a `$(...)` would run the cache
# assignment in a subshell and throw it away, which turns one `uname` into one
# per block.
PREFLIGHT_REPORT_OS=""

preflight_report_set_os() {
    local u
    [ -n "$PREFLIGHT_REPORT_OS" ] && return 0
    u=$(uname -s 2>/dev/null </dev/null) || u=""
    case "$u" in
        Darwin) PREFLIGHT_REPORT_OS="darwin" ;;
        Linux)  PREFLIGHT_REPORT_OS="linux" ;;
        # Anything else is named by no record's OS column, so only `any`
        # records can apply. The raw value is never rendered: it is the one
        # piece of uname output that would otherwise reach the report.
        *)      PREFLIGHT_REPORT_OS="other" ;;
    esac
    return 0
}

preflight_report_routes_file() {
    local lib="${PREFLIGHT_LIB-}"
    if [ -z "$lib" ]; then
        lib=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || lib=""
    fi
    [ -n "$lib" ] || return 1
    printf '%s/tool-routes.tsv' "$lib"
    return 0
}

# preflight_route_run <path> [<arg>...]
#
# Runs a route driver with stdin closed and both output streams discarded,
# returning its exit status. A driver is a program on the user's host, so it
# gets the same never-block treatment a probe does: when preflight-probe.sh is
# loaded its watchdog bounds this call too. Without that file the call is made
# directly, which is the honest degradation -- the alternative is a second
# watchdog implementation maintained in parallel with the first.
preflight_route_run() {
    local path="$1"
    shift
    local st=0
    if declare -f preflight_probe_watchdog >/dev/null 2>&1 &&
       declare -f preflight_probe_helpers_ready >/dev/null 2>&1 &&
       preflight_probe_helpers_ready; then
        (
            exec >/dev/null 2>&1
            set -m
            "$path" "$@" </dev/null >/dev/null 2>&1 &
            _preflight_route_pid=$!
            set +m
            preflight_probe_watchdog "$_preflight_route_pid" &
            _preflight_route_watchdog=$!
            wait "$_preflight_route_pid"
            _preflight_route_status=$?
            kill "$_preflight_route_watchdog" 2>/dev/null
            wait "$_preflight_route_watchdog" 2>/dev/null
            exit "$_preflight_route_status"
        ) </dev/null || st=$?
    else
        "$path" "$@" </dev/null >/dev/null 2>&1 || st=$?
    fi
    return "$st"
}

# preflight_route_driver_path <driver>  ->  PREFLIGHT_ROUTE_DRIVER
#
# The driver is executed for a package-knowledge verb, so it is held to the
# resolution rule the declared tools are held to: absolute, conforming, and
# outside the working directory. A driver that resolves under the directory the
# check was invoked from is not run -- at skill load that directory may be a
# branch under review, and a route driver is no safer to run from there than a
# declared tool is.
PREFLIGHT_ROUTE_DRIVER=""
preflight_route_driver_path() {
    local driver="$1" cv
    PREFLIGHT_ROUTE_DRIVER=""
    cv=$(command -v "$driver" 2>/dev/null </dev/null) || cv=""
    [ -n "$cv" ] || return 1
    preflight_report_path_ok "$cv" || return 2
    if declare -f preflight_path_under_cwd >/dev/null 2>&1 &&
       preflight_path_under_cwd "$cv"; then
        return 2
    fi
    [ -x "$cv" ] || return 1
    PREFLIGHT_ROUTE_DRIVER="$cv"
    return 0
}

# The per-probe memo, in the two-string form bash 3.2 forces. A `brew -` record
# appears three times in the shipped table, and a report that names three
# absent tools should resolve `brew` once.
PREFLIGHT_ROUTE_KEYS=""
PREFLIGHT_ROUTE_DATA=""
PREFLIGHT_ROUTE_REASON=""

# preflight_route_available <probe> <tool>
#
# The closed verb vocabulary lives here, in the reader, so the table cannot
# introduce a new command shape:
#
#   `<driver> -`            the route is available when <driver> resolves.
#   `<driver> tsuku-info`   ... and when `<driver> info <tool>` also succeeds.
#   `never`                 the route is excluded; handled by the caller,
#                           which needs the citation.
#
# Adding a driver is a code change, not a data change. A record naming a verb
# outside the vocabulary is rejected rather than executed -- the failure a
# permissive reader would ship is a table that can name any command it likes
# and have this check run it.
#
# Returns 0 when the route is available; 1 otherwise, with the reason in
# PREFLIGHT_ROUTE_REASON.
preflight_route_available() {
    local probe="$1" tool="$2" driver verb key k s r

    PREFLIGHT_ROUTE_REASON=""

    # The probe string becomes a `case` pattern below, so its alphabet is
    # checked before it does.
    case "$probe" in
        ''|*[!A-Za-z0-9._' '-]*)
            PREFLIGHT_ROUTE_REASON="carries an availability test this check will not read"
            return 1
            ;;
    esac

    key="$probe $tool"
    case "$PREFLIGHT_ROUTE_KEYS" in
        *"$PREFLIGHT_NL$key$PREFLIGHT_NL"*)
            while IFS="$PREFLIGHT_TAB" read -r k s r; do
                if [ "$k" = "$key" ]; then
                    PREFLIGHT_ROUTE_REASON="$r"
                    [ "$s" = "ok" ] && return 0
                    return 1
                fi
            done <<<"$PREFLIGHT_ROUTE_DATA"
            ;;
    esac

    driver="${probe%% *}"
    if [ "$driver" = "$probe" ]; then
        verb="-"
    else
        verb="${probe#* }"
    fi

    case "$verb" in
        -|tsuku-info) ;;
        *)
            PREFLIGHT_ROUTE_REASON="names an availability test this check does not implement, so the route was not used"
            preflight_route_memo "$key" "no" "$PREFLIGHT_ROUTE_REASON"
            return 1
            ;;
    esac

    case "$driver" in
        ''|-*|*[!A-Za-z0-9._-]*)
            PREFLIGHT_ROUTE_REASON="names a driver this check will not run"
            preflight_route_memo "$key" "no" "$PREFLIGHT_ROUTE_REASON"
            return 1
            ;;
    esac

    preflight_route_driver_path "$driver"
    case "$?" in
        0) ;;
        2)
            PREFLIGHT_ROUTE_REASON="$driver resolves to a path this check will not run"
            preflight_route_memo "$key" "no" "$PREFLIGHT_ROUTE_REASON"
            return 1
            ;;
        *)
            PREFLIGHT_ROUTE_REASON="$driver does not resolve"
            preflight_route_memo "$key" "no" "$PREFLIGHT_ROUTE_REASON"
            return 1
            ;;
    esac

    if [ "$verb" = "tsuku-info" ]; then
        if ! preflight_route_run "$PREFLIGHT_ROUTE_DRIVER" info "$tool"; then
            PREFLIGHT_ROUTE_REASON="$driver resolves, but does not know $tool"
            preflight_route_memo "$key" "no" "$PREFLIGHT_ROUTE_REASON"
            return 1
        fi
    fi

    PREFLIGHT_ROUTE_REASON=""
    preflight_route_memo "$key" "ok" ""
    return 0
}

preflight_route_memo() {
    PREFLIGHT_ROUTE_KEYS="$PREFLIGHT_ROUTE_KEYS$PREFLIGHT_NL$1$PREFLIGHT_NL"
    PREFLIGHT_ROUTE_DATA="$PREFLIGHT_ROUTE_DATA$1$PREFLIGHT_TAB$2$PREFLIGHT_TAB$3$PREFLIGHT_NL"
}

# preflight_route_command_ok <command>
#
# Field five is committed text and is emitted verbatim, which is exactly why it
# is checked before it is: a control character in it would reach a terminal,
# and a 512-byte line is not a command anybody meant to run.
preflight_route_command_ok() {
    local c="${1-}"
    [ -n "$c" ] || return 1
    [ "$c" != "-" ] || return 1
    [ "${#c}" -le "$PREFLIGHT_REPORT_COMMAND_MAX" ] || return 1
    case "$c" in
        *[[:cntrl:]]*) return 1 ;;
    esac
    return 0
}

# preflight_render_route <tool> [<mode>]
#
# The remedy section of a block: either exactly one command on its own indented
# line, or the explicit statement that no route is available, enumerating every
# route that was checked with the reason it did not apply. Never two commands,
# and never a choice for the reader.
#
# <mode> is `install` (the default, for an absent tool) or `update` (for a tool
# that is installed and missing part of its surface). It changes the lead-in
# and the closing sentence, nothing else.
#
# The entry point calls this with one argument and expects the whole section,
# lead-in included; that contract is what lets scripts/skill-preflight.sh stay
# unedited when this file drops in.
preflight_render_route() {
    local tool="$1" mode="${2-install}"
    local file hostos line tabs rtool route os probe command citation
    local reasons="" width=0 n
    local winner="" k r pad gap

    if [ "$mode" = "update" ]; then
        pad="Update to the newest $tool:"
    else
        pad="Install $tool:"
    fi

    file=$(preflight_report_routes_file) || file=""
    if [ -z "$file" ] || [ ! -r "$file" ]; then
        preflight_report_wrap "The route table this check reads could not be opened, so this report gives no command. Install $tool by whatever means this host supports."
        return 0
    fi

    preflight_report_set_os
    hostos="$PREFLIGHT_REPORT_OS"

    while IFS= read -r line || [ -n "$line" ]; do
        if declare -f preflight_strip >/dev/null 2>&1; then
            preflight_strip "$line"
            line="$PREFLIGHT_STRIPPED"
        fi
        [ -n "$line" ] || continue
        case "$line" in '#'*) continue ;; esac

        if declare -f preflight_tab_count >/dev/null 2>&1; then
            preflight_tab_count "$line"
            tabs=$PREFLIGHT_TABCOUNT
        else
            tabs=5
        fi
        [ "$tabs" = "5" ] || continue

        IFS="$PREFLIGHT_TAB" read -r rtool route os probe command citation <<<"$line"

        [ "$rtool" = "$tool" ] || continue

        # Field two is printed in the enumeration, so it is allowlisted here
        # even though the reader has already rejected the record on stderr.
        # This loop is a second reader, and a second reader that trusts the
        # first is a reader that stops being true when the first one changes.
        case "$route" in
            ''|*[!a-z0-9-]*) continue ;;
        esac

        n=${#route}
        [ "$n" -gt "$width" ] && width=$n

        if [ "$probe" = "never" ]; then
            case "$citation" in
                ''|-|*[!A-Za-z0-9._/#-]*)
                    # The reader rejects an uncited exclusion, so this is the
                    # unreachable branch. It names no citation rather than
                    # printing one it could not check.
                    reasons="$reasons$route$PREFLIGHT_TAB"
                    reasons="${reasons}excluded for $tool on $os$PREFLIGHT_NL"
                    ;;
                *)
                    reasons="$reasons$route$PREFLIGHT_TAB"
                    reasons="${reasons}excluded for $tool on $os -- see $citation$PREFLIGHT_NL"
                    ;;
            esac
            continue
        fi

        case "$os" in
            any) ;;
            darwin|linux)
                if [ "$os" != "$hostos" ]; then
                    reasons="$reasons$route$PREFLIGHT_TAB"
                    reasons="${reasons}offered on $os only, and this host is $hostos$PREFLIGHT_NL"
                    continue
                fi
                ;;
            *)
                reasons="$reasons$route$PREFLIGHT_TAB"
                reasons="${reasons}names an operating system this check does not read$PREFLIGHT_NL"
                continue
                ;;
        esac

        if ! preflight_route_command_ok "$command"; then
            reasons="$reasons$route$PREFLIGHT_TAB"
            reasons="${reasons}carries no command this report will print$PREFLIGHT_NL"
            continue
        fi

        if [ -n "$winner" ]; then
            # A later record for a tool that already has a winner is not
            # probed: the first match wins, and probing the rest would run
            # programs for an answer nobody reads.
            continue
        fi

        if preflight_route_available "$probe" "$tool"; then
            winner="$command"
            continue
        fi

        reasons="$reasons$route$PREFLIGHT_TAB$PREFLIGHT_ROUTE_REASON$PREFLIGHT_NL"
    done <"$file"

    if [ -n "$winner" ]; then
        preflight_report_wrap "$pad"
        printf '\n'
        printf '  %s\n' "$winner"
        return 0
    fi

    if [ "$mode" = "update" ]; then
        pad="Update $tool by whatever means this host supports."
    else
        pad="Install $tool by whatever means this host supports."
    fi

    if [ -z "$reasons" ]; then
        preflight_report_wrap "No install route is available on this host, so this report gives no command. The route table carries no route for $tool at all."
        printf '\n'
        preflight_report_wrap "$pad"
        return 0
    fi

    preflight_report_wrap "No install route is available on this host, so this report gives no command. Every route was checked:"
    printf '\n'
    while IFS="$PREFLIGHT_TAB" read -r k r; do
        [ -n "$k" ] || continue
        n=$(( width - ${#k} ))
        gap=""
        while [ "$n" -gt 0 ]; do
            gap="$gap "
            n=$(( n - 1 ))
        done
        printf '  %s%s  %s\n' "$k" "$gap" "$r"
    done <<<"$reasons"
    printf '\n'
    preflight_report_wrap "$pad"
    return 0
}

# ---------------------------------------------------------------------------
# The blocks
#
# Seven shape rules, encoded rather than described:
#
#   1. The first line names the skill and states the posture in words.
#   2. The posture paragraph distinguishes all four unsatisfied cases
#      explicitly. Off PATH says "installed at ... but is not on this shell's
#      PATH"; absent says "is not installed on this host"; a subcommand gap
#      says the tool "does not have the subcommand"; a flag gap says the
#      subcommand "does not advertise the flag". R13 exists because collapsing
#      any of these sends the reader after the wrong thing.
#   3. The impact paragraph names the skill, the declared call, and that the
#      call will fail as written. It is composed from the record's own fields
#      and says nothing about phases: the declaration carries no phase, no call
#      site, and no capability, so a sentence naming one would be prose no data
#      source can generate and nothing can keep true.
#   4. Exactly one command on its own indented line, or an explicit no-route
#      statement.
#   5. Off-PATH blocks say "nothing needs installing" in the first line and are
#      emitted before any other block, so an agent reading top-down cannot
#      reinstall a tool it already has. The block ends by saying so again,
#      because the failure this prevents is an agent that read only the remedy.
#   6. Surface-gap blocks list what the level does advertise. The probe already
#      parsed the list, and it is what turns "wrong subcommand" into a fixable
#      observation.
#   7. Nothing points at a second run. A block is complete on first emission:
#      there is no verbose mode, no follow-up command, and no suggestion to run
#      anything again.
# ---------------------------------------------------------------------------

# preflight_emit_unresolvable <skill> <tool> <status> <path>
#
# The three postures that never reach a probe: off PATH, absent, and resolution
# refused. Ordering is the caller's -- the entry point runs an off-PATH pass
# before the rest.
preflight_emit_unresolvable() {
    local skill="$1" tool="$2" status="$3" path="$4"

    preflight_report_separator

    case "$status" in
        offpath)
            preflight_report_wrap "shirabe /$skill: prerequisite not met, and nothing needs installing."
            printf '\n'
            if preflight_report_path_ok "$path"; then
                preflight_report_wrap "$tool is installed at $path but is not on this shell's PATH. $(preflight_report_checked "PATH first")"
            else
                preflight_report_wrap "$tool is installed under one of the checked roots but is not on this shell's PATH. Its path is not rendered here: it carries characters this report does not print. $(preflight_report_checked "PATH first")"
            fi
            printf '\n'
            preflight_report_wrap "/$skill declares $tool. Every call to it will fail as written until PATH includes the directory above."
            printf '\n'
            preflight_report_wrap "Put it on PATH:"
            printf '\n'
            printf '  . ~/.tsuku/env\n'
            printf '\n'
            preflight_report_wrap "Do not reinstall $tool. It is already here."
            ;;
        absent)
            preflight_report_wrap "shirabe /$skill: prerequisite not met."
            printf '\n'
            preflight_report_wrap "$tool is not installed on this host. $(preflight_report_checked "PATH")"
            printf '\n'
            preflight_report_wrap "/$skill declares $tool. Every call to it will fail as written."
            printf '\n'
            preflight_render_route "$tool" "install"
            ;;
        refused)
            preflight_report_wrap "shirabe /$skill: prerequisite not met."
            printf '\n'
            case "$path" in
                /*)
                    preflight_report_wrap "$tool resolves to a path inside the working directory and was not probed. This check does not run a binary that resolves under the directory it was invoked from: at skill load that directory may be a branch under review."
                    ;;
                *)
                    preflight_report_wrap "$tool resolves to something that is not an absolute path and was not probed. This check runs only an absolute path that lies outside the working directory."
                    ;;
            esac
            printf '\n'
            preflight_report_wrap "/$skill declares $tool. This report makes no claim about the surface $tool advertises, or about whether that call would work: the binary was never run."
            ;;
    esac
    return 0
}

# preflight_emit_surface_gap <skill> <tool> <path> <kind> <level> <missing> <advertised>
#
#   kind        subcommand | flag
#   level       the level whose advertised surface was read (`koto context`)
#   missing     the declared subcommand path, or the declared flag
#   advertised  the level's extracted token list
#
# Both gaps close on the same bound, and it is deliberately weaker than a
# confident upgrade instruction. This check reads one installed binary's
# advertised surface. There is no version-to-feature map anywhere in it, so it
# cannot say whether any *released* version carries the missing surface --
# `koto context remove` has never existed at any version, and a report that
# said "upgrade koto" and stopped would be sending a reader to reinstall a
# binary that was never going to help. Naming the other possibility is the
# honest bound on what a surface probe knows, and it keeps the block complete
# on first emission.
preflight_emit_surface_gap() {
    local skill="$1" tool="$2" path="$3" kind="$4" level="$5" missing="$6" advertised="$7"
    local where

    preflight_report_separator

    if preflight_report_path_ok "$path"; then
        where="resolves at $path"
    else
        where="resolves to a path this report will not render"
    fi

    preflight_report_wrap "shirabe /$skill: prerequisite not met."
    printf '\n'

    if [ "$kind" = "subcommand" ]; then
        preflight_report_wrap "$tool $where and runs, but it does not have the subcommand \`$missing\`. The tool is installed and working; only this part of its surface is absent."
        printf '\n'
        preflight_report_advertises "$level" commands "$advertised"
        printf '\n'
        preflight_report_wrap "/$skill declares \`$missing\`. That call will fail as written, exiting 2 with an unrecognized-subcommand error."
    else
        preflight_report_wrap "$tool $where and has the subcommand \`$level\`, but that subcommand does not advertise the flag $missing. The tool is installed and the subcommand exists; only this flag is absent."
        printf '\n'
        preflight_report_advertises "$level" flags "$advertised"
        printf '\n'
        preflight_report_wrap "/$skill declares \`$level $missing\`. That call will fail as written."
    fi
    printf '\n'

    preflight_render_route "$tool" "update"
    printf '\n'

    preflight_report_wrap "This check reads the installed binary's advertised surface and nothing else. It cannot tell you whether any released $tool has \`$missing\`. If the newest build still does not, the call site is wrong and needs changing -- the binary is not the problem."
    return 0
}

# preflight_emit_inconclusive <skill> <tool> <level> <reason>
#
# A probe that hit the wall-clock budget, the byte cap, or a help page this
# extractor cannot read establishes nothing about the surface, so none of them
# may be reported as a missing subcommand or a missing flag. The block names
# the tool, says the probe did not complete, and stops. A slow binary that
# could fabricate a finding here would be worse than no check at all.
preflight_emit_inconclusive() {
    local skill="$1" tool="$2" level="$3" reason="$4"
    local why budget="${PREFLIGHT_PROBE_BUDGET-2}" cap="${PREFLIGHT_PROBE_CAP-65536}"

    case "$reason" in
        timeout)    why="did not finish within the ${budget}-second budget this check gives it" ;;
        overcap)    why="wrote more than $cap bytes, which is more than this check reads" ;;
        unreadable) why="printed help this check cannot read: it carries neither a Commands nor an Options block at the depths a subcommand and a flag are defined at" ;;
        *)          why="produced nothing this check could read" ;;
    esac

    preflight_report_separator
    preflight_report_wrap "shirabe /$skill: prerequisite could not be checked."
    printf '\n'
    preflight_report_wrap "\`$level --help\` $why, so the probe did not complete. This report makes no claim about the surface $tool advertises: a probe that did not finish is not evidence that anything is missing."
    printf '\n'
    preflight_report_wrap "/$skill declares $tool. Whether that call works was not established here."
    return 0
}
