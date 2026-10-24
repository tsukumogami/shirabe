# engine-session.sh -- a coordinator's record as its koto session holds it, for
# the engine suites that drive real koto. The session is the record's only
# store, so a suite that needs a run to find a record seeds it into the run's
# own keys, before the run's first find, rather than into the gh stand-in.
# Not shipped behaviour.
#
# Sourced after testdata/test-lib.sh (render, session_keys), with HERE set to
# skills/coordinate/scripts. Every koto call runs in the caller's directory and
# environment, so a suite runs these from the directory its session's koto
# calls run in.
#
#   session_seed <session> <record-json> [written]
#       the record, rendered by the codec at <written> (test-lib.sh's render
#       default when not given) and parsed back with the parse half's copy the
#       legacy importer keeps (legacy-import/record-parse.jq, which reads a
#       body to the same JSON), so every column a writer leaves is there,
#       written whole into the session's record/meta and one
#       key per section the record holds (test-lib.sh's session_keys); a
#       section key the session had that the record doesn't hold is removed.
#       Entries, legs and every other key are left as they are.
#   session_record <session>
#       the session's record as JSON on stdout: record/meta's scope and
#       written time and one field per section key, pushed heads dropped, as
#       a body rendered from the keys parses back. Exits 1 when the session
#       holds no record/meta.
#   koto_store_ready
#       0 when this koto has what the session store needs (`context list
#       --prefix` and `session import`), the features coordinate-open.sh
#       probes for before a start; 1 when it lacks either.

ES_SECTIONS="holdings:holdings deferrals:deferrals side_effects:side-effects reversals:reversals decisions:decisions holds:holds run:run standing:standing work:work"

session_seed() {
    local s=$1 j=$2 w=${3-} f pair field key
    f=$(mktemp "$T/session-seed.XXXXXX") || return 1
    if [ -n "$w" ]; then render "$j" issue "$w" > "$f.md"; else render "$j" issue > "$f.md"; fi || return 1
    jq -R -s -L "$HERE/../legacy-import" 'include "record-parse"; parse_record' < "$f.md" > "$f" || return 1
    koto context list "$s" --prefix record/ > "$f.keys" 2> /dev/null || return 1
    for pair in $ES_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        jq -e --arg f "$field" 'has($f)' "$f" > /dev/null && continue
        jq -e --arg k "record/$key" 'index($k) != null' "$f.keys" > /dev/null || continue
        koto context remove "$s" "record/$key" > /dev/null 2>&1 || return 1
    done
    session_keys "$s" "$f" > /dev/null
}

session_record() {
    local s=$1 pair field key f
    f=$(mktemp "$T/session-record.XXXXXX") || return 1
    koto context list "$s" --prefix record/ > "$f.keys" 2> /dev/null || return 1
    jq -e 'index("record/meta") != null' "$f.keys" > /dev/null || return 1
    koto context get "$s" record/meta 2> /dev/null | jq -c '{scope, written}' > "$f" || return 1
    for pair in $ES_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        jq -e --arg k "record/$key" 'index($k) != null' "$f.keys" > /dev/null || continue
        koto context get "$s" "record/$key" > "$f.sec" 2> /dev/null || return 1
        jq -c --arg f "$field" --slurpfile v "$f.sec" '. + {($f): $v[0]}' "$f" > "$f.next" && mv "$f.next" "$f" || return 1
    done
    jq -c 'if has("holdings") then .holdings |= map(del(.pushed_head)) else . end' "$f"
}

# koto_store_ready: this koto has the session store's features, by the same
# probe coordinate-open.sh makes (each subcommand's own help), through KOTO_BIN
# as the scripts call it.
koto_store_ready() {
    local k=${KOTO_BIN:-koto}
    case "$("$k" context list --help 2> /dev/null)" in *--prefix*) ;; *) return 1 ;; esac
    "$k" session import --help > /dev/null 2>&1
}
