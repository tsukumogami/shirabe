#!/usr/bin/env bash
# record-source_test.sh -- record-source.sh, the one reader of a coordinator
# record's state (docs/designs/DESIGN-coordinator-session-record.md, Decision 1),
# and the store a run is on (Decision 2).
#
# Covers:
#   1. the structure rule: no script reads a record body, parses one or reads a
#      `record/` key except the seam and the scripts named here, shown on this
#      tree and refused on a fixture script that does each;
#   2. rs_facts on a fixture record with two holdings, a hold on one's pull
#      request and a pause on the other's unit, against a fixed JSON, both as a
#      library call and through `--facts`;
#   3. the store: a `store` Run row reading `github` is read; `bogus` and a
#      doubled row are store-malformed; a `session` row, `--store session`,
#      `record-state.sh --run store session` and the session store reached
#      through rs_record each stop with store-unavailable and write nothing;
#      `--store` and a store row are refused at discipline scope;
#   4. coord/source.json: record-find.sh seals the run's store with the probe's
#      reading, and an invocation's --store is reported ignored when a record
#      exists;
#   5. the pinned interface outside readers use: on a record on the GitHub
#      store, `record-append.sh --session S --kind cost --text-file F` posts the
#      entry as a comment with its marker, and `--session S --list` reads it
#      back, with the same flags, output shape and exit codes as before.
#
# Usage: bash skills/coordinate/scripts/record-source_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PLUGIN_ROOT_REAL=$(cd "$HERE/../../.." && pwd -P)
RS="$HERE/record-source.sh"
TITLE="Coordinator record: ROADMAP-plugin-system"

# ---- 1. the structure rule ------------------------------------------------------

# body_readers <dir>: every line of a non-test script in <dir> that parses a
# record body (record-parse.sh or lib_parse without --format handoff, or
# bl_record_parsed), reads an issue's or pull request's body with gh, or reads a
# `record/` key, outside the scripts allowed to: the seam itself, the codec's own
# scripts, the find (which judges candidate bodies), the opener of a record, the
# write core (which parses the body it writes), the entry writer (which reads a
# target's declaration line) and reconcile's reader, which salvages a GitHub
# body row by row.
ALLOWED='^(record-source|record-common|record-parse|record-render|record-find|record-open|record-write-core|record-append|reconcile-read|reconcile-deps)\.sh$'
body_readers() {
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh) continue ;; esac
        [[ $base =~ $ALLOWED ]] && continue
        grep -nE 'record-parse\.sh|lib_parse |bl_record_parsed|gh (issue|pr) view.*body|context get [^|]*record/' "$f" \
            | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -- '--format handoff' | grep -v 'record-parse.sh failed' | sed "s|^|$base:|"
    done
}
echo "== 1. one reader =="
OUT=$(body_readers "$HERE")
eq "no script outside the seam reads or parses a record body" "" "$OUT"
FX="$T/fixture"; mkdir -p "$FX"
printf '#!/usr/bin/env bash\nlib_parse "$T/body.md" "$T/p.json"\n' > "$FX/a.sh"
printf '#!/usr/bin/env bash\ngh issue view 7 --repo o/r --json body > x\n' > "$FX/b.sh"
printf '#!/usr/bin/env bash\nbl_record_parsed "$S" out\n' > "$FX/c.sh"
printf '#!/usr/bin/env bash\nkoto context get "$S" record/holdings > x\n' > "$FX/d.sh"
printf '#!/usr/bin/env bash\nbash "$HERE/record-parse.sh" --format handoff f.md\n' > "$FX/e.sh"
eq "  ... and the rule refuses each way of reading one, not a handoff file" "a.sh b.sh c.sh d.sh" \
    "$(body_readers "$FX" | cut -d: -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"

# ---- 2. rs_facts --------------------------------------------------------------------

F1=$(holding worker-f1 '{"unit": "Feature 1", "branch": "feat/first", "pull_request": "[#12](https://github.com/acme/widgets/pull/12)", "verified_head": "1111111111111111111111111111111111111111"}')
F2=$(holding worker-f2 '{"unit": "Feature 2", "branch": "", "pull_request": "", "phase": "scoping-ahead"}')
REC=$(record_json roadmap plugin-system | jq -c --argjson a "$F1" --argjson b "$F2" '
    .holdings = [$a, $b]
    | .holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""},
                {hold: "other", on: "acme/widgets#99", until: "lifted", set_by: "the human", set: "2026-09-29T20:31Z", lifted: ""}]
    | .run = [{key: "arguments", value: "docs/roadmaps/ROADMAP-plugin-system.md", set_by: "the human", set: "2026-09-28T11:27Z"}]
    | .standing = [{standing: "s1", kind: "pause", on: "Feature 2", until: "lifted", what: "hold Feature 2", owner: "alice", relayed_by: "", set: "2026-09-29T17:40Z"},
                   {standing: "s2", kind: "go-ahead", on: "Feature 1", until: "", what: "one release", owner: "alice", relayed_by: "", set: "2026-09-29T17:41Z"},
                   {standing: "s3", kind: "answer", on: "", until: "", what: "panels first", owner: "alice", relayed_by: "", set: "2026-09-29T17:42Z"}]')
render "$REC" issue > "$T/rec.md"
bash "$HERE/record-parse.sh" --container issue --expect-scope roadmap:plugin-system "$T/rec.md" > "$T/rec.json" || bad "the fixture parses" ""

echo "== 2. one holding's facts =="
facts() { ( PROG=t; . "$HERE/record-common.sh"; rs_facts "$T/rec.json" "$1" ); }
GOT=$(facts worker-f1); eq "rs_facts prints" 0 $?
EXPECT_F1='{"topic":"worker-f1","unit":"Feature 1","repo":"acme/widgets","pull_request":"[#12](https://github.com/acme/widgets/pull/12)","number":"12","branch":"feat/first","verified_head":"1111111111111111111111111111111111111111","phase":"executing","dispatch_status":"dispatched","return_path":"message","holds":[{"hold":"after-release","on":"acme/widgets#12","until":"lifted","set_by":"the human","set":"2026-09-29T20:30Z","lifted":""}],"pauses":{"rows":[{"standing":"s1","kind":"pause","on":"Feature 2","until":"lifted","what":"hold Feature 2","owner":"alice","relayed_by":"","set":"2026-09-29T17:40Z"},{"standing":"s2","kind":"go-ahead","on":"Feature 1","until":"","what":"one release","owner":"alice","relayed_by":"","set":"2026-09-29T17:41Z"}],"paused":null}}'
eq "  ... worker-f1: its repository, pull request, head, its one hold, the pause rows, not paused" \
    "$EXPECT_F1" "$(printf '%s' "$GOT" | jq -c 'del(.pauses.read)')"
GOT=$(facts worker-f2)
eq "  ... worker-f2: no pull request, no hold, paused by s1" '{"number":"","holds":[],"paused":"s1","phase":"scoping-ahead"}' \
    "$(printf '%s' "$GOT" | jq -c '{number, holds, paused: .pauses.paused, phase}')"
facts worker-f9 >/dev/null; eq "  ... a topic no holding has is 1" 1 $?
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/rec.md")"
OUT=$(bash "$RS" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --facts worker-f1 2>"$T/err"); eq "--facts reads the live record" 0 $?
eq "  ... to the same facts" "$EXPECT_F1" "$(printf '%s' "$OUT" | jq -c 'del(.pauses.read)')"
grep -q '^issue view 7 --repo acme/widgets --json body --jq .body$' "$GH_DB.calls" && ok "  ... through one issue view" || bad "  ... through one issue view" "$(calls)"

# ---- 3. the store -------------------------------------------------------------------

echo "== 3. the store =="
with_store() { printf '%s' "$REC" | jq -c --arg v "$1" '.run += [{key: "store", value: $v, set_by: "alice", set: "2026-10-11T10:00Z"}]'; }
printf '%s' "$(with_store github)" | bash "$HERE/record-render.sh" --container issue --written 2026-09-26T09:00:00Z > "$T/gh.md" \
    && ok "a store row reading github renders" || bad "a store row reading github renders" ""
printf '%s' "$(with_store bogus)" | bash "$HERE/record-render.sh" --container issue >/dev/null 2>"$T/err"
grep -q 'store-malformed' "$T/err" && ok "a store reading bogus is store-malformed" || bad "a store reading bogus is store-malformed" "$(cat "$T/err")"
printf '%s' "$(with_store github)" | jq -c '.run += [{key: "store", value: "github", set_by: "alice", set: "2026-10-11T10:01Z"}]' \
    | bash "$HERE/record-render.sh" --container issue >/dev/null 2>"$T/err"
grep -q 'store-malformed' "$T/err" && ok "two store rows are store-malformed" || bad "two store rows are store-malformed" "$(cat "$T/err")"
printf '%s' "$REC" | jq -c '.run += [{key: "colour", value: "x", set_by: "alice", set: "2026-10-11T10:00Z"}]' \
    | bash "$HERE/record-render.sh" --container issue >/dev/null 2>&1; eq "any other unknown Run key is still refused" 65 $?

# A record whose store row reads session: the find stops it before reconcile.
db_init
printf '%s' "$(with_store session)" | bash "$HERE/record-render.sh" --container issue --written 2026-09-26T09:00:00Z > "$T/sess.md"
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/sess.md")"
OUT=$(bash "$HERE/record-find.sh" --scope roadmap --name plugin-system --repo "$REPO" --no-seal 2>"$T/err")
eq "the find reads a session-store record as malformed" "malformed 7" "$OUT"
grep -Eq '^(issue|pr) (edit|close|create)|api --method (POST|PATCH|PUT)' "$GH_DB.calls" && bad "  ... and writes nothing" "$(calls)" || ok "  ... and writes nothing"

# rs_record on the session store, under the test override.
( PROG=t; SCOPE=roadmap NAME=plugin-system REPO=$REPO REF=7; . "$HERE/record-common.sh"; lib_facts
  RS_SOURCE=session rs_record "$T/r" body --json body --jq .body; echo "rc=$?"; grep -q store-unavailable "$T/r.err" && echo named ) > "$T/out"
eq "rs_record on the session store stops with store-unavailable" "rc=4 named" "$(tr '\n' ' ' < "$T/out" | sed 's/ $//')"

# record-state.sh refuses to move a record now, and refuses a store at discipline scope.
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/rec.md")"
bash "$HERE/record-state.sh" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks --run store session --by alice >/dev/null 2>"$T/err"
eq "record-state.sh --run store session is refused" 65 $?
grep -q store-unavailable "$T/err" && ok "  ... as store-unavailable" || bad "  ... as store-unavailable" "$(cat "$T/err")"
grep -q '^issue edit' "$GH_DB.calls" && bad "  ... with no write" "$(calls)" || ok "  ... with no write"
bash "$HERE/record-state.sh" --scope discipline --name ci-health --repo "$REPO" --ref 7 --skip-session-checks --run store github --by alice >/dev/null 2>"$T/err"
eq "a store row at discipline scope is refused" 65 $?

# The opener: --store session and a discipline --store are refused before any koto call.
open_with() { printf '%s' "$1" > "$T/args.json"; ( cd "$T" && bash "$HERE/coordinate-open.sh" --plugin-root "$PLUGIN_ROOT_REAL" "$T/args.json" ); }
: > "$KOTO_STORE/calls"
OUT=$(open_with '["docs/roadmaps/ROADMAP-plugin-system.md", "--store", "session"]' 2>"$T/err"); rc=$?
eq "--store session is refused" "2 refused=store-unavailable" "$rc $OUT"
OUT=$(open_with '["--discipline", "ci-health", "--host", "acme/widgets", "--store", "github"]' 2>"$T/err"); rc=$?
eq "--store at discipline scope is refused" "2 refused=store-discipline" "$rc $OUT"
grep -q '^init' "$KOTO_STORE/calls" && bad "  ... and no session is opened" "$(cat "$KOTO_STORE/calls")" || ok "  ... and no session is opened"

# ---- 4. coord/source.json -----------------------------------------------------------

echo "== 4. the sealed store =="
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/gh.md")"
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system | jq -c '. + {STORE: "github"}')"
log_to "$S" start_posture record_find 2026-09-26T08:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$S" 2>"$T/err"); eq "a session find exits 0" 0 $?
SRC=$(cat "$KOTO_STORE/context/$S/coord/source.json" 2>/dev/null)
eq "coord/source.json holds the record's store" github "$(printf '%s' "$SRC" | jq -r .source)"
printf '%s' "$SRC" | jq -e '.probe | has("context_list_prefix") and has("session_import")' >/dev/null \
    && ok "  ... and the probe's reading" || bad "  ... and the probe's reading" "$SRC"
printf '%s' "$SRC" | jq -r .reason | grep -q 'is ignored: the record decides' \
    && ok "  ... and reports the invocation's --store ignored" || bad "  ... and reports the invocation's --store ignored" "$SRC"
eq "rs_source reads it" github "$(bash "$RS" --session "$S" --source 2>/dev/null)"

# ---- 5. the pinned interface outside readers use ----------------------------------

echo "== 5. cost entries on a record on the GitHub store =="
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "coord", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/gh.md")"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
found_session "$S2" "$(roadmap_vars plugin-system)" 7
printf 'cost of worker-f1\n\n```json\n{"schema":"unit-cost/1","key":"worker-f1"}\n```\n' > "$T/cost.txt"
OUT=$(bash "$HERE/record-append.sh" --session "$S2" --kind cost --text-file "$T/cost.txt" 2>"$T/err"); rc=$?
eq "record-append.sh --session S --kind cost --text-file F posts" "0 https://github.com/acme/widgets/issues/7#issuecomment-1001" "$rc $OUT"
BODY=$(jq -r '.comments[0].body' "$GH_DB")
[ "$(printf '%s' "$BODY" | head -1)" = '<!-- coordinator-record-entry v1 kind=cost -->' ] \
    && ok "  ... a comment whose first line is the cost marker the join selects on" || bad "  ... a comment whose first line is the cost marker the join selects on" "$BODY"
L=$(bash "$HERE/record-append.sh" --session "$S2" --list 2>"$T/err"); eq "record-append.sh --session S --list reads" 0 $?
eq "  ... the entry, with its kind and text" "cost|$(cat "$T/cost.txt")" "$(printf '%s' "$L" | jq -r '.[0] | "\(.kind)|\(.text)"')"
eq "  ... in the list's shape" '["author","created","edited","id","kind","stamp","text"]' "$(printf '%s' "$L" | jq -c '.[0] | keys')"

done_tests record-source
