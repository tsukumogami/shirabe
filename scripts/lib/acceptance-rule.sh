# acceptance-rule.sh -- the interim acceptance rule: who may accept, decline
# or overrule a test edit or an observation, and whether a unit's ledger
# counts it.
#
# Sourced, never run. Every allow-or-refuse decision about a test change is
# made here and nowhere else: skills/work-on/scripts/test-change.sh asks
# acceptance_rule_decide before it writes an accept, a decline or an overrule,
# and its status gate asks acceptance_rule_live, which replays
# acceptance_rule_decide over every stored line. When a shared decision rule
# for delegated decisions lands, it replaces the bodies of these two
# functions; the callers pass the same inputs and read the same answers.
# skills/work-on/references/red-first.md says what the rule means for a run.
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
#   acceptance_rule_live <ledger-file> <current-digests-file> [<sessions-file> [<key-file>]]
#
#     Folds the ledger against the items that need an acceptance now, and
#     prints `counted`, or one `held<TAB><reason>` line per reason. The
#     digests file has one `<item><TAB><digest>` row per item: an edited test
#     file by path with its blob id (or `deleted`), or an observation as
#     `observation:before` or `observation:after` with its digest. An empty
#     file means nothing needs an acceptance. The sessions file lists, one per
#     line, the koto sessions that exist now among those the ledger's
#     coordinator lines name; the key file is the per-user key person lines
#     are tagged with. Either may be absent, and then no coordinator
#     acceptance, or no person line, counts.
#
#     The ledger's first line must be its header (`event: header`, with the
#     author); without one every unit is held (`no header`). Every accept,
#     decline and overrule line is judged again with acceptance_rule_decide
#     from what the fold can establish now, never from flags the line stores:
#     whether its seat was minted and unused at that point, the header's
#     author and person-required flag, whether a coordinator's acceptance
#     names a session in the sessions file (a session cleaned up since stops
#     its acceptances counting; its declines and overrules, which only hold
#     the unit, stay in force), and whether a person line's integrity tag checks under the
#     key (acceptance_rule_tag); a stored terminal or session_exists flag is
#     never trusted. So a hand-written line the rule would refuse never
#     counts. An overrule counts only when it targets an earlier accept line
#     by id and the rule finds it strictly higher than that accept; it
#     covers the accept's items.
#
#     Each item is then decided by its judgments in order. An overrule raises
#     the item's floor to its authority and ends a live acceptance below that
#     floor; an accept below the floor is ignored, one at or above it counts
#     again. The last state decides:
#
#       no judgment, or a decline of an older digest   unaccepted <item>
#       an accept of an older digest                    changed since acceptance <item>
#       a decline of the current digest                 declined <item> by <identity>
#       an acceptance ended by an overrule              overruled <item> by <identity>
#       an accept of the current digest                 (covered)
#
#     Declines are also counted per sorted path set; the third that counts on
#     one set prints `held<TAB>decline-limit <paths>`, whatever the items now.
#
#   acceptance_rule_tag <key-file>
#
#     Prints the integrity tag of the text on stdin: a SHA-256 of the key
#     around the text. test-change.sh tags a person line's canonical form
#     (`jq -cS 'del(.tag)'`) with it, and the fold checks that tag. It guards
#     against a hand-written line or a careless edit, not against an agent
#     running as the same user, which can read the key. Returns 1 when the key
#     can't be read or no SHA-256 tool is found.
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

# _ar_sha256: the SHA-256 of stdin, as hex.
_ar_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{ print $1 }'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{ print $1 }'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 | awk '{ print $NF }'
    else
        return 1
    fi
}

acceptance_rule_tag() {
    local keyf="$1" k
    [ -n "$keyf" ] && [ -r "$keyf" ] || return 1
    k=$(tr -d '\n' < "$keyf")
    [ -n "$k" ] || return 1
    { printf '%s\n' "$k"; cat; printf '\n%s\n' "$k"; } | _ar_sha256
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
    local ledger="$1" current="$2" sessions="${3:-}" keyf="${4:-}" w tab us
    tab=$(printf '\t')
    us=$(printf '\037')
    w=$(mktemp -d "${TMPDIR:-/tmp}/acceptance-rule.XXXXXX") || { printf 'held\tthe rule could not create a temporary directory\n'; return 0; }

    # The header: the first line, which must say who the author is.
    local author person_required run
    author=$(head -n 1 "$ledger" 2>/dev/null | jq -r 'select(type == "object" and .event == "header") | .author // empty' 2>/dev/null)
    if [ -z "$author" ]; then
        printf 'held\tno header: the ledger has no header line, so nothing it holds can count (test-change.sh init writes it)\n'
        rm -rf "$w"
        return 0
    fi
    person_required=$(head -n 1 "$ledger" | jq -r 'if .person_required == true then "true" else "false" end')
    run=${author#agent:}

    # Every ledger line as one JSON value per line (null for a line that
    # doesn't parse), so a line's index is its position in the ledger.
    jq -Rc 'fromjson? // null' "$ledger" > "$w/lines" 2>/dev/null

    # The person lines whose integrity tag checks under the key, by index.
    : > "$w/tagok"
    if [ -n "$keyf" ] && [ -r "$keyf" ]; then
        jq -nr '[inputs] | to_entries[]
            | select((.value | type) == "object" and .value.kind == "person"
                     and (.value.event == "accept" or .value.event == "decline" or .value.event == "overrule"))
            | "\(.key)\t\(.value.tag // "")"' < "$w/lines" > "$w/persons" 2>/dev/null
        local pi ptag want
        while IFS="$tab" read -r pi ptag; do
            [ -n "$ptag" ] || continue
            sed -n "$((pi + 1))p" "$w/lines" | jq -cS 'del(.tag)' > "$w/canon" 2>/dev/null || continue
            want=$(acceptance_rule_tag "$keyf" < "$w/canon") || continue
            [ "$want" = "$ptag" ] && printf '%s\n' "$pi" >> "$w/tagok"
        done < "$w/persons"
    fi

    # One row per seat, accept, decline and overrule line: index, event,
    # identity, kind, authority, id, target, then the files as path<US>digest
    # pairs, one field each. Paths hold no control character (test-change.sh
    # strips them), so tabs and the unit separator are safe. An empty field
    # is written as `-`: a tab is whitespace to `read`, which would otherwise
    # fold an empty field away and shift the rest.
    jq -nr --arg us "$us" '[inputs] | to_entries[] | .key as $i | .value
        | select(type == "object" and (.event == "seat" or .event == "accept" or .event == "decline" or .event == "overrule"))
        | [($i | tostring), .event, (.identity // ""), (.kind // ""), (.authority // ""), (.id // ""), (.target // "")]
          + [(.files // [])[] | select(type == "object") | "\(.path // "")\($us)\(.digest // "")"]
        | map(tostring | gsub("[\t\n\r]"; " ") | if . == "" then "-" else . end) | join("\t")' \
        < "$w/lines" > "$w/rows" 2>/dev/null

    local minted="" used="" idx ev id kind auth aid target rest verdict f p d key
    local seat sx term tauth trow rank name
    : > "$w/judged"
    : > "$w/declines"
    while IFS="$tab" read -r idx ev id kind auth aid target rest; do
        case "$ev" in
            seat)
                minted="$minted
$id"
                continue
                ;;
        esac
        seat=false
        if grep -Fxq -- "$id" <<<"$minted" && ! grep -Fxq -- "$id" <<<"$used"; then
            seat=true
        fi
        # A seat is used by its first judgment, allowed or not.
        used="$used
$id"
        # A coordinator's session is checked now, not taken from the line,
        # and only for an accept: an acceptance stops counting once its
        # writer's session is gone, while a decline or an overrule, which can
        # only hold the unit, stays in force. Either way the name must be a
        # session name other than the run's, so neither the run nor one of its
        # seats passes as a coordinator.
        sx=false
        if [ "$kind" = agent ] && [ "$auth" = coordinator ]; then
            name=${id#agent:}
            if [ "$name" != "$run" ] && [[ $name =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
                if [ "$ev" != accept ]; then
                    sx=true
                elif [ -n "$sessions" ] && [ -f "$sessions" ] && grep -Fxq -- "$name" "$sessions"; then
                    sx=true
                fi
            fi
        fi
        term=false
        if [ "$kind" = person ] && grep -Fxq -- "$idx" "$w/tagok"; then
            term=true
        fi
        tauth=""
        if [ "$ev" = overrule ]; then
            # The target: an earlier accept line with that id. It lends the
            # overrule its authority to compare against and its items.
            trow=$(awk -F '\t' -v t="$target" -v i="$idx" '$2 == "accept" && $6 == t && ($1 + 0) < (i + 0) { print; exit }' "$w/rows")
            [ -n "$trow" ] || continue
            tauth=$(printf '%s\n' "$trow" | cut -f 5)
            rest=$(printf '%s\n' "$trow" | cut -f 8-)
        fi
        verdict=$(acceptance_rule_decide "$id" "$kind" "$auth" "$ev" "$author" "$person_required" "$term" "$seat" "$sx" "$tauth")
        [ "$verdict" = allow ] || continue
        rank=$(_ar_rank "$auth")
        : > "$w/paths"
        printf '%s\n' "$rest" | tr '\t' '\n' > "$w/files"
        while IFS= read -r f; do
            [ -n "$f" ] && [ "$f" != "-" ] || continue
            p=${f%%"$us"*}
            d=${f#*"$us"}
            [ "$ev" != overrule ] || d=-
            printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$ev" "$d" "$id" "$rank" >> "$w/judged"
            printf '%s\n' "$p" >> "$w/paths"
        done < "$w/files"
        if [ "$ev" = decline ]; then
            key=$(LC_ALL=C sort -u "$w/paths" | paste -sd, -)
            printf '%s\n' "$key" >> "$w/declines"
        fi
    done < "$w/rows"

    : > "$w/held"
    local item digest
    while IFS="$tab" read -r item digest; do
        [ -n "$item" ] || continue
        awk -F '\t' -v p="$item" -v cur="$digest" '
            $1 == p {
                r = $5 + 0
                if ($2 == "accept") {
                    if (r >= floor) { st = "accept"; d = $3; who = $4; ar = r }
                } else if ($2 == "decline") {
                    st = "decline"; d = $3; who = $4
                } else if ($2 == "overrule") {
                    if (r > floor) floor = r
                    if (st == "accept" && ar < floor) { st = "overruled"; who = $4 }
                }
            }
            END {
                if (st == "") print "held\tunaccepted " p
                else if (st == "overruled") print "held\toverruled " p " by " who
                else if (st == "accept") { if (d != cur) print "held\tchanged since acceptance " p }
                else if (d == cur) print "held\tdeclined " p " by " who
                else print "held\tunaccepted " p
            }' "$w/judged" >> "$w/held"
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
