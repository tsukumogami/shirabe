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
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
S="$HERE/publish-scoping-pr.sh"
STUB="$HERE/testdata/gh-stateful-stub.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/publish-test.XXXXXX")" || exit 1
T="$(cd -P "$T" && pwd -P)" || exit 1
ktg_on_exit 'case "$T" in */publish-test.*) rm -rf "$T" ;; esac'
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
    *) exit 2 ;;
esac
KOTO
chmod +x "$SHIM/gh" "$SHIM/koto"

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

echo "== the run marker =="
MINE=0123456789abcdef0123456789abcdef
FOREIGN=fedcba9876543210fedcba9876543210
# mark <url> <id> -- append a run marker line to that seeded PR's body.
mark() {
    jq --arg u "$1" --arg m "<!-- shirabe-run: $2 -->" 'map(if .url == $u then .body += ($m + "\n") else . end)' \
        "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
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
    *"intent=continue"*"<!-- shirabe-run: $MINE -->"*) ok "the intent rewrite keeps the PR's run marker" ;;
    *) bad "the intent rewrite keeps the PR's run marker" "$BODY7" ;;
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

echo "== every body has two parts =="
# The squash message is the title and Part 1, everything above the body's
# first top-level `---` outside a code fence (scripts/lib/squash-message.sh).
# Every body /scope writes, on create and on a rewrite, has exactly one, a
# Part 1 of plain prose with no heading, and the run marker below it.
SQUASH="$HERE/../../../scripts/lib/squash-message.sh"
# sep_line <file> -- the first top-level `---` line outside a fence, 0 when
# there is none. seps <file> -- how many such lines there are.
sep_line() {
    awk '{ l = $0; sub(/\r$/, "", l) }
         l ~ /^[ \t]*```/ { f = !f; next }
         !f && l ~ /^[ \t]*---[ \t]*$/ { print NR; found = 1; exit }
         END { if (!found) print 0 }' "$1"
}
seps() {
    awk '{ l = $0; sub(/\r$/, "", l) }
         l ~ /^[ \t]*```/ { f = !f; next }
         !f && l ~ /^[ \t]*---[ \t]*$/ { n++ }
         END { print n + 0 }' "$1"
}
# two_parts <label> <body-file> -- one separator, a non-empty Part 1, no ATX
# heading in it (references/pr-body-conformance.md, PB2 and PB4).
two_parts() {
    local s p1=""
    eq "$1: exactly one top-level ---" "1" "$(seps "$2")"
    s=$(sep_line "$2")
    [ "$s" -gt 1 ] && p1=$(sed -n "1,$((s - 1))p" "$2")
    if [ -n "$(tr -d '[:space:]' <<<"$p1")" ]; then ok "$1: Part 1 is not empty"; else bad "$1: Part 1 is not empty" "$(cat "$2")"; fi
    if grep -Eq '^ {0,3}#{1,6}([[:space:]]|$)' <<<"$p1"; then
        bad "$1: no ATX heading in Part 1" "$p1"
    else
        ok "$1: no ATX heading in Part 1"
    fi
    if command -v shirabe >/dev/null 2>&1; then
        if shirabe validate --pr-body "$2" >/dev/null 2>&1; then
            ok "$1: shirabe validate --pr-body passes"
        else
            bad "$1: shirabe validate --pr-body passes" "$(shirabe validate --pr-body "$2" 2>&1 | tail -3)"
        fi
    fi
}
# marker_below <label> <body-file> -- this run's marker, once, below the separator.
marker_below() {
    local s m
    s=$(sep_line "$2")
    m=$(awk -v m="<!-- shirabe-run: $MINE -->" '$0 == m { print NR }' "$2")
    case "$m" in
        ""|*[!0-9]*) bad "$1: the run marker sits once, below the separator" "$(cat "$2")" ;;
        *) if [ "$s" -gt 0 ] && [ "$m" -gt "$s" ]; then
               ok "$1: the run marker sits once, below the separator"
           else
               bad "$1: the run marker sits once, below the separator" "$(cat "$2")"
           fi ;;
    esac
}

for kind in default records coordinated; do
    if [ "$kind" = coordinated ] && ! command -v shirabe >/dev/null 2>&1; then
        echo "SKIP: shirabe not on PATH -- the coordinated two-part body was not rendered"
        continue
    fi
    case "$kind" in
        default) CONTENT=omit setup single-pr ;;
        records) setup single-pr ;;
        coordinated) setup coordinated ;;
    esac
    run --topic topic --exit full-run --intent continue
    eq "$kind: the create exits 0" "0" "$RC"
    jq -r '.[0].body' "$GHF/prs.json" >"$T/created.md"
    two_parts "$kind: the created body" "$T/created.md"
    if [ "$kind" = default ]; then
        eq "default: the squash message is the title and the one sentence" \
            "$(printf 'docs: add the topic scoping documents\n\nThe scoping documents for topic.')" \
            "$(bash "$SQUASH" --title "docs: add the topic scoping documents" "$T/created.md")"
    fi
    # A rewrite of the same PR, whose body this run marked and which has no
    # separator: the template's two parts, the marker carried below them.
    jq --arg m "<!-- shirabe-run: $MINE -->" '.[0].body = ("intent=stop\n" + $m + "\n")' \
        "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
    mkdir -p "$STORE/s-two-$kind"; printf '%s' "$MINE" >"$STORE/s-two-$kind/run_id"
    run --topic topic --exit full-run --intent continue --session "s-two-$kind"
    eq "$kind: the rewrite exits 0" "0" "$RC"
    eq "$kind: one pr edit" "1" "$(calls edit)"
    jq -r '.[0].body' "$GHF/prs.json" >"$T/rewritten.md"
    two_parts "$kind: the rewritten body" "$T/rewritten.md"
    marker_below "$kind: the rewritten body" "$T/rewritten.md"
    if [ "$kind" = coordinated ]; then
        if shirabe validate --coordination-body "$T/rewritten.md" >/dev/null 2>&1; then
            ok "coordinated: the rewritten body passes shirabe validate --coordination-body"
        else
            bad "coordinated: the rewritten body passes shirabe validate --coordination-body" \
                "$(shirabe validate --coordination-body "$T/rewritten.md" 2>&1 | tail -3)"
        fi
    fi
done

echo "== a rewrite keeps the live Part 1 and the Part 2 sections it does not write =="
# set_body <url> <file> -- replace that seeded PR's body with the file's bytes.
set_body() {
    jq --arg u "$1" --rawfile b "$2" 'map(if .url == $u then .body = $b else . end)' \
        "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
}
P7="https://github.com/acme/widgets/pull/7"
setup single-pr
seed_pr "$P7" false me main stop
# A person's Part 1, with a list and a fenced `---` that is not the separator,
# then a Part 2 holding the template's old sections and two someone added.
cat >"$T/live-part1.md" <<'EOF'
A person's description of the change, kept on every rewrite.

```text
---
```

- a list item

EOF
cat >"$T/live-part2.md" <<EOF
---

# /scope: topic

topic=topic
intent=stop

## Artifact Chain

- docs/old-path.md

## Review panel

| Seat | Model | Run | Verdict |
|------|-------|-----|---------|
| scrutiny | m | run-1 | pass |

## Work Items

- #99

## Notes for the reviewer

Text someone added.

<!-- shirabe-run: $MINE -->
EOF
cat "$T/live-part1.md" "$T/live-part2.md" >"$T/live.md"
set_body "$P7" "$T/live.md"
mkdir -p "$STORE/s-keep"; printf '%s' "$MINE" >"$STORE/s-keep/run_id"
run --topic topic --exit full-run --intent continue --session s-keep
eq "keep: exit 0" "0" "$RC"
eq "keep: one pr edit" "1" "$(calls edit)"
jq -r --arg u "$P7" '.[] | select(.url == $u) | .body' "$GHF/prs.json" >"$T/kept.md"
head -c "$(wc -c <"$T/live-part1.md" | tr -d ' ')" "$T/kept.md" >"$T/kept-part1.md"
if cmp -s "$T/live-part1.md" "$T/kept-part1.md"; then
    ok "keep: the live Part 1 is kept byte for byte"
else
    bad "keep: the live Part 1 is kept byte for byte" "$(cat "$T/kept.md")"
fi
eq "keep: the separator follows the kept Part 1" "$(( $(wc -l <"$T/live-part1.md") + 1 ))" "$(sep_line "$T/kept.md")"
two_parts "keep: the rewritten body" "$T/kept.md"
marker_below "keep: the rewritten body" "$T/kept.md"
section() { # section <heading> <file> -- that `## ` section, heading to the next one
    awk -v h="$1" '$0 == h { p = 1; print; next } p && /^## / { exit } p' "$2"
}
eq "keep: the live Part 2's ## Review panel section is carried unchanged" \
    "$(printf '## Review panel\n\n| Seat | Model | Run | Verdict |\n|------|-------|-----|---------|\n| scrutiny | m | run-1 | pass |')" \
    "$(section '## Review panel' "$T/kept.md")"
eq "keep: a second section someone added is carried unchanged" \
    "$(printf '## Notes for the reviewer\n\nText someone added.\n\n<!-- shirabe-run: %s -->' "$MINE")" \
    "$(section '## Notes for the reviewer' "$T/kept.md")"
HEADS=$(awk -v s="$(sep_line "$T/kept.md")" 'NR > s && /^## /' "$T/kept.md")
eq "keep: the template's sections, then the carried ones in live order" \
    "$(printf '## Artifact Chain\n## Work Items\n## Review panel\n## Notes for the reviewer')" "$HEADS"
KEPT=$(cat "$T/kept.md")
case "$KEPT" in
    *"docs/old-path.md"*|*"#99"*|*"intent=stop"*) bad "keep: the template's own sections and record lines are replaced" "$KEPT" ;;
    *"intent=continue"*"docs/plans/PLAN-topic.md"*"#31"*) ok "keep: the template's own sections and record lines are replaced" ;;
    *) bad "keep: the template's own sections and record lines are replaced" "$KEPT" ;;
esac
case "$(cat "$T/err")" in
    *"## Review panel"*"## Notes for the reviewer"*) ok "keep: stderr names each carried section" ;;
    *) bad "keep: stderr names each carried section" "$(cat "$T/err")" ;;
esac
MSG=$(bash "$SQUASH" --title "docs(scope): topic (full-run)" "$T/kept.md")
eq "keep: squash-message.sh exits 0 on the rewritten body" "0" "$?"
case "$MSG" in
    *"Review panel"*|*"topic="*|*"Artifact Chain"*|*"Work Items"*|*"shirabe-run"*|*"Text someone added"*|*"#31"*)
        bad "keep: the squash message carries none of Part 2" "$MSG" ;;
    "docs(scope): topic (full-run)"$'\n\n'"A person's description of the change, kept on every rewrite."*"a list item")
        ok "keep: the squash message carries none of Part 2" ;;
    *) bad "keep: the squash message carries none of Part 2" "$MSG" ;;
esac

# A run of the same body again carries each section once, not twice.
rm -f "$STORE/s-keep/published_intent"
run --topic topic --exit full-run --intent continue --session s-keep
jq -r --arg u "$P7" '.[] | select(.url == $u) | .body' "$GHF/prs.json" >"$T/kept2.md"
eq "keep: a second rewrite carries the Review panel section once" "1" "$(grep -c '^## Review panel$' "$T/kept2.md" | tr -d ' ')"
if cmp -s "$T/kept.md" "$T/kept2.md"; then ok "keep: a second rewrite changes nothing"; else bad "keep: a second rewrite changes nothing" "$(diff "$T/kept.md" "$T/kept2.md")"; fi

# \r\n line endings, as a body edited in the browser comes back.
setup single-pr
seed_pr "$P7" false me main stop
printf 'Line one of a description.\r\n\r\n' >"$T/crlf-part1.md"
printf -- '---\r\n\r\n## Review panel\r\n\r\n| Seat | Verdict |\r\n| a | pass |\r\n' >"$T/crlf-part2.md"
cat "$T/crlf-part1.md" "$T/crlf-part2.md" >"$T/crlf.md"
set_body "$P7" "$T/crlf.md"
run --topic topic --exit full-run --intent continue --session s-crlf
jq -r --arg u "$P7" '.[] | select(.url == $u) | .body' "$GHF/prs.json" >"$T/crlf-kept.md"
head -c "$(wc -c <"$T/crlf-part1.md" | tr -d ' ')" "$T/crlf-kept.md" >"$T/crlf-kept-part1.md"
if cmp -s "$T/crlf-part1.md" "$T/crlf-kept-part1.md"; then
    ok "crlf: the live Part 1 is kept byte for byte, \\r included"
else
    bad "crlf: the live Part 1 is kept byte for byte, \\r included" "$(od -c "$T/crlf-kept.md" | head -5)"
fi
if grep -qF $'| a | pass |\r' "$T/crlf-kept.md"; then
    ok "crlf: the carried Review panel section keeps its \\r"
else
    bad "crlf: the carried Review panel section keeps its \\r" "$(od -c "$T/crlf-kept.md" | tail -8)"
fi
eq "crlf: exactly one top-level ---" "1" "$(seps "$T/crlf-kept.md")"

# A live body with no separator has no Part 1 to keep: the template's goes in.
setup single-pr
seed_pr "$P7" false me main stop
printf 'intent=stop\n\n## Review panel\n\n| x |\n' >"$T/nosep.md"
set_body "$P7" "$T/nosep.md"
run --topic topic --exit full-run --intent continue --session s-nosep
jq -r --arg u "$P7" '.[] | select(.url == $u) | .body' "$GHF/prs.json" >"$T/nosep-new.md"
eq "no separator: the template's Part 1" "The scoping documents for topic." "$(sed -n 1p "$T/nosep-new.md")"
eq "no separator: the separator follows it" "3" "$(sep_line "$T/nosep-new.md")"
two_parts "no separator: the rewritten body" "$T/nosep-new.md"

# A live Part 1 with no text is not kept (PB2 needs one); its sections still are.
setup single-pr
seed_pr "$P7" false me main stop
printf '\n---\n\n## Review panel\n\n| x |\n' >"$T/blank.md"
set_body "$P7" "$T/blank.md"
run --topic topic --exit full-run --intent continue --session s-blank
jq -r --arg u "$P7" '.[] | select(.url == $u) | .body' "$GHF/prs.json" >"$T/blank-new.md"
eq "blank Part 1: the template's Part 1" "The scoping documents for topic." "$(sed -n 1p "$T/blank-new.md")"
eq "blank Part 1: the Review panel section is still carried" "$(printf '## Review panel\n\n| x |')" \
    "$(section '## Review panel' "$T/blank-new.md")"
two_parts "blank Part 1: the rewritten body" "$T/blank-new.md"

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
