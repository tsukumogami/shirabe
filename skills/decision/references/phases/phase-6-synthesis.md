# Phase 6: Synthesis and Report

The decider reads all findings and produces the final decision report.

## Resume Check

If key `<report_key>` exists in `<session>`, read its block status. A
`confirmed` or `assumed` report means the decision is complete: skip this
phase. An `undecided` report means the decision handed a question back: skip
this phase too, and go to 6.7 if the question has been answered since.

## Steps

### 6.1 Read All Inputs

**Fast path (Tier 3):**
- Context (key `<key_dir>/context.md`)
- Research findings (key `<key_dir>/research.md`)
- Alternatives comparison (key `<key_dir>/alternatives.md`)

**Full path (Tier 4):**
- All of the above, plus:
- Bakeoff reports (keys `<key_dir>/bakeoff_*.md`)
- Cross-examination record (key `<key_dir>/examination.md`)

### 6.2 Synthesize Decision

Weigh the evidence and commit to a choice. For full path, the cross-examination
record provides the most refined view -- focus on:

- Points where all validators agreed (high confidence)
- Points where validators conceded (settled debates)
- Unresolved tensions (genuine trade-offs to document)

### 6.2a When the Evidence Does Not Settle It

The evidence does not settle the question when no option is a clear winner,
or a fact the choice rests on could not be found: the cases
`references/decision-block-format.md` lists as a best guess or a close call.
A choice the evidence clearly favours is settled: go on to 6.3 as before.

When it does not settle and the run can ask (an attended session, in a turn
the person started), ask, and settle on the reply.

When nobody can be asked, apply the cheap-or-costly test in
`references/question-procedure.md`. Attended or unattended is read for the
session the decision runs in, the way that reference says, never from the
fact that this decider was told to run without prompting. The attempt is
recorded in the session that will raise the question, called `<attempt
session>` below: `<session>` (the caller's) under a parent skill; in a direct
run that a skill started with a brief naming an attempt session, that
session (`explore-<topic>` under `/explore`); in a direct run nobody called,
the decision's own `decision-<topic>`. Only a decision nobody called raises
its own question.

- **Cheap, in an unattended session, with no ground against it:** choose the
  recommendation, record the
  attempt `provisional` (`shirabe question attempt --in <attempt session> --what
  "<question>" --result provisional --undo cheap --undo-reason "<what undoing
  would take>" --chosen "<name>"`), note its id, and write the settled report
  in 6.3 with status `assumed`.
- **Otherwise** (costly; cheap but kept from the session by one of the
  grounds that reference lists; or attended with nobody to ask): record the
  attempt `undecided` (`shirabe question attempt --in <attempt session> --what
  "<question>" --result undecided`, adding `--undo costly --undo-reason
  "<why>"` in an unattended session, or `--undo cheap --undo-reason "<what
  undoing would take>" --ground <ground>` for a cheap choice a ground keeps
  from it), note its id, write the undecided report in 6.3a and the
  question in 6.3b, and return `UNDECIDED` in 6.6.

### 6.3 Write Decision Report

Write key `<report_key>` in `<session>` (`koto context add <session>
<report_key>`, the content on stdin) using the canonical format from
`references/decision-report-format.md`:

```markdown
<!-- decision:start id="<topic>" status="<confirmed|assumed>" -->
### Decision: <Topic>

**Context**
<from context artifact and research, 1-3 paragraphs>

**Assumptions**
- <from research assumptions + validator findings>

**Chosen: <Name>**
<full description, detailed enough to understand without reading alternatives>

**Rationale**
<why this option, tied to constraints and decision drivers>

**Alternatives Considered**
- **<Alt 1>**: <description>. Rejected because <reason from validators>.
- **<Alt 2>**: <description>. Rejected because <reason>.

**Consequences**
<what changes, what becomes easier, what becomes harder>
<!-- decision:end -->
```

### 6.3a Write the Undecided Report

For a decision that ends undecided, write key `<report_key>` with the
undecided report from `references/decision-report-format.md`: the block with
`status="undecided"` holding Context, Question, a Recommendation with its
reason, Alternatives Considered with a reason each, and What Would Settle It.
It has no Chosen section and no assumption stands in for one.

### 6.3b Write the Question

Write key `<key_dir>/question.json` in `<session>` with the question in the
form `shirabe question raise` takes (`references/question-procedure.md`, step
4): `context`, `problem`, `question`, two to four `options` each with a
`label` and a `reason` (the recommendation first), `ground`, `waiting` and a
short `label`. The caller may replace `ground` and `waiting` with its own;
the rest it raises as written here. Then check both keys:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/decision/scripts/check-undecided.sh" <session> <report_key>
```

Exit 0 means the report and the question are whole. Exit 1 names the part
that is missing; fix it and run the check again.

### 6.4 Determine Status

Apply the status threshold from `references/decision-block-format.md`:

- If evidence clearly favored the choice and no assumptions were made: `confirmed`
- If assumptions exist, or evidence was contested, or the decision was made in
  --auto mode without user confirmation: `assumed`
- A provisional decision (6.2a): `assumed`
- A decision that ends undecided (6.2a): `undecided`, in the undecided report

### 6.5 Remove the Intermediate Keys

An undecided decision removes no intermediate key: skip this step. The
research stays readable for whoever answers the question and for the run that
writes the answer afterward.

For a settled decision, remove every intermediate key for this decision (`koto context remove
<session> <key>` for each):
- `<key_dir>/context.md`
- `<key_dir>/research.md`
- `<key_dir>/alternatives.md`
- `<key_dir>/bakeoff_<k>.md`, each one `koto context list <session> --prefix
  <key_dir>/bakeoff_` lists
- `<key_dir>/examination.md`

Only the report (key `<report_key>`) persists, so a parent reading the session
finds one answer per decision and a restarted decision starts fresh. Nothing
is deleted from the staging folder: `/decision` writes nothing there.

### 6.6 Return Result

If running as a sub-operation (agent), return the structured result:

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "<name>"
  confidence: "<high|medium|low>"
  rationale: "<1-2 sentences>"
  assumptions:
    - "<assumption 1>"
  rejected:
    - name: "<alt>"
      reason: "<reason>"
  report_key: "<report_key>"
```

A provisional decision returns the same result with `provisional: true` and
`attempt: "<session>:<id>"` added. A decision that ends undecided returns:

```yaml
decision_result:
  status: "UNDECIDED"
  question: "<the question>"
  recommendation:
    name: "<name>"
    reason: "<reason>"
  alternatives:
    - name: "<alt>"
      reason: "<reason>"
  missing: "<what would settle it>"
  attempt: "<attempt session>:<id>"
  question_key: "<key_dir>/question.json"
  report_key: "<report_key>"
```

Under a parent skill, or in a direct run a skill started with an attempt
session, the decider raises nothing: the caller raises the question from the
attempt session. In a direct run nobody called, it raises its own question
from `decision-<topic>`:

```bash
koto context get decision-<topic> work/question.json \
  | shirabe question raise --in decision-<topic> --content - --attempt <id>
```

If running standalone with an undecided result and nobody called it, present
the summary, the report and the question's identity, and leave
`decision-<topic>` open: the question waits on its answer (6.7). A direct run
a skill started returns the result to that skill and closes
`decision-<topic>` with `done`, as a settled run does. Its close, when it comes, keeps every key,
since `skill-session.sh close` ticks with `--no-cleanup`.

If running standalone with a settled result, present a summary and the report to the user (it stays
readable as key `work/report.md` in `decision-<topic>`), then close the
session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close decision-<topic> done
```

Under a parent skill, close nothing: the parent owns the session and closes
it at its own end.

### 6.7 After the Answer

When the question a direct run raised is answered (`shirabe question pending
--in decision-<topic>` lists the answer, or `koto decisions history
<identity>` shows it), record the answer as the choice: `shirabe question
attempt --in decision-<topic> --what "<question>" --result decided --chosen
"<the answer's option>" --basis <the answer's session>:<id>`, rewrite key
`work/report.md` as a settled report with status `confirmed` whose Rationale
cites the answer, then run 6.5 and close the session as a settled run does.

## Quality Checklist

- [ ] All relevant inputs read (fast path or full path)
- [ ] Decision report written in canonical format
- [ ] Status correctly assigned (confirmed vs assumed, or undecided)
- [ ] Settled: intermediate keys removed; a standalone run closed `decision-<topic>`
- [ ] Undecided: an undecided attempt recorded, `<key_dir>/question.json`
      written, `check-undecided.sh` exits 0, no intermediate key removed

## Next Phase

None. Phase 6 is the final phase. The report is the deliverable.
