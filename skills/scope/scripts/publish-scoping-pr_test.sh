#!/usr/bin/env bash
# publish-scoping-pr_test.sh -- /scope's publish step against a stub gh and a
# local bare origin.
#
# Usage: bash skills/scope/scripts/publish-scoping-pr_test.sh
#
# Every case clones a fresh bare `origin`, commits a PLAN and the topic's wip/
# on a topic branch, and runs the script with testdata/gh-stateful-stub.sh as
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

T="$(mktemp -d "${TMPDIR:-/tmp}/publish-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
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
# holding a PLAN of that mode and tracked wip/. Sets R, O, GHF.
setup() {
    local mode="${1:-single-pr}" branch="${2:-docs/topic}"
    N=$((N + 1))
    O="$T/origin$N.git"; R="$T/work$N"; GHF="$T/gh$N"
    mkdir -p "$GHF"; : >"$GHF/calls"; printf '[]' >"$GHF/prs.json"
    git init -q --bare -b main "$O"
    git init -q -b main "$R"
    printf '# repo\n' >"$R/README.md"
    git -C "$R" add README.md && git -C "$R" commit -q -m init
    git -C "$R" remote add origin "$O"
    git -C "$R" push -q -u origin main
    [ "$branch" = main ] || git -C "$R" checkout -q -b "$branch"
    mkdir -p "$R/docs/plans" "$R/wip/research"
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
    printf 'topic: topic\n' >"$R/wip/scope_topic_state.md"
    printf 'notes\n' >"$R/wip/research/design_topic_notes.md"
    printf 'other\n' >"$R/wip/other_file.md"
    git -C "$R" add docs wip && git -C "$R" commit -q -m "docs: scope topic"
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
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1; }

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
eq "the topic's wip/ is untracked" "" "$(git -C "$R" ls-files -- 'wip/scope_topic_*' 'wip/research/design_topic_*')"
eq "another skill's wip/ is left tracked" "wip/other_file.md" "$(git -C "$R" ls-files -- wip/other_file.md)"
if [ -f "$R/wip/scope_topic_state.md" ]; then ok "the untracked files stay on disk"; else bad "the untracked files stay on disk"; fi
eq "the untrack commit holds exactly the removal" "D	wip/research/design_topic_notes.md
D	wip/scope_topic_state.md" "$(git -C "$R" show --format= --name-status HEAD)"
case "$(line wip_paths)" in
    *wip/scope_topic_state.md*) ok "wip_paths names the wip/ in unpushed history" ;;
    *) bad "wip_paths names the wip/ in unpushed history" "$OUT" ;;
esac
eq "--session: wip_paths recorded" "$(line wip_paths)" "$(cat "$STORE/s-new/wip_paths" 2>/dev/null)"
if [ -f "$STORE/s-new/publish_step" ]; then bad "--session: no publish_step on success"; else ok "--session: no publish_step on success"; fi
BODY=$(jq -r '.[0].body' "$GHF/prs.json")
case "$BODY" in *"intent=continue"*) ok "the body records intent=continue" ;; *) bad "the body records intent=continue" "$BODY" ;; esac
case "$BODY" in *"docs/plans/PLAN-topic.md"*"#31"*) ok "the body lists the PLAN and its work items" ;; *) bad "the body lists the PLAN and its work items" "$BODY" ;; esac

echo "== a second run after a successful one =="
BEFORE=$(remote_sha docs/topic)
run --topic topic --exit full-run --intent continue
eq "second run: exit 0" "0" "$RC"
eq "second run: still one pr create" "1" "$(calls create)"
eq "second run: no pr edit (intent unchanged)" "0" "$(calls edit)"
eq "second run: no new push" "$BEFORE" "$(remote_sha docs/topic)"
eq "second run: the same PR" "https://github.com/acme/widgets/pull/100" "$(line pr)"

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

echo "== /brief's jury verdict files are untracked too =="
setup single-pr
VERDICT="research/brief_topic_phase4_content-quality.md"
printf 'verdict\n' >"$R/wip/$VERDICT"
git -C "$R" add -- "wip/$VERDICT" && git -C "$R" commit -q -m "wip: verdict"
run --topic topic --exit full-run --intent continue --session s-verdict
eq "verdict: exit 0" "0" "$RC"
eq "verdict: the verdict file is untracked" "" "$(git -C "$R" ls-files -- "wip/$VERDICT")"
case "$(git -C "$R" show --format= --name-status HEAD)" in
    *"D	wip/$VERDICT"*) ok "verdict: the untrack commit removes it" ;;
    *) bad "verdict: the untrack commit removes it" "$(git -C "$R" show --format= --name-status HEAD)" ;;
esac
if [ -f "$R/wip/$VERDICT" ]; then ok "verdict: the file stays on disk"; else bad "verdict: the file stays on disk"; fi

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
printf '# repo\n\n## Repo Visibility: Public\n' >"$R/CLAUDE.md"
printf 'see private/tools/notes.md for the numbers\n' >"$R/wip/research/design_topic_notes.md"
git -C "$R" add CLAUDE.md wip && git -C "$R" commit -q -m "wip: research"
run --topic topic --exit full-run --intent continue
eq "a visibility-check hit in unpushed wip/: scope:push" "scope:push" "$(line step)"
eq "a visibility-check hit: nothing pushed" "" "$(remote_sha docs/topic)"
eq "a visibility-check hit: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"

# The same hit on the first line of a blob far larger than a pipe buffer. Piped
# into `grep -q`, grep exits on that line while git is still writing, git dies of
# SIGPIPE, and under pipefail the `if` read the 141 as "no match" and pushed.
setup single-pr
printf '# repo\n\n## Repo Visibility: Public\n' >"$R/CLAUDE.md"
{
    printf 'see private/tools/notes.md for the numbers\n'
    awk 'BEGIN { for (i = 0; i < 20000; i++) print "filler line to outgrow the pipe buffer" }'
} >"$R/wip/research/design_topic_notes.md"
git -C "$R" add CLAUDE.md wip && git -C "$R" commit -q -m "wip: research"
run --topic topic --exit full-run --intent continue
eq "a hit on line 1 of a large blob: scope:push" "scope:push" "$(line step)"
eq "a hit on line 1 of a large blob: nothing pushed" "" "$(remote_sha docs/topic)"
eq "a hit on line 1 of a large blob: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"

# The same failure one step earlier: a wip/ path list larger than a pipe buffer,
# with the offending path sorted first. Piped into `grep -qxF`, the listing
# check died of SIGPIPE on the match and `|| continue` skipped the path unscanned.
setup single-pr
printf '# repo\n\n## Repo Visibility: Public\n' >"$R/CLAUDE.md"
printf 'see private/tools/notes.md for the numbers\n' >"$R/wip/aaa_first_notes.md"
mkdir -p "$R/wip/zz"
awk -v d="$R/wip/zz" 'BEGIN { for (i = 0; i < 2000; i++) { f = sprintf("%s/filler_note_with_a_long_name_to_grow_the_list_%05d.md", d, i); print "x" > f; close(f) } }'
git -C "$R" add CLAUDE.md wip && git -C "$R" commit -q -m "wip: research"
run --topic topic --exit full-run --intent continue
eq "a hit first in a large wip/ list: scope:push" "scope:push" "$(line step)"
eq "a hit first in a large wip/ list: nothing pushed" "" "$(remote_sha docs/topic)"
eq "a hit first in a large wip/ list: no gh write" "0" "$(( $(calls create) + $(calls edit) ))"

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
run --topic topic --exit full-run --intent continue
run --topic topic --verify
eq "verify after a publish: exit 0" "0" "$RC"
eq "verify: pr=" "https://github.com/acme/widgets/pull/100" "$(line pr)"
run --topic topic --verify --expect-intent continue
eq "verify --expect-intent continue: exit 0" "0" "$RC"
: >"$GHF/calls"
printf 'more\n' >>"$R/README.md"; git -C "$R" commit -q -am more
run --topic topic --verify
eq "verify with origin behind HEAD: exit 1" "1" "$RC"
eq "verify makes no write call" "0" "$(( $(calls create) + $(calls edit) ))"

setup single-pr
seed_pr "https://github.com/acme/widgets/pull/7" false me main stop
git -C "$R" push -q origin HEAD:refs/heads/docs/topic
run --topic topic --verify --expect-intent continue
eq "verify --expect-intent continue against intent=stop: exit 1" "1" "$RC"
run --topic topic --exit full-run --intent continue
eq "republish over intent=stop: no pr create" "0" "$(calls create)"
eq "republish over intent=stop: one pr edit --body-file" "1" "$(grep -c '^pr edit https://github.com/acme/widgets/pull/7 --body-file ' "$GHF/calls" | tr -d ' ')"
run --topic topic --verify --expect-intent continue
eq "after the rewrite, verify --expect-intent continue passes" "0" "$RC"
run --topic topic --verify --expect-intent continue --run-id "$MINE"
eq "verify --run-id: an unmarked PR verifies on the fallback" "0" "$RC"
mark "https://github.com/acme/widgets/pull/7" "$FOREIGN"
run --topic topic --verify --expect-intent continue --run-id "$MINE"
eq "verify --run-id: another run's PR does not verify (exit 1)" "1" "$RC"
mkdir -p "$STORE/s-verify"; printf '%s' "$FOREIGN" >"$STORE/s-verify/run_id"
run --topic topic --verify --expect-intent continue --session s-verify
eq "verify --session: the session's own run verifies" "0" "$RC"

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
