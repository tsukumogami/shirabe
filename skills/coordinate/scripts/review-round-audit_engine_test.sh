#!/usr/bin/env bash
# review-round-audit_engine_test.sh -- review-round.sh audit records the
# light-cap audit's miss or no-miss as a koto decision, on real koto sessions
# of the shipped work-on.md.
#
# Prints one line per criterion:
#   a verdict ledger whose scrutiny seat raised a blocking finding at the
#        head the light seat passed records one `verdict` decision, outcome
#        fail, subject what=light-audit/miss/<category>, by check:light-audit,
#        and a second call records no other;
#   the miss's category is its most severe finding's: security over
#        correctness, and uncategorized for a finding with none;
#   a ledger whose full panels raised nothing blocking records nothing at a
#        scrutiny round (pending) and one pass decision, subject
#        what=light-audit/no-miss, at the QA round, once;
#   a blocking full-panel finding at a head the light seat did not pass (it
#        was blocking there) is not a miss;
#   a session that isn't audited, one whose level is no longer light, and
#        one with no light round record nothing;
#   a bad session name or panel is a usage error;
#   on a koto whose `decisions record` has no --kind (0.33.0, the entry
#        floor), a miss records nothing: exit 0, an `unsupported:` line and
#        one notice on stderr. The decision cases above are skipped there,
#        with a `note:` line, and the cases that record nothing still run.
#
# Every koto call runs on a store under this suite's scratch directory (the
# guard in scripts/lib/koto-test-guard.sh). Needs koto and jq; SKIPs (exit 0)
# without koto.
# Usage: bash skills/coordinate/scripts/review-round-audit_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/review-round-audit.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'rm -rf "$T"'
unset KOTO_BIN KOTO_STORE
RR="$HERE/review-round.sh"
RL="$REPO_ROOT/skills/work-on/scripts/review-level.sh"
TPL="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

d=$(cd "$T" && koto session dir s1 2>&1) || { echo "FAIL: koto session dir failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$KOTO_TEST_GUARD_DIR"/*) ;;
    *) echo "FAIL: koto's session directory is not under the guard's directory: [$d]; no case ran"; exit 1 ;;
esac

# audited_name <prefix> <want>: the first <prefix>-<n> whose audit exits <want>.
audited_name() {
    local n=0
    while [ "$n" -lt 400 ]; do
        bash "$RL" audit "$1-$n" >/dev/null 2>&1
        [ $? -eq "$2" ] && { printf '%s-%s\n' "$1" "$n"; return 0; }
        n=$((n + 1))
    done
    return 1
}

H=0123456789abcdef0123456789abcdef01234567
G=89abcdef0123456789abcdef0123456789abcdef

# open <session> <level>: a live work-on session whose review-level ledger's
# last level is <level>.
open() {
    (cd "$T" && koto init "$1" --template "$TPL" --var ARTIFACT_PREFIX="$1" \
        --var PLUGIN_ROOT="$REPO_ROOT" > "$T/init.out" 2>&1) \
        || { bad "koto init $1" "$(grep -v -E '^(warning|  remedy)' "$T/init.out" | head -5)"; return 1; }
    printf '{"ts":"2026-01-01T00:00:00Z","event":"bound","floor":null,"ceiling":null}\n{"ts":"2026-01-01T00:00:01Z","event":"from_facts","from":"","to":"%s","source":"facts"}\n' "$2" \
        | (cd "$T" && koto context add "$1" review_level.jsonl >/dev/null)
}
# ledger <session> <jq program>: writes the verdict ledger the program builds.
ledger() {
    jq -nc --arg h "$H" --arg g "$G" "$2" | (cd "$T" && koto context add "$1" verdict_ledger.json >/dev/null)
}
# finding: one entry of the ledger's findings map, in the shape panel-scope.sh
# writes, reduced to what the audit reads.
finding() {
    # $1 id, $2 panel, $3 severity, $4 commit var ($h or $g), $5 category or ""
    printf '"%s": {id: "%s", panel: "%s", severity: "%s", raiser: {kind: "reviewer", name: "s"}, records: [{kind: "raised", commit: %s}]%s}' \
        "$1" "$1" "$2" "$3" "$4" "$( [ -n "${5:-}" ] && printf ', category: "%s"' "$5")"
}
audit() { (cd "$T" && bash "$RR" audit "$@" 2> "$T/err"); }
decisions() {
    (cd "$T" && koto decisions list "$1" --format v1 2>/dev/null) \
        | jq -c '[.decisions[]?.decision | select(.kind == "verdict") | {outcome, what: .subject.what, by: (.decider.name.value // .decider.kind)}]'
}

# The decision cases need a koto whose `decisions record` takes --kind;
# koto 0.33.0, the entry floor, has none, and review-round.sh records nothing
# there (the last case below).
CAN_RECORD=0
case "$(koto decisions record --help)" in *--kind*) CAN_RECORD=1 ;; esac
# The notice doesn't start with SKIP: run-tests.sh --engine, which the koto
# entry floor job runs, fails a suite that prints one, as a suite that ran
# nothing. This one still runs every case that records nothing, and the case
# that pins what review-round.sh does on such a koto.
if [ "$CAN_RECORD" = 0 ]; then
    echo "note: this koto has no \`koto decisions record --kind\` -- the decision cases were skipped; the cases that record nothing still run"
fi

if [ "$CAN_RECORD" = 1 ]; then
# --- a miss -------------------------------------------------------------------
S=$(audited_name rr-miss 0) || { echo "FAIL: no audited name found"; exit 1; }
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}, {panel: \"scrutiny\", head: \$h}],
                 findings: {$(finding aaaa000000000001 scrutiny blocking '$h' correctness)}}"
    OUT=$(audit --session "$S" --panel scrutiny); RC=$?
    eq "a blocking scrutiny finding at the head the light seat passed: exit 0" 0 "$RC"
    case "$OUT" in "miss correctness "*) ok "  ... prints the miss and its category" ;; *) bad "  ... prints the miss" "got [$OUT] err [$(cat "$T/err")]" ;; esac
    eq "  ... one verdict decision, outcome fail, what=light-audit/miss/correctness, by check:light-audit" \
        '[{"outcome":"fail","what":"light-audit/miss/correctness","by":"light-audit"}]' "$(decisions "$S")"
    OUT=$(audit --session "$S" --panel review)
    case "$OUT" in "miss recorded: "*) ok "a second call says the miss is recorded" ;; *) bad "a second call" "got [$OUT]" ;; esac
    eq "  ... and records no other decision" 1 "$(decisions "$S" | jq length)"
    OUT=$(audit --session "$S" --panel qa)
    eq "  ... nor a no-miss at QA" 1 "$(decisions "$S" | jq length)"
fi

S=$(audited_name rr-sec 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}],
                 findings: {$(finding bbbb000000000001 review blocking '$h' correctness), $(finding bbbb000000000002 qa blocking '$h' security), $(finding bbbb000000000003 scrutiny advisory '$h' security)}}"
    audit --session "$S" --panel qa >/dev/null
    eq "two misses: the category is the more severe, security" '["light-audit/miss/security"]' "$(decisions "$S" | jq -c '[.[].what]')"
fi

S=$(audited_name rr-uncat 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}], findings: {$(finding cccc000000000001 scrutiny blocking '$h' '')}}"
    audit --session "$S" --panel scrutiny >/dev/null
    eq "a finding with no category: the miss is uncategorized" '["light-audit/miss/uncategorized"]' "$(decisions "$S" | jq -c '[.[].what]')"
fi

# --- no miss ------------------------------------------------------------------
S=$(audited_name rr-nomiss 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}, {panel: \"scrutiny\", head: \$h}],
                 findings: {$(finding dddd000000000001 scrutiny advisory '$h' other)}}"
    OUT=$(audit --session "$S" --panel scrutiny)
    case "$OUT" in pending:*) ok "no blocking finding at scrutiny: pending" ;; *) bad "at scrutiny" "got [$OUT]" ;; esac
    [ "$CAN_RECORD" = 0 ] || eq "  ... and nothing recorded" '[]' "$(decisions "$S")"
    ledger "$S" "{history: [{panel: \"light\", head: \$h}, {panel: \"scrutiny\", head: \$h}, {panel: \"review\", head: \$h}, {panel: \"qa\", head: \$h}],
                 findings: {$(finding dddd000000000001 scrutiny advisory '$h' other)}}"
    OUT=$(audit --session "$S" --panel qa)
    case "$OUT" in "no-miss "*) ok "the QA round with no blocking full-panel finding: no-miss" ;; *) bad "at QA" "got [$OUT] err [$(cat "$T/err")]" ;; esac
    eq "  ... one verdict decision, outcome pass, what=light-audit/no-miss" \
        '[{"outcome":"pass","what":"light-audit/no-miss","by":"light-audit"}]' "$(decisions "$S")"
    audit --session "$S" --panel qa >/dev/null
    eq "  ... recorded once" 1 "$(decisions "$S" | jq length)"
fi

# A blocking full-panel finding raised at a head where the light seat was
# itself blocking (it didn't pass there) is not a miss.
S=$(audited_name rr-notpassed 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$g}, {panel: \"light\", head: \$h}, {panel: \"qa\", head: \$h}],
                 findings: {$(finding eeee000000000001 light blocking '$g' ''), $(finding eeee000000000002 scrutiny blocking '$g' security)}}"
    OUT=$(audit --session "$S" --panel qa)
    case "$OUT" in "no-miss "*) ok "a blocking finding at a head the light seat did not pass is no miss" ;; *) bad "not passed" "got [$OUT]" ;; esac
fi

fi

# --- nothing to record --------------------------------------------------------
S=$(audited_name rr-plain 1) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}], findings: {$(finding ffff000000000001 scrutiny blocking '$h' '')}}"
    OUT=$(audit --session "$S" --panel scrutiny); RC=$?
    eq "a session that isn't audited: exit 0" 0 "$RC"
    case "$OUT" in none:*"not audited"*) ok "  ... none, not audited" ;; *) bad "  ... none" "got [$OUT]" ;; esac
    [ "$CAN_RECORD" = 0 ] || eq "  ... and nothing recorded" '[]' "$(decisions "$S")"
fi
S=$(audited_name rr-std 0) || exit 1
if open "$S" standard; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}], findings: {$(finding ffff000000000002 scrutiny blocking '$h' '')}}"
    OUT=$(audit --session "$S" --panel scrutiny)
    case "$OUT" in none:*"standard, not light"*) ok "an escalated run, now standard: none" ;; *) bad "standard" "got [$OUT]" ;; esac
    [ "$CAN_RECORD" = 0 ] || eq "  ... and nothing recorded" '[]' "$(decisions "$S")"
fi
S=$(audited_name rr-nolight 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"scrutiny\", head: \$h}], findings: {$(finding ffff000000000003 scrutiny blocking '$h' '')}}"
    OUT=$(audit --session "$S" --panel scrutiny)
    case "$OUT" in none:*"no light round"*) ok "a ledger with no light round: none" ;; *) bad "no light" "got [$OUT]" ;; esac
fi

# --- a koto that can't record a verdict decision ------------------------------
# A koto stand-in in front of the real one whose `decisions record --help`
# has no --kind, as 0.33.0's hasn't; every other call goes to the real koto.
# On a koto that already lacks it, the real one serves.
S=$(audited_name rr-old 0) || exit 1
if open "$S" light; then
    ledger "$S" "{history: [{panel: \"light\", head: \$h}], findings: {$(finding 9999000000000001 scrutiny blocking '$h' security)}}"
    mkdir -p "$T/oldkoto"
    REAL=$(command -v koto)
    printf '#!/usr/bin/env bash\nif [ "$1 $2 $3" = "decisions record --help" ]; then echo "Usage: koto decisions record [OPTIONS] <NAME>"; echo "      --with-data <WITH_DATA>"; exit 0; fi\nexec "%s" "$@"\n' "$REAL" > "$T/oldkoto/koto"
    chmod +x "$T/oldkoto/koto"
    OUT=$(cd "$T" && PATH="$T/oldkoto:$PATH" bash "$RR" audit --session "$S" --panel scrutiny 2> "$T/err"); RC=$?
    eq "a koto without --kind: a miss exits 0" 0 "$RC"
    case "$OUT" in unsupported:*) ok "  ... and says the decision is unsupported" ;; *) bad "  ... unsupported" "got [$OUT]" ;; esac
    eq "  ... with one notice on stderr" "1 review-round:" "$(wc -l < "$T/err" | tr -d ' ') $(cut -d' ' -f1 "$T/err")"
    [ "$CAN_RECORD" = 0 ] || eq "  ... and records nothing" '[]' "$(decisions "$S")"
    (cd "$T" && koto context exists "$S" light_audit.json >/dev/null) \
        && bad "  ... and writes no light_audit.json" "the key exists" || ok "  ... and writes no light_audit.json"
fi

(cd "$T" && bash "$RR" audit --session 'bad name' >/dev/null 2>&1); eq "a bad session name: exit 64" 64 $?
(cd "$T" && bash "$RR" audit --session x --panel bogus >/dev/null 2>&1); eq "a bad panel: exit 64" 64 $?
(cd "$T" && bash "$RR" audit >/dev/null 2>&1); eq "no --session: exit 64" 64 $?

echo
echo "review-round-audit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
