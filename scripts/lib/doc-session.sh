# doc-session.sh -- what scripts/doc-check.sh and scripts/doc-events.sh share:
# the phase map, the document's canonical path, the check state kept in the
# skill's own session, and best-effort telemetry through `koto review record`.
#
# Sourced, never run. The caller sets, before calling anything here:
#
#   PROG          its name, for the lines it prints (doc-check, doc-events)
#   PLUGIN_ROOT   the plugin root
#   KOTO          the koto binary (from KOTO_BIN, default `koto`)
#   ROOT_REAL     the physical path of the repository root, the directory the
#                 caller has already changed to
#   WORK          a private (0700) scratch directory it removes on exit
#
# Functions:
#
#   ds_notice <text>      one `<prog>: notice: <text>` line on stderr
#   ds_sanitize           stdin to stdout: control characters (C0, DEL, C1),
#                         the Unicode line and paragraph separators and the
#                         bidirectional controls replaced by a space, so a
#                         line carrying validator or document text can't start
#                         a new line or reorder what a reader sees
#   ds_formats            the seven formats, space-separated
#   ds_phase_map <jq-path...>
#                         jq over references/doc-check-phases.json
#   ds_canonical_paths <format> <topic>
#                         the canonical paths, one per line
#   ds_resolve_doc <start_dir> <arg>
#                         follows <arg> (relative to <start_dir>) through
#                         symlinks to a physical path and sets DS_DOC to that
#                         path relative to the repository root. Refuses (1, with
#                         DS_REASON) a path outside the repository, one with a
#                         `.` or `..` component past the existing directories,
#                         and a link chain longer than 40.
#   ds_topic_of <format> <rel>
#                         the topic a canonical path names, or nothing
#   ds_slug <section>     a required section's slug ("User Journeys" ->
#                         user-journeys)
#   ds_doc_commit <rel>   the commit that last changed <rel>, when it is
#                         tracked and has no uncommitted change; else nothing
#   ds_record_session <skill> <topic>
#                         the session telemetry is recorded on: the parent's
#                         when `skill-session.sh dispatch read` names one, else
#                         <skill>-<topic>. Sets DS_RECORD_SESSION.
#   ds_state_read <session> <out>
#                         writes the session's work/doc-check.json to <out>, or
#                         `{}` when it is absent or unreadable
#   ds_state_write <session> <file>
#                         stores <file> as work/doc-check.json; a notice on
#                         failure
#   ds_record <what> <verb> <arg...>
#                         `koto review record <verb> <arg...>`; a notice naming
#                         <what> on failure. Never changes the caller's exit.
#
# Recording is best effort: koto absent, a koto without the verb, no session,
# a refused call -- each prints one notice and the caller goes on as if it had
# recorded. The records are telemetry and never change an outcome.
#
# Written for the bash 3.2 floor.

DS_REASON=""
DS_DOC=""
DS_RECORD_SESSION=""
DS_PHASES="$PLUGIN_ROOT/references/doc-check-phases.json"
DS_FORMATS="brief prd design plan vision strategy roadmap"
DS_RE_SKILL='^[a-z][a-z-]*$'
DS_RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
DS_RE_SESSION='^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$'

# The replacement set, as a jq regex: C0, DEL, C1, ALM (U+061C), LRM and RLM,
# the line and paragraph separators, the embeddings and overrides, the isolates.
DS_SANITIZE_JQ='gsub("[\u0000-\u001f\u007f-\u009f؜‎‏  ‪-‮⁦-⁩]"; " ")'

ds_notice() {
    printf '%s: notice: %s\n' "$PROG" "$*" >&2
}

ds_sanitize() {
    jq -Rrs "$DS_SANITIZE_JQ"
}

ds_formats() {
    printf '%s' "$DS_FORMATS"
}

ds_phase_map() {
    jq -r "$@" "$DS_PHASES"
}

ds_canonical_paths() {
    jq -r --arg f "$1" --arg t "$2" '.formats[$f].paths[] | sub("\\{topic\\}"; $t)' "$DS_PHASES"
}

ds_resolve_doc() {
    local start=$1 arg=$2 abs target hops=0 dir rest="" base phys
    DS_DOC=""
    case "$arg" in
        "") DS_REASON="--doc is empty"; return 1 ;;
        /*) abs=$arg ;;
        *) abs="$start/$arg" ;;
    esac
    while [ -L "$abs" ] && [ "$hops" -lt 40 ]; do
        target=$(readlink "$abs") || { DS_REASON="cannot read the link --doc names"; return 1; }
        case "$target" in
            /*) abs=$target ;;
            *) abs="$(dirname "$abs")/$target" ;;
        esac
        hops=$((hops + 1))
    done
    [ -L "$abs" ] && { DS_REASON="--doc resolves through more than 40 links"; return 1; }
    base=$(basename "$abs")
    dir=$(dirname "$abs")
    # The part of the path that doesn't exist yet can't be resolved; it may
    # hold no `.` or `..` component, so its spelling is its meaning.
    while [ ! -d "$dir" ]; do
        rest="/$(basename "$dir")$rest"
        dir=$(dirname "$dir")
    done
    case "/$base$rest/" in
        */./*|*/../*) DS_REASON="--doc has a . or .. component that doesn't exist"; return 1 ;;
    esac
    case "$base" in .|..) DS_REASON="--doc names a directory"; return 1 ;; esac
    phys=$(cd "$dir" 2>/dev/null && pwd -P) || { DS_REASON="cannot resolve the directory of --doc"; return 1; }
    phys="$phys$rest/$base"
    case "$phys" in
        "$ROOT_REAL"/*) DS_DOC=${phys#"$ROOT_REAL"/} ;;
        *) DS_REASON="--doc resolves outside the repository"; return 1 ;;
    esac
    case "$DS_DOC" in
        docs/*) ;;
        *) DS_REASON="--doc resolves outside the repository's docs/"; DS_DOC=""; return 1 ;;
    esac
    return 0
}

ds_topic_of() {
    jq -r --arg f "$1" --arg rel "$2" '
        [.formats[$f].paths[] | split("{topic}") as [$pre, $post]
         | select(($rel | startswith($pre)) and ($rel | endswith($post))
                  and ($rel | length) > ($pre | length) + ($post | length))
         | $rel[($pre | length):(($rel | length) - ($post | length))]] | first // ""' "$DS_PHASES"
}

ds_slug() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//'
}

ds_doc_commit() {
    local rel=$1 dirty
    [ -f "$rel" ] || return 0
    dirty=$(git status --porcelain --untracked-files=all -- "$rel" 2>/dev/null) || return 0
    [ -z "$dirty" ] || return 0
    git log -1 --format=%H --end-of-options HEAD -- "$rel" 2>/dev/null
}

ds_record_session() {
    local skill=$1 topic=$2 out rc parent
    DS_RECORD_SESSION="$skill-$topic"
    out=$(KOTO_BIN="$KOTO" "$PLUGIN_ROOT/scripts/skill-session.sh" dispatch read "$skill" "$topic" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        ds_notice "could not read the chain's dispatch (skill-session exit $rc); telemetry goes to $DS_RECORD_SESSION"
        return 0
    fi
    parent=$(printf '%s\n' "$out" | sed -n 's/^parent=//p' | head -n 1)
    if [ -n "$parent" ] && [[ "$parent" =~ $DS_RE_SESSION ]]; then
        DS_RECORD_SESSION=$parent
    fi
    return 0
}

ds_state_read() {
    local s=$1 out=$2
    printf '{}\n' > "$out"
    command -v "$KOTO" >/dev/null 2>&1 || return 0
    "$KOTO" context exists "$s" work/doc-check.json >/dev/null 2>&1 || return 0
    if ! "$KOTO" context get "$s" work/doc-check.json > "$out.raw" 2>/dev/null; then
        ds_notice "could not read work/doc-check.json from $s; starting from no recorded check"
        return 0
    fi
    if jq -e 'type == "object" and .schema == "doc-check-state/v1"' "$out.raw" >/dev/null 2>&1; then
        mv "$out.raw" "$out"
    else
        ds_notice "work/doc-check.json in $s is not a doc-check state; starting from no recorded check"
    fi
    rm -f "$out.raw"
    return 0
}

ds_state_write() {
    local s=$1 file=$2
    if ! command -v "$KOTO" >/dev/null 2>&1; then
        ds_notice "koto is not on PATH; work/doc-check.json was not written"
        return 0
    fi
    "$KOTO" context add "$s" work/doc-check.json --from-file "$file" >/dev/null 2>&1 \
        || ds_notice "could not write work/doc-check.json into $s"
    return 0
}

ds_record() {
    local what=$1 rc
    shift
    if ! command -v "$KOTO" >/dev/null 2>&1; then
        ds_notice "koto is not on PATH; telemetry for $what was not recorded"
        return 0
    fi
    "$KOTO" review record "$@" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || ds_notice "telemetry for $what was not recorded (koto exit $rc)"
    return 0
}
