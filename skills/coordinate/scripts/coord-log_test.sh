#!/usr/bin/env bash
# coord-log_test.sh -- coord-log.sh and coord-verdict.sh over prepared session
# logs, offline, through the koto stand-in. The engine test proves the same
# behaviour against real koto; this one runs everywhere, including the bash
# 3.2 floor and macOS, where shasum rather than sha256sum does the hashing.
#
# Covers: seal and check (latest visit, --any-visit, an edited hash, another
# state's or session's seal, an unsealed token), seal --file and check --key,
# capture with and without --for and --state, directed-since, run-facts,
# run-start, vars, entered, entry, evidence (--where, --has), captures, unit
# (the message and leg paths), count, slug, live-session --all, the refusal of
# a header whose schema_version isn't 1, provenance by template hash and
# plugin root (and, after the plugin is rewritten in place, by the template
# path koto compiled the run from and the compiled copy it runs), and
# coord-verdict.sh's exit codes for a valid, a stale and an unknown token.
#
# Usage: bash skills/coordinate/scripts/coord-log_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
CL="$HERE/coord-log.sh"
CV="$HERE/coord-verdict.sh"

run_suite() { # run_suite <label>: every case, under the current PATH
    local S=coordinate-demo-20260926T080000Z L=$1
    rm -rf "$KOTO_STORE/sessions/$S" "$KOTO_STORE/context/$S"
    found_session "$S" "$(roadmap_vars demo)" 7
    CAP1=$(bash "$CL" capture --session "$S" --name RECORD_FIND)
    bash "$CL" check --session "$S" --state record_find --sealed "$CAP1" && ok "$L: check accepts the latest visit" || bad "$L: check accepts the latest visit"
    eq "$L: run-facts" '{"scope":"roadmap","name":"demo","repo":"acme/widgets","ref":"7"}' "$(bash "$CL" run-facts --session "$S")"
    eq "$L: run-start" 2026-09-26T08:00:00.000Z "$(bash "$CL" run-start --session "$S")"
    eq "$L: vars" roadmap "$(bash "$CL" vars --session "$S" | jq -r .SCOPE)"
    bash "$CL" entered --session "$S" --state record_find; eq "$L: entered finds a visited state" 0 $?
    bash "$CL" entered --session "$S" --state dispatch; eq "$L: entered reports an unvisited state" 1 $?
    eq "$L: current is the latest transition's target and its sequence" "reconcile 5" "$(bash "$CL" current --session "$S")"
    bash "$CV" --session "$S" --state record_find --capture "$CAP1"; eq "$L: coord-verdict maps found to 10" 10 $?
    bash "$CV" --session "$S" --state record_find --capture "found 8 ${CAP1#found 7 }" 2>/dev/null; eq "$L: an edited token is refused" 1 $?
    bash "$CV" --session "$S" --state record_find --capture "found 7" 2>/dev/null; eq "$L: an unsealed token is refused" 1 $?
    bash "$CV" --session "$S" --state reconcile --capture "$CAP1" 2>/dev/null; eq "$L: another state's seal is refused" 1 $?
    B=$(bash "$CL" seal --session "$S" --state record_find --token "bogus 1")
    bash "$CV" --session "$S" --state record_find --capture "$B"; eq "$L: an unknown verdict exits 3" 3 $?
    # A second visit supersedes the first seal.
    log_to "$S" reconcile record_find
    log_capture "$S" RECORD_FIND "$(bash "$CL" seal --session "$S" --state record_find --token "found 9")"
    bash "$CV" --session "$S" --state record_find --capture "$CAP1" 2>/dev/null; eq "$L: a superseded seal is refused" 1 $?
    bash "$CL" check --session "$S" --state record_find --sealed "$CAP1" --any-visit && ok "$L: --any-visit accepts an earlier real visit" || bad "$L: --any-visit accepts an earlier real visit"
    bash "$CL" capture --session "$S" --name RECORD_FIND --for 7 --state record_find >/dev/null 2>&1; eq "$L: capture --state refuses a superseded value" 1 $?
    bash "$CL" capture --session "$S" --name RECORD_FIND --for 7 --state record_find --any-visit >/dev/null && ok "$L: capture --any-visit accepts a per-unit value" || bad "$L: capture --any-visit accepts a per-unit value"
    eq "$L: capture reads the latest" "found 9" "$(bash "$CL" capture --session "$S" --name RECORD_FIND | cut -d' ' -f1-2)"
    bash "$CL" capture --session "$S" --name NOPE; eq "$L: an absent capture exits 1" 1 $?
    # Another session's seal.
    S2=coordinate-other-20260926T080000Z
    rm -rf "$KOTO_STORE/sessions/$S2"; found_session "$S2" "$(roadmap_vars other)" 7
    bash "$CL" check --session "$S" --state record_find --sealed "$(bash "$CL" capture --session "$S2" --name RECORD_FIND)" --any-visit 2>/dev/null; eq "$L: another session's seal is refused" 1 $?
    # seal --file and check --key.
    printf '{"verdict":"durable"}' > "$T/v.json"
    SF=$(bash "$CL" seal --session "$S" --state record_find --file "$T/v.json" --key coord/v)
    eq "$L: check --key prints the verified bytes" '{"verdict":"durable"}' "$(bash "$CL" check --session "$S" --state record_find --sealed "$SF" --key coord/v)"
    printf 'forged' > "$KOTO_STORE/context/$S/coord/v"
    bash "$CL" check --session "$S" --state record_find --sealed "$SF" --key coord/v >/dev/null 2>&1; eq "$L: an edited context value is refused" 1 $?
    # directed-since.
    bash "$CL" directed-since --session "$S" --from 0 >/dev/null; eq "$L: no directed transition" 0 $?
    log_ev "$S" directed_transition '{"from":"record_find","to":"dispatch"}'
    OUT=$(bash "$CL" directed-since --session "$S" --from 0); eq "$L: a directed transition is reported" 1 $?
    case "$OUT" in *"record_find->dispatch"*) ok "$L: the report names the edge" ;; *) bad "$L: the report names the edge" "$OUT" ;; esac
    # provenance: the stand-in compiles to $KOTO_COMPILED_HASH.
    bash "$CL" provenance --session "$S"; eq "$L: provenance passes for the matching template hash" 0 $?
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S" 2>/dev/null; eq "$L: provenance fails for another template" 1 $?
    S3=coordinate-alien-20260926T080000Z
    rm -rf "$KOTO_STORE/sessions/$S3"; found_session "$S3" "$(roadmap_vars alien | jq -c '.PLUGIN_ROOT = "/elsewhere"')" 7
    bash "$CL" provenance --session "$S3" 2>/dev/null; eq "$L: provenance fails for another plugin root" 1 $?
    # The plugin rewritten in place since the run opened: the shipped template
    # now compiles to another hash, but koto opened the run from the shipped
    # template's path and still holds the compiled copy it runs it from.
    local SHIPPED="$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/coordinate.md" S5=coordinate-swap-20260926T080000Z
    rm -rf "$KOTO_STORE/sessions/$S5"; found_session "$S5" "$(roadmap_vars swap)" 7
    H5=$(opened_from "$S5" "$SHIPPED" '{"compiled":"as opened"}')
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S5"; eq "$L: provenance passes after the plugin is rewritten in place" 0 $?
    rm -f "$KOTO_STORE/cache/$H5.json"
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S5" 2>/dev/null; eq "$L: provenance fails once the run's compiled copy is gone" 1 $?
    opened_from "$S5" "$SHIPPED" '{"compiled":"as opened"}' >/dev/null
    printf 'edited' > "$KOTO_STORE/cache/$H5.json"
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S5" 2>/dev/null; eq "$L: provenance fails when the run's compiled copy no longer matches its hash" 1 $?
    # A reinstall that left the shipped template uncompilable.
    opened_from "$S5" "$SHIPPED" '{"compiled":"as opened"}' >/dev/null
    KOTO_COMPILE_FAIL=1 bash "$CL" provenance --session "$S5"; eq "$L: provenance passes when the rewritten template doesn't compile" 0 $?
    # koto opened the run through a symlink to the shipped directory.
    rm -rf "$T/linked"; ln -s "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates" "$T/linked"
    opened_from "$S5" "$T/linked/coordinate.md" '{"compiled":"as opened"}' >/dev/null
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S5"; eq "$L: provenance passes for a source directory reached through a symlink" 0 $?
    # A foreign session: opened from a real copy of the template at another path.
    local S6=coordinate-foreign-20260926T080000Z
    rm -rf "$KOTO_STORE/sessions/$S6"; found_session "$S6" "$(roadmap_vars foreign)" 7
    mkdir -p "$T/elsewhere"; cp "$SHIPPED" "$T/elsewhere/coordinate.md"
    opened_from "$S6" "$T/elsewhere/coordinate.md" '{"compiled":"foreign"}' >/dev/null
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S6" 2>/dev/null; eq "$L: provenance fails for a session opened from another template path" 1 $?
    opened_from "$S6" "$PLUGIN_ROOT_REAL/skills/coordinate/koto-templates/other.md" '{"compiled":"foreign"}' >/dev/null
    KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S6" 2>/dev/null; eq "$L: provenance fails for another template beside the shipped one" 1 $?
    # A relative source directory names no fixed place, so it never matches,
    # even one that would resolve to the shipped directory from here.
    opened_from "$S6" "skills/coordinate/koto-templates/coordinate.md" '{"compiled":"foreign"}' >/dev/null
    (cd "$PLUGIN_ROOT_REAL" && KOTO_COMPILED_HASH=deadbeef bash "$CL" provenance --session "$S6" 2>/dev/null); eq "$L: provenance fails for a relative source directory" 1 $?
    bash "$CL" frobnicate 2>/dev/null; eq "$L: an unknown subcommand is a usage error" 64 $?
    event_reads "$L"
}

event_reads() { # event_reads <label>: entry, evidence, captures, unit, count, slug, live-session --all, the schema check
    local S=coordinate-events-20260926T080000Z L=$1
    rm -rf "$KOTO_STORE/sessions/$S" "$KOTO_STORE/context/$S"
    log_new "$S" "$(roadmap_vars events)"                                      # seq 1-2
    log_evidence "$S" wait '{"event":"report","unit":"alpha"}' 2026-09-26T09:00:00.000Z   # 3
    log_to "$S" wait report_facts                                              # 4
    log_evidence "$S" wait '{"event":"merged","unit":"beta"}'                  # 5
    log_evidence "$S" wait '{"event":"tick"}'                                  # 6
    eq "$L: entry prints the seq and the source" "4 wait" "$(bash "$CL" entry --session "$S" --state report_facts)"
    bash "$CL" entry --session "$S" --state report_facts --before 4; eq "$L: entry before the only entry is none" 1 $?
    eq "$L: entry --with-time adds the entry's timestamp" "4 wait 2026-09-26T10:00:00.000Z" "$(bash "$CL" entry --session "$S" --state report_facts --with-time)"
    bash "$CL" entry --session "$S" --state wait --with-time >/dev/null 2>&1; eq "$L: entry --with-time into a state never entered is none" 1 $?
    local S2=coordinate-twice-20260926T080000Z
    rm -rf "$KOTO_STORE/sessions/$S2" "$KOTO_STORE/context/$S2"
    log_new "$S2" "$(roadmap_vars twice)"                                      # seq 1-2
    log_to "$S2" pick_facts wait 2026-09-26T09:00:00.000Z                     # 3
    log_to "$S2" wait decision_apply 2026-09-26T09:05:00.000Z                 # 4
    log_to "$S2" pick_facts wait 2026-09-26T09:10:00.000Z                     # 5
    eq "$L: entry --with-time into a state entered twice is the latest" "5 pick_facts 2026-09-26T09:10:00.000Z" "$(bash "$CL" entry --session "$S2" --state wait --with-time)"
    eq "$L: entry --with-time --before takes the earlier one" "3 pick_facts 2026-09-26T09:00:00.000Z" "$(bash "$CL" entry --session "$S2" --state wait --before 5 --with-time)"
    eq "$L: evidence is the latest in the state" 6 "$(bash "$CL" evidence --session "$S" --state wait | jq .seq)"
    eq "$L: evidence --before bounds the window" 3 "$(bash "$CL" evidence --session "$S" --state wait --before 5 | jq .seq)"
    eq "$L: evidence --after bounds the window" 6 "$(bash "$CL" evidence --session "$S" --state wait --after 5 | jq .seq)"
    eq "$L: evidence --where matches a field" 3 "$(bash "$CL" evidence --session "$S" --state wait --where event=report | jq .seq)"
    eq "$L: evidence --where twice matches both" 5 "$(bash "$CL" evidence --session "$S" --state wait --where event=merged --where unit=beta | jq .seq)"
    bash "$CL" evidence --session "$S" --state wait --where unit=gamma; eq "$L: evidence --where with no match is none" 1 $?
    eq "$L: evidence --has skips evidence without the field" 5 "$(bash "$CL" evidence --session "$S" --state wait --has unit | jq .seq)"
    bash "$CL" evidence --session "$S" --state wait --where noequals 2>/dev/null; eq "$L: --where without FIELD=VALUE is a usage error" 64 $?
    # unit: the message path.
    eq "$L: unit is the latest wait evidence naming a unit" "topic beta" "$(bash "$CL" unit --session "$S")"
    eq "$L: unit --event takes that event's evidence" "topic alpha" "$(bash "$CL" unit --session "$S" --event report)"
    eq "$L: unit --event takes the evidence even when it names no unit" "topic " "$(bash "$CL" unit --session "$S" --event tick)"
    eq "$L: unit --before bounds the window" "topic alpha" "$(bash "$CL" unit --session "$S" --before 5)"
    bash "$CL" unit --session "$S" --before 3; eq "$L: unit with no arrival is none" 1 $?
    # unit: the leg path.
    log_to "$S" wait leg_pick                                                  # 7
    log_capture "$S" WAIT_REQ "req-1 sealed:7:ab"                              # 8
    log_to "$S" leg_pick wait_leg                                              # 9
    log_capture "$S" WAIT_LEG execute                                          # 10
    log_to "$S" wait_leg take_report 2026-09-26T10:30:00.000Z                  # 11
    eq "$L: unit on the leg path names the leg" "leg req-1:execute" "$(bash "$CL" unit --session "$S")"
    eq "$L: unit on the leg path ignores --event" "leg req-1:execute" "$(bash "$CL" unit --session "$S" --event report)"
    eq "$L: unit before the leg arrival is the message's" "topic beta" "$(bash "$CL" unit --session "$S" --before 11)"
    log_capture "$S" WAIT_REQ "req-2"                                          # 12
    eq "$L: unit reads the leg captures before the entry into take_report" "leg req-1:execute" "$(bash "$CL" unit --session "$S")"
    log_evidence "$S" wait '{"event":"report","unit":"gamma"}'                 # 13
    eq "$L: a later message arrival wins over the leg" "topic gamma" "$(bash "$CL" unit --session "$S")"
    log_to "$S" wait leg_pick; log_capture "$S" WAIT_REQ "Bad:Req"             # 14 15
    log_to "$S" leg_pick wait_leg; log_to "$S" wait_leg take_report            # 16 17
    bash "$CL" unit --session "$S" >/dev/null 2>&1; eq "$L: a leg whose captures are not a request id is unusable" 3 $?
    log_to "$S" record take_report                                             # 18
    eq "$L: an entry into take_report from elsewhere is not the leg path" "topic gamma" "$(bash "$CL" unit --session "$S")"
    # captures.
    eq "$L: captures lists every value, oldest first" "req-1 sealed:7:ab|req-2|Bad:Req" \
        "$(bash "$CL" captures --session "$S" --name WAIT_REQ | jq -r .value | tr '\n' '|' | sed 's/|$//')"
    eq "$L: captures carries each one's seq" "8 12" "$(bash "$CL" captures --session "$S" --name WAIT_REQ --before 15 | jq -r .seq | tr '\n' ' ' | sed 's/ $//')"
    eq "$L: captures --after bounds the window" 15 "$(bash "$CL" captures --session "$S" --name WAIT_REQ --after 12 | jq -r .seq)"
    bash "$CL" captures --session "$S" --name NOPE; eq "$L: no capture of the name is none" 1 $?
    # count, slug, live-session --all.
    eq "$L: count is the events after the header" 18 "$(bash "$CL" count --session "$S")"
    eq "$L: slug lowercases, dashes and squeezes" discipline-ci-health "$(bash "$CL" slug --scope discipline --name CI_Health..)"
    eq "$L: slug of a roadmap" roadmap-plugin-system "$(bash "$CL" slug --scope roadmap --name plugin-system)"
    local S2=coordinate-events-20260926T090000Z
    rm -rf "$KOTO_STORE/sessions/$S2"; log_new "$S2" "$(roadmap_vars events)"
    bash "$CL" live-session --scope-slug events >/dev/null 2>&1; eq "$L: two live sessions are several" 3 $?
    eq "$L: live-session --all lists both" "$S $S2" "$(bash "$CL" live-session --scope-slug events --all | sort | tr '\n' ' ' | sed 's/ $//')"
    log_end "$S2"
    eq "$L: live-session --all skips an ended one" "$S" "$(bash "$CL" live-session --scope-slug events --all)"
    log_end "$S"
    bash "$CL" live-session --scope-slug events --all; eq "$L: live-session --all with none live" 1 $?
    # A header this reader doesn't know is refused, not misread.
    sed 's/"schema_version":1/"schema_version":2/' "$KOTO_STORE/sessions/$S/koto-$S.state.jsonl" > "$T/v2"
    cp "$T/v2" "$KOTO_STORE/sessions/$S/koto-$S.state.jsonl"
    bash "$CL" count --session "$S" 2>"$T/err"; eq "$L: a schema_version 2 log is refused" 2 $?
    grep -q 'schema_version 2' "$T/err" && ok "$L: the refusal names the schema version" || bad "$L: the refusal names the schema version" "$(cat "$T/err")"
    sed 's/"schema_version":2,//' "$T/v2" > "$KOTO_STORE/sessions/$S/koto-$S.state.jsonl"
    bash "$CL" entry --session "$S" --state wait 2>/dev/null; eq "$L: a header without schema_version is refused" 2 $?
}

run_suite default
# The macOS path: no sha256sum on PATH, so shasum hashes.
if command -v shasum >/dev/null 2>&1; then
    mkdir -p "$T/nosha"
    for tool in bash sh env cat sed awk grep head tail tr cut wc sort mktemp rm mkdir cp mv ln chmod date basename dirname printf jq shasum perl dd od; do
        p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$T/nosha/$tool"
    done
    OLDPATH=$PATH
    PATH="$HERE/testdata:$T/nosha"
    if command -v sha256sum >/dev/null 2>&1; then bad "shasum path: sha256sum is still visible"
    else run_suite shasum; fi
    PATH=$OLDPATH
else
    echo "note: shasum not present; the macOS hashing path was not exercised here"
fi
done_tests coord-log
