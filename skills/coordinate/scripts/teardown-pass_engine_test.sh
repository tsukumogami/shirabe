#!/usr/bin/env bash
# teardown-pass_engine_test.sh -- a full teardown pass in real koto.
#
# The skeleton template is cut from coordinate.md: teardown,
# teardown_inventory, promote, teardown_handoff, destroy and teardown_confirm
# unchanged, with record and surface as terminal stand-ins. koto, its session
# store and coord-log.sh are real, and so are the inventory, the verdict, the
# pass and the confirm check. niwa, claude, gh and the record's
# state-holding.sh are stand-ins over a stand-in instance (a clone of a local
# origin) and a stand-in Claude Code job (a job directory, a transcript and a
# listing) under a test HOME. state-entry.sh is a stand-in too, so the cost
# capture's post can be counted.
#
# Proves: a durable, merged, handed-off worker reaches destroy with one sealed
# verdict naming its instance, job, transcript, pull request and handoff; the
# pass run with that verdict's key seal archives the instance's Claude Code
# project directory (the transcript and its subagents, in claude-projects/,
# and no transcript/), the job's state.json, timeline.jsonl and tmp/, and the
# worker's koto sessions (by
# execution directory, and nothing else), with a manifest whose hashes hold;
# it runs exactly one `niwa destroy --force <name>`, at the workspace root,
# and exactly one `claude rm <job>`, confirms both listings, and leaves the
# transcript where it was; with the row removed, `destroyed` passes
# teardown_confirm to record. A second pass on the same verdict refuses and
# removes nothing. teardown_handoff refuses to surface, nothing removed and
# teardown_topic cleared, when the pull request isn't merged (the seal's other
# refusals are teardown-handoff_test.sh's). The pass refuses a key seal that
# isn't the verdict's, a pull request no longer merged, unique material
# since the inventory, and a job that since the verdict took a live pid, whose state file
# reads working, or that left the listing (the listing's state alone, which Claude Code
# 2.1.309 reports as working for every job, changes nothing); it
# reports incomplete when the removal fails after the destroy; and
# teardown_confirm refuses a `destroyed` no pass backs. The verdict carries
# niwa's dispatch id (`invalid` outside its shape) and the pass writes it into
# teardown.json, which the MANIFEST lists; the capture (the real
# unit-cost.sh, posting through a state-entry.sh stand-in) posts one `cost`
# entry.
#
# A unit torn down outside the pass (`teardown: removed`, its instance and
# job gone): the inventory seals absent and the run reaches destroy with a
# `removed yes` verdict whose instance path comes from the worker's koto
# session, or from a transcript's cwd when there is none; the pass archives
# the surviving project directory (transcript and subagents) and the koto
# session with
# teardown.json (no dispatch id), posts one `cost` entry, runs no destroy and
# no rm, and teardown_confirm passes it to record, never to surface. With
# two main session transcripts the later first event is the worker's and
# keys the archive; with none the pass archives and posts nothing and still
# confirms. A `stopped` whose instance is gone goes back to teardown with
# teardown_topic kept. `removed` with the instance still listed, a job
# listed at the path, a session for the topic in niwa's listing, or two
# candidate paths ends at surface with nothing removed, and a job listed
# after the verdict makes the pass refuse. (teardown-pass_test.sh feeds the
# pass verdict fields no seal would carry.)
#
# Needs koto, git and jq; SKIPs (exit 0) without koto.
# Usage: bash skills/coordinate/scripts/teardown-pass_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$HERE/../../../scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass-engine.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */teardown-pass-engine.*) rm -rf "$T" ;; esac' EXIT
# Its own HOME and koto home, inside the scratch directory, so suites run
# side by side share no path.
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T" KOTO_SESSIONS_BASE="$T/koto-home"
unset XDG_DATA_HOME TEARDOWN_ARCHIVE_DIR TEARDOWN_CLAUDE_HOME TEARDOWN_KOTO_SESSIONS
# No sweep of removal records as a run ends: the engine's passes are the subject.
export TEARDOWN_SWEEP=""
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
cd "$T" || exit 1
# The real koto runs here, so its session store must be this suite's own:
# before any koto command, the directory it resolves for a session has to be
# under the scratch directory, or nothing runs.
case "$(koto session dir teardown-pass-engine-probe 2>&1)" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory is not under $T; no engine case ran"; exit 1 ;;
esac
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
for f in dispatch-common.sh archive-common.sh teardown-inventory.sh inventory-common.sh github-refs.sh teardown-verdict.sh coord-log.sh \
    coord-verdict.sh teardown-handoff.sh teardown-pass.sh unit-cost.sh; do
    cp "$HERE/$f" "$S/$f"
done
export ST="$T/state"
mkdir -p "$ST"

# state-entry.sh: the cost capture's entry list (empty) and its post, one
# line per entry posted in $ST/cost.log.
cat >"$S/state-entry.sh" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --list "*) echo '[]'; exit 0 ;; esac
kind=""
while [ $# -gt 0 ]; do [ "$1" = --kind ] && kind=$2; shift; done
printf '%s\n' "$kind" >>"$ST/cost.log"
EOF

cat >"$S/state-holding.sh" <<'EOF'
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
SID=4b3597d2-6184-4a48-ab7f-802b6a29
# Claude Code's project directory for the instance: its path, every
# character outside [A-Za-z0-9] made `-`.
SLUG=$(printf '%s' "$INST" | sed 's/[^A-Za-z0-9]/-/g')
TR="$HOME/.claude/projects/$SLUG/$SID.jsonl"
URL="https://github.com/acme/widgets/pull/600#issuecomment-1001"
KS="$HOME/.koto/sessions"
# fixture: a fresh instance, job, transcript, koto sessions and listings for
# the worker w5, stopped the way Claude Code 2.1.309 shows it: its state file
# reads done, and the listing has no pid for it and reports it as working.
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
    printf '[{"name":"tsuku+w5","path":"%s","session_name":"w5-1a2b3c4d","dispatch_id":"dsp-01:7f3a.b"}]\n' "$INST" >"$ST/niwa.json"
    printf '[{"id":"%s","cwd":"%s","sessionId":"%s","name":"w5-1a2b3c4d","state":"working"}]\n' "$JOB" "$INST" "$SID" >"$ST/agents.json"
    printf '[{"worker":"w5","unit":"#591","repo":"acme/widgets","branch":"feat/w5"}]\n' >"$ST/rows.json"
    printf '[{"number":600,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"acme"}}]\n' "$MERGE" >"$ST/merged-feat_w5.json"
    printf '{"state":"MERGED","mergeCommit":{"oid":"%s"}}\n' "$MERGE" >"$ST/pr-600.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/600","body":"what only the worker knew"}\n' >"$ST/comment-1001.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/599","body":"another unit"}\n' >"$ST/comment-1002.json"
    : >"$ST/niwa.log"; : >"$ST/claude.log"; : >"$ST/cost.log"
}
stopped() { tick --with-data "{\"teardown\":\"stopped\",\"handoff\":\"${1-$URL}\"}"; }
handover() { (cd "$W" && bash "$S/teardown-handoff.sh" read --session "$SESS" 2>"$T/read.err"); }
agent_pass() { (cd "$W" && bash "$S/teardown-pass.sh" run --session "$SESS" --keyseal "$1" >"$T/pass.out" 2>&1); echo $?; }
# mode <dir>: its permission string, from ls (stat isn't on the suites' PATH).
mode() { ls -ld "$1" | cut -c1-10; }
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
has "the verdict names niwa's dispatch id" "$V" "dispatch dsp-01:7f3a.b"
case "$V" in *"removed yes"*) fail "a stopped unit's verdict doesn't say removed" "$V" ;; *) pass "a stopped unit's verdict doesn't say removed" ;; esac
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
for f in "claude-projects/$SLUG/$SID.jsonl" "claude-projects/$SLUG/$SID/subagents/a.jsonl" job/state.json job/timeline.jsonl job/tmp/draft.md \
    koto/wk-inst/koto-wk-inst.state.jsonl koto/wk-tmp/koto-wk-tmp.state.jsonl teardown.json README.md MANIFEST MANIFEST.sha256 RESULT; do
    [ -f "$A/$f" ] && pass "archived: $f" || fail "archived: $f" "$(cd "$A" 2>/dev/null && find . -type f)"
done
[ -e "$A/koto/wk-other" ] && fail "a koto session run elsewhere is not archived" "" || pass "a koto session run elsewhere is not archived"
[ -e "$A/transcript" ] && fail "nothing is written to transcript/" "" || pass "nothing is written to transcript/"
has "the README lists the project directory taken" "$(cat "$A/README.md")" "- Project directory taken: $SLUG"
[ -e "$A/koto/$SESS" ] && fail "the coordinator's own session is not archived" "" || pass "the coordinator's own session is not archived"
BADSUM=0
while read -r h size rel; do
    if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum <"$A/$rel" | cut -d' ' -f1); else got=$(shasum -a 256 <"$A/$rel" | cut -d' ' -f1); fi
    [ "$got" = "$h" ] && [ "$(wc -c <"$A/$rel" | tr -d ' ')" = "$size" ] || BADSUM=$((BADSUM + 1))
done <"$A/MANIFEST"
eq  "every MANIFEST hash and size holds" 0 "$BADSUM"
eq  "the MANIFEST lists every copied file and teardown.json" 8 "$(wc -l <"$A/MANIFEST" | tr -d ' ')"
grep -q ' teardown.json$' "$A/MANIFEST" && pass "teardown.json is in the MANIFEST" || fail "teardown.json is in the MANIFEST" "$(cat "$A/MANIFEST")"
eq  "teardown.json records what the pass acted on, with niwa's dispatch id" \
    "w5|tsuku+w5|$INST|$JOB|$SID|false|dsp-01:7f3a.b|null" \
    "$(jq -r '[.topic, .instance.name, .instance.path, .job.id, .job.session, .removed, .niwa.dispatch_id, .niwa.reason] | map(tostring) | join("|")' "$A/teardown.json")"
eq  "the pass posts one cost entry" cost "$(cat "$ST/cost.log")"
eq  "exactly one destroy, of the one instance, at the workspace root" "destroy --force tsuku+w5 | $W" "$(cat "$ST/niwa.log")"
eq  "exactly one rm, of the one job" "rm $JOB" "$(cat "$ST/claude.log")"
[ -e "$INST" ] && fail "the instance is gone" "" || pass "the instance is gone"
[ -e "$HOME/.claude/jobs/$JOB" ] && fail "the job directory is gone" "" || pass "the job directory is gone"
[ -f "$TR" ] && pass "the transcript stays where it was" || fail "the transcript stays where it was" ""
eq  "only the user can read the archive" drwx------ "$(mode "$A")"
eq  "nor the archive root the pass created" drwx------ "$(mode "$(dirname "$A")")"
eq  "a second pass on the spent verdict refuses" 1 "$(agent_pass "$KSEAL")"
eq  "and runs no second destroy" 1 "$(wc -l <"$ST/niwa.log" | tr -d ' ')"
eq  "and no second rm" 1 "$(wc -l <"$ST/claude.log" | tr -d ' ')"
printf '[]\n' >"$ST/rows.json"
tick --with-data '{"destroyed":"destroyed"}'
eq  "destroyed passes teardown_confirm to record" record "$(at)"
eq  "leaving the teardown clears teardown_topic" "" "$(ctx teardown_topic)"
has "teardown_confirm says why" "$(ctx coord/teardown_confirm.json)" "the archive is whole"

# --- refusals before anything is removed --------------------------------------------------------------
#
# One refusal proves the refused arm; teardown-handoff_test.sh holds the rest
# of the seal's refusals.

fixture
printf '[]\n' >"$ST/merged-feat_w5.json"
start
stopped
eq  "an unmerged pull request: teardown_handoff refuses to surface" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "is merged"
nothing_removed "an unmerged pull request"
eq  "and teardown_topic is cleared" "" "$(ctx teardown_topic)"

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
eq  "that root keeps its mode" drwxr-xr-x "$(mode "$SHARED_ROOT")"

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
jq -c --argjson p "$$" '[.[] | .pid = $p]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
eq  "a job that took a live pid since the verdict: the pass refuses" 1 "$(agent_pass "$KSEAL")"
has "and says so" "$(tail -1 "$T/pass.out")" "job $JOB is no longer finished: job $JOB is still running (pid $$)"
nothing_removed "a job that took a live pid since the verdict"

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
printf '{"id":"%s","state":"working"}\n' "$JOB" >"$HOME/.claude/jobs/$JOB/state.json"
eq  "a job whose state file reads working since the verdict: the pass refuses" 1 "$(agent_pass "$KSEAL")"
has "and says so" "$(tail -1 "$T/pass.out")" "the state file of job $JOB reads working"
nothing_removed "a job whose state file reads working since the verdict"

fixture
start
stopped
KSEAL=$(handover | sed -n 's/^keyseal //p')
printf '[]\n' >"$ST/agents.json"
eq  "a job gone from the listing since the verdict: the pass refuses" 1 "$(agent_pass "$KSEAL")"
has "and says so" "$(tail -1 "$T/pass.out")" "no longer the job of"
nothing_removed "a job gone from the listing since the verdict"

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

# An invalid dispatch id is never carried: the verdict says `invalid`, and
# teardown.json names the reason.
fixture
jq -c '[.[] | .dispatch_id = "has space;rm"]' "$ST/niwa.json" >"$ST/n.tmp" && mv "$ST/n.tmp" "$ST/niwa.json"
start
stopped
has "a dispatch id outside its shape is sealed as invalid" "$(ctx teardown_handoff)" "dispatch invalid"
KSEAL=$(handover | sed -n 's/^keyseal //p')
eq  "and the pass is done" 0 "$(agent_pass "$KSEAL")"
eq  "and teardown.json carries no id, with the reason" "null|invalid input" \
    "$(jq -r '"\(.niwa.dispatch_id)|\(.niwa.reason)"' "$(archive)/teardown.json")"

# --- a unit torn down outside the pass: teardown: removed ---------------------------------------
#
# The instance sits directly under the workspace root, named as niwa names
# one for the topic (`<anything>+<slug>-<8 hex>`), and is gone: niwa and
# Claude Code list nothing. What survives is the worker's koto session (its
# execution_dir under the instance) and its transcripts, in the project
# directory Claude Code names for the instance path. The instance names and
# session ids are put together at run time from their parts, so no line here
# reads as a real instance name or session id.
# inst <prefix> <8 hex>: an instance directory name for w5.
inst() { printf '%s+w5-%s' "$1" "$2"; }
RINST="$W/$(inst tsuku 1a2b3c4d)"
pdir() { printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')"; }
RPD=$(pdir "$RINST")
RJOB=9f8e7d6c
RSID="$RJOB-1111-4222-8333-444455556666"
# transcript <session id> <first timestamp> [later timestamp]: a main session
# transcript in the instance's project directory, whose cwd is the instance.
transcript() {
    mkdir -p "$RPD"
    {
        printf '{"type":"summary","summary":"no timestamp here"}\n'
        printf '{"type":"user","timestamp":"%s","cwd":"%s","sessionId":"%s"}\n' "$2" "$RINST" "$1"
        printf '{"type":"assistant","timestamp":"%s","cwd":"%s","message":{"id":"m-%s","usage":{"input_tokens":3,"output_tokens":5}}}\n' "${3:-$2}" "$RINST" "$1"
    } >"$RPD/$1.jsonl"
}
# rfixture: the stand-in worker of fixture, then everything of it removed
# outside the pass, leaving one koto session and one transcript, with its
# subagents, at the removed instance's path.
rfixture() {
    fixture
    rm -rf "$INST" "$HOME/.claude/jobs/$JOB"
    printf '[]\n' >"$ST/niwa.json"
    printf '[]\n' >"$ST/agents.json"
    transcript "$RSID" 2026-10-01T09:00:00.000Z
    mkdir -p "$RPD/$RSID/subagents"
    printf '{"agent":"sub"}\n' >"$RPD/$RSID/subagents/a.jsonl"
    mkdir -p "$KS/wk-rm"
    printf '{"schema_version":1,"workflow":"wk-rm","execution_dir":"%s"}\n{"seq":1}\n' "$RINST/public/repo" >"$KS/wk-rm/koto-wk-rm.state.jsonl"
}
removed() { tick --with-data "{\"teardown\":\"removed\",\"handoff\":\"${1-$URL}\"}"; }
rarchive() { ls -d "$HOME/.local/share/teardown-archive/"*"-w5-$1" 2>/dev/null | head -1; }
# visits_to <state>: the log's entries into a state, one sequence number per line.
visits_to() {
    jq -r --arg s "$1" 'select((.type == "transitioned" or .type == "directed_transition") and .payload.to == $s) | .seq' \
        "$(koto session dir "$SESS")/koto-$SESS.state.jsonl" 2>/dev/null
}
nothing_run() {
    eq "$1: no destroy ran" "" "$(cat "$ST/niwa.log")"
    eq "$1: no rm ran" "" "$(cat "$ST/claude.log")"
}

rfixture
start
removed
eq  "removed, the instance and job gone: the run reaches destroy" destroy "$(at)"
has "the inventory sealed absent" "$(ctx teardown_verdict)" "absent"
V=$(ctx teardown_handoff)
has "the verdict says removed" "$V" "removed yes"
has "the verdict names the recovered instance path, with no name" "$V" "instance - $RINST"
has "the verdict names the worker's session and its job id" "$V" "job $RJOB $RSID"
has "the verdict names the surviving transcript" "$V" "transcript $RPD/$RSID.jsonl"
has "the verdict names the merged pull request" "$V" "pr acme/widgets#600 $MERGE"
has "the verdict names the handoff" "$V" "handoff $URL"
has "the verdict carries no dispatch id" "$V" "dispatch -"
KSEAL=$(handover | sed -n 's/^keyseal //p')
case "$KSEAL" in keyseal:*) pass "the coordinator's read of a removed verdict succeeds" ;; *) fail "the coordinator's read of a removed verdict succeeds" "$(cat "$T/read.err")" ;; esac
eq  "the removed pass is done" 0 "$(agent_pass "$KSEAL")"
has "its last line says done" "$(tail -1 "$T/pass.out")" "teardown-pass: done"
A=$(rarchive "$RJOB")
[ -n "$A" ] && pass "the archive is keyed by the session's job id" || fail "the archive is keyed by the session's job id" "$(ls -R "$HOME/.local/share" 2>&1)"
for f in "claude-projects/${RPD##*/}/$RSID.jsonl" "claude-projects/${RPD##*/}/$RSID/subagents/a.jsonl" koto/wk-rm/koto-wk-rm.state.jsonl teardown.json README.md MANIFEST MANIFEST.sha256 RESULT unit-cost.json; do
    [ -f "$A/$f" ] && pass "removed, archived: $f" || fail "removed, archived: $f" "$(cd "$A" 2>/dev/null && find . -type f)"
done
[ -e "$A/job" ] && fail "removed: no job files are archived (the job is gone)" "" || pass "removed: no job files are archived (the job is gone)"
eq  "removed: the MANIFEST lists the transcript, its subagent, the koto session and teardown.json" 4 "$(wc -l <"$A/MANIFEST" | tr -d ' ')"
eq  "removed: teardown.json records the removed unit, with no dispatch id" \
    "w5|null|$RINST|$RJOB|$RSID|true|null|no source" \
    "$(jq -r '[.topic, .instance.name, .instance.path, .job.id, .job.session, .removed, .niwa.dispatch_id, .niwa.reason] | map(tostring) | join("|")' "$A/teardown.json")"
eq  "removed: the pass posts one cost entry" cost "$(cat "$ST/cost.log")"
eq  "removed: the entry reads the surviving worker's tokens and niwa's missing dispatch id" "1 5|null|no source" \
    "$(jq -r '"\(.tokens.worker.messages) \(.tokens.worker.output)|\(."niwa.dispatch.id")|\([.missing[] | select(.figure == "niwa.dispatch.id") | .reason] | join(","))"' "$A/unit-cost.json")"
nothing_run "removed"
printf '[]\n' >"$ST/rows.json"
tick --with-data '{"destroyed":"destroyed"}'
eq  "removed: destroyed passes teardown_confirm to record" record "$(at)"
has "and teardown_confirm says the archive is whole" "$(ctx coord/teardown_confirm.json)" "the archive is whole"
eq  "and teardown_topic is cleared" "" "$(ctx teardown_topic)"
eq  "a removed unit never reaches surface" "" "$(visits_to surface)"

# No session survived: nothing to archive and nothing to post.
rfixture
rm -rf "$RPD"
start
removed
eq  "removed with no surviving session: the run reaches destroy" destroy "$(at)"
has "the verdict says job -" "$(ctx teardown_handoff)" "job -"
KSEAL=$(handover | sed -n 's/^keyseal //p')
eq  "the pass is done" 0 "$(agent_pass "$KSEAL")"
has "its last line says done" "$(tail -1 "$T/pass.out")" "teardown-pass: done"
eq  "no archive is made" "" "$(ls "$HOME/.local/share/teardown-archive" 2>/dev/null)"
eq  "no cost entry is posted" "" "$(cat "$ST/cost.log")"
nothing_run "no surviving session"
printf '[]\n' >"$ST/rows.json"
tick --with-data '{"destroyed":"destroyed"}'
eq  "and teardown_confirm passes it to record" record "$(at)"
has "saying no session survived" "$(ctx coord/teardown_confirm.json)" "no session of it survived"

# stopped, but the instance is already gone: back to teardown, the topic kept;
# then removed takes the removed route.
rfixture
start
stopped
eq  "stopped with the instance gone goes back to teardown" teardown "$(at)"
eq  "keeping teardown_topic" w5 "$(ctx teardown_topic)"
has "with the inventory sealed absent" "$(ctx teardown_verdict)" "absent"
nothing_run "stopped with the instance gone"
removed
eq  "removed after that reaches destroy" destroy "$(at)"

# A removed that isn't: the instance still listed, a job still listed, or two
# instance paths to choose from. Each goes to surface and nothing is removed.
fixture
start
removed
eq  "removed with the instance still listed: surface" surface "$(at)"
has "and the verdict says it wasn't removed" "$(ctx teardown_handoff)" "was not removed"
nothing_removed "removed with the instance still listed"

rfixture
printf '[{"id":"%s","cwd":"%s","sessionId":"%s","name":"w5-1a2b3c4d","state":"done"}]\n' "$RJOB" "$RINST" "$RSID" >"$ST/agents.json"
start
removed
eq  "removed with a job still listed at the instance path: surface" surface "$(at)"
has "and the verdict says why" "$(ctx teardown_handoff)" "Claude Code lists job $RJOB"
nothing_run "removed with a job still listed"

rfixture
printf '[{"name":"other","path":"%s","session_name":"w5-9f9f9f9f"}]\n' "$T/elsewhere" >"$ST/niwa.json"
start
removed
eq  "removed with niwa listing an instance for the topic: surface" surface "$(at)"
nothing_run "removed with niwa listing a session for the topic"

rfixture
mkdir -p "$KS/wk-rm2"
printf '{"schema_version":1,"workflow":"wk-rm2","execution_dir":"%s"}\n{"seq":1}\n' "$W/$(inst other 2b3c4d5e)" >"$KS/wk-rm2/koto-wk-rm2.state.jsonl"
start
removed
eq  "removed with two candidate instance paths: surface" surface "$(at)"
has "and the verdict names both" "$(ctx teardown_handoff)" "2 instance paths"
nothing_run "removed with two candidate instance paths"
rm -rf "$KS/wk-rm2"

# A koto session recorded outside the workspace root is no candidate.
rfixture
mkdir -p "$KS/wk-far"
printf '{"schema_version":1,"workflow":"wk-far","execution_dir":"%s"}\n{"seq":1}\n' "$T/far/$(inst x 3c4d5e6f)/repo" >"$KS/wk-far/koto-wk-far.state.jsonl"
start
removed
eq  "a candidate outside the workspace root is ignored" destroy "$(at)"
has "the path is the one under the root" "$(ctx teardown_handoff)" "instance - $RINST"
rm -rf "$KS/wk-far"

# No koto session: the path comes from a transcript's cwd.
rfixture
rm -rf "$KS/wk-rm"
start
removed
eq  "removed with no koto session: the run reaches destroy" destroy "$(at)"
has "the path comes from the transcript's cwd" "$(ctx teardown_handoff)" "instance - $RINST"

# Two main session transcripts: the one whose first event is later is the
# worker's, even when the other's last event is later still.
rfixture
RJOB2=5a4b3c2d
RSID2="$RJOB2-aaaa-4bbb-8ccc-dddddddddddd"
transcript "$RSID" 2026-10-01T09:00:00.000Z 2026-10-03T09:00:00.000Z
transcript "$RSID2" 2026-10-02T09:00:00.000Z
start
removed
eq  "two transcripts: the run reaches destroy" destroy "$(at)"
has "the later first event is the worker's session" "$(ctx teardown_handoff)" "job 5a4b3c2d $RSID2"
KSEAL=$(handover | sed -n 's/^keyseal //p')
eq  "the pass is done" 0 "$(agent_pass "$KSEAL")"
[ -n "$(rarchive 5a4b3c2d)" ] && pass "the archive is keyed by the later session" || fail "the archive is keyed by the later session" "$(ls "$HOME/.local/share/teardown-archive" 2>&1)"
eq  "and only by it" "" "$(rarchive "$RJOB")"

# Two first events in the same second, one with a fraction: the fractional
# one is later, though compared as raw text `.1Z` sorts before `Z`.
rfixture
transcript "$RSID" 2026-10-02T09:00:05Z
transcript "$RSID2" 2026-10-02T09:00:05.1Z
start
removed
eq  "same second: the run reaches destroy" destroy "$(at)"
has "the fractional first event is the later one" "$(ctx teardown_handoff)" "job $RJOB2 $RSID2"

# The pass re-checks absence: a job that appears at the path after the
# verdict refuses, and nothing is archived as done.
rfixture
start
removed
KSEAL=$(handover | sed -n 's/^keyseal //p')
printf '[{"id":"%s","cwd":"%s","sessionId":"%s","state":"working"}]\n' "$RJOB" "$RINST" "$RSID" >"$ST/agents.json"
eq  "a job listed at the path since the verdict: the removed pass refuses" 1 "$(agent_pass "$KSEAL")"
has "and says why" "$(tail -1 "$T/pass.out")" "claude agents lists a job"
nothing_run "a job listed since the verdict"

echo
echo "teardown-pass engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
