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
   gives. It prints the packet's path. Every packet command takes `--scratch`,
   a directory of the run's own from `skill-session.sh scratch`, which the
   packet is written into: a `/work-on` run's scratch directory (the one its
   evidence files go in, which nothing ingests), a jury's `<inputs-dir>`, or,
   at a site that keeps
   neither, one allocated for the packet. Never a directory whose files are
   ingested as keys, and never the shared `$TMPDIR`, where another run's
   cleanup can remove the packet between panels. The script refuses a missing
   `--scratch` with exit 67, and one that isn't a private directory of the
   current user's outside the work tree with exit 64. The criteria for a code
   packet come from `--issue <N>`; a plan-backed child whose criteria live in
   a PLAN outline, and a free-form run with no issue, write their criteria to
   a file in the same scratch directory and pass `--criteria <file>` instead.
   A plan-outline child's `<N>` numbers an item in its PLAN, not an issue, so
   the script refuses
   `--issue` for its session with exit 67 rather than read an unrelated issue
   under that number. `--issue <N>` always comes with `--issue-repo`, the
   run's `ISSUE_REPO` as the state's directive gives it: empty for an issue
   in this repository, `owner/repo` for one elsewhere, which the script reads
   from there. Without the flag, or with a value that isn't `owner/repo`, the
   script exits 67 rather than guess this repository. An exit of 64 from a
   code packet means no base resolved: record `impl_base` as `analysis`'s
   fallback says and run it again. Don't spawn a seat without a packet.
   A `/work-on` panel's re-verifier, the `reverifier` decision its
   `<panel>_scope.json` marks `recheck`, gets its own `recheck` packet
   instead of the round's code packet; build the code packet only when a
   `full` seat is spawned. A `full` seat's code packet takes `--panel <panel>
   --seat <seat>` as well, which adds the seat's own unclosed findings by id,
   the ones it answers this round. An exit of 64 from a `recheck` packet means
   the scope can't give a re-verification (no scope, an unreadable one, a
   decision other than `recheck`, or no base to fall back to); its message
   names which. Don't spawn the run without a packet; read the scope again.
2. Pass the model on every spawn (`model: "sonnet"` or `model: "haiku"`). A
   spawn with no model inherits the parent's.
3. Open each prompt with the seat preamble below, after any fixed preamble the
   spawn site already has, with the packet path, the head and the seat's
   budget filled in. `<head>` is the full commit the packet's `head:` line
   must name: `git rev-parse HEAD` when you build a `code` or `recheck`
   packet. A `doc` packet has no `head:` line, so its seats' preamble leaves
   out the sentence that begins `This review is of head`. Where a prompt
   template says to include the document or its sections (`[Contents of
   ...]`), name the packet path instead of pasting the text.
   The re-verifier's prompt is the re-check prompt below, with `<panel>`
   filled in, after the preamble, in place of its panel's full-review prompt: its packet carries
   no acceptance criteria for that prompt to judge.
4. Delete the packet once the round is aggregated, with the seats' detail
   files.

## The seat preamble

```
Your input is the review packet at <packet-path>, and only that file: never
read another packet, or a file with a similar name or in another directory,
in its place. If it is missing or can't be read, stop and return no verdict,
saying so. This review is of head <head>: before anything else, check the
packet's `head:` line against it, and if the line is missing or names
another commit, stop and return no verdict, quoting the line you found. The
packet carries what this review needs. Read anything else only when a
specific finding needs it, and list each such read under "Reads beyond
packet" in your output, with the finding it served. You have a budget of
<cap> tool calls. When you reach it, stop and return your verdict on what
you have, and say the budget ran out.
```

A packet that is gone or names another head is never replaced by a search:
a seat that found its path empty once read another run's packet and returned
a verdict on a different change.

## The re-check prompt

```
You are the <panel> panel's re-verifier. The packet lists, by id, each
blocking finding that is due for re-verification. Answer every one of
them by id: `holds` if it is still a defect, `reverified` if the fix
diff resolves it, with a one-line reason for each `reverified` saying
what in the fix diff resolves it. Don't dismiss a finding; that is the
raising seat's call, in a full round. A finding you leave out keeps its
status and stays due. If the packet's `fix diff from:` or `review from:`
line says `fallback:`, the diff is wider than the fix, from the start of
the change; judge the same questions on it. An empty fix diff means
nothing fixed the findings.

When the packet's `fix review:` line says `yes`, also review the fix
diff from its `review from:` commit against every panel's criteria in
the packet. You stand in for every panel this retry re-enters, so judge
the fix as each of them would, and return each defect the fix introduced
as a new finding with `severity: blocking` and its location.

Return your answers as {"id", "record", "reason"} entries in an
`answers` list, and any new defects in `findings`.
```

The QA panel's re-verifier also runs each due failing scenario again, since
those findings are failures the tester observed, not lines it read.

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
from `impl_base`. A `recheck` packet is for a panel's re-verifier, the one
run a retry round plans: it carries the due findings by id and the diff since
they were last judged, plus every panel's criteria when the run also reviews
the fix diff, and nothing the seats already read. A `doc` packet carries the document under review, its format
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
