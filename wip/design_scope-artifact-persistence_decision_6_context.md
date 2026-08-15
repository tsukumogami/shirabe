# Decision Context: How is the pre-deletion citation guard implemented, and where does it live?

## Question

R15 requires that before deleting an artifact, the absorb procedure searches the
repository's git-tracked files (excluding `wip/`) for citations of it. Where does
that search run (skill prose, shell script, or `shirabe` binary mode), what
exactly does it search and how, what does R18 cover that R15 has not already
excluded, and where does R16's `R<n>` citation-resolution rule live?

## Complexity

standard (Tier 3, fast path: phases 0, 1, 2, 6)

## Constraints

- Two tiers of outcome only: path-exact hit downgrades `absorb` to `keep`
  through the existing abort path; bare-name hit is a finding surfaced to the
  judging agent and does not by itself change the verdict.
- No override. No outcome stronger than `keep` (R15, R27, R30).
- Reuse the existing abort path verbatim (`phase-2-chain-orchestration.md`
  Stage 3, "Any `carried: false` aborts the absorb"). No new severity, no new
  error code.
- No retroactive commitment: the guard produces no verdict about any document
  already on disk (R15, R29).
- Same-repo only. Cross-repo citations, issue bodies, PR descriptions and commit
  messages are out of reach (stated Known Limitation).
- Fixtures and vendor directories must not produce false positives that block
  real folds.
- The choice determines which PRD criterion tags ([mech]/[judg]/[insp]) R15's
  criteria can honestly carry.

## Known Options

1. Skill prose instructing the judging agent to run a search.
2. A shell script invoked by the skill's Stage 3.
3. A new mode/subcommand of the `shirabe` Rust binary.
4. Hybrid: mechanical search shipped as a script or binary mode, agent
   interprets the bare-name tier.

## Background

- Absorb procedure: `skills/scope/references/phases/phase-2-chain-orchestration.md`
  Stage 3 — read absorbed `upstream:`, re-point survivor, `git rm`, re-validate
  survivor, revert on non-zero. The `git rm` is unconditional today.
- `lifecycle::build_referrer_map` (`crates/shirabe-validate/src/lifecycle.rs`) is
  the finalization walk's retirement guard from PR #271. It indexes only
  `upstream:` frontmatter edges, so it is blind to prose, skill, code, CI and
  script citations — the classes that have actually broken. The exploration's
  claim that wiring it is "the single change that turns the reduction back into a
  move" is false and was corrected in D4.
- Prose citation surface is far wider than frontmatter: ~35 files cite a
  `docs/designs/current/DESIGN-*.md` path, ~73 cite a `docs/prds/PRD-*.md` path,
  and nothing validates them.
- CI (`.github/workflows/validate-docs.yml`) computes its file set with
  `git diff`, so a document stranded by a deletion is never a changed file and R6
  can never fire on it. Fold time is the only catchable point.
- Five documents in this repo carry dangling `upstream:` refs today; `shirabe
  validate` exits 2 on them and diff-scoped CI does not catch it.
