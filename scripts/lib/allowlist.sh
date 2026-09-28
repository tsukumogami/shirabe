#!/usr/bin/env bash
# allowlist.sh -- the tab-separated allowlist shared by the directive checks.
#
# Sourced, not run. A check that defers known findings keeps them in a
# scripts/<check>.allow file, one record per line:
#
#   <rule>\t<location>\t<subject>\t<issue>\t<reason>
#
# The check decides what the location and subject mean (a directive file and a
# script path, a template and a state name); this file only reads the records,
# rejects the malformed ones and answers whether a finding is deferred. Blank
# lines and #-comments are skipped. The reason field is not parsed.
#
# A record is rejected, and counted as a finding, when:
#
#   - it has fewer than four tab-separated fields, or an empty location or
#     subject;
#   - its rule is not one of the rules the check names;
#   - its issue field carries no issue reference, checked as something#N
#     (owner/repo#N by convention). An allowlist entry is a deferral, and a
#     deferral needs somewhere to be chased; without a ticket it is just a
#     suppression nobody revisits.
#
# State this file owns (read it, don't write it):
#
#   allowlist_rejected  how many records the last allowlist_load rejected. The
#                       caller adds it to its own finding count.
#   allowlist_records   one "<rule>|<location>|<subject>" line per accepted
#                       record. Read it only through allowlist_has.
#
# Written for bash 3.2: no namerefs, no associative arrays.

allowlist_records=""
allowlist_rejected=0

# allowlist_load <allow-file> <location-label> <rule>...
#
# Reads the file if it exists; a missing file is an empty allowlist. The
# location label names field 2 in the error text ("file", "template"), so each
# check's message keeps describing its own format. Each rejected record prints
# a FAIL: line to stdout and counts toward allowlist_rejected.
allowlist_load() {
    local allow_file="$1" location_label="$2"
    shift 2
    allowlist_rejected=0
    [ -f "$allow_file" ] || return 0

    local tab known line rule location subject issue rest lineno=0 r ok
    tab=$(printf '\t')
    known=$(printf '%s, ' "$@")
    known="${known%, }"

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in
            ''|'#'*) continue ;;
        esac

        # Fewer than three tabs means a field is missing, and the expansions
        # below would quietly reuse the last one for every field after it.
        case "$line" in
            *"$tab"*"$tab"*"$tab"*)
                rule="${line%%"$tab"*}"; rest="${line#*"$tab"}"
                location="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
                subject="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
                issue="${rest%%"$tab"*}"
                ;;
            *) location="" subject="" ;;
        esac

        if [ -z "$location" ] || [ -z "$subject" ]; then
            echo "FAIL: $allow_file:$lineno is not a tab-separated record"
            echo "  expected: <rule><TAB><$location_label><TAB><subject><TAB><issue><TAB><reason>"
            allowlist_rejected=$((allowlist_rejected + 1))
            continue
        fi

        ok=0
        for r in "$@"; do
            [ "$rule" = "$r" ] && ok=1
        done
        if [ "$ok" -eq 0 ]; then
            echo "FAIL: $allow_file:$lineno names an unknown rule '$rule'"
            echo "  known rules: $known"
            allowlist_rejected=$((allowlist_rejected + 1))
            continue
        fi

        case "$issue" in
            *[A-Za-z0-9]'#'[0-9]*) ;;
            *)
                echo "FAIL: $allow_file:$lineno has no issue reference"
                echo "  field 4 must carry one, in the form owner/repo#N"
                echo "  record: $line"
                allowlist_rejected=$((allowlist_rejected + 1))
                continue
                ;;
        esac

        allowlist_records="${allowlist_records}${rule}|${location}|${subject}
"
    done < "$allow_file"
}

# allowlist_has <rule> <location> <subject> -- true when a record defers it.
allowlist_has() {
    case "
$allowlist_records" in
        *"
$1|$2|$3
"*) return 0 ;;
    esac
    return 1
}
