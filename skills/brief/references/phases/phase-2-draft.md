# Phase 2: Draft

Author the two prose-driven sections that carry the framing: Problem Statement and
User Outcome. Phase 3 owns the structural sections (User Journeys, Scope Boundary,
and any optional sections); Phase 2 owns the prose that makes the feature legible.

## Goal

Produce a partial BRIEF draft with:

- A Problem Statement that names the user problem the feature solves — a problem,
  not a solution in disguise.
- A User Outcome that describes what a user should experience once the feature
  exists — outcome-shaped, not a feature list.

Frontmatter and the Status section are written at Phase 2 in their Draft shape.
User Journeys and Scope Boundary are placeholder-stubbed; Phase 3 fills them.

## Resume Check

If `docs/briefs/BRIEF-<topic>.md` exists with `status: Draft`, Phase 2 or later has
already produced a draft. Re-read it, identify which sections are complete, and
continue from the first incomplete section.

If the file does not exist, proceed to step 2.1.

## 2.1 Load Inputs

Read all available context:

- `wip/brief_<topic>_context.md` (Phase 0)
- `wip/brief_<topic>_discover.md` (Phase 1)
- The upstream document (ROADMAP or PRD) if Phase 0 recorded one
- `skills/brief/references/brief-format.md` (format specification — load this in
  full at Phase 2 since the section-by-section guidance lives there)

Detect repo visibility from `wip/brief_<topic>_context.md`. Load the appropriate
content governance skill:

- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

## 2.2 Private-Upstream Sanitization Warning

When Phase 0 recorded an upstream path inside a private repo AND the current repo's
visibility is Public, surface a warning to the user before drafting:

> The upstream `<path>` lives in a private repo. Quoting verbatim from a private
> upstream into a public-visibility BRIEF would leak private framing into a public
> artifact. Phase 2 will paraphrase rather than quote when carrying content
> forward; please review the Problem Statement and User Outcome when the draft is
> ready to confirm no private wording slipped through.

This is a defense-in-depth warning. The Phase 4 structural-format reviewer also
flags likely-private content, but the author's eye at Phase 2 is the cheapest place
to catch the issue.

For Public-to-Public and Private-to-Private flows the warning is unnecessary and
should not appear.

## 2.3 Write Frontmatter and Status

Create `docs/briefs/BRIEF-<topic>.md` with frontmatter:

```yaml
---
schema: brief/v1
status: Draft
problem: |
  <2-4 line summary of the user problem the feature solves; same content the
  Problem Statement section elaborates in prose>
outcome: |
  <2-4 line summary of the outcome a user should experience; same content the
  User Outcome section elaborates in prose>
upstream: <path to upstream ROADMAP or PRD, omit field if none or if private>
---
```

The `problem` and `outcome` fields are paragraph-length YAML literal blocks (`|`).
They carry the same content the Problem Statement and User Outcome sections
elaborate in prose; the two stay in sync (the Phase 4 structural-format reviewer
checks consistency).

Omit the `upstream` field entirely when the upstream is a private artifact a public
brief cannot name. Cross-repo references use the `owner/repo:path` convention
defined in `references/cross-repo-references.md`.

Write the body Status section as:

```markdown
## Status

Draft
```

The bare status word goes alone on its own line. `shirabe validate` (FC03) compares
the first non-blank line under `## Status` to the frontmatter `status`; any prose
on the status line breaks the check. Explanatory prose, if any, goes after a blank
line — but at Draft stage the bare word alone is enough.

## 2.4 Draft Problem Statement

The Problem Statement names the user problem the feature solves. It must read as a
problem, not as a solution in disguise.

**Required content properties:**

- Names something a user struggles with, lacks, or can't do today. The reader
  should be able to picture the user hitting the problem before any solution
  exists.
- Stands alone: a reader who has never seen the upstream still understands what
  problem this feature addresses after reading the section.
- States the problem before any mechanism. If the feature is the only natural way
  to describe the problem, name the user's situation and the friction, not the
  feature's parts.

**What not to include:**

- A solution wearing a problem's clothes. "Users can't export to CSV" describes a
  missing feature; "users have no way to get their data out of the tool for use
  elsewhere" describes a problem. The content-quality reviewer rejects the former.
- Requirements. The downstream PRD owns user stories and acceptance criteria; the
  brief frames why the feature matters, not what it must do.
- Verbatim copies of upstream prose, especially across visibility boundaries.

**Length guidance:** 2-5 short paragraphs. A brief frames one feature; the Problem
Statement is a framing, not a research report.

## 2.5 Draft User Outcome

The User Outcome describes what a user should experience once the feature exists.
It must read as an outcome, not a feature list.

**Required content properties:**

- Describes the user's experience: what they can now do, what friction is gone,
  what they no longer have to think about. Walk a reader through the changed
  experience.
- Ties back to the Problem Statement: the outcome is the problem resolved, seen
  from the user's side.
- Matches (paraphrased) the frontmatter `outcome:` field. The Phase 4
  structural-format reviewer checks consistency.

**What not to include:**

- A feature list. "The skill adds a `/brief` command, a format reference, and a
  jury" describes the product's parts; "an author reaches for `/brief` the way they
  reach for `/prd` today" describes the experience. The content-quality reviewer
  rejects the former.
- Acceptance criteria or measurable targets. Those are PRD-altitude content.

**Length guidance:** 2-5 short paragraphs.

## 2.6 Stub Remaining Sections

To pass the format reference's required-sections check, the file needs all five
required sections present. Phase 3 fills the structural sections; Phase 2 stubs
them with placeholder content:

```markdown
## User Journeys

<Phase 3 will name the concrete journeys that exercise the feature.>

## Scope Boundary

<Phase 3 will record what this feature holds in and pushes out.>
```

The stubs satisfy the structural validator but make obvious to a reader that Phase
3 has not yet run. Phase 4's structural-format reviewer will reject the draft if it
sees these placeholders unfilled.

## 2.7 Present the Partial Draft

Tell the user the partial draft is ready:

> The BRIEF partial draft is at `docs/briefs/BRIEF-<topic>.md`. Problem Statement
> and User Outcome are written; Phase 3 will fill the structural sections (User
> Journeys, Scope Boundary, and any optional sections) next.

Surface thematic questions the user should weigh in on. Use AskUserQuestion for
questions that have a tradeoff shape. Avoid rehashing the draft ("does the problem
look right?") — the user can read the draft themselves.

Good questions target the framing:
- "The Problem Statement frames this as a discoverability problem. Is the real
  problem that the feature is hard to find, or that users don't know it exists at
  all? The framing changes which journeys matter."
- "The outcome assumes the user already knows what they want to frame. Should the
  brief also cover the user who's unsure whether a brief is even the right tool?"

Bad questions:
- "Is the Problem Statement accurate?"
- "Does the outcome capture your intent?"

## 2.8 Incorporate Feedback

After the user responds:

- **Minor changes** (wording, sharpening a problem framing): Apply directly and
  confirm what changed.
- **Significant changes** (re-framing the problem, swapping the outcome's center of
  gravity): Apply, summarize what was updated, and ask if the changes landed.

Loop back to Phase 1 only if the problem/outcome pair itself needs to change. Phase
2 feedback loops within Phase 2 by default.

## 2.9 Commit

Commit the partial draft:

```
docs(brief): draft BRIEF for <topic>
```

Update `wip/brief_<topic>_context.md`'s `## Phase` line to `2`.

## Quality Checklist

Before proceeding:
- [ ] Frontmatter `schema`, `status`, `problem`, `outcome` fields are present
- [ ] Body `## Status` section opens with the bare status word on its own line
- [ ] Problem Statement names a user problem, not a smuggled solution
- [ ] User Outcome is outcome-shaped, not a feature list, and ties back to the problem
- [ ] Stubbed sections are present (so the file passes structural checks)
- [ ] Private-upstream sanitization warning surfaced if the visibility cross is Private-to-Public

## Artifact State

After this phase:
- Partial BRIEF draft at `docs/briefs/BRIEF-<topic>.md` with `status: Draft`
- Context and discovery files still in `wip/`
- Phase 3 will extend the same file

## Next Phase

Proceed to Phase 3: Structural Fill (`phase-3-structural-fill.md`)
