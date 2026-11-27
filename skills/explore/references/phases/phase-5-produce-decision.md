# Phase 5: Decision Record Handoff

When crystallize selects "Decision Record", write a decision brief and hand
off to the decision skill. This replaces the former inline ADR production.

## Decision Brief

Write the brief as key `work/decision-brief.md` in `explore-<topic>`: assemble
it in a scratch directory, put it, and remove the directory.

```bash
dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch)
# write the brief to "$dir/decision-brief.md", then:
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put explore-<topic> work/decision-brief.md "$dir/decision-brief.md"
rm -rf "$dir"
```

The brief's content:

```markdown
# Decision Brief: <topic>

## Decision Question
<One sentence: what specific choice needs to be made?>

## Context
<From findings: why this decision matters, what's blocked, forces at play.>

## Known Options
<From findings/decisions: options identified during exploration.
Each with a brief description and evidence for/against from research.>

## Constraints
<From findings: non-negotiable requirements, compatibility needs, timebox.>

## Relevant Research
<The research keys the decision skill should read for detail, each as a
`koto context get explore-<topic> research/<name>` read.>

## Complexity Signal
<Simple (2 clear options, evidence strongly favors one) or
Complex (3+ options, trade-offs genuinely contested, stakeholders disagree)>

## Attempt Session
explore-<topic>
```

The Attempt Session section names `explore-<topic>` as the session the
decision records its attempt in, so a question it hands back is raised from
this session (`/decision`'s Phase 6, 6.2a).

## Handoff

After putting the brief:

1. Read the decision skill: `skills/decision/SKILL.md`
2. Invoke the decision skill as a direct run on `<topic>`, with the brief as
   input context. It opens and closes its own session, `decision-<topic>`
   (see the skill's Session and Keys):
   - question: from the Decision Question section
   - options: from Known Options (if any)
   - constraints: from Constraints
   - background: from Context
   - complexity: from Complexity Signal ("simple" → standard, "complex" → critical)
   - attempt session: `explore-<topic>`, from Attempt Session
3. The decision skill runs its phases and writes its report as key
   `work/report.md` in `decision-<topic>` (`koto context get decision-<topic>
   work/report.md` reads it)
4. A settled report (`status: "COMPLETE"`) serves as the Decision Record (ADR)
5. An `UNDECIDED` result is not a failure and is not retried; see "An
   Undecided Result" below. It produces no Decision Record.
6. When the decision skill returns, close the session. It reads the research
   keys while it runs, so the close comes only after it returns:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close explore-<topic> done
```

## An Undecided Result

When the decision skill returns `status: "UNDECIDED"`, it chose nothing and
recorded its undecided attempt in `explore-<topic>`. Its report and question
are keys in `decision-<topic>`.

1. Check them:
   `"${CLAUDE_PLUGIN_ROOT}/skills/decision/scripts/check-undecided.sh" decision-<topic> work/report.md`.
   Exit 0 goes on; exit 1 names the missing part, which goes into the
   summary below as a failed hand-back.
2. Raise the question from `explore-<topic>`:

   ```bash
   koto context get decision-<topic> work/question.json \
     | shirabe question raise --in explore-<topic> --content - --attempt <attempt id>
   ```

   The question is raised as the decision wrote it; only `ground` and
   `waiting` may be replaced.
3. Write no Decision Record, no chosen option and no assumption for it.
4. In a turn a person started in an attended session, present the question
   with `shirabe question render <identity>` and record the reply with
   `shirabe question answer <identity> --in explore-<topic>`
   (`references/question-procedure.md`, steps 5 and 6). Otherwise it waits.
5. Close `explore-<topic>` as above. The close ticks with `--no-cleanup`, so
   the question stays open and the research keys (`research/...` here,
   `work/...` in `decision-<topic>`) stay readable for whoever answers it.

Tell the user the exploration ended with an open question, its identity and
who it is addressed to. Once it is answered, re-running `/decision` on the
topic with the answer writes the Decision Record.

## Escalation from Lightweight

If explore was running the lightweight protocol and escalated (status="escalated"),
the partial decision block's Question and Evidence become the brief's Decision
Question and Context sections. No information is lost.

## Artifact State

After this step:
- Key `work/decision-brief.md` in `explore-<topic>` (new)
- The decision skill's report at `work/report.md` in `decision-<topic>`
  (settled, or undecided with `work/question.json` beside it and its question
  open, raised from `explore-<topic>`)
- Session `explore-<topic>` closed after the decision skill returned; its keys
  stay readable
