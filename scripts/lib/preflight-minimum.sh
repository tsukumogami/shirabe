#!/usr/bin/env bash
# preflight-minimum.sh -- refuse, at skill load, a koto older than shirabe's
# koto minimum.
#
# Sourced by scripts/skill-preflight.sh after preflight-probe.sh. It defines
# preflight_check_koto_minimum, which the entry point calls once per run, for
# the first in-scope koto record whose tool resolved `present`.
#
# WHY A VERSION, WHEN EVERY OTHER CHECK READS SURFACE
#
# Surface probing is the rule, and it stays the rule for every other tool (see
# references/tool-declaration-policy.md). The koto minimum is the one exception,
# recorded in docs/decisions/DECISION-preflight-koto-minimum-2026-09-27.md: what
# the minimum release added is behaviour with no flag to probe, and on a koto
# below it a /work-on child passing --no-cleanup silently withholds its result
# from /execute. A silent wrong outcome is the failure a load-time check exists
# to prevent, and no amount of `--help` reading can see it.
#
# ONE VALUE
#
# The minimum is read from scripts/assert-koto-floor.sh with the same sed CI
# uses (check-koto-entry-floor.yml, check-koto-release.sh), so it is the one
# value shirabe defines and never a second copy. requires.tsv still carries no
# version.
#
# WHAT IT PRINTS
#
# Nothing when koto is at or above the minimum. Nothing, too, when the minimum
# or the installed version can't be read: the floor file is missing or
# malformed, `koto version` times out, prints too much, or prints no
# MAJOR.MINOR.PATCH. That is the probe's own posture for a `--help` it couldn't
# read -- a check that couldn't read the version isn't evidence that it's low --
# and it is a known limit, stated in the decision record. Below the minimum it
# prints one block naming both versions and the upgrade command.
#
# A pre-release or build suffix is dropped before comparing, as
# assert-koto-floor.sh drops it: `0.14.1-dev` compares as 0.14.1.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

if [ "${PREFLIGHT_MINIMUM_SOURCED-}" = "1" ]; then
    return 0 2>/dev/null || true
fi
PREFLIGHT_MINIMUM_SOURCED=1

PREFLIGHT_MINIMUM_DONE=0

# preflight_minimum_read_floor <root>  ->  prints MAJOR.MINOR.PATCH or nothing
preflight_minimum_read_floor() {
    local file="$1/scripts/assert-koto-floor.sh" v
    [ -r "$file" ] || return 1
    v=$(sed -n 's/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p' "$file" 2>/dev/null | head -1)
    case "$v" in
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) return 1 ;;
    esac
    case "$v" in
        *.*.*.*|*[!0-9.]*) return 1 ;;
    esac
    printf '%s' "$v"
}

# preflight_minimum_ge <a> <b>  ->  0 when a >= b, field by field, numerically
preflight_minimum_ge() {
    local a="$1" b="$2" i x y
    local IFS=.
    # shellcheck disable=SC2206
    local av=($a) bv=($b)
    for i in 0 1 2; do
        x="${av[$i]:-0}"
        y="${bv[$i]:-0}"
        if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
        if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
    done
    return 0
}

# preflight_check_koto_minimum <skill> <path> <root>
#
# Runs once per preflight run whatever the number of koto records. <path> is
# the one preflight_resolve_tool vetted: absolute, executable, outside the
# working directory.
preflight_check_koto_minimum() {
    local skill="$1" path="$2" root="$3" floor got line

    [ "$PREFLIGHT_MINIMUM_DONE" -eq 0 ] || return 0
    PREFLIGHT_MINIMUM_DONE=1

    floor=$(preflight_minimum_read_floor "$root") || return 0
    [ -n "$floor" ] || return 0

    # The bounded runner lives in preflight-probe.sh; without it there is no way
    # to run koto under a budget, and an unbounded call could hang skill load.
    declare -f preflight_probe_run >/dev/null 2>&1 || return 0
    preflight_probe_run "$path" version
    [ "$PREFLIGHT_PROBE_OUTCOME" = "ok" ] || return 0

    line="${PREFLIGHT_PROBE_TEXT%%$PREFLIGHT_NL*}"
    got=$(printf '%s' "$line" | sed -n 's/^koto v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
    [ -n "$got" ] || return 0
    # Bounded before it reaches report text: digits and two dots only.
    [ "${#got}" -le 32 ] || return 0

    preflight_minimum_ge "$got" "$floor" && return 0

    preflight_probe_separator
    preflight_probe_wrap "shirabe /$skill: prerequisite not met."
    printf '\n'
    preflight_probe_wrap "koto $got is installed, and shirabe needs koto $floor or later. The subcommands /$skill calls may all be present, but what koto does with them changed in $floor, and on an older koto a run can end without its result reaching the run that is waiting for it."
    printf '\n'
    if declare -f preflight_render_route >/dev/null 2>&1; then
        preflight_render_route koto update
    else
        preflight_probe_wrap "Install-route resolution is not available in this check, so this report gives no command. Upgrade koto to $floor or later by whatever means this host supports."
    fi
    return 0
}
