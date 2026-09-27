#!/usr/bin/env bash
# coord-log_test.sh -- coord-log.sh and coord-verdict.sh over prepared session
# logs, offline, through the koto stand-in. The engine test proves the same
# behaviour against real koto; this one runs everywhere, including the bash
# 3.2 floor and macOS, where shasum rather than sha256sum does the hashing.
#
# Covers: seal and check (latest visit, --any-visit, an edited hash, another
# state's or session's seal, an unsealed token), seal --file and check --key,
# capture with and without --for and --state, directed-since, run-facts,
# run-start, vars, entered, provenance by template hash and plugin root, and
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
    bash "$CL" frobnicate 2>/dev/null; eq "$L: an unknown subcommand is a usage error" 64 $?
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
