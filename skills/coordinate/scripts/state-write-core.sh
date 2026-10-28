# state-write-core.sh -- the coordinator record's one write path. Sourced, never
# run, and only by the agent-run write scripts (state-write.sh, which
# state-holding.sh calls, the decision writer, the hold writer, the stored-set
# writer, the opener for its seeding writes and coordinate-open.sh for the
# carry, and the legacy importer in ../legacy-import for its import); no check
# script sources it, which keeps state-common.sh's promise that everything a
# check sources only reads.
#
# The record lives in the coordinator's koto session (state-read.sh).
# core_write re-reads it and writes the next state whole, after the checks
# state-write.sh's header lists; every check from the state's own on lives
# here.
# core_write_host writes the record's record/host, the one key outside its
# tables and account; only state-stored-set.sh --host calls it.
# Four of core_write's checks, in brief:
#   - the Decisions section may be changed only by a script that sets
#     DECISIONS_WRITER=1 after sourcing this file, which resets it to 0, so a
#     value in the environment never counts (exit 65). Only
#     state-decision.sh sets it; a structure test holds every other script
#     to that;
#   - the Holds section likewise, through HOLDS_WRITER=1, which only
#     state-hold.sh sets; even it may only add a hold or stamp a blank
#     Lifted cell, never drop or change a hold (exit 65);
#   - the stored set's sections (Run, Standing, Work) likewise, through
#     STATE_WRITER=1, which only state-stored-set.sh sets (exit 65), except a
#     milestone's verdict-owed Work row, which changes only through
#     VERDICT_WRITER=1, which only roadmap-status.sh sets (exit 65), and a
#     rework Work row, which only VERDICT_WRITER adds or changes and either
#     writer removes (exit 65).
# The writer hands core_write the next state's JSON (STATE_FILE), which passes
# state-schema.jq's normalize_state (core_validate) before the live record is
# read: every column's grammar, the worker and pull request link shapes, the
# Holds, stored set and Decisions rules, and the home-path and token checks over
# every string, each refused with the module's `refused: ` message (exit 65).
# The private-repository check over every string runs again once the named
# repositories' visibility is read, still before any key is written. No body
# is rendered and no size limit applies: the state lives in the session's keys.
#
# The last step (core_write_session; docs/designs/DESIGN-coordinator-session-record.md,
# Decision 4) writes the changed section keys between two writes of
# record/meta. Each key's owner is its section's owner, so the owner checks
# above are the one-writer-per-key rule.
#
# The caller's contract:
#   - it has sourced state-common.sh, run lib_facts and lib_write_guard, and
#     set PROG, HERE, SESSION, SCOPE, NAME, REPO and STATE_FILE, the next state
#     as JSON carrying the written time of the version it was built from, in a
#     file of the writer's own private directory (mode 0600), which the writer
#     removes after the write (naming its directory in CORE_CLEANUP does that);
#     a writer that may change the Decisions section sets DECISIONS_WRITER=1
#     after sourcing this file;
#   - it runs without `set -e`: core_write reads the status of commands that
#     fail by design;
#   - core_write takes over the global T (its own temporary directory) and
#     the EXIT trap, which removes it, so a caller keeps nothing it needs in
#     $T. A caller with a scratch directory of its own names it in
#     CORE_CLEANUP, and the trap removes that too; any other EXIT trap the
#     caller set is replaced;
#   - core_write exits on every refusal and failure (10, 11, 12, 2, 65)
#     and returns only after a write, having printed the session that holds
#     the record.
# state-open.sh refuses a first state carrying a Decisions section, and seeds
# the run's keys through core_write.

# Closed by default at the moment this file is sourced, so a value in the
# environment never counts; the decision writer opens it after sourcing.
DECISIONS_WRITER=0
HOLDS_WRITER=0
STATE_WRITER=0
VERDICT_WRITER=0
# SESSION_SEED=1 makes the write the first one into a session holding no
# record/meta, or only the pending one an unfinished seed left; only
# state-open.sh sets it, to open a record or carry a predecessor rotation's
# sections into a new one. A structure test holds it to that script.
SESSION_SEED=0
# IMPORT_WRITER=1 opens core_import and core_import_meta, the legacy importer's
# write of a GitHub record's state into a session that holds no record
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The legacy
# importer"); only skills/coordinate/legacy-import/import.sh sets it, and a
# structure test holds every script here to that.
IMPORT_WRITER=0
# A holding's last pushed head (Decision 9; PRD R17) lives beside its row in
# record/holdings and never in the state a reader is handed: every Holdings write
# carries each row's value forward by Worker, and only state-write.sh
# --pushed-head, which state-holding.sh alone passes, sets one (CORE_PUSHED_SET=1
# with CORE_PUSHED_TOPIC and CORE_PUSHED_HEAD, 40 hex or empty to clear it).
CORE_PUSHED_SET=0 CORE_PUSHED_TOPIC= CORE_PUSHED_HEAD=
# The template compat a run was compiled at and its template's structural
# fingerprint, kept in record/meta as template_compat and template_fingerprint
# (shirabe#1333), so the run's compat stays known once a later compat table
# drops its fingerprint (coord-log.sh compat reads them). They are written
# where record/meta is born, by a seed, a carry and the legacy import, and by
# coordinate-open.sh's takeover over the predecessor's carried pair; every
# other write keeps them.
# The highest Standing id number the record has given out, kept in record/meta
# as standing_used so the next id is chosen without reading every entry
# (shirabe#1283). A write keeps it as record/meta has it; state-stored-set.sh
# --standing raises it to the id it gives out (CORE_STANDING_USED, a whole
# number); a seed into a session holding no entry, and a carry, set it.
CORE_STANDING_USED=

# core_live: the live record, read through the seam, and every check against it:
# the record this scope's, the compare on the written time, and the section
# owners. Sets BASE, URL and the live files in $T. A seeding write
# (SESSION_SEED) has no live record and skips it.
core_live() {
    local live_rc
    rs_record "$T/live.json"; live_rc=$?
    [ $live_rc -eq 2 ] && lib_die2 "cannot read the record: $(lib_scrub < "$T/live.json.err" | head -1)"
    [ $live_rc -eq 4 ] && { lib_scrub < "$T/live.json.err" >&2; exit 10; }
    [ $live_rc -eq 12 ] && { lib_scrub < "$T/live.json.err" >&2; exit 12; }
    # A session holding another scope's record holds no record of this one.
    if [ $live_rc -eq 65 ] && [ -s "$T/live.json.state" ] \
        && [ "$(jq -c '.scope' "$T/live.json.state")" != "$(jq -nc --arg k "$SCOPE" --arg n "$NAME" '{kind: $k, name: $n}')" ]; then
        echo "$PROG: refused: $(lib_record_name) holds another scope's record, not this $SCOPE's" >&2
        exit 10
    fi
    URL=${RS_SESSION:-$SESSION}
    # Compare and swap on the written time. The state carries the written time
    # of the version it was edited from; the live record must still carry that
    # time, or someone wrote the record since it was read and this write would
    # lose their change. A live record that no longer reads back as this
    # scope's has changed too.
    BASE=$(jq -r '.written // ""' "$T/parsed.json")
    if [ $live_rc -eq 0 ]; then
        LIVE_W=$(jq -r '.written // ""' "$T/live.json")
    else
        LIVE_W="(a record that doesn't read back: $(lib_scrub < "$T/live.json.err" | head -1))"
    fi
    if [ -z "$BASE" ] || [ "$BASE" != "$LIVE_W" ]; then
        echo "$PROG: refused: record-changed: $(lib_record_name) was written at $LIVE_W, but this state was edited from ${BASE:-no version}; re-read it and redo the change" >&2
        exit 12
    fi
    # The Decisions section changes only through the decision writer, which
    # checks each transition; any other write must carry it as the live record
    # has it.
    if [ "$DECISIONS_WRITER" != 1 ]; then
        NEW_D=$(jq -cS '.decisions // null' "$T/parsed.json") && LIVE_D=$(jq -cS '.decisions // null' "$T/live.json") \
            || lib_die2 "cannot compare the Decisions sections"
        if [ "$NEW_D" != "$LIVE_D" ]; then
            echo "$PROG: refused: the Decisions section changes only through state-decision.sh; carry it as the live record has it" >&2
            exit 65
        fi
    fi
    # The Holds section changes only through the hold writer, and even it may
    # only add a hold or stamp a blank Lifted cell: every live hold stays, with
    # every other cell as it was.
    NEW_H=$(jq -cS '.holds // []' "$T/parsed.json") && LIVE_H=$(jq -cS '.holds // []' "$T/live.json") \
        || lib_die2 "cannot compare the Holds sections"
    if [ "$HOLDS_WRITER" != 1 ]; then
        if [ "$NEW_H" != "$LIVE_H" ]; then
            echo "$PROG: refused: the Holds section changes only through state-hold.sh; carry it as the live record has it" >&2
            exit 65
        fi
    elif ! jq -n -e --argjson n "$NEW_H" --argjson l "$LIVE_H" '
            all($l[]; . as $o | [$n[] | select(.hold == $o.hold)] as $m
                | ($m | length) == 1
                  and ($m[0] | del(.lifted)) == ($o | del(.lifted))
                  and ($o.lifted == "" or $m[0].lifted == $o.lifted))' > /dev/null; then
        echo "$PROG: refused: a hold is never removed or changed, only added or lifted once" >&2
        exit 65
    fi

    # A milestone's verdict-owed Work row changes only through
    # roadmap-status.sh, which writes it at the landed tick and clears it
    # when the verdict's roadmap edit is confirmed.
    if [ "$VERDICT_WRITER" != 1 ]; then
        NEW_V=$(jq -cS '[(.work // [])[] | select(.kind == "verdict-owed")]' "$T/parsed.json") \
            && LIVE_V=$(jq -cS '[(.work // [])[] | select(.kind == "verdict-owed")]' "$T/live.json") \
            || lib_die2 "cannot compare the verdict-owed rows"
        if [ "$NEW_V" != "$LIVE_V" ]; then
            echo "$PROG: refused: a verdict-owed Work row changes only through roadmap-status.sh; carry the rows as the live record has them" >&2
            exit 65
        fi
        # A rework row is written only there too, at the confirmation of a
        # changes-needed verdict or a reopen; state-stored-set.sh may only remove
        # one.
        if ! jq -e --slurpfile live "$T/live.json" '
                [(.work // [])[] | select(.kind == "rework")] as $n
                | [($live[0].work // [])[] | select(.kind == "rework")] as $l
                | all($n[]; . as $r | any($l[]; . == $r))' "$T/parsed.json" > /dev/null; then
            echo "$PROG: refused: a rework Work row is written only by roadmap-status.sh --confirm; carry the rows as the live record has them" >&2
            exit 65
        fi
    fi
    # The stored set's other rows change only through state-stored-set.sh, and a
    # rework row leaves through it or roadmap-status.sh.
    if [ "$STATE_WRITER" != 1 ]; then
        NEW_S=$(jq -cS '{run: (.run // []), standing: (.standing // []), work: [(.work // [])[] | select(.kind != "verdict-owed" and .kind != "rework")]}' "$T/parsed.json") \
            && LIVE_S=$(jq -cS '{run: (.run // []), standing: (.standing // []), work: [(.work // [])[] | select(.kind != "verdict-owed" and .kind != "rework")]}' "$T/live.json") \
            || lib_die2 "cannot compare the stored set's sections"
        if [ "$NEW_S" != "$LIVE_S" ]; then
            echo "$PROG: refused: the Run, Standing and Work sections change only through state-stored-set.sh; carry them as the live record has them" >&2
            exit 65
        fi
        if [ "$VERDICT_WRITER" != 1 ] && [ "$(jq -cS '[(.work // [])[] | select(.kind == "rework")]' "$T/parsed.json")" != "$(jq -cS '[(.work // [])[] | select(.kind == "rework")]' "$T/live.json")" ]; then
            echo "$PROG: refused: a rework Work row leaves only through state-stored-set.sh --done or roadmap-status.sh; carry the rows as the live record has them" >&2
            exit 65
        fi
    fi

}

# core_write_session <state-file>: the write's last step, for the next state in
# normal form with its new written time. record/meta is read once more and the
# write refused record-changed (12) unless its written time is the one the
# caller edited from (a seeding write needs no record/meta at all); then
# record/meta is marked pending, each section key whose JSON changed is written
# (a section the state no longer holds loses its key), and record/meta is written
# last with the new time, its standing_used kept, raised to CORE_STANDING_USED
# when that is set, or started on a seed (CORE_STANDING_USED above). A failure
# after the first key changed exits 11; the
# pending mark tells a reader not to trust the sections until a write clears it.
core_write_session() {
    local s=${RS_SESSION:-$SESSION} pair field key rc RESEED= LIVE_SEC
    [ -n "$s" ] || lib_die2 "the session store needs the run's session"
    [ "$1" = "$T/next-state.json" ] || cp "$1" "$T/next-state.json" || lib_die2 "cannot copy the state"
    rs_key "$s" record/meta "$T/meta.now"; rc=$?
    if [ "$SESSION_SEED" = 1 ]; then
        # A seed that stopped part way left record/meta pending with no written
        # time, which no finished write leaves: seeding again finishes it.
        [ $rc -eq 1 ] || { [ $rc -eq 0 ] && jq -e '.pending == true and .written == ""' "$T/meta.now" > /dev/null; } \
            || { echo "$PROG: refused: session $s already holds a record" >&2; exit 65; }
        RESEED=$([ $rc -eq 0 ] && echo 1)
        jq -nc --argjson sc "$(jq -c .scope "$T/next-state.json")" --argjson tc "$(core_compat_meta "$s")" \
            '{scope: $sc, store: "session", written: "", pending: false} + $tc' > "$T/meta.now"
        : > "$T/live.json"
    else
        [ $rc -eq 0 ] || lib_die2 "cannot read session $s's record/meta"
        if [ "$(jq -r '.written' "$T/meta.now")" != "$BASE" ]; then
            echo "$PROG: refused: record-changed: session $s's record was written at $(jq -r '.written' "$T/meta.now"), but this state was edited from $BASE; re-read it and redo the change" >&2
            exit 12
        fi
    fi
    jq -c '.pending = true' "$T/meta.now" > "$T/meta.pending"
    "$KOTO" context add "$s" record/meta --from-file "$T/meta.pending" < /dev/null > /dev/null 2> "$T/k.err" \
        || { echo "$PROG: the session write failed: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
    # A seed lists the session's record keys once: a re-seed removes the section
    # keys the unfinished seed left that this state doesn't hold, and a session
    # holding no entry starts standing_used at the seeded Standing rows' highest
    # id, since no entry names another.
    if [ "$SESSION_SEED" = 1 ]; then
        rs_list "$s" record/ "$T/reseed-keys" || lib_die2 "cannot list session $s's record keys: $(lib_scrub < "$T/reseed-keys.err")"
        if ! jq -e 'any(.[]; startswith("record/entries/"))' "$T/reseed-keys" > /dev/null; then
            jq -c --slurpfile st "$T/next-state.json" \
                '.standing_used = ([($st[0].standing // [])[] | .standing[1:] | tonumber] | max // 0)' \
                "$T/meta.now" > "$T/meta.seeded" && mv "$T/meta.seeded" "$T/meta.now" || lib_die2 "jq failed"
        fi
    fi
    # The live holdings as the session keeps them, pushed heads included (the
    # parsed live record has them stripped): each row's head is carried forward
    # by Worker, and CORE_PUSHED_* sets one.
    if [ -s "$T/live.json" ] && [ -s "$T/live.json.state" ]; then
        jq -c '.holdings // []' "$T/live.json.state" > "$T/live-holdings.json" || lib_die2 "jq failed"
    else
        echo '[]' > "$T/live-holdings.json"
    fi
    for pair in $RS_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        if jq -e --arg f "$field" 'has($f)' "$T/next-state.json" > /dev/null; then
            jq -c --arg f "$field" '.[$f]' "$T/next-state.json" > "$T/sec.new"
            LIVE_SEC=$( [ -s "$T/live.json" ] && jq -cS --arg f "$field" 'if has($f) then .[$f] else empty end' "$T/live.json")
            if [ "$field" = holdings ]; then
                jq -c --slurpfile live "$T/live-holdings.json" --arg set "$CORE_PUSHED_SET" --arg t "$CORE_PUSHED_TOPIC" --arg h "$CORE_PUSHED_HEAD" '
                    ($live[0] | map(select((.pushed_head // "") != "") | {(.worker): .pushed_head}) | add // {}) as $p
                    | map(. as $r | (if $set == "1" and $r.worker == $t then $h else ($p[$r.worker] // "") end) as $v
                          | if $v == "" then del(.pushed_head) else . + {pushed_head: $v} end)' "$T/sec.new" > "$T/sec.merged" \
                    || lib_die2 "jq failed"
                mv "$T/sec.merged" "$T/sec.new"
                LIVE_SEC=$( [ -s "$T/live.json" ] && jq -cS '.' "$T/live-holdings.json")
            fi
            if [ -n "$LIVE_SEC" ] && [ "$LIVE_SEC" = "$(jq -cS . "$T/sec.new")" ]; then
                continue
            fi
            "$KOTO" context add "$s" "record/$key" --from-file "$T/sec.new" < /dev/null > /dev/null 2> "$T/k.err" \
                || { echo "$PROG: the session write failed part way, at record/$key: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
        elif { [ -s "$T/live.json" ] && jq -e --arg f "$field" 'has($f)' "$T/live.json" > /dev/null; } \
            || { [ -n "${RESEED:-}" ] && jq -e --arg key "record/$key" 'index($key) != null' "$T/reseed-keys" > /dev/null; }; then
            "$KOTO" context remove "$s" "record/$key" < /dev/null > /dev/null 2> "$T/k.err" \
                || { echo "$PROG: the session write failed part way, removing record/$key: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
        fi
    done
    jq -c --arg w "$(jq -r '.written' "$T/next-state.json")" --arg u "$CORE_STANDING_USED" '.written = $w | .pending = false
        | if $u == "" then . else .standing_used = ([(.standing_used | if type == "number" then . else 0 end), ($u | tonumber)] | max) end' \
        "$T/meta.now" > "$T/meta.next" || lib_die2 "jq failed"
    "$KOTO" context add "$s" record/meta --from-file "$T/meta.next" < /dev/null > /dev/null 2> "$T/k.err" \
        || { echo "$PROG: the session write failed part way, at record/meta: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
}

# core_write_host <json-file>: replace the run's record/host with the object in
# <json-file>, the host facts state-stored-set.sh --host merged and checked (PRD R14,
# R17). Only state-stored-set.sh calls it, which a structure test holds; it writes
# no section and no entry, since host facts never leave the host. Exits 10 when
# the session holds no record (no record/meta), 11 when the write fails, 2 when
# a read fails.
core_write_host() {
    local s=${RS_SESSION:-$SESSION} d
    [ -n "$s" ] || lib_die2 "record/host needs the run's session"
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-host.XXXXXX") || lib_die2 "mktemp failed"
    rs_key "$s" record/meta "$d/meta"
    case $? in
        0) ;;
        1) rm -rf "$d"; echo "$PROG: refused: session $s holds no record" >&2; exit 10 ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $s's record/meta" ;;
    esac
    "$KOTO" context add "$s" record/host --from-file "$1" < /dev/null > /dev/null 2> "$d/k.err" \
        || { echo "$PROG: the record/host write failed: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
    rm -rf "$d"
}

# core_compat_meta <session>: the run's template_compat and
# template_fingerprint as a JSON object for record/meta, from coord-log.sh
# compat: the compat the table beside the run's plugin lists its fingerprint
# at. A table never renumbers a fingerprint (check-template-compat.sh), so that
# is the compat the run was compiled at. {} when the fingerprint can't be read
# or the table doesn't list it: the record then says nothing rather than
# something wrong, and a reader falls back to the table as before.
core_compat_meta() {
    local c f
    read -r c _ f <<EOF
$(bash "$HERE/coord-log.sh" compat --session "$1" < /dev/null 2> /dev/null)
EOF
    if [[ $c =~ ^[1-9][0-9]*$ ]] && [[ $f =~ ^[0-9a-f]{64}$ ]]; then
        jq -nc --argjson c "$c" --arg f "$f" '{template_compat: $c, template_fingerprint: $f}'
    else
        echo '{}'
    fi
}

# core_write_meta <session> <jq filter> [jq args...]: rewrite the run's
# record/meta with <filter> applied, for the fields a takeover keeps there
# (driver, takeover, takeover_done; DESIGN-coordinate-successor-continues.md).
# Every other write keeps them, since core_write_session changes only written,
# pending and standing_used, and the filter keeps standing_used as it is. One
# key replaced whole, and never while a write holds it
# pending. Only coordinate-open.sh calls it. Exits 10 the session holds no
# record; 12 its record is being written; 65 the filter failed; 11 the write
# failed; 2 a read failed.
core_write_meta() {
    local s=$1 f=$2 d
    shift 2
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-meta.XXXXXX") || lib_die2 "mktemp failed"
    rs_key "$s" record/meta "$d/meta"
    case $? in
        0) ;;
        1) rm -rf "$d"; echo "$PROG: refused: session $s holds no record" >&2; exit 10 ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $s's record/meta" ;;
    esac
    jq -e '.pending != true' "$d/meta" > /dev/null 2>&1 \
        || { rm -rf "$d"; echo "$PROG: refused: session $s's record is being written" >&2; exit 12; }
    jq -c "$@" "$f" "$d/meta" > "$d/next" 2> /dev/null \
        || { rm -rf "$d"; echo "$PROG: refused: the record/meta filter failed" >&2; exit 65; }
    "$KOTO" context add "$s" record/meta --from-file "$d/next" < /dev/null > /dev/null 2> "$d/k.err" \
        || { echo "$PROG: the record/meta write failed: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
    rm -rf "$d"
}

# core_carry_withdraw <to>: remove record/meta from the run a carry wrote into
# when the carry didn't land (shirabe#1257), so it holds no record and a later
# start never takes its copy for the record; the keys copied before it stay,
# unread. Only coordinate-open.sh calls it, before cancelling that run. Returns
# 0 removed or never written; 1 the listing or the removal failed.
core_carry_withdraw() {
    local d rc=0
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-withdraw.XXXXXX") || return 1
    rs_list "$1" record/meta "$d/keys" || { rm -rf "$d"; return 1; }
    if jq -e 'index("record/meta") != null' "$d/keys" > /dev/null; then
        "$KOTO" context remove "$1" record/meta < /dev/null > /dev/null 2>&1 || rc=1
    fi
    rm -rf "$d"
    return $rc
}

# core_write_pushed: set one holding's pushed head (CORE_PUSHED_TOPIC,
# CORE_PUSHED_HEAD: 40 hex, or empty to clear it) by rewriting record/holdings
# alone, the one key that keeps it. The head is no field of the state, so the
# state, its written time and every other key stay as they are, and none of the
# state's checks apply: no live re-read, validation or visibility read
# (shirabe#1094, #1095). Only state-write.sh calls it, for --pushed-head with
# no state file. One key replaced whole is never seen half written, so the write
# needs no pending mark. Exits 65 on a malformed head or a topic no holding
# has; 10 when the run has no found record or the session holds none; 11 when
# the write fails; 2 when a read fails. Prints the session holding the record.
core_write_pushed() {
    local s=${RS_SESSION:-$SESSION} d
    [[ $CORE_PUSHED_HEAD =~ ^([0-9a-f]{40})?$ ]] || { echo "$PROG: refused: a pushed head is 40 hex, or empty to clear it" >&2; exit 65; }
    lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-pushed.XXXXXX") || lib_die2 "mktemp failed"
    rs_key "$s" record/holdings "$d/holdings"
    case $? in
        0) ;;
        1) rs_key "$s" record/meta "$d/meta"
           case $? in
               1) rm -rf "$d"; echo "$PROG: refused: session $s holds no record" >&2; exit 10 ;;
               0) rm -rf "$d"; echo "$PROG: refused: no holding's Worker is $CORE_PUSHED_TOPIC" >&2; exit 65 ;;
           esac
           rm -rf "$d"; lib_die2 "cannot read session $s's record/meta" ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $s's record/holdings" ;;
    esac
    jq -e --arg t "$CORE_PUSHED_TOPIC" 'type == "array" and any(.[]; .worker == $t)' "$d/holdings" > /dev/null 2>&1 \
        || { rm -rf "$d"; echo "$PROG: refused: no holding's Worker is $CORE_PUSHED_TOPIC" >&2; exit 65; }
    jq -c --arg t "$CORE_PUSHED_TOPIC" --arg h "$CORE_PUSHED_HEAD" '
        map(if .worker == $t then (if $h == "" then del(.pushed_head) else . + {pushed_head: $h} end) else . end)' \
        "$d/holdings" > "$d/holdings.new" || { rm -rf "$d"; lib_die2 "jq failed"; }
    # The step's shared read is forgotten before the write and once it lands,
    # as core_write forgets it.
    rs_once_drop
    if [ "$(jq -cS . "$d/holdings")" != "$(jq -cS . "$d/holdings.new")" ]; then
        "$KOTO" context add "$s" record/holdings --from-file "$d/holdings.new" < /dev/null > /dev/null 2> "$d/k.err" \
            || { echo "$PROG: the record/holdings write failed: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
        rs_once_drop
    fi
    rm -rf "$d"
    printf '%s\n' "$s"
}

# core_write_rotation <key> <json-file>: a discipline rotation's own key,
# record/rotation (its window, host and predecessor) or record/reasoning (what
# it leaves the next rotation), written whole. They describe the rotation, not
# its rows, so they are no section and the state a reader is handed never
# carries them.
# Only state-stored-set.sh writes them, with STATE_WRITER=1 (the structure test
# holds it there); the caller has checked the value. Exits 65 refused (not the
# state writer, another key, or not discipline scope); 10 the session holds no
# record (no record/meta); 11 the write failed; 2 a read failed.
core_write_rotation() {
    local key=$1 s=${RS_SESSION:-$SESSION} d
    case "$key" in record/rotation|record/reasoning) ;; *) echo "$PROG: refused: $key is not a rotation key" >&2; exit 65 ;; esac
    [ "$STATE_WRITER" = 1 ] || { echo "$PROG: refused: $key changes only through state-stored-set.sh" >&2; exit 65; }
    [ "$SCOPE" = discipline ] || { echo "$PROG: refused: $key belongs to a discipline rotation" >&2; exit 65; }
    [ -n "$s" ] || lib_die2 "$key needs the run's session"
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-rotation.XXXXXX") || lib_die2 "mktemp failed"
    rs_key "$s" record/meta "$d/meta"
    case $? in
        0) ;;
        1) rm -rf "$d"; echo "$PROG: refused: session $s holds no record" >&2; exit 10 ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $s's record/meta" ;;
    esac
    rs_once_drop
    "$KOTO" context add "$s" "$key" --from-file "$2" < /dev/null > /dev/null 2> "$d/k.err" \
        || { echo "$PROG: the $key write failed: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
    rs_once_drop
    rm -rf "$d"
}

# core_carry <from> <to>: copy a record, its state and its account, from run
# <from> into the new run <to> on this host: every record/ and
# legs/ key (PRD R12; Decision 6). The source is read through the seam, so it
# passes every check a read makes: it assembles and reads back as this scope's
# record (SCOPE, NAME) under state-schema.jq's rules, and holds only
# well-formed pushed heads. The target must hold no record. Each key's name is
# checked against the session store's names and its value checked (JSON, or for
# record/posted/<n> a comment URL on an issue or pull request, the item an
# outward entry was posted on), then copied, and
# record/meta goes last, with the source's written time and a standing_used no
# lower than any Standing id the source's meta, entries or rows name (read from
# the entries as they are copied, so no extra call): until it lands the new
# run holds no record, so a carry cut short leaves nothing a start would resume,
# and the next start carries again. Only coordinate-open.sh calls it, which a
# structure test holds. Exits 10 the source holds no record; 12 it was being
# written; 65 refused (the reason on stderr); 11 a
# write failed; 2 a read failed.
core_carry() {
    local from=$1 to=$2 d k rc secs
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-carry.XXXXXX") || lib_die2 "mktemp failed"
    rs_session_read "$d/rec" "$from" "$SCOPE" "$NAME"; rc=$?
    case $rc in
        0) ;;
        4) lib_scrub < "$d/rec.err" >&2; rm -rf "$d"; exit 10 ;;
        12) lib_scrub < "$d/rec.err" >&2; rm -rf "$d"; exit 12 ;;
        65) echo "$PROG: refused: session $from's record doesn't read back as this scope's:" >&2; lib_scrub < "$d/rec.err" >&2; rm -rf "$d"; exit 65 ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $from's record" ;;
    esac
    rs_key "$to" record/meta "$d/to-meta"
    case $? in
        1) ;;
        0) rm -rf "$d"; echo "$PROG: refused: session $to already holds a record" >&2; exit 65 ;;
        *) rm -rf "$d"; lib_die2 "cannot read session $to's record/meta" ;;
    esac
    rs_list "$from" record/ "$d/rk" && rs_list "$from" legs/ "$d/lk" || { rm -rf "$d"; lib_die2 "cannot list session $from's keys"; }
    secs=" $(for p in $RS_SECTIONS; do printf 'record/%s ' "${p#*:}"; done)"
    jq -r '.[]' "$d/rk" "$d/lk" > "$d/keys" || { rm -rf "$d"; lib_die2 "jq failed"; }
    # standing_used for the new run, from the entries the carry reads anyway:
    # each one's leading Standing id is collected as it is copied.
    : > "$d/used"
    while IFS= read -r k; do
        case "$k" in
            record/meta) continue ;;
            # A rotation's window and its reasoning go with it on a restart.
            record/host|record/rotation|record/reasoning) ;;
            record/entries/*|record/posted/*|record/archive/*) [[ $k =~ ^record/(entries|posted|archive)/[0-9]{6}$ ]] || { rm -rf "$d"; echo "$PROG: refused: session $from holds a key named $k" >&2; exit 65; } ;;
            record/*) case "$secs" in *" $k "*) ;; *) rm -rf "$d"; echo "$PROG: refused: session $from holds a key named $k, not one of the session store's" >&2; exit 65 ;; esac ;;
            legs/*) [[ $k =~ ^legs/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || { rm -rf "$d"; echo "$PROG: refused: session $from holds a key named $k" >&2; exit 65; } ;;
        esac
        "$KOTO" context get "$from" "$k" < /dev/null > "$d/v" 2> "$d/k.err" || { rm -rf "$d"; lib_die2 "cannot read $k: $(lib_scrub < "$d/k.err")"; }
        case "$k" in
            record/posted/*)
                [[ $(cat "$d/v") =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[1-9][0-9]*#issuecomment-[0-9]+$ ]] \
                    || { rm -rf "$d"; echo "$PROG: refused: $k isn't a comment URL on an issue or a pull request" >&2; exit 65; } ;;
            *) jq -e . "$d/v" > /dev/null 2>&1 || { rm -rf "$d"; echo "$PROG: refused: $k isn't JSON" >&2; exit 65; } ;;
        esac
        case "$k" in
            record/entries/*) jq -r '.text? // empty | strings | scan("^(s[1-9][0-9]*)") | .[0][1:]' "$d/v" >> "$d/used" \
                || { rm -rf "$d"; lib_die2 "jq failed"; } ;;
        esac
        "$KOTO" context add "$to" "$k" --from-file "$d/v" < /dev/null > /dev/null 2> "$d/k.err" \
            || { echo "$PROG: the carry into $to failed at $k: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
    done < "$d/keys"
    # The highest of the source's own standing_used, the ids the entries name
    # and the Standing rows': the next id in the new run is above all of them.
    # The new run's own template compat, never the source's: the two may run
    # different templates. Before standing_used, in the order a seed leaves.
    jq -c --rawfile e "$d/used" --slurpfile m "$d/rec.meta" --argjson tc "$(core_compat_meta "$to")" '
        {scope, store: "session", written, pending: false} + $tc
        + {standing_used: ([($m[0].standing_used | if type == "number" then . else 0 end),
                            ($e | split("\n")[] | select(. != "") | tonumber),
                            ((.standing // [])[] | .standing[1:] | tonumber)] | max)}' \
        "$d/rec.state" > "$d/meta" || { rm -rf "$d"; lib_die2 "jq failed"; }
    "$KOTO" context add "$to" record/meta --from-file "$d/meta" < /dev/null > /dev/null 2> "$d/k.err" \
        || { echo "$PROG: the carry into $to failed at record/meta: $(lib_scrub < "$d/k.err")" >&2; rm -rf "$d"; exit 11; }
    rm -rf "$d"
}

# core_validate <state-file> [<out>]: the state's JSON checked by
# state-schema.jq's normalize_state, with the repositories the host can't show
# public ($PRIVATE), before anything is written; <out>, when given, gets the
# state in the normal form a reader is handed. A state that breaks a rule is
# refused with the module's `refused: ` message (exit 65).
core_validate() {
    if jq -L "$HERE" --arg private "$PRIVATE" 'include "state-schema";
            normalize_state($private | split(",") | map(select(. != "")))' "$1" > "${2:-/dev/null}" 2> "$T/schema.err" < /dev/null; then
        return 0
    fi
    grep -q 'refused: ' "$T/schema.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$T/schema.err")"
    echo "$PROG: refused: $(sed -n 's/.*refused: //p' "$T/schema.err" | head -1 | lib_scrub)" >&2
    [ -z "$PRIVATE" ] || echo "$PROG: private, or unreadable from the public host $REPO: $PRIVATE" >&2
    exit 65
}

# core_import <state-file> <entries-file> [<rotation-file>]: the legacy
# importer's write of a GitHub record's state, as its own parser read it, into
# the run's session, which must hold no record/meta. The state passes
# core_validate whole before any key is written; each section key is then
# written whole (a section the state doesn't hold loses its key), each entry in
# <entries-file>, a JSON array of {n, stamp, kind, text} numbered from 1, as
# record/entries/<n> (an entry key numbered past the last is removed), a
# `decisions` entry with its marker record/archive/<n> as state-entry.sh writes
# one (a marker on any other number is removed), and at
# discipline scope <rotation-file>, {start, end, host_repo, predecessor: null},
# as record/rotation. record/meta is left to core_import_meta, which the
# importer calls last, so an import cut short leaves no record and the next
# start imports again, rewriting the same keys. Both need IMPORT_WRITER=1.
# Exits 65 refused (the reason on stderr); 11 a write failed; 2 a read failed.
core_import() {
    local s=${RS_SESSION:-$SESSION} pair field key n
    core_import_open "$s"
    PRIVATE=
    core_validate "$1"
    jq -e 'type == "array" and (to_entries | all(.key as $i | .value | type == "object"
            and keys == ["kind", "n", "stamp", "text"] and .n == $i + 1
            and (.stamp | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
            and (.kind | type == "string" and test("^[a-z][a-z-]*$")) and (.text | type) == "string"))' "$2" > /dev/null 2>&1 \
        || { echo "$PROG: refused: the entries are not a list of {n, stamp, kind, text} numbered from 1" >&2; exit 65; }
    if [ "$SCOPE" = discipline ]; then
        [ -n "${3:-}" ] && jq -e --arg r "$REPO" 'type == "object" and keys == ["end", "host_repo", "predecessor", "start"]
                and .predecessor == null and .host_repo == $r and (.start | type) == "string" and (.end | type) == "string"' "$3" > /dev/null 2>&1 \
            && lib_valid_date "$(jq -r .start "$3")" && lib_valid_date "$(jq -r .end "$3")" \
            && [ ! "$(jq -r .end "$3")" \< "$(jq -r .start "$3")" ] \
            || { echo "$PROG: refused: a discipline import needs its rotation, {start, end, host_repo, predecessor: null}" >&2; exit 65; }
    fi
    rs_list "$s" record/ "$T/keys" || lib_die2 "cannot list session $s's record keys: $(lib_scrub < "$T/keys.err")"
    for pair in $RS_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        if jq -e --arg f "$field" 'has($f)' "$1" > /dev/null; then
            jq -c --arg f "$field" '.[$f]' "$1" > "$T/sec"
            core_import_add "$s" "record/$key" "$T/sec"
        elif jq -e --arg k "record/$key" 'index($k) != null' "$T/keys" > /dev/null; then
            core_import_remove "$s" "record/$key"
        fi
    done
    n=$(jq length "$2")
    for i in $(jq -r 'keys[]' "$2"); do
        jq -c --argjson i "$i" '.[$i]' "$2" > "$T/entry"
        if [ "$(jq -r .kind "$T/entry")" = decisions ]; then
            jq -c '{n}' "$T/entry" > "$T/marker"
            core_import_add "$s" "record/archive/$(printf '%06d' $((i + 1)))" "$T/marker"
        fi
        core_import_add "$s" "record/entries/$(printf '%06d' $((i + 1)))" "$T/entry"
    done
    for key in $(jq -r --argjson n "$n" '.[] | select(test("^record/entries/[0-9]{6}$")) | select((ltrimstr("record/entries/") | tonumber) > $n)' "$T/keys"); do
        core_import_remove "$s" "$key"
    done
    # A marker an earlier, cut-short import left on an entry this one doesn't
    # write as a decisions entry.
    for key in $(jq -r --slurpfile e "$2" '[$e[0][] | select(.kind == "decisions") | .n] as $d
            | .[] | select(test("^record/archive/[0-9]{6}$")) | select((ltrimstr("record/archive/") | tonumber) as $m | $d | index($m) | not)' "$T/keys"); do
        core_import_remove "$s" "$key"
    done
    [ "$SCOPE" != discipline ] || core_import_add "$s" record/rotation "$3"
}

# core_import_meta <state-file>: the import's last write, record/meta with the
# state's scope and written time and the run's template compat; from then the
# session holds the record.
core_import_meta() {
    local s=${RS_SESSION:-$SESSION}
    core_import_open "$s"
    jq -c --argjson tc "$(core_compat_meta "$s")" '{scope, store: "session", written, pending: false} + $tc' "$1" > "$T/meta" || lib_die2 "jq failed"
    core_import_add "$s" record/meta "$T/meta"
}

# core_import_open <session>: the checks both import writes make first: the
# importer's flag, and a session holding no record/meta.
core_import_open() {
    [ "$IMPORT_WRITER" = 1 ] || { echo "$PROG: refused: only the legacy importer imports a record" >&2; exit 65; }
    [ -n "$1" ] || lib_die2 "the import needs the run's session"
    T=$(mktemp -d "${TMPDIR:-/tmp}/state-import.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$T" ${CORE_CLEANUP:+"$CORE_CLEANUP"}' EXIT
    rs_key "$1" record/meta "$T/meta.now"
    case $? in
        1) ;;
        0) echo "$PROG: refused: session $1 already holds a record" >&2; exit 65 ;;
        *) lib_die2 "cannot read session $1's record/meta: $(lib_scrub < "$T/meta.now.err")" ;;
    esac
}
core_import_add() { # core_import_add <session> <key> <file>
    "$KOTO" context add "$1" "$2" --from-file "$3" < /dev/null > /dev/null 2> "$T/k.err" \
        || { echo "$PROG: the import into $1 failed at $2: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
}
core_import_remove() { # core_import_remove <session> <key>
    "$KOTO" context remove "$1" "$2" < /dev/null > /dev/null 2> "$T/k.err" \
        || { echo "$PROG: the import into $1 failed removing $2: $(lib_scrub < "$T/k.err")" >&2; exit 11; }
}

core_write() {
    # Every write but a seed goes to a run whose find sealed its record.
    if [ "$SESSION_SEED" != 1 ]; then
        lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
    fi

    T=$(mktemp -d "${TMPDIR:-/tmp}/state-write.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$T" ${CORE_CLEANUP:+"$CORE_CLEANUP"}' EXIT

    # The next state, as the writer built it from the version it read (its
    # written time that version's), checked whole by state-schema.jq before the
    # live record is read: every rule but the private-repository scan, which
    # needs the visibility reads below and runs once they are made.
    jq -e 'type == "object"' "$STATE_FILE" > /dev/null 2>&1 \
        || { echo "$PROG: refused: the state file doesn't hold a JSON object" >&2; exit 65; }
    if [ "$(jq -c '.scope' "$STATE_FILE")" != "$(jq -nc --arg k "$SCOPE" --arg n "$NAME" '{kind: $k, name: $n}')" ]; then
        echo "$PROG: refused: the state is not a $SCOPE record for $NAME" >&2
        exit 65
    fi
    PRIVATE=
    core_validate "$STATE_FILE" "$T/parsed.json"

    # A pushed head (state-write.sh --pushed-head) is kept beside a holding
    # the record has.
    if [ "$CORE_PUSHED_SET" = 1 ]; then
        [[ $CORE_PUSHED_HEAD =~ ^([0-9a-f]{40})?$ ]] || { echo "$PROG: refused: a pushed head is 40 hex, or empty to clear it" >&2; exit 65; }
        jq -e --arg t "$CORE_PUSHED_TOPIC" 'any(.holdings[]; .worker == $t)' "$T/parsed.json" > /dev/null \
            || { echo "$PROG: refused: no holding's Worker is $CORE_PUSHED_TOPIC" >&2; exit 65; }
    fi
    if [ "$SESSION_SEED" = 1 ]; then
        BASE=$(jq -r '.written // ""' "$T/parsed.json")
        URL=${RS_SESSION:-$SESSION}
    else
        core_live
    fi

    # A public host never names a private repository: not in a Holdings Repo,
    # not in a Pull request link, not in a hold's or a pause's On or Until, not in a Side
    # effects Target (an owner/repo token, owner/repo#n, or a github.com URL),
    # and not in any other string of the state. A named repository the host can't read
    # (404) can't be shown public, so it is refused too. This finds the
    # repositories the state names and reads each one's visibility; the checks
    # below refuse a value naming any on the list (state-schema.jq's names_repo, the one
    # test of whether a cell names a repository, and scan_strings over every string).
    PRIVATE=
    HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"
    if [ "$HOST_PRIVATE" = false ]; then
        # A cell that holds only a repository (Side effects Target) is read for
        # any owner/repo token. Decisions text is prose, where "and/or" or
        # "CI/CD" is not a repository, so only its unambiguous forms count
        # there, as state-schema.jq's text_named_repos reads them for a record entry
        # too: a github.com/<owner>/<repo> link and <owner>/<repo>#<n>.
        jq -r -L "$HERE" 'include "state-schema";
            def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
            def links: scan("github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)") | .[0] | clean;
            [ (.holdings[] | .repo, (.pull_request | pr_link_parts | .r)),
              ((.holds // [])[] | (.on | sub("#.*$"; "")),
                (.until | split(" ") | if .[0] == "merged" then (.[1] | sub("#.*$"; "")) elif .[0] == "tag" then .[1] else empty end)),
              ((.standing // [])[] | ((.on // "") | select(test("/")) | if startswith("release ") then split(" ")[1] else sub("#.*$"; "") end),
                ((.until // "") | split(" ") | if .[0] == "merged" then (.[1] | sub("#.*$"; "")) elif .[0] == "tag" then .[1] else empty end)),
              ((.side_effects[] | (.target // "")) | tostring
                | ( links,
                    (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
                     | scan("(?:^|[\\s(\\[<,;:])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?=#[0-9]|[\\s)\\]>,;:]|$)") | .[0] | clean) )),
              (((.decisions.entries // [])[] | .[d_text_cols[]] // "") | tostring | text_named_repos[]),
              (. as $rec | state_secs[] | .key as $k | (($rec[$k] // [])[] | .[s_text_cols[$k][]] // "") | text_named_repos[]),
              (.. | strings | text_named_repos[]) ]
            | map(select(. != "")) | unique | .[]' "$T/parsed.json" > "$T/named" || lib_die2 "jq failed"
        while IFS= read -r r; do
            [[ $r =~ $RE_REPO ]] || { echo "$PROG: refused: $r is not owner/repo" >&2; exit 65; }
            [ "$r" = "$REPO" ] && continue
            if ! P=$(gh api --method GET "repos/$r" --jq .private 2> "$T/v.err" < /dev/null); then
                grep -q 'HTTP 404' "$T/v.err" || lib_die2 "cannot read $r's visibility"
                P=unreadable
            fi
            [ "$P" = false ] || PRIVATE="$PRIVATE${PRIVATE:+,}$r"
        done < "$T/named"
    fi

    # The named repositories the host can't show public are refused now, the
    # one rule the first check couldn't run.
    [ -z "$PRIVATE" ] || core_validate "$T/parsed.json" "$T/checked.json"
    # The state is always written with this script's own written time: the
    # time the coordinator's state carries is never trusted, because
    # state-confirm.sh reads it as proof a write came after an event. Once the
    # run has entered dispatch, deferrals already filed or closed are dropped
    # first.
    cp "$T/parsed.json" "$T/next.json"
    if lib_dispatched && lib_drop_disposed "$T/parsed.json" "$T/dropped.json"; then
        mv "$T/dropped.json" "$T/next.json"
    fi
    jq --arg w "$(lib_now)" '.written = $w' "$T/next.json" > "$T/next-state.json" || lib_die2 "jq failed"
    # A step's shared read (state-read.sh rs_once_begin) is the record as it
    # was before this write: forget it, so a read after the write is live. It
    # is forgotten again once the write lands, since a reader running beside
    # this one (the pass's settle and legs) may have read in between.
    rs_once_drop
    core_write_session "$T/next-state.json"
    rs_once_drop
    printf '%s\n' "$URL"
}
