#!/usr/bin/env bash
# check-rule-registry_test.sh -- tests for check-rule-registry.sh and
# check-rule-registry-adoption.sh.
#
# The standing check runs against a scratch copy of the files it reads. The
# copy is a git repository whose object store borrows the real one's, so the
# baseline's pinned commit resolves there as it does in CI. The unaltered copy
# must pass; each case then alters one thing, expects exit 1 and the problem
# line that names it, and restores the copy. The adoption script runs against
# small scratch repositories with a base commit and a working tree.
#
# Run from anywhere: bash scripts/check-rule-registry_test.sh

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -P -- "$SCRIPT_DIR/.." && pwd -P)
CHECK="$SCRIPT_DIR/check-rule-registry.sh"
ADOPT="$SCRIPT_DIR/check-rule-registry-adoption.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ $# -lt 2 ] || printf '  %s\n' "$2"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-rule-registry-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$WORK"'

GIT_ID="-c user.name=test -c user.email=test@example.com -c commit.gpgsign=false"

# ---------------------------------------------------------------- the copy

S="$WORK/s"
git init -q "$S"
# The common directory, not the git directory: in a linked worktree the
# objects live with the main checkout. git prints it relative to the
# repository root or absolute.
COMMON=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
case "$COMMON" in /*) ;; *) COMMON="$REPO_ROOT/$COMMON" ;; esac
echo "$COMMON/objects" > "$S/.git/objects/info/alternates"

# The copy is a sparse checkout, not a recursive copy: it writes only the
# files the check reads (the scanned scripts, the templates, every path the
# registry names) rather than every file under skills/ and scripts/, where the
# recursive copy it replaces wrote over a thousand files per run, each one
# scanned by the host. It is cut from `git stash create` when the checkout
# has uncommitted changes to tracked files, so it holds what the suite is
# testing; a file nothing has added yet is not in it, so `git add` a new file
# the check reads before running the suite. Its HEAD is that commit, the base
# the --base cases build on.
SNAP=$(git -C "$REPO_ROOT" stash create 2>/dev/null) || SNAP=""
[ -n "$SNAP" ] || SNAP=$(git -C "$REPO_ROOT" rev-parse HEAD) || { echo "no commit to test" >&2; exit 2; }
git -C "$S" config core.sparseCheckout true
git -C "$S" config core.sparseCheckoutCone false
{
    printf '%s\n' /references/ /hooks/ /scripts/lib/ '/scripts/*.sh' /scripts/review-shadow/criteria.json \
        '/skills/*/scripts/*.sh' '/skills/*/koto-templates/*.md' /CLAUDE.md /.claude-plugin/plugin.json \
        /docs/designs/current/DESIGN-output-gates.md /docs/measurement/offload-baseline/template-pin.json \
        /.github/workflows/check-rule-registry.yml /.github/workflows/validate-pr-body.yml
    git -C "$REPO_ROOT" show "$SNAP:references/rule-registry.json" | jq -r '.rules[]
        | (.text.path?, .check.path?, .backstop.check?, .deny.hook?, (.fixtures[]?), (.stage_backstops[]?.check))
        | strings | "/" + .'
} > "$S/.git/info/sparse-checkout"
git -C "$S" checkout -q --detach "$SNAP" || { echo "could not check out the scratch copy" >&2; exit 2; }

REG="$S/references/rule-registry.json"
MUTABLE="references/rule-registry.json references/rule-registry.md references/pr-body-conformance.md
docs/measurement/offload-baseline/template-pin.json .github/workflows/check-rule-registry.yml
docs/designs/current/DESIGN-output-gates.md skills/execute/koto-templates/execute.md
skills/work-on/scripts/check-pr-output.sh skills/execute/scripts/adopt-or-create-pr.sh
skills/work-on/scripts/panel-scope.sh hooks/pre-action-deny.sh"
mkdir -p "$WORK/orig"
for f in $MUTABLE; do
    mkdir -p "$WORK/orig/$(dirname "$f")"
    cp "$S/$f" "$WORK/orig/$f"
done
reset_copy() {
    local f
    for f in $MUTABLE; do cp "$WORK/orig/$f" "$S/$f"; done
}

# reg <jq filter>: rewrite the copy's registry through a jq filter.
reg() {
    jq "$1" "$WORK/orig/references/rule-registry.json" > "$REG" || { echo "bad test filter: $1" >&2; exit 2; }
}

run_check() {
    OUT=$("$CHECK" --root "$S" "$@" 2>&1)
    RC=$?
}

# altered: 0 when some file of the copy differs from its original, so a case
# whose alteration silently failed can't pass on the unaltered copy.
altered() {
    local f
    for f in $MUTABLE; do
        cmp -s "$WORK/orig/$f" "$S/$f" || return 0
    done
    return 1
}

# expect_problem <label> <substring> [check args]: exit 1 and a problem line
# holding <substring>. The copy is restored afterwards.
expect_problem() {
    local label=$1 want=$2
    shift 2
    if ! altered; then
        fail "$label" "the case altered nothing"
        reset_copy
        return
    fi
    run_check "$@"
    if [ "$RC" = 1 ] && grep -qF -- "$want" <<<"$OUT"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want 1 and [$want]; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_copy
}

# expect_clean <label>: exit 0 on an altered copy. The copy is restored
# afterwards.
expect_clean() {
    local label=$1
    if ! altered; then
        fail "$label" "the case altered nothing"
        reset_copy
        return
    fi
    run_check
    if [ "$RC" = 0 ]; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want 0; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_copy
}

G=pr-body/no-heading-in-part1
G2=pr-body/one-separator
RS=rs-004
TK=execute/pr-takeover-needs-signal
sel() { printf '(.rules[] | select(.id == "%s"))' "$1"; }

# ---------------------------------------------------------------- control

run_check
[ "$RC" = 0 ] && pass "the unaltered copy passes" || fail "the unaltered copy passes" "rc=$RC: $OUT"

OUT=$("$CHECK" 2>&1); RC=$?
[ "$RC" = 0 ] && pass "the repository itself passes" || fail "the repository itself passes" "rc=$RC: $OUT"

# ---------------------------------------------------------------- shape

reg "del($(sel $G).summary)"
expect_problem "a missing field" "$G: missing field summary"

reg '.rules = []'
expect_problem "an empty registry" "the registry has no active entries"

reg "$(sel $G).level = \"hard\""
expect_problem "an out-of-vocabulary value" "level \"hard\" is not gate"

reg ".rules += [$(sel $TK) | .id = \"Takeover_Copy\" | .notes = \"copy\"]"
expect_problem "an id matching neither pattern" "id \"Takeover_Copy\" matches neither"

reg ".rules += [$(sel $TK)]"
expect_problem "a duplicate id" "id $TK is used by more than one entry"

reg "$(sel $TK).aliases = [\"PB1\"]"
expect_problem "a duplicate alias" "alias PB1 is used more than once"

reg "$(sel $TK).aliases = [\"$G\"]"
expect_problem "an alias equal to an id" "$TK: alias $G is also an id"

reg "$(sel $RS).guards = [\"deploy\"]"
expect_problem "a guard outside the vocabulary" "$RS: guard \"deploy\" is not in the vocabulary"

reg "$(sel $RS).guards = [\"none\", \"push\"]"
expect_problem "none mixed with another guard" "$RS: none is mixed with other guards"

reg "$(sel $RS).timing = [\"work-on:no_such_state\"]"
expect_problem "a timing naming no state section" "names no '## no_such_state' section"

reg "$(sel $G).summary = \"one\\u0001two\""
expect_problem "a summary with a control character" "$G: summary holds a control character"

reg "$(sel $G).summary = \"one :: two\""
expect_problem "a summary with ::" "$G: summary holds the marker ::"

# ---------------------------------------------------------------- withhold

reg "$(sel $RS).guards = [\"push\"]"
expect_problem "an eligible entry with a protected guard" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).guards = [\"merge\"]"
expect_problem "an eligible entry guarding merge" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).guards = [\"pr-create\"]"
expect_problem "an eligible entry guarding pr-create" "$RS: a protected guard requires withhold never"

reg "$(sel $RS).check = {\"kind\": \"none\"}"
expect_problem "an eligible entry with check none" "$RS: check.kind none requires withhold never"

reg "$(sel $G2).guards = [\"none\"]"
expect_problem "a gate entry guarding none" "$G2: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"eligible\""
expect_problem "an eligible gate entry with no backstop" "$G2: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G2).withhold = \"eligible\""
expect_problem "another gate entry marked eligible with its guards" "$G2: a protected guard requires withhold never"

reg "del($(sel $G).backstop)"
expect_problem "the eligible gate entry without its backstop" "$G: a gate entry needs a guard other than none, or a backstop"

reg "$(sel $G).backstop.before = \"deploy\""
expect_problem "a backstop before an unprotected action" "$G: backstop.before \"deploy\" is not a protected action"

reg "$(sel $G).backstop.check = \"\""
expect_problem "a backstop with no check" "$G: backstop.check is not a path"

reg "$(sel $G).backstop.check = \".github/workflows/no-such.yml\""
expect_problem "a backstop check that does not exist" "$G: backstop path .github/workflows/no-such.yml does not exist"

reg "$(sel $G).guards = [\"merge\"]"
expect_problem "a backstop beside a protected guard" "$G: a backstop needs guards [\"none\"]"

reg "$(sel $G).withhold = \"never\""
expect_problem "a backstop on a never-withhold entry" "$G: a backstop needs withhold eligible"

reg "$(sel $G).notes = \"\""
expect_problem "a backstop with no notes" "$G: a backstop needs notes saying why"

reg "$(sel $RS).backstop = {\"before\": \"merge\", \"check\": \".github/workflows/validate-pr-body.yml\"}"
expect_problem "a backstop on a review-shadow entry" "$RS: a backstop needs level gate"

reg "$(sel $TK).check = {\"kind\": \"script\", \"path\": \"skills/execute/scripts/adopt-or-create-pr.sh\"}"
expect_problem "a prose entry with a check" "$TK: a prose entry must have check.kind none"

# A decider check: a koto decider-check gate's criterion. It guards nothing,
# so check 2's guard rule doesn't apply to it, while a script gate with the
# same fields still fails ("a gate entry guarding none" above). The lifecycle
# fields belong to script entries only, so the converted entry drops them.
DECIDER='{"kind": "decider", "template": "skills/work-on/koto-templates/work-on.md", "state": "review_level_check", "gate": "level_fits_facts", "criterion": "level_fits_facts"}'
reg "$(sel $G2).check = $DECIDER | $(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"never\"
     | del($(sel $G2).stage, $(sel $G2).stage_since, $(sel $G2).gates, $(sel $G2).stage_backstops)"
expect_clean "a decider entry guarding none"

reg "$(sel $RS).jev = {\"state\": \"rejected\"}"
expect_clean "a jev object on an entry"

reg "$(sel $G2).check = ($DECIDER | del(.gate))"
expect_problem "a decider check with no gate" "$G2: a decider check has no gate"

reg "$(sel $G2).check = ($DECIDER | .criterion = \"\")"
expect_problem "a decider check with an empty criterion" "$G2: a decider check has no criterion"

reg "$(sel $RS).jev = []"
expect_problem "a jev that is not an object" "$RS: jev is not an object"

reg "$(sel $G2).check = {\"kind\": \"jev\"}"
expect_problem "an unknown check kind" "check.kind \"jev\" is not script, review-shadow, decider or none"

# ---------------------------------------------------------------- paths

reg "$(sel $G).check.path = \"skills/work-on/scripts/no-such-check.sh\""
expect_problem "a missing check path" "$G: check path skills/work-on/scripts/no-such-check.sh does not exist"

reg "$(sel $G2).check = ($DECIDER | .template = \"skills/work-on/koto-templates/no-such.md\") | $(sel $G2).guards = [\"none\"] | $(sel $G2).withhold = \"never\""
expect_problem "a decider check naming a missing template" "$G2: template path skills/work-on/koto-templates/no-such.md does not exist"

reg "$(sel $G).fixtures = [\"scripts/no-such_test.sh\"]"
expect_problem "a missing fixture" "$G: fixture path scripts/no-such_test.sh does not exist"

reg "$(sel $RS).check.criterion = \"rs-999\""
expect_problem "a criterion absent from criteria.json" "$RS: review-shadow criterion rs-999 is not in criteria.json"

reg "$(sel $G).text.path = \"../outside.md\""
expect_problem "an unsafe path" "$G: text path [../outside.md] is unsafe"

# ---------------------------------------------------------------- pointers

reg "$(sel $G).text.first = \"PB4\""
expect_problem "an anchor found twice" "first anchor is not on exactly one line"

reg "$(sel $G).text.first = \"no line says this 7f3a\""
expect_problem "an anchor found zero times" "first anchor is not on exactly one line"

reg "$(sel $G).text.last = \"# PR-body conformance: the mechanical rule\""
expect_problem "a last anchor before the first" "last anchor is not at or after its first"

awk '{ print } index($0, "**PB4 — no markdown section heading in Part 1.**") { print "::shirabe-rule-end::" }' \
    "$WORK/orig/references/pr-body-conformance.md" > "$S/references/pr-body-conformance.md"
expect_problem "a marker line in a range" "$G: its range holds a ::shirabe-rule marker line"

reg "$(sel $RS).status = \"retired\" | $(sel $RS).text.first = \"no line says this 7f3a\""
run_check
[ "$RC" = 0 ] && pass "a retired entry with an unresolvable anchor passes" \
    || fail "a retired entry with an unresolvable anchor passes" "rc=$RC: $OUT"
reset_copy

# ---------------------------------------------------------------- review-shadow

reg ".rules += [$(sel $RS) | .id = \"rs-998\" | .check.criterion = \"rs-998\"]"
expect_problem "an rs- id only in the registry" "rs-998: in the registry but not in criteria.json"

reg "del(.rules[] | select(.id == \"$RS\"))"
expect_problem "an rs- id only in criteria.json" "$RS: in criteria.json but not in the registry"

reg "$(sel $RS).text.path = \"references/wip-hygiene.md\""
expect_problem "a mismatched criterion path" "$RS: text.path \"references/wip-hygiene.md\" differs from the criterion rule_ref"

# ---------------------------------------------------------------- printable ids

sed 's#^\(RULE_IDS="pr-body/conventional-title\)#\1 pr-body/not-registered#' \
    "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" > "$S/skills/work-on/scripts/check-pr-output.sh"
expect_problem "an unregistered RULE_IDS id" "RULE_IDS names pr-body/not-registered"

sed 's|^RULE_IDS="\(.*\)"$|RULE_IDS="\1" # trailing words|' \
    "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" > "$S/skills/work-on/scripts/check-pr-output.sh"
# The line is read from the script rather than pinned, so its header can grow.
RULE_IDS_LINE=$(grep -n '^RULE_IDS=' "$WORK/orig/skills/work-on/scripts/check-pr-output.sh" | cut -d: -f1)
expect_problem "a malformed RULE_IDS line" "check-pr-output.sh:$RULE_IDS_LINE: malformed RULE_IDS line"

# The declared exception: RULE_IDS_ANY_ACTIVE=1 beside an rf_require_any call,
# in panel-scope.sh only. Each case builds its alteration from the original so
# it holds whether or not the original already carries the pair.
PS=skills/work-on/scripts/panel-scope.sh
PO=skills/work-on/scripts/check-pr-output.sh
{ cat "$WORK/orig/$PO"; echo 'RULE_IDS_ANY_ACTIVE=1'; echo 'rf_require_any "$id"'; } > "$S/$PO"
expect_problem "the any-active marker outside the allowed script" "RULE_IDS_ANY_ACTIVE is allowed only in"

{ sed 's/rf_require_any/rf_require_some/g; /^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PS"; echo 'RULE_IDS_ANY_ACTIVE=1'; } > "$S/$PS"
expect_problem "the any-active marker with no rf_require_any call" "declares RULE_IDS_ANY_ACTIVE=1 but never calls rf_require_any"

{ sed '/^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PO"; echo 'rf_require_any "$id"'; } > "$S/$PO"
expect_problem "an rf_require_any call with no marker" "calls rf_require_any without declaring RULE_IDS_ANY_ACTIVE=1"

{ sed '/^RULE_IDS_ANY_ACTIVE=/d' "$WORK/orig/$PS"; echo 'RULE_IDS_ANY_ACTIVE=yes'; } > "$S/$PS"
expect_problem "a malformed any-active marker" "malformed RULE_IDS_ANY_ACTIVE line"

# The hook's RULE_IDS line is read like a gate script's. Its suite's own
# RULE_IDS=$(...) line is not a declaration: the unaltered copy carries it and
# passes.
HK=hooks/pre-action-deny.sh
# The line the checker names, read from the script so an edit above it
# doesn't break these cases.
HKL="$HK:$(grep -n '^RULE_IDS="' "$WORK/orig/$HK" | cut -d: -f1)"
sed 's#^\(RULE_IDS="pr-body/conventional-title\)#\1 pr-body/not-registered#' "$WORK/orig/$HK" > "$S/$HK"
expect_problem "an unregistered RULE_IDS id in a hook script" "$HKL: RULE_IDS names pr-body/not-registered, which is not"

# ---------------------------------------------------------------- hook links

P=commit/no-ai-trailer

reg "$(sel $G).deny = \"$HK\""
expect_problem "a deny that is not an object" "$G: deny is not an object"

reg "$(sel $G).deny = {\"before\": [\"pr-create\"]}"
expect_problem "a deny with no hook" "$G: deny.hook is not a path"

reg "$(sel $G).deny.befor = [\"pr-create\"]"
expect_problem "a deny with an unknown field" "$G: deny has a field other than hook and before: befor"

reg "$(sel $G).deny.hook = \"../outside.sh\""
expect_problem "a deny naming an unsafe path" "$G: deny.hook [../outside.sh] is unsafe"

reg "$(sel $G).deny.hook = \"hooks/no-such-hook.sh\""
expect_problem "a deny naming a missing file" "$G: deny.hook hooks/no-such-hook.sh does not exist"

reg "$(sel $P).deny.before = []"
expect_problem "a deny with an empty before" "$P: deny.before is not a non-empty list"

reg "$(sel $P).deny.before = \"push\""
expect_problem "a deny whose before is not a list" "$P: deny.before is not a non-empty list"

reg "$(sel $P).deny.before = [\"push\", \"deploy\"]"
expect_problem "a deny before an unprotected action" "$P: deny.before \"deploy\" is not a protected action"

reg "$(sel $P).deny.before = [\"none\"]"
expect_problem "a deny before none" "$P: deny.before \"none\" is not a protected action"

reg "del($(sel $P).deny)"
expect_problem "a hook's RULE_IDS id with no deny" "$HKL: RULE_IDS names $P, whose registry entry has no deny naming $HK"

reg "$(sel $P).deny.hook = \"skills/work-on/scripts/check-branch-output.sh\""
expect_problem "a deny naming another script" "$HKL: RULE_IDS names $P, whose registry entry has no deny naming $HK"

reg "$(sel commit/conventional-subject).deny = {\"hook\": \"$HK\", \"before\": [\"push\"]}"
expect_problem "a deny whose script does not list the id" "commit/conventional-subject: deny names $HK, whose RULE_IDS line does not list it"

sed 's#^RULE_IDS="\(.*\) commit/no-ai-trailer"$#RULE_IDS="\1"#' "$WORK/orig/$HK" > "$S/$HK"
expect_problem "an id dropped from the hook's RULE_IDS line" "$P: deny names $HK, whose RULE_IDS line does not list it"

# ---------------------------------------------------------------- stage shape

R=branch/no-wip-files
for f in stage stage_since gates; do
    reg "del($(sel $G).$f)"
    expect_problem "a script entry with no $f" "$G: missing field $f"
done

reg "$(sel $G).stage = \"hard\""
expect_problem "a stage outside the vocabulary" "$G: stage \"hard\" is not shadow, warn, block or retired"

reg "$(sel $G).stage_since = \"2026-13-01\""
expect_problem "a stage_since with no such month" "$G: stage_since \"2026-13-01\" is not a YYYY-MM-DD date"

reg "$(sel $G).stage_since = \"16 Oct 2026\""
expect_problem "a stage_since in another format" "$G: stage_since \"16 Oct 2026\" is not a YYYY-MM-DD date"

reg "$(sel $RS).stage = \"block\""
expect_problem "a review-shadow entry with a stage" "$RS: stage is only for an entry with check.kind script"

reg "$(sel $TK).stage_backstops = []"
expect_problem "a prose entry with stage_backstops" "$TK: stage_backstops is only for an entry with check.kind script"

reg "$(sel $R).stage = \"block\""
expect_problem "a status retired entry at another stage" "$R: a status retired entry needs stage retired"

reg "$(sel $G).gates = []"
expect_problem "an active script entry with no gates" "$G: gates is empty on an active entry"

# scripts/doc-check.sh runs from a skill's phase step, not a koto gate, so an
# entry it checks may have no gates; the same entry under another check may not.
reg "$(sel plan/step-shape).check.path = \"skills/scope/scripts/check-hop-document.sh\""
expect_problem "an empty gates list on an entry another script checks" "plan/step-shape: gates is empty on an active entry"

reg "$(sel rs-027).held_by = \"rs-026\""
expect_problem "a held_by naming an entry no script checks" "rs-027: held_by \"rs-026\" is not an active script-checked entry"

reg "$(sel rs-027).held_by = \"docs/no-such-rule\""
expect_problem "a held_by naming no entry" "rs-027: held_by \"docs/no-such-rule\" is not an active script-checked entry"

reg "$(sel $G).held_by = \"docs/required-sections\""
expect_problem "a held_by on an entry that isn't an rs- item" "$G: held_by is only for an rs- jury or review-shadow item"

reg "$(sel rs-027).held_by = 7"
expect_problem "a held_by that isn't a string" "rs-027: held_by is not a string"

reg "$(sel $G).gates = [\"work-on:pr_creation\"]"
expect_problem "a gate missing its gate name" "$G: gate \"work-on:pr_creation\" is not <skill>:<state>:<gate>"

reg "$(sel $G).gates = [\"Work-On:pr_creation:pr_body_conformant\"]"
expect_problem "a gate with an upper-case skill" "is not <skill>:<state>:<gate>"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"$HK\"}]"
expect_problem "stage_backstops with no notes" "$G2: stage_backstops needs notes saying why"

reg "$(sel $G2).stage_backstops = [{\"before\": \"deploy\", \"check\": \"$HK\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop before an unprotected action" "$G2: stage_backstops before \"deploy\" is not a protected action"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"$HK\"}, {\"before\": \"pr-create\", \"check\": \".github/workflows/validate-pr-body.yml\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop action named twice" "$G2: stage_backstops names pr-create more than once"

reg "$(sel $G2).stage_backstops = [{\"before\": \"pr-create\", \"check\": \"\"}] | $(sel $G2).notes = \"why\""
expect_problem "a stage backstop with no check" "$G2: a stage_backstops check is not a path"

# ---------------------------------------------------------------- stage safety

# G2 guards pr-create and publish. Each case lowers it below block.
BS_PR="{\"before\": \"pr-create\", \"check\": \"$HK\"}"
BS_PUB='{"before": "publish", "check": ".github/workflows/validate-pr-body.yml"}'
below() { printf '%s.stage = "%s" | %s.notes = "a backstop holds each guard"' "$(sel $G2)" "$1" "$(sel $G2)"; }

reg "$(below warn)"
expect_problem "a guarded entry at warn with no backstop" "$G2: guards pr-create at stage warn with no stage_backstops entry"

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR]"
expect_problem "a guarded entry at warn with a backstop for one guard of two" "$G2: guards publish at stage warn with no stage_backstops entry"

reg "$(below shadow) | $(sel $G2).stage_backstops = [$BS_PR, {\"before\": \"publish\", \"check\": \".github/workflows/no-such.yml\"}]"
expect_problem "a stage backstop path that does not exist" "$G2: stage backstop path .github/workflows/no-such.yml does not exist"

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR, {\"before\": \"publish\", \"check\": \"skills/work-on/scripts/check-pr-output.sh\"}]"
expect_problem "a stage backstop that is the entry's own check" "$G2: guards publish at stage warn with no stage_backstops entry"

reg "$(below retired) | $(sel $G2).stage_backstops = [$BS_PR, $BS_PUB]"
run_check
[ "$RC" = 0 ] && pass "an active guarded entry at retired with an existing backstop for every guard passes" \
    || fail "an active guarded entry at retired with an existing backstop for every guard passes" "rc=$RC: $OUT"
reset_copy

reg "$(below warn) | $(sel $G2).stage_backstops = [$BS_PR, $BS_PUB]"
run_check
[ "$RC" = 0 ] && pass "a guarded entry at warn with every guard backed passes" \
    || fail "a guarded entry at warn with every guard backed passes" "rc=$RC: $OUT"
reset_copy

reg "$(sel $G).stage = \"shadow\""
run_check
[ "$RC" = 0 ] && pass "an unguarded entry at shadow needs no backstop" \
    || fail "an unguarded entry at shadow needs no backstop" "rc=$RC: $OUT"
reset_copy

# The stage safety rule and rule-registry.sh's run-time copy of it read the
# same protected actions.
P1=$(grep -m1 '^PROTECTED=' "$SCRIPT_DIR/rule-registry.sh")
P2=$(grep -m1 '^PROTECTED=' "$CHECK")
if [ -n "$P1" ] && [ "$P1" = "$P2" ]; then
    pass "rule-registry.sh and check-rule-registry.sh list the same protected actions"
else
    fail "rule-registry.sh and check-rule-registry.sh list the same protected actions" "[$P1] vs [$P2]"
fi

# ---------------------------------------------------------------- gates

reg "$(sel $G).gates += [\"work-on:no_such_state:pr_body_conformant\"]"
expect_problem "a gate naming no state of the skill" "$G: gate work-on:no_such_state:pr_body_conformant names no state no_such_state"

reg "$(sel $G).gates += [\"work-on:pr_creation:no_such_gate\"]"
expect_problem "a gate that is not a command gate of its state" "$G: gate work-on:pr_creation:no_such_gate is not a command gate of state pr_creation"

reg "$(sel $G).gates += [\"work-on:verification:verification_verdict\"]"
expect_problem "a gate whose script does not list the id" "$G: gate work-on:verification:verification_verdict runs no script whose RULE_IDS line lists $G"

reg "$(sel $R).gates = [\"execute:no_such_state:x\"]"
expect_problem "a retired entry's gate is still checked by name" "$R: gate execute:no_such_state:x names no state"

# A review-panel gate runs panel-scope.sh, which prints any active rule, so
# only panel/open-finding may list one; rule-lifecycle.sh counts every
# finding there for it.
reg "$(sel $G).gates += [\"work-on:scrutiny:scrutiny_verdict\", \"work-on:light_review:light_verdict\"]"
expect_problem "a review-panel gate on another entry" "$G: gate work-on:scrutiny:scrutiny_verdict is a panel gate; only panel/open-finding may list one"

reg "$(sel $R).gates = [\"work-on:review:review_verdict\"]"
expect_problem "a review-panel gate on a retired entry" "$R: gate work-on:review:review_verdict is a panel gate; only panel/open-finding may list one"

run_check
[ "$RC" = 0 ] && pass "panel/open-finding lists the review-panel gates and passes" \
    || fail "panel/open-finding lists the review-panel gates and passes" "rc=$RC: $OUT"

sed 's/^      owned_pr_body_conformant:/      owned_pr_body_renamed:/' \
    "$WORK/orig/skills/execute/koto-templates/execute.md" > "$S/skills/execute/koto-templates/execute.md"
expect_problem "a gate renamed in its template" "$G: gate execute:pr_finalization:owned_pr_body_conformant is not a command gate"

# ---------------------------------------------------------------- releasable

{ cat "$WORK/orig/skills/execute/scripts/adopt-or-create-pr.sh"
  printf '%s\n' '"$SELF_DIR/../../../scripts/rule-registry.sh" release rs-001 </dev/null >&2 || true'
} > "$S/skills/execute/scripts/adopt-or-create-pr.sh"
expect_problem "a released id outside the releasable directories" "rs-001 would not be released"

{ cat "$WORK/orig/skills/execute/scripts/adopt-or-create-pr.sh"
  printf '%s\n' '    "$SELF_DIR/../../../scripts/rule-registry.sh" release no-such/rule >&2 || true  # a trailing comment'
} > "$S/skills/execute/scripts/adopt-or-create-pr.sh"
expect_problem "an indented release with a trailing comment is still read" "releases no-such/rule, which is not an active registry entry"

awk '{ print } index($0, "**Another run'"'"'s PR (exit 6 on") { for (i = 0; i < 70; i++) print "filler line" }' \
    "$WORK/orig/skills/execute/koto-templates/execute.md" > "$S/skills/execute/koto-templates/execute.md"
expect_problem "a released range over 60 lines" "$TK would not be released"

# ---------------------------------------------------------------- baseline keys

jq '.pinned_commit = "abc123"' "$WORK/orig/docs/measurement/offload-baseline/template-pin.json" \
    > "$S/docs/measurement/offload-baseline/template-pin.json"
expect_problem "a pinned commit that isn't 40 hex" "pinned_commit [abc123] is not 40 lowercase hex characters"

reg "$(sel $G).baseline_keys = [\"references/pr-body-conformance.md:61\"]"
expect_problem "a malformed baseline key" "$G: baseline key [references/pr-body-conformance.md:61] is not"

reg "$(sel $G).baseline_keys = [\"references/pr-body-conformance.md#L61-L99999\"]"
expect_problem "a baseline key past its file's end" "$G: baseline key references/pr-body-conformance.md#L61-L99999 runs past"

reg "$(sel $TK).baseline_keys = [\"references/pr-body-conformance.md#L61-L75\"]"
expect_problem "an unexplained shared key" "$TK: shares baseline key references/pr-body-conformance.md#L61-L75 with $G"

reg "$(sel $G).baseline_keys = [] | $(sel $G).notes = \"\""
expect_problem "an unexplained empty key list" "$G: an empty baseline_keys needs a reason in notes"

# ---------------------------------------------------------------- path filter

grep -vxF "      - 'CLAUDE.md'" "$WORK/orig/.github/workflows/check-rule-registry.yml" \
    > "$S/.github/workflows/check-rule-registry.yml"
expect_problem "a text.path outside the workflow's path filter" "rs-001: text.path CLAUDE.md is outside"

# ---------------------------------------------------------------- routing-gate rule

OLD="gate-rules"".tsv"
{ cat "$WORK/orig/references/rule-registry.md"; echo "See $OLD."; } > "$S/references/rule-registry.md"
expect_problem "the removed table named in a scanned file" "references/rule-registry.md names $OLD"

grep -vF 'A **registered rule** is an id' "$WORK/orig/references/rule-registry.md" > "$S/references/rule-registry.md"
expect_problem "rule-registry.md missing the registered-rule definition" "does not define a registered rule"

awk '{ print } /^### Decision 9:/ { print "Counted against the gate scripts'"'"' rule tables." }' \
    "$WORK/orig/docs/designs/current/DESIGN-output-gates.md" > "$S/docs/designs/current/DESIGN-output-gates.md"
expect_problem "Decision 9 still naming the rule tables" "Decision 9 still refers to the gate scripts' rule tables"

# ---------------------------------------------------------------- could not run

# A check copy beside a reader whose release prints neither of its answers:
# no answer is exit 2, never a pass.
F="$WORK/fake-scripts"
mkdir -p "$F"
cp "$CHECK" "$F/check-rule-registry.sh"
cat > "$F/rule-registry.sh" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
    [ "\$a" = release ] && { echo "something else broke" >&2; exit 0; }
done
exec "$SCRIPT_DIR/rule-registry.sh" "\$@"
EOF
chmod +x "$F/check-rule-registry.sh" "$F/rule-registry.sh"
OUT=$("$F/check-rule-registry.sh" --root "$S" 2>&1); RC=$?
if [ "$RC" = 2 ] && grep -qF "gave no answer" <<<"$OUT"; then
    pass "a release that gives no answer exits 2"
else
    fail "a release that gives no answer exits 2" "rc=$RC: $OUT"
fi

# An unreadable directory under a scanned tree is a scan that couldn't run.
# Skipped where permissions don't bind (running as root).
mkdir -p "$S/skills/unreadable"
chmod 000 "$S/skills/unreadable"
if [ -r "$S/skills/unreadable" ]; then
    echo "skip: an unreadable directory exits 2 (permissions don't bind here)"
else
    run_check
    if [ "$RC" = 2 ] && grep -qF "could not read the tree" <<<"$OUT"; then
        pass "an unreadable directory in a scanned tree exits 2"
    else
        fail "an unreadable directory in a scanned tree exits 2" "rc=$RC: $OUT"
    fi
fi
chmod 755 "$S/skills/unreadable"
rmdir "$S/skills/unreadable"

# ---------------------------------------------------------------- stage transitions

# base_commit: a commit of the copy, on its HEAD, whose registry is standard
# input. It is written through a scratch index, so the copy's HEAD, index and
# tree stay as they are; it prints the commit.
base_commit() {
    local blob tree
    blob=$(git -C "$S" hash-object -w --stdin) || return 1
    rm -f "$WORK/base.idx"
    GIT_INDEX_FILE="$WORK/base.idx" git -C "$S" read-tree HEAD || return 1
    GIT_INDEX_FILE="$WORK/base.idx" git -C "$S" update-index --cacheinfo "100644,$blob,references/rule-registry.json" \
        || return 1
    tree=$(GIT_INDEX_FILE="$WORK/base.idx" git -C "$S" write-tree) || return 1
    git $GIT_ID -C "$S" commit-tree "$tree" -p HEAD -m base
}

# expect_base <label> <rc> <substring> <base filter> <head filter>: the
# registry at the base and in the tree are the original through each filter;
# the check with --base exits <rc> and prints <substring>.
expect_base() {
    local label=$1 want_rc=$2 want=$3 b
    reg "$5"
    b=$(jq "$4" "$WORK/orig/references/rule-registry.json" | base_commit) && [ -n "$b" ] \
        || { echo "bad base filter: $4" >&2; exit 2; }
    run_check --base "$b"
    if [ "$RC" = "$want_rc" ] && grep -qF -- "$want" <<<"$OUT"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want $want_rc and [$want]; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_copy
}

OK="check-rule-registry: ok"
# at <stage> [<since>]: a filter setting G's stage, and its stage_since when
# given.
at() {
    printf '%s.stage = "%s"' "$(sel $G)" "$1"
    [ $# -lt 2 ] || printf ' | %s.stage_since = "%s"' "$(sel $G)" "$2"
}
LATER=2099-01-01

expect_base "transition: no change passes" 0 "$OK" '.' '.'
for s in shadow warn block; do
    expect_base "transition: a new entry at $s passes" 0 "$OK" "del($(sel $G))" "$(at $s)"
done
expect_base "transition: a base entry with no stage taking block passes" 0 "$OK" "del($(sel $G).stage)" '.'
expect_base "transition: a retired base entry with no stage taking retired passes" 0 "$OK" "del($(sel $R).stage)" '.'
expect_base "transition: shadow to warn passes" 0 "$OK" "$(at shadow)" "$(at warn $LATER)"
expect_base "transition: warn to block passes" 0 "$OK" "$(at warn)" "$(at block $LATER)"
expect_base "transition: block to shadow passes" 0 "$OK" '.' "$(at shadow $LATER)"
expect_base "transition: warn to retired passes" 0 "$OK" "$(at warn)" "$(at retired $LATER)"
expect_base "transition: retired to shadow on an active entry passes" 0 "$OK" "$(at retired)" "$(at shadow $LATER)"
expect_base "transition: a protected guard dropped at block passes" 0 "$OK" '.' "$(sel $G2).guards = [\"pr-create\"]"

expect_base "transition: shadow to block fails" 1 "$G: stage shadow to block skips a step" \
    "$(at shadow)" "$(at block $LATER)"
expect_base "transition: retired to warn fails" 1 "$G: stage retired may change only to shadow" \
    "$(at retired)" "$(at warn $LATER)"
expect_base "transition: a new entry at retired fails" 1 "$G: a new entry starts at shadow, warn or block" \
    "del($(sel $G))" "$(at retired)"
expect_base "transition: a base entry with no stage taking warn fails" 1 "$G: an entry with no stage at the base takes block" \
    "del($(sel $G).stage)" "$(at warn $LATER)"
expect_base "transition: a stage change that keeps stage_since fails" 1 "$G: stage changed from shadow to warn but stage_since" \
    "$(at shadow)" "$(at warn)"
expect_base "transition: a stage change that lowers stage_since fails" 1 "is not later than the base" \
    "$(at shadow $LATER)" "$(at warn 2026-01-01)"
expect_base "transition: a status change to retired at block fails" 1 "$G: a status change to retired sets stage retired" \
    '.' "$(sel $G).status = \"retired\""
expect_base "transition: a status retired entry made active fails" 1 "$R: a status retired entry keeps its status and stage" \
    '.' "$(sel $R).status = \"active\""
expect_base "transition: a status retired entry's stage changed fails" 1 "$R: a status retired entry keeps its status and stage" \
    '.' "$(sel $R).stage = \"shadow\" | $(sel $R).stage_since = \"$LATER\""
expect_base "transition: a protected guard dropped while leaving block fails" 1 "$G2: drops protected guard(s) publish while at stage warn" \
    '.' "$(sel $G2).guards = [\"pr-create\"] | $(sel $G2).stage = \"warn\" | $(sel $G2).stage_since = \"$LATER\" | $(sel $G2).stage_backstops = [$BS_PR] | $(sel $G2).notes = \"why\""

b=$(printf 'not json\n' | base_commit)
run_check --base "$b"
if [ "$RC" = 2 ]; then
    pass "transition: a base registry that does not parse exits 2"
else
    fail "transition: a base registry that does not parse exits 2" "rc=$RC: $OUT"
fi
b=$(printf '{"rules": 1}\n' | base_commit)
run_check --base "$b"
if [ "$RC" = 2 ]; then
    pass "transition: a base registry with no rules list exits 2"
else
    fail "transition: a base registry with no rules list exits 2" "rc=$RC: $OUT"
fi
run_check --base no-such-ref
if [ "$RC" = 2 ] && grep -qF "is not a commit" <<<"$OUT"; then
    pass "transition: a base that is not a commit exits 2"
else
    fail "transition: a base that is not a commit exits 2" "rc=$RC: $OUT"
fi

# ---------------------------------------------------------------- id removal

reg "del(.rules[] | select(.id == \"$TK\"))"
expect_problem "an id removed relative to --base" "$TK: in the registry at the base but removed" --base HEAD

git -C "$S" rm -q --cached references/rule-registry.json
git $GIT_ID -C "$S" commit -qm "no registry"
run_check --base HEAD
if [ "$RC" = 0 ] && grep -qF "the base has no registry" <<<"$OUT"; then
    pass "a base with no registry passes the id-removal check"
else
    fail "a base with no registry passes the id-removal check" "rc=$RC: $OUT"
fi

# ---------------------------------------------------------------- adoption

# A repository whose first commit has no rule table, whose second (the base)
# has the table, the review-shadow files and a manifest, and whose working tree
# adopts the registry.
A="$WORK/adopt"
mkdir -p "$A"
git init -q "$A"
echo "before" > "$A/README"
git -C "$A" add -A
git $GIT_ID -C "$A" commit -qm before
NO_TABLE=$(git -C "$A" rev-parse HEAD)

mkdir -p "$A/skills/work-on/scripts" "$A/scripts/review-shadow" "$A/docs/measurement/offload-baseline" \
    "$A/docs" "$A/skills/s/koto-templates" "$A/skills/execute/koto-templates" "$A/references"
printf '# table\n%s\tref\tsha\texcerpt\n' "x/one" > "$A/skills/work-on/scripts/$OLD"
printf '{"criteria":[{"rule_id":"rs-001","rule_ref":"CLAUDE.md"}]}\n' > "$A/scripts/review-shadow/criteria.json"
printf 'print("shadow")\n' > "$A/scripts/review-shadow/review-shadow.py"
printf 'print("test")\n' > "$A/scripts/review-shadow/test_review_shadow.py"
printf 'profile\tpath\tselector\tweight\tnote\np\tdocs/loaded.md\tfile\t1\tx\np\tdocs/fm.md\tbody\t1\tx\np\tskills/s/koto-templates/s.md\tstate:alpha\t1\tx\n' \
    > "$A/docs/measurement/offload-baseline/load-manifest.tsv"
printf 'loaded one\nloaded two\n' > "$A/docs/loaded.md"
printf -- '---\nfm: one\nfm2: two\n---\nbody one\nbody two\n' > "$A/docs/fm.md"
printf -- '---\nstates: x\nmore: y\n---\n## alpha\nalpha one\nalpha two\n## beta\nbeta one\nbeta two\n' \
    > "$A/skills/s/koto-templates/s.md"
printf 'execute one\nexecute two\n' > "$A/skills/execute/koto-templates/execute.md"
git -C "$A" add -A
git $GIT_ID -C "$A" commit -qm base
BASE=$(git -C "$A" rev-parse HEAD)

# reset_adopt: the working tree that adopts the registry, rebuilt over the
# base commit rather than copied back.
reset_adopt() {
    git -C "$A" reset -q --hard "$BASE"
    git -C "$A" clean -qfd
    git -C "$A" rm -q "skills/work-on/scripts/$OLD"
    mkdir -p "$A/references"
    printf '{"rules":[{"id":"x/one"},{"id":"rs-001"}]}\n' > "$A/references/rule-registry.json"
}
reset_adopt

# expect_adopt <label> <rc> <substring> [base]
expect_adopt() {
    local label=$1 want_rc=$2 want=$3 base=${4:-$BASE}
    OUT=$("$ADOPT" --root "$A" "$base" 2>&1)
    RC=$?
    if [ "$RC" = "$want_rc" ] && grep -qF -- "$want" <<<"$OUT"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want $want_rc and [$want]; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_adopt
}

# drop_line <file> <text>: remove the line equal to <text>.
drop_line() {
    grep -vxF -- "$2" "$A/$1" > "$WORK/dropped"
    cat "$WORK/dropped" > "$A/$1"
}

expect_adopt "adoption: a faithful adoption passes" 0 "check-rule-registry-adoption: ok"

expect_adopt "adoption: skipped when the base has no table" 0 "skipped: the base has no" "$NO_TABLE"

printf '{"rules":[{"id":"rs-001"}]}\n' > "$A/references/rule-registry.json"
expect_adopt "adoption: a table id dropped" 1 "x/one: at the base, and the id of 0 registry entries"

printf '{"rules":[{"id":"x/one"}]}\n' > "$A/references/rule-registry.json"
expect_adopt "adoption: a criterion id dropped" 1 "rs-001: at the base, and the id of 0 registry entries"

drop_line docs/loaded.md "loaded two"
expect_adopt "adoption: a line removed from a whole loaded file" 1 "docs/loaded.md (file): base line(s) 2 removed"

drop_line docs/fm.md "body one"
expect_adopt "adoption: a line removed from a loaded body" 1 "docs/fm.md (body): base line(s) 5 removed"

drop_line docs/fm.md "fm2: two"
expect_adopt "adoption: a frontmatter line is outside a body span" 0 "check-rule-registry-adoption: ok"

drop_line skills/s/koto-templates/s.md "alpha two"
expect_adopt "adoption: a line removed from a loaded state section" 1 "s.md (state:alpha): base line(s) 7 removed"

drop_line skills/s/koto-templates/s.md "beta two"
expect_adopt "adoption: a state section the manifest doesn't load is outside" 0 "check-rule-registry-adoption: ok"

drop_line skills/execute/koto-templates/execute.md "execute one"
expect_adopt "adoption: a line removed from /execute's template" 1 "execute.md (file): base line(s) 1 removed"

# A manifest row that cuts nothing at the base would protect nothing; with a
# line removed from its file, it is no answer.
git -C "$A" stash -q -u
printf 'p\tdocs/loaded.md\tstate:missing\t1\tx\n' >> "$A/docs/measurement/offload-baseline/load-manifest.tsv"
git -C "$A" add -A
git $GIT_ID -C "$A" commit -qm "a state the file doesn't have"
BAD_BASE=$(git -C "$A" rev-parse HEAD)
git -C "$A" reset -q --hard "$BASE"
git -C "$A" stash pop -q
drop_line docs/loaded.md "loaded two"
expect_adopt "adoption: a selector that cuts nothing exits 2" 2 "docs/loaded.md (state:missing) selects no lines at the base" "$BAD_BASE"

echo '# changed' >> "$A/scripts/review-shadow/review-shadow.py"
expect_adopt "adoption: review-shadow.py changed" 1 "scripts/review-shadow/review-shadow.py differs from the base"

echo '# changed' >> "$A/scripts/review-shadow/test_review_shadow.py"
expect_adopt "adoption: test_review_shadow.py changed" 1 "test_review_shadow.py differs from the base"

printf '{"criteria":[{"rule_id":"rs-001","rule_ref":"CLAUDE.md"}],"x":1}\n' > "$A/scripts/review-shadow/criteria.json"
expect_adopt "adoption: criteria.json changed" 1 "criteria.json differs from the base"

echo
echo "check-rule-registry_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
