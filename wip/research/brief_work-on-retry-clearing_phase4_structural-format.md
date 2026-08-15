# Phase 4 Jury -- Structural/Format Review

Target: `docs/briefs/BRIEF-work-on-retry-clearing.md`
Rubric: `skills/brief/references/brief-format.md` (Frontmatter, Required Sections,
Section Matrix, Validation Rules)

## Validator output

Built the release binary (`cargo build --release --bin shirabe`, none was
present in this worktree) and ran:

```
./target/release/shirabe validate docs/briefs/BRIEF-work-on-retry-clearing.md --format json --visibility=Public
```

```json
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```

Zero errors, zero notices. Clean.

## Manual rubric walk

**FC01 (required frontmatter fields).** `schema: brief/v1`, `status: Draft`,
`problem: |...`, `outcome: |...` all present. Pass.

**FC02 (valid status).** `status: Draft` -- a valid value. Pass.

**FC03 (frontmatter/body Status match).** Body `## Status` section:

```
## Status

Draft

The framing stops at the contract a retry owes the next round. ...
```

First non-blank line is the bare word `Draft`, alone, followed by a blank line
before the explanatory prose. Matches frontmatter `status: Draft` exactly.
Pass.

**FC04/FC15 (required sections, canonical order).** Body carries, in order:
Status, Problem Statement, User Outcome, User Journeys, Scope Boundary,
References. All five required sections present and correctly ordered (the
trailing References section is optional and correctly placed after the
required set). Pass.

**upstream: absence.** No `upstream:` key in frontmatter. The rubric permits
this when the brief is authored from a freeform topic (not derived from a
ROADMAP feature with a known strategic ancestor). Nothing in the brief's body
references a roadmap or strategy it was sequenced from -- the Problem
Statement and Scope Boundary both stand alone and derive their framing from
the `/work-on` skill's own defect, not from an upstream strategic artifact.
Treating this as a legitimate freeform-topic brief; no violation.

**Public-visibility cleanliness.** Grepped the file for `private/` paths,
private repo names (`tsukumogami/vision`, `tsukumogami/coding-tools`,
`tsukumogami/tools`, `tsukumogami/dot-niwa-overlay`), and any `#NNN` issue
references -- all zero hits. The document names only public-repo paths
(`skills/work-on/...`, `skills/execute/...`, `docs/designs/...`) and generic
technical terms (`koto`, `scrutiny`, `review`, `qa_validation`). Clean.

**Downstream Artifacts.** Section not present. Nothing to check (optional,
absence is fine at Draft).

**References section paths.** Two entries, both verified to exist on disk in
this worktree:

- `docs/designs/current/DESIGN-settled-branch-record.md` -- exists (20822
  bytes).
- `skills/execute/scripts/settled-branch-record_test.sh` -- exists (14034
  bytes, executable).

Both are durable repo-relative paths, neither under `wip/`. Pass.

Also spot-checked the Scope Boundary's in-scope file list (paths the brief
says the retry-clearing prose/state machine lives in), since a brief that
names nonexistent files would be a legitimate structural red flag even though
not explicitly a References entry:

- `skills/work-on/references/phases/phase-4a-scrutiny.md` -- exists
- `skills/work-on/references/phases/phase-4b-review.md` -- exists
- `skills/work-on/references/phases/phase-4c-qa.md` -- exists
- `skills/work-on/koto-templates/work-on.md` -- exists

All resolve.

**Writing style.** Repo terms of art (`tier`, `journey`, `underscore`) are not
flagged per instructions -- and in fact "Journeys" only appears as the
required section name here, no stray "tier" usage. The document's prose style
is unusually dense and aphoristic throughout (this is consistent across
Problem Statement, User Outcome, and Journeys, so it reads as a deliberate
authorial voice rather than AI-tell filler) -- no hedging, no "It's worth
noting," no bullet-table overuse. No writing-style violations found at the
structural level.

One genuine defect: the frontmatter `problem:` block's second sentence is
missing a word and does not parse:

> "The one step that would names a koto subcommand that does not exist, and
> the gate it is meant to trip tests presence rather than freshness..."

"would names" is ungrammatical -- reads like a dropped verb after "would"
(likely "would clear it names a koto subcommand..." or similar was cut
during editing). The body's Problem Statement says the same thing clearly
("`scrutiny`'s retry loop tells the agent to delete the stale artifact with
`koto context remove`"), so the meaning is recoverable from context, but the
frontmatter summary itself is broken on a close read. This isn't one of the
four FC checks (FC01 only checks presence, not grammaticality) and the
validator naturally doesn't catch it, so it's advisory rather than blocking
-- but it should be fixed before Accepted since a reader skimming just the
frontmatter hits a garden-path sentence.

Also advisory: the `problem:` block runs 5 content lines; the format
reference's guidance is "2-4 line summary." Not a validator-enforced rule
(not in the FC01-04/FC15 list), just a documented convention the block
slightly exceeds. `outcome:` is within range at 4 lines.

## Verdict

PASS. All four automated checks (FC01-04) plus FC15 pass, both via the
validator and manual re-verification. No `upstream:` violation, no
public-visibility leaks, all cited paths (References section and Scope
Boundary's in-scope file list) resolve on disk. The two issues found are
advisory-only: a dropped word in the frontmatter `problem:` block's second
sentence, and that block running one line past the documented 2-4 line
guidance.
