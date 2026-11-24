#!/usr/bin/env bash
# roadmap-status-v4_test.sh -- roadmap-status.sh --unit on a roadmap/v4
# roadmap: the merge records the milestone Completed
# (docs/designs/DESIGN-completed-verified-states.md, Decision 3).
#
# Covers: with no pending roadmap edit, --unit writes the verdict-owed row and
# opens one pull request whose diff sets the milestone's block Status and
# Progress row to Completed, writes its Delivered line and removes its Needs
# line, nothing else in the file changing, with a Side effects row of Action
# roadmap-status; with the run's own roadmap edit pending, it commits onto that
# edit's branch with the branch's head as parent, adds one line naming the
# milestone to that pull request's body and opens nothing; a branch that moved
# after the read is read again: its pull request merged meanwhile opens a new
# one, still open refuses naming the new head with no commit and the record
# unchanged; run a second time it changes nothing and says the milestone
# already reads Completed; refusals (a Verified milestone, a tag that isn't a
# milestone, no --outcome); a roadmap/v3 roadmap still gets only its
# verdict-owed row and a roadmap/v1 one its Done pull request.
#
# Usage: bash skills/coordinate/scripts/roadmap-status-v4_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
printf '#!/usr/bin/env bash\necho include\n' > "$T/pr-content-reader"
export STATE_ENTRY_PR_CONTENT_READER="$T/pr-content-reader"
RS="$HERE/roadmap-status.sh"
RA="$HERE/state-entry.sh"

# A stand-in shirabe whose `roadmap populate` leaves the file as it is, so the
# diff is exactly what the script changes, and a stand-in date pinning the
# day (as roadmap-status_test.sh does).
mkdir -p "$T/bin"
cat > "$T/bin/shirabe" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/shirabe.calls"
[ "\${1-} \${2-}" = "roadmap populate" ] || { echo "stand-in shirabe: unexpected call: \$*" >&2; exit 9; }
[ -f "\${3-}" ] || { echo "stand-in shirabe: no such roadmap: \${3-}" >&2; exit 2; }
exit 0
EOF
chmod +x "$T/bin/shirabe"
REAL_DATE=$(command -v date)
cat > "$T/bin/date" <<EOF
#!/usr/bin/env bash
[ "\$*" = "-u +%Y-%m-%d" ] && { echo $("$REAL_DATE" -u +%Y-%m-%d); exit 0; }
exec "$REAL_DATE" "\$@"
EOF
chmod +x "$T/bin/date"
PATH="$T/bin:$PATH"
TODAY=$(date -u +%Y-%m-%d)

ROADMAP=docs/roadmaps/ROADMAP-plugin-system.md
KEY="main:$ROADMAP"
SR=coordinate-roadmap-plugin-system-20261122T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W=("${RM[@]}" --skip-session-checks)
live() { session_state "$SR"; }
on_branch() { jq -r --arg k "$1:$ROADMAP" '.files["acme/widgets"][$k] // empty' "$GH_DB"; }
writes() { grep -cE 'POST repos/[^ ]*/git/refs|PUT repos|pr create|pr edit|PATCH' "$GH_DB.calls"; }
owed() { live | jq -r --arg t "$1" '[(.work // [])[] | select(.kind == "verdict-owed" and .item == $t) | "\(.who)|\(.next)"][0] // "none"'; }

cat > "$T/v4.md" <<'EOF'
---
schema: roadmap/v4
status: Active
theme: |
  Plugins a maintainer can find.
scope: |
  The loader, the registry and search.
---

# ROADMAP: plugins

## Status

Active

## Theme

Plugins a maintainer can find.

## Milestones

### Milestone 1: Loader

**Outcome:** A maintainer who installed three plugins sees each one listed
by name with the version it loaded.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs the list
  command and sees exactly those three names and versions.

**Left open:** None

**Needs:** `needs-design` -- the list layout,
  and where it reads from
**Dependencies:** None
**Status:** In progress

### Milestone 2: Registry

**Outcome:** A maintainer finds a plugin by name without reading the plugin
directory.

**Evidence:**
- A reviewer runs the find command for an installed plugin and sees its path.

**Left open:** None

**Dependencies:** Milestone 1
**Status:** Not started

### Milestone 3: Search

**Outcome:** A maintainer searches plugins by keyword and sees the matches.

**Evidence:**
- A reviewer searches for a keyword two sample plugins share and sees both.

**Left open:** None

**Dependencies:** None
**Status:** Verified

### Milestone 4: Docs

**Outcome:** A maintainer reads how to write a plugin.

**Evidence:**
- A reviewer follows the guide and loads the plugin they wrote.

**Left open:** None

**Dependencies:** None
**Status:** In progress

## Sequencing Rationale

The loader comes first because the registry reads what it loads.

## Progress

| Milestone | Status | Verdict |
|-----------|--------|---------|
| Milestone 1: Loader | In progress | -- |
| Milestone 2: Registry | Not started | -- |
| Milestone 3: Search | ~~Verified~~ | verified (2026-11-01) |
| Milestone 4: Docs | In progress | -- |

- 2026-11-01: Milestone 3 -- verified

## Implementation Issues

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

| Milestone | Issues | Dependencies | Status |
|-----------|--------|--------------|--------|

## Dependency Graph

<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->

```mermaid
graph TD
```
EOF
V4=$(cat "$T/v4.md")
# m4_completed <text>: the roadmap with Milestone 4 recorded Completed, as a
# pending edit for it leaves its branch.
m4_completed() {
    printf '%s\n' "$1" | awk '
        /^### Milestone 4:/ { in4 = 1 }
        /^### Milestone [0-35-9]/ { in4 = 0 }
        in4 && /^\*\*Status:\*\*/ { print "**Status:** Completed"; print "**Delivered:** #9"; next }
        /^\| Milestone 4: Docs \|/ { print "| Milestone 4: Docs | Completed | -- |"; next }
        { print }'
}
V4_M4=$(m4_completed "$V4")
# m1_diff <row-hunk>: the diff Milestone 1's Completed makes: its Needs field
# (with its wrapped line) gone, Status Completed with Delivered #12 after it,
# and its Progress row Completed, at the row hunk given.
m1_diff() {
    printf '%s\n' '33,34d32' '< **Needs:** `needs-design` -- the list layout,' '<   and where it reads from' \
        '36c34,35' '< **Status:** In progress' '---' '> **Status:** Completed' '> **Delivered:** #12' \
        "$1" '< | Milestone 1: Loader | In progress | -- |' '---' '> | Milestone 1: Loader | Completed | -- |'
}

seed() { # seed [record-json]
    db_init
    db '.files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "$V4"
    db '.issues += [{repo: "acme/widgets", number: 7, title: "the plugin tracker", body: "", state: "open", author: "alice", editor: null}]'
    seed_session "$SR" "${1:-$(record_json roadmap plugin-system | jq -c --argjson h "$(holding plugin-loader '{"unit": "Milestone 1: Loader", "pull_request": ""}')" '.holdings = [$h]')}"
}
# PENDING_BRANCH: the run's own roadmap edit for Milestone 4, pull request #5,
# open at SHA_HEAD; pending_seed seeds it in the DB and its row in the record.
PENDING_BRANCH=coordinate/roadmap-status-milestone-4-202611210900
PENDING_BODY=$(printf '%s\n' 'Records milestones of the roadmap whose work merged as Completed. One line per milestone:' '' \
    '- Milestone 4, Docs: Completed; Delivered: #9' '' '---' '' 'Opened by the coordinator for plugin-system.')
pending_seed() {
    seed "$(record_json roadmap plugin-system | jq -c '.side_effects = [{action: "roadmap-status",
        target: "Milestone 4 [#5](https://github.com/acme/widgets/pull/5)", verified_head: "", attempted: "2026-11-21T09:00Z",
        how_to_confirm: "the roadmap on main reads Milestone 4 Completed"}]
        | .work = [{item: "Milestone 4", kind: "verdict-owed", who: "none", next: "verdict owed since 2026-11-21", wakes: "0", updated: "2026-11-21T09:00Z"}]')"
    db '.branches["acme/widgets"][$b] = $s | .commits[$s] = {tree: "6666666666666666666666666666666666666666", parents: [$m]}
        | .files["acme/widgets"][$b + ":" + $f] = $r
        | .prs += [{repo: "acme/widgets", number: 5, title: "docs(roadmap): record Milestone 4, Docs, as completed", body: $body,
                    state: "OPEN", isDraft: false, isCrossRepository: false, baseRefName: "main", headRefName: $b,
                    headRefOid: $s, author: "coord", editor: null}]' \
        --arg b "$PENDING_BRANCH" --arg s "$SHA_HEAD" --arg m "$SHA_MAIN" --arg f "$ROADMAP" --arg r "$V4_M4" --arg body "$PENDING_BODY"
}

echo "== no pending edit: a new pull request records Completed =="
seed
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "--unit prints the verdict owed and the pull request" "0 verdict-owed Milestone 1
https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... the verdict-owed row, Who its holding's worker" "plugin-loader|verdict owed since $TODAY" "$(owed 'Milestone 1')"
eq "  ... one pull request opened" 1 "$(jq '.prs | length' "$GH_DB")"
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
case "$PRB" in coordinate/roadmap-status-milestone-1-[0-9]*) ok "  ... from a new coordinate/roadmap-status branch" ;; *) bad "  ... from a new coordinate/roadmap-status branch" "$PRB" ;; esac
eq "  ... titled for the milestone" "docs(roadmap): record Milestone 1, Loader, as completed" "$(jq -r '.prs[] | select(.number == 8) | .title' "$GH_DB")"
on_branch "$PRB" > "$T/written-new.md"
diff "$T/v4.md" "$T/written-new.md" > "$T/d"
eq "  ... its diff: Needs (with its wrapped line) gone, Status Completed, Delivered #12, the Progress row Completed" \
    "$(m1_diff 83c82)" "$(cat "$T/d")"
eq "  ... main is untouched" "$V4" "$(on_branch main)"
grep -q '^roadmap populate ROADMAP-plugin-system.md$' "$T/shirabe.calls" && ok "  ... the generated sections are regenerated" || bad "  ... the generated sections are regenerated"
jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB" > "$T/body8"
grep -qxF -- '- Milestone 1, Loader: Completed; Delivered: #12' "$T/body8" && ok "  ... its body names the milestone on a line" || bad "  ... its body names the milestone on a line" "$(cat "$T/body8")"
eq "  ... and has one separator" 1 "$(grep -cx -- '---' "$T/body8")"
eq "  ... the record holds one pending edit, Action roadmap-status" \
    "1|roadmap-status|Milestone 1 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads Milestone 1 Completed" \
    "$(live | jq -r '"\(.side_effects | length)|\(.side_effects[0].action)|\(.side_effects[0].target)|\(.side_effects[0].how_to_confirm)"')"
bash "$RA" "${RM[@]}" --list | jq -e '.[-1].kind == "roadmap-status" and (.[-1].text | test("verdict is owed.*sets it Completed"))' >/dev/null \
    && ok "  ... one entry tells both" || bad "  ... one entry tells both" "$(bash "$RA" "${RM[@]}" --list | jq -c '.[-1]')"
grep -qE 'pr merge|/merges' "$GH_DB.calls" && bad "  ... nothing is merged" || ok "  ... nothing is merged"

echo "== run a second time: nothing changes =="
SNAP=$(session_snapshot "$SR")
DB_BEFORE=$(jq -c 'del(.fail)' "$GH_DB")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "--unit again says Milestone 1 already reads Completed" "0 verdict-owed Milestone 1
Milestone 1 already reads Completed on the pending roadmap edit https://github.com/acme/widgets/pull/8" "$rc $OUT"
eq "  ... with no write to GitHub" 0 "$(writes)"
eq "  ... the roadmap, branches and pull requests as they were" "$DB_BEFORE" "$(jq -c 'del(.fail)' "$GH_DB")"
eq "  ... and the record unchanged" "$SNAP" "$(session_snapshot "$SR")"
# Once the edit merged, the default branch says it.
db '.files["acme/widgets"][$k] = $r | (.prs[] | select(.number == 8)).state = "MERGED"' --arg k "$KEY" --arg r "$(cat "$T/written-new.md")"
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "  ... and after it merged, the default branch says so" "0 verdict-owed Milestone 1
Milestone 1 already reads Completed on main" "$rc $OUT"
eq "  ... still with nothing written" "$SNAP 0" "$(session_snapshot "$SR") $(writes)"

echo "== a pending edit of the run's own: the Completed change folds into it =="
pending_seed
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "--unit prints the verdict owed and the pending pull request" "0 verdict-owed Milestone 1
https://github.com/acme/widgets/pull/5" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... no new pull request and no new branch" "1 0" "$(jq '.prs | length' "$GH_DB") $(grep -c 'POST repos/acme/widgets/git/refs' "$GH_DB.calls")"
NEWHEAD=$(jq -r --arg b "$PENDING_BRANCH" '.branches["acme/widgets"][$b]' "$GH_DB")
eq "  ... one new commit on the pending branch, its parent the head read" "$SHA_HEAD" "$(jq -r --arg s "$NEWHEAD" '.commits[$s].parents[0]' "$GH_DB")"
on_branch "$PENDING_BRANCH" > "$T/written-fold.md"
diff <(printf '%s\n' "$V4_M4") "$T/written-fold.md" > "$T/d"
eq "  ... whose diff is Milestone 1's Completed alone, Milestone 4's kept" "$(m1_diff 84c83)" "$(cat "$T/d")"
eq "  ... main is untouched" "$V4" "$(on_branch main)"
jq -r '.prs[] | select(.number == 5) | .body' "$GH_DB" > "$T/body5"
diff <(printf '%s\n' "$PENDING_BODY") "$T/body5" > "$T/d"
eq "  ... one line naming Milestone 1 added to that pull request's body, after Milestone 4's" \
    "$(printf '%s\n' '3a4' '> - Milestone 1, Loader: Completed; Delivered: #12')" "$(cat "$T/d")"
eq "  ... the record still holds one pending edit, Milestone 4's" "1 Milestone 4 [#5](https://github.com/acme/widgets/pull/5)" \
    "$(live | jq -r '"\(.side_effects | length) \(.side_effects[0].target)"')"
eq "  ... and now owes Milestone 1's verdict, Who none with no holding" "none|verdict owed since $TODAY" "$(owed 'Milestone 1')"
# Folding again changes nothing: the branch reads Completed.
SNAP=$(session_snapshot "$SR")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "  ... run again it says Milestone 1 already reads Completed there" "0 verdict-owed Milestone 1
Milestone 1 already reads Completed on the pending roadmap edit https://github.com/acme/widgets/pull/5" "$rc $OUT"
eq "  ... and writes nothing" "$SNAP 0" "$(session_snapshot "$SR") $(writes)"

# A gh in front of the stand-in that moves the pending branch to SHA_OTHER on
# its second head read (after the script read the branch, before it commits),
# and with MOVE_MERGED=1 also merges the pending edit into main.
mkdir -p "$T/move"
cat > "$T/move/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *"git/ref/heads/$PENDING_BRANCH"*)
        n=\$(cat "$T/move.count" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$T/move.count"
        if [ "\$n" = 2 ]; then
            jq --arg b "$PENDING_BRANCH" --arg s "$SHA_OTHER" --arg o "$SHA_HEAD" --arg k "$KEY" --arg f "$ROADMAP" --argjson m "\${MOVE_MERGED:-0}" '
                .branches["acme/widgets"][\$b] = \$s | .commits[\$s] = {tree: "7777777777777777777777777777777777777777", parents: [\$o]}
                | if \$m == 1 then (.prs[] | select(.number == 5)).state = "MERGED"
                    | .files["acme/widgets"][\$k] = .files["acme/widgets"][\$b + ":" + \$f] else . end' "$GH_DB" > "$GH_DB.mv" && mv "$GH_DB.mv" "$GH_DB"
        fi ;;
esac
exec "$HERE/testdata/gh" "\$@"
EOF
chmod +x "$T/move/gh"

echo "== the pending branch moved after the read, its pull request still open =="
pending_seed
rm -f "$T/move.count"
SNAP=$(session_snapshot "$SR")
reset_calls
PATH="$T/move:$PATH" bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' >/dev/null 2>"$T/err"; rc=$?
eq "--unit refuses" 65 "$rc"
grep -q "moved to $SHA_OTHER" "$T/err" && ok "  ... naming the moved head" || bad "  ... naming the moved head" "$(cat "$T/err")"
eq "  ... with no commit, no pull request and no body edit" 0 "$(writes)"
eq "  ... the branch as the move left it" "$SHA_OTHER" "$(jq -r --arg b "$PENDING_BRANCH" '.branches["acme/widgets"][$b]' "$GH_DB")"
eq "  ... and the record unchanged" "$SNAP" "$(session_snapshot "$SR")"

echo "== the pending branch moved after the read, its pull request merged meanwhile =="
pending_seed
rm -f "$T/move.count"
reset_calls
OUT=$(MOVE_MERGED=1 PATH="$T/move:$PATH" bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "--unit opens a new pull request" "0 verdict-owed Milestone 1
https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... nothing committed on the merged edit's branch" "$SHA_OTHER" "$(jq -r --arg b "$PENDING_BRANCH" '.branches["acme/widgets"][$b]' "$GH_DB")"
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
on_branch "$PRB" > "$T/written-merged.md"
diff <(printf '%s\n' "$V4_M4") "$T/written-merged.md" > "$T/d"
eq "  ... from the default branch as it is now (Milestone 4 merged), with Milestone 1's Completed" "$(m1_diff 84c83)" "$(cat "$T/d")"
eq "  ... the new edit's row beside the merged one's" "Milestone 4 [#5](https://github.com/acme/widgets/pull/5),Milestone 1 [#8](https://github.com/acme/widgets/pull/8)" \
    "$(live | jq -r '[.side_effects[].target] | join(",")')"
eq "  ... the merged edit's body untouched" "$PENDING_BODY" "$(jq -r '.prs[] | select(.number == 5) | .body' "$GH_DB")"

echo "== a pending edit merged before the read: a new pull request =="
pending_seed
db '(.prs[] | select(.number == 5)).state = "MERGED" | .files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "$V4_M4"
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "--unit opens its own" "0 verdict-owed Milestone 1
https://github.com/acme/widgets/pull/8" "$rc $OUT"

echo "== refusals =="
seed
SNAP=$(session_snapshot "$SR")
reset_calls
bash "$RS" "${W[@]}" --unit 'Milestone 3' --outcome '#12' >/dev/null 2>"$T/err"; eq "a Verified milestone is refused" 65 $?
grep -q 'Milestone 3 already reads Verified' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
bash "$RS" "${W[@]}" --unit 'Milestone 9' --outcome '#12' >/dev/null 2>"$T/err"; eq "a tag that isn't a milestone is refused" 65 $?
bash "$RS" "${W[@]}" --unit 'Milestone 1' >/dev/null 2>"$T/err"; eq "--unit without --outcome is a usage error" 64 $?
eq "  ... none writes anything" "$SNAP 0" "$(session_snapshot "$SR") $(writes)"

echo "== the status table's word =="
# The block and the Progress row read the word the table's finished move
# gives, which validate's block-versus-row check compares exactly.
# move <status> <trigger>: lib_status_move, in a subshell that sourced
# state-common.sh, so its variables stay out of this suite's.
move() { (PROG=move; . "$HERE/state-common.sh"; lib_status_move "$@"); }
eq "lib_status_move: In progress on finished" Completed "$(move 'In progress' finished)"
eq "  ... Not started on finished" Completed "$(move 'Not started' finished)"
move Verified finished > /dev/null; eq "  ... Verified moves nowhere on finished" 1 $?
move 'Done' finished > /dev/null; eq "  ... a word that names no status moves nowhere" 1 $?
eq "  ... Completed on reopen" "In progress" "$(move Completed reopen)"
mkdir -p "$T/badtable/skills/coordinate/scripts" "$T/badtable/skills/roadmap/references"
cp "$HERE/state-common.sh" "$HERE/milestone.sh" "$T/badtable/skills/coordinate/scripts/"
jq -c 'del(.transitions)' "$HERE/../../roadmap/references/milestone-statuses.json" > "$T/badtable/skills/roadmap/references/milestone-statuses.json"
(HERE="$T/badtable/skills/coordinate/scripts" PROG=move; . "$HERE/state-common.sh"; lib_status_move 'In progress' finished) > /dev/null 2>"$T/err"
eq "  ... a table with no transition list is 2" 2 $?
grep -q 'no v4 transition list' "$T/err" && ok "  ... naming the table" || bad "  ... naming the table" "$(cat "$T/err")"
eq "the written block and row read it" "Completed Completed" \
    "$(sed -n '/^### Milestone 1:/,/^### Milestone 2:/p' "$T/written-new.md" | sed -n 's/^\*\*Status:\*\* //p') $(grep '^| Milestone 1: Loader |' "$T/written-new.md" | cut -d'|' -f3 | tr -d ' ')"

# With SHIRABE_VALIDATE naming a shirabe that reads roadmap/v4 (a build of
# this tree), each written roadmap validates; run-tests.sh's PATH has none.
if [ -n "${SHIRABE_VALIDATE:-}" ]; then
    for f in written-new written-fold written-merged; do
        "$SHIRABE_VALIDATE" validate "$T/$f.md" > "$T/v.out" 2>&1; rc=$?
        eq "shirabe validate passes on the $f roadmap" 0 "$rc"; [ "$rc" = 0 ] || cat "$T/v.out"
    done
fi

echo "== roadmap/v3 and roadmap/v1 as before =="
V3=$(printf '%s\n' "$V4" | sed -e 's#^schema: roadmap/v4#schema: roadmap/v3#' -e 's/^\*\*Status:\*\* Verified/**Status:** Done/' -e 's/| ~~Verified~~ |/| ~~Done~~ |/')
seed
db '.files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "$V3"
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit 'Milestone 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "roadmap/v3: --unit prints only the verdict owed" "0 verdict-owed Milestone 1" "$rc $OUT"
eq "  ... opens nothing" "0 0" "$(writes) $(jq '.prs | length' "$GH_DB")"
eq "  ... and writes the row" "plugin-loader|verdict owed since $TODAY" "$(owed 'Milestone 1')"
V1=$(printf '%s\n' '---' 'schema: roadmap/v1' 'status: Active' '---' '' '# ROADMAP: plugins' '' '## Features' '' \
    '### Feature 1: the loader' '**Dependencies:** None' '**Status:** In progress' '' '## Progress' '' 'Started.')
seed
db '.files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "$V1"
OUT=$(bash "$RS" "${W[@]}" --unit 'Feature 1' --outcome '#12' 2>"$T/err"); rc=$?
eq "roadmap/v1: --unit opens the Done pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
eq "  ... setting Done" "**Status:** Done" "$(on_branch "$(jq -r '.prs[0].headRefName' "$GH_DB")" | grep '^\*\*Status')"
eq "  ... with no verdict-owed row" none "$(owed 'Feature 1')"

done_tests roadmap-status-v4_test
