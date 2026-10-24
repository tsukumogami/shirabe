# gh-issue-testlib.sh -- for the work-on suites that walk a real koto session of
# work-on.md past fix_determination. Sourced, never run.
#
#   gh_issue_stand_in <dir>
#       writes <dir>/gh and puts <dir> first on PATH. fix_determination's
#       action, fix-kind.sh resolve, reads an issue-backed run's labels with
#       `gh issue view <n> [--repo <r>] --json labels,body`, and fails the run
#       there when gh can't answer. The stand-in answers exactly that call
#       with an unlabelled issue, so every issue-backed walk is a change and
#       goes on to implementation, as before fix_determination existed. Every
#       other gh call fails the way gh does in a repository with no GitHub
#       remote, which is what the suites' fixtures already get from a real gh,
#       so check-staleness.sh still finds itself unavailable.
#
# Call it before `koto init`: koto keeps the PATH a session was created with
# for the commands it runs. Written for the bash 3.2 floor.

gh_issue_stand_in() {
    mkdir -p "$1" || return 1
    cat > "$1/gh" <<'EOF'
#!/bin/sh
# gh stand-in from scripts/lib/gh-issue-testlib.sh.
if [ "$1" = issue ] && [ "$2" = view ]; then
    for a in "$@"; do
        if [ "$a" = labels,body ]; then
            echo '{"labels":[],"body":""}'
            exit 0
        fi
    done
fi
echo "no git remotes found" >&2
exit 1
EOF
    chmod +x "$1/gh" || return 1
    PATH="$1:$PATH"
    export PATH
}
