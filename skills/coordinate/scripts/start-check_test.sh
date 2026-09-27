#!/usr/bin/env bash
# start-check_test.sh -- start-check.sh reads the roadmap's status from the
# host's default branch.
#
# Covers: Active; Draft; a missing file; a quoted "Active"; a lowercase
# `active` (case-sensitive, so not Active); no status line; a status outside
# the frontmatter; a status value that isn't a word; the file read from the
# default branch (not another branch); discipline scope with no GitHub read;
# a failed read (exit 2); a path outside docs/roadmaps/ (64); the path taken
# from the session's ROADMAP variable; the sealed token.
#
# Usage: bash skills/coordinate/scripts/start-check_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
SC="$HERE/start-check.sh"
P=docs/roadmaps/ROADMAP-plugin-system.md
RM=(--scope roadmap --name plugin-system --repo "$REPO" --no-seal)

file() { # file <branch> <text>
    db '.files["acme/widgets"][$k] = $t' --arg k "$1:$P" --arg t "$2"
}
check() { local o rc; o=$(bash "$SC" "${RM[@]}" "$@" 2>"$T/err"); rc=$?; [ -z "$o" ] || seen "$o"; return $rc; }
fm() { printf -- '---\nschema: roadmap/v1\n%s\n---\n\n# Roadmap\n\nstatus: Active\n' "$1"; }

db_init
file main "$(fm 'status: Active')"
eq "an Active roadmap is active" active "$(check)"
grep -q "contents/$P?ref=main" "$GH_DB.calls" && ok "it reads the default branch" || bad "it reads the default branch" "$(calls)"
db_init; file main "$(fm 'status: Draft')"
eq "a Draft roadmap is not active" "not-active Draft" "$(check)"
db_init
eq "a missing roadmap is not-active missing" "not-active missing" "$(check)"
db_init; file feat "$(fm 'status: Active')"; file main "$(fm 'status: Planned')"
eq "an Active copy on another branch doesn't count" "not-active Planned" "$(check)"
db_init; file main "$(fm 'status: "Active"')"
eq "a quoted Active is active" active "$(check)"
db_init; file main "$(fm 'status: active')"
eq "the status is case-sensitive" "not-active active" "$(check)"
db_init; file main "$(fm 'title: x')"
eq "no status line is unset (a status below the frontmatter doesn't count)" "not-active unset" "$(check)"
db_init; file main "$(fm 'status: Active; rm -rf /')"
eq "a status that isn't a word is other" "not-active other" "$(check)"
db_init; db '.fail = [{match: "contents/", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
check >/dev/null; eq "a failed read exits 2" 2 $?
bash "$SC" "${RM[@]}" --roadmap ../etc/ROADMAP-x.md >/dev/null 2>&1; eq "a path outside docs/roadmaps/ is a usage error" 64 $?
bash "$SC" "${RM[@]}" --roadmap docs/roadmaps/../ROADMAP-x.md >/dev/null 2>&1; eq "a path with .. is a usage error" 64 $?

db_init; reset_calls
eq "discipline scope answers discipline" discipline "$(bash "$SC" --scope discipline --name ci-health --repo "$REPO" --no-seal)"
eq "without reading GitHub" "" "$(calls)"

echo "== the session =="
db_init
db '.files["acme/widgets"]["main:docs/roadmaps/v2/ROADMAP-plugin-system.md"] = $t' --arg t "$(fm 'status: Active')"
S=coordinate-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system | jq -c '.ROADMAP = "docs/roadmaps/v2/ROADMAP-plugin-system.md"')"
OUT=$(bash "$SC" --session "$S" 2>"$T/err")
seen "$OUT" > /dev/null
case "$OUT" in "active sealed:"*) ok "the session's ROADMAP path is read and the verdict sealed" ;; *) bad "the session's ROADMAP path is read and the verdict sealed" "$OUT $(cat "$T/err")" ;; esac
bash "$HERE/coord-log.sh" check --session "$S" --state start --sealed "$OUT" && ok "the seal checks against the start entry" || bad "the seal checks against the start entry"

tokens_ok start-check
done_tests start-check
