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
# --legacy-environment in `koto init --help`, and unsets it otherwise, so the
# same harness runs unchanged on a koto older than the flag, which would
# refuse it. A value already set in the environment is left alone, so a
# developer can run a suite with SHIRABE_KOTO_LEGACY_ENVIRONMENT=0 to see what
# the recorded environment breaks.
#
# A harness that runs `koto init` itself, not through koto-open.sh, appends
# "${KOTO_LEGACY_ENV_FLAG[@]}" to its init line instead; that array holds the
# one flag when the knob is on and is empty otherwise.
#
# Temporary: koto removes the flag in the release after the one that adds it.
# Before then the stand-ins read their configuration from a file, and this
# file and the knob go.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

KOTO_LEGACY_ENV_FLAG=()

koto_legacy_env_enable() {
    local koto="${KOTO_BIN:-koto}"
    if [ -z "${SHIRABE_KOTO_LEGACY_ENVIRONMENT+set}" ]; then
        if command -v "$koto" >/dev/null 2>&1 &&
            "$koto" init --help 2>/dev/null | grep -q -- '--legacy-environment'; then
            SHIRABE_KOTO_LEGACY_ENVIRONMENT=1
            export SHIRABE_KOTO_LEGACY_ENVIRONMENT
        fi
    fi
    KOTO_LEGACY_ENV_FLAG=()
    case "${SHIRABE_KOTO_LEGACY_ENVIRONMENT:-}" in
        ''|0|false) ;;
        *) KOTO_LEGACY_ENV_FLAG=(--legacy-environment) ;;
    esac
    return 0
}
