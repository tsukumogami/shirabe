# record-common.sh -- shared helpers for /coordinate's record scripts. Sourced,
# never run: `. "$HERE/record-common.sh"` after the caller sets HERE, PROG and
# the flag globals below.
#
# It holds the pieces every record script repeats: the run's facts (scope,
# name, host) from the session or from the test-only override flags, the
# closed patterns, date checks, the GitHub reads the find, the open and the
# confirm all make (the open-issue listing, the discipline branch and its pull
# requests, the author-authority read), sealing a check's verdict, and the
# session checks every write makes first. It makes no GitHub write: writes
# live only in the agent-run scripts that call these helpers, and the record's
# body is written only by record-write-core.sh, which only those scripts
# source, so a lint over a check script's own text and this file finds only
# reads.
#
# Globals the caller sets before calling lib_facts:
#   SESSION   --session, may be empty when OVERRIDE=1 and the script only reads
#   SCOPE NAME REPO   --scope --name --repo (all three, or none)
#   REF       --ref (test override; write scripts take it from run-facts)
# lib_facts sets SCOPE NAME REPO (validated), ROADMAP (roadmap path, may be
# empty), and OVERRIDE (1 when the facts came from the flags).
#
# Requires: bash 3.2+, jq, and coord-log.sh beside this file.

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
# RE_NAME is a scope's name (a roadmap's or a discipline's), the codec's
# re_name: unlike a topic it may start with `.`, `_` or `-`.
RE_NAME='^[A-Za-z0-9._-]+$'
# RE_TOPIC is a dispatch topic, the Worker cell's shape (the codec's
# check_worker): a letter or digit, then letters, digits, `.`, `_` or `-`.
# Every script that holds a topic to its shape uses this one.
RE_TOPIC='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
RE_NUM='^[1-9][0-9]*$'
RE_SHA='^[0-9a-f]{40}$'
DECL_PREFIX='> This is a **coordinator record** for '
KOTO=${KOTO_BIN:-koto}
OVERRIDE=0
ROADMAP=
# Only a write script (lib_write_guard) reads SKIP_CHECKS, and each of those
# sets it from --skip-session-checks; every other script leaves it off.
: "${SKIP_CHECKS:=0}"

lib_die2() { echo "$PROG: $*" >&2; exit 2; }

# lib_redact: replace anything shaped like a GitHub token (a ghp_, gho_,
# ghu_, ghs_ or ghr_ prefix, or github_pat_, then six or more token
# characters) and drop control characters. The one token rule; lib_scrub and
# board-lib.sh's bl_scrub differ only in how much text they keep.
lib_redact() {
    sed -E 's/(gh[pousr]_[A-Za-z0-9_]{6,}|github_pat_[A-Za-z0-9_]{6,})/[redacted]/g' | tr -d '\000-\010\013\014\016-\037'
}

# lib_scrub: a gh error quoted inside one diagnostic, redacted and capped at
# 300 bytes, so it can never carry a credential.
lib_scrub() {
    lib_redact | head -c 300
}

# lib_facts: the run's scope, name and host. From the session's init variables
# (coord-log.sh vars), or from --scope --name --repo when a test passes them.
lib_facts() {
    if [ -n "$SCOPE$NAME$REPO" ]; then
        [ -n "$SCOPE" ] && [ -n "$NAME" ] && [ -n "$REPO" ] || { echo "$PROG: --scope, --name and --repo go together" >&2; exit 64; }
        OVERRIDE=1
        [ -n "$ROADMAP" ] || ROADMAP="docs/roadmaps/ROADMAP-$NAME.md"
    else
        [ -n "$SESSION" ] || { echo "$PROG: --session is required" >&2; exit 64; }
        local vars
        vars=$(bash "$HERE/coord-log.sh" vars --session "$SESSION") || lib_die2 "cannot read the session's variables"
        SCOPE=$(printf '%s' "$vars" | jq -r '.SCOPE // ""')
        REPO=$(printf '%s' "$vars" | jq -r '.HOST_REPO // ""')
        ROADMAP=$(printf '%s' "$vars" | jq -r '.ROADMAP // ""')
        if [ "$SCOPE" = roadmap ]; then
            NAME=$(basename "$ROADMAP" .md)
            NAME=${NAME#ROADMAP-}
        else
            NAME=$(printf '%s' "$vars" | jq -r '.DISCIPLINE // ""')
        fi
    fi
    case "$SCOPE" in roadmap|discipline) ;; *) echo "$PROG: scope is not roadmap or discipline" >&2; exit 64 ;; esac
    [[ $NAME =~ $RE_NAME ]] || { echo "$PROG: the scope's name is not a name" >&2; exit 64; }
    [[ $REPO =~ $RE_REPO ]] || { echo "$PROG: the host is not owner/repo" >&2; exit 64; }
    BRANCH="coordinate/discipline-$NAME"
    ISSUE_TITLE="Coordinator record: ROADMAP-$NAME"
    if [ "$SCOPE" = roadmap ]; then
        DECL="${DECL_PREFIX}ROADMAP-$NAME."
        CONTAINER=issue
    else
        DECL="${DECL_PREFIX}the $NAME discipline."
        CONTAINER=pr
    fi
}

# lib_valid_date YYYY-MM-DD: a real calendar date. Pure bash arithmetic, so it
# behaves the same on GNU and BSD systems, whose `date` parsers differ.
lib_valid_date() {
    case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 1 ;; esac
    local y m d max
    y=$((10#${1%%-*})); m=${1#*-}; m=$((10#${m%-*})); d=$((10#${1##*-}))
    [ "$m" -ge 1 ] && [ "$m" -le 12 ] && [ "$d" -ge 1 ] || return 1
    case $m in
        4|6|9|11) max=30 ;;
        2) if [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; }; then max=29; else max=28; fi ;;
        *) max=31 ;;
    esac
    [ "$d" -le "$max" ]
}

# lib_rotation_dates <title>: split a rotation title into ROT_START ROT_END.
# The name is compared as a literal prefix, never spliced into a regex.
lib_rotation_dates() {
    local want="docs(coordinate): $NAME rotation " rest
    # In a variable: bash 3.2 and 4+ disagree on quoting inside [[ =~ ]].
    local re='^([0-9]{4}-[0-9]{2}-[0-9]{2}) to ([0-9]{4}-[0-9]{2}-[0-9]{2})$'
    ROT_START= ROT_END=
    case "$1" in "$want"*) ;; *) return 1 ;; esac
    rest=${1#"$want"}
    [[ $rest =~ $re ]] || return 1
    ROT_START=${BASH_REMATCH[1]}
    ROT_END=${BASH_REMATCH[2]}
    lib_valid_date "$ROT_START" && lib_valid_date "$ROT_END" || return 1
    [ ! "$ROT_END" \< "$ROT_START" ]
}

# lib_has_declaration <file>: some line (CRLF tolerated) opens with the
# declaration text. Which scope it declares is record-parse.sh's to judge.
# No grep -q: stopping at the first match would SIGPIPE tr on a body larger
# than the pipe buffer, and pipefail would read that as no declaration.
lib_has_declaration() {
    tr -d '\r' < "$1" | grep -F -- "$DECL_PREFIX" >/dev/null
}

# lib_parse <body-file> <out-json>: record-parse.sh for this scope and
# container. Returns its exit code (0 canonical; 3 or 65 not a record of this
# scope; anything else an internal failure).
lib_parse() {
    bash "$HERE/record-parse.sh" --container "$CONTAINER" --expect-scope "$SCOPE:$NAME" "$1" > "$2" 2> "$2.err"
}

# lib_open_issues <out-json>: every open issue (not pull request) in REPO whose
# title is exactly the record's, through the paginated REST listing. Never a
# search: the search index lags a new issue, and a phrase search matches a
# longer -v2 title.
lib_open_issues() {
    local raw="$1.raw"
    gh api --method GET "repos/$REPO/issues?state=open&per_page=100" --paginate > "$raw" 2> "$raw.err" < /dev/null || return 2
    jq -s --arg t "$ISSUE_TITLE" 'add // [] | map(select((has("pull_request") | not) and .title == $t))
        | map({number, url: .html_url, title, body: (.body // ""), author: (.user.login // "")})' "$raw" > "$1" 2>/dev/null || return 2
}

# lib_discipline_read <dir>: the default branch, whether the record branch
# exists, and its same-repository pull requests into the default branch.
# Sets DEFAULT_BRANCH and BRANCH_EXISTS (1/0); writes <dir>/prs.json.
# Returns 2 on a failed read (anything but a 404 on the branch).
lib_discipline_read() {
    DEFAULT_BRANCH=$(gh api --method GET "repos/$REPO" --jq .default_branch 2> "$1/repo.err" < /dev/null) || return 2
    [[ $DEFAULT_BRANCH =~ ^[A-Za-z0-9._/-]+$ ]] || return 2
    local enc="coordinate%2Fdiscipline-$NAME"
    if gh api --method GET "repos/$REPO/branches/$enc" > "$1/branch.json" 2> "$1/branch.err" < /dev/null; then
        BRANCH_EXISTS=1
    elif grep -q 'HTTP 404' "$1/branch.err"; then
        BRANCH_EXISTS=0
    else
        return 2
    fi
    gh pr list --repo "$REPO" --head "$BRANCH" --state all --limit 100 \
        --json number,url,title,body,state,isDraft,isCrossRepository,baseRefName,headRefName,headRefOid,author \
        > "$1/prs.raw" 2> "$1/prs.err" < /dev/null || return 2
    jq --arg b "$DEFAULT_BRANCH" --arg h "$BRANCH" '[.[] | select(.isCrossRepository == false and .baseRefName == $b and .headRefName == $h)]' \
        "$1/prs.raw" > "$1/prs.json" 2>/dev/null || return 2
}

# lib_authority <issue|pullRequest> <number>: the candidate's author and last
# editor (the author when nobody edited it) each have write access to REPO.
# Returns 0 authorized, 1 not (AUTH_REASON says who), 2 a read failed: a
# failed read never adopts a record.
lib_authority() {
    local kind=$1 n=$2 q out author editor login perm seen=
    AUTH_REASON=
    q="query(\$owner: String!, \$name: String!, \$number: Int!) { repository(owner: \$owner, name: \$name) { $kind(number: \$number) { author { login } editor { login } } } }"
    out=$(gh api graphql -f query="$q" -f owner="${REPO%%/*}" -f name="${REPO#*/}" -F number="$n" < /dev/null) || return 2
    author=$(printf '%s' "$out" | jq -r --arg k "$kind" '.data.repository[$k].author.login // ""') || return 2
    editor=$(printf '%s' "$out" | jq -r --arg k "$kind" '.data.repository[$k].editor.login // ""') || return 2
    [ -n "$editor" ] || editor=$author
    for login in "$author" "$editor"; do
        [ "$login" = "$seen" ] && continue
        seen=$login
        if ! [[ $login =~ $RE_LOGIN ]]; then AUTH_REASON="no usable login"; return 1; fi
        perm=$(gh api --method GET "repos/$REPO/collaborators/$login/permission" --jq .permission < /dev/null) || return 2
        case "$perm" in
            admin|maintain|write) ;;
            *) AUTH_REASON="$login has $perm access"; return 1 ;;
        esac
    done
    return 0
}

# ENTRY_MARKER_PREFIX: a record entry's first line up to its kind, the one
# definition the entry's writer (record-append.sh) and its readers share.
ENTRY_MARKER_PREFIX='<!-- coordinator-record-entry v1 kind='

# lib_has_write_access <login>: 0 when <login> has admin, maintain or write
# access to REPO, 1 when it has less or isn't a collaborator (GitHub answers
# 404), 2 when the read failed. record-append.sh's reader keeps an entry only
# when its author passes.
lib_has_write_access() {
    local perm err
    [[ $1 =~ $RE_LOGIN ]] || return 1
    err=$(mktemp "${TMPDIR:-/tmp}/write-access.XXXXXX")
    if ! perm=$(gh api --method GET "repos/$REPO/collaborators/$1/permission" --jq .permission 2> "$err" < /dev/null); then
        if grep -q 'HTTP 404' "$err"; then rm -f "$err"; return 1; fi
        rm -f "$err"; return 2
    fi
    rm -f "$err"
    case "$perm" in admin|maintain|write) return 0 ;; *) return 1 ;; esac
}

# lib_emit <state> <token> <context-key> <detail-file>: finish a check. Under
# --no-seal print the bare token; otherwise store the detail as data in the
# context key, seal the token to this visit, and print the sealed token.
lib_emit() {
    if [ "$NO_SEAL" = 1 ]; then
        printf '%s\n' "$2"
        exit 0
    fi
    [ -n "$SESSION" ] || { echo "$PROG: sealing needs --session" >&2; exit 64; }
    if [ -n "$3" ]; then
        "$KOTO" context add "$SESSION" "$3" --from-file "$4" >/dev/null || lib_die2 "koto context add $3 failed"
    fi
    local sealed
    sealed=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$1" --token "$2") || lib_die2 "cannot seal the verdict"
    printf '%s\n' "$sealed"
    exit 0
}

# lib_slug: SLUG, the scope slug coordinate-open.sh names sessions by, from
# coord-log.sh slug, the one derivation both use.
lib_slug() {
    SLUG=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || lib_die2 "cannot derive the scope slug"
}

# lib_write_guard: every write refuses (exit 10) when the session wasn't
# created from the shipped template for this plugin root, when it isn't the
# one live session for its scope (coord-log.sh live-session; so a --session
# naming an older run of the same scope, still provenanced and pointing at
# the same record, is refused), or when the run has any directed transition
# (`koto next --to` skipped gates before koto 0.14.0, koto#251; kept as defence in depth).
# --skip-session-checks bypasses it, only with the test override flags.
lib_write_guard() {
    if [ "$SKIP_CHECKS" = 1 ]; then
        [ "$OVERRIDE" = 1 ] || { echo "$PROG: --skip-session-checks is only for tests with --scope --name --repo" >&2; exit 64; }
        return 0
    fi
    [ -n "$SESSION" ] || { echo "$PROG: --session is required" >&2; exit 64; }
    if ! bash "$HERE/coord-log.sh" provenance --session "$SESSION" > /dev/null 2>&1; then
        echo "$PROG: refused: the session fails provenance (not created from the shipped template for this plugin)" >&2
        exit 10
    fi
    local out rc live
    lib_slug
    live=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$SLUG" 2>/dev/null)
    rc=$?
    case $rc in
        0) [ "$live" = "$SESSION" ] || { echo "$PROG: refused: $SESSION is not the live $SLUG session ($live is)" >&2; exit 10; } ;;
        1) echo "$PROG: refused: no live $SLUG session; $SESSION has ended" >&2; exit 10 ;;
        3) echo "$PROG: refused: several live $SLUG sessions; restart the run" >&2; exit 10 ;;
        *) lib_die2 "cannot find the live $SLUG session" ;;
    esac
    out=$(bash "$HERE/coord-log.sh" directed-since --session "$SESSION" --from 0 2>/dev/null)
    rc=$?
    case $rc in
        0) ;;
        1) echo "$PROG: refused: the run has a directed transition ($(printf '%s' "$out" | head -1)); restart the run" >&2; exit 10 ;;
        *) lib_die2 "cannot read the session log" ;;
    esac
}

# lib_dispatched: has this run entered `dispatch`? Without a session (a test
# with overrides only) the answer is no.
lib_dispatched() {
    [ -n "$SESSION" ] || return 1
    bash "$HERE/coord-log.sh" entered --session "$SESSION" --state dispatch > /dev/null 2>&1
    local rc=$?
    [ $rc -eq 2 ] && lib_die2 "cannot read the session log"
    return $rc
}

# lib_drop_disposed <json-in> <json-out>: drop Deferrals rows already filed or
# closed. Carried rows and open rows stay. Returns 0 when a row was dropped.
lib_drop_disposed() {
    jq '.deferrals |= map(select((.disposition | startswith("filed ") or startswith("closed:")) | not))' "$1" > "$2" || lib_die2 "jq failed"
    [ "$(jq '.deferrals | length' "$1")" != "$(jq '.deferrals | length' "$2")" ]
}

lib_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# lib_run_stamp: RUN, the run's own stamp, the UTC time in the session's name
# (coordinate-<slug>-<YYYYMMDDTHHMMSSZ>, one per run). Every Decisions stamp
# starts with it, so a write keyed on a log sequence is never mistaken for
# another run's: sequences restart with each run, the record outlives them.
lib_run_stamp() {
    RUN=${SESSION##*-}
    [[ $RUN =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || lib_die2 "the session's name carries no run stamp: $SESSION"
}

# lib_log_readable: the session's log is there and in a schema coord-log.sh
# knows. A check calls it before its first GitHub read, so a run whose log
# can't be read reads nothing; every event it needs comes through coord-log.sh.
lib_log_readable() {
    bash "$HERE/coord-log.sh" count --session "$SESSION" > /dev/null
}

# lib_unit <before-seq> <event> <holdings-fn>: set UNIT to the dispatch topic
# of the unit the run's latest arrival names (coord-log.sh unit, with
# --before and --event when given). On the message path that is the wait
# evidence's unit. On the leg path (wait_leg, then take_report) the hub's
# evidence carries no unit, so the unit is the one Holdings row whose Return
# path is the `leg <request>:<leg>` coord-log.sh prints; <holdings-fn> is a
# function printing the Holdings rows as a JSON array, called only then (it
# may exit the script on a failed read). On the leg path UNIT_LEG is that
# leg and LEG_ROWS how many rows carry it (both empty otherwise). Returns 0
# UNIT set; 1 no arrival, or evidence whose unit is empty; 3 an arrival
# naming no unit (not a topic, or a leg no single row carries). Exits 2 on a
# read failure.
lib_unit() {
    local before=$1 event=$2 fn=$3 out rc rows n
    UNIT= UNIT_LEG= LEG_ROWS=
    set --
    [ -n "$before" ] && set -- --before "$before"
    [ -n "$event" ] && set -- "$@" --event "$event"
    out=$(bash "$HERE/coord-log.sh" unit --session "$SESSION" "$@" 2> /dev/null)
    rc=$?
    case $rc in 0) ;; 1|3) return $rc ;; *) lib_die2 "cannot read the session log" ;; esac
    case "$out" in
        "topic ") return 1 ;;
        "topic "*) UNIT=${out#topic } ;;
        "leg "*)
            rows=$("$fn") || exit 2
            n=$(printf '%s' "$rows" | jq --arg l "$out" '[.[] | select(.return_path == $l)] | length') || lib_die2 "the Holdings rows are not JSON"
            UNIT_LEG=$out LEG_ROWS=$n
            [ "$n" = 1 ] && UNIT=$(printf '%s' "$rows" | jq -r --arg l "$out" '.[] | select(.return_path == $l) | .worker')
            ;;
    esac
    [[ $UNIT =~ $RE_TOPIC ]] || { UNIT=; return 3; }
}

# lib_run_ref: REF from --ref (tests) or from coord-log.sh run-facts.
# Returns 1 when the run has no found record; exits 2 on a read failure.
lib_run_ref() {
    if [ "$OVERRIDE" = 1 ]; then
        [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
    else
        [ -z "$REF" ] || { echo "$PROG: --ref is only for tests with the override flags" >&2; exit 64; }
        local facts rc
        facts=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION" 2>/dev/null)
        rc=$?
        [ $rc -eq 1 ] && return 1
        [ $rc -eq 0 ] || lib_die2 "cannot read the run's facts"
        REF=$(printf '%s' "$facts" | jq -r '.ref')
    fi
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: the record number is not a number" >&2; exit 64; }
}

# ---- the turn's and the close-outs' reads -----------------------------------

# lib_default_branch: set DEFAULT_BRANCH from the host. Returns 2 on a failed read.
lib_default_branch() {
    DEFAULT_BRANCH=$(gh api --method GET "repos/$REPO" --jq .default_branch 2> /dev/null < /dev/null) || return 2
    [[ $DEFAULT_BRANCH =~ ^[A-Za-z0-9._/-]+$ ]] || return 2
}

# lib_b64d <in> <out>: decode base64, ignoring line breaks and spaces (GitHub
# wraps it in lines). GNU decodes with -d, older macOS with -D.
lib_b64d() {
    tr -d '\n\r ' < "$1" > "$1.flat"
    base64 -d < "$1.flat" > "$2" 2> /dev/null || base64 -D < "$1.flat" > "$2" 2> /dev/null
}

# lib_file_at <path> <ref> <out>: a file's bytes at a ref, through the contents
# API. Returns 0 read, 1 absent (404), 2 a read or decode failed.
lib_file_at() {
    if ! gh api --method GET "repos/$REPO/contents/$1?ref=$2" --jq .content > "$3.b64" 2> "$3.err" < /dev/null; then
        grep -q 'HTTP 404' "$3.err" && return 1
        return 2
    fi
    lib_b64d "$3.b64" "$3" || return 2
}

# lib_roadmap_path: check ROADMAP's closed shape (docs/roadmaps/.../ROADMAP-*.md,
# no `..`). Exits 64 otherwise.
lib_roadmap_path() {
    local re='^docs/roadmaps/([A-Za-z0-9._-]+/)*ROADMAP-[A-Za-z0-9._-]+\.md$'
    [[ $ROADMAP =~ $re ]] || { echo "$PROG: the roadmap path is not docs/roadmaps/.../ROADMAP-<name>.md" >&2; exit 64; }
    case "$ROADMAP" in *..*) echo "$PROG: the roadmap path holds .." >&2; exit 64 ;; esac
}

# lib_roadmap_features <roadmap.md>: the features under `## Features`, as a JSON
# array in source order: {number, id, title, status, finished, done,
# dependencies}. The picker's reading of a roadmap of either version, its
# rules applied in this order:
#   1. An item is a `### <tag>: <title>` heading whose tag is `Feature <N>` or
#      `<PREFIX><N>` with an optional lower-case letter (`AB10a`); any other
#      `### ` heading ends the item before it. Items are numbered by
#      position, as shirabe-validate numbers them; `id` is the tag.
#   2. `finished` when the `**Status:**` value starts with Done or Shipped
#      followed by its end or a character other than a letter, digit or
#      hyphen; closed the same way with Dropped. Case-sensitive, so a
#      missing Status, `Doneness` or `done` is neither. `done` is finished
#      or closed.
#   3. The Dependencies paragraph is the `**Dependencies:**` line and the
#      lines below it, joined with single spaces, up to a blank line, the
#      next field line or a heading. One whose first word is None names none.
#   4. A tag followed by an optional `(` and then soft, optional, preferred,
#      sequencing-preferred or `paced by` (any case) is a soft mention: the
#      tag and its marker are struck out together, so a hard mention of the
#      same tag elsewhere still counts and a leftover marker can't make rule
#      6 drop the sentence (`AB2 soft, AB5` still names AB5).
#   5. Parenthesised text goes, innermost pair first, replaced by nothing so
#      `Features 1 (x), 2 and 3` still reads as one list (at most 20 passes;
#      an unbalanced paren stays rather than loop).
#   6. The rest splits into sentences at `.` or `;` and whitespace; one
#      whose first word is soft (any case) goes.
#   7. What is left names `Feature N`, `Features N, M and K` and `F<N>`
#      (the item tagged `Feature N` when there is one, else the Nth item),
#      and every whole word equal to another item's tag. Soft mentions, the
#      item itself and tags no item carries are not dependencies.
# `dependencies` is those positions, ascending, each once. A paragraph over
# 4096 bytes fails the read: non-zero, the item's tag on stderr, prefixed by
# the caller's PROG.
lib_roadmap_features() {
    local tsv
    # LC_ALL=C: length() counts bytes, and the classes are ASCII.
    tsv=$(tr -d '\r' < "$1" | LC_ALL=C awk -v prog="${PROG:-record-common}" '
        function flush() {
            if (have) {
                gsub(/\t/, " ", title); gsub(/\t/, " ", status); gsub(/\t/, " ", deps)
                # exit still runs END; `failed` keeps END from flushing again.
                if (length(deps) > 4096) {
                    printf "%s: %s: the Dependencies paragraph is over 4096 bytes\n", prog, id > "/dev/stderr"
                    failed = 1; exit 3
                }
                printf "%d\t%s\t%s\t%s\t%s\n", n, id, title, status, deps
            }
            have = 0; indeps = 0
        }
        /^## / { if (infeat) { flush(); infeat = 0 } if ($0 ~ /^## Features[ \t]*$/) infeat = 1; next }
        !infeat { next }
        indeps && (/^[ \t]*$/ || /^\*\*[A-Z][A-Za-z ]*:\*\*/ || /^#+([ \t]|$)/) { indeps = 0 }
        indeps { s = $0; sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); deps = (deps == "" ? s : deps " " s); next }
        /^### / {
            flush()
            line = substr($0, 5)
            if (match(line, /^(Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?): /)) {
                n++; have = 1
                id = substr(line, 1, RLENGTH - 2); title = substr(line, RLENGTH + 1)
                status = ""; deps = ""
            }
            next
        }
        have && /^\*\*Status:\*\*/ { s = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", s); sub(/[ \t]+$/, "", s); status = s; next }
        have && /^\*\*Dependencies:\*\*/ { s = $0; sub(/^\*\*Dependencies:\*\*[ \t]*/, "", s); sub(/[ \t]+$/, "", s); deps = s; indeps = 1; next }
        END { if (infeat && !failed) flush() }') || return
    printf '%s\n' "$tsv" | jq -R -s -c 'split("\n") | map(select(. != "") | split("\t"))
        | map(.[1]) as $ids | length as $count
        # num: `Feature N` or `F<N>`, the item tagged `Feature N`, else the Nth.
        | def num($n): ($ids | index("Feature \($n)")) as $i
            | if $i != null then $i + 1 elif $n >= 1 and $n <= $count then $n else empty end;
          def tag($t): range(0; $count) | select($ids[.] == $t) | . + 1;
          def named: (scan("\\b(?i:features?) ([0-9]+(?:(?:,? and |, | & )[0-9]+)*)") | .[0] | scan("[0-9]+") | tonumber | num(.)),
              (scan("\\bF([0-9]+)\\b") | .[0] | tonumber | num(.)),
              (scan("[A-Za-z0-9]+") | tag(.));
          def desoft: gsub("\\b(?<t>(?i:feature) [0-9]+|[A-Za-z]+[0-9]+[a-z]?)(?<m>\\s*\\(?\\s*(?i:soft|optional|preferred|sequencing-preferred|paced by)\\b)"; "");
          def unparen: reduce range(20) as $_ (.; if test("\\([^()]*\\)") then gsub("\\([^()]*\\)"; "") else . end);
          def deps($p; $self): if ($p | test("^None([^A-Za-z0-9]|$)")) then [] else
              ([$p | desoft | unparen | splits("[.;]\\s+") | select(test("^\\s*(?i:soft)\\b") | not) | named] | unique)
              - [$self] end;
          def opens($w): test("^(" + $w + ")([^A-Za-z0-9-]|$)");
        map({number: (.[0] | tonumber), id: .[1], title: (.[2] | .[0:120]), status: (.[3] | .[0:60]),
             finished: (.[3] | opens("Done|Shipped")), done: (.[3] | opens("Done|Shipped|Dropped")),
             dependencies: deps(.[4] // ""; .[0] | tonumber)})'
}

# lib_pr_link <cell>: split a Pull request cell `[#n](https://github.com/o/r/pull/n)`
# into LINK_REPO and LINK_NUM. Returns 1 when the cell isn't that shape or the
# two numbers differ. The one bash parser of the cell; record-codec.jq's
# pr_link is the jq one, with the same grammar.
lib_pr_link() {
    local re='^\[#([0-9]+)\]\(https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)\)$'
    LINK_REPO= LINK_NUM=
    [[ $1 =~ $re ]] || return 1
    [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[3]}" ] || return 1
    LINK_REPO=${BASH_REMATCH[2]}
    LINK_NUM=${BASH_REMATCH[1]}
    [[ $LINK_NUM =~ $RE_NUM ]]
}

# lib_pr_ref <ref>: split a pull request as a report names it, its URL
# `https://github.com/o/r/pull/n` (one trailing `/` allowed) or `o/r#n`, into
# LINK_REPO and LINK_NUM. Returns 1 on any other shape.
lib_pr_ref() {
    local url='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?$'
    local short='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([1-9][0-9]*)$'
    LINK_REPO= LINK_NUM=
    [[ $1 =~ $url ]] || [[ $1 =~ $short ]] || return 1
    LINK_REPO=${BASH_REMATCH[1]}
    LINK_NUM=${BASH_REMATCH[2]}
}

# lib_report_pr: set REPORT_PR to the pull request the run's latest report
# names, as it names it; empty when it names none. Call it after lib_unit ""
# report, whose UNIT_LEG says which path the report came by. On the leg path
# it is the `pr` of the result koto holds for that leg, promoted by the
# worker's own session: koto's record, never the worker_report text. On the
# message path it is the `pull_request` field of the latest `wait` evidence
# whose event is report or progress, the arrival lib_unit read. A value that isn't a
# string is kept as JSON, so it fails lib_pr_ref rather than reading as none.
# Exits 2 on a failed read.
lib_report_pr() {
    local leg req out rc
    REPORT_PR=
    if [ -n "$UNIT_LEG" ]; then
        leg=${UNIT_LEG#leg }
        req=${leg%%:*}
        leg=${leg#*:}
        out=$("$KOTO" request get "$req" < /dev/null 2> /dev/null) || lib_die2 "cannot read request $req"
        REPORT_PR=$(printf '%s' "$out" | jq -r --arg l "$leg" '
            (.request // .) | .legs[$l] // empty
            | select(.disposition == "resolved" and .result_source == "promoted")
            | .result.payload | if type == "object" then .pr else null end
            | if . == null then "" elif type == "string" then . else tojson end') \
            || lib_die2 "koto's record of request $req is not JSON"
    else
        out=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait --where 'event=report|progress' 2> /dev/null)
        rc=$?
        case $rc in 0) ;; 1) return 0 ;; *) lib_die2 "cannot read the session log" ;; esac
        REPORT_PR=$(printf '%s' "$out" | jq -r '.fields.pull_request
            | if . == null then "" elif type == "string" then . else tojson end') || lib_die2 "the wait evidence is not JSON"
    fi
    # Surrounding blanks are how a person types it, not part of the name.
    REPORT_PR=$(printf '%s' "$REPORT_PR" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
}

# lib_in_scope <repo> <holdings-json-file>: is <repo> the host ($REPO) or the
# Repo of a Holdings row? Compared case-insensitively. The scope a report's
# pull request must be in.
lib_in_scope() {
    jq -e --arg r "$1" --arg h "$REPO" '($r | ascii_downcase) as $l
        | ($l == ($h | ascii_downcase)) or any(.[]; (.repo | ascii_downcase) == $l)' "$2" > /dev/null
}

# lib_pr_held <repo> <number> <topic> <holdings-json-file>: does a Holdings row
# other than <topic>'s link <repo>#<number>? Such a pull request's owner is
# ambiguous, so it is reported, never adopted.
lib_pr_held() {
    jq -e -L "$HERE" --arg r "$1" --arg n "$2" --arg t "$3" 'include "record-codec";
        any(.[]; .worker != $t and ((.pull_request // "" | pr_link) as $p
            | $p != null and $p.number == $n and ($p.repo | ascii_downcase) == ($r | ascii_downcase)))' "$4" > /dev/null
}

# lib_row_merged <row-json>: the row's merge was confirmed and it waits for
# its worker's teardown: a Verified head kept and the Pull request cell
# blank, which only the cleared cell after a confirmed merge writes
# (record-confirm.sh; record-holding.sh's header keeps the rule). The one
# definition pick, dispatch_check and the quiet check read. Reconcile's report
# reads the same row more narrowly, as merged only when every pull request on
# its branch is merged, because it reports what it measured.
lib_row_merged() {
    printf '%s' "$1" | jq -e '((.verified_head // "") != "") and ((.pull_request // "") == "")' > /dev/null
}

# lib_parked <holdings-json-file> <out>: the Holdings rows as a JSON array,
# each with `parked` and `merged` set. A row is parked when it has a Verified
# head and its pull request is open and not a draft (gh pr view in the linked
# repository). A row is merged when it has a Verified head and a blank Pull
# request cell: a confirmed merge clears the cell and keeps the row until its
# worker's teardown (record-confirm.sh), and nothing else writes that pair.
# Every other row is active. Local agents never have a row, so they are never
# counted. Returns 2 on a failed read.
lib_parked() {
    local n i row vh pr st mg
    n=$(jq length "$1") || return 2
    : > "$2.rows"
    i=0
    while [ "$i" -lt "$n" ]; do
        row=$(jq -c --argjson i "$i" '.[$i]' "$1")
        vh=$(printf '%s' "$row" | jq -r '.verified_head // ""')
        pr=$(printf '%s' "$row" | jq -r '.pull_request // ""')
        st=false mg=false
        lib_row_merged "$row" && mg=true
        if [ -n "$vh" ] && lib_pr_link "$pr"; then
            gh pr view "$LINK_NUM" --repo "$LINK_REPO" --json state,isDraft > "$2.pr" 2> /dev/null < /dev/null || return 2
            st=$(jq -r 'if .state == "OPEN" and .isDraft == false then "true" else "false" end' "$2.pr") || return 2
        fi
        printf '%s' "$row" | jq -c --argjson p "$st" --argjson m "$mg" '. + {parked: $p, merged: $m}' >> "$2.rows"
        i=$((i + 1))
    done
    jq -s -c '.' "$2.rows" > "$2" || return 2
}

# lib_bounds [record-json]: CAP and PARKED_BOUND from the session's variables
# (defaults 5 and 3 without a session, or when a variable is unset). Given the
# record as JSON (parsed, or record-state.sh --list), a `cap` row in its Run
# section wins over the variable: a cap a person changed is in the record, and
# survives a restart that didn't pass it. Every reader of the cap comes here,
# so they agree on it.
lib_bounds() {
    CAP=5 PARKED_BOUND=3
    if [ -n "$SESSION" ]; then
        local vars
        vars=$(bash "$HERE/coord-log.sh" vars --session "$SESSION") || lib_die2 "cannot read the session's variables"
        CAP=$(printf '%s' "$vars" | jq -r '.CAP // "5"')
        PARKED_BOUND=$(printf '%s' "$vars" | jq -r '.PARKED_BOUND // "3"')
    fi
    if [ -n "${1-}" ]; then
        local rc
        rc=$(jq -r '[(.run // [])[] | select(.key == "cap") | .value][0] // empty' "$1") || lib_die2 "cannot read the record's Run section"
        [ -z "$rc" ] || CAP=$rc
    fi
    [[ $CAP =~ $RE_NUM ]] && [[ $PARKED_BOUND =~ $RE_NUM ]] || lib_die2 "CAP or PARKED_BOUND is not a number"
}

# lib_epoch <time>: seconds since the epoch for YYYY-MM-DDTHH:MM[:SS[.fff]]Z,
# in bash arithmetic so GNU and BSD systems agree. Returns 1 on another shape.
lib_epoch() {
    local re='^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.[0-9]+)?)?Z$'
    [[ $1 =~ $re ]] || return 1
    local y=$((10#${BASH_REMATCH[1]})) m=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
    local H=$((10#${BASH_REMATCH[4]})) M=$((10#${BASH_REMATCH[5]})) S=0
    [ -n "${BASH_REMATCH[7]}" ] && S=$((10#${BASH_REMATCH[7]}))
    lib_valid_date "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" || return 1
    [ "$y" -ge 1970 ] || return 1
    y=$(( m <= 2 ? y - 1 : y ))
    local era=$(( y / 400 ))
    local yoe=$(( y - era * 400 ))
    local doy=$(( (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1 ))
    local doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    echo $(( (era * 146097 + doe - 719468) * 86400 + H * 3600 + M * 60 + S ))
}
