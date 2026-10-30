#!/usr/bin/env bash
# teardown-pass.sh -- one teardown pass over one sealed target, and the check
# that reads its result.
#
# The coordinator's local teardown agent (references/teardown-agent.md) runs
# `run` with the session and the key seal it was handed. Its target is read
# from the session itself, through `teardown-handoff.sh read`, never taken from
# the message or an argument: the key seal it was handed is only compared with
# the one that read prints, so a stale or edited hand-off refuses.
#
# Usage:
#   teardown-pass.sh run --session <s> --keyseal <keyseal:seq:sha256>
#       In order, stopping at the first failure:
#         1. read the verdict (seal, topic, no directed transition) and match
#            the key seal;
#         2. re-read every fact: each pull request still merged at its merge
#            commit, the handoff comment still there, the job still listed
#            with the same cwd and session and still finished as
#            dc_job_finished reads it (its own state.json reads done,
#            stopped or failed, and the listing shows no live pid; the
#            listing's state isn't read), niwa still
#            listing the instance by that name and path;
#         3. re-inventory the instance (teardown-inventory.sh, unsealed);
#            anything but durable refuses;
#         4. preserve, into <archive>/<UTC date>-<topic>-<job id>/: every
#            Claude Code project directory of the instance, whole, into
#            claude-projects/<directory name>/ (below), the job's
#            state.json, timeline.jsonl and tmp/, and every koto session
#            whose header's execution_dir is at or under the instance path or
#            the job's tmp/, and teardown.json (`{topic, instance: {name,
#            path}, job: {id, session}, removed, niwa: {dispatch_id,
#            reason}}`, written from the verdict, the dispatch id from its
#            `dispatch` line, reason `no source` or `invalid input` when
#            there is no id); each copy checked against its source's hash, a
#            MANIFEST (`<sha256> <bytes> <path>` per file), MANIFEST.sha256
#            (the MANIFEST's own digest, `<sha256>  MANIFEST`) and a README;
#            the job's tmp/ is copied without its build trees (below);
#         4a. the unit's cost capture (unit-cost.sh capture): one `cost`
#            entry on the record and unit-cost.json in the archive, under its
#            own deadline, with no stream of the pass's and its status
#            ignored, so it never changes the pass's exit code, last line or
#            RESULT; a capture that posts nothing adds one warning line on
#            stderr. Just before the capture, one `retired` event goes
#            through scripts/emit-event.sh
#            (docs/designs/DESIGN-fleet-cost-emit.md), run as a child whose
#            output and status are ignored: the topic, this session, the
#            verdict's job session, dispatch id and pull request (when it
#            names exactly one), and the unit's request as the archived koto
#            sessions name it (archive-common.sh ac_dispatch_request). A
#            field the pass doesn't have is left out;
#         5. `niwa destroy --force <name>` at the workspace root, the name
#            checked before the command is built;
#         6. `claude rm <job id>`; when niwa destroy already removed the
#            job, rm prints `No job matching`, and that counts as done only
#            when niwa no longer lists the instance, <claude home>/jobs/<job
#            id> is gone and `claude agents --json --all` doesn't list the
#            job; RESULT then says so after `done <time>`. Any other rm
#            failure is incomplete;
#         7. confirm `niwa list --json` no longer shows the instance and
#            `claude agents --json --all` no longer shows the job.
#       RESULT in the archive says `done`, or why the pass stopped once the
#       archive exists. A rerun on the same UTC day reuses the day's archive
#       directory; one on a later day makes a second, and `confirm` then
#       reports that it can't find a single archive.
#       Steps 1 to 4 remove nothing, so a failure there is `refused`; a
#       failure from step 5 on is `incomplete`, naming the step.
#
#       Project directories: under <claude home>/projects, the directory
#       named for the instance path (every character outside [A-Za-z0-9]
#       made `-`) is always taken; one named for it followed by `-` (a
#       worktree or clone under the instance) only when at least one line of
#       a .jsonl file in it carries a `cwd` at or under the instance path and
#       none carries one outside it, so a sibling instance whose name extends
#       this one's is never swept in. Each is entered with `cd -P` and its
#       physical path checked, and its files are listed with `find -type f`,
#       which never follows a symbolic link: a link is skipped. The README
#       lists every directory taken, every one skipped with its reason
#       (`cwd outside the instance`, or a directory that is itself a link)
#       and every link skipped inside one. The verdict's transcript must be
#       in a directory taken, so the cost capture reads the worker's own
#       session from the archive. The pass runs under umask 077.
#
#       Build trees: the job's tmp/ is copied whole except the build output
#       a worker left in it, each tree found by what it holds, never by its
#       name alone, except node_modules: a directory holding a CACHEDIR.TAG
#       that starts with the cache-directory signature, or a .rustc_info.json
#       naming a rustc_fingerprint (a cargo target directory, whatever it is
#       named); one holding a .cargo-lock (a cargo build profile directory,
#       such as target/debug); one holding a .package-cache (a cargo home);
#       and any directory named node_modules. Only the outermost tree is left
#       out (one inside another is part of it), and no link is followed, as
#       everywhere else. tmp/ itself never is one, since the worker's scratch
#       beside it would go too: a target directory set to tmp/ itself still
#       loses its profile directories, by their .cargo-lock, while a cargo
#       home set to tmp/ itself is archived whole. Each one left out is a line
#       of SKIPPED, `<bytes> <marker> job/tmp/<path>`, its bytes the sum of
#       its regular files' sizes; SKIPPED is in the MANIFEST and the README
#       lists the trees. It is a file of its own, not a field of
#       teardown.json, whose shape unit-cost.sh reads: a tmp/ with no build
#       tree gets no SKIPPED and no README line, so its archive is what it was
#       before trees were left out.
#
#       Removed mode, when the verdict says `removed yes` (the unit was torn
#       down outside the pass; teardown-handoff.sh): the instance name is
#       `-` and the job line may be `job -`. Step 2 checks the pull requests
#       and the handoff comment as above, then that niwa lists no instance
#       at the path or for the topic and Claude Code lists no job there (a
#       listing that can't be read refuses); there is no job or instance to
#       re-read and step 3 is skipped. Step 4 preserves what survives (the
#       project directories, as above, and koto sessions by
#       execution_dir), 4a captures as above, and RESULT says done: steps 5
#       to 7 never run, so the pass has no path to `niwa destroy` or `claude
#       rm`. With `job -` no session survived: nothing is archived or
#       posted, the retired event is sent without a request, and the last
#       line still says done.
#   teardown-pass.sh confirm --session <s>
#       The teardown_confirm state's default action: reads the verdict the
#       same way, both listings, and the archive (RESULT says done, the
#       MANIFEST's digest is the one MANIFEST.sha256 records, and every
#       MANIFEST file is present at its size; the full hash check is run's),
#       and prints, sealed to this visit, `teardown-confirmed` or
#       `teardown-incomplete`, the reason in context key
#       coord/teardown_confirm.json and on stderr. For a removed verdict it
#       also checks Claude Code lists no job at the path, and with `job -`
#       it confirms without an archive, since none was made. The sizes come
#       from one listing of the archive, never a process per file, and that
#       read has its own deadline inside koto's 30-second action bound: an
#       archive it can't finish is `teardown-incomplete`, never a state left
#       timing out.
#
# Output (run): progress lines, then one last line `teardown-pass: done
# <archive>`, `teardown-pass: refused: <why>` or `teardown-pass: incomplete at
# <step>: <why>`. File contents are never printed, only paths and hashes.
#
# Exit codes (run): 0 done; 1 refused, nothing removed; 2 incomplete, after
# the destroy began; 64 usage. (confirm): 0 a verdict printed; 2 a read or
# the seal failed; 64 usage.
#
# Environment: NIWA, CLAUDE_CLI, GH and KOTO name the tools (tests);
# TEARDOWN_CLAUDE_HOME (default $HOME/.claude), TEARDOWN_KOTO_SESSIONS (default
# $HOME/.koto/sessions), TEARDOWN_ARCHIVE_DIR (default
# ${XDG_DATA_HOME:-$HOME/.local/share}/teardown-archive), TEARDOWN_FETCH_SECS
# (each GitHub read's bound, default 8), TEARDOWN_CAPTURE_SECS (the cost
# capture's bound, default 120), TEARDOWN_CONFIRM_SECS (confirm's archive
# read's bound, default 15), KOTO_REQUESTS (koto's request store, default
# $HOME/.koto/requests, where the retired event's request is looked up).
# bash 3.2.
set -uo pipefail

PROG=teardown-pass
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"
# The collection it shares with the capture after a removal.
# shellcheck source=archive-common.sh
. "$HERE/archive-common.sh"

KOTO="${KOTO:-koto}"
GH="${GH:-gh}"
NIWA="${NIWA:-niwa}"
CLAUDE_CLI="${CLAUDE_CLI:-claude}"
CLAUDE_HOME="${TEARDOWN_CLAUDE_HOME:-$HOME/.claude}"
KOTO_SESSIONS="${TEARDOWN_KOTO_SESSIONS:-$HOME/.koto/sessions}"
ARCHIVE_ROOT="${TEARDOWN_ARCHIVE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/teardown-archive}"
FETCH_SECS="${TEARDOWN_FETCH_SECS:-8}"
CAPTURE_SECS="${TEARDOWN_CAPTURE_SECS:-120}"
# confirm's archive read gets half of koto's 30-second action bound; the
# listings, the RESULT read and the MANIFEST digest before it get the rest.
CONFIRM_SECS="${TEARDOWN_CONFIRM_SECS:-15}"
# The repository's one event helper, found from this script's own directory;
# nothing in the environment names another.
EMIT="$HERE/../../../scripts/emit-event.sh"

usage() { sed -n '/^# Usage:/,/^# Output (run)/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION="" WANT_KS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --keyseal) [ $# -ge 2 ] || usage; WANT_KS="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in run) [ -n "$WANT_KS" ] || usage ;; confirm) [ -z "$WANT_KS" ] || usage ;; *) usage ;; esac
[ -n "$SESSION" ] || usage
# Everything the pass writes (the archive, its scratch files) is the user's
# alone: the archive holds whole project directories, tool results included.
umask 077

T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

sha256() { ac_sha256; }
say() { printf '%s: %s\n' "$PROG" "$*"; }
STEP=read
ARCH=""
refused() { say "refused: $*"; [ -n "$ARCH" ] && [ -d "$ARCH" ] && printf 'refused at %s: %s\n' "$STEP" "$*" >"$ARCH/RESULT"; exit 1; }
incomplete() { say "incomplete at $STEP: $*"; [ -n "$ARCH" ] && printf 'incomplete at %s: %s\n' "$STEP" "$*" >"$ARCH/RESULT"; exit 2; }

# ---------------------------------------------------------------------------
# The verdict, through the one reader; sets TOPIC, INAME, IPATH, JOB, SID, TR,
# HANDOFF, PRS (one `owner/repo#n sha` per line) and KS. Returns 1 with the
# reason in $T/why when it doesn't stand.
read_verdict() {
    local v rc
    v=$(bash "$HERE/teardown-handoff.sh" read --session "$SESSION" 2>"$T/why")
    rc=$?
    [ "$rc" = 0 ] || { [ -s "$T/why" ] || echo "the verdict can't be read" >"$T/why"; return 1; }
    TOPIC=$(sed -n '/^topic /{s///p;q;}' <<<"$v")
    INAME=$(sed -n '/^instance \([^ ]*\) .*/{s//\1/p;q;}' <<<"$v")
    IPATH=$(sed -n '/^instance [^ ]* /{s///p;q;}' <<<"$v")
    JOB=$(sed -n '/^job \([^ ]*\) .*/{s//\1/p;q;}' <<<"$v")
    SID=$(sed -n '/^job [^ ]* /{s///p;q;}' <<<"$v")
    TR=$(sed -n '/^transcript /{s///p;q;}' <<<"$v")
    HANDOFF=$(sed -n '/^handoff /{s///p;q;}' <<<"$v")
    PRS=$(printf '%s\n' "$v" | sed -n 's/^pr //p')
    DISPATCH=$(sed -n '/^dispatch /{s///p;q;}' <<<"$v")
    KS=$(printf '%s\n' "$v" | sed -n 's/^keyseal //p' | tail -1)
    # Removed mode: the verdict says the unit was torn down outside the pass.
    # Only beside `removed yes` may the instance name be `-` and the job line
    # be `job -`, and then the name must be `-`: nothing is destroyed, so no
    # name is ever built into a command.
    REMOVED=0 NOJOB=0
    grep -qx 'removed yes' <<<"$v" && REMOVED=1
    if [ "$REMOVED" = 1 ]; then
        [ "$INAME" = - ] || { echo "a removed verdict names an instance [$INAME]; it must be -" >"$T/why"; return 1; }
        grep -qx 'job -' <<<"$v" && { NOJOB=1 JOB="" SID=""; }
    fi
    # The fields the commands are built from are checked here, whatever the
    # verdict says: an empty or odd name never reaches niwa or claude.
    dc_valid_topic "$TOPIC" || { echo "the verdict's topic is not a dispatch topic" >"$T/why"; return 1; }
    if [ "$REMOVED" = 0 ]; then
        grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]*$' <<<"$INAME" || { echo "the verdict's instance name is not a plain name" >"$T/why"; return 1; }
    fi
    case "$IPATH" in /*) ;; *) echo "the verdict's instance path is not absolute" >"$T/why"; return 1 ;; esac
    if [ "$NOJOB" = 0 ]; then
        grep -Eq '^[0-9a-f]{6,64}$' <<<"$JOB" || { echo "the verdict's job id is not a job id" >"$T/why"; return 1; }
        grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' <<<"$SID" || { echo "the verdict's session id is not a session id" >"$T/why"; return 1; }
    fi
    [ -n "$PRS" ] || { echo "the verdict names no merged pull request" >"$T/why"; return 1; }
    return 0
}

niwa_list() { (cd "$ROOT" && "$NIWA" list --json); }
agents() { "$CLAUDE_CLI" agents --json --all; }

# ---------------------------------------------------------------------------
if [ "$MODE" = confirm ]; then
    verdict() {
        local word=$1 why=$2
        jq -nc --arg v "$word" --arg w "$why" --arg a "${ARCH:-}" '{verdict: $v, reason: $w, archive: $a}' >"$T/detail.json"
        "$KOTO" context add "$SESSION" coord/teardown_confirm.json --from-file "$T/detail.json" >/dev/null \
            || { say "cannot store the detail"; exit 2; }
        [ "$word" = teardown-confirmed ] || say "$why" >&2
        bash "$DC_COORD_LOG" seal --session "$SESSION" --state teardown_confirm --token "$word" || { say "cannot seal the verdict"; exit 2; }
        exit 0
    }
    # archive_whole <archive>: 0 when every MANIFEST line's file is in the
    # archive at its size; 1 with the first that isn't on stdout; 2 when the
    # archive can't be listed, 3 when the join can't run, the cause on
    # stderr. One listing of every file's size (find never follows a link, so
    # a link is no file) and one awk over it and the MANIFEST: no process per
    # file, whatever the archive holds. It writes $T/sizes, confirm's scratch.
    # shellcheck disable=SC2329 # run through dc_with_deadline's "$@"
    archive_whole() {
        local st
        # wc -c takes a regular file's size from fstat on GNU and BSD alike,
        # and is on the restricted PATH the tests run under, which stat isn't.
        # Each batch prints `<padding><bytes> ./<path>` per file and, past
        # one file, a `<bytes> total` line no path collides with.
        (cd "$1" && find . -type f -exec wc -c {} +) >"$T/sizes" || return 2
        # Each MANIFEST line is `<sha256> <bytes> <path>`; a path may hold
        # spaces, so both inputs split at their leading fields only.
        awk '
            FILENAME == ARGV[1] { sub(/^ +/, ""); i = index($0, " "); size[substr($0, i + 1)] = substr($0, 1, i - 1); next }
            {
                rel = $0
                if (!sub(/^[^ ]+ [^ ]+ /, "", rel) || rel == "") next
                if (!(("./" rel) in size)) { print rel " is missing from the archive"; bad = 1; exit }
                if (size["./" rel] != $2) { print rel " in the archive is not the size the MANIFEST records"; bad = 1; exit }
            }
            END { exit bad }
        ' "$T/sizes" "$1/MANIFEST"
        st=$?
        [ "$st" -le 1 ] && return "$st"
        return 3
    }
    read_verdict || verdict teardown-incomplete "$(cat "$T/why")"
    ROOT=$(dc_workspace_root) || verdict teardown-incomplete "no workspace root found"
    NL=$(niwa_list) || { say "niwa list could not be read"; exit 2; }
    printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" 'type == "array" and (any(.[]; .name == $n or .path == $p) | not)' >/dev/null \
        || verdict teardown-incomplete "niwa still lists $INAME"
    AG=$(agents) || { say "claude agents could not be read"; exit 2; }
    printf '%s' "$AG" | jq -e --arg j "$JOB" 'type == "array" and (any(.[]; .id == $j) | not)' >/dev/null \
        || verdict teardown-incomplete "claude agents still lists job $JOB"
    if [ "$REMOVED" = 1 ]; then
        printf '%s' "$AG" | jq -e --arg p "$IPATH" 'any(.[]; .cwd == $p) | not' >/dev/null \
            || verdict teardown-incomplete "claude agents lists a job in $IPATH"
        # No session survived the removal: there was nothing to archive.
        [ "$NOJOB" = 1 ] && verdict teardown-confirmed "the unit was removed outside the pass and no session of it survived to archive"
    fi
    ls -d "$ARCHIVE_ROOT"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$TOPIC-$JOB" >"$T/arch" 2>/dev/null
    [ "$(wc -l <"$T/arch" | tr -d ' ')" = 1 ] || verdict teardown-incomplete "no single archive for $TOPIC and job $JOB under $ARCHIVE_ROOT"
    ARCH=$(cat "$T/arch")
    case "$(head -1 "$ARCH/RESULT" 2>/dev/null)" in done*) ;; *) verdict teardown-incomplete "the archive's RESULT doesn't say done" ;; esac
    [ -s "$ARCH/MANIFEST" ] || verdict teardown-incomplete "the archive has no MANIFEST"
    # The MANIFEST is the one the pass wrote once every copy matched its
    # source: its digest is the one the pass recorded beside it.
    [ -s "$ARCH/MANIFEST.sha256" ] || verdict teardown-incomplete "the archive has no MANIFEST.sha256"
    [ "$(sha256 <"$ARCH/MANIFEST")" = "$(cut -d' ' -f1 "$ARCH/MANIFEST.sha256")" ] \
        || verdict teardown-incomplete "the archive's MANIFEST is not the one the pass recorded"
    # Every file it lists is in the archive at its size, read under a
    # deadline inside koto's 30-second command bound: past it the archive is
    # not confirmed, never left holding the state.
    dc_with_deadline "$CONFIRM_SECS" dc_tree archive_whole "$ARCH" >"$T/whole" 2>"$T/whole.err"
    rc=$?
    err=$(grep . "$T/whole.err" | tail -n 1 | cut -c1-200)
    case $rc in
        0) ;;
        1) verdict teardown-incomplete "$(head -1 "$T/whole")" ;;
        124) verdict teardown-incomplete "the archive's files could not be checked within $CONFIRM_SECS seconds" ;;
        2) verdict teardown-incomplete "the archive's files could not be listed${err:+: $err}" ;;
        *) verdict teardown-incomplete "the archive's sizes could not be checked (status $rc)${err:+: $err}" ;;
    esac
    verdict teardown-confirmed "the instance and the job are gone and the archive is whole"
fi

# ---------------------------------------------------------------------------
# run
say "reading the verdict"
read_verdict || refused "$(cat "$T/why")"
[ "$KS" = "$WANT_KS" ] || refused "the key seal handed over is not the session's current verdict"
ROOT=$(dc_workspace_root) || refused "no workspace root found"

STEP=facts
say "re-reading the facts for $TOPIC"
while read -r ref sha; do
    [ -n "$ref" ] || continue
    repo=${ref%#*} n=${ref##*#}
    out=$(dc_with_deadline "$FETCH_SECS" "$GH" pr view "$n" --repo "$repo" --json state,mergeCommit 2>"$T/gh.err") \
        || refused "$ref could not be read: $(tail -1 "$T/gh.err")"
    printf '%s' "$out" | jq -e --arg s "$sha" '.state == "MERGED" and (.mergeCommit.oid // "") == $s' >/dev/null \
        || refused "$ref is not merged at $sha"
done <<EOF
$PRS
EOF
cid=${HANDOFF##*#issuecomment-}
hrepo=${HANDOFF#https://github.com/}; hrepo=$(printf '%s' "$hrepo" | cut -d/ -f1-2)
grep -Eq '^[1-9][0-9]*$' <<<"$cid" || refused "the handoff link is not a comment link"
out=$(dc_with_deadline "$FETCH_SECS" "$GH" api "repos/$hrepo/issues/comments/$cid" 2>"$T/gh.err") \
    || refused "the handoff comment could not be read: $(tail -1 "$T/gh.err")"
printf '%s' "$out" | jq -e '(.body // "") | test("[^[:space:]]")' >/dev/null || refused "the handoff comment is gone or empty"
if [ "$REMOVED" = 1 ]; then
    # Removed mode: the unit is already gone. Check that it is (neither
    # listing names it; a listing that can't be read refuses), then preserve
    # what survives. There is no job to check and no instance to inventory,
    # and nothing below this branch destroys or removes anything.
    NL=$(niwa_list) || refused "niwa list could not be read"
    printf '%s' "$NL" | jq -e --arg p "$IPATH" 'type == "array" and (any(.[]; .path == $p) | not)' >/dev/null \
        || refused "niwa lists an instance at $IPATH"
    printf '%s' "$NL" | jq -r '.[] | .session_name | strings' >"$T/niwa-sessions"
    while IFS= read -r n; do
        dc_session_matches "$TOPIC" "$n" && refused "niwa lists an instance for $TOPIC (session $n)"
    done <"$T/niwa-sessions"
    AG=$(agents) || refused "claude agents could not be read"
    printf '%s' "$AG" | jq -e --arg p "$IPATH" --arg j "$JOB" 'type == "array" and (any(.[]; .cwd == $p or ($j != "" and .id == $j)) | not)' >/dev/null \
        || refused "claude agents lists a job for $IPATH"
else
    AG=$(agents) || refused "claude agents could not be read"
    printf '%s' "$AG" | jq -e --arg j "$JOB" --arg p "$IPATH" --arg s "$SID" \
        '[.[] | select(.id == $j)] | length == 1 and .[0].cwd == $p and .[0].sessionId == $s' >/dev/null \
        || refused "job $JOB is no longer the job of $IPATH with session $SID"
    # Finished by the same reading as the verdict's: the listing's state is
    # activity on current Claude Code, so it isn't read.
    WHY=$(dc_job_finished "$CLAUDE_HOME" "$JOB" "$(printf '%s' "$AG" | jq -c --arg j "$JOB" '[.[] | select(.id == $j)][0]')") \
        || refused "job $JOB is no longer finished: $WHY"
    NL=$(niwa_list) || refused "niwa list could not be read"
    printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" '[.[] | select(.name == $n or .path == $p)] | length == 1 and .[0].name == $n and .[0].path == $p' >/dev/null \
        || refused "niwa no longer lists $INAME at $IPATH"

    STEP=inventory
    say "re-inventorying $IPATH"
    bash "$HERE/teardown-inventory.sh" --topic "$TOPIC" --instance "$IPATH" >"$T/inv" 2>&1
    case $? in
        0) ;;
        1) refused "the instance holds unique material now: $(grep -m1 '^unique' "$T/inv")" ;;
        *) refused "the inventory reads an error: $(grep -m1 '^error' "$T/inv" || tail -1 "$T/inv")" ;;
    esac
fi

# send_retired: the retired event (step 4a's), from what the pass already
# holds: the verdict, and the unit's request as the archived koto sessions
# name it (the capture's own rule: the earliest request a coordinator made),
# once there is an archive. Each field it doesn't have is left out, and the
# helper runs as a child with no stream of the pass's, its status ignored, so
# the pass's output, exit code and RESULT are the same whatever it does.
send_retired() {
    local req="" pr="" wd="" kv f
    f=()
    if [ -n "$ARCH" ] && ac_dispatch_request "$ARCH"/koto/*/ 2>/dev/null; then req=$AC_REQ; fi
    [ "$(printf '%s\n' "$PRS" | grep -c .)" = 1 ] && pr="github.com/${PRS%% *}"
    case "$DISPATCH" in '' | - | invalid) ;; *) wd=$DISPATCH ;; esac
    for kv in "unit.topic=$TOPIC" "unit.request=$req" "unit.koto_session=$SESSION" "unit.worker_session=$SID" \
        "unit.worker_dispatch=$wd" "unit.pr=$pr"; do
        [ -n "${kv#*=}" ] && f+=("$kv")
    done
    bash "$EMIT" event --scope unit-cost --kind retired --koto-dir "$ROOT" ${f[@]+"${f[@]}"} </dev/null >/dev/null 2>&1 || :
}

STEP=preserve
# A unit removed outside the pass with no surviving session has nothing to
# archive and no entry to post: its cost can't be read from anything. The
# pass still retires it.
if [ "$NOJOB" = 1 ]; then
    send_retired
    say "done: the unit was removed outside the pass and no session of it survives; nothing archived"
    exit 0
fi
ARCH="$ARCHIVE_ROOT/$(date -u +%Y-%m-%d)-$TOPIC-$JOB"
# The archive holds transcripts, which hold whatever the worker saw: only
# the user reads this pass's directory, and the root too when this pass
# creates it. A root that already exists keeps its mode: it may be a
# directory the user set up and shares.
if [ ! -d "$ARCHIVE_ROOT" ]; then
    mkdir -p "$ARCHIVE_ROOT" && chmod 700 "$ARCHIVE_ROOT" || { ARCH=""; refused "cannot create the archive root $ARCHIVE_ROOT"; }
fi
mkdir -p "$ARCH" && chmod 700 "$ARCH" || { ARCH=""; refused "cannot create the archive directory"; }
say "preserving into $ARCH"
: >"$T/copies"
# copy_file <src> <rel>: one file into the archive, listed for the check.
copy_file() { ac_copy_file "$ARCH" "$T" "$1" "$2" || refused "$AC_WHY"; }
# build_trees <dir>: the build trees under it (the header's rule) into
# $T/bt, one `<marker>\t<path>` per line, the path relative to <dir> with no
# leading `./`, outermost only, in byte order. Returns 1 when <dir> can't be
# listed.
build_trees() {
    local f d m
    : >"$T/bt.all"
    (cd "$1" && find . -type d -name node_modules -prune -print) >"$T/bt.nm" 2>/dev/null || return 1
    while IFS= read -r d; do
        [ -n "$d" ] && [ "$d" != . ] && printf 'node_modules\t%s\n' "${d#./}" >>"$T/bt.all"
    done <"$T/bt.nm"
    (cd "$1" && find . -type d -name node_modules -prune -o \
        -type f \( -name CACHEDIR.TAG -o -name .rustc_info.json -o -name .cargo-lock -o -name .package-cache \) -print) >"$T/bt.mk" 2>/dev/null || return 1
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        d=$(dirname "$f") m=${f##*/}
        # tmp/ itself is never a tree (the header says why).
        [ "$d" = . ] && continue
        # A marker is checked for what its tool writes, so a scratch file
        # that only shares the name keeps its directory in the archive.
        case "$m" in
            CACHEDIR.TAG) [ "$(head -c 43 "$1/$f" 2>/dev/null)" = "Signature: 8a477f597d28d172789f06886806bc55" ] || continue ;;
            .rustc_info.json) grep -q '"rustc_fingerprint"' "$1/$f" 2>/dev/null || continue ;;
        esac
        printf '%s\t%s\n' "$m" "${d#./}" >>"$T/bt.all"
    done <"$T/bt.mk"
    # Sorted by path, a tree comes before every path under it, so one pass
    # keeps the outermost and drops the rest, a second marker in a tree's own
    # directory included.
    LC_ALL=C sort -t '	' -k2 "$T/bt.all" | awk -F'\t' '
        { p = substr($0, length($1) + 2)
          for (i = 1; i <= n; i++) if (p == kept[i] || substr(p, 1, length(kept[i]) + 1) == kept[i] "/") next
          kept[++n] = p; print }' >"$T/bt"
}
# copy_job_tmp <src dir> <rel dir>: copy_tree, leaving out the build trees;
# each one left out goes on $T/trees.skipped (SKIPPED's source; not
# $T/skipped, which a case-insensitive file system takes for the same name)
# as `<bytes> <marker> <rel dir>/<path>`. Its bytes are summed from `ls -ln`,
# whose fifth field is the size on BSD and GNU alike (stat isn't on the
# suites' PATH), so no file in it is opened; a directory in it that can't be
# read adds nothing, so the figure is a floor. Nothing in a tree is copied,
# so an unreadable file there never refuses the pass.
copy_job_tmp() {
    local f m p b
    build_trees "$1" || refused "cannot list $1"
    (cd "$1" && find . -type d -name node_modules -prune -o -type f -print) >"$T/tree" 2>/dev/null || refused "cannot list $1"
    awk -F'\t' '
        FILENAME == ARGV[1] { root[++n] = "./" substr($0, length($1) + 2) "/"; next }
        { for (i = 1; i <= n; i++) if (substr($0, 1, length(root[i])) == root[i]) next; print }
    ' "$T/bt" "$T/tree" >"$T/tree.kept"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        copy_file "$1/${f#./}" "$2/${f#./}"
    done <"$T/tree.kept"
    while IFS='	' read -r m p; do
        [ -n "$p" ] || continue
        b=$( (cd "$1/$p" && find . -type f -exec ls -ln {} +) 2>/dev/null | awk '{ s += $5 } END { printf "%.0f\n", s }')
        printf '%s %s %s/%s\n' "$b" "$m" "$2" "$p" >>"$T/trees.skipped"
    done <"$T/bt"
}
[ -f "$TR" ] || refused "the transcript $TR is missing"
# The project directories of the instance (the header's rule).
: >"$T/trees.skipped"
ac_projects "$ARCH" "$T" "$CLAUDE_HOME" "$IPATH" || refused "$AC_WHY"
PPROJ=$AC_PPROJ
# The worker's own transcript is in one of them, or its row couldn't be read.
TRD=$(cd -P -- "$(dirname "$TR")" 2>"$T/cd.err" && pwd -P) || TRD=""
[ -n "$TRD" ] && [ -n "$PPROJ" ] && [ "$TRD" = "$PPROJ/${TRD##*/}" ] && grep -qxF -- "${TRD##*/}" "$T/taken" \
    || refused "the transcript $TR is not in a project directory of the instance"
J="$CLAUDE_HOME/jobs/$JOB"
if [ "$REMOVED" = 0 ]; then
    [ -f "$J/state.json" ] || refused "the job's state.json is missing"
    copy_file "$J/state.json" job/state.json
    [ -f "$J/timeline.jsonl" ] && copy_file "$J/timeline.jsonl" job/timeline.jsonl
    [ -d "$J/tmp" ] && copy_job_tmp "$J/tmp" job/tmp
    JTMP=$(cd "$J/tmp" 2>/dev/null && pwd -P) || JTMP="$J/tmp"
else
    # The job went with the unit: its koto sessions are found by the
    # instance path alone.
    J="$IPATH" JTMP="$IPATH"
fi
ac_koto_find "$T" "$KOTO_SESSIONS" "$IPATH" "$JTMP" "$J/tmp"
ac_koto_copy "$ARCH" "$T" || refused "$AC_WHY"
NK=$AC_NK
say "copied $(wc -l <"$T/copies" | tr -d ' ') files, $NK koto sessions"
# SKIPPED, in the MANIFEST like teardown.json, only when a tree was left out.
if [ -s "$T/trees.skipped" ]; then
    say "left out $(wc -l <"$T/trees.skipped" | tr -d ' ') build trees of job/tmp"
    copy_file "$T/trees.skipped" SKIPPED
fi
# teardown.json: what the pass acted on, written by the pass and checked
# into the MANIFEST like the copies. The pass only writes it; nothing here
# reads it back. niwa's dispatch id comes from the sealed verdict's
# `dispatch` line, kept only in the shape the handoff admitted; otherwise the
# reason it is missing is one of the cost capture's closed words.
jq -n -c --arg topic "$TOPIC" --arg name "$INAME" --arg path "$IPATH" --arg job "$JOB" --arg sid "$SID" \
    --argjson removed "$([ "$REMOVED" = 1 ] && echo true || echo false)" --arg d "$DISPATCH" '
    {topic: $topic,
     instance: {name: (if $name == "-" then null else $name end), path: $path},
     job: {id: $job, session: $sid},
     removed: $removed,
     niwa: (if $d == "" or $d == "-" then {dispatch_id: null, reason: "no source"}
            elif $d == "invalid" then {dispatch_id: null, reason: "invalid input"}
            else {dispatch_id: $d, reason: null} end)}' >"$T/teardown.json" || refused "cannot write teardown.json"
copy_file "$T/teardown.json" teardown.json
ac_manifest "$ARCH" "$T" || refused "$AC_WHY"
{
    printf '# Teardown of %s\n\n' "$TOPIC"
    if [ "$REMOVED" = 1 ]; then
        printf 'Taken %s by the coordinator'"'"'s teardown pass, after the unit was removed outside it: this is what survived.\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
        printf -- '- Instance: removed (%s)\n' "$IPATH"
        printf -- '- Claude Code job: removed; session %s (job id %s, from the session id)\n' "$SID" "$JOB"
    else
        printf 'Taken %s by the coordinator'"'"'s teardown pass, before anything was removed.\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
        printf -- '- Instance: %s (%s)\n' "$INAME" "$IPATH"
        printf -- '- Claude Code job: %s, session %s\n' "$JOB" "$SID"
    fi
    printf '%s\n' "$PRS" | sed 's/^/- Merged pull request: /'
    printf -- '- Handoff: %s\n\n' "$HANDOFF"
} >"$T/readme.head"
ac_readme "$ARCH" "$T" "$T/readme.head" "$T/trees.skipped"

# The retired event, once the archive is whole and before the capture, so a
# pass stopped during the capture has already sent it.
send_retired

# The cost capture: a child with none of the pass's streams (stdin empty,
# output to a file), under its own deadline, its status only ever a warning.
# It never calls refused or incomplete, and STEP goes back to destroy before
# anything can name it. The deadline is a backstop: unit-cost.sh keeps its
# reads to a 90-second budget and its post to 25, inside these 120.
STEP=capture
printf '%s\n' "$PRS" >"$T/prs"
dc_with_deadline "$CAPTURE_SECS" bash "$HERE/unit-cost.sh" capture --session "$SESSION" \
    --archive "$ARCH" --topic "$TOPIC" --prs-file "$T/prs" \
    </dev/null >/dev/null 2>"$T/capture.err" \
    || say "capture: no cost entry (status $?): $(tail -n 1 "$T/capture.err" 2>/dev/null | cut -c1-200)" >&2
# Removed mode ends here: the instance and the job are already gone, so the
# pass never reaches the destroy or the removal below.
if [ "$REMOVED" = 1 ]; then
    STEP=confirm
    printf 'done %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ARCH/RESULT"
    say "done $ARCH"
    exit 0
fi
STEP=destroy
say "destroying $INAME"
(cd "$ROOT" && "$NIWA" destroy --force "$INAME") >"$T/destroy" 2>&1 || incomplete "niwa destroy failed: $(tail -1 "$T/destroy")"
STEP=remove
say "removing job $JOB"
GONE=""
if ! "$CLAUDE_CLI" rm "$JOB" >"$T/rm" 2>&1; then
    # niwa destroy can remove the instance's owning job itself (niwa 0.34.1
    # on), leaving rm nothing to find. That is done only when rm said so and
    # the job is gone everywhere it is read: niwa no longer lists the
    # instance, the job has no directory and the agents listing has no row.
    # A wording change in rm's message only brings back the old incomplete.
    rmerr="claude rm failed: $(tail -1 "$T/rm")"
    grep -q 'No job matching' "$T/rm" || incomplete "$rmerr"
    NL=$(niwa_list) || incomplete "$rmerr; niwa list could not be read"
    printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" 'type == "array" and (any(.[]; .name == $n or .path == $p) | not)' >/dev/null \
        || incomplete "$rmerr; niwa still lists $INAME"
    # -e is false for a dangling link; a link left there is not a removal.
    if [ -e "$J" ] || [ -L "$J" ]; then incomplete "$rmerr; $J is still there"; fi
    AG=$(agents) || incomplete "$rmerr; claude agents could not be read"
    printf '%s' "$AG" | jq -e --arg j "$JOB" 'type == "array" and (any(.[]; .id == $j) | not)' >/dev/null \
        || incomplete "$rmerr; claude agents still lists job $JOB"
    # On RESULT's one line: confirm and the suites read its first word.
    GONE=" (remove: job $JOB was already removed by niwa destroy)"
    say "job $JOB was already removed by niwa destroy"
fi
STEP=confirm
NL=$(niwa_list) || incomplete "niwa list could not be read"
printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" 'any(.[]; .name == $n or .path == $p) | not' >/dev/null \
    || incomplete "niwa still lists $INAME"
AG=$(agents) || incomplete "claude agents could not be read"
printf '%s' "$AG" | jq -e --arg j "$JOB" 'any(.[]; .id == $j) | not' >/dev/null || incomplete "claude agents still lists job $JOB"
printf 'done %s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$GONE" >"$ARCH/RESULT"
say "done $ARCH"
exit 0
