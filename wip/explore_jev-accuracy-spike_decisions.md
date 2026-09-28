# Exploration Decisions: jev-accuracy-spike

## Round 1

- Test six criteria, drop "a scrutiny finding is resolved by a given diff": no scrutiny finding text survives in any public artifact, so fixtures and labels would both be invented, and inputs would be whole diffs.
- Keep "hedge language with no approved deferral" with a per-fixture approved-deferrals input: the rule can't be judged from the text alone; the report will say it tests list-matching.
- Ask each criterion as a koto-shaped boolean `noul` question at threshold 0.9 as the primary measure, with a three-way `choice` variant as a second run: that's what a decider declaration would send.
- One question per request (unbatched): each fixture carries one criterion, and Jev's docs say batching doesn't change per-question scoring; the report records it.
- 12 good, 22 seeded-bad, 6 adversarial fixtures per criterion: clears the bar's minimums (20 and 5) with slack and gives a false-fail sample.
- Network calls to the Jev API stay off until the human rules on the workspace's network gate; the harness defaults to offline and is proven on stub and replay.
- One round is enough: the remaining gap is live data, which more research can't close.
