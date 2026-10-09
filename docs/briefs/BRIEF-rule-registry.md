---
schema: brief/v1
status: Accepted
problem: |
  shirabe's rules live in unconnected lists (the gates' rule table, the review trial's
  criteria, the prose itself), so nobody can say which rules exist, what checks each one,
  or which may ever leave an agent's default context, and a rule reaches an agent only by
  being loaded up front.
outcome: |
  A maintainer or measurement reader looks up any rule id a gate, script or trial record
  carries and finds one entry naming its text, its check, its fixtures, how strongly it is
  enforced, when it applies, and whether it may ever be withheld. A script can hand an agent
  a rule's text at the moment the rule applies, so later work can try withholding rules safely.
motivating_context: |
  The instruction-offload work wants to stop loading every rule into every run and to let
  cheap decider rounds stand in for expensive review panels one rule at a time. Both need a
  rule to be a thing with an id, a check and a known home. The output gates and the
  review-shadow trial each chose ids with a registry in mind and left the registry itself
  for later; the measurement baseline keys rules by line range until one exists.
---

# BRIEF: One home for every workflow rule

## Status

Accepted

## Problem Statement

shirabe enforces a growing number of rules, and each enforcement surface keeps its own
list. The output gates' scripts read `skills/work-on/scripts/gate-rules.tsv`, where 22 rules
carry names like `pr-body/no-ai-trailer` and a pinned source location. The review-shadow
trial reads `scripts/review-shadow/criteria.json`, where 17 criteria carry opaque ids like
`rs-002` and a bare file path as their reference. The offload measurement baseline keys a
rule by its line range at one commit. The rule's actual words live in skill prose,
references and templates, and none of these lists points at the others.

That leaves four gaps that the offload work runs into directly:

- **No inventory.** Nobody can answer "which rules does shirabe have, and which of them does
  anything check?" without reading three formats and the prose they point at. A rule with
  no check is invisible, and a check whose rule moved is invisible too.
- **References that rot.** A rule's location is stored as a line range pinned to a commit.
  The next edit above the rule moves it, and because pull requests are squash-merged, most
  of the commits the gate table pins aren't on `main` at all, so a reader can't open the
  text a finding points at.
- **No safety marking.** Later work wants to take some rules out of the default context and
  deliver them only when needed. Nothing records which rules must never leave, so the first
  attempt to withhold one has to guess, and a guess about the rule that guards a push or a
  merge is the expensive kind.
- **One delivery path.** Today a rule reaches an agent only by being loaded up front, so a
  rule taken out of the default context would simply be gone, even in the rare run where
  it's the rule that matters.

The people who feel this now are maintainers chasing a finding back to its rule, and the
offload work, which can't take its next step until rules can be named, checked and
delivered some other way.

## User Outcome

A maintainer who meets a rule id in a gate finding, a trial record or a review comment looks
it up in one place and finds the rule: a one-line statement of what broke, a pointer to the
full text that still resolves at the current commit, the check that enforces it (or a plain
statement that nothing does), the fixtures that exercise that check, how strongly it is
enforced, at which point in a workflow it applies, and whether it may ever be withheld from
an agent's default context.

A measurement reader joining gate events and trial records to the baseline gets one id per
rule that never changes, plus the baseline keys each entry replaces, so before-and-after
counts line up without hand matching.

An agent in a run where a rare rule suddenly applies sees that rule's text in the output of
the script that noticed, at the moment it matters, while the same text stays in its default
context for now. That gives later work a proven path to withhold rules without losing them.

## User Journeys

### A maintainer traces a gate finding to its rule

A shirabe maintainer reading a held `/work-on` run sees a finding with `rule_id:
branch/no-wip-files` and a `rule_ref`. They look the id up in the registry and land on the
entry: the short text the agent saw, the full-text pointer that opens the right lines at the
commit the run used, the gate script that reported it, the test that covers it, and a
never-withhold mark because the rule guards what a pull request publishes. They didn't have
to know which of three files held the rule.

### A measurement reader joins old records to new ones

Someone computing the preloaded rate after a template change has baseline records keyed by
line range at the pinned commit and new gate events keyed by `rule_id`. Each registry entry
lists the baseline key or keys it replaces, so the reader maps every old record to an id in
one pass, and a routing gate's koto fallback, whose name isn't a registered id, is set aside
as not a violation.

### An agent taking over a pull request gets the takeover rule when it applies

An agent running `/execute` re-enters a plan whose shared branch already carries another
run's pull request. The lookup script that finds the foreign marker prints the takeover rule's
text, taken from the registry's pointer, alongside its usual answer, so the agent reads the
"take over only on a positive signal" rule at the moment of the decision. The same text is
still in the template it loaded, so nothing is lost if the script's output is skimmed.

### A contributor adds a new rule

A contributor adding a gate check for a new rule writes its registry entry alongside it. They
can't leave out the decision about whether the rule may ever be withheld, so a rule that
guards a merge says so the day it lands, and they can't ship a gate that prints an id nobody
registered or a pointer that no longer finds its text.

## Scope Boundary

### In scope

- One registry holding every rule that shirabe's output gates, gate scripts and review-shadow
  criteria cite, at a location the design picks and justifies.
- Keeping every id already emitted: the 22 output-gate names and `rs-001` to `rs-017`
  resolve to entries unchanged, so existing gate events and trial records keep their meaning.
- The rule_id and rule_ref contract koto gate events carry, including how a rule_ref stays
  accurate after the rule's file is edited.
- A required, default-free field marking whether each rule may ever be withheld, with the
  rules that guard pull request creation, push, merge, closing issues, releases, deleting
  branches, outward publishing and record destruction marked never.
- CI checks that every printed rule_id resolves to an entry and every entry's full-text
  pointer resolves.
- The first deliver-on-trigger shape, using no new koto capability, shown on one real trigger.
- Each entry's link to the baseline keys it replaces.

### Out of scope

- Withholding any rule from default context. The demonstration copies a rule's text at the
  trigger and leaves the default prose where it is; taking it out is later work.
- Letting a decider pass skip or replace a review panel. The registry is where those criteria
  get one home; changing what a pass can do is separate work.
- Any koto change, including the routing-gate declaration koto's issue #306 asks for. The
  interim rule (a fallback whose id isn't registered isn't a violation) stays.
- Edits to the measurement harness or baseline files. The baseline keeps its keys; the
  registry carries the mapping.
- Registering every rule the prose states. This feature covers the rules something already
  cites; prose rules no check or criterion names join the registry as later work adopts them.
- The doc validator's internal codes (FC, R, L and PB codes). They stay the validator's own;
  where a gate wraps one, the entry records the code as an alias.
