# reconcile-env.sh -- the environment scrub for the scripts koto runs.
#
# Sourced first, never run. koto runs a state's action and its command gates
# with the environment of whoever ran `koto next`, and that is the agent. The
# template starts each script koto runs for reconcile (the pass and the report
# reader) as `/usr/bin/env -u BASH_ENV -u ENV /bin/bash -p <script>`: absolute
# paths, so no PATH lookup picks the interpreter, and privileged mode, so bash
# imports no function from the environment (an exported function could
# otherwise stand in for gh, date or any command) and reads no BASH_ENV. The
# script then calls rd_scrub before anything else:
#
#   . "$(dirname "$0")/reconcile-env.sh"
#   if [ "${1-}" = --scrubbed ]; then shift; else rd_scrub "$0" "$@"; fi
#
# rd_scrub refuses to run when a variable that changes what is read or how a
# tool behaves is set, then re-executes the script under a fixed PATH with
# every variable outside a short allowlist unset. It unsets rather than using
# `env -i NAME=value`, so a credential it keeps never appears on a command
# line.
#
# Refused: BASH_ENV, ENV, LD_PRELOAD, any LD_* or DYLD_* loader variable,
# GIT_DIR, any GIT_CONFIG*, GH_HOST, GH_REPO. The template's command line runs
# the script through `env -u BASH_ENV -u ENV`, so no startup file runs before
# this check.
#
# Kept: the operator's GitHub credential (GH_TOKEN, GITHUB_TOKEN; it decides
# who reads, not what is read), what gh needs to reach a keyring
# (DBUS_SESSION_BUS_ADDRESS, XDG_RUNTIME_DIR), and where koto keeps sessions
# (KOTO_HOME, KOTO_SESSIONS_BASE), which the engine that ran this script used
# too. HOME is the account's home from the password database, never the
# inherited HOME; LC_ALL is C.
#
# The fixed PATH: the system directories, each existing /opt/*/bin (where tools
# installed by an administrator live), then the account's own tool
# directories under that home.
#
# Exit 70 on a refusal, with the reason on stderr.

RD_SCRUB_KEEP="GH_TOKEN GITHUB_TOKEN DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR KOTO_HOME KOTO_SESSIONS_BASE"

# rd_home -- the account's home directory from the password database.
rd_home() {
    local u h="" PATH=/usr/bin:/bin
    u=$(id -un 2>/dev/null) || return 1
    if command -v getent >/dev/null 2>&1; then
        h=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
    fi
    if [ -z "$h" ] && command -v dscl >/dev/null 2>&1; then
        h=$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')
    fi
    if [ -z "$h" ] && [ -r /etc/passwd ]; then
        h=$(awk -F: -v u="$u" '$1 == u { print $6; exit }' /etc/passwd)
    fi
    [ -n "$h" ] && [ -d "$h" ] || return 1
    printf '%s' "$h"
}

# rd_fixed_path HOME -- the fixed PATH.
rd_fixed_path() {
    local h=$1 p d
    p=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin
    for d in /opt/*/bin; do
        [ -d "$d" ] && p="$p:$d"
    done
    # The account's own tool directories come last, so nothing placed there
    # stands in for a tool the system directories have.
    for d in "$h/.tsuku/bin" "$h/.tsuku/tools/current" "$h/.koto/bin" "$h/.local/bin" "$h/bin" "$h/go/bin" "$h/.cargo/bin"; do
        p="$p:$d"
    done
    printf '%s' "$p"
}

# rd_scrub SCRIPT ARGS... -- refuse, or re-execute SCRIPT --scrubbed ARGS...
# in the scrubbed environment. Never returns.
rd_scrub() {
    local script=$1 v keep h p
    shift
    for v in BASH_ENV ENV LD_PRELOAD GIT_DIR GH_HOST GH_REPO; do
        if [ -n "${!v+x}" ]; then
            echo "reconcile: refused: $v is set; unset it and tick again" >&2
            exit 70
        fi
    done
    for v in $(compgen -e); do
        case "$v" in
            GIT_CONFIG*|LD_*|DYLD_*)
                echo "reconcile: refused: $v is set; unset it and tick again" >&2
                exit 70 ;;
        esac
    done
    h=$(rd_home) || { echo "reconcile: refused: the account's home can't be read from the password database" >&2; exit 70; }
    p=$(rd_fixed_path "$h")
    for v in $(compgen -e); do
        keep=0
        case " $RD_SCRUB_KEEP " in *" $v "*) keep=1 ;; esac
        [ "$keep" = 1 ] || unset "$v" 2>/dev/null
    done
    export HOME="$h" PATH="$p" LC_ALL=C
    # The bash already running this script, whatever its path.
    exec "$BASH" -p "$script" --scrubbed "$@"
}
