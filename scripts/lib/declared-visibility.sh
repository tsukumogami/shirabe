# declared-visibility.sh -- the visibility a repository declares for itself.
#
# Sourced, never run. Defines one function:
#
#   declared_visibility        prints `public` or `private`, from the first
#                              well-formed `## Repo Visibility:` header in the
#                              repository root's CLAUDE.local.md, else its
#                              CLAUDE.md, lowercased; prints nothing when
#                              neither file declares one. Always returns 0.
#
# The header is parsed as the validator parses it: the first well-formed header
# in a file wins, and CLAUDE.local.md is read before CLAUDE.md. A caller passes
# the result to `shirabe validate --visibility=<v>`, and omits the flag when
# nothing printed, so the validator detects visibility as it does in CI.
#
# Precondition: the caller has already changed to the repository root. Both
# files are read by relative path, so from a subdirectory the function finds
# neither and prints nothing.
#
# Two gate scripts source this file: skills/work-on/scripts/check-branch-output.sh
# (--docs-visibility) and skills/scope/scripts/check-hop-document.sh. One
# parser for one header, so the two gates can't disagree about a repository.
#
# Written for the bash 3.2 floor.

declared_visibility() {
    # Local, so a sourcing script's own f or v is left alone.
    local f v
    for f in CLAUDE.local.md CLAUDE.md; do
        [ -f "$f" ] || continue
        v=$(LC_ALL=C tr '[:upper:]' '[:lower:]' < "$f" | awk '
            {
                line = $0
                sub(/^[ \t]+/, "", line)
                if (index(line, "## repo visibility:") != 1) next
                value = substr(line, length("## repo visibility:") + 1)
                sub(/^[ \t]+/, "", value)
                if (index(value, "private") == 1) { print "private"; exit }
                if (index(value, "public") == 1) { print "public"; exit }
            }')
        if [ -n "$v" ]; then
            printf '%s\n' "$v"
            return 0
        fi
    done
    return 0
}
