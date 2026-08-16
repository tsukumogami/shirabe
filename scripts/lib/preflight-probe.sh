#!/usr/bin/env bash
# preflight-probe.sh -- read the surface a resolved tool advertises, under a
# wall-clock budget, and report the two surface gaps.
#
# Sourced by scripts/skill-preflight.sh after the plugin root has been
# validated and after preflight-read.sh and preflight-resolve.sh. It defines
# preflight_check_surface, which the entry point calls for every in-scope
# record whose tool resolved `present` -- the `always` records on a load-time
# run, the `mode:<name>` records on a `--mode <name>` run. The two runs share
# this function unchanged: a surface gap is a fact about the binary, and
# nothing here reads field four. Until this file exists the entry point
# defines a no-op with the honest posture -- nothing has read the binary's
# surface -- and sourcing this file replaces it.
#
# THREE THINGS THIS FILE OWNS
#
#   1. A bounded probe. `<path> [<subcommand>...] --help` with stdin closed, a
#      wall-clock budget, and an output cap. A probe that hits either bound is
#      INCONCLUSIVE, never a finding: a slow tool must not be able to fabricate
#      a missing subcommand.
#   2. A position-anchored extractor. clap names flags inside prose
#      descriptions, so a loose grep reports a flag as present at a level that
#      does not accept it -- `grep -q -- --issues` over `shirabe roadmap --help`
#      is a true match on `populate`'s description and a false claim about
#      `shirabe roadmap`. Only the `Commands:` and `Options:` regions are read,
#      and only at the indentation clap gives a definition line.
#   3. Memoization by level, so sibling subcommands cost nothing. `koto context
#      add`, `koto context get`, and `koto context exists` share one
#      `koto context --help`.
#
# THE WATCHDOG AND THE FILE DESCRIPTORS IT MUST RELEASE
#
# macOS ships no timeout(1), so the budget is a watchdog subshell: the probe is
# backgrounded, the watchdog sleeps the budget and sends TERM then KILL, and the
# parent waits. The trap is that the parent captures the probe's stdout through
# a pipe, and a subshell inherits every open descriptor. A watchdog that keeps
# the capture pipe open is a second writer, so the parent's read does not reach
# EOF until the watchdog exits -- which is to say, until the whole budget has
# elapsed, on every probe, however fast the binary is. Measured on this host
# with the watchdog left as-inherited: 2.017s on a `shirabe --help` that costs
# 3ms, and 2.046s against this very file with the release line commented out --
# which at nine probes is roughly 18s added to a /work-on load. The watchdog
# therefore runs `exec >/dev/null 2>&1` as its first statement, before it
# sleeps, and preflight_probe_returns_at_call_speed asserts the fast path is
# fast. A test that only asks whether a hung binary times out passes with the
# defect present, because the defect makes everything time out.
#
# Releasing the descriptors is necessary and not sufficient. A probe that
# forks -- a shell wrapper whose `sleep` outlives the TERM sent to its parent --
# leaves a grandchild holding the same capture pipe, and the parent blocks on it
# for as long as the grandchild lives, with the descriptors released and the
# probe itself correctly killed: 30.019s against a fixture whose only content is
# `sleep 30`, and 184.998s against one that sleeps longer, where the number is
# just when the measurement gave up and killed the child by hand. The outcome
# reads `timeout` in both, which is exactly why the wall clock is the assertion
# and the outcome is not. So the probe is started under `set -m`, which puts it
# in its own process group, and the watchdog signals the group rather than the
# process. Same fixture, same budget: 2.050s, and no `sleep` survives the run.
# The group signal is used only when `ps` confirms the group id is the probe's
# own pid, and falls back to signalling the process otherwise, so a platform
# that declines job control degrades to the release-only behaviour rather than
# to signalling a process group that belongs to someone else.
#
# WHAT IS CAPTURED
#
# Only stdout is read. Stderr is given its own descriptor and discarded at the
# source: it is never merged into the stream the extractor parses, and the
# report never echoes it -- that is an invariant of the design, not a
# preference, because stderr is the one channel where a tool writes free-form
# text about its own failure. Keeping those bytes in a variable would create a
# thing that must never be printed, sitting next to the thing that is printed.
# The separation is realized as separate-and-discard, and
# preflight_probe_never_reads_stderr holds it.
#
# The probe only ever appends `--help`, and it never runs a declared
# subcommand: the path to `koto context add` is verified by reading what
# `koto context --help` advertises, not by running `add`.
#
# bash 3.2 floor throughout: no `declare -A` (hence PROBE_KEYS/PROBE_DATA
# below), no namerefs, no mapfile, no `${var^^}`, no `[[ -v ]]`.

if [ "${PREFLIGHT_PROBE_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_PROBE_SOURCED=1

# Byte semantics, not collation semantics. The extractor's character classes --
# `[[:cntrl:]]`, the C1 range, and the `[@-~]` that ends an ANSI CSI sequence --
# are ranges over byte values, and under a UTF-8 locale a glob range is
# collation-ordered instead: measured, `  --<ESC>[1mbold<ESC>[0m-flag` loses its
# flag entirely under en_US.UTF-8 and yields it correctly under C. The entry
# point already exports LC_ALL=C, so this is a no-op there; it is here so the
# file does not silently depend on a caller that might not.
LC_ALL=C
export LC_ALL

# Defined by preflight-read.sh, which is sourced first. Defaulted here so this
# file does not silently depend on that order.
: "${PREFLIGHT_TAB:=$(printf '\t')}"
: "${PREFLIGHT_NL:=
}"

# ---------------------------------------------------------------------------
# Bounds
# ---------------------------------------------------------------------------

# Wall-clock budget per probe, in seconds. SHIRABE_PREFLIGHT_BUDGET overrides
# it; the value reaches `sleep` as an argument, so it is allowlisted first and
# a non-conforming value falls back to the default rather than being passed on.
PREFLIGHT_PROBE_BUDGET=2

preflight_probe_set_budget() {
    local v="${SHIRABE_PREFLIGHT_BUDGET-}"
    [ -n "$v" ] || return 0
    [ "${#v}" -le 8 ] || return 0
    case "$v" in
        *[!0-9.]*|.*|*.|*.*.*) return 0 ;;
    esac
    PREFLIGHT_PROBE_BUDGET="$v"
    return 0
}
preflight_probe_set_budget

# Seconds between TERM and KILL. A `sleep` that rejects a fractional argument
# falls back to a whole second; the watchdog's stderr is closed, so the
# rejection is not printed.
PREFLIGHT_PROBE_GRACE=0.2

# The two external programs a bounded probe needs: `sleep` for the watchdog and
# `head` for the byte cap. Both are resolved lazily, on the first probe, so a
# declaration that names no subcommand and no flag pays nothing for them, and
# both are looked for at their standard absolute locations before `command -v`
# is consulted -- PATH is the untrusted thing this check was written around, and
# a `.` entry in it should not decide which `head` runs.
#
# If either is missing the surface check is skipped in silence. Skipping is not
# a preference: an unbounded probe would break the never-block promise, and a
# block saying so on every load would put bytes on a satisfied host for a
# condition the reader cannot act on from a skill body.
#
# `ps` is optional and used for one thing only: confirming, before the watchdog
# signals a process group, that the group id really is the probe's own pid. If
# job control were unavailable the backgrounded probe would sit in this shell's
# group instead, and a bare `kill -- -PID` would then signal whatever unrelated
# group happens to carry that number. Without `ps` the watchdog signals the
# process alone, which is the conservative degradation: a forking probe's child
# may outlive it, but nothing else is ever signalled.
PREFLIGHT_PROBE_HELPERS=""   # unresolved | ok | missing
PREFLIGHT_PROBE_SLEEP=""
PREFLIGHT_PROBE_HEAD=""
PREFLIGHT_PROBE_PS=""

preflight_probe_find_helper() {
    local name="$1" p
    for p in "/bin/$name" "/usr/bin/$name"; do
        if [ -x "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    p=$(command -v "$name" 2>/dev/null) || p=""
    case "$p" in
        /*)
            printf '%s' "$p"
            return 0
            ;;
    esac
    return 1
}

preflight_probe_helpers_ready() {
    [ "$PREFLIGHT_PROBE_HELPERS" = "ok" ] && return 0
    [ "$PREFLIGHT_PROBE_HELPERS" = "missing" ] && return 1
    PREFLIGHT_PROBE_HELPERS="missing"
    PREFLIGHT_PROBE_SLEEP=$(preflight_probe_find_helper sleep) || return 1
    PREFLIGHT_PROBE_HEAD=$(preflight_probe_find_helper head) || return 1
    PREFLIGHT_PROBE_PS=$(preflight_probe_find_helper ps) || PREFLIGHT_PROBE_PS=""
    PREFLIGHT_PROBE_HELPERS="ok"
    return 0
}

# preflight_probe_watchdog <pid>
#
# Sleeps the budget, then TERM and KILL. Runs as a subshell of the capture
# group, which is why its first statement releases the inherited descriptors:
# see the header. Signals the process group only when the group id is confirmed
# to be the probe's own pid.
preflight_probe_watchdog() {
    local pid="$1" pgid="" target
    exec >/dev/null 2>&1
    "$PREFLIGHT_PROBE_SLEEP" "$PREFLIGHT_PROBE_BUDGET"

    if [ -n "$PREFLIGHT_PROBE_PS" ]; then
        pgid=$("$PREFLIGHT_PROBE_PS" -o pgid= -p "$pid" 2>/dev/null) || pgid=""
        pgid="${pgid//[[:space:]]/}"
    fi
    if [ -n "$pgid" ] && [ "$pgid" = "$pid" ]; then
        target="-$pid"
    else
        target="$pid"
    fi

    kill -TERM "$target" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    "$PREFLIGHT_PROBE_SLEEP" "$PREFLIGHT_PROBE_GRACE" || "$PREFLIGHT_PROBE_SLEEP" 1
    kill -KILL "$target" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
    return 0
}

# Output cap in bytes. One byte more than this is read, which is what makes a
# capped read distinguishable from an exactly-full one.
PREFLIGHT_PROBE_CAP=65536

# Longest token rendered, and the longest advertised list rendered before the
# literal `and N more` overflow.
PREFLIGHT_PROBE_TOKEN_MAX=64
PREFLIGHT_PROBE_LIST_MAX=24

# ---------------------------------------------------------------------------
# Memo
#
# Two newline-delimited strings, because bash 3.2 has no associative arrays and
# because the check writes nothing to disk. The names are the design's.
#
#   PROBE_KEYS  one visited level key per line: the tool name and the
#               subcommand path joined by spaces (`koto`, `koto context`).
#   PROBE_DATA  one `key<TAB>tokens` line per visited level, where `tokens` is
#               the space-joined extracted subcommand and flag list. A flag is
#               distinguishable from a subcommand by its leading dash, which is
#               why one list is enough.
#
# Membership is a `case` glob against the key bracketed by newlines, an
# exact-line test rather than a substring one. The pattern is built from a key,
# and a key built from untrusted text would be a glob-injection hazard: keys are
# composed only of field one and field two of a declaration record, both of
# which passed the [A-Za-z0-9._-] allowlist in preflight-read.sh, so no glob
# metacharacter can enter the pattern.
#
# An inconclusive level is memoized too, as the single token
# `!inconclusive:<reason>`. The bang cannot collide with an extracted token --
# the extractor's allowlists exclude it -- and memoizing the outcome is what
# stops a hung binary from being probed once per record. The reason travels in
# the memo rather than in a global, because the global holds the outcome of the
# last probe actually run, which on a memo hit is some other level's.
# ---------------------------------------------------------------------------

PROBE_KEYS=""
PROBE_DATA=""

PREFLIGHT_PROBE_INCONCLUSIVE_TOKEN='!inconclusive:'

# One line per block already emitted, so a hung tool that seven records name
# produces one block rather than seven.
PROBE_EMITTED=""

# Outputs.
PREFLIGHT_PROBE_TEXT=""       # captured stdout of the last probe
PREFLIGHT_PROBE_OUTCOME=""    # ok | timeout | overcap | empty | unbounded
PREFLIGHT_PROBE_LINE=""       # last line passed through the control strip
PREFLIGHT_PROBE_TOKENS=""     # last extraction, space-joined
PREFLIGHT_LEVEL_TOKENS=""     # last level looked up, space-joined
PREFLIGHT_LEVEL_OK=0          # 1 when the last level lookup is usable
PREFLIGHT_LEVEL_REASON=""     # why not, when PREFLIGHT_LEVEL_OK is 0

# preflight_probe_once <token>
#
# True the first time a token is offered and false afterwards. Keys are built
# from allowlisted fields only, so the `case` pattern carries no glob
# metacharacter.
preflight_probe_once() {
    case "$PROBE_EMITTED" in
        *"$PREFLIGHT_NL$1$PREFLIGHT_NL"*) return 1 ;;
    esac
    PROBE_EMITTED="$PROBE_EMITTED$PREFLIGHT_NL$1$PREFLIGHT_NL"
    return 0
}

# ---------------------------------------------------------------------------
# The bounded probe
# ---------------------------------------------------------------------------

# preflight_probe_capture <path> [<arg>...]
#
# Runs `<path> [<arg>...] --help` and sets PREFLIGHT_PROBE_TEXT and
# PREFLIGHT_PROBE_OUTCOME. Never returns non-zero: an unusable probe is an
# outcome, not an error, because the caller's job is to say nothing about a
# surface it could not read.
preflight_probe_capture() {
    local path="$1"
    shift
    local cap=$(( PREFLIGHT_PROBE_CAP + 1 ))
    local status=0

    PREFLIGHT_PROBE_TEXT=""
    PREFLIGHT_PROBE_OUTCOME="empty"

    if ! preflight_probe_helpers_ready; then
        PREFLIGHT_PROBE_OUTCOME="unbounded"
        return 0
    fi

    PREFLIGHT_PROBE_TEXT=$(
        {
            # The group's own stderr, not the probe's: job control notices
            # ("Terminated: 15") are written here when the watchdog fires, and
            # they would land in the model's context ahead of the skill body.
            exec 2>/dev/null

            # Job control gives the probe its own process group, so the
            # watchdog can signal descendants that would otherwise keep the
            # capture pipe open. It is turned back off immediately: nothing
            # else in this group wants it.
            set -m
            "$path" "$@" --help </dev/null 2>/dev/null &
            _preflight_probe_pid=$!
            set +m

            # The subshell whose first statement releases both inherited
            # capture descriptors, before it blocks on the budget.
            preflight_probe_watchdog "$_preflight_probe_pid" &
            _preflight_probe_watchdog=$!

            wait "$_preflight_probe_pid"
            _preflight_probe_status=$?

            kill "$_preflight_probe_watchdog" 2>/dev/null
            wait "$_preflight_probe_watchdog" 2>/dev/null

            exit "$_preflight_probe_status"
        } | "$PREFLIGHT_PROBE_HEAD" -c "$cap"
        # The pipeline's status is head's; the probe's is the one that says
        # whether the watchdog fired.
        exit "${PIPESTATUS[0]}"
    ) || status=$?

    if [ "${#PREFLIGHT_PROBE_TEXT}" -ge "$PREFLIGHT_PROBE_CAP" ]; then
        PREFLIGHT_PROBE_TEXT=""
        PREFLIGHT_PROBE_OUTCOME="overcap"
        return 0
    fi

    case "$status" in
        0)
            if [ -n "$PREFLIGHT_PROBE_TEXT" ]; then
                PREFLIGHT_PROBE_OUTCOME="ok"
            else
                PREFLIGHT_PROBE_OUTCOME="empty"
            fi
            ;;
        137|143)
            # KILL or TERM: the watchdog fired.
            PREFLIGHT_PROBE_TEXT=""
            PREFLIGHT_PROBE_OUTCOME="timeout"
            ;;
        141)
            # SIGPIPE: the reader stopped at the cap and the writer noticed.
            PREFLIGHT_PROBE_TEXT=""
            PREFLIGHT_PROBE_OUTCOME="overcap"
            ;;
        *)
            # A tool that prints its help and exits non-zero is unusual but
            # working, and reporting it would put bytes on a satisfied host's
            # load path. A non-zero exit with nothing on stdout is the case
            # nothing can be concluded from.
            if [ -n "$PREFLIGHT_PROBE_TEXT" ]; then
                PREFLIGHT_PROBE_OUTCOME="ok"
            else
                PREFLIGHT_PROBE_TEXT=""
                PREFLIGHT_PROBE_OUTCOME="empty"
            fi
            ;;
    esac

    return 0
}

# ---------------------------------------------------------------------------
# The extractor
# ---------------------------------------------------------------------------

# preflight_probe_strip_controls <line>  ->  PREFLIGHT_PROBE_LINE
#
# ANSI CSI sequences first, then every C0, C1, and DEL code point, so an escape
# sequence cannot survive by hiding inside an otherwise-conforming token. Real
# clap output on a pipe carries none of these, so the common path is one `case`
# per line and no rewriting at all.
preflight_probe_strip_controls() {
    local s="$1" pre rest
    case "$s" in
        *[[:cntrl:]]*|*[$'\200'-$'\237']*) ;;
        *)
            PREFLIGHT_PROBE_LINE="$s"
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
    PREFLIGHT_PROBE_LINE="$s"
    return 0
}

# preflight_probe_valid_command_token <token>
#
# One advertised subcommand name: [A-Za-z0-9._-]+, at most
# PREFLIGHT_PROBE_TOKEN_MAX bytes, no leading dash. A token that does not match
# is dropped, never sanitized -- a sanitized token would be a claim about a
# surface that does not exist.
preflight_probe_valid_command_token() {
    local t="${1-}"
    case "$t" in
        ''|-*) return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    [ "${#t}" -le "$PREFLIGHT_PROBE_TOKEN_MAX" ] || return 1
    return 0
}

# preflight_probe_valid_flag_token <token>
#
# One advertised flag: --?[A-Za-z0-9][A-Za-z0-9-]*, at most
# PREFLIGHT_PROBE_TOKEN_MAX bytes. Same alphabet the declaration reader
# enforces on field three, so a declared flag and an advertised one are
# comparable as plain strings.
preflight_probe_valid_flag_token() {
    local t="${1-}" rest
    [ "${#t}" -le "$PREFLIGHT_PROBE_TOKEN_MAX" ] || return 1
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

# preflight_probe_extract <help-text>  ->  PREFLIGHT_PROBE_TOKENS
#
# The layout rule, stated rather than grepped.
#
#   Section. A line with no leading space that begins `Commands:` opens the
#   command region and one that begins `Options:` opens the option region; any
#   other unindented non-blank line closes whichever region is open. Blank
#   lines are skipped rather than treated as terminators, since clap has been
#   known to separate entries with one.
#
#   Depth. A definition line carries 2 to 6 leading spaces. A line carrying 8
#   or more is a wrapped description and contributes nothing -- that is the
#   `shirabe roadmap populate` layout, where `--milestone <MILESTONE>` sits at
#   6 and its description sits at 10 on the next line. 1 and 7 belong to
#   neither layout and are skipped.
#
#   Command lines. The advertised name is the first whitespace-delimited token
#   after the indent.
#
#   Option lines. Every whitespace- or comma-delimited token up to the first
#   run of two or more spaces is a candidate flag; everything after that run is
#   description text. This is the rule a literal first-token reading gets
#   wrong: `  -h, --help  Print help` starts with `-h,`, and dropping the rest
#   of the region would lose `--help`, which is the form a declaration names.
#   Non-flag tokens inside the region -- the `<FROM_FILE>` of
#   `--from-file <FROM_FILE>` -- fail the allowlist and are dropped.
#
# Ordering is the order clap printed, which is the order the report lists.
preflight_probe_extract() {
    local text="$1"
    local line rest tok region indent out=""

    PREFLIGHT_PROBE_TOKENS=""
    region="none"

    while IFS= read -r line || [ -n "$line" ]; do
        preflight_probe_strip_controls "$line"
        line="$PREFLIGHT_PROBE_LINE"

        [ -n "$line" ] || continue

        indent=0
        rest="$line"
        while [ "$indent" -lt 8 ]; do
            case "$rest" in
                ' '*)
                    rest="${rest# }"
                    indent=$(( indent + 1 ))
                    ;;
                *) break ;;
            esac
        done

        if [ "$indent" -eq 0 ]; then
            case "$line" in
                Commands:*) region="commands" ;;
                Options:*)  region="options" ;;
                *)          region="none" ;;
            esac
            continue
        fi

        [ "$region" = "none" ] && continue
        [ -n "$rest" ] || continue
        [ "$indent" -ge 2 ] || continue
        [ "$indent" -le 6 ] || continue

        if [ "$region" = "commands" ]; then
            tok="${rest%% *}"
            if preflight_probe_valid_command_token "$tok"; then
                out="$out $tok"
            fi
            continue
        fi

        # Option region: cut at the first run of two or more spaces, then split
        # what is left on spaces and commas.
        rest="${rest%%"  "*}"
        rest="${rest//,/ }"
        while [ -n "$rest" ]; do
            tok="${rest%% *}"
            if [ "$tok" = "$rest" ]; then
                rest=""
            else
                rest="${rest#* }"
            fi
            [ -n "$tok" ] || continue
            if preflight_probe_valid_flag_token "$tok"; then
                out="$out $tok"
            fi
        done
    done <<<"$text"

    PREFLIGHT_PROBE_TOKENS="${out# }"
    return 0
}

# ---------------------------------------------------------------------------
# Levels
# ---------------------------------------------------------------------------

# preflight_probe_advertises <token-list> <token>
#
# Membership in a space-joined list. Both sides passed an allowlist, so the
# `case` pattern carries no glob metacharacter.
preflight_probe_advertises() {
    case " $1 " in
        *" $2 "*) return 0 ;;
    esac
    return 1
}

# preflight_probe_level <key> <path> [<arg>...]
#
# Sets PREFLIGHT_LEVEL_TOKENS, PREFLIGHT_LEVEL_OK, and PREFLIGHT_LEVEL_REASON
# for one level, probing it at most once per run.
preflight_probe_level() {
    local key="$1" path="$2"
    shift 2
    local k v

    PREFLIGHT_LEVEL_TOKENS=""
    PREFLIGHT_LEVEL_OK=0
    PREFLIGHT_LEVEL_REASON=""

    case "$PROBE_KEYS" in
        *"$PREFLIGHT_NL$key$PREFLIGHT_NL"*)
            while IFS="$PREFLIGHT_TAB" read -r k v; do
                if [ "$k" = "$key" ]; then
                    case "$v" in
                        "$PREFLIGHT_PROBE_INCONCLUSIVE_TOKEN"*)
                            PREFLIGHT_LEVEL_TOKENS=""
                            PREFLIGHT_LEVEL_OK=0
                            PREFLIGHT_LEVEL_REASON="${v#$PREFLIGHT_PROBE_INCONCLUSIVE_TOKEN}"
                            ;;
                        *)
                            PREFLIGHT_LEVEL_TOKENS="$v"
                            PREFLIGHT_LEVEL_OK=1
                            ;;
                    esac
                    return 0
                fi
            done <<<"$PROBE_DATA"
            ;;
    esac

    preflight_probe_capture "$path" "$@"

    if [ "$PREFLIGHT_PROBE_OUTCOME" = "ok" ]; then
        preflight_probe_extract "$PREFLIGHT_PROBE_TEXT"
        if [ -z "$PREFLIGHT_PROBE_TOKENS" ]; then
            # The help text parsed to nothing at all. Every clap level
            # advertises at least `-h, --help`, so an empty extraction means
            # the output is not in the layout this extractor reads -- a
            # hand-rolled `--help`, a man-page-shaped one, a localized one.
            # That is not evidence that a subcommand or a flag is absent, and
            # reporting it as one would fabricate a finding against every tool
            # that does not use clap.
            PREFLIGHT_LEVEL_TOKENS=""
            PREFLIGHT_LEVEL_OK=0
            PREFLIGHT_LEVEL_REASON="unreadable"
            v="${PREFLIGHT_PROBE_INCONCLUSIVE_TOKEN}unreadable"
        else
            PREFLIGHT_LEVEL_TOKENS="$PREFLIGHT_PROBE_TOKENS"
            PREFLIGHT_LEVEL_OK=1
            v="$PREFLIGHT_PROBE_TOKENS"
        fi
    else
        PREFLIGHT_LEVEL_TOKENS=""
        PREFLIGHT_LEVEL_OK=0
        PREFLIGHT_LEVEL_REASON="$PREFLIGHT_PROBE_OUTCOME"
        v="$PREFLIGHT_PROBE_INCONCLUSIVE_TOKEN$PREFLIGHT_PROBE_OUTCOME"
    fi

    PROBE_KEYS="$PROBE_KEYS$PREFLIGHT_NL$key$PREFLIGHT_NL"
    PROBE_DATA="$PROBE_DATA$key$PREFLIGHT_TAB$v$PREFLIGHT_NL"
    return 0
}

# ---------------------------------------------------------------------------
# Rendering
#
# The blocks below are the probe helper's own fallbacks, defined only if a
# reporter helper has not already defined them, the same way the entry point
# guards preflight_emit_unresolvable. scripts/lib/preflight-report.sh takes the
# rendering over -- including the install-route line these versions cannot
# resolve -- without this file changing.
# ---------------------------------------------------------------------------

# preflight_probe_wrap <text>
#
# Delegates to the entry point's wrapper when there is one, so the blocks this
# file emits and the blocks the entry point emits wrap identically. Standalone
# -- in the test harness, or under a future caller -- it prints the line as-is
# rather than growing a second wrapping implementation.
preflight_probe_wrap() {
    if declare -f preflight_wrap >/dev/null 2>&1; then
        preflight_wrap "$1"
    else
        printf '%s\n' "$1"
    fi
}

preflight_probe_separator() {
    if declare -f preflight_block_separator >/dev/null 2>&1; then
        preflight_block_separator
    fi
}

# preflight_probe_render_list <kind> <token-list>
#
# The advertised list, filtered and bounded: `flags` keeps the dash-led tokens
# and `commands` keeps the rest, capped at PREFLIGHT_PROBE_LIST_MAX items with
# a literal `and N more` overflow. Prints nothing when the level advertises
# nothing of that kind.
preflight_probe_render_list() {
    local kind="$1" list="$2" tok rest out="" shown=0 extra=0

    # Split by hand rather than with an unquoted expansion: the tokens are
    # allowlisted and carry no glob metacharacter, but relying on that to keep
    # pathname expansion harmless is a dependency nobody would maintain.
    rest="$list"
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
                ;;
            commands)
                case "$tok" in -*) continue ;; esac
                ;;
        esac
        if [ "$shown" -ge "$PREFLIGHT_PROBE_LIST_MAX" ]; then
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

# preflight_probe_route_line <tool>
#
# The one command, when route resolution is available. Without it the block
# says it has no command rather than guessing one -- the same posture the entry
# point takes for an absent tool.
preflight_probe_route_line() {
    local tool="$1"
    if declare -f preflight_render_route >/dev/null 2>&1; then
        preflight_probe_wrap "Update to the newest $tool:"
        printf '\n'
        preflight_render_route "$tool"
    else
        preflight_probe_wrap "Install-route resolution is not available in this check, so this report gives no command. Update to the newest $tool by whatever means this host supports."
    fi
}

# preflight_emit_surface_gap <skill> <tool> <path> <kind> <level> <missing> <advertised>
#
#   kind       subcommand | flag
#   level      the level whose advertised surface was read (`koto context`)
#   missing    the declared subcommand path or the declared flag
#   advertised the level's extracted token list
#
# Both gaps close on the same bound, and it is deliberately weaker than a
# confident upgrade instruction: this check reads the installed binary's
# advertised surface and cannot say whether any released version carries the
# missing surface. `koto context remove` has never existed at any version, and
# the confident wording would send a reader to reinstall a binary that was
# never going to help.
if ! declare -f preflight_emit_surface_gap >/dev/null 2>&1; then
preflight_emit_surface_gap() {
    local skill="$1" tool="$2" path="$3" kind="$4" level="$5" missing="$6" advertised="$7"
    local where listing

    preflight_probe_separator

    if declare -f preflight_valid_path >/dev/null 2>&1 && preflight_valid_path "$path"; then
        where="resolves at $path"
    else
        where="resolves to a path this report will not render"
    fi

    preflight_probe_wrap "shirabe /$skill: prerequisite not met."
    printf '\n'

    if [ "$kind" = "subcommand" ]; then
        listing=$(preflight_probe_render_list commands "$advertised")
        preflight_probe_wrap "$tool $where and runs, but it does not have the subcommand \`$missing\`. The tool is installed and working; only this part of its surface is absent."
        printf '\n'
        if [ -n "$listing" ]; then
            preflight_probe_wrap "\`$level\` advertises:"
            printf '  %s\n' "$listing"
        else
            preflight_probe_wrap "\`$level\` advertises no subcommand this check can render."
        fi
    else
        listing=$(preflight_probe_render_list flags "$advertised")
        preflight_probe_wrap "$tool $where and has the subcommand \`$level\`, but that subcommand does not advertise the flag $missing. The tool is installed and the subcommand exists; only this flag is absent."
        printf '\n'
        if [ -n "$listing" ]; then
            preflight_probe_wrap "\`$level\` advertises:"
            printf '  %s\n' "$listing"
        else
            preflight_probe_wrap "\`$level\` advertises no flag this check can render."
        fi
    fi

    printf '\n'
    if [ "$kind" = "subcommand" ]; then
        preflight_probe_wrap "/$skill declares \`$missing\`. That call will fail as written, exiting 2 with an unrecognized-subcommand error."
    else
        preflight_probe_wrap "/$skill declares \`$level $missing\`. That call will fail as written."
    fi
    printf '\n'

    preflight_probe_route_line "$tool"
    printf '\n'

    preflight_probe_wrap "This check reads the installed binary's advertised surface and nothing else. It cannot tell you whether any released $tool has \`$missing\`. If the newest build still does not, the call site is wrong and needs changing -- the binary is not the problem."
    return 0
}
fi

# preflight_emit_inconclusive <skill> <tool> <level> <reason>
#
# Neither bound establishes anything about the surface, so neither may be
# reported as a missing subcommand or a missing flag. The block names the tool,
# says the probe did not complete, and stops. A slow binary that could
# fabricate a finding here would be worse than no check at all.
if ! declare -f preflight_emit_inconclusive >/dev/null 2>&1; then
preflight_emit_inconclusive() {
    local skill="$1" tool="$2" level="$3" reason="$4"
    local why

    case "$reason" in
        timeout)    why="did not finish within the ${PREFLIGHT_PROBE_BUDGET}-second budget this check gives it" ;;
        overcap)    why="wrote more than $PREFLIGHT_PROBE_CAP bytes, which is more than this check reads" ;;
        unreadable) why="printed help this check cannot read: it carries neither a Commands nor an Options block at the depths a subcommand and a flag are defined at" ;;
        *)          why="produced nothing this check could read" ;;
    esac

    preflight_probe_separator
    preflight_probe_wrap "shirabe /$skill: prerequisite could not be checked."
    printf '\n'
    preflight_probe_wrap "\`$level --help\` $why, so the probe did not complete. This report makes no claim about the surface $tool advertises: a probe that did not finish is not evidence that anything is missing."
    printf '\n'
    preflight_probe_wrap "/$skill declares $tool. Whether that call works was not established here."
    return 0
}
fi

# ---------------------------------------------------------------------------
# The entry point the check calls
# ---------------------------------------------------------------------------

# preflight_check_surface <skill> <tool> <sub> <flags> <path>
#
# One `--help` per subcommand level visited, plus one per leaf carrying a
# declared flag. Verifying `koto context add` costs `koto --help` and
# `koto context --help`: the last token is checked against what its parent
# advertises rather than by probing it, so a record with no declared flag never
# probes its own leaf. That is the rule the nine-call figure for /work-on comes
# from, and it is why `koto context get` and `koto context exists` cost nothing
# after `koto context add`.
#
# The path is the one preflight_resolve_tool vetted: absolute, executable, and
# outside the working directory. This function executes that path and never the
# bare tool name.
preflight_check_surface() {
    local skill="$1" tool="$2" sub="$3" flags="$4" path="$5"
    local key="$tool" rest tok flag flagrest
    local args
    args=()

    # A tool-only record declares no surface, so there is nothing to read.
    if { [ "$sub" = "-" ] || [ -z "$sub" ]; } && { [ "$flags" = "-" ] || [ -z "$flags" ]; }; then
        return 0
    fi

    if [ "$sub" != "-" ] && [ -n "$sub" ]; then
        rest="$sub"
        while [ -n "$rest" ]; do
            tok="${rest%% *}"
            if [ "$tok" = "$rest" ]; then
                rest=""
            else
                rest="${rest#* }"
            fi
            [ -n "$tok" ] || continue

            preflight_probe_level "$key" "$path" ${args[@]+"${args[@]}"}
            if [ "$PREFLIGHT_LEVEL_OK" -ne 1 ]; then
                if [ "$PREFLIGHT_LEVEL_REASON" != "unbounded" ] &&
                   preflight_probe_once "inconclusive $key"; then
                    preflight_emit_inconclusive "$skill" "$tool" "$key" "$PREFLIGHT_LEVEL_REASON"
                fi
                return 0
            fi
            if ! preflight_probe_advertises "$PREFLIGHT_LEVEL_TOKENS" "$tok"; then
                if preflight_probe_once "subcommand $tool $sub"; then
                    preflight_emit_surface_gap "$skill" "$tool" "$path" "subcommand" \
                        "$key" "$tool $sub" "$PREFLIGHT_LEVEL_TOKENS"
                fi
                return 0
            fi

            args[${#args[@]}]="$tok"
            key="$key $tok"
        done
    fi

    [ "$flags" = "-" ] && return 0
    [ -n "$flags" ] || return 0

    preflight_probe_level "$key" "$path" ${args[@]+"${args[@]}"}
    if [ "$PREFLIGHT_LEVEL_OK" -ne 1 ]; then
        if [ "$PREFLIGHT_LEVEL_REASON" != "unbounded" ] &&
           preflight_probe_once "inconclusive $key"; then
            preflight_emit_inconclusive "$skill" "$tool" "$key" "$PREFLIGHT_LEVEL_REASON"
        fi
        return 0
    fi

    flagrest="$flags"
    while [ -n "$flagrest" ]; do
        flag="${flagrest%%,*}"
        if [ "$flag" = "$flagrest" ]; then
            flagrest=""
        else
            flagrest="${flagrest#*,}"
        fi
        [ -n "$flag" ] || continue
        if ! preflight_probe_advertises "$PREFLIGHT_LEVEL_TOKENS" "$flag"; then
            if preflight_probe_once "flag $key $flag"; then
                preflight_emit_surface_gap "$skill" "$tool" "$path" "flag" \
                    "$key" "$flag" "$PREFLIGHT_LEVEL_TOKENS"
            fi
        fi
    done

    return 0
}
