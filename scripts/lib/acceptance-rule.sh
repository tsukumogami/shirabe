# acceptance-rule.sh -- the interim acceptance rule: who may accept, decline
# or overrule a test edit or an observation, and whether a unit's ledger
# counts it.
#
# Sourced, never run. Every allow-or-refuse decision about a test change is
# made here and nowhere else: skills/work-on/scripts/test-change.sh asks
# acceptance_rule_decide before it writes an accept or a decline, and its
# status gate asks acceptance_rule_live, which replays acceptance_rule_decide
# over every stored line. When a shared decision rule for delegated decisions
# lands, it replaces the bodies of these two functions; the callers pass the
# same inputs and read the same answers. skills/work-on/references/red-first.md
# says what the rule means for a run.
#
#   acceptance_rule_decide <identity> <kind> <authority> <action> <author> \
#       <person_required> <terminal> <seat_minted> <session_exists> [<target_authority>]
#
#     Prints `allow`, or `refuse <rule-id> <reason>`, and returns 0 either way.
#     <kind> is agent or person, <authority> reviewer, coordinator or owner,
#     <action> accept, decline or overrule, <author> the run's own identity
#     (agent:<session>), and the four flags true or false. <target_authority>
#     is the authority of the acceptance an overrule targets. The rules, checked
#     in this order so an attempt that breaks several is refused by the first:
#
#       author           the author's identity can't accept or overrule
#       authority-kind   an agent acts only as reviewer or coordinator, a
#                        person only as reviewer or owner
#       person-required  a repository that requires a person refuses every
#                        agent acceptance
#       unminted-seat    an agent at reviewer must be an unused seat the run
#                        minted
#       unknown-session  an agent at coordinator must name an existing koto
#                        session other than the run and its seats
#       no-terminal      a person counts only from an interactive terminal
#       not-higher       an overrule needs an authority strictly higher than
#                        the acceptance it targets
#
#   acceptance_rule_live <ledger-file> <current-digests-file>
#
#     Folds the ledger against the items that need an acceptance now, and
#     prints `counted`, or one `held<TAB><reason>` line per reason. The
#     digests file has one `<item><TAB><digest>` row per item: an edited test
#     file by path with its blob id (or `deleted`), or an observation as
#     `observation:before` or `observation:after` with its digest. An empty
#     file means nothing needs an acceptance.
#
#     The ledger's first line must be its header (`event: header`, with the
#     author); without one every unit is held (`no header`). Every accept and
#     decline line is judged again with acceptance_rule_decide from what the
#     ledger itself shows (whether its seat was minted and unused at that
#     point, the header's author and person-required flag), so a hand-written
#     line the rule would refuse never counts. A person line counts only with a
#     terminal this fold can verify, which this version can't, so none does;
#     a stored terminal flag is never trusted. The last judgment that counts
#     for an item decides it:
#
#       no judgment, or a decline of an older digest   unaccepted <item>
#       an accept of an older digest                    changed since acceptance <item>
#       a decline of the current digest                 declined <item> by <identity>
#       an accept of the current digest                 (covered)
#
#     Declines are also counted per sorted path set; the third that counts on
#     one set prints `held<TAB>decline-limit <paths>`, whatever the items now.
#
# Written for the bash 3.2 floor: no associative arrays, no mapfile. Needs jq.

# _ar_rank <authority>: 1, 2 or 3; 0 for anything else.
_ar_rank() {
    case "$1" in
        reviewer) echo 1 ;;
        coordinator) echo 2 ;;
        owner) echo 3 ;;
        *) echo 0 ;;
    esac
}

acceptance_rule_decide() {
    local identity="$1" kind="$2" authority="$3" action="$4" author="$5"
    local person_required="$6" terminal="$7" seat_minted="$8" session_exists="$9"
    local target="${10:-}"

    if [ "$identity" = "$author" ] && { [ "$action" = accept ] || [ "$action" = overrule ]; }; then
        echo "refuse author the run's own identity can't $action its own test change"
        return 0
    fi
    case "$kind:$authority" in
        agent:reviewer|agent:coordinator|person:reviewer|person:owner) ;;
        *)
            echo "refuse authority-kind an $kind can't act as ${authority:-nothing}; an agent acts as reviewer or coordinator, a person as reviewer or owner"
            return 0
            ;;
    esac
    if [ "$person_required" = true ] && [ "$kind" = agent ] && [ "$action" = accept ]; then
        echo "refuse person-required the repository requires a person to accept a test change"
        return 0
    fi
    if [ "$kind" = agent ] && [ "$authority" = reviewer ] && [ "$seat_minted" != true ]; then
        echo "refuse unminted-seat an agent at reviewer must be an unused seat the run minted (test-change.sh seat)"
        return 0
    fi
    if [ "$kind" = agent ] && [ "$authority" = coordinator ] && [ "$session_exists" != true ]; then
        echo "refuse unknown-session an agent at coordinator must name an existing koto session other than the run and its seats"
        return 0
    fi
    if [ "$kind" = person ] && [ "$terminal" != true ]; then
        echo "refuse no-terminal a person's attempt counts only from an interactive terminal"
        return 0
    fi
    if [ "$action" = overrule ] && [ "$(_ar_rank "$authority")" -le "$(_ar_rank "$target")" ]; then
        echo "refuse not-higher an overrule needs an authority above the acceptance's (${target:-none})"
        return 0
    fi
    echo allow
    return 0
}

acceptance_rule_live() {
    local ledger="$1" current="$2" w tab us
    tab=$(printf '\t')
    us=$(printf '\037')
    w=$(mktemp -d "${TMPDIR:-/tmp}/acceptance-rule.XXXXXX") || { printf 'held\tthe rule could not create a temporary directory\n'; return 0; }

    # The header: the first line, which must say who the author is.
    local author person_required
    author=$(head -n 1 "$ledger" 2>/dev/null | jq -r 'select(type == "object" and .event == "header") | .author // empty' 2>/dev/null)
    if [ -z "$author" ]; then
        printf 'held\tno header: the ledger has no header line, so nothing it holds can count (test-change.sh init writes it)\n'
        rm -rf "$w"
        return 0
    fi
    person_required=$(head -n 1 "$ledger" | jq -r 'if .person_required == true then "true" else "false" end')

    # One row per seat, accept and decline line after the header:
    # event, identity, kind, authority, session_exists, then the files as
    # path<US>digest pairs, one field each. Paths hold no control character
    # (test-change.sh strips them), so tabs and the unit separator are safe.
    # An empty field is written as `-`: a tab is whitespace to `read`, which
    # would otherwise fold an empty field away and shift the rest.
    tail -n +2 "$ledger" | jq -Rr --arg us "$us" '
        fromjson? | select(type == "object" and (.event == "seat" or .event == "accept" or .event == "decline"))
        | [.event, (.identity // ""), (.kind // ""), (.authority // ""),
           (if .session_exists == true then "true" else "false" end)]
          + [(.files // [])[] | select(type == "object") | "\(.path // "")\($us)\(.digest // "")"]
        | map(tostring | gsub("[\t\n\r]"; " ") | if . == "" then "-" else . end) | join("\t")' 2>/dev/null > "$w/rows"

    local minted="" used="" ev id kind auth sx rest verdict f p d key
    : > "$w/judged"
    : > "$w/declines"
    while IFS="$tab" read -r ev id kind auth sx rest; do
        case "$ev" in
            seat)
                minted="$minted
$id"
                continue
                ;;
        esac
        local seat=false
        if printf '%s\n' "$minted" | grep -Fxq -- "$id" && ! printf '%s\n' "$used" | grep -Fxq -- "$id"; then
            seat=true
        fi
        # A seat is used by its first judgment, allowed or not.
        used="$used
$id"
        verdict=$(acceptance_rule_decide "$id" "$kind" "$auth" "$ev" "$author" "$person_required" false "$seat" "$sx")
        [ "$verdict" = allow ] || continue
        : > "$w/paths"
        printf '%s\n' "$rest" | tr '\t' '\n' > "$w/files"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            p=${f%%"$us"*}
            d=${f#*"$us"}
            printf '%s\t%s\t%s\t%s\n' "$p" "$ev" "$d" "$id" >> "$w/judged"
            printf '%s\n' "$p" >> "$w/paths"
        done < "$w/files"
        if [ "$ev" = decline ]; then
            key=$(LC_ALL=C sort -u "$w/paths" | paste -sd, -)
            printf '%s\n' "$key" >> "$w/declines"
        fi
    done < "$w/rows"

    : > "$w/held"
    local item digest last jev jd jid
    while IFS="$tab" read -r item digest; do
        [ -n "$item" ] || continue
        last=$(awk -F '\t' -v p="$item" '$1 == p { l = $0 } END { print l }' "$w/judged")
        if [ -z "$last" ]; then
            printf 'held\tunaccepted %s\n' "$item" >> "$w/held"
            continue
        fi
        jev=$(printf '%s' "$last" | cut -f 2)
        jd=$(printf '%s' "$last" | cut -f 3)
        jid=$(printf '%s' "$last" | cut -f 4)
        if [ "$jd" != "$digest" ]; then
            if [ "$jev" = accept ]; then
                printf 'held\tchanged since acceptance %s\n' "$item" >> "$w/held"
            else
                printf 'held\tunaccepted %s\n' "$item" >> "$w/held"
            fi
        elif [ "$jev" = decline ]; then
            printf 'held\tdeclined %s by %s\n' "$item" "$jid" >> "$w/held"
        fi
    done < "$current"
    LC_ALL=C sort "$w/declines" | uniq -c | awk '$1 >= 3 { sub(/^ *[0-9]+ /, ""); print "held\tdecline-limit " $0 }' >> "$w/held"

    if [ -s "$w/held" ]; then
        cat "$w/held"
    else
        echo counted
    fi
    rm -rf "$w"
    return 0
}
