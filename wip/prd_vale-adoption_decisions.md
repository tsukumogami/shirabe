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

**A directory argument silently validates nothing.** Found while trying to
reproduce the research's claim of five pre-existing R6 errors. `shirabe
validate -- docs` returns "All checks passed" at exit 0 with an empty
`findings` array; the same corpus passed as an explicit file list returns 5
errors and 139 notices (97 FC10, 33 SCHEMA skips, 7 FC08, 5 R6, 1 FC09, 1
FC15). The mechanism is the same prefix gate R3 addresses: `main.rs:604`
resolves each argument through `detect_format(basename(path))` and `continue`s
on `None`, and there is no directory walk, so a directory name matches no
artifact prefix and is skipped like any other non-matching file.

Three consequences now trace to one root cause: instruction files are skipped,
`check_claude_md_conventions` is unreachable, and a directory argument reports
clean having read nothing. Recorded in the PRD's Known Limitations rather than
as a requirement, because requiring a directory walk is a separate change and
the PRD should not grow scope to absorb every symptom of a defect it already
addresses at the root.

Worth noting for the DESIGN: the first attempt to verify the corpus claim
produced a false negative, and the false negative was itself an instance of
the defect under investigation. A checking surface that reports success
without having run is the failure mode this whole feature is about.
