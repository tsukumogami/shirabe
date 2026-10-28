# Review Verdict Blocks

A document jury seat (the /brief, /prd, /design and /review-plan reviewers)
ends its output with one fenced block that says, per rubric item and section,
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

`round-started` goes beside the `review-packet.sh` call, before the seats are
spawned; pass `--fallback` when the round runs as the serial self-jury.
`verdicts` goes just before `skill-session.sh ingest`, which removes the
directory. `decision` goes after the orchestrator decides what follows the
round: `rerun`, `fix_and_proceed`, `loop_back`, `proceed` or `stop`.
