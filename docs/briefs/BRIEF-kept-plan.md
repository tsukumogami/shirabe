---
schema: brief/v1
status: Accepted
problem: |
  Once a feature's work merges, the plan that work followed is gone: completion
  deletes it, and a single-PR plan never reaches the default branch at all. A
  later reader can't get from a merged PR to the plan it carried out, and the
  steps' proof and the run's departures are lost with the file.
outcome: |
  A reader on the default branch opens the plan a feature's work followed, finds
  each step's proof and every recorded departure beside the step it changed,
  and moves between that plan and each of its PRs in both directions. shirabe's
  references all say the same thing about a plan once its work is done.
---

# BRIEF: Kept plan

## Status

Accepted

One question goes downstream. shirabe's own classification of the plan as a
working document is in scope and changes here, but the same classification is
also held outside this repository, in the toolkit's planning record, by whoever
owns that record. The PRD and design say whether a kept plan needs that outside
classification to change or already fits it, and build nothing that waits on
the answer.

Accepted under `/scope`'s non-interactive mode: this run was dispatched as a
background worker with no interactive author, so the approval gate took the
recommended verdict on an all-PASS jury rather than blocking.

## Problem Statement

When a feature's work is done, the plan it followed disappears, and with it the
only document that says what was agreed.

A plan in shirabe is where a feature's work is broken into steps, each with its
acceptance criteria and, in a step plan, the proof that the step landed. While
the work runs, the plan is the contract the sessions doing it read from. When
the work finishes, the completion step marks the plan Done and removes it in a
commit that names no pull request. A plan that ships as a single pull request
has it worse: it is added and removed on the same branch, so a squash merge
never puts it on the default branch at all. Nothing on the default branch ever
records that the plan existed.

That leaves every later reader without the thing they came for. A reviewer
judging whether a finished feature did what was agreed has to reconstruct the
agreement from issue bodies and PR descriptions. A maintainer looking at one
merged pull request can't tell which step of which plan it carried out, or what
the other steps were. A session picking up related work can't find what the
earlier run decided. And when a run departed from its plan, which happens, the
departure was recorded in the workflow engine's state outside the repository,
beside a plan that is now deleted. Nobody can check the departure against the
step it changed, because neither is on the default branch.

The deletion isn't an accident of one script. It follows from how shirabe
classifies the plan: as a working document, like a roadmap, that lives only as
long as its work. A validator rule built on that class stops any durable
document from naming a plan, because the link would dangle once the plan was
removed. So a design can't point at the plan that implemented it, and a design
that tries fails validation.

shirabe's own references don't agree on any of this. The plan format reference
says a plan stays in place through every state. The planning skill and the
completion step delete it. The pipeline reference calls it a working document
and the validator enforces that. A reader trying to learn what happens to a
plan gets a different answer depending on which file they open.

## User Outcome

A reviewer who opens the default branch after a feature's work has merged
finds the plan that work followed, in a known place, without searching for it
by name. Each step in it carries its proof, and each departure the run recorded
sits beside the step it changed, so the reviewer can judge the merged work
against what was agreed and check any departure against the run's own record.

From the plan, the reviewer reaches each pull request that carried it out.
From any one of those pull requests, a maintainer reaches the plan. Neither
direction depends on remembering a topic name or a branch.

The same holds when the whole plan shipped as one pull request: the plan is on
the default branch afterwards like any other.

A design can point at the plan that implemented it and still validate. And an
author who reads the plan format reference, the planning skill, the completion
step or the pipeline reference to learn what happens to a plan once its work is
done gets the same answer from each.

## User Journeys

### A reviewer checks a finished feature against its plan

A reviewer is asked whether a feature that merged last week did what was
agreed. They open the default branch, go to where kept plans live, and open the
feature's plan. They read each step's acceptance criteria and its proof, and
the departures recorded against two of the steps. They pick two departures and
check each against the run's own record of the decision. They leave with a
verdict grounded in the agreement rather than in their memory of it.

### A maintainer starts from one merged pull request

A maintainer bisecting a regression lands on a squash commit. The pull request
it came from names the plan and the step it carried out. They open the plan,
see the step's acceptance criteria and the neighbouring steps, and learn which
other pull requests belong to the same piece of work. They never search by
name or guess at a branch.

### An author delivers a small feature in one pull request

An author runs a delivery whose plan fits a single pull request. The pull
request is squash-merged. Afterwards the plan is on the default branch, with
its step marked done and its proof recorded, exactly as a multi-PR plan's would
be. Today the same run leaves no trace of the plan once the branch is gone.

### A design author links the design to its plan

An author finishing a design wants the design to say which plan implemented
it, so a reader of the design can follow it to the work. They add the
reference, and `shirabe validate` accepts it, because the plan it names is a
document that stays. Today the validator rejects that link.

## Scope Boundary

**In:**

- Where a plan sits once its work has merged, and what its status says.
- The way from a plan to each pull request that carried it out, and from each
  of those pull requests back to the plan.
- Keeping each step's proof and each recorded departure in the kept plan, so
  a reader can check a departure against the run's own record.
- What completion does to a plan instead of deleting it, for single-PR,
  multi-PR and coordinated plans alike.
- Getting a single-PR plan onto the default branch.
- The validator behaviour that treats a plan as a document that disappears,
  both where it stops other documents naming a plan and where it requires a
  plan to be gone at merge.
- Making shirabe's references agree: the plan format reference, the planning
  skill, the completion step and the pipeline reference.

**Out:**

- Where a plan is kept for a team whose record isn't the repository. Until
  that question is settled elsewhere, the repository is the record; this work
  only leaves room for another home.
- Recording departures in the plan as they happen during a run, and accepting
  them. Keeping the plan in step with the work is a separate feature; this one
  keeps whatever the run already records.
- Who accepts a plan before work starts, and how acceptance is shown.
- Plans deleted before this lands. They stay deleted; nothing reconstructs
  them from history.
- Roadmaps. A roadmap is also a working document today, and whether it is
  kept is not this feature's question, though a kept plan that names its
  roadmap has to be handled.
- Changes to the workflow engine or the workspace manager. Anything this
  needs from them is read from what they already record.

## References

- `references/pipeline-model.md` -- the lifecycle table, the working and
  durable classes, and the lifetime rule.
- `skills/plan/references/plan-format.md` -- the plan format reference.
- `skills/plan/SKILL.md` -- the planning skill.
- `skills/execute/SKILL.md` -- the completion cascade.
- `docs/briefs/BRIEF-cascade-post-verify-seed.md` -- an earlier brief on the
  cascade's handling of the plan it deletes.
