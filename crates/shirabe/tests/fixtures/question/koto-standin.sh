#!/usr/bin/env bash
# A koto stand-in for the `shirabe question` tests. It logs every call to
# $KOTO_STANDIN/log, one line of arguments per call, and answers from files
# under $KOTO_STANDIN, so a test can show which koto commands ran and serve
# the records a case needs without a koto store.
#
# Files a test may write under $KOTO_STANDIN (all optional):
#   version            the version `koto version` reports (default 0.42.0)
#   fail               one line per call prefix that fails, e.g.
#                      "decisions content write", optionally followed by
#                      "|<code>|<error>" and "|<field>"; a matching call
#                      prints a koto-shaped refusal and exits 2
#   origin/<session>   the JSON `session origin <session>` prints
#   attempts/<session> the JSON `decisions attempts --in <session>` prints
#   open-person.json   the JSON `decisions open --person owner` prints
#   open-at.json       the JSON `decisions open --at <x>` prints
#   history/<key>      the JSON `decisions history <identity>` prints
#   content/<key>      the bytes `decisions content read <identity>` prints
#   answer.json        the JSON `decisions answer` (not a withdrawal) prints
#   show-answer.json   the JSON `decisions show` of an answer entry prints
#   show/<session>_<id> the JSON `decisions show <session> <id>` prints, ahead
#                      of the other `show` answers
#   precedent.json     the JSON `decisions precedent` prints
#   readdress.json     the JSON `decisions readdress` prints; without it, a
#                      pass-up numbered from the counter
#   sleep              one line per call prefix that hangs (sleeps 60 seconds),
#                      matched against the call as `log` records it
# <key> is the identity with its "/" replaced by "_". A session's id is
# "sid-<session name>".
#
# shirabe puts options before a `--` and the positionals after it, with
# caller values as `--option=value`. The stand-in records each call exactly
# as given in $KOTO_STANDIN/rawlog, then rewrites it to subcommand words,
# positionals, then options, each `--option=value` split in two, and logs and
# serves that form.
set -euo pipefail

D="${KOTO_STANDIN:?KOTO_STANDIN is not set}"
printf '%s\n' "$*" >> "$D/rawlog"

words=()
pos=()
opts=()
after_dash=0
for a in "$@"; do
    if [ "$after_dash" = 1 ]; then pos+=("$a"); continue; fi
    case "$a" in
        --) after_dash=1 ;;
        --*=*) opts+=("${a%%=*}" "${a#*=}") ;;
        -*) opts+=("$a") ;;
        *)
            if [ "${#opts[@]}" -gt 0 ]; then opts+=("$a"); else words+=("$a"); fi
            ;;
    esac
done
set -- ${words[@]+"${words[@]}"} ${pos[@]+"${pos[@]}"} ${opts[@]+"${opts[@]}"}
printf '%s\n' "$*" >> "$D/log"

if [ -f "$D/sleep" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        case "$*" in
            "$line"*) exec sleep 60 ;;
        esac
    done < "$D/sleep"
fi

refuse() { # refuse <code> <error> [field]
    if [ -n "${3:-}" ]; then
        printf '{"code":"%s","command":"standin","error":"%s","field":"%s"}\n' "$1" "$2" "$3"
    else
        printf '{"code":"%s","command":"standin","error":"%s","field":null}\n' "$1" "$2"
    fi
    exit 2
}

if [ -f "$D/fail" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        prefix="${line%%|*}"
        code=standin_failure
        error="the stand-in fails $prefix"
        field=""
        case "$line" in
            *"|"*)
                rest="${line#*|}"
                code="${rest%%|*}"
                error="${rest#*|}"
                case "$error" in
                    *"|"*)
                        field="${error#*|}"
                        error="${error%%|*}"
                        ;;
                esac
                ;;
        esac
        case "$*" in
            "$prefix"*) refuse "$code" "$error" "$field" ;;
        esac
    done < "$D/fail"
fi

header_of() {
    printf '#%s' "$(printf '%s' "$1" | sha256sum | cut -c1-11)"
}

next_id() {
    local n=0
    [ -f "$D/counter" ] && n=$(cat "$D/counter")
    n=$((n + 1))
    printf '%s' "$n" > "$D/counter"
    printf '%012d' "$n"
}

case "${1:-} ${2:-}" in
    "version "*)
        printf 'koto %s (standin)\n' "$(cat "$D/version" 2>/dev/null || echo 0.42.0)"
        ;;
    "session origin")
        if [ -f "$D/origin/$3" ]; then cat "$D/origin/$3"; else
            printf '{"session":"%s","via":null,"origin":{"state":"none"}}\n' "$3"
        fi
        ;;
    "decisions attempts")
        if [ -f "$D/attempts/$4" ]; then cat "$D/attempts/$4"; else
            printf '{"v":1,"in":"%s","attempts":[],"unreadable":[]}\n' "$4"
        fi
        ;;
    "decisions record")
        session="$3"
        shift 3
        packet=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --subject) case "$2" in packet=*) packet="${2#packet=}" ;; esac; shift ;;
            esac
            shift
        done
        id=$(next_id)
        key="sid-${session}_${id}"
        mkdir -p "$D/raised"
        printf '%s\n%s\n' "$session" "$packet" > "$D/raised/$key"
        printf '{"v":1,"id":"%s","session":"%s","status":"in-effect","decision":{"id":"%s","session":{"id":"sid-%s","name":"%s"}}}\n' \
            "$id" "$session" "$id" "$session" "$session"
        ;;
    "decisions content")
        case "$3" in
            write)
                session="$4" id="$5" file="$7"
                identity="sid-$session/$id"
                mkdir -p "$D/content"
                cp "$file" "$D/content/${identity/\//_}"
                printf '{"v":1,"session":"%s","id":"%s","question":"%s","packet":"x","bytes":%s,"prompt_header":"%s"}\n' \
                    "$session" "$id" "$identity" "$(wc -c < "$file" | tr -d ' ')" "$(header_of "$identity")"
                ;;
            read)
                key="${4/\//_}"
                [ -f "$D/content/$key" ] || refuse decision_not_found "no content for $4"
                cat "$D/content/$key"
                ;;
        esac
        ;;
    "decisions history")
        key="${3/\//_}"
        if [ -f "$D/history/$key" ]; then cat "$D/history/$key"; exit 0; fi
        [ -f "$D/raised/$key" ] || refuse decision_not_found "no question $3"
        { read -r session; read -r packet; } < "$D/raised/$key"
        id="${3#*/}"
        printf '{"v":1,"identity":"%s","raiser":{"name":"%s","id":"sid-%s"},"question":{"id":"%s","packet":"%s","content_stored":true},"open":true,"answer":null,"entries":[]}\n' \
            "$3" "$session" "$session" "$id" "$packet"
        ;;
    "decisions show")
        if [ -f "$D/show/${3}_$4" ]; then cat "$D/show/${3}_$4"; exit 0; fi
        if [ -f "$D/show-answer.json" ] && [ -f "$D/answered" ]; then cat "$D/show-answer.json"; exit 0; fi
        printf '{"v":1,"id":"%s","session":"%s","prompt_header":"%s"}\n' "$4" "$3" "$(header_of "sid-$3/$4")"
        ;;
    "decisions open")
        case "$3" in
            --person) cat "$D/open-person.json" 2>/dev/null || echo '{"v":1,"person":"owner","questions":[]}' ;;
            --at) cat "$D/open-at.json" 2>/dev/null || printf '{"v":1,"at":"%s","questions":[]}\n' "$4" ;;
        esac
        ;;
    "decisions answer")
        case " $* " in
            *" --outcome withdrawn "*) printf '{"v":1,"id":"w1","session":"%s","status":"in-effect"}\n' "$3" ;;
            *)
                : > "$D/answered"
                cat "$D/answer.json" 2>/dev/null || printf '{"v":1,"id":"000000000009","session":"%s","status":"in-effect"}\n' "$6"
                ;;
        esac
        ;;
    "decisions list")
        printf '{"v":1,"session":"%s","decisions":[]}\n' "$3"
        ;;
    "decisions precedent")
        cat "$D/precedent.json" 2>/dev/null || echo '{"v":1,"person":"owner","answers":[]}'
        ;;
    "decisions readdress")
        if [ -f "$D/readdress.json" ]; then cat "$D/readdress.json"; exit 0; fi
        raiser="$3" qid="$4"
        shift 4
        in="" to=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --in) in="$2"; shift ;;
                --to) to="$2"; shift ;;
            esac
            shift
        done
        id=$(next_id)
        printf '{"v":1,"id":"%s","session":"%s","question":"sid-%s/%s","status":"in-effect","addressee":"%s"}\n' \
            "$id" "$in" "$raiser" "$qid" "$to"
        ;;
    *)
        refuse standin_unknown "the stand-in does not serve: $*"
        ;;
esac
