#!/usr/bin/env bash
# import.sh -- the legacy importer: a coordinator record still on GitHub, read
# once into the run's koto session on a fresh start
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The legacy
# importer"). One way only: it never writes the record's state back.
#
# It lives outside scripts/ so its parser, its comment reader and its one
# permission read stay off the skill's normal path: record-parse.jq here is
# its own copy of the codec's parse half, and gh_marked, gh_entries and
# has_write_access below are copies of record-append.sh's comment reader and
# record-common.sh's lib_has_write_access. Its writes go through the write
# core's core_import and core_import_meta, which only it opens
# (IMPORT_WRITER).
#
# Usage:
#   import.sh --lookup --session S --scope roadmap|discipline --name N --repo O/R
#   import.sh --session S --scope roadmap|discipline --name N --repo O/R --ref N
#
# --lookup prints one line. `resume` when session S holds record/meta, read
# before anything on GitHub, which it then doesn't read. Otherwise `record <n>`
# for the scope's one open record: at roadmap scope an open issue in O/R titled
# `Coordinator record: ROADMAP-<name>` whose body isn't in the moved shape (every
# section empty and a Run section holding only the `store session` row); at
# discipline scope an open same-repository pull request from
# coordinate/discipline-<name> into the default branch. A candidate whose author
# has no write access to O/R isn't a record: anyone can open an issue with the
# record's title on a public repository. Each one skipped is named on stderr,
# since a record opened by a token without that access (an app's or a bot's)
# would otherwise read as no record at all. `none` when there is no record;
# `several <n> <n>...` (exit 65) when there is more than one, which needs a
# person to say which is the scope's.
#
# The import reads record <n>'s body and parses it with its own copy; a body
# that doesn't parse as this scope's record, a parsed state the write core's
# state-schema.jq check refuses, or a rotation title without its dates, prints
# `record-unreadable <n>` (exit 65). Any `store` Run row is
# dropped. It reads the record's marked comments and keeps those whose author
# has write access; an author whose access can't be read is
# `record-unreadable <n>` too. Nothing is written before every read is done.
# Then, in this order:
#   1. the sections and the entries (record/entries/<n>, numbered from 1 in the
#      comments' order, leaving out a `moved` note naming S), and at discipline
#      scope record/rotation from the pull request's title, through
#      core_import;
#   2. one `moved` comment on the record naming S, unless the login gh answers
#      for already posted one;
#   3. record/meta, through core_import_meta.
# Until record/meta lands S holds no record, so a run cut short leaves the
# start fresh and the next one imports again: it rewrites the same keys and
# finds its note posted. It makes no other GitHub write. It prints
# `imported=<n> entries=<count>`.
#
# Exit codes: 0 printed; 2 a read failed; 11 a write failed part way (the next
# start imports again); 64 usage; 65 refused (the reason on stderr).
#
# GitHub calls:
#   reads:  gh api --method GET repos/R/issues?state=open&per_page=100 --paginate
#           gh api --method GET repos/R --jq .default_branch
#           gh pr list --repo R --head B --state open --limit 100 --json ...
#           gh issue view N --repo R --json title,body | gh pr view N --repo R --json title,body
#           gh api --method GET repos/R/issues/N/comments?per_page=100 --paginate
#           gh api --method GET repos/R/collaborators/<login>/permission --jq .permission
#           gh api user --jq .login
#   writes: gh api --method POST repos/R/issues/N/comments --input <json>
# koto calls: context list and context get (record/meta), and the write core's.
#
# Requires: bash 3.2+, jq, gh, koto, and the write core with record-common.sh
# in ../scripts.
set -uo pipefail

PROG=import
OWN=$(cd "$(dirname "$0")" && pwd)
# The write core's contract: HERE is the scripts directory it lives in.
HERE=$(cd "$OWN/../scripts" && pwd)
SESSION= SCOPE= NAME= REPO= REF= LOOKUP=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --lookup) LOOKUP=1; shift ;;
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
case "$SCOPE" in roadmap|discipline) ;; *) usage ;; esac
[[ $SESSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ $NAME =~ $RE_NAME ]] && [[ $REPO =~ $RE_REPO ]] || usage
if [ "$LOOKUP" = 1 ]; then [ -z "$REF" ] || usage; else [[ $REF =~ $RE_NUM ]] || usage; fi
TITLE="Coordinator record: ROADMAP-$NAME"
BRANCH="coordinate/discipline-$NAME"

W=$(mktemp -d "${TMPDIR:-/tmp}/legacy-import.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$W"' EXIT
unreadable() { echo "record-unreadable $REF"; echo "$PROG: refused: #$REF: $1" >&2; exit 65; }

# has_write_access <login>: 0 admin, maintain or write on REPO; 1 less, or not a
# collaborator (GitHub answers 404); 2 the read failed. A copy of
# record-common.sh's lib_has_write_access.
has_write_access() {
    local perm
    [[ $1 =~ $RE_LOGIN ]] || return 1
    if ! perm=$(gh api --method GET "repos/$REPO/collaborators/$1/permission" --jq .permission 2> "$W/perm.err" < /dev/null); then
        grep -q 'HTTP 404' "$W/perm.err" && return 1
        return 2
    fi
    case "$perm" in admin|maintain|write) return 0 ;; *) return 1 ;; esac
}

# parse <body-file> <out>: the body as this scope's record, with this
# directory's copy of the codec's parse half. Returns 1 when it doesn't parse or
# is another scope's, the reason in <out>.err.
parse() {
    local size
    tr -d '\r' < "$1" > "$1.lf" || return 1
    size=$(wc -c < "$1.lf" | tr -d ' ')
    [ "$size" -le 65536 ] || { echo "the body is $size bytes, over GitHub's 65536" > "$2.err"; return 1; }
    jq -R -s -L "$OWN" 'include "record-parse"; parse_record' < "$1.lf" > "$2" 2> "$2.err" || return 1
    jq -e --arg k "$SCOPE" --arg n "$NAME" '.scope == {kind: $k, name: $n}' "$2" > /dev/null \
        || { echo "the record is for another scope" > "$2.err"; return 1; }
}
# moved <parsed>: 0 when the record is in the moved shape.
moved() {
    jq -e '([.holdings, .deferrals, .side_effects, .reversals, .holds, .standing, .work] | all(. == null or . == []))
        and (has("decisions") | not)
        and ([(.run // [])[] | "\(.key)=\(.value)"] == ["store=session"])' "$1" > /dev/null
}

# rotation_dates <title>: a rotation pull request's window from its title,
# `docs(coordinate): <name> rotation <start> to <end>`, into ROT_START and
# ROT_END. A copy of record-common.sh's lib_rotation_dates.
rotation_dates() {
    local want="docs(coordinate): $NAME rotation " rest
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

# gh_marked <out>: the record's comments carrying the entry marker, as JSON
# lines {id, created_at, updated_at, user, body}, every author's, into <out>.all,
# and those by authors with write access into <out>. Returns 3 when an author's
# access can't be read. A copy of record-append.sh's reader.
gh_marked() {
    local login
    gh api --method GET "repos/$REPO/issues/$REF/comments?per_page=100" --paginate \
        --jq '.[] | {id, created_at, updated_at, user: (.user.login // ""), body: (.body // "")}' \
        > "$W/comments.jsonl" 2> "$W/c.err" < /dev/null || lib_die2 "cannot read #$REF's comments: $(lib_scrub < "$W/c.err")"
    jq -c --arg m "$ENTRY_MARKER_PREFIX" 'select(.body | gsub("\r"; "") | startswith($m))' "$W/comments.jsonl" > "$1.all" \
        || lib_die2 "the comments read is not JSON"
    : > "$W/writers"
    for login in $(jq -r '.user' "$1.all" | sort -u); do
        has_write_access "$login"
        case $? in
            0) printf '%s\n' "$login" >> "$W/writers" ;;
            1) ;;
            *) return 3 ;;
        esac
    done
    jq -c --rawfile w "$W/writers" '($w | split("\n") | map(select(. != ""))) as $writers
        | select(.user as $u | $writers | index($u))' "$1.all" > "$1" || lib_die2 "jq failed"
}
# gh_entries <marked-jsonl>: the entries those comments carry, oldest first:
# {stamp, author, kind, text}, the text decoded as record-append.sh wrote it.
gh_entries() {
    jq -s -c --arg m "$ENTRY_MARKER_PREFIX" '
        sort_by(.created_at, .id)
        | map((.body | gsub("\r"; "")) as $b
            | ($b | split("\n")) as $l
            | {stamp: ($l[1] // "" | capture("^\\*\\*(?<s>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\\*\\*").s // .created_at),
               author: .user,
               kind: ($l[0] | ltrimstr($m) | sub(" -->$"; "")),
               text: ($l[3:] | join("\n") | rtrimstr("\n") | gsub("&#64;"; "@") | gsub("&amp;"; "&"))})' "$1" || lib_die2 "jq failed"
}

# The lookup. A session holding record/meta is a resume, whatever GitHub holds.
rs_key "$SESSION" record/meta "$W/meta"
case $? in
    0) if [ "$LOOKUP" = 1 ]; then echo resume; exit 0; fi
       echo "$PROG: refused: session $SESSION already holds a record" >&2; exit 65 ;;
    1) ;;
    *) lib_die2 "cannot read session $SESSION's record/meta: $(lib_scrub < "$W/meta.err")" ;;
esac
if [ "$LOOKUP" = 1 ]; then
    if [ "$SCOPE" = roadmap ]; then
        gh api --method GET "repos/$REPO/issues?state=open&per_page=100" --paginate > "$W/raw" 2> "$W/r.err" < /dev/null \
            || lib_die2 "cannot list $REPO's open issues: $(lib_scrub < "$W/r.err")"
        jq -s -c --arg t "$TITLE" 'add // [] | map(select((has("pull_request") | not) and .title == $t))
            | map({number, author: (.user.login // ""), body: (.body // "")}) | sort_by(.number) | .[]' "$W/raw" > "$W/cands" \
            || lib_die2 "the issue listing is not JSON"
    else
        DEFAULT=$(gh api --method GET "repos/$REPO" --jq .default_branch 2> "$W/r.err" < /dev/null) \
            || lib_die2 "cannot read $REPO's default branch: $(lib_scrub < "$W/r.err")"
        gh pr list --repo "$REPO" --head "$BRANCH" --state open --limit 100 \
            --json number,body,isCrossRepository,baseRefName,headRefName,author > "$W/raw" 2> "$W/r.err" < /dev/null \
            || lib_die2 "cannot list $REPO's pull requests: $(lib_scrub < "$W/r.err")"
        jq -c --arg b "$DEFAULT" --arg h "$BRANCH" 'map(select(.isCrossRepository == false and .baseRefName == $b and .headRefName == $h))
            | sort_by(.number) | .[] | {number, author: (.author.login // ""), body: (.body // "")}' "$W/raw" > "$W/cands" \
            || lib_die2 "the pull request listing is not JSON"
    fi
    FOUND=
    while IFS= read -r c; do
        n=$(printf '%s' "$c" | jq -r .number)
        has_write_access "$(printf '%s' "$c" | jq -r .author)"
        case $? in
            0) ;;
            1) echo "$PROG: #$n skipped: its author has no write access to $REPO, so it isn't taken as this scope's record" >&2
               continue ;;
            *) lib_die2 "cannot read the access of #$n's author to $REPO" ;;
        esac
        if [ "$SCOPE" = roadmap ]; then
            printf '%s' "$c" | jq -r .body > "$W/cand.md"
            parse "$W/cand.md" "$W/cand.json" && moved "$W/cand.json" && continue
        fi
        FOUND="$FOUND $n"
    done < "$W/cands"
    case "$FOUND" in
        "") echo none ;;
        " "*" "*) echo "several$FOUND"; echo "$PROG: refused: several open records for this scope:$FOUND" >&2; exit 65 ;;
        *) echo "record${FOUND}" ;;
    esac
    exit 0
fi

# The import: every read first.
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json title,body > "$W/target.json" 2> "$W/r.err" < /dev/null \
        || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$W/r.err")"
else
    gh pr view "$REF" --repo "$REPO" --json title,body > "$W/target.json" 2> "$W/r.err" < /dev/null \
        || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$W/r.err")"
fi
jq -r '.body // ""' "$W/target.json" > "$W/body.md" || lib_die2 "the record read is not JSON"
parse "$W/body.md" "$W/parsed.json" || unreadable "$(sed 's/.*refused: //' "$W/parsed.json.err" | head -1 | lib_scrub)"
if [ "$SCOPE" = roadmap ] && moved "$W/parsed.json"; then
    echo "$PROG: refused: #$REF is in the moved shape: its state was moved before" >&2; exit 65
fi
jq -c 'if has("run") then .run |= map(select(.key != "store")) else . end' "$W/parsed.json" > "$W/state.json" || lib_die2 "jq failed"
if [ "$SCOPE" = discipline ]; then
    rotation_dates "$(jq -r '.title // ""' "$W/target.json")" || unreadable "its title isn't this discipline's rotation title"
    jq -nc --arg s "$ROT_START" --arg e "$ROT_END" --arg r "$REPO" '{start: $s, end: $e, host_repo: $r, predecessor: null}' > "$W/rotation.json"
fi
gh_marked "$W/marked.jsonl" || unreadable "an entry author's access to $REPO can't be read"
LOGIN=$(gh api user --jq .login 2> "$W/u.err" < /dev/null) || lib_die2 "cannot read the gh login: $(lib_scrub < "$W/u.err")"
[[ $LOGIN =~ $RE_LOGIN ]] || lib_die2 "the gh login isn't a login"
NOTE="Imported into koto session $SESSION on a coordinator start: the record's state now lives in that session, and this record is no longer written."
# The entries, without this import's own note, numbered from 1.
gh_entries "$W/marked.jsonl" > "$W/kept.json" || exit 2
jq -c --arg note "$NOTE" 'map(select((.kind == "moved" and .text == $note) | not))
    | to_entries | map({n: (.key + 1), stamp: .value.stamp, kind: .value.kind, text: .value.text})' "$W/kept.json" > "$W/entries.json" \
    || lib_die2 "jq failed"
# The note is posted already when a marked comment by this login carries it.
gh_entries "$W/marked.jsonl.all" > "$W/all.json" || exit 2
POSTED=0
jq -e --arg l "$(printf '%s' "$LOGIN" | tr 'A-Z' 'a-z')" --arg note "$NOTE" \
    'any(.[]; (.author | ascii_downcase) == $l and .kind == "moved" and .text == $note)' "$W/all.json" > /dev/null && POSTED=1

# 1. The sections and the entries, through the core (in a subshell: it takes
# over the EXIT trap and exits on a refusal).
( . "$HERE/record-write-core.sh"
  IMPORT_WRITER=1
  core_import "$W/state.json" "$W/entries.json" ${ROT_START:+"$W/rotation.json"} )
rc=$?
# The core refuses (65) a parsed state that fails state-schema.jq, or an entry
# it won't take: the record can't be read as a state, as a body that doesn't
# parse can't, and nothing was written.
case $rc in 0) ;; 65) echo "record-unreadable $REF"; exit 65 ;; *) exit $rc ;; esac
# 2. The note.
if [ "$POSTED" = 0 ]; then
    { printf '%s%s -->\n' "$ENTRY_MARKER_PREFIX" moved
      printf '**%s** (host clock) %s\n\n' "$(lib_now)" moved
      printf '%s\n' "$NOTE" | sed -e 's/&/\&amp;/g' -e 's/@/\&#64;/g'; } > "$W/note.md"
    jq -n --rawfile b "$W/note.md" '{body: $b}' > "$W/post.json" || lib_die2 "jq failed"
    gh api --method POST "repos/$REPO/issues/$REF/comments" --input "$W/post.json" > /dev/null 2> "$W/w.err" < /dev/null \
        || { echo "$PROG: the moved note wasn't posted: $(lib_scrub < "$W/w.err"); the next start imports again" >&2; exit 11; }
fi
# 3. record/meta, last.
( . "$HERE/record-write-core.sh"
  IMPORT_WRITER=1
  core_import_meta "$W/state.json" ) || exit $?
echo "imported=$REF entries=$(jq length "$W/entries.json")"
