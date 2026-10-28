#!/usr/bin/env bash
# legacy-import_test.sh -- the legacy importer's suite (import.sh), driven
# directly with /coordinate's gh and koto stand-ins.
#
# The lookup at both scopes: an open record, a moved-shape body, a record by an
# author without write access, none, several, and a session holding
# record/meta, which is a resume with no GitHub read. The import of a fixture
# record holding every section (Decisions with an Archived line) and entries
# from writers, a non-writer, a stranger and an unmarked comment: each section
# key as the body holds it, the Run section without its store row, every key
# passing state-schema.jq, the writers' entries decoded and numbered, record/meta
# last, and one moved comment as the only GitHub write. A crash part way
# through the entries, after the entries, and after the note: each next start
# is still fresh, imports again and ends with one note and one record/meta. A
# body that doesn't parse, another scope's body and an author whose access
# can't be read are record-unreadable with nothing written. A discipline
# rotation's pull request, its window from the title. After the import the
# session reads back as a resume, and the handover gate and the reconcile read
# run on it. Only the opener, coordinate-open.sh, calls the importer, and it
# reaches none of the code the record's removal deletes.
#
# The fixture bodies under testdata/ were rendered once by the codec this
# importer reads, so the suite needs no renderer; testdata/state.json is the
# state they hold.
#
# Needs bash and jq only.
# Usage: bash skills/coordinate/legacy-import/legacy-import_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

OWN=$(cd "$(dirname "$0")" && pwd)
HERE=$(cd "$OWN/../scripts" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
export KOTO_FEATURES=1 RS_RETRY_PAUSE=0
HS=abababababababababababababababababababababababababababababababab
export KOTO_COMPILED_HASH=$HS

IMP="$OWN/import.sh"
FX="$OWN/testdata"
TITLE="Coordinator record: ROADMAP-plugin-system"
S=coordinate-roadmap-plugin-system-20261023T100000Z
SD=coordinate-discipline-ci-health-20261023T100000Z
NOTE="Imported into koto session $S on a coordinator start: the record's state now lives in that session, and this record is no longer written."

add_issue() { # add_issue <n> <author> <body-file> [title]
    db '.issues += [{repo: "acme/widgets", number: $n, title: $t, body: $b, state: "open", author: $a, editor: null}]' \
        --argjson n "$1" --arg a "$2" --rawfile b "$3" --arg t "${4:-$TITLE}"
}
add_pr() { # add_pr <n> <author> <body-file> <title> [cross-repository]
    db '.prs += [{repo: "acme/widgets", number: $n, title: $t, body: $b, state: "OPEN", isDraft: false,
        isCrossRepository: $x, baseRefName: "main", headRefName: "coordinate/discipline-ci-health",
        headRefOid: "2222222222222222222222222222222222222222", author: $a, editor: null}]' \
        --argjson n "$1" --arg a "$2" --rawfile b "$3" --arg t "$4" --argjson x "${5:-false}"
}
comment() { # comment <n> <id> <user> <body>
    db '.comments = ((.comments // []) + [{repo: "acme/widgets", number: $n, id: $i, body: $b, user: $u,
        created_at: "2026-10-08T1\($i % 10):00:00Z", updated_at: "2026-10-08T1\($i % 10):00:00Z"}])' \
        --argjson n "$1" --argjson i "$2" --arg u "$3" --arg b "$4"
}
entry() { # entry <n> <id> <user> <kind> <encoded text>: a marked comment as state-entry.sh posts it
    comment "$1" "$2" "$3" "$(printf '<!-- coordinator-record-entry v1 kind=%s -->\n**2026-10-08T09:0%s:00Z** (host clock) %s\n\n%s\n' "$4" "$(($2 % 10))" "$4" "$5")"
}
# world <n> <scope>: a fresh DB holding record <n> with five comments, and an
# empty koto store.
world() {
    db_init
    rm -rf "$KOTO_STORE/context" "$KOTO_STORE/sessions"
    mkdir -p "$KOTO_STORE/sessions"
    if [ "$2" = roadmap ]; then add_issue "$1" alice "$FX/roadmap.md"
    else add_pr "$1" alice "$FX/discipline.md" "docs(coordinate): ci-health rotation $TODAY to $NEXT_WEEK"; fi
    entry "$1" 1001 alice entry 'dispatched Feature 2 to plugin-registry &amp; told &#64;lane_owner'
    entry "$1" 1002 bob entry 'a reader wrote this'
    entry "$1" 1003 carol decisions 'settled 1-3'
    comment "$1" 1004 alice 'an unmarked comment'
    entry "$1" 1005 mallory entry 'a stranger wrote this'
    reset_calls
}
TODAY=$(date -u +%Y-%m-%d)
NEXT_WEEK=$(jq -rn 'now + 7 * 86400 | strftime("%Y-%m-%d")')
key() { cat "$KOTO_STORE/context/$1/$2" 2>/dev/null; }
# gh_writes: every GitHub call that could change something.
gh_writes() { grep -E 'issue (edit|close|create|reopen|comment)|pr (edit|create|ready|close|merge|comment)|--method (POST|PUT|PATCH|DELETE)|graphql' "$GH_DB.calls"; }
notes() { jq --argjson n "$1" '[(.comments // [])[] | select(.number == $n and (.body | contains("kind=moved")))] | length' "$GH_DB"; }
imp() { bash "$IMP" --session "${SESS:-$S}" --scope "${SCOPE_:-roadmap}" --name "${NAME_:-plugin-system}" --repo acme/widgets "$@"; }
EXPECT=$(jq -c '.run |= map(select(.key != "store"))' "$FX/state.json")
ENTRIES='[{"n":1,"stamp":"2026-10-08T09:01:00Z","kind":"entry","text":"dispatched Feature 2 to plugin-registry & told @lane_owner"},{"n":2,"stamp":"2026-10-08T09:03:00Z","kind":"decisions","text":"settled 1-3"}]'
# state_of <session>: the record the session's keys hold, as one JSON object.
state_of() {
    local d="$KOTO_STORE/context/$1/record" pair
    jq -c '{scope, written}' "$d/meta" > "$T/so.json" || return 1
    for pair in holdings:holdings deferrals:deferrals side_effects:side-effects reversals:reversals decisions:decisions holds:holds run:run standing:standing work:work; do
        [ -f "$d/${pair#*:}" ] || continue
        jq -c --arg f "${pair%%:*}" --slurpfile v "$d/${pair#*:}" '.[$f] = $v[0]' "$T/so.json" > "$T/so.new" && mv "$T/so.new" "$T/so.json"
    done
    cat "$T/so.json"
}
entries_of() { # entries_of <session>: the record/entries/ keys' values, in order
    local f
    for f in "$KOTO_STORE/context/$1/record/entries"/*; do [ -f "$f" ] && cat "$f"; done | jq -s -c .
}

echo "== the fixture =="
eq "the fixture body parses to the fixture state" "$(jq -cS . "$FX/state.json")" \
    "$(jq -R -s -L "$OWN" 'include "record-parse"; parse_record | del(.written)' < "$FX/roadmap.md" | jq -cS .)"
eq "  ... and the pull request body to the same state at discipline scope" \
    "$(jq -cS '.scope = {kind: "discipline", name: "ci-health"}' "$FX/state.json")" \
    "$(jq -R -s -L "$OWN" 'include "record-parse"; parse_record | del(.written)' < "$FX/discipline.md" | jq -cS .)"
# Its Run section's `store github` row, which the import drops, is the one
# row the session's schema refuses.
jq -n -L "$HERE" --slurpfile s "$FX/state.json" 'include "state-schema"; $s[0] | .run |= map(select(.key != "store")) | check_record([]) | empty' > /dev/null 2> "$T/err" \
    && ok "  ... which holds every section and, its store row aside, passes state-schema.jq" || bad "  ... which holds every section and, its store row aside, passes state-schema.jq" "$(cat "$T/err")"
if jq -n -L "$HERE" --slurpfile s "$FX/state.json" 'include "state-schema"; $s[0] | check_record([]) | empty' > /dev/null 2> "$T/err"; then r=passed; else r=refused; fi
eq "  ... and with it is refused: the store is the session" "refused 1" "$r $(grep -c 'the store is the session; a store row reads session, never github' "$T/err")"

echo "== the lookup =="
world 7 roadmap
eq "an open record at roadmap scope" "record 7" "$(imp --lookup 2> "$T/err")"
eq "  ... with no GitHub write" "" "$(gh_writes)"
add_issue 8 alice "$FX/moved.md"
eq "a moved-shape body beside it is no record" "record 7" "$(imp --lookup 2> "$T/err")"
add_issue 9 bob "$FX/roadmap.md"
eq "nor is one opened by an author without write access" "record 7" "$(imp --lookup 2> "$T/err")"
grep -q '#9 skipped: its author has no write access' "$T/err" \
    && ok "  ... which the lookup names on stderr" || bad "  ... which the lookup names on stderr" "$(cat "$T/err")"
add_issue 10 carol "$FX/roadmap.md" "Coordinator record: ROADMAP-plugin-system-v2"
eq "nor one with a longer title" "record 7" "$(imp --lookup 2> "$T/err")"
add_issue 11 carol "$FX/roadmap.md"
OUT=$(imp --lookup 2> "$T/err"); rc=$?
eq "two open records: several, refused" "65 several 7 11" "$rc $OUT"
world 7 roadmap; db '.issues = []'
eq "no record: none" "none" "$(imp --lookup 2> "$T/err")"
world 7 roadmap
printf '{"scope":{"kind":"roadmap","name":"plugin-system"},"store":"session","written":"x","pending":false}' | koto context add "$S" record/meta
eq "a session holding record/meta: resume" "resume" "$(imp --lookup 2> "$T/err")"
eq "  ... read before GitHub, which it never reads" "" "$(cat "$GH_DB.calls")"
OUT=$(imp --ref 7 2> "$T/err"); rc=$?
eq "  ... and the import refuses it" "65" "$rc"
world 76 discipline
eq "an open rotation pull request at discipline scope" "record 76" "$(SESS=$SD SCOPE_=discipline NAME_=ci-health imp --lookup 2> "$T/err")"
db '.prs[0].isCrossRepository = true'
eq "  ... and not one from a fork" "none" "$(SESS=$SD SCOPE_=discipline NAME_=ci-health imp --lookup 2> "$T/err")"

echo "== the import =="
world 7 roadmap
OUT=$(imp --ref 7 2> "$T/err"); rc=$?
eq "the import of a full record" "0 imported=7 entries=2" "$rc $OUT"
eq "  ... writes each section as the body holds it, the store row dropped" "$(printf '%s' "$EXPECT" | jq -cS 'del(.written)')" \
    "$(state_of "$S" | jq -cS 'del(.written)')"
eq "  ... keeps no store row" "[]" "$(key "$S" record/run | jq -c '[.[] | select(.key == "store")]')"
state_of "$S" > "$T/imported.json"
jq -n -L "$HERE" --slurpfile s "$T/imported.json" 'include "state-schema"; $s[0] | check_record([]) | empty' > /dev/null 2> "$T/err" \
    && ok "  ... every key passing state-schema.jq" || bad "  ... every key passing state-schema.jq" "$(cat "$T/err")"
eq "  ... with Decisions' Archived line" "[1,2,3]" "$(key "$S" record/decisions | jq -c .archived)"
eq "  ... the writers' entries only, decoded and numbered" "$ENTRIES" "$(entries_of "$S")"
eq "  ... the decisions entry marked as state-entry.sh marks one" 'record/archive/000002 {"n":2}' \
    "$(cd "$KOTO_STORE/context/$S" && ls record/archive/*) $(key "$S" record/archive/000002)"
eq "  ... record/meta with the body's written time" '{"scope":{"kind":"roadmap","name":"plugin-system"},"store":"session","written":"2026-10-08T10:00:00Z","pending":false}' "$(key "$S" record/meta)"
eq "  ... record/meta written last" "record/meta" "$(grep '^context add' "$KOTO_STORE/calls" | tail -1 | awk '{print $4}')"
eq "  ... one GitHub write: a comment on the record" "api --method POST repos/acme/widgets/issues/7/comments" \
    "$(gh_writes | sed 's/ --input.*//')"
eq "  ... the moved note, by the coordinator's login, naming the session" "coord|moved|$NOTE" \
    "$(jq -r --arg m "kind=moved" '[.comments[] | select(.body | contains($m))][0] | "\(.user)|moved|\(.body | split("\n")[3:] | join("\n") | rtrimstr("\n"))"' "$GH_DB")"
eq "  ... and no body edit" "$(cat "$FX/roadmap.md")" "$(jq -r '.issues[0].body' "$GH_DB")"
eq "the next start is a resume" "resume" "$(reset_calls; imp --lookup 2> "$T/err")"
eq "  ... with no GitHub read" "" "$(cat "$GH_DB.calls")"

echo "== a crash, and the next start =="
crash() { # crash <label> <setup>: a run cut short, then the next start
    world 7 roadmap
    koto context add "$S" record/entries/000005 < "$FX/state.json" > /dev/null
    printf '{"n":5}' | koto context add "$S" record/archive/000005 > /dev/null
    OUT=$(eval "$2"; imp --ref 7 2> "$T/err"); rc=$?
    eq "$1: the run stops part way" "11" "$rc"
    eq "  ... leaving no record/meta" "" "$(key "$S" record/meta)"
    eq "  ... so the next start is fresh" "record 7" "$(imp --lookup 2> "$T/err")"
    db '.fail = []'
    OUT=$(imp --ref 7 2> "$T/err"); rc=$?
    eq "  ... and imports again" "0 imported=7 entries=2" "$rc $OUT"
    eq "  ... rewriting the same sections whole" "$(printf '%s' "$EXPECT" | jq -cS 'del(.written)')" "$(state_of "$S" | jq -cS 'del(.written)')"
    eq "  ... and the same entries, none left past them" "$ENTRIES" "$(entries_of "$S")"
    eq "  ... and only the decisions entry's marker" "record/archive/000002" "$(cd "$KOTO_STORE/context/$S" && ls record/archive/*)"
    eq "  ... ending with one note" "1" "$(notes 7)"
    eq "  ... and one record/meta" "false" "$(key "$S" record/meta | jq -r .pending)"
}
crash "part way through the entries" 'export KOTO_FAIL_ADD=record/entries/000002'
crash "after the sections and entries" 'db ".fail = [{match: \"POST repos/acme/widgets/issues/7/comments\", rc: 1, stderr: \"HTTP 502\"}]"'
crash "after the note" 'export KOTO_FAIL_ADD=record/meta'

echo "== record-unreadable =="
unreadable() { # unreadable <label>
    OUT=$(imp --ref 7 2> "$T/err"); rc=$?
    eq "$1" "65 record-unreadable 7" "$rc $OUT"
    eq "  ... writing nothing to the session" "none" "$(session_snapshot "$S")"
    eq "  ... nor to GitHub" "" "$(gh_writes)"
}
world 7 roadmap; db '.issues[0].body = "> This is a **coordinator record** for ROADMAP-plugin-system.\n\nnot a record"'
unreadable "a body that doesn't parse"
world 7 roadmap
sed 's/^| go | acme\/widgets#14 |/| go | acme\/widgets |/' "$FX/roadmap.md" > "$T/schema.md"
db '.issues[0].body = $b' --rawfile b "$T/schema.md"
unreadable "a body that parses to a state the schema check refuses"
world 7 roadmap; db '.issues[0].body = $b' --rawfile b "$FX/discipline.md"
unreadable "another scope's body"
world 7 roadmap; db '.fail = [{match: "collaborators/carol/permission", rc: 1, stderr: "HTTP 502: Bad Gateway"}]'
unreadable "an entry author whose access can't be read"
world 7 roadmap; db '.issues[0].body = $b' --rawfile b "$FX/moved.md"
OUT=$(imp --ref 7 2> "$T/err"); rc=$?
eq "a moved-shape record is refused" "65 none" "$rc $(session_snapshot "$S")"

echo "== the store row =="
for v in github session; do
    world 7 roadmap
    sed "s/^| store | github |/| store | $v |/" "$FX/roadmap.md" > "$T/store.md"
    db '.issues[0].body = $b' --rawfile b "$T/store.md"
    OUT=$(imp --ref 7 2> "$T/err"); rc=$?
    eq "a store $v row is dropped" "0 coordinator" "$rc $(key "$S" record/run | jq -r 'map(.key) | join(" ")')"
done
jq -n -L "$HERE" --slurpfile r "$KOTO_STORE/context/$S/record/run" 'include "state-schema"; {scope: {kind: "roadmap", name: "plugin-system"},
        holdings: [], deferrals: [], side_effects: [], reversals: [], run: $r[0]} | check_record([]) | empty' > /dev/null 2> "$T/err" \
    && ok "  ... and the Run section passes state-schema.jq without it" || bad "  ... and the Run section passes state-schema.jq without it" "$(cat "$T/err")"

echo "== a discipline rotation =="
world 76 discipline
OUT=$(SESS=$SD SCOPE_=discipline NAME_=ci-health imp --ref 76 2> "$T/err"); rc=$?
eq "the import of a rotation pull request" "0 imported=76 entries=2" "$rc $OUT"
eq "  ... its window from the title" "{\"start\":\"$TODAY\",\"end\":\"$NEXT_WEEK\",\"host_repo\":\"acme/widgets\",\"predecessor\":null}" "$(key "$SD" record/rotation)"
eq "  ... its sections" "$(jq -cS '.scope = {kind: "discipline", name: "ci-health"} | .run |= map(select(.key != "store")) | del(.written)' "$FX/state.json")" \
    "$(state_of "$SD" | jq -cS 'del(.written)')"
eq "  ... and one comment on the pull request" "api --method POST repos/acme/widgets/issues/76/comments" "$(gh_writes | sed 's/ --input.*//')"
world 76 discipline; db '.prs[0].title = "docs(coordinate): ci-health rotation"'
OUT=$(SESS=$SD SCOPE_=discipline NAME_=ci-health imp --ref 76 2> "$T/err"); rc=$?
eq "a rotation title without its dates is record-unreadable" "65 record-unreadable 76 none" "$rc $OUT $(session_snapshot "$SD")"

echo "== after the import =="
# The opener opens the run's session and seals its find before the import;
# here the suite does both.
world 7 roadmap
found_session "$S" "$(roadmap_vars plugin-system)" "$HS"
printf '{"source":"session","reason":"found"}' | koto context add "$S" coord/source.json
imp --ref 7 > /dev/null 2> "$T/err"
eq "the session is the scope's resume candidate" "resume $S" \
    "$(bash "$HERE/state-read.sh" --candidate --scope roadmap --name plugin-system --hash "$HS" 2> "$T/err" | jq -r '"\(.action) \(.session)"')"
OUT=$(bash "$HERE/state-handover.sh" --session "$S" 2> "$T/err"); rc=$?
# The sandbox row is still dispatching, which the gate leaves out.
eq "the handover gate runs on the imported state" "0 lane_owner plugin-registry" \
    "$rc $(printf '%s' "$OUT" | jq -r '"\(.coordinator) \([.workers[].worker] | sort | join(","))"' 2>/dev/null)"
OUT=$(bash "$HERE/reconcile-read.sh" --session "$S" 2> "$T/err"); rc=$?
eq "  ... and so does the reconcile read" "0 found 2" "$rc $(printf '%s' "$OUT" | jq -r '"\(.status) \(.holdings | length)"' 2>/dev/null)"

echo "== where it stands =="
eq "only the opener, coordinate-open.sh, calls the importer" "coordinate-open.sh" \
    "$(grep -rn 'legacy-import/import\.sh' "$HERE" "$HERE/../koto-templates" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
        | grep -v '_test\.sh:' | sed 's/:.*//; s|.*/||' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
# What the record's removal deletes or strips from the files it keeps.
GONE='record-(parse|render|append|find|move|open|write|holding|confirm)\.sh|record-codec|lib_(open_issues|discipline_read|authority|has_write_access|rotation_dates|file_at|parse)([^A-Za-z_]|$)|ISSUE_TITLE|rs_(view|record_api|moved|record|source)([^A-Za-z_]|$)'
eq "the importer reaches nothing the removal deletes" "" "$(grep -nE "$GONE" "$IMP" | grep -vE '^[0-9]+:[[:space:]]*#')"
eq "  ... and sources only the write core and its library" "state-common.sh state-write-core.sh state-write-core.sh" \
    "$(grep -oE '^[[:space:]]*(\( )?\. "\$HERE/[a-z-]+\.sh"' "$IMP" | sed 's|.*/||; s|"||' | tr '\n' ' ' | sed 's/ $//')"
eq "its parser is its own copy, with no renderer" "0 0" \
    "$(grep -c 'include "record-codec"' "$IMP") $(grep -cE '^def (render|r_)' "$OWN/record-parse.jq")"

done_tests legacy-import_test
