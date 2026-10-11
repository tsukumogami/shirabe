# Phase 5: Competitive Analysis

Route to `/comp`. `/explore` writes no competitive analysis of its own.

`/comp` owns `docs/competitive/COMP-<topic>.md` and drives a six-phase workflow,
a three-reviewer jury, and the lifecycle transition to Accepted. The inline
handler this arm replaces wrote a Draft at the same path with none of that, so
the two producers disagreed about what a finished COMP is.

This arm is reachable only in a private repo. Crystallize evaluates visibility
as a candidacy precondition and removes the category outright under public
visibility, so the refusal the old handler carried has no run to fire on. If you
reached this file in a public repo, the precondition was skipped — go back to
key `work/crystallize.md` and read the Candidacy section rather than
producing anything here.

**What the arm passes:** the topic slug. `/comp` takes `<topic-slug>` and an
optional `--upstream <path>`; the exploration's research stays readable in
`explore-<topic>` (`koto context get explore-<topic> research/<name>`), which
stays open until `/comp` returns.

Invoke `/comp <topic>`. It runs its own Phase 0 visibility detection, scopes the
competitive question with the author, and produces the document.

When `/comp` returns, close the session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close explore-<topic> done
```

## Artifact State

After this step:
- No document written by `/explore`
- Session `explore-<topic>` closed after `/comp` returned; its keys stay readable
