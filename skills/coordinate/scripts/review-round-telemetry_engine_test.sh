#!/usr/bin/env bash
# review-round-telemetry_engine_test.sh -- a round review-round.sh records
# reaches koto's run journal as review telemetry, on a real koto session of
# the shipped work-on.md, and a koto that can't take it changes nothing else.
#
# Prints one line per criterion:
#   a three-seat round writes one code_review_round record (round 1, three
#        seats, the reviewed head's digest) and one code_review_verdict per
#        seat, with the seat, model and verdict the round gave;
#   the seats work-on.md declares are kept by name, and a seat it doesn't
#        declare is recorded as other;
#   a second round on the same session is round 2;
#   a koto that refuses `review record`, and one without `code-round`, each
#        leave exit 0, the same stdout line, the round stored, one notice on
#        stderr and no new record in the journal.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable,
# KOTO_SESSIONS_BASE and KOTO_HOME and sets HOME under its own directory, and
# `koto session dir` must name a directory there before the first case.
#
# Needs koto and jq; SKIPs (exit 0) without koto, or with a koto that has no
# `koto review record code-round`, which run-tests.sh --engine turns into a
# failure.
# Usage: bash skills/coordinate/scripts/review-round-telemetry_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
case "$(koto review record --help 2>&1)" in
    *code-round*) ;;
    *) echo "SKIP: this koto has no \`koto review record code-round\` -- the engine cases did not run"; exit 0 ;;
esac
if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum | cut -d' ' -f1; }
else sha() { shasum -a 256 | cut -d' ' -f1; }; fi

T=$(mktemp -d "${TMPDIR:-/tmp}/review-round-telemetry.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'rm -rf "$T"'
unset KOTO_BIN KOTO_STORE
RR="$HERE/review-round.sh"
TPL="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
REAL_KOTO=$(command -v koto)

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

# The journal sits beside the sessions directory koto names.
d=$(cd "$T" && koto session dir s1 2>&1) || { echo "FAIL: koto session dir failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$KOTO_TEST_GUARD_DIR"/*) ;;
    *) echo "FAIL: koto's session directory is not under the guard's directory: [$d]; no case ran"; exit 1 ;;
esac
J="$(dirname "$(dirname "$d")")/_run_journal.jsonl"

open() {
    (cd "$T" && koto init "$1" --template "$TPL" --var ARTIFACT_PREFIX="$1" \
        --var PLUGIN_ROOT="$REPO_ROOT" > "$T/init.out" 2>&1) \
        || { echo "FAIL: koto init $1 failed: $(grep -v -E '^(warning|  remedy)' "$T/init.out" | head -5); no case ran"; exit 1; }
}
# rounds/verdicts <session>: the code review records koto journalled on it.
rounds() {
    jq -c --arg s "$1" 'select(.session == $s and .kind == "code_review_round")
        | {round: .["koto.code_review.round"], seats: .["koto.code_review.seat_count"], head: .["koto.code_review.head"]}' "$J" 2>/dev/null
}
verdicts() {
    jq -c --arg s "$1" --argjson r "$2" 'select(.session == $s and .kind == "code_review_verdict" and .["koto.code_review.round"] == $r)
        | {seat: .["koto.code_review.seat"], model: .["koto.code_review.model"], verdict: .["koto.code_review.verdict"]}' "$J" 2>/dev/null \
        | jq -s -c 'sort_by(.seat, .model)'
}
stored() { (cd "$T" && koto context get "$1" review_round.json 2>/dev/null); }
H=0123456789abcdef0123456789abcdef01234567
G=89abcdef0123456789abcdef0123456789abcdef
digest() { printf 'sha256:%s' "$(printf '%s' "$1" | sha | cut -c1-32)"; }
jq -nc --arg h "$H" '{reviewed_head: $h, seats: [
    {seat: "architect", model: "sonnet", run: "agent-a1", verdict: "pass"},
    {seat: "maintainer", model: "opus", run: "agent-a2", verdict: "pass"},
    {seat: "adversarial", model: "haiku", run: "agent-a3", verdict: "fail"}]}' > "$T/r1"
jq -c --arg g "$G" '.reviewed_head = $g' "$T/r1" > "$T/r2"

# ---- a recorded round reaches the run journal ----------------------------------------
echo "== a round recorded with review-round.sh is review telemetry =="
open s1
OUT=$(cd "$T" && bash "$RR" record --session s1 "$T/r1" 2> "$T/err"); RC=$?
eq "a well-formed round: exit 0" 0 "$RC"
eq "  ... the same line on stdout" "recorded 3 seats at $H" "$OUT"
eq "  ... nothing on stderr" "" "$(cat "$T/err")"
eq "  ... the round stored as review_round.json" "$(jq -c . "$T/r1")" "$(stored s1)"
GOT=$(rounds s1)
if [ "$GOT" = "$(jq -nc --arg h "$(digest "$H")" '{round: 1, seats: 3, head: $h}')" ]; then
    ok "one code_review_round record: round 1, three seats, the reviewed head's digest"
else
    bad "one code_review_round record: round 1, three seats, the reviewed head's digest" "no review telemetry: the journal holds [$GOT]"
fi
eq "  ... one code_review_verdict per seat: declared seats by name, an undeclared one as other" \
    '[{"seat":"architect","model":"sonnet","verdict":"pass"},{"seat":"maintainer","model":"opus","verdict":"pass"},{"seat":"other","model":"haiku","verdict":"fail"}]' \
    "$(verdicts s1 1)"

(cd "$T" && bash "$RR" record --session s1 "$T/r2" > /dev/null 2> "$T/err")
eq "a second round on the session is round 2, at its own head" \
    "$(jq -nc --arg h "$(digest "$G")" '{round: 2, seats: 3, head: $h}')" "$(rounds s1 | tail -n 1)"
eq "  ... with its three verdicts" 3 "$(verdicts s1 2 | jq length)"

# ---- a koto that can't take it changes nothing else ----------------------------------
echo "== a koto that can't record the round leaves the round as it was =="
mkdir -p "$T/kotos"
# refuses: a koto that answers every `review record` with a refusal.
cat > "$T/kotos/refuses" <<EOF
#!/bin/sh
[ "\$1 \$2" = "review record" ] && { echo '{"command":"review record","error":"refused"}'; exit 1; }
exec "$REAL_KOTO" "\$@"
EOF
# no-verb: a koto from before \`code-round\`, as clap answers an unknown one.
cat > "$T/kotos/no-verb" <<EOF
#!/bin/sh
case "\$*" in "review record "*code-round*) echo "error: unrecognized subcommand 'code-round'" >&2; exit 2 ;; esac
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/kotos/refuses" "$T/kotos/no-verb"
for k in refuses no-verb; do
    s="s-$k"
    open "$s"
    OUT=$(cd "$T" && KOTO_BIN="$T/kotos/$k" bash "$RR" record --session "$s" "$T/r1" 2> "$T/err"); RC=$?
    eq "$k: exit 0" 0 "$RC"
    eq "$k:   ... the same line on stdout" "recorded 3 seats at $H" "$OUT"
    eq "$k:   ... the round stored" "$(jq -c . "$T/r1")" "$(stored "$s")"
    if [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && grep -q '^review-round: ' "$T/err"; then
        ok "$k:   ... one notice on stderr"
    else
        bad "$k:   ... one notice on stderr" "stderr [$(cat "$T/err")]"
    fi
    eq "$k:   ... no code review record in the journal" "" "$(rounds "$s")"
done

echo
echo "review-round-telemetry: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
