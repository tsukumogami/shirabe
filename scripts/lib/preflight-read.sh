#!/usr/bin/env bash
# preflight-read.sh -- parse and validate the tab-separated declaration files
# the load-time prerequisite check reads.
#
# Sourced by scripts/skill-preflight.sh. Never executed directly, and never
# sourced before the plugin root has been validated: sourcing is code
# execution, and the root is where this file comes from.
#
# Two files are read here.
#
#   skills/<name>/requires.tsv   one skill's declaration, four fields per record
#   scripts/lib/tool-routes.tsv  the route table, six fields per record
#
# Both share the same line kinds. A line whose first non-blank character is `#`
# is a comment, a blank line is skipped, and every other line is a record whose
# field count is exact. Both carry a `#schema` first line compared literally, so
# a file written for a later schema fails loudly on an older reader rather than
# being half-understood.
#
# The character allowlists live here rather than only in CI because CI runs
# after the fact. A reviewer whose plugin root points at a pull-request checkout
# -- the normal developer configuration, since marketplace.json uses
# "source": "./" -- loads skills from that branch before any scan has run. The
# committed reader is the control on that path.
#
# Two rules about what a rejection is allowed to say, both deliberate:
#
#   A rejected field value is never echoed back. A value that failed the
#   allowlist is by definition outside the alphabet the report is filtered to,
#   and this text lands in the model's context ahead of the skill body. The
#   report names the line, the field, and the expectation, which is what an
#   author needs in order to fix it. The one exception is a tool name that
#   passed the allowlist and failed only the route-table membership test: that
#   value is inside the alphabet, and naming it is what makes the message
#   actionable.
#
#   A rejected record is reported, never silently dropped. A silent drop would
#   put a malformed record into the same zero-byte outcome as a satisfied one,
#   which is the blind spot this whole check is written against.
#
# Helpers that transform a string set a global rather than printing into a
# command substitution. Each `$(...)` is a fork, and the load path is budgeted
# in milliseconds against a fifteen-record declaration.
#
# Everything here is bash 3.2 compatible: no associative arrays, no namerefs,
# no mapfile, no [[ -v ]]. macOS ships bash 3.2.57 as /bin/bash and CI runs an
# explicit /bin/bash leg.

# Guard against double-sourcing.
if [ "${PREFLIGHT_READ_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_READ_SOURCED=1

PREFLIGHT_TAB=$(printf '\t')
PREFLIGHT_CR=$(printf '\r')
PREFLIGHT_NL='
'

# Newline-bracketed list of every tool name in the route table's first column.
# Membership is tested with a `case` glob against the name bracketed by
# newlines, which is an exact-line test rather than a substring one.
PREFLIGHT_ROUTE_TOOLS=""

# Outputs of the transform helpers below.
PREFLIGHT_STRIPPED=""
PREFLIGHT_COLLAPSED=""
PREFLIGHT_TABCOUNT=0

# preflight_strip <string>  ->  PREFLIGHT_STRIPPED
#
# Strips leading and trailing spaces, tabs, and carriage returns. Applied to a
# record line before the tab count is taken, so an editor that leaves a space
# next to the newline does not break the file, and so a CRLF checkout reads the
# same as a Unix one.
preflight_strip() {
    local s="$1"
    while [ -n "$s" ]; do
        case "$s" in
            ' '*|"$PREFLIGHT_TAB"*|"$PREFLIGHT_CR"*) s="${s#?}" ;;
            *) break ;;
        esac
    done
    while [ -n "$s" ]; do
        case "$s" in
            *' '|*"$PREFLIGHT_TAB"|*"$PREFLIGHT_CR") s="${s%?}" ;;
            *) break ;;
        esac
    done
    PREFLIGHT_STRIPPED="$s"
}

# preflight_tab_count <line>  ->  PREFLIGHT_TABCOUNT
#
# Every character that is not a tab is deleted and the remainder measured,
# which needs no external process.
preflight_tab_count() {
    local only_tabs="${1//[!$PREFLIGHT_TAB]/}"
    PREFLIGHT_TABCOUNT=${#only_tabs}
}

# preflight_collapse_spaces <string>  ->  PREFLIGHT_COLLAPSED
#
# Runs of spaces inside field two collapse to one, so `roadmap  populate` and
# `roadmap populate` name the same level. Whitespace is significant in field
# two only as a separator.
preflight_collapse_spaces() {
    local s="$1"
    while :; do
        case "$s" in
            *'  '*) s="${s//  / }" ;;
            *) break ;;
        esac
    done
    PREFLIGHT_COLLAPSED="$s"
}

# preflight_valid_name <value>
#
# The field-one alphabet: [A-Za-z0-9._-]+ with a first character that is not a
# dash. The leading-dash rejection is the security-relevant half of the rule --
# see preflight_valid_subcommand, where the same shape becomes an argv element
# ahead of --help.
preflight_valid_name() {
    case "${1-}" in
        ''|-*) return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

# preflight_valid_subcommand <value>
#
# `-` for a tool with an independent release cadence, which declares no
# subcommands, or space-separated tokens each passing preflight_valid_name.
#
# This is the field the leading-dash rule exists for. Field two is split on
# spaces into argv elements and appended before --help, so an unvalidated
# subcommand of `--version` or `-x` would reach the probed tool as a flag.
preflight_valid_subcommand() {
    local sub="${1-}" tok rest
    [ "$sub" = "-" ] && return 0
    [ -n "$sub" ] || return 1
    case "$sub" in
        ' '*|*' ') return 1 ;;
    esac
    rest="$sub"
    while [ -n "$rest" ]; do
        tok="${rest%% *}"
        if [ "$tok" = "$rest" ]; then
            rest=""
        else
            rest="${rest#* }"
        fi
        preflight_valid_name "$tok" || return 1
    done
    return 0
}

# preflight_valid_flag_token <token>
#
# One flag: --?[A-Za-z0-9][A-Za-z0-9-]*. Flags are never passed to a tool; they
# are compared against text the probe extracts. The allowlist is enforced
# anyway, because a flag reaches the report and because a memo key is built
# from it.
preflight_valid_flag_token() {
    local t="${1-}" rest
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

# preflight_valid_flags <value>
#
# `-` for none, or a comma-separated list with no spaces. There is no escaping
# mechanism: a flag whose own name contains a comma cannot be declared, and the
# allowlist makes that a rejected record rather than a silent mis-split.
preflight_valid_flags() {
    local flags="${1-}" tok rest
    [ "$flags" = "-" ] && return 0
    [ -n "$flags" ] || return 1
    case "$flags" in
        ,*|*,|*,,*) return 1 ;;
    esac
    rest="$flags"
    while [ -n "$rest" ]; do
        tok="${rest%%,*}"
        if [ "$tok" = "$rest" ]; then
            rest=""
        else
            rest="${rest#*,}"
        fi
        preflight_valid_flag_token "$tok" || return 1
    done
    return 0
}

# preflight_valid_when <value>
#
# `always` or `mode:<name>`. Every field is mandatory and `-` is not accepted
# here: an entry that forgets its mode marker must fail rather than silently
# become always-required.
preflight_valid_when() {
    local w="${1-}" name
    [ "$w" = "always" ] && return 0
    case "$w" in
        mode:*) ;;
        *) return 1 ;;
    esac
    name="${w#mode:}"
    case "$name" in
        ''|*[!a-z0-9-]*) return 1 ;;
    esac
    return 0
}

# preflight_tool_is_routed <tool>
#
# True when the tool appears in the route table's first column. Field one is
# rejected otherwise, so a declaration cannot introduce a new executable name
# without a reviewed edit to tool-routes.tsv.
#
# The caller must run the character allowlist first. The `case` pattern is
# built from the value, and a value carrying a glob metacharacter would match
# lines it is not.
preflight_tool_is_routed() {
    local tool="${1-}"
    [ -n "$PREFLIGHT_ROUTE_TOOLS" ] || return 1
    case "$PREFLIGHT_ROUTE_TOOLS" in
        *"$PREFLIGHT_NL$tool$PREFLIGHT_NL"*) return 0 ;;
    esac
    return 1
}

# preflight_check_schema <file> <expected-version>
#
# The first line, stripped, must equal `#schema<TAB><expected-version>`
# exactly. Comparing the whole line rather than parsing it is what makes the
# version token literal: a version bump is a deliberate, visible act.
#
# Prints nothing. Returns 1 on any mismatch; the caller owns the wording of the
# failure, because the two callers name different files.
preflight_check_schema() {
    local file="$1" want="$2" first
    IFS= read -r first <"$file" || first=""
    preflight_strip "$first"
    [ "$PREFLIGHT_STRIPPED" = "#schema$PREFLIGHT_TAB$want" ] || return 1
    return 0
}

# preflight_read_routes <routes-file>
#
# Populates PREFLIGHT_ROUTE_TOOLS from the route table. Reports malformed
# records on stderr and skips them. Returns 1 when the file cannot be read or
# its schema line is wrong, in which case the caller must not go on to validate
# declarations against an empty tool set -- every record would then be rejected
# for the wrong reason.
#
# Route *resolution* -- matching the OS column, running the probe verb, picking
# the winning record -- is not here. This function reads the column the
# declaration reader validates field one against, and enforces the two schema
# rules that make the table trustworthy: six fields, and a citation on any
# record whose probe is `never`, so a deliberately excluded route can never
# become an unexplained absence.
preflight_read_routes() {
    local file="$1"
    local line lineno=0 tabs tool route os probe command citation

    [ -r "$file" ] || return 1
    preflight_check_schema "$file" "tool-routes/v1" || return 1

    PREFLIGHT_ROUTE_TOOLS="$PREFLIGHT_NL"

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$(( lineno + 1 ))
        preflight_strip "$line"
        line="$PREFLIGHT_STRIPPED"
        [ -n "$line" ] || continue
        case "$line" in '#'*) continue ;; esac

        preflight_tab_count "$line"
        tabs=$PREFLIGHT_TABCOUNT
        if [ "$tabs" != "5" ]; then
            printf 'shirabe preflight: skipping tool-routes.tsv line %s: expected exactly 6 tab-separated fields (5 tabs), found %s.\n' \
                "$lineno" "$(( tabs + 1 ))" >&2
            continue
        fi

        IFS="$PREFLIGHT_TAB" read -r tool route os probe command citation <<<"$line"

        if ! preflight_valid_name "$tool"; then
            printf 'shirabe preflight: skipping tool-routes.tsv line %s, field 1 (tool): expected [A-Za-z0-9._-]+ with no leading dash.\n' \
                "$lineno" >&2
            continue
        fi
        case "$route" in
            ''|*[!a-z0-9-]*)
                printf 'shirabe preflight: skipping tool-routes.tsv line %s, field 2 (route): expected [a-z0-9-]+.\n' \
                    "$lineno" >&2
                continue
                ;;
        esac
        case "$os" in
            any|darwin|linux) ;;
            *)
                printf 'shirabe preflight: skipping tool-routes.tsv line %s, field 3 (os): expected any, darwin, or linux.\n' \
                    "$lineno" >&2
                continue
                ;;
        esac
        if [ "$probe" = "never" ] && { [ -z "$citation" ] || [ "$citation" = "-" ]; }; then
            printf 'shirabe preflight: skipping tool-routes.tsv line %s, field 6 (citation): mandatory and non-dash on a record whose probe is never.\n' \
                "$lineno" >&2
            continue
        fi
        if [ -z "$probe" ] || [ -z "$command" ] || [ -z "$citation" ]; then
            printf 'shirabe preflight: skipping tool-routes.tsv line %s: no field may be empty, and `-` is the explicit empty value.\n' \
                "$lineno" >&2
            continue
        fi

        preflight_tool_is_routed "$tool" && continue
        PREFLIGHT_ROUTE_TOOLS="$PREFLIGHT_ROUTE_TOOLS$tool$PREFLIGHT_NL"
    done <"$file"

    return 0
}

# preflight_read_declaration <skill> <declaration-file>
#
# Prints one validated record per line on stdout, tab-separated, four fields,
# field two space-collapsed. Prints skip reports on stderr. Returns 1 on a hard
# error -- an unreadable file or a wrong schema line -- having printed nothing
# on stdout.
#
# Fields are read with `IFS=$'\t' read -r tool sub flags when`, with the IFS
# assignment scoped to the read so it never leaks. Under the default IFS a
# two-word subcommand like `roadmap populate` splits and every multi-word
# record fails the four-field check.
preflight_read_declaration() {
    local skill="$1" file="$2"
    local line lineno=0 tabs tool sub flags when

    if [ ! -r "$file" ]; then
        printf 'shirabe /%s: the prerequisite declaration exists but cannot be read; the check was skipped.\n' \
            "$skill" >&2
        return 1
    fi
    if ! preflight_check_schema "$file" "skill-requires/v1"; then
        printf 'shirabe /%s: requires.tsv does not open with `#schema<TAB>skill-requires/v1`; no record was read and no prerequisite was checked.\n' \
            "$skill" >&2
        return 1
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$(( lineno + 1 ))
        preflight_strip "$line"
        line="$PREFLIGHT_STRIPPED"
        [ -n "$line" ] || continue
        case "$line" in '#'*) continue ;; esac

        preflight_tab_count "$line"
        tabs=$PREFLIGHT_TABCOUNT
        if [ "$tabs" != "3" ]; then
            printf 'shirabe /%s: skipping requires.tsv line %s: expected exactly 4 tab-separated fields (3 tabs), found %s.\n' \
                "$skill" "$lineno" "$(( tabs + 1 ))" >&2
            continue
        fi

        IFS="$PREFLIGHT_TAB" read -r tool sub flags when <<<"$line"

        preflight_strip "$sub"
        preflight_collapse_spaces "$PREFLIGHT_STRIPPED"
        sub="$PREFLIGHT_COLLAPSED"

        if ! preflight_valid_name "$tool"; then
            printf 'shirabe /%s: skipping requires.tsv line %s, field 1 (tool): expected [A-Za-z0-9._-]+ with no leading dash.\n' \
                "$skill" "$lineno" >&2
            continue
        fi
        if ! preflight_tool_is_routed "$tool"; then
            printf 'shirabe /%s: skipping requires.tsv line %s, field 1 (tool): `%s` does not appear in scripts/lib/tool-routes.tsv, which is the closed set of tool names a declaration may name.\n' \
                "$skill" "$lineno" "$tool" >&2
            continue
        fi
        if ! preflight_valid_subcommand "$sub"; then
            printf 'shirabe /%s: skipping requires.tsv line %s, field 2 (subcommand): expected `-` or space-separated tokens matching [A-Za-z0-9._-]+ with no leading dash.\n' \
                "$skill" "$lineno" >&2
            continue
        fi
        if ! preflight_valid_flags "$flags"; then
            printf 'shirabe /%s: skipping requires.tsv line %s, field 3 (flags): expected `-` or a comma-separated list of flags matching --?[A-Za-z0-9][A-Za-z0-9-]*.\n' \
                "$skill" "$lineno" >&2
            continue
        fi
        if ! preflight_valid_when "$when"; then
            printf 'shirabe /%s: skipping requires.tsv line %s, field 4 (when): expected `always` or `mode:<name>` with a name matching [a-z0-9-]+.\n' \
                "$skill" "$lineno" >&2
            continue
        fi

        printf '%s\t%s\t%s\t%s\n' "$tool" "$sub" "$flags" "$when"
    done <"$file"

    return 0
}
