# coord-test-helpers.sh — shared fixtures for the coordinated scripts' tests.
#
# Sourced by run-record_test.sh, coordinated-next_test.sh,
# coordination-verdict_test.sh, record-coordination-verdict_test.sh,
# node-push_test.sh, node-cut_test.sh, coord-merge_test.sh,
# record-coord-setup_test.sh, record-coord-follow-up_test.sh,
# repo-visibility_test.sh, coordinated-visibility_test.sh,
# execute-coordinated-engine_test.sh, coordinated-home-outside_test.sh,
# coord-render_test.sh, and merge-message_test.sh. Not a test itself.
#
# GitHub is the eval gh shim (skills/execute/evals/fixtures/bin/gh) in its
# repository-model mode: each case writes a gh/db.json seed into its own
# scenario directory and points the shim at it with EVAL_SCENARIO_DIR, so the
# tests exercise the same call surface the coordinated evals run on, and every
# gh call lands in the case's call log.
#
# koto is a stub whose context store is a directory, so reads, clears, and
# writes are observable without an engine; `workflows --roots` lists the
# sessions the store holds a directory for. It has no workspaces: a session
# is one directory whatever the caller's working directory, which is how the
# coordinated scripts reach the run's session from a node's worktree. For the
# run's trail (scripts/run-trail.sh) and its lookup
# (scripts/run-record-lookup.sh) it also serves `init` (a session directory,
# --attach-live attaching), `session list` (each session with a fixed id
# derived from its name), `--help` (naming no --workspace option, so reads
# run from the addressed directory), and --from-file/--to-file.
#
# The index sessions those scripts write sit at the shared address, which
# record-store.sh's test-only SHIRABE_RUN_RECORD_TEST_ROOT points at a
# directory under CT_WORK, so no suite touches the real
# /tmp/shirabe-run-record and suites run side by side never share one: each
# reads only the index directories it wrote, and its exit removes them.
#
# Sourcing stops the suite (exit 1) unless the koto on PATH is the stub. A
# suite that drives the real koto (rm -f "$CT_BIN/koto") calls
# ct_real_koto_guard before its first koto command.
#
# Callers set SCRIPT_DIR (this directory) before sourcing, and define nothing
# these names use.

CT_FIXTURES="$SCRIPT_DIR/../evals/fixtures"
CT_WORK=$(mktemp -d "${TMPDIR:-/tmp}/coord-test.XXXXXX") || exit 1
trap 'rm -rf "$CT_WORK"' EXIT
CT_BIN="$CT_WORK/bin"
mkdir -p "$CT_BIN" "$CT_WORK/home"
SHIRABE_RUN_RECORD_TEST_ROOT="$(cd "$CT_WORK" && pwd -P)/shared-record"
export SHIRABE_RUN_RECORD_TEST_ROOT
export HOME="$CT_WORK/home"
# --global writes land in this HOME's config, never a file the caller's
# environment names: some cases write --global settings.
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# gh is a wrapper around the shim: it appends `gh <args>` to the case's
# order.log, which the koto stub appends to as well, so a test can check that
# a body post came after the koto write of the keys it shows (ct_order). With
# CT_GH_HOOK set, it runs that script with gh's arguments first: a case's way
# to change the model between two calls (a person editing the body).
cat > "$CT_BIN/gh" <<STUB
#!/usr/bin/env bash
# A command koto runs may not see KOTO_STORE (the engine suites' real koto):
# the call then goes unlogged here, and still reaches the shim.
if [ -n "\${KOTO_STORE:-}" ]; then printf 'gh %s\\n' "\$*" >> "\$KOTO_STORE/order.log"; fi
if [ -n "\${CT_GH_HOOK:-}" ]; then
    bash "\$CT_GH_HOOK" "\$@" || exit 1
fi
exec "$CT_FIXTURES/bin/gh" "\$@"
STUB
chmod +x "$CT_BIN/gh"
cat > "$CT_BIN/koto" <<'STUB'
#!/usr/bin/env bash
store="${KOTO_STORE:?}"
printf '%s\n' "$*" >> "$store/koto-calls.log"
printf 'koto %s\n' "$*" >> "$store/order.log"
for a in "$@"; do
    case "$a" in
        --help) printf 'Usage: koto %s [OPTIONS]\n  -h, --help\n' "$1 ${2:-}"; exit 0 ;;
    esac
done
# workflows --roots: every session the store holds a context directory for.
if [ "$1 ${2:-}" = "workflows --roots" ]; then
    [ -n "${KOTO_FAIL_WORKFLOWS:-}" ] && exit 3
    (cd "$store/ctx" && find . -mindepth 1 -maxdepth 1 -type d | sed 's#^\./##' | LC_ALL=C sort) \
        | jq -R '{name: .}' | jq -sc .
    exit 0
fi
# session list: every session directory, each with an id fixed by its name.
if [ "$1 ${2:-}" = "session list" ]; then
    (cd "$store/ctx" && find . -mindepth 1 -maxdepth 1 -type d | sed 's#^\./##' | LC_ALL=C sort) \
        | while IFS= read -r n; do
            printf '%s\t%s\n' "$n" "$(printf '%s' "$n" | cksum | tr -c '0-9\n' '-')"
        done | jq -R 'split("\t") | {id: .[0], session_id: ("sid-" + .[1])}' | jq -sc .
    exit 0
fi
# init <name> ...: a session directory; --attach-live attaches to one there.
if [ "$1" = init ]; then
    [ -n "${KOTO_FAIL_INIT:-}" ] && [ "${KOTO_FAIL_INIT}" = "$2" ] && exit 3
    mkdir -p "$store/ctx/$2"
    printf '{"name":"%s","state":"open"}\n' "$2"
    exit 0
fi
[ "$1" = context ] || { echo "koto stub: only context, init, session list and workflows --roots are served" >&2; exit 9; }
if [ "$2" = list ]; then
    # list [--prefix <p>] <session>, the flag on either side.
    shift 2
    prefix=""; s=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefix) prefix="$2"; shift 2 ;;
            *) s="$1"; shift ;;
        esac
    done
    [ -n "${KOTO_FAIL_LIST:-}" ] && exit 3
    d="$store/ctx/$s"
    [ -d "$d" ] || { printf '[]\n'; exit 0; }
    (cd "$d" && find . -type f | sed 's#^\./##' | LC_ALL=C sort) \
        | while IFS= read -r k; do case "$k" in "$prefix"*) printf '%s\n' "$k" ;; esac; done \
        | jq -R . | jq -sc .
    exit 0
fi
d="$store/ctx/$3"
mkdir -p "$d"
case "$2" in
    add) [ "${KOTO_FAIL_ADD:-}" = "$4" ] && exit 3; mkdir -p "$(dirname "$d/$4")"
         if [ "${5:-}" = --from-file ]; then cat -- "$6" > "$d/$4"; else cat > "$d/$4"; fi ;;
    get) [ "${KOTO_FAIL_GET:-}" = "$4" ] && exit 3; [ -f "$d/$4" ] || exit 3
         if [ "${5:-}" = --to-file ]; then cat "$d/$4" > "$6"; else cat "$d/$4"; fi ;;
    remove) rm -f "$d/$4" ;;
    exists) [ "${KOTO_FAIL_EXISTS:-}" = "$4" ] && exit 2; [ -f "$d/$4" ] ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$CT_BIN/koto"
# A shirabe stub: --coordination-body passes a body carrying the declaration
# marker and fails one without it (the check the real validator makes first);
# --pr-body passes a body with exactly one top-level `---` line (outside
# fences) and text above it, and a --pr-title of the form <type>[(scope)]: <x>,
# and fails otherwise or when CT_PR_BODY_FAIL is set; --merge-gate passes
# unless CT_GATE_FAIL is set. Each call is logged.
cat > "$CT_BIN/shirabe" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KOTO_STORE:?}/shirabe-calls.log"
case "$1 $2" in
    "validate --coordination-body")
        [ -n "${CT_BODY_FAIL:-}" ] && exit 2
        grep -qF 'This is a **coordination PR**' "$3" || exit 2
        exit 0
        ;;
    "validate --pr-body")
        [ -n "${CT_PR_BODY_FAIL:-}" ] && exit 2
        awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } f { next }
             /^---[[:space:]]*$/ { sep++; next }
             !sep && /[^[:space:]]/ { text = 1 }
             END { exit !(sep == 1 && text) }' "$3" || exit 2
        if [ "${4:-}" = --pr-title ]; then
            grep -Eq '^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\([^)]+\))?!?: .' <<<"${5:-}" || exit 2
        fi
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
# The koto on PATH must be the stub until a suite removes it on purpose: the
# scripts under test write sessions, and a real koto would write them to a
# real store. Every stub suite stops here, before its first case, when it
# isn't; a suite that drives the real koto removes the stub after sourcing
# this file and calls ct_real_koto_guard instead.
if [ "$(command -v koto)" != "$CT_BIN/koto" ]; then
    echo "FAIL: the koto on PATH is not the context stub at $CT_BIN/koto; no case ran" >&2
    exit 1
fi
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
    mkdir -p "$CASE/scenario/gh" "$CASE/ctx/execute-t"
    # The run identity record-coord-setup.sh mints when it seals a new run,
    # for the execute-t session the tests drive; the other scripts under test
    # only read it.
    printf '%s' 00112233445566778899aabbccddeeff > "$CASE/ctx/execute-t/run_id"
    # The PR content switch execute-open.sh records at the run's open. The
    # coordinated suites were written for the full coordination body, so a
    # case reads include unless it sets CT_CONTENT=omit before ct_case (or
    # rewrites this key) to drive the default, Part 1 alone.
    printf '%s' "${CT_CONTENT:-include}" > "$CASE/ctx/execute-t/pr_content"
    : > "$CASE/koto-calls.log"
    : > "$CASE/shirabe-calls.log"
    : > "$CASE/order.log"
    export EVAL_SCENARIO_DIR="$CASE/scenario"
    export GH_CALL_LOG="$CASE/gh.log"
    export KOTO_STORE="$CASE"
    unset CT_GATE_FAIL CT_BODY_FAIL KOTO_FAIL_ADD KOTO_FAIL_GET KOTO_FAIL_EXISTS KOTO_FAIL_LIST KOTO_FAIL_WORKFLOWS KOTO_FAIL_INIT
    unset CT_RECORD_REPOS GH_SHIM_FAIL CT_GH_HOOK
    CT_PRS='[]'
    CT_INDEX=""
    CT_COORD_STATE=OPEN
    CT_COORD_DRAFT=true
    CT_COORD_MERGE=ok
    CT_LOGIN=eval-user
    CT_VIS_A=public
    CT_VIS_B=public
}

# The run record (run-record-lib.sh's layout), seeded through run-record.sh
# itself so the record's shape and its checks are defined once. Each helper
# writes into CT_RECORD_SESSION (execute-t unless a caller sets it) in the
# case's koto store, and returns nonzero, with run-record.sh's refusal on
# stderr, when the write is refused.
CT_RECORD_SESSION=execute-t
# The default PLAN fixture's nodes, as record-coord-setup.sh seals them.
CT_NODES_DEFAULT='[{"name":"pr-repo-a-core","kind":"pr","repo":"acme/repo-a","waits_on":[]},{"name":"pr-repo-a-cli","kind":"pr","repo":"acme/repo-a","waits_on":["pr-repo-a-core"]}]'

# ct_nodes_of <plan-file> -- the PLAN's nodes in the run/setup shape.
ct_nodes_of() {
    bash "$SCRIPT_DIR/../../plan/scripts/plan-to-tasks.sh" "$1" 2>/dev/null </dev/null \
        | jq -c '[.[] | {name, kind: (.vars.NODE_KIND // "pr"), repo: (.vars.REPO // ""), waits_on}]'
}

# ct_record <verb> <json> -- one run-record.sh write.
ct_record() {
    local f="$CASE/record-doc.json"
    printf '%s' "$2" > "$f"
    bash "$SCRIPT_DIR/run-record.sh" "$1" --session "$CT_RECORD_SESSION" --json "$f" >/dev/null </dev/null \
        || { echo "ct_record: run-record.sh $1 refused [$2]" >&2; rm -f "$f"; return 1; }
    rm -f "$f"
}

# ct_record_setup [store] [coord-pr] [nodes-json] -- seal run/setup: store
# github, coordination PR #10, and the default PLAN fixture's nodes unless
# given. repos is CT_RECORD_REPOS (comma-joined) when set, else the PR nodes'
# repositories.
ct_record_setup() {
    local store="${1:-github}" cpr="${2:-10}" nodes="${3:-$CT_NODES_DEFAULT}" repos
    if [ -n "${CT_RECORD_REPOS:-}" ]; then
        repos=$(jq -cn --arg r "$CT_RECORD_REPOS" '$r | split(",") | unique')
    else
        repos=$(printf '%s' "$nodes" | jq -c '[.[] | select(.kind == "pr") | .repo] | unique')
    fi
    ct_record setup "$(jq -cn --arg s "$store" --argjson c "$cpr" --argjson r "$repos" --argjson n "$nodes" \
        '{"run/setup": {store: $s, coordination_pr: $c, repos: $r, mode: "coordinated", nodes: $n, run_lines: {}}}')" \
        || return 1
    ct_seed_self
}

# ct_seed_self -- the root's trail/self, as record-coord-setup.sh writes it
# once it sealed the record (scripts/run-trail.sh self): this directory as
# the workspace, the session, its id and its run_id (the case's run_id, or
# the helpers' default when the session holds none yet). node-push.sh's index
# entries read it. Under the stub it is written straight into the store, so
# the case's koto call log holds only the calls the script under test makes;
# under the real koto, through run-trail.sh itself.
ct_seed_self() {
    local rid sid
    if [ ! -x "$CT_BIN/koto" ]; then
        bash "$SCRIPT_DIR/../../../scripts/run-trail.sh" self --session "$CT_RECORD_SESSION" </dev/null >/dev/null 2>&1
        return 0
    fi
    rid=$(cat "$CASE/ctx/$CT_RECORD_SESSION/run_id" 2>/dev/null) || rid=""
    [ -n "$rid" ] || rid=00112233445566778899aabbccddeeff
    sid="sid-$(printf '%s' "$CT_RECORD_SESSION" | cksum | tr -c '0-9\n' '-')"
    mkdir -p "$CASE/ctx/$CT_RECORD_SESSION/trail"
    jq -cn --arg w "$(pwd -P)" --arg s "$CT_RECORD_SESSION" --arg i "$sid" --arg r "$rid" \
        '{workspace: $w, session: $s, session_id: $i, run_id: $r}' > "$CASE/ctx/$CT_RECORD_SESSION/trail/self"
}

# ct_record_node <node> <repo> <pr> [head] -- a node's recorded PR and pushed
# head (CT_HEAD unless given), as node-push.sh records them.
ct_record_node() {
    ct_record push "$(jq -cn --arg k "run/node/$1" --arg r "$2" --argjson p "$3" --arg h "${4:-$CT_HEAD}" \
        '{($k): {repo: $r, pr: $p, head: $h}}')"
}

# ct_record_follow_up <node> <repo> <pr> [head] [removed] -- a follow-up PR
# recorded against <node> (run/follow-up/<node>/<pr>), as setup's follow-up
# step records it; `removed` true marks it removed.
ct_record_follow_up() {
    ct_record follow-up "$(jq -cn --arg k "run/follow-up/$1/$3" --arg r "$2" --argjson p "$3" \
        --arg h "${4:-$CT_HEAD}" --arg rm "${5:-}" \
        '{($k): ({repo: $r, pr: $p, head: $h} + (if $rm == "true" then {removed: true} else {} end))}')"
}

# ct_order -- the case's gh and koto calls, interleaved in the order they
# were made, one per line.
ct_order() { [ -f "$CASE/order.log" ] && cat "$CASE/order.log"; return 0; }

# ct_record_cascade pushed <sha> | failed <step> -- the cascade's verdict.
ct_record_cascade() {
    case "$1" in
        pushed) ct_record cascade "$(jq -cn --arg h "$2" '{"run/cascade": {verdict: "pushed", head: $h}}')" ;;
        failed) ct_record cascade "$(jq -cn --arg s "$2" '{"run/cascade": {verdict: "failed", step: $s}}')" ;;
        *) echo "ct_record_cascade: pushed <sha> or failed <step>" >&2; return 1 ;;
    esac
}

# ct_ctx_writes -- the case's koto context writes (add and remove), one per
# line, from the stub's call log.
ct_ctx_writes() { grep -E '^context (add|remove) ' "$CASE/koto-calls.log" 2>/dev/null; return 0; }

# ct_index_line <node> <repo> <number> [head] -- append one PR index line.
ct_index_line() {
    local l="- $1 | $2:docs/plans/PLAN-$CT_SLUG.md#$3 | open"
    [ -n "${4:-}" ] && l="$l | head=$4"
    CT_INDEX="$CT_INDEX$l
"
}

# ct_pr <repo> <number> <head-branch> [key=json ...] -- add a PR to the model.
# Defaults: owned, open, ready, CLEAN, one passing check, head CT_HEAD, titled
# `feat(t): <head-branch>` with a two-part body (a Part 1, one top-level
# `---`, the fixed fields), the shape a squash message is built from.
ct_pr() {
    local repo="$1" n="$2" head="$3" kv obj
    shift 3
    obj=$(jq -nc --arg r "$repo" --argjson n "$n" --arg h "$head" --arg sha "$CT_HEAD" --arg login "$CT_LOGIN" '{
        repo: $r, number: $n, headRefName: $h, baseRefName: "main", author: $login,
        isCrossRepository: false, state: "OPEN", isDraft: false, title: ("feat(t): " + $h),
        body: "Implements the node.\n\n---\n\nCoordinated node.\n",
        headRefOid: $sha, mergeStateStatus: "CLEAN", reviewDecision: "",
        checks: [{name: "build", bucket: "pass"}], files: ["src/x.go"], merge: "ok"}')
    for kv in "$@"; do
        if [ "${kv%%=*}" = index ]; then
            ct_index_entry "$repo" "$n" "$(jq -r . <<<"${kv#*=}")"
            continue
        fi
        obj=$(printf '%s' "$obj" | jq -c --arg k "${kv%%=*}" --argjson v "${kv#*=}" '.[$k] = $v')
    done
    CT_PRS=$(printf '%s' "$CT_PRS" | jq -c --argjson o "$obj" '. + [$o]')
}

# ct_index_entry <repo> <number> <run_id> -- an entry naming <run_id> in the
# PR's index session at its owner's shared address, laid out as
# scripts/run-trail.sh index writes one and dated before any entry a script
# under test writes, so a later entry is the latest. ct_pr's `index="<id>"`
# key plants one: the run a PR belongs to is its index entry, never its text.
ct_index_entry() {
    local owner name
    owner=$(printf '%s' "${1%%/*}" | tr '[:upper:]' '[:lower:]')
    name=$(printf '%s' "${1#*/}" | tr '[:upper:]' '[:lower:]')
    mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/$owner" "$CASE/ctx/pr.$owner.$name.$2/run"
    jq -nc '{workspace: "/w", session: "execute-t", session_id: "sid-9", mode: "coordinated",
        topic: "t", written_at: "2020-01-01T00:00:00Z"}' > "$CASE/ctx/pr.$owner.$name.$2/run/$3"
}

# ct_follow_up_pr <repo> <number> [key=json ...] -- add a follow-up PR to the
# model: ct_pr's defaults on head branch fix/<number> (a person's branch, not
# a node's impl/ one), titled `fix(t): follow-up <number>`.
ct_follow_up_pr() {
    local repo="$1" n="$2"
    shift 2
    ct_pr "$repo" "$n" "fix/$n" "title=\"fix(t): follow-up $n\"" "$@"
}

# ct_rendered_body <file> <run> <store> [<node>=<pr> ...] -- the coordination
# PR's body as coord-render.sh renders it, through the codec's own cb_render:
# the default PLAN's nodes, run=<run> (left out when empty), store=<store>,
# and an index line for each <node>=<pr> given, in acme/repo-a with head
# CT_OTHER, which is never a live head in the model.
ct_rendered_body() {
    local f="$1" run="$2" store="$3" recs='{}' kv
    shift 3
    for kv in "$@"; do
        recs=$(jq -cn --argjson m "$recs" --arg n "${kv%%=*}" --argjson p "${kv#*=}" --arg h "$CT_OTHER" \
            '$m + {($n): {repo: "acme/repo-a", pr: $p, head: $h}}')
    done
    jq -cn --arg run "$run" --arg store "$store" --argjson nodes "$CT_NODES_DEFAULT" --argjson recs "$recs" '
        {topic: "t", part1: null, run_lines: {topic: "t"}, store: $store, run: $run, nodes: $nodes,
         records: $recs, follow_ups: {}, states: {},
         home: {repo: "acme/repo-a", pr: 10, visibility: "public"}, visibility: {}}' > "$CASE/render-doc.json"
    (
        # shellcheck source=../../../scripts/lib/coordination-body.sh
        . "$SCRIPT_DIR/../../../scripts/lib/coordination-body.sh" && cb_render "$CASE/render-doc.json"
    ) > "$f"
}

# ct_write_db [body-file] -- write the case's gh/db.json: the model
# repository, the coordination PR (#10 on CT_CB, whose body is /scope's shape
# carrying the marker and CT_INDEX, or the given file's bytes), and the PRs
# ct_pr added. CT_VIS_A and CT_VIS_B are the two repositories' `visibility`
# (public by default); `none` leaves the repository out of the model, so a
# read of it fails.
ct_write_db() {
    local body
    if [ -n "${1:-}" ]; then
        body=$(cat -- "$1"; printf x)
        body="${body%x}"
    else
        body=$(printf '# Coordination PR: %s\n\n> This is a **coordination PR** for a coordinated effort.\n\n## PR Index\n\n%s\n## Merge Order\n\n```merge-order\n%s | open\n%s | open\n```\n' \
            "$CT_SLUG" "$CT_INDEX" "$CT_CORE" "$CT_CLI")
    fi
    jq -n --arg login "$CT_LOGIN" --argjson prs "$CT_PRS" --arg body "$body" --arg cb "$CT_CB" \
        --arg state "$CT_COORD_STATE" --argjson draft "$CT_COORD_DRAFT" --arg cmerge "$CT_COORD_MERGE" \
        --arg sha "$CT_HEAD" --arg va "$CT_VIS_A" --arg vb "$CT_VIS_B" '
        def repo: {default_branch: "main", allow_squash_merge: true, allow_merge_commit: true,
                   allow_rebase_merge: true, branch: {name: "main", protected: false},
                   rules: [{type: "required_status_checks",
                            parameters: {required_status_checks: [{context: "build"}]}}]};
        {login: $login, default_repo: "acme/repo-a", next_number: 50,
         repos: ({"acme/repo-a": (repo + {visibility: $va}), "acme/repo-b": (repo + {visibility: $vb})}
                 | with_entries(select(.value.visibility != "none"))),
         created_defaults: {mergeStateStatus: "CLEAN", reviewDecision: "",
                            checks: [{name: "build", bucket: "pass"}], files: ["src/x.go"], merge: "ok"},
         prs: ([{repo: "acme/repo-a", number: 10, headRefName: $cb, baseRefName: "main",
                 author: "eval-user", isCrossRepository: false, state: $state, isDraft: $draft,
                 title: "docs: t", body: $body, headRefOid: $sha, mergeStateStatus: "CLEAN",
                 reviewDecision: "", checks: [{name: "build", bucket: "pass"}],
                 files: ["docs/plans/PLAN-t.md"], merge: $cmerge}] + $prs)}' \
        > "$CASE/scenario/gh/db.json"
}

# ct_plan <dir> [two-repo|gated|remote|three] -- write docs/plans/PLAN-t.md
# into <dir>: an issue-carrying coordinated PLAN (no tracking_level, so
# plan-to-tasks.sh's table path, which needs no shirabe binary). One
# repository, groups core (issues 1, 2) and cli (issue 3, blocked by 1); with
# `three`, the same plus an independent group docs (issue 4, pr-repo-a-docs);
# with `gated`, the same plus a gate node publish-core after core and before cli;
# with `two-repo`, two independent roots in acme/repo-a and acme/repo-b, Group
# default; or, with `remote`, the one-repository shape with every node in
# acme/repo-b (pr-repo-b-core, then pr-repo-b-cli), so a coordination PR in
# acme/repo-a sits in a repository that holds no node.
ct_plan() {
    mkdir -p "$1/docs/plans"
    if [ "${2:-}" = remote ]; then
        ct_plan "$1"
        sed -i.bak 's#acme/repo-a#acme/repo-b#' "$1/docs/plans/PLAN-t.md" && rm -f "$1/docs/plans/PLAN-t.md.bak"
        return
    fi
    if [ "${2:-}" = three ]; then
        ct_plan "$1"
        sed -i.bak 's#^issue_count: 3$#issue_count: 4#' "$1/docs/plans/PLAN-t.md" && rm -f "$1/docs/plans/PLAN-t.md.bak"
        printf '%s\n' '| [#4: docs](https://example.com/4) | None | testable |' \
            '| ^_Repo: acme/repo-a \| Group: docs_ | | |' >> "$1/docs/plans/PLAN-t.md"
        return
    fi
    if [ "${2:-}" = gated ]; then
        ct_plan "$1"
        printf '%s\n' '| ^_Gate: publish-core \| After: pr-repo-a-core \| Before: pr-repo-a-cli_ | | |' \
            >> "$1/docs/plans/PLAN-t.md"
        return
    fi
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
# commit), checked out on CT_CB (the caller writes and commits the PLAN). Prints nothing; the
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

# ct_real_koto_guard -- for a suite that drives the real koto: clear the
# caller's koto session context (every KOTO_SESSION_* variable,
# KOTO_SESSIONS_BASE, KOTO_TICK_SESSION), so koto's store follows this
# suite's scratch HOME, and stop the suite before any case runs unless
# `koto session dir` resolves under the scratch directory. Call it before the
# first koto command.
ct_real_koto_guard() {
    local v dir work_p
    unset KOTO_SESSIONS_BASE KOTO_TICK_SESSION
    for v in $(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$v"
    done
    dir=$(koto session dir coord-test-guard </dev/null 2>/dev/null) || dir=""
    work_p=$(cd "$CT_WORK" && pwd -P) && [ -n "$work_p" ] \
        || { echo "FAIL: could not resolve the scratch directory" >&2; exit 1; }
    case "$dir" in
        "$CT_WORK"/*|"$work_p"/*) ;;
        *)
            echo "FAIL: koto's session directory [$dir] is not under this suite's scratch directory; no case ran" >&2
            exit 1
            ;;
    esac
}
