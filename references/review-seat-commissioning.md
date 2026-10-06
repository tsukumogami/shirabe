# Review seat commissioning

How shirabe spawns a review seat, and why. A review seat is a subagent that
judges work someone else produced: a `/work-on` panel reviewer, the
implementation-phase agent review, a document jury member, a `/review-plan`
validator. Research, discovery and issue-generation agents are not review
seats; they produce work rather than judge it, and their inputs are open by
design.

Each spawn site carries one **Seat commissioning** line naming each seat's
model and call budget, and the packet command. This file holds everything
those lines have in common, so it is said once.

## At the spawn site

1. Assemble the packet once per round with the command the commissioning line
   gives. It prints the packet's path. The criteria for a code packet come
   from `--issue <N>`; a plan-backed child whose criteria live in a PLAN
   outline, and a free-form run with no issue, write their criteria to a
   `mktemp` file and pass `--criteria <file>` instead. An exit of 64 from a
   code packet means no base resolved: record `impl_base` as `analysis`'s
   fallback says and run it again. Don't spawn a seat without a packet.
   A `/work-on` panel seat whose `<panel>_scope.json` decision is `recheck`
   gets its own `recheck` packet, one per such seat, instead of the round's
   code packet; build the code packet only when a `full` or `rerun` seat is
   spawned. A seat with any other decision gets the code packet, unchanged.
   An exit of 64 from a `recheck` packet means the scope doesn't mark that
   seat `recheck` (or there is no scope): give the seat the code packet
   instead, as its decision says.
2. Pass the model on every spawn (`model: "sonnet"` or `model: "haiku"`). A
   spawn with no model inherits the parent's.
3. Open each prompt with the seat preamble below, after any fixed preamble the
   spawn site already has, with the packet path and the seat's budget filled
   in. Where a prompt template says to include the document or its sections
   (`[Contents of ...]`), name the packet path instead of pasting the text.
   A `recheck` seat's prompt is the re-check prompt below, after the
   preamble, in place of its panel's full-review prompt: its packet carries
   no acceptance criteria for that prompt to judge.
4. Delete the packet once the round is aggregated, with the seats' detail
   files.

## The seat preamble

```
Your input is the review packet at <packet-path>. Read it first; it carries
what this review needs. Read anything else only when a specific finding needs
it, and list each such read under "Reads beyond packet" in your output, with
the finding it served. You have a budget of <cap> tool calls. When you reach
it, stop and return your verdict on what you have, and say the budget ran out.
```

## The re-check prompt

```
You raised the blocking findings in the packet last round, as the <seat>
seat. Answer, for each one, whether the fix diff in the packet fixes it.
Read the whole fix diff: a defect the fix itself introduces is a blocking
finding too, because a passing re-check records this seat as passed at
HEAD. Don't re-review anything else; the rest of the change kept its
verdict. If the packet's `fix diff from:` line says `fallback:`, the diff
is wider than the fix, from the start of the change; judge the same
questions on it. An empty fix diff means nothing fixed the findings.
```

The QA tester's re-check also runs each failing scenario again, since its
findings are failures it observed, not lines it read.

## Why a model is named

The sessions that drive shirabe's workflows usually run on the largest model,
so an unnamed seat runs there too, at several times the price, to check a diff
against acceptance criteria or a document against its format reference.
`sonnet` is the default. `haiku` is for seats whose criteria are a closed
checklist: the structural-format reviewers, which check named sections and
fields against a format reference. A seat that needs the parent's model says
why on its commissioning line, and the same change adds that model to the
allowed list in `scripts/review-packet_test.sh`, which otherwise rejects it.

## Why a packet

A seat given a role and nothing else explores: it reads skill references, the
repository and design documents turn after turn, and each turn re-reads
everything before it. [`scripts/review-packet.sh`](../scripts/review-packet.sh)
assembles a bounded input instead. A `code` packet carries the acceptance
criteria, the design context phase 0 recorded, the changed paths and the diff
from `impl_base`. A `recheck` packet is for a seat that blocked last round
and now checks only whether its findings are fixed: it carries those findings
and the diff since the commit the seat judged, and nothing the seat already
read. A `doc` packet carries the document under review, its format
reference, and any supporting files the spawn site names. Each section is
capped and says when it was cut; the script's header has the details.

A script, rather than the orchestrator, builds it so the contents are the same
every time, the orchestrator doesn't pay to paste documents into prompts, and
every seat in a round reads the same file. The "Reads beyond packet" list is
the evidence for changing what a packet carries.

## Why a call budget

The Agent tool takes no turn limit, so the budget is stated in the prompt
rather than enforced by the host. It still stops the common failure, a seat
that keeps reading because nothing told it when to stop. A host that can
enforce a per-agent limit should use the same number. Jury seats get 6 to 8
calls (one packet, one verdict, a few reads beyond), code seats 10 to 15, and
the QA tester 30 because it runs the implementation.

## Measuring the effect

Coordinators record panel spend per unit. Compare per-seat input and output
tokens, split by model, against the pre-change baseline. A working packet
shows as seat input near the packet's size; a long "Reads beyond packet" list
on most runs, or a budget that keeps running out, says the packet or the cap
needs changing.
