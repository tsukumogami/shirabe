#!/usr/bin/env bash
# offload-canary.sh -- the live offload canary's draw for /work-on.
#
# The canary leaves one registry rule, pr-body/no-heading-in-part1 (PB4), out
# of the PR-body conformance text a random half of /work-on runs read, keeps it
# in the other half, and shows each run's group in koto's exported events as the
# marker state it passes through. docs/designs/current/DESIGN-offload-live-canary.md is
# the design; docs/guides/offload-live-canary.md says how to read the result.
#
# work-on.md's offload_canary state, which analysis's plan_ready edge enters,
# runs `draw` as its default action and captures what it prints as
# PR_BODY_RULES, the conformance text the pr_creation directive names. Its
# offload_arm gate runs `arm` and routes on the exit code to
# offload_arm_withheld, offload_arm_preloaded, or straight to
# review_level_choice.
#
# Usage:
#   offload-canary.sh draw <switch> <shared-branch> <session-dir> <plugin-root>
#   offload-canary.sh arm <session-dir>
#
# draw prints exactly one line, the absolute path of the conformance text this
# run reads, and always exits 0: a failing default action would hold the run's
# first state. The path is <plugin-root>/references/pr-body-conformance.md for
# every run in neither group or the preloaded one, so their pr_creation
# directive is byte-for-byte a canary-off run's. A withheld run gets
# <session-dir>/pr-rules/pr-body-conformance.md, the same file with PB4's lines
# removed.
#
# A run takes part only when every one of these holds; otherwise it is in
# neither group and nothing is written:
#   - <switch> is `on` (OFFLOAD_CANARY, the template's off switch);
#   - <shared-branch> is empty (an /execute child on its shared branch opens no
#     pull request);
#   - the host has opted in: ${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/offload-canary
#     is a regular file whose first line is `on`;
#   - the registry marks the rule withhold: eligible;
#   - the session directory exists and is not a symlink.
# The group is drawn from one byte of /dev/urandom (even: withheld, odd:
# preloaded) and recorded in <session-dir>/pr-rules/sample, written last, after
# the withheld rendering succeeded. A second draw in the same session reads the
# recorded group back, so a rewind into the state never changes it.
#
# arm exits 0 for a withheld run whose rendering exists, 1 for a preloaded run,
# and 3 for a run in neither group, so every outcome has an edge.

set -u

RULE=pr-body/no-heading-in-part1
CONF_REL=references/pr-body-conformance.md
RULES_DIR=pr-rules

# safe_dir <dir>: an existing directory that is not a symlink.
safe_dir() { [ -n "$1" ] && [ -d "$1" ] && [ ! -L "$1" ]; }

# opted_in: the host's opt-in file is a regular file reading `on` first.
opted_in() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/offload-canary" line
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    IFS= read -r line < "$f" || [ -n "$line" ] || return 1
    [ "$line" = on ]
}

# recorded <rules-dir>: the group a previous draw recorded, or nothing.
recorded() {
    local f="$1/sample" g
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    IFS= read -r g < "$f" || [ -n "$g" ] || return 1
    case "$g" in withheld|preloaded) printf '%s' "$g" ;; *) return 1 ;; esac
}

# write_file <dir> <name>: stdin to <dir>/<name> through a temporary file in the
# same directory, refusing a symlink at the target.
write_file() {
    local tmp
    [ ! -L "$1/$2" ] || return 1
    tmp=$(mktemp "$1/.$2.XXXXXX") || return 1
    if cat > "$tmp" && mv -f "$tmp" "$1/$2"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# render <plugin-root> <conformance file> <rules-dir>: the conformance text
# without PB4's lines, checked to carry no trace of PB4.
render() {
    local root=$1 conf=$2 dir=$3 range a b out
    range=$("$root/scripts/rule-registry.sh" range "$RULE" 2>/dev/null) || return 1
    a=${range% *}
    b=${range#* }
    case "$a$b" in *[!0-9]*|'') return 1 ;; esac
    out=$(LC_ALL=C awk -v a="$a" -v b="$b" 'NR < a || NR > b' "$conf") || return 1
    # The rendering must not name the rule it leaves out, or it would hand the
    # withheld run what the canary is withholding.
    if printf '%s\n' "$out" | grep -qiE 'PB4|heading|no-heading-in-part1'; then
        return 1
    fi
    printf '%s\n' "$out" | write_file "$dir" pr-body-conformance.md
}

cmd_draw() {
    local switch=$1 shared=$2 sdir=$3 root=$4 conf dir group byte
    conf="$root/$CONF_REL"
    dir="$sdir/$RULES_DIR"
    group=""
    if safe_dir "$sdir" && [ ! -L "$dir" ]; then
        group=$(recorded "$dir") || group=""
        if [ -z "$group" ] && [ "$switch" = on ] && [ -z "$shared" ] && opted_in \
            && [ "$("$root/scripts/rule-registry.sh" withhold "$RULE" 2>/dev/null)" = eligible ]; then
            byte=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' ')
            case "$byte" in
                ''|*[!0-9]*) group="" ;;
                *) if [ $((byte % 2)) -eq 0 ]; then group=withheld; else group=preloaded; fi ;;
            esac
            if [ -n "$group" ]; then
                mkdir -p "$dir" 2>/dev/null && safe_dir "$dir" || group=""
            fi
            if [ "$group" = withheld ] && ! render "$root" "$conf" "$dir"; then
                group=""
            fi
            if [ -n "$group" ] && ! printf '%s\n' "$group" | write_file "$dir" sample; then
                group=""
            fi
        fi
    fi
    if [ "$group" = withheld ] && [ -f "$dir/pr-body-conformance.md" ] && [ ! -L "$dir/pr-body-conformance.md" ]; then
        printf '%s\n' "$dir/pr-body-conformance.md"
    else
        printf '%s\n' "$conf"
    fi
    exit 0
}

cmd_arm() {
    local dir="$1/$RULES_DIR" group
    safe_dir "$1" && [ ! -L "$dir" ] || exit 3
    group=$(recorded "$dir") || exit 3
    case "$group" in
        withheld)
            [ -f "$dir/pr-body-conformance.md" ] && [ ! -L "$dir/pr-body-conformance.md" ] || exit 3
            exit 0 ;;
        preloaded) exit 1 ;;
    esac
    exit 3
}

case "${1-}" in
    draw)
        [ $# -eq 5 ] || { printf '%s\n' "${5-}/$CONF_REL"; exit 0; }
        cmd_draw "$2" "$3" "$4" "$5" ;;
    arm)
        [ $# -eq 2 ] || exit 3
        cmd_arm "$2" ;;
    *)
        echo "usage: offload-canary.sh draw <switch> <shared-branch> <session-dir> <plugin-root> | arm <session-dir>" >&2
        exit 64 ;;
esac
