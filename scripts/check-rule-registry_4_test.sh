#!/usr/bin/env bash
# check-rule-registry_4_test.sh -- part 4 of 4 of the tests for
# check-rule-registry.sh and check-rule-registry-adoption.sh: the
# routing-gate rule, runs that could not run, stage transitions, id removal
# and adoption.
#
# The four parts were one suite, cut by case order so each runs in its own CI
# slice; scripts/lib/check-rule-registry-testlib.sh holds the setup they share
# and describes the scratch copy the cases alter.
#
# Run from anywhere: bash scripts/check-rule-registry_4_test.sh

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
. "$(dirname "$0")/lib/check-rule-registry-testlib.sh" || exit 1

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

# The warn exception, against a base: a step up to block must add a protected
# guard, and a new entry can't take a code a base entry holds, so a blocking
# rule can't be deleted and re-added unguarded at warn under a new id.
expect_base "transition: warn to block guarding nothing fails" 1 \
    "$WN: steps from warn to block guarding nothing; give it a protected guard" \
    '.' "$(sel $WN).stage = \"block\" | $(sel $WN).stage_since = \"$LATER\""
expect_base "transition: warn to block adding protected guards passes" 0 "$OK" \
    '.' "$(sel $WN).stage = \"block\" | $(sel $WN).stage_since = \"$LATER\" | $(sel $WN).guards = [\"pr-create\", \"publish\"]"
RA=docs/required-fields
expect_base "transition: a blocking entry deleted and re-added unguarded at warn under a new id fails" 1 \
    "$RA-again: a new entry takes alias FC01, which an entry at the base holds" \
    '.' "(.rules += [$(sel $RA) | .id = \"$RA-again\" | .stage = \"warn\" | .guards = [\"none\"]]) | del(.rules[] | select(.id == \"$RA\"))"
expect_base "transition: a new entry taking a retired base entry's alias fails" 1 \
    "$RA-again: a new entry takes alias FC01" \
    "$(sel $RA).status = \"retired\" | $(sel $RA).stage = \"retired\" | $(sel $RA).aliases = [\"FC01\"]" \
    "$(sel $RA).status = \"retired\" | $(sel $RA).stage = \"retired\" | $(sel $RA).aliases = [] | .rules += [$(sel $RA) | .id = \"$RA-again\" | .status = \"active\" | .stage = \"warn\" | .guards = [\"none\"] | .aliases = [\"FC01\"]]"
expect_base "transition: a new entry with an alias no base entry holds passes" 0 "$OK" \
    "del($(sel $WN))" '.'

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
echo "check-rule-registry_4_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
