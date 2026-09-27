#!/usr/bin/env bash
# reconcile-check_test.sh -- reconcile-check.sh makes each GitHub re-check
# with read-only calls and prints one fact, turning a failed, late or
# uninterpretable read into a not_verified fact and refusing a bad row value
# before any call.
#
# The scripts run from a copy of the tree in a temp directory, so the record
# feature's board-verdict.sh and deferral-check.sh can be stand-ins placed
# beside them (the scripts take no override for either). gh and git are
# keyed stand-ins on PATH: each call is appended to the case's log and served
# from <case>/<key>.out.<N> (the Nth call to that key), with an optional
# .rc.<N> exit status, .err.<N> stderr, and .sleep.<N> delay. Every case gets
# a fresh directory, so call counters never carry over. Needs bash and jq.
#
# Usage: bash skills/coordinate/scripts/reconcile-check_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-check-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The copied tree: reconcile's scripts, /execute's validators, and the two
# stand-in record-feature checks beside reconcile's scripts.
mkdir -p "$T/tree/skills/coordinate/scripts" "$T/tree/skills/execute/scripts" "$T/bin"
cp "$HERE"/reconcile-check.sh "$HERE"/reconcile-deps.sh "$T/tree/skills/coordinate/scripts/"
cp "$HERE/../../execute/scripts/coord-common.sh" "$T/tree/skills/execute/scripts/"
S="$T/tree/skills/coordinate/scripts/reconcile-check.sh"

REAL_GIT=$(command -v git)
export REAL_GIT
cat > "$T/bin/stub" <<'STUB'
#!/usr/bin/env bash
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$STUB_LOG"
# git calls other than ls-remote go to the real git: the inventory reads a
# real clone. rd_git puts its -c flags before the subcommand, so find it.
if [ "$name" = git ]; then
    sub=""; skip=0
    for a in "$@"; do
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$a" in -c|-C) skip=1 ;; --*) ;; *) sub=$a; break ;; esac
    done
    [ "$sub" = ls-remote ] || exec "$REAL_GIT" "$@"
fi
# Contents reads keyed by ref and path, when the case serves them that way.
if [ "$name" = gh ] && [ "$1" = api ]; then
    case "$2" in */contents/*"?ref="*)
        p=${2#*/contents/}; ref=${p##*\?ref=}; p=${p%%\?ref=*}
        f="$STUB_DIR/contents@$ref@$(printf '%s' "$p" | tr '/' '_')"
        if [ -f "$f" ]; then jq -r .sha < "$f"; exit 0; fi
        if ls "$STUB_DIR"/contents@* >/dev/null 2>&1; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
    ;; esac
fi
case "$name:$1:$2" in
    gh:pr:view) key=pr-view ;;
    gh:pr:list) key=pr-list ;;
    gh:issue:view) key=issue-view ;;
    gh:api:*/pulls/*/files*) key=api-files ;;
    gh:api:*/compare/*) key=compare ;;
    gh:api:*/contents/*) ref=${2##*ref=}; key=contents-$ref ;;
    gh:api:*/git/trees/*) key=tree ;;
    gh:api:*/git/ref/*) key=git-ref ;;
    gh:api:*/pulls/*) key=api-pull ;;
    git:*) key=ls-remote ;;
    niwa:list:*) key=niwa-list ;;
    koto:request:get) key=koto-request ;;
    board-verdict.sh:*) key=board ;;
    deferral-check.sh:*) key=deferral ;;
    *) echo "stub: unexpected call: $name $*" >&2; exit 99 ;;
esac
n_file="$STUB_DIR/.n.$key"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
[ -f "$STUB_DIR/$key.sleep.$n" ] && sleep "$(cat "$STUB_DIR/$key.sleep.$n")"
[ -f "$STUB_DIR/$key.err.$n" ] && cat "$STUB_DIR/$key.err.$n" >&2
rc=$(cat "$STUB_DIR/$key.rc.$n" 2>/dev/null || echo 0)
# gh applies --jq to the API's JSON and prints strings raw, one per line: run
# the caller's own program the same way, so the jq in the script is tested.
jqexpr=""
prev=""
for a in "$@"; do [ "$prev" = --jq ] && jqexpr=$a; prev=$a; done
[ -f "$STUB_DIR/$key.out.$n" ] || { [ -f "$STUB_DIR/$key.out.all" ] && cp "$STUB_DIR/$key.out.all" "$STUB_DIR/$key.out.$n"; }
if [ -f "$STUB_DIR/$key.out.$n" ]; then
    if [ "$name" = gh ] && [ -n "$jqexpr" ] && [ "$rc" = 0 ]; then
        jq -r "$jqexpr" < "$STUB_DIR/$key.out.$n" || exit 1
    else
        cat "$STUB_DIR/$key.out.$n"
    fi
fi
exit "$rc"
STUB
chmod +x "$T/bin/stub"
for n in gh git niwa koto; do ln -s stub "$T/bin/$n"; done
mkdir -p "$T/nobin"
for n in board-verdict.sh deferral-check.sh; do ln -s "$T/bin/stub" "$T/tree/skills/coordinate/scripts/$n"; done

CASE=""
CASES=0
new_case() {
    CASES=$((CASES + 1))
    CASE="$T/case-$CASES-$1"
    mkdir -p "$CASE"
    : > "$CASE/log"
}
serve() { printf '%s' "$3" > "$CASE/$1.out.$2"; }           # serve <key> <n> <stdout>
fail_with() { echo "$3" > "$CASE/$1.rc.$2"; [ -n "${4-}" ] && printf '%s' "$4" > "$CASE/$1.err.$2"; return 0; }
run() {
    STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$T/bin:$PATH" \
      RECONCILE_READ_DEADLINE="${DL:-5}" RECONCILE_BOARD_DEADLINE="${BDL:-5}" "$BASH" "$S" "$@"
}
expect() {  # expect <label> <jq predicate> <output>
    if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "$3 | log: $(cat "$CASE/log")"; fi
}

VH=1111111111111111111111111111111111111111
LH=2222222222222222222222222222222222222222
BS=3333333333333333333333333333333333333333
R=acme/widgets
MERGED_PR="{\"state\":\"closed\",\"merged\":true,\"base\":{\"ref\":\"main\",\"sha\":\"$BS\"}}"
BN=cccccccccccccccccccccccccccccccccccccccc
BA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

echo "== pr =="
new_case pr-merged
serve pr-view 1 "{\"state\":\"MERGED\",\"isDraft\":false,\"headRefOid\":\"$VH\",\"mergeStateStatus\":\"UNKNOWN\",\"baseRefName\":\"main\"}"
expect "a merged pull request is a merged fact" '.kind == "pr" and .status == "ok" and .state == "MERGED" and .base == "main"' "$(run pr --repo $R --number 7)"
new_case pr-draft
serve pr-view 1 "{\"state\":\"OPEN\",\"isDraft\":true,\"headRefOid\":\"$VH\",\"mergeStateStatus\":\"DRAFT\",\"baseRefName\":\"main\"}"
expect "a draft pull request carries its draft flag and merge state" '.draft == true and .merge_state == "DRAFT"' "$(run pr --repo $R --number 7)"
new_case pr-empty
serve pr-view 1 '{}'
expect "an empty pull request response is not verified" '.status == "not_verified"' "$(run pr --repo $R --number 7)"

echo "== board =="
new_case board-fails
serve board 1 '{"verdict":"unverified","head":null,"reasons":[{"code":"job-no-runner","run":1,"job":2,"name":"build","detail":"no runner"}]}'
out=$(run board --repo $R --sha $VH --base main)
expect "an unverified board fails, naming the job" '.verdict == "fails" and .detail == "build (no runner)" and .at == "'$VH'"' "$out"
grep -q "^board-verdict.sh --repo $R --sha $VH --base main$" "$CASE/log" && ok "the board check beside the script is called at the given sha" || bad "board check called" "$(cat "$CASE/log")"
new_case board-holds
serve board 1 '{"verdict":"verified","reasons":[]}'
expect "a verified board holds" '.verdict == "holds"' "$(run board --repo $R --sha $VH --base main)"
new_case board-pending
serve board 1 '{"verdict":"pending","reasons":[{"code":"run-pending","name":"ci"}]}'
expect "a pending board is pending" '.verdict == "pending"' "$(run board --repo $R --sha $VH --base main)"
new_case board-error
serve board 1 '{"verdict":"error:board-read","reasons":[]}'
expect "a board read error is not verified" '.status == "not_verified" and (.reason | test("board-read"))' "$(run board --repo $R --sha $VH --base main)"
new_case board-unknown
serve board 1 '{"verdict":"sideways","reasons":[]}'
expect "an unknown board verdict is not verified, never a failing board" '.status == "not_verified"' "$(run board --repo $R --sha $VH --base main)"
new_case board-env
serve board 1 '{"verdict":"unverified","reasons":[{"name":"x"}]}'
printf '#!/bin/sh\necho %s\n' "'{\"verdict\":\"verified\",\"reasons\":[]}'" > "$T/bin/fake-board"; chmod +x "$T/bin/fake-board"
out=$(RECONCILE_BOARD_CHECK="$T/bin/fake-board" run board --repo $R --sha $VH --base main)
expect "the environment can't choose which board check runs" '.verdict == "fails"' "$out"

echo "== branch =="
new_case branch-gone
serve ls-remote 1 ""
expect "an absent ref reads branch gone" '.state == "gone"' "$(run branch --repo $R --branch feat/x)"
grep -q "^git ls-remote https://github.com/$R.git refs/heads/feat/x$" "$CASE/log" && ok "ls-remote reads the row's repository URL" || bad "ls-remote reads the row's repository URL" "$(cat "$CASE/log")"
new_case branch-present
serve ls-remote 1 "$LH	refs/heads/feat/x"
expect "a present ref carries its tip" '.state == "present" and .tip == "'$LH'"' "$(run branch --repo $R --branch feat/x)"

echo "== appeared =="
new_case appeared-one
serve pr-list 1 '[{"number":9,"state":"OPEN","url":"https://github.com/acme/widgets/pull/9"}]'
expect "one pull request on the branch is listed" '(.prs | length) == 1 and .prs[0].number == 9' "$(run appeared --repo $R --branch feat/x)"
new_case appeared-two
serve pr-list 1 '[{"number":9,"state":"OPEN","url":"u9"},{"number":10,"state":"CLOSED","url":"u10"}]'
expect "two pull requests are both listed" '(.prs | length) == 2' "$(run appeared --repo $R --branch feat/x)"

echo "== files =="
new_case files
serve api-files 1 '[{"filename":"docs/a.md"},{"filename":"src/new.go","previous_filename":"src/old name.go"},{"filename":"odd\ttab"}]'
out=$(run files --repo $R --number 7)
expect "every path arrives intact through the real --jq program, rename sides and tabs included" '.paths == ["docs/a.md","src/new.go","src/old name.go","odd\ttab"] and .truncated == false' "$out"
grep -q 'per_page=100 --paginate' "$CASE/log" && ok "the file list is paginated" || bad "the file list is paginated" "$(cat "$CASE/log")"
new_case files-cap
serve api-files 1 "$(jq -nc '[range(1; 302) | {filename: "docs/\(.).md"}]')"
expect "past 300 paths the list says truncated" '(.paths | length) == 300 and .truncated == true' "$(run files --repo $R --number 7)"

echo "== merge =="
# cmp FILES-JSON -- a compare response with these files.
cmp() { printf '{"files":%s}' "$1"; }
merge_setup() {  # merge_setup <case> <compare-files-json>
    new_case "$1"
    serve api-pull 1 "$MERGED_PR"
    serve git-ref 1 "{\"object\":{\"sha\":\"$BN\"}}"
    serve compare 1 "$(cmp "$2")"
}
blob() { serve "contents-$1" "$2" "{\"sha\":\"$3\"}"; }
gone() { fail_with "contents-$1" "$2" 1 "gh: Not Found (HTTP 404)"; }

merge_setup merge-confirmed '[{"status":"modified","filename":"src/a.go"},{"status":"removed","filename":"src/gone.go"}]'
blob "$VH" 1 "$BA"; blob "$BN" 1 "$BA"; gone "$BN" 2
expect "matching files and a deletion absent on the base confirm the merge" '.verdict == "confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"
grep -q "compare/$BS...$VH" "$CASE/log" && ok "the file list is the verified head's own diff" || bad "the file list is the verified head's own diff" "$(cat "$CASE/log")"
grep -q "ref=main" "$CASE/log" && bad "contents are read by resolved sha, never by branch name" || ok "contents are read by resolved sha, never by branch name"

merge_setup merge-deletions-later '[{"status":"modified","filename":"src/a.go"},{"status":"removed","filename":"src/x.go"},{"status":"removed","filename":"src/y.go"}]'
blob "$VH" 1 "$BA"; blob "$BN" 1 "$BA"; gone "$BN" 2; gone "$BN" 3
expect "deletions after the first entry confirm too" '.verdict == "confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-moved '[{"status":"modified","filename":"src/a.go"}]'
blob "$VH" 1 "$BA"; blob "$BN" 1 "$BB"
out=$(run merge --repo $R --number 7 --verified-head $VH)
expect "a branch moved past the verified head reads not confirmed though merged" '.verdict == "not_confirmed" and (.reason | test("src/a.go"))' "$out"
grep -q "ref=$LH" "$CASE/log" && bad "never compares against the branch's current head" || ok "never compares against the branch's current head"

merge_setup merge-reverted '[{"status":"modified","filename":"src/a.go"},{"status":"modified","filename":"src/b.go"}]'
# src/b.go changed at the verified head and was reverted before the merge, so
# it isn't in the merged pull request's final diff; the compare list has it.
blob "$VH" 1 "$BA"; blob "$BN" 1 "$BA"; blob "$VH" 2 "$BA"; blob "$BN" 2 "$BB"
expect "a file reverted after the verified head reads not confirmed" '.verdict == "not_confirmed" and (.reason | test("src/b.go"))' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-rename '[{"status":"renamed","filename":"src/new.go","previous_filename":"src/old.go"}]'
blob "$BN" 1 "$BA"
expect "a rename's old path still on the base reads not confirmed" '.verdict == "not_confirmed" and (.reason | test("src/old.go"))' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-404-both '[{"status":"modified","filename":"src/a.go"}]'
gone "$VH" 1; gone "$BN" 1
expect "a changed file missing at both refs is not verified, never a match" '.status == "not_verified"' "$(run merge --repo $R --number 7 --verified-head $VH)"

new_case merge-base-gone
serve api-pull 1 "$MERGED_PR"
fail_with git-ref 1 1 "gh: Not Found (HTTP 404)"
serve compare 1 "$(cmp '[{"status":"removed","filename":"src/x.go"}]')"
out=$(run merge --repo $R --number 7 --verified-head $VH)
expect "a deleted base branch is not verified, never confirmed on 404s" '.status == "not_verified"' "$out"
grep -q contents "$CASE/log" && bad "no contents read without a resolved base" || ok "no contents read without a resolved base"

new_case merge-open
serve api-pull 1 "{\"state\":\"open\",\"merged\":false,\"base\":{\"ref\":\"main\",\"sha\":\"$BS\"}}"
expect "an unmerged pull request is not confirmed" '.verdict == "not_confirmed" and (.reason | test("open"))' "$(run merge --repo $R --number 7 --verified-head $VH)"
new_case merge-malformed
serve api-pull 1 '{}'
expect "a malformed pull request read is not verified" '.status == "not_verified"' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-deleted-still-there '[{"status":"removed","filename":"src/gone.go"}]'
blob "$BN" 1 "$BB"
expect "a file deleted at the verified head but on the base is not confirmed" '.verdict == "not_confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"

for bad_path in '../etc/passwd' '/abs/path' 'a//b' 'a/./b' 'x\ny' 'x\ty' 'x\u007fy'; do
    merge_setup merge-path "[{\"status\":\"modified\",\"filename\":\"$bad_path\"}]"
    out=$(run merge --repo $R --number 7 --verified-head $VH)
    if printf '%s' "$out" | jq -e '.status == "not_verified" and (.reason | test("refused a file path"))' >/dev/null \
       && ! grep -q contents "$CASE/log"; then
        ok "the path '$bad_path' is refused before any contents read"
    else bad "the path '$bad_path' is refused before any contents read" "$out | $(cat "$CASE/log")"; fi
done

merge_setup merge-encode '[{"status":"modified","filename":"docs/a b#c.md"}]'
blob "$VH" 1 "$BA"; blob "$BN" 1 "$BA"
run merge --repo $R --number 7 --verified-head $VH >/dev/null
grep -q 'contents/docs/a%20b%23c.md?ref=' "$CASE/log" && ok "a path is percent-encoded per segment" || bad "a path is percent-encoded per segment" "$(cat "$CASE/log")"

merge_setup merge-late '[{"status":"modified","filename":"src/a.go"}]'
echo 4 > "$CASE/contents-$VH.sleep.1"
expect "a late contents read says it timed out" '.status == "not_verified" and (.reason | test("timed out"))' "$(DL=1 run merge --repo $R --number 7 --verified-head $VH)"

echo "== host =="
LIST='[{"name":"tsuku+codex_test","path":"/w/tsuku+codex_test"},{"name":"tsuku+coordinate_reconcile-730e6b0e","path":"/w/tsuku+coordinate_reconcile-730e6b0e","session_name":"coordinate_reconcile-730e6b0e"},{"name":"tsuku+recon-11112222","path":"/w/tsuku+recon-11112222"}]'
new_case host-found
serve niwa-list 1 "$LIST"
expect "a worker is found by its topic's slug" '.state == "found" and .path == "/w/tsuku+coordinate_reconcile-730e6b0e"' "$(run host --topic coordinate-reconcile)"
new_case host-missed
serve niwa-list 1 "$LIST"
expect "a topic with no instance reads missed after one read" '.state == "missed" and .reads == 1' "$(run host --topic coordinate-dispatch)"
[ "$(grep -c '^niwa list' "$CASE/log")" = 1 ] && ok "host makes exactly one listing read and never sleeps" || bad "host makes one listing read" "$(cat "$CASE/log")"
new_case host-prefix
serve niwa-list 1 "$LIST"
expect "a topic that is a prefix of another's slug doesn't match it" '.state == "missed"' "$(run host --topic reco)"
new_case host-ambiguous
serve niwa-list 1 '[{"name":"a+x_y-11111111","path":"/w/a"},{"name":"b+x_y-22222222","path":"/w/b"}]'
expect "two instances for one topic are ambiguous" '.state == "ambiguous"' "$(run host --topic x-y)"
new_case host-fails
fail_with niwa-list 1 1 "boom"
expect "a failing workspace manager is not verified" '.status == "not_verified"' "$(run host --topic coordinate-reconcile)"
new_case host-garbage
serve niwa-list 1 'No instances found.'
expect "unparseable listing output is not verified" '.status == "not_verified"' "$(run host --topic coordinate-reconcile)"
new_case host-late
echo 4 > "$CASE/niwa-list.sleep.1"; serve niwa-list 1 "$LIST"
expect "a late listing read is not verified" '.status == "not_verified" and (.reason | test("timed out"))' "$(DL=1 run host --topic coordinate-reconcile)"
new_case host-absent
out=$(STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$T/nobin:/usr/bin:/bin" "$BASH" "$S" host --topic coordinate-reconcile 2>/dev/null)
expect "with no workspace manager on the host, host reads are not verified" '.status == "not_verified"' "$out"

echo "== teardown =="
W="$T/ws"; mkdir -p "$W/tsuku+keep-aaaaaaaa"
TLIST="[{\"name\":\"tsuku+keep-aaaaaaaa\",\"path\":\"$W/tsuku+keep-aaaaaaaa\"}]"
new_case teardown-done
serve niwa-list 1 "$TLIST"
expect "a topic absent from the listing and the disk is torn down" '.verdict == "confirmed"' "$(run teardown --topic gone-topic)"
new_case teardown-dir-left
mkdir -p "$W/tsuku+left_topic-bbbbbbbb"
serve niwa-list 1 "$TLIST"
expect "an instance directory still on disk is not confirmed" '.verdict == "not_confirmed" and (.reason | test("directory"))' "$(run teardown --topic left-topic)"
new_case teardown-listed
serve niwa-list 1 "$TLIST"
expect "a topic still listed is not confirmed" '.verdict == "not_confirmed" and (.reason | test("listed"))' "$(run teardown --topic keep)"

echo "== leg =="
REQ_JSON='{"request_id":"req1","request_state":"open","legs":{"deliver":{"name":"deliver","disposition":"resolved","bound_child":"deliver-x","result":{"status":"success","summary":"done","payload":{"outcome":"merged","step":null}},"result_source":"promoted"},"work-on":{"name":"work-on","disposition":"resolved","bound_child":"w","result":{"status":"success","summary":"completed at done"},"result_source":"promoted","result_final_state":"done"},"refused":{"name":"refused","disposition":"resolved","bound_child":null,"result":{"status":"failure","summary":"refused","payload":{"outcome":"error","reason":"var-mismatch:TOPIC"}},"result_source":"refused"},"waiting":{"name":"waiting","disposition":"open","bound_child":"w2","result":null,"result_source":null}}}'
new_case leg-deliver
serve koto-request 1 "$REQ_JSON"
expect "a deliver leg carries its outcome" '.disposition == "resolved" and .result == "merged"' "$(run leg --return-path 'leg req1:deliver')"
grep -q '^koto request get req1$' "$CASE/log" && ok "the leg is read with koto request get" || bad "the leg is read with koto request get" "$(cat "$CASE/log")"
new_case leg-workon
serve koto-request 1 "$REQ_JSON"
expect "a work-on leg carries the engine's status and final state" '.result == "success at done"' "$(run leg --return-path 'leg req1:work-on')"
new_case leg-refused
serve koto-request 1 "$REQ_JSON"
expect "a refused leg carries its reason" '.result == "refused:var-mismatch:TOPIC"' "$(run leg --return-path 'leg req1:refused')"
new_case leg-bound
serve koto-request 1 "$REQ_JSON"
expect "an open leg with a bound child reads bound" '.disposition == "bound" and .result == ""' "$(run leg --return-path 'leg req1:waiting')"
new_case leg-missing
serve koto-request 1 '{"error":{"code":"request_not_found","message":"x"}}'
fail_with koto-request 1 2
expect "a request not on this host is not verified" '.status == "not_verified" and (.reason | test("not found on this host"))' "$(run leg --return-path 'leg req9:deliver')"
new_case leg-message
expect "a message return path makes no request-store read" '.status == "not_verified"' "$(run leg --return-path message)"
[ -s "$CASE/log" ] && bad "a message return path makes no call" "$(cat "$CASE/log")" || ok "a message return path makes no call"
new_case leg-bad
expect "an invalid request id reaches no command" '.status == "not_verified"' "$(run leg --return-path 'leg ../x:deliver')"
[ -s "$CASE/log" ] && bad "an invalid request id makes no call" || ok "an invalid request id makes no call"

echo "== inventory =="
# A real clone in a temp instance. ls-remote is served; every other git call
# runs the real git. Contents reads are keyed by path.
I="$T/inst"; RP="$I/repo"; mkdir -p "$RP"
g() { git -C "$RP" -c user.email=t@example.com -c user.name=t "$@" >/dev/null 2>&1; }
g init -q -b main; g remote add origin https://github.com/acme/widgets.git
echo base > "$RP/x.txt"; echo keep > "$RP/k.txt"; g add -A; g commit -qm base
MAIN=$(git -C "$RP" rev-parse HEAD)
g checkout -qb pushed; echo p > "$RP/p.txt"; g add -A; g commit -qm p; PUSHED=$(git -C "$RP" rev-parse HEAD)
g checkout -q main; g checkout -qb deleted; echo d > "$RP/d.txt"; g add -A; g commit -qm d
g checkout -q main; g checkout -qb squashed; echo S > "$RP/x.txt"; g add -A; g commit -qm s
SBLOB=$(git -C "$RP" rev-parse squashed:x.txt)
g checkout -q main
echo changed > "$RP/k.txt"                       # a modified tracked file: unique
echo same > "$RP/landed.txt"                      # untracked, content on main: not unique
echo mine > "$RP/mine.txt"                        # untracked, unique
ln -s /etc/hostname "$RP/link-out"                # a symlink: listed, not read
g worktree add -q "$T/outside-wt" -b wt           # a worktree outside the instance
LANDED=$(git -C "$RP" hash-object --no-filters landed.txt)
# mktree REPO COMMIT [EXTRA-PATH SHA ...] -- the git/trees?recursive=1
# response for COMMIT, with extra path/blob pairs added, served on every call.
mktree() {
    local repo=$1 commit=$2
    shift 2
    { git -C "$repo" ls-tree -r "$commit" | awk -F'\t' '{ split($1, m, " "); print m[3] "\t" $2 }'
      while [ $# -ge 2 ]; do printf '%s\t%s\n' "$2" "$1"; shift 2; done
    } | jq -Rsc '{truncated: false, tree: [split("\n")[] | select(length > 0) | split("\t") | {path: .[1], type: "blob", sha: .[0]}]}' \
      > "$CASE/tree.out.all"
}
inv_case() {
    new_case "$1"
    printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n%s\trefs/heads/pushed\n' "$MAIN" "$MAIN" "$PUSHED" > "$CASE/ls-remote.out.1"
    # The default branch as GitHub has it: main, with the squashed branch's
    # x.txt landed and landed.txt added.
    mktree "$RP" "$MAIN" x.txt "$SBLOB" landed.txt "$LANDED"
}
cksum < "$RP/.git/index" > "$T/idx-before"
inv_case inventory
out=$(run inventory --path "$I")
expect "the inventory is taken" '.kind == "inventory" and .status == "ok" and .taken == true' "$out"
expect "a branch deleted on the remote is unique" '[.items[] | select(.kind == "commit") | .path] | index("branch deleted") != null' "$out"
expect "a pushed branch is not unique" '[.items[] | select(.kind == "commit") | .path] | index("branch pushed") == null' "$out"
expect "a squash-landed branch is not unique" '[.items[] | select(.kind == "commit") | .path] | index("branch squashed") == null' "$out"
expect "a modified tracked file is unique" '[.items[] | .path] | index("k.txt") != null' "$out"
expect "an untracked file whose content is on main is not unique" '[.items[] | .path] | index("landed.txt") == null' "$out"
expect "an untracked unique file is listed" '[.items[] | .path] | index("mine.txt") != null' "$out"
expect "a symlink is listed, not read" '[.items[] | .path] | any(startswith("link-out (symlink"))' "$out"
expect "a worktree outside the instance is listed, not read" '[.items[] | select(.kind == "worktree")] | length == 1' "$out"
expect "paths are clone-relative" '[.items[] | .clone, .path] | all(startswith("/") | not)' "$out"
ALOG="$CASE/log"
grep -qE '^git .* (fetch|pull|push|checkout|commit|reset|add|stash|gc|update-index|update-ref|config [^-]|config --(add|unset|replace))( |$)' "$ALOG" && bad "the inventory never writes in the clone" "$(grep -E ' (fetch|pull|push|checkout|commit|reset|add) ' "$ALOG")" || ok "the inventory never writes in the clone"
grep -E '^git ' "$ALOG" | grep -vE -- '--no-optional-locks -c core\.fsmonitor= -c core\.hooksPath=/dev/null -c protocol\.allow=never' | grep -q . && bad "every in-clone git call is lock-free and hook-free" "$(grep -E '^git ' "$ALOG" | grep -v -- '--no-optional-locks')" || ok "every in-clone git call is lock-free and hook-free"
grep -q 'hash-object --no-filters --stdin-paths' "$ALOG" && ! grep -qE 'hash-object.* -w( |$)' "$ALOG" && ok "hash-object runs unfiltered and never writes" || bad "hash-object runs unfiltered and never writes"
grep -qE '^git .* status( |$)' "$ALOG" && bad "git status is never run" || ok "git status is never run"
[ "$(cat "$T/idx-before")" = "$(cksum < "$RP/.git/index")" ] && ok "the clone's index is untouched" || bad "the clone's index is untouched"

new_case inventory-missing
expect "a missing instance directory: inventory not taken" '.status == "not_verified" and (.reason | test("not found"))' "$(run inventory --path "$T/no-such-instance")"
mkdir -p "$T/linkdir-target"; ln -s "$T/linkdir-target" "$T/linked-instance"
new_case inventory-symlinked
expect "a symlinked instance path is not followed" '.status == "not_verified"' "$(run inventory --path "$T/linked-instance")"
new_case inventory-no-remote
I2="$T/inst2"; mkdir -p "$I2/r"; git -C "$I2/r" init -q; git -C "$I2/r" remote add origin https://gitlab.example/x/y.git
expect "a clone with no github.com origin is marked unchecked" '.items | any(.kind == "unchecked")' "$(run inventory --path "$I2")"

echo "== inventory: panel cases =="
# A clean filter the clone's config names must never run.
I3="$T/inst3"; R3="$I3/repo"; mkdir -p "$R3"
g3() { git -C "$R3" -c user.email=t@example.com -c user.name=t "$@" >/dev/null 2>&1 || echo "setup failed: git $*" >&2; }
g3 init -q -b main; g3 remote add origin https://github.com/acme/widgets.git
printf '*.txt filter=probe\n' > "$R3/.gitattributes"; echo a > "$R3/a.txt"
g3 add -A; g3 commit -qm a
M3=$(git -C "$R3" rev-parse HEAD)
g3 checkout -q --detach                          # a detached HEAD with its own commit
echo det > "$R3/det.md"; g3 add det.md; g3 commit -qm det
echo stashme > "$R3/s.md"; g3 add s.md; g3 stash -q
mkdir -p "$R3/.claude/worktrees"; g3 worktree add -q "$R3/.claude/worktrees/deep" -b deep "$M3"
echo deepwork > "$R3/.claude/worktrees/deep/work.md"
mkdir -p "$R3/vendor/inner"; git -C "$R3/vendor/inner" init -q; git -C "$R3/vendor/inner" remote add origin https://github.com/acme/inner.git
echo inner > "$R3/vendor/inner/i.md"
# Last: a clean filter the clone's config names, and a same-size edit under
# it, so git has to hash the file to see the change.
git -C "$R3" config filter.probe.clean "touch $T/FILTER-RAN; cat"
git -C "$R3" config filter.probe.required true
sleep 1; echo c > "$R3/a.txt"
rm -f "$T/FILTER-RAN"
new_case inventory-probe
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M3" "$M3" > "$CASE/ls-remote.out.1"
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M3" "$M3" > "$CASE/ls-remote.out.2"
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M3" "$M3" > "$CASE/ls-remote.out.3"
mktree "$R3" "$M3"
out=$(run inventory --path "$I3")
[ ! -e "$T/FILTER-RAN" ] && ok "a clean filter the clone's config names never runs" || bad "a clean filter the clone's config names never runs" "$out"
expect "a same-size edit under a filter is still found" '[.items[] | .path] | index("a.txt") != null' "$out"
expect "a detached HEAD's commit is unique" '[.items[] | select(.kind == "commit") | .path] | index("detached HEAD") != null' "$out"
expect "a stash is listed" '[.items[] | .path] | any(startswith("stash ("))' "$out"
expect "a worktree deep inside the instance is walked" '[.items[] | select(.clone | test("worktrees/deep")) | .path] | index("work.md") != null' "$out"
expect "a nested repository is walked as a clone" '[.items[] | select(.clone | test("vendor/inner"))] | length > 0' "$out"

# Truncation: more clones than the cap, the last one holding the only work.
I4="$T/inst4"; mkdir -p "$I4"
for k in $(seq -w 1 21); do
    git -C "$I4" init -q -b main "r$k" >/dev/null 2>&1
    git -C "$I4/r$k" remote add origin https://github.com/acme/widgets.git
done
echo late > "$I4/r21/late.txt"
new_case inventory-cap
for k in $(seq 1 21); do printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M3" > "$CASE/ls-remote.out.$k"; done
mktree "$R3" "$M3"
out=$(run inventory --path "$I4")
expect "past the clone cap the inventory says truncated" '.truncated == true' "$out"
rep=$(jq -nc --argjson inv "$out" '{schema: "coordinate-reconcile-facts/v1", scope: {kind: "roadmap", name: "d", repo: "acme/widgets"},
  record: {written: "2026-09-26T10:00:00Z"}, reconciled_at: "2026-09-27T10:00:00Z", reasoning: null, unparseable: [], side_effects: [], deferrals: [],
  holdings: [{row: {worker: "w", pull_request: "none yet"}, refused: null, facts: [{kind: "host", status: "ok", state: "found"}, $inv]}]}' \
  | bash "$HERE/reconcile-report.sh" md)
printf '%s' "$rep" | grep -q 'not everything was read' && ok "a truncated empty inventory never reads 'nothing unique found'" || bad "a truncated empty inventory never reads 'nothing unique found'" "$rep"

# Many live refs: a pushed branch whose own ref sorts late is still pushed.
I5="$T/inst5"; R5="$I5/repo"; mkdir -p "$R5"
git -C "$R5" init -q -b main; git -C "$R5" remote add origin https://github.com/acme/widgets.git
echo a > "$R5/a"; git -C "$R5" add -A; git -C "$R5" -c user.email=t@e -c user.name=t commit -qm a
M5=$(git -C "$R5" rev-parse HEAD)
git -C "$R5" checkout -qb feature; echo f > "$R5/f"; git -C "$R5" add -A; git -C "$R5" -c user.email=t@e -c user.name=t commit -qm f
F5=$(git -C "$R5" rev-parse HEAD); git -C "$R5" checkout -q main
new_case inventory-refs
{ printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M5"
  for k in $(seq 1 600); do printf '%040x\trefs/pull/%s/head\n' "$k" "$k"; done
  printf '%s\trefs/heads/feature\n' "$F5"; } > "$CASE/ls-remote.out.1"
mktree "$R5" "$M5"
out=$(run inventory --path "$I5")
expect "a pushed branch is pushed however many refs the remote has" '[.items[] | select(.kind == "commit")] | length == 0' "$out"

echo "== inventory: what git status would hide =="
I6="$T/inst6"; R6="$I6/repo"; mkdir -p "$R6"
g6() { git -C "$R6" -c user.email=t@example.com -c user.name=t "$@" >/dev/null 2>&1 || echo "setup failed: git $*" >&2; }
g6 init -q -b main; g6 remote add origin https://github.com/acme/widgets.git
for f in staged.txt skip.txt assume.txt same.txt; do echo orig > "$R6/$f"; done
printf 'build/\n' > "$R6/.gitignore"
g6 add -A; g6 commit -qm base
M6=$(git -C "$R6" rev-parse HEAD)
g6 tag -a -m t local-tag; echo tagged > "$R6/t.md"; g6 add t.md; g6 commit -qm t; g6 tag only-tag; g6 reset -q --hard "$M6"
g6 tag -d local-tag
echo staged-only > "$R6/staged.txt"; g6 add staged.txt; echo orig > "$R6/staged.txt"   # MM: index differs, file restored
g6 update-index --skip-worktree skip.txt; echo edited > "$R6/skip.txt"
g6 update-index --assume-unchanged assume.txt; echo edited > "$R6/assume.txt"
mkdir -p "$R6/build/deps/deeper/other"; OTH="$R6/build/deps/deeper/other"
git -C "$OTH" init -q -b main; git -C "$OTH" remote add origin https://github.com/acme/other.git
echo o > "$OTH/o.md"; git -C "$OTH" add -A; git -C "$OTH" -c user.email=t@e -c user.name=t commit -qm o
new_case inventory-hidden
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M6" "$M6" > "$CASE/ls-remote.out.all"
mktree "$R6" "$M6"
out=$(run inventory --path "$I6")
expect "a staged change whose file was restored is unique" '[.items[] | .path] | index("staged.txt") != null' "$out"
expect "an edit to a skip-worktree file is unique" '[.items[] | .path] | index("skip.txt") != null' "$out"
expect "an edit to an assume-unchanged file is unique" '[.items[] | .path] | index("assume.txt") != null' "$out"
expect "an unchanged tracked file is not listed" '[.items[] | .path] | index("same.txt") == null' "$out"
expect "a commit reachable only from a local tag is unique" '[.items[] | select(.kind == "commit") | .path] | index("tag only-tag") != null' "$out"
expect "a clone deep inside an ignored directory is walked" '[.items[] | select(.clone | test("build/deps/deeper/other")) | select(.kind == "commit")] | length == 1' "$out"
grep -qE '^git .* status( |$)' "$CASE/log" && bad "no git status anywhere" || ok "no git status anywhere"

echo "== inventory: containment =="
I7="$T/inst7"; mkdir -p "$I7" "$T/elsewhere"
git -C "$T/elsewhere" init -q real
ln -s "$T/elsewhere/real/.git" "$I7/.git-link-target" 2>/dev/null
mkdir -p "$I7/r"; ln -s "$T/elsewhere/real/.git" "$I7/r/.git"
new_case inventory-gitlink
out=$(run inventory --path "$I7")
expect "a clone whose .git is a symlink out of the instance is unchecked" '.items | any(.kind == "unchecked" and (.path | test("symlink")))' "$out"
I8="$T/inst8"; mkdir -p "$I8/r" "$T/wt-elsewhere"
git -C "$I8/r" init -q -b main; git -C "$I8/r" remote add origin https://github.com/acme/widgets.git
git -C "$I8/r" config core.worktree "$T/wt-elsewhere"
new_case inventory-coreworktree
printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M6" > "$CASE/ls-remote.out.all"
mktree "$R6" "$M6"
out=$(run inventory --path "$I8")
expect "a clone whose working tree is set outside is unchecked" '.items | any(.kind == "unchecked" and (.path | test("core.worktree")))' "$out"

echo "== inventory: round-3 cases =="
I9="$T/inst9"; R9="$I9/repo"; mkdir -p "$R9"
g9() { git -C "$R9" -c user.email=t@example.com -c user.name=t "$@" >/dev/null 2>&1 || echo "setup failed: git $*" >&2; }
g9 init -q -b main; g9 remote add origin https://github.com/acme/widgets.git
printf 'a\n' > "$R9/keep.txt"; printf 'a\n' > "$R9/gone.txt"; printf 'a\n' > "$R9/	lead.txt"; printf 'a\n' > "$R9/trail.txt	"
ln -s keep.txt "$R9/link"
printf 'ignored/\n' > "$R9/.gitignore"
g9 add -A; g9 commit -qm base
M9=$(git -C "$R9" rev-parse HEAD)
g9 rm -q gone.txt                                   # a staged deletion
printf 'b\n' > "$R9/	lead.txt"; printf 'b\n' > "$R9/trail.txt	"   # edits to tab-edged paths
D="$R9/ignored/a/b/c/d/e/f/g/h/deep"; mkdir -p "$D"
git -C "$D" init -q -b main; git -C "$D" remote add origin https://github.com/acme/deep.git
echo z > "$D/z.md"; git -C "$D" add -A; git -C "$D" -c user.email=t@e -c user.name=t commit -qm z

new_case inventory-r3
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M9" "$M9" > "$CASE/ls-remote.out.all"
# GitHub truncated the tree: it holds keep.txt and link only, so gone.txt
# has to be asked of the contents API, which says it's on main.
git -C "$R9" ls-tree -r "$M9" | awk -F'\t' '$2 == "keep.txt" || $2 == "link" { split($1, m, " "); print m[3] "\t" $2 }' \
  | jq -Rsc '{truncated: true, tree: [split("\n")[] | select(length > 0) | split("\t") | {path: .[1], type: "blob", sha: .[0]}]}' > "$CASE/tree.out.all"
printf '{"sha":"%s"}' "$(git -C "$R9" rev-parse "$M9:gone.txt")" > "$CASE/contents@$M9@gone.txt"
out=$(run inventory --path "$I9")
expect "a staged deletion is found when the tree is truncated" '[.items[] | .path] | index("gone.txt (deleted)") != null' "$out"
expect "an edit to a path with a leading tab is found" '[.items[] | .path] | index("\tlead.txt") != null' "$out"
expect "an edit to a path with a trailing tab is found" '[.items[] | .path] | index("trail.txt\t") != null' "$out"
expect "an unchanged tracked symlink is not listed" '[.items[] | .path] | any(startswith("link")) | not' "$out"
expect "a clone ten levels down inside an ignored directory is walked" '[.items[] | select(.clone | test("ignored/a/b/c/d/e/f/g/h/deep"))] | length > 0' "$out"
grep -q '^git .* -C / .*ls-remote' "$CASE/log" && ok "ls-remote runs outside any repository" || bad "ls-remote runs outside any repository" "$(grep ls-remote "$CASE/log")"

new_case inventory-hang
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M9" "$M9" > "$CASE/ls-remote.out.all"
mktree "$R9" "$M9"
# A git that hangs on ls-files: the clone is unchecked, never empty.
mkdir -p "$T/hangbin"
cat > "$T/hangbin/git" <<HANG
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = ls-files ] && sleep 30; done
exec "$T/bin/git" "\$@"
HANG
chmod +x "$T/hangbin/git"
start=$(date +%s)
out=$(STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$T/hangbin:$T/bin:$PATH" RECONCILE_READ_DEADLINE=2 "$BASH" "$S" inventory --path "$I9" 2>/dev/null)
took=$(( $(date +%s) - start ))
expect "an in-clone git read past its deadline marks the clone unchecked" '.items | any(.kind == "unchecked" and .clone == "repo")' "$out"
[ "$took" -le 20 ] && ok "a hanging in-clone read is ended by the deadline (${took}s)" || bad "a hanging in-clone read is ended by the deadline" "took ${took}s"

I10="$T/inst10"; R10="$I10/repo"; mkdir -p "$R10"
git -C "$R10" init -q -b main; git -C "$R10" remote add origin https://github.com/acme/widgets.git
echo a > "$R10/a"; git -C "$R10" add -A; git -C "$R10" -c user.email=t@e -c user.name=t commit -qm a
M10=$(git -C "$R10" rev-parse HEAD)
for k in $(seq 1 230); do echo "$k" > "$R10/u$k.md"; done
new_case inventory-items-cap
printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M10" > "$CASE/ls-remote.out.all"
mktree "$R10" "$M10"
out=$(run inventory --path "$I10")
expect "past the item and file caps the inventory says truncated" '.truncated == true and (.items | length) <= 200' "$out"

echo "== close =="
new_case close-closed
serve issue-view 1 '{"state":"CLOSED"}'
expect "a closed target confirms the close" '.verdict == "confirmed"' "$(run close --repo $R --kind issue --number 3)"
new_case close-merged
serve pr-view 1 '{"state":"MERGED"}'
expect "a merged pull request confirms a close" '.verdict == "confirmed"' "$(run close --repo $R --kind pr --number 3)"
new_case close-open
serve pr-view 1 '{"state":"OPEN"}'
expect "an open target does not" '.verdict == "not_confirmed"' "$(run close --repo $R --kind pr --number 3)"

echo "== deferral =="
ROW="$T/row.json"
echo '{"deferral":"d","reason":"r","raised":"2026-09-20","disposition":"filed #5"}' > "$ROW"
RS=2026-09-27T00:00:00Z
new_case deferral-filed
serve deferral 1 "disposed filed 5"
serve issue-view 1 '{"number":5}'
expect "a filed deferral whose issue exists is disposed" '.disposed == true and .how == "filed #5"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-filed-missing
serve deferral 1 "disposed filed 5"
fail_with issue-view 1 1 "GraphQL: Could not resolve to an issue"
expect "a filed deferral whose issue can't be read is not verified" '.status == "not_verified"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-closed
serve deferral 1 "disposed closed"
expect "a closed deferral is disposed" '.disposed == true and .how == "closed"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-carried
serve deferral 1 "disposed carried 2026-09-27T01:00:00Z"
expect "a carried deferral is disposed" '.disposed == true and (.how | startswith("carried"))' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-this-run
serve deferral 1 "undisposed raised-this-run"
expect "a deferral raised this run isn't the predecessor's to dispose of" '.disposed == true and .how == "raised this run"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-open
serve deferral 1 "undisposed empty"
fail_with deferral 1 1
expect "an undisposed deferral is undisposed" '.disposed == false and .how == "empty"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"
new_case deferral-two-lines
serve deferral 1 "$(printf 'disposed closed\ndisposed filed 9')"
expect "a two-line disposal answer is not verified" '.status == "not_verified"' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"

echo "== bad row values reach no command =="
for args in "pr --repo a;b --number 1" "pr --repo -x/y --number 1" "pr --repo acme/widgets --number 0" "branch --repo acme/widgets --branch -x" "branch --repo acme/widgets --branch a;b" "board --repo acme/widgets --sha nothex --base main" "merge --repo acme/widgets --number 7 --verified-head nothex"; do
    new_case bad
    # shellcheck disable=SC2086
    out=$(run $args)
    if printf '%s' "$out" | jq -e '.status == "not_verified"' >/dev/null && [ ! -s "$CASE/log" ]; then
        ok "refused before any call: $args"
    else bad "refused before any call: $args" "$out $(cat "$CASE/log")"; fi
done

echo "== deadlines and failures =="
new_case slow
echo 6 > "$CASE/pr-view.sleep.1"
serve pr-view 1 '{"state":"OPEN"}'
start=$(date +%s)
out=$(DL=1 run pr --repo $R --number 7)
took=$(( $(date +%s) - start ))
expect "a read past its deadline is not verified, with the reason" '.status == "not_verified" and (.reason | test("timed out"))' "$out"
[ "$took" -le 3 ] && ok "a forking command is ended at its deadline (${took}s for 1s)" || bad "a forking command is ended at its deadline" "took ${took}s"
for sub in "appeared --repo $R --branch x:pr-list" "branch --repo $R --branch x:ls-remote" "files --repo $R --number 7:api-files" "close --repo $R --kind issue --number 3:issue-view" "board --repo $R --sha $VH --base main:board"; do
    args=${sub%:*}; key=${sub##*:}
    new_case fail
    fail_with "$key" 1 1 "boom"
    # shellcheck disable=SC2086
    out=$(run $args)
    expect "a failed $key read is not verified" '.status == "not_verified" and (.reason | test("failed"))' "$out"
    new_case late
    echo 4 > "$CASE/$key.sleep.1"
    # shellcheck disable=SC2086
    out=$(DL=1 BDL=1 run $args)
    expect "a late $key read is not verified" '.status == "not_verified" and (.reason | test("timed out"))' "$out"
done

echo "== read-only =="
ALL="$T/all.log"
cat "$T"/case-*/log > "$ALL"
[ "$(wc -l < "$ALL" | tr -d ' ')" -gt 40 ] && ok "the read-only check sees every case's calls" || bad "the read-only check sees every case's calls"
ALLOW='^(gh pr view [0-9]+ --repo [^ ]+ --json [a-zA-Z,]+|gh pr list --repo [^ ]+ --head [^ ]+ --state all --json [a-z,]+|gh issue view [0-9]+ --repo [^ ]+ --json [a-z]+|gh api repos/[^ ]+ --jq .*|gh api repos/[^ ]+ --paginate --jq .*|git ls-remote https://github\.com/[^ ]+\.git refs/heads/[^ ]+|board-verdict\.sh --repo [^ ]+ --sha [0-9a-f]{40} --base [^ ]+|deferral-check\.sh --row-file [^ ]+ --run-start [^ ]+|niwa list --json|koto request get [a-z0-9_-]+|git --no-optional-locks -c core\.fsmonitor= -c core\.hooksPath=/dev/null -c protocol\.allow=never (-C / -c protocol\.https\.allow=always ls-remote --symref https://github\.com/[^ ]+\.git|-C [^ ]+ (config --get remote\.origin\.url|rev-parse --path-format=absolute --git-common-dir --show-toplevel|cat-file --batch-check=.*|cat-file -e [0-9a-f]{40}\^\{commit\}|symbolic-ref -q HEAD|rev-parse --verify --quiet .*|rev-list --stdin --count|rev-list --walk-reflogs --count refs/stash|merge-base [0-9a-f]{40} [0-9a-f]{40}|diff --name-only -z [0-9a-f]{40} [0-9a-f]{40}|for-each-ref refs/heads refs/tags --format=.*|ls-files -z -s -v|hash-object --stdin|ls-files -z --others --exclude-standard|ls-tree -r -z --full-tree HEAD|hash-object --no-filters --stdin-paths|worktree list --porcelain)))$'
off=$(grep -vE "$ALLOW" "$ALL" || true)
[ -z "$off" ] && ok "every call matches the read allowlist" || bad "every call matches the read allowlist" "$off"
grep -qE ' (-f|-F|--field|--raw-field|--input|--method|-X) ' "$ALL" && bad "no gh api write flags" "$(grep -E ' (-f|-F|--field|--raw-field|--input|--method|-X) ' "$ALL")" || ok "no gh api write flags anywhere"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
