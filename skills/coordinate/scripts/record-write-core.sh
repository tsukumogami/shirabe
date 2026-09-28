# record-write-core.sh -- the coordinator record's one write path. Sourced, never
# run, and only by the agent-run write scripts (record-write.sh, which
# record-holding.sh calls, and the decision writer); no check script sources
# it, which keeps record-common.sh's promise that everything a check sources
# only reads.
#
# core_write re-reads the target and writes the whole body, after the checks
# record-write.sh's header lists. Two of them live only here:
#   - the Decisions section may be changed only by a script that sets
#     DECISIONS_WRITER=1 after sourcing this file; every other writer sets it to
#     0 itself, so a value in the environment never counts (exit 65);
#   - a rendered body over RECORD_BUDGET bytes is refused before GitHub sees it
#     (exit 13, record-full), leaving room under GitHub's 65,536-byte limit.
#
# The caller has sourced record-common.sh, run lib_facts and lib_write_guard,
# and set PROG, HERE, SESSION, SCOPE, NAME, REPO, REF, BODY, END, CLOSE and
# DECISIONS_WRITER.

# RECORD_BUDGET: the largest body core_write sends, in bytes.
RECORD_BUDGET=60000

core_write() {
    if [ -z "$REF" ]; then
        FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION" 2>/dev/null)
        case $? in
            0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
            1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
            *) lib_die2 "cannot read the run's facts" ;;
        esac
    fi
    [[ $REF =~ $RE_NUM ]] || usage

    T=$(mktemp -d "${TMPDIR:-/tmp}/record-write.XXXXXX")
    trap 'rm -rf "$T"' EXIT

    lib_parse "$BODY" "$T/parsed.json"
    case $? in
        0) ;;
        3|65) echo "$PROG: refused: the body is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 65 ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac

    # The target, re-read now.
    if [ "$SCOPE" = roadmap ]; then
        gh issue view "$REF" --repo "$REPO" --json state,body,url > "$T/target.json" 2> "$T/r.err" < /dev/null || lib_die2 "cannot read issue #$REF"
    else
        gh pr view "$REF" --repo "$REPO" --json state,body,url,title,headRefName,isCrossRepository > "$T/target.json" 2> "$T/r.err" < /dev/null || lib_die2 "cannot read pull request #$REF"
    fi
    jq -r '.body // ""' "$T/target.json" | tr -d '\r' > "$T/live.md" || lib_die2 "the target read is not JSON"
    STATE=$(jq -r '.state' "$T/target.json")
    URL=$(jq -r '.url' "$T/target.json")
    [ "$STATE" = OPEN ] || { echo "$PROG: refused: #$REF is $STATE, not an open record" >&2; exit 10; }
    grep -qxF -- "$DECL" "$T/live.md" || { echo "$PROG: refused: #$REF does not carry this scope's declaration line" >&2; exit 10; }
    # Compare and swap on the Written: line. The body carries the Written: time of
    # the version it was edited from; the live body must still carry that time, or
    # someone wrote the record since it was read and this write would lose their
    # change. A live body that no longer parses as a canonical record has changed
    # too.
    BASE=$(jq -r '.written // ""' "$T/parsed.json")
    if lib_parse "$T/live.md" "$T/live.json" 2> /dev/null; then
        LIVE_W=$(jq -r '.written // ""' "$T/live.json")
    else
        LIVE_W="(not a canonical record)"
    fi
    if [ -z "$BASE" ] || [ "$BASE" != "$LIVE_W" ]; then
        echo "$PROG: refused: record-changed: #$REF was written at $LIVE_W, but this body was edited from ${BASE:-no version}; re-read it and redo the change" >&2
        exit 12
    fi
    if [ "$SCOPE" = discipline ]; then
        [ "$(jq -r '.headRefName' "$T/target.json")" = "$BRANCH" ] && [ "$(jq -r '.isCrossRepository' "$T/target.json")" = false ] \
            || { echo "$PROG: refused: #$REF is not on $BRANCH in $REPO" >&2; exit 10; }
    fi
    # The Decisions section changes only through the decision writer, which
    # checks each transition; any other write must carry it as the live record
    # has it.
    if [ "${DECISIONS_WRITER:-0}" != 1 ] \
       && [ "$(jq -cS '.decisions // null' "$T/parsed.json")" != "$(jq -cS '.decisions // null' "$T/live.json")" ]; then
        echo "$PROG: refused: the Decisions section changes only through record-decision.sh; carry it as the live record has it" >&2
        exit 65
    fi

    # A public host never names a private repository: not in a Holdings Repo, not
    # in a Pull request link, not in a Side effects Target (an owner/repo token,
    # owner/repo#n, or a github.com URL). A named repository the host can't read
    # (404) can't be shown public, so it is refused too. This finds the
    # repositories the body names and reads each one's visibility; the render
    # below refuses a cell naming any on the list (the codec's names_repo, the one
    # test of whether a cell names a repository).
    PRIVATE=
    HOST_PRIVATE=$(gh api --method GET "repos/$REPO" --jq .private 2> /dev/null < /dev/null) || lib_die2 "cannot read $REPO's visibility"
    if [ "$HOST_PRIVATE" = false ]; then
        jq -r -L "$HERE" 'include "record-codec";
            def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
            [ (.holdings[] | .repo, (.pull_request | pr_link_parts | .r)),
              ((.side_effects[] | (.target // "")),
               ((.decisions.entries // [])[] | .[d_text_cols[]] // "") | tostring
                | ( (scan("github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)") | .[0] | clean),
                    (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
                     | scan("(?:^|[\\s(\\[<,;:])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?=#[0-9]|[\\s)\\]>,;:]|$)") | .[0] | clean) )) ]
            | map(select(. != "")) | unique | .[]' "$T/parsed.json" > "$T/named" || lib_die2 "jq failed"
        while IFS= read -r r; do
            [[ $r =~ $RE_REPO ]] || { echo "$PROG: refused: $r is not owner/repo" >&2; exit 65; }
            [ "$r" = "$REPO" ] && continue
            if ! P=$(gh api --method GET "repos/$r" --jq .private 2> "$T/v.err" < /dev/null); then
                grep -q 'HTTP 404' "$T/v.err" || lib_die2 "cannot read $r's visibility"
                P=unreadable
            fi
            [ "$P" = false ] || PRIVATE="$PRIVATE${PRIVATE:+,}$r"
        done < "$T/named"
    fi

    # The body is always re-rendered with this script's own Written: time: the
    # time in the coordinator's body is never trusted, because record-confirm.sh
    # reads it as proof a write came after an event. Once the run has entered
    # dispatch, deferrals already filed or closed are dropped first.
    cp "$T/parsed.json" "$T/next.json"
    if lib_dispatched && lib_drop_disposed "$T/parsed.json" "$T/dropped.json"; then
        mv "$T/dropped.json" "$T/next.json"
    fi
    jq 'del(.written)' "$T/next.json" | bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(lib_now)" --private-repos "$PRIVATE" \
        > "$T/body.md" 2> "$T/render.err" || {
        echo "$PROG: refused:" >&2; lib_scrub < "$T/render.err" >&2; echo >&2
        [ -z "$PRIVATE" ] || echo "$PROG: private, or unreadable from the public host $REPO: $PRIVATE" >&2
        exit 65; }
    SIZE=$(wc -c < "$T/body.md" | tr -d ' ')
    if [ "$SIZE" -gt "$RECORD_BUDGET" ]; then
        echo "$PROG: refused: record-full: the body would be $SIZE bytes, over the $RECORD_BUDGET-byte budget; compact settled decisions or prune the record" >&2
        exit 13
    fi
    OUT="$T/body.md"

    if [ "$SCOPE" = roadmap ]; then
        gh issue edit "$REF" --repo "$REPO" --body-file "$OUT" > /dev/null 2> "$T/w.err" < /dev/null \
            || { echo "$PROG: the issue edit failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
        if [ "$CLOSE" = 1 ]; then
            gh issue close "$REF" --repo "$REPO" > /dev/null 2> "$T/w.err" < /dev/null \
                || { echo "$PROG: the body was written but the close failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
        fi
    else
        set -- --body-file "$OUT"
        if [ -n "$END" ]; then
            lib_rotation_dates "$(jq -r '.title' "$T/target.json")" || { echo "$PROG: refused: #$REF's title is not this rotation's title" >&2; exit 10; }
            if [ "$END" \< "$ROT_START" ]; then echo "$PROG: refused: the end $END is before the rotation's start $ROT_START" >&2; exit 65; fi
            set -- "$@" --title "docs(coordinate): $NAME rotation $ROT_START to $END"
        fi
        gh pr edit "$REF" --repo "$REPO" "$@" > /dev/null 2> "$T/w.err" < /dev/null \
            || { echo "$PROG: the pull request edit failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }
    fi
    printf '%s\n' "$URL"
}
