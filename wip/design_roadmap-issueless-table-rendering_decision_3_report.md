# Decision 3 — does issue-creating mode adopt the fallback rule?

## Question

Issue-creating mode keys its rows on `strip_label_decoration(&f.label)` and
resolves dependencies to the same text. It therefore carries exactly the
exposures R2 exists to close: a comma in a label splits the Dependencies cell
into tokens that name no row, a pipe breaks the markdown row, and two features
sharing a label make dependency references ambiguous. R24 freezes that mode's key
column and Dependencies-cell resolution.

## Options

### O1 — Extend the fallback to both modes

Tempting on the merits: the bug is identical and the fix is already written. It
would change issue-creating output only for labels that are empty, duplicated, or
delimiter-bearing — never for a well-formed roadmap.

Rejected, on scope rather than on merit. The PRD is Accepted with R24 stating the
opposite, and the brief's Scope Boundary puts issue-creating mode's rendering out
except where a shared code path forces the change. Decision 1's key-table
parameter means nothing forces it: the shared function takes whichever key table
its caller builds. Changing an accepted requirement because the fix looked cheap
is how a bugfix turns into an unreviewed behaviour change in a second mode.

### O2 — Issueless only, with the seam left open (chosen)

`render_table` builds its key table from `strip_label_decoration` and gets
byte-identical output to today. `render_issueless_table` builds its key table
from `feature_keys`. Extending the rule to issue-creating mode later is a
one-line change at one call site.

Chosen. It honours R24 exactly, keeps the diff scoped to the mode the report is
about, and leaves the extension a single edit away rather than a refactor.

### O3 — Issueless only, with no shared seam

Duplicate the dependency renderer for issueless mode so the two modes share
nothing.

Rejected. It buys the same scope discipline as O2 at the price of a second copy
of the `Feature N` resolution, the cross-repo passthrough, and the `None`
fallback — three behaviours the PRD constrains identically in both modes
(R6, R7, R8).

## Consequence for the implementation

The Consequences section of the design records that issue-creating mode keeps the
comma, pipe, duplicate-label, and empty-label exposures, that this is deliberate
under R24, and where the one-line extension goes.
