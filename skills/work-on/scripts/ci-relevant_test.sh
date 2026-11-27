#!/usr/bin/env bash
# ci-relevant_test.sh -- does ci_monitor wait only on the checks a change can
# reach, and still on every check where the map hasn't opted in?
# Part of the work-on skill
#
# Three parts, over throwaway repositories whose main carries a verification
# map with a coordinate row (twin `test-coordinate-scripts` in "Check
# coordinate scripts", for skills/coordinate/**), a skill row (twin
# `skill-gate (ubuntu-latest)` in "Check skill gate", for skills/plan/**), an
# untwinned default row, and always_required naming `lint` in "Lint", pushed
# to a bare origin so the current default branch can move under the run.
#
#   set      run-verification.sh --relevant: the twins of the selected
#            commands plus always_required, one line per display name; the
#            union of the merge-base's map and the current default branch's
#            (an entry added on the remote is fetched and kept, one dropped
#            there is kept from the merge-base); `off`, with nothing recorded,
#            for a map with no always_required, CI_WAIT=all, a malformed
#            always_required, and an empty set.
#   gate     the ci_passing command EXTRACTED FROM work-on.md, with
#            {{PLUGIN_ROOT}}, {{SESSION_NAME}} and {{CI_WAIT}} substituted as
#            koto would, against a gh stub: a change that selects no
#            coordinate command is green while a coordinate-only check is
#            pending; a pending selected twin holds; an always-required check
#            holds until it passes; a skipped twin holds (its slice failed);
#            a relevant check not reported holds; a check the current default
#            branch made relevant holds; a failing outside check doesn't hold
#            and is commented on once per head, its name and link neutral,
#            and recorded in ci_outside_failures.txt; a comment that can't be
#            posted is tried again; with no always_required, and under
#            CI_WAIT=all, a pending coordinate check holds; and /execute's
#            merge readiness still reads every check.
#   koto     the SHIPPED ci_monitor block under real koto, its other gates
#            stubbed to pass: a docs change with a coordinate-only check
#            pending reaches ci_pass_counting in one tick and records
#            relevant_checks.txt; a pending always-required check holds it;
#            CI_WAIT=all holds it on the coordinate check; and a CI_WAIT
#            other than all is refused at init.
#
# The first two parts use a koto stand-in that keeps context keys as files;
# the third needs koto on PATH and is skipped without it.
#
# Usage: ci-relevant_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.
#
# Bash 3.2: no associative arrays, no mapfile.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
RV="$SCRIPT_DIR/run-verification.sh"
WORK_ON="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
# shellcheck source=../../../scripts/lib/koto-gates.sh
. "$REPO_ROOT/scripts/lib/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf 'SKIP: %s\n' "$*"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
REAL_KOTO=$(command -v koto 2>/dev/null || true)

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/ci-relevant-test.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P) || exit 2
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
mkdir -p "$HOME" "$WORKDIR/kbin" "$WORKDIR/ghbin"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main
unset CI_WAIT

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

# koto stand-in: context add/exists/get/remove on files under
# $KOTO_STUB_STORE/<session>/<key>.
cat > "$WORKDIR/kbin/koto" <<'EOF'
#!/bin/sh
case "$1 ${2-}" in
    "context add")
        mkdir -p "$KOTO_STUB_STORE/$3"
        if [ "${5-}" = --from-file ]; then cp "$6" "$KOTO_STUB_STORE/$3/$4"; else cat > "$KOTO_STUB_STORE/$3/$4"; fi ;;
    "context exists") [ -f "$KOTO_STUB_STORE/$3/$4" ] ;;
    "context get") [ -f "$KOTO_STUB_STORE/$3/$4" ] || exit 1; cat "$KOTO_STUB_STORE/$3/$4" ;;
    "context remove") rm -f "$KOTO_STUB_STORE/$3/$4" ;;
    *) exit 9 ;;
esac
EOF
chmod +x "$WORKDIR/kbin/koto"
export KOTO_STUB_STORE="$WORKDIR/kotostore"
mkdir -p "$KOTO_STUB_STORE"

# gh: pr list (pull request 7), pr checks ($FIX/checks.json, --jq applied),
# pr view ($FIX/head and the pull request's URL), pr comment (the body
# appended to $FIX/comments, one record per comment; $FIX/comment.fail makes
# it fail), api repos/<r>/contents/... (404: no hosted-CI declaration). Every
# call is logged to $FIX/gh.log. The fixture's path is written in, since koto
# runs a gate in a cleared environment.
FIX="$WORKDIR/fix"
mkdir -p "$FIX"
{
    printf '#!/usr/bin/env bash\nFIX="%s"\n' "$FIX"
    cat <<'EOF'
echo "$*" >> "$FIX/gh.log"
jqf="" prev="" body=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    [ "$prev" = "--body-file" ] && body="$a"
    prev="$a"
done
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
case "$1 ${2:-}" in
    "pr list") echo '[{"number": 7}]' | out ;;
    "pr checks") out < "$FIX/checks.json" ;;
    "pr view")
        jq -n --arg h "$(cat "$FIX/head")" '{headRefOid: $h, url: "https://github.com/acme/widgets/pull/7", state: "OPEN"}' | out ;;
    "pr comment")
        if [ -f "$FIX/comment.fail" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
        { cat "$body"; echo "----"; } >> "$FIX/comments" ;;
    "api repos/"*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
EOF
} > "$WORKDIR/ghbin/gh"
chmod +x "$WORKDIR/ghbin/gh"

STUB_PATH="$WORKDIR/kbin:$WORKDIR/ghbin:$PATH"
H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222

# ---------------------------------------------------------------------------
# The repositories
# ---------------------------------------------------------------------------

LINT='{"workflow": ".github/workflows/lint.yml", "job": "lint"}'
MAP=$(jq -cn --argjson lint "$LINT" '{
    schema: "shirabe-verification-map/v1",
    commands: {
        coord: {run: ["true"], hosted: [{workflow: ".github/workflows/coord.yml", job: "test-coordinate-scripts", runs: "coord"}]},
        skill: {run: ["true"], each: "skills/*",
                hosted: [{workflow: ".github/workflows/gate.yml", job: "skill-gate (ubuntu-latest)", runs: "skill {skill}"}]},
        plain: {run: ["true"]}},
    entries: [{paths: ["skills/coordinate/**"], commands: ["coord"]},
              {paths: ["skills/plan/**"], commands: ["skill"]}],
    default: ["plain"],
    always_required: [$lint]}')

# mkrepo <name> [map json]: main carries the map and the three workflows, on
# a bare origin; HEAD is a `work` branch at main. Leaves the shell in it.
mkrepo() {
    local dir="$WORKDIR/r-$1" map=${2:-$MAP}
    git init -q --bare "$WORKDIR/o-$1.git" || exit 2
    mkdir -p "$dir/.claude/shirabe-extensions" "$dir/.github/workflows" "$dir/docs" "$dir/skills/plan" "$dir/skills/coordinate"
    cd "$dir" || exit 2
    git init -q -b main .
    printf 'name: Check coordinate scripts\non:\n  pull_request:\njobs:\n  test-coordinate-scripts:\n    runs-on: ubuntu-latest\n' > .github/workflows/coord.yml
    printf 'name: "Check skill gate"\non:\n  pull_request:\njobs:\n  skill-gate:\n    runs-on: ubuntu-latest\n' > .github/workflows/gate.yml
    printf "name: 'Lint'  # the lint\non:\n  pull_request:\njobs:\n  lint:\n    runs-on: ubuntu-latest\n" > .github/workflows/lint.yml
    printf 'on:\n  pull_request:\njobs:\n  scan:\n    runs-on: ubuntu-latest\n' > .github/workflows/scan.yml
    echo base > docs/x.md
    echo base > skills/plan/a.md
    echo base > skills/coordinate/a.sh
    printf '%s\n' "$map" > .claude/shirabe-extensions/verification-map.json
    git add -A && git commit -q -m init
    git remote add origin "$WORKDIR/o-$1.git"
    git push -q origin main || exit 2
    git fetch -q origin || exit 2
    git checkout -q -b work
}
# change <path>...: append to each path and commit.
change() {
    local p
    for p in "$@"; do
        mkdir -p "$(dirname "$p")"
        echo "change $RANDOM" >> "$p"
    done
    git add -A && git commit -q -m "change $*"
}
# remote_map <repo> <jq edit>: edit the map on origin's main, as a merge
# there after the run began would.
remote_map() {
    local tmp="$WORKDIR/remote-$1"
    rm -rf "$tmp"
    git clone -q "$WORKDIR/o-$1.git" "$tmp" || return 1
    jq "$2" "$tmp/.claude/shirabe-extensions/verification-map.json" > "$tmp/map.new" \
        && mv "$tmp/map.new" "$tmp/.claude/shirabe-extensions/verification-map.json" || return 1
    (cd "$tmp" && git commit -q -am "edit the map" && git push -q origin main) || return 1
}
# rel <session> [args]: --relevant in the current repository; sets RC, OUT, ERR.
rel() {
    local s=$1
    shift
    OUT=$(env PATH="$STUB_PATH" "$RV" --relevant --session "$s" "$@" 2>"$WORKDIR/rel.err")
    RC=$?
    ERR=$(cat "$WORKDIR/rel.err")
}
key_of() { cat "$KOTO_STUB_STORE/$1/$2" 2>/dev/null; }
line() { printf '%s\t%s\t%s' "$1" "$2" "$3"; }
TAB=$(printf '\t')

L_LINT=$(line .github/workflows/lint.yml lint Lint)
L_GATE=$(line .github/workflows/gate.yml "skill-gate (ubuntu-latest)" "Check skill gate")
L_COORD=$(line .github/workflows/coord.yml test-coordinate-scripts "Check coordinate scripts")

# ---------------------------------------------------------------------------
# Part 1: the set
# ---------------------------------------------------------------------------
echo "--- the set"

mkrepo a
change docs/x.md
rel s-docs
eq "set: a docs change (untwinned default) is always_required alone" "$L_LINT" "$OUT"
eq "set: exit 0" 0 "$RC"
eq "set: the set is recorded as relevant_checks.txt" "$L_LINT" "$(key_of s-docs relevant_checks.txt)"
case "$OUT" in *coord*) fail "set: a docs change made the coordinate check relevant" ;; *) pass "set: a docs change makes no coordinate check relevant" ;; esac

git checkout -q -B plan origin/main && change skills/plan/a.md
rel s-plan
eq "set: a skills/plan change adds the skill gate's twin, and only it" "$(printf '%s\n%s' "$L_GATE" "$L_LINT")" "$OUT"

git checkout -q -B coord origin/main && change skills/coordinate/a.sh
rel s-coord
eq "set: a coordinate change adds the coordinate twin" "$(printf '%s\n%s' "$L_COORD" "$L_LINT")" "$OUT"

# The union: the remote's map drops lint and adds scan after the run began.
git checkout -q -B union origin/main && change docs/x.md
remote_map a '.always_required = [{"workflow": ".github/workflows/scan.yml", "job": "scan"}]' \
    || fail "set: could not edit the remote's map"
rel s-union
L_SCAN=$(line .github/workflows/scan.yml scan .github/workflows/scan.yml)
eq "set: the union of the merge-base's read and the fetched default branch's" "$(printf '%s\n%s' "$L_LINT" "$L_SCAN")" "$OUT"
case "$OUT" in *"$L_LINT"*) pass "set: an entry the default branch dropped stays, from the merge-base" ;; *) fail "set: the merge-base's lint was dropped" ;; esac
eq "set: a workflow with no name: is matched by its path, as GitHub shows it" "$L_SCAN" "$(printf '%s\n' "$OUT" | grep scan)"

# A twin added on the remote for the selected row joins the set too.
remote_map a '.commands.plain.hosted = [{"workflow": ".github/workflows/coord.yml", "job": "plain-twin", "runs": "plain"}]' \
    || fail "set: could not edit the remote's map"
rel s-union2
case "$OUT" in *"plain-twin"*) pass "set: a twin the current default branch added for a selected command is relevant" ;; *) fail "set: the current branch's new twin is missing: $OUT" ;; esac

# A renamed workflow: one line per display name, so a check under either matches.
git checkout -q -B renamed origin/main
sed 's/^name: "Check skill gate"/name: Skill gate renamed/' .github/workflows/gate.yml > gate.new && mv gate.new .github/workflows/gate.yml
echo x >> skills/plan/a.md
git add -A && git commit -q -m rename
rel s-renamed
case "$OUT" in
    *"$L_GATE"*"$(line .github/workflows/gate.yml "skill-gate (ubuntu-latest)" "Skill gate renamed")"*) pass "set: a workflow renamed on the branch has a line per display name" ;;
    *) fail "set: the renamed workflow's lines: $OUT" ;;
esac

# Off.
git checkout -q -B off origin/main && change docs/x.md
rel s-wait --ci-wait all
eq "set: --ci-wait all is off" off "$OUT"
eq "set: --ci-wait all records nothing" "" "$(key_of s-wait relevant_checks.txt)"
OUT=$(cd "$PWD" && env PATH="$STUB_PATH" CI_WAIT=all "$RV" --relevant --session s-wait-env 2>/dev/null)
eq "set: CI_WAIT=all in the environment is off" off "$OUT"
rel s-bad --ci-wait some
eq "set: a --ci-wait other than all or empty is a usage error" 2 "$RC"

mkrepo b "$(jq -c 'del(.always_required)' <<<"$MAP")"
change skills/plan/a.md
rel s-nokey
eq "set: a merge-base map with no always_required is off" off "$OUT"
eq "set: and records nothing" "" "$(key_of s-nokey relevant_checks.txt)"
case "$ERR" in *"no always_required"*) pass "set: stderr says why it is off" ;; *) fail "set: stderr: $ERR" ;; esac
# The key added on the remote later doesn't turn it on: the merge-base decides.
remote_map b ".always_required = [$LINT]" || fail "set: could not edit the remote's map"
rel s-nokey2
eq "set: always_required added only on the default branch leaves it off" off "$OUT"

mkrepo c "$(jq -c '.always_required = []' <<<"$MAP")"
change skills/plan/a.md
rel s-empty-twin
eq "set: an empty always_required counts as present, the twins alone" "$L_GATE" "$OUT"
git checkout -q -B docs origin/main && change docs/x.md
rel s-empty
eq "set: an empty set is off, never an empty wait" off "$OUT"

mkrepo d "$(jq -c '.always_required = [{"workflow": "elsewhere.yml", "job": "lint"}]' <<<"$MAP")"
change docs/x.md
rel s-malformed
eq "set: an always_required outside .github/workflows/ is off" off "$OUT"
mkrepo e "$(jq -c '.always_required = {"workflow": ".github/workflows/lint.yml"}' <<<"$MAP")"
change docs/x.md
rel s-malformed2
eq "set: an always_required that isn't an array is off" off "$OUT"

# ---------------------------------------------------------------------------
# Part 2: the gate as work-on.md ships it
# ---------------------------------------------------------------------------
echo "--- the gate"

RAW=$(koto_gate_command "$WORK_ON" ci_passing)
GATE=$(koto_unquote_scalar "$RAW")
[ -n "$GATE" ] || { fail "could not read ci_passing from $WORK_ON"; GATE="exit 9"; }
case "$GATE" in
    *'ci-relevant.sh" --session "{{SESSION_NAME}}" --ci-wait "{{CI_WAIT}}" $N; case $? in 0) exit 0 ;; 1) ;; *)'*)
        pass "ci_passing reads the relevant set first, and falls to every check on anything but 0 and 1" ;;
    *) fail "ci_passing's relevant read: $GATE" ;;
esac

# run_gate <session> [CI_WAIT]: the gate in the current repository. Sets GOT, ERR.
run_gate() {
    local cmd="$GATE"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$REPO_ROOT}"
    cmd="${cmd//\{\{SESSION_NAME\}\}/$1}"
    cmd="${cmd//\{\{CI_WAIT\}\}/${2:-}}"
    env PATH="$STUB_PATH" sh -c "$cmd" >/dev/null 2>"$WORKDIR/gate.err"
    GOT=$?
    ERR=$(cat "$WORKDIR/gate.err")
}
# checks <json objects...>: the list gh reports.
checks() { jq -sc '.' <<<"$*" > "$FIX/checks.json"; : > "$FIX/gh.log"; }
ck() { jq -nc --arg n "$1" --arg w "$2" --arg b "$3" --arg l "${4:-https://github.com/acme/widgets/actions/runs/1/job/$RANDOM}" \
    '{name: $n, workflow: $w, bucket: $b, link: $l}'; }
comments() { [ -f "$FIX/comments" ] || { echo 0; return; }; grep -c '^----$' "$FIX/comments"; }
echo "$H1" > "$FIX/head"

cd "$WORKDIR/r-a" || exit 2
# The twin part 1 added on the remote goes again; scan stays required there.
remote_map a 'del(.commands.plain.hosted)' || fail "gate: could not edit the remote's map"
git checkout -q -B g-docs "$(git rev-list --max-parents=0 HEAD)"
change docs/x.md

C_LINT_PASS=$(ck lint Lint pass)
C_COORD_PENDING=$(ck test-coordinate-scripts "Check coordinate scripts" pending)
C_SCAN_PASS=$(ck scan .github/workflows/scan.yml pass)

# The remote's map since part 1 adds scan; a docs change waits on lint and scan.
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_COORD_PENDING"
run_gate g1
eq "gate: a change selecting no coordinate command is green while a coordinate-only check is pending" 0 "$GOT"

checks "$(ck lint Lint pending)" "$C_SCAN_PASS"
run_gate g2
eq "gate: an always-required check still pending holds" 1 "$GOT"
case "$ERR" in *"relevant, not passed: lint (Lint): pending"*) pass "gate: stderr names the relevant check not passed" ;; *) fail "gate: stderr: $ERR" ;; esac
checks "$C_LINT_PASS" "$C_SCAN_PASS"
run_gate g2
eq "gate: the always-required check passes, and the gate with it" 0 "$GOT"
checks "$(ck lint Lint fail)" "$C_SCAN_PASS"
run_gate g2b
eq "gate: a failed always-required check holds" 1 "$GOT"
checks "$C_SCAN_PASS" "$C_COORD_PENDING"
run_gate g3
eq "gate: an always-required check not reported at all holds" 1 "$GOT"
checks "$C_LINT_PASS" "$C_COORD_PENDING"
run_gate g3b
eq "gate: a check only the current default branch's map requires holds (the union)" 1 "$GOT"
checks
run_gate g3c
eq "gate: no checks at all is not green" 1 "$GOT"

git checkout -q -B g-plan "$(git rev-list --max-parents=0 HEAD)"
change skills/plan/a.md
C_GATE_PASS=$(ck "skill-gate (ubuntu-latest)" "Check skill gate" pass)
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$(ck "skill-gate (ubuntu-latest)" "Check skill gate" pending)" "$C_COORD_PENDING"
run_gate g4
eq "gate: a selected twin still pending holds" 1 "$GOT"
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$(ck "skill-gate (ubuntu-latest)" "Check skill gate" skipping)" \
    "$(ck "skill-gate-suites (ubuntu-latest, 2)" "Check skill gate" fail)"
run_gate g5
eq "gate: a skipped twin holds (its slice failed)" 1 "$GOT"
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$(ck "skill-gate (ubuntu-latest)" "Another workflow" pass)"
run_gate g5b
eq "gate: a job of the twin's name in another workflow doesn't answer for the twin" 1 "$GOT"

# A failing check outside the set: green, one neutral comment per head.
EVIL='evil @octocat #12 <img src=x> [link](https://example.com) `code`'
rm -f "$FIX/comments"
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_GATE_PASS" \
    "$(ck "$EVIL" "Check coordinate scripts" fail "https://github.com/acme/widgets/actions/runs/9/job/9#step:1")"
run_gate g6
eq "gate: a failing check outside the set doesn't hold" 0 "$GOT"
eq "gate: it gets one comment" 1 "$(comments)"
BODY=$(cat "$FIX/comments" 2>/dev/null)
case "$BODY" in
    *'`evil _octocat _12 _img src=x_ _link_(https://example.com) code`'*'`https://github.com/acme/widgets/actions/runs/9/job/9_step:1`'*)
        pass "gate: the comment carries the name and link, mentions and markup neutralised" ;;
    *) fail "gate: the comment: $BODY" ;;
esac
case "$BODY" in *@*|*'<img'*|*'#12'*) fail "gate: the comment still mentions, tags or references: $BODY" ;; *) pass "gate: no @, # reference or tag reaches the comment" ;; esac
KEY=$(key_of g6 ci_outside_failures.txt)
eq "gate: ci_outside_failures.txt records the check once, at the head, posted" 1 "$(grep -c "^$H1${TAB}Check coordinate scripts${TAB}evil _octocat.*${TAB}posted\$" <<<"$KEY")"
run_gate g6
eq "gate: green again at the same head" 0 "$GOT"
eq "gate: no second comment at the same head" 1 "$(comments)"
echo "$H2" > "$FIX/head"
run_gate g6
eq "gate: a new head comments again" 2 "$(comments)"
eq "gate: and records a line per head" 2 "$(key_of g6 ci_outside_failures.txt | grep -c 'posted$')"
echo "$H1" > "$FIX/head"

# A comment that can't be posted doesn't hold the run, and is tried again.
rm -f "$FIX/comments"
touch "$FIX/comment.fail"
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_GATE_PASS" "$(ck other-check "Other" fail)"
run_gate g7
eq "gate: a comment that fails to post doesn't hold the run" 0 "$GOT"
eq "gate: it is recorded not-posted" 1 "$(key_of g7 ci_outside_failures.txt | grep -c 'not-posted$')"
rm -f "$FIX/comment.fail"
run_gate g7
eq "gate: the next green read posts it" 1 "$(comments)"
eq "gate: and the line now says posted, once" "1 0" \
    "$(key_of g7 ci_outside_failures.txt | grep -c "${TAB}posted\$") $(key_of g7 ci_outside_failures.txt | grep -c 'not-posted$')"

# Not green: nothing is commented, however the outside checks read.
rm -f "$FIX/comments"
checks "$(ck lint Lint pending)" "$C_SCAN_PASS" "$C_GATE_PASS" "$(ck other-check "Other" fail)"
run_gate g8
eq "gate: a relevant check pending holds" 1 "$GOT"
eq "gate: and nothing is commented while it holds" 0 "$(comments)"

# Off: every check, as before.
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_GATE_PASS" "$C_COORD_PENDING"
run_gate g9 all
eq "gate: CI_WAIT=all waits on the pending coordinate check" 1 "$GOT"
checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_GATE_PASS" "$(ck "skill-gate-suites (ubuntu-latest, 2)" "Check skill gate" skipping)"
run_gate g9 all
eq "gate: CI_WAIT=all reads skipped as green, as before" 0 "$GOT"

cd "$WORKDIR/r-b" || exit 2
checks "$C_LINT_PASS" "$C_GATE_PASS" "$C_COORD_PENDING"
run_gate g10
eq "gate: with no always_required at the merge-base, a pending coordinate check holds" 1 "$GOT"
checks "$C_LINT_PASS" "$C_GATE_PASS" "$(ck test-coordinate-scripts "Check coordinate scripts" pass)"
run_gate g10
eq "gate: with no always_required, every check green is green" 0 "$GOT"
eq "gate: with no always_required, nothing is recorded" "" "$(key_of g10 relevant_checks.txt)"

# Merge readiness is unchanged: /execute reads every check, never the set.
MV="$REPO_ROOT/skills/execute/scripts/merge-verdict.sh"
if grep -q -- '--relevant\|--outside\|ci-relevant' "$MV"; then fail "merge readiness reads a filtered list"
else pass "merge readiness (merge-verdict.sh) reads every check, never the relevant set"; fi
OWNED=$(koto_unquote_scalar "$(koto_gate_command "$REPO_ROOT/skills/execute/koto-templates/execute.md" owned_ci_passing)")
case "$OWNED" in
    *ci-relevant*|*--relevant*|*--outside*) fail "/execute's owned_ci_passing reads the relevant set" ;;
    "") fail "could not read owned_ci_passing" ;;
    *) pass "/execute's owned_ci_passing still waits on every check" ;;
esac

# ---------------------------------------------------------------------------
# Part 3: the shipped ci_monitor under real koto
# ---------------------------------------------------------------------------
echo "--- koto"

if [ -z "$REAL_KOTO" ]; then
    skip "koto not on PATH; the routing cases need the engine"
else
    CI_MONITOR=$(awk '
        $0 == "  ci_monitor:" { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }' "$WORK_ON")
    STUBBED=$(printf '%s\n' "$CI_MONITOR" | awk '
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ && gate != "ci_passing" { print "        command: \"exit 0\""; next }
        { print }')
    cat > "$WORKDIR/fixture.md" <<FIXTURE
---
name: ci-relevant-fixture
version: "1.0"
description: The shipped ci_monitor, every gate but ci_passing passing.
initial_state: start
variables:
  PLUGIN_ROOT:
    description: Plugin root
    required: false
  CI_WAIT:
    description: As work-on.md declares it
    required: false
    pattern: ^(all)?\$
states:
  start:
    transitions:
      - target: ci_monitor
$STUBBED
  ci_pass_counting:
    terminal: true
  hosted_record:
    terminal: true
  verification:
    terminal: true
  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
---

## start
Stand-in for pr_creation.

## ci_monitor
Green CI routes on the gates.

## ci_pass_counting
Stand-in terminal: green CI reached it.

## hosted_record
Stand-in terminal.

## verification
Stand-in terminal.

## done_blocked
Blocked.
FIXTURE
    KOTO_PATH="$WORKDIR/ghbin:$PATH"
    # tick <session> [CI_WAIT]: init and one koto next in the current repository; sets STATE.
    tick() {
        local vars="--var PLUGIN_ROOT=$REPO_ROOT"
        [ -z "${2:-}" ] || vars="$vars --var CI_WAIT=$2"
        RESP=$(env PATH="$KOTO_PATH" "$REAL_KOTO" init "$1" --template "$WORKDIR/fixture.md" $vars >/dev/null 2>"$WORKDIR/init.err" \
            && env PATH="$KOTO_PATH" "$REAL_KOTO" next "$1" --no-cleanup 2>"$WORKDIR/next.err")
        STATE=$(jq -r '.state // empty' <<<"$RESP" 2>/dev/null)
    }
    cd "$WORKDIR/r-a" || exit 2
    git checkout -q g-docs
    checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_COORD_PENDING"
    tick k-green-$$
    eq "koto: a docs change with a coordinate-only check pending reaches ci_pass_counting" ci_pass_counting "$STATE"
    REC=$(env PATH="$KOTO_PATH" "$REAL_KOTO" context get "k-green-$$" relevant_checks.txt 2>/dev/null)
    eq "koto: the session records relevant_checks.txt" "$(printf '%s\n%s' "$L_LINT" "$L_SCAN")" "$REC"

    checks "$(ck lint Lint pending)" "$C_SCAN_PASS" "$C_COORD_PENDING"
    tick k-hold-$$
    eq "koto: a pending always-required check holds the run at ci_monitor" ci_monitor "$STATE"

    checks "$C_LINT_PASS" "$C_SCAN_PASS" "$C_COORD_PENDING"
    tick k-all-$$ all
    eq "koto: CI_WAIT=all holds the run on the pending coordinate check" ci_monitor "$STATE"

    # koto answers an init it refuses with JSON on stdout.
    env PATH="$KOTO_PATH" "$REAL_KOTO" init "k-bad-$$" --template "$WORK_ON" --var CI_WAIT=some \
        --var PLUGIN_ROOT="$REPO_ROOT" --var ARTIFACT_PREFIX=x >"$WORKDIR/bad.out" 2>"$WORKDIR/bad.err"
    BAD_RC=$?
    if [ "$BAD_RC" -ne 0 ] && jq -e '.code == "invalid_var" and .var == "CI_WAIT"' "$WORKDIR/bad.out" >/dev/null 2>&1; then
        pass "koto: work-on.md refuses a CI_WAIT other than all (invalid_var)"
    else
        fail "koto: CI_WAIT=some was not refused as invalid_var (exit $BAD_RC): $(head -c 300 "$WORKDIR/bad.out")"
    fi
    env PATH="$KOTO_PATH" "$REAL_KOTO" init "k-ok-$$" --template "$WORK_ON" --var CI_WAIT=all \
        --var PLUGIN_ROOT="$REPO_ROOT" --var ARTIFACT_PREFIX=x >"$WORKDIR/ok.out" 2>"$WORKDIR/ok.err"
    eq "koto: work-on.md accepts CI_WAIT=all" 0 "$?"
    for s in k-green-$$ k-hold-$$ k-all-$$ k-bad-$$ k-ok-$$; do
        env PATH="$KOTO_PATH" "$REAL_KOTO" session cleanup "$s" >/dev/null 2>&1
    done
fi

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
