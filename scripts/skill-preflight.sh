#!/usr/bin/env bash
# skill-preflight.sh -- the load-time prerequisite check for one shirabe skill.
#
# Usage: bash scripts/skill-preflight.sh <skill-name>
#
# Injected at column 0 in a skill body as:
#
#   !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> 2>&1 || true`
#
# It reads skills/<skill-name>/requires.tsv, resolves every tool the skill
# declares as always-required, and prints one plain-prose block per prerequisite
# that is not met. A fully satisfied declaration prints nothing at all -- zero
# bytes on stdout and on stderr, which is a rule a test asserts with `wc -c`
# rather than by inspection.
#
# THIS SCRIPT ALWAYS EXITS 0.
#
# That is the single most load-bearing property in the file. A non-zero exit
# from a command injected into a skill body aborts the entire skill invocation:
# the failure mode is not a missing report, it is a skill that will not load.
# So there is no `set -e` anywhere here, `set -u` is the only option set, every
# failure path prints and continues, and the last statement is an explicit
# `exit 0`. A missing, unreadable, or malformed input is a report, never a
# refusal.
#
# The interpreter is bash with a hard bash 3.2 floor. macOS ships 3.2.57 as
# /bin/bash and CI runs an explicit /bin/bash leg. No `declare -A`, no
# namerefs, no `mapfile`, no `${var^^}`, no `[[ -v ]]`.
#
# What this file owns and what it delegates:
#
#   here                      plugin-root resolution and validation, argument
#                             validation, posture dispatch, block rendering for
#                             the three unresolvable postures
#   lib/preflight-read.sh     the TSV readers and every character allowlist
#   lib/preflight-resolve.sh  command -v, the root list, the refusal rule
#   lib/preflight-probe.sh    surface probing (optional; absent until it lands)
#   lib/preflight-report.sh   route resolution and block rendering (optional)
#
# The two optional helpers are picked up when present and hooked through
# `declare -f`: preflight_check_surface for a resolved tool's advertised
# surface, and preflight_render_route for the one command an absent-tool block
# prints. Until they exist the corresponding text says what it does not know
# rather than guessing.

set -u

# Deterministic byte semantics for every character-class test below.
LC_ALL=C
export LC_ALL

PREFLIGHT_EXIT_NOTE="shirabe preflight: could not locate the plugin root, so no prerequisite was checked."

# ---------------------------------------------------------------------------
# Plugin root
#
# Prefer the harness-provided root, fall back to this script's own location one
# level up. Since the interpreter is bash, ${BASH_SOURCE[0]} is available; the
# `sh`-flavoured version of this fallback yields `dirname ""` -> `.` -> a
# $PWD-relative root, which is exactly what the threat model forbids, and the
# 127 that followed would be swallowed by the injected line's `|| true` with
# nobody learning anything.
#
# Whatever root is resolved is the directory the helpers are *sourced* from,
# and sourcing is code execution. So the root is validated before anything is
# sourced: absolute, a directory, and containing a readable plugin.json. Failing
# either test the script prints one line, sources nothing, and exits 0. A check
# that cannot find itself should say so rather than join the silent-failure set.
# ---------------------------------------------------------------------------

PREFLIGHT_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"

preflight_root_is_valid() {
    case "$PREFLIGHT_ROOT" in
        /*) ;;
        *) return 1 ;;
    esac
    [ -d "$PREFLIGHT_ROOT" ] || return 1
    # The manifest lives at .claude-plugin/plugin.json in this plugin's layout;
    # a root-level plugin.json is accepted too, since both are the marker that
    # says "this directory is the plugin".
    [ -r "$PREFLIGHT_ROOT/.claude-plugin/plugin.json" ] && return 0
    [ -r "$PREFLIGHT_ROOT/plugin.json" ] && return 0
    return 1
}

if ! preflight_root_is_valid; then
    printf '%s\n' "$PREFLIGHT_EXIT_NOTE"
    exit 0
fi

PREFLIGHT_LIB="$PREFLIGHT_ROOT/scripts/lib"

for _preflight_required in preflight-read.sh preflight-resolve.sh; do
    if [ ! -r "$PREFLIGHT_LIB/$_preflight_required" ]; then
        printf '%s\n' "$PREFLIGHT_EXIT_NOTE"
        exit 0
    fi
done

# shellcheck source=scripts/lib/preflight-read.sh
. "$PREFLIGHT_LIB/preflight-read.sh"
# shellcheck source=scripts/lib/preflight-resolve.sh
. "$PREFLIGHT_LIB/preflight-resolve.sh"

# Optional helpers, sourced when present so a later component drops in without
# editing this file.
if [ -r "$PREFLIGHT_LIB/preflight-probe.sh" ]; then
    # shellcheck source=/dev/null
    . "$PREFLIGHT_LIB/preflight-probe.sh"
fi
if [ -r "$PREFLIGHT_LIB/preflight-report.sh" ]; then
    # shellcheck source=/dev/null
    . "$PREFLIGHT_LIB/preflight-report.sh"
fi

# A sourced file with a syntax error returns non-zero without defining
# anything, and without `set -e` execution would carry on into undefined
# functions. Check for the two entry points that must exist.
if ! declare -f preflight_read_declaration >/dev/null 2>&1 ||
   ! declare -f preflight_resolve_tool >/dev/null 2>&1; then
    printf '%s\n' "$PREFLIGHT_EXIT_NOTE"
    exit 0
fi

# ---------------------------------------------------------------------------
# Argument
# ---------------------------------------------------------------------------

if [ "$#" -ne 1 ]; then
    printf 'shirabe preflight: expected exactly one argument, the skill name; no prerequisite was checked.\n'
    exit 0
fi

PREFLIGHT_SKILL="$1"
case "$PREFLIGHT_SKILL" in
    ''|-*|*[!a-z0-9-]*)
        printf 'shirabe preflight: the skill name must match [a-z0-9-]+ with no leading dash; no prerequisite was checked.\n'
        exit 0
        ;;
esac
if [ "${#PREFLIGHT_SKILL}" -gt 64 ]; then
    printf 'shirabe preflight: the skill name is too long; no prerequisite was checked.\n'
    exit 0
fi

PREFLIGHT_DECL="$PREFLIGHT_ROOT/skills/$PREFLIGHT_SKILL/requires.tsv"

# An absent sidecar is silent. Undeclared is a real state, distinct from an
# explicitly empty declaration, but it is decidable by `ls` and it is the
# conformance scan's finding to make. Speaking here would put a byte on the
# load path of every skill that has not been rolled out yet.
if [ ! -e "$PREFLIGHT_DECL" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# preflight_wrap <text>
#
# Prints the text wrapped on word boundaries. Runs only on a path that is
# already emitting output, so it costs the satisfied path nothing. Globbing is
# disabled around the deliberate word split.
preflight_wrap() {
    (
        set -f
        width=72
        line=""
        for word in $1; do
            if [ -z "$line" ]; then
                line="$word"
            elif [ "$(( ${#line} + 1 + ${#word} ))" -le "$width" ]; then
                line="$line $word"
            else
                printf '%s\n' "$line"
                line="$word"
            fi
        done
        [ -n "$line" ] && printf '%s\n' "$line"
        exit 0
    )
}

PREFLIGHT_BLOCKS_EMITTED=0

preflight_block_separator() {
    if [ "$PREFLIGHT_BLOCKS_EMITTED" -gt 0 ]; then
        printf '\n'
    fi
    PREFLIGHT_BLOCKS_EMITTED=$(( PREFLIGHT_BLOCKS_EMITTED + 1 ))
}

# preflight_checked_sentence <lead>
#
# "Checked PATH first, then A, B, and C." -- the roots, filtered through the
# path allowlist, because a root entry is input and it is echoed into report
# text.
preflight_checked_sentence() {
    local lead="$1" roots
    roots=$(preflight_rendered_roots)
    if [ -n "$roots" ]; then
        printf 'Checked %s, then %s.' "$lead" "$roots"
    else
        printf 'Checked %s. No additional root was configured for this check.' "$lead"
    fi
}

# preflight_emit_unresolvable <skill> <tool> <status> <path>
#
# The three postures that never reach a probe. Defined only if a reporter
# helper has not already defined it, so scripts/lib/preflight-report.sh can
# take the rendering over without this file changing.
#
# Off-PATH blocks open with "nothing needs installing" and close by saying so
# again, because the failure this prevents is an agent that read only the
# remedy and reinstalled a tool it already has.
if ! declare -f preflight_emit_unresolvable >/dev/null 2>&1; then
preflight_emit_unresolvable() {
    local skill="$1" tool="$2" status="$3" path="$4"

    preflight_block_separator

    case "$status" in
        offpath)
            preflight_wrap "shirabe /$skill: prerequisite not met, and nothing needs installing."
            printf '\n'
            if preflight_valid_path "$path"; then
                preflight_wrap "$tool is installed at $path but is not on this shell's PATH. $(preflight_checked_sentence "PATH first")"
            else
                preflight_wrap "$tool is installed under one of the checked roots but is not on this shell's PATH. Its path is not rendered here: it carries characters this report does not print. $(preflight_checked_sentence "PATH first")"
            fi
            printf '\n'
            preflight_wrap "/$skill declares $tool. Every call to it will fail as written until PATH includes the directory above."
            printf '\n'
            preflight_wrap "Put it on PATH:"
            printf '\n'
            printf '  . ~/.tsuku/env\n'
            printf '\n'
            preflight_wrap "Do not reinstall $tool. It is already here."
            ;;
        absent)
            preflight_wrap "shirabe /$skill: prerequisite not met."
            printf '\n'
            preflight_wrap "$tool is not installed on this host. $(preflight_checked_sentence "PATH")"
            printf '\n'
            preflight_wrap "/$skill declares $tool. Every call to it will fail as written."
            printf '\n'
            if declare -f preflight_render_route >/dev/null 2>&1; then
                preflight_render_route "$tool"
            else
                preflight_wrap "Install-route resolution is not available in this check, so this report gives no command. Install $tool by whatever means this host supports."
            fi
            ;;
        refused)
            preflight_wrap "shirabe /$skill: prerequisite not met."
            printf '\n'
            case "$path" in
                /*)
                    preflight_wrap "$tool resolves to a path inside the working directory and was not probed. This check does not run a binary that resolves under the directory it was invoked from: at skill load that directory may be a branch under review."
                    ;;
                *)
                    preflight_wrap "$tool resolves to something that is not an absolute path and was not probed. This check runs only an absolute path that lies outside the working directory."
                    ;;
            esac
            printf '\n'
            preflight_wrap "/$skill declares $tool. This report makes no claim about the surface $tool advertises, or about whether that call would work: the binary was never run."
            ;;
    esac
    return 0
}
fi

# The surface check belongs to the probe helper. Until it lands, a resolved
# tool is reported on no further, which is the honest posture: nothing here has
# read the binary's surface.
if ! declare -f preflight_check_surface >/dev/null 2>&1; then
preflight_check_surface() {
    return 0
}
fi

# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

if ! preflight_read_routes "$PREFLIGHT_LIB/tool-routes.tsv"; then
    printf 'shirabe preflight: scripts/lib/tool-routes.tsv is missing or does not open with `#schema<TAB>tool-routes/v1`; no prerequisite was checked for /%s.\n' \
        "$PREFLIGHT_SKILL"
    exit 0
fi

PREFLIGHT_RECORDS=$(preflight_read_declaration "$PREFLIGHT_SKILL" "$PREFLIGHT_DECL") || PREFLIGHT_RECORDS=""

if [ -z "$PREFLIGHT_RECORDS" ]; then
    exit 0
fi

preflight_split_roots

# ---------------------------------------------------------------------------
# Evaluate
#
# Only `always` records are evaluated. A `mode:` record produces no byte at
# load -- not deferred, not satisfied, not unsatisfied -- because the mode has
# not been chosen and any byte about it would imply an evaluation that did not
# happen. The deferral is visible in the declaration's fourth field instead.
#
# Two passes so off-PATH blocks sort first, and one block per tool rather than
# one per record: the unresolvable postures are facts about the tool, and ten
# koto records would otherwise print ten identical blocks.
# ---------------------------------------------------------------------------

PREFLIGHT_EMITTED_TOOLS=""

preflight_already_emitted() {
    case "$PREFLIGHT_EMITTED_TOOLS" in
        *"$PREFLIGHT_NL$1$PREFLIGHT_NL"*) return 0 ;;
    esac
    return 1
}

preflight_mark_emitted() {
    PREFLIGHT_EMITTED_TOOLS="$PREFLIGHT_EMITTED_TOOLS$PREFLIGHT_NL$1$PREFLIGHT_NL"
}

for _preflight_pass in offpath other; do
    while IFS="$PREFLIGHT_TAB" read -r _tool _sub _flags _when; do
        [ -n "$_tool" ] || continue
        [ "$_when" = "always" ] || continue

        preflight_resolve_tool "$_tool"

        case "$PREFLIGHT_STATUS" in
            present)
                [ "$_preflight_pass" = "other" ] || continue
                preflight_check_surface "$PREFLIGHT_SKILL" "$_tool" "$_sub" "$_flags" "$PREFLIGHT_PATH"
                ;;
            offpath)
                [ "$_preflight_pass" = "offpath" ] || continue
                preflight_already_emitted "$_tool" && continue
                preflight_mark_emitted "$_tool"
                preflight_emit_unresolvable "$PREFLIGHT_SKILL" "$_tool" "offpath" "$PREFLIGHT_PATH"
                ;;
            absent|refused)
                [ "$_preflight_pass" = "other" ] || continue
                preflight_already_emitted "$_tool" && continue
                preflight_mark_emitted "$_tool"
                preflight_emit_unresolvable "$PREFLIGHT_SKILL" "$_tool" "$PREFLIGHT_STATUS" "$PREFLIGHT_PATH"
                ;;
        esac
    done <<<"$PREFLIGHT_RECORDS"
done

exit 0
