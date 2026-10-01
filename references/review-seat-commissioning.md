# Review seat commissioning

What every review seat shirabe spawns is commissioned with, and why. A review
seat is a subagent that judges work someone else produced: a `/work-on` panel
reviewer, the implementation-phase agent review, a document jury member, a
`/review-plan` validator. Normative prose, like
[`tool-declaration-policy.md`](tool-declaration-policy.md): each spawn site
carries its own commissioning block, short enough to act on where the spawn
happens, and cites this file for the argument and the full registry.

## The declaration

A spawn site states five things for each seat it commissions, in a
commissioning block placed immediately before its spawn instruction:

| Field | What it says |
|---|---|
| Subagent type | The agent type the spawn names. `general-purpose` for every seat today. |
| Tools | The tools the seat's brief may ask it to use. A brief never asks a seat to run something or write a file outside this grant. Like the turn cap, the grant is stated in the prompt: the Agent tool takes no per-spawn tool list, so a spawn that can restrict tools should, and one that can't still keeps the brief inside the grant. |
| Model | `sonnet` by default; `haiku` where the seat's criteria are a closed checklist; anything else only with a written reason at the spawn site. |
| Turn cap | The most tool calls the seat makes before it returns what it has. |
| Packet | The fixed input the seat starts from, and the command that assembles it. |

Subagent type and tools are the capability shirabe#369 asks each panel to
state at commissioning. Model, turn cap and packet sit in the same block
because they are decided at the same moment, by the same author, and a reader
checking one wants the others beside it.

## Why a model is named

An Agent-tool spawn with no `model` inherits the parent session's model. The
sessions that drive shirabe's workflows usually run on the largest model, so
an unnamed seat runs there too, at several times the per-token price, to do
work that rarely needs it: checking a diff against acceptance criteria, or a
document against its format reference. The spawn passes the model explicitly
(`model: "sonnet"`), so the choice is visible in the call and does not change
when the parent does.

`haiku` is for seats whose criteria are closed: the structural-format
reviewers, which check named sections, frontmatter fields and their order
against a format reference. A seat whose verdict rests on judgment (does the
problem statement smuggle a solution, does the implementation match the
design's intent) stays on `sonnet`.

No seat currently stays on the parent's model. A seat that needs to says why
in its own row, next to the model, so the exception is reviewed with the
spawn rather than discovered in a cost report.

## Why a packet

A seat given a role and nothing else explores. It reads skill references, the
repository and design documents turn after turn, and each turn re-reads
everything before it, so cost grows with the square of the turns rather than
with what the review needs. Reviewing one diff should not cost what reviewing
the repository costs.

The packet is the bounded input the seat starts from, assembled by
[`scripts/review-packet.sh`](../scripts/review-packet.sh) rather than by the
orchestrating agent. A script decides the same contents every time, the
orchestrator never pastes a document into a prompt (which it would pay for as
output on the parent's model), and the packet is the same file for every seat
in a round, so the seats disagree about the work and not about what they read.

Two kinds:

- **Code packet** (`review-packet.sh code --session <WF> --issue <N>`, or
  `--criteria <file>` when the criteria come from a PLAN outline): the issue's
  acceptance criteria, the design context phase 0 recorded (`context.md`), the
  changed-path list and the diff, all from `impl_base` to `HEAD`. For the
  `/work-on` panels and the implementation-phase agent review.
- **Document packet** (`review-packet.sh doc --doc <path> --format <reference>
  [--extra <path>]...`): the document under review, its format reference, and
  the supporting files the spawn site names, such as a scope file or an
  upstream document. For the juries and `/review-plan`.

Each section has a byte cap and ends with a truncation line when cut, so a
seat knows when there is more to read. The script's header has the caps, the
base order and the exit codes.

The orchestrator assembles the packet once per round, hands every seat its
path, and deletes it after aggregation, as it does the seats' detail files. A
jury prompt's `[Contents of ...]` placeholders are the packet: the prompt
names the packet path in their place rather than carrying the text.

A seat may read beyond its packet when a specific finding needs it: the full
file behind a truncated diff, a caller of a changed function, an upstream
document the packet names but does not carry. It lists each such read in its
output with the finding it served. That list is how a later reader tells a
packet that was enough from one that was not, and it is the evidence for
changing what a packet carries.

## Why a turn cap

The Agent tool takes no turn limit, so the cap is a budget stated in the
seat's prompt rather than one the host enforces. It still bounds the common
failure: a seat that keeps reading because nothing told it when to stop. A
seat that reaches its cap returns its verdict on what it has and says the
budget ran out, and the orchestrator treats that like any other verdict. A
host that supports a per-agent turn limit should apply the same number.

The caps are sized to the work. A jury seat reads one packet and writes one
verdict, so a handful of calls covers it plus the occasional read beyond. A
code seat may check a few callers or run `git log`. The QA tester executes
the implementation, which takes more calls than reading it.

## The seat preamble

Every seat's prompt opens with this, after any fixed preamble its spawn site
already has (the jury prompt-injection preamble, for one), with the packet
path and the cap filled in:

```
Your input is the review packet at <packet-path>. Read it first; it carries
what this review needs. Read anything else only when a specific finding needs
it, and list each such read under "Reads beyond packet" in your output, with
the finding it served. You have a budget of <cap> tool calls. When you reach
it, stop and return your verdict on what you have, and say the budget ran out.
```

## Registry

Every review seat in shirabe's skills. A new seat is added here and at its
spawn site in the same change.

| Skill | Spawn site | Seats | Model | Turn cap | Tools | Packet |
|---|---|---|---|---|---|---|
| work-on | `phases/phase-4a-scrutiny.md` | completeness, justification, intent | sonnet | 15 | Read, Grep, Glob, Bash | code |
| work-on | `phases/phase-4b-review.md` | pragmatic, architect, maintainer | sonnet | 15 | Read, Grep, Glob, Bash | code |
| work-on | `phases/phase-4c-qa.md` | tester | sonnet | 30 | Read, Grep, Glob, Bash | code |
| work-on | `phases/phase-4-implementation.md` | security, performance, testing, architecture (as needed) | sonnet | 15 | Read, Grep, Glob, Bash | code |
| brief | `phases/phase-4-validate.md` | content quality | sonnet | 8 | Read, Write | doc: BRIEF + `brief-format.md` + context (one packet for both seats) |
| brief | `phases/phase-4-validate.md` | structural format | haiku | 6 | Read, Write | doc: BRIEF + `brief-format.md` + context (the same packet) |
| prd | `phases/phase-4-validate.md` | completeness, clarity, testability | sonnet | 8 | Read, Write | doc: PRD + `prd-format.md` + scope |
| design | `phases/phase-5-security.md` | security researcher | sonnet | 12 | Read, Grep, Glob, Write | doc: DESIGN + `design-format.md` |
| design | `phases/phase-6-final-review.md` | architecture, security | sonnet | 8 | Read, Write | doc: DESIGN + `design-format.md` |
| design | `phases/phase-6-final-review.md` | structural format | haiku | 6 | Read, Write | doc: DESIGN + `design-format.md` |
| vision | `phases/phase-4-validate.md` | thesis quality, content boundary, section guidance | sonnet | 8 | Read, Write | doc: VISION + `vision-format.md` + scope |
| strategy | `phases/phase-4-validate.md` | bet quality, altitude | sonnet | 8 | Read, Write | doc: STRATEGY + `strategy-format.md` + upstream |
| strategy | `phases/phase-4-validate.md` | structural format | haiku | 6 | Read, Write | doc: STRATEGY + `strategy-format.md` |
| roadmap | `phases/phase-4-validate.md` | theme coherence, sequencing and dependency, annotation and boundary | sonnet | 8 | Read, Write | doc: ROADMAP + `roadmap-format.md` + scope |
| comp | `phases/phase-4-validate.md` | competitive framing, content quality | sonnet | 8 | Read, Write | doc: COMP + `comp-format.md` |
| comp | `phases/phase-4-validate.md` | structural format | haiku | 6 | Read, Write | doc: COMP + `comp-format.md` |
| review-plan | `SKILL.md` | validators (three per category in adversarial mode, one in fast-path when spawned) | sonnet | 10 | Read, Grep, Glob | doc: plan decomposition + the category's phase reference + analysis, dependencies, upstream design, issue bodies |
| review-plan | `SKILL.md` | cross-examination | sonnet | 6 | Read | the category's packet, plus the disagreeing findings in the prompt |

Spawn-site paths are relative to the skill's `references/` directory, except
`review-plan`'s `SKILL.md`.

Seats with no Write grant (the `/review-plan` validators and cross-examination
agents) return their findings in their reply, in the `critical_findings` format
their spawn site names, rather than writing a file.

The issue's later measurements (per-seat token figures against the pre-change
baseline, and no rise in defects caught after merge) are taken on the
coordinator-driven features that run after this lands; see **Measuring the
effect** below.

Not review seats, and so not in the registry: research and discovery agents
(the `/explore`, `/prd`, `/vision` and `/roadmap` discover phases, `/design`'s
decision agents, `/decision`'s research and bakeoff validators), the `/plan`
issue-generation agents, and the `/work-on` analysis agent. They produce work
rather than judge it, and their inputs are open by design.

## Measuring the effect

Coordinators record panel spend per unit. The figures to compare against the
pre-change baseline are per-seat input and output tokens, split by model, for
each panel in a coordinator-driven feature. A packet that is working shows as
seats whose input stays near the packet's size; a seat whose "Reads beyond
packet" list is long on most runs is the signal that its packet is missing
something.
