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
lib_has_declaration() {
    tr -d '\r' < "$1" | grep -qF -- "$DECL_PREFIX"
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
# array in source order: {number, id, title, status, done, dependencies}.
# A feature heading is `### Feature <N>: <title>` or `### <PREFIX><N>: <title>`;
# features are numbered by position, as shirabe-validate numbers them. Status
# is the `**Status:**` line's value; `done` is true when it reads Done or
# Dropped (one trailing period tolerated), compared case-sensitively.
# Dependencies are the positions named by `Feature N`, `Features N and M`,
# `Features N, M` or `F<N>` on the `**Dependencies:**` line; a line opening
# with `None` names none, whatever prose follows.
lib_roadmap_features() {
    tr -d '\r' < "$1" | awk '
        function flush() { if (have) { gsub(/\t/, " ", title); gsub(/\t/, " ", status); gsub(/\t/, " ", deps)
            printf "%d\t%s\t%s\t%s\t%s\n", n, id, title, status, deps }; have = 0 }
        /^## / { if (infeat) { flush(); infeat = 0 } if ($0 ~ /^## Features[ \t]*$/) infeat = 1; next }
        !infeat { next }
        /^### / {
            flush()
            line = substr($0, 5)
            if (match(line, /^(Feature [0-9]+|[A-Za-z]+[0-9]+): /)) {
                n++; have = 1
                id = substr(line, 1, RLENGTH - 2); title = substr(line, RLENGTH + 1)
                status = ""; deps = ""
            }
            next
        }
        have && /^\*\*Status:\*\*/ { s = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", s); sub(/[ \t]+$/, "", s); status = s; next }
        have && /^\*\*Dependencies:\*\*/ { s = $0; sub(/^\*\*Dependencies:\*\*[ \t]*/, "", s); deps = s; next }
        END { if (infeat) flush() }' \
    | jq -R -s -c 'split("\n") | map(select(. != "") | split("\t")) | map({
            number: (.[0] | tonumber), id: .[1], title: (.[2] | .[0:120]), status: (.[3] | .[0:60]),
            done: (.[3] | test("^(Done|Dropped)\\.?$")),
            dependencies: (if (.[4] | test("^None\\b")) then [] else [(.[4] | scan("[Ff]eatures? ([0-9]+(?:(?:,? and |, | & )[0-9]+)*)") | .[0] | scan("[0-9]+") | tonumber),
                            (.[4] | scan("\\bF([0-9]+)\\b") | .[0] | tonumber)] | unique end)})'
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

# lib_parked <holdings-json-file> <out>: the Holdings rows as a JSON array,
# each with `parked` set. A row is parked when it has a Verified head and its
# pull request is open and not a draft (gh pr view in the linked repository);
# every other row is active. Local agents never have a row, so they are never
# counted. Returns 2 on a failed read.
lib_parked() {
    local n i row vh pr st
    n=$(jq length "$1") || return 2
    : > "$2.rows"
    i=0
    while [ "$i" -lt "$n" ]; do
        row=$(jq -c --argjson i "$i" '.[$i]' "$1")
        vh=$(printf '%s' "$row" | jq -r '.verified_head // ""')
        pr=$(printf '%s' "$row" | jq -r '.pull_request // ""')
        st=false
        if [ -n "$vh" ] && lib_pr_link "$pr"; then
            gh pr view "$LINK_NUM" --repo "$LINK_REPO" --json state,isDraft > "$2.pr" 2> /dev/null < /dev/null || return 2
            st=$(jq -r 'if .state == "OPEN" and .isDraft == false then "true" else "false" end' "$2.pr") || return 2
        fi
        printf '%s' "$row" | jq -c --argjson p "$st" '. + {parked: $p}' >> "$2.rows"
        i=$((i + 1))
    done
    jq -s -c '.' "$2.rows" > "$2" || return 2
}

# lib_bounds: CAP and PARKED_BOUND from the session's variables (defaults 5
# and 3 without a session, or when a variable is unset).
lib_bounds() {
    CAP=5 PARKED_BOUND=3
    [ -n "$SESSION" ] || return 0
    local vars
    vars=$(bash "$HERE/coord-log.sh" vars --session "$SESSION") || lib_die2 "cannot read the session's variables"
    CAP=$(printf '%s' "$vars" | jq -r '.CAP // "5"')
    PARKED_BOUND=$(printf '%s' "$vars" | jq -r '.PARKED_BOUND // "3"')
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
