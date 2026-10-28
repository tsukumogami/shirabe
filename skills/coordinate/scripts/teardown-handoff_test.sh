#!/usr/bin/env bash
# teardown-handoff_test.sh -- the handoff seal's refusals for a stopped unit.
#
# Runs `teardown-handoff.sh --seal` in a plugin tree whose inventory reader
# (teardown-verdict.sh) is a stand-in printing a durable verdict, with the
# koto stand-in (testdata/koto) holding teardown_topic, a coord-log.sh
# stand-in for the seals and the teardown evidence, and stand-ins for
# state-holding.sh, niwa, claude and gh. A durable, merged, handed-off
# worker seals a ready verdict naming its instance, job, transcript, pull
# request, handoff and dispatch id. Each refusal seals `refused` with its
# reason, prints `handoff-refused`, and runs nothing but the listings: a
# pull request merged only from a fork's branch of the same name; no handoff
# link; a handoff on another unit's pull request; a handoff comment that
# doesn't exist; two jobs in the instance; and an instance name that isn't a
# plain name.
#
# The job line follows the job's own state file and the listing's pid, never
# the listing's state, which Claude Code 2.1.309 reports as working for every
# job. A job listed working with no pid or a dead one, whose state file reads
# done, stopped or failed, passes, as does one whose listing state is missing
# or unknown. A live pid refuses whatever the state file says; a state file
# reading working refuses whatever the listing says; so do a state file in an
# unknown state, no state file, and a pid that isn't one.
#
# Removed mode, against a koto home of many unrelated sessions: the seal
# recovers the instance path from the one header for the topic and opens only
# the headers that name the topic's slug, never a symlinked one; with no koto
# session store the path comes from a transcript; only unrelated sessions, or
# two instances for the topic, refuse. With only unrelated sessions, a canary
# header that names the topic's instance through a JSON escape stays
# unparsed, so the refusal shows no unrelated header was parsed, whatever
# read it; the same header, once grep can see the slug, recovers the path.
#
# teardown-pass_engine_test.sh keeps one refusal (an unmerged pull request)
# to prove the refused arm reaches surface in real koto, and drives the
# removed mode end to end.
#
# Usage: bash skills/coordinate/scripts/teardown-handoff_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-handoff-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */teardown-handoff-test.*) rm -rf "$T" ;; esac'

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$2]" ;; esac; }

# --- the plugin tree and its stand-ins --------------------------------------------------------

S="$T/plugin/skills/coordinate/scripts"
BIN="$T/bin"
mkdir -p "$S" "$BIN"
cp "$HERE/teardown-handoff.sh" "$HERE/dispatch-common.sh" "$S/"

# teardown-verdict.sh read: the sealed inventory, durable, for the instance;
# with $ST/inventory-rc, it answers that code (5: the inventory says absent).
cat >"$S/teardown-verdict.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = read ] || exit 64
cat "$ST/inventory"
[ -f "$ST/inventory-rc" ] && exit "$(cat "$ST/inventory-rc")"
exit 0
EOF
# coord-log.sh: a file seal stores the file under ctx/<key> and prints a
# token over it; a token seal is logged and printed back sealed; the
# inventory's capture is a sealed token; the latest entry into teardown and
# the evidence there come from $ST/teardown-ev.
cat >"$S/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
sha() { if command -v sha256sum >/dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
cmd="$1"; shift
A_file="" A_key="" A_token="" A_state="" A_after=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--name|--where) shift 2 ;;
        --key) A_key=$2; shift 2 ;;
        --state) A_state=$2; shift 2 ;;
        --file) A_file=$2; shift 2 ;;
        --token) A_token=$2; shift 2 ;;
        --after) A_after=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$cmd" in
    seal)
        if [ -n "$A_file" ]; then
            cp "$A_file" "$ST/ctx/$A_key"
            printf 'sealed:7:%s\n' "$(sha <"$A_file")"
        else
            printf '%s\n' "$A_token" >>"$ST/tokens"
            printf '%s sealed:8:%064d\n' "$A_token" 0
        fi ;;
    capture) printf 'sealed:6:%064d\n' 0 ;;
    entry) [ "$A_state" = teardown ] || exit 1; echo "4 wait" ;;
    evidence)
        [ "$A_state" = teardown ] && [ "$A_after" = 4 ] || exit 64
        printf '{"seq":5,"timestamp":"t","fields":%s}\n' "$(cat "$ST/teardown-ev")" ;;
    *) exit 64 ;;
esac
EOF
# state-holding.sh --read: the holding's row.
cat >"$S/state-holding.sh" <<'EOF'
#!/usr/bin/env bash
cat "$ST/row.json"
EOF
# niwa list and claude agents read their listings; any other call is logged.
cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] && { cat "$ST/niwa.json"; exit 0; }
printf 'niwa %s\n' "$*" >>"$ST/calls"; exit 64
EOF
cat >"$BIN/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" = agents ] && { cat "$ST/agents.json"; exit 0; }
printf 'claude %s\n' "$*" >>"$ST/calls"; exit 64
EOF
# gh: merged pull requests by branch, and a comment by id.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ]; then cat "$ST/merged.json"; exit 0; fi
case "$1 ${2-}" in
    "api repos/"*/issues/comments/*)
        f="$ST/comment-${2##*/}.json"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
printf 'gh %s\n' "$*" >>"$ST/calls"; exit 64
EOF
chmod +x "$S"/*.sh "$BIN"/*

W="$T/ws"
mkdir -p "$W/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
export KOTO_STORE="$T/koto" KOTO="$HERE/testdata/koto" NIWA="$BIN/niwa" CLAUDE_CLI="$BIN/claude" GH="$BIN/gh"
export TEARDOWN_CLAUDE_HOME="$T/claude" HOME="$T/home"
mkdir -p "$KOTO_STORE/context/coord" "$HOME"

# --- the worker w5 ----------------------------------------------------------------------------

INST="$W/tsuku+w5"
JOB=4b3597d2
SID=4b3597d2-6184-4a48-ab7f-802b6a29
TR="$TEARDOWN_CLAUDE_HOME/projects/$(printf '%s' "$INST" | sed 's/[^A-Za-z0-9]/-/g')/$SID.jsonl"
URL="https://github.com/acme/widgets/pull/600#issuecomment-1001"
MERGE=0123456789abcdef0123456789abcdef01234567
mkdir -p "$(dirname "$TR")"
printf '{"type":"user"}\n' >"$TR"
printf 'w5' >"$KOTO_STORE/context/coord/teardown_topic"
N=0
# fixture: a durable, merged, handed-off w5 whose job is finished the way
# Claude Code 2.1.309 shows it: listed as working with no pid, and its own
# state file reading done. It builds a fresh state directory with no
# removed-mode session store: rfixture exports TEARDOWN_KOTO_SESSIONS after
# calling this, so a case built here never reads the store a removed-mode
# case left behind.
fixture() {
    unset TEARDOWN_KOTO_SESSIONS
    N=$((N + 1))
    export ST="$T/state-$N"
    mkdir -p "$ST/ctx"
    printf 'durable\ninstance %s\ntopic w5\n' "$INST" >"$ST/inventory"
    printf '{"teardown":"stopped","handoff":"%s"}' "$URL" >"$ST/teardown-ev"
    printf '{"worker":"w5","unit":"#591","repo":"acme/widgets","branch":"feat/w5"}\n' >"$ST/row.json"
    printf '[{"name":"tsuku+w5","path":"%s","session_name":"w5-1a2b3c4d","dispatch_id":"dsp-01"}]\n' "$INST" >"$ST/niwa.json"
    printf '[{"id":"%s","cwd":"%s","sessionId":"%s","name":"w5-1a2b3c4d","state":"working"}]\n' "$JOB" "$INST" "$SID" >"$ST/agents.json"
    jobstate done
    printf '[{"number":600,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"acme"}}]\n' "$MERGE" >"$ST/merged.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/600","body":"what only the worker knew"}\n' >"$ST/comment-1001.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/599","body":"another unit"}\n' >"$ST/comment-1002.json"
    : >"$ST/calls"
}
# jobstate <state>: the job's own state file reads that state.
jobstate() {
    mkdir -p "$TEARDOWN_CLAUDE_HOME/jobs/$JOB"
    printf '{"state":"%s","sessionId":"%s"}\n' "$1" "$SID" >"$TEARDOWN_CLAUDE_HOME/jobs/$JOB/state.json"
}
# listed <jq filter>: the job's listing row, changed by the filter.
listed() { jq -c "[.[] | $1]" "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"; }
seal() { (cd "$W" && bash "$S/teardown-handoff.sh" --seal --session coord 2>"$T/seal.err"); }
verdict() { cat "$ST/ctx/teardown_handoff" 2>/dev/null; }
# refused <label> <reason>: the seal refuses with the reason, sealed, running
# nothing beyond the listings and reads.
refused() {
    local out rc
    out=$(seal); rc=$?
    eq  "$1: exit 0" 0 "$rc"
    case "$out" in "handoff-refused sealed:"*) ok "$1: prints handoff-refused" ;; *) bad "$1: prints handoff-refused" "$out $(cat "$T/seal.err")" ;; esac
    eq  "$1: the verdict is refused" refused "$(verdict | sed -n 1p)"
    has "$1: the verdict says why" "$(verdict | sed -n 2p)" "$2"
    eq  "$1: nothing else ran" "" "$(cat "$ST/calls")"
}

# --- ready: the control the refusals are measured against --------------------------------------

fixture
OUT=$(seal); RC=$?
eq  "ready: exit 0" 0 "$RC"
case "$OUT" in "handoff-ready keyseal:7:"*) ok "ready: prints handoff-ready with the verdict's key seal" ;; *) bad "ready: prints handoff-ready with the verdict's key seal" "$OUT $(cat "$T/seal.err")" ;; esac
eq  "ready: the verdict names the topic, instance, job, transcript, pull request, handoff, dispatch id and inventory" \
    "ready|topic w5|instance tsuku+w5 $INST|job $JOB $SID|transcript $TR|pr acme/widgets#600 $MERGE|handoff $URL|dispatch dsp-01|inventory sealed:6:$(printf '%064d' 0)" \
    "$(verdict | tr '\n' '|' | sed 's/|$//')"
eq  "ready: nothing else ran" "" "$(cat "$ST/calls")"

# --- refusals --------------------------------------------------------------------------------

fixture
printf '[{"number":601,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"someone"}}]\n' "$MERGE" >"$ST/merged.json"
refused "a merged pull request from a fork's branch of the same name" "no pull request from feat/w5 in acme/widgets is merged"

fixture
printf '{"teardown":"stopped"}' >"$ST/teardown-ev"
refused "no handoff link" "no handoff link"

fixture
printf '{"teardown":"stopped","handoff":"https://github.com/acme/widgets/pull/599#issuecomment-1002"}' >"$ST/teardown-ev"
refused "a handoff on another unit's pull request" "neither a merged pull request of the unit nor its issue"

fixture
printf '{"teardown":"stopped","handoff":"https://github.com/acme/widgets/pull/600#issuecomment-9999"}' >"$ST/teardown-ev"
refused "a handoff comment that doesn't exist" "doesn't exist"

fixture
jq -c '. + [.[0] | .id = "9c9c9c9c" | .sessionId = "9c9c9c9c-0000-4000-8000-00000000"]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
refused "two jobs in the instance" "$JOB, 9c9c9c9c"

# --- the job line: finished by its state file and its pid (shirabe#1182) -----------------------
#
# The listing's state is activity, not lifecycle: Claude Code 2.1.309 lists
# every job as working, a stopped one included (the ready control above). A
# job passes when its own state file reads done, stopped or failed and the
# listing shows no live pid; a disagreement in the running direction, a live
# pid or a state file reading working, refuses whatever the other source says.
# A live pid is this shell's; a dead one is a reaped child's.
sleep 0 &
DEAD=$!
wait "$DEAD"
# passes <label>: the seal is ready and its verdict carries the job line.
passes() {
    local out rc
    out=$(seal); rc=$?
    eq  "$1: exit 0" 0 "$rc"
    case "$out" in "handoff-ready keyseal:"*) ok "$1: prints handoff-ready" ;; *) bad "$1: prints handoff-ready" "$out $(cat "$T/seal.err")" ;; esac
    has "$1: the verdict carries the job line" "$(verdict | tr '\n' '|')" "|job $JOB $SID|"
    eq  "$1: nothing else ran" "" "$(cat "$ST/calls")"
}

for s in stopped failed; do
    fixture
    jobstate "$s"
    passes "listed working, no pid, a state file reading $s"
done
fixture
listed ".pid = $DEAD"
passes "listed working with a dead pid, a state file reading done"
fixture
listed 'del(.state)'
passes "a listing row with no state, a state file reading done"
fixture
listed '.state = "waiting"'
passes "a listing state the script doesn't know, a state file reading done"

for s in done stopped failed; do
    fixture
    listed ".state = \"done\" | .pid = $$"
    jobstate "$s"
    refused "a live pid, a state file reading $s" "job $JOB is still running (pid $$)"
done
for l in working done; do
    fixture
    listed ".state = \"$l\""
    jobstate working
    refused "a state file reading working, listed $l with no pid" "the state file of job $JOB reads working"
done
fixture
jobstate waiting
refused "a state file in a state the script doesn't know" "reads [waiting], which isn't known to be finished"
fixture
rm -f "$TEARDOWN_CLAUDE_HOME/jobs/$JOB/state.json"
refused "a job with no state file" "job $JOB has no state file"
fixture
listed '.pid = "1234x"'
refused "a pid that isn't one" "which is not a pid"

# An instance name niwa lists that isn't a plain name never reaches a command.
fixture
jq -c '[.[] | .name = "--workspace"]' "$ST/niwa.json" >"$ST/n.tmp" && mv "$ST/n.tmp" "$ST/niwa.json"
refused "an instance name that isn't a plain name" "not a plain instance name"

# --- removed: the instance path from a large koto home ---------------------------------------------
#
# A unit torn down outside the pass: the inventory answers absent, the
# evidence says removed, and niwa and Claude Code list nothing. The instance
# path comes from the one koto session header whose execution_dir sits under
# `<anything>+w5-<8 hex>` directly in the workspace root. The koto home also
# holds 300 unrelated sessions, and a `head` stand-in on PATH logs every
# session file the seal opens, so the test sees that only the headers naming
# the topic's slug are read. The instance names are put together at run time
# from their parts, as in teardown-pass_engine_test.sh.
inst() { printf '%s+w5-%s' "$1" "$2"; }
RINST="$W/$(inst tsuku 5e6f7a8b)"
REAL_HEAD=$(command -v head)
CB="$T/countbin"
mkdir -p "$CB"
cat >"$CB/head" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in "$TEARDOWN_KOTO_SESSIONS"/*) printf '%s\n' "$a" >>"$ST/opened" ;; esac
done
exec "$REAL_HEAD" "$@"
EOF
chmod +x "$CB/head"
export REAL_HEAD
# header <session name> <execution_dir> [extra field]: one koto session file.
header() {
    mkdir -p "$TEARDOWN_KOTO_SESSIONS/$1"
    printf '{"schema_version":1,"workflow":"%s","execution_dir":"%s"%s}\n{"seq":1}\n' "$1" "$2" "${3-}" \
        >"$TEARDOWN_KOTO_SESSIONS/$1/koto-$1.state.jsonl"
}
# unrelated <n>: n sessions of other units, some in other instances under the
# workspace root and some outside it, none naming w5's slug.
unrelated() {
    local i=0 dirs=""
    while [ "$i" -lt "$1" ]; do
        dirs="$dirs $TEARDOWN_KOTO_SESSIONS/other-$i"
        i=$((i + 1))
    done
    # shellcheck disable=SC2086
    mkdir -p $dirs
    i=0
    while [ "$i" -lt "$1" ]; do
        if [ $((i % 2)) = 0 ]; then
            ed="$W/tsuku+other$i-0a0b0c0d/public/repo"
        else
            ed="$T/elsewhere/$i"
        fi
        printf '{"schema_version":1,"workflow":"other-%s","execution_dir":"%s"}\n{"seq":1}\n' "$i" "$ed" \
            >"$TEARDOWN_KOTO_SESSIONS/other-$i/koto-other-$i.state.jsonl"
        i=$((i + 1))
    done
}
# rfixture: the worker w5, removed outside the pass, with its own session store.
rfixture() {
    fixture
    export TEARDOWN_KOTO_SESSIONS="$ST/koto-sessions"
    mkdir -p "$TEARDOWN_KOTO_SESSIONS"
    printf 'absent\ntopic w5\n' >"$ST/inventory"
    printf '5' >"$ST/inventory-rc"
    printf '{"teardown":"removed","handoff":"%s"}' "$URL" >"$ST/teardown-ev"
    printf '[]\n' >"$ST/niwa.json"
    printf '[]\n' >"$ST/agents.json"
    : >"$ST/opened"
}
# cseal: the seal, with the counting head first on PATH; its output in OUT
# and its exit code in RC.
cseal() {
    local saved=$PATH
    export PATH="$CB:$PATH"
    OUT=$(seal)
    RC=$?
    export PATH="$saved"
}
RVERDICT="ready|topic w5|removed yes|instance - $RINST|job -|pr acme/widgets#600 $MERGE|handoff $URL|dispatch -|inventory sealed:6:$(printf '%064d' 0)"

# 300 unrelated sessions, the worker's own, and a decoy that names the slug
# but records a directory outside the workspace root.
rfixture
unrelated 300
header wk-rm "$RINST/public/repo"
header wk-far "$T/far/repo" ",\"note\":\"$(inst x 3c4d5e6f)\""
cseal
eq  "removed, 300 unrelated sessions: exit 0" 0 "$RC"
case "$OUT" in "handoff-ready keyseal:7:"*) ok "removed, 300 unrelated sessions: prints handoff-ready" ;; *) bad "removed, 300 unrelated sessions: prints handoff-ready" "$OUT $(cat "$T/seal.err")" ;; esac
eq  "removed, 300 unrelated sessions: the verdict names the recovered instance path" "$RVERDICT" "$(verdict | tr '\n' '|' | sed 's/|$//')"
eq  "removed, 300 unrelated sessions: only the two headers naming the slug were opened" \
    "$TEARDOWN_KOTO_SESSIONS/wk-far/koto-wk-far.state.jsonl|$TEARDOWN_KOTO_SESSIONS/wk-rm/koto-wk-rm.state.jsonl" \
    "$(sort "$ST/opened" | tr '\n' '|' | sed 's/|$//')"
eq  "removed, 300 unrelated sessions: nothing else ran" "" "$(cat "$ST/calls")"

# A header symlinked into the store is never read, even when it names the slug.
rfixture
unrelated 4
header wk-rm "$RINST/public/repo"
mkdir -p "$TEARDOWN_KOTO_SESSIONS/wk-link"
ln -s "$TEARDOWN_KOTO_SESSIONS/wk-rm/koto-wk-rm.state.jsonl" "$TEARDOWN_KOTO_SESSIONS/wk-link/koto-wk-link.state.jsonl"
cseal
eq  "removed, a symlinked header: the verdict names the instance path" "$RVERDICT" "$(verdict | tr '\n' '|' | sed 's/|$//')"
eq  "removed, a symlinked header: it isn't opened" "$TEARDOWN_KOTO_SESSIONS/wk-rm/koto-wk-rm.state.jsonl" "$(cat "$ST/opened")"

# No koto session store at all: the path comes from a transcript's cwd.
rfixture
# rm, not rmdir: rmdir isn't on run-tests.sh's PATH, and the store it left in
# place passed this case without testing a missing store.
rm -r "$TEARDOWN_KOTO_SESSIONS"
[ -e "$TEARDOWN_KOTO_SESSIONS" ] && bad "removed, no koto session store: the fixture has no store" "$TEARDOWN_KOTO_SESSIONS is still there"
RPD="$TEARDOWN_CLAUDE_HOME/projects/$(printf '%s' "$RINST" | sed 's/[^A-Za-z0-9]/-/g')"
RJOB=9f8e7d6c
RSID="$RJOB-1111-4222-8333-444455556666"
mkdir -p "$RPD"
printf '{"type":"user","timestamp":"2026-10-01T09:00:00.000Z","cwd":"%s","sessionId":"%s"}\n' "$RINST" "$RSID" >"$RPD/$RSID.jsonl"
cseal
eq  "removed, no koto session store: exit 0" 0 "$RC"
eq  "removed, no koto session store: the path and job come from the transcript" \
    "ready|topic w5|removed yes|instance - $RINST|job $RJOB $RSID|transcript $RPD/$RSID.jsonl|pr acme/widgets#600 $MERGE|handoff $URL|dispatch -|inventory sealed:6:$(printf '%064d' 0)" \
    "$(verdict | tr '\n' '|' | sed 's/|$//')"
rm -rf "$RPD"

# Only unrelated sessions and no transcript: no candidate, refused. One of
# them is a canary whose header spells the `+` in w5's instance as a JSON
# unicode escape: jq reads it as a path candidate() accepts, but grep's
# fixed string doesn't match the file, so the prefilter never hands it on. A
# seal that opened the unrelated headers by any means (head, sed, read) and
# parsed them would recover the canary's path and turn ready, so the refusal
# and the verdict's silence on that path hold without the head stand-in.
# The doubled backslash is shell quoting: the file must hold the six-character
# escape, never a plain `+`, or grep would match the canary and the case would
# prove nothing.
CANARY="$W/tsuku\\u002bw5-5e6f7a8b/public/repo"
rfixture
unrelated 20
header canary "$CANARY"
cseal
case "$OUT" in "handoff-refused sealed:"*) ok "removed, only unrelated sessions: prints handoff-refused" ;; *) bad "removed, only unrelated sessions: prints handoff-refused" "$OUT $(cat "$T/seal.err")" ;; esac
has "removed, only unrelated sessions: the verdict says why" "$(verdict | sed -n 2p)" "no instance path for w5 could be recovered"
case "$(verdict)" in
    *"$RINST"*) bad "removed, only unrelated sessions: no header was parsed, the canary's path isn't recovered" "$(verdict)" ;;
    *) ok "removed, only unrelated sessions: no header was parsed, the canary's path isn't recovered" ;;
esac
eq  "removed, only unrelated sessions: no header was opened through head" "" "$(cat "$ST/opened")"

# The canary's control: the same header with the slug also written plainly in
# a later field, so grep hands it on. The seal must recover the instance path
# from the escaped execution_dir; were candidate() to stop accepting it, the
# case above would pass without testing anything.
rfixture
unrelated 4
header canary "$CANARY" ',"note":"+w5-"'
cseal
eq  "removed, the canary's control: a header grep hands on recovers the canary's path" "$RVERDICT" "$(verdict | tr '\n' '|' | sed 's/|$//')"

# Two sessions in two instances for the topic: two candidates, refused.
rfixture
unrelated 20
header wk-rm "$RINST/public/repo"
header wk-rm2 "$W/$(inst other 2b3c4d5e)"
cseal
case "$OUT" in "handoff-refused sealed:"*) ok "removed, two candidates: prints handoff-refused" ;; *) bad "removed, two candidates: prints handoff-refused" "$OUT $(cat "$T/seal.err")" ;; esac
has "removed, two candidates: the verdict names both" "$(verdict | sed -n 2p)" "2 instance paths for w5 were recovered"

# --- ready: the holding read doesn't grow with the entries (shirabe#1315) ---------------------
#
# The holding comes from the real state-holding.sh, reading the record the
# coord session holds: Holdings alone, got directly, and record/ never
# listed, so the same seal on a record with 300 entries makes the same koto
# calls as on one with 3, and reads no entry. The session's log is the run's
# start and its found record, sealed at record_find, so the real reader takes
# the run's facts from it.
echo "== ready: the koto calls don't grow with the entries (shirabe#1315) =="
LOG="$KOTO_STORE/sessions/coord/koto-coord.state.jsonl"
mkdir -p "$(dirname "$LOG")"
{
    printf '{"schema_version":1,"workflow":"coord","template_hash":"feedface","created_at":"2026-09-26T08:00:00.000Z","template_name":"coordinate"}\n'
    jq -nc --arg p "$(cd "$HERE/../../.." && pwd -P)" '{seq: 1, timestamp: "2026-09-26T08:00:00.000Z", type: "workflow_initialized",
        payload: {template_path: "x", variables: {SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-demo.md", DISCIPLINE: "", HOST_REPO: "acme/widgets", PLUGIN_ROOT: $p}}}'
    printf '{"seq":2,"timestamp":"2026-09-26T08:01:00.000Z","type":"transitioned","payload":{"from":"start","to":"record_find","condition_type":"auto"}}\n'
} >"$LOG"
FOUND=$(KOTO_BIN="$KOTO" bash "$HERE/coord-log.sh" seal --session coord --state record_find --token found)
jq -nc --arg v "$FOUND" '{seq: 3, timestamp: "2026-09-26T08:01:00.000Z", type: "variable_captured", payload: {key: "RECORD_FIND", value: $v}}' >>"$LOG"
# th_calls <entries>: the seal's output with the real holding reader, on a
# record holding w5's row and <entries> entries, and its koto calls, kept in
# $T/th.calls.
th_calls() {
    local r="$KOTO_STORE/context/coord/record" i
    fixture
    export KOTO_BIN="$KOTO" DC_RECORD_HOLDING="$HERE/state-holding.sh"
    rm -rf "$r"
    mkdir -p "$r/entries"
    printf '{"scope":{"kind":"roadmap","name":"demo"},"store":"session","written":"2026-09-26T09:00:00Z","pending":false}' >"$r/meta"
    printf '[{"unit":"#591","entry_point":"/shirabe:deliver","mode":"--auto","phase":"executing","dispatch_status":"dispatched","return_path":"message","worker":"w5","repo":"acme/widgets","branch":"feat/w5","verified_head":"","dispatched":"2026-09-26","pull_request":""}]' >"$r/holdings"
    for ((i = 1; i <= $1; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" >"$r/entries/$(printf '%06d' "$i")"
    done
    : >"$KOTO_STORE/calls"
    printf '%s %s' "$(seal)" "$(wc -l <"$KOTO_STORE/calls" | tr -d ' ')"
    cp "$KOTO_STORE/calls" "$T/th.calls"
}
FEW=$(th_calls 3)
MANY=$(th_calls 300)
case "$FEW" in "handoff-ready keyseal:"*) ok "the seal with the real holding reader is ready" ;; *) bad "the seal with the real holding reader is ready" "$FEW $(cat "$T/seal.err")" ;; esac
eq  "the same verdict and koto calls with 3 entries and with 300 (${FEW##* } calls)" "$FEW" "$MANY"
eq  "  ... reading no entry and never listing record/" "0 0" \
    "$(grep -c '^context get [^ ]* record/entries/' "$T/th.calls") $(grep -c '^context list [^ ]* --prefix record/$' "$T/th.calls")"
eq  "  ... and of the record, only Holdings is got, once" "record/holdings" \
    "$(sed -n 's|^context get coord \(record/[a-z-]*\)$|\1|p' "$T/th.calls" | grep -vx record/meta | tr '\n' ' ' | sed 's/ $//')"

printf '\nteardown-handoff: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
