# pr-url.sh -- the one parse of a pull request URL into its host, owner and
# repository.
# Part of the work-on skill
#
# Sourced, never run. ci-none-declared.sh and ci-cancel-after-merge.sh both
# take the repository a pull request lives in from its URL and read more from
# that repository through `gh api`. gh api sends a request to gh's default
# host unless it is told otherwise, so the host has to come from the URL too:
# on a GitHub Enterprise host, or anywhere the default host isn't the pull
# request's, a read built from owner/repo alone goes to the wrong server
# (#1051). Both scripts parse here, so a fix to the parse reaches both.
#
# The URL is the one gh answers for a pull request:
#
#   https://<host>/<owner>/<repo>/pull/<number>
#
# optionally followed by a suffix that starts with `/`, `?` or `#` (a
# trailing slash, `/files`, a query, a fragment), which is ignored. The host
# keeps a `:<port>` when it has one, since that is part of where the server
# is. Anything else is refused rather than guessed at: another scheme, an
# empty host or one with userinfo, an issue or other non-pull path, a number
# that isn't all digits, an owner or repository that is empty, `.` or `..`,
# and a path with more segments before `/pull/` than owner and repository.
# The last is how a server under a path prefix (`https://<host>/<prefix>/
# <owner>/<repo>/pull/<n>`) would look; gh doesn't serve one, and reading
# `<prefix>` as the owner would send the read to the wrong repository.
#
# Function:
#
#   pr_url_parse <url>   sets PR_HOST, PR_OWNER and PR_REPO and returns 0,
#                        or sets all three empty and returns 1. Prints
#                        nothing: each caller words its own refusal.
#
# Callers set `set -uo pipefail` themselves; this file changes no option.
#
# Bash 3.2: no associative arrays, no mapfile. The pattern is kept in a
# variable and used unquoted on the right of =~, the form 3.2 and 5 read the
# same way.

pr_url_parse() {
    local url="${1:-}"
    local re='^https://([A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?)/([^/?#[:space:]]+)/([^/?#[:space:]]+)/pull/([0-9]+)([/?#].*)?$'
    PR_HOST=""
    PR_OWNER=""
    PR_REPO=""
    # One URL is one line. The suffix's `.*` could otherwise carry a second
    # line, and a lookup that answered two URLs must not pass as its first.
    case "$url" in
        *$'\n'*|*$'\r'*) return 1 ;;
    esac
    [[ $url =~ $re ]] || return 1
    case "${BASH_REMATCH[3]}" in .|..) return 1 ;; esac
    case "${BASH_REMATCH[4]}" in .|..) return 1 ;; esac
    PR_HOST="${BASH_REMATCH[1]}"
    PR_OWNER="${BASH_REMATCH[3]}"
    PR_REPO="${BASH_REMATCH[4]}"
    return 0
}
