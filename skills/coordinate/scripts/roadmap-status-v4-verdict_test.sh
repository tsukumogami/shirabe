#!/usr/bin/env bash
# roadmap-status-v4-verdict_test.sh -- roadmap-status.sh --verdict and
# --reopen on a roadmap/v4 roadmap: a verdict sets Verified or In progress,
# a reopen sets In progress, and the status table refuses the moves it
# doesn't list (docs/designs/DESIGN-completed-verified-states.md, Decision 3).
#
# Covers: a verified verdict on a Completed milestone opens one pull request
# whose diff sets its block Status and its Progress row to Verified (Needs
# gone, Delivered naming the work checked, a Progress line citing the entry),
# consumes its verdict-owed row, and writes a milestone-done row that
# --confirm clears only once main reads Verified; a verified-with-follow-ups
# verdict adds its follow-up milestone in the same pull request; a verified
# verdict needs no verdict-owed row (a Not started milestone) and doesn't ask
# the milestone's dependencies (one whose dependency is only Completed); a
# changes-needed verdict on a Completed milestone sets block and row In
# progress and prints one held-dependent line for the dependent a holding
# covers; --reopen on a Verified and on a Completed milestone sets each In
# progress in block and row, and names a dependent that reads Completed with
# no holding as `none`; refusals with nothing opened and the record
# unchanged, each naming the milestone, its status and the trigger: a
# verified or changes-needed verdict on a Verified milestone, and a verdict
# or reopen on a Dropped one; and a verdict whose checker is the delivering
# session, refused as on v1 to v3. The host doesn't opt in to workflow
# content, so no entry is posted and each Progress line cites `entry N`.
#
# Usage: bash skills/coordinate/scripts/roadmap-status-v4-verdict_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
# acme/widgets doesn't opt in: each entry stays in the session.
printf '#!/usr/bin/env bash\necho omit\n' > "$T/pr-content-reader"
export STATE_ENTRY_PR_CONTENT_READER="$T/pr-content-reader"
RS="$HERE/roadmap-status.sh"
RA="$HERE/state-entry.sh"

# A stand-in shirabe whose `roadmap populate` leaves the file as it is, so the
# diff is exactly what the script changes.
mkdir -p "$T/bin"
cat > "$T/bin/shirabe" <<EOF
#!/usr/bin/env bash
[ "\${1-} \${2-}" = "roadmap populate" ] || { echo "stand-in shirabe: unexpected call: \$*" >&2; exit 9; }
[ -f "\${3-}" ] || { echo "stand-in shirabe: no such roadmap: \${3-}" >&2; exit 2; }
exit 0
EOF
chmod +x "$T/bin/shirabe"
PATH="$T/bin:$PATH"
TODAY=$(date -u +%Y-%m-%d)

ROADMAP=docs/roadmaps/ROADMAP-plugin-system.md
KEY="main:$ROADMAP"
SR=coordinate-roadmap-plugin-system-20261122T070000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")
W=("${RM[@]}" --skip-session-checks)
SRC="Source: $ROADMAP at $SHA_MAIN"
live() { session_state "$SR"; }
on_branch() { jq -r --arg k "$1:$ROADMAP" '.files["acme/widgets"][$k] // empty' "$GH_DB"; }
writes() { grep -cE 'POST repos/[^ ]*/git/refs|PUT repos|pr create|pr edit|PATCH|comments --input' "$GH_DB.calls"; }
owed() { live | jq -r --arg t "$1" '[(.work // [])[] | select(.kind == "verdict-owed" and .item == $t) | .who][0] // "none"'; }
branch_of() { jq -r --argjson n "$1" '.prs[] | select(.number == $n) | .headRefName' "$GH_DB"; }
sha8() { (sha256sum < "$1" 2>/dev/null || shasum -a 256 < "$1") | cut -c1-8; }
write_entry() { local o; o=$(bash "$RA" "${RM[@]}" --kind "$1" --on none --text-file "$2") || return 1; echo "$((10#${o##*/}))"; }
ventry() { # ventry <file> <tag> <verdict> <checked-by> <work> <follow-ups> <changes> <clause>...
    local f=$1 tag=$2 v=$3 by=$4 work=$5 fu=$6 ch=$7 i=1; shift 7
    { printf 'Verdict: %s -- %s\nChecked by: %s\nChecked on: %s\n%s\nWork checked: %s\n\nEvidence:\n' "$tag" "$v" "$by" "$TODAY" "$SRC" "$work"
      for c in "$@"; do printf '%s. %s -- checked on a clean install\n' "$i" "$c"; i=$((i + 1)); done
      printf '\nStrategy fit: fits -- it serves the plugin bet\nFollow-ups: %s\nChanges needed: %s\n' "$fu" "$ch"; } > "$f"
}
fentry() { # fentry <file> <tag> <clause> <what>
    printf 'Failure: %s\nReported by: an operator\nSeen on: %s\nClause: %s\nWhat was seen: %s\n' "$2" "$TODAY" "$3" "$4" > "$1"
}

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

**Needs:** `needs-design` -- the list layout
**Dependencies:** None
**Status:** Completed
**Delivered:** acme/widgets#12

### Milestone 2: Registry

**Outcome:** A maintainer finds a plugin by name without reading the plugin
directory.

**Evidence:**
- A reviewer runs the find command for an installed plugin and sees its path.

**Left open:** None

**Dependencies:** Milestone 1
**Status:** In progress

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
**Status:** Not started

### Milestone 5: Archive

**Outcome:** A maintainer archives a plugin they no longer use.

**Evidence:**
- A reviewer archives a sample plugin and no longer sees it listed.

**Left open:** None

**Dependencies:** None
**Status:** Dropped

## Sequencing Rationale

The loader comes first because the registry reads what it loads.

## Progress

| Milestone | Status | Verdict |
|-----------|--------|---------|
| Milestone 1: Loader | Completed | -- |
| Milestone 2: Registry | In progress | -- |
| Milestone 3: Search | ~~Verified~~ | verified (2026-11-01) |
| Milestone 4: Docs | Not started | -- |
| Milestone 5: Archive | ~~Dropped~~ | -- |

- 2026-11-01: Milestone 3 -- verified
EOF
V4=$(cat "$T/v4.md")

# seed [roadmap-text]: main reads the roadmap; the record holds Milestone 2
# by plugin-registry and owes Milestone 1's verdict to plugin-loader, the
# session that delivered it.
seed() {
    db_init
    db '.files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "${1:-$V4}"
    db '.issues += [{repo: "acme/widgets", number: 7, title: "the plugin tracker", body: "", state: "open", author: "alice", editor: null}]'
    seed_session "$SR" "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding plugin-registry '{"unit": "Milestone 2: Registry", "pull_request": ""}')" '
        .holdings = [$h]
        | .work = [{item: "Milestone 1", kind: "verdict-owed", who: "plugin-loader", next: "verdict owed since 2026-11-21", wakes: "0", updated: "2026-11-21T09:00Z"}]')"
}
# refused <label> <want-in-stderr> <args...>: exit 65, nothing written to
# GitHub, no pull request, the record unchanged, and stderr naming WANT.
refused() {
    local label=$1 want=$2 snap rc; shift 2
    snap=$(session_snapshot "$SR")
    reset_calls
    bash "$RS" "${W[@]}" "$@" >/dev/null 2>"$T/err"; rc=$?
    if [ "$rc" = 65 ] && [ "$(writes)" = 0 ] && [ "$(jq '.prs | length' "$GH_DB")" = 0 ] && [ "$snap" = "$(session_snapshot "$SR")" ]; then
        ok "$label"
    else
        bad "$label" "rc $rc, writes $(writes), prs $(jq '.prs | length' "$GH_DB"): $(cat "$T/err")"
    fi
    grep -qF -- "$want" "$T/err" && ok "  ... naming $want" || bad "  ... naming $want" "$(cat "$T/err")"
}

echo "== a verified verdict on a Completed milestone sets it Verified =="
seed
ventry "$T/v1.txt" 'Milestone 1' verified coordinate-plugins "acme/widgets#12, acme/widgets#13" none none held
N1=$(write_entry milestone-verdict "$T/v1.txt")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict 'Milestone 1' --entry "$N1" 2>"$T/err"); rc=$?
eq "--verdict opens the roadmap pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... one pull request" 1 "$(jq '.prs | length' "$GH_DB")"
eq "  ... titled for Verified" "docs(roadmap): record Milestone 1, Loader, as verified on its verdict" "$(jq -r '.prs[] | select(.number == 8) | .title' "$GH_DB")"
PRB=$(branch_of 8)
H1=$(sha8 "$T/v1.txt")
diff "$T/v4.md" <(on_branch "$PRB") > "$T/d"
eq "  ... its diff: Needs gone, block and Progress row Verified, Delivered names #13, a Progress line citing the entry" \
    "$(printf '%s\n' '33d32' '< **Needs:** `needs-design` -- the list layout' '35,36c34,35' '< **Status:** Completed' '< **Delivered:** acme/widgets#12' '---' \
        '> **Status:** Verified' '> **Delivered:** acme/widgets#12, acme/widgets#13' '95c94' '< | Milestone 1: Loader | Completed | -- |' '---' \
        '> | Milestone 1: Loader | Verified | -- |' '101a101' "> - $TODAY: Milestone 1 -- verified, checked by coordinate-plugins (entry $N1, $H1)")" "$(cat "$T/d")"
eq "  ... main is untouched" "$V4" "$(on_branch main)"
eq "  ... the verdict-owed row goes" none "$(owed 'Milestone 1')"
eq "  ... a milestone-done row naming Verified and the entry" \
    "1|milestone-done|Milestone 1 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads Milestone 1 Verified (entry $N1)" \
    "$(live | jq -r '"\(.side_effects | length)|\(.side_effects[0].action)|\(.side_effects[0].target)|\(.side_effects[0].how_to_confirm)"')"
eq "  ... no comment posted" 0 "$(jq '.comments // [] | length' "$GH_DB")"
grep -qE 'pr merge|/merges' "$GH_DB.calls" && bad "  ... nothing is merged" || ok "  ... nothing is merged"
bash "$RS" "${W[@]}" --confirm 'Milestone 1' >/dev/null 2>"$T/err"
eq "--confirm while main still reads Completed is 1" 1 $?
db '.files["acme/widgets"][$k] = $r' --arg k "$KEY" --arg r "$(on_branch "$PRB")"
bash "$RS" "${W[@]}" --confirm 'Milestone 1' >/dev/null 2>"$T/err"; rc=$?
eq "--confirm once main reads Verified" 0 "$rc"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... clears the row" 0 "$(live | jq '.side_effects | length')"

echo "== a verified-with-follow-ups verdict adds its follow-ups in the same pull request =="
seed
ventry "$T/v2.txt" 'Milestone 1' "verified with follow-ups" coordinate-plugins "acme/widgets#12" "new: plugin export" none held
N2=$(write_entry milestone-verdict "$T/v2.txt")
cat > "$T/fu.md" <<'EOF'
### Milestone 6: plugin export

**Outcome:** A maintainer exports the list of plugins they installed.

**Evidence:**
- A reviewer exports the list and sees each installed plugin in the file.

**Left open:** the file format.

**Dependencies:** Milestone 1
EOF
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict 'Milestone 1' --entry "$N2" --follow-ups "$T/fu.md" 2>"$T/err"); rc=$?
eq "--verdict with follow-ups opens one pull request" "0 https://github.com/acme/widgets/pull/8 1" "$rc $OUT $(jq '.prs | length' "$GH_DB")"
[ "$rc" = 0 ] || cat "$T/err"
on_branch "$(branch_of 8)" > "$T/fu-written.md"
eq "  ... Milestone 1 reads Verified in its block" Verified "$(bash "$HERE/milestone.sh" evidence "$T/fu-written.md" 'Milestone 1' | jq -r .status)"
grep -qxF '| Milestone 1: Loader | Verified | -- |' "$T/fu-written.md" && ok "  ... and in its Progress row" || bad "  ... and in its Progress row" "$(grep 'Milestone 1' "$T/fu-written.md")"
eq "  ... the follow-up Milestone 6 is added, Not started" "plugin export|Not started" \
    "$(bash "$HERE/milestone.sh" evidence "$T/fu-written.md" 'Milestone 6' | jq -r '"\(.title)|\(.status)"')"
eq "  ... and the verdict-owed row goes" none "$(owed 'Milestone 1')"

echo "== a verified verdict needs no verdict-owed row, and doesn't ask the dependencies =="
seed
ventry "$T/v4n.txt" 'Milestone 4' verified coordinate-plugins "acme/widgets#21" none none held
N4=$(write_entry milestone-verdict "$T/v4n.txt")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict 'Milestone 4' --entry "$N4" 2>"$T/err"); rc=$?
eq "--verdict on a Not started milestone with no verdict-owed row opens its pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
on_branch "$(branch_of 8)" > "$T/m4.md"
eq "  ... Milestone 4 reads Verified in its block" Verified "$(bash "$HERE/milestone.sh" evidence "$T/m4.md" 'Milestone 4' | jq -r .status)"
grep -qxF '| Milestone 4: Docs | Verified | -- |' "$T/m4.md" && ok "  ... and in its Progress row" || bad "  ... and in its Progress row" "$(grep 'Milestone 4' "$T/m4.md")"
eq "  ... Milestone 1's verdict-owed row stands" plugin-loader "$(owed 'Milestone 1')"
seed
ventry "$T/v2m.txt" 'Milestone 2' verified coordinate-plugins "acme/widgets#22" none none held
NM2=$(write_entry milestone-verdict "$T/v2m.txt")
OUT=$(bash "$RS" "${W[@]}" --verdict 'Milestone 2' --entry "$NM2" 2>"$T/err"); rc=$?
eq "--verdict on Milestone 2 while Milestone 1 is only Completed opens its pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
eq "  ... Milestone 2 reads Verified" Verified "$(on_branch "$(branch_of 8)" > "$T/m2.md"; bash "$HERE/milestone.sh" evidence "$T/m2.md" 'Milestone 2' | jq -r .status)"

echo "== a changes-needed verdict sets In progress and names the held dependent =="
seed
ventry "$T/c1.txt" 'Milestone 1' "changes needed" coordinate-plugins "acme/widgets#12" none "list the versions too" "not held"
NC=$(write_entry milestone-verdict "$T/c1.txt")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict 'Milestone 1' --entry "$NC" 2>"$T/err"); rc=$?
eq "--verdict changes needed prints the pull request and one held-dependent line" "0 https://github.com/acme/widgets/pull/8
held-dependent Milestone 2 plugin-registry" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
HC=$(sha8 "$T/c1.txt")
diff "$T/v4.md" <(on_branch "$(branch_of 8)") > "$T/d"
eq "  ... its diff: block and Progress row In progress, Delivered and Needs kept, a Progress line citing the entry" \
    "$(printf '%s\n' '35c35' '< **Status:** Completed' '---' '> **Status:** In progress' '95c95' '< | Milestone 1: Loader | Completed | -- |' '---' \
        '> | Milestone 1: Loader | In progress | -- |' '101a102' "> - $TODAY: Milestone 1 -- changes needed, checked by coordinate-plugins (entry $NC, $HC)")" "$(cat "$T/d")"
eq "  ... a milestone-verdict row" "milestone-verdict|the roadmap on main carries its entry in Progress (entry $NC)" \
    "$(live | jq -r '.side_effects[0] | "\(.action)|\(.how_to_confirm)"')"
eq "  ... and the verdict-owed row goes" none "$(owed 'Milestone 1')"
reset_calls
bash "$RS" "${W[@]}" --owe-completed >/dev/null 2>"$T/err"
eq "  ... --owe-completed doesn't owe it again while its verdict's edit is pending" "0 none" "$(writes) $(owed 'Milestone 1')"

echo "== --reopen sets a Verified and a Completed milestone In progress =="
seed
fentry "$T/f3.txt" 'Milestone 3' 1 "the search missed one of the two plugins"
NF3=$(write_entry milestone-failure "$T/f3.txt")
OUT=$(bash "$RS" "${W[@]}" --reopen 'Milestone 3' --entry "$NF3" 2>"$T/err"); rc=$?
eq "--reopen on a Verified milestone opens its pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
diff "$T/v4.md" <(on_branch "$(branch_of 8)") > "$T/d"
eq "  ... its diff: block and Progress row In progress, a reopen line citing the entry" \
    "$(printf '%s\n' '61c61' '< **Status:** Verified' '---' '> **Status:** In progress' '97c97' '< | Milestone 3: Search | ~~Verified~~ | verified (2026-11-01) |' '---' \
        '> | Milestone 3: Search | In progress | verified (2026-11-01) |' '101a102' "> - $TODAY: Milestone 3 -- reopened: clause 1 failed, reported by an operator (entry $NF3, $(sha8 "$T/f3.txt"))")" "$(cat "$T/d")"
# Milestone 4 depends on Milestone 1 and reads Completed, with no holding.
seed "$(printf '%s\n' "$V4" | awk '
    /^### Milestone 4:/ { in4 = 1 } /^### Milestone 5:/ { in4 = 0 }
    in4 && /^\*\*Dependencies:\*\*/ { print "**Dependencies:** Milestone 1"; next }
    in4 && /^\*\*Status:\*\*/ { print "**Status:** Completed"; next }
    /^\| Milestone 4: Docs \|/ { print "| Milestone 4: Docs | Completed | -- |"; next }
    { print }')"
fentry "$T/f1.txt" 'Milestone 1' 1 "the list left out the third plugin"
NF1=$(write_entry milestone-failure "$T/f1.txt")
OUT=$(bash "$RS" "${W[@]}" --reopen 'Milestone 1' --entry "$NF1" 2>"$T/err"); rc=$?
eq "--reopen on a Completed milestone prints its pull request and a line per dependent that read it met" "0 https://github.com/acme/widgets/pull/8
held-dependent Milestone 2 plugin-registry
held-dependent Milestone 4 none" "$rc $OUT"
[ "$rc" = 0 ] || cat "$T/err"
on_branch "$(branch_of 8)" > "$T/r1.md"
eq "  ... Milestone 1 reads In progress in its block" "In progress" "$(bash "$HERE/milestone.sh" evidence "$T/r1.md" 'Milestone 1' | jq -r .status)"
grep -qxF '| Milestone 1: Loader | In progress | -- |' "$T/r1.md" && ok "  ... and in its Progress row" || bad "  ... and in its Progress row" "$(grep 'Milestone 1' "$T/r1.md")"
eq "  ... a milestone-reopen row" "milestone-reopen|the roadmap on main reads Milestone 1 In progress (entry $NF1)" \
    "$(live | jq -r '.side_effects[0] | "\(.action)|\(.how_to_confirm)"')"

echo "== moves the status table doesn't list are refused =="
seed
ventry "$T/x1.txt" 'Milestone 3' verified coordinate-plugins "acme/widgets#31" none none held
refused "a verified verdict on a Verified milestone" "Milestone 3 reads Verified on main, and the status table lists no move from it on verified" \
    --verdict 'Milestone 3' --entry "$(write_entry milestone-verdict "$T/x1.txt")"
ventry "$T/x2.txt" 'Milestone 3' "changes needed" coordinate-plugins "acme/widgets#31" none "find both plugins" "not held"
refused "a changes-needed verdict on a Verified milestone" "Milestone 3 reads Verified on main, and the status table lists no move from it on changes-needed" \
    --verdict 'Milestone 3' --entry "$(write_entry milestone-verdict "$T/x2.txt")"
ventry "$T/x3.txt" 'Milestone 5' verified coordinate-plugins "acme/widgets#41" none none held
refused "a verified verdict on a Dropped milestone" "Milestone 5 reads Dropped on main, and the status table lists no move from it on verified" \
    --verdict 'Milestone 5' --entry "$(write_entry milestone-verdict "$T/x3.txt")"
ventry "$T/x4.txt" 'Milestone 5' "changes needed" coordinate-plugins "acme/widgets#41" none "archive it" "not held"
refused "a changes-needed verdict on a Dropped milestone" "Milestone 5 reads Dropped on main, and the status table lists no move from it on changes-needed" \
    --verdict 'Milestone 5' --entry "$(write_entry milestone-verdict "$T/x4.txt")"
fentry "$T/x5.txt" 'Milestone 5' 1 "the archived plugin still listed"
refused "a reopen of a Dropped milestone" "Milestone 5 reads Dropped on main, and the status table lists no move from it on reopen" \
    --reopen 'Milestone 5' --entry "$(write_entry milestone-failure "$T/x5.txt")"
fentry "$T/x6.txt" 'Milestone 2' 1 "the find command showed no path"
refused "a reopen of an In progress milestone" "Milestone 2 reads In progress on main, and the status table lists no move from it on reopen" \
    --reopen 'Milestone 2' --entry "$(write_entry milestone-failure "$T/x6.txt")"

echo "== a verdict checked by the delivering session is refused =="
seed
ventry "$T/x7.txt" 'Milestone 1' verified plugin-loader "acme/widgets#12" none none held
refused "a verdict whose checker is the session that delivered the milestone" "the session that did the work never checks it" \
    --verdict 'Milestone 1' --entry "$(write_entry milestone-verdict "$T/x7.txt")"

done_tests roadmap-status-v4-verdict_test
