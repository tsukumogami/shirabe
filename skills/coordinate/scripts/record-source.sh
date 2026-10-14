# record-source.sh -- the one reader of a coordinator record's state. A library:
# `. "$HERE/record-source.sh"` after record-common.sh (it needs lib_parse and the
# facts lib_facts sets). Run as a script, it also prints one read (see Usage).
#
# Every script that needs the record's state reads it here, whichever store the
# run is on (docs/designs/DESIGN-coordinator-session-record.md, Decision 1). A
# record's store is `github` (the issue or pull request body) or `session` (one
# key per section in the coordinator's own koto session, roadmap scope only).
#
# On the GitHub store each read keeps its caller's own call shape, because what
# a caller reads beside the body (the container's state, its title, its head
# branch) is GitHub's and stays its own. On the session store the record is
# assembled from record/meta and one key per section (record/holdings,
# record/deferrals, record/side-effects, record/reversals, record/decisions,
# record/holds, record/run, record/standing, record/work; a section the record
# doesn't hold has no key), rendered at record/meta's written time and parsed
# back, so a caller gets the same files, and the same JSON, as from a GitHub
# record holding the same state. record/meta is read before and after the
# sections, and the read is taken again, up to three times, while a write is
# part way through (meta marked pending, or the two meta reads differing).
#
#   rs_record <out> <mode> <gh view args...>
#       GitHub: runs `gh issue view <REF> --repo <REPO> <args>` at roadmap scope
#       and `gh pr view <REF> --repo <REPO> <args>` at discipline scope, exactly
#       as given, with stdin from /dev/null. <mode> says what the args print:
#       `body` (the body text, e.g. `--json body --jq .body`) or `json` (a JSON
#       object with .body, e.g. `--json state,body`). Session: <out>.raw is what
#       the same `gh issue view` would print, the body for `body` and {state:
#       "OPEN", body, url} for `json`. Writes <out> (the parsed record,
#       record-parse.sh's JSON), <out>.raw, <out>.md (the body) and <out>.err
#       (the read's stderr, or the parser's refusal).
#       Returns 0 parsed; 2 the read failed; 3 or 65 the body isn't a canonical
#       record of this scope (record-parse.sh's codes); 4 the session holds no
#       record/meta (session-absent, the reason in <out>.err); 5 the parser or
#       the renderer itself failed; 12 the session record was still being
#       written after three re-reads (record-changed).
#   rs_record_api <out> [<session>]
#       GitHub: the same record through `gh api --method GET
#       repos/<repo>/issues/<ref>`, read with board-lib.sh's bl_gh (its retry and
#       deadline) when the caller sourced board-lib.sh; session: the session
#       read. The repository, number and scope come from the run's facts
#       (coord-log.sh run-facts) of <session>, $SESSION when not given. Writes
#       <out>, <out>.md and, on GitHub, the raw response <out>.rec (with bl_gh's
#       <out>.rec.err and <out>.rec.fail, or gh's <out>.rec.err), all beside
#       <out>, for the caller's own scratch directory to clean up.
#       Returns 0 parsed; 2 the read or the parse failed.
#   rs_view <container> <ref> <repo> <gh view args...>
#       Prints the container's fields as `gh <issue|pr> view <ref> --repo <repo>
#       <args>` prints them, the body among them, for the one reader that keeps
#       its own deadline and its row-by-row salvage of a body the codec refuses
#       (reconcile-read.sh, under rd_deadline). On the session store it prints
#       {state: "OPEN", body, url}. Returns gh's status, or the session read's.
#   rs_facts <parsed-record> <topic>
#       Prints one holding's facts, from a record rs_record or rs_record_api
#       parsed: {topic, unit, repo, pull_request, number, branch, verified_head,
#       phase, dispatch_status, return_path, holds, pauses}. holds are the Holds
#       rows on the holding's pull request; pauses the Standing pause and
#       go-ahead rows pause-read.sh reads. On the session store it adds
#       pushed_head when the holding keeps one. Returns 0 printed; 1 no holding
#       has that topic; 2 the record couldn't be read.
#   rs_source
#       Prints the run's store, `github` or `session`, as coord-log.sh run-store
#       reads it from the run's sealed RECORD_FIND token: `session` for
#       `found <n> session` or `move <n>`, `github` otherwise. It caches the
#       answer in RS_SOURCE_READ, for the session named in RS_SOURCE_FOR, and
#       the reads above use it. Under the test override flags it is `github`
#       unless RS_SOURCE names another.
#   rs_probe
#       Prints what this koto offers the session store, by feature:
#       {"context_list_prefix": bool, "session_import": bool}.
#
# Usage (as a script):
#   record-source.sh --session S --source
#   record-source.sh --session S --probe
#   record-source.sh --session S --facts <topic>
#   record-source.sh --session S --show
#   record-source.sh --session S --host
#   record-source.sh --candidate --scope roadmap|discipline --name N --hash H
#                    (the opener, before any session of its own: rs_resume_candidate)
#   record-source.sh --scope roadmap|discipline --name N --repo O/R --ref N --facts <topic>   (tests)
#
# --show prints the record as its body would read, from either store, so a
# reviewer on the coordinator's host reads a session-store record without
# knowing key names (PRD R11). record/host is never part of it; --host prints
# it, the object rs_host reads, and `{}` for a record on GitHub.
#
# Exit codes (as a script): 0 printed; 1 no holding has that topic; 2 a read
# failed; 4 the session holds no record/meta; 12 the session record was still
# being written; 64 usage.
#
# Requires: bash 3.2+, jq, gh, koto, and record-common.sh, record-parse.sh,
# record-render.sh, coord-log.sh and pause-read.sh beside this file.

RS_LOADED=1
# The session store's section keys, as `<record-parse.sh field>:<key under
# record/>` pairs (docs/designs/DESIGN-coordinator-session-record.md, Decision 3).
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

# rs_assemble <meta-file> <section-dir>: the record as record-parse.sh's JSON,
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
# keys into <out> as record-parse.sh's JSON, with `written` from record/meta.
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
        rs_key "$s" record/meta "$out.m1"
        case $? in
            0) ;;
            1) echo "${PROG:-record-source}: session-absent: session $s holds no record/meta; the record's state isn't on this host" >> "$out.err"; return 4 ;;
            *) return 2 ;;
        esac
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

# rs_source: the run's store.
rs_source() {
    if [ "${OVERRIDE:-0}" = 1 ] || [ -z "${SESSION:-}" ]; then
        case "${RS_SOURCE:-github}" in session) RS_SOURCE_READ=session ;; *) RS_SOURCE_READ=github ;; esac
        printf '%s\n' "$RS_SOURCE_READ"
        return 0
    fi
    if [ -z "${RS_SOURCE_READ:-}" ] || [ "${RS_SOURCE_FOR:-}" != "$SESSION" ]; then
        local s
        s=$(bash "$HERE/coord-log.sh" run-store --session "$SESSION" 2>/dev/null)
        case "$s" in session) RS_SOURCE_READ=session ;; *) RS_SOURCE_READ=github ;; esac
        RS_SOURCE_FOR=$SESSION
    fi
    printf '%s\n' "$RS_SOURCE_READ"
}

# rs_session_read <out> <body|json> <session> <scope> <name> <repo> <ref>: the
# files rs_record writes, from the session store: <out> the record as
# record-parse.sh parses it, <out>.md the body rendered at record/meta's written
# time, exactly as a GitHub record holding the same state reads, and <out>.raw
# what `gh issue view` would print for <mode> (body: the body; json: {state:
# "OPEN", body, url}, the url the GitHub record's). Parsing the rendered body
# back is what makes a session read and a GitHub read of the same state give the
# same JSON (PRD R19). Returns rs_session_state's codes; 65 record/meta names
# another scope; 3 or 65 the body doesn't parse back canonical; 5 the renderer
# or the parser failed.
rs_session_read() {
    local out=$1 mode=$2 s=$3 scope=$4 name=$5 repo=$6 ref=$7 rc w
    : > "$out.err"
    [ -n "$s" ] || { echo "${PROG:-record-source}: the session store needs the run's session" >> "$out.err"; return 2; }
    rs_session_state "$s" "$out.state"; rc=$?
    cat "$out.state.err" >> "$out.err"
    [ $rc -eq 0 ] || return $rc
    if [ "$(jq -c '.scope' "$out.state")" != "$(jq -nc --arg k "$scope" --arg n "$name" '{kind: $k, name: $n}')" ]; then
        echo "${PROG:-record-source}: session $s's record/meta is for another scope than $scope:$name" >> "$out.err"
        return 65
    fi
    # A holding's last pushed head (PRD R17) is kept beside its row on the
    # session store only: 40 hex or empty, never rendered, so a GitHub body
    # never carries it. It is read into <out>.pushed, {worker topic: sha}.
    if ! jq -e '[(.holdings // [])[] | (.pushed_head // "")] | all(type == "string" and test("^([0-9a-f]{40})?$"))' "$out.state" > /dev/null 2>> "$out.err"; then
        echo "${PROG:-record-source}: session $s's record/holdings holds a pushed_head that isn't 40 hex" >> "$out.err"
        return 65
    fi
    jq '[(.holdings // [])[] | select((.pushed_head // "") != "") | {(.worker): .pushed_head}] | add // {}' "$out.state" > "$out.pushed" || return 5
    w=$(jq -r '.written' "$out.state")
    jq 'del(.written) | if has("holdings") then .holdings |= map(del(.pushed_head)) else . end' "$out.state" \
        | bash "$HERE/record-render.sh" --container issue --written "$w" > "$out.md" 2>> "$out.err" || return 5
    if [ "$mode" = body ]; then
        cp "$out.md" "$out.raw"
    else
        jq -n --rawfile b "$out.md" --arg u "https://github.com/$repo/issues/$ref" '{state: "OPEN", body: $b, url: $u}' > "$out.raw" || return 5
    fi
    bash "$HERE/record-parse.sh" --container issue --expect-scope "$scope:$name" "$out.md" > "$out" 2> "$out.err"
    rc=$?
    case $rc in
        0|3|65) return $rc ;;
        *) return 5 ;;
    esac
}

# rs_probe: the koto features the session store needs, read by feature.
rs_probe() {
    local prefix=false import=false
    "$KOTO" context list --help < /dev/null 2>/dev/null | grep -q -- '--prefix' && prefix=true
    "$KOTO" session import --help < /dev/null > /dev/null 2>&1 && import=true
    jq -nc --argjson p "$prefix" --argjson i "$import" '{context_list_prefix: $p, session_import: $i}'
}

# rs_probe_missing: the session-store features this koto lacks, comma-separated,
# empty when it has both (PRD R2).
rs_probe_missing() {
    rs_probe | jq -r '[if .context_list_prefix then empty else "context list --prefix" end,
        if .session_import then empty else "session import" end] | join(", ")'
}

# rs_scope_sessions <scope> <name>: this host's coordinator sessions of the
# scope, coordinate-<slug>-<stamp> (the slug coord-log.sh slug derives, as
# coordinate-open.sh names them), that hold record/meta, one name per line,
# oldest stamp first. A child session is never one: a coordinator run is a root.
# Returns 2 when the session list can't be read.
rs_scope_sessions() {
    local d s slug
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$1" --name "$2") || return 2
    d=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX") || return 2
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
#   carry   it holds a session-store record but fails one of the run checks
#           (finished, cancelled, another template hash, provenance, a directed
#           transition, another live run): the start opens a new run and copies
#           its record/ and legs/ keys into it through the write core
#   none    no session here holds a record, or the newest's store isn't
#           session: the start opens a new run as on GitHub
# live is whether that session is a live run, which the opener cancels on a
# carry. Returns 0 printed; 2 a read failed.
rs_resume_candidate() {
    local scope=$1 name=$2 hash=$3 holders s slug live d src reason=
    holders=$(rs_scope_sessions "$scope" "$name") || return 2
    s=$(printf '%s\n' "$holders" | grep -v '^$' | tail -1)
    if [ -z "$s" ]; then
        jq -nc '{session: null, action: "none", live: false, reason: "no session here holds a record"}'
        return 0
    fi
    slug=$(bash "$HERE/coord-log.sh" slug --scope "$scope" --name "$name") || return 2
    live=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$slug" --all 2>/dev/null)
    case $? in 0|1) ;; *) return 2 ;; esac
    d=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX") || return 2
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
    elif [ "$(bash "$HERE/coord-log.sh" template-hash --session "$s" 2>/dev/null)" != "$hash" ]; then reason="koto compiled it from another template"
    elif ! bash "$HERE/coord-log.sh" provenance --session "$s" > /dev/null 2>&1; then reason="it fails provenance"
    else
        bash "$HERE/coord-log.sh" directed-since --session "$s" --from 0 > /dev/null 2>&1
        case $? in 0) ;; 1) reason="it has a directed transition" ;; *) return 2 ;; esac
    fi
    jq -nc --arg s "$s" --arg r "$reason" --argjson l "$(grep -qxF -- "$s" <<< "$live" && echo true || echo false)" \
        '{session: $s, action: (if $r == "" then "resume" else "carry" end), live: $l, reason: (if $r == "" then "the live run" else $r end)}'
}

# rs_host <session> <out>: the host facts a session-store record keeps in
# record/host, as a JSON object into <out>: where its state came from on an
# import (source_workspace, source_session, template_hash) and where its crash
# set's files live (rules:<label>, briefs:<label>, friction). They describe
# this host, so they never go to GitHub and --show never prints them. {} when
# the session holds none. Returns 0; 2 a read failed or the key isn't an
# object.
rs_host() {
    rs_key "$1" record/host "$2"
    case $? in
        0) jq -e 'type == "object"' "$2" > /dev/null 2>> "$2.err" || return 2 ;;
        1) echo '{}' > "$2" ;;
        *) return 2 ;;
    esac
}

# rs_moved <parsed-record>: 0 when the record is in the moved shape (PRD R8):
# every section empty and a Run section holding only the `store session` row.
rs_moved() {
    jq -e '([.holdings, .deferrals, .side_effects, .reversals, .holds, .standing, .work] | all(. == null or . == []))
        and (has("decisions") | not)
        and ([(.run // [])[] | "\(.key)=\(.value)"] == ["store=session"])' "$1" > /dev/null
}

# rs_record <out> <body|json> <gh view args...>
rs_record() {
    local out=$1 mode=$2 rc
    shift 2
    case "$mode" in body|json) ;; *) echo "$PROG: rs_record: mode is body or json" >&2; return 2 ;; esac
    rs_source > /dev/null
    # RS_READ_STORE names the store to read when it isn't the run's: the write
    # core sets it to the store it is writing, so the move reads the GitHub body
    # it rewrites while the run itself is on the session store.
    if [ "${RS_READ_STORE:-$RS_SOURCE_READ}" = session ]; then
        rs_session_read "$out" "$mode" "${RS_SESSION:-${SESSION:-}}" "$SCOPE" "$NAME" "$REPO" "$REF"
        return $?
    fi
    if [ "$CONTAINER" = issue ]; then
        gh issue view "$REF" --repo "$REPO" "$@" > "$out.raw" 2> "$out.err" < /dev/null
    else
        gh pr view "$REF" --repo "$REPO" "$@" > "$out.raw" 2> "$out.err" < /dev/null
    fi
    rc=$?
    [ $rc -eq 0 ] || return 2
    # Line endings as the write core reads them, so a body GitHub serves with
    # CRLF parses the same in every reader.
    if [ "$mode" = body ]; then
        tr -d '\r' < "$out.raw" > "$out.md"
    else
        jq -r '.body // ""' "$out.raw" 2>> "$out.err" | tr -d '\r' > "$out.md" || return 2
    fi
    # lib_parse writes its refusal to <out>.err, in place of gh's stderr, which
    # is where a caller that parsed the body itself read it before.
    lib_parse "$out.md" "$out"
    rc=$?
    case $rc in
        0|3|65) return $rc ;;
        *) return 5 ;;
    esac
}

# rs_view <container> <ref> <repo> <gh view args...>
rs_view() {
    local c=$1 r=$2 repo=$3 d rc
    shift 3
    case "$c" in issue|pr) ;; *) echo "${PROG:-record-source}: rs_view: the container is issue or pr" >&2; return 64 ;; esac
    if [ -n "${SESSION:-}" ] && [ "$c" = issue ] && [ "$(rs_source)" = session ]; then
        d=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX") || return 2
        rs_session_read "$d/rec" json "$SESSION" "$SCOPE" "$NAME" "$repo" "$r"; rc=$?
        [ $rc -eq 0 ] && cat "$d/rec.raw"
        [ $rc -eq 0 ] || cat "$d/rec.err" >&2
        rm -rf "$d"
        return $rc
    fi
    gh "$c" view "$r" --repo "$repo" "$@" < /dev/null
}

# rs_target_ok <repo> <ref>: the repository and record number rs_record_api will
# read, held to exactly the checks board-lib.sh's bl_repo_ok and bl_pr_ok made on
# this read before the seam, so land-check.sh and land-merge.sh take the same
# inputs they did: owner/name with no `.` or `..` segment, a number of one to nine
# digits with no leading zero. record-source_test.sh compares the two.
rs_target_ok() {
    [[ $1 =~ $RE_REPO ]] && [[ $2 =~ $RE_NUM ]] && [ ${#2} -le 9 ] || return 1
    case "/$1/" in */./*|*/../*) return 1 ;; esac
    return 0
}

# rs_record_api <out>: the run's record through the issues API, under
# board-lib.sh's bl_gh when it is loaded.
rs_record_api() {
    local out=$1 facts rrepo ref scope name c rc
    local SESSION=${2:-${SESSION:-}}
    facts=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION") || return 2
    rrepo=$(printf '%s' "$facts" | jq -r '.repo // ""')
    ref=$(printf '%s' "$facts" | jq -r '.ref // ""')
    scope=$(printf '%s' "$facts" | jq -r '.scope // ""')
    name=$(printf '%s' "$facts" | jq -r '.name // ""')
    rs_target_ok "$rrepo" "$ref" || return 2
    case "$scope" in roadmap) c=issue ;; discipline) c=pr ;; *) return 2 ;; esac
    rs_source > /dev/null
    if [ "$RS_SOURCE_READ" = session ]; then
        rs_session_read "$out" json "$SESSION" "$scope" "$name" "$rrepo" "$ref"; rc=$?
        cat "$out.err" >&2
        [ $rc -eq 0 ] || return 2
        return 0
    fi
    if declare -F bl_gh > /dev/null; then
        bl_gh "$out.rec" api --method GET "repos/$rrepo/issues/$ref" || return 2
    else
        gh api --method GET "repos/$rrepo/issues/$ref" > "$out.rec" 2> "$out.rec.err" < /dev/null || return 2
    fi
    jq -r '.body // ""' "$out.rec" > "$out.md" || return 2
    bash "$HERE/record-parse.sh" --container "$c" --expect-scope "$scope:$name" "$out.md" > "$out" \
        || { echo "$PROG: the record couldn't be parsed" >&2; return 2; }
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
    d=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX") || return 2
    jq '{standing: (.standing // [])}' "$f" > "$d/standing" || { rm -rf "$d"; return 2; }
    jq -nc --arg u "$unit" '[$u]' > "$d/units"
    if ! bash "$HERE/pause-read.sh" --standing "$d/standing" --units "$d/units" > "$d/pauses" 2> /dev/null; then
        rm -rf "$d"; return 2
    fi
    # The holding's pushed head, kept beside the row on the session store only
    # (rs_session_read's <parsed>.pushed): present only when one is kept, so the
    # same state reads the same on either store (PRD R19).
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
    PROG=record-source
    HERE=$(cd "$(dirname "$0")" && pwd)
    SESSION= SCOPE= NAME= REPO= REF= ACTION= TOPIC= HASH=
    rs_usage() { sed -n '/^# Usage (as a script):/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
    while [ $# -gt 0 ]; do
        case "$1" in
            --session) [ $# -ge 2 ] || rs_usage; SESSION=$2; shift 2 ;;
            --scope) [ $# -ge 2 ] || rs_usage; SCOPE=$2; shift 2 ;;
            --name) [ $# -ge 2 ] || rs_usage; NAME=$2; shift 2 ;;
            --repo) [ $# -ge 2 ] || rs_usage; REPO=$2; shift 2 ;;
            --ref) [ $# -ge 2 ] || rs_usage; REF=$2; shift 2 ;;
            --source) ACTION=source; shift ;;
            --probe) ACTION=probe; shift ;;
            --show) ACTION=show; shift ;;
            --host) ACTION=host; shift ;;
            --candidate) ACTION=candidate; shift ;;
            --hash) [ $# -ge 2 ] || rs_usage; HASH=$2; shift 2 ;;
            --facts) [ $# -ge 2 ] || rs_usage; ACTION=facts; TOPIC=$2; shift 2 ;;
            *) rs_usage ;;
        esac
    done
    [ -n "$ACTION" ] || rs_usage
    . "$HERE/record-common.sh"
    case "$ACTION" in
        probe) rs_probe; exit 0 ;;
        candidate)
            # Before any session exists: the scope and name, and the shipped
            # template's hash, come from the opener.
            [[ $SCOPE =~ ^(roadmap|discipline)$ ]] && [[ $NAME =~ $RE_NAME ]] && [[ $HASH =~ ^[0-9a-f]{64}$ ]] || rs_usage
            rs_resume_candidate "$SCOPE" "$NAME" "$HASH"; exit $? ;;
    esac
    lib_facts
    case "$ACTION" in
        source) rs_source; exit 0 ;;
        host)
            [ "$(rs_source)" = session ] || { echo '{}'; exit 0; }
            RS_T=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX")
            trap 'rm -rf "$RS_T"' EXIT
            rs_host "${RS_SESSION:-$SESSION}" "$RS_T/host" \
                || { echo "$PROG: record/host couldn't be read: $(lib_scrub < "$RS_T/host.err" | head -3)" >&2; exit 2; }
            jq -c . "$RS_T/host"
            exit 0 ;;
    esac
    [ "$ACTION" != facts ] || [[ $TOPIC =~ $RE_TOPIC ]] || { echo "$PROG: the topic is not a dispatch topic" >&2; exit 64; }
    lib_run_ref || { echo "$PROG: the run has no record yet" >&2; exit 2; }
    RS_T=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX")
    trap 'rm -rf "$RS_T"' EXIT
    rs_record "$RS_T/rec" body --json body --jq .body
    case $? in
        0) ;;
        4) lib_scrub < "$RS_T/rec.err" >&2; exit 4 ;;
        12) lib_scrub < "$RS_T/rec.err" >&2; exit 12 ;;
        *) echo "$PROG: the record couldn't be read: $(lib_scrub < "$RS_T/rec.err" | head -3)" >&2; exit 2 ;;
    esac
    if [ "$ACTION" = show ]; then
        cat "$RS_T/rec.md"
        exit 0
    fi
    rs_facts "$RS_T/rec" "$TOPIC"
    exit $?
fi
