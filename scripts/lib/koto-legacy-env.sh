#!/usr/bin/env bash
# koto-legacy-env.sh -- turn on koto-open.sh's harness-only legacy-environment
# knob, for a test harness whose koto accepts it.
#
# Sourced, not run, and only by test harnesses: production code never sources
# it. From the koto release that records a session's command environment,
# koto runs a template's gates and default actions in a cleared environment
# fixed when the session was created. A variable the harness exports is no
# longer seen by the commands koto runs, and the harnesses' stand-in tools (a
# fake `gh`, a fake `koto`, test boards) read their configuration from such
# variables. That release's `koto init --legacy-environment` keeps the old
# behaviour for one session, and scripts/koto-open.sh appends it when
# SHIRABE_KOTO_LEGACY_ENVIRONMENT is set.
#
# koto_legacy_env_enable exports SHIRABE_KOTO_LEGACY_ENVIRONMENT=1 when the
# koto the harness drives (KOTO_BIN, else `koto` on PATH) lists
# --legacy-environment in `koto init --help`, and leaves it unset otherwise,
# so the same harness runs unchanged on a koto older than the flag, which
# would refuse it. No koto, or a `koto init --help` that fails or prints
# nothing, also leaves it unset. A value already set in the environment is
# left alone, so a developer can run a suite with
# SHIRABE_KOTO_LEGACY_ENVIRONMENT=0 to see what the recorded environment
# breaks. An explicit 1 is kept too, even on a koto without the flag, where
# every `koto init` then refuses it: a loud failure, not a silent one.
#
# The knob belongs to test harnesses only. Exported in a user's own shell it is
# unsupported: on a koto without the flag every skill's entry fails, and on one
# with it the user's sessions quietly run with the caller's whole environment.
#
# A harness that runs `koto init` itself, not through koto-open.sh, adds
# $KOTO_LEGACY_ENV_ARG, unquoted, to its init line instead. It holds the one
# flag when the knob is on and is empty otherwise, so unquoted it expands to
# nothing. It is a scalar rather than an array because bash 3.2 treats an
# empty array's "${a[@]}" as unset under set -u.
#
# Temporary (#483): koto removes the flag in the release after the one that
# adds it, so step two, the stand-ins reading their configuration from a file,
# has to land before that release; then this file and the knob go. Every site
# carries #483, and `git grep -e '#483' -e KOTO_LEGACY_ENV_ARG -e
# SHIRABE_KOTO_LEGACY_ENVIRONMENT -e koto-legacy-env` finds them all: removing
# the helper while a `koto init ... $KOTO_LEGACY_ENV_ARG` line remains fails
# that harness on an unbound variable under set -u.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

KOTO_LEGACY_ENV_ARG=

koto_legacy_env_enable() {
    local koto="${KOTO_BIN:-koto}" help=""
    if [ -z "${SHIRABE_KOTO_LEGACY_ENVIRONMENT+set}" ]; then
        # The help text is read whole before it's searched: `koto ... | grep -q`
        # under pipefail can end with koto killed by SIGPIPE and read as "no
        # flag".
        command -v "$koto" >/dev/null 2>&1 && help=$("$koto" init --help 2>/dev/null) || true
        case "$help" in
            *--legacy-environment*)
                SHIRABE_KOTO_LEGACY_ENVIRONMENT=1
                export SHIRABE_KOTO_LEGACY_ENVIRONMENT
                ;;
        esac
    fi
    KOTO_LEGACY_ENV_ARG=
    # The same on/off rule as scripts/koto-open.sh; keep the two in step.
    case "${SHIRABE_KOTO_LEGACY_ENVIRONMENT:-}" in
        ''|0|false) ;;
        *) KOTO_LEGACY_ENV_ARG=--legacy-environment ;;
    esac
    return 0
}
