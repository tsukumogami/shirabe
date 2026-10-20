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
#      doubled row are store-malformed; on a `session` row the find stops on a
#      koto without the session store's features (store-unsupported), without
#      the owner's run entry (store-unverified), and on a moved record this
#      run's session doesn't hold (session-absent); with the entry it is a
#      move, and a moved record the session holds is found on the session
#      store; a GitHub record while a session here holds the scope's state is
#      store-conflict; record-state.sh writes the owner's row with its run
#      entry; `--store` and a store row are refused at discipline scope;
#   4. coord/source.json: record-find.sh writes the run's store with the probe's
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

# body_readers <dir>: every line of a non-test script in <dir> that reads a
# record's body or keys, or parses a body, outside the scripts allowed to.
#   Reading: a gh issue/pr view (any spelling of the container) that asks for
#   the body, or a `record/` key. Allowed: the seam; the find, which judges the
#   candidate bodies the open-issue listing returns; the entry writer, which
#   reads a target's declaration line.
#   Parsing: record-parse.sh or lib_parse (a handoff file aside), or
#   bl_record_parsed. Allowed: the seam and the codec's scripts; the find; the
#   opener of a new record and the write core, which parse the body they are
#   about to write; and reconcile's reader, which salvages row by row a body the
#   seam handed it, with the parser reconcile-deps.sh names.
READ_ALLOWED='^(record-source|record-find|record-append)\.sh$'
PARSE_ALLOWED='^(record-source|record-common|record-parse|record-render|record-find|record-open|record-write-core|reconcile-read|reconcile-deps)\.sh$'
body_readers() {
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh) continue ;; esac
        if ! [[ $base =~ $READ_ALLOWED ]]; then
            grep -nE 'gh ("?\$[A-Za-z_{}]+"?|issue|pr) view.*body|context get [^|]*record/' "$f" \
                | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
        fi
        if ! [[ $base =~ $PARSE_ALLOWED ]]; then
            grep -nE 'record-parse\.sh|lib_parse |bl_record_parsed' "$f" \
                | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -- '--format handoff' | grep -v 'record-parse.sh failed' | sed "s|^|$base:|"
        fi
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
printf '#!/usr/bin/env bash\ngh "$CONTAINER" view "$REF" --repo "$REPO" --json state,body > x\n' > "$FX/f.sh"
eq "  ... and the rule refuses each way of reading one, not a handoff file" "a.sh b.sh c.sh d.sh f.sh" \
    "$(body_readers "$FX" | cut -d: -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"

# The move's write paths (docs/designs/DESIGN-coordinator-session-record.md,
# Decision 11): MOVE_WRITER, which lifts the section-owner checks and the
# store-moved refusal, is set only by the move; SESSION_SEED, the first write
# into an empty session, only by the move and the opener of a session-store
# record.
flag_setters() { # flag_setters <dir> <flag> <allowed-regex>: scripts that set flag=1 outside the allowed ones
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh|record-write-core.sh) continue ;; esac
        [[ $base =~ $3 ]] && continue
        grep -nE "(^|[^A-Za-z_])$2=1" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
    done
}
eq "only record-move.sh sets MOVE_WRITER" "" "$(flag_setters "$HERE" MOVE_WRITER '^record-move\.sh$')"
eq "only record-move.sh and record-open.sh set SESSION_SEED" "" "$(flag_setters "$HERE" SESSION_SEED '^(record-move|record-open)\.sh$')"
printf '#!/usr/bin/env bash\n. "$HERE/record-write-core.sh"\nMOVE_WRITER=1 SESSION_SEED=1\ncore_write\n' > "$FX/g.sh"
eq "  ... and the rule refuses a script that sets either" "g.sh g.sh" \
    "$( { flag_setters "$FX" MOVE_WRITER '^record-move\.sh$'; flag_setters "$FX" SESSION_SEED '^(record-move|record-open)\.sh$'; } | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//')"
# record/host (Decision 9; PRD R14, R17) is written only by record-state.sh
# --host, through core_write_host.
fn_callers() { # fn_callers <dir> <function> <allowed-regex>: scripts that call it outside the allowed ones
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh|record-write-core.sh) continue ;; esac
        [[ $base =~ $3 ]] && continue
        grep -nE "(^|[^A-Za-z_])$2([^A-Za-z_]|$)" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
    done
}
eq "only record-state.sh calls core_write_host" "" "$(fn_callers "$HERE" core_write_host '^record-state\.sh$')"
# A holding's pushed head is set only through record-write.sh --pushed-head.
eq "only record-write.sh sets CORE_PUSHED_SET" "" "$(flag_setters "$HERE" CORE_PUSHED_SET '^record-write\.sh$')"
printf '#!/usr/bin/env bash\n. "$HERE/record-write-core.sh"\ncore_write_host "$f"\n' > "$FX/h.sh"
eq "  ... and the rule refuses a script that calls it" "h.sh" "$(fn_callers "$FX" core_write_host '^record-state\.sh$' | cut -d: -f1)"

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

# A record whose store row reads session and that still holds its state tables.
# FIND <session> <vars-json> [env...]: the find as the template's action runs it.
FIND() { local s=$1 v=$2; shift 2; log_new "$s" "$v"; log_to "$s" start_posture record_find 2026-09-26T07:01:00.000Z
    env "$@" bash "$HERE/record-find.sh" --session "$s" 2>"$T/err" | sed 's/ sealed:.*//'; }
SRCOF() { jq -r '"\(.source)|\(.reason)"' "$KOTO_STORE/context/$1/coord/source.json"; }
db_init
printf '%s' "$(with_store session)" | bash "$HERE/record-render.sh" --container issue --written 2026-09-26T09:00:00Z > "$T/sess.md"
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/sess.md")"
SU=coordinate-roadmap-plugin-system-20260926T070000Z
eq "on a koto without the session store's features the find stops" "malformed 7" "$(FIND "$SU" "$(roadmap_vars plugin-system)")"
case "$(SRCOF "$SU")" in "session|store-unsupported: this koto lacks context list --prefix, session import"*) ok "  ... naming what is missing, its store still session (R2)" ;;
    *) bad "  ... naming what is missing, its store still session (R2)" "$(SRCOF "$SU")" ;; esac
koto context exists "$SU" record/meta && bad "  ... with no key written" "" || ok "  ... with no key written"
grep -Eq '^(issue|pr) (edit|close|create)|api --method (POST|PATCH|PUT)' "$GH_DB.calls" && bad "  ... and no GitHub change" "$(calls)" || ok "  ... and no GitHub change"
SV=coordinate-roadmap-plugin-system-20260926T070100Z
eq "with no run entry recording the row, the find stops" "malformed 7" "$(FIND "$SV" "$(roadmap_vars plugin-system)" KOTO_FEATURES=1)"
jq -r .reason "$KOTO_STORE/context/$SV/coord/record_find.json" | grep -q '^store-unverified' \
    && ok "  ... as store-unverified" || bad "  ... as store-unverified" "$(cat "$KOTO_STORE/context/$SV/coord/record_find.json")"
db '.comments = [{repo: "acme/widgets", number: 7, id: 900, user: "coord", created_at: "2026-10-11T10:00:05Z", updated_at: "2026-10-11T10:00:05Z",
    body: "<!-- coordinator-record-entry v1 kind=run -->\n**2026-10-11T10:00:05Z** (host clock) run\n\nRun store set to session by alice."}]'
SM=coordinate-roadmap-plugin-system-20260926T070200Z
eq "with the owner's run entry, it is a move (R3)" "move 7" "$(FIND "$SM" "$(roadmap_vars plugin-system)" KOTO_FEATURES=1)"
case "$(SRCOF "$SM")" in "session|the record's store row reads session"*) ok "  ... on the session store" ;; *) bad "  ... on the session store" "$(SRCOF "$SM")" ;; esac
log_capture "$SM" RECORD_FIND "$(KOTO_FEATURES=1 bash "$HERE/record-find.sh" --session "$SM" 2>/dev/null)" 2026-09-26T07:01:00.000Z
eq "  ... and the run's facts and store read it" "7|session" \
    "$(bash "$HERE/coord-log.sh" run-facts --session "$SM" 2>/dev/null | jq -r .ref)|$(bash "$HERE/coord-log.sh" run-store --session "$SM")"
# A record in the moved shape.
jq -nc '{scope: {kind: "roadmap", name: "plugin-system"}, holdings: [], deferrals: [], side_effects: [], reversals: [],
    run: [{key: "store", value: "session", set_by: "alice", set: "2026-10-11T10:00Z"}]}' \
    | bash "$HERE/record-render.sh" --container issue --written 2026-10-11T10:05:00Z > "$T/moved.md"
db '.issues[0].body = $b | .comments = []' --arg b "$(cat "$T/moved.md")"
SA=coordinate-roadmap-plugin-system-20260926T070300Z
eq "a moved record this run's session doesn't hold stops the find" "malformed 7" "$(FIND "$SA" "$(roadmap_vars plugin-system)" KOTO_FEATURES=1)"
case "$(SRCOF "$SA")" in "session|session-absent: "*) ok "  ... as session-absent, on the session store" ;; *) bad "  ... as session-absent, on the session store" "$(SRCOF "$SA")" ;; esac
SH=coordinate-roadmap-plugin-system-20260926T070400Z
bash "$HERE/record-parse.sh" --container issue "$T/rec.md" > "$T/held.json"
session_keys "$SH" "$T/held.json"
eq "a moved record this run's session holds is found on the session store" "found 7 session" "$(FIND "$SH" "$(roadmap_vars plugin-system)" KOTO_FEATURES=1)"
eq "  ... which coord/source.json names" "session|the record's store" "$(SRCOF "$SH")"
# A GitHub record while a session of this scope here holds the state.
db '.issues[0].body = $b' --arg b "$(cat "$T/gh.md")"
SC=coordinate-roadmap-plugin-system-20260926T070500Z
eq "a GitHub record while a session here holds the scope's state stops the find" "malformed 7" "$(FIND "$SC" "$(roadmap_vars plugin-system)" KOTO_FEATURES=1)"
case "$(SRCOF "$SC")" in "github|store-conflict: #7 reads store github, but session $SH"*) ok "  ... as store-conflict, naming the session" ;; *) bad "  ... as store-conflict, naming the session" "$(SRCOF "$SC")" ;; esac
rm -rf "${KOTO_STORE:?}/context/$SH/record"

# record-state.sh writes the owner's row, telling it as a run entry, and refuses
# a store at discipline scope.
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/rec.md")"
bash "$HERE/record-state.sh" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks --run store session --by alice >/dev/null 2>"$T/err"
eq "record-state.sh --run store session writes the owner's row" "0 session" \
    "$? $(jq -r '.issues[0].body' "$GH_DB" | bash "$HERE/record-parse.sh" | jq -r '[.run[] | select(.key == "store") | .value][0]')"
jq -r '.comments[-1].body' "$GH_DB" | grep -qxF 'Run store set to session by alice.' \
    && ok "  ... and posts the run entry the find looks for" || bad "  ... and posts the run entry the find looks for" "$(jq -c '.comments' "$GH_DB")"
bash "$HERE/record-state.sh" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --skip-session-checks --run store bogus --by alice >/dev/null 2>"$T/err"
eq "a store that is neither is refused" 65 $?
bash "$HERE/record-state.sh" --scope discipline --name ci-health --repo "$REPO" --ref 7 --skip-session-checks --run store github --by alice >/dev/null 2>"$T/err"
eq "a store row at discipline scope is refused" 65 $?
bash "$HERE/record-state.sh" --scope discipline --name ci-health --repo "$REPO" --ref 7 --skip-session-checks --run store session --by alice >/dev/null 2>"$T/err"
eq "  ... store session too" 65 $?
grep -q 'store-discipline' "$T/err" && ok "  ... as store-discipline" || bad "  ... as store-discipline" "$(cat "$T/err")"

# The opener: a discipline --store is refused before any koto call; --store
# session reaches koto.
open_with() { printf '%s' "$1" > "$T/args.json"; ( cd "$T" && bash "$HERE/coordinate-open.sh" --plugin-root "$PLUGIN_ROOT_REAL" "$T/args.json" ); }
: > "$KOTO_STORE/calls"
OUT=$(open_with '["--discipline", "ci-health", "--host", "acme/widgets", "--store", "github"]' 2>"$T/err"); rc=$?
eq "--store at discipline scope is refused" "2 refused=store-discipline" "$rc $OUT"
grep -q '^init' "$KOTO_STORE/calls" && bad "  ... and no session is opened" "$(cat "$KOTO_STORE/calls")" || ok "  ... and no session is opened"
OUT=$(open_with '["docs/roadmaps/ROADMAP-plugin-system.md", "--store", "session"]' 2>"$T/err")
case "$OUT" in *refused=store*) bad "--store session at roadmap scope isn't refused by the opener" "$OUT" ;; *) ok "--store session at roadmap scope isn't refused by the opener" ;; esac

# ---- 4. coord/source.json -----------------------------------------------------------

echo "== 4. the store the find writes =="
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/gh.md")"
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system | jq -c '. + {STORE: "github"}')"
log_to "$S" start_posture record_find 2026-09-26T08:01:00.000Z
# The koto stand-in offers neither `context list --prefix` nor `session import`:
# the probe reads both missing, and a run on the GitHub store goes on anyway,
# its find adopting the record, which routes the run to reconcile.
OUT=$(bash "$HERE/record-find.sh" --session "$S" 2>"$T/err"); eq "a session find exits 0" 0 $?
eq "  ... and adopts the record, so the run goes on to reconcile" "found 7" "$(printf '%s' "$OUT" | cut -d' ' -f1-2)"
SRC=$(cat "$KOTO_STORE/context/$S/coord/source.json" 2>/dev/null)
eq "coord/source.json holds the record's store" github "$(printf '%s' "$SRC" | jq -r .source)"
eq "  ... and the probe's reading of a koto with neither feature" '{"context_list_prefix":false,"session_import":false}' \
    "$(printf '%s' "$SRC" | jq -c .probe)"
printf '%s' "$SRC" | jq -r .reason | grep -q 'is ignored: the record decides' \
    && ok "  ... and reports the invocation's --store ignored" || bad "  ... and reports the invocation's --store ignored" "$SRC"
eq "rs_source reads it" github "$(bash "$RS" --session "$S" --source 2>/dev/null)"
# What the sealed token carries in this release: the verdict and the record's
# number, never the store; run-store reads the GitHub store from it.
log_capture "$S" RECORD_FIND "$OUT" 2026-09-26T08:01:00.000Z
eq "the sealed token is the verdict and the number only" "found 7" "$(bash "$HERE/coord-log.sh" capture --session "$S" --name RECORD_FIND | sed 's/ sealed:.*//')"
eq "  ... and coord-log.sh run-store reads github from it" github "$(bash "$HERE/coord-log.sh" run-store --session "$S")"

# A new scope with STORE=session: on a koto with the session store's features the
# find routes it to record_open on the session store; without them it stops.
db_init
SN=coordinate-roadmap-plugin-system-20260926T060000Z
log_new "$SN" "$(roadmap_vars plugin-system | jq -c '. + {STORE: "session"}')"
log_to "$SN" start_posture record_find 2026-09-26T06:01:00.000Z
OUT=$(KOTO_FEATURES=1 bash "$HERE/record-find.sh" --session "$SN" 2>"$T/err")
eq "a new scope with STORE=session goes on to record_open" none "$(printf '%s' "$OUT" | cut -d' ' -f1)"
eq "  ... on the session store" "session|no record found: the invocation's store" "$(jq -r '"\(.source)|\(.reason)"' "$KOTO_STORE/context/$SN/coord/source.json")"
SN2=coordinate-roadmap-plugin-system-20260926T060100Z
log_new "$SN2" "$(roadmap_vars plugin-system | jq -c '. + {STORE: "session"}')"
log_to "$SN2" start_posture record_find 2026-09-26T06:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$SN2" 2>"$T/err")
eq "  ... and without the features it stops" malformed "$(printf '%s' "$OUT" | cut -d' ' -f1)"
jq -r .reason "$KOTO_STORE/context/$SN2/coord/record_find.json" | grep -q '^store-unsupported' \
    && ok "  ... as store-unsupported" || bad "  ... as store-unsupported" "$(cat "$KOTO_STORE/context/$SN2/coord/record_find.json")"
# The same at discipline scope, with any store.
SD=coordinate-discipline-ci-health-20260926T060000Z
log_new "$SD" "$(discipline_vars ci-health | jq -c '. + {STORE: "github"}')"
log_to "$SD" start_posture record_find 2026-09-26T06:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$SD" --today 2026-09-26 2>"$T/err")
eq "a discipline run with a store is stopped at the find" malformed "$(printf '%s' "$OUT" | cut -d' ' -f1)"
jq -r .reason "$KOTO_STORE/context/$SD/coord/record_find.json" | grep -q '^store-discipline' \
    && ok "  ... as store-discipline" || bad "  ... as store-discipline" "$(cat "$KOTO_STORE/context/$SD/coord/record_find.json")"

# A candidate the find rejects is a record it didn't adopt, not a missing one:
# coord/source.json says so, with the find's own verdict and reason.
# The renderer refuses a bogus store, so the bogus row is edited into a rendered one.
sed '/^| store |/s/| github |/| bogus |/' "$T/gh.md" > "$T/bogus.md"
grep -q '^| store | bogus |' "$T/bogus.md" && [ "$(diff "$T/gh.md" "$T/bogus.md" | grep -c '^>')" = 1 ] \
    && ok "the fixture carries a store row reading bogus" || bad "the fixture carries a store row reading bogus" "$(grep -n store "$T/gh.md")"
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/bogus.md")"
SB=coordinate-roadmap-plugin-system-20260926T050000Z
log_new "$SB" "$(roadmap_vars plugin-system)"
log_to "$SB" start_posture record_find 2026-09-26T05:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$SB" 2>"$T/err")
eq "a record whose store row reads bogus is malformed at the find" malformed "$(printf '%s' "$OUT" | cut -d' ' -f1)"
SRC=$(jq -r '"\(.source)|\(.reason)"' "$KOTO_STORE/context/$SB/coord/source.json")
case "$SRC" in
    "github|no record adopted: malformed: "*store-malformed*) ok "  ... and coord/source.json names the malformed record, not a missing one" ;;
    *) bad "  ... and coord/source.json names the malformed record, not a missing one" "$SRC" ;;
esac
# Two open candidates: ambiguous, again a record that wasn't adopted.
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null},
                {repo: "acme/widgets", number: 8, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/gh.md")"
SA=coordinate-roadmap-plugin-system-20260926T040000Z
log_new "$SA" "$(roadmap_vars plugin-system)"
log_to "$SA" start_posture record_find 2026-09-26T04:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$SA" 2>"$T/err")
eq "two open candidates are ambiguous at the find" ambiguous "$(printf '%s' "$OUT" | cut -d' ' -f1)"
SRC=$(jq -r '"\(.source)|\(.reason)"' "$KOTO_STORE/context/$SA/coord/source.json")
case "$SRC" in
    "github|no record adopted: ambiguous: "*) ok "  ... and coord/source.json says no record was adopted" ;;
    *) bad "  ... and coord/source.json says no record was adopted" "$SRC" ;;
esac
# rs_record_api keeps the checks board-lib made on this read before the seam: a
# record number of ten digits is refused before any read, nine digits is read.
api_on() { # api_on <number> <session>: find the record numbered <number>, then read it through rs_record_api
    db_init
    db '.issues += [{repo: "acme/widgets", number: ($n | tonumber), title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg n "$1" --arg t "$TITLE" --arg b "$(cat "$T/gh.md")"
    log_new "$2" "$(roadmap_vars plugin-system)"
    log_to "$2" start_posture record_find 2026-09-26T02:01:00.000Z
    log_capture "$2" RECORD_FIND "$(bash "$HERE/record-find.sh" --session "$2" 2>/dev/null)" 2026-09-26T02:01:00.000Z
    reset_calls
    ( PROG=t; . "$HERE/record-common.sh"; rs_record_api "$T/api" "$2" 2>/dev/null; echo "rc=$?" )
}
eq "a ten-digit record number is refused by rs_record_api" rc=2 "$(api_on 1234567890 coordinate-roadmap-plugin-system-20260926T020000Z)"
grep -q 'api' "$GH_DB.calls" && bad "  ... before any read" "$(calls)" || ok "  ... before any read"
eq "a nine-digit record number is read" rc=0 "$(api_on 123456789 coordinate-roadmap-plugin-system-20260926T021000Z)"
grep -q 'api' "$GH_DB.calls" && ok "  ... through the API" || bad "  ... through the API" "$(calls)"

# Parity with the checks the seam replaced: every repository and number
# board-lib.sh's bl_repo_ok and bl_pr_ok refused, rs_target_ok refuses, and
# every one they took, it takes. land-check.sh and land-merge.sh read the record
# through rs_record_api, so this is what keeps their inputs unchanged.
parity_row() { # parity_row <repo> <ref> <want: ok|refused>
    ( PROG=t; . "$HERE/record-common.sh"; . "$HERE/board-lib.sh"
      if bl_repo_ok "$1" && bl_pr_ok "$2"; then old=ok; else old=refused; fi
      if rs_target_ok "$1" "$2"; then new=ok; else new=refused; fi
      echo "$old $new" )
}
while IFS='|' read -r prepo pref pwant; do
    [ -n "$prepo$pref" ] || continue
    eq "parity: repo [$prepo] number [$pref] is $pwant before and after the seam" "$pwant $pwant" "$(parity_row "$prepo" "$pref")"
done <<'ROWS'
acme/widgets|7|ok
acme/widgets|123456789|ok
acme/widgets|1234567890|refused
acme/widgets|0|refused
acme/widgets|07|refused
acme/widgets|-7|refused
acme/widgets|7a|refused
acme/widgets||refused
acme/..|7|refused
acme/.|7|refused
../widgets|7|refused
./widgets|7|refused
acme|7|refused
acme/widgets/extra|7|refused
acme/wid gets|7|refused
|7|refused
a.b/c-d_e|7|ok
ROWS

# No candidate at all: the one case that is "no record found".
db_init
S0=coordinate-roadmap-plugin-system-20260926T030000Z
log_new "$S0" "$(roadmap_vars plugin-system)"
log_to "$S0" start_posture record_find 2026-09-26T03:01:00.000Z
OUT=$(bash "$HERE/record-find.sh" --session "$S0" 2>"$T/err")
eq "no candidate is none at the find" none "$(printf '%s' "$OUT" | cut -d' ' -f1)"
eq "  ... and coord/source.json says no record was found" "github|no record found and no --store" \
    "$(jq -r '"\(.source)|\(.reason)"' "$KOTO_STORE/context/$S0/coord/source.json")"

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
[ "$(head -1 <<<"$BODY")" = '<!-- coordinator-record-entry v1 kind=cost -->' ] \
    && ok "  ... a comment whose first line is the cost marker the join selects on" || bad "  ... a comment whose first line is the cost marker the join selects on" "$BODY"
L=$(bash "$HERE/record-append.sh" --session "$S2" --list 2>"$T/err"); eq "record-append.sh --session S --list reads" 0 $?
eq "  ... the entry, with its kind and text" "cost|$(cat "$T/cost.txt")" "$(printf '%s' "$L" | jq -r '.[0] | "\(.kind)|\(.text)"')"
eq "  ... in the list's shape" '["author","created","edited","id","kind","stamp","text"]' "$(printf '%s' "$L" | jq -c '.[0] | keys')"

# ---- 6. the session store's read ----------------------------------------------------

echo "== 6. the session store's read =="
# seam_read <out> [<source> <session>]: rs_record on record #7 of plugin-system,
# in a subshell, from the GitHub store, or from <session> when <source> is
# `session`. It names every variable it sets and exports none, so nothing it
# runs can print the environment; with no arguments it does nothing.
seam_read() {
    [ $# -ge 1 ] || return 64
    local out=$1 src=${2:-github} ses=${3:-}
    ( PROG=t; SCOPE=roadmap NAME=plugin-system REPO=$REPO REF=7; . "$HERE/record-common.sh"; lib_facts
      RS_SOURCE=$src RS_SESSION=$ses RS_RETRY_PAUSE=0 rs_record "$out" body --json body --jq .body; echo "rc=$?" )
}
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$(cat "$T/rec.md")"
bash "$HERE/record-parse.sh" --container issue "$T/rec.md" > "$T/rec.json"
eq "the read helper with no arguments prints nothing" "" "$(seam_read 2>&1)"
SS=coordinate-roadmap-plugin-system-20260926T110000Z
session_keys "$SS" "$T/rec.json"
eq "rs_record reads the GitHub record" rc=0 "$(seam_read "$T/g")"
eq "rs_record reads the same state from the session" rc=0 "$(seam_read "$T/s" session "$SS")"
eq "  ... as the same JSON (R19)" "$(jq -cS . "$T/g")" "$(jq -cS . "$T/s")"
eq "  ... and the same body" "$(cat "$T/g.md")" "$(cat "$T/s.md")"
W1=$(jq -r '.holdings[0].worker' "$T/rec.json")
eq "rs_facts gives the same holding facts from both" \
    "$( ( PROG=t; . "$HERE/record-common.sh"; rs_facts "$T/g" "$W1" ) | jq -cS .)" \
    "$( ( PROG=t; . "$HERE/record-common.sh"; rs_facts "$T/s" "$W1" ) | jq -cS .)"
grep -q '^issue view' "$GH_DB.calls" && reset_calls
seam_read "$T/s2" session "$SS" > /dev/null
grep -q 'issue view' "$GH_DB.calls" && bad "  ... and the session read asks GitHub for nothing" "$(calls)" || ok "  ... and the session read asks GitHub for nothing"

# A write part way through: record/meta marked pending.
SP=coordinate-roadmap-plugin-system-20260926T110100Z
session_keys "$SP" "$T/rec.json" true
: > "$KOTO_STORE/calls"
eq "a record marked pending is re-read and then refused record-changed" rc=12 "$(seam_read "$T/p" session "$SP")"
eq "  ... after three re-reads" 4 "$(grep -c "^context get $SP record/meta" "$KOTO_STORE/calls")"
grep -q record-changed "$T/p.err" && ok "  ... naming record-changed" || bad "  ... naming record-changed" "$(cat "$T/p.err")"
# No record/meta in the run's session.
SA=coordinate-roadmap-plugin-system-20260926T110200Z
eq "a session holding no record/meta is session-absent" rc=4 "$(seam_read "$T/a" session "$SA")"
grep -q '^t: session-absent' "$T/a.err" && ok "  ... with the reason" || bad "  ... with the reason" "$(cat "$T/a.err")"
# record/meta for another scope.
SX=coordinate-roadmap-plugin-system-20260926T110300Z
jq '.scope.name = "other"' "$T/rec.json" > "$T/other.json"
session_keys "$SX" "$T/other.json"
eq "a session record for another scope is refused" rc=65 "$(seam_read "$T/x" session "$SX")"

# --show on a run whose find sealed the session store.
SW=coordinate-roadmap-plugin-system-20260926T110400Z
found_session "$SW" "$(roadmap_vars plugin-system)" "7 session"
session_keys "$SW" "$T/rec.json"
koto context add "$SW" record/host < <(jq -nc '{source_workspace: "/srv/ws/host-only-marker", session: "x"}')
eq "a run sealed found 7 session reads the session store" session "$(bash "$RS" --session "$SW" --source 2>"$T/err")"
bash "$RS" --session "$SW" --show > "$T/show.md" 2>"$T/err"; eq "--show prints the record" 0 $?
eq "  ... a body that parses back to the session's state (R11)" "$(jq -cS . "$T/rec.json")" \
    "$(bash "$HERE/record-parse.sh" --container issue "$T/show.md" | jq -cS .)"
grep -q 'host-only-marker' "$T/show.md" && bad "  ... and holds nothing from record/host" "$(cat "$T/show.md")" || ok "  ... and holds nothing from record/host"

echo "== the resume decision (PRD R12) =="
# rs_resume_candidate over this host's runs of one scope, on the koto stand-in:
# resume the newest holder of a session-store record when it is the scope's
# only live run, compiled from the shipped hash, passing provenance, sealed to
# the session store and without a directed transition; carry it otherwise; none
# without one.
HS=abababababababababababababababababababababababababababababababab
HO=cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
jq -c '.scope.name = "resume-probe"' "$T/rec.json" > "$T/rp.json"
clear_rp() { rm -rf "$KOTO_STORE"/sessions/coordinate-roadmap-resume-probe-* "$KOTO_STORE"/context/coordinate-roadmap-resume-probe-*; }
mk() { # mk <name> [template-hash] [vars-jq]: a run of resume-probe holding a session-store record
    found_session "$1" "$(roadmap_vars resume-probe | jq -c "${3:-.}")" "7 session" "${2:-$HS}"
    session_keys "$1" "$T/rp.json"
    printf '{"source":"session","reason":"found"}' | koto context add "$1" coord/source.json
}
cand() { KOTO_COMPILED_HASH=$HS bash "$RS" --candidate --scope roadmap --name resume-probe --hash "$HS" 2>"$T/c.err" | jq -r '"\(.action) \(.session)"'; }
R1=coordinate-roadmap-resume-probe-20261013T100000Z R2=coordinate-roadmap-resume-probe-20261013T110000Z
clear_rp; eq "no run here holds a record: none" "none null" "$(cand)"
clear_rp; mk "$R1"; eq "the scope's one live run, as shipped: resume" "resume $R1" "$(cand)"
clear_rp; mk "$R1"; mk "$R2"; log_end "$R1"; eq "the newest holder is the one decided on" "resume $R2" "$(cand)"
clear_rp; mk "$R1" "$HO"
eq "a run koto compiled from another template is carried" "carry $R1" "$(cand)"
clear_rp; mk "$R1"; log_end "$R1"; eq "a cancelled run is carried" "carry $R1" "$(cand)"
clear_rp; mk "$R1"; log_ev "$R1" directed_transition '{"from":"reconcile","to":"pick"}'; eq "a run with a directed transition is carried" "carry $R1" "$(cand)"
clear_rp; mk "$R1" "$HS" '.PLUGIN_ROOT = "/elsewhere"'; eq "a run failing provenance is carried, not resumed" "carry $R1" "$(cand)"
clear_rp; mk "$R1"; mk "$R2"; eq "two live runs: the newest is carried" "carry $R2" "$(cand)"
clear_rp; mk "$R1"; printf '{"source":"github","reason":"found"}' | koto context add "$R1" coord/source.json
eq "a run whose store isn't session: none" "none $R1" "$(cand)"
clear_rp; mk coordinate-roadmap-resume-probe-copy; eq "a name off the pattern is never a candidate" "none null" "$(cand)"
clear_rp; mk "$R1"; printf '%s' coordinate-roadmap-other-20261013T090000Z > "$KOTO_STORE/sessions/$R1/.parent"
eq "a child session is never a candidate" "none null" "$(cand)"
clear_rp
bash "$RS" --candidate --scope roadmap --name resume-probe --hash abc >/dev/null 2>&1; eq "--candidate refuses a hash that isn't 64 hex" 64 $?
# The carry's write path: core_carry is called only by the opener.
eq "only coordinate-open.sh calls core_carry" "" "$(fn_callers "$HERE" core_carry '^coordinate-open\.sh$')"

done_tests record-source
