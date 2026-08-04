#!/usr/bin/env bash
# Shared reader for the gate commands in a koto template.
#
# Sourced by scripts/validate-template-mermaid.sh (which compares gate commands
# across templates) and scripts/ci-gate-expression_test.sh (which executes one).
# It lives here because both need to know koto's gate layout, and two copies of
# that knowledge is the thing the drift check exists to prevent.
#
# koto's layout inside a template's YAML frontmatter:
#
#   states:
#     <state>:            2 spaces
#       gates:            4 spaces
#         <gate-name>:    6 spaces
#           command: ...  8 spaces
#
# Only the single-line `command: "..."` form can be read. A YAML block scalar
# (`command: >` or `command: |`) puts the body on following lines, and reporting
# an empty body as if it were the command would let two different commands look
# identical. Callers are told so explicitly rather than handed a blank.

# koto_gate_rows <template>
#
# Prints one tab-separated row per gate that declares a command:
#
#   COMMAND<TAB><gate-name><TAB><raw-yaml-scalar>
#   UNREADABLE<TAB><gate-name><TAB>
#
# The scalar is printed as it appears in the file, still quoted and escaped.
koto_gate_rows() {
    local template="$1"
    awk '
        /^    gates:[[:space:]]*$/ { in_gates = 1; gate = ""; next }
        in_gates && /^      [a-z_][a-z_0-9]*:[[:space:]]*$/ {
            gate = $0
            sub(/:.*/, "", gate)
            sub(/^[[:space:]]+/, "", gate)
            next
        }
        in_gates && gate != "" && /^        command:/ {
            cmd = $0
            sub(/^        command:[[:space:]]*/, "", cmd)
            if (cmd ~ /^[|>][0-9+-]*[[:space:]]*$/ || cmd == "") {
                print "UNREADABLE\t" gate "\t"
            } else {
                print "COMMAND\t" gate "\t" cmd
            }
            next
        }
        /^  [a-z_]/ { in_gates = 0 }
    ' "$template"
}

# koto_gate_command <template> <gate-name>
#
# Prints the raw YAML scalar for one named gate, or nothing when the gate is
# absent or unreadable.
koto_gate_command() {
    local template="$1" gate="$2"
    koto_gate_rows "$template" \
        | awk -F'\t' -v g="$gate" '$1 == "COMMAND" && $2 == g { print $3; exit }'
}

# koto_unquote_scalar <raw-scalar>
#
# Turns the double-quoted YAML scalar into the string the shell would receive.
# Handles the `\"` escape, which is the only one these templates use.
koto_unquote_scalar() {
    local raw="$1"
    raw="${raw#\"}"
    raw="${raw%\"}"
    printf '%s' "${raw//\\\"/\"}"
}
