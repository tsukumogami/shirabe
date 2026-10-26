#!/usr/bin/env bash
# publish-scoping-pr_test.sh -- /scope's publish step against a stub gh and a
# local bare origin.
#
# Usage: bash skills/scope/scripts/publish-scoping-pr_test.sh
#
# Every case clones a fresh bare `origin`, commits a PLAN on a topic branch, and runs the script with testdata/gh-stateful-stub.sh as
# `gh`. The stub logs every call, so each case asserts the exact GitHub writes
# (`pr create`, `pr edit`) and, through `git ls-remote`, whether anything was
# pushed. A koto stand-in records the context keys the script writes with
# --session.
#
# The last case greps skills/scope/ for the flags a publish must never use: a
# force push in any spelling or a `+` refspec, a merge or review call, and
# --admin or --auto on a gh call.
#
# Needs bash, git and jq; the coordinated-body case also needs shirabe and is
# skipped with a message without it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
S="$HERE/publish-scoping-pr.sh"
STUB="$HERE/testdata/gh-stateful-stub.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/publish-test.XXXXXX")" || exit 1
T="$(cd -P "$T" && pwd -P)" || exit 1
trap 'case "$T" in */publish-test.*) rm -rf "$T" ;; esac' EXIT
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

SHIM="$T/shim"
STORE="$T/store"
mkdir -p "$SHIM" "$STORE"
export STORE
cp "$STUB" "$SHIM/gh"
cat >"$SHIM/koto" <<'KOTO'
#!/usr/bin/env bash
[ "$1" = context ] || exit 2
# KOTO_FAIL_KEY makes every call on that key fail the way an unreadable store does.
[ -n "${KOTO_FAIL_KEY:-}" ] && [ "${4:-}" = "$KOTO_FAIL_KEY" ] && exit 3
d="$STORE/$3"
case "$2" in
    add) mkdir -p "$d"; cat >"$d/$4" ;;
    remove) rm -f "$d/$4" ;;
    exists) [ -f "$d/$4" ] ;;
    get) cat "$d/$4" 2>/dev/null || exit 1 ;;
    # list <s> --prefix <p>: the keys under <p>, as a JSON array (the index
    # read owned-pr.sh makes).
    list) p=""; [ "${4:-}" = --prefix ] && p=${5:-}
          (cd "$d" 2>/dev/null && find . -type f | sed 's#^\./##' | grep "^$p") \
              | jq -Rsc 'split("\n") | map(select(length > 0))' ;;
    *) exit 2 ;;
esac
KOTO
chmod +x "$SHIM/gh" "$SHIM/koto"
# The PRs' index sessions sit at a shared address of this suite's own, never
# the real /tmp/shirabe-run-record.
export SHIRABE_RUN_RECORD_TEST_ROOT="$T/shared-record"

N=0
R=""; O=""; GHF=""
# setup [mode] [branch] -- a bare origin with main, a clone on the topic branch
# holding a PLAN of that mode. Sets R, O, GHF. The repository declares
# `## PR Workflow Content: include`, so the body carries the run's record as it
# always has; with CONTENT=omit it declares nothing, the default.
setup() {
    local mode="${1:-single-pr}" branch="${2:-docs/topic}"
    N=$((N + 1))
    O="$T/origin$N.git"; R="$T/work$N"; GHF="$T/gh$N"
    mkdir -p "$GHF"; : >"$GHF/calls"; printf '[]' >"$GHF/prs.json"
    # Each case's PRs start with no index entry.
    rm -rf "$SHIRABE_RUN_RECORD_TEST_ROOT" "$STORE"/pr.*
    git init -q --bare -b main "$O"
    git init -q -b main "$R"
    printf '# repo\n' >"$R/README.md"
    if [ "${CONTENT:-include}" = include ]; then
        printf '# repo\n\n## PR Workflow Content: include\n' >"$R/CLAUDE.md"
    else
        printf '# repo\n' >"$R/CLAUDE.md"
    fi
    git -C "$R" add README.md CLAUDE.md && git -C "$R" commit -q -m init
    git -C "$R" remote add origin "$O"
    git -C "$R" push -q -u origin main
    [ "$branch" = main ] || git -C "$R" checkout -q -b "$branch"
    mkdir -p "$R/docs/plans"
    cat >"$R/docs/plans/PLAN-topic.md" <<EOF
---
schema: plan/v1
status: Active
execution_mode: $mode
---

# PLAN: topic

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#31: feat: one](#issue-31) | None | simple |
| [#32: feat: two](#issue-32) | [#31](#issue-31) | simple |
EOF
    git -C "$R" add docs && git -C "$R" commit -q -m "docs: scope topic"
}

seed_pr() { # seed_pr <url> <cross> <author> <base> <intent>
    jq --arg u "$1" --argjson c "$2" --arg a "$3" --arg b "$4" --arg i "$5" \
       '. + [{url: $u, state: "OPEN", isCrossRepository: $c, author: {login: $a},
              baseRefName: $b, headRefName: "docs/topic", body: ("intent=" + $i + "\n"), isDraft: true}]' \
       "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
}

OUT=""; RC=0
# run <args...> -- from inside R. A --session names a session scope-open.sh
# opened, so it carries a run_id unless the case already wrote one (or set
# NO_RUN_ID=1 to test a session without one).
run() {
    local prev="" a
    for a in "$@"; do
        if [ "$prev" = --session ] && [ -z "${NO_RUN_ID:-}" ] && [ ! -f "$STORE/$a/run_id" ]; then
            mkdir -p "$STORE/$a"
            printf '%s' 00112233445566778899aabbccddeeff >"$STORE/$a/run_id"
        fi
        prev="$a"
    done
    OUT=$(cd "$R" && PATH="$SHIM:$PATH" GHF="$GHF" bash "$S" "$@" 2>"$T/err")
    RC=$?
}
calls() { grep -c "^pr $1" "$GHF/calls" 2>/dev/null | tr -d ' '; }
remote_sha() { git -C "$R" ls-remote origin "refs/heads/$1" | awk '{print $1}'; }
line() { sed -n "/^$1=/{s///p;q;}" <<<"$OUT"; }

echo "== no PR on the branch =="
setup single-pr
run --topic topic --exit full-run --intent continue --session s-new
eq "exit 0" "0" "$RC"
eq "one pr create" "1" "$(calls create)"
if grep -q '^pr create .*--draft' "$GHF/calls"; then ok "a single-pr full-run opens a draft"; else bad "a single-pr full-run opens a draft" "$(cat "$GHF/calls")"; fi
if grep -q "^pr create .*--head docs/topic --base main --title .*topic.* --body-file " "$GHF/calls"; then
    ok "the create names head, base, a title with the slug, and a body file"
else
    bad "the create names head, base, a title with the slug, and a body file" "$(cat "$GHF/calls")"
fi
eq "pr= names the created PR" "https://github.com/acme/widgets/pull/100" "$(line pr)"
eq "the branch was pushed: origin equals HEAD" "$(git -C "$R" rev-parse HEAD)" "$(remote_sha docs/topic)"
if [ -f "$STORE/s-new/publish_step" ]; then bad "--session: no publish_step on success"; else ok "--session: no publish_step on success"; fi
eq "--session: the publish records published_intent" "continue" "$(cat "$STORE/s-new/published_intent" 2>/dev/null)"
BODY=$(jq -r '.[0].body' "$GHF/prs.json")
case "$BODY" in *"intent=continue"*) ok "the body records intent=continue" ;; *) bad "the body records intent=continue" "$BODY" ;; esac
case "$BODY" in *"docs/plans/PLAN-topic.md"*"#31"*) ok "the body lists the PLAN and its work items" ;; *) bad "the body lists the PLAN and its work items" "$BODY" ;; esac

echo "== the default: no record lines, no PLAN pointer =="
CONTENT=omit setup single-pr
run --topic topic --exit full-run --intent continue --session s-omit
eq "default: exit 0" "0" "$RC"
BODY=$(jq -r '.[0].body' "$GHF/prs.json")
if grep -Eq '^(topic|exit|outcome|intent|mode)=' <<<"$BODY"; then
    bad "default: the body carries no topic=/exit=/outcome=/intent=/mode= line" "$BODY"
else
    ok "default: the body carries no topic=/exit=/outcome=/intent=/mode= line"
fi
case "$BODY" in *"PLAN-topic"*) bad "default: the body names no PLAN file" "$BODY" ;; *) ok "default: the body names no PLAN file" ;; esac
case "$BODY" in *"/scope"*) bad "default: the body names no skill" "$BODY" ;; *) ok "default: the body names no skill" ;; esac
case "$BODY" in "The scoping documents for topic."*"#31"*"#32"*) ok "default: a plain sentence and the work items" ;; *) bad "default: a plain sentence and the work items" "$BODY" ;; esac
if grep -q -- '--title docs: add the topic scoping documents --body-file' "$GHF/calls"; then
    ok "default: the title names no skill and no exit value"
else
    bad "default: the title names no skill and no exit value" "$(grep '^pr create' "$GHF/calls")"
fi
eq "default: the session still records published_intent" "continue" "$(cat "$STORE/s-omit/published_intent" 2>/dev/null)"

echo "== a second run after a successful one =="
BEFORE=$(remote_sha docs/topic)
run --topic topic --exit full-run --intent continue --session s-new
eq "second run: exit 0" "0" "$RC"
eq "second run: still one pr create" "1" "$(calls create)"
eq "second run: no pr edit (published_intent already continue)" "0" "$(calls edit)"
eq "second run: no new push" "$BEFORE" "$(remote_sha docs/topic)"
eq "second run: the same PR" "https://github.com/acme/widgets/pull/100" "$(line pr)"

echo "== the rewrite keys on the session, never on the body =="
# The body says intent=continue, but this session last published stop: the
# session decides, so the body is rewritten.
printf 'stop' >"$STORE/s-new/published_intent"
run --topic topic --exit full-run --intent continue --session s-new
eq "published_intent stop, --intent continue: one pr edit" "1" "$(calls edit)"
eq "published_intent stop, --intent continue: the key now says continue" "continue" "$(cat "$STORE/s-new/published_intent" 2>/dev/null)"
# The body is edited to say stop by hand; the session says continue, so the
# run leaves the body alone. The line is text for people, not run state.
jq '.[0].body = "intent=stop\n"' "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
run --topic topic --exit full-run --intent continue --session s-new
eq "a hand-edited intent= line: no pr edit (the session already says continue)" "1" "$(calls edit)"
# No session at all (a hand run): there is no run state to compare against,
# so the reused PR's body is left as it is, whatever its intent= line says.
run --topic topic --exit full-run --intent continue
eq "no --session: the body is left alone" "1" "$(calls edit)"
eq "no --session: exit 0" "0" "$RC"
# A session without the key (a new run republishing) has published nothing
# yet, so it rewrites.
run --topic topic --exit full-run --intent continue --session s-fresh
eq "a session with no published_intent: the body is rewritten" "2" "$(calls edit)"
eq "a session with no published_intent: the key is recorded" "continue" "$(cat "$STORE/s-fresh/published_intent" 2>/dev/null)"
export KOTO_FAIL_KEY=published_intent
run --topic topic --exit full-run --intent continue --session s-new
unset KOTO_FAIL_KEY
eq "an unreadable published_intent: scope:pr-create" "scope:pr-create" "$(line step)"
eq "an unreadable published_intent: exit 11" "11" "$RC"
eq "an unreadable published_intent: no pr edit" "2" "$(calls edit)"

echo "== a successful publish consumes the prior-run facts =="
setup single-pr
mkdir -p "$STORE/s-prior/work"
printf 'step: scope:push\nexit: full-run\nintent: continue\n' >"$STORE/s-prior/work/prior-run.md"
run --topic topic --exit full-run --intent continue --session s-prior
eq "prior-run: exit 0" "0" "$RC"
if [ -f "$STORE/s-prior/work/prior-run.md" ]; then
    bad "a successful publish removes work/prior-run.md"
else
    ok "a successful publish removes work/prior-run.md"
fi
printf 'step: scope:push\n' >"$STORE/s-prior/work/prior-run.md"
run --topic topic --verify --expect-intent continue --session s-prior
eq "prior-run: verify exits 0" "0" "$RC"
if [ -f "$STORE/s-prior/work/prior-run.md" ]; then
    ok "--verify leaves work/prior-run.md alone (no context write)"
else
    bad "--verify leaves work/prior-run.md alone (no context write)"
fi

echo "== one owned PR already open =="
setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main continue
run --topic topic --exit full-run --intent continue
eq "reused: no pr create" "0" "$(calls create)"
eq "reused: URL printed" "https://github.com/acme/widgets/pull/7" "$(line pr)"

echo "== foreign-only branches get a fresh PR =="
for kind in cross author base; do
    setup single-pr
    case "$kind" in
        cross)  seed_pr "https://github.com/fork/widgets/pull/9" true me main continue ;;
        author) seed_pr "https://github.com/acme/widgets/pull/9" false someone main continue ;;
        base)   seed_pr "https://github.com/acme/widgets/pull/9" false me release continue ;;
    esac
    run --topic topic --exit full-run --intent continue
    eq "$kind-only: one pr create" "1" "$(calls create)"
    case "$OUT" in *pull/9*) bad "$kind-only: the foreign URL is never printed" "$OUT" ;; *) ok "$kind-only: the foreign URL is never printed" ;; esac
done

echo "== several owned PRs =="
setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main continue
seed_pr "https://github.com/acme/widgets/pull/8" false me main continue
seed_pr "https://github.com/fork/widgets/pull/9" true me main continue
run --topic topic --exit full-run --intent continue --session s-several
eq "several: scope:pr-create" "scope:pr-create" "$(line step)"
eq "several: exit 11" "11" "$RC"
eq "several: no pr create" "0" "$(calls create)"
eq "several: no pr edit" "0" "$(calls edit)"
eq "several: publish_step recorded" "scope:pr-create" "$(cat "$STORE/s-several/publish_step" 2>/dev/null)"

echo "== the run's index entry =="
MINE=0123456789abcdef0123456789abcdef
FOREIGN=fedcba9876543210fedcba9876543210
# mark <url> <id> -- an index entry naming <id> for that seeded PR, at the
# shared address, as scripts/run-trail.sh index lays one out.
mark() {
    local n="${1##*/}"
    mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/acme" "$STORE/pr.acme.widgets.$n/run"
    printf '{"workspace":"/w","session":"execute-topic","session_id":"sid-1","mode":"single-pr","topic":"topic","written_at":"2026-01-01T00:00:00Z"}' \
        >"$STORE/pr.acme.widgets.$n/run/$2"
}

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main continue
mark "https://github.com/acme/widgets/pull/7" "$FOREIGN"
mkdir -p "$STORE/s-foreign"; printf '%s' "$MINE" >"$STORE/s-foreign/run_id"
run --topic topic --exit full-run --intent continue --session s-foreign
eq "another run's PR: scope:pr-create" "scope:pr-create" "$(line step)"
eq "another run's PR: no pr create" "0" "$(calls create)"
eq "another run's PR: no pr edit" "0" "$(calls edit)"

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main stop
mark "https://github.com/acme/widgets/pull/7" "$MINE"
mkdir -p "$STORE/s-carry"; printf '%s' "$MINE" >"$STORE/s-carry/run_id"
run --topic topic --exit full-run --intent continue --session s-carry
BODY7=$(jq -r '.[] | select(.url == "https://github.com/acme/widgets/pull/7") | .body' "$GHF/prs.json")
eq "the intent rewrite: one pr edit" "1" "$(calls edit)"
case "$BODY7" in
    *"intent=continue"*) case "$BODY7" in
        *"$MINE"*|*'shirabe''-run'*) bad "the intent rewrite carries nothing of the run" "$BODY7" ;;
        *) ok "the intent rewrite is the template alone, nothing of the run in it" ;;
        esac ;;
    *) bad "the intent rewrite is the template" "$BODY7" ;;
esac

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main continue
run --topic topic --exit full-run --intent continue --session s-reuse
eq "an unmarked /scope PR is reused on the fallback" "https://github.com/acme/widgets/pull/7" "$(line pr)"
case "$(jq -r '.[0].body' "$GHF/prs.json")" in
    *shirabe-run*) bad "/scope stamps no marker on its PR" "$(jq -r '.[0].body' "$GHF/prs.json")" ;;
    *) ok "/scope stamps no marker on its PR" ;;
esac

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main continue
NO_RUN_ID=1 run --topic topic --exit full-run --intent continue --session s-noid
eq "a session with no run_id: exit 66, nothing published" "66" "$RC"
if [ -f "$STORE/s-noid/run_id" ]; then bad "publish mints no run_id" "$(cat "$STORE/s-noid/run_id")"; else ok "publish mints no run_id"; fi
eq "a session with no run_id: nothing created or edited" "0" "$(( $(calls create) + $(calls edit) ))"

echo "== refusals before any push =="
setup single-pr
git -C "$R" checkout -q --detach
run --topic topic --exit full-run --intent continue --session s-detached
eq "detached HEAD: scope:push" "scope:push" "$(line step)"
eq "detached HEAD: exit 10" "10" "$RC"
eq "detached HEAD: nothing pushed" "" "$(remote_sha docs/topic)"
eq "detached HEAD: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"
eq "detached HEAD: publish_step recorded" "scope:push" "$(cat "$STORE/s-detached/publish_step" 2>/dev/null)"

setup single-pr main
run --topic topic --exit full-run --intent continue
eq "the default branch: scope:push" "scope:push" "$(line step)"
eq "the default branch: origin's main unchanged" "$(git -C "$R" rev-parse HEAD~1)" "$(remote_sha main)"
eq "the default branch: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"

setup single-pr
git -C "$R" remote remove origin
run --topic topic --exit full-run --intent continue
eq "no origin: scope:push" "scope:push" "$(line step)"
eq "no origin: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"

setup single-pr
rm "$R/docs/plans/PLAN-topic.md"; git -C "$R" commit -q -am "drop plan"
run --topic topic --exit full-run --intent continue
eq "a full-run with no PLAN: scope:push, the mode is never guessed" "scope:push" "$(line step)"

echo "== a failing pr create =="
setup single-pr
echo 1 >"$GHF/pr-create.rc"
run --topic topic --exit full-run --intent continue --session s-createfail
eq "failing create: scope:pr-create" "scope:pr-create" "$(line step)"
eq "failing create: exit 11" "11" "$RC"
eq "failing create: the branch was pushed first" "$(git -C "$R" rev-parse HEAD)" "$(remote_sha docs/topic)"
eq "failing create: publish_step recorded" "scope:pr-create" "$(cat "$STORE/s-createfail/publish_step" 2>/dev/null)"

echo "== draft or ready, by mode and exit =="
setup multi-pr
run --topic topic --exit full-run --intent stop
if grep '^pr create' "$GHF/calls" | grep -q -- '--draft'; then bad "multi-pr full-run: a ready PR" "$(cat "$GHF/calls")"; else ok "multi-pr full-run: a ready PR"; fi
for x in re-evaluation abandonment-forced; do
    setup multi-pr
    run --topic topic --exit "$x" --intent continue
    if grep '^pr create' "$GHF/calls" | grep -q -- '--draft'; then ok "$x: a draft, whatever the mode"; else bad "$x: a draft, whatever the mode" "$(cat "$GHF/calls")"; fi
    if [ "$x" = abandonment-forced ]; then
        # An abandoned run writes no PLAN, so a PLAN on disk is never part of
        # the body's artifact chain or work items.
        BODY=$(jq -r '.[0].body // ""' "$GHF/prs.json")
        case "$BODY" in
            *"docs/plans/PLAN-topic.md"*|*"## Work Items"*) bad "abandonment: the body names no PLAN and no work items" "$BODY" ;;
            *"## Artifact Chain"*) ok "abandonment: the body names no PLAN and no work items" ;;
            *) bad "abandonment: the body names no PLAN and no work items" "no body rendered: $BODY" ;;
        esac
    fi
done
setup coordinated
run --topic topic --exit full-run --intent continue
if command -v shirabe >/dev/null 2>&1; then
    if grep '^pr create' "$GHF/calls" | grep -q -- '--draft'; then ok "coordinated full-run: a draft"; else bad "coordinated full-run: a draft" "$(cat "$GHF/calls")"; fi
    BODY=$(jq -r '.[0].body // ""' "$GHF/prs.json")
    case "$BODY" in
        *"> This is a **coordination PR**"*) ok "coordinated: the body carries the declaration prefix" ;;
        *) bad "coordinated: the body carries the declaration prefix" "$BODY $(cat "$T/err")" ;;
    esac
    printf '%s' "$BODY" >"$T/coord-body.md"
    if shirabe validate --coordination-body "$T/coord-body.md" >/dev/null 2>&1; then
        ok "coordinated: the body passes shirabe validate --coordination-body"
    else
        bad "coordinated: the body passes shirabe validate --coordination-body" "$(shirabe validate --coordination-body "$T/coord-body.md" 2>&1 | tail -3)"
    fi
else
    # Without the validator a coordinated publish refuses rather than posting
    # an unchecked body.
    eq "coordinated, no shirabe: scope:pr-create" "scope:pr-create" "$(line step)"
    eq "coordinated, no shirabe: no pr create" "0" "$(calls create)"
    echo "SKIP: shirabe not on PATH -- the coordinated body was not rendered or validated"
fi
# Under omit a coordinated full-run's body is the plain description: no
# declaration, run lines, index or merge order, and a title naming no skill.
CONTENT=omit setup coordinated
run --topic topic --exit full-run --intent continue --session s-coord-omit
BODY=$(jq -r '.[0].body // ""' "$GHF/prs.json")
TITLE=$(grep '^pr create' "$GHF/calls" | sed -n 's/.*--title \(.*\) --body-file.*/\1/p')
eq "coordinated under omit: exit 0" 0 "$RC"
case "$BODY" in
    *"coordination PR"*|*"## PR Index"*|*"## Merge Order"*|*"topic="*|*"intent="*|*'shirabe''-run'*)
        bad "coordinated under omit: the body carries nothing of the run" "$BODY" ;;
    "The scoping documents for topic."*) ok "coordinated under omit: the body is the plain description" ;;
    *) bad "coordinated under omit: the body is the plain description" "$BODY" ;;
esac
case "$TITLE" in
    *scope*|*full-run*) bad "coordinated under omit: the title names no skill or exit" "$TITLE" ;;
    *) ok "coordinated under omit: the title names no skill or exit" ;;
esac

echo "== --verify =="
setup single-pr
run --topic topic --exit full-run --intent continue --session s-v
run --topic topic --verify
eq "verify after a publish: exit 0" "0" "$RC"
eq "verify: pr=" "https://github.com/acme/widgets/pull/100" "$(line pr)"
run --topic topic --verify --expect-intent continue --session s-v
eq "verify --expect-intent continue: exit 0" "0" "$RC"
run --topic topic --verify --expect-intent stop --session s-v
eq "verify --expect-intent stop against published_intent continue: exit 1" "1" "$RC"
: >"$GHF/calls"
printf 'more\n' >>"$R/README.md"; git -C "$R" commit -q -am more
run --topic topic --verify
eq "verify with origin behind HEAD: exit 1" "1" "$RC"
eq "verify makes no write call" "0" "$(( $(calls create) + $(calls edit) ))"

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main stop
git -C "$R" push -q origin HEAD:refs/heads/docs/topic
run --topic topic --verify --expect-intent continue --session s-rp
eq "verify --expect-intent before any publish in the session: exit 1" "1" "$RC"
case "$(cat "$T/err")" in *"no published_intent"*) ok "the refusal says the session records no published intent" ;; *) bad "the refusal says the session records no published intent" "$(cat "$T/err")" ;; esac
run --topic topic --exit full-run --intent continue --session s-rp
eq "republish over intent=stop: no pr create" "0" "$(calls create)"
eq "republish over intent=stop: one pr edit --body-file" "1" "$(grep -c '^pr edit https://github.com/acme/widgets/pull/7 --body-file ' "$GHF/calls" | tr -d ' ')"
run --topic topic --verify --expect-intent continue --session s-rp
eq "after the rewrite, verify --expect-intent continue passes" "0" "$RC"
# verify never reads the body: a body edited back to intent=stop by hand
# still verifies, because the session recorded what the run published.
jq 'map(if .url == "https://github.com/acme/widgets/pull/7" then .body = "intent=stop\n" else . end)' \
    "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
: >"$GHF/calls"
run --topic topic --verify --expect-intent continue --session s-rp
eq "a hand-edited intent= line does not change the verdict" "0" "$RC"
if grep -q -- '--json body' "$GHF/calls"; then bad "verify reads no PR body" "$(cat "$GHF/calls")"; else ok "verify reads no PR body"; fi
export KOTO_FAIL_KEY=published_intent
run --topic topic --verify --expect-intent continue --session s-rp
unset KOTO_FAIL_KEY
eq "verify with an unreadable published_intent: exit 2" "2" "$RC"
run --topic topic --verify --run-id "$MINE"
eq "verify --run-id: an unmarked PR verifies on the fallback" "0" "$RC"
mark "https://github.com/acme/widgets/pull/7" "$FOREIGN"
run --topic topic --verify --run-id "$MINE"
eq "verify --run-id: another run's PR does not verify (exit 1)" "1" "$RC"
mkdir -p "$STORE/s-verify"; printf '%s' "$FOREIGN" >"$STORE/s-verify/run_id"; printf 'continue' >"$STORE/s-verify/published_intent"
run --topic topic --verify --expect-intent continue --session s-verify
eq "verify --session: the session's own run verifies" "0" "$RC"

echo "== a plan/v2 step plan lists its step headings =="
# setup_v2 <fixture> -- setup, then the PLAN replaced by a plan/v2 fixture.
setup_v2() {
    setup multi-pr
    cp "$1" "$R/docs/plans/PLAN-topic.md"
    git -C "$R" add docs && git -C "$R" commit -q -m "docs: step plan"
}
setup_v2 "$HERE/testdata/PLAN-v2-steps.md"
run --topic topic --exit full-run --intent continue
eq "plan/v2: exit 0" "0" "$RC"
eq "plan/v2: one pr create" "1" "$(calls create)"
BODY=$(jq -r '.[0].body' "$GHF/prs.json")
WANT_STEPS='### Step 1: report export writes a one-row report as CSV
### Step 2: report export keeps only the columns named by --columns
### Step 3: report export writes to standard output when the path is -
### Step 4: report export refuses to overwrite a file without --force'
eq "plan/v2: the body lists every ### Step N: <title>, in order" "$WANT_STEPS" \
    "$(printf '%s\n' "$BODY" | grep '^### Step ')"
if grep -Eq '^### Step [0-9]+: *$' <<<"$BODY"; then
    bad "plan/v2: no step is listed with a blank title" "$BODY"
else
    ok "plan/v2: no step is listed with a blank title"
fi
case "$BODY" in
    *'## Work Items'*'```text'*'### Step 1:'*'### Step 4:'*'```'*) ok "plan/v2: the steps sit inside a fenced block under Work Items" ;;
    *) bad "plan/v2: the steps sit inside a fenced block under Work Items" "$BODY" ;;
esac
case "$BODY" in *"- Issue "*) bad "plan/v2: no plan/v1 Issue line" "$BODY" ;; *) ok "plan/v2: no plan/v1 Issue line" ;; esac

echo "== hostile step titles stay data in the body =="
setup_v2 "$HERE/../../execute/scripts/testdata/PLAN-v2-hostile.md"
rm -f "$R/PWNED" "$T/PWNED"
run --topic topic --exit full-run --intent continue
eq "hostile: exit 0" "0" "$RC"
if [ -e "$R/PWNED" ] || [ -e "$T/PWNED" ] || [ -e "$HERE/PWNED" ]; then
    bad "hostile: no PWNED file appears" ""
else
    ok "hostile: no PWNED file appears"
fi
BODY=$(jq -r '.[0].body' "$GHF/prs.json")
for want in '### Step 1: $(touch PWNED) runs end to end' \
            '### Step 2: `touch PWNED` in backticks, and Fixes #1' \
            '### Step 3: --help is not an option, @octocat is not a mention' \
            '### Step 4: [31mred [0m and $(touch PWNED)'; do
    if grep -Fxq -- "$want" <<<"$BODY"; then
        ok "hostile: the body holds [$want] as text"
    else
        bad "hostile: the body holds [$want] as text" "$BODY"
    fi
done
ESC=$(printf '\033')
case "$BODY" in *"$ESC"*) bad "hostile: no escape character reaches the body" "" ;; *) ok "hostile: no escape character reaches the body" ;; esac
# Every title line sits inside the one fenced block, so the closing keyword and
# the mention are code, not live text: the fence opens before step 1 and
# closes after step 4, with nothing but step lines between.
INSIDE=$(printf '%s\n' "$BODY" | awk '/^```text$/ { f = 1; next } f && /^```$/ { exit } f')
eq "hostile: the fenced block holds exactly the four step lines" "4" \
    "$(printf '%s\n' "$INSIDE" | grep -c '^### Step [1-4]: ' | tr -d ' ')"
eq "hostile: nothing else sits inside the fence" "4" "$(printf '%s\n' "$INSIDE" | wc -l | tr -d ' ')"

echo "== usage =="
setup single-pr
run --topic Bad --exit full-run --intent continue
eq "a bad topic is a usage error" "64" "$RC"
run --topic topic --exit full-run --intent none
eq "intent none is a usage error: a no-intent run never publishes" "64" "$RC"
run --topic topic --exit full-run --intent continue --run-id "$MINE"
eq "--run-id on a publish is a usage error (publish reads it from --session)" "64" "$RC"
run --topic topic --verify --session s --run-id "$MINE"
eq "--verify with both --session and --run-id is a usage error" "64" "$RC"
run --topic topic --verify --run-id ABC
eq "a malformed --run-id is a usage error" "64" "$RC"
run --topic topic --verify --expect-intent continue
eq "--expect-intent without --session is a usage error (it reads the session)" "64" "$RC"
run --topic topic --verify --expect-intent continue --run-id "$MINE"
eq "--expect-intent with --run-id is a usage error" "64" "$RC"
eq "usage errors make no gh call" "" "$(cat "$GHF/calls")"

echo "== flags a publish never uses, anywhere under skills/scope/ =="
HITS=$(grep -rnE 'git push[^|;&]*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$)|[[:space:]]"?\+)' "$SKILL" 2>/dev/null | grep -v '_test\.sh:' || true)
if [ -z "$HITS" ]; then ok "no force push and no + refspec"; else bad "no force push and no + refspec" "$HITS"; fi
HITS=$(grep -rnE 'gh pr (merge|review)' "$SKILL" 2>/dev/null | grep -v '_test\.sh:' || true)
if [ -z "$HITS" ]; then ok "no merge or review call"; else bad "no merge or review call" "$HITS"; fi
HITS=$(grep -rnE '(^|[^A-Za-z-])gh (pr|api|repo|issue|release|run|workflow) [^|;&]*(--admin|--auto)' "$SKILL" 2>/dev/null | grep -v '_test\.sh:' || true)
if [ -z "$HITS" ]; then ok "no --admin or --auto on a gh call"; else bad "no --admin or --auto on a gh call" "$HITS"; fi
HITS=$(grep -rn -- '--force-with-lease\|--admin' "$SKILL" 2>/dev/null | grep -v '_test\.sh:' || true)
if [ -z "$HITS" ]; then ok "--force-with-lease and --admin appear nowhere"; else bad "--force-with-lease and --admin appear nowhere" "$HITS"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
