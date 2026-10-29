#!/usr/bin/env bash
# coordinate-open-carry-window_engine_test.sh -- the opener's carry in koto's
# write window (shirabe#1337), against real koto and the shipped coordinate.md.
#
# Proves: on a koto with `koto session flush`, a start that carries a live run
# makes every add of a key into the new run with KOTO_WRITE_WINDOW set to the
# new run, flushes the new run once after the last add, and writes record/meta
# after the flush without the variable, the new run landing with the source's
# written time; a carry whose flush fails is failed=carry, exit 1, saying the
# window didn't close, with the new run cancelled holding no record and the
# source live, uncancelled and untouched (its record/meta and its keys as they
# were), as for a failed add. On a koto without `session flush` a carry lands
# with no call carrying the variable.
#
# koto runs behind a shim that logs every call with the variable's value and,
# with WF_FAIL set, fails `koto session flush <run>`. The starts run a copy of
# the plugin whose template the compat table doesn't list, so each carries the
# scope's live run, as a handover to a session whose plugin path differs does.
#
# Needs koto, jq and git; SKIPs (exit 0) without one, which run-tests.sh
# --engine turns into a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
# The window's variable is what the shim logs; none may come in from the caller.
unset KOTO_WRITE_WINDOW
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for b in koto jq git; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open-carry-window.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */coordinate-open-carry-window.*) rm -rf "$T" ;; esac'
export HOME="$T/home"; mkdir -p "$HOME"; export GIT_CEILING_DIRECTORIES="$T"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
# gh is the testdata/gh stand-in over a DB with no issue and no pull request.
export GH_DB="$T/gh.json"
jq -n '{login: "coord", repos: {"acme/widgets": {private: false, default_branch: "main"}}, issues: [], prs: [],
    branches: {}, commits: {}, permissions: {}, files: {}, fail: []}' > "$GH_DB"
: > "$GH_DB.calls"
mkdir -p "$T/bin" && ln -s "$HERE/testdata/gh" "$T/bin/gh"
export PATH="$T/bin:$PATH"
. "$HERE/testdata/engine-session.sh"
mkdir "$T/repo" && cd "$T/repo" && git init -q && git remote add origin https://github.com/acme/widgets.git
ln -s "$REPO_ROOT" "$T/plugin"
sessions() { koto session list 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' '; }
if ! koto_store_ready; then
    echo "SKIP: this koto lacks the session store's features, so every start is refused before a carry"; exit 0
fi
# state_json and session_keys as testdata/test-lib.sh has them (session_seed
# needs both); this suite doesn't source test-lib.sh, which puts the koto
# stand-in first on PATH.
state_json() { printf '%s' "$1" | jq -c -L "$HERE" --arg w "${2:-2026-09-26T09:00:00Z}" 'include "state-schema"; normalize_state([]) | .written = $w'; }
session_keys() {
    local pair field key
    jq -c '{scope, store: "session", written, pending: false}' "$2" | koto context add "$1" record/meta
    for pair in $ES_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        jq -e --arg f "$field" 'has($f)' "$2" > /dev/null || continue
        jq -c --arg f "$field" '.[$f]' "$2" | koto context add "$1" "record/$key"
    done
}

REAL_KOTO=$(command -v koto)
mkdir -p "$T/wshim" "$T/plugin2"
cat > "$T/wshim/koto" <<EOF
#!/bin/sh
printf 'W=%s %s\n' "\${KOTO_WRITE_WINDOW:--}" "\$*" >> "$T/wcalls"
if [ -n "\${WF_FAIL:-}" ] && [ "\$1 \$2" = "session flush" ] && [ "\$3" != --help ]; then
    echo "koto: the push of session \$3 failed: the bucket could not be reached" >&2
    exit 1
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/wshim/koto"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin2/"
printf '\n<!-- a change to the template, for the carry case -->\n' >> "$T/plugin2/skills/coordinate/koto-templates/coordinate.md"
jq '.compat += 1' "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json" > "$T/plugin2/skills/coordinate/koto-templates/coordinate.compat.json"
RMW='["docs/roadmaps/ROADMAP-window.md"]'
open_w() { # open_w [fail]: a start from the plugin copy behind the shim; output in $T/out, calls in $T/wcalls
    printf '%s' "$RMW" > "$T/args.json"
    : > "$T/wcalls"
    WF_FAIL=${1-} PATH="$T/wshim:$PATH" bash "$T/plugin2/skills/coordinate/scripts/coordinate-open.sh" \
        --plugin-root "$T/plugin2" "$T/args.json" > "$T/out" 2>"$T/err"
}
live_window() { bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-window --all 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
cancelled() { jq -s '[.[] | select(.type == "workflow_cancelled")] | length' "$(koto session dir "$1")/koto-$1.state.jsonl"; }
opened_by() { jq -nr --arg b "$1" --arg a "$(sessions)" '($a | split(" ")) - ($b | split(" ")) | map(select(. != "")) | join(" ")'; }
keys() { koto context list "$1" --prefix "$2" 2>/dev/null | jq -r '.[]' | tr '\n' ' '; }

# The scope's live run, holding a record with a few entries and legs/ keys.
printf '%s' "$RMW" > "$T/args.json"
OUT=$(bash "$T/plugin/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$T/plugin" "$T/args.json" 2>"$T/err")
WS=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
session_seed "$WS" "$(jq -nc '{scope: {kind: "roadmap", name: "window"}, holdings: [], deferrals: [], side_effects: [], reversals: []}')"
for i in 1 2 3; do
    printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" \
        | koto context add "$WS" "record/entries/00000$i"
    printf '{"leg":"work-on","result":{"pr":"https://github.com/acme/widgets/pull/%d"}}' "$i" \
        | koto context add "$WS" "legs/req-$i/work-on/result.json"
done
printf '{"source":"session"}' | koto context add "$WS" coord/source.json
eq "a live run of the scope holds its record" "$WS" "$(live_window)"
SRC_META=$(koto context get "$WS" record/meta)
SRC_KEYS="$(keys "$WS" record/)$(keys "$WS" legs/)"

if ! koto session flush --help > /dev/null 2>&1; then
    sleep 1
    open_w; rc=$?
    eq "on a koto without session flush, a carry lands" "0 carried=$WS" "$rc $(grep '^carried=' "$T/out")"
    eq "  ... with no call carrying KOTO_WRITE_WINDOW" 0 "$(grep -vc '^W=- ' "$T/wcalls")"
    echo; echo "coordinate-open-carry-window engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit $?
fi

echo "== a carry whose flush fails =="
sleep 1
BEFORE=$(sessions)
open_w 1; rc=$?
NW=$(opened_by "$BEFORE")
eq "a carry whose write window doesn't flush is failed=carry, exit 1" "1 failed=carry" "$rc $(grep '^failed=' "$T/out")"
grep -q "failed closing its write window: .*the bucket could not be reached" "$T/err" \
    && pass "  ... saying so, with koto's message" || fail "  ... saying so, with koto's message" "$(cat "$T/err")"
eq "  ... after adds made in the window" 1 "$([ -n "$NW" ] && [ "$(grep -c "^W=$NW context add $NW " "$T/wcalls")" -gt 0 ] && echo 1)"
eq "  ... and writing no record/meta into the new run" 0 "$(grep -c "context add $NW record/meta" "$T/wcalls")"
eq "  ... the new run cancelled" 1 "$( [ -n "$NW" ] && cancelled "$NW")"
koto context exists "$NW" record/meta; eq "  ... holding no record" 1 $?
eq "  ... the source still live and uncancelled" "$WS 0" "$(live_window) $(cancelled "$WS")"
eq "  ... its record/meta as it was" "$SRC_META" "$(koto context get "$WS" record/meta)"
eq "  ... and its keys" "$SRC_KEYS" "$(keys "$WS" record/)$(keys "$WS" legs/)"

echo "== a carry that lands in one window =="
sleep 1
open_w; rc=$?
NW=$(sed -n 's/^session=//p' "$T/out")
eq "a carry whose window flushes opens the new run" "0 carried=$WS" "$rc $(grep '^carried=' "$T/out")"
ADDS=$(grep -c "^W=[^ ]* context add $NW \(record/\|legs/\)" "$T/wcalls")
eq "  ... every add of a key into the new run carries KOTO_WRITE_WINDOW set to it" "$((ADDS - 1))" \
    "$(grep -c "^W=$NW context add $NW " "$T/wcalls")"
eq "  ... and no other call carries it" 0 "$(grep -v '^W=- ' "$T/wcalls" | grep -vc "^W=$NW context add $NW ")"
LAST=$(grep -n "^W=$NW " "$T/wcalls" | tail -1 | cut -d: -f1)
FLUSH=$(grep -n "^W=- session flush $NW\$" "$T/wcalls" | cut -d: -f1)
META=$(grep -n "^W=- context add $NW record/meta " "$T/wcalls" | cut -d: -f1)
eq "  ... one flush of the new run, right after the last add" "$((LAST + 1))" "$FLUSH"
eq "  ... and record/meta after it, without the variable" 1 "$([ -n "$META" ] && [ "$META" -gt "$FLUSH" ] && echo 1)"
eq "  ... the new run's record/meta at the source's written time" "$(jq -r .written <<<"$SRC_META")" \
    "$(koto context get "$NW" record/meta | jq -r .written)"
eq "  ... and every key of the source in it" "$SRC_KEYS" "$(keys "$NW" record/)$(keys "$NW" legs/)"
eq "  ... the source cancelled after it" "carried=$WS|cancelled=$WS" "$(grep -E '^(carried|cancelled)=' "$T/out" | tr '\n' '|' | sed 's/|$//')"

echo; echo "coordinate-open-carry-window engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
