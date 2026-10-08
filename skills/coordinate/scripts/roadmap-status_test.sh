#!/usr/bin/env bash
# roadmap-status_test.sh -- roadmap-status.sh, the write-back of a landed
# feature's Status and Outcome to the roadmap as a pull request, and the
# record's row that says it is pending.
#
# Covers: --unit opens a pull request from a new branch whose only change to
# the roadmap is the feature's Status (Done), its Outcome (added after it, or
# replacing one) and its Needs line (gone), with the populate run on it; the
# Side effects row it writes and the entry that tells it; --list; a second
# --unit refused while one is pending; --confirm refused (1) while the
# roadmap on the default branch doesn't read Done, then removing the row once
# it does; --drop removing it with the reason; an outcome with backslashes, &
# and % written exactly; a CRLF roadmap keeping CRLF; the roadmap read at the
# default branch's head commit, which the branch starts from; refusals: a tag that isn't a
# feature, one already Done, a discipline scope, a malformed tag, an outcome
# over two lines; nothing is ever merged.
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
eq "only Feature 2's Needs, Status and Outcome lines change" \
    "$(printf '%s\n' '17d16' '< **Needs:** `needs-design` -- the registry shape' '19c18,19' '< **Status:** In progress' '---' '> **Status:** Done' '> **Outcome:** acme/widgets#12 and #14, the registry and its docs')" "$(cat "$T/d")"
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
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] = $r' --arg r "$(roadmap_text Done)"
bash "$RS" "${W[@]}" --confirm "Feature 2" >/dev/null 2>"$T/err"; eq "--confirm once main reads Done" 0 $?
eq "  ... removes the row" 0 "$(live | jq '.side_effects | length')"
bash "$RS" "${W[@]}" --confirm "Feature 2" >/dev/null 2>"$T/err"; eq "  ... and a second confirm finds nothing pending" 65 $?

echo "== drop =="
seed
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>&1
bash "$RS" "${W[@]}" --drop "Feature 2" --reason "the pull request was closed; the feature needs one more fix" >/dev/null 2>"$T/err"; eq "--drop removes the row" "0 0" "$? $(live | jq '.side_effects | length')"
bash "$RA" "${RM[@]}" --list | jq -e '.[-1].text | test("dropped: the pull request was closed")' >/dev/null && ok "  ... and the entry gives the reason" || bad "  ... and the entry gives the reason"

echo "== Outcome replaced, not doubled =="
seed
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] |= sub("\\*\\*Status:\\*\\* In progress"; "**Status:** In progress\n**Outcome:** an old note")'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "opened" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
eq "one Outcome line, the new one" "**Outcome:** acme/widgets#12" "$(on_branch "$PRB" | sed -n '/^### Feature 2/,/^### Feature 3/p' | grep '^\*\*Outcome')"

echo "== an outcome taken as written =="
seed
OUTC='C:\temp\new & 100% "quoted" a\\b'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "$OUTC" >/dev/null 2>"$T/err"; eq "an outcome with backslashes, & and % opens" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
eq "  ... its Outcome line exactly as given" "**Outcome:** $OUTC" "$(on_branch "$PRB" | grep '^\*\*Outcome:\*\* C:')"

echo "== a CRLF roadmap keeps its line endings =="
seed
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-plugin-system.md"] |= gsub("\n"; "\r\n")'
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "acme/widgets#12" >/dev/null 2>"$T/err"; eq "opened" 0 $?
PRB=$(jq -r '.prs[] | select(.number == 8) | .headRefName' "$GH_DB")
diff <(roadmap_text "In progress" | sed 's/$/\r/') <(on_branch "$PRB") > "$T/d"
eq "  ... only the three lines differ: the Needs and old Status lines out, Status and Outcome in" "2 2" "$(grep -c '^< ' "$T/d") $(grep -c '^> ' "$T/d")"
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
bash "$RS" "${W[@]}" --unit "the registry" --outcome x >/dev/null 2>"$T/err"; eq "a unit that isn't a heading tag is a usage error" 64 $?
bash "$RS" "${W[@]}" --unit "Feature 2" --outcome "$(printf 'two\nlines')" >/dev/null 2>"$T/err"; eq "a two-line outcome is a usage error" 64 $?
bash "$RS" --scope discipline --name ci --repo "$REPO" --ref 9 --skip-session-checks --unit "Feature 2" --outcome x >/dev/null 2>"$T/err"; eq "a discipline scope is a usage error" 64 $?
bash "$RS" "${W[@]}" --unit "Feature 2" >/dev/null 2>&1; eq "--unit without --outcome is a usage error" 64 $?
eq "no refusal opened a pull request" 0 "$(jq '.prs | length' "$GH_DB")"

done_tests roadmap-status_test
