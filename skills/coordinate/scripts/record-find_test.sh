#!/usr/bin/env bash
# record-find_test.sh -- record-find.sh reads the record from the run's own
# koto session, and nothing on GitHub.
#
# Covers, at roadmap scope: a session holding a canonical record (with and
# without a Decisions section) is found; one declared for another roadmap is
# malformed; a state that breaks a rule of the schema is malformed too, and a
# key that isn't JSON is a failed read (exit 2); a session holding no record is none, unless another session
# of the scope on this host holds one, which is malformed (session-absent), a
# stop rather than a second record. At discipline scope a run holding no record
# with no earlier rotation is first (discipline-session_test.sh covers the
# predecessor). The find makes no GitHub call. Also the sealed token, its
# context detail, coord/source.json reading session (what the resume candidate
# keys on), record_url naming the session, and facts read from the session.
#
# Usage: bash skills/coordinate/scripts/record-find_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
F="$HERE/record-find.sh"

S=coordinate-roadmap-plugin-system-20260926T080000Z
export RS_SESSION=$S
RM=(--scope roadmap --name plugin-system --repo "$REPO" --no-seal)
DS=(--scope discipline --name ci-health --repo "$REPO" --today 2026-09-26 --no-seal)
find_rm() { local o rc; o=$(bash "$F" "${RM[@]}" 2>"$T/err"); rc=$?; [ -z "$o" ] || seen "$o"; return $rc; }
fresh() { db_init; rm -rf "$KOTO_STORE/context" "$KOTO_STORE/sessions"; mkdir -p "$KOTO_STORE/sessions"; }

echo "== roadmap: the run's session =="
fresh
eq "a session holding no record is none" none "$(find_rm)"
eq "  ... read without any GitHub call" "" "$(calls)"
seed_session "$S" "$(record_json roadmap plugin-system)"
eq "a session holding a canonical record is found" found "$(find_rm)"
seed_session "$S" "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding alpha)" '.holdings = [$h] | .decisions = {next: 3, entries: []}')"
eq "a record with Holdings and a Decisions section is found" found "$(find_rm)"
eq "  ... with no GitHub call" "" "$(calls)"
seed_session "$S" "$(record_json roadmap other)"
eq "a record declared for another roadmap is malformed" malformed "$(find_rm)"
grep -q "another scope" "$T/err" && ok "  ... naming it" || bad "  ... naming it" "$(cat "$T/err")"
seed_session "$S" "$(record_json roadmap plugin-system)"
printf '[{"unit": "Feature 2"}]' > "$KOTO_STORE/context/$S/record/holdings"
eq "a section that breaks a rule of the state's schema is malformed" malformed "$(find_rm)"
cat "$T/err" > "$T/err.rule"
grep -q "doesn't read back" "$T/err.rule" && ok "  ... naming that the record doesn't read back" || bad "  ... naming that the record doesn't read back" "$(cat "$T/err.rule")"
printf 'not json' > "$KOTO_STORE/context/$S/record/holdings"
find_rm > /dev/null; eq "a section that isn't JSON is a failed read" 2 $?

echo "== roadmap: another session holds the record =="
fresh
OLD=coordinate-roadmap-plugin-system-20260925T080000Z
log_new "$OLD" "$(roadmap_vars plugin-system)"
seed_session "$OLD" "$(record_json roadmap plugin-system)"
eq "another session of the scope holding the record stops the find" malformed "$(find_rm)"
grep -q "session-absent: session $OLD" "$T/err" && ok "  ... as session-absent, naming it" || bad "  ... as session-absent, naming it" "$(cat "$T/err")"
fresh
log_new coordinate-roadmap-other-20260925T080000Z "$(roadmap_vars other)"
seed_session coordinate-roadmap-other-20260925T080000Z "$(record_json roadmap other)"
eq "another scope's session is no holder" none "$(find_rm)"

echo "== discipline =="
fresh
SD=coordinate-discipline-ci-health-20260926T080000Z
eq "a rotation with no earlier one is the first" first "$(RS_SESSION=$SD bash "$F" "${DS[@]}" 2>"$T/err")"
eq "  ... with no GitHub call" "" "$(calls)"

echo "== sealing and session facts =="
fresh
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start_posture record_find
OUT=$(env -u RS_SESSION bash "$F" --session "$S" 2>"$T/err"); rc=$?
eq "a session run exits 0" 0 "$rc"
seen "$OUT" > /dev/null
case "$OUT" in "none sealed:"*) ok "the verdict is sealed" ;; *) bad "the verdict is sealed" "$OUT $(cat "$T/err")" ;; esac
bash "$HERE/coord-log.sh" check --session "$S" --state record_find --sealed "$OUT" && ok "the seal checks against the log" || bad "the seal checks against the log"
eq "the detail is stored as data, on the session store" "none|session" \
    "$(jq -r '"\(.verdict)|\(.store)"' "$KOTO_STORE/context/$S/coord/record_find.json" 2>&1)"
eq "coord/source.json reads session" session "$(jq -r .source "$KOTO_STORE/context/$S/coord/source.json" 2>&1)"
[ -e "$KOTO_STORE/context/$S/record_url" ] && bad "none writes no record_url" || ok "none writes no record_url"
seed_session "$S" "$(record_json roadmap plugin-system)"
log_to "$S" record_open record_find
OUT=$(env -u RS_SESSION bash "$F" --session "$S" 2>"$T/err"); rc=$?
seen "$OUT" > /dev/null
case "$rc $OUT" in "0 found sealed:"*) ok "the record the session holds is found, sealed" ;; *) bad "the record the session holds is found, sealed" "$rc $OUT $(cat "$T/err")" ;; esac
eq "the record's session goes to context key record_url, for the terminal results" "$S" "$(cat "$KOTO_STORE/context/$S/record_url" 2>&1)"
eq "coord/source.json still reads session" session "$(jq -r .source "$KOTO_STORE/context/$S/coord/source.json" 2>&1)"
log_capture "$S" RECORD_FIND "$OUT"
eq "run-facts reads the found record, with no number" '{"scope":"roadmap","name":"plugin-system","repo":"acme/widgets"}' \
    "$(bash "$HERE/coord-log.sh" run-facts --session "$S")"
eq "no GitHub call in either visit" "" "$(calls)"
bash "$F" --scope roadmap --name plugin-system --repo "$REPO" >/dev/null 2>&1; eq "sealing without a session is a usage error" 64 $?
bash "$F" --scope roadmap --name plugin-system >/dev/null 2>&1; eq "partial override flags are a usage error" 64 $?
bash "$F" --scope roadmap --name 'a b' --repo "$REPO" --no-seal >/dev/null 2>&1; eq "a bad name is a usage error" 64 $?
bash "$F" --scope roadmap --name plugin-system --repo "$REPO" --store session --no-seal >/dev/null 2>&1; eq "--store is a usage error" 64 $?

tokens_ok record-find
done_tests record-find
