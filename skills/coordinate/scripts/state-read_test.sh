#!/usr/bin/env bash
# state-read_test.sh -- state-read.sh, the one reader of a coordinator
# record's state (docs/designs/DESIGN-coordinator-session-record.md, Decision 1),
# which lives only in the coordinator's koto session
# (docs/designs/current/DESIGN-coordinator-record-teardown.md).
#
# Covers:
#   1. the structure rule: no script reads a record body, parses one or reads a
#      `record/` key except the seam and the scripts named here, shown on this
#      tree and refused on a fixture script that does each; the write paths'
#      flags and functions held to their one script each;
#   2. rs_facts on a fixture record with two holdings, a hold on one's pull
#      request and a pause on the other's unit, against a fixed JSON, both as a
#      library call and through `--facts`;
#   3. the store row, as the write core is handed it as JSON: `github`, `bogus`
#      and a doubled row are refused (65), the legacy `store session`
#      row an existing session holds is accepted and read back,
#      and the crash-set rows need no store row; state-stored-set.sh refuses `--run
#      store` as no Run key (65) at either scope; the opener refuses --store as
#      an unknown option (64), naming it, before any koto call;
#   4. coord/source.json: the find writes session; the opener's koto feature
#      probe refuses a start on a koto without `context list --prefix` or
#      `session import` (store-unsupported, naming what is missing), and reads
#      --prefix from a help text longer than a pipe's buffer;
#   5. outward entries: a cost entry is refused with nowhere to go, posted on
#      the item --on names, and `--list` reads the session's entries in the
#      list's shape;
#   6. the session read: the same state from rs_record and rs_record_api,
#      pending (record-changed), absent (session-absent) and another scope's
#      record, record/host kept out of the state, --host, and --show an unknown
#      option (64); a read of some sections handing back only those, never
#      listing record/, refusing a field with no section and reading again when
#      a listed section's get failed while record/meta moved;
#   7. one read per step (rs_once_begin): reads under one shared read take one
#      assembly, a write's drop makes the next read live, and reconcile-read.sh's
#      read takes one assembly;
#   8. the resume decision;
#   9. the opener's fresh start: the legacy importer's lookup once, an import
#      when it finds a record, a refusal that stops and cancels the new run, and
#      none on a resume.
#
# Usage: bash skills/coordinate/scripts/state-read_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
# state-entry.sh posts on an item only when its repository opts in to
# workflow content; acme/widgets does here, through the reader's stand-in.
printf '#!/usr/bin/env bash\necho include\n' > "$T/pr-content-reader"
export STATE_ENTRY_PR_CONTENT_READER="$T/pr-content-reader"
PLUGIN_ROOT_REAL=$(cd "$HERE/../../.." && pwd -P)
RS="$HERE/state-read.sh"

# ---- 1. the structure rule ------------------------------------------------------

# body_readers <dir>: every line of a non-test script in <dir> that reads a
# record's body or keys, or parses a body, outside the scripts allowed to.
#   Reading: a gh issue/pr view (any spelling of the container) that asks for
#   the body, or a `record/` key. Allowed: the seam; the entry writer, which
#   reads its entries.
#   Parsing: lib_parse or bl_record_parsed, the helpers a body was parsed
#   through. Allowed: the seam. (The body's parser itself is gone, and the
#   structure test refuses any new mention of it.)
READ_ALLOWED='^(state-read|state-entry)\.sh$'
PARSE_ALLOWED='^state-read\.sh$'
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
            grep -nE 'lib_parse |bl_record_parsed' "$f" \
                | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
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
printf '#!/usr/bin/env bash\ngh "$CONTAINER" view "$REF" --repo "$REPO" --json state,body > x\n' > "$FX/f.sh"
eq "  ... and the rule refuses each way of reading one" "a.sh b.sh c.sh d.sh f.sh" \
    "$(body_readers "$FX" | cut -d: -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"

# SESSION_SEED, the first write into an empty session, is set only by the
# opener of a record.
flag_setters() { # flag_setters <dir> <flag> <allowed-regex>: scripts that set flag=1 outside the allowed ones
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh|state-write-core.sh) continue ;; esac
        [[ $base =~ $3 ]] && continue
        grep -nE "(^|[^A-Za-z_])$2=1" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
    done
}
eq "only state-open.sh sets SESSION_SEED" "" "$(flag_setters "$HERE" SESSION_SEED '^state-open\.sh$')"
eq "no script sets MOVE_WRITER: the move is gone" "" "$(flag_setters "$HERE" MOVE_WRITER '^$')"
grep -n 'MOVE_WRITER' "$HERE/state-write-core.sh" > /dev/null && bad "  ... and the write core has no such flag" "" || ok "  ... and the write core has no such flag"
printf '#!/usr/bin/env bash\n. "$HERE/state-write-core.sh"\nSESSION_SEED=1\ncore_write\n' > "$FX/g.sh"
eq "  ... and the rule refuses a script that sets it" "g.sh" \
    "$(flag_setters "$FX" SESSION_SEED '^state-open\.sh$' | cut -d: -f1)"
# record/host (Decision 9; PRD R14, R17) is written only by state-stored-set.sh
# --host, through core_write_host.
fn_callers() { # fn_callers <dir> <function> <allowed-regex>: scripts that call it outside the allowed ones
    local f base
    for f in "$1"/*.sh; do
        base=$(basename "$f")
        case "$base" in *_test.sh|state-write-core.sh) continue ;; esac
        [[ $base =~ $3 ]] && continue
        grep -nE "(^|[^A-Za-z_])$2([^A-Za-z_]|$)" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$base:|"
    done
}
eq "only state-stored-set.sh calls core_write_host" "" "$(fn_callers "$HERE" core_write_host '^state-stored-set\.sh$')"
# A holding's pushed head is set only through state-write.sh --pushed-head.
eq "only state-write.sh sets CORE_PUSHED_SET" "" "$(flag_setters "$HERE" CORE_PUSHED_SET '^state-write\.sh$')"
printf '#!/usr/bin/env bash\n. "$HERE/state-write-core.sh"\ncore_write_host "$f"\n' > "$FX/h.sh"
eq "  ... and the rule refuses a script that calls it" "h.sh" "$(fn_callers "$FX" core_write_host '^state-stored-set\.sh$' | cut -d: -f1)"
# The legacy importer's write (core_import, core_import_meta, opened by
# IMPORT_WRITER) belongs to ../legacy-import/import.sh alone: no script here
# sets the flag or calls either.
eq "no script here sets IMPORT_WRITER" "" "$(flag_setters "$HERE" IMPORT_WRITER '^$')"
eq "  ... nor calls core_import or core_import_meta" "" "$(fn_callers "$HERE" 'core_import(_meta)?' '^$')"
printf '#!/usr/bin/env bash\n. "$HERE/state-write-core.sh"\nIMPORT_WRITER=1\ncore_import_meta "$f"\n' > "$FX/i.sh"
eq "  ... and the rule refuses a script that does" "i.sh i.sh" \
    "$( { flag_setters "$FX" IMPORT_WRITER '^$'; fn_callers "$FX" 'core_import(_meta)?' '^$'; } | grep '^i\.sh:' | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//')"
# The store choice is gone from the seam.
for fn in rs_source rs_view rs_probe rs_moved rs_target_ok; do
    grep -nE "^$fn\(\)" "$RS" > /dev/null && bad "state-read.sh defines no $fn" "" || ok "state-read.sh defines no $fn"
done

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
state_json "$REC" > "$T/rec.json" 2>"$T/err" && ok "the fixture is a valid state" || bad "the fixture is a valid state" "$(cat "$T/err")"

echo "== 2. one holding's facts =="
facts() { ( PROG=t; . "$HERE/state-common.sh"; rs_facts "$T/rec.json" "$1" ); }
GOT=$(facts worker-f1); eq "rs_facts prints" 0 $?
EXPECT_F1='{"topic":"worker-f1","unit":"Feature 1","repo":"acme/widgets","pull_request":"[#12](https://github.com/acme/widgets/pull/12)","number":"12","branch":"feat/first","verified_head":"1111111111111111111111111111111111111111","phase":"executing","dispatch_status":"dispatched","return_path":"message","holds":[{"hold":"after-release","on":"acme/widgets#12","until":"lifted","set_by":"the human","set":"2026-09-29T20:30Z","lifted":""}],"pauses":{"rows":[{"standing":"s1","kind":"pause","on":"Feature 2","until":"lifted","what":"hold Feature 2","owner":"alice","relayed_by":"","set":"2026-09-29T17:40Z"},{"standing":"s2","kind":"go-ahead","on":"Feature 1","until":"","what":"one release","owner":"alice","relayed_by":"","set":"2026-09-29T17:41Z"}],"paused":null}}'
eq "  ... worker-f1: its repository, pull request, head, its one hold, the pause rows, not paused" \
    "$EXPECT_F1" "$(printf '%s' "$GOT" | jq -c 'del(.pauses.read)')"
GOT=$(facts worker-f2)
eq "  ... worker-f2: no pull request, no hold, paused by s1" '{"number":"","holds":[],"paused":"s1","phase":"scoping-ahead"}' \
    "$(printf '%s' "$GOT" | jq -c '{number, holds, paused: .pauses.paused, phase}')"
facts worker-f9 >/dev/null; eq "  ... a topic no holding has is 1" 1 $?
db_init
SF=coordinate-roadmap-plugin-system-20260926T060000Z
seed_session "$SF" "$REC"
OUT=$(RS_SESSION=$SF bash "$RS" --scope roadmap --name plugin-system --repo "$REPO" --facts worker-f1 2>"$T/err"); eq "--facts reads the live record" 0 $?
eq "  ... to the same facts" "$EXPECT_F1" "$(printf '%s' "$OUT" | jq -c 'del(.pauses.read)')"
eq "  ... from the session, with no GitHub call" "" "$(calls)"
RS_SESSION=$SF bash "$RS" --scope roadmap --name plugin-system --repo "$REPO" --ref 7 --facts worker-f1 >/dev/null 2>&1; eq "--ref is a usage error" 64 $?
RS_SESSION=$SF bash "$RS" --session "$SF" --source >/dev/null 2>&1; eq "--source is a usage error" 64 $?
RS_SESSION=$SF bash "$RS" --session "$SF" --probe >/dev/null 2>&1; eq "--probe is a usage error" 64 $?

# ---- 3. the store row -----------------------------------------------------------------

echo "== 3. the store row =="
with_store() { printf '%s' "$REC" | jq -c --arg v "$1" '.run += [{key: "store", value: $v, set_by: "alice", set: "2026-10-11T10:00Z"}]'; }
# try_state <json>: the write core handed the state as the writer's next state
# (edited from the version the session holds): RC and $T/err.
SW3=coordinate-roadmap-plugin-system-20260926T120000Z
seam_read_run() { ( RS_SESSION=$SW3 PROG=reader SCOPE=roadmap NAME=plugin-system
    . "$HERE/state-common.sh"; . "$HERE/state-read.sh"; RS_RETRY_PAUSE=0
    rs_record "$T/reader3" > /dev/null 2>&1 && jq -c . "$T/reader3" ); }
try_state() {
    seed_session "$SW3" "$REC"
    printf '%s' "$1" | jq -c '.written = "2026-09-26T09:00:00Z"' > "$T/try.json"
    RS_SESSION=$SW3 bash "$HERE/state-write.sh" --scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks --state-file "$T/try.json" >/dev/null 2>"$T/err"
    RC=$?
}
try_state "$(with_store github)"
eq "a store row reading github is refused" 65 "$RC"
grep -q 'the store is the session' "$T/err" && ok "  ... the store being the session" || bad "  ... the store being the session" "$(cat "$T/err")"
try_state "$(with_store bogus)"
grep -q 'the store is the session' "$T/err" && ok "a store reading bogus is refused, the store being the session" || bad "a store reading bogus is refused, the store being the session" "$(cat "$T/err")"
state_json "$(with_store session)" > "$T/legacy.json" 2>"$T/err"
eq "the legacy store session row an existing session holds is accepted" 0 "$?"
seed_session "$SW3" "$(with_store session)"
eq "  ... and read back from the session" "store" "$(seam_read_run | jq -r '.run[-1].key')"
try_state "$(with_store session | jq -c '.run += [{key: "store", value: "session", set_by: "alice", set: "2026-10-11T10:01Z"}]')"
grep -q 'the store row is used twice' "$T/err" && ok "two store rows are refused" || bad "two store rows are refused" "$(cat "$T/err")"
try_state "$(printf '%s' "$REC" | jq -c '.run += [{key: "colour", value: "x", set_by: "alice", set: "2026-10-11T10:00Z"}]')"
eq "any other unknown Run key is still refused" 65 "$RC"
state_json "$(printf '%s' "$REC" | jq -c '.run += [{key: "friction", value: "fr", set_by: "alice", set: "2026-10-11T10:00Z"},
        {key: "reports-to", value: "the planner", set_by: "alice", set: "2026-10-11T10:00Z"}]')" > /dev/null 2>"$T/err"
eq "the crash-set rows need no store row" 0 "$?"
# state-stored-set.sh: the store is no Run key it sets, at either scope.
for sc in roadmap:plugin-system discipline:ci-health; do
    bash "$HERE/state-stored-set.sh" --scope "${sc%%:*}" --name "${sc#*:}" --repo "$REPO" --skip-session-checks --run store session --by alice >/dev/null 2>"$T/err"
    eq "state-stored-set.sh --run store session is refused at ${sc%%:*} scope" 65 $?
    grep -q 'not a Run key' "$T/err" && ok "  ... as no Run key" || bad "  ... as no Run key" "$(cat "$T/err")"
done
bash "$HERE/state-stored-set.sh" --scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks --run store github --by alice >/dev/null 2>"$T/err"
eq "  ... and store github too" 65 $?
# The opener: --store is an unknown option, usage (64), named, before any koto call.
open_with() { printf '%s' "$1" > "$T/args.json"; ( cd "$T" && bash "$HERE/coordinate-open.sh" --plugin-root "$PLUGIN_ROOT_REAL" "$T/args.json" ); }
for v in session github bogus; do
    : > "$KOTO_STORE/calls"
    OUT=$(open_with "[\"--discipline\", \"ci-health\", \"--host\", \"acme/widgets\", \"--store\", \"$v\"]" 2>"$T/err"); rc=$?
    eq "coordinate-open.sh --store $v exits 64" 64 "$rc"
    grep -q 'unknown option --store' "$T/err" && ok "  ... naming --store" || bad "  ... naming --store" "$(cat "$T/err")"
    eq "  ... before any koto call" "" "$(cat "$KOTO_STORE/calls")"
done

# ---- 4. coord/source.json and the probe -----------------------------------------

echo "== 4. the store the find writes, and the opener's probe =="
db_init
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start_posture record_find 2026-09-26T08:01:00.000Z
OUT=$(bash "$HERE/state-find.sh" --session "$S" 2>"$T/err"); eq "a session find exits 0" 0 $?
SRC=$(cat "$KOTO_STORE/context/$S/coord/source.json" 2>/dev/null)
eq "coord/source.json reads session" session "$(printf '%s' "$SRC" | jq -r .source)"
eq "  ... with the find's reason and no probe" "none|null" "$(printf '%s' "$SRC" | jq -r '"\(.reason | split(":")[0])|\(.probe)"')"
# The opener's probe, on the stand-in with neither feature (KOTO_FEATURES
# unset): refused before any session opens.
: > "$KOTO_STORE/calls"
OUT=$(open_with '["--discipline", "ci-health", "--host", "acme/widgets"]' 2>"$T/err"); rc=$?
eq "a koto without the session store's features refuses the start" "2 refused=store-unsupported" "$rc $OUT"
grep -q 'lacks context list --prefix, session import' "$T/err" && ok "  ... naming both" || bad "  ... naming both" "$(cat "$T/err")"
grep -qE '^(init|template compile|session list)' "$KOTO_STORE/calls" && bad "  ... before anything else" "$(cat "$KOTO_STORE/calls")" || ok "  ... before anything else"
mkdir -p "$T/noimport"
cat > "$T/noimport/koto" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "context list --help") echo "      --prefix <PREFIX>  Filter keys by prefix" ;;
    "session import --help") exit 2 ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$T/noimport/koto"
OUT=$(KOTO_BIN="$T/noimport/koto" open_with '["--discipline", "ci-health", "--host", "acme/widgets"]' 2>"$T/err"); rc=$?
eq "a koto without session import refuses the start" "2 refused=store-unsupported" "$rc $OUT"
grep -q 'lacks session import,' "$T/err" && ok "  ... naming it alone" || bad "  ... naming it alone" "$(cat "$T/err")"
OUT=$(KOTO_BIN="$T/noimport/koto" open_with '["--import", "coordinate-discipline-ci-health-20261001T100000Z", "--from", "/srv/ws", "--discipline", "ci-health", "--host", "acme/widgets"]' 2>"$T/err"); rc=$?
eq "  ... an --import as well" "2 refused=store-unsupported" "$rc $OUT"
# shirabe#855: a help text longer than a pipe's buffer, naming --prefix on its
# first line. A reader that stops at the match would leave koto writing into a
# closed pipe, and under pipefail the probe would read the feature as missing.
mkdir -p "$T/bighelp"
cat > "$T/bighelp/koto" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "context list --help")
        echo "      --prefix <PREFIX>  Filter keys by prefix"
        i=0; while [ "$i" -lt 4000 ]; do echo "padding line $i of a help text longer than any pipe buffer"; i=$((i + 1)); done ;;
    "session import --help") exit 0 ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$T/bighelp/koto"
OUT=$(KOTO_BIN="$T/bighelp/koto" open_with '["--discipline", "ci-health", "--host", "acme/widgets"]' 2>"$T/err"); rc=$?
case "$rc $OUT" in
    *store-unsupported*) bad "the probe reads --prefix from a help text longer than a pipe's buffer" "$rc $OUT $(cat "$T/err")" ;;
    "1 failed=template_compile") ok "the probe reads --prefix from a help text longer than a pipe's buffer" ;;
    *) bad "the probe reads --prefix from a help text longer than a pipe's buffer" "$rc $OUT $(cat "$T/err")" ;;
esac

# ---- 5. outward entries -----------------------------------------------------------

echo "== 5. cost entries =="
db_init
db '.issues += [{repo: "acme/widgets", number: 12, title: "a unit", body: "x", state: "open", author: "alice", editor: null}]'
S2=coordinate-roadmap-plugin-system-20260926T090000Z
found_session "$S2" "$(roadmap_vars plugin-system)"
seed_session "$S2" "$REC"
printf 'cost of worker-f1\n\n```json\n{"schema":"unit-cost/1","key":"worker-f1"}\n```\n' > "$T/cost.txt"
bash "$HERE/state-entry.sh" --session "$S2" --kind cost --text-file "$T/cost.txt" > /dev/null 2>"$T/err"
eq "a cost entry with nowhere to go is refused" 65 $?
grep -q -- '--on owner/repo#n, or --on none' "$T/err" && ok "  ... naming --on" || bad "  ... naming --on" "$(cat "$T/err")"
OUT=$(bash "$HERE/state-entry.sh" --session "$S2" --kind cost --text-file "$T/cost.txt" --on acme/widgets#12 2>"$T/err"); rc=$?
eq "state-entry.sh --session S --kind cost --on <pull request> posts on it" "0 https://github.com/acme/widgets/issues/12#issuecomment-1001" "$rc $OUT"
BODY=$(jq -r '.comments[0].body' "$GH_DB")
[ "$(head -1 <<<"$BODY")" = '<!-- coordinator-record-entry v1 kind=cost -->' ] \
    && ok "  ... a comment whose first line is the cost marker the join selects on" || bad "  ... a comment whose first line is the cost marker the join selects on" "$BODY"
L=$(bash "$HERE/state-entry.sh" --session "$S2" --list 2>"$T/err"); eq "state-entry.sh --session S --list reads" 0 $?
eq "  ... the entry, with its kind and text" "cost|$(cat "$T/cost.txt")" "$(printf '%s' "$L" | jq -r '.[0] | "\(.kind)|\(.text)"')"
eq "  ... in the list's shape" '["author","created","edited","id","kind","stamp","text"]' "$(printf '%s' "$L" | jq -c '.[0] | keys')"
grep -Eq 'issues/[0-9]+/comments\?|collaborator[s]/' "$GH_DB.calls" && bad "  ... with no comment listing or permission read" "$(calls)" || ok "  ... with no comment listing or permission read"

# ---- 6. the session read ------------------------------------------------------------

echo "== 6. the session read =="
# seam_read <out> <session>: rs_record on plugin-system's record in <session>, in
# a subshell. It names every variable it sets and exports none.
seam_read() {
    [ $# -ge 2 ] || return 64
    local out=$1 ses=$2
    ( PROG=t; SCOPE=roadmap NAME=plugin-system REPO=$REPO; . "$HERE/state-common.sh"; lib_facts
      RS_SESSION=$ses RS_RETRY_PAUSE=0 rs_record "$out"; echo "rc=$?" )
}
db_init
eq "the read helper with too few arguments prints nothing" "" "$(seam_read 2>&1)"
SS=coordinate-roadmap-plugin-system-20260926T110000Z
seed_session "$SS" "$REC"
eq "rs_record reads the session" rc=0 "$(seam_read "$T/s" "$SS")"
eq "  ... as the state it holds" "$(jq -cS 'del(.written)' "$T/rec.json")" "$(jq -cS 'del(.written)' "$T/s")"
eq "  ... the keys as assembled beside it" "$(jq -cS 'del(.written)' "$T/s")" "$(jq -cS 'del(.written)' "$T/s.state")"
eq "  ... asking GitHub for nothing" "" "$(calls)"
found_session "$SS" "$(roadmap_vars plugin-system)"
eq "rs_record_api reads the run's record by its session" rc=0 \
    "$( ( PROG=t; . "$HERE/state-common.sh"; rs_record_api "$T/api" "$SS" 2>/dev/null; echo "rc=$?" ) )"
eq "  ... to the same JSON" "$(jq -cS . "$T/s")" "$(jq -cS . "$T/api")"
eq "  ... asking GitHub for nothing" "" "$(calls)"
SN=coordinate-roadmap-plugin-system-20260926T110500Z
log_new "$SN" "$(roadmap_vars plugin-system)"
eq "rs_record_api on a run with no found record fails" rc=2 \
    "$( ( PROG=t; . "$HERE/state-common.sh"; rs_record_api "$T/api2" "$SN" 2>/dev/null; echo "rc=$?" ) )"
# A write part way through: record/meta marked pending.
SP=coordinate-roadmap-plugin-system-20260926T110100Z
session_keys "$SP" "$T/rec.json" true
: > "$KOTO_STORE/calls"
eq "a record marked pending is re-read and then refused record-changed" rc=12 "$(seam_read "$T/p" "$SP")"
eq "  ... after three re-reads" 4 "$(grep -c "^context get $SP record/meta" "$KOTO_STORE/calls")"
grep -q record-changed "$T/p.err" && ok "  ... naming record-changed" || bad "  ... naming record-changed" "$(cat "$T/p.err")"
# No record/meta in the run's session.
SA=coordinate-roadmap-plugin-system-20260926T110200Z
eq "a session holding no record/meta is session-absent" rc=4 "$(seam_read "$T/a" "$SA")"
grep -q '^t: session-absent' "$T/a.err" && ok "  ... with the reason" || bad "  ... with the reason" "$(cat "$T/a.err")"
# record/meta for another scope.
SX=coordinate-roadmap-plugin-system-20260926T110300Z
jq '.scope.name = "other"' "$T/rec.json" > "$T/other.json"
session_keys "$SX" "$T/other.json"
eq "a session record for another scope is refused" rc=65 "$(seam_read "$T/x" "$SX")"

# A read of some sections (shirabe#1308): each got directly, record/ never
# listed, the record handed back holding only those sections.
seam_fields() { # seam_fields <out> <session> <fields>
    ( PROG=t; SCOPE=roadmap NAME=plugin-system REPO=$REPO; . "$HERE/state-common.sh"; lib_facts
      RS_SESSION=$2 RS_RETRY_PAUSE=0 rs_record "$1" "$3"; echo "rc=$?" )
}
SF=coordinate-roadmap-plugin-system-20260926T110600Z
seed_session "$SF" "$REC"
: > "$KOTO_STORE/calls"
eq "a read of some sections reads the session" rc=0 "$(seam_fields "$T/f" "$SF" "holdings deferrals")"
eq "  ... handing back only those sections" "deferrals holdings scope written" "$(jq -r 'keys | join(" ")' "$T/f")"
eq "  ... as the state holds them" "$(jq -cS '{holdings, deferrals}' "$T/rec.json")" "$(jq -cS '{holdings, deferrals}' "$T/f")"
eq "  ... and never lists record/" 0 "$(grep -c "^context list $SF --prefix record/\$" "$KOTO_STORE/calls")"
eq "a field the record has no section for is refused" rc=2 "$(seam_fields "$T/fu" "$SF" "holdings holding")"
grep -q 'holding is not a section of the record' "$T/fu.err" && ok "  ... naming it" || bad "  ... naming it" "$(cat "$T/fu.err")"
# A section that is listed but whose get failed, while record/meta moved
# (a write landed): the read is taken again rather than failed.
mkdir -p "$T/fbin"
cat > "$T/fbin/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-} \${4:-}" = "context get record/deferrals" ] && [ ! -f "$T/fbin/moved" ]; then
    : > "$T/fbin/moved"
    printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
    m="\$KOTO_STORE/context/\$3/record/meta"
    jq -c '.written = "2026-09-26T09:30:00Z"' "\$m" > "\$m.new" && mv "\$m.new" "\$m"
    exit 1
fi
exec "$HERE/testdata/koto" "\$@"
EOF
chmod +x "$T/fbin/koto"
: > "$KOTO_STORE/calls"
eq "a listed section whose get failed while record/meta moved is read again" rc=0 \
    "$(PATH="$T/fbin:$PATH" seam_fields "$T/fm" "$SF" "holdings deferrals")"
eq "  ... getting it twice, the second time whole" "2 $(jq -cS '.deferrals' "$T/rec.json")" \
    "$(grep -c "^context get $SF record/deferrals\$" "$KOTO_STORE/calls") $(jq -cS '.deferrals' "$T/fm")"

# record/host is read through --host, and is no part of the state a reader is handed.
SW=coordinate-roadmap-plugin-system-20260926T110400Z
found_session "$SW" "$(roadmap_vars plugin-system)"
session_keys "$SW" "$T/rec.json"
koto context add "$SW" record/host < <(jq -nc '{source_workspace: "/srv/ws/host-only-marker", session: "x"}')
eq "a read of a run whose find sealed its record" rc=0 "$(seam_read "$T/w" "$SW")"
eq "  ... is the session's state" "$(jq -cS . "$T/rec.json")" "$(jq -cS . "$T/w")"
grep -q 'host-only-marker' "$T/w" "$T/w.state" && bad "  ... and holds nothing from record/host" "$(cat "$T/w")" || ok "  ... and holds nothing from record/host"
bash "$RS" --session "$SW" --show >/dev/null 2>"$T/err"; eq "--show is an unknown option" 64 $?
eq "--host prints record/host" "/srv/ws/host-only-marker" "$(bash "$RS" --session "$SW" --host 2>"$T/err" | jq -r .source_workspace)"

echo "== 7. one read per step (rs_once_begin) =="
# once_reads <dir>: reads of session $SW's record under one shared read kept in
# <dir>, in a subshell: the state, the state again, then a write's drop and the
# state again. Prints each one's return code.
once_reads() {
    [ $# -ge 1 ] || return 64
    ( PROG=t; SCOPE=roadmap NAME=plugin-system REPO=$REPO; . "$HERE/state-common.sh"; lib_facts
      RS_SESSION=$SW RS_RETRY_PAUSE=0
      rs_once_begin "$1" || exit 2
      rs_record "$1/a"; printf 'a%s ' $?
      rs_record "$1/b"; printf 'b%s ' $?
      rs_once_drop
      rs_record "$1/c"; printf 'c%s' $? )
}
metas() { grep -c "^context get $SW record/meta" "$KOTO_STORE/calls"; }
: > "$KOTO_STORE/calls"
eq "reads under one shared read, and one after a write's drop, all answer" "a0 b0 c0" "$(once_reads "$T/once")"
eq "  ... from two assemblies: the shared one, and the live one after the drop (two record/meta reads each)" 4 "$(metas)"
eq "  ... the shared reads with the same state" "$(jq -cS . "$T/once/a")" "$(jq -cS . "$T/once/b")"
eq "  ... and the same keys as assembled" "$(jq -cS . "$T/once/a.state")" "$(jq -cS . "$T/once/b.state")"
# The read reconcile-read.sh makes takes one assembly: two record/meta reads.
: > "$KOTO_STORE/calls"
bash "$HERE/reconcile-read.sh" --session "$SW" > "$T/rr.json" 2> "$T/rr.err"
eq "reconcile-read.sh reads a session record" "0 found" "$? $(jq -r .status "$T/rr.json" 2>/dev/null)"
eq "  ... in one assembly" 2 "$(metas)"

echo "== 8. the resume decision (PRD R12) =="
# rs_resume_candidate over this host's runs of one scope, on the koto stand-in:
# resume the newest holder of a record when it is the scope's only live run,
# compiled from the shipped hash, passing provenance, whose find recorded the
# session and without a directed transition; carry it otherwise; none without
# one.
HS=abababababababababababababababababababababababababababababababab
HO=cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
jq -c '.scope.name = "resume-probe"' "$T/rec.json" > "$T/rp.json"
clear_rp() { rm -rf "$KOTO_STORE"/sessions/coordinate-roadmap-resume-probe-* "$KOTO_STORE"/context/coordinate-roadmap-resume-probe-*; }
mk() { # mk <name> [template-hash] [vars-jq]: a run of resume-probe holding a record
    found_session "$1" "$(roadmap_vars resume-probe | jq -c "${3:-.}")" "${2:-$HS}"
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
clear_rp; mk "$R1"; koto context remove "$R1" coord/source.json
eq "a run whose find never recorded the session: none" "none $R1" "$(cand)"
clear_rp; mk coordinate-roadmap-resume-probe-copy; eq "a name off the pattern is never a candidate" "none null" "$(cand)"
clear_rp; mk "$R1"; printf '%s' coordinate-roadmap-other-20261013T090000Z > "$KOTO_STORE/sessions/$R1/.parent"
eq "a child session is never a candidate" "none null" "$(cand)"
# A run whose record/meta listing koto refuses may hold the record, so it is
# never skipped (shirabe#1257): newer than the newest holder, or with no holder
# at all, it is the answer, unreadable, with koto's reason, and the code
# bound-elsewhere when koto refused it as bound to another directory.
cand_json() { KOTO_COMPILED_HASH=$HS bash "$RS" --candidate --scope roadmap --name resume-probe --hash "$HS" 2>"$T/c.err"; }
clear_rp; mk "$R1"; log_end "$R1"; mk "$R2"
KOTO_BOUND_ELSEWHERE=$R2 cand_json > "$T/cand.json"
eq "a newer run refused as session_bound_elsewhere is unreadable, not skipped" "unreadable $R2 bound-elsewhere" \
    "$(jq -r '"\(.action) \(.session) \(.code)"' "$T/cand.json")"
grep -q session_bound_elsewhere <<< "$(jq -r .reason "$T/cand.json")" && ok "  ... its reason koto's" || bad "  ... its reason koto's" "$(cat "$T/cand.json")"
clear_rp; mk "$R1"; log_end "$R1"
eq "  ... and so is the only holder (the issue's second start)" "unreadable $R1 bound-elsewhere" \
    "$(KOTO_BOUND_ELSEWHERE=$R1 cand_json | jq -r '"\(.action) \(.session) \(.code)"')"
clear_rp; mk "$R1"; log_end "$R1"; mk "$R2"
KOTO_READ_FAIL=$R2 cand_json > "$T/cand.json"
eq "a newer run whose listing fails otherwise is unreadable with no code" "unreadable $R2 " \
    "$(jq -r '"\(.action) \(.session) \(.code // "")"' "$T/cand.json")"
grep -q 'the read of' <<< "$(jq -r .reason "$T/cand.json")" && ok "  ... its reason koto's" || bad "  ... its reason koto's" "$(cat "$T/cand.json")"
clear_rp; mk "$R1"; log_end "$R1"; mk "$R2"
eq "an unreadable run older than the newest holder changes nothing" "resume $R2" "$(KOTO_BOUND_ELSEWHERE=$R1 cand)"
clear_rp
bash "$RS" --candidate --scope roadmap --name resume-probe --hash abc >/dev/null 2>&1; eq "--candidate refuses a hash that isn't 64 hex" 64 $?
# The carry's write path: core_carry is called only by the opener.
eq "only coordinate-open.sh calls core_carry" "" "$(fn_callers "$HERE" core_carry '^coordinate-open\.sh$')"

echo "== 9. the opener's fresh start and the legacy importer =="
# A koto for the opener: the stand-in, with the session store's features, plus
# `init` (a session opened from the vars file, its log in the stand-in's
# shape) and `cancel` (the run marked cancelled), which the stand-in lacks.
mkdir -p "$T/opener"
cat > "$T/opener/koto" <<STUB
#!/usr/bin/env bash
REAL="$HERE/testdata/koto"
case "\${1:-}" in
    init)
        printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
        s=\$2 vf=
        while [ \$# -gt 0 ]; do [ "\$1" = --vars-file ] && vf=\$2; shift; done
        d="\$KOTO_STORE/sessions/\$s"
        mkdir -p "\$d"
        vars=\$(jq -c 'if type == "array" then map({(.[0]): .[1]}) | add else . end' "\$vf")
        jq -nc --arg s "\$s" '{schema_version: 1, workflow: \$s, template_hash: "$(printf '%064d' 0 | tr 0 a)", created_at: "2026-10-23T10:00:00.000Z", template_name: "coordinate"}' > "\$d/koto-\$s.state.jsonl"
        jq -nc --argjson v "\$vars" '{seq: 1, timestamp: "2026-10-23T10:00:00.000Z", type: "workflow_initialized", payload: {template_path: "x", variables: \$v}}' >> "\$d/koto-\$s.state.jsonl"
        echo '{"outcome":"created"}' ;;
    cancel)
        printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
        d="\$KOTO_STORE/sessions/\$2"
        [ -d "\$d" ] || exit 1
        printf '{"seq":99,"timestamp":"2026-10-23T10:00:00.000Z","type":"workflow_cancelled","payload":{}}\n' >> "\$d/koto-\$2.state.jsonl" ;;
    *) KOTO_FEATURES=1 exec "\$REAL" "\$@" ;;
esac
STUB
chmod +x "$T/opener/koto"
FX_IMP="$HERE/../legacy-import/testdata"
HSHIP=$(printf '%064d' 0 | tr 0 a)
fresh_open() { # fresh_open: a discipline start of ci-health through the opener; OUT and RC
    printf '%s' '["--discipline", "ci-health", "--host", "acme/widgets"]' > "$T/args.json"
    OUT=$(cd "$T" && KOTO_BIN="$T/opener/koto" KOTO_COMPILED_HASH=$HSHIP bash "$HERE/coordinate-open.sh" --plugin-root "$PLUGIN_ROOT_REAL" "$T/args.json" 2>"$T/err")
    RC=$?
    NEW=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
    CANCELLED=$(sed -n 's/^cancel //p' "$KOTO_STORE/calls" | tail -1)
}
importer_calls() { grep -c 'issues?state=open\|pr list --repo acme/widgets --head coordinate/discipline-ci-health' "$GH_DB.calls"; }
rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
db_init; : > "$KOTO_STORE/calls"
fresh_open
case "$RC $OUT" in "0 opened=new"*"session=coordinate-discipline-ci-health-"*) ok "a fresh start with no record on GitHub opens a run" ;;
    *) bad "a fresh start with no record on GitHub opens a run" "$RC $OUT $(cat "$T/err")" ;; esac
eq "  ... after the importer's one lookup" 1 "$(importer_calls)"
[ -e "$KOTO_STORE/context/$NEW/record/meta" ] && bad "  ... importing nothing" "" || ok "  ... importing nothing"
# A rotation pull request still open on GitHub: imported into the new run.
rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
TODAY=$(date -u +%Y-%m-%d) NEXT_WEEK=$(jq -rn 'now + 7 * 86400 | strftime("%Y-%m-%d")')
db_init; : > "$KOTO_STORE/calls"
db '.prs += [{repo: "acme/widgets", number: 76, title: $t, body: $b, state: "OPEN", isDraft: false,
    isCrossRepository: false, baseRefName: "main", headRefName: "coordinate/discipline-ci-health",
    headRefOid: "2222222222222222222222222222222222222222", author: "alice", editor: null}]' \
    --rawfile b "$FX_IMP/discipline.md" --arg t "docs(coordinate): ci-health rotation $TODAY to $NEXT_WEEK"
fresh_open
case "$RC $OUT" in *"record-imported=76"*"session=$NEW") ok "a rotation still open on GitHub is imported into the new run" ;;
    *) bad "a rotation still open on GitHub is imported into the new run" "$RC $OUT $(cat "$T/err")" ;; esac
eq "  ... which holds its record and its window" "false|$TODAY" \
    "$(koto context get "$NEW" record/meta | jq -r .pending)|$(koto context get "$NEW" record/rotation | jq -r .start)"
eq "  ... after one lookup" 1 "$(importer_calls)"
eq "  ... and the new run isn't cancelled" "" "$CANCELLED"
# The next start: a resume, which calls nothing on GitHub.
printf '{"source":"session","reason":"found"}' | koto context add "$NEW" coord/source.json
reset_calls; : > "$KOTO_STORE/calls"
fresh_open
eq "the next start resumes the run" "0 outcome=resumed resumed=1 session=$NEW" "$RC $(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
eq "  ... with no importer lookup and no GitHub call" "" "$(calls)"
# The next rotation, once that one has ended: not a fresh start, since the
# ended rotation's session is here, so the importer isn't asked, though the
# rotation pull request is still open on GitHub.
koto context get "$NEW" record/rotation | jq -c '.start = "2026-01-01" | .end = "2026-01-08"' > "$T/ended.json"
koto context add "$NEW" record/rotation --from-file "$T/ended.json"
ENDED=$NEW
reset_calls; : > "$KOTO_STORE/calls"
fresh_open
case "$RC $OUT" in "0 "*"session=coordinate-discipline-ci-health-"*)
        [ "$NEW" != "$ENDED" ] && ok "a start after the rotation ended opens the next one" \
            || bad "a start after the rotation ended opens the next one" "$OUT" ;;
    *) bad "a start after the rotation ended opens the next one" "$RC $OUT $(cat "$T/err")" ;; esac
eq "  ... with no importer lookup" 0 "$(importer_calls)"
# Two open rotation pull requests: the start stops, and the run it opened is
# cancelled so it can't go on without the record's state.
rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
db '.prs += [.prs[0] | .number = 77]'
reset_calls; : > "$KOTO_STORE/calls"
fresh_open
eq "two open records stop the start" "2 refused=several" "$RC $(printf '%s\n' "$OUT" | tail -1)"
OPENED=$(sed -n 's/^init \([^ ]*\) .*/\1/p' "$KOTO_STORE/calls" | tail -1)
eq "  ... cancelling the run it opened" "$OPENED" "$CANCELLED"
grep -q '76 77' "$T/err" && ok "  ... naming both" || bad "  ... naming both" "$(cat "$T/err")"
# A record that can't be read: record-unreadable, the run cancelled.
rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
db '.prs = [.prs[0] | .body = "> This is a **coordinator record** for the ci-health discipline.\n\nnot a record"]'
reset_calls; : > "$KOTO_STORE/calls"
fresh_open
eq "a record that can't be read stops the start" "2 refused=record-unreadable" "$RC $(printf '%s\n' "$OUT" | tail -1)"
OPENED=$(sed -n 's/^init \([^ ]*\) .*/\1/p' "$KOTO_STORE/calls" | tail -1)
eq "  ... cancelling the run it opened" "$OPENED" "$CANCELLED"
[ -e "$KOTO_STORE/context/$OPENED/record/meta" ] && bad "  ... with nothing imported" "" || ok "  ... with nothing imported"

done_tests state-read
