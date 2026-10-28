#!/usr/bin/env bash
# doc-check-wiring_test.sh -- do the document skills call the document checks
# where they should, with the phase each call site fixes, and does a run that
# follows their phase files record its telemetry in the right order?
#
# Two parts:
#
#   call sites  every doc-check.sh call in a skill's phase files, read from
#               the files, against the table below (file, moment, phase,
#               format, skill); the fix, sections and jury calls around them;
#               and the prose that sends an unresolved check to the skill's
#               escape.
#   sessions    the commands themselves, taken line for line from the phase
#               files and run in the order a run takes them, against a stub
#               koto whose review log keeps every recorded event in call order
#               (the order of koto's event sequence numbers). The log is then
#               read for the ordering the skills promise: a pre-jury check
#               before the first jury round, a fix and a post-fix check
#               before the next, and the same records for a standalone run
#               and the same skill under /scope or /charter.
#
# A stub `shirabe` supplies the validator's envelopes (scripts/lib/
# doc-check-testlib.sh), so the suite needs only bash, git and jq.
#
# Usage: doc-check-wiring_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
PHASES="$ROOT_DIR/references/doc-check-phases.json"
FIX="$SCRIPT_DIR/fixtures/review-events"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-check-wiring-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */doc-check-wiring-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"
# shellcheck source=lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/lib/rule-findings-testlib.sh"
rf_test_setup "$WORKDIR"
LOG="$STUB_KOTO_DIR/review.log"

# ================================================================== call sites

P=skills
# file|moment|phase|format|skill|count: every doc-check.sh call site.
EXPECTED="brief/references/phases/phase-4-validate.md|pre_jury|4|brief|brief|1
brief/references/phases/phase-4-validate.md|post_fix|4|brief|brief|2
prd/references/phases/phase-4-validate.md|pre_jury|4|prd|prd|1
prd/references/phases/phase-4-validate.md|post_fix|4|prd|prd|1
design/references/phases/phase-5-security.md|pre_jury|5|design|design|1
design/references/phases/phase-5-security.md|post_fix|5|design|design|1
design/references/phases/phase-6-final-review.md|pre_jury|6|design|design|1
design/references/phases/phase-6-final-review.md|post_fix|6|design|design|1
plan/references/phases/phase-6-review.md|pre_jury|6|plan|plan|1
plan/references/phases/phase-7-creation.md|post_create|7|plan|plan|1
plan/references/phases/phase-7-creation.md|post_fix|7|plan|plan|1
review-plan/references/phases/phase-0-setup.md|pre_jury|0|plan|review-plan|1
vision/references/phases/phase-4-validate.md|pre_jury|4|vision|vision|1
vision/references/phases/phase-4-validate.md|post_fix|4|vision|vision|1
strategy/references/phases/phase-4-validate.md|pre_jury|4|strategy|strategy|1
strategy/references/phases/phase-4-validate.md|post_fix|4|strategy|strategy|1
roadmap/references/phases/phase-4-validate.md|pre_jury|4|roadmap|roadmap|1
roadmap/references/phases/phase-4-validate.md|post_fix|4|roadmap|roadmap|1"

# arg <line> <flag>: the value after <flag> on a command line.
arg() { printf '%s\n' "$1" | awk -v f="$2" '{ for (i = 1; i < NF; i++) if ($i == f) { print $(i + 1); exit } }'; }

found=$(cd "$ROOT_DIR/$P" && grep -rn --include='*.md' 'scripts/doc-check.sh" ' . | sed 's|^\./||' | while IFS= read -r hit; do
    file=${hit%%:*}
    line=${hit#*:}
    line=${line#*:}
    printf '%s|%s|%s|%s|%s\n' "$file" "$(arg "$line" --moment)" "$(arg "$line" --phase)" "$(arg "$line" --format)" "$(arg "$line" --skill)"
done | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print $0 "|" c }')
if [ "$found" = "$(printf '%s\n' "$EXPECTED" | sort)" ]; then
    pass "every doc-check.sh call site passes its fixed moment, phase, format and skill, and there are no others"
else
    fail "call sites differ: $(diff <(printf '%s\n' "$EXPECTED" | sort) <(printf '%s\n' "$found") | grep '^[<>]' | tr '\n' ' ')"
fi
bad=""
while IFS='|' read -r file moment phase format skill count; do
    jq -e --arg f "$format" --arg p "$phase" '.formats[$f].phases | has($p)' "$PHASES" >/dev/null 2>&1 || bad="$bad $file:$phase"
done <<< "$EXPECTED"
[ -z "$bad" ] && pass "every call site's phase is one its format lists in references/doc-check-phases.json" || fail "phases not listed:$bad"

# Each call's --doc is the format's canonical path for the topic placeholder.
bad=$(cd "$ROOT_DIR/$P" && grep -rhn --include='*.md' 'scripts/doc-\(check\|events\)\.sh" ' . | while IFS= read -r hit; do
    line=${hit#*:}
    doc=$(arg "$line" --doc); format=$(arg "$line" --format)
    jq -e --arg f "$format" --arg d "$doc" '.formats[$f].paths | map(sub("\\{topic\\}"; "<topic>")) | index($d)' "$PHASES" >/dev/null 2>&1 \
        || printf '%s ' "$format:$doc"
done)
[ -z "$bad" ] && pass "every doc-check.sh and doc-events.sh call names the format's canonical document" || fail "documents: $bad"

# line_of <file> <fixed text> [<after line>]: the first line at or after
# <after line> holding the text, or nothing.
line_of() { awk -v t="$2" -v a="${3:-0}" 'NR >= a && index($0, t) { print NR; exit }' "$ROOT_DIR/$P/$1"; }
# before <file> <earlier text> <later text>: the first earlier line comes
# before the first later line.
before() {
    local a b
    a=$(line_of "$1" "$2"); b=$(line_of "$1" "$3")
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
for s in brief prd vision strategy roadmap; do
    f=$s/references/phases/phase-4-validate.md
    before "$f" "--moment pre_jury" "review-events.sh\" round-started --skill $s " \
        && before "$f" "review-events.sh\" verdicts --skill $s " "skill-session.sh\" ingest $s-<topic>" \
        && pass "/$s: the pre-jury check comes before round-started, and the verdicts before ingest" \
        || fail "/$s: jury order in $f"
done
before design/references/phases/phase-6-final-review.md "--moment pre_jury" 'review-events.sh" round-started --skill design ' \
    && before design/references/phases/phase-5-security.md "--moment pre_jury" "Launch a dedicated security agent" \
    && pass "/design: a pre-jury check before the security researcher and before the review panel" \
    || fail "/design: jury order"
before plan/references/phases/phase-6-review.md "--moment pre_jury" "/review-plan <topic>" \
    && pass "/plan: the not-ready check comes before /review-plan runs" || fail "/plan: review order"
before review-plan/references/phases/phase-0-setup.md 'skill-session.sh" open review-plan <topic>' "--moment pre_jury" \
    && before review-plan/references/phases/phase-0-setup.md "--moment pre_jury" 'review-events.sh" round-started --skill plan ' \
    && pass "/review-plan: opens review-plan-<topic>, then checks, before the round starts" || fail "/review-plan: order"
for s in vision strategy roadmap; do
    f=$s/references/phases/phase-4-validate.md
    n=$(grep -c "review-events.sh\" [a-z-]* --skill $s .*--doc-format $s\$" "$ROOT_DIR/$P/$f")
    [ "$n" -eq 3 ] && pass "/$s: round-started, verdicts and decision each pass --doc-format $s" || fail "/$s: $n review-events calls with --doc-format"
done

# Every fix is followed by sections and a post-fix check; every jury fix
# answers jury_fail; the unresolved line sends the skill to its escape.
for spec in "brief/references/phases/phase-4-validate.md jury_fail" "prd/references/phases/phase-4-validate.md jury_fail" \
    "design/references/phases/phase-6-final-review.md jury_fail" "vision/references/phases/phase-4-validate.md jury_fail" \
    "strategy/references/phases/phase-4-validate.md jury_fail" "roadmap/references/phases/phase-4-validate.md jury_fail" \
    "plan/references/phases/phase-7-creation.md check_fail"; do
    set -- $spec
    f=$1 ans=$2
    a=$(line_of "$f" "doc-events.sh\" fix ")
    b=$(line_of "$f" "doc-events.sh\" sections " "${a:-0}")
    c=$(line_of "$f" "--moment post_fix" "${a:-0}")
    if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ $((b - a)) -eq 1 ] && [ $((c - b)) -eq 1 ] \
        && sed -n "${a}p" "$ROOT_DIR/$P/$f" | grep -q -- "--answers $ans "; then
        pass "$f: fix ($ans), then sections, then the post-fix check"
    else
        fail "$f: fix sequence [$a $b $c]"
    fi
    grep -q 'unresolved after 3' "$ROOT_DIR/$P/$f" && grep -q -- '--auto' "$ROOT_DIR/$P/$f" \
        && pass "$f: an unresolved check takes the skill's escape, and its bail under --auto" || fail "$f: no escape for an unresolved check"
done
for f in brief/references/phases/phase-2-draft.md brief/references/phases/phase-3-structural-fill.md \
    prd/references/phases/phase-3-draft.md design/references/phases/phase-5-security.md plan/references/phases/phase-7-creation.md \
    vision/references/phases/phase-3-draft.md strategy/references/phases/phase-2-draft.md \
    strategy/references/phases/phase-3-structural-fill.md roadmap/references/phases/phase-3-draft.md; do
    grep -q 'doc-events.sh" sections ' "$ROOT_DIR/$P/$f" && pass "$f records the sections its commit wrote" || fail "$f: no sections call"
done

# The /scope hop gate stays the hop's final check and records nothing of its
# own: its evaluations reach the journal as koto's check_evaluated records.
hop="$ROOT_DIR/skills/scope/scripts/check-hop-document.sh"
if grep -v '^[[:space:]]*#' "$hop" | grep -qE 'doc-check\.sh|doc-events\.sh|review-events\.sh|review record'; then
    fail "check-hop-document.sh records check, section or fix events"
else
    pass "check-hop-document.sh records no check, section or fix event; its gate evaluations are koto's alone"
fi

# ================================================================== sessions

# cmd <file> <fixed text> [<nth>]: the nth command line (default 1) of a
# phase file holding the text, with its placeholders filled for topic t.
cmd() {
    local l
    l=$(grep -F -- "$2" "$ROOT_DIR/$P/$1" | grep '^ *"\${CLAUDE_PLUGIN_ROOT}/scripts/' | sed -n "${3:-1}p")
    [ -n "$l" ] || { echo "no command [$2] in $1" >&2; return 1; }
    printf '%s\n' "$l" | sed -e 's/^ *//' -e 's/<topic>/t/g' -e "s|<verdicts-dir>|$VD|g" -e "s|<reviews-dir>|$VD|g" \
        -e 's/<decision>/fix_and_proceed/g' -e 's|<plan-doc>|docs/plans/PLAN-t.md|g'
}
# step <file> <fixed text> [<nth>]: run that command from the fixture
# repository, as the skill would; its exit status is kept in RC.
RC=0
step() {
    local c
    c=$(cmd "$@") || { RC=99; return; }
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" eval "$c") >> "$WORKDIR/steps.out" 2>> "$WORKDIR/steps.err"
    RC=$?
}
# events <session>: the session's recorded events, one token each, in order.
events() {
    awk -v s="$1" '$1 == s {
        v = $2; m = ""
        for (i = 3; i < NF; i++) if ($i == "--moment" || $i == "--answers") m = $(i + 1)
        print (m == "" ? v : v ":" m) }' "$LOG" | tr '\n' ' '
}
# batches_of <session> <verb>: that verb's batches for the session, in order.
batches_of() {
    awk -v s="$1" -v v="$2" '/^file:/ { if (keep) print substr($0, 6); keep = 0; next } { keep = ($1 == s && $2 == v) }' "$LOG"
}
VD="$WORKDIR/verdicts"
seats() { # <format>: the seats' fixture files as the jury's ingested keys, and in the verdicts directory
    rm -rf "$VD"; mkdir -p "$VD"
    cp "$FIX/$1"/*.md "$VD/"
    local f
    for f in "$FIX/$1"/*.md; do dct_put "$1-t" "research/${f##*/}" < "$f"; done
}
doc_of() { jq -r --arg f "$1" '.formats[$f].paths[0] | sub("\\{topic\\}"; "t")' "$PHASES"; }
write_doc() { # <format>: every required section, written
    local d
    d=$(doc_of "$1")
    mkdir -p "$REPO/$(dirname "$d")"
    {
        printf -- '---\nschema: %s/v1\nstatus: Draft\n---\n\n# Doc\n' "$1"
        jq -r --arg f "$1" '.formats[$f].required_sections[]' "$PHASES" | while IFS= read -r s; do printf '\n## %s\n\nText.\n' "$s"; done
    } > "$REPO/$d"
}
edit_doc() { printf '\nA fix.\n' >> "$REPO/$(doc_of "$1")"; dct_commit "docs: fix the $1"; }
# parent <scope|charter> <child>: a chain parent that dispatched <child>.
parent() {
    dct_session "$1-t"
    printf 'main' | dct_put "$1-t" session/branch
    printf 'child: %s\nsuppress_status_aware_prompt: false\nrationale: fresh-chain\n' "$2" | dct_put "$1-t" chain/dispatch
}

# jury_run <format> <draft file> <draft text> <jury file> <seats> [<parent>]:
# a draft commit, the pre-jury check, a jury round whose seats FAIL, a fix in
# place, then the next round. Prints the record session's event tokens.
jury_run() {
    local f=$1 draft=$2 dtext=$3 jury=$4 nseats=$5 par=${6:-}
    dct_repo "$f-${par:-alone}"
    dct_session "$f-t"
    [ -z "$par" ] || parent "$par" "$f"
    dct_envelope 0
    write_doc "$f"
    dct_commit "docs: draft the $f"
    step "$draft" "$dtext"
    if [ "$f" = design ]; then
        step design/references/phases/phase-5-security.md "--moment pre_jury"
        printf '\nSecurity text.\n' >> "$REPO/$(doc_of design)"; dct_commit "docs: security"
        step design/references/phases/phase-5-security.md 'doc-events.sh" sections ' 2
        step design/references/phases/phase-5-security.md "--moment post_fix"
    fi
    step "$jury" "--moment pre_jury"
    step "$jury" "round-started --skill $f "
    seats "$f"
    step "$jury" "verdicts --skill $f "
    step "$jury" "decision --skill $f "
    edit_doc "$f"
    step "$jury" "--answers jury_fail"
    step "$jury" 'doc-events.sh" sections '
    step "$jury" "--moment post_fix"
    step "$jury" "--moment pre_jury"
    step "$jury" "round-started --skill $f "
}

# strip <tokens>: the tokens without the session, for comparing two runs.
for spec in "brief brief/references/phases/phase-2-draft.md brief/references/phases/phase-4-validate.md scope" \
    "prd prd/references/phases/phase-3-draft.md prd/references/phases/phase-4-validate.md scope" \
    "design design/references/phases/phase-5-security.md design/references/phases/phase-6-final-review.md scope" \
    "vision vision/references/phases/phase-3-draft.md vision/references/phases/phase-4-validate.md charter" \
    "strategy strategy/references/phases/phase-2-draft.md strategy/references/phases/phase-4-validate.md charter" \
    "roadmap roadmap/references/phases/phase-3-draft.md roadmap/references/phases/phase-4-validate.md charter"; do
    set -- $spec
    f=$1 draft=$2 jury=$3 par=$4
    : > "$WORKDIR/steps.err"
    jury_run "$f" "$draft" 'doc-events.sh" sections ' "$jury" 3 "$par"
    chained=$(events "$par-t")
    chained_checks=$(batches_of "$par-t" rule-checks | jq -c 'sort_by(.rule_id)' | tr '\n' ' ')
    chained_fixes=$(batches_of "$par-t" fix | jq -c 'sort_by(.rule_id)' | tr '\n' ' ')
    [ -z "$(events "$f-t")" ] && [ -n "$chained" ] \
        && pass "/$f under /$par: every record lands on $par-t" || fail "/$f under /$par: own session has [$(events "$f-t")]"

    # A pre-jury check before the first round.
    first_check=$(printf '%s\n' $chained | grep -n '^rule-checks:pre_jury$' | head -n 1 | cut -d: -f1)
    first_round=$(printf '%s\n' $chained | grep -n '^round-started$' | head -n 1 | cut -d: -f1)
    [ -n "$first_check" ] && [ -n "$first_round" ] && [ "$first_check" -lt "$first_round" ] \
        && pass "/$f under /$par: a pre-jury check precedes the first review round" || fail "/$f under /$par: order [$chained]"
    if [ "$f" = design ]; then
        n=$(printf '%s\n' $chained | grep -c '^rule-checks:pre_jury$')
        prev=$(printf '%s\n' $chained | sed -n "$((first_round - 1))p")
        [ "$n" -eq 2 ] && [ "$prev" = rule-checks:pre_jury ] \
            && pass "/design: one pre-jury check before the security review and one just before the panel's round" \
            || fail "/design: [$chained]"
    fi
    # After the round's FAIL: the fix, the sections, the post-fix check, then
    # the next round with no separate pre-jury check.
    tail_seq=$(printf '%s\n' $chained | awk '/^decision$/ { on = 1; next } on' | grep -v '^section-written$' | tr '\n' ' ')
    [ "$tail_seq" = "fix:jury_fail rule-checks:post_fix round-started " ] \
        && pass "/$f under /$par: the jury fix and a post-fix check come before the next round, which has no pre-jury check of its own" \
        || fail "/$f under /$par: after the decision [$tail_seq]"
    printf '%s\n' $chained | awk '/^fix:jury_fail$/ { on = 1; next } on && /^section-written$/ { s = 1 } on && /^rule-checks/ { exit !s }' \
        && pass "/$f under /$par: the fix commit's sections are recorded" || fail "/$f under /$par: no sections after the fix"
    fix_batch=$(batches_of "$par-t" fix | head -n 1)
    fix_rules=$(printf '%s' "$fix_batch" | jq -r '.[].rule_id' | sort -u | tr '\n' ' ')
    want_rules=$(cat "$FIX/$f"/*.md | awk '/^```review-verdicts/ { on = 1; next } /^```/ { on = 0 } on' \
        | jq -s -r 'add | map(select(.verdict == "FAIL") | .rule_id) | unique | .[]' | tr '\n' ' ')
    [ -n "$fix_rules" ] && [ "$fix_rules" = "$want_rules" ] \
        && pass "/$f under /$par: the fix answers the round's FAIL verdicts [$fix_rules]" || fail "/$f under /$par: fix [$fix_batch] want [$want_rules]"
    [ ! -s "$WORKDIR/steps.err" ] || ! grep -q 'refused' "$WORKDIR/steps.err" \
        && pass "/$f under /$par: no call was refused" || fail "/$f under /$par: $(grep refused "$WORKDIR/steps.err" | head -n 3 | tr '\n' '|')"

    # The same skill run standalone records the same events on its own session.
    jury_run "$f" "$draft" 'doc-events.sh" sections ' "$jury" 3
    alone=$(events "$f-t")
    alone_checks=$(batches_of "$f-t" rule-checks | jq -c 'sort_by(.rule_id)' | tr '\n' ' ')
    alone_fixes=$(batches_of "$f-t" fix | jq -c 'sort_by(.rule_id)' | tr '\n' ' ')
    [ "$alone" = "$chained" ] && [ "$alone_checks" = "$chained_checks" ] && [ "$alone_fixes" = "$chained_fixes" ] \
        && pass "/$f standalone and under /$par: the same events, moments, rule ids and outcomes" \
        || fail "/$f standalone [$alone] vs /$par [$chained]"
done

# Every recorded attribute is a closed-set value, a registered rule id, a
# declared name, other, a boolean or an integer.
bad=$(sed -n 's/^file://p' "$LOG" | jq -c '.[]' 2>/dev/null | jq -r '
    to_entries[] | .value as $v | select(
        (.key == "outcome" and ((["pass","fail","not_ready","error"] | index($v)) == null))
        or (.key == "verdict" and ((["PASS","FAIL"] | index($v)) == null))
        or ((.key == "section" or .key == "seat") and ((.value | type) != "string" or (.value | test("^[a-z0-9-]+$") | not)))
        or ((.key == "rule_id" or .key == "check_rule") and ((.value | type) != "string" or (.value | test("^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3}|rs-verdict-missing|none)$") | not)))
        or (.key == "round" and (.value | type) != "number")) | "\(.key)=\(.value)"' | sort -u | tr '\n' ' ')
[ -z "$bad" ] && pass "every recorded entry holds only closed-set values, rule ids, slugs, booleans or integers" || fail "attributes: $bad"
unreg=$(sed -n 's/^file://p' "$LOG" | jq -r '.[] | .rule_id, (.check_rule // empty)' | sort -u | grep -v '^none$' \
    | while IFS= read -r id; do "$ROOT_DIR/scripts/rule-registry.sh" resolve "$id" >/dev/null 2>&1 || echo "$id"; done | tr '\n' ' ')
[ -z "$unreg" ] && pass "every recorded rule id is registered" || fail "unregistered: $unreg"

# --- the fix loop: a block failure that persists, and a warn-stage one -------------

J=brief/references/phases/phase-4-validate.md
FC01='{"code":"FC01","severity":"error","message":"[FC01] missing required field status","file":"x","line":2}'
dct_repo persist
dct_session brief-t
write_doc brief
dct_commit "docs: draft the brief"
dct_envelope 2 "$FC01"
: > "$WORKDIR/steps.out"
step "$J" "--moment pre_jury"
pre_rc=$RC
step "$J" "round-started --skill brief "
[ "$pre_rc" -eq 1 ] && [ "$(events brief-t)" = "rule-checks:pre_jury round-started " ] \
    && pass "a failing pre-jury check exits 1 (the skill fixes before spawning)" || fail "pre-jury failure rc=$pre_rc [$(events brief-t)]"
: > "$LOG"; : > "$WORKDIR/steps.out"
printed=""
for i in 1 2 3 4; do
    edit_doc brief
    if [ "$i" -eq 1 ]; then step "$J" "--answers jury_fail"; else step "$J" "--answers jury_fail" | true; fi
    c=$(cmd "$J" "--answers jury_fail" | sed 's/--answers jury_fail/--answers check_fail/')
    [ "$i" -eq 1 ] || (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" eval "$c") >> "$WORKDIR/steps.out" 2>&1
    step "$J" 'doc-events.sh" sections '
    : > "$WORKDIR/check.out"
    c=$(cmd "$J" "--moment post_fix")
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" eval "$c") > "$WORKDIR/check.out" 2>/dev/null
    rc=$?
    grep -q '^doc-check: unresolved after 3 cycles$' "$WORKDIR/check.out" && printed="$printed$i"
    [ "$rc" -eq 1 ] || printed="${printed}x"
done
fixes=$(events brief-t | tr ' ' '\n' | grep -c '^fix:check_fail$')
checks=$(events brief-t | tr ' ' '\n' | grep -c '^rule-checks:post_fix$')
[ "$printed" = 4 ] && [ "$checks" -eq 4 ] && [ "$fixes" -ge 2 ] \
    && pass "a block failure that persists through three fix-and-check cycles prints the unresolved line at the fourth failing check" \
    || fail "persisting failure: printed [$printed] checks=$checks fixes=$fixes [$(events brief-t)]"
grep -q 'doc-check: unresolved after 3' "$ROOT_DIR/$P/$J" && grep -q 'under `--auto`, stop' "$ROOT_DIR/$P/$J" \
    && pass "/brief sends the unresolved line to its significant-issue path, and to its bail under --auto" || fail "/brief escape prose"

COPY="$RF_TEST_DIR/warn"
if rf_test_stage_copy "$COPY" docs/required-fields warn scripts/doc-check.sh scripts/doc-events.sh scripts/skill-session.sh \
    scripts/koto-open.sh references/doc-check-phases.json skills/writing-style/rules.yaml 2>"$WORKDIR/copy.err"; then
    dct_repo warn
    dct_session brief-t
    write_doc brief
    dct_commit "docs: draft the brief"
    dct_envelope 2 "$FC01"
    c=$(cmd "$J" "--moment post_fix" | sed "s|\"\${CLAUDE_PLUGIN_ROOT}\"|\"$COPY\"|; s|\${CLAUDE_PLUGIN_ROOT}|$COPY|")
    (cd "$REPO" && eval "$c") > "$WORKDIR/check.out" 2>/dev/null
    rc=$?
    outcome=$(batches_of brief-t rule-checks | jq -r '.[] | select(.rule_id == "docs/required-fields") | .outcome')
    [ "$rc" -eq 0 ] && [ "$outcome" = fail ] \
        && pass "a post-fix check failing only a warn-stage rule exits 0 (the run proceeds) with the fail recorded" \
        || fail "warn stage: rc=$rc outcome=[$outcome]"
else
    fail "could not make a plugin copy at warn: $(cat "$WORKDIR/copy.err")"
fi

# --- /plan and /review-plan ------------------------------------------------------------

dct_repo plan
dct_session plan-t
dct_envelope 0
step plan/references/phases/phase-6-review.md "--moment pre_jury"
nr=$(batches_of plan-t rule-checks | jq -r '[.[].outcome] | unique | join(",")')
[ "$RC" -eq 0 ] && [ "$(events plan-t)" = "rule-checks:pre_jury " ] && [ "$nr" = not_ready ] \
    && pass "/plan records not-ready check events at its review, before any PLAN exists" || fail "/plan review: rc=$RC [$(events plan-t)] [$nr]"
write_doc plan
dct_commit "docs(plan): add PLAN for t"
dct_envelope 2 "$FC01"
step plan/references/phases/phase-7-creation.md 'doc-events.sh" sections '
step plan/references/phases/phase-7-creation.md "--moment post_create"
create_rc=$RC
edit_doc plan
dct_envelope 0
step plan/references/phases/phase-7-creation.md "--answers check_fail"
step plan/references/phases/phase-7-creation.md 'doc-events.sh" sections ' 2
step plan/references/phases/phase-7-creation.md "--moment post_fix"
seq=$(events plan-t | sed 's/section-written //g')
[ "$create_rc" -eq 1 ] && [ "$seq" = "rule-checks:pre_jury rule-checks:post_create fix:check_fail rule-checks:post_fix " ] \
    && pass "/plan checks the written PLAN (post_create), and its fix is a fix event followed by a post-fix check" \
    || fail "/plan written PLAN: rc=$create_rc [$(events plan-t)]"

dct_repo review-plan
dct_session plan-t
dct_session review-plan-t
dct_envelope 0
write_doc plan
dct_commit "docs(plan): add PLAN for t"
step review-plan/references/phases/phase-0-setup.md "--moment pre_jury"
step review-plan/references/phases/phase-0-setup.md 'round-started --skill plan '
order=$(awk '{ print $1 " " $2 }' "$LOG" | grep -v '^file:' | tr '\n' '|')
[ "$order" = "review-plan-t rule-checks|plan-t round-started|" ] \
    && pass "/review-plan on a PLAN with no plan session records its pre-jury check on review-plan-t before its round starts" \
    || fail "/review-plan: [$order]"

rf_test_verify "doc-check-wiring" 2>/dev/null || true

echo
echo "doc-check-wiring_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
