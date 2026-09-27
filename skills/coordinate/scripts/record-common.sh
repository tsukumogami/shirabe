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
# live only in the agent-run scripts that call these helpers, so a lint over
# a check script's own text and this file finds only reads.
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
RE_NAME='^[A-Za-z0-9._-]+$'
RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
RE_NUM='^[1-9][0-9]*$'
RE_SHA='^[0-9a-f]{40}$'
DECL_PREFIX='> This is a **coordinator record** for '
KOTO=${KOTO_BIN:-koto}
OVERRIDE=0
ROADMAP=

lib_die2() { echo "$PROG: $*" >&2; exit 2; }

# lib_scrub: cap text at 300 bytes and replace anything shaped like a GitHub
# token, so a gh error quoted in a diagnostic can never carry a credential.
lib_scrub() {
    sed -E 's/(gh[pousr]_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]{10,})/[redacted]/g' | tr -d '\000-\010\013\014\016-\037' | head -c 300
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
    out=$(gh api graphql -f query="$q" -f owner="${REPO%%/*}" -f name="${REPO#*/}" -F number="$n" 2>/dev/null < /dev/null) || return 2
    author=$(printf '%s' "$out" | jq -r --arg k "$kind" '.data.repository[$k].author.login // ""' 2>/dev/null) || return 2
    editor=$(printf '%s' "$out" | jq -r --arg k "$kind" '.data.repository[$k].editor.login // ""' 2>/dev/null) || return 2
    [ -n "$editor" ] || editor=$author
    for login in "$author" "$editor"; do
        [ "$login" = "$seen" ] && continue
        seen=$login
        if ! [[ $login =~ $RE_LOGIN ]]; then AUTH_REASON="no usable login"; return 1; fi
        perm=$(gh api --method GET "repos/$REPO/collaborators/$login/permission" --jq .permission 2>/dev/null < /dev/null) || return 2
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
        "$KOTO" context add "$SESSION" "$3" --from-file "$4" >/dev/null 2>&1 || lib_die2 "koto context add $3 failed"
    fi
    local sealed
    sealed=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$1" --token "$2") || lib_die2 "cannot seal the verdict"
    printf '%s\n' "$sealed"
    exit 0
}

# lib_write_guard: every write refuses (exit 10) when the session wasn't
# created from the shipped template for this plugin root, or when the run has
# any directed transition (`koto next --to` skips gates, koto#251).
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
    local out rc
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

# lib_log: set LOG to the session's state log, found the way coord-log.sh
# finds it (koto session dir). record-confirm.sh reads evidence events that
# coord-log.sh has no subcommand for; every seal it relies on is still
# checked through coord-log.sh.
lib_log() {
    local d
    d=$("$KOTO" session dir "$SESSION" 2>/dev/null) || return 1
    LOG="$d/koto-$SESSION.state.jsonl"
    [ -r "$LOG" ]
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
