#!/usr/bin/env bash
# adopt-or-create-pr_test.sh — orchestrator_setup's home-PR step, and the write
# set it runs against
# Part of the execute skill
#
# Two scripts that run before any child is spawned:
#
#   adopt-or-create-pr.sh  finds the owned PR on a branch, opens one only on the
#                          create path, and records home_pr from owned-pr.sh's
#                          output (never from anything the agent says);
#   record-write-set.sh    fixes the run's write set, `repos`, at start.
#
# A `gh` stub serves per-case fixtures (a numbered file answers the Nth call,
# which is how "no PR, then the PR just created" is served) and logs every call;
# a `koto` stub keeps context in a directory. No network, no engine.
#
# Usage: adopt-or-create-pr_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ADOPT="$SCRIPT_DIR/adopt-or-create-pr.sh"
WRITESET="$SCRIPT_DIR/record-write-set.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/adopt-or-create-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"
# The run record's shared address is a directory of this suite's own
# (record-store.sh's test-only override), never the real
# /tmp/shirabe-run-record a run on this host writes to.
SHIRABE_RUN_RECORD_TEST_ROOT="$(cd "$WORK" && pwd -P)/shared-record"
export SHIRABE_RUN_RECORD_TEST_ROOT
S=execute-topic
URL="https://github.com/o/r/pull/7"

# The run record's writes reach it too (scripts/run-trail.sh): `init` opens
# the index session, keys may hold slashes, and `session list` names every
# session with one fixed id. koto-cwd.log keeps the directory each call ran
# from, so a case can see the index written from the shared address.
# KOTO_FAIL_KEY fails a `context add` of keys under that prefix.
cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
store="${KOTO_STORE:?}"
printf '%s\n' "$*" >> "$store/koto.log"
printf '%s\t%s\n' "$(pwd -P)" "$*" >> "$store/koto-cwd.log"
case "$1 ${2:-}" in
    "init "*) mkdir -p "$store/ctx/$2"; echo '{}'; exit 0 ;;
    "session list")
        for s in "$store"/ctx/*/; do
            n=${s%/}; n=${n##*/}
            printf '{"id":"%s","session_id":"sid-0001"}\n' "$n"
        done | jq -sc .
        exit 0 ;;
esac
d="$store/ctx/$3"
mkdir -p "$d"
case "$1 $2" in
    "context add")
        case "$4" in "${KOTO_FAIL_KEY:-//}"*) exit 1 ;; esac
        mkdir -p "$(dirname "$d/$4")"; cat > "$d/$4" ;;
    "context get") [ -f "$d/$4" ] || exit 3; cat "$d/$4" ;;
    "context exists") [ -f "$d/$4" ] ;;
    "context list")
        # context list <s> --prefix <p>: the keys under <p>, as a JSON array.
        p=""; [ "${4:-}" = --prefix ] && p=${5:-}
        (cd "$d" && find . -type f | sed 's#^\./##' | grep "^$p" | jq -Rsc 'split("\n") | map(select(length > 0))') ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$BIN/koto"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?}"
printf '%s\n' "$*" >> "$fix/gh.log"
key=unknown
case "$1 ${2:-}" in
    "api user") key=user ;;
    "api repos/"*) key=repo ;;
    "pr list") key=list ;;
    "pr create") key=create
        # Keep what the PR would be opened with: the --body-file's content.
        while [ $# -gt 0 ]; do
            [ "$1" = "--body-file" ] && cp "$2" "$fix/created-body"
            shift
        done ;;
    "pr edit") key=edit ;;
    "repo view") key=repoview ;;
esac
n=0; [ -f "$fix/$key.count" ] && n=$(cat "$fix/$key.count"); n=$((n + 1)); echo "$n" > "$fix/$key.count"
out="$fix/$key.out"; [ -f "$fix/$key.out.$n" ] && out="$fix/$key.out.$n"
rcf="$fix/$key.rc"; [ -f "$fix/$key.rc.$n" ] && rcf="$fix/$key.rc.$n"
[ -f "$out" ] || [ -f "$rcf" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$out" ] && cat "$out"
rc=0; [ -f "$rcf" ] && rc=$(cat "$rcf")
exit "$rc"
STUB
chmod +x "$BIN/gh"

owned() { # owned <number> [jq edit] — one PR object on impl/topic
    jq -nc --arg n "$1" '{url: ("https://github.com/o/r/pull/" + $n), state: "OPEN",
        isCrossRepository: false, author: {login: "octo"}, baseRefName: "main", headRefName: "impl/topic"}' \
        | jq -c "${2:-.}"
}

new_case() {
    CASE="$WORK/cases/$1"
    rm -rf "$CASE"; mkdir -p "$CASE/ctx/$S"
    : > "$CASE/gh.log"; : > "$CASE/koto.log"
    echo '{"login":"octo"}' > "$CASE/user.out"
    echo '{"default_branch":"main"}' > "$CASE/repo.out"
    echo '[]' > "$CASE/list.out"
    : > "$CASE/create.out"
    # The run's identity, as execute-open.sh leaves it at the session's birth;
    # adopt-or-create-pr.sh only reads it.
    printf '%s' "$SEEDED" > "$CASE/ctx/$S/run_id"
}
SEEDED=00112233445566778899aabbccddeeff
ctx() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

# Exit 6 is the one answer that releases the takeover rule. Every other run is
# tallied here, and the end of the suite asserts none of them released it.
RELEASED_ELSEWHERE=""
OTHER_EXITS=""
# Runs in REPO_DIR: a repository with no `## PR Workflow Content:` header (the
# default, omit), unless a case points it at one that opts in.
mkdir -p "$WORK/omit-repo" "$WORK/include-repo"
printf '## PR Workflow Content: include\n' > "$WORK/include-repo/CLAUDE.md"
REPO_DIR="$WORK/omit-repo"
run_adopt() {
    OUT=$(cd "$REPO_DIR" && env KOTO_STORE="$CASE" GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$ADOPT" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
    if [ "$RC" -ne 6 ]; then
        OTHER_EXITS="$OTHER_EXITS $RC"
        grep -q '^::shirabe-rule::' "$CASE/stderr" && RELEASED_ELSEWHERE="$RELEASED_ELSEWHERE ${CASE##*/}:$RC"
    fi
}
creates() { grep -c '^pr create' "$CASE/gh.log"; }

# --- adopt: one owned PR on the branch ----------------------------------------

new_case adopt
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 0 ] && [ "$OUT" = "$URL" ] && [ "$(ctx home_pr)" = "$URL" ] \
    && [ "$(ctx waiting)" = "$URL:human" ] && [ "$(creates)" -eq 0 ]; then
    pass "one owned PR: adopted, home_pr and waiting recorded, no pr create"
else
    fail "adopt: exit $RC, out [$OUT], home_pr [$(ctx home_pr)], creates $(creates)"
fi

# The run record: the adopted PR is in the root's trail, and the PR's index
# session names the root, written from the shared address.
TRAIL_PR=$(ctx trail/pr/o.r.7)
INDEX_ENTRY=$(cat "$CASE/ctx/pr.o.r.7/run/$SEEDED" 2>/dev/null)
REPO_WS=$(cd "$REPO_DIR" && pwd -P)
SHARED_WS=$(mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/o" && cd "$SHIRABE_RUN_RECORD_TEST_ROOT/o" && pwd -P)
if [ "$(jq -r '[.repo, .number, .role, .state] | map(tostring) | join(" ")' <<<"$TRAIL_PR")" = "o/r 7 home open" ]; then
    pass "the adopted home PR is recorded in the root's trail/pr, role home, state open"
else
    fail "trail/pr/o.r.7: [$TRAIL_PR]"
fi
if [ "$(jq -r '[.session, .mode, .topic, .workspace] | join(" ")' <<<"$INDEX_ENTRY")" = "$S single-pr topic $REPO_WS" ] \
    && [ "$(jq -r '.workspace' <<<"$(ctx trail/self)")" = "$REPO_WS" ]; then
    pass "the PR's index entry names the root, its mode, its topic and the checkout it runs in"
else
    fail "index entry [$INDEX_ENTRY], trail/self [$(ctx trail/self)]"
fi
if grep -qF "$(printf '%s\tinit pr.o.r.7 ' "$SHARED_WS")" "$CASE/koto-cwd.log" \
    && grep -qF "$(printf '%s\tcontext add pr.o.r.7 run/%s' "$SHARED_WS" "$SEEDED")" "$CASE/koto-cwd.log" \
    && ! grep -q -- '--workspace' "$CASE/koto.log"; then
    pass "the index session is opened and written from the shared address, with no --workspace"
else
    fail "index writes: [$(cat "$CASE/koto-cwd.log")]"
fi

new_case trail-fails
echo "[$(owned 7)]" > "$CASE/list.out"
KOTO_FAIL_KEY=trail/pr
export KOTO_FAIL_KEY
run_adopt --session "$S" --repo o/r --head impl/topic
unset KOTO_FAIL_KEY
if [ "$RC" -eq 70 ] && [ -z "$OUT" ] && [ ! -e "$CASE/ctx/pr.o.r.7/run/$SEEDED" ]; then
    pass "a failed run-record write: exit 70, no URL printed, no index entry"
else
    fail "trail fails: exit $RC, out [$OUT]"
fi

new_case index-fails
echo "[$(owned 7)]" > "$CASE/list.out"
KOTO_FAIL_KEY=run/
export KOTO_FAIL_KEY
run_adopt --session "$S" --repo o/r --head impl/topic
unset KOTO_FAIL_KEY
if [ "$RC" -eq 70 ] && [ -z "$OUT" ] && [ -n "$(ctx trail/pr/o.r.7)" ]; then
    pass "a failed index write: exit 70 after the root's trail/pr is written"
else
    fail "index fails: exit $RC, out [$OUT]"
fi

new_case adopt-with-create
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 0 ] && [ "$(creates)" -eq 0 ]; then
    pass "--create with an owned PR already there reuses it and creates nothing"
else
    fail "adopt with --create: exit $RC, creates $(creates)"
fi

# --- zero survivors -----------------------------------------------------------

new_case current-branch-foreign
echo "[$(owned 7 '.author.login = "someone-else"')]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 4 ] && [ -z "$(ctx home_pr)" ] && [ "$(creates)" -eq 0 ]; then
    pass "another author's PR only, no --create: exit 4, not adopted, nothing recorded"
else
    fail "foreign no-create: exit $RC, home_pr [$(ctx home_pr)]"
fi

new_case create
echo '[]' > "$CASE/list.out.1"
echo "[$(owned 7)]" > "$CASE/list.out.2"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 0 ] && [ "$(creates)" -eq 1 ] && [ "$(ctx home_pr)" = "$URL" ]; then
    pass "zero owned PRs with --create: exactly one pr create, then the new PR is recorded"
else
    fail "create: exit $RC, creates $(creates), home_pr [$(ctx home_pr)]"
fi
if grep -q '^pr create --draft --repo o/r --head impl/topic --title impl: topic --body-file ' "$CASE/gh.log"; then
    pass "the create call is the fixed draft form"
else
    fail "create call: $(grep '^pr create' "$CASE/gh.log")"
fi
RID=$(ctx run_id)
if [[ $RID =~ ^[0-9a-f]{32}$ ]] \
    && [ "$(cat "$CASE/created-body")" = "Draft of the topic work; its description is written when the work is done." ]; then
    pass "default (omit): the created PR's body is one plain line, nothing of the run"
else
    fail "created body [$(cat "$CASE/created-body" 2>/dev/null)], run_id [$RID]"
fi
if grep -qF -e "$RID" -e "$S" -e 'shirabe''-run' -e 'Run record' "$CASE/created-body"; then
    fail "default: the created body carries the run: [$(cat "$CASE/created-body")]"
else
    pass "default: the created body holds no run id, session name, marker or record line"
fi
if [ -f "$CASE/ctx/pr.o.r.7/run/$RID" ]; then
    pass "the created PR's ownership is its index entry for this run, not its text"
else
    fail "no index entry for the created PR"
fi
if grep -q 'PLAN-' "$CASE/created-body"; then
    fail "default: the created body points at the PLAN: [$(cat "$CASE/created-body")]"
else
    pass "default: the created body names no PLAN file"
fi

new_case create-include
echo '[]' > "$CASE/list.out.1"
echo "[$(owned 7)]" > "$CASE/list.out.2"
REPO_DIR="$WORK/include-repo"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
REPO_DIR="$WORK/omit-repo"
WANT_BODY=$(printf 'Implements docs/plans/PLAN-topic.md.\n\n---\n\nRun record: %s (run %s)' "$S" "$SEEDED")
if [ "$RC" -eq 0 ] && [ "$(cat "$CASE/created-body")" = "$WANT_BODY" ]; then
    pass "include: the body points at the PLAN, and its Part 2 is the one Run record line"
else
    fail "include: exit $RC, created body [$(cat "$CASE/created-body" 2>/dev/null)]"
fi

# The switch is the run's recorded value, not the files at the write: an
# opener that recorded omit wins over a checkout whose header now says include.
new_case create-recorded-omit
echo '[]' > "$CASE/list.out.1"
echo "[$(owned 7)]" > "$CASE/list.out.2"
printf 'omit' > "$CASE/ctx/$S/pr_content"
REPO_DIR="$WORK/include-repo"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
REPO_DIR="$WORK/omit-repo"
if [ "$RC" -eq 0 ] && [ "$(cat "$CASE/created-body")" = "Draft of the topic work; its description is written when the work is done." ]; then
    pass "a recorded omit wins over an include header read at the write"
else
    fail "recorded omit: exit $RC, created body [$(cat "$CASE/created-body" 2>/dev/null)]"
fi

# --- the run's index entry --------------------------------------------------------

MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210
# plant <n> <run_id>: an index entry for PR <n>, laid out as run-trail.sh
# index writes one, dated well before any entry this suite's runs write.
plant() {
    mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/o" "$CASE/ctx/pr.o.r.$1/run"
    printf '{"workspace":"/w","session":"execute-topic","session_id":"sid-9","mode":"single-pr","topic":"topic","written_at":"2020-01-01T00:00:00Z"}' \
        > "$CASE/ctx/pr.o.r.$1/run/$2"
}

new_case index-mine
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"; plant 7 "$MINE"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 0 ] && [ "$(ctx home_pr)" = "$URL" ]; then
    pass "the PR this run recorded (its index entry) is adopted"
else
    fail "index-mine: exit $RC, home_pr [$(ctx home_pr)]"
fi

new_case index-foreign
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"; plant 7 "$OTHER"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 6 ] && [ -z "$(ctx home_pr)" ] && [ "$(creates)" -eq 0 ] \
    && ! grep -q '^pr edit' "$CASE/gh.log"; then
    pass "another run's PR on the branch: exit 6, not adopted, nothing created or edited"
else
    fail "index-foreign: exit $RC, home_pr [$(ctx home_pr)], creates $(creates)"
fi

# The same answer releases the takeover rule on stderr: the marker line, the
# rule's lines exactly as execute.md has them, and the end marker. The expected
# lines come from the registry's anchors and the template itself, so neither is
# written into this test.
ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
REG="$ROOT/references/rule-registry.json"
TEMPLATE="$ROOT/skills/execute/koto-templates/execute.md"
FIRST=$(jq -r '.rules[] | select(.id == "execute/pr-takeover-needs-signal") | .text.first' "$REG")
LAST=$(jq -r '.rules[] | select(.id == "execute/pr-takeover-needs-signal") | .text.last' "$REG")
A=$(grep -n -F -- "$FIRST" "$TEMPLATE" | cut -d: -f1); A=${A%%$'\n'*}
B=$(tail -n "+$A" "$TEMPLATE" | grep -n -F -- "$LAST" | cut -d: -f1); B=${B%%$'\n'*}; B=$((A + B - 1))
WANT=$(sed -n "${A},${B}p" "$TEMPLATE")
GOT=$(sed -n '/^::shirabe-rule::/,/^::shirabe-rule-end::$/p' "$CASE/stderr" | sed '1d;$d')
OPEN=$(grep '^::shirabe-rule::' "$CASE/stderr" | sed 's/^::shirabe-rule:://' | jq -r '.rule_id' 2>/dev/null)
if [ -n "$A" ] && [ "$GOT" = "$WANT" ] && [ "$OPEN" = "execute/pr-takeover-needs-signal" ] \
    && grep -q '^::shirabe-rule-end::$' "$CASE/stderr"; then
    pass "exit 6 releases the takeover rule on stderr, its lines exactly as execute.md has them"
else
    fail "takeover release: open [$OPEN], lines $A-$B, stderr [$(cat "$CASE/stderr")]"
fi
[ -z "$OUT" ] && pass "exit 6 still prints nothing on stdout" || fail "exit 6 printed on stdout: [$OUT]"

new_case index-takeover
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"; plant 7 "$OTHER"
run_adopt --session "$S" --repo o/r --head impl/topic --take-over --plan-slug topic
if [ "$RC" -eq 0 ] && [ "$(ctx home_pr)" = "$URL" ] && ! grep -q '^pr edit' "$CASE/gh.log" \
    && [ "$(creates)" -eq 0 ] && [ -f "$CASE/ctx/pr.o.r.7/run/$MINE" ]; then
    pass "--take-over writes this run's index entry for the other run's PR on impl/<slug>, edits no body, and adopts it"
else
    fail "index-takeover: exit $RC, home_pr [$(ctx home_pr)], edits $(grep -c '^pr edit' "$CASE/gh.log")"
fi

# Cross-PLAN: the branch the user is on (another PLAN's impl/<slug>, a
# scoping branch, a node branch) carries a live run's PR. A takeover there
# must be refused before any gh or koto call.
for head in impl/other-plan docs/topic impl/topic-node-a; do
    new_case "takeover-refused-$(printf '%s' "$head" | tr '/' '-')"
    echo "[$(owned 7)]" > "$CASE/list.out"
    run_adopt --session "$S" --repo o/r --head "$head" --take-over --plan-slug topic
    if [ "$RC" -eq 64 ] && [ ! -s "$CASE/gh.log" ] && ! grep -q '^pr edit' "$CASE/gh.log"; then
        pass "--take-over on $head (not this PLAN's impl/topic) is refused, nothing read or edited"
    else
        fail "--take-over on $head: exit $RC, gh [$(cat "$CASE/gh.log")]"
    fi
done
new_case takeover-no-slug
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --take-over
if [ "$RC" -eq 64 ] && [ ! -s "$CASE/gh.log" ]; then
    pass "--take-over without --plan-slug is refused"
else
    fail "--take-over without --plan-slug: exit $RC"
fi

new_case no-identity
rm -f "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 70 ] && [ ! -f "$CASE/ctx/$S/run_id" ] && [ ! -s "$CASE/gh.log" ]; then
    pass "a session with no run_id: exit 70, no id minted, no lookup made"
else
    fail "no-identity: exit $RC, run_id [$(ctx run_id)]"
fi

new_case index-unrecorded
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic
if [ "$RC" -eq 0 ] && [ "$(ctx home_pr)" = "$URL" ] && ! grep -q '^pr edit' "$CASE/gh.log"; then
    pass "a PR with no index entry (a /scope PR) is adopted on the login-and-branch match, unedited"
else
    fail "index-unrecorded: exit $RC, home_pr [$(ctx home_pr)]"
fi

new_case index-ambiguous
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7),$(owned 8)]" > "$CASE/list.out"; plant 7 "$MINE"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 3 ] && [ -z "$(ctx home_pr)" ] && [ "$(creates)" -eq 0 ]; then
    pass "an ambiguous lookup (owned-pr.sh 4) ends pr-adopt (3), nothing recorded or created"
else
    fail "index-ambiguous: exit $RC"
fi

new_case fork-then-create
echo "[$(owned 7 '.isCrossRepository = true')]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 3 ] && [ "$(creates)" -eq 1 ] && [ -z "$(ctx home_pr)" ]; then
    pass "a same-named fork PR: one pr create, the fork PR is never adopted; still none owned ends pr-adopt (3)"
else
    fail "fork then create: exit $RC, creates $(creates), home_pr [$(ctx home_pr)]"
fi

new_case create-fails
echo 1 > "$CASE/create.rc"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 5 ] && [ -z "$(ctx home_pr)" ]; then
    pass "a failed pr create: exit 5, nothing recorded"
else
    fail "create fails: exit $RC"
fi

# --- several, and read failure ------------------------------------------------

new_case several
echo "[$(owned 7),$(owned 8)]" > "$CASE/list.out"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 3 ] && [ "$(creates)" -eq 0 ] && [ -z "$(ctx home_pr)" ]; then
    pass "several owned PRs: exit 3 (pr-adopt), no create, nothing recorded"
else
    fail "several: exit $RC, creates $(creates)"
fi

new_case read-fails
rm -f "$CASE/list.out"; echo 1 > "$CASE/list.rc"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
if [ "$RC" -eq 2 ] && [ "$(creates)" -eq 0 ]; then
    pass "a failed read: exit 2 (status-read), no create"
else
    fail "read fails: exit $RC, creates $(creates)"
fi

# --- usage --------------------------------------------------------------------

for args in \
    "--repo o/r --head impl/topic" \
    "--session $S --repo o/r,o/s --head impl/topic" \
    "--session $S --repo o/r --head a..b" \
    "--session $S --repo o/r --head impl/topic --create" \
    "--session $S --repo o/r --head impl/topic --create --plan-slug Topic --plan-doc x.md" \
    "--session $S --repo o/r --head impl/topic --create --plan-slug topic --plan-doc ../x.md" \
    "--session $S --repo o/r --head impl/topic --plan-slug topic" \
    "--session $S --repo o/r --head impl/topic --take-over --take-over"; do
    new_case usage
    # shellcheck disable=SC2086
    run_adopt $args
    if [ "$RC" -eq 64 ] && [ ! -s "$CASE/gh.log" ] && [ ! -s "$CASE/koto.log" ]; then
        pass "usage: [$args]"
    else
        fail "usage: [$args] exit $RC"
    fi
done

# --- record-write-set.sh ------------------------------------------------------

ws_repo() { # ws_repo <name> <origin url or empty>
    WS="$WORK/ws/$1"
    rm -rf "$WS"; mkdir -p "$WS"
    git init -q "$WS"
    [ -n "$2" ] && git -C "$WS" remote add origin "$2"
    return 0
}
run_ws() {
    OUT=$(cd "$WS" && env KOTO_STORE="$CASE" GH_FIX="$CASE" PATH="$BIN:$PATH" bash "$WRITESET" "$@" </dev/null 2>"$CASE/stderr")
    RC=$?
}

for url in https://github.com/o/r https://github.com/o/r.git https://github.com/o/r/ \
           git@github.com:o/r.git ssh://git@github.com/o/r.git https://token@github.com/o/r.git; do
    new_case ws
    ws_repo url "$url"
    run_ws "$S"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "o/r" ] && [ "$(ctx repos)" = "o/r" ]; then
        pass "write set from origin [$url] is o/r"
    else
        fail "write set from [$url]: exit $RC, out [$OUT], repos [$(ctx repos)]"
    fi
done

new_case ws-insteadof
ws_repo insteadof https://github.com/o/r.git
git -C "$WS" config url."$WORK/elsewhere.git".insteadOf https://github.com/o/r.git
run_ws "$S"
[ "$(ctx repos)" = "o/r" ] && pass "the configured URL is read, not its insteadOf rewrite" \
    || fail "insteadOf: repos [$(ctx repos)]"

new_case ws-fallback
ws_repo local "$WORK/some/local/origin.git"
echo 'o/fallback' > "$CASE/repoview.out"
run_ws "$S"
if [ "$RC" -eq 0 ] && [ "$(ctx repos)" = "o/fallback" ]; then
    pass "a non-GitHub origin falls back to gh repo view"
else
    fail "fallback: exit $RC, repos [$(ctx repos)]"
fi

new_case ws-none
ws_repo none ""
echo 1 > "$CASE/repoview.rc"
run_ws "$S"
if [ "$RC" -eq 65 ] && [ -z "$(ctx repos)" ]; then
    pass "no readable owner/repo: exit 65, nothing recorded"
else
    fail "none: exit $RC"
fi

new_case ws-bad
ws_repo bad "$WORK/x.git"
echo 'o/r;rm' > "$CASE/repoview.out"
run_ws "$S"
if [ "$RC" -eq 66 ] && [ -z "$(ctx repos)" ]; then
    pass "an owner/repo outside the pattern: exit 66"
else
    fail "bad: exit $RC"
fi

new_case ws-fixed
ws_repo fixed https://github.com/o/r
printf 'o/other' > "$CASE/ctx/$S/repos"
run_ws "$S"
if [ "$RC" -eq 67 ] && [ "$(ctx repos)" = "o/other" ]; then
    pass "a write set already fixed is never changed (exit 67)"
else
    fail "fixed: exit $RC, repos [$(ctx repos)]"
fi

new_case ws-same
ws_repo same https://github.com/o/r
printf 'o/r' > "$CASE/ctx/$S/repos"
run_ws "$S"
[ "$RC" -eq 0 ] && pass "re-running with the same write set is a no-op" || fail "same: exit $RC"

new_case ws-print
ws_repo print git@github.com:o/r.git
run_ws --print
if [ "$RC" -eq 0 ] && [ "$OUT" = "o/r" ] && [ ! -s "$CASE/koto.log" ]; then
    pass "--print derives the same write set and records nothing"
else
    fail "--print: exit $RC, out [$OUT], koto [$(cat "$CASE/koto.log")]"
fi

new_case ws-usage
ws_repo usage https://github.com/o/r
run_ws 'a b'
[ "$RC" -eq 64 ] && [ ! -s "$CASE/koto.log" ] && pass "record-write-set.sh: an invalid session is a usage error" \
    || fail "ws usage: exit $RC"

# --- the takeover release, everywhere else -------------------------------------

[ -z "$RELEASED_ELSEWHERE" ] && pass "no other answer releases a rule (exits seen:$OTHER_EXITS)" \
    || fail "a rule was released outside exit 6:$RELEASED_ELSEWHERE"
MISSING=""
for want in 0 2 3 4 5; do
    case " $OTHER_EXITS " in *" $want "*) ;; *) MISSING="$MISSING $want" ;; esac
done
[ -z "$MISSING" ] && pass "the no-release check covered exits 0, 2, 3, 4 and 5" \
    || fail "the no-release check never saw exit(s)$MISSING"

# A copy of the plugin with no registry: exit 6 is unchanged and stderr carries
# release's one notice line instead of the rule.
NOREG="$WORK/noreg"
mkdir -p "$NOREG/skills/execute" "$NOREG/scripts/lib"
cp -R "$SCRIPT_DIR" "$NOREG/skills/execute/"
cp "$ROOT/scripts/rule-registry.sh" "$NOREG/scripts/"
cp "$ROOT/scripts/lib/record-store.sh" "$NOREG/scripts/lib/"
new_case no-registry
printf '%s' "$MINE" > "$CASE/ctx/$S/run_id"
echo "[$(owned 7)]" > "$CASE/list.out"; plant 7 "$OTHER"
SAVED_ADOPT=$ADOPT
ADOPT="$NOREG/skills/execute/scripts/adopt-or-create-pr.sh"
run_adopt --session "$S" --repo o/r --head impl/topic --create --plan-slug topic --plan-doc docs/plans/PLAN-topic.md
ADOPT=$SAVED_ADOPT
if [ "$RC" -eq 6 ] && [ -z "$OUT" ] \
    && [ "$(grep -c '^rule-registry: could not release execute/pr-takeover-needs-signal: ' "$CASE/stderr")" -eq 1 ] \
    && ! grep -q '^::shirabe-rule::' "$CASE/stderr"; then
    pass "with the registry unreadable, exit 6 and stdout are unchanged and stderr carries one notice line"
else
    fail "no registry: exit $RC, stdout [$OUT], stderr [$(cat "$CASE/stderr")]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
