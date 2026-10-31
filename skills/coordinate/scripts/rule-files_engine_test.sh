#!/usr/bin/env bash
# rule-files_engine_test.sh -- the Run section's `rules` digests every start
# writes: rule-files.sh's list of the skill's and the workspace's files, written
# by state-stored-set.sh --rule-files from coordinate-open.sh and
# state-open.sh, and read back by --rules, on real koto sessions of the
# shipped coordinate.md, against the testdata/gh stand-in
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# The plugin tree (.claude-plugin/, skills/, scripts/) is copied into the
# scratch directory twice, and every run is opened from a copy with
# --plugin-root naming it, so editing a skill file never touches the checkout.
# The workspace is built under the scratch HOME: the working directory
# $HOME/ws/inst/repo holds CLAUDE.md, $HOME/ws/inst holds CLAUDE.local.md and
# .claude/rules/imports.md (and two rules files whose labels break the
# grammar), and $HOME and $HOME/.claude each hold a CLAUDE.md of their own.
# Prints one line per criterion:
#   1. a fresh roadmap start (the opener, then state-open.sh as the find runs
#      it) leaves exactly eleven `rules` rows, the eight skill- labels and the
#      three workspace ones, each digest its file's sha256, none for either
#      home-directory file;
#   2. record/host holds rules:<label> for each of the eleven, its file's
#      absolute path, and no other rules: key;
#   3. `two words.md` and a rules file whose label would pass 64 bytes get no
#      row and no rules: key, are named on the opener's stderr, and the start
#      still prints session= and exits 0;
#   4. a resume with no file changed appends no entry, leaves record/meta's
#      written time, the Run section and record/host byte-identical, and
#      prints no warning= line;
#   5. after SKILL.md in the plugin copy and the working directory's CLAUDE.md
#      are edited and the copy's manifest version raised, the next start
#      replaces exactly those two rows, leaves the other nine byte-identical
#      (Set included), and appends one run entry naming both labels with
#      their old and new digests;
#   6. after .claude/rules/imports.md is deleted, the next start removes its
#      row and its rules: key and its entry names the label removed, while a
#      `rules notes` row written with --run rules, its rules:notes key and the
#      briefs row stay byte-identical through every start;
#   7. a takeover (the opener as a second Claude session, outcome=continued)
#      leaves the successor's rows naming the files it loaded from its own
#      plugin root and working directory, and the predecessor's record/run
#      and record/host byte-identical;
#   8. --rules prints the Standing objects byte-identical to the same record
#      with its rules rows taken out, then one object per Run rules row in
#      record order (kind skill, workspace or other), and --rules --id s1 only
#      s1's object;
#   9. with the plugin copy's SKILL.md unreadable the opener prints session=,
#      exits 0 and then warning=rules-unrecorded, the reason on stderr, and no
#      skill- row is written; the next start, the file readable again, writes
#      all eight;
#  11. scripts/check-template-compat.sh passes against the base branch's
#      coordinate.compat.json, compat unchanged.
# Criterion 10, the skill list read from SKILL.md's Reference Files table, is
# rule-files_test.sh's, offline.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there before the
# first koto command, or the suite stops.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure. On a koto without
# `koto init --supersede` criterion 7 is left out with a line naming it.
# Usage: bash skills/coordinate/scripts/rule-files_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
. "$HERE/testdata/takeover-flags.sh"
export KOTO_HOME="$HOME/.koto"
case "$(koto session dir probe 2>&1)" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory is not under $T: [$(koto session dir probe 2>&1)]; no case ran"; exit 1 ;;
esac
# niwa is never the real one: --rules may read the session's grant, so a fake
# niwa in the scratch directory, first on PATH, logs its arguments and answers
# not-dispatched.
mkdir -p "$T/fake"
cat > "$T/fake/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
printf '%s\n' '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"no-mapping","grant":[]}'
EOF
chmod +x "$T/fake/niwa"
export PATH="$T/fake:$PATH"
unset NIWA_BIN NIWA_LOOKUP_SECONDS

# One line per criterion: need records what failed, crit keeps the line under
# its number and report prints them in order.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { local n=${1%%.*}; printf -v "CM_$n" '%s' "$1"; printf -v "CW_$n" '%s' "$WHY"; WHY=; }
report() {
    local n m w
    for n in 1 2 3 4 5 6 7 8 9 11; do
        m="CM_$n" w="CW_$n"
        [ -n "${!m-}" ] || { [ "$n" = 7 ] && [ "$TAKEOVER_FLAGS" = 0 ] && continue; bad "criterion $n" "no case reached it"; continue; }
        if [ -z "${!w}" ]; then ok "${!m}"; else bad "${!m}" "${!w#; }"; fi
    done
}
stop() { bad "$1" "${2-}"; done_tests rule-files-engine; exit 1; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1; else shasum -a 256 < "$1" | cut -d' ' -f1; fi; }

# ---- the plugin copies and the workspace -------------------------------------
# PA is the copy run A and run F open from; PB the copy the takeover's second
# session opens from.
PA="$T/plugin-a" PB="$T/plugin-b"
mkdir -p "$PA" "$PB"
cp -R "$REPO_ROOT/.claude-plugin" "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$PA/" || stop "the plugin tree is copied" ""
cp -R "$REPO_ROOT/.claude-plugin" "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$PB/" || stop "the plugin tree is copied again" ""
SKA="$PA/skills/coordinate"
INST="$HOME/ws/inst"
WS="$INST/repo"
WS_B="$HOME/ws/inst-b/repo"
for d in "$WS" "$WS_B"; do
    mkdir -p "$d"
    (cd "$d" && git init -q && git remote add origin https://github.com/acme/widgets.git) || stop "the working directory $d is a clone" ""
done
mkdir -p "$INST/.claude/rules" "$HOME/.claude"
printf 'The repository rules.\n' > "$WS/CLAUDE.md"
printf 'The instance rules.\n' > "$INST/CLAUDE.local.md"
printf '@an-import.md\n' > "$INST/.claude/rules/imports.md"
printf 'A label with a space.\n' > "$INST/.claude/rules/two words.md"
LONG=rules-file-whose-name-runs-on-past-the-sixty-four-bytes-a-label-may-hold
printf 'A label over 64 bytes.\n' > "$INST/.claude/rules/$LONG.md"
printf 'The person'"'"'s own rules.\n' > "$HOME/CLAUDE.md"
printf 'The person'"'"'s own rules, again.\n' > "$HOME/.claude/CLAUDE.md"
printf 'The second session'"'"'s repository rules.\n' > "$WS_B/CLAUDE.md"

# Synthetic Claude session ids, built here so no id-shaped literal ships. B's
# job names it coord-b; A has no job, so it can't tell itself from a driver
# and a run nobody took over is its own.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/job-b"
jq -n --arg s "$B_ID" '{sessionId: $s, name: "coord-b", state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-b/state.json"

# ---- helpers -------------------------------------------------------------------
# opener <roadmap name> <workdir> <plugin root>: coordinate-open.sh as the agent
# runs it; OUT its stdout, ORC its exit, $T/open.err its stderr.
opener() {
    printf '["docs/roadmaps/ROADMAP-%s.md"]' "$1" > "$T/args.json"
    OUT=$(cd "$2" && bash "$3/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$3" "$T/args.json" 2>"$T/open.err"); ORC=$?
}
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
# next_at <session> [koto next args]: one advance from WS, the state it lands on.
next_at() { local s=$1; shift; (cd "$WS" && koto next "$s" "$@" --no-cleanup 2>"$T/tick.err") | jq -r '.state // empty'; }
ctx() { (cd "$WS" && koto context get "$1" "$2" 2>/dev/null); }
put() { (cd "$WS" && koto context add "$1" "$2" --from-file "$3" >/dev/null); }
agent() { local s=$1 x=$2; shift 2; (cd "$WS" && bash "$SKA/scripts/$x" --session "$s" "$@"); }
entries() { agent "$1" state-entry.sh --list 2>/dev/null; }
# rules_values <session>: the Run rules rows' values, in record order, one per line.
rules_values() { ctx "$1" record/run | jq -r 'arrays | .[] | select(.key == "rules") | .value'; }
# host_rules <session>: record/host's rules: keys, `<label> <path>` one per line, sorted.
host_rules() { ctx "$1" record/host | jq -r 'to_entries[] | select(.key | startswith("rules:")) | "\(.key | ltrimstr("rules:")) \(.value)"' | LC_ALL=C sort; }
# want_files: the eleven files run A loads, `<label> <path>` in rule-files.sh's order.
want_files() {
    local r
    printf 'skill-SKILL.md %s\n' "$SKA/SKILL.md"
    printf 'skill-coordinate.md %s\n' "$SKA/koto-templates/coordinate.md"
    for r in loop brief-template verification-checklist state-keys landing-milestone-roadmap landing-feature-roadmap; do
        printf 'skill-%s.md %s\n' "$r" "$SKA/references/$r.md"
    done
    printf 'workspace-0-CLAUDE.md %s\n' "$WS/CLAUDE.md"
    printf 'workspace-1-CLAUDE.local.md %s\n' "$INST/CLAUDE.local.md"
    [ -f "$INST/.claude/rules/imports.md" ] && printf 'workspace-1-rules-imports.md %s\n' "$INST/.claude/rules/imports.md"
    return 0
}
# want_values: want_files' rows as the Run section holds them.
want_values() { want_files | while read -r l p; do printf '%s sha256:%s\n' "$l" "$(sha "$p")"; done; }

db_init
for n in rulefiles rulefiles-unread; do seed_roadmap "$n"; done
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"

# ---- 1, 2: the fresh start -----------------------------------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
opener rulefiles "$WS" "$PA"
A=$(line session)
[ "$ORC" = 0 ] && [ -n "$A" ] || stop "run A opens" "$OUT $(cat "$T/open.err")"
need "the fresh start, which holds no record yet, prints no warning" "" "$(line warning)"
[ "$(next_at "$A")" = record_open ] || stop "run A's find reads no record" "$(cat "$T/tick.err")"
(cd "$WS" && bash "$SKA/scripts/state-open.sh" --session "$A") > "$T/so.out" 2> "$T/so.err"
need "state-open.sh opens the record" "0 $A" "$? $(sed -n 's/^record=//p' "$T/so.out")"
need "  ... with no warning" "" "$(sed -n 's/^warning=//p' "$T/so.out")"
need "the Run section holds exactly the eleven rows, each digest its file's" "$(want_values)" "$(rules_values "$A")"
grep -qF "$HOME/CLAUDE.md" <<< "$(ctx "$A" record/host)" && needf "the home directory's CLAUDE.md has a host key"
grep -qF "$HOME/.claude/CLAUDE.md" <<< "$(ctx "$A" record/host)" && needf "\$HOME/.claude/CLAUDE.md has a host key"
need "  ... set by the run's session name" "$A" "$(ctx "$A" record/run | jq -r '[.[] | select(.key == "rules") | .set_by] | unique | join(" ")')"
crit "1. a fresh roadmap start leaves exactly the eleven rules rows (eight skill-, three workspace-), each its file's sha256, none for a home-directory file"
need "record/host holds rules:<label> for each of the eleven, its file's path, and no other" "$(want_files | LC_ALL=C sort)" "$(host_rules "$A")"
crit "2. record/host holds rules:<label> for each of the eleven labels, its file's absolute path, and no other rules: key"

# The run's find reads the record; then a person's rules row, its host key, a
# briefs row, the coordinator's address and one Standing row, through today's
# writers.
ST=$(next_at "$A" --with-data '{"opened":"opened"}')
case "$ST" in ''|record_open|record_conflict) stop "run A's find reads the record" "$ST $(cat "$T/tick.err")" ;; esac
DN=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
agent "$A" state-stored-set.sh --run rules "notes sha256:$DN" --by "the human" > /dev/null 2> "$T/w.err" \
    && agent "$A" state-stored-set.sh --host rules:notes "$HOME/notes.md" > /dev/null 2>> "$T/w.err" \
    && agent "$A" state-stored-set.sh --run briefs "brief-1 sha256:$DN" --by "the human" > /dev/null 2>> "$T/w.err" \
    && agent "$A" state-stored-set.sh --run coordinator coord-a --by coord-a > /dev/null 2>> "$T/w.err" \
    && agent "$A" state-stored-set.sh --standing approval --what "the release notes as drafted" --owner "the human" > /dev/null 2>> "$T/w.err" \
    || stop "today's writers write a notes row, its host key, a briefs row, the address and s1" "$(cat "$T/w.err")"
# kept <session>: the rows and key no start owns: the notes row, its host key
# and the briefs row, as stored.
kept() { ctx "$1" record/run | jq -c '[.[] | select((.key == "rules" and (.value | startswith("notes "))) or .key == "briefs")]'; ctx "$1" record/host | jq -c '.["rules:notes"]'; }
KEPT=$(kept "$A")
[ "$(jq length <<< "${KEPT%%$'\n'*}")" = 2 ] || stop "the notes and briefs rows are written" "$KEPT"

# ---- 3, 4: a resume with nothing changed ---------------------------------------
N_BEFORE=$(entries "$A" | jq length)
META_W=$(ctx "$A" record/meta | jq -r .written)
RUN_BEFORE=$(ctx "$A" record/run); HOST_BEFORE=$(ctx "$A" record/host)
opener rulefiles "$WS" "$PA"
need "the second start resumes A and exits 0" "0 resumed $A" "$ORC $(line outcome) $(line session)"
grep -qF "two words.md" "$T/open.err" || needf "the opener's stderr doesn't name two words.md: $(cat "$T/open.err")"
grep -qF "$LONG.md" "$T/open.err" || needf "the opener's stderr doesn't name the long file: $(cat "$T/open.err")"
LEFT=$(rules_values "$A"; host_rules "$A")
grep -qE "two words|$LONG" <<< "$LEFT" && needf "a left-out file has a row or a host key"
crit "3. two words.md and a file whose label would pass 64 bytes get no row and no rules: key, are named on the opener's stderr, and the start prints session= and exits 0"
need "the resume appends no entry" "$N_BEFORE" "$(entries "$A" | jq length)"
need "  ... leaves record/meta's written time" "$META_W" "$(ctx "$A" record/meta | jq -r .written)"
need "  ... the Run section byte-identical" "$RUN_BEFORE" "$(ctx "$A" record/run)"
need "  ... record/host byte-identical" "$HOST_BEFORE" "$(ctx "$A" record/host)"
need "  ... and prints no warning" "" "$(line warning)"
need "  ... the notes and briefs rows kept" "$KEPT" "$(kept "$A")"
crit "4. a resume with no file changed appends no entry, leaves record/meta's written time, the Run section and record/host byte-identical, and prints no warning"

# ---- 5: two files edited -------------------------------------------------------
row_of() { ctx "$1" record/run | jq -c --arg l "$2" '.[] | select(.key == "rules" and (.value | startswith($l + " ")))'; }
OLD_SKILL=$(sha "$SKA/SKILL.md") OLD_WS=$(sha "$WS/CLAUDE.md")
OTHERS=$(ctx "$A" record/run | jq -c '[.[] | select(.key == "rules" and (.value | test("^(skill-SKILL\\.md|workspace-0-CLAUDE\\.md|notes) ") | not))]')
printf '\nOne more line of the skill.\n' >> "$SKA/SKILL.md"
printf 'One more repository rule.\n' >> "$WS/CLAUDE.md"
jq '.version = "99.0.0"' "$PA/.claude-plugin/plugin.json" > "$T/plugin.json" && cp "$T/plugin.json" "$PA/.claude-plugin/plugin.json"
N_BEFORE=$(entries "$A" | jq length)
opener rulefiles "$WS" "$PA"
need "the next start resumes A, with no warning" "0 resumed $A " "$ORC $(line outcome) $(line session) $(line warning)"
NEW_SKILL=$(sha "$SKA/SKILL.md") NEW_WS=$(sha "$WS/CLAUDE.md")
need "SKILL.md's row carries its new digest" "skill-SKILL.md sha256:$NEW_SKILL $A" "$(row_of "$A" skill-SKILL.md | jq -r '"\(.value) \(.set_by)"')"
need "the working directory's CLAUDE.md row carries its new digest" "workspace-0-CLAUDE.md sha256:$NEW_WS" "$(row_of "$A" workspace-0-CLAUDE.md | jq -r .value)"
need "the other nine rows are byte-identical, Set included" "$OTHERS" \
    "$(ctx "$A" record/run | jq -c '[.[] | select(.key == "rules" and (.value | test("^(skill-SKILL\\.md|workspace-0-CLAUDE\\.md|notes) ") | not))]')"
need "  ... nine of them" 9 "$(printf '%s' "$OTHERS" | jq length)"
NEW=$(entries "$A" | jq -c --argjson n "$N_BEFORE" '.[$n:]')
need "one entry is appended, of kind run" "1 run" "$(printf '%s' "$NEW" | jq -r '"\(length) \(.[0].kind)"')"
TXT=$(printf '%s' "$NEW" | jq -r '.[0].text')
for want in "skill-SKILL.md sha256:$OLD_SKILL to sha256:$NEW_SKILL" "workspace-0-CLAUDE.md sha256:$OLD_WS to sha256:$NEW_WS"; do
    grep -qF "$want" <<< "$TXT" || needf "the entry doesn't name $want: $TXT"
done
need "  ... the notes and briefs rows kept" "$KEPT" "$(kept "$A")"
crit "5. after SKILL.md and the working directory's CLAUDE.md are edited, the next start replaces exactly those two rows, keeps the other nine byte-identical, and appends one run entry naming both with old and new digests"

# ---- 6: a file deleted ---------------------------------------------------------
rm "$INST/.claude/rules/imports.md"
N_BEFORE=$(entries "$A" | jq length)
opener rulefiles "$WS" "$PA"
need "the next start resumes A, with no warning" "0 resumed $A " "$ORC $(line outcome) $(line session) $(line warning)"
need "imports.md's row is gone" "" "$(row_of "$A" workspace-1-rules-imports.md)"
need "  ... and its rules: key" null "$(ctx "$A" record/host | jq -c '.["rules:workspace-1-rules-imports.md"]')"
need "the Run section holds the ten files' rows" "$(want_values)" "$(rules_values "$A" | grep -v '^notes ')"
NEW=$(entries "$A" | jq -c --argjson n "$N_BEFORE" '.[$n:]')
need "one run entry" "1 run" "$(printf '%s' "$NEW" | jq -r '"\(length) \(.[0].kind)"')"
grep -qF "removed workspace-1-rules-imports.md" <<< "$(printf '%s' "$NEW" | jq -r '.[0].text')" \
    || needf "the entry doesn't name the label as removed: $(printf '%s' "$NEW" | jq -r '.[0].text')"
need "the notes row, its rules:notes key and the briefs row are byte-identical through every start" "$KEPT" "$(kept "$A")"
crit "6. after imports.md is deleted the next start removes its row and rules: key and its entry names it removed; the notes row, its host key and the briefs row stay byte-identical"

# ---- 8: --rules ----------------------------------------------------------------
# The same record with its rules rows taken out, read, then put back.
ctx "$A" record/run > "$T/run.saved"
jq -c 'map(select(.key != "rules"))' "$T/run.saved" > "$T/run.norules"
put "$A" record/run "$T/run.norules" && agent "$A" state-stored-set.sh --rules > "$T/rules.none" 2> "$T/rules.err" \
    || needf "--rules on the record without rules rows fails: $(cat "$T/rules.err")"
put "$A" record/run "$T/run.saved"
need "the record's Run section is put back as it was" "$(cat "$T/run.saved")" "$(ctx "$A" record/run)"
agent "$A" state-stored-set.sh --rules > "$T/rules.with" 2> "$T/rules.err" || needf "--rules fails: $(cat "$T/rules.err")"
need "without rules rows --rules prints only s1's object" "s1" "$(jq -r '.standing // "run"' "$T/rules.none" | tr '\n' ' ' | sed 's/ $//')"
jq -c 'select(has("run") | not)' "$T/rules.with" > "$T/rules.with.standing"
cmp -s "$T/rules.none" "$T/rules.with.standing" || needf "the Standing objects differ: [$(cat "$T/rules.none")] vs [$(cat "$T/rules.with.standing")]"
need "the Standing objects come first" "s1" "$(head -1 "$T/rules.with" | jq -r '.standing // "run"')"
want_files | while read -r l p; do
    case "$l" in skill-*) k=skill ;; *) k=workspace ;; esac
    jq -nc --arg k "$k" --arg l "$l" --arg d "sha256:$(sha "$p")" '{run: "rules", kind: $k, label: $l, digest: $d}'
done > "$T/rules.want"
jq -nc --arg d "sha256:$DN" '{run: "rules", kind: "other", label: "notes", digest: $d}' >> "$T/rules.want"
need "then one object per Run rules row in record order, each with its kind" "$(jq -s -S -c . "$T/rules.want")" \
    "$(jq -s -S -c '[.[] | select(has("run"))]' "$T/rules.with")"
agent "$A" state-stored-set.sh --rules --id s1 > "$T/rules.s1" 2> "$T/rules.err"
need "--rules --id s1 prints only s1's object" "0 1 s1" "$? $(jq -s length "$T/rules.s1") $(jq -r .standing "$T/rules.s1")"
crit "8. --rules prints the Standing objects as on the record without rules rows, then one object per Run rules row in record order with its kind; --rules --id s1 prints only s1's"

# ---- 7: a takeover --------------------------------------------------------------
if needs_takeover "7: a takeover writes the successor's own rows"; then
    PRED_RUN=$(ctx "$A" record/run) PRED_HOST=$(ctx "$A" record/host)
    export CLAUDE_CODE_SESSION_ID=$B_ID
    opener rulefiles "$WS_B" "$PB"
    B=$(line session)
    need "the opener as a second Claude session takes A over" "0 continued $A" "$ORC $(line outcome) $(line predecessor)"
    need "  ... with no warning" "" "$(line warning)"
    (cd "$WS_B" && bash "$PB/skills/coordinate/scripts/rule-files.sh" --plugin-root "$PB") > "$T/b.files" 2> /dev/null
    need "the successor's rows name the files it loaded from its own plugin root and working directory" \
        "$(jq -r '"\(.label) sha256:\(.digest)"' "$T/b.files")" "$(rules_values "$B" | grep -v '^notes ')"
    need "  ... nine of them" 9 "$(jq -s length "$T/b.files")"
    need "  ... its host keys their paths" "$( { jq -r '"\(.label) \(.path)"' "$T/b.files"; echo "notes $HOME/notes.md"; } | LC_ALL=C sort)" "$(host_rules "$B")"
    need "  ... the notes and briefs rows carried and kept" "$KEPT" "$(kept "$B")"
    need "the predecessor's record/run is byte-identical" "$PRED_RUN" "$(ctx "$A" record/run)"
    need "  ... and its record/host" "$PRED_HOST" "$(ctx "$A" record/host)"
    crit "7. a takeover leaves the successor's rules rows naming the files it loaded from its own plugin root and working directory, and the predecessor's record/run and record/host byte-identical"
    export CLAUDE_CODE_SESSION_ID=$A_ID
fi

# ---- 9: an unreadable SKILL.md --------------------------------------------------
chmod 000 "$SKA/SKILL.md"
if [ -r "$SKA/SKILL.md" ]; then
    echo "     (this user reads a mode-000 file: criterion 9's unreadable SKILL.md can't be made)"
    chmod 644 "$SKA/SKILL.md"
    crit "9. an unreadable SKILL.md (not checked: this user reads a mode-000 file)"
else
    opener rulefiles-unread "$WS" "$PA"
    F=$(line session)
    [ "$ORC" = 0 ] && [ -n "$F" ] || stop "run F opens" "$OUT $(cat "$T/open.err")"
    [ "$(next_at "$F")" = record_open ] || stop "run F's find reads no record" "$(cat "$T/tick.err")"
    (cd "$WS" && bash "$SKA/scripts/state-open.sh" --session "$F") > "$T/so.out" 2> "$T/so.err"
    need "state-open.sh opens F's record and warns" "0 $F rules-unrecorded" "$? $(sed -n 's/^record=//p' "$T/so.out") $(sed -n 's/^warning=//p' "$T/so.out")"
    ST=$(next_at "$F" --with-data '{"opened":"opened"}')
    case "$ST" in ''|record_open|record_conflict) stop "run F's find reads the record" "$ST $(cat "$T/tick.err")" ;; esac
    opener rulefiles-unread "$WS" "$PA"
    need "the opener prints session= and exits 0" "0 $F" "$ORC $(line session)"
    need "  ... then warning=rules-unrecorded" "session=$F warning=rules-unrecorded" "$(printf '%s\n' "$OUT" | grep -E '^(session|warning)=' | tr '\n' ' ' | sed 's/ $//')"
    grep -q "SKILL.md" "$T/open.err" || needf "the reason on stderr doesn't name SKILL.md: $(cat "$T/open.err")"
    need "  ... and the Run section holds no skill- row" 0 "$(rules_values "$F" | grep -c '^skill-')"
    chmod 644 "$SKA/SKILL.md"
    opener rulefiles-unread "$WS" "$PA"
    need "the next start, SKILL.md readable, warns of nothing" "0 $F " "$ORC $(line session) $(line warning)"
    need "  ... and writes all eight skill- rows" "$(want_values | grep '^skill-')" "$(rules_values "$F" | grep '^skill-')"
    crit "9. with SKILL.md unreadable the opener prints session=, exits 0 and warning=rules-unrecorded with the reason on stderr, writing no skill- row; the next start writes all eight"
fi

# ---- 11: the compat table --------------------------------------------------------
# The base branch's table, origin/main's (or main's). A checkout holding
# neither (a shallow clone) still checks that the table records this
# template's structure and gate scripts digest, and says it had no base.
BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q origin/main 2>/dev/null) || BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q main 2>/dev/null) || BASE=
CARGS=(--template skills/coordinate/koto-templates/coordinate.md)
if [ -n "$BASE" ]; then
    git -C "$REPO_ROOT" show "$BASE:skills/coordinate/koto-templates/coordinate.compat.json" > "$T/base.compat.json" 2> "$T/base.err" \
        || needf "the base's coordinate.compat.json can't be read: $(cat "$T/base.err")"
    CARGS+=(--base-table "$T/base.compat.json")
    need "  ... compat unchanged from the base's" "$(jq -c .compat "$T/base.compat.json" 2>/dev/null)" \
        "$(jq -c .compat "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json")"
else
    echo "     (no origin/main or main in this checkout: the compat check runs without a base table)"
fi
(cd "$REPO_ROOT" && bash scripts/check-template-compat.sh "${CARGS[@]}") > "$T/compat.out" 2>&1
rc=$?
[ "$rc" = 0 ] || needf "scripts/check-template-compat.sh exits $rc: $(cat "$T/compat.out")"
crit "11. scripts/check-template-compat.sh passes against the base branch's coordinate.compat.json, compat unchanged, the gate scripts digest recorded"

report
done_tests rule-files-engine
