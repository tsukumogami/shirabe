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
cp "$HERE"/reconcile-check.sh "$HERE"/reconcile-deps.sh "$HERE"/github-refs.sh "$T/tree/skills/coordinate/scripts/"
# The record feature's merge check and what it sources, which the merge
# subcommand calls rather than copies.
cp "$HERE"/board-lib.sh "$HERE"/record-common.sh "$T/tree/skills/coordinate/scripts/"
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
    # A private repository (the case holds a "private" file) answers ls-remote
    # only when the call's own credential config yields the gh login's token,
    # the way GitHub answers one over https; otherwise git's own failure.
    if [ -f "$STUB_DIR/private" ]; then
        cfg=(); prev=""
        for a in "$@"; do [ "$prev" = -c ] && cfg+=(-c "$a"); prev=$a; done
        # Only the call's own flags may answer: no config of the developer's,
        # and no prompt, so a call without the gh helper fails rather than hangs.
        cred=$(printf 'protocol=https\nhost=github.com\n\n' | HOME="$STUB_DIR" XDG_CONFIG_HOME="$STUB_DIR" GIT_CONFIG_NOSYSTEM=1 \
            GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= SSH_ASKPASS= "$REAL_GIT" ${cfg[@]+"${cfg[@]}"} credential fill 2>&1) \
            || { printf '%s\n' "$cred" >&2; exit 128; }
        case "$cred" in
            *password=gh-login-token*) ;;
            *) echo "fatal: Authentication failed for 'https://github.com/'" >&2; exit 128 ;;
        esac
    fi
fi
# gh as git's credential helper: the gh login's token, unless the case says
# the login can't read the repository (a "gh-auth-fail" file).
if [ "$name" = gh ] && [ "$1 ${2-}" = "auth git-credential" ]; then
    cat > /dev/null
    [ -f "$STUB_DIR/gh-auth-fail" ] && exit 1
    [ "${3-}" = get ] && printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=gh-login-token\n'
    exit 0
fi
# board-lib.sh reads with `gh api --method GET <path>`: match on the path.
if [ "$name" = gh ] && [ "$1" = api ] && [ "${2-}" = --method ]; then
    shift 3; set -- api "$@"
fi
# Contents reads keyed by ref and path, when the case serves them that way.
if [ "$name" = gh ] && [ "$1" = api ]; then
    case "$2" in */contents/*"?ref="*)
        p=${2#*/contents/}; ref=${p##*\?ref=}; p=${p%%\?ref=*}
        f="$STUB_DIR/contents@$ref@$(printf '%s' "$p" | tr '/' '_')"
        if [ -f "$f" ]; then
            case " $* " in *" --jq "*) jq -r .sha < "$f" ;; *) cat "$f" ;; esac
            exit 0
        fi
        if ls "$STUB_DIR"/contents@* >/dev/null 2>&1; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
    ;; esac
fi
# Compare reads keyed by base and head, when the case serves them that way
# (a missing pair is GitHub's 404 for a commit it doesn't have).
if [ "$name" = gh ] && [ "$1" = api ]; then
    case "$2" in */compare/*...*)
        if ls "$STUB_DIR"/cmp@* >/dev/null 2>&1; then
            p=${2##*/compare/}; f="$STUB_DIR/cmp@${p%%...*}@${p##*...}"
            if [ -f "$f" ]; then jq -r '.behind_by' < "$f"; exit 0; fi
            echo "gh: Not Found (HTTP 404)" >&2; exit 1
        fi
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
    gh:api:repos/*) key=api-repo ;;
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
new_case board-not-run
serve board 1 '{"verdict":"not-run","reasons":[{"code":"job-not-run","run":1,"job":2,"name":"Validate PR body","detail":"The job was not started because recent account payments have failed or your spending limit needs to be increased."}]}'
expect "a board whose job never ran is not run, naming the job and GitHub's reason, never failing (shirabe#564)" \
    '.status == "ok" and .verdict == "not-run" and (.detail | startswith("Validate PR body (The job was not started"))' "$(run board --repo $R --sha $VH --base main)"
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
grep -q "^git .* -C / .*ls-remote --symref https://github.com/$R.git refs/heads/feat/x$" "$CASE/log" && ok "ls-remote reads the row's repository URL, from outside any repository" || bad "ls-remote reads the row's repository URL, from outside any repository" "$(cat "$CASE/log")"
new_case branch-present
serve ls-remote 1 "$LH	refs/heads/feat/x"
expect "a present ref carries its tip" '.state == "present" and .tip == "'$LH'"' "$(run branch --repo $R --branch feat/x)"
# A private repository: https answers only with the gh login's credential.
new_case branch-private
: > "$CASE/private"
serve ls-remote 1 "$LH	refs/heads/feat/x"
expect "a private repository's branch reads through the gh login" '.status == "ok" and .state == "present" and .tip == "'$LH'"' "$(run branch --repo $R --branch feat/x)"
grep -q '^gh auth git-credential get$' "$CASE/log" && ok "the branch read authenticates with the gh login" || bad "the branch read authenticates with the gh login" "$(cat "$CASE/log")"
new_case branch-private-denied
: > "$CASE/private"; : > "$CASE/gh-auth-fail"
serve ls-remote 1 "$LH	refs/heads/feat/x"
expect "a private branch the gh login can't read is not verified, never gone, with git's reason" '.status == "not_verified" and (.reason | test("^read failed \\(exit 128\\): fatal: (could not read Username|unable to get password)"))' "$(run branch --repo $R --branch feat/x)"

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
# The merge subcommand is the record feature's bl_merge_compare: the pull
# request's state and final file list, then each file's blob on the default
# branch and at the verified head.
merge_setup() {  # merge_setup <case> <state> <paths-json>
    new_case "$1"
    serve pr-view 1 "$(jq -nc --arg s "$2" --argjson p "$3" '{state: $s, files: ($p | map({path: .}))}')"
    serve api-repo 1 '{"default_branch":"main"}'
}
# at REF PATH BLOB -- the contents read of PATH at REF answers BLOB.
at() { printf '{"type":"file","sha":"%s"}' "$3" > "$CASE/contents@$1@$(printf '%s' "$2" | tr '/' '_')"; }
# A contents read with no file served for its ref and path is GitHub's 404.

merge_setup merge-confirmed MERGED '["src/a.go","src/gone.go"]'
at main src/a.go "$BA"; at "$VH" src/a.go "$BA"
expect "matching files and a deletion absent on the default branch confirm the merge" '.kind == "merge" and .status == "ok" and .verdict == "confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"
grep -q "gh pr view 7 --repo $R --json state,files" "$CASE/log" && ok "the file list is the merged pull request's own" || bad "the file list is the merged pull request's own" "$(cat "$CASE/log")"
grep -q "contents/src/a.go?ref=$VH" "$CASE/log" && grep -q "contents/src/a.go?ref=main" "$CASE/log" \
    && ok "each file is read at the verified head and on the default branch" || bad "each file is read at the verified head and on the default branch" "$(cat "$CASE/log")"
grep -E '^gh api' "$CASE/log" | grep -v -- '--method GET' && bad "every API call is a GET" || ok "every API call is a GET"

merge_setup merge-differs MERGED '["src/a.go"]'
at main src/a.go "$BB"; at "$VH" src/a.go "$BA"
expect "a file whose default-branch content differs from the verified head is not confirmed" '.verdict == "not_confirmed" and (.reason | test("default branch"))' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-deleted-still-there MERGED '["src/gone.go"]'
at main src/gone.go "$BB"
expect "a file deleted at the verified head but still on the default branch is not confirmed" '.verdict == "not_confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-open OPEN '["src/a.go"]'
expect "an unmerged pull request is not confirmed" '.verdict == "not_confirmed" and (.reason | test("not merged"))' "$(run merge --repo $R --number 7 --verified-head $VH)"
grep -q contents "$CASE/log" && bad "no contents read for an unmerged pull request" || ok "no contents read for an unmerged pull request"

merge_setup merge-odd-state WEIRD '[]'
expect "a pull request state it doesn't know is not verified" '.status == "not_verified"' "$(run merge --repo $R --number 7 --verified-head $VH)"

new_case merge-read-fails
fail_with pr-view 1 1 "gh: server error"; fail_with pr-view 2 1 "gh: server error"
expect "a failed pull request read is not verified, never confirmed" '.status == "not_verified" and .kind == "merge"' "$(run merge --repo $R --number 7 --verified-head $VH)"

merge_setup merge-encode MERGED '["docs/a b#c.md"]'
at main 'docs/a%20b%23c.md' "$BA"; at "$VH" 'docs/a%20b%23c.md' "$BA"
run merge --repo $R --number 7 --verified-head $VH >/dev/null
grep -q 'contents/docs/a%20b%23c.md?ref=' "$CASE/log" && ok "a path is percent-encoded per segment" || bad "a path is percent-encoded per segment" "$(cat "$CASE/log")"

echo "== host =="
# h8 C -- eight C's: the instance names' hex suffixes are built here rather
# than written out, so no file carries a literal instance name.
h8() { printf '%s' "$1$1$1$1$1$1$1$1"; }
A8=$(h8 a); B8=$(h8 b); C8=$(h8 c); D8=$(h8 d); E8=$(h8 e)
LIST="[{\"name\":\"ws+codex_test\",\"path\":\"/w/ws+codex_test\"},{\"name\":\"ws+coordinate_reconcile-$A8\",\"path\":\"/w/ws+coordinate_reconcile-$A8\",\"session_name\":\"coordinate_reconcile-$A8\"},{\"name\":\"ws+recon-$B8\",\"path\":\"/w/ws+recon-$B8\"}]"
new_case host-found
serve niwa-list 1 "$LIST"
expect "a worker is found by its topic's slug" ".state == \"found\" and .path == \"/w/ws+coordinate_reconcile-$A8\"" "$(run host --topic coordinate-reconcile)"
new_case host-missed
serve niwa-list 1 "$LIST"
expect "a topic with no instance reads missed after one read" '.state == "missed" and .reads == 1' "$(run host --topic coordinate-dispatch)"
[ "$(grep -c '^niwa list' "$CASE/log")" = 1 ] && ok "host makes exactly one listing read and never sleeps" || bad "host makes one listing read" "$(cat "$CASE/log")"
new_case host-prefix
serve niwa-list 1 "$LIST"
expect "a topic that is a prefix of another's slug doesn't match it" '.state == "missed"' "$(run host --topic reco)"
new_case host-ambiguous
serve niwa-list 1 "[{\"name\":\"a+x_y-$C8\",\"path\":\"/w/a\"},{\"name\":\"b+x_y-$D8\",\"path\":\"/w/b\"}]"
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
W="$T/ws"; mkdir -p "$W/ws+keep-$E8"
TLIST="[{\"name\":\"ws+keep-$E8\",\"path\":\"$W/ws+keep-$E8\"}]"
new_case teardown-done
serve niwa-list 1 "$TLIST"
expect "a topic absent from the listing and the disk is torn down" '.verdict == "confirmed"' "$(run teardown --topic gone-topic)"
new_case teardown-dir-left
mkdir -p "$W/ws+left_topic-$B8"
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
od -An -tx1 < "$RP/.git/index" > "$T/idx-before"
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
[ "$(cat "$T/idx-before")" = "$(od -An -tx1 < "$RP/.git/index")" ] && ok "the clone's index is untouched" || bad "the clone's index is untouched"

# A private repository: https answers only with the gh login's credential, so
# the clone reads as it would in a public one.
inv_case inventory-private
: > "$CASE/private"
out=$(run inventory --path "$I")
expect "a private clone's remote refs read through the gh login" '.status == "ok" and ([.items[] | select(.kind == "unchecked")] | length == 0)' "$out"
expect "a private clone is judged by content like any other" '[.items[] | select(.kind == "commit") | .path] | (index("branch deleted") != null and index("branch pushed") == null)' "$out"
grep -q '^gh auth git-credential get$' "$CASE/log" && ok "the inventory authenticates with the gh login" || bad "the inventory authenticates with the gh login" "$(cat "$CASE/log")"
# The gh login can't read it: the clone is unchecked with git's reason, never
# judged, even though the clone's own credential helper would answer.
inv_case inventory-private-denied
: > "$CASE/private"; : > "$CASE/gh-auth-fail"
git -C "$RP" config credential.helper "!f() { touch '$CASE/clone-helper-ran'; echo password=gh-login-token; }; f"
out=$(run inventory --path "$I")
git -C "$RP" config --unset credential.helper
expect "a private clone the gh login can't read is unchecked, saying why" '.items | any(.kind == "unchecked" and .clone == "repo" and (.path | test("^remote refs could not be read: fatal: (could not read Username|unable to get password)")))' "$out"
expect "an unread private clone lists no verdict on its commits" '[.items[] | select(.kind == "commit")] | length == 0' "$out"
[ -e "$CASE/clone-helper-ran" ] && bad "the clone's own credential helper never runs" || ok "the clone's own credential helper never runs"
# The refs read runs past its deadline: unchecked, naming the timeout.
inv_case inventory-refs-late
echo 4 > "$CASE/ls-remote.sleep.1"
out=$(DL=1 run inventory --path "$I")
expect "a refs read past its deadline marks the clone unchecked, naming the timeout" '.items | any(.kind == "unchecked" and .clone == "repo" and .path == "remote refs could not be read: the read timed out after 1s")' "$out"

new_case inventory-missing
expect "a missing instance directory: inventory not taken" '.status == "not_verified" and (.reason | test("not found"))' "$(run inventory --path "$T/no-such-instance")"
mkdir -p "$T/linkdir-target"; ln -s "$T/linkdir-target" "$T/linked-instance"
new_case inventory-symlinked
expect "a symlinked instance path is not followed" '.status == "not_verified"' "$(run inventory --path "$T/linked-instance")"
new_case inventory-no-remote
I2="$T/inst2"; mkdir -p "$I2/r"; git -C "$I2/r" init -q; git -C "$I2/r" remote add origin https://gitlab.example/x/y.git
expect "a clone with no github.com origin is marked unchecked" '.items | any(.kind == "unchecked")' "$(run inventory --path "$I2")"
# count A B [-w] -- the integers A..B, one per line (seq isn't a declared tool);
# -w pads them to B's width.
count() { local i=$1 w=""; [ "${3-}" = -w ] && w=${#2}; while [ "$i" -le "$2" ]; do if [ -n "$w" ]; then printf "%0${w}d\n" "$i"; else echo "$i"; fi; i=$((i + 1)); done; }

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
for k in $(count 1 21 -w); do
    git -C "$I4" init -q -b main "r$k" >/dev/null 2>&1
    git -C "$I4/r$k" remote add origin https://github.com/acme/widgets.git
done
echo late > "$I4/r21/late.txt"
new_case inventory-cap
for k in $(count 1 21); do printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M3" > "$CASE/ls-remote.out.$k"; done
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
  for k in $(count 1 600); do printf '%040x\trefs/pull/%s/head\n' "$k" "$k"; done
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
# The other clone lacks GitHub's main commit: GitHub doesn't know its own
# main tip either (compare answers 404), so its commit is unique.
for n in 1 2 3; do fail_with compare $n 1 "gh: Not Found (HTTP 404)"; done
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
for k in $(count 1 230); do echo "$k" > "$R10/u$k.md"; done
new_case inventory-items-cap
printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M10" > "$CASE/ls-remote.out.all"
mktree "$R10" "$M10"
out=$(run inventory --path "$I10")
expect "past the item and file caps the inventory says truncated" '.truncated == true and (.items | length) <= 200' "$out"

new_case inventory-find-late
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M9" "$M9" > "$CASE/ls-remote.out.all"
mktree "$R9" "$M9"
mkdir -p "$T/slowfind"
printf '#!/bin/sh\nsleep 30\n' > "$T/slowfind/find"; chmod +x "$T/slowfind/find"
out=$(STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$T/slowfind:$T/bin:$PATH" RECONCILE_READ_DEADLINE=2 "$BASH" "$S" inventory --path "$I9" 2>/dev/null)
expect "a clone search that runs late is truncated and unchecked, never empty" '.truncated == true and (.items | any(.kind == "unchecked" and (.path | test("timed out"))))' "$out"

I11="$T/inst11"; mkdir -p "$I11/target/x" "$I11/node_modules/y"
for d in target/x node_modules/y; do
    git -C "$I11/$d" init -q -b main; git -C "$I11/$d" remote add origin https://github.com/acme/widgets.git
    echo w > "$I11/$d/w.md"
done
new_case inventory-no-prune
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M9" "$M9" > "$CASE/ls-remote.out.all"
mktree "$R9" "$M9"
out=$(run inventory --path "$I11")
expect "clones under target/ and node_modules/ are walked" '([.items[] | .clone] | index("target/x") != null) and ([.items[] | .clone] | index("node_modules/y") != null)' "$out"

I12="$T/inst12"; R12="$I12/repo"; mkdir -p "$R12"
git -C "$R12" init -q -b main; git -C "$R12" remote add origin https://github.com/acme/widgets.git
for k in $(count 1 150); do echo "$k" > "$R12/t$k.md"; done
git -C "$R12" add -A; git -C "$R12" -c user.email=t@e -c user.name=t commit -qm a
M12=$(git -C "$R12" rev-parse HEAD)
for k in $(count 1 150); do echo "x$k" > "$R12/t$k.md"; done
for k in $(count 1 100); do echo "$k" > "$R12/u$k.md"; done
new_case inventory-item-cap-only
printf 'ref: refs/heads/main\tHEAD\n%s\trefs/heads/main\n' "$M12" > "$CASE/ls-remote.out.all"
mktree "$R12" "$M12"
out=$(run inventory --path "$I12")
expect "past 200 listed items (under the file cap) the inventory says truncated" '.truncated == true and (.items | length) == 200' "$out"

echo "== inventory: a clone that hasn't fetched =="
# GitHub has moved on: its main (X13) and its "extended" branch (Y13) are
# commits this clone never fetched. The clone's main is behind GitHub's; its
# "extended" was pushed and then extended from elsewhere; "sq" was
# squash-merged into X13 and deleted; "unpushed" exists nowhere else.
I13="$T/inst13"; R13="$I13/repo"; mkdir -p "$R13"
g13() { git -C "$R13" -c user.email=t@e -c user.name=t "$@" >/dev/null 2>&1 || echo "setup failed: git $*" >&2; }
g13 init -q -b main; g13 remote add origin https://github.com/acme/widgets.git
echo 1 > "$R13/a.txt"; g13 add -A; g13 commit -qm base
M13=$(git -C "$R13" rev-parse HEAD)
g13 checkout -q -b extended; echo e > "$R13/e.txt"; g13 add -A; g13 commit -qm e
E13=$(git -C "$R13" rev-parse HEAD)
g13 checkout -q -b sq main; echo 2 > "$R13/a.txt"; g13 commit -qam sq
S13=$(git -C "$R13" rev-parse HEAD)
g13 checkout -q -b unpushed main; echo u > "$R13/u.txt"; g13 add -A; g13 commit -qm u
g13 checkout -q main
X13=9999999999999999999999999999999999999999
Y13=8888888888888888888888888888888888888888
new_case inventory-stale
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n%s\trefs/heads/extended\n' "$X13" "$X13" "$Y13" > "$CASE/ls-remote.out.all"
mktree "$R13" "$M13" a.txt "$(git -C "$R13" rev-parse "$S13:a.txt")"
echo '{"behind_by":0}' > "$CASE/cmp@$M13@$X13"
echo '{"behind_by":0}' > "$CASE/cmp@$E13@$Y13"
echo '{"behind_by":2}' > "$CASE/cmp@$E13@$X13"
out=$(run inventory --path "$I13")
commits='[.items[] | select(.kind == "commit") | .path]'
expect "a pushed main behind GitHub's is not unique" "$commits | index(\"branch main\") == null" "$out"
expect "a branch GitHub's same-named branch contains is not unique" "$commits | index(\"branch extended\") == null" "$out"
expect "a branch squash-merged after the clone's last fetch is not unique" "$commits | index(\"branch sq\") == null" "$out"
expect "a branch GitHub has never seen is unique" "$commits == [\"branch unpushed\"] and (.items | all(.kind != \"unchecked\"))" "$out"
grep -q "compare/$S13...$X13" "$CASE/log" && ok "the squash check asks GitHub, not a fetch" || bad "the squash check asks GitHub, not a fetch" "$(cat "$CASE/log")"
if grep -E '(^| )(fetch|pull|remote update)( |$)' "$CASE/log" >/dev/null; then bad "no fetch in a stale clone" "$(cat "$CASE/log")"; else ok "no fetch in a stale clone"; fi
new_case inventory-stale-fails
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$X13" "$X13" > "$CASE/ls-remote.out.all"
mktree "$R13" "$M13"
for n in 1 2 3 4 5 6 7 8; do fail_with compare $n 1 "HTTP 502"; done
out=$(run inventory --path "$I13")
expect "a containment read that fails leaves the tip unchecked, not pushed" '[.items[] | select(.kind == "unchecked") | .path] | index("branch main could not be compared with the remote") != null' "$out"

echo "== inventory: a linked worktree inside the instance =="
I14="$T/inst14"; R14="$I14/repo"; mkdir -p "$R14"
g14() { git -C "$R14" -c user.email=t@e -c user.name=t "$@" >/dev/null 2>&1 || echo "setup failed: git $*" >&2; }
g14 init -q -b main; g14 remote add origin https://github.com/acme/widgets.git
echo 1 > "$R14/a.txt"; g14 add -A; g14 commit -qm base
M14=$(git -C "$R14" rev-parse HEAD)
g14 worktree add -q -b wt "$I14/a-wt"
echo w > "$I14/a-wt/w.txt"; git -C "$I14/a-wt" add w.txt; git -C "$I14/a-wt" -c user.email=t@e -c user.name=t commit -qm w >/dev/null
echo dirty > "$I14/a-wt/a.txt"
echo stashed > "$R14/a.txt"; g14 stash; echo main-dirty > "$R14/a.txt"
new_case inventory-linked
printf 'ref: refs/heads/main\tHEAD\n%s\tHEAD\n%s\trefs/heads/main\n' "$M14" "$M14" > "$CASE/ls-remote.out.all"
mktree "$R14" "$M14"
out=$(run inventory --path "$I14")
expect "a branch shared with a linked worktree is listed once" '[.items[] | select(.path == "branch wt")] | length == 1' "$out"
expect "the stash is listed once" '[.items[] | select(.path | startswith("stash"))] | length == 1' "$out"
expect "each working tree's own change is listed under it" '[.items[] | select(.kind == "change" and .path == "a.txt") | .clone] | sort == ["a-wt", "repo"]' "$out"
[ "$(grep -c 'ls-remote' "$CASE/log")" = 1 ] && ok "the remote is read once per repository" || bad "the remote is read once per repository" "$(grep -c ls-remote "$CASE/log")"
[ "$(grep -c 'git/trees' "$CASE/log")" = 1 ] && ok "the default tree is read once per repository" || bad "the default tree is read once per repository" "$(grep -c git/trees "$CASE/log")"

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
# koto's own run start carries milliseconds (shirabe#552: a check that
# refused it printed nothing, and every deferral read "nothing readable").
new_case deferral-millis
serve deferral 1 "disposed closed"
expect "a run start with milliseconds is a time" '.disposed == true and .how == "closed"' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-28T14:34:17.326Z --chain-start 2026-09-28T14:34:17.326Z)"
# Every input this read can't take is a fact naming it, never a silent exit.
new_case deferral-no-row
expect "a missing row file is not verified, and says so" '.status == "not_verified" and (.reason | test("row file"))' "$(run deferral --repo $R --row-file "$T/no-such-row.json" --run-start $RS)"
new_case deferral-bad-start
expect "a run start that isn't a time is not verified, and says so" '.status == "not_verified" and (.reason | test("run start"))' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27)"
new_case deferral-bad-chain
expect "a chain start that isn't a time is not verified, and says so" '.status == "not_verified" and (.reason | test("chain start"))' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS --chain-start yesterday)"
new_case deferral-usage
fail_with deferral 1 64
expect "a disposal check that refuses its input is not verified, and says so" '.status == "not_verified" and (.reason | test("refused its input"))' "$(run deferral --repo $R --row-file "$ROW" --run-start $RS)"

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
ALLOW='^(gh pr view [0-9]+ --repo [^ ]+ --json [a-zA-Z,]+|gh pr list --repo [^ ]+ --head [^ ]+ --state all --json [a-z,]+|gh issue view [0-9]+ --repo [^ ]+ --json [a-z]+|gh api repos/[^ ]+ --jq .*|gh api repos/[^ ]+ --paginate --jq .*|gh api --method GET repos/[^ ]+|gh auth git-credential get|board-verdict\.sh --repo [^ ]+ --sha [0-9a-f]{40} --base [^ ]+|deferral-check\.sh --row-file [^ ]+ --run-start [^ ]+( --chain-start [^ ]+)?|niwa list --json|koto request get [a-z0-9_-]+|git --no-optional-locks -c core\.fsmonitor= -c core\.hooksPath=/dev/null -c protocol\.allow=never (-C / -c protocol\.https\.allow=always -c protocol\.file\.allow=always -c core\.askPass= -c credential\.interactive=false -c credential\.helper= -c credential\.https://github\.com\.helper= -c credential\.helper=!gh auth git-credential ls-remote --symref https://github\.com/[^ ]+\.git( refs/heads/[^ ]+)?|-C [^ ]+ (config --get remote\.origin\.url|rev-parse --path-format=absolute --git-common-dir --show-toplevel|cat-file --batch-check=.*|cat-file -e [0-9a-f]{40}\^\{commit\}|symbolic-ref -q HEAD|rev-parse --verify --quiet .*|rev-list --stdin --count|rev-list --walk-reflogs --count refs/stash|merge-base [0-9a-f]{40} [0-9a-f]{40}|diff --name-only -z [0-9a-f]{40} [0-9a-f]{40}|for-each-ref refs/heads refs/tags --format=.*|ls-files -z -s -v|hash-object --no-filters --stdin|ls-files -z --others --exclude-standard|ls-tree -r -z --full-tree HEAD|hash-object --no-filters --stdin-paths|worktree list --porcelain)))$'
off=$(grep -vE "$ALLOW" "$ALL" || true)
[ -z "$off" ] && ok "every call matches the read allowlist" || bad "every call matches the read allowlist" "$off"
# --method is allowed only as `--method GET`, the merge check's reads.
WRITES=$(sed 's/ --method GET / /' "$ALL" | grep -E ' (-f|-F|--field|--raw-field|--input|--method|-X) ' || true)
[ -z "$WRITES" ] && ok "no gh api write flags anywhere" || bad "no gh api write flags" "$WRITES"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
