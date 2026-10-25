#!/usr/bin/env bash
# dispatch-link.sh -- record which session dispatched a session, through
# koto's link verb, and say so when koto won't record it.
#
# Sourced by scripts/skill-session.sh (`adopt`, and `open --dispatched-by`),
# skills/work-on/scripts/work-on-open.sh (`--dispatched-by`) and /coordinate's
# coordinate-open.sh and link-dispatcher.sh, so the openers that link a session
# to its dispatcher retry, warn and record the same way. koto keeps a session
# while anything in its hierarchy is alive (`koto session hierarchy <name>`
# shows why), and a dispatched-by link is what joins a dispatched session to
# the session that dispatched it.
#
# dl_valid_dispatcher <name>
#   exit 0 when <name> can be a dispatcher: koto's session-name rule
#   (^[A-Za-z0-9][A-Za-z0-9._-]*$) and at most 200 bytes, so the link key
#   koto/links/dispatched-by/<name> stays inside koto's key length cap. The
#   caller refuses anything else before any koto call.
#
# dl_link <koto> <session> <dispatcher>
#   runs `<koto> session link <session> --dispatched-by <dispatcher>` and, when
#   it fails, runs it once more. On success it removes an earlier failure's
#   record of this dispatcher from <session> (DL_WARNING_KEY) and returns 0,
#   printing nothing. When both attempts fail it prints, on stdout,
#     warning=link-failed dispatched_by=<dispatcher>
#   writes the key DL_WARNING_KEY into <session> as the two lines
#     warning=link-failed
#     dispatched_by=<dispatcher>
#   says what happened on stderr, and returns 1. A failed link never stops the
#   caller: the session is open and usable, it is just not joined to its
#   dispatcher's hierarchy. A key that can't be written is said on stderr too.
#   A session linked to two dispatchers (a carried /coordinate run, joined to
#   the run it carried and to the run that dispatched it) keeps one
#   dispatched_by line per dispatcher whose link failed, under the one
#   warning line: a failure adds its line, a success removes only its own,
#   and the key goes when no line is left. A key that can't be read is taken
#   as holding no other dispatcher.
#
# Requires: bash 3.2+. No eval, no associative arrays, no namerefs.

DL_WARNING_KEY="session/link-warning"
DL_RE_NAME='^[A-Za-z0-9][A-Za-z0-9._-]*$'

dl_valid_dispatcher() {
    [ "${#1}" -le 200 ] || return 1
    [[ "$1" =~ $DL_RE_NAME ]]
}

# dl_others <koto> <session> <dispatcher>: the dispatched_by lines the
# session's warning key holds for every other dispatcher, one per line.
dl_others() {
    "$1" context get "$2" "$DL_WARNING_KEY" 2>/dev/null </dev/null \
        | grep '^dispatched_by=' | grep -vxF "dispatched_by=$3"
    return 0
}

dl_link() {
    local koto="$1" s="$2" d="$3" others
    if "$koto" session link "$s" --dispatched-by "$d" >/dev/null 2>&1 \
        || "$koto" session link "$s" --dispatched-by "$d" >/dev/null 2>&1; then
        others=$(dl_others "$koto" "$s" "$d")
        if [ -z "$others" ]; then
            "$koto" context remove "$s" "$DL_WARNING_KEY" >/dev/null 2>&1
        else
            printf 'warning=link-failed\n%s\n' "$others" | "$koto" context add "$s" "$DL_WARNING_KEY" >/dev/null 2>&1
        fi
        return 0
    fi
    printf 'warning=link-failed dispatched_by=%s\n' "$d"
    printf 'dispatch-link: koto did not record that %s dispatched %s (two attempts); %s is open but outside %s'"'"'s hierarchy, so koto may reclaim it on its own schedule\n' \
        "$d" "$s" "$s" "$d" >&2
    others=$(dl_others "$koto" "$s" "$d")
    if ! printf 'warning=link-failed\n%s%sdispatched_by=%s\n' "$others" "${others:+$'\n'}" "$d" \
        | "$koto" context add "$s" "$DL_WARNING_KEY" >/dev/null 2>&1; then
        printf 'dispatch-link: could not record the failed link in %s as %s either\n' "$s" "$DL_WARNING_KEY" >&2
    fi
    return 1
}
