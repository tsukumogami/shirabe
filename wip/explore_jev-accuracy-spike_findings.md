# Exploration Findings: jev-accuracy-spike

## Core Question

How accurately does Jev grade shirabe's own prose-shaped criteria when called
through its API directly: false-pass on seeded-bad text, pass rate on text
written to steer it, false-fail on known-good text, and which criteria clear
the bar for a decider design?

## Round 1

### Key Insights

- Jev's request is `{"model":"jev-latest","state":{...},"questions":{...}}`;
  the response echoes the dated build (currently `jev-1.13.0`). koto sends a
  boolean field as a `noul` question with `instructions` only, so a boolean
  criterion's whole meaning must fit in one sentence; the true/false value
  descriptions a template author writes never reach Jev. (lead-jev-api)
- Jev's own docs say it reads questions literally, struggles with negations
  and scoping words, loses accuracy as unrelated text fills the state, and is
  vulnerable to adversarial text in the state. The last is exactly what the
  adversarial bar tests. (lead-jev-api)
- Batching several questions over one state is documented as accuracy-neutral
  and much cheaper; the request limit is 64k tokens, 32k for state plus the
  longest question. koto's 8192-byte default input budget is far tighter and
  is the practical limit. (lead-jev-api)
- Every candidate criterion has a quotable public rule, but two of them
  (scrutiny finding resolved by a diff; hedge with no approved deferral) turn
  on information outside the graded text. No scrutiny finding text survives
  anywhere public, since the working files are deleted before merge.
  (lead-criteria-sources)
- koto's fixture report computes false positives per value at threshold,
  which is the same quantity as false-pass here; a JSONL file under
  docs/spikes/ trips no CI check. (lead-decider-conventions)

### Tensions

- The hedge criterion is still testable if each fixture carries its own
  approved-deferrals list, but that tests matching a caveat against a list
  more than prose judgment, and the list is authored.
- The PR title criterion's rule text says almost nothing about which type fits
  which change, so a false-fail there partly measures the vague rule.

### Gaps

- No live measurement yet: calls to the Jev API are on hold pending a
  decision by the human who owns the workspace's network rules. The harness
  is proven only against stubbed and replayed answers.

### Decisions

- See wip/explore_jev-accuracy-spike_decisions.md, Round 1.

### User Focus

Auto mode; the brief fixes the bar (0 of at least 20 seeded-bad, 0 of 5
adversarial) and the candidate list.

## Accumulated Understanding

The spike is a measurement, not a design question: the approach (labelled
fixtures, a direct API harness, koto's threshold mapping) is settled by the
brief and the research, and the deliverable is a spike report. Six criteria
are testable from public artifacts; the scrutiny criterion is not, for lack of
any public finding text. The harness and fixture file can be built and proven
offline. The numbers the report must carry need live calls, which are on hold,
so the report can't reach Complete until they're allowed.

## Decision: Crystallize
