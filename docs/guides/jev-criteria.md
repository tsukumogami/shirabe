# Jev criteria: reading figures, promoting and demoting

A Jev criterion is a closed question Jev answers about a slice of an agent's
work. Its contract and trust record live in its entry in
`references/rule-registry.json`, under `jev`, and its written case in
`references/jev-criteria.md`, which also defines the states and the bars. This
guide is for the maintainer who reads a criterion's live figures, opens the
pull request that promotes it to `trusted`, or opens the one that demotes it
after a false pass.

Nothing changes a criterion's state on its own. Promotion and demotion are
both ordinary registry changes, reviewed and merged by someone other than
their author, and `scripts/jev-criteria/jev_criteria.py check` holds every
record to the rules in CI.

## Reading the live figures

The live figures come from koto's decider events, exported from every host to
a log backend. Read them there: a figure read from one machine's session logs
misses every other machine's runs.

Each decider event carries these attributes:

| Attribute | What it holds |
|---|---|
| `koto.session.id` | the koto session the evaluation ran in |
| `koto.visit.seq` | the visit of the state, so two visits to one state are two evaluations |
| `koto.check` | the gate, as the template names it |
| `koto.rule.id` | the criterion id the template declares (not the registry id) |
| `koto.decider.outcome` | on `decider_checked`: `pass`, `fail`, `escape`, `unanswered` or `not_graded` |
| `koto.decider.reason` | on `decider_fallback`: why the decider gave no verdict, such as `over_budget` or `provider_error` |
| `koto.decider.mode` | the effective mode, `veto` or `shadow` |
| `koto.decider.input_bytes` | the slice's size in bytes, when there was a slice |

The definitions, over events of every mode from every host:

- **Window.** From the later of the entry's `declared.since` and the day after
  the latest recorded false pass's `evaluated` date, to the day the figures are
  read. Both ends are included, in UTC by event timestamp.
- **Evaluation.** A distinct (`koto.session.id`, `koto.visit.seq`,
  `koto.check`, `koto.rule.id`) tuple with at least one `decider_checked` or
  `decider_fallback` event in the window, filtered to the entry's gate and
  criterion. koto writes a fallback again each time a held visit is ticked;
  those fall in the same tuple and count once.
- **Answered.** An evaluation any of whose `decider_checked` events has
  `koto.decider.outcome` `pass` or `fail`. A tuple with only fallbacks, or
  only other outcomes, is unanswered. An agent's own answer
  (`decider_check_answered`) never makes it answered.
- **Sessions.** The distinct `koto.session.id` values among the evaluations.
- **Over-budget fallbacks.** Evaluations with a `decider_fallback` whose
  `koto.decider.reason` is `over_budget`.
- **Largest input.** The largest `koto.decider.input_bytes` on either event.

As queries over the exported events, for one criterion:

1. Filter to event type `decider_checked` or `decider_fallback`, with
   `koto.check` equal to the entry's `check.gate` and `koto.rule.id` equal to
   its `check.criterion`, inside the window.
2. Count distinct (`koto.session.id`, `koto.visit.seq`) pairs: the
   evaluations. The filter has already fixed `koto.check` and
   `koto.rule.id`, so a pair here is the full tuple above.
3. Count distinct `koto.session.id`: the sessions.
4. Among `decider_checked` events with `koto.decider.outcome` in (`pass`,
   `fail`), count distinct (`koto.session.id`, `koto.visit.seq`) pairs: the
   answered evaluations.
5. Among `decider_fallback` events with `koto.decider.reason` `over_budget`,
   count distinct pairs: the over-budget fallbacks.
6. Take the maximum `koto.decider.input_bytes`.

The bar is met with at least 30 evaluations across at least 5 sessions, at
least 95% of them answered, no over-budget fallback, and no input over the
entry's `budget`.

`jev_criteria.py figures` computes the same figures from local koto session
logs and prints the `live` JSON a promotion records:

```bash
python3 scripts/jev-criteria/jev_criteria.py figures <rule-id> --sessions <koto sessions directory> [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--bar]
```

Without `--from` and `--to` it uses the window above. It skips and counts any
line it can't read. It is a tested reference for the definitions: use it to
check a query, and to see what a promotion's `live` record looks like. The
figures a promotion records are the ones read from the exported events.

## Promoting a criterion

A criterion can be promoted once it is `untrusted` (declared in a template,
its slice measured within budget, a fixture file in place), its template
declares it in `veto` mode, and both bars are met.

1. **Run the fixtures.** With a decider key in `KOTO_DECIDER_API_KEY`:

   ```bash
   python3 scripts/jev-criteria/jev_criteria.py fixtures <rule-id>
   ```

   It sends every case to Jev under the template's declaration and prints the
   counts and a `fixture_run` record. Exit 0 means the fixture bar is met: no
   seeded-bad or adversarial case answered `pass`, at least 80% of good cases
   answered `pass`, and no case without an answer. The key is only ever sent
   to an https endpoint; a loopback endpoint (a local stub) gets a placeholder.
2. **Read the live figures** as above, and check they meet the bar.
3. **Edit the entry** in `references/rule-registry.json`:
   - `jev.state` to `trusted`, and the rule's `withhold` to `eligible`;
   - `jev.promotion`: `trusted_since` (the window's end date), the
     `fixture_run` record as printed, the `live` figures with `from` and `to`,
     and `slice_script_blob`, the git blob hash of the slice script as
     committed (`git hash-object --no-filters -- <slice script>`).
4. **Open the pull request.** CI runs `jev_criteria.py check`, which refuses
   the change when a field is missing, the fixture counts don't add up to the
   fixture file, either bar isn't met, the live window starts on or before a
   recorded false pass or before `declared.since`, `trusted_since` isn't the
   window's end, the declaration, slice script or fixture file changed since
   the figures were taken, the template mode isn't `veto`, or the rule isn't
   `withhold: eligible`.
5. **Review.** The reviewer re-runs the queries over the exported events for
   the same window, and `fixtures` against the same fixture file, and compares
   the results with the record. `figures --bar` over session logs the reviewer
   holds is a cross-check on the queries, not a substitute: it sees only the
   runs on that machine. The author doesn't merge their own promotion.

Promotion makes the rule eligible to be withheld; it doesn't wire anything.
`scripts/jev-withhold.sh` decides at run time whether a session leaves the
rule out, and a template calls it only in a later, separately reviewed change
that `check` holds to the rules in `references/jev-criteria.md`.

## Demoting a criterion

A confirmed false pass is an evaluation the decider answered `pass` where an
oracle showed the slice broke the criterion: a review-panel finding at the
same head that the run then fixed (`review`), a failing check at that head
(`ci`), or a person's report (`human`, the only oracle for a session with no
commit to name).

1. **Record the false pass** on the entry's `jev.false_passes`: `evaluated`
   (the evaluation's date), `recorded` (today), `oracle` and `evidence`, a
   `https://github.com/` link to the pull request and finding, the check run,
   or the issue or comment.
2. **If the criterion is `trusted`, demote it** in the same change: set
   `jev.state` to `untrusted`, remove `jev.promotion`, and set the rule's
   `withhold` to `never`.
3. **Open the pull request.** CI refuses a false pass missing a field, and,
   against the base, any change that removes or edits a false pass already
   recorded. Reviewers confirm the false pass by merging.

A false pass can be recorded on an `untrusted` criterion too. Either way it
moves the start of any later live window to the day after its evaluation, so
a later promotion needs fresh figures.
