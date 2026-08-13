# PRD Decisions: vale-adoption

Decisions taken while drafting, in `--auto` mode. Each records what was
decided, what the alternatives were, and why. The four questions inherited
from the BRIEF close here and in the PRD's Decisions and Trade-offs section.

## Orchestrator findings recorded during Phase 2

These were verified directly rather than delegated, because they bear on the
DESIGN's mechanism choice and would be easy to lose.

**`regex` is already a direct dependency and is already imported.**
`crates/shirabe-validate/Cargo.toml:9` declares `regex = "1"`, and
`crates/shirabe-validate/src/checks.rs:15` carries `use regex::Regex;`. FC10
itself does not use it: `check_writing_style` hand-rolls ASCII byte-boundary
matching with a comment describing the approach as "regex-free". So widening
FC10 into pattern rules costs no new dependency, and the current
implementation's narrowness is not explained by a missing one.

**shirabe has an explicit no-new-dependency value for validator checks.**
`crates/shirabe-validate/src/checks.rs` carries a test named
`check_fc08_introduces_no_new_dependency`, which asserts that FC08 "uses only
`std::collections::HashSet`, `regex` (already in workspace deps), and the
existing mermaid extractor infrastructure. No new external crate is imported
in checks.rs for FC08." A test exists whose entire purpose is to pin that a
check added no dependency.

This is precedent, not a rule the PRD can cite as binding, and it applies to
checks compiled into the validator rather than to tools the validator might
invoke. But it is a recorded expression of how this repo weighs new
dependencies in its checking path, and any DESIGN proposing an external
binary on every adopter's CI runner has to argue against it rather than
around it. Recorded here so the DESIGN inherits it as a constraint to
address.
