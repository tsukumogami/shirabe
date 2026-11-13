# verification-deferral.sh -- the opener checks for a verification deferral to
# hosted CI (--verification=hosted-ci with --verification-reason=<text>), and
# the character check for a partial delivery's reason
# (--delivery-reason=<text>).
#
# Sourced, never run. Defines two functions, each reading the invocation's
# tokens (a JSON array of strings) from its one argument and printing the
# refusal message, or nothing when the tokens pass:
#
#   vd_reason_chars_refusal <tokens>
#       Every --verification-reason= and every --delivery-reason= value
#       against koto's variable value allowlist, ^[a-zA-Z0-9._/:@+ \-]*$:
#       letters, digits, spaces and . _ / : @ + -. A natural reason such as
#       "host can't run suites, CI only" has an apostrophe and a comma, and
#       koto's own invalid_var names neither, so the message names each
#       character that isn't allowed, once, JSON-quoted so a newline or a tab
#       shows. Every occurrence is checked, since every one becomes a variable
#       pair. Each flag with a finding gets one line, which names the flag:
#       --verification-reason first, then --delivery-reason. The rule that a
#       reason starts with a letter or digit is not repeated here: it lives only
#       in the templates' patterns on VERIFICATION_DEFERRAL_REASON and
#       DELIVERY_REASON. The delivery flags are work-on-open.sh's only; the
#       check reads them wherever this file is sourced, which is harmless in an
#       opener that never maps them.
#
#   vd_missing_reason_refusal <tokens>
#       --verification=hosted-ci with no non-empty --verification-reason. Only
#       the last occurrence of each flag is looked at; a repeat still reaches
#       koto, which refuses it. koto can't relate two variables, so this is the
#       one place a deferral without a reason is stopped before a run starts.
#
# Both return 0 whether or not they print. The caller turns a message into its
# own usage refusal (error=usage, exit 64, no koto call). Two openers source
# this file: skills/work-on/scripts/work-on-open.sh and
# skills/execute/scripts/execute-open.sh, so /work-on and /execute refuse the
# same reasons in the same words.
#
# Requires jq. Written for the bash 3.2 floor.

vd_reason_chars_refusal() {
    local flag example bad
    # One jq call serves both flags, the prefix passed in with --arg.
    # The class must stay koto's VALUE_PATTERN (src/engine/substitute.rs).
    # The allowlist agreement case in skills/work-on/scripts/work-on-open_test.sh
    # reads it out of the select(test("...")) line below by text and holds it to
    # a real koto, so keep the class written whole in that call, the file's one
    # such line: moving it to another file, building it from variables or
    # adding a second such line breaks the case.
    for flag in --verification-reason --delivery-reason; do
        bad=$(printf '%s' "$1" | jq -r --arg p "$flag=" '[.[] | select(startswith($p))
            | ltrimstr($p) | explode[] | [.] | implode
            | select(test("^[a-zA-Z0-9._/:@+ -]$") | not)] | unique | map(@json) | join(" ")')
        [ -n "$bad" ] || continue
        case "$flag" in
            --verification-reason) example="host is in a measurement window until 02:40Z" ;;
            *) example="step 1 of 2: validator side" ;;
        esac
        printf '%s\n' "$flag has characters koto does not accept in a variable value: $bad. A reason may use only letters, digits, spaces and . _ / : @ + - (koto's allowlist, ^[a-zA-Z0-9._/:@+ \\-]*\$); apostrophes and commas are not among them. Reword it, for example: $flag=$example"
    done
    return 0
}

vd_missing_reason_refusal() {
    local defer reason
    defer=$(printf '%s' "$1" | jq -r '[.[] | select(startswith("--verification="))
        | ltrimstr("--verification=")] | last // ""')
    reason=$(printf '%s' "$1" | jq -r '[.[] | select(startswith("--verification-reason="))
        | ltrimstr("--verification-reason=")] | last // ""')
    if [ "$defer" = hosted-ci ] && [ -z "$reason" ]; then
        printf '%s\n' "--verification=hosted-ci needs --verification-reason=<why>: a deferral to hosted CI has to say why local verification does not run"
    fi
    return 0
}
