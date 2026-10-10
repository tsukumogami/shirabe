#!/usr/bin/env bash
# roadmap-status_test.sh -- roadmap-status.sh, the write-back of a landed
# feature's Status and Delivered line to the roadmap as a pull request, and
# the record's row that says it is pending.
#
# Covers: --unit opens a pull request from a new branch whose only change to
# the roadmap is the feature's Status (Done), its Delivered line (added after
# it, or replacing one) and its Needs line (gone), with the populate run on
# it, every Outcome line in the file left as it was; on an item with
# milestone fields, a two-line Outcome kept byte for byte while a wrapped
# Needs and an earlier Delivered go with their wrapped lines; the Side effects row it writes and
# the entry that tells it; --list; a second --unit refused while one is
# pending; --confirm refused (1) while the roadmap on the default branch
# doesn't read Done, then removing the row once it reads an annotated
# `Done -- shipped in #12`; --drop removing it with the reason; a text with
# backslashes, &, % and regex characters written exactly; a CRLF roadmap
# keeping CRLF; the roadmap read at the default branch's head commit, which
# the branch starts from; refusals: a tag that isn't a feature (a prefixed
# tag with a letter suffix reaching that check), one already Done, one
# reading `Done -- shipped` or Dropped, a discipline scope, a malformed tag,
# a text over two lines or with a carriage return; nothing is ever merged.
#
# On a roadmap/v2 (milestone) roadmap (docs/designs/DESIGN-milestone-verdicts.md):
# --unit opens nothing, writes a verdict-owed row whose Who is the holding's
# topic or none, prints `verdict-owed TAG`, and run again writes nothing; it
# refuses a tag that isn't a milestone and a milestone already Done, and a
# pending feature-style row doesn't hold it back. --verdict for a verified
# verdict opens one pull request whose diff sets Done, drops Needs, adds the
# new work to Delivered and appends the Progress line with the entry's URL and
# hash, carries the entry in its body, writes a milestone-done row and is never
# merged; for changes needed the diff is the Progress line alone and the row
# milestone-verdict; --list names each row's Action; a second edit while one
# is pending is refused; --confirm checks per Action (Done, or the entry URL
# in Progress), exits 1 until main shows it, then clears the row and the
# verdict-owed row; --drop keeps the verdict owed. Refused with nothing
# opened: no verdict-owed row, an entry check-verdict refuses, verified with
# follow-ups, a checker naming the holding worker, a checker or Work checked
# value outside its shape, an entry file over 16 KiB, an entry URL that isn't
# on the record, a Source naming another roadmap, Evidence on main that
# differs from the Evidence at Source, and a TAG outside the
# heading-tag grammar.
#
# Usage: bash skills/coordinate/scripts/roadmap-status_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/roadmap-status.sh"
RA="$HERE/record-append.sh"

# A stand-in shirabe: `roadmap populate <file>` is logged and leaves the file
# as it is, so the test sees exactly the three lines the script changes.
mkdir -p "$T/bin"
cat > "$T/bin/shirabe" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/shirabe.calls"
[ "\${1-} \${2-}" = "roadmap populate" ] || { echo "stand-in shirabe: unexpected call: \$*" >&2; exit 9; }
[ -f "\${3-}" ] || { echo "stand-in shirabe: no such roadmap: \${3-}" >&2; exit 2; }
exit 0
EOF
chmod +x "$T/bin/shirabe"
PATH="$T/bin:$PATH"

ROADMAP=docs/roadmaps/ROADMAP-plugin-system.md
roadmap_text() { # roadmap_text <feature 2 status>
    printf -- '---\nstatus: Active\n---\n\n# ROADMAP: plugins\n\n## Features\n\n### Feature 1: the loader\n**Dependencies:** None\n**Status:** Done\n**Outcome:** acme/widgets#3\n\nThe loader.\n\n### Feature 2: the registry\n**Needs:** `needs-design` -- the registry shape\n**Dependencies:** Feature 1\n**Status:** %s\n**Functional outcome:** A plugin is found by name.\n\nThe registry.\n\n### Feature 3: the docs\n**Dependencies:** Feature 2\n**Status:** Not started\n\n## Progress\n\nFeature 1 is done.\n' "$1"
}
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-plugin-system", body: $b, state: "open", author: "alice", editor: null}]
        | .files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' \
        --arg b "$(render "$(record_json roadmap plugin-system)" issue 2026-09-26T08:00:00Z)" --arg r "$(roadmap_text "In progress")"
}
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
W=("${RM[@]}" --skip-session-checks)
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }
on_branch() { jq -r --arg b "$1" '.files["acme/widgets"][$b + ":docs/roadmaps/ROADMAP-plugin-system.md"] // empty' "$GH_DB"; }

echo "== open =="
seed
OUT=$(bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12 and #14, the registry and its docs" 2>"$T/err"); rc=$?
eq "the roadmap pull request is opened" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
case "$PRB" in coordinate/roadmap-status-feature-2-[0-9]*) ok "  ... from a new coordinate/roadmap-status branch" ;; *) bad "  ... from a new coordinate/roadmap-status branch" "$PRB" ;; esac
eq "  ... against the default branch, not a draft" "main false" "$(jq -r '.prs[] | select(.number == 8) | "\(.baseRefName) \(.isDraft)"' "$GH_DB")"
eq "  ... titled for the feature" "docs(roadmap): record Feature 2, the registry, as done" "$(jq -r '.prs[] | select(.number == 8) | .title' "$GH_DB")"
jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB" | grep -qx -- '---' && ok "  ... its body has a Part 1 and a single separator" || bad "  ... its body has a Part 1 and a single separator"
diff <(roadmap_text "In progress") <(on_branch "$PRB") > "$T/d"
eq "only Feature 2's Needs and Status lines change, and a Delivered line is added" \
    "$(printf '%s\n' '17d16' '< **Needs:** `needs-design` -- the registry shape' '19c18,19' '< **Status:** In progress' '---' '> **Status:** Done' '> **Delivered:** acme/widgets#12 and #14, the registry and its docs')" "$(cat "$T/d")"
grep -q '^roadmap populate ROADMAP-plugin-system.md$' "$T/shirabe.calls" && ok "the generated sections are regenerated" || bad "the generated sections are regenerated" "$(cat "$T/shirabe.calls" 2>/dev/null)"
eq "main is untouched" "$(roadmap_text "In progress")" "$(jq -r '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"]' "$GH_DB")"
grep -qE 'pr merge|/merges|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "nothing is merged" "$(calls)" || ok "nothing is merged"
eq "the record holds the pending row" "roadmap-status|Feature 2 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads Feature 2 Done" \
    "$(live | jq -r '.side_effects[0] | "\(.action)|\(.target)|\(.how_to_confirm)"')"
eq "--list reads it" '[{"unit":"Feature 2","pull_request":"[#8](https://github.com/acme/widgets/pull/8)"}]' \
    "$(bash "$RS" "${RM[@]}" --list | jq -c 'map({unit, pull_request})')"
bash "$RA" "${RM[@]}" --list | jq -e '.[-1].kind == "roadmap-status" and (.[-1].text | test("Feature 2 landed"))' >/dev/null \
    && ok "an entry tells it" || bad "an entry tells it" "$(bash "$RA" "${RM[@]}" --list)"

echo "== one at a time =="
bash "$RS" "${W[@]}" --unit "Feature 3" --outcome x >/dev/null 2>"$T/err"; eq "a second roadmap pull request is refused while one is pending" 65 $?
grep -q 'already pending' "$T/err" && ok "  ... saying which" || bad "  ... saying which" "$(cat "$T/err")"

echo "== confirm =="
bash "$RS" "${W[@]}" --confirm "Feature 2" >/dev/null 2>"$T/err"; eq "--confirm while main doesn't read Done is 1" 1 $?
eq "  ... and leaves the row" 1 "$(live | jq '.side_effects | length')"
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(roadmap_text 'Done -- shipped in #12')"
bash "$RS" "${W[@]}" --confirm "Feature 2" >/dev/null 2>"$T/err"; eq "--confirm once main reads Done -- shipped in #12" 0 $?
eq "  ... removes the row" 0 "$(live | jq '.side_effects | length')"
bash "$RS" "${W[@]}" --confirm "Feature 2" >/dev/null 2>"$T/err"; eq "  ... and a second confirm finds nothing pending" 65 $?

echo "== drop =="
seed
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>&1
bash "$RS" "${W[@]}" --drop "Feature 2" --reason "the pull request was closed; the feature needs one more fix" >/dev/null 2>"$T/err"; eq "--drop removes the row" "0 0" "$? $(live | jq '.side_effects | length')"
bash "$RA" "${RM[@]}" --list | jq -e '.[-1].text | test("dropped: the pull request was closed")' >/dev/null && ok "  ... and the entry gives the reason" || bad "  ... and the entry gives the reason"

echo "== Delivered replaced, not doubled; Outcome kept =="
seed
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] |= sub("\\*\\*Status:\\*\\* In progress"; "**Status:** In progress\n**Outcome:** the promise\n**Delivered:** an old note")'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "opened" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
eq "one Delivered line, the new one" "**Delivered:** acme/widgets#12" "$(on_branch "$PRB" | sed -n '/^### Feature 2/,/^### Feature 3/p' | grep '^\*\*Delivered')"
eq "  ... and the Outcome line as it was" "**Outcome:** the promise" "$(on_branch "$PRB" | sed -n '/^### Feature 2/,/^### Feature 3/p' | grep '^\*\*Outcome')"

echo "== wrapped fields on a feature roadmap =="
db_init
V2=$(printf -- '---\nschema: roadmap/v1\nstatus: Active\n---\n\n# ROADMAP: plugins\n\n## Features\n\n### PS1: the loader\n**Outcome:** A plugin author installs a plugin by name\nand it loads on the next start.\n**Evidence:**\n- an author outside the team installs one\n**Needs:** `needs-design` -- the loader shape,\n  and where it reads from\n**Dependencies:** None\n**Status:** In progress\n**Delivered:** acme/widgets#3, a first cut\n  behind a flag\n**Left open:** remote plugins\n\nThe loader.\n\n### PS2: the registry\n**Outcome:** A plugin is found by name.\n**Dependencies:** PS1\n**Status:** Not started\n')
db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-plugin-system", body: $b, state: "open", author: "alice", editor: null}]
    | .files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' \
    --arg b "$(render "$(record_json roadmap plugin-system)" issue 2026-09-26T08:00:00Z)" --arg r "$V2"
bash "$RS" "${W[@]}" --unit PS1 --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "opened" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
diff <(printf '%s\n' "$V2") <(on_branch "$PRB") > "$T/d"
eq "  ... the Needs and old Delivered go with their wrapped lines; Status and Delivered are written; the two-line Outcome is untouched" \
    "$(printf '%s\n' '15,16d14' '< **Needs:** `needs-design` -- the loader shape,' '<   and where it reads from' '18,20c16,17' '< **Status:** In progress' '< **Delivered:** acme/widgets#3, a first cut' '<   behind a flag' '---' '> **Status:** Done' '> **Delivered:** acme/widgets#12')" "$(cat "$T/d")"

echo "== an outcome taken as written =="
seed
OUTC='C:\temp\new & 100% "quoted" a\\b [x]* ^$ (.+)? \1'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "$OUTC" >/dev/null 2>"$T/err"; eq "a text with backslashes, &, % and regex characters opens" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
eq "  ... its Delivered line exactly as given" "**Delivered:** $OUTC" "$(on_branch "$PRB" | grep '^\*\*Delivered:\*\* C:')"

echo "== a CRLF roadmap keeps its line endings =="
seed
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] |= gsub("\n"; "\r\n")'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "opened" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
diff <(roadmap_text "In progress" | sed 's/$/\r/') <(on_branch "$PRB") > "$T/d"
eq "  ... only the three lines differ: the Needs and old Status lines out, Status and Delivered in" "2 2" "$(grep -c '^< ' "$T/d") $(grep -c '^> ' "$T/d")"
[ "$(grep '^> ' "$T/d" | grep -c $'\r$')" = 2 ] && ok "  ... the changed lines end in CRLF" || bad "  ... the changed lines end in CRLF" "$(od -c "$T/d" | head -5)"

echo "== the branch starts at the commit the roadmap was read at =="
seed
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"
grep -q 'contents/docs/roadmaps/ROADMAP-plugin-system.md?ref=1111111111111111111111111111111111111111' "$GH_DB.calls" \
    && ok "the roadmap is read at the default branch's head commit" || bad "the roadmap is read at the default branch's head commit" "$(grep contents "$GH_DB.calls")"

echo "== refusals =="
seed
bash "$RS" "${W[@]}" --unit "Feature 9" --outcome x >/dev/null 2>"$T/err"; eq "a tag that isn't a feature is refused" 65 $?
bash "$RS" "${W[@]}" --unit "Feature 1" --outcome x >/dev/null 2>"$T/err"; eq "a feature already Done is refused" 65 $?
bash "$RS" "${W[@]}" --unit AB10a --outcome x >/dev/null 2>"$T/err"; eq "a prefixed tag with a letter suffix is a tag, refused as no feature" 65 $?
for st in 'Done -- shipped' Dropped; do
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(roadmap_text "$st")"
    bash "$RS" "${W[@]}" --unit "Feature 2" --outcome x >/dev/null 2>"$T/err"; eq "a feature reading $st is refused" 65 $?
done
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(roadmap_text "In progress")"
grep -qE 'POST|PUT|pr create' "$GH_DB.calls" && bad "  ... with nothing written" "$(calls)" || ok "  ... with nothing written"
# A feature whose scoping alone landed isn't Done: its follow-up still stands.
db '(.issues[] | select(.number == 7)).body = $b' --arg b "$(render "$(record_json roadmap plugin-system | jq -c '.work = [{item: "Feature 2", kind: "follow-up",
    who: "acme/widgets#12", next: "/shirabe:execute docs/plans/PLAN-registry.md", wakes: "0", updated: "2026-09-26T07:00Z"}]')" issue 2026-09-26T08:00:00Z)"
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "a feature with a follow-up row is refused" 65 $?
grep -q "its execution is a follow-up still to dispatch" "$T/err" && ok "  ... saying its execution is still to come" || bad "  ... saying its execution is still to come" "$(cat "$T/err")"
grep -qE 'POST|PUT|pr create' "$GH_DB.calls" && bad "  ... with nothing opened" "$(calls)" || ok "  ... with nothing opened"
seed
bash "$RS" "${W[@]}" --unit "the registry" --outcome x >/dev/null 2>"$T/err"; eq "a unit that isn't a heading tag is a usage error" 64 $?
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "$(printf 'two\nlines')" >/dev/null 2>"$T/err"; eq "a two-line outcome is a usage error" 64 $?
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "$(printf 'one\rtwo')" >/dev/null 2>"$T/err"; eq "an outcome with a carriage return is a usage error" 64 $?
bash "$RS" --scope discipline --name ci --repo "$REPO" --ref 9 --skip-session-checks --unit "Feature 2" --outcome x >/dev/null 2>"$T/err"; eq "a discipline scope is a usage error" 64 $?
bash "$RS" "${W[@]}" --unit "Feature 2" >/dev/null 2>&1; eq "--unit without --outcome is a usage error" 64 $?
eq "no refusal opened a pull request" 0 "$(jq '.prs | length' "$GH_DB")"

# ---- a milestone roadmap (docs/designs/DESIGN-milestone-verdicts.md) -------
# Written to a file first: bash 3.2 misreads a quote inside a here-document
# inside $( ).
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
mv_seed() { # mv_seed [record-json]
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-plugin-system", body: $b, state: "open", author: "alice", editor: null}]
        | .files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' \
        --arg b "$(render "${1:-$(record_json roadmap plugin-system | jq -c --argjson h "$(holding plugin-list '{"unit": "MV1: the plugin list", "pull_request": ""}')" '.holdings = [$h]')}" issue 2026-09-26T08:00:00Z)" \
        --arg r "$MV"
}
writes() { grep -cE 'POST repos/[^ ]*/git/refs|PUT repos|pr create|issue edit|PATCH' "$GH_DB.calls"; }
owed() { live | jq -r --arg t "$1" '[(.work // [])[] | select(.kind == "verdict-owed" and .item == $t) | "\(.who)|\(.next)"][0] // "none"'; }
TODAY=$(date -u +%Y-%m-%d)

echo "== a milestone roadmap: --unit marks the verdict owed =="
mv_seed
OUT=$(bash "$RS" "${W[@]}" --unit MV1 2>"$T/err"); rc=$?
eq "--unit on a roadmap/v2 milestone prints verdict-owed" "0 verdict-owed MV1" "$rc $OUT"
grep -qE 'git/refs|PUT repos|pr create' "$GH_DB.calls" && bad "  ... with no branch, commit or pull request" "$(calls)" || ok "  ... with no branch, commit or pull request"
eq "  ... a verdict-owed row, Who its holding's topic" "plugin-list|verdict owed since $TODAY" "$(owed MV1)"
eq "  ... and no Side effects row" 0 "$(live | jq '.side_effects | length')"
bash "$RA" "${RM[@]}" --list | jq -e '.[-1].kind == "roadmap-status" and (.[-1].text | test("MV1.s work is finished \\(plugin-list held it\\); its verdict is owed"))' >/dev/null \
    && ok "  ... an entry tells it" || bad "  ... an entry tells it" "$(bash "$RA" "${RM[@]}" --list | jq -c '.[-1]')"
BODY1=$(jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --unit MV1 --outcome "acme/widgets#12" 2>"$T/err"); rc=$?
eq "run again it prints the same" "0 verdict-owed MV1" "$rc $OUT"
eq "  ... and writes nothing" "$BODY1 0" "$(jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB") $(grep -c 'comments' "$GH_DB.calls" | sed 's/^[1-9].*/posted/')"
OUT=$(bash "$RS" "${W[@]}" --unit MV2 2>"$T/err"); rc=$?
eq "a milestone no holding names" "0 verdict-owed MV2" "$rc $OUT"
eq "  ... has Who none" "none|verdict owed since $TODAY" "$(owed MV2)"
bash "$RS" "${W[@]}" --unit MV9 >/dev/null 2>"$T/err"; eq "a tag that isn't a milestone is refused" 65 $?
bash "$RS" "${W[@]}" --unit MV3 >/dev/null 2>"$T/err"; eq "a milestone already Done is refused" 65 $?
eq "--list holds nothing pending" "[]" "$(bash "$RS" "${RM[@]}" --list)"
# The schema is read before any other refusal: a feature-roadmap rule (one
# roadmap pull request at a time) doesn't hold the mark back.
mv_seed "$(record_json roadmap plugin-system | jq -c '.side_effects = [{action: "roadmap-status", target: "MV3 [#5](https://github.com/acme/widgets/pull/5)", verified_head: "", attempted: "2026-09-26T07:00Z", how_to_confirm: "the roadmap on main reads MV3 Done"}]')"
OUT=$(bash "$RS" "${W[@]}" --unit MV2 2>"$T/err"); rc=$?
eq "a pending roadmap pull request doesn't hold back the mark" "0 verdict-owed MV2" "$rc $OUT"

echo "== --verdict: verified =="
mv_seed
bash "$RS" "${W[@]}" --unit MV1 >/dev/null 2>&1
bash "$RS" "${W[@]}" --unit MV2 >/dev/null 2>&1
SRC="Source: docs/roadmaps/ROADMAP-plugin-system.md at $SHA_MAIN"
ventry() { # ventry <file> <tag> <verdict> <checked-by> <work> <fit> <follow-ups> <changes> <clause>...
    local f=$1 tag=$2 v=$3 by=$4 work=$5 fit=$6 fu=$7 ch=$8 i=1; shift 8
    { printf 'Verdict: %s -- %s\nChecked by: %s\nChecked on: %s\n%s\nWork checked: %s\n\nEvidence:\n' "$tag" "$v" "$by" "$TODAY" "$SRC" "$work"
      for c in "$@"; do printf '%s. %s -- checked on a clean install\n' "$i" "$c"; i=$((i + 1)); done
      printf '\nStrategy fit: %s -- it serves the plugin bet\nFollow-ups: %s\nChanges needed: %s\n' "$fit" "$fu" "$ch"; } > "$f"
}
post() { bash "$RA" "${RM[@]}" --kind milestone-verdict --text-file "$1"; }
ventry "$T/v1.txt" MV1 verified coordinate-plugins "acme/widgets#12, acme/widgets#3" fits none none held held
URL1=$(post "$T/v1.txt")
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict MV1 --entry-file "$T/v1.txt" --entry-url "$URL1" 2>"$T/err"); rc=$?
eq "a verified verdict opens the roadmap pull request" "0 https://github.com/acme/widgets/pull/8" "$rc $OUT"
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
case "$PRB" in coordinate/roadmap-verdict-mv1-[0-9]*) ok "  ... from a new coordinate/roadmap-verdict branch" ;; *) bad "  ... from a new coordinate/roadmap-verdict branch" "$PRB" ;; esac
HASH=$( (sha256sum < "$T/v1.txt" 2>/dev/null || shasum -a 256 < "$T/v1.txt") | cut -c1-8)
diff <(printf '%s\n' "$MV") <(on_branch "$PRB") > "$T/d"
eq "  ... setting Done, dropping Needs, adding the new work to Delivered and a Progress line, and nothing else" \
    "$(printf '%s\n' '21d20' '< **Needs:** `needs-design` -- the list layout' '23,24c22,23' '< **Status:** In progress' '< **Delivered:** acme/widgets#3' '---' '> **Status:** Done' '> **Delivered:** acme/widgets#3, acme/widgets#12' '52a52' "> - $TODAY: MV1 -- verified, checked by coordinate-plugins ($URL1, $HASH)")" "$(cat "$T/d")"
jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB" | grep -qxF '> Verdict: MV1 -- verified' && ok "  ... its body carries the entry" || bad "  ... its body carries the entry" "$(jq -r '.prs[] | select(.number == 8) | .body' "$GH_DB")"
eq "  ... titled for the milestone" "docs(roadmap): record MV1, the plugin list, as done on its verdict" "$(jq -r '.prs[] | select(.number == 8) | .title' "$GH_DB")"
grep -qE 'pr merge|/merges|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "  ... never merged" "$(calls)" || ok "  ... never merged"
eq "  ... a milestone-done row" "milestone-done|MV1 [#8](https://github.com/acme/widgets/pull/8)|the roadmap on main reads MV1 Done" \
    "$(live | jq -r '.side_effects[0] | "\(.action)|\(.target)|\(.how_to_confirm)"')"
eq "--list names its Action" '[{"unit":"MV1","action":"milestone-done"}]' "$(bash "$RS" "${RM[@]}" --list | jq -c 'map({unit, action})')"
eq "  ... and the verdict stays owed" "plugin-list|verdict owed since $TODAY" "$(owed MV1)"
ventry "$T/v2.txt" MV2 "changes needed" coordinate-plugins none fits none "answer on the public name" "not held"
URL2=$(post "$T/v2.txt")
bash "$RS" "${W[@]}" --verdict MV2 --entry-file "$T/v2.txt" --entry-url "$URL2" >/dev/null 2>"$T/err"; eq "a second edit while one is pending is refused" 65 $?
bash "$RS" "${W[@]}" --confirm MV1 >/dev/null 2>"$T/err"; eq "--confirm while main doesn't read Done is 1" 1 $?
eq "  ... and keeps the mark" "plugin-list|verdict owed since $TODAY" "$(owed MV1)"
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(on_branch "$PRB")"
bash "$RS" "${W[@]}" --confirm MV1 >/dev/null 2>"$T/err"; eq "--confirm once main reads Done" 0 $?
eq "  ... removes the row and the verdict-owed mark" "0 none" "$(live | jq '.side_effects | length') $(owed MV1)"

echo "== --verdict: changes needed =="
reset_calls
OUT=$(bash "$RS" "${W[@]}" --verdict MV2 --entry-file "$T/v2.txt" --entry-url "$URL2" 2>"$T/err"); rc=$?
eq "a changes-needed verdict opens the roadmap pull request" "0 https://github.com/acme/widgets/pull/9" "$rc $OUT"
PRB2=$(jq -r '.prs[] | select(.number == 9) | .headRefName' "$GH_DB")
HASH2=$( (sha256sum < "$T/v2.txt" 2>/dev/null || shasum -a 256 < "$T/v2.txt") | cut -c1-8)
diff <(jq -r '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"]' "$GH_DB") <(on_branch "$PRB2") > "$T/d"
eq "  ... adding only the Progress line: Status and Delivered unchanged" \
    "$(printf '%s\n' '52a53' "> - $TODAY: MV2 -- changes needed, checked by coordinate-plugins ($URL2, $HASH2)")" "$(cat "$T/d")"
eq "  ... a milestone-verdict row" "milestone-verdict|the roadmap on main carries $URL2 in Progress" \
    "$(live | jq -r '.side_effects[0] | "\(.action)|\(.how_to_confirm)"')"
grep -qE 'pr merge|/merges|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "  ... never merged" "$(calls)" || ok "  ... never merged"
bash "$RS" "${W[@]}" --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm before main carries the line is 1" 1 $?
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(on_branch "$PRB2")"
bash "$RS" "${W[@]}" --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm once main carries the entry in Progress" 0 $?
jq -r '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"]' "$GH_DB" > "$T/main.md"
eq "  ... removes the row and the mark; MV2 still reads In progress" "0 none In progress" \
    "$(live | jq '.side_effects | length') $(owed MV2) $(bash "$HERE/milestone.sh" evidence "$T/main.md" MV2 | jq -r .status)"

echo "== --verdict: refusals =="
mv_seed
bash "$RS" "${W[@]}" --unit MV1 >/dev/null 2>&1
vrefuse() { # vrefuse <label> <tag> <entry-file> [url]
    local u=${4-}
    [ -n "$u" ] || u=$(post "$3")
    reset_calls
    bash "$RS" "${W[@]}" --verdict "$2" --entry-file "$3" --entry-url "$u" >/dev/null 2>"$T/err"; local rc=$?
    if [ $rc = 65 ] && [ "$(writes)" = 0 ]; then ok "$1"; else bad "$1" "rc $rc, writes $(writes): $(cat "$T/err")"; fi
}
ventry "$T/r.txt" MV2 verified coordinate-plugins none fits none none held
vrefuse "a milestone with no verdict-owed row" MV2 "$T/r.txt"
grep -q 'MV2 has no verdict-owed row' "$T/err" && ok "  ... saying so" || bad "  ... saying so" "$(cat "$T/err")"
ventry "$T/r.txt" MV1 verified coordinate-plugins none fits none none held
vrefuse "an entry check-verdict refuses (a clause count other than the milestone's)" MV1 "$T/r.txt"
grep -q 'line 8: the entry judges 1 clause' "$T/err" && ok "  ... naming the line" || bad "  ... naming the line" "$(cat "$T/err")"
ventry "$T/r.txt" MV1 "verified with follow-ups" coordinate-plugins none fits "new: a plugin search" none held held
vrefuse "a verified-with-follow-ups verdict, until its follow-ups can be written" MV1 "$T/r.txt"
ventry "$T/r.txt" MV1 verified "Plugin-List relayed" none fits none none held held
vrefuse "a checker naming the holding worker's topic" MV1 "$T/r.txt"
ventry "$T/r.txt" MV1 verified "a/b" none fits none none held held
vrefuse "a checker outside its closed shape" MV1 "$T/r.txt"
ventry "$T/r.txt" MV1 verified coordinate-plugins "acme/widgets 12" fits none none held held
vrefuse "a Work checked value outside its closed shape" MV1 "$T/r.txt"
ventry "$T/r.txt" MV1 verified coordinate-plugins none fits none none held held
{ cat "$T/r.txt"; head -c 17000 /dev/zero | tr '\0' 'x'; } > "$T/big.txt"
vrefuse "an entry file over 16 KiB" MV1 "$T/big.txt" "https://github.com/acme/widgets/issues/7#issuecomment-1001"
vrefuse "an entry URL that isn't a comment on the record" MV1 "$T/r.txt" "https://github.com/acme/widgets/issues/8#issuecomment-1001"
sed "s|^Source: .*|Source: docs/roadmaps/ROADMAP-other.md at $SHA_MAIN|" "$T/r.txt" > "$T/r2.txt"
vrefuse "a Source naming another roadmap" MV1 "$T/r2.txt"
# Evidence sharpened on main since the entry's Source: the clauses it judged
# are not the ones main carries now.
db '.files["acme/widgets"][$k] = $t' --arg k "$SHA_OTHER:docs/roadmaps/ROADMAP-plugin-system.md" --arg t "$MV"
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] |= sub("named as skipped"; "named as skipped, with the reason")'
sed "s|^Source: .*|Source: docs/roadmaps/ROADMAP-plugin-system.md at $SHA_OTHER|" "$T/r.txt" > "$T/r3.txt"
vrefuse "Evidence on main that differs from the Evidence at Source" MV1 "$T/r3.txt"
grep -q "differs from its Evidence at the entry's Source" "$T/err" && ok "  ... saying to check the clauses again" || bad "  ... saying to check the clauses again" "$(cat "$T/err")"
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $t' --arg t "$MV"
bash "$RS" "${W[@]}" --verdict "not a tag" --entry-file "$T/r.txt" --entry-url "https://github.com/acme/widgets/issues/7#issuecomment-1001" >/dev/null 2>"$T/err"
eq "a TAG outside the heading-tag grammar is refused" 65 $?
eq "no refusal opened a pull request" 0 "$(jq '.prs | length' "$GH_DB")"
bash "$RS" "${W[@]}" --verdict MV1 --entry-file "$T/r.txt" >/dev/null 2>&1; eq "--verdict without --entry-url is a usage error" 64 $?
bash "$RS" "${W[@]}" --verdict MV1 --entry-file "$T/r.txt" --entry-url x --outcome y >/dev/null 2>&1; eq "--verdict with --outcome is a usage error" 64 $?

echo "== --drop keeps the verdict owed =="
URLR=$(post "$T/r.txt")
bash "$RS" "${W[@]}" --verdict MV1 --entry-file "$T/r.txt" --entry-url "$URLR" >/dev/null 2>"$T/err"; eq "the verdict's edit opens" 0 $?
bash "$RS" "${W[@]}" --drop MV1 --reason "closed unmerged: the reviewer wants a second look" >/dev/null 2>"$T/err"; eq "--drop removes its row" "0 0" "$? $(live | jq '.side_effects | length')"
eq "  ... and the verdict is still owed" "plugin-list|verdict owed since $TODAY" "$(owed MV1)"

done_tests roadmap-status_test
