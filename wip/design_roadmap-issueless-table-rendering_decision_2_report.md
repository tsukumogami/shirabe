# Decision 2 — how the diagnostics are produced

## Question

R16 and R17 require stderr lines naming features whose description was truncated
or whose key fell back. The renderers are `pub fn ... -> String`, pure, and
covered by unit tests that call them directly. Where does the IO happen?

## Options

### O1 — `eprintln!` inside the renderers

Rejected. It makes the renderers impure, so every unit test that calls
`render_issueless_table` starts writing to the test harness's stderr, and the
diagnostics themselves become testable only through the CLI. It also puts the IO
inside a function whose whole contract is "return the section body".

### O2 — Renderers return `(String, Vec<String>)`

Rejected. It changes two public signatures that eight existing unit tests call,
for no gain over O3: the warnings are derivable from `&[Feature]` alone and do
not need anything the renderer computes along the way. The churn would land in
tests that have nothing to do with this change, which makes the diff harder to
review for the thing it is actually doing.

### O3 — A separate pure `render_warnings(features) -> Vec<String>` (chosen)

Chosen. The run paths (`run_issueless`, and `run_inner` for the shared
description ceiling) call it and print each line to stderr. The function is pure,
directly unit-testable for content and ordering, and leaves both renderers' 
signatures and their existing tests untouched.

R18's ordering requirement falls out of iterating `features` in order. R18's
`--dry-run` clause is satisfied without a branch, because the warnings do not
depend on the mapping and the issueless path ignores `--dry-run` anyway.

The cost is that the derivation runs twice: once inside the renderer to produce
the cell, once inside `render_warnings` to decide whether it was truncated. For a
feature list this size that is not worth avoiding, and the alternative
(threading state out of the renderer) is O2.

## Consequence for the implementation

`summarize_description(desc) -> (String, bool)` is the single derivation;
`concise_description` becomes its `.0` for the renderers, and `render_warnings`
reads its `.1`. The same function backs both modes, satisfying R15.
