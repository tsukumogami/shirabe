#!/usr/bin/env bash
set -euo pipefail

# Fails the build when a skill directive runs a script in a form a
# worktree-isolated session refuses, or names a script that cannot run by path.
#
# A directive is text the agent reads and acts on: a SKILL.md, a koto template,
# a reference or phase file under skills/ or references/. When one says to run
# `bash {{PLUGIN_ROOT}}/skills/x/scripts/y.sh args`, a Claude Code session
# isolated in a worktree refuses the command line: it cannot show what a script
# handed to `bash` does with git, so it will not let the call through. The same
# script run by path, `{{PLUGIN_ROOT}}/skills/x/scripts/y.sh args`, passes. An
# agent that meets the refusal rewrites the directive by hand, and a directive
# that has to be rewritten to run invites other departures from it.
#
# Running by path moves the requirement onto the script: it has to be committed
# executable, and it has to name its interpreter. Neither shows up until the
# call fails on someone's machine, so both are checked here.
#
# ---------------------------------------------------------------------------
# The rules
# ---------------------------------------------------------------------------
#
#   bash-invocation   A directive line runs a `.sh` through `bash` or `sh`
#                     (`bash x.sh`, `sh -e x.sh`, `Bash(bash x.sh *)` in an
#                     allowed-tools entry). Fix: drop the interpreter and call
#                     the script by path, in the permission pattern too.
#   exec-bit          A script a directive names by a root-anchored path is not
#                     committed with mode 100755 (`git ls-files -s`). Fix:
#                     `git update-index --chmod=+x <path>`.
#   shebang           The same script's first line is not a `#!` line. Fix:
#                     start it with `#!/usr/bin/env bash`.
#   unresolved        A root-anchored path names no file in the tree. The other
#                     two rules cannot be enforced on a file the check cannot
#                     find, and passing it would overstate what was checked.
#
# A root-anchored path is one written from a root the harness or koto supplies:
# `{{PLUGIN_ROOT}}/`, `${CLAUDE_PLUGIN_ROOT}/` or `$CLAUDE_PLUGIN_ROOT/` (the
# repository root), and `${CLAUDE_SKILL_DIR}/` or `$CLAUDE_SKILL_DIR/` (the
# skill directory holding the file). Those are the paths a directive writes to
# be run; a bare `plan-to-tasks.sh` in prose names a script without telling the
# agent where to run it from, so it is not followed.
#
# Out of the scan, deliberately:
#
#   skills/*/evals/**   test data. A fixture holding the old form is evidence
#                       about the old form, not a directive.
#   *.sh                a script calling another script as `bash "$HERE/x.sh"`
#                       runs inside that script; the isolation check only sees
#                       the command line the agent submits.
#   .github/**          CI steps run on a runner that is not worktree-isolated.
#   docs/**             design and requirements history, which records the form
#                       each decision was made against.
#
# Findings are reported once per rule, file and subject, so a script named
# forty times from one file is one finding, not forty.
#
# ---------------------------------------------------------------------------
# The allowlist
# ---------------------------------------------------------------------------
#
# scripts/check-directive-invocations.allow carries known findings, one
# tab-separated record each, with an issue reference beside every one. A record
# without an `owner/repo#N` reference is itself an error, so the allowlist
# cannot silence a finding that has no ticket behind it.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#
#   scripts/check-directive-invocations.sh
#
# Scans every tracked `.md` under skills/ and references/ in the repository,
# outside skills/*/evals/.
#
# Environment:
#   DIRECTIVE_INVOCATIONS_ROOT        the git work tree to scan (tests use it)
#   DIRECTIVE_INVOCATIONS_ALLOWLIST   override the allowlist path (tests use it)
#
# Exit codes:
#   0  clean
#   1  one or more findings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${DIRECTIVE_INVOCATIONS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ALLOWLIST="${DIRECTIVE_INVOCATIONS_ALLOWLIST:-$SCRIPT_DIR/check-directive-invocations.allow}"

TAB=$(printf '\t')

errors=0
allow_records=""
reported=""

RULE_BASH="bash-invocation"
RULE_EXEC="exec-bit"
RULE_SHEBANG="shebang"
RULE_UNRESOLVED="unresolved"

# -- allowlist ---------------------------------------------------------------

# Records are "<rule>\t<file>\t<subject>\t<issue>\t<reason>". The file path is
# repository-relative; the subject is the script path exactly as the directive
# writes it.
load_allowlist() {
    [ -f "$ALLOWLIST" ] || return 0

    local line rule file subject issue rest lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in
            ''|'#'*) continue ;;
        esac

        rule="${line%%"$TAB"*}"; rest="${line#*"$TAB"}"
        file="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        subject="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        issue="${rest%%"$TAB"*}"

        if [ "$rule" = "$line" ] || [ -z "$file" ] || [ -z "$subject" ]; then
            echo "FAIL: $ALLOWLIST:$lineno is not a tab-separated record"
            echo "  expected: <rule><TAB><file><TAB><subject><TAB><issue><TAB><reason>"
            errors=$((errors + 1))
            continue
        fi

        case "$rule" in
            "$RULE_BASH"|"$RULE_EXEC"|"$RULE_SHEBANG"|"$RULE_UNRESOLVED") ;;
            *)
                echo "FAIL: $ALLOWLIST:$lineno names an unknown rule '$rule'"
                echo "  known rules: $RULE_BASH, $RULE_EXEC, $RULE_SHEBANG, $RULE_UNRESOLVED"
                errors=$((errors + 1))
                continue
                ;;
        esac

        # An allowlist entry is a deferral, and a deferral needs somewhere to be
        # chased. Without a ticket it is just a suppression nobody revisits.
        case "$issue" in
            *[A-Za-z0-9]'#'[0-9]*) ;;
            *)
                echo "FAIL: $ALLOWLIST:$lineno has no issue reference"
                echo "  field 4 must carry one, in the form owner/repo#N"
                echo "  record: $line"
                errors=$((errors + 1))
                continue
                ;;
        esac

        allow_records="${allow_records}${rule}|${file}|${subject}
"
    done < "$ALLOWLIST"
}

# is_allowed <rule> <file> <subject>
is_allowed() {
    case "
$allow_records" in
        *"
$1|$2|$3
"*) return 0 ;;
    esac
    return 1
}

# first_report <rule> <file> <subject> -- true the first time a key is seen.
first_report() {
    case "
$reported" in
        *"
$1|$2|$3
"*) return 1 ;;
    esac
    reported="${reported}$1|$2|$3
"
    return 0
}

# -- scanning ----------------------------------------------------------------

# scan_file <file>
#
# One record per finding candidate: "<line>\t<kind>\t<token>", where kind is
# BASH for a script handed to bash or sh, and REF for a root-anchored script
# path. A line can yield both: `bash {{PLUGIN_ROOT}}/x.sh` is a bash invocation
# of a script whose exec bit also matters once the interpreter is dropped.
#
# The regular expressions are built as strings around a quote variable rather
# than written with `\047` escapes: busybox awk, which the bash 3.2 floor image
# carries, does not honour an octal escape inside a bracket expression.
scan_file() {
    awk -v Q="'" '
        BEGIN {
            # The interpreter must stand alone, not be the tail of a longer
            # word (`mybash`, `x.sh`, `foo-sh`). A leading slash is allowed,
            # so `/bin/bash x.sh` is caught like `bash x.sh`. Short and long
            # flags (`-e`, `--`, `--norc`) may sit between it and the script,
            # and quotes may sit anywhere in the operand, as in
            # `bash "$CLAUDE_PLUGIN_ROOT"/x.sh`.
            BASH_RE = "(^|[^A-Za-z0-9_.-])(bash|sh)[ \t]+(--?[A-Za-z-]*[ \t]+)*[^ \t`()|;&]*[.]sh([^A-Za-z0-9_]|$)"
        }
        # unquote <s> -- the token with every quote character removed, so a
        # quoted root reads the same as a bare one.
        function unquote(s) {
            gsub(/"/, "", s)
            gsub(Q, "", s)
            return s
        }
        {
            s = $0
            while (match(s, BASH_RE)) {
                tok = substr(s, RSTART, RLENGTH)
                s = substr(s, RSTART + RLENGTH)
                # Peel the match down to the script operand one piece at a
                # time: the leading boundary, the interpreter, its flags, the
                # quotes, and whatever follows `.sh`.
                sub(/^[^a-z]*/, "", tok)
                sub(/^(bash|sh)/, "", tok)
                sub(/^[ \t]+/, "", tok)
                while (tok ~ /^--?[A-Za-z-]*[ \t]/) {
                    sub(/^--?[A-Za-z-]*[ \t]+/, "", tok)
                }
                tok = unquote(tok)
                tok = substr(tok, 1, index(tok, ".sh") + 2)
                printf "%d\tBASH\t%s\n", NR, tok
            }
            s = $0
            while (match(s, /(\{\{PLUGIN_ROOT\}\}|\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT|\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_SKILL_DIR)"?\/[A-Za-z0-9_.\/-]*\.sh/)) {
                printf "%d\tREF\t%s\n", NR, unquote(substr(s, RSTART, RLENGTH))
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

# resolve_ref <file> <token> -- the repository-relative script path, or empty.
resolve_ref() {
    local file="$1" token="$2" rest skill_dir
    case "$token" in
        '{{PLUGIN_ROOT}}/'*|'${CLAUDE_PLUGIN_ROOT}/'*|'$CLAUDE_PLUGIN_ROOT/'*)
            rest="${token#*/}"
            ;;
        '${CLAUDE_SKILL_DIR}/'*|'$CLAUDE_SKILL_DIR/'*)
            # The skill directory is skills/<name>; a file outside skills/ has
            # none, and its reference cannot resolve.
            case "$file" in
                skills/*/*) ;;
                *) return 0 ;;
            esac
            skill_dir="${file#skills/}"
            skill_dir="skills/${skill_dir%%/*}"
            rest="$skill_dir/${token#*/}"
            ;;
        *) return 0 ;;
    esac
    [ -f "$ROOT/$rest" ] && printf '%s' "$rest"
    return 0
}

# report <rule> <file> <line> <subject> <message...>
report() {
    local rule="$1" file="$2" lineno="$3" subject="$4"
    shift 4
    is_allowed "$rule" "$file" "$subject" && return 0
    first_report "$rule" "$file" "$subject" || return 0
    echo "FAIL: $file:$lineno [$rule] $subject"
    local m
    for m in "$@"; do
        echo "  $m"
    done
    errors=$((errors + 1))
}

check_file() {
    local file="$1"
    local lineno kind token rel mode

    while IFS="$TAB" read -r lineno kind token; do
        [ -n "$kind" ] || continue
        case "$kind" in
            BASH)
                report "$RULE_BASH" "$file" "$lineno" "$token" \
                    "The directive runs the script through an interpreter. A worktree-isolated" \
                    "session refuses that command line; the same call by path passes." \
                    "Fix: drop the interpreter and run the script by path, including in any" \
                    "allowed-tools pattern that matches the call."
                ;;
            REF)
                rel=$(resolve_ref "$file" "$token")
                if [ -z "$rel" ]; then
                    report "$RULE_UNRESOLVED" "$file" "$lineno" "$token" \
                        "No file at this path in the tree, so its exec bit and interpreter" \
                        "cannot be checked. Fix the path, or defer it with an issue."
                    continue
                fi
                mode=$(git -C "$ROOT" ls-files -s -- "$rel" | awk 'NR == 1 { print $1 }')
                if [ -z "$mode" ]; then
                    report "$RULE_EXEC" "$file" "$lineno" "$token" \
                        "$rel is not committed, so the mode it ships with is unknown." \
                        "Fix: commit it with the executable bit (mode 100755)."
                elif [ "$mode" != "100755" ]; then
                    report "$RULE_EXEC" "$file" "$lineno" "$token" \
                        "$rel is committed as $mode, not 100755. A directive runs it by" \
                        "path, which needs the executable bit." \
                        "Fix: git update-index --chmod=+x $rel"
                fi
                case "$(head -n 1 "$ROOT/$rel")" in
                    '#!'*) ;;
                    *)
                        report "$RULE_SHEBANG" "$file" "$lineno" "$token" \
                            "$rel has no #! line. Run by path, it would not name its interpreter." \
                            "Fix: start it with #!/usr/bin/env bash"
                        ;;
                esac
                ;;
        esac
    done <<EOF
$(scan_file "$ROOT/$file")
EOF
}

# -- main --------------------------------------------------------------------

load_allowlist

FILES=$(git -C "$ROOT" ls-files -- skills references \
    | grep -E '\.md$' \
    | grep -vE '^skills/[^/]+/evals/' || true)

checked=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    checked=$((checked + 1))
    check_file "$file"
done <<EOF
$FILES
EOF

if [ "$errors" -gt 0 ]; then
    echo ""
    echo "check-directive-invocations: $errors finding(s) across $checked file(s)"
    exit 1
fi

echo "check-directive-invocations: OK ($checked directive file(s) checked)"
exit 0
