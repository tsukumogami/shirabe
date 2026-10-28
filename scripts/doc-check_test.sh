#!/usr/bin/env bash
# doc-check_test.sh -- does doc-check.sh give every check-held rule the right
# outcome, hold only on a block-stage failure, keep its state, record its
# telemetry best effort, and refuse what it should?
#
# A stub `shirabe` supplies the validator's envelopes and a stub koto keeps
# sessions as directories, so the suite needs only bash, git and jq and runs
# on the bash 3.2 floor. The phase map's own consistency and the enumeration
# of error-level codes are checked against the registry and the validator's
# source.
#
# Usage: doc-check_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
CHECK="$SCRIPT_DIR/doc-check.sh"
PHASES="$ROOT_DIR/references/doc-check-phases.json"
REGISTRY="$ROOT_DIR/references/rule-registry.json"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-check-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */doc-check-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
ktg_on_exit cleanup

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"
# shellcheck source=lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/lib/rule-findings-testlib.sh"
rf_test_setup "$WORKDIR"

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
RC=0
# run [<script>] -- <args...>: doc-check from $REPO's root.
run() {
    local script=$CHECK
    if [ "$1" != -- ]; then script=$1; shift; fi
    shift
    (cd "$REPO" && "$script" "$@") > "$OUT" 2> "$ERR"
    RC=$?
}
# check_prd <moment> <phase> [<script>]: the usual PRD check of topic t.
check_prd() {
    run ${3:-} -- --doc docs/prds/PRD-t.md --format prd --moment "$1" --phase "$2" --topic t --skill prd
}
outcome() { sed -n "s|^doc-check: $1 ||p" "$OUT"; }
findings() { sed -n 's/^::koto-finding:://p' "$OUT"; }
finding_count() { findings | awk 'END { print NR }'; }
first_line() { head -n 1 "$OUT"; }
show() { printf 'rc=%s out=[%s] err=[%s]' "$RC" "$(head -c 600 "$OUT" | tr '\n' '|')" "$(head -c 400 "$ERR" | tr '\n' '|')"; }

FC01='{"code":"FC01","severity":"error","message":"[FC01] missing required field status","file":"x","line":2}'
CLEAN() { dct_envelope 0; }

prd_doc() {
    mkdir -p "$REPO/docs/prds"
    printf -- '---\nschema: prd/v1\nstatus: Draft\n---\n\n# PRD\n\n## Status\n\nDraft\n' > "$REPO/docs/prds/PRD-t.md"
}

# --- usage and input hardening ----------------------------------------------------

dct_repo usage
prd_doc
dct_commit "docs: a prd"
CLEAN
run -- --doc docs/prds/PRD-t.md --format prd
[ "$RC" -eq 2 ] && grep -q '^Usage: doc-check.sh' "$ERR" && pass "a missing argument is a usage error (exit 2)" || fail "usage: $(show)"
run -- --doc docs/prds/PRD-t.md --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic t --skill prd
[ "$RC" -eq 2 ] && pass "an argument given twice is refused" || fail "twice: $(show)"

refused() { # <label> <args...>
    local label=$1
    shift
    run -- "$@"
    if [ "$RC" -eq 2 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_LOG" ]; then
        pass "refused: $label"
    else
        fail "refused: $label: $(show)"
    fi
    : > "$STUB_LOG"
}
refused "--format outside the seven" --doc docs/prds/PRD-t.md --format comp --moment pre_jury --phase 4 --topic t --skill prd
refused "--moment outside its set" --doc docs/prds/PRD-t.md --format prd --moment later --phase 4 --topic t --skill prd
refused "--phase the format doesn't list" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 9 --topic t --skill prd
refused "--phase that is not a number" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 'x;y' --topic t --skill prd
refused "--topic outside the topic pattern" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic 'T/../x' --skill prd
refused "--skill outside the skill pattern" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic t --skill 'Prd;x'
refused "--doc not under docs/" --doc CLAUDE.md --format prd --moment pre_jury --phase 4 --topic t --skill prd
refused "--doc another format's path" --doc docs/prds/PRD-t.md --format brief --moment pre_jury --phase 4 --topic t --skill brief
refused "--doc another topic's path" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic u --skill prd
refused "--doc with a .. past a directory that doesn't exist" --doc docs/none/../prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic t --skill prd
mkdir -p "$WORKDIR/outside/docs/prds"
cp "$REPO/docs/prds/PRD-t.md" "$WORKDIR/outside/docs/prds/PRD-t.md"
ln -s "$WORKDIR/outside/docs/prds/PRD-t.md" "$REPO/link-out.md"
refused "--doc a symlink resolving outside the repository" --doc link-out.md --format prd --moment pre_jury --phase 4 --topic t --skill prd
cp "$REPO/docs/prds/PRD-t.md" "$REPO/docs/prds/PRD-other.md"
ln -s PRD-other.md "$REPO/docs/prds/PRD-u.md"
refused "--doc a symlink resolving to a non-canonical path" --doc docs/prds/PRD-u.md --format prd --moment pre_jury --phase 4 --topic u --skill prd
ln -s docs/prds/PRD-t.md "$REPO/link-in.md"
run -- --doc link-in.md --format prd --moment pre_jury --phase 4 --topic t --skill prd
[ "$RC" -eq 0 ] && [ "$(outcome docs/required-fields)" = pass ] \
    && pass "a symlink resolving to the canonical path is followed and checked" || fail "symlink in: $(show)"

# --- one case per format ----------------------------------------------------------

for f in brief prd design plan vision strategy roadmap; do
    dct_repo "format-$f"
    path=$(jq -r --arg f "$f" '.formats[$f].paths[0] | sub("\\{topic\\}"; "t")' "$PHASES")
    phase=$(jq -r --arg f "$f" '.formats[$f].phases | keys | last' "$PHASES")
    mkdir -p "$REPO/$(dirname "$path")"
    printf -- '---\nschema: x\n---\n\n## Status\n\nDraft\n' > "$REPO/$path"
    dct_commit "docs: $f"
    CLEAN
    run -- --doc "$path" --format "$f" --moment pre_jury --phase "$phase" --topic t --skill "$f"
    want=$(jq -r --arg f "$f" '.formats[$f].rules[] + " pass"' "$PHASES")
    got=$(sed -n 's/^doc-check: //p' "$OUT")
    if [ "$RC" -eq 0 ] && [ "$got" = "$want" ] && ! grep -q '^::koto-not-ready::' "$OUT" && [ "$(finding_count)" -eq 0 ]; then
        pass "$f: a clean envelope gives pass for every check-held rule, no marker, exit 0"
    else
        fail "$f clean: $(show)"
    fi
    # A missing document: every rule not_ready, the marker first, exit 0.
    rm -f "$REPO/$path"
    : > "$STUB_LOG"
    run -- --doc "$path" --format "$f" --moment pre_jury --phase "$phase" --topic t --skill "$f"
    want=$(jq -r --arg f "$f" '.formats[$f].rules[] + " not_ready"' "$PHASES")
    got=$(sed -n 's/^doc-check: //p' "$OUT")
    if [ "$RC" -eq 0 ] && [ "$(first_line)" = "::koto-not-ready::" ] && [ "$got" = "$want" ] \
        && ! grep -q 'validate --format json --visibility' "$STUB_LOG"; then
        pass "$f: a missing document is not_ready for every rule, marker first, no validator run, exit 0"
    else
        fail "$f missing: $(show)"
    fi
done

# --- fail, stages and exit codes --------------------------------------------------

dct_repo fail
prd_doc
dct_commit "docs: a prd"
dct_envelope 2 "$FC01"
check_prd pre_jury 4
ln=$(findings | jq -c '{rule_id, path, line, has_ref: (.rule_ref != null), level}')
if [ "$RC" -eq 1 ] && [ "$(outcome docs/required-fields)" = fail ] && [ "$(outcome docs/valid-status)" = pass ] \
    && [ "$ln" = '{"rule_id":"docs/required-fields","path":"docs/prds/PRD-t.md","line":2,"has_ref":true,"level":"error"}' ]; then
    pass "a block-stage failure: outcome fail, exit 1, one finding with rule id, file and line"
else
    fail "block fail: $(show) finding=$ln"
fi

LONG=$(awk 'BEGIN { for (i = 0; i < 60; i++) printf "0123456789" }')
dct_envelope 2 "{\"code\":\"FC01\",\"severity\":\"error\",\"message\":\"[FC01] $LONG\",\"file\":\"x\",\"line\":3}"
check_prd pre_jury 4
summary=$(jq -r '.rules[] | select(.id == "docs/required-fields") | .summary' "$REGISTRY")
detail=$(findings | jq -r '.message' | awk -v p="$summary: " '{ print substr($0, length(p) + 1) }')
case "$detail" in
    *...) [ "${#detail}" -eq 400 ] && pass "a long validator message is cut to 400 characters" || fail "cut: length ${#detail}" ;;
    *) fail "cut: no ... ($(show))" ;;
esac

for stage in warn shadow; do
    COPY="$RF_TEST_DIR/stage-$stage"
    if rf_test_stage_copy "$COPY" docs/required-fields "$stage" scripts/doc-check.sh scripts/skill-session.sh \
        scripts/koto-open.sh references/doc-check-phases.json skills/writing-style/rules.yaml 2>"$ERR"; then
        dct_envelope 2 "$FC01"
        check_prd post_fix 4 "$COPY/scripts/doc-check.sh"
        if [ "$RC" -eq 0 ] && [ "$(outcome docs/required-fields)" = fail ] && [ "$(finding_count)" -eq 0 ]; then
            pass "a $stage-stage failure: outcome fail, no finding line, exit 0"
        else
            fail "$stage stage: $(show)"
        fi
    else
        fail "could not make a plugin copy at $stage: $(cat "$ERR")"
    fi
    rm -rf "$COPY"
done

# --- error outcomes -----------------------------------------------------------------

dct_repo errors
prd_doc
dct_commit "docs: a prd"
printf 'oops, not JSON\n' > "$STUB_JSON"; STUB_RC=0
check_prd pre_jury 4
if [ "$RC" -eq 0 ] && [ -z "$(sed -n 's/^doc-check: [^ ]* //p' "$OUT" | grep -v '^error$')" ] \
    && grep -q 'defect: no validator verdict' "$ERR"; then
    pass "no envelope: every rule is error (not fail), a defect on stderr, exit 0"
else
    fail "no envelope: $(show)"
fi
CLEAN; STUB_RC=3
check_prd pre_jury 4
[ "$RC" -eq 0 ] && [ "$(outcome docs/required-fields)" = error ] && pass "a validator exiting 3: error, exit 0" || fail "exit 3: $(show)"
CLEAN
STUB_CANARY=none check_prd pre_jury 4
[ "$RC" -eq 0 ] && [ "$(outcome prose/banned-word)" = error ] && pass "a failed canary: error, exit 0" || fail "canary: $(show)"
dct_envelope 2 '{"code":"FC99","severity":"error","message":"[FC99] new","file":"x","line":3}' "$FC01"
check_prd pre_jury 4
if [ "$RC" -eq 1 ] && [ "$(outcome docs/valid-status)" = error ] && [ "$(outcome docs/required-fields)" = fail ] \
    && grep -q 'defect: the validator reported error-level code \[FC99\]' "$ERR"; then
    pass "an unmapped code: a defect on stderr, would-be passes become error, a real failure still fails"
else
    fail "unmapped code: $(show)"
fi
mkdir -p "$REPO/bin"
cp "$WORKDIR/stub-bin/shirabe" "$REPO/bin/shirabe"
CLEAN
(cd "$REPO" && PATH="$REPO/bin:$DCT_ORIG_PATH" "$CHECK" --doc docs/prds/PRD-t.md --format prd --moment pre_jury --phase 4 --topic t --skill prd) > "$OUT" 2> "$ERR"
RC=$?
[ "$RC" -eq 0 ] && [ "$(outcome docs/required-fields)" = error ] && grep -q 'inside the repository' "$ERR" \
    && pass "a validator inside the repository is refused: error, exit 0" || fail "in-repo validator: $(show)"
rm -rf "$REPO/bin"

# --- the phase map: not_ready for an unreached section ------------------------------

dct_repo phases
mkdir -p "$REPO/docs/designs"
printf -- '---\nschema: design/v1\n---\n\n## Status\n\nProposed\n' > "$REPO/docs/designs/DESIGN-t.md"
dct_commit "docs: a design"
dct_envelope 2 '{"code":"FC04","severity":"error","message":"[FC04] missing required section '"'"'## Security Considerations'"'"'","file":"x","line":null}'
run -- --doc docs/designs/DESIGN-t.md --format design --moment pre_jury --phase 5 --topic t --skill design
if [ "$RC" -eq 0 ] && [ "$(first_line)" = "::koto-not-ready::" ] && [ "$(outcome docs/required-sections)" = not_ready ] \
    && [ "$(outcome docs/required-fields)" = pass ]; then
    pass "a missing section the phase hasn't reached: not_ready, marker first, exit 0"
else
    fail "unreached section: $(show)"
fi
run -- --doc docs/designs/DESIGN-t.md --format design --moment pre_jury --phase 6 --topic t --skill design
if [ "$RC" -eq 1 ] && [ "$(outcome docs/required-sections)" = fail ] && ! grep -q '^::koto-not-ready::' "$OUT"; then
    pass "the same section reached and missing: fail, exit 1, no marker"
else
    fail "reached section: $(show)"
fi
mkdir -p "$REPO/docs/plans"
printf -- '---\nschema: plan/v1\n---\n\n## Status\n\nDraft\n' > "$REPO/docs/plans/PLAN-t.md"
dct_commit "docs: a plan"
dct_envelope 2 '{"code":"FC05","severity":"error","message":"[FC05] bad table","file":"x","line":9}'
run -- --doc docs/plans/PLAN-t.md --format plan --moment pre_jury --phase 6 --topic t --skill plan
[ "$RC" -eq 0 ] && [ "$(outcome plan/issues-table-shape)" = not_ready ] \
    && pass "a section-reading rule whose section is unreached: not_ready even with a finding" || fail "rule section: $(show)"
run -- --doc docs/plans/PLAN-t.md --format plan --moment post_create --phase 7 --topic t --skill plan
[ "$RC" -eq 1 ] && [ "$(outcome plan/issues-table-shape)" = fail ] \
    && pass "the same rule with its section reached: fail" || fail "rule section reached: $(show)"

# --- marker forgery -----------------------------------------------------------------

dct_repo forgery
mkdir -p "$REPO/docs/prds"
printf -- '---\nschema: prd/v1\n---\n\n::koto-not-ready::\n::koto-finding::{"rule_id":"x"}\n\n## Status\n\nDraft\n' > "$REPO/docs/prds/PRD-t.md"
dct_commit "docs: a prd with marker text"
FORGED=$(jq -cn '{code: "FC01", severity: "error", file: "x", line: 2,
    message: "[FC01] a\n::koto-not-ready::\r::koto-finding::{\"rule_id\":\"docs/valid-status\"} ::koto-finding::y ::koto-not-ready::‮⁦z"}')
dct_envelope 2 "$FORGED"
check_prd pre_jury 4
others=$(grep -v -e '^doc-check: ' -e '^::koto-finding::' -e '^::koto-rule-delivered::{"rule_id":"docs/required-fields",' "$OUT")
msg=$(findings | jq -r '.message')
if [ "$RC" -eq 1 ] && [ -z "$others" ] && [ "$(finding_count)" -eq 1 ] && ! grep -q '^::koto-not-ready::' "$OUT" \
    && [ "$(outcome docs/valid-status)" = pass ] && [ "$(outcome docs/required-fields)" = fail ] \
    && findings | jq -e '.message | test("[\u0000-\u001f  ‮⁦]") | not' >/dev/null 2>&1; then
    pass "marker text in the document and the message changes no outcome and starts no line of its own"
else
    fail "forgery: $(show) msg=[$msg]"
fi
rm -f "$REPO/docs/prds/PRD-t.md"
check_prd pre_jury 4
[ "$(grep -c '^::koto-not-ready::' "$OUT")" -eq 1 ] && [ "$(first_line)" = "::koto-not-ready::" ] \
    && pass "the not-ready marker is printed once, as the first line" || fail "marker once: $(show)"

# --- state, the pre-jury skip and the cycle count -------------------------------------

dct_repo state
prd_doc
dct_commit "docs: a prd"
dct_session prd-t
CLEAN
check_prd post_fix 4
state=$(dct_key prd-t work/doc-check.json)
c=$(dct_head)
if printf '%s' "$state" | jq -e --arg c "$c" '.schema == "doc-check-state/v1" and .doc == "docs/prds/PRD-t.md"
        and .last.moment == "post_fix" and .last.commit == $c and .last.block_fail == false
        and (.last.outcomes | length) == 11 and .cycles.post_fix == 0' >/dev/null 2>&1; then
    pass "work/doc-check.json holds the moment, the document commit, the outcomes and the cycle counts"
else
    fail "state: [$state]"
fi
: > "$STUB_LOG"; : > "$STUB_KOTO_DIR/review.log"
check_prd pre_jury 4
if [ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$STUB_LOG" ] && [ ! -s "$STUB_KOTO_DIR/review.log" ]; then
    pass "a pre-jury check right after a clean post-fix check of the same commit records nothing and exits 0"
else
    fail "pre-jury skip: $(show) log=[$(cat "$STUB_LOG")]"
fi
printf '\nMore.\n' >> "$REPO/docs/prds/PRD-t.md"
dct_commit "docs: change the prd"
check_prd pre_jury 4
[ "$RC" -eq 0 ] && [ -s "$OUT" ] && [ -s "$STUB_KOTO_DIR/review.log" ] \
    && pass "on a different commit the pre-jury check runs in full" || fail "pre-jury on a new commit: $(show)"
check_prd post_fix 4
printf '\nUncommitted.\n' >> "$REPO/docs/prds/PRD-t.md"
check_prd pre_jury 4
[ -s "$OUT" ] && pass "an uncommitted change to the document is not the same commit: the check runs" \
    || fail "dirty document skipped: $(show)"
git -C "$REPO" checkout -q -- docs/prds/PRD-t.md
check_prd post_fix 3
: > "$STUB_KOTO_DIR/review.log"
check_prd pre_jury 4
[ "$RC" -eq 0 ] && [ -s "$OUT" ] && [ -s "$STUB_KOTO_DIR/review.log" ] \
    && pass "a clean post-fix check at another phase doesn't serve the pre-jury check: it runs in full" \
    || fail "pre-jury after another phase's post-fix: $(show)"

dct_envelope 2 "$FC01"
lines=""
for i in 1 2 3 4; do
    check_prd post_fix 4
    grep -q '^doc-check: unresolved after 3 cycles$' "$OUT" && lines="$lines$i"
done
[ "$lines" = 4 ] && pass "the fourth failing check at one moment prints the unresolved line; the first three don't" \
    || fail "cycles: printed on [$lines]"
CLEAN
check_prd post_fix 4
[ "$(dct_key prd-t work/doc-check.json | jq -r '.cycles.post_fix')" = 0 ] \
    && pass "a check that doesn't fail sets its moment's count back to 0" || fail "cycle reset"

# --- telemetry ------------------------------------------------------------------------

dct_repo telemetry
prd_doc
dct_commit "docs: a prd"
dct_session prd-t
dct_envelope 2 "$FC01"
check_prd pre_jury 4
call=$(sed -n 1p "$STUB_KOTO_DIR/review.log")
batch=$(sed -n 's/^file://p' "$STUB_KOTO_DIR/review.log")
case "$call" in
    "prd-t rule-checks --doc-format prd --moment pre_jury --file "*)
        if printf '%s' "$batch" | jq -e 'length == 11 and all(.[]; keys == ["outcome", "rule_id"])
                and (map(select(.rule_id == "docs/required-fields"))[0].outcome == "fail")' >/dev/null 2>&1; then
            pass "the outcomes are recorded with koto review record rule-checks on the skill's session"
        else
            fail "batch: [$batch]"
        fi ;;
    *) fail "record call: [$call]" ;;
esac
grep -q -- "--file $WORKDIR" "$STUB_KOTO_DIR/review.log" && fail "the batch file lives in the test's directory" \
    || pass "the batch file is outside the repository and the suite's tree (a private scratch directory)"

# The chain's parent, when it dispatched this skill, gets the records.
dct_session scope-t
printf 'main' | dct_put scope-t session/branch
printf 'child: prd\nsuppress_status_aware_prompt: false\nrationale: fresh-chain\n' | dct_put scope-t chain/dispatch
: > "$STUB_KOTO_DIR/review.log"
check_prd post_fix 4
grep -q '^scope-t rule-checks ' "$STUB_KOTO_DIR/review.log" \
    && pass "a skill dispatched by /scope records on the scope session" || fail "dispatch: [$(cat "$STUB_KOTO_DIR/review.log")]"
[ "$(dct_key prd-t work/doc-check.json | jq -r '.last.moment')" = post_fix ] \
    && pass "the state stays in the skill's own session" || fail "state session"
rm -rf "$STUB_KOTO_DIR/s/scope-t"

# A check-held rule the registry doesn't hold is dropped from the batch.
COPY="$RF_TEST_DIR/dropped"
if rf_test_stage_copy "$COPY" docs/required-fields block scripts/doc-check.sh scripts/skill-session.sh \
    scripts/koto-open.sh references/doc-check-phases.json skills/writing-style/rules.yaml 2>"$ERR"; then
    jq '.rules |= map(select(.id != "docs/upstream-lifetime"))' "$COPY/references/rule-registry.json" > "$COPY/reg.tmp" \
        && mv "$COPY/reg.tmp" "$COPY/references/rule-registry.json"
    CLEAN
    : > "$STUB_KOTO_DIR/review.log"
    check_prd pre_jury 4 "$COPY/scripts/doc-check.sh"
    batch=$(sed -n 's/^file://p' "$STUB_KOTO_DIR/review.log")
    if [ "$(outcome docs/upstream-lifetime)" = pass ] \
        && printf '%s' "$batch" | jq -e 'length == 10 and all(.[]; .rule_id != "docs/upstream-lifetime")' >/dev/null 2>&1; then
        pass "an entry whose rule id the registry lacks is dropped before the call"
    else
        fail "dropped entry: $(show) batch=[$batch]"
    fi
else
    fail "could not make a plugin copy: $(cat "$ERR")"
fi
rm -rf "$COPY"

# Recording failures change nothing but stderr.
dct_envelope 2 "$FC01"
ref_run() { # a run with working recording, from a fresh state
    rm -f "$STUB_KOTO_DIR/s/prd-t/work_doc-check.json"
    check_prd post_fix 4
    cp "$OUT" "$WORKDIR/ref.out"
    REF_RC=$RC
}
for mode in missing refuse; do
    ref_run
    rm -f "$STUB_KOTO_DIR/s/prd-t/work_doc-check.json"
    STUB_KOTO_REVIEW=$mode check_prd post_fix 4
    if [ "$RC" -eq "$REF_RC" ] && cmp -s "$OUT" "$WORKDIR/ref.out" \
        && [ "$(grep -c 'notice: telemetry for the rule checks was not recorded' "$ERR")" -eq 1 ]; then
        pass "recording refused ($mode): one notice; outcome, stdout and exit unchanged"
    else
        fail "recording $mode: $(show)"
    fi
done
ref_run
rm -rf "$STUB_KOTO_DIR/s/prd-t"
check_prd post_fix 4
if [ "$RC" -eq "$REF_RC" ] && cmp -s "$OUT" "$WORKDIR/ref.out" \
    && [ "$(grep -c 'notice: telemetry for the rule checks was not recorded' "$ERR")" -eq 1 ]; then
    pass "no session: one notice per failed call; outcome, stdout and exit unchanged"
else
    fail "no session: $(show)"
fi
(cd "$REPO" && KOTO_BIN="$WORKDIR/no-such-koto" "$CHECK" --doc docs/prds/PRD-t.md --format prd --moment post_fix --phase 4 --topic t --skill prd) > "$OUT" 2> "$ERR"
RC=$?
if [ "$RC" -eq "$REF_RC" ] && cmp -s "$OUT" "$WORKDIR/ref.out" \
    && [ "$(grep -c 'telemetry for the rule checks was not recorded' "$ERR")" -eq 1 ]; then
    pass "koto absent: one notice for the call; outcome, stdout and exit unchanged"
else
    fail "koto absent: $(show)"
fi

# --- the phase map and the registry ----------------------------------------------------

rule_ids=$(sed -n 's/^RULE_IDS="\(.*\)"$/\1/p' "$CHECK")
bad=""
for f in $(jq -r '.formats | keys[]' "$PHASES"); do
    extra=$(jq -r --arg f "$f" '.formats[$f] as $x
        | ($x.phases | to_entries[] | .value[] | select(. as $s | $x.required_sections | index($s) | not)),
          ($x.rule_sections | to_entries[] | .value[] | select(. as $s | $x.required_sections | index($s) | not))' "$PHASES")
    [ -z "$extra" ] || bad="$bad $f:[$extra]"
    for r in $(jq -r --arg f "$f" '.formats[$f].rules[], (.formats[$f].rule_sections | keys[])' "$PHASES"); do
        case " $rule_ids " in *" $r "*) ;; *) bad="$bad $f:$r-not-in-RULE_IDS" ;; esac
        jq -e --arg r "$r" '.rules[] | select(.id == $r and .status == "active")' "$REGISTRY" >/dev/null 2>&1 \
            || bad="$bad $f:$r-not-active"
    done
done
[ -z "$bad" ] && pass "every phase and rule section names a section the format requires, and every rule is active and in RULE_IDS" \
    || fail "phase map: $bad"
[ "$(jq -r '.formats | keys | sort | join(" ")' "$PHASES")" = "brief design plan prd roadmap strategy vision" ] \
    && pass "the phase map covers exactly the seven formats" || fail "phase map formats"

# The enumeration: every error-level code a format can emit, against the
# validator's own lists when its source is here, and the codes still lacking a
# registered id reported, not failed.
SRC="$ROOT_DIR/crates/shirabe-validate/src/validate.rs"
listed=$(jq -r '[.formats[].error_codes[]] | unique | .[]' "$PHASES" | sort)
if [ -f "$SRC" ]; then
    known=$(awk '/pub fn is_known_check_code/ { on = 1 } on { print } on && /^}/ { exit }' "$SRC" | grep -o '"[A-Z0-9-]*"' | tr -d '"' | sort -u)
    notice=$(awk '/fn is_intrinsic_notice/ { on = 1 } on { print } on && /^}/ { exit }' "$SRC" | grep -o '"[A-Z0-9-]*"' | tr -d '"' | sort -u)
    # R9 fires only for a private-only format (COMP), none of the seven; FC10
    # is a notice the checks hold on for its banned words.
    want=$( { comm -23 <(printf '%s\n' "$known") <(printf '%s\n' "$notice") | grep -v -x R9; echo FC10; } | sort -u)
    missing=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$listed"))
    [ -z "$missing" ] && pass "the phase map's error_codes cover every error-level code the validator can emit for the seven formats" \
        || fail "error codes the phase map doesn't list: $missing"
else
    echo "SKIP: $SRC not present -- the error-code enumeration was not compared with the validator"
fi
lacking=""
for code in $listed; do
    id=$(jq -r --arg c "$code" '[.rules[] | select(.status == "active" and ((.aliases // []) | index($c))) | .id] | first // ""' "$REGISTRY")
    [ -n "$id" ] || lacking="$lacking $code"
done
echo "REPORT: error-level codes with no registered id yet:${lacking:- none}"
pass "the enumeration lists every error-level code and reports those lacking a registered id"

# Every error-level code a VISION, STRATEGY, ROADMAP or PLAN can emit, seeded
# one at a time, fails the rule it maps to and leaves no rule in error.
seeded_bad=""
for f in vision strategy roadmap plan; do
    dct_repo "seed-$f"
    doc=$(jq -r --arg f "$f" '.formats[$f].paths[0] | sub("\\{topic\\}"; "t")' "$PHASES")
    mkdir -p "$REPO/$(dirname "$doc")"
    printf -- '---\nschema: %s/v1\nstatus: Draft\n---\n\n# Doc\n\n## Status\n\nDraft\n' "$f" > "$REPO/$doc"
    dct_commit "docs: a $f"
    dct_session "$f-t"
    phase=$(jq -r --arg f "$f" '.formats[$f].phases | keys | last' "$PHASES")
    for code in $(jq -r --arg f "$f" '.formats[$f].error_codes[]' "$PHASES"); do
        rule=$(jq -r --arg c "$code" '[.rules[] | select(.status == "active" and ((.aliases // []) | index($c))) | .id] | first // ""' "$REGISTRY")
        if [ -z "$rule" ]; then seeded_bad="$seeded_bad $f:$code-unregistered"; continue; fi
        msg="[$code] seeded"
        [ "$code" = FC04 ] && msg="[FC04] missing required section '## Status'"
        dct_envelope 2 "$(jq -cn --arg c "$code" --arg m "$msg" '{code: $c, severity: "error", message: $m, file: "x", line: 9}')"
        run -- --doc "$doc" --format "$f" --moment post_fix --phase "$phase" --topic t --skill "$f"
        [ "$(outcome "$rule")" = fail ] || seeded_bad="$seeded_bad $f:$code->$rule:$(outcome "$rule")"
        grep -q '^doc-check: [^ ]* error$' "$OUT" && seeded_bad="$seeded_bad $f:$code-error"
    done
done
[ -z "$seeded_bad" ] && pass "each seeded error-level VISION, STRATEGY, ROADMAP and PLAN code fails its registered rule, with no error outcome" \
    || fail "seeded codes: $seeded_bad"

# --- source properties ---------------------------------------------------------------

for s in "$CHECK" "$SCRIPT_DIR/doc-events.sh" "$SCRIPT_DIR/lib/doc-validate.sh" "$SCRIPT_DIR/lib/doc-session.sh"; do
    if grep -nE '^[[:space:]]*set[[:space:]]+-[a-z]*e' "$s" >/dev/null; then
        fail "$(basename "$s") uses set -e"
    else
        pass "$(basename "$s") has no set -e"
    fi
done
revs=$(grep -nE 'git (show|log|rev-parse|diff|cat-file)' "$CHECK" "$SCRIPT_DIR/doc-events.sh" "$SCRIPT_DIR/lib/doc-session.sh" \
    | grep -v -- '--end-of-options' | grep -v -- '--show-toplevel' | grep -v '^[^:]*:[0-9]*:[[:space:]]*#')
[ -z "$revs" ] && pass "every revision argument follows --end-of-options" || fail "revision without --end-of-options: $revs"
grep -q 'BATCH=$(mktemp "$WORK/' "$CHECK" && grep -q 'WORK=$(mktemp -d' "$CHECK" && grep -q 'chmod 700 "$WORK"' "$CHECK" \
    && grep -q 'BATCH=$(mktemp "$WORK/' "$SCRIPT_DIR/doc-events.sh" \
    && pass "each --file batch is a mktemp file in a private scratch directory" || fail "batch files"

rf_test_verify "doc-check"

echo
echo "doc-check_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
