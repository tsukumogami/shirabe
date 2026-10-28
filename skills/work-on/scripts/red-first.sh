#!/usr/bin/env bash
# red-first.sh -- for /work-on: a fix's red before its correcting change, its
# green after, or an observation pair in their place.
#
# references/red-first.md says what the records mean and when a run makes
# them. Everything here is written to one context key, `red_first.json`, and
# only by this script.
#
# Usage:
#   red-first.sh red <session> --marker <text> --passage-file <file>
#                    [--tests <path>...] [--timeout <secs>] -- <command> [<arg>...]
#   red-first.sh observe <session> --phase before|after --file <observation.md>
#   red-first.sh green <session> [--timeout <secs>]
#   red-first.sh check-red <session>
#   red-first.sh check-green <session>
#
#   red          runs <command> on the base code with the unit's tests applied
#                and records the red only when every condition holds:
#                  - the unit is recorded as a fix (fix-kind.sh)
#                  - the marker is at least 8 characters, the passage at least
#                    20, the marker is in the passage, and the passage is
#                    verbatim in the unit's report (`fix_report.txt`, which
#                    fix-kind.sh resolve stored: the plan step's Fixes line,
#                    the issue body or the task text). CRLF counts as LF.
#                  - the command exits non-zero, and its output holds the
#                    marker
#                The base is `impl_base`. A detached temporary worktree is
#                built there, and every test file the unit's committed diff
#                touched (scripts/lib/test-classify.sh, with the rules copy
#                review-level.sh init stored) is copied in from HEAD, so the
#                command runs on the base code with the unit's tests and none
#                of its other changes. The reproducing tests are those files,
#                or the existing tests named with --tests. A test file that is
#                a symlink at HEAD is refused, and so is one under a directory
#                that is a symlink at the base, which would carry the copy
#                outside the worktree. Paths among the command's words that
#                name files at the base are recorded as harness files. The
#                command runs with only PATH, HOME, LANG and TMPDIR in its
#                environment, stdin closed, in its own process group, killed
#                whole after --timeout seconds (default 600, at most 3600).
#                Each failed condition exits 1 with a `refused:` line naming
#                it and records nothing. A new red replaces an earlier one and
#                drops its green.
#   observe      records an observation in place of a red (before) or a green
#                (after), for a bug no automated check can reproduce. The file
#                is markdown whose `## ` sections are, for `before`: Produced
#                (how the failure was produced), Environment, Seen (what was
#                seen, with the marker), Why no check, Passage and Marker; for
#                `after`: Produced, Environment and Seen. A missing section is
#                refused naming it. A before-observation's passage and marker
#                meet the red's rules, and the marker is in Seen. An `after`
#                needs a `before`. The file's blob id is its digest.
#   green        runs the red's command at HEAD, in a detached temporary
#                worktree (committed changes only), and records the result:
#                head, exit, output tail, time. Exit 0 when the command
#                passed; exit 1 (`failed:`) when it didn't, with the failing
#                green recorded.
#   check-red    reproduce's red_recorded gate. Passes for a unit that isn't a
#                fix, and for a fix with a red or a before-observation.
#                Otherwise holds with finding red-first/no-red.
#   check-green  pass_counting's fix_green gate. Passes for a unit that isn't
#                a fix, for a fix whose green ran the red's command at HEAD
#                and exited 0, and for a fix recorded by an observation pair
#                that a live acceptance covers (test-change.sh covered). An
#                observation pair without one is held with a `refused:` line
#                saying observations wait for acceptance. Every hold prints
#                finding red-first/no-green.
#
# The record (`red_first.json`, schema shirabe-red-first/v1):
#   red           command (argv), base, head, tests and harness ([{path,
#                 blob}], the blob that ran), exit, output_tail (the last 40
#                 lines, at most 4096 bytes), marker_context (three lines
#                 either side of the first line holding the marker), passage,
#                 marker, report_source, timeout_secs, duration_secs, ran_at
#   observations  before and after: digest, text, head, recorded_at (and
#                 passage and marker on before)
#   green         command, head, exit, output_tail, ran_at
#
# The red's command is the agent's; this script doesn't sandbox it. The
# temporary worktree shares the repository's object store and the network;
# the environment allowlist keeps credential variables (GH_TOKEN,
# GITHUB_TOKEN, GIT_*) out of it by accident, not by containment.
#
# Exit codes:
#   0   recorded, or the gate passes
#   1   refused (a `refused:` line names the condition), a failing green
#       (`failed:`), or the gate holds (`hold:`, then a finding)
#   2   could not decide: no impl_base, no rules copy, the worktree could not
#       be built, the record doesn't parse, or the gate's rules don't resolve
#   64  usage
#   66  a koto context read or write failed
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT_SELF=$(cd "$HERE/../../.." && pwd)
RULE_IDS="red-first/no-red red-first/no-green"
SCHEMA=shirabe-red-first/v1
KEY=red_first.json
REPORT_KEY=fix_report.txt
RULES_KEY=review_level_rules.tsv
MARKER_MIN=8
PASSAGE_MIN=20
TAIL_LINES=40
TAIL_BYTES=4096
OBS_MAX=16384
TIMEOUT_DEFAULT=600
TIMEOUT_MAX=3600

show_errlog() {
    if [ -n "${ERRLOG:-}" ] && [ -s "$ERRLOG" ]; then
        echo "red-first: the tools' last diagnostics:" >&2
        tail -n 5 "$ERRLOG" >&2
    fi
}

undecided() {
    echo "red-first: $*" >&2
    show_errlog
    exit 2
}

usage() {
    echo "red-first: $1" >&2
    cat >&2 <<'EOF'
usage: red-first.sh red <session> --marker <text> --passage-file <file> [--tests <path>...] [--timeout <secs>] -- <command> [<arg>...]
       red-first.sh observe <session> --phase before|after --file <observation.md>
       red-first.sh green <session> [--timeout <secs>]
       red-first.sh check-red <session>
       red-first.sh check-green <session>
EOF
    exit 64
}

die66() {
    echo "red-first: $1" >&2
    show_errlog
    exit 66
}

refuse() {
    echo "refused: $1"
    exit 1
}

valid_session() {
    case "$1" in
        ""|-*|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

# safe_path <path>: repository-relative, no `..` segment, no leading `-` or `/`.
safe_path() {
    case "$1" in
        ""|-*|/*|..|../*|*/..|*/../*) return 1 ;;
    esac
    return 0
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/red-first.XXXXXX") || { echo "red-first: could not create a temporary directory" >&2; exit 2; }
# What the tools printed on stderr where a failure is expected (a key that
# doesn't exist yet, a probe), kept rather than discarded, and shown when the
# script gives up.
ERRLOG="$TMP/tool-stderr.log"
: > "$ERRLOG"
WT=""
cleanup() {
    if [ -n "$WT" ] && [ -d "$WT" ]; then
        git worktree remove --force "$WT" >/dev/null 2>>"$ERRLOG" || rm -rf "$WT"
        git worktree prune >/dev/null 2>>"$ERRLOG" || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

# ctx_has <session> <key>: 0 when the key is present, 1 when koto answers that
# it is absent, 2 when the read failed. koto's `context exists` answers an
# absent key with exit 1 and nothing on stdout; a refusal (a session bound to
# another workspace, say) prints its JSON on stdout and exits 2. An exit 1
# that prints anything is a failed read too, never an absent key. What koto
# prints goes to $ERRLOG, never to stdout.
ctx_has() {
    local rc=0
    koto context exists "$1" "$2" > "$TMP/exists.out" 2>>"$ERRLOG" || rc=$?
    cat "$TMP/exists.out" >> "$ERRLOG"
    case "$rc" in
        0) return 0 ;;
        1) [ -s "$TMP/exists.out" ] || return 1 ;;
    esac
    echo "koto context exists $1 $2 exited $rc" >> "$ERRLOG"
    return 2
}

# ctx_get <session> <key> <file>: the key's content into <file>, empty when the
# key is absent. Returns 1 when the read failed, with <file> empty.
ctx_get() {
    : > "$3"
    ctx_has "$1" "$2"
    case $? in
        0) ;;
        1) return 0 ;;
        *) return 1 ;;
    esac
    koto context get "$1" "$2" > "$3" 2>>"$ERRLOG" && return 0
    : > "$3"
    return 1
}

ctx_put() {
    koto context add "$1" "$2" < "$3" >/dev/null 2>>"$ERRLOG" || return 1
    koto context get "$1" "$2" > "$TMP/readback" 2>>"$ERRLOG" || return 1
    cmp -s "$3" "$TMP/readback"
}

# unit_kind <session>: the fix-kind ledger's kind, or nothing; 66 on a read failure.
unit_kind() {
    "$HERE/fix-kind.sh" kind "$1" 2>"$TMP/kind.err" || die66 "could not read the unit's kind: $(head -c 300 "$TMP/kind.err")"
}

# load_record <session>: the record into $TMP/record, an empty one when absent.
load_record() {
    ctx_get "$1" "$KEY" "$TMP/record" || die66 "could not read $KEY"
    if [ ! -s "$TMP/record" ]; then
        jq -n --arg s "$SCHEMA" '{schema: $s, red: null, observations: {}, green: null}' > "$TMP/record"
    fi
    jq -e --arg s "$SCHEMA" '.schema == $s' "$TMP/record" >/dev/null 2>>"$ERRLOG" \
        || undecided "$KEY is not a $SCHEMA record"
}

save_record() {
    ctx_put "$1" "$KEY" "$TMP/record.next" || die66 "could not write $KEY"
}

# crlf <file>: CRLF line endings to LF, in place.
crlf() {
    LC_ALL=C tr -d '\r' < "$1" > "$1.lf" && mv "$1.lf" "$1"
}

# check_passage <marker> <passage-file> <report-file>: refuses unless the
# marker and passage meet the red's rules against the report.
check_passage() {
    local marker="$1" passage
    case "$marker" in *"
"*) refuse "the marker spans more than one line" ;; esac
    [ "${#marker}" -ge "$MARKER_MIN" ] \
        || refuse "the marker [$marker] is ${#marker} characters; it needs at least $MARKER_MIN, so a bare word can't stand in for the report"
    passage=$(cat "$2")
    [ "${#passage}" -ge "$PASSAGE_MIN" ] \
        || refuse "the passage is ${#passage} characters; it needs at least $PASSAGE_MIN"
    case "$passage" in *"$marker"*) ;; *) refuse "the marker [$marker] is not in the passage" ;; esac
    [ -s "$3" ] || refuse "no report is stored for this unit ($REPORT_KEY); fix_determination stores it, so tick through it first"
    local report
    report=$(cat "$3")
    case "$report" in *"$passage"*) ;; *) refuse "the passage is not verbatim in the unit's report (the plan step's Fixes line, the issue body or the task text, as $REPORT_KEY holds it)" ;; esac
}

# tail_of <file>: the last lines of the output, capped.
tail_of() {
    tail -n "$TAIL_LINES" "$1" | tail -c "$TAIL_BYTES"
}

# marker_context <file> <marker>: three lines either side of the first line
# holding the marker, capped.
marker_context() {
    MARKER="$2" awk '
        { line[NR] = $0 }
        !hit && index($0, ENVIRON["MARKER"]) { hit = NR }
        END {
            if (!hit) exit
            a = hit - 3; if (a < 1) a = 1
            b = hit + 3; if (b > NR) b = NR
            for (i = a; i <= b; i++) print line[i]
        }' "$1" | head -c "$TAIL_BYTES"
}

# make_worktree <commit>: a detached temporary worktree at <commit> in $WT.
make_worktree() {
    WT="$TMP/wt"
    git worktree add --detach -q "$WT" "$1" >/dev/null 2>"$TMP/wt.err" \
        || { WT=""; undecided "could not build a temporary worktree at $1: $(head -c 300 "$TMP/wt.err")"; }
}

# run_bounded <timeout> <out-file> <argv...>: runs argv in $WT with the
# allowlisted environment, in its own process group, and sets RUN_EXIT,
# RUN_TIMED_OUT and RUN_SECS.
RUN_EXIT=0
RUN_TIMED_OUT=false
RUN_SECS=0
run_bounded() {
    local limit="$1" out="$2" pid start now
    shift 2
    start=$(date +%s)
    RUN_TIMED_OUT=false
    set -m
    (
        cd "$WT" || exit 127
        exec env -i PATH="$PATH" HOME="$HOME" LANG="${LANG:-C}" TMPDIR="${TMPDIR:-/tmp}" "$@"
    ) </dev/null >"$out" 2>&1 &
    pid=$!
    set +m
    while kill -0 "$pid" 2>/dev/null; do
        now=$(date +%s)
        if [ $((now - start)) -ge "$limit" ]; then
            kill -TERM -- "-$pid" 2>/dev/null
            sleep 1
            kill -KILL -- "-$pid" 2>/dev/null
            RUN_TIMED_OUT=true
            break
        fi
        sleep 0.2
    done
    wait "$pid" 2>/dev/null
    RUN_EXIT=$?
    kill -KILL -- "-$pid" 2>/dev/null
    RUN_SECS=$(( $(date +%s) - start ))
}

parse_timeout() {
    case "$1" in ""|*[!0-9]*) usage "--timeout [$1] is not a number of seconds" ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le "$TIMEOUT_MAX" ] || usage "--timeout must be 1 to $TIMEOUT_MAX seconds"
}

# ---------------------------------------------------------------------- red ----

cmd_red() {
    [ $# -ge 1 ] || usage "red takes <session>"
    local s="$1" marker="" has_marker=0 pfile="" timeout="$TIMEOUT_DEFAULT"
    local -a named=()
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --marker) [ $# -ge 2 ] || usage "--marker needs a value"; marker="$2"; has_marker=1; shift 2 ;;
            --passage-file) [ $# -ge 2 ] || usage "--passage-file needs a file"; pfile="$2"; shift 2 ;;
            --timeout) [ $# -ge 2 ] || usage "--timeout needs a value"; parse_timeout "$2"; timeout="$2"; shift 2 ;;
            --tests)
                shift
                while [ $# -gt 0 ]; do
                    case "$1" in --*) break ;; esac
                    named[${#named[@]}]="$1"
                    shift
                done
                ;;
            --) shift; break ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    [ "$has_marker" -eq 1 ] || usage "red needs --marker"
    [ -n "$pfile" ] || usage "red needs --passage-file"
    [ -r "$pfile" ] && [ -f "$pfile" ] || usage "--passage-file [$pfile] is not a readable file"
    [ $# -ge 1 ] || usage "red needs the command after --"

    [ "$(unit_kind "$s")" = fix ] || refuse "the unit is not recorded as a fix; a red is owed only by a fix (fix-kind.sh declare records one)"

    cp "$pfile" "$TMP/passage" && crlf "$TMP/passage"
    printf '%s' "$(cat "$TMP/passage")" > "$TMP/passage.t"
    ctx_get "$s" "$REPORT_KEY" "$TMP/report" || die66 "could not read $REPORT_KEY"
    crlf "$TMP/report"
    check_passage "$marker" "$TMP/passage.t" "$TMP/report"

    local base head
    ctx_get "$s" impl_base "$TMP/base" || die66 "could not read impl_base"
    base=$(tr -d '[:space:]' < "$TMP/base")
    [ -n "$base" ] || undecided "no impl_base is recorded; analysis records it"
    git cat-file -e "$base^{commit}" 2>>"$ERRLOG" || undecided "impl_base [$base] names no commit"
    head=$(git rev-parse -q --verify "HEAD^{commit}") || undecided "HEAD names no commit"
    ctx_get "$s" "$RULES_KEY" "$TMP/rules" || die66 "could not read $RULES_KEY"
    [ -s "$TMP/rules" ] || undecided "no rules copy ($RULES_KEY) is stored; review_level_choice stores it"

    # shellcheck source=../../../scripts/lib/test-classify.sh
    . "$PLUGIN_ROOT_SELF/scripts/lib/test-classify.sh" || undecided "cannot load scripts/lib/test-classify.sh"
    test_classify "$base" "$head" "$TMP/rules" > "$TMP/classified" 2>"$TMP/classify.err" \
        || undecided "could not classify the unit's test files: $(head -c 300 "$TMP/classify.err")"

    # The files copied onto the base: every test file the diff touched that is
    # still there at HEAD.
    local tab label path digest
    tab=$(printf '\t')
    : > "$TMP/copy"
    while IFS="$tab" read -r label path digest; do
        [ -n "$path" ] || continue
        [ "$digest" != deleted ] || continue
        # The list below is one path per line, so a path that holds a control
        # character (a newline, say) can't be carried in it.
        case "$path" in *[[:cntrl:]]*) refuse "a test path in the diff holds a control character; rename it" ;; esac
        printf '%s\n' "$path" >> "$TMP/copy"
    done < "$TMP/classified"
    local p
    for p in "${named[@]+"${named[@]}"}"; do
        safe_path "$p" || refuse "--tests [$p] is not a repository-relative path"
        [ "$(git cat-file -t "HEAD:$p" 2>>"$ERRLOG")" = blob ] || refuse "--tests [$p] names no committed file at HEAD"
        grep -Fxq -- "$p" "$TMP/copy" || printf '%s\n' "$p" >> "$TMP/copy"
    done
    if [ "${#named[@]}" -gt 0 ]; then
        printf '%s\n' "${named[@]}" > "$TMP/repro"
    else
        cp "$TMP/copy" "$TMP/repro"
    fi
    [ -s "$TMP/repro" ] || refuse "the unit's committed diff touches no test file and none is named with --tests; commit the reproducing test first (the red copies only committed test files), or name the existing tests that reproduce the bug"

    local mode
    while IFS= read -r p; do
        mode=$(git ls-tree HEAD -- "$p" | awk '{ print $1; exit }')
        [ "$mode" != 120000 ] || refuse "the test file [$p] is a symlink; a red copies only regular files"
    done < "$TMP/copy"

    make_worktree "$base"
    local dir
    while IFS= read -r p; do
        # The worktree holds the base's tree, so a directory on the path that
        # is a symlink there would carry the copy outside the worktree; refuse
        # it. A symlink at the path itself is removed, not followed.
        dir=$(dirname "$p")
        while [ "$dir" != . ] && [ "$dir" != / ]; do
            [ ! -L "$WT/$dir" ] || refuse "the directory [$dir] is a symlink at the base, so the test [$p] can't be copied under it"
            dir=$(dirname "$dir")
        done
        mkdir -p "$WT/$(dirname "$p")"
        [ ! -L "$WT/$p" ] || rm -f "$WT/$p"
        git cat-file blob "HEAD:$p" > "$WT/$p" || undecided "could not copy $p into the temporary worktree"
        mode=$(git ls-tree HEAD -- "$p" | awk '{ print $1; exit }')
        if [ "$mode" = 100755 ]; then chmod 755 "$WT/$p"; else chmod 644 "$WT/$p"; fi
    done < "$TMP/copy"

    run_bounded "$timeout" "$TMP/out" "$@"
    if [ "$RUN_TIMED_OUT" = true ]; then
        refuse "the command ran past $timeout seconds and was killed; nothing was recorded"
    fi
    if [ "$RUN_EXIT" -eq 0 ]; then
        refuse "the command exited 0 on the base code; a red needs a check that fails without the fix"
    fi
    if ! grep -Fq -- "$marker" "$TMP/out"; then
        echo "refused: the command failed (exit $RUN_EXIT) but its output doesn't hold the marker [$marker], so it didn't fail for the reported reason (a compile error fails the same way). The output's last lines:"
        tail -n 15 "$TMP/out" | LC_ALL=C tr -d '\000-\010\013-\037'
        exit 1
    fi

    # The tests and harness files with the blob that ran: a copied file's at
    # HEAD, anything else's at the base.
    : > "$TMP/tests.tsv"
    while IFS= read -r p; do
        printf '%s\t%s\n' "$p" "$(git rev-parse -q --verify "HEAD:$p")" >> "$TMP/tests.tsv"
    done < "$TMP/repro"
    : > "$TMP/harness.tsv"
    local a
    for a in "$@"; do
        a=${a#./}
        safe_path "$a" || continue
        grep -Fxq -- "$a" "$TMP/repro" && continue
        grep -Fq -- "$a$tab" "$TMP/harness.tsv" && continue
        if grep -Fxq -- "$a" "$TMP/copy"; then
            printf '%s\t%s\n' "$a" "$(git rev-parse -q --verify "HEAD:$a")" >> "$TMP/harness.tsv"
        elif [ "$(git cat-file -t "$base:$a" 2>>"$ERRLOG")" = blob ]; then
            printf '%s\t%s\n' "$a" "$(git rev-parse -q --verify "$base:$a")" >> "$TMP/harness.tsv"
        fi
    done
    tail_of "$TMP/out" > "$TMP/tail"
    marker_context "$TMP/out" "$marker" > "$TMP/context"

    local rsrc
    rsrc=$(koto context get "$s" fix_kind.jsonl 2>>"$ERRLOG" \
        | jq -Rr 'fromjson? | select(type == "object" and .report_source != null) | .report_source' | tail -n 1)
    load_record "$s"
    jq --argjson argv "$(jq -nc '$ARGS.positional' --args "$@")" \
        --arg base "$base" --arg head "$head" \
        --rawfile tests "$TMP/tests.tsv" --rawfile harness "$TMP/harness.tsv" \
        --argjson exit "$RUN_EXIT" --rawfile tail "$TMP/tail" --rawfile context "$TMP/context" \
        --rawfile passage "$TMP/passage.t" --arg marker "$marker" --arg rsrc "$rsrc" \
        --argjson timeout "$timeout" --argjson secs "$RUN_SECS" --arg ts "$(now)" '
        def rows($t): $t | split("\n") | map(select(. != "") | split("\t") | {path: .[0], blob: .[1]});
        .red = {command: $argv, base: $base, head: $head,
                tests: rows($tests), harness: rows($harness),
                exit: $exit, output_tail: $tail, marker_context: $context,
                passage: $passage, marker: $marker, report_source: $rsrc,
                timeout_secs: $timeout, duration_secs: $secs, ran_at: $ts}
        | .green = null' "$TMP/record" > "$TMP/record.next" || undecided "could not build the record"
    save_record "$s"
    echo "recorded: red at base $base, exit $RUN_EXIT, marker found; reproducing tests: $(cut -f 1 "$TMP/tests.tsv" | paste -sd, -)"
    exit 0
}

# ------------------------------------------------------------------ observe ----

# section <file> <name>: the body of the `## <name>` section, trimmed of
# leading and trailing blank lines; nothing when absent.
section() {
    NAME="$2" awk '
        function norm(s) { s = tolower(s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        /^## / { inside = (norm(substr($0, 4)) == norm(ENVIRON["NAME"])); if (inside) found = 1; next }
        inside { buf = buf $0 "\n" }
        END { if (found) printf "%s", buf }
    ' "$1" | awk 'NF { seen = 1 } seen { lines[++n] = $0 } END { while (n > 0 && lines[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
}

cmd_observe() {
    [ $# -ge 1 ] || usage "observe takes <session>"
    local s="$1" phase="" file=""
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --phase) [ $# -ge 2 ] || usage "--phase needs before or after"; phase="$2"; shift 2 ;;
            --file) [ $# -ge 2 ] || usage "--file needs a file"; file="$2"; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    case "$phase" in before|after) ;; *) usage "--phase [$phase] is not before or after" ;; esac
    [ -f "$file" ] && [ -r "$file" ] || usage "--file [$file] is not a readable file"
    [ "$(wc -c < "$file" | tr -d ' ')" -le "$OBS_MAX" ] || refuse "the observation is over $OBS_MAX bytes"
    [ "$(unit_kind "$s")" = fix ] || refuse "the unit is not recorded as a fix; an observation stands in only for a fix's red or green"

    cp "$file" "$TMP/obs" && crlf "$TMP/obs"
    local -a want=()
    if [ "$phase" = before ]; then
        want=("Produced" "Environment" "Seen" "Why no check" "Passage" "Marker")
    else
        want=("Produced" "Environment" "Seen")
    fi
    local missing="" n
    for n in "${want[@]}"; do
        [ -n "$(section "$TMP/obs" "$n" | tr -d '[:space:]')" ] || missing="$missing, $n"
    done
    [ -z "$missing" ] || refuse "the observation is missing: ${missing#, } (each a \`## \` section)"

    load_record "$s"
    local marker="" passage="" head
    head=$(git rev-parse -q --verify "HEAD^{commit}") || undecided "HEAD names no commit"
    if [ "$phase" = before ]; then
        section "$TMP/obs" Passage > "$TMP/passage"
        printf '%s' "$(cat "$TMP/passage")" > "$TMP/passage.t"
        marker=$(section "$TMP/obs" Marker | awk 'NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }')
        ctx_get "$s" "$REPORT_KEY" "$TMP/report" || die66 "could not read $REPORT_KEY"
        crlf "$TMP/report"
        check_passage "$marker" "$TMP/passage.t" "$TMP/report"
        case "$(section "$TMP/obs" Seen)" in *"$marker"*) ;; *) refuse "the marker [$marker] is not in the Seen section" ;; esac
        passage=$(cat "$TMP/passage.t")
    else
        jq -e '.observations.before != null' "$TMP/record" >/dev/null \
            || refuse "an after-observation needs a before-observation first"
    fi
    jq --arg phase "$phase" --arg digest "$(git hash-object "$TMP/obs")" --rawfile text "$TMP/obs" \
        --arg head "$head" --arg ts "$(now)" --arg passage "$passage" --arg marker "$marker" '
        .observations[$phase] = ({digest: $digest, text: $text, head: $head, recorded_at: $ts}
            + (if $phase == "before" then {passage: $passage, marker: $marker} else {} end))' \
        "$TMP/record" > "$TMP/record.next" || undecided "could not build the record"
    save_record "$s"
    echo "recorded: $phase-observation at $head"
    exit 0
}

# -------------------------------------------------------------------- green ----

cmd_green() {
    [ $# -ge 1 ] || usage "green takes <session>"
    local s="$1" timeout="$TIMEOUT_DEFAULT"
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) [ $# -ge 2 ] || usage "--timeout needs a value"; parse_timeout "$2"; timeout="$2"; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    [ "$(unit_kind "$s")" = fix ] || refuse "the unit is not recorded as a fix; only a fix has a green"
    load_record "$s"
    jq -e '.red != null' "$TMP/record" >/dev/null || refuse "no red is recorded; a green re-runs the red's command"
    local head n i
    head=$(git rev-parse -q --verify "HEAD^{commit}") || undecided "HEAD names no commit"
    n=$(jq '.red.command | length' "$TMP/record")
    local -a argv=()
    i=0
    while [ "$i" -lt "$n" ]; do
        argv[$i]=$(jq -r --argjson i "$i" '.red.command[$i]' "$TMP/record")
        i=$((i + 1))
    done
    make_worktree "$head"
    run_bounded "$timeout" "$TMP/out" "${argv[@]}"
    tail_of "$TMP/out" > "$TMP/tail"
    local code="$RUN_EXIT"
    [ "$RUN_TIMED_OUT" = false ] || code=124
    jq --arg head "$head" --argjson exit "$code" --rawfile tail "$TMP/tail" --arg ts "$(now)" \
        --argjson to "$RUN_TIMED_OUT" '
        .green = {command: .red.command, head: $head, exit: $exit, timed_out: $to,
                  output_tail: $tail, ran_at: $ts}' "$TMP/record" > "$TMP/record.next" \
        || undecided "could not build the record"
    save_record "$s"
    if [ "$code" -eq 0 ]; then
        echo "recorded: green at HEAD $head, exit 0"
        exit 0
    fi
    if [ "$RUN_TIMED_OUT" = true ]; then
        echo "failed: the check ran past $timeout seconds at HEAD $head and was killed; the fix's check doesn't pass"
    else
        echo "failed: the check exited $code at HEAD $head; the fix's check doesn't pass yet"
    fi
    tail -n 15 "$TMP/out" | LC_ALL=C tr -d '\000-\010\013-\037'
    exit 1
}

# -------------------------------------------------------------------- gates ----

gate_setup() {
    # shellcheck source=../../../scripts/lib/rule-findings.sh
    . "$PLUGIN_ROOT_SELF/scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
}

# gate_hold <rule> <message>: a hold line, its finding, and the gate's exit.
gate_hold() {
    echo "hold: $2"
    rf_finding "$1" "$2"
    if [ "$RF_COUNTED" -eq 1 ]; then
        rf_dispute_hint
        rf_deliver
        exit 1
    fi
    rf_deliver
    exit 0
}

cmd_check_red() {
    [ $# -eq 1 ] || usage "check-red takes <session>"
    local s="$1" kind
    valid_session "$s" || usage "bad session name [$s]"
    gate_setup
    rf_require red-first/no-red
    kind=$("$HERE/fix-kind.sh" kind "$s" 2>>"$ERRLOG") || undecided "could not read the unit's kind"
    if [ "$kind" != fix ]; then
        echo "pass: the unit is not a fix"
        exit 0
    fi
    ctx_get "$s" "$KEY" "$TMP/record" || undecided "could not read $KEY"
    if [ -s "$TMP/record" ]; then
        jq -e --arg s "$SCHEMA" '.schema == $s' "$TMP/record" >/dev/null 2>>"$ERRLOG" || undecided "$KEY is not a $SCHEMA record"
        if jq -e '.red != null' "$TMP/record" >/dev/null; then
            echo "pass: a red is recorded at base $(jq -r .red.base "$TMP/record")"
            exit 0
        fi
        if jq -e '.observations.before != null' "$TMP/record" >/dev/null; then
            echo "pass: a before-observation is recorded"
            exit 0
        fi
    fi
    gate_hold red-first/no-red "the unit is a fix and has neither a red nor a before-observation; record a red with red-first.sh red $s --marker <text> --passage-file <file> -- <command>, or an observation with red-first.sh observe $s --phase before --file <observation.md>"
}

cmd_check_green() {
    [ $# -eq 1 ] || usage "check-green takes <session>"
    local s="$1" kind head
    valid_session "$s" || usage "bad session name [$s]"
    gate_setup
    rf_require red-first/no-green
    kind=$("$HERE/fix-kind.sh" kind "$s" 2>>"$ERRLOG") || undecided "could not read the unit's kind"
    if [ "$kind" != fix ]; then
        echo "pass: the unit is not a fix"
        exit 0
    fi
    head=$(git rev-parse -q --verify "HEAD^{commit}") || undecided "HEAD names no commit"
    ctx_get "$s" "$KEY" "$TMP/record" || undecided "could not read $KEY"
    if [ ! -s "$TMP/record" ]; then
        gate_hold red-first/no-green "the unit is a fix with no red and no observation recorded"
    fi
    jq -e --arg s "$SCHEMA" '.schema == $s' "$TMP/record" >/dev/null 2>>"$ERRLOG" || undecided "$KEY is not a $SCHEMA record"
    if jq -e '.red != null' "$TMP/record" >/dev/null; then
        jq -e '.green != null' "$TMP/record" >/dev/null \
            || gate_hold red-first/no-green "no green is recorded; run red-first.sh green $s to re-run the red's command at HEAD"
        jq -e '.green.command == .red.command' "$TMP/record" >/dev/null \
            || gate_hold red-first/no-green "the green ran a different command from the red's; run red-first.sh green $s"
        local gh gx
        gh=$(jq -r '.green.head' "$TMP/record")
        gx=$(jq -r '.green.exit' "$TMP/record")
        [ "$gh" = "$head" ] \
            || gate_hold red-first/no-green "the green was recorded at $gh, not HEAD $head; run red-first.sh green $s again"
        [ "$gx" = 0 ] \
            || gate_hold red-first/no-green "the green at HEAD exited $gx; the fix's check doesn't pass, so change the code and record the green again"
        echo "pass: the red's command passed at HEAD $head"
        exit 0
    fi
    if jq -e '.observations.before != null' "$TMP/record" >/dev/null; then
        if jq -e '.observations.after != null' "$TMP/record" >/dev/null; then
            # An observation pair counts once a live acceptance covers both
            # digests; test-change.sh holds the ledger and asks the rule.
            if "$HERE/test-change.sh" covered "$s" observation:before observation:after > "$TMP/covered" 2>>"$ERRLOG"; then
                echo "pass: the observation pair has a live acceptance"
                exit 0
            fi
            echo "refused: observations wait for acceptance; an observation pair counts only once someone other than the run accepts it ($(paste -sd ';' "$TMP/covered" | sed 's/;/; /g'))"
            gate_hold red-first/no-green "the unit's red and green are observations that no live acceptance covers yet; mint a seat with test-change.sh seat $s"
        fi
        gate_hold red-first/no-green "no after-observation is recorded; record one with red-first.sh observe $s --phase after --file <observation.md>"
    fi
    gate_hold red-first/no-green "the unit is a fix with no red and no observation recorded"
}

command -v jq >/dev/null || undecided "jq is not on PATH"
command -v git >/dev/null || undecided "git is not on PATH"
[ $# -ge 1 ] || usage "no subcommand"
sub="$1"
shift
case "$sub" in
    red)         cmd_red "$@" ;;
    observe)     cmd_observe "$@" ;;
    green)       cmd_green "$@" ;;
    check-red)   cmd_check_red "$@" ;;
    check-green) cmd_check_green "$@" ;;
    *) usage "unknown subcommand [$sub]" ;;
esac
