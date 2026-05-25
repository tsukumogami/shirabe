# Phase 3: Structural Fill

Replace the Phase 2 stubs with the structural sections: User Journeys and Scope
Boundary. Add any optional sections (Open Questions, Downstream Artifacts,
References) the brief warrants. Phase 3 is where the feature's concrete shape
becomes legible to the downstream PRD author.

## Goal

Complete the BRIEF draft so it passes the format reference's required-sections
check with real content (not placeholders). By the end of Phase 3 the draft should
be jury-ready: every required section has prose, the User Journeys are concrete and
distinct, and the Scope Boundary draws a real line through what the feature touches.

## Resume Check

If `docs/briefs/BRIEF-<topic>.md` exists with `status: Draft` and the User Journeys
section contains real content (not the Phase 2 placeholder), Phase 3 already ran in
part. Re-read it and continue from the first still-stubbed section.

## 3.1 Load Inputs

Read all available context:

- The current draft at `docs/briefs/BRIEF-<topic>.md`
- `wip/brief_<topic>_discover.md` (the journey sketch lives here)
- `skills/brief/references/brief-format.md` (especially the per-section quality
  guidance for User Journeys and Scope Boundary)

## 3.2 Draft User Journeys

User Journeys name the concrete paths through the feature. Each journey is a
`###` subsection that names a user, a trigger, and the outcome shape. The journeys
must be distinct from one another — different users, different entry points, or
different outcomes, not the same path retold.

**Required content properties:**

- Each journey has a `###` heading naming the journey (e.g.
  `### Journey 1: Standalone author, cold invocation`).
- Each journey names three things concretely:
  - **The user** — who they are (a named role, not "the user" generically).
  - **The trigger** — what brings them to the feature, the situation they're in.
  - **The outcome shape** — what they get, walked through as an experience.
- The journeys are distinct. Two journeys that differ only in wording are one
  journey written twice. Distinctness usually comes from different entry points
  (cold invocation vs. tracing an upstream), different users (author vs. reviewer),
  or different outcomes (a produced artifact vs. a hand-off).
- A short closing line per journey naming what the journey validates is useful but
  not required.

**Count guidance:** 2-5 journeys is typical. One journey suggests the feature is a
single path and the section is thin; more than 6 suggests the feature spans more
than one framable thing.

**Common failure modes:**

- Every journey is the same user doing the same thing with cosmetic variation. The
  content-quality reviewer flags non-distinct journeys.
- A journey names a trigger and a user but trails off without an outcome shape —
  the reader can't tell what the user got.
- Journeys describe the implementation ("the skill loads phase-4-validate.md")
  rather than the user's experience ("the jury runs and returns verdicts").

## 3.3 Draft Scope Boundary

Scope Boundary records what the feature holds in and what it deliberately pushes
out. Both halves are required — an in-list without a real out-list is not a
boundary.

**Required content properties:**

- An explicit **in-scope** list: what this feature covers. Each item is concrete
  enough that the downstream PRD author knows it's theirs to specify.
- An explicit **out-of-scope** list with *real* exclusions: things a reader might
  reasonably expect this feature to cover but that it deliberately doesn't. Each
  out item names what it is and, briefly, why it's out (a later feature owns it,
  it's a separate concern, it's an adjacent feature's job).
- The out-list must contain genuine exclusions, not strawmen. "Out of scope:
  solving world hunger" is filler; "out of scope: the parent-skill integration
  that delegates to this feature as a child phase — that's separate downstream
  work" is a real boundary.

**What not to include:**

- "Out of scope for this PR" or PR-level exclusions. BRIEF Scope Boundary is
  durable; it outlives any single PR.
- Requirements smuggled in as scope items. "In scope: the command must validate
  input" is a requirement; "in scope: input validation behavior" is a scope item.
  The PRD owns the requirement.

**Common failure mode:** an out-of-scope list full of things no one would expect
the feature to do. The content-quality reviewer checks that the OUT items are real
exclusions a reader might otherwise assume are in.

## 3.4 Add Optional Sections

The format reference defines three optional sections. Add the ones the brief
warrants:

- **Open Questions.** Draft-status only — the section must be empty or removed
  before Draft -> Accepted (the format reference enforces this; Phase 5 clears it).
  Each open question is a framing question this brief deliberately leaves for the
  downstream PRD to resolve. The questions must genuinely defer to the PRD, not
  hide blockers that should stop the brief from being accepted. End the section
  with a line stating none of the questions block the brief.

- **Downstream Artifacts.** A typed link list of the documents that pick up this
  brief (the PRD, the design), with a one-sentence purpose per entry. Add entries
  as downstream work starts; an empty Downstream Artifacts section adds nothing, so
  omit it until there's something to list.

- **References.** In-repo precedents the brief draws on — the prior brief it
  follows, the skill structure it mirrors, the format reference it conforms to.

**Durability rule for links:** every link in Downstream Artifacts and References
MUST point to a durable path. Specifically:

- No `wip/...` paths. wip/ artifacts are non-durable per the workspace's
  wip-hygiene rule; references to wip/ paths become dangling pointers the moment
  the cleanup phase runs.
- No private-repo paths from a public-visibility BRIEF. Cross-repo references use
  the `owner/repo:path` convention.
- Paths to artifacts that don't exist yet are acceptable if the artifact is planned
  (forthcoming work). Annotate them as "(planned)" in the description.

Phase 4's structural-format reviewer checks durability per link.

## 3.5 Re-read the Full Draft

After the structural sections are filled, re-read the full draft as a whole. Check
that:

- The User Journeys exercise the problem named in the Problem Statement. A journey
  that has nothing to do with the stated problem is either a sign the problem is
  framed too narrowly or the journey doesn't belong.
- The Scope Boundary's in-list covers the feature the journeys describe, and the
  out-list excludes the adjacent things the journeys brush against.
- The outcome in User Outcome is reachable through at least one journey.

Apply edits inline. If a structural inconsistency surfaces a deeper issue with the
problem/outcome pair, loop back to Phase 2 to revise the foundational sections
before continuing.

## 3.6 Present and Iterate

Tell the user the structural sections are complete:

> The BRIEF draft is fully written at `docs/briefs/BRIEF-<topic>.md`. Phase 4 (jury
> review) is next. Skim it now and flag any structural concerns before the jury
> runs.

Surface thematic questions about the structural choices:

- Journey distinctness (do any two journeys collapse into one?)
- Journey count (one journey, or more than the feature warrants?)
- Scope out-list (are the exclusions real, or strawmen?)
- Optional sections (does Open Questions hide a blocker? Are Downstream Artifacts
  links durable?)

For minor edits, apply directly. For major restructuring, loop back to Phase 2 (if
the problem/outcome pair needs revision) or stay in Phase 3 (if the journeys or
boundary just need adjustment).

## 3.7 Commit

Commit the structural fill:

```
docs(brief): fill BRIEF structural sections for <topic>
```

Update `wip/brief_<topic>_context.md`'s `## Phase` line to `3`.

## Quality Checklist

Before proceeding:
- [ ] User Journeys has 2-5 entries, each with a `###` heading
- [ ] Each journey names a user, a trigger, and an outcome shape
- [ ] The journeys are distinct from one another
- [ ] Scope Boundary has an explicit in-list AND an out-list with real exclusions
- [ ] Optional sections (if present) follow the durability rule for links
- [ ] Open Questions (if present) genuinely defer to the downstream PRD
- [ ] No Phase 2 placeholder text remains in any required section

## Artifact State

After this phase:
- Complete BRIEF draft at `docs/briefs/BRIEF-<topic>.md` with `status: Draft`
- All five required sections filled with real content
- Ready for Phase 4 jury review

## Next Phase

Proceed to Phase 4: Validate (`phase-4-validate.md`)
