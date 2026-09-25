# coord-test-helpers.sh — shared fixtures for the coordinated scripts' tests.
#
# Sourced by coordinated-next_test.sh, coordination-verdict_test.sh,
# record-coordination-verdict_test.sh, node-push_test.sh, node-cut_test.sh,
# coord-merge_test.sh, and record-coord-setup_test.sh. Not a test itself.
#
# GitHub is the eval gh shim (skills/execute/evals/fixtures/bin/gh) in its
# repository-model mode: each case writes a gh/db.json seed into its own
# scenario directory and points the shim at it with EVAL_SCENARIO_DIR, so the
# tests exercise the same call surface the coordinated evals run on, and every
# gh call lands in the case's call log.
#
# koto is a stub whose context store is a directory, so reads, clears, and
# writes are observable without an engine.
#
# Callers set SCRIPT_DIR (this directory) before sourcing, and define nothing
# these names use.

CT_FIXTURES="$SCRIPT_DIR/../evals/fixtures"
CT_WORK=$(mktemp -d "${TMPDIR:-/tmp}/coord-test.XXXXXX") || exit 1
trap 'rm -rf "$CT_WORK"' EXIT
CT_BIN="$CT_WORK/bin"
mkdir -p "$CT_BIN" "$CT_WORK/home"
export HOME="$CT_WORK/home"
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

ln -s "$CT_FIXTURES/bin/gh" "$CT_BIN/gh"
cat > "$CT_BIN/koto" <<'STUB'
#!/usr/bin/env bash
store="${KOTO_STORE:?}"
printf '%s\n' "$*" >> "$store/koto-calls.log"
[ "$1" = context ] || { echo "koto stub: only context is served" >&2; exit 9; }
d="$store/ctx/$3"
mkdir -p "$d"
case "$2" in
    add) [ "${KOTO_FAIL_ADD:-}" = "$4" ] && exit 3; cat > "$d/$4" ;;
    get) [ -f "$d/$4" ] || exit 3; cat "$d/$4" ;;
    remove) rm -f "$d/$4" ;;
    exists) [ -f "$d/$4" ] ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$CT_BIN/koto"
# A shirabe stub: --coordination-body passes a body carrying the declaration
# marker and fails one without it (the check the real validator makes first);
# --merge-gate passes unless CT_GATE_FAIL is set. Each call is logged.
cat > "$CT_BIN/shirabe" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KOTO_STORE:?}/shirabe-calls.log"
case "$1 $2" in
    "validate --coordination-body")
        [ -n "${CT_BODY_FAIL:-}" ] && exit 2
        grep -qF 'This is a **coordination PR**' "$3" || exit 2
        exit 0
        ;;
    "validate --merge-gate")
        [ -n "${CT_GATE_FAIL:-}" ] && exit 2
        exit 0
        ;;
esac
exit 1
STUB
chmod +x "$CT_BIN/shirabe"
export PATH="$CT_BIN:$PATH"
unset SHIRABE_BIN
export EVAL_SCENARIO=coord-test
export MERGE_CONFIRM_WAIT_SECS=0

CT_HEAD=1111111111111111111111111111111111111111
CT_OTHER=2222222222222222222222222222222222222222
CT_REPO=acme/repo-a
CT_SLUG=t
CT_CB=docs/t
CT_CORE=pr-repo-a-core
CT_CLI=pr-repo-a-cli

# ct_case <name> -- a fresh case directory: its scenario (gh/db.json), its
# koto store, and its call logs. Sets CASE, and exports what the stubs read.
ct_case() {
    CASE="$CT_WORK/cases/$1"
    rm -rf "$CASE"
    mkdir -p "$CASE/scenario/gh" "$CASE/ctx"
    : > "$CASE/koto-calls.log"
    : > "$CASE/shirabe-calls.log"
    export EVAL_SCENARIO_DIR="$CASE/scenario"
    export GH_CALL_LOG="$CASE/gh.log"
    export KOTO_STORE="$CASE"
    unset CT_GATE_FAIL CT_BODY_FAIL KOTO_FAIL_ADD
    CT_PRS='[]'
    CT_INDEX=""
    CT_COORD_STATE=OPEN
    CT_COORD_DRAFT=true
    CT_COORD_MERGE=ok
    CT_LOGIN=eval-user
}

# ct_index_line <node> <repo> <number> [head] -- append one PR index line.
ct_index_line() {
    local l="- $1 | $2:docs/plans/PLAN-$CT_SLUG.md#$3 | open"
    [ -n "${4:-}" ] && l="$l | head=$4"
    CT_INDEX="$CT_INDEX$l
"
}

# ct_pr <repo> <number> <head-branch> [key=json ...] -- add a PR to the model.
# Defaults: owned, open, ready, CLEAN, one passing check, head CT_HEAD.
ct_pr() {
    local repo="$1" n="$2" head="$3" kv obj
    shift 3
    obj=$(jq -nc --arg r "$repo" --argjson n "$n" --arg h "$head" --arg sha "$CT_HEAD" --arg login "$CT_LOGIN" '{
        repo: $r, number: $n, headRefName: $h, baseRefName: "main", author: $login,
        isCrossRepository: false, state: "OPEN", isDraft: false, title: "t", body: "",
        headRefOid: $sha, mergeStateStatus: "CLEAN", reviewDecision: "",
        checks: [{name: "build", bucket: "pass"}], files: ["src/x.go"], merge: "ok"}')
    for kv in "$@"; do
        obj=$(printf '%s' "$obj" | jq -c --arg k "${kv%%=*}" --argjson v "${kv#*=}" '.[$k] = $v')
    done
    CT_PRS=$(printf '%s' "$CT_PRS" | jq -c --argjson o "$obj" '. + [$o]')
}

# ct_write_db -- write the case's gh/db.json: the model repository, the
# coordination PR (#10 on CT_CB carrying the marker and CT_INDEX), and the PRs
# ct_pr added.
ct_write_db() {
    local body
    body=$(printf '# Coordination PR: %s\n\n> This is a **coordination PR** for a coordinated effort.\n\n## PR Index\n\n%s\n## Merge Order\n\n```merge-order\n%s | open\n%s | open\n```\n' \
        "$CT_SLUG" "$CT_INDEX" "$CT_CORE" "$CT_CLI")
    jq -n --arg login "$CT_LOGIN" --argjson prs "$CT_PRS" --arg body "$body" --arg cb "$CT_CB" \
        --arg state "$CT_COORD_STATE" --argjson draft "$CT_COORD_DRAFT" --arg cmerge "$CT_COORD_MERGE" \
        --arg sha "$CT_HEAD" '
        def repo: {default_branch: "main", allow_squash_merge: true, allow_merge_commit: true,
                   allow_rebase_merge: true, branch: {name: "main", protected: false},
                   rules: [{type: "required_status_checks",
                            parameters: {required_status_checks: [{context: "build"}]}}]};
        {login: $login, default_repo: "acme/repo-a", next_number: 50,
         repos: {"acme/repo-a": repo, "acme/repo-b": repo},
         created_defaults: {mergeStateStatus: "CLEAN", reviewDecision: "",
                            checks: [{name: "build", bucket: "pass"}], files: ["src/x.go"], merge: "ok"},
         prs: ([{repo: "acme/repo-a", number: 10, headRefName: $cb, baseRefName: "main",
                 author: "eval-user", isCrossRepository: false, state: $state, isDraft: $draft,
                 title: "docs: t", body: $body, headRefOid: $sha, mergeStateStatus: "CLEAN",
                 reviewDecision: "", checks: [{name: "build", bucket: "pass"}],
                 files: ["docs/plans/PLAN-t.md"], merge: $cmerge}] + $prs)}' \
        > "$CASE/scenario/gh/db.json"
}

# ct_plan <dir> [two-repo] -- write docs/plans/PLAN-t.md into <dir>: an
# issue-carrying coordinated PLAN (no tracking_level, so plan-to-tasks.sh's
# table path, which needs no shirabe binary). One repository, groups core
# (issues 1, 2) and cli (issue 3, blocked by 1); or, with `two-repo`, two
# independent roots in acme/repo-a and acme/repo-b, Group default.
ct_plan() {
    mkdir -p "$1/docs/plans"
    if [ "${2:-}" = two-repo ]; then
        cat > "$1/docs/plans/PLAN-t.md" <<'PLAN'
---
schema: plan/v1
status: Active
execution_mode: coordinated
milestone: "t"
issue_count: 2
---

# PLAN: t

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat a](https://example.com/1) | None | testable |
| ^_Repo: acme/repo-a \| Group: default_ | | |
| [#2: feat b](https://example.com/2) | None | testable |
| ^_Repo: acme/repo-b \| Group: default_ | | |
PLAN
    else
        cat > "$1/docs/plans/PLAN-t.md" <<'PLAN'
---
schema: plan/v1
status: Active
execution_mode: coordinated
milestone: "t"
issue_count: 3
---

# PLAN: t

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat parser](https://example.com/1) | None | testable |
| ^_Repo: acme/repo-a \| Group: core_ | | |
| [#2: test parser](https://example.com/2) | [#1](https://example.com/1) | testable |
| ^_Repo: acme/repo-a \| Group: core_ | | |
| [#3: feat cli](https://example.com/3) | [#1](https://example.com/1) | testable |
| ^_Repo: acme/repo-a \| Group: cli_ | | |
PLAN
    fi
}

# ct_repo <dir> -- a clone of a fresh bare origin (default branch main, one
# commit), checked out on CT_CB with the PLAN committed. Prints nothing; the
# origin is <dir>.origin.git.
ct_repo() {
    local d="$1"
    git init -q --bare "$d.origin.git"
    git init -q "$d"
    (
        cd "$d" || exit 1
        git commit -q --allow-empty -m init
        git remote add origin "$d.origin.git"
        git push -q origin main
        git remote set-head origin main >/dev/null || true
        git fetch -q origin
        git checkout -q -b "$CT_CB"
    )
}

ct_calls() { [ -f "$GH_CALL_LOG" ] && cat "$GH_CALL_LOG"; return 0; }
