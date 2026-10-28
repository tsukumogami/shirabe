# takeover-flags.sh -- whether the running koto can take a run over, for the
# coordinate engine suites. Not shipped behaviour.
#
# entry-floor runs the engine suites against the oldest koto shirabe supports,
# which has no `koto init --continues` or `--supersede`. A case that needs them
# can't run there, and a SKIP line would fail run-tests.sh --engine, so a suite
# declares each such case instead and the case is left out with a line naming
# it.
#
# Sourced at a suite's top level, after the koto-test-guard.sh line, with koto
# on PATH:
#
#     . "$HERE/testdata/takeover-flags.sh"
#
# Sourcing reads `koto init --help` once and sets TAKEOVER_FLAGS to 1 when it
# lists both --continues and --supersede, 0 otherwise. Then, per case:
#
#     if needs_takeover "3: past the hop cap"; then
#         ...the case...
#     fi
#
# needs_takeover <case> returns 0 when the flags are there. Without them it
# prints `left out <case>: this koto has no init --continues or --supersede`,
# adds one to TAKEOVER_LEFT_OUT and returns 1. A suite whose remaining cases
# all need the flags can end there in one line:
#
#     needs_takeover "4-7: the takeover" || { echo "...summary..."; [ "$FAIL" -eq 0 ]; exit; }
#
# A case that runs only on a koto without the flags tests TAKEOVER_FLAGS = 0.
#
# bash 3.2 floor: plain case matching only.

TAKEOVER_FLAGS=0
TAKEOVER_LEFT_OUT=0
_tf_help=$(koto init --help 2>/dev/null)
case "$_tf_help" in
    *--continues*) case "$_tf_help" in *--supersede*) TAKEOVER_FLAGS=1 ;; esac ;;
esac
unset _tf_help

needs_takeover() { # needs_takeover <case>
    [ "$TAKEOVER_FLAGS" = 1 ] && return 0
    TAKEOVER_LEFT_OUT=$((TAKEOVER_LEFT_OUT + 1))
    printf 'left out %s: this koto has no init --continues or --supersede\n' "$1"
    return 1
}
