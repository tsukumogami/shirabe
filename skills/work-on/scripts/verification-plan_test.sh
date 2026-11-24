#!/usr/bin/env bash
# verification-plan_test.sh -- VERIFICATION=auto's resolution: does
# run-verification.sh --plan pick hosted CI exactly when every command the run
# would start has a hosted twin and no changed path is in a risky class, does
# --resolved read the decision back, and does --twins notice a twin gone from
# the current default branch?
# Part of the work-on skill
#
# Builds throwaway repositories whose main carries a verification map with one
# twinned row (`chk`, each skills/*, one hosted entry) and one row with no twin
# (`plain`, for top.txt), and a bare origin, so --twins has a remote default
# branch to fetch. koto is a stand-in on PATH that keeps context keys as files,
# so the record --plan writes, a fix round's fix_round.json and the
# verification_twin_gone key are all plain files here.
#
# Cases:
#   - a skills-only change whose only selected command has a twin resolves to
#     hosted-ci (exit 0), starts nothing, and records the hosted reason;
#   - a change that also selects the untwinned command resolves to local;
#   - a template, ci, security or engine path beside the same skills change
#     resolves to local, naming the class;
#   - a fix round whose only started command has a twin resolves to hosted-ci,
#     its carried checks listed with the run they came from, while the same
#     diff in a fresh session (nothing carried) resolves to local;
#   - a step on a shared branch, and a session holding verification_twin_gone,
#     resolve to local;
#   - --resolved reads hosted-ci back, and local once the gone key is there;
#   - --twins passes while the twin is on the default branch, fails naming the
#     check once the remote's map drops it (after a fetch: the local
#     remote-tracking ref is stale until then), fails when the workflow file is
#     gone, and passes for a run that resolved local.
#
# Usage: verification-plan_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RV="$SCRIPT_DIR/run-verification.sh"
HOSTED_REASON="hosted twins cover every selected command"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$RV" ] || { echo "$RV is not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-plan-test.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P) || exit 2
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
unset SHIRABE_VERIFY_FULL SHIRABE_VERIFY_BASE
mkdir -p "$HOME" "$WORKDIR/bin"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

# The koto stand-in: context add/exists/get/remove on files under
# $KOTO_STUB_STORE/<session>/<key>; anything else exits 9.
cat > "$WORKDIR/bin/koto" <<'EOF'
#!/bin/sh
echo "$*" >> "$KOTO_STUB_STORE/calls"
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
chmod +x "$WORKDIR/bin/koto"
export KOTO_STUB_STORE="$WORKDIR/kotostore"
mkdir -p "$KOTO_STUB_STORE"
export PATH="$WORKDIR/bin:$PATH"

REC="$WORKDIR/ran.rec"
TWIN='{"workflow": ".github/workflows/ci.yml", "job": "gate (ubuntu-latest)", "runs": "chk {skill}"}'
MAP=$(jq -cn --arg f "$REC" --argjson t "$TWIN" '{
    schema: "shirabe-verification-map/v1",
    commands: {
        chk: {run: ["bin/rec.sh", $f, "chk"], each: "skills/*", hosted: [$t]},
        plain: {run: ["bin/rec.sh", $f, "plain"]}},
    entries: [{paths: ["skills/**"], commands: ["chk"]},
              {paths: ["top.txt"], commands: ["plain"]}]}')

# mkrepo <name>: a repository whose main carries the map, the workflow the
# twin names and a recording command, pushed to a bare origin; HEAD is a
# `work` branch at main. Leaves the shell in the repository.
mkrepo() {
    local dir="$WORKDIR/r-$1"
    git init -q --bare "$WORKDIR/o-$1.git" || exit 2
    mkdir -p "$dir/bin" "$dir/skills/a" "$dir/skills/b" "$dir/.claude/shirabe-extensions" "$dir/.github/workflows"
    cd "$dir" || exit 2
    git init -q -b main .
    printf '#!/bin/sh\nrec=$1; shift\nprintf "%%s\\n" "$*" >> "$rec"\n' > bin/rec.sh
    chmod +x bin/rec.sh
    echo base > top.txt
    echo base > skills/a/f.txt
    echo base > skills/b/f.txt
    printf 'on:\n  pull_request:\njobs:\n  gate:\n    runs-on: ubuntu-latest\n' > .github/workflows/ci.yml
    printf '%s\n' "$MAP" > .claude/shirabe-extensions/verification-map.json
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

# plan <session> [args]: run --plan; sets RC, OUT and REC_JSON (the record).
plan() {
    local s=$1
    shift
    OUT=$("$RV" --plan --session "$s" "$@" 2>"$WORKDIR/plan.err")
    RC=$?
    REC_JSON=$(cat "$KOTO_STUB_STORE/$s/verification_plan" 2>/dev/null)
}
recq() { printf '%s' "$REC_JSON" | jq -r "$1" 2>/dev/null; }

# --- hosted and local ----------------------------------------------------------------

echo "--- a skills-only change with a twinned command"
mkrepo plan
change skills/a/f.txt
rm -f "$REC"
plan p-hosted
eq "skills only: --plan exits 0 (hosted-ci)" 0 "$RC"
eq "skills only: it prints the resolution and the reason" "hosted-ci: $HOSTED_REASON" "$OUT"
eq "skills only: the record resolves to hosted-ci" hosted-ci "$(recq .resolution)"
eq "skills only: the record carries the hosted reason" "$HOSTED_REASON" "$(recq .reason)"
eq "skills only: the record names the started check and its twin" \
    "[{\"check\":\"chk:a\",\"id\":\"chk\",\"hosted\":[$(jq -c . <<<"$TWIN")]}]" "$(recq '.started | tojson')"
eq "skills only: the record is at this head" "$(git rev-parse HEAD)" "$(recq .head)"
eq "skills only: the record's schema" shirabe-verification-plan/v1 "$(recq .schema)"
[ ! -e "$REC" ] && pass "skills only: --plan ran no command" || fail "skills only: --plan ran [$(cat "$REC")]"
RES=$("$RV" --locate --session p-hosted | sed -n 3p)
[ ! -e "$RES" ] && pass "skills only: --plan wrote no result" || fail "skills only: a result exists at $RES"
eq "skills only: --resolved reads hosted-ci" hosted-ci "$("$RV" --resolved --session p-hosted)"

echo "--- a selected command without a twin"
change top.txt
plan p-untwinned
eq "untwinned: --plan exits 1 (local)" 1 "$RC"
eq "untwinned: the record resolves to local" local "$(recq .resolution)"
case "$OUT" in
    "local: no hosted twin in the merge-base's map for: plain") pass "untwinned: the reason names the check" ;;
    *) fail "untwinned: printed [$OUT]" ;;
esac
eq "untwinned: --resolved reads local" local "$("$RV" --resolved --session p-untwinned)"

echo "--- risky path classes"
# Each beside the skills change that alone resolves to hosted-ci.
for case in "template|skills/a/koto-templates/x.md" "ci|.github/workflows/ci.yml" \
            "security|.claude/settings.json" "engine|skills/work-on/scripts/run-verification.sh"; do
    cls=${case%%|*}
    path=${case#*|}
    git checkout -q -B "risky-$cls" main
    change skills/a/f.txt "$path"
    plan "p-$cls"
    eq "$cls path: --plan exits 1 (local)" 1 "$RC"
    case "$OUT" in
        "local: the change touches a path in the ci, security, template or engine class: $path ("*"$cls"*")")
            pass "$cls path: the reason names $path and its class" ;;
        *) fail "$cls path: printed [$OUT]" ;;
    esac
done

echo "--- a rename out of a risky class still counts its old side"
git checkout -q -B risky-rename main
mkdir -p skills/a/koto-templates
echo template > skills/a/koto-templates/t.md
git add -A && git commit -q -m "add a template"
git push -q origin risky-rename:main && git fetch -q origin
git checkout -q -B risky-rename2 origin/main
git mv skills/a/koto-templates/t.md skills/a/t.md
git commit -q -m "move the template out"
plan p-rename
eq "renamed template: --plan exits 1 (local)" 1 "$RC"
case "$OUT" in *"skills/a/koto-templates/t.md (template"*) pass "renamed template: the old side is named" ;;
    *) fail "renamed template: printed [$OUT]" ;; esac

echo "--- a shared branch and a gone twin"
git checkout -q -B shared origin/main
change skills/b/f.txt
plan p-shared --shared-branch impl/shared
eq "shared branch: --plan exits 1 (local)" 1 "$RC"
case "$OUT" in "local: a step on the shared branch impl/shared"*) pass "shared branch: the reason says so" ;;
    *) fail "shared branch: printed [$OUT]" ;; esac
plan p-shared-empty --shared-branch ""
eq "an empty --shared-branch is no shared branch: --plan exits 0" 0 "$RC"
mkdir -p "$KOTO_STUB_STORE/p-gone"
echo gone > "$KOTO_STUB_STORE/p-gone/verification_twin_gone"
plan p-gone
eq "a session holding verification_twin_gone: --plan exits 1 (local)" 1 "$RC"
case "$OUT" in *verification_twin_gone*) pass "gone key: the reason names it" ;;
    *) fail "gone key: printed [$OUT]" ;; esac

echo "--- --resolved after a twin is gone"
mkdir -p "$KOTO_STUB_STORE/p-hosted"
echo gone > "$KOTO_STUB_STORE/p-hosted/verification_twin_gone"
eq "--resolved reads local once verification_twin_gone is there" local "$("$RV" --resolved --session p-hosted)"
rm -f "$KOTO_STUB_STORE/p-hosted/verification_twin_gone"
eq "--resolved for a session with no record reads local" local "$("$RV" --resolved --session p-none)"

echo "--- usage"
"$RV" --resolved --session p-hosted --shared-branch x >/dev/null 2>&1
eq "--shared-branch is refused outside --plan" 2 "$?"

# --- a fix round ---------------------------------------------------------------------

echo "--- a fix round whose only started command has a twin"
mkrepo fix
change skills/a/f.txt skills/b/f.txt top.txt
"$RV" --start --session f-orig >"$WORKDIR/start.out" 2>&1 || fail "fix round: the parent's --start: $(cat "$WORKDIR/start.out")"
PARENT_RES=$("$RV" --locate --session f-orig | sed -n 3p)
k=0
while [ ! -f "$PARENT_RES" ] && [ "$k" -lt 150 ]; do sleep 0.2; k=$((k + 1)); done
jq -e '.status == "done" and ([.commands[].outcome] | all(. == "passed"))' "$PARENT_RES" >/dev/null 2>&1 \
    && pass "fix round: the parent passed every check" || fail "fix round: the parent's result: $(head -c 400 "$PARENT_RES" 2>&1)"
PARENT_BEFORE=$(cat "$PARENT_RES" 2>/dev/null)
BASE=$(git rev-parse HEAD)
mkdir -p "$KOTO_STUB_STORE/f-orig-fix-1"
jq -cn --arg base "$BASE" '{from: "f-orig", round: 1, base: $base}' > "$KOTO_STUB_STORE/f-orig-fix-1/fix_round.json"
change skills/a/f.txt
rm -f "$REC"
plan f-orig-fix-1
eq "fix round: --plan exits 0 (hosted-ci)" 0 "$RC"
eq "fix round: the started command is the round's own" '["chk:a"]' "$(recq '[.started[].check] | tojson')"
eq "fix round: the carried checks are kept, with the run they came from" \
    "[{\"check\":\"chk:b\",\"carried_from\":{\"session\":\"f-orig\",\"head\":\"$BASE\"}},{\"check\":\"plain\",\"carried_from\":{\"session\":\"f-orig\",\"head\":\"$BASE\"}}]" \
    "$(recq '.carried | tojson')"
[ ! -e "$REC" ] && pass "fix round: --plan ran no command" || fail "fix round: --plan ran [$(cat "$REC")]"
eq "fix round: the parent's result is unchanged" "$PARENT_BEFORE" "$(cat "$PARENT_RES" 2>/dev/null)"
# The same diff from the merge-base, in a session that is no fix round, starts
# plain too, which has no twin.
plan f-not-a-round
eq "the same head outside a fix round: --plan exits 1 (local)" 1 "$RC"
case "$OUT" in *"for: plain"*) pass "outside a fix round: plain is the untwinned check" ;;
    *) fail "outside a fix round: printed [$OUT]" ;; esac

echo "--- a fix round with nothing left to start"
# A round at the parent's own verified head: its diff is empty, so every
# selected check is carried and nothing would start. Local verification then
# costs nothing and writes the carried records into a result.
git checkout -q -B nothing "$BASE"
mkdir -p "$KOTO_STUB_STORE/f-orig-fix-0"
jq -cn --arg base "$BASE" '{from: "f-orig", round: 1, base: $base}' > "$KOTO_STUB_STORE/f-orig-fix-0/fix_round.json"
plan f-orig-fix-0
eq "a fix round with nothing to start: --plan exits 1 (local)" 1 "$RC"
case "$OUT" in "local: every selected check is carried"*) pass "nothing to start: the reason says every check is carried" ;;
    *) fail "nothing to start: printed [$OUT]" ;; esac
eq "nothing to start: the record lists three carried checks" 3 "$(recq '.carried | length')"

# --- --twins -------------------------------------------------------------------------

echo "--- --twins"
cd "$WORKDIR/r-plan" || exit 2
git checkout -q -B twins origin/main
change skills/a/f.txt
plan t-run
eq "twins: the run resolves to hosted-ci" 0 "$RC"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: every twin is on the default branch: exit 0" 0 "$?"
"$RV" --twins --session p-untwinned >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: a run that resolved local: exit 0" 0 "$?"
"$RV" --twins --session t-never >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: a run with no record: exit 0" 0 "$?"

# The remote's main drops the twin, from another clone, so this repository's
# origin/main is stale until --twins fetches it.
OTHER="$WORKDIR/other"
git clone -q "$WORKDIR/o-plan.git" "$OTHER" || exit 2
(cd "$OTHER" && jq '.commands.chk |= del(.hosted)' .claude/shirabe-extensions/verification-map.json > m.json \
    && mv m.json .claude/shirabe-extensions/verification-map.json \
    && git commit -q -am "drop the twin" && git push -q origin main) || fail "twins: could not edit the remote's map"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: the remote's map dropped the twin: exit 1 after a fetch" 1 "$?"
case "$(cat "$WORKDIR/twins.err")" in *"for: chk:a"*) pass "twins: stderr names the check" ;;
    *) fail "twins: stderr [$(cat "$WORKDIR/twins.err")]" ;; esac
mkdir -p "$KOTO_STUB_STORE/t-run"
echo gone > "$KOTO_STUB_STORE/t-run/verification_twin_gone"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: once verification_twin_gone is written, exit 0 (the run is local now)" 0 "$?"
rm -f "$KOTO_STUB_STORE/t-run/verification_twin_gone"

# Put the twin back but remove the workflow file it names.
(cd "$OTHER" && git revert --no-edit HEAD >/dev/null && git rm -q .github/workflows/ci.yml \
    && git commit -q -m "drop the workflow" && git push -q origin main) || fail "twins: could not edit the remote again"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: the twin's workflow file is gone: exit 1" 1 "$?"
(cd "$OTHER" && git revert --no-edit HEAD >/dev/null && git push -q origin main) || fail "twins: could not restore the remote"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: the twin and its workflow are back: exit 0" 0 "$?"

# A fetch that fails is exit 2, never a pass.
git remote set-url origin "$WORKDIR/no-such-origin.git"
"$RV" --twins --session t-run >/dev/null 2>"$WORKDIR/twins.err"
eq "twins: a fetch that fails: exit 2" 2 "$?"
git remote set-url origin "$WORKDIR/o-plan.git"

echo
echo "verification-plan_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
