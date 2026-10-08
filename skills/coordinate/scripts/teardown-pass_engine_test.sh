#!/usr/bin/env bash
# teardown-pass_engine_test.sh -- a full teardown pass in real koto.
#
# The skeleton template is cut from coordinate.md: teardown,
# teardown_inventory, promote, teardown_handoff, destroy and teardown_confirm
# unchanged, with record and surface as terminal stand-ins. koto, its session
# store and coord-log.sh are real, and so are the inventory, the verdict, the
# pass and the confirm check. niwa, claude, gh and the record's
# record-holding.sh are stand-ins over a stand-in instance (a clone of a local
# origin) and a stand-in Claude Code job (a job directory, a transcript and a
# listing) under a test HOME.
#
# Proves: a durable, merged, handed-off worker reaches destroy with one sealed
# verdict naming its instance, job, transcript, pull request and handoff; the
# pass run with that verdict's key seal archives the transcript, the job's
# state.json, timeline.jsonl and tmp/, and the worker's koto sessions (by
# execution directory, and nothing else), with a manifest whose hashes hold;
# it runs exactly one `niwa destroy --force <name>`, at the workspace root,
# and exactly one `claude rm <job>`, confirms both listings, and leaves the
# transcript where it was; with the row removed, `destroyed` passes
# teardown_confirm to record. A second pass on the same verdict refuses and
# removes nothing. teardown_handoff refuses, and nothing is removed, when the
# pull request isn't merged, when the handoff is missing, on another unit's
# pull request or gone, when the job is still working or in a state not
# known to be finished (a missing state included), when two jobs ran in the
# instance, and when niwa's name for the instance isn't a plain name. The pass refuses a key seal that isn't the verdict's and a
# pull request no longer merged; it reports incomplete when the removal
# fails after the destroy; and teardown_confirm refuses a `destroyed` no pass
# backs.
#
# Needs koto, git and jq; SKIPs (exit 0) without koto.
# Usage: bash skills/coordinate/scripts/teardown-pass_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$HERE/../../../scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass-engine.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
unset XDG_DATA_HOME TEARDOWN_ARCHIVE_DIR TEARDOWN_CLAUDE_HOME TEARDOWN_KOTO_SESSIONS
mkdir -p "$HOME"
cd "$T" || exit 1
git config --file "$HOME/.gitconfig" user.email t@example.invalid
git config --file "$HOME/.gitconfig" user.name t

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
has()  { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing [$3] in [$2]" ;; esac; }

# --- the plugin tree ------------------------------------------------------------------------------

PR="$T/plugin"
S="$PR/skills/coordinate/scripts"
mkdir -p "$S" "$PR/skills/coordinate/koto-templates"
for f in dispatch-common.sh teardown-inventory.sh github-refs.sh teardown-verdict.sh coord-log.sh \
    coord-verdict.sh teardown-handoff.sh teardown-pass.sh; do
    cp "$HERE/$f" "$S/$f"
done
export ST="$T/state"
mkdir -p "$ST"

cat >"$S/record-holding.sh" <<'EOF'
#!/usr/bin/env bash
MODE=""; TOPIC=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) MODE=list; shift ;;
        --read) MODE=read; shift ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --session) shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$MODE" in
    list) cat "$ST/rows.json" ;;
    read) jq -ce --arg t "$TOPIC" '.[] | select(.worker == $t)' "$ST/rows.json" || exit 1 ;;
    *) exit 64 ;;
esac
EOF
BIN="$T/bin"
mkdir -p "$BIN"
# niwa: `list --json` reads the listing; `destroy --force <name>` is logged
# with the directory it ran in, and removes the instance and its entry.
cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list) cat "$ST/niwa.json" ;;
    destroy)
        printf '%s | %s\n' "$*" "$(pwd -P)" >>"$ST/niwa.log"
        [ "$2" = --force ] || exit 64
        p=$(jq -r --arg n "$3" '.[] | select(.name == $n) | .path' "$ST/niwa.json")
        [ -n "$p" ] || { echo "no instance $3" >&2; exit 1; }
        rm -rf "$p"
        jq -c --arg n "$3" '[.[] | select(.name != $n)]' "$ST/niwa.json" >"$ST/n.tmp" && mv "$ST/n.tmp" "$ST/niwa.json" ;;
    *) printf '%s\n' "$*" >>"$ST/niwa.log"; exit 64 ;;
esac
EOF
# claude: `agents --json --all` reads the listing; `rm <id>` is logged and
# removes the job directory and its entry, unless RM_FAILS is set.
cat >"$BIN/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    agents) cat "$ST/agents.json" ;;
    rm)
        printf 'rm %s\n' "$2" >>"$ST/claude.log"
        [ -f "$ST/rm-fails" ] && { echo "cannot remove" >&2; exit 1; }
        rm -rf "$HOME/.claude/jobs/$2"
        jq -c --arg j "$2" '[.[] | select(.id != $j)]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json" ;;
    *) printf '%s\n' "$*" >>"$ST/claude.log"; exit 64 ;;
esac
EOF
# gh: merged pull requests by branch, a pull request's state, a comment, and
# trees from the local origin.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ]; then
    b="" jqf=""
    while [ $# -gt 0 ]; do case "$1" in --head) b=$2; shift ;; --jq) jqf=$2; shift ;; esac; shift; done
    f="$ST/merged-$(printf '%s' "$b" | tr / _).json"
    [ -f "$f" ] || f=/dev/null
    out=$(cat "$f"); [ -n "$out" ] || out='[]'
    if [ -n "$jqf" ]; then printf '%s' "$out" | jq -r "$jqf"; else printf '%s\n' "$out"; fi
    exit 0
fi
if [ "$1 $2" = "pr view" ]; then cat "$ST/pr-$3.json" 2>/dev/null || { echo "HTTP 404" >&2; exit 1; }; exit 0; fi
if [ "$1" = api ]; then
    case "$2" in
        repos/*/issues/comments/*)
            f="$ST/comment-${2##*/}.json"
            [ -f "$f" ] && { cat "$f"; exit 0; }
            echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        repos/*/git/trees/*)
            sha=${2##*/trees/}; sha=${sha%%\?*}
            git --git-dir="$O" ls-tree -r "$sha" |
                jq -R -s '{truncated: false, tree: [split("\n")[] | select(length > 0) | split("\t") as $f | ($f[0] | split(" ")) as $m | {path: $f[1], type: $m[1], sha: $m[2]}]}'
            exit 0 ;;
    esac
fi
exit 0
EOF
chmod +x "$BIN"/* "$S"/*.sh
export PATH="$BIN:$PATH"

W="$T/ws"
mkdir -p "$W/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"

# --- the origin --------------------------------------------------------------------------------

export O="$T/origin.git"
git init -q --bare "$O"
GHURL=https://github.com/acme/widgets
git config --file "$HOME/.gitconfig" "url.$O.insteadOf" "$GHURL"
git config --file "$HOME/.gitconfig" --add "url.$O.insteadOf" "$GHURL.git"
git config --file "$HOME/.gitconfig" protocol.file.allow always
git clone -q "$O" "$T/seed" 2>/dev/null
printf 'a\n' >"$T/seed/a.txt"
git -C "$T/seed" add a.txt && git -C "$T/seed" commit -q -m init && git -C "$T/seed" branch -M main && git -C "$T/seed" push -q origin main
git --git-dir="$O" symbolic-ref HEAD refs/heads/main
MERGE=$(git -C "$T/seed" rev-parse HEAD)

# --- the skeleton template -------------------------------------------------------------------------

SRC="$HERE/../koto-templates/coordinate.md"
UNDER="teardown teardown_inventory promote teardown_handoff destroy teardown_confirm"
ENDS="record surface"
block() {
    awk -v s="  $1:" '
        $0 == s { on = 1; print; next }
        on && /^  [a-z_]+:$/ { exit }
        on && /^---$/ { exit }
        on { print }
    ' "$SRC"
}
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
{
    cat <<'EOF'
---
name: coordinate
version: "1.0"
description: the teardown states, cut from coordinate.md, for teardown-pass_engine_test.sh
initial_state: entry
variables:
  PLUGIN_ROOT:
    description: plugin root
    required: true
states:
  entry:
    accepts:
      go:
        type: enum
        values: [teardown]
        required: true
    transitions:
      - target: teardown
        when:
          go: teardown
EOF
    for st in $UNDER; do block "$st"; echo; done
    for st in $ENDS; do printf '  %s:\n    terminal: true\n\n' "$st"; done
    echo '---'
    for st in entry $UNDER $ENDS; do printf '## %s\nStand-in.\n\n' "$st"; done
} >"$TPL"
koto template compile "$TPL" >/dev/null 2>"$T/compile.err" || { fail "the skeleton compiles" "$(cat "$T/compile.err")"; echo "$PASS passed, $FAIL failed"; exit 1; }
pass "the skeleton cut from coordinate.md compiles"

N=0
start() {
    N=$((N + 1))
    SESS="coord-td-$N"
    (cd "$W" && koto init "$SESS" $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>"$T/init.err") ||
        fail "session $SESS starts" "$(cat "$T/init.err")"
    printf 'w5' >"$T/v"; koto context add "$SESS" teardown_topic --from-file "$T/v" >/dev/null
    tick --with-data '{"go":"teardown"}'
}
tick() { (cd "$W" && koto next "$SESS" --no-cleanup "$@" >"$T/next.json" 2>&1); }
at() { (cd "$W" && koto status "$SESS" 2>/dev/null) | jq -r '.current_state // .state // "gone"'; }
ctx() { koto context get "$SESS" "$1" 2>/dev/null; }

# --- the stand-in worker -----------------------------------------------------------------------------

INST="$T/instances/tsuku+w5"
JOB=4b3597d2
SID=4b3597d2-6184-4a48-ab7f-802b6a2929ce
SLUG=-instances-tsuku-w5
TR="$HOME/.claude/projects/$SLUG/$SID.jsonl"
URL="https://github.com/acme/widgets/pull/600#issuecomment-1001"
KS="$HOME/.koto/sessions"
# fixture [state]: a fresh instance, job, transcript, koto sessions and
# listings for the worker w5, stopped unless a state is given.
fixture() {
    rm -rf "$T/instances" "$HOME/.claude" "$HOME/.local/share/teardown-archive" "$ST"/*.json "$ST"/*.log "$ST/rm-fails" "$KS/wk-"*
    mkdir -p "$INST" "$HOME/.claude/jobs/$JOB/tmp" "$(dirname "$TR")/$SID/subagents" "$KS"
    git clone -q "$GHURL" "$INST/repo"
    printf '{"type":"user","text":"worker transcript"}\n' >"$TR"
    printf '{"agent":"sub"}\n' >"$(dirname "$TR")/$SID/subagents/a.jsonl"
    printf '{"id":"%s","state":"done"}\n' "$JOB" >"$HOME/.claude/jobs/$JOB/state.json"
    printf '{"t":"started"}\n' >"$HOME/.claude/jobs/$JOB/timeline.jsonl"
    printf 'handoff draft\n' >"$HOME/.claude/jobs/$JOB/tmp/draft.md"
    for k in wk-inst:"$INST/repo" wk-tmp:"$HOME/.claude/jobs/$JOB/tmp/run.x" wk-other:"$T/elsewhere"; do
        n=${k%%:*}; d=${k#*:}
        mkdir -p "$KS/$n"
        printf '{"schema_version":1,"workflow":"%s","execution_dir":"%s"}\n{"seq":1}\n' "$n" "$d" >"$KS/$n/koto-$n.state.jsonl"
    done
    printf '[{"name":"tsuku+w5","path":"%s","session_name":"w5-1a2b3c4d"}]\n' "$INST" >"$ST/niwa.json"
    printf '[{"id":"%s","cwd":"%s","sessionId":"%s","name":"w5-1a2b3c4d","state":"%s"}]\n' "$JOB" "$INST" "$SID" "${1:-done}" >"$ST/agents.json"
    printf '[{"worker":"w5","unit":"#591","repo":"acme/widgets","branch":"feat/w5"}]\n' >"$ST/rows.json"
    printf '[{"number":600,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"acme"}}]\n' "$MERGE" >"$ST/merged-feat_w5.json"
    printf '{"state":"MERGED","mergeCommit":{"oid":"%s"}}\n' "$MERGE" >"$ST/pr-600.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/600","body":"what only the worker knew"}\n' >"$ST/comment-1001.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/599","body":"another unit"}\n' >"$ST/comment-1002.json"
    : >"$ST/niwa.log"; : >"$ST/claude.log"
}
stopped() { tick --with-data "{\"teardown\":\"stopped\",\"handoff\":\"${1-$URL}\"}"; }
handover() { (cd "$W" && bash "$S/teardown-handoff.sh" read --session "$SESS" 2>"$T/read.err"); }
agent_pass() { (cd "$W" && bash "$S/teardown-pass.sh" run --session "$SESS" --keyseal "$1" >"$T/pass.out" 2>&1); echo $?; }
archive() { ls -d "$HOME/.local/share/teardown-archive/"*"-w5-$JOB" 2>/dev/null | head -1; }
nothing_removed() {
    eq "$1: no destroy ran" "" "$(cat "$ST/niwa.log")"
    eq "$1: no rm ran" "" "$(cat "$ST/claude.log")"
    [ -d "$INST" ] && [ -d "$HOME/.claude/jobs/$JOB" ] && pass "$1: the instance and the job are still there" || fail "$1: the instance and the job are still there" ""
}

# --- the pass, end to end ---------------------------------------------------------------------------

fixture
start
eq  "the run starts at teardown" teardown "$(at)"
stopped
eq  "a durable, merged, handed-off worker reaches destroy" destroy "$(at)"
V=$(ctx teardown_handoff)
has "the verdict names the instance" "$V" "instance tsuku+w5 $INST"
has "the verdict names the job and its session" "$V" "job $JOB $SID"
has "the verdict names the transcript" "$V" "transcript $TR"
has "the verdict names the merged pull request" "$V" "pr acme/widgets#600 $MERGE"
has "the verdict names the handoff" "$V" "handoff $URL"
OUT=$(handover); RC=$?
eq  "the coordinator's read of the verdict succeeds" 0 "$RC"
KSEAL=$(printf '%s\n' "$OUT" | sed -n 's/^keyseal //p')
case "$KSEAL" in keyseal:*) pass "the read ends with the key seal to hand over" ;; *) fail "the read ends with the key seal to hand over" "$OUT" ;; esac
eq  "a key seal that isn't the verdict's refuses" 1 "$(agent_pass keyseal:1:0000000000000000000000000000000000000000000000000000000000000000)"
nothing_removed "a wrong key seal"
eq  "the agent's pass with the handed key seal is done" 0 "$(agent_pass "$KSEAL")"
has "the pass's last line says done" "$(tail -1 "$T/pass.out")" "teardown-pass: done"
A=$(archive)
[ -n "$A" ] && pass "the archive is under the data home, named by date, topic and job" || fail "the archive is under the data home" "$(ls -R "$HOME/.local" 2>&1)"
for f in "transcript/$SID.jsonl" "transcript/$SID/subagents/a.jsonl" job/state.json job/timeline.jsonl job/tmp/draft.md \
    koto/wk-inst/koto-wk-inst.state.jsonl koto/wk-tmp/koto-wk-tmp.state.jsonl README.md MANIFEST RESULT; do
    [ -f "$A/$f" ] && pass "archived: $f" || fail "archived: $f" "$(cd "$A" 2>/dev/null && find . -type f)"
done
[ -e "$A/koto/wk-other" ] && fail "a koto session run elsewhere is not archived" "" || pass "a koto session run elsewhere is not archived"
[ -e "$A/koto/$SESS" ] && fail "the coordinator's own session is not archived" "" || pass "the coordinator's own session is not archived"
BADSUM=0
while read -r h size rel; do
    if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum <"$A/$rel" | cut -d' ' -f1); else got=$(shasum -a 256 <"$A/$rel" | cut -d' ' -f1); fi
    [ "$got" = "$h" ] && [ "$(wc -c <"$A/$rel" | tr -d ' ')" = "$size" ] || BADSUM=$((BADSUM + 1))
done <"$A/MANIFEST"
eq  "every MANIFEST hash and size holds" 0 "$BADSUM"
eq  "the MANIFEST lists every copied file" 7 "$(wc -l <"$A/MANIFEST" | tr -d ' ')"
eq  "exactly one destroy, of the one instance, at the workspace root" "destroy --force tsuku+w5 | $W" "$(cat "$ST/niwa.log")"
eq  "exactly one rm, of the one job" "rm $JOB" "$(cat "$ST/claude.log")"
[ -e "$INST" ] && fail "the instance is gone" "" || pass "the instance is gone"
[ -e "$HOME/.claude/jobs/$JOB" ] && fail "the job directory is gone" "" || pass "the job directory is gone"
[ -f "$TR" ] && pass "the transcript stays where it was" || fail "the transcript stays where it was" ""
eq  "only the user can read the archive" 700 "$(stat -c %a "$A" 2>/dev/null || stat -f %Lp "$A")"
eq  "nor the archive root the pass created" 700 "$(stat -c %a "$(dirname "$A")" 2>/dev/null || stat -f %Lp "$(dirname "$A")")"
eq  "a second pass on the spent verdict refuses" 1 "$(agent_pass "$KSEAL")"
eq  "and runs no second destroy" 1 "$(wc -l <"$ST/niwa.log" | tr -d ' ')"
eq  "and no second rm" 1 "$(wc -l <"$ST/claude.log" | tr -d ' ')"
printf '[]\n' >"$ST/rows.json"
tick --with-data '{"destroyed":"destroyed"}'
eq  "destroyed passes teardown_confirm to record" record "$(at)"
eq  "leaving the teardown clears teardown_topic" "" "$(ctx teardown_topic)"
has "teardown_confirm says why" "$(ctx coord/teardown_confirm.json)" "the archive is whole"

# --- refusals before anything is removed --------------------------------------------------------------

fixture
printf '[]\n' >"$ST/merged-feat_w5.json"
start
stopped
eq  "an unmerged pull request: teardown_handoff refuses to surface" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "is merged"
nothing_removed "an unmerged pull request"

# A root the user set up keeps its mode, and an owner in another case is
# still the holding's own.
fixture
SHARED_ROOT="$T/shared-archive"
mkdir -p "$SHARED_ROOT" && chmod 755 "$SHARED_ROOT"
printf '[{"number":600,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"ACME"}}]\n' "$MERGE" >"$ST/merged-feat_w5.json"
start
stopped
eq  "an owner login in another case is the holding's own" destroy "$(at)"
KSEAL=$(handover | sed -n 's/^keyseal //p')
eq  "a pass into a root the user set up is done" 0 "$( (cd "$W" && TEARDOWN_ARCHIVE_DIR="$SHARED_ROOT" bash "$S/teardown-pass.sh" run --session "$SESS" --keyseal "$KSEAL" >"$T/pass.out" 2>&1); echo $?)"
eq  "that root keeps its mode" 755 "$(stat -c %a "$SHARED_ROOT" 2>/dev/null || stat -f %Lp "$SHARED_ROOT")"

fixture
printf '[{"number":601,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"someone"}}]\n' "$MERGE" >"$ST/merged-feat_w5.json"
start
stopped
eq  "a merged pull request from a fork's branch of the same name: refused" surface "$(at)"
nothing_removed "a merged pull request from a fork's branch of the same name"
eq  "and teardown_topic is cleared" "" "$(ctx teardown_topic)"

fixture
start
tick --with-data '{"teardown":"stopped"}'
eq  "no handoff link: refused to surface" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "no handoff link"
nothing_removed "no handoff link"

fixture
start
stopped "https://github.com/acme/widgets/pull/599#issuecomment-1002"
eq  "a handoff on another unit's pull request: refused" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "neither a merged pull request of the unit nor its issue"
nothing_removed "a handoff on another unit's pull request"

fixture
start
stopped "https://github.com/acme/widgets/pull/600#issuecomment-9999"
eq  "a handoff comment that doesn't exist: refused" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "doesn't exist"
nothing_removed "a handoff comment that doesn't exist"

fixture working
start
stopped
eq  "a job still working: refused" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "still working"
nothing_removed "a job still working"

fixture
jq -c '. + [.[0] | .id = "9c9c9c9c" | .sessionId = "9c9c9c9c-0000-4000-8000-000000000000"]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
start
stopped
eq  "two jobs in the instance: refused" surface "$(at)"
has "and the reason names both" "$(ctx teardown_handoff)" "$JOB, 9c9c9c9c"
nothing_removed "two jobs in the instance"

# Only a state known to be finished passes: a missing state, or one the
# script doesn't know, is treated as possibly running.
for st in missing waiting; do
    fixture
    if [ "$st" = missing ]; then
        jq -c '[.[] | del(.state)]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
    else
        jq -c --arg s "$st" '[.[] | .state = $s]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
    fi
    start
    stopped
    eq  "a job whose state is $st: refused" surface "$(at)"
    has "and the verdict says why" "$(ctx teardown_handoff)" "isn't known to be finished"
    nothing_removed "a job whose state is $st"
done

# An instance name niwa lists that isn't a plain name never reaches a
# command: the verdict refuses it.
fixture
jq -c '[.[] | .name = "--workspace"]' "$ST/niwa.json" >"$ST/n.tmp" && mv "$ST/n.tmp" "$ST/niwa.json"
start
stopped
eq  "an instance name that isn't a plain name: refused" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "not a plain instance name"
nothing_removed "an instance name that isn't a plain name"

# --- the pass refuses, or stops part way --------------------------------------------------------------

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
printf '{"state":"OPEN","mergeCommit":null}\n' >"$ST/pr-600.json"
eq  "a pull request no longer merged: the pass refuses" 1 "$(agent_pass "$KSEAL")"
has "and says which" "$(tail -1 "$T/pass.out")" "acme/widgets#600 is not merged"
nothing_removed "a pull request no longer merged"
tick --with-data '{"destroyed":"refused"}'
eq  "refused goes to surface" surface "$(at)"

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
printf 'x\n' >>"$INST/repo/a.txt"
eq  "unique material since the inventory: the pass refuses" 1 "$(agent_pass "$KSEAL")"
nothing_removed "unique material since the inventory"

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
jq -c '[.[] | del(.state)]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
eq  "a job whose state went missing since the verdict: the pass refuses" 1 "$(agent_pass "$KSEAL")"
nothing_removed "a job whose state went missing since the verdict"

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
: >"$ST/rm-fails"
eq  "a removal that fails after the destroy is incomplete" 2 "$(agent_pass "$KSEAL")"
has "and names the step" "$(tail -1 "$T/pass.out")" "incomplete at remove"
has "the archive's RESULT says so" "$(cat "$(archive)/RESULT")" "incomplete at remove"
tick --with-data '{"destroyed":"incomplete"}'
eq  "incomplete goes to surface" surface "$(at)"

fixture
start
stopped
tick --with-data '{"destroyed":"destroyed"}'
eq  "a destroyed no pass backs: teardown_confirm sends it to surface" surface "$(at)"
has "and says why" "$(ctx coord/teardown_confirm.json)" "still lists"
nothing_removed "a destroyed no pass backs"

echo
echo "teardown-pass engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
