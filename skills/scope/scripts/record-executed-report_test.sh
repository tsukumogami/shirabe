#!/usr/bin/env bash
# record-executed-report_test.sh -- executed_report's default action against a
# gh stub and a koto stand-in.
#
# Usage: bash skills/scope/scripts/record-executed-report_test.sh
#
# The gh stub serves canned JSON per case directory and logs every call, so each
# case asserts both what was written to context and that nothing was written to
# GitHub. The koto stand-in stores each context key as a file. Cases: a merged,
# an open and a closed owned PR; zero survivors, including a branch whose only
# PRs are a fork's, another author's, or aimed at another base; several owned
# PRs (owned-pr.sh exit 3); a failing read (owned-pr.sh exit 2, and a failing
# `gh pr view`); and stale keys from an earlier run that get cleared.
# Needs bash, git and jq.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/record-executed-report.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/executed-report-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

SHIM="$T/shim"
STORE="$T/store"
mkdir -p "$SHIM" "$STORE"
export STORE

cat >"$SHIM/koto" <<'STUB'
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
STUB

# The gh stub: $GHF/<key>.json is stdout, <key>.rc the exit status; a trailing
# --jq is applied. Every call is logged to $GHF/calls.
cat >"$SHIM/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GHF/calls"
case "$1 $2" in
    "api user") key=user ;;
    "api repos/"*) key=repo ;;
    "repo view") key=repo-view ;;
    "pr list") key=pr-list ;;
    "pr view") key=pr-view ;;
    *) echo "gh stub: unexpected: $*" >&2; exit 9 ;;
esac
rc=0; [ -f "$GHF/$key.rc" ] && rc=$(cat "$GHF/$key.rc")
[ "$rc" = 0 ] || exit "$rc"
jqf=""; prev=""
for a in "$@"; do [ "$prev" = "--jq" ] && jqf="$a"; prev="$a"; done
if [ -n "$jqf" ]; then jq -r "$jqf" "$GHF/$key.json"; else cat "$GHF/$key.json"; fi
STUB
chmod +x "$SHIM/koto" "$SHIM/gh"

R="$T/repo"
git -C "$T" init -q repo
git -C "$R" checkout -q -b docs/exec-topic

URL="https://github.com/acme/widgets/pull/42"
N=0
GHF=""
# fixture <pr-list-json> [pr-view-state] -- a fresh case directory.
fixture() {
    N=$((N + 1))
    GHF="$T/gh$N"
    mkdir -p "$GHF"
    printf '{"login":"me"}' >"$GHF/user.json"
    printf '{"default_branch":"main"}' >"$GHF/repo.json"
    printf '{"nameWithOwner":"acme/widgets"}' >"$GHF/repo-view.json"
    printf '%s' "$1" >"$GHF/pr-list.json"
    printf '{"state":"%s"}' "${2:-OPEN}" >"$GHF/pr-view.json"
    : >"$GHF/calls"
}

pr() { # pr <url> <state> <cross> <author> <base>
    printf '{"url":"%s","state":"%s","isCrossRepository":%s,"author":{"login":"%s"},"baseRefName":"%s","headRefName":"docs/exec-topic"}' "$1" "$2" "$3" "$4" "$5"
}

run() { # run <session>
    (cd "$R" && PATH="$SHIM:$PATH" GHF="$GHF" bash "$S" --session "$1" --topic exec-topic >/dev/null 2>"$T/err")
    RC=$?
}
key() { cat "$STORE/$1/$2" 2>/dev/null; }
has() { [ -f "$STORE/$1/$2" ]; }
no_writes() {
    if grep -E '^pr (create|edit|merge|ready|close|review|comment)|^api .*(-X|--method)' "$GHF/calls" >/dev/null; then
        bad "$1: no GitHub write" "$(cat "$GHF/calls")"
    else
        ok "$1: no GitHub write"
    fi
}

echo "== one owned PR =="
for pair in MERGED:merged OPEN:open CLOSED:closed; do
    ghs="${pair%%:*}"; want="${pair#*:}"
    if [ "$ghs" = CLOSED ]; then
        # owned-pr.sh --state all never returns a closed-unmerged PR, so the
        # closed case is a PR that closed between the lookup and the state read.
        fixture "[$(pr "$URL" OPEN false me main)]" CLOSED
    else
        fixture "[$(pr "$URL" "$ghs" false me main)]" "$ghs"
    fi
    run "s-$want"
    eq "$want: exit 0" "0" "$RC"
    eq "$want: verdict one" "one" "$(key "s-$want" executed_verdict)"
    eq "$want: the PR's URL" "$URL" "$(key "s-$want" executed_pr)"
    eq "$want: its state" "$want" "$(key "s-$want" executed_pr_state)"
    no_writes "$want"
done
if grep -q -- '--state all' "$GHF/calls"; then ok "the lookup is owned-pr.sh --state all"; else bad "the lookup is owned-pr.sh --state all" "$(cat "$GHF/calls")"; fi

echo "== zero survivors =="
fixture "[]"
run s-empty
eq "no PR at all: none" "none" "$(key s-empty executed_verdict)"
if has s-empty executed_pr; then bad "none writes no executed_pr"; else ok "none writes no executed_pr"; fi
no_writes "none"

FOREIGN="https://github.com/fork/widgets/pull/7"
fixture "[$(pr "$FOREIGN" OPEN true me main),$(pr "https://github.com/acme/widgets/pull/8" MERGED false someone-else main),$(pr "https://github.com/acme/widgets/pull/9" OPEN false me release)]"
run s-foreign
eq "a foreign-only branch: none" "none" "$(key s-foreign executed_verdict)"
if grep -rq "pull/7\|pull/8\|pull/9" "$STORE/s-foreign" 2>/dev/null; then bad "no foreign URL reaches context"; else ok "no foreign URL reaches context"; fi

echo "== several, and read failures =="
fixture "[$(pr "$URL" MERGED false me main),$(pr "https://github.com/acme/widgets/pull/43" OPEN false me main)]"
run s-several
eq "several owned PRs (owned-pr.sh exit 3): several" "several" "$(key s-several executed_verdict)"
eq "several: still exit 0, so the gates route it" "0" "$RC"
if has s-several executed_pr; then bad "several writes no executed_pr"; else ok "several writes no executed_pr"; fi

fixture "[]"
echo 1 >"$GHF/pr-list.rc"
run s-readfail
eq "a failing list (owned-pr.sh exit 2): read-failed" "read-failed" "$(key s-readfail executed_verdict)"

fixture "[$(pr "$URL" MERGED false me main)]"
echo 1 >"$GHF/pr-view.rc"
run s-viewfail
eq "a failing state read: read-failed" "read-failed" "$(key s-viewfail executed_verdict)"
if has s-viewfail executed_pr; then bad "a failed state read leaves no executed_pr"; else ok "a failed state read leaves no executed_pr"; fi

fixture "[]"
echo 1 >"$GHF/repo-view.rc"
run s-norepo
eq "an unreadable repository name: read-failed" "read-failed" "$(key s-norepo executed_verdict)"

echo "== stale keys are cleared =="
mkdir -p "$STORE/s-stale"
printf 'one' >"$STORE/s-stale/executed_verdict"
printf '%s' "$URL" >"$STORE/s-stale/executed_pr"
printf 'merged' >"$STORE/s-stale/executed_pr_state"
fixture "[]"
run s-stale
eq "a stale one becomes none" "none" "$(key s-stale executed_verdict)"
if has s-stale executed_pr || has s-stale executed_pr_state; then
    bad "stale executed_pr and executed_pr_state are removed"
else
    ok "stale executed_pr and executed_pr_state are removed"
fi

echo "== usage =="
(cd "$R" && PATH="$SHIM:$PATH" GHF="$GHF" bash "$S" --session s-u --topic Bad >/dev/null 2>&1); RC=$?
eq "a bad topic is a usage error" "64" "$RC"
if [ -d "$STORE/s-u" ]; then bad "a usage error writes nothing"; else ok "a usage error writes nothing"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
