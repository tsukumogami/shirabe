# pick-slice.jq -- pick_slice, the pick decider's slice of coord/pick.json.
#
# pick-facts.sh writes coord/pick.json, the facts the agent reads at pick, and
# then this slice of the same JSON to coord/pick_slice.json, the input pick's
# decider reads under its 12,000-byte cap. The slice is built from nothing but
# the facts pick-facts.sh wrote on that visit. The full facts give every unit a
# full row whatever its state, and a long-running record is mostly finished
# units whose rows are null and false; the slice drops what the choice can't
# use (references/jev-criteria.md, coordinate/pick-choice).
#
#   done       the tags of the done units, in the facts' order: a unit whose
#              done is true, with no holding covering it, verdict_owed false
#              and rework unset. Pick's rules never act on one, and a
#              dependent's blocked and blocker_landed already carry what it
#              needs from it.
#   units      every other unit, in the facts' order, its fields that are null,
#              false or an empty list left out. blocked_by names its blockers
#              by tag rather than by position, since the positions count the
#              full list, done units included. pick-facts.sh only writes
#              positions inside that list; one outside it (never written)
#              is left as its number rather than dropped.
#   holdings   every holding, with the same fields left out.
#   scope, name, host, cap, active, parked, parked_bound, paused_all, pauses,
#   go_aheads, decisions
#              as the facts carry them; a key the facts lack stays absent. A
#              key added to the facts reaches the decider only once it is
#              named here; pick-facts_test.sh pins the slice's key set.
#
# The facts have no done list of their own, so a slice's done list is carried
# through when it is sliced again: pick_slice of a slice is that slice, which
# is how pick-facts_test.sh holds the decider's fixtures to this shape.
#
# Usage: jq -c -L <scripts dir> 'include "pick-slice"; pick_slice' <pick.json>

# A row without its null, false and empty-list fields.
def pick_slice_compact: with_entries(select(.value != null and .value != false and .value != []));

# Whether the pick slice collapses a unit to its tag.
def pick_slice_done: .done == true and .holding == null and .verdict_owed != true and .rework == null;

def pick_slice:
    (.units // []) as $u
    | with_entries(select(.key | IN("scope", "name", "host", "cap", "active", "parked", "parked_bound",
                                    "paused_all", "pauses", "go_aheads", "decisions")))
    + {done: ((.done // []) + [$u[] | select(pick_slice_done) | .unit]),
       units: [$u[] | select(pick_slice_done | not)
               | if (.blocked_by | type) == "array"
                 then .blocked_by |= map(if type == "number" and . >= 1 then ($u[. - 1].unit // .) else . end) else . end
               | pick_slice_compact],
       holdings: [(.holdings // [])[] | pick_slice_compact]};
