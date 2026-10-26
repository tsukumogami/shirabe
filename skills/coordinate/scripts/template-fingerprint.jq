# template-fingerprint.jq -- the structure of a compiled koto template that a
# run's behaviour depends on: the initial state, the variables and every
# state's accepts, gates, actions and transitions. Every description,
# directive and details text is left out, and so is a variable's `rebind`
# flag, since none of them changes what a run does.
#
# Run with `jq -S -c -f template-fingerprint.jq <compiled.json>` and hash the
# output: coord-log.sh compares a run's compiled template with the compat
# table this way (coordinate.compat.json), and scripts/check-template-compat.sh
# keeps the table's fingerprints honest with the same program.
#
# Only a text value is left out: an evidence field or a decider answer that
# happens to be named description, directive or details holds an object, and
# stays in the structure.
def strip: walk(if type == "object"
    then with_entries(select((.key == "description" or .key == "directive" or .key == "details") and (.value | type == "string") | not))
    else . end);
{initial_state,
 variables: (.variables | strip | map_values(del(.rebind))),
 states: (.states | strip)}
