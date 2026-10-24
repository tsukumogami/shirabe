# state-read.sh -- the one reader of a coordinator record's state. A library:
# `. "$HERE/state-read.sh"` after state-common.sh (it needs the facts
# lib_facts sets). Run as a script, it also prints one read (see Usage).
#
# Every script that needs the record's state reads it here. The record lives in
# the coordinator's own koto session, one key per section (record/holdings,
# record/deferrals, record/side-effects, record/reversals, record/decisions,
# record/holds, record/run, record/standing, record/work; a section the record
# doesn't hold has no key), with record/meta naming its scope and written time;
# a discipline rotation also keeps its window and reasoning in record/rotation
# and record/reasoning. The record is assembled from those keys and handed out
# as state-schema.jq's normalize_state gives it, so every caller gets the same
# JSON from one state. record/meta is read before and after the sections, and
# the read is taken again, up to three times, while a write is part way through
# (meta marked pending, or the two meta reads differing). The session read is
# the run's (SESSION), or RS_SESSION when a caller names another, as the tests
# do with the override flags.
#
#   rs_record <out>
#       The run's record. Writes <out> (the record, normalize_state's JSON),
#       <out>.state (the keys as assembled, pushed heads included),
#       <out>.pushed (the pushed heads, {worker topic: sha}) and <out>.err (the
#       read's stderr, or the rule the state breaks).
#       Returns 0 read; 2 the read failed; 4 the session holds no record/meta
#       (session-absent, the reason in <out>.err); 12 the session record was
#       still being written after three re-reads (record-changed); 65 the
#       session's record is another scope's or breaks a rule of
#       state-schema.jq.
#   rs_record_api <out> [<session>]
#       The record of <session> ($SESSION when not given), its scope, name and
#       host from that run's facts (coord-log.sh run-facts), for the land check
#       and the merge, which name the session they read. Writes <out> and its
#       side files, for the caller's own scratch directory to clean up.
#       Returns 0 read; 2 the read failed or the record breaks a rule.
#   rs_facts <parsed-record> <topic>
#       Prints one holding's facts, from a record rs_record or rs_record_api
#       parsed: {topic, unit, repo, pull_request, number, branch, verified_head,
#       phase, dispatch_status, return_path, holds, pauses}. holds are the Holds
#       rows on the holding's pull request; pauses the Standing pause and
#       go-ahead rows pause-read.sh reads. It adds pushed_head when the holding
#       keeps one. Returns 0 printed; 1 no holding has that topic; 2 the record
#       couldn't be read.
#   rs_once_begin <dir>
#       One record read per step (shirabe#1094, #1095). Creates <dir> and
#       exports RS_ONCE=<dir>. From then on rs_record, in this process and in
#       every script it runs (they inherit RS_ONCE), answers from one read of
#       the run's record: the first rs_record assembles the record's keys into
#       <dir>, and the rest take their files from there. A read of another record (another session, scope or
#       name) is made live, as without RS_ONCE, and a read that fails is never
#       kept. Returns 2 when <dir> can't be made.
#
#       What this bounds is the number of reads a step makes, not the cost of
#       one. An assembly is still one koto call per key and one listing (koto
#       has no multi-key get), and the reconcile deadlines stay 8 and 12
#       seconds rather than growing with the record. On koto's cloud backend
#       each call is a bucket round trip of 0.3 to 1 s, so there the calls are
#       the cost, and a step that reads the record more than once can pass a
#       30-second action limit (shirabe#1156). A deadline that grew with the
#       record would instead let a slow read hide a hung one.
#   rs_once_drop
#       Forgets the step's read, so the next read is live. state-write-core.sh
#       calls it before it writes and again once the write lands, so nothing in
#       the step reads the record as it was before the step's own write, not
#       even a reader running beside the writer; a read still out when the
#       write came, a timed-out read's surviving child among them, lands where
#       no later read looks. Without RS_ONCE it does nothing.
#
# Usage (as a script):
#   state-read.sh --session S --facts <topic>
#   state-read.sh --session S --host
#   state-read.sh --candidate --scope roadmap|discipline --name N --hash H [--today YYYY-MM-DD]
#                    (the opener, before any session of its own: rs_resume_candidate)
#   state-read.sh --scope roadmap|discipline --name N --repo O/R --facts <topic>
#                    (tests: RS_SESSION names the session holding the record)
#
# A person reads the state through koto's own view of the session (`koto
# context get` on its record/ keys); --host prints record/host, the object
# rs_host reads.
#
# Exit codes (as a script): 0 printed; 1 no holding has that topic; 2 a read
# failed; 4 the session holds no record/meta; 12 the session record was still
# being written; 64 usage.
#
# Requires: bash 3.2+, jq, koto, and state-common.sh, state-schema.jq,
# coord-log.sh and pause-read.sh beside this file.

RS_LOADED=1
# The session store's section keys, as `<state field>:<key under record/>`
# pairs (docs/designs/DESIGN-coordinator-session-record.md, Decision 3).
# A section the record doesn't hold has no key.
RS_SECTIONS="holdings:holdings deferrals:deferrals side_effects:side-effects reversals:reversals decisions:decisions holds:holds run:run standing:standing work:work"
# How long a reader waits before re-reading a session record a write is part way
# through, in seconds; tests set 0.
RS_RETRY_PAUSE=${RS_RETRY_PAUSE:-1}

# rs_list <session> <prefix> <file>: the session's keys under <prefix>, koto's
# JSON array, into <file>. Returns 0 listed; 2 the listing failed or isn't an
# array (koto's reason appended to <file>.err). Presence is read from a listing,
# never from `context exists`: on koto's cloud backend an exists of a missing key
# retries its 404 for about a second, and a record has several absent sections.
rs_list() {
    local k=${KOTO:-${KOTO_BIN:-koto}}
    "$k" context list "$1" --prefix "$2" < /dev/null > "$3" 2>> "$3.err" || return 2
    jq -e 'type == "array"' "$3" > /dev/null 2>> "$3.err" || return 2
}

# rs_key <session> <key> <file>: a key's content into <file>. Returns 0 read; 1
# the key is absent; 2 a read failed (koto's reason appended to <file>.err).
rs_key() {
    local k=${KOTO:-${KOTO_BIN:-koto}}
    : > "$3.keys.err"
    rs_list "$1" "$2" "$3.keys" || { cat "$3.keys.err" >> "$3.err"; return 2; }
    jq -e --arg key "$2" 'index($key) != null' "$3.keys" > /dev/null || return 1
    "$k" context get "$1" "$2" < /dev/null > "$3" 2>> "$3.err" || return 2
}

# rs_assemble <meta-file> <section-dir>: the record as the state's JSON,
# the scope and written time from meta and one field per section file present.
rs_assemble() {
    local m=$1 d=$2 pair field
    jq '{scope: .scope, written: .written}' "$m" > "$d/.acc" || return 1
    for pair in $RS_SECTIONS; do
        field=${pair%%:*}
        [ -f "$d/$field" ] || continue
        jq --arg f "$field" --slurpfile v "$d/$field" '. + {($f): $v[0]}' "$d/.acc" > "$d/.next" || return 1
        mv "$d/.next" "$d/.acc"
    done
    cat "$d/.acc"
}

# rs_session_state <session> <out>: the session's record, assembled from its
# keys into <out> as the state's JSON, with `written` from record/meta.
# record/meta is read before and after the section keys, and the whole read is
# taken again, up to three times, while meta is marked pending or the two meta
# reads differ: a write changes its sections between two meta writes. Returns 0
# assembled; 2 a read failed or a key isn't JSON; 4 the session holds no
# record/meta (session-absent), the reason in <out>.err; 12 the record was still
# being written after three re-reads.
rs_session_state() {
    local s=$1 out=$2 try pair field key changed k=${KOTO:-${KOTO_BIN:-koto}}
    : > "$out.err"
    for try in 0 1 2 3; do
        [ "$try" -eq 0 ] || sleep "$RS_RETRY_PAUSE"
        # record/meta is got directly; only a get that fails lists the key, to
        # tell a session with no record (absent) from a failed read. A record
        # that is there costs one koto call here, not two. A first get that
        # failed and a fallback that then reads the key is a read, and the
        # first get's error is dropped with it.
        if ! "$k" context get "$s" record/meta < /dev/null > "$out.m1" 2> "$out.m1.err"; then
            rs_key "$s" record/meta "$out.m1"
            case $? in
                0) ;;
                1) echo "${PROG:-record-source}: session-absent: session $s holds no record/meta; the record's state isn't on this host" >> "$out.err"; return 4 ;;
                *) cat "$out.m1.err" >> "$out.err"; return 2 ;;
            esac
        fi
        jq -e 'type == "object" and (.written | type) == "string"' "$out.m1" > /dev/null 2>> "$out.err" || return 2
        [ "$(jq -r '.pending // false' "$out.m1")" = true ] && continue
        # One listing names the sections present; only those are read.
        rs_list "$s" record/ "$out.keys" || { cat "$out.keys.err" >> "$out.err"; return 2; }
        rm -rf "$out.sec"; mkdir -p "$out.sec" || return 2
        changed=0
        for pair in $RS_SECTIONS; do
            field=${pair%%:*} key=${pair#*:}
            jq -e --arg key "record/$key" 'index($key) != null' "$out.keys" > /dev/null || continue
            if ! "$k" context get "$s" "record/$key" < /dev/null > "$out.sec/$field" 2>> "$out.err"; then
                # Listed but gone: a write removed it since the listing, which
                # moves record/meta; that is a re-read, not a failed read.
                "$k" context get "$s" record/meta < /dev/null > "$out.m2" 2>> "$out.err" || return 2
                [ "$(jq -cS . "$out.m1")" = "$(jq -cS . "$out.m2")" ] && return 2
                changed=1; break
            fi
            jq -e . "$out.sec/$field" > /dev/null 2>> "$out.err" || return 2
        done
        [ "$changed" = 1 ] && continue
        "$k" context get "$s" record/meta < /dev/null > "$out.m2" 2>> "$out.err" || return 2
        [ "$(jq -cS . "$out.m1")" = "$(jq -cS . "$out.m2")" ] || continue
        rs_assemble "$out.m1" "$out.sec" > "$out" 2>> "$out.err" || return 2
        return 0
    done
    echo "${PROG:-record-source}: record-changed: session $s's record was still being written after three re-reads" >> "$out.err"
    return 12
}

# rs_session_read <out> <session> <scope> <name>: the files rs_record writes:
# <out> the record as state-schema.jq's normalize_state gives it, <out>.state
# the keys as assembled (pushed heads included) and <out>.pushed the pushed
# heads, {worker topic: sha}. normalize_state is what gives every reader the
# same JSON for one state (PRD R19). Returns rs_session_state's codes; 65
# record/meta names another scope, or the state breaks a rule of
# state-schema.jq (the reason in <out>.err).
rs_session_read() {
    local out=$1 s=$2 scope=$3 name=$4 rc
    : > "$out.err"
    [ -n "$s" ] || { echo "${PROG:-record-source}: the session store needs the run's session" >> "$out.err"; return 2; }
    rs_session_state "$s" "$out.state"; rc=$?
    cat "$out.state.err" >> "$out.err"
    [ $rc -eq 0 ] || return $rc
    if [ "$(jq -c '.scope' "$out.state")" != "$(jq -nc --arg k "$scope" --arg n "$name" '{kind: $k, name: $n}')" ]; then
        echo "${PROG:-record-source}: session $s's record/meta is for another scope than $scope:$name" >> "$out.err"
        return 65
    fi
    # A holding's last pushed head (PRD R17) is kept beside its row: 40 hex or
    # empty, never rendered. It is read into <out>.pushed, {worker topic: sha}.
    if ! jq -e '[(.holdings // [])[] | (.pushed_head // "")] | all(type == "string" and test("^([0-9a-f]{40})?$"))' "$out.state" > /dev/null 2>> "$out.err"; then
        echo "${PROG:-record-source}: session $s's record/holdings holds a pushed_head that isn't 40 hex" >> "$out.err"
        return 65
    fi
    jq '[(.holdings // [])[] | select((.pushed_head // "") != "") | {(.worker): .pushed_head}] | add // {}' "$out.state" > "$out.pushed" || return 2
    if ! jq -L "$HERE" 'include "state-schema";
            if has("holdings") then .holdings |= map(del(.pushed_head)) else . end | normalize_state([])' \
            "$out.state" > "$out" 2> "$out.check"; then
        grep -q 'refused: ' "$out.check" || { cat "$out.check" >> "$out.err"; return 2; }
        echo "${PROG:-record-source}: session $s's record doesn't read back: $(sed -n 's/.*refused: //p' "$out.check" | head -1)" >> "$out.err"
        return 65
    fi
}

# rs_scope_sessions <scope> <name>: this host's coordinator sessions of the
# scope, coordinate-<slug>-<stamp> (the slug coord-log.sh slug derives, as
# coordinate-open.sh names them), that hold record/meta, one name per line,
# oldest stamp first. A child session is never one: a coordinator run is a root.
# Returns 2 when the session list can't be read.
rs_scope_sessions() {
    local d s slug
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$1" --name "$2") || return 2
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX") || return 2
    "${KOTO:-${KOTO_BIN:-koto}}" session list < /dev/null > "$d/list" 2> "$d/err" || { rm -rf "$d"; return 2; }
    jq -r --arg p "coordinate-$slug-" '.[] | select(.parent_workflow == null) | .id
        | select(startswith($p) and (ltrimstr($p) | test("^[0-9]{8}T[0-9]{6}Z$")))' "$d/list" \
        2> "$d/err" | LC_ALL=C sort > "$d/names" || { rm -rf "$d"; return 2; }
    while IFS= read -r s; do
        rs_list "$s" record/meta "$d/keys" || continue
        jq -e 'index("record/meta") != null' "$d/keys" > /dev/null && printf '%s\n' "$s"
    done < "$d/names"
    rm -rf "$d"
}

# rs_resume_candidate <scope> <name> <shipped-hash>: what a start on this host
# does with the scope's sessions that hold a record (PRD R12; Decision 6). It
# looks at the newest by stamp of rs_scope_sessions (named
# coordinate-<slug>-<stamp>, a root session, holding record/meta) and prints
# {session, action, live, reason}:
#   resume  it is live and the scope's only live run, koto compiled it from the
#           shipped template's hash, it passes provenance, its find recorded the
#           session store (coord/source.json), and it has no directed
#           transition: the start keeps it, opening and cancelling nothing
#   carry   it holds a record but fails one of the run checks
#           (finished, cancelled, another template hash, provenance, a directed
#           transition, another live run): the start opens a new run and copies
#           its record/ and legs/ keys into it through the write core
#   none    no session here holds a record, or the newest's find never
#           recorded the session (no coord/source.json reading session): the
#           start opens a new run
# At discipline scope the window rule comes first
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3): the
# newest rotation is resumed or carried only while it is open (rs_rotation_open,
# against <today>); one that has ended, by date or by closing, is `none`, so the
# start opens the next rotation as a new run and its find carries the
# predecessor. There is never a second open rotation of a discipline on a host.
# live is whether that session is a live run, which the opener cancels on a
# carry. Returns 0 printed; 2 a read failed.
rs_resume_candidate() {
    local scope=$1 name=$2 hash=$3 today=${4:-$(date -u +%Y-%m-%d)} holders s slug live d src reason=
    holders=$(rs_scope_sessions "$scope" "$name") || return 2
    s=$(printf '%s\n' "$holders" | grep -v '^$' | tail -1)
    if [ -z "$s" ]; then
        jq -nc '{session: null, action: "none", live: false, reason: "no session here holds a record"}'
        return 0
    fi
    if [ "$scope" = discipline ]; then
        rs_rotation_open "$s" "$today"
        case $? in
            0) ;;
            1) jq -nc --arg s "$s" '{session: $s, action: "none", live: false, reason: "its rotation has ended: a start opens the next rotation"}'
               return 0 ;;
            3) jq -nc --arg s "$s" '{session: $s, action: "none", live: false, reason: "it holds no rotation window"}'
               return 0 ;;
            *) return 2 ;;
        esac
    fi
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$scope" --name "$name") || return 2
    live=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$slug" --all 2>/dev/null)
    case $? in 0|1) ;; *) return 2 ;; esac
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX") || return 2
    rs_key "$s" coord/source.json "$d/src"
    case $? in
        0) src=$(jq -r '.source // ""' "$d/src" 2>/dev/null) ;;
        1) src= ;;
        *) rm -rf "$d"; return 2 ;;
    esac
    rm -rf "$d"
    if [ "$src" != session ]; then
        jq -nc --arg s "$s" '{session: $s, action: "none", live: false, reason: "its store isn'"'"'t session"}'
        return 0
    fi
    if ! grep -qxF -- "$s" <<< "$live"; then reason="it is finished or cancelled"
    elif [ "$(printf '%s\n' "$live" | grep -c .)" -gt 1 ]; then reason="another run of the scope is live"
    elif [ "$("$HERE/coord-log.sh" template-hash --session "$s" 2>/dev/null)" != "$hash" ]; then reason="koto compiled it from another template"
    elif ! bash "$HERE/coord-log.sh" provenance --session "$s" > /dev/null 2>&1; then reason="it fails provenance"
    else
        bash "$HERE/coord-log.sh" directed-since --session "$s" --from 0 > /dev/null 2>&1
        case $? in 0) ;; 1) reason="it has a directed transition" ;; *) return 2 ;; esac
    fi
    jq -nc --arg s "$s" --arg r "$reason" --argjson l "$(grep -qxF -- "$s" <<< "$live" && echo true || echo false)" \
        '{session: $s, action: (if $r == "" then "resume" else "carry" end), live: $l, reason: (if $r == "" then "the live run" else $r end)}'
}

# rs_host <session> <out>: the host facts a record keeps in record/host, as a
# JSON object into <out>: where its state came from on an import
# (source_workspace, source_session, template_hash) and where its crash set's
# files live (rules:<label>, briefs:<label>, friction). They describe this
# host, so they never leave it and never join the state. {} when the
# session holds none. Returns 0; 2 a read failed or the key isn't an object.
rs_host() {
    rs_key "$1" record/host "$2"
    case $? in
        0) jq -e 'type == "object"' "$2" > /dev/null 2>> "$2.err" || return 2 ;;
        1) echo '{}' > "$2" ;;
        *) return 2 ;;
    esac
}

# rs_rotation <session> <out>: a discipline rotation's window,
# record/rotation, {start, end, host_repo, predecessor}, into <out>.
# Returns 0 read; 1 the session holds none; 2 a read failed or it isn't an
# object with the three dates and host as strings.
rs_rotation() {
    rs_key "$1" record/rotation "$2"
    case $? in
        0) jq -e 'type == "object" and (.start | type) == "string" and (.end | type) == "string"
                  and (.host_repo | type) == "string"' "$2" > /dev/null 2>> "$2.err" || return 2 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

# rs_reasoning <session> <out>: the reasoning a rotation left for the next one,
# record/reasoning, a JSON string, into <out> as that string's JSON. Returns 0
# read; 1 the session holds none; 2 a read failed or it isn't a string.
rs_reasoning() {
    rs_key "$1" record/reasoning "$2"
    case $? in
        0) jq -e 'type == "string"' "$2" > /dev/null 2>> "$2.err" || return 2 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

# rs_rotation_open <session> <today>: the window rule
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3). A
# rotation is open while <today> (a UTC date, the time of the start) is on or
# before its record/rotation end and it holds no record/reasoning, which closing
# a rotation writes. Returns 0 open; 1 ended; 3 the session holds no
# record/rotation; 2 a read failed.
rs_rotation_open() {
    local d rc end
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX") || return 2
    rs_rotation "$1" "$d/rot"; rc=$?
    case $rc in 0) ;; 1) rm -rf "$d"; return 3 ;; *) rm -rf "$d"; return 2 ;; esac
    end=$(jq -r '.end' "$d/rot")
    rs_key "$1" record/reasoning "$d/reason"; rc=$?
    rm -rf "$d"
    case $rc in
        0) return 1 ;;
        1) ;;
        *) return 2 ;;
    esac
    [ "$2" \> "$end" ] && return 1
    return 0
}

# ---- one read per step (rs_once_begin, rs_once_drop) -------------------------
# The step's read lives in $RS_ONCE/read.<n>, where n ($RS_ONCE/gen, 0 when
# absent) counts the step's writes: key (which record it is) and the files
# rs_session_read writes for a json read (s, s.err, s.md, s.raw, s.pushed).
#
# A write moves n on before it removes the old read. A deadline stops a read's
# process but not always its children, so a read the step gave up on can land
# after a write: it lands under the n it started at, which no reader looks at
# any more, and the step never takes the record from before its own write.

rs_once_begin() {
    mkdir -p "$1" || return 2
    RS_ONCE=$(cd "$1" && pwd) || return 2
    export RS_ONCE
}

# rs_once_gen: the step's write count, n.
rs_once_gen() {
    local g
    g=$(cat "$RS_ONCE/gen" 2> /dev/null) || g=0
    [[ $g =~ ^[0-9]+$ ]] || g=0
    printf '%s\n' "$g"
}

rs_once_drop() {
    local g t
    [ -n "${RS_ONCE:-}" ] && [ -d "$RS_ONCE" ] || return 0
    g=$(rs_once_gen)
    t=$(mktemp "$RS_ONCE/gen.XXXXXX") || { rm -rf "$RS_ONCE"/read.*; return 0; }
    echo $((g + 1)) > "$t" && mv "$t" "$RS_ONCE/gen" || rm -f "$t"
    rm -rf "$RS_ONCE/read.$g"
    return 0
}

# rs_once_record <out>: rs_record from the step's read, made now unless it is
# already there. Returns rs_record's codes, or 99 when the step wrote while it
# read, or the read held is another record's, and the caller reads live.
rs_once_record() {
    local out=$1 s=${RS_SESSION:-${SESSION:-}} key g r d rc
    key="$SCOPE $NAME $s"
    g=$(rs_once_gen)
    r=$RS_ONCE/read.$g
    if [ ! -f "$r/key" ]; then
        d=$(mktemp -d "$RS_ONCE/fill.XXXXXX") || return 99
        rs_session_read "$d/s" "$s" "$SCOPE" "$NAME"; rc=$?
        if [ $rc -ne 0 ]; then
            cp "$d/s.err" "$out.err" 2> /dev/null || : > "$out.err"
            rm -rf "$d"
            return $rc
        fi
        printf '%s\n' "$key" > "$d/key"
        # Two readers of one step may fill at once: the first to arrive is
        # kept, and a later one finds it there (its own copy lands inside, unread).
        [ -d "$r" ] || mv "$d" "$r" 2> /dev/null
        rm -rf "$d"
        [ "$(rs_once_gen)" = "$g" ] || return 99
    fi
    [ -f "$r/key" ] && [ "$(cat "$r/key")" = "$key" ] || return 99
    cp "$r/s" "$out" && cp "$r/s.err" "$out.err" && cp "$r/s.state" "$out.state" && cp "$r/s.pushed" "$out.pushed" || return 99
}

# rs_record <out>
rs_record() {
    local out=$1 rc
    # The step's one read (rs_once_begin).
    if [ -n "${RS_ONCE:-}" ]; then
        rs_once_record "$out"; rc=$?
        [ $rc -eq 99 ] || return $rc
    fi
    rs_session_read "$out" "${RS_SESSION:-${SESSION:-}}" "$SCOPE" "$NAME"
}

# rs_record_api <out> [<session>]: the record of a run named by its session.
rs_record_api() {
    local out=$1 facts rrepo scope name rc
    local SESSION=${2:-${SESSION:-}}
    facts=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION") || return 2
    rrepo=$(printf '%s' "$facts" | jq -r '.repo // ""')
    scope=$(printf '%s' "$facts" | jq -r '.scope // ""')
    name=$(printf '%s' "$facts" | jq -r '.name // ""')
    case "$scope" in roadmap|discipline) ;; *) return 2 ;; esac
    [[ $rrepo =~ $RE_REPO ]] || return 2
    rs_session_read "$out" "$SESSION" "$scope" "$name"; rc=$?
    cat "$out.err" >&2
    [ $rc -eq 0 ] || return 2
}

# rs_facts <parsed-record> <topic>
rs_facts() {
    local f=$1 topic=$2 row unit d
    jq -e --arg t "$topic" 'any(.holdings[]?; .worker == $t)' "$f" > /dev/null 2>&1 || {
        jq -e . "$f" > /dev/null 2>&1 || return 2
        return 1
    }
    row=$(jq -c --arg t "$topic" '[.holdings[] | select(.worker == $t)][0]' "$f") || return 2
    unit=$(printf '%s' "$row" | jq -r '.unit')
    d=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX") || return 2
    jq '{standing: (.standing // [])}' "$f" > "$d/standing" || { rm -rf "$d"; return 2; }
    jq -nc --arg u "$unit" '[$u]' > "$d/units"
    if ! bash "$HERE/pause-read.sh" --standing "$d/standing" --units "$d/units" > "$d/pauses" 2> /dev/null; then
        rm -rf "$d"; return 2
    fi
    # The holding's pushed head, kept beside the row (rs_session_read's
    # <parsed>.pushed): present only when one is kept.
    if [ -s "$f.pushed" ]; then cp "$f.pushed" "$d/pushed"; else echo '{}' > "$d/pushed"; fi
    jq -c --argjson row "$row" --slurpfile p "$d/pauses" --slurpfile h "$d/pushed" '
        ($row.pull_request | capture("^\\[#(?<n>[0-9]+)\\]\\(https://github\\.com/(?<r>[^/]+/[^/]+)/pull/[0-9]+\\)$") // {n: "", r: ""}) as $pr
        | (if $pr.r == "" then "" else ($pr.r + "#" + $pr.n) end) as $on
        | {topic: $row.worker, unit: $row.unit, repo: $row.repo, pull_request: $row.pull_request,
           number: $pr.n, branch: $row.branch, verified_head: $row.verified_head, phase: $row.phase,
           dispatch_status: $row.dispatch_status, return_path: $row.return_path,
           holds: (if $on == "" then [] else [(.holds // [])[] | select((.on | ascii_downcase) == ($on | ascii_downcase))] end),
           pauses: {rows: [(.standing // [])[] | select(.kind == "pause" or .kind == "go-ahead")],
                    read: $p[0], paused: ($p[0].covers[$row.unit] // $p[0].all // null)}}
        | if $h[0][$row.worker] then . + {pushed_head: $h[0][$row.worker]} else . end' "$f"
    local rc=$?
    rm -rf "$d"
    [ $rc -eq 0 ] || return 2
}

# ---- run as a script --------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    PROG=state-read
    HERE=$(cd "$(dirname "$0")" && pwd)
    SESSION= SCOPE= NAME= REPO= ACTION= TOPIC= HASH= TODAY=
    rs_usage() { sed -n '/^# Usage (as a script):/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
    while [ $# -gt 0 ]; do
        case "$1" in
            --session) [ $# -ge 2 ] || rs_usage; SESSION=$2; shift 2 ;;
            --scope) [ $# -ge 2 ] || rs_usage; SCOPE=$2; shift 2 ;;
            --name) [ $# -ge 2 ] || rs_usage; NAME=$2; shift 2 ;;
            --repo) [ $# -ge 2 ] || rs_usage; REPO=$2; shift 2 ;;
            --host) ACTION=host; shift ;;
            --candidate) ACTION=candidate; shift ;;
            --hash) [ $# -ge 2 ] || rs_usage; HASH=$2; shift 2 ;;
            --today) [ $# -ge 2 ] || rs_usage; TODAY=$2; shift 2 ;;
            --facts) [ $# -ge 2 ] || rs_usage; ACTION=facts; TOPIC=$2; shift 2 ;;
            *) rs_usage ;;
        esac
    done
    [ -n "$ACTION" ] || rs_usage
    . "$HERE/state-common.sh"
    case "$ACTION" in
        candidate)
            # Before any session exists: the scope and name, and the shipped
            # template's hash, come from the opener.
            [[ $SCOPE =~ ^(roadmap|discipline)$ ]] && [[ $NAME =~ $RE_NAME ]] && [[ $HASH =~ ^[0-9a-f]{64}$ ]] || rs_usage
            [ -z "$TODAY" ] || lib_valid_date "$TODAY" || rs_usage
            rs_resume_candidate "$SCOPE" "$NAME" "$HASH" "$TODAY"; exit $? ;;
    esac
    lib_facts
    case "$ACTION" in
        host)
            RS_T=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX")
            trap 'rm -rf "$RS_T"' EXIT
            rs_host "${RS_SESSION:-$SESSION}" "$RS_T/host" \
                || { echo "$PROG: record/host couldn't be read: $(lib_scrub < "$RS_T/host.err" | head -3)" >&2; exit 2; }
            jq -c . "$RS_T/host"
            exit 0 ;;
    esac
    [ "$ACTION" != facts ] || [[ $TOPIC =~ $RE_TOPIC ]] || { echo "$PROG: the topic is not a dispatch topic" >&2; exit 64; }
    lib_run_found || { echo "$PROG: the run has no record yet" >&2; exit 2; }
    RS_T=$(mktemp -d "${TMPDIR:-/tmp}/state-read.XXXXXX")
    trap 'rm -rf "$RS_T"' EXIT
    rs_record "$RS_T/rec"
    case $? in
        0) ;;
        4) lib_scrub < "$RS_T/rec.err" >&2; exit 4 ;;
        12) lib_scrub < "$RS_T/rec.err" >&2; exit 12 ;;
        *) echo "$PROG: the record couldn't be read: $(lib_scrub < "$RS_T/rec.err" | head -3)" >&2; exit 2 ;;
    esac
    rs_facts "$RS_T/rec" "$TOPIC"
    exit $?
fi
