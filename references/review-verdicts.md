# Review Verdict Blocks

A document jury seat (the /brief, /prd, /design, /review-plan, /vision,
/strategy and /roadmap reviewers) ends its output with one fenced block that says, per rubric item and section,
whether the document passed. `scripts/review-events.sh` reads the block and
records it as telemetry through `koto review record`. Recording never changes
a verdict, a gate or what the skill does next: the seat's own PASS or FAIL line
is still what the orchestrator acts on.

## The block

The block is the last thing in the seat's output, fenced and tagged
`review-verdicts`, holding a JSON array:

````
```review-verdicts
[
  {"rule_id": "rs-021", "section": "problem-statement", "verdict": "PASS"},
  {"rule_id": "rs-011", "section": "user-journeys", "verdict": "FAIL"}
]
```
````

- `rule_id` is the rubric item's id, as the seat's prompt lists it. Every
  rubric item has an entry in `references/rule-registry.json`.
- `section` is the slug of the section the item was judged on: the format's
  required `##` heading, lower case, with each run of other characters turned
  into one hyphen (`Scope Boundary` is `scope-boundary`), or `frontmatter`, or
  `document` for an item about the whole document. An item judged on several
  sections gets one entry per section.
- `verdict` is `PASS` or `FAIL`.

One entry per rubric item per section judged. A seat that couldn't judge an
item leaves it out rather than guessing.

The /vision, /strategy and /roadmap seats each have one rubric item standing
for the rest of the seat's verdict (`rs-064` to `rs-072`), judged on
`document`. Their criteria get ids of their own when the per-item telemetry is
wanted. Two of those seats already split one item off, below.

## Items the document criteria are compared with

Each document criterion (`references/jev-criteria.md`) is compared with the
jury's verdict on the same rule id and section key, so the seat that reads
the rule judges it as an item of its own. A seat's FAIL on an unrelated item
never lands on the criterion's id.

| Rule | Section key | Format | Seat | Item |
|------|-------------|--------|------|------|
| `rs-073` | `scope-boundary` | BRIEF | content-quality | 7: each Scope Boundary bullet names what the feature covers or leaves out, not a mechanism, path or command |
| `rs-073` | `milestones` | ROADMAP | annotation-boundary | item 5's Evidence-clause bullets; `rs-072` keeps the rest |
| `rs-074` | `bet-specific-falsifiability` | STRATEGY | bet-quality | the falsifier items, 3 to 6; `rs-067` keeps items 1 and 2 |
| `rs-009` | `document` | PRD | clarity | 6: two passages sharing a number or backticked term contradict each other |
| `rs-009` | `document` | DESIGN | architecture | 5: the same question, over the whole document |

`rs-011`, `rs-012` and `rs-013` already had items of their own: content-quality
item 3 and structural-format item 6 in /brief, and clarity item 3 in /prd.
Each section key is declared in both review vocabularies
(`koto-templates/skill-session.md`, and `skills/scope/koto-templates/scope.md`
for the formats /scope runs), and `scripts/review-events_test.sh` records each
pair through a stub seat.

## What the script trusts

Seats read documents their authors control, so the script trusts nothing a
seat writes:

- The seat's name comes from the skill's own seat list and the pinned file
  name, never from the seat's output.
- An entry whose rule id the registry doesn't hold (`rule-registry.sh
  resolve` fails or can't run) is dropped, and so is an entry whose verdict
  isn't `PASS` or `FAIL`, or that isn't an object of three strings.
- A section outside the format's closed list (its required sections from
  `references/doc-check-phases.json`, plus `frontmatter` and `document`) is
  recorded as `document`.
- A parse error or a dropped entry is reported on stderr by entry number and
  field, never by the text the seat wrote.

A seat whose output has no block, a block that doesn't parse as a JSON array,
or no valid entry records one verdict: FAIL on `rs-verdict-missing`, section
`document`. That keeps a seat that ignored the format visible in the
telemetry instead of silently absent.

## The calls

The skill's jury reference makes three calls around each round, all best
effort (a koto without `koto review record`, a missing session or a refused
batch prints one line on stderr and the skill goes on):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" round-started --skill <skill> --topic <topic> --doc <path> --seat-count <n> [--fallback]
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" verdicts --skill <skill> --topic <topic> --doc <path> --dir <verdicts-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" decision --skill <skill> --topic <topic> --doc <path> --decision <decision>
```

The /vision, /strategy and /roadmap juries add `--doc-format <skill>` to each
call: koto records the format on every record and no document type, which it
keeps for the other four.

`round-started` goes beside the `review-packet.sh` call, before the seats are
spawned, and after the pre-jury document check
(`references/doc-check-steps.md`); pass `--fallback` when the round runs as the serial self-jury.
`verdicts` goes just before `skill-session.sh ingest`, which removes the
directory. `decision` goes after the orchestrator decides what follows the
round: `rerun`, `fix_and_proceed`, `loop_back`, `proceed` or `stop`.

A fix made after a round's FAIL verdicts is recorded with
`scripts/doc-events.sh fix --answers jury_fail`, which reads the FAIL entries
of the seats' ingested files with the same parser
(`scripts/lib/review-verdicts.sh`) and joins each rubric item to the document
check that decides it through the registry's `held_by`.
