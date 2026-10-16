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

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -P -- "$SCRIPT_DIR/.." && pwd -P)
CHECK="$SCRIPT_DIR/check-rule-registry.sh"
ADOPT="$SCRIPT_DIR/check-rule-registry-adoption.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ $# -lt 2 ] || printf '  %s\n' "$2"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-rule-registry-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

GIT_ID="-c user.name=test -c user.email=test@example.com -c commit.gpgsign=false"

# ---------------------------------------------------------------- the copy

S="$WORK/s"
mkdir -p "$S/docs/designs/current" "$S/docs/measurement/offload-baseline" "$S/.github/workflows" \
    "$S/.claude-plugin"
for d in references skills scripts hooks docs/guides; do
    cp -R "$REPO_ROOT/$d" "$S/$d"
done
for f in CLAUDE.md .claude-plugin/plugin.json docs/designs/current/DESIGN-output-gates.md \
    docs/measurement/offload-baseline/template-pin.json .github/workflows/check-rule-registry.yml \
    .github/workflows/validate-pr-body.yml; do
    cp "$REPO_ROOT/$f" "$S/$f"
done

git init -q "$S"
# The common directory, not the git directory: in a linked worktree the
# objects live with the main checkout. git prints it relative to the
# repository root or absolute.
COMMON=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
case "$COMMON" in /*) ;; *) COMMON="$REPO_ROOT/$COMMON" ;; esac
echo "$COMMON/objects" > "$S/.git/objects/info/alternates"
git -C "$S" add -A
git $GIT_ID -C "$S" commit -qm scratch

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
    if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -qF -- "$want"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want 1 and [$want]; got: $(printf '%s' "$OUT" | head -n 5 | tr '\n' '|')"
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

# ---------------------------------------------------------------- paths

reg "$(sel $G).check.path = \"skills/work-on/scripts/no-such-check.sh\""
expect_problem "a missing check path" "$G: check path skills/work-on/scripts/no-such-check.sh does not exist"

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
expect_problem "a malformed RULE_IDS line" "check-pr-output.sh:63: malformed RULE_IDS line"

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
if [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qF "gave no answer"; then
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
    if [ "$RC" = 2 ] && printf '%s\n' "$OUT" | grep -qF "could not read the tree"; then
        pass "an unreadable directory in a scanned tree exits 2"
    else
        fail "an unreadable directory in a scanned tree exits 2" "rc=$RC: $OUT"
    fi
fi
chmod 755 "$S/skills/unreadable"
rmdir "$S/skills/unreadable"

# ---------------------------------------------------------------- id removal

reg "del(.rules[] | select(.id == \"$TK\"))"
expect_problem "an id removed relative to --base" "$TK: in the registry at the base but removed" --base HEAD

git -C "$S" rm -q --cached references/rule-registry.json
git $GIT_ID -C "$S" commit -qm "no registry"
run_check --base HEAD
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qF "the base has no registry"; then
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

git -C "$A" rm -q "skills/work-on/scripts/$OLD"
printf '{"rules":[{"id":"x/one"},{"id":"rs-001"}]}\n' > "$A/references/rule-registry.json"
mkdir -p "$WORK/adopt-orig"
cp -R "$A/." "$WORK/adopt-orig/"
rm -rf "$WORK/adopt-orig/.git"
reset_adopt() {
    rm -rf "$A/docs" "$A/skills" "$A/scripts" "$A/references"
    cp -R "$WORK/adopt-orig/docs" "$WORK/adopt-orig/skills" "$WORK/adopt-orig/scripts" \
        "$WORK/adopt-orig/references" "$A/"
}

# expect_adopt <label> <rc> <substring> [base]
expect_adopt() {
    local label=$1 want_rc=$2 want=$3 base=${4:-$BASE}
    OUT=$("$ADOPT" --root "$A" "$base" 2>&1)
    RC=$?
    if [ "$RC" = "$want_rc" ] && printf '%s\n' "$OUT" | grep -qF -- "$want"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want $want_rc and [$want]; got: $(printf '%s' "$OUT" | head -n 5 | tr '\n' '|')"
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
