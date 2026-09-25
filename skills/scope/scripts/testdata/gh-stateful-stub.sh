#!/usr/bin/env bash
# gh-stateful-stub.sh -- a gh stand-in for /scope's publish tests.
#
# Installed on PATH as `gh` by publish-scoping-pr_test.sh and the engine suite.
# It keeps the pull requests of one fake repository in $GHF/prs.json and
# answers the calls /scope's scripts make:
#
#   gh api user                       {"login": $GH_LOGIN (default "me")}
#   gh api repos/<r>                  {"default_branch": $GH_DEFAULT}
#   gh repo view --json ... [--jq f]  nameWithOwner $GH_REPO, defaultBranchRef
#   gh pr list --head <b> ...         prs.json entries whose headRefName is <b>
#                                     and whose state matches --state
#   gh pr view <url> --json <f> [--jq f]
#   gh pr create --head --base --title --body-file [--draft]
#                                     appends an owned OPEN PR (fails with the
#                                     status in $GHF/pr-create.rc when present)
#   gh pr edit <url> --body-file <f>  replaces that PR's body
#
# Every call's argument list is appended to $GHF/calls first. A key file
# $GHF/<key>.rc (pr-list, pr-view, repo-view) makes that call fail.
set -uo pipefail

: "${GHF:?GHF must name the state directory of the stub}"
LOGIN="${GH_LOGIN:-me}"
REPO="${GH_REPO:-acme/widgets}"
DEFAULT="${GH_DEFAULT:-main}"
PRS="$GHF/prs.json"
[ -f "$PRS" ] || printf '[]' >"$PRS"

printf '%s\n' "$*" >>"$GHF/calls"

# argval <flag> <args...> -- the value following <flag>.
argval() {
    local want="$1" prev=""
    shift
    for a in "$@"; do
        [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }
        prev="$a"
    done
    return 1
}
has_flag() {
    local want="$1"
    shift
    for a in "$@"; do [ "$a" = "$want" ] && return 0; done
    return 1
}
emit() { # emit <json> <args...> -- apply a trailing --jq
    local json="$1" f
    shift
    if f=$(argval --jq "$@"); then printf '%s' "$json" | jq -r "$f"; else printf '%s\n' "$json"; fi
}
failing() { [ -f "$GHF/$1.rc" ] && exit "$(cat "$GHF/$1.rc")"; return 0; }

case "${1:-} ${2:-}" in
    "api user") printf '{"login":"%s"}\n' "$LOGIN" ;;
    "api repos/"*) printf '{"default_branch":"%s"}\n' "$DEFAULT" ;;
    "repo view")
        failing repo-view
        emit "$(jq -nc --arg r "$REPO" --arg d "$DEFAULT" '{nameWithOwner: $r, defaultBranchRef: {name: $d}}')" "$@"
        ;;
    "pr list")
        failing pr-list
        head=$(argval --head "$@") || head=""
        state=$(argval --state "$@") || state=open
        emit "$(jq -c --arg h "$head" --arg s "$state" '
            map(select(.headRefName == $h
                and (if $s == "open" then .state == "OPEN" else true end)))' "$PRS")" "$@"
        ;;
    "pr view")
        failing pr-view
        url="${3:-}"
        emit "$(jq -c --arg u "$url" 'map(select(.url == $u)) | .[0] // {}' "$PRS")" "$@"
        ;;
    "pr create")
        [ -f "$GHF/pr-create.rc" ] && { echo "gh stub: pr create failed" >&2; exit "$(cat "$GHF/pr-create.rc")"; }
        head=$(argval --head "$@") || exit 2
        base=$(argval --base "$@") || exit 2
        bodyf=$(argval --body-file "$@") || exit 2
        draft=false; has_flag --draft "$@" && draft=true
        n=$(( $(jq 'length' "$PRS") + 100 ))
        url="https://github.com/$REPO/pull/$n"
        jq --arg u "$url" --arg h "$head" --arg b "$base" --arg l "$LOGIN" \
           --rawfile body "$bodyf" --argjson d "$draft" \
           '. + [{url: $u, state: "OPEN", isCrossRepository: false, author: {login: $l},
                  baseRefName: $b, headRefName: $h, body: $body, isDraft: $d}]' \
           "$PRS" >"$PRS.new" && mv "$PRS.new" "$PRS"
        printf '%s\n' "$url"
        ;;
    "pr edit")
        url="${3:-}"
        bodyf=$(argval --body-file "$@") || exit 2
        jq --arg u "$url" --rawfile body "$bodyf" 'map(if .url == $u then .body = $body else . end)' \
            "$PRS" >"$PRS.new" && mv "$PRS.new" "$PRS"
        ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 9 ;;
esac
