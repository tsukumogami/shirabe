# Design Decisions: chain-cardinality

Execution mode: `--auto`, at the author's direction. Decisions are recorded here rather
than prompted; anything that would change the shape of the work is surfaced regardless.

## Inherited: the PRD's jury disposition

Recorded because the PRD was accepted on a partial jury and a future reader should know
that rather than infer a clean three-of-three.

- **Testability — independent PASS.** Two rounds. The reviewer built scratch corpora and
  ran the real binary: it reproduced the shared-BRIEF conflict, the filename lottery, the
  finalization walk retiring a shared parent, and the sequence-collapse on all three list
  shapes. It caught two defects reading alone would not have — a requirement that
  admitted an implementation transitioning nothing, and a requirement written against a
  suppression mechanism that measurement showed does not exist. It also swept for stale
  cross-references after the final edit and confirmed the working tree clean.
- **Completeness — one blocking finding, fixed; no re-verdict.** Its blocker was that the
  PRD claimed no strategic documents exist in this workspace, which was false and was the
  entire stated reason for declining to index the strategic directories. The fact was
  verified directly against the filesystem before the fix, not taken on trust. It had
  explicitly marked its eleven other findings resolved. The agent re-reviewing the
  corrected document never reported.
- **Clarity — findings addressed; no re-verdict.** Its round was against a draft that no
  longer exists. Its most valuable finding — that the ordering claim was unenforceable —
  was taken, then re-taken in the opposite direction when testability showed a release
  ordering cannot be an acceptance criterion at all. The constraint now lives in the plan.
- **Three reviewer agents died mid-round on an account-level session limit**, and two
  replacements went idle without reporting. The author accepted the PRD with this
  disposition disclosed rather than waiting on agents that were not returning.

What this means for the design: the requirement set has had one thorough independent
verification and one substantive correction, not three clean passes. Treat R1-R25 as
well-tested but not exhaustively reviewed, and let the design's own jury look for gaps in
the requirements as well as in the design.

## Decisions taken in this phase

### Decomposition into five questions

Five decision questions rather than more, following the instruction to err toward fewer
and broader and merge coupled ones. Parsing representation and resolution reporting were
merged because the representation choice determines the message shapes. The finalization
question merged consumer-awareness with the multi-branch walk because both require the
same document index in a module that has none. The parent question kept the pre-authoring
notice with the flag mechanism because the notice has to name the flag.

R21 and R22 are specification corrections with no design choice and were excluded from
the count rather than padding it to six, which would have tripped the warn-and-confirm
band for no reason. R23 and R24 bind every decision rather than forming one.

### Two briefs argue against the PRD

D3 and D4 were briefed to make a genuine case for options the PRD rejected implicitly.
D3 must argue for emitting the conflict finding alongside the per-chain findings instead
of superseding them; D4 must argue for putting the refusal in a gate that wraps the
finalization walk rather than inside the walker. An implicit rejection is how a strawman
gets written, and Phase 6 checks rejected alternatives for real depth.
