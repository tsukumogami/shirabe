# review-verdicts.sh -- the parser for a jury seat's review-verdicts block,
# shared by scripts/review-events.sh (which records a round's verdicts) and
# scripts/doc-events.sh (whose `fix --answers jury_fail` reads the FAIL
# entries a fix answers). references/review-verdicts.md describes the block.
#
# Sourced, never run. The caller sets PROG and PLUGIN_ROOT and sources
# scripts/lib/doc-session.sh first (for ds_notice). Functions:
#
#   rv_seats_of <skill>   the skill's jury seats, one `<seat>\t<pinned file>`
#                         line each; the jury references pin these file names
#   rv_block <src> <out>  writes the last complete fenced `review-verdicts`
#                         block of <src> to <out> (empty when there is none)
#   rv_entries <block> <sections> <seat> <out> <list name>
#                         writes one `<rule>\t<section>\t<verdict>` line per
#                         valid entry of <block> to <out>, and returns 1 when
#                         the block isn't a JSON array. An entry is dropped
#                         when it isn't an object of string rule_id, section
#                         and verdict, when its verdict isn't PASS or FAIL, or
#                         when its rule id isn't one `rule-registry.sh
#                         resolve` resolves. A section outside <sections> (one
#                         slug per line) is kept as `document`, with a notice
#                         saying it is not on the <list name> list. Each drop or
#                         change is a notice naming the seat, the entry number
#                         and the field, never the text the seat wrote.
#   rv_registered <id>    whether the registry resolves <id>
#
# The seat name always comes from rv_seats_of and the pinned file name, never
# from the seat's output.
#
# Written for the bash 3.2 floor.

RV_ID_SHAPE='^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3}|rs-verdict-missing)$'

rv_seats_of() {
    case "$1" in
        brief) printf '%s\t%s\n' content-quality phase4_content-quality.md structural-format phase4_structural-format.md ;;
        prd) printf '%s\t%s\n' completeness phase4_completeness.md clarity phase4_clarity.md testability phase4_testability.md ;;
        design) printf '%s\t%s\n' architecture phase6_architecture-review.md security phase6_security-review.md \
            structural-format phase6_structural-format-review.md ;;
        plan) printf '%s\t%s\n' scope-gate category-a.md design-fidelity category-b.md ac-discriminability category-c.md \
            sequencing category-d.md functional-shape category-e.md ;;
        vision) printf '%s\t%s\n' thesis-quality phase4_thesis-quality.md content-boundary phase4_content-boundary.md \
            section-guidance phase4_section-guidance.md ;;
        strategy) printf '%s\t%s\n' bet-quality phase4_bet-quality.md altitude phase4_altitude.md \
            structural-format phase4_structural-format.md ;;
        roadmap) printf '%s\t%s\n' theme-coherence phase4_theme-coherence.md sequencing-dependency phase4_sequencing-dependency.md \
            annotation-boundary phase4_annotation-boundary.md ;;
    esac
}

rv_registered() {
    [[ "$1" =~ $RV_ID_SHAPE ]] || return 1
    "$PLUGIN_ROOT/scripts/rule-registry.sh" resolve "$1" >/dev/null 2>&1
}

rv_block() {
    awk '/^```review-verdicts[ \t]*$/ { inside = 1; n++; buf[n] = ""; next }
         inside && /^```[ \t]*$/ { inside = 0; done[n] = 1; next }
         inside { buf[n] = buf[n] $0 "\n" }
         END { for (i = n; i >= 1; i--) if (i in done) { printf "%s", buf[i]; exit } }' "$1" > "$2" 2>/dev/null
}

rv_entries() {
    local block=$1 sections=$2 seat=$3 out=$4 list=$5 e n bad verdict rule section
    : > "$out"
    jq -e 'type == "array"' "$block" >/dev/null 2>&1 || return 1
    while IFS= read -r e; do
        n=$(( $(printf '%s' "$e" | jq -r '.key') + 1 ))
        bad=$(printf '%s' "$e" | jq -r '.value as $v
            | if ($v | type) != "object" then "entry"
              else (["rule_id", "section", "verdict"][] | select(($v[.] | type) != "string")) end' | head -n 1)
        if [ -n "$bad" ]; then
            ds_notice "seat $seat entry $n: $bad is missing or not a string; dropped"
            continue
        fi
        verdict=$(printf '%s' "$e" | jq -r '.value.verdict')
        case "$verdict" in
            PASS|FAIL) ;;
            *) ds_notice "seat $seat entry $n: verdict is not PASS or FAIL; dropped"; continue ;;
        esac
        rule=$(printf '%s' "$e" | jq -r '.value.rule_id')
        if ! rv_registered "$rule"; then
            ds_notice "seat $seat entry $n: rule_id is not a registered rule; dropped"
            continue
        fi
        section=$(printf '%s' "$e" | jq -r '.value.section')
        # The slug shape comes first: grep -F reads a value with a newline as
        # several patterns, so "document\n<forged row>" would match the list
        # and its extra line would reach the tab-separated output as an
        # unchecked entry.
        if ! [[ "$section" =~ ^[a-z0-9-]+$ ]] || ! grep -qxF -- "$section" "$sections"; then
            ds_notice "seat $seat entry $n: section is not on the $list list; recorded as document"
            section=document
        fi
        printf '%s\t%s\t%s\n' "$rule" "$section" "$verdict" >> "$out"
    done <<EOF
$(jq -c 'to_entries[]' "$block")
EOF
    return 0
}
