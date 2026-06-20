# /brief Discovery: execute-skill

## Problem Candidate (revised after #196 merge + responsibility-split directive)
The implementation flow does double duty: one workflow both executes a single issue
and iterates a whole plan of many issues to completion. So there is no
implementation-altitude coordinator that owns plan-level execution, and the
single-issue path carries plan-orchestration weight at the wrong altitude. For a
plan whose issues land as several coordinated pull requests, the across-issue picture
lives nowhere durable and an interrupted run loses it.

## Outcome Candidate (revised)
Plan-level execution becomes its own coordinator (/execute), completing the
parent-skill trio. An author hands a finished plan off in one move and it iterates
the plan's issues to merged code — single-PR or coordinated multi-PR — delegating
each individual issue down to the single-issue executor (/work-on, narrowed to
exactly that job). Progress reports against the whole, a single done-signal closes a
coordinated set, and resume works across branches from the plan's durable
coordination state. Whether /execute's plan iteration uses koto is left to the
downstream design.

## Grounding Anchor
Conversation only (public framing). Related public artifacts the BRIEF may cite:
the progression-authoring design (DESIGN-shirabe-progression-authoring.md), the
coordinated execution-mode work (shirabe#196), and the /charter + /scope parent
skills as precedent. The motivating exploration is non-durable wip on another
branch and is NOT cited.

## Journey Sketch
- Author has a single-unit (single-PR) plan -> invokes the coordinator -> it runs
  the one unit to a merged PR and reports done.
- Author has a coordinated multi-unit plan -> invokes the coordinator -> it walks
  the merge-order of units, delegating each to the existing implementation flow,
  surfaces progress against the whole, and signals done when the coordinating PR
  merges last.
- Author is interrupted mid-execution -> re-invokes the coordinator -> it resumes
  from the plan's durable coordination state (across branches), picking up the next
  unit rather than starting over.

## Open Questions for Drafting
- Naming: the feature introduces a new implementation-altitude parent skill
  (working name /execute). Confirm the BRIEF frames the capability, leaving the
  in-place-rename-vs-new-skill call to the downstream design.
- Scope boundary precision: keep the work-on-internals migration, the koto
  folder-lease substrate, the redirect mechanism, and non-coordinated multi-PR
  fan-out explicitly OUT.
