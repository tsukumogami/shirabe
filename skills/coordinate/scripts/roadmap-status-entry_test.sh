#!/usr/bin/env bash
# roadmap-status-entry_test.sh -- roadmap-status.sh --verdict and --reopen
# with --entry N, a run's milestone entry posted on the roadmap
# pull request it opens
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2).
#
# Covers: --verdict --entry opening one pull request with the entry in its
# body, posting the session entry on it as a comment by the coordinator
# (marker, kind and text as record-append.sh posts them, an `@` escaped),
# keeping its URL in record/posted/<n>, writing a milestone-done row whose How
# to confirm names the entry, and pushing a second commit whose Progress line
# names that comment and the entry's hash, nothing posted on any issue;
# --confirm clearing it once main
# reads Done. A changes-needed verdict's milestone-verdict row confirmed from
# record/posted/<n>: 1 before main carries the line, refused for a comment by
# another login and for one whose text no longer hashes to the line, then its
# rework row. A failed post (14, naming the pull request, its row written),
# and a run again with the same entry posting once and pushing the missing
# commit with no second pull request; a failed Progress commit the same; a
# post that landed before its record/posted key was kept, found by the
# retry rather than posted twice; and a third run changing nothing. --reopen
# --entry the same way, its reopen line naming the pull request's comment,
# its held dependent printed, and --confirm writing its rework row.
# Refusals with nothing opened: --entry with no session holding the record,
# with --entry-file, an entry of another kind, no such entry, and an entry
# already posted elsewhere. The record is the session's alone.
#
# Usage: bash skills/coordinate/scripts/roadmap-status-entry_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/roadmap-status.sh"
RA="$HERE/record-append.sh"

# A stand-in shirabe: `roadmap populate <file>` leaves the file as it is.
mkdir -p "$T/bin"
cat > "$T/bin/shirabe" <<EOF
#!/usr/bin/env bash
[ "\${1-} \${2-}" = "roadmap populate" ] || { echo "stand-in shirabe: unexpected call: \$*" >&2; exit 9; }
[ -f "\${3-}" ] || { echo "stand-in shirabe: no such roadmap: \${3-}" >&2; exit 2; }
exit 0
EOF
chmod +x "$T/bin/shirabe"
PATH="$T/bin:$PATH"

# The milestone roadmap roadmap-status_test.sh uses. Written to a file first:
# bash 3.2 misreads a quote inside a here-document inside $( ).
cat > "$T/mv.md" <<'EOF'
---
schema: roadmap/v2
status: Active
---

# ROADMAP: plugins

## Features

### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs
  `widgets list` and sees exactly those three names.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Needs:** `needs-design` -- the list layout
**Dependencies:** None
**Status:** In progress
**Delivered:** acme/widgets#3

### MV2: the host serves

**Outcome:** The host answers on its public name.

**Evidence:**
- An operator curls the host's public name and gets a 200.

**Left open:** None

**Dependencies:** MV1
**Status:** In progress

### MV3: done already

**Outcome:** Shipped.

**Evidence:**
- A reviewer saw it.

**Left open:** None

**Dependencies:** None
**Status:** Done

## Progress

- 2026-10-01: MV1 and MV2 started
EOF
MV=$(cat "$T/mv.md")
printf '%s\n' "$MV" | awk '!d && /^\*\*Status:\*\* In progress$/ { print "**Status:** Done"; d = 1; next } { print }' > "$T/mvd.md"
MVD=$(cat "$T/mvd.md")
ROADMAP=docs/roadmaps/ROADMAP-plugin-system.md
# An ordinary issue, no record: the pull requests a test opens number from 8.
issue7() { db '.issues += [{repo: "acme/widgets", number: 7, title: "the plugin tracker", body: "", state: "open", author: "alice", editor: null}]'; }
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W=("${RM[@]}" --skip-session-checks)
SV=coordinate-roadmap-plugin-system-20260926T170000Z
SEN=(env RS_SESSION="$SV")
TODAY=$(date -u +%Y-%m-%d)
SRC="Source: $ROADMAP at $SHA_MAIN"

# sv_seed [main-text] [holding-json]: the record in the session, MV1
# held by plugin-list (or the holding given), and main reading MAIN-TEXT.
sv_seed() {
    db_init
    issue7
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "${1:-$MV}"
    rm -rf "$KOTO_STORE/context/$SV"
    record_json roadmap plugin-system | jq -c --argjson h "${2:-$(holding plugin-list '{"unit": "MV1: the plugin list", "pull_request": ""}')}" \
        '.holdings = [$h] | .written = "2026-09-26T08:00:00Z"' > "$T/sv.json"
    session_keys "$SV" "$T/sv.json"
}
rs() { "${SEN[@]}" bash "$RS" "${W[@]}" "$@"; }
# slive: the record as a reader is handed it (rs_record), in normal form.
slive() {
    ( RS_SESSION=$SV PROG=reader SCOPE=roadmap NAME=plugin-system
      . "$HERE/record-common.sh"; . "$HERE/record-source.sh"; RS_RETRY_PAUSE=0
      rs_record "$T/reader" > /dev/null 2>&1 && jq -cS . "$T/reader" )
}
on_branch() { jq -r --arg b "$1" '.files["acme/widgets"][$b + ":" + $p] // empty' --arg p "$ROADMAP" "$GH_DB"; }
to_main() { db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$1"; }
branch_of() { jq -r --argjson n "$1" '.prs[] | select(.number == $n) | .headRefName' "$GH_DB"; }
posted() { koto context get "$SV" "record/posted/$(printf '%06d' "$1")" 2>/dev/null; }
# write_entry <kind> <file>: the session entry, --on none; prints its number.
write_entry() { local o; o=$("${SEN[@]}" bash "$RA" "${RM[@]}" --kind "$1" --on none --text-file "$2") || return 1; echo "$((10#${o##*/}))"; }
sha8() { (sha256sum < "$1" 2>/dev/null || shasum -a 256 < "$1") | cut -c1-8; }
puts() { grep -c 'PUT repos/acme/widgets/contents' "$GH_DB.calls"; }
ncomments() { jq '.comments // [] | length' "$GH_DB"; }
writes() { grep -cE 'POST repos/[^ ]*/git/refs|PUT repos|pr create|issues/[0-9]+/comments --input' "$GH_DB.calls"; }
ventry() { # ventry <file> <tag> <verdict> <work> <fit> <changes> <clause>...
    local f=$1 tag=$2 v=$3 work=$4 fit=$5 ch=$6 i=1; shift 6
    { printf 'Verdict: %s -- %s\nChecked by: coordinate-plugins\nChecked on: %s\n%s\nWork checked: %s\n\nEvidence:\n' "$tag" "$v" "$TODAY" "$SRC" "$work"
      for c in "$@"; do printf '%s. %s -- checked on a clean install\n' "$i" "$c"; i=$((i + 1)); done
      printf '\nStrategy fit: %s -- it serves the plugin bet, as @alice asked\nFollow-ups: none\nChanges needed: %s\n' "$fit" "$ch"; } > "$f"
}
fentry() { # fentry <file> <tag> <clause> <what>
    printf 'Failure: %s\nReported by: an operator\nSeen on: %s\nClause: %s\nWhat was seen: %s\n' "$2" "$TODAY" "$3" "$4" > "$1"
}

echo "== --verdict --entry: verified =="
sv_seed
rs --unit MV1 >/dev/null 2>"$T/err"; eq "--unit marks MV1's verdict owed" 0 $?
ventry "$T/v1.txt" MV1 verified "acme/widgets#12, acme/widgets#3" fits none held held
N1=$(write_entry milestone-verdict "$T/v1.txt")
eq "the verdict is written to the session with --on none, posted nowhere" "0" "$(ncomments)"
reset_calls
OUT=$(rs --verdict MV1 --entry "$N1" 2>"$T/err"); rc=$?
eq "--verdict --entry opens the roadmap pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
eq "  ... one pull request" 1 "$(jq '.prs | length' "$GH_DB")"
jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB" | grep -qxF '> Verdict: MV1 -- verified' && ok "  ... its body carries the entry" || bad "  ... its body carries the entry" "$(jq -r '.prs[0].body' "$GH_DB")"
jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB" | grep -q 'issue #7' && bad "  ... and names no record issue" "" || ok "  ... and names no record issue"
URL1=$(posted "$N1")
case "$URL1" in https://github.com/acme/widgets/pull/8\#issuecomment-*) ok "  ... the entry posted on it, its URL kept" ;; *) bad "  ... the entry posted on it, its URL kept" "[$URL1]" ;; esac
C1=$(jq -r --argjson i "${URL1##*-}" '.comments[] | select(.id == $i) | "\(.number)|\(.user)"' "$GH_DB")
eq "  ... as a comment on pull request 8 by the coordinator" "8|coord" "$C1"
B1=$(jq -r --argjson i "${URL1##*-}" '.comments[] | select(.id == $i) | .body' "$GH_DB")
eq "  ... under the milestone-verdict marker" "<!-- coordinator-record-entry v1 kind=milestone-verdict -->" "$(printf '%s\n' "$B1" | sed -n 1p)"
case "$B1" in *'as &#64;alice asked'*) case "$B1" in *@alice*) bad "  ... with its @ escaped" "$B1" ;; *) ok "  ... with its @ escaped" ;; esac ;;
    *) bad "  ... with its @ escaped" "$B1" ;; esac
eq "  ... and its text the entry's" "$(cat "$T/v1.txt")" "$(printf '%s\n' "$B1" | sed -n '4,$p' | sed -e 's/&#64;/@/g' -e 's/&amp;/\&/g')"
PRB=$(branch_of 8)
eq "  ... two commits on its branch: the edit, then the Progress line" 2 "$(puts)"
H1=$(sha8 "$T/v1.txt")
diff "$T/mv.md" <(on_branch "$PRB") > "$T/d"
eq "  ... setting Done, dropping Needs, adding to Delivered, and a Progress line naming the posted comment and the entry's hash" \
    "$(printf '%s\n' '21d20' '< **Needs:** `needs-design` -- the list layout' '23,24c22,23' '< **Status:** In progress' '< **Delivered:** acme/widgets#3' '---' '> **Status:** Done' '> **Delivered:** acme/widgets#3, acme/widgets#12' '52a52' "> - $TODAY: MV1 -- verified, checked by coordinate-plugins ($URL1, $H1)")" "$(cat "$T/d")"
eq "  ... a milestone-done row naming the entry" "milestone-done|MV1 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads MV1 Done (entry $N1)" \
    "$(slive | jq -r '.side_effects[0] | "\(.action)|\(.target)|\(.how_to_confirm)"')"
grep -E 'issues/[0-9]+/comments' "$GH_DB.calls" | grep -qv 'issues/8/comments' && bad "  ... nothing posted on any other issue" "$(calls)" || ok "  ... nothing posted on any other issue"
reset_calls
OUT=$(rs --verdict MV1 --entry "$N1" 2>"$T/err"); rc=$?
eq "run again it changes nothing" "0 https://github.com/acme/widgets/pull/8 1 0 0" "$rc $OUT $(jq '.prs | length' "$GH_DB") $(puts) $(grep -c 'comments --input' "$GH_DB.calls")"
rs --confirm MV1 >/dev/null 2>"$T/err"; eq "--confirm while main doesn't read Done is 1" 1 $?
to_main "$(on_branch "$PRB")"
rs --confirm MV1 >/dev/null 2>"$T/err"; eq "--confirm once main reads Done" 0 $?
eq "  ... clears the row" 0 "$(slive | jq '.side_effects | length')"

echo "== --verdict --entry: changes needed, confirmed from the posted comment =="
sv_seed "$MV" "$(holding mv2-host '{"unit": "MV2: the host serves", "pull_request": ""}')"
rs --unit MV2 >/dev/null 2>&1
ventry "$T/v2.txt" MV2 "changes needed" none fits "answer on the public name" "not held"
N2=$(write_entry milestone-verdict "$T/v2.txt")
OUT=$(rs --verdict MV2 --entry "$N2" 2>"$T/err"); rc=$?
eq "a changes-needed verdict opens its pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
URL2=$(posted "$N2")
eq "  ... a milestone-verdict row naming the entry" "milestone-verdict|the roadmap on main carries its entry's comment in Progress (entry $N2)" \
    "$(slive | jq -r '.side_effects[0] | "\(.action)|\(.how_to_confirm)"')"
rs --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm before main carries the line is 1" 1 $?
to_main "$(on_branch "$(branch_of 8)")"
CID=${URL2##*-}
db '(.comments[] | select(.id == ($i | tonumber))).user = "mallory"' --arg i "$CID"
rs --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm refuses the pull request's comment by another login" 65 $?
grep -q "not by the coordinator's login" "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
db '(.comments[] | select(.id == ($i | tonumber))).user = "Coord"' --arg i "$CID"
db '(.comments[] | select(.id == ($i | tonumber))).body |= sub("public name"; "private name")' --arg i "$CID"
rs --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm refuses a comment whose text no longer hashes to its line" 65 $?
db '(.comments[] | select(.id == ($i | tonumber))).body |= sub("private name"; "public name")' --arg i "$CID"
rs --confirm MV2 >/dev/null 2>"$T/err"; rc=$?; eq "--confirm accepts the coordinator's comment, its login in any case" 0 "$rc"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
eq "  ... and writes the rework row" "verdict $CID|Evidence clauses not held: 1. Changes needed: answer on the public name" \
    "$(slive | jq -r '[.work[] | select(.kind == "rework" and .item == "MV2")][0] | "\(.who)|\(.next)"')"

echo "== a failed post, and the same entry run again =="
sv_seed
rs --unit MV1 >/dev/null 2>&1
N3=$(write_entry milestone-verdict "$T/v1.txt")
db '.fail = [{match: "POST repos/acme/widgets/issues/8/comments", rc: 1, stderr: "gh: HTTP 502"}]'
rs --verdict MV1 --entry "$N3" >/dev/null 2>"$T/err"; eq "a failed post after the pull request opened exits 14" 14 $?
grep -q 'https://github.com/acme/widgets/pull/8' "$T/err" && ok "  ... naming the pull request" || bad "  ... naming the pull request" "$(cat "$T/err")"
eq "  ... its row written, naming the pull request and the entry" "MV1 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads MV1 Done (entry $N3)" \
    "$(slive | jq -r '.side_effects[0] | "\(.target)|\(.how_to_confirm)"')"
eq "  ... nothing posted, one commit" "0 1" "$(ncomments) $(puts)"
db '.fail = []'
OUT=$(rs --verdict MV1 --entry "$N3" 2>"$T/err"); rc=$?
eq "run again it finishes" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
eq "  ... with no second pull request, one comment and the missing commit" "1 1 2" "$(jq '.prs | length' "$GH_DB") $(ncomments) $(puts)"
on_branch "$(branch_of 8)" | grep -qF "($(posted "$N3"), $(sha8 "$T/v1.txt"))" && ok "  ... its Progress line naming the comment" || bad "  ... its Progress line naming the comment" "$(on_branch "$(branch_of 8)")"

echo "== a failed Progress commit, and the same entry run again =="
sv_seed
rs --unit MV1 >/dev/null 2>&1
N4=$(write_entry milestone-verdict "$T/v1.txt")
db '.fail = [{match: "message=docs(roadmap): name the verdict entry", rc: 1, stderr: "gh: HTTP 409"}]'
rs --verdict MV1 --entry "$N4" >/dev/null 2>"$T/err"; eq "a failed Progress commit exits 14" 14 $?
grep -q 'https://github.com/acme/widgets/pull/8' "$T/err" && ok "  ... naming the pull request" || bad "  ... naming the pull request" "$(cat "$T/err")"
eq "  ... the entry posted" "1 1" "$(ncomments) $(jq '.prs | length' "$GH_DB")"
db '.fail = []'
rs --verdict MV1 --entry "$N4" >/dev/null 2>"$T/err"; eq "run again it pushes the commit" 0 $?
eq "  ... posting nothing twice, opening nothing twice, committing once more (the edit, the failed commit, this one)" \
    "1 1 3" "$(ncomments) $(jq '.prs | length' "$GH_DB") $(puts)"
on_branch "$(branch_of 8)" | grep -qF "($(posted "$N4"), $(sha8 "$T/v1.txt"))" && ok "  ... its Progress line naming the comment" || bad "  ... its Progress line naming the comment" "$(on_branch "$(branch_of 8)")"

echo "== a post that landed before its URL was kept =="
sv_seed
rs --unit MV1 >/dev/null 2>&1
N5=$(write_entry milestone-verdict "$T/v1.txt")
KOTO_FAIL_ADD="record/posted/$(printf '%06d' "$N5")" rs --verdict MV1 --entry "$N5" >/dev/null 2>"$T/err"; eq "a post whose URL couldn't be kept exits 14" 14 $?
eq "  ... with the comment posted" 1 "$(ncomments)"
rs --verdict MV1 --entry "$N5" >/dev/null 2>"$T/err"; eq "run again it finishes" 0 $?
eq "  ... finding the comment rather than posting it twice" "1 $(jq -r '.comments[0].id' "$GH_DB")" "$(ncomments) $(posted "$N5" | sed 's/.*-//')"

echo "== --reopen --entry =="
sv_seed "$MVD" "$(holding mv2-host '{"unit": "MV2: the host serves", "pull_request": ""}')"
fentry "$T/f.txt" MV1 2 "the removed manifest was listed as installed by @carol"
NF=$(write_entry milestone-failure "$T/f.txt")
OUT=$(rs --reopen MV1 --entry "$NF" 2>"$T/err"); rc=$?
eq "--reopen --entry opens the reopen pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $(head -n 1 <<<"$OUT")"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
eq "  ... and names the held dependent" "held-dependent MV2 mv2-host" "$(printf '%s\n' "$OUT" | sed -n '2,$p')"
URLF=$(posted "$NF")
diff "$T/mvd.md" <(on_branch "$(branch_of 8)") > "$T/d"
eq "  ... MV1 In progress, and a reopen line naming the pull request's comment" \
    "$(printf '%s\n' '23c23' '< **Status:** Done' '---' '> **Status:** In progress' '52a53' "> - $TODAY: MV1 -- reopened: clause 2 failed, reported by an operator ($URLF, $(sha8 "$T/f.txt"))")" "$(cat "$T/d")"
case "$URLF" in https://github.com/acme/widgets/pull/8\#issuecomment-*) ok "  ... a comment on the pull request" ;; *) bad "  ... a comment on the pull request" "[$URLF]" ;; esac
eq "  ... a milestone-reopen row naming the entry" "milestone-reopen|the roadmap on main reads MV1 In progress (entry $NF)" \
    "$(slive | jq -r '.side_effects[0] | "\(.action)|\(.how_to_confirm)"')"
to_main "$(on_branch "$(branch_of 8)")"
rs --confirm MV1 >/dev/null 2>"$T/err"; rc=$?; eq "--confirm once main reads it" 0 "$rc"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
eq "  ... writes the rework row" "failure ${URLF##*-}|Evidence clause 2 failed: the removed manifest was listed as installed by @carol" \
    "$(slive | jq -r '[.work[] | select(.kind == "rework" and .item == "MV1")][0] | "\(.who)|\(.next)"')"

echo "== refusals, nothing opened =="
sv_seed
rs --unit MV1 >/dev/null 2>&1
N6=$(write_entry milestone-verdict "$T/v1.txt")
reset_calls
env -u RS_SESSION bash "$RS" "${W[@]}" --verdict MV1 --entry "$N6" >/dev/null 2>"$T/err"; eq "--entry with no session holding the record is a usage error" 64 $?
rs --verdict MV1 --entry "$N6" --entry-file "$T/v1.txt" >/dev/null 2>&1; eq "--entry with --entry-file is a usage error" 64 $?
rs --verdict MV1 --entry 0 >/dev/null 2>&1; eq "--entry 0 is a usage error" 64 $?
fentry "$T/f9.txt" MV1 1 "nothing"
NW=$(write_entry milestone-failure "$T/f9.txt")
rs --verdict MV1 --entry "$NW" >/dev/null 2>"$T/err"; eq "an entry of another kind is refused" 65 $?
rs --verdict MV1 --entry 999 >/dev/null 2>"$T/err"; eq "no such entry is refused" 65 $?
printf 'https://github.com/acme/widgets/issues/7#issuecomment-4242\n' | koto context add "$SV" "record/posted/$(printf '%06d' "$N6")"
rs --verdict MV1 --entry "$N6" >/dev/null 2>"$T/err"; eq "an entry already posted elsewhere is refused" 65 $?
grep -q 'already posted' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
eq "  ... and no refusal wrote to GitHub" "0 0" "$(writes) $(jq '.prs | length' "$GH_DB")"

done_tests roadmap-status-entry_test
