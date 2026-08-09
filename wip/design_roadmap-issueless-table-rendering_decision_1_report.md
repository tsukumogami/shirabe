# Decision 1 — where the key-resolution rule lives

## Question

R2 makes a feature's key conditional on properties of the whole roadmap (a label
is unusable if *another* feature shares it), and R5 requires Dependencies cells to
name exactly the key each row renders. `render_deps_cell` is shared with
issue-creating mode, whose Dependencies-cell resolution R24 freezes. Where does
the resolution live so that both columns agree without changing the other mode?

## Options

### O1 — Resolve at each call site

`render_issueless_table` computes the key for the row it is on;
`render_deps_cell` computes the key for each feature it resolves.

Rejected. The uniqueness clause makes resolution a function of the whole feature
list, so both call sites would have to build the same duplicate-label index, and
any divergence between the two copies produces a Dependencies cell naming a key
no row carries — an error-level FC06 failure that only shows up on roadmaps with
a duplicate or comma-bearing label. Two copies of a rule whose disagreement is
invisible in the common case is the worst shape available.

### O2 — Resolve once into a key table, thread it through (chosen)

A single `feature_keys(features) -> Vec<String>` returns the resolved key per
feature, positionally aligned with the slice. `render_issueless_table` indexes it
for the key column, and `render_deps_cell` gains a `keys: &[String]` parameter it
uses instead of computing labels itself.

Chosen. One rule, one place, and the agreement between the two columns is
structural rather than something two code paths have to keep converging on.
Threading a parameter also settles decision 3 for free: issue-creating mode calls
the same `render_deps_cell` with a key table built from `strip_label_decoration`
alone, which is exactly what it computes today, so its output is unchanged by
construction rather than by inspection.

The cost is one more parameter on an internal function and a `Vec<String>`
allocated per render. Both are negligible against a function that is called once
per populate run.

### O3 — Make the key a field on `Feature`

Resolve during `parse_features` and store the key on the struct.

Rejected. `Feature` lives in `shirabe-validate` and is consumed by the validator
as well as the renderer; the key form is a rendering concern of one mode of one
subcommand. Pushing it into the parsed model would put a populate-specific
decision in a type the validator shares, and the uniqueness rule would then apply
to every consumer whether it wanted it or not.

## Consequence for the implementation

`render_deps_cell(deps, features, keys)`; `feature_keys(features)` is the only
place R2's predicate is expressed; `render_table` passes the plain-label table
and `render_issueless_table` passes the resolved one.
