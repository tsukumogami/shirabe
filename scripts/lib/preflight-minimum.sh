#!/usr/bin/env bash
# preflight-minimum.sh -- report, at skill load, a koto older than shirabe's
# koto minimum.
#
# Sourced by scripts/skill-preflight.sh after preflight-probe.sh and
# preflight-report.sh. It defines preflight_check_minimum, the hook the entry
# point calls for every in-scope record whose tool resolved `present`. The
# entry point names no tool; this file decides that koto is the only tool with
# a minimum, holds the once-per-run guard, and makes the `--mode` skip.
#
# WHY A VERSION, WHEN EVERY OTHER CHECK READS SURFACE
#
# Surface probing is the rule, and it stays the rule for every other tool and
# for koto's own surface (references/tool-declaration-policy.md). The koto
# minimum is the one exception, recorded in
# docs/decisions/DECISION-preflight-koto-minimum-2026-09-27.md: what shirabe
# needs from the minimum release is behaviour with no flag to probe, and on an
# older koto a run can finish with a wrong result and no error. `--help` can't
# see that.
#
# ONE VALUE
#
# The minimum is the FLOOR line of scripts/assert-koto-floor.sh, read from the
# plugin root the entry point validated -- never $PWD, and never KOTO_FLOOR from
# the environment, which only the CI script honours. That line's shape is a
# runtime contract; assert-koto-floor.sh's header says so. requires.tsv still
# carries no version.
#
# WHAT IT PRINTS
#
#   at or above the minimum          nothing
#   below it                         the below-minimum block
#   `koto version` ran and printed   the version-unreadable block: whether koto
#     no MAJOR.MINOR.PATCH, or       meets the minimum was not established. A
#     nothing at all                 released koto built without a release tag
#                                    prints `dev+<hash>` and lands here.
#   `koto version` timed out or      the same block, naming which bound it hit.
#     overflowed the cap             It also claims the probe's "inconclusive
#                                    koto" slot, so the surface probe of the
#                                    same binary's `--help` doesn't print a
#                                    second block about it.
#   the probe is unbounded (no       nothing, as for every probe
#     sleep or head)
#   no readable minimum              nothing: a reader can't act on it, and CI
#                                    fails when the FLOOR line can't be read
#
# A pre-release or build suffix after MAJOR.MINOR.PATCH is dropped before
# comparing, as assert-koto-floor.sh drops it: `0.14.0-dev+abc1234` compares
# as 0.14.0. Each component is at most six digits, so no value reaches shell
# arithmetic large enough to wrap. Parsing is on builtins; the satisfied path
# forks only the one bounded `koto version`.
#
# The two blocks are rendered by preflight-report.sh
# (preflight_emit_below_minimum, preflight_emit_version_unreadable). The
# fallbacks below exist for a configuration without the reporter, like the
# probe's own fallbacks.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile. `[[ =~ ]]`
# with the pattern in a variable is 3.2-safe.

if [ "${PREFLIGHT_MINIMUM_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_MINIMUM_SOURCED=1

PREFLIGHT_MINIMUM_DONE=0

# MAJOR.MINOR.PATCH, each component one to six digits, not followed by a digit.
PREFLIGHT_MINIMUM_TRIPLE='([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})([^0-9]|$)'

# preflight_minimum_read_floor <root>  ->  PREFLIGHT_MINIMUM_FLOOR, or return 1
preflight_minimum_read_floor() {
    local file="$1/scripts/assert-koto-floor.sh" line
    local re='^FLOOR="\$\{KOTO_FLOOR:-'"$PREFLIGHT_MINIMUM_TRIPLE"
    PREFLIGHT_MINIMUM_FLOOR=""
    [ -r "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ $re ]]; then
            PREFLIGHT_MINIMUM_FLOOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
            return 0
        fi
    done <"$file"
    return 1
}

# preflight_minimum_parse <version-line>  ->  PREFLIGHT_MINIMUM_GOT, or return 1
preflight_minimum_parse() {
    local re='^koto v?'"$PREFLIGHT_MINIMUM_TRIPLE"
    PREFLIGHT_MINIMUM_GOT=""
    [[ $1 =~ $re ]] || return 1
    PREFLIGHT_MINIMUM_GOT="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    return 0
}

# preflight_minimum_ge <a> <b>  ->  0 when a >= b, field by field, numerically.
# Both arguments come from the two functions above, so each field is 1-6 digits.
preflight_minimum_ge() {
    local a="$1" b="$2" i x y
    local IFS=.
    # shellcheck disable=SC2206
    local av=($a) bv=($b)
    for i in 0 1 2; do
        x="${av[$i]}"
        y="${bv[$i]}"
        if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
        if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
    done
    return 0
}

# preflight_minimum_mode_covered  ->  0 when this is a `--mode` run and an
# `always` record names koto, so the load-time run made the comparison.
#
# Reads PREFLIGHT_WHEN and PREFLIGHT_RECORDS, the entry point's globals. The
# skip assumes load time reached koto; it did not if koto was absent or off
# PATH then and was fixed mid-session, in which case the `--mode` run misses
# the comparison. That is rare, and the next load makes it.
preflight_minimum_mode_covered() {
    local _t _s _f _w
    [ "${PREFLIGHT_WHEN-always}" = "always" ] && return 1
    while IFS="${PREFLIGHT_TAB-	}" read -r _t _s _f _w; do
        if [ "$_t" = "koto" ] && [ "$_w" = "always" ]; then
            return 0
        fi
    done <<<"${PREFLIGHT_RECORDS-}"
    return 1
}

# preflight_check_minimum <skill> <tool> <path> <root>
#
# Called for every present record. Only koto has a minimum, and it is checked
# once per run. <path> is the one preflight_resolve_tool vetted: absolute,
# executable, outside the working directory.
preflight_check_minimum() {
    local skill="$1" tool="$2" path="$3" root="$4" line

    [ "$tool" = "koto" ] || return 0
    [ "$PREFLIGHT_MINIMUM_DONE" -eq 0 ] || return 0
    PREFLIGHT_MINIMUM_DONE=1

    preflight_minimum_mode_covered && return 0
    preflight_minimum_read_floor "$root" || return 0
    declare -f preflight_probe_version >/dev/null 2>&1 || return 0

    preflight_probe_version "$path"
    case "$PREFLIGHT_PROBE_OUTCOME" in
        ok|empty) ;;
        timeout|overcap)
            if declare -f preflight_probe_once >/dev/null 2>&1; then
                preflight_probe_once "inconclusive $tool" || return 0
            fi
            preflight_emit_version_unreadable "$skill" "$tool" "$PREFLIGHT_MINIMUM_FLOOR" "$PREFLIGHT_PROBE_OUTCOME"
            return 0
            ;;
        *) return 0 ;;
    esac

    line="${PREFLIGHT_PROBE_TEXT%%${PREFLIGHT_NL-
}*}"
    if ! preflight_minimum_parse "$line"; then
        preflight_emit_version_unreadable "$skill" "$tool" "$PREFLIGHT_MINIMUM_FLOOR"
        return 0
    fi

    preflight_minimum_ge "$PREFLIGHT_MINIMUM_GOT" "$PREFLIGHT_MINIMUM_FLOOR" && return 0
    preflight_emit_below_minimum "$skill" "$tool" "$PREFLIGHT_MINIMUM_GOT" "$PREFLIGHT_MINIMUM_FLOOR"
    return 0
}

# Fallback renderers, for a configuration without preflight-report.sh, which
# defines both unconditionally and is the last word on what they say.
if ! declare -f preflight_emit_below_minimum >/dev/null 2>&1; then
preflight_emit_below_minimum() {
    local skill="$1" tool="$2" got="$3" floor="$4"
    preflight_probe_separator
    preflight_probe_wrap "shirabe /$skill: prerequisite not met."
    printf '\n'
    preflight_probe_wrap "$tool $got is installed. shirabe's skills are tested on $tool $floor and later, and on an older $tool a run can finish with a wrong result and no error."
    printf '\n'
    preflight_probe_wrap "/$skill declares $tool. Upgrade $tool to $floor or later before running /$skill."
    return 0
}
fi
if ! declare -f preflight_emit_version_unreadable >/dev/null 2>&1; then
preflight_emit_version_unreadable() {
    local skill="$1" tool="$2" floor="$3" reason="${4-unreadable}" what
    case "$reason" in
        timeout) what="did not finish within the budget this check gives it" ;;
        overcap) what="wrote more than this check reads" ;;
        *)       what="printed no version this check can read" ;;
    esac
    preflight_probe_separator
    preflight_probe_wrap "shirabe /$skill: prerequisite could not be checked."
    printf '\n'
    preflight_probe_wrap "\`$tool version\` $what, so whether $tool meets shirabe's minimum, $floor, was not established."
    return 0
}
fi
