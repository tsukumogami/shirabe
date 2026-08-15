# Validation: Alternative 3 — Graded workspace policy

I was assigned to argue for the decider's frontrunner and told not to
rubber-stamp it. I attacked it first, and it did not survive in the form it was
drafted. It survives in a narrower form, and the narrowing is not cosmetic: the
part of Alternative 3 that earns its place is the **predicate used as a
detector**, and the parts that do not are the **policy surface** and the **`gate`
rung**. My verdict is adopt-with-conditions, where the conditions remove roughly
half the drafted alternative.

I also have to correct one claim in my own brief. The koto lead did not dissolve
Alternative 3's implementation gap. It dissolved one half of it and left the
half that carries all the risk. Details in Weakness 2, because everything else
depends on it.

## Strengths

**It is the only alternative that satisfies constraint 4.** Detection must not
depend on agent self-report. Both incidents surfaced only because the user asked,
and in the second the agent let an inaccurate earlier answer stand. Alternative 1
has no observation leg at all — it raises the odds and then goes quiet.
Alternative 5's leg is explicitly a self-report. Alternative 4 has none. And
Alternative 2's leg, which looked like the shipped answer, is now known to be
**impossible today**: the koto lead read `pr_finalization` line by line and found
the PR body carries no session id, no template hash, no marker of any kind, while
the `wip/` state projection is `git rm`ed before the PR flips ready. A CI check
literally cannot distinguish a koto-driven PR from a hand-rolled one. So the
field is not "3 versus the cheaper 2" on this axis. On the hard constraint that
matters most, 2 is not in the running without an `R9` amendment and a new PR
trailer.

**The predicate is real, verified, and cheap.** Roughly 25 lines of bash, no koto
dependency, no network, tested against three live sessions, and forensically
confirmed against incident 2 — the incident workspace's project directory
contains no `workflows/` directory at all. It reads a record koto writes on every
state commit by self-discovering `CLAUDE_CODE_SESSION_ID`, which means the agent
does not choose to produce it. It is repo-scoped and it survives the cleanup that
deletes `~/.koto/sessions/<id>/` on success. That last property matters more than
it sounds: the obvious naive check inverts the signal for every successful run,
and this one does not.

**One condition, three lifecycle events.** Stop for reporting, UserPromptSubmit
for reminding, PreToolUse for gating are the same predicate read at three
moments. That is a genuine argument for a graded level over three unrelated
mechanisms, and it makes "guidance now, enforcement later" a change of rung
rather than a redesign — which is exactly what the user asked to have mapped.

**Nothing has to be invented to distribute it.** `shirabe pr-body-hook` is a
shipped, niwa-injected, shirabe-plugin-gated PreToolUse allow/deny hook with a
fail-safe fallback and an off switch. `work-summary absence` is a shipped
UserPromptSubmit injection. `appendToWorkspaceRulesFile` is the shipped path for
a generated CLAUDE.md fragment that reaches sub-repo sessions. The niwa-declares
/ shirabe-decides split is established practice, not a proposal.

## Weaknesses

**1. The comparison table credits `gate` and the recommendation ships `remind`.**
This is the most important thing in this report. The table's bold **Yes / Yes**
for catching both incidents is true of the PreToolUse deny rung. It is not true
of `remind`, which is a nudge, and a nudge is a probability play with the same
honest scoring Alternative 1 gets. The recommendation therefore argues from one
rung's properties and ships a different rung's. Read strictly, "ship at `remind`"
and "the only mechanism that catches both incidents" cannot both be the
justification for the same release.

My answer, and it is a real one rather than a save: at ship time the value is not
the reminder, it is the **detector**. `remind` and detect ride the same predicate,
and the detector is what converts "surfaced only because the user asked" into
"surfaced automatically." That is a hard constraint, not a nice-to-have, and it
is the thing Alternative 1 cannot buy at any price. So `remind` is *not*
Alternative 1 with more machinery — but only if the detector ships with it. If
the release is the reminder alone, the assignment's question is conceded: it
would be Alternative 1 with a config file attached and a worse cost profile.

Two secondary points on the reminder itself, one for and one against. For:
UserPromptSubmit fires per turn and its content is *conditional on current
observed state*, where a SessionStart banner is unconditional and decays —
and shirabe's own doctrine (`DESIGN-execute-skill.md:227`) concluded that
entry-time instruction decays and binding should happen at every tick. Against:
UserPromptSubmit fires per **user prompt**, not per agent tick. In an autonomous
dispatched worker under `bypassPermissions` the number of user prompts approaches
one. So on the dispatch path — half the requirement per constraint 3 — `remind`
degenerates to a single turn-1 injection and its per-tick advantage over
SessionStart evaporates entirely. The rung is meaningfully better than a banner
in an interactive session and roughly equivalent to one in a dispatched session.

**2. The implementation gap moved; it did not close.** The predicate as stated in
the alternative is a conjunction: *a plan is in play* **and** *no koto session is
bound to it*. The koto lead confirmed the right conjunct, session-exactly, with
no plan path needed. The left conjunct is untouched. Applied blind, "does a koto
record exist for my session over the execute/work-on template" answers NO-KOTO
for every session on the machine that is not running koto — a session answering a
question, fixing a typo, writing a doc. All of them. So the gap did not dissolve;
it migrated from "which plan is in play" to "is plan-scale work in play at all,"
and the entire false-positive blast radius lives in the half that migrated. My
brief told me this was resolved. It is not, and the alternative should not be
scored as though it were.

The left conjunct is solvable — a UserPromptSubmit hook that sees a plan-doc path
or an execute-shaped instruction could stash a session-scoped marker the
PreToolUse hook later reads; or the hook could grep the transcript it is handed.
Neither is confirmed, neither is free, and the stateful marker adds a second
thing that can be stale or missing. This is a design question, not a patch.

**3. The `gate` rung is simultaneously too blunt and too porous.** Blunt: a wrong
deny under `bypassPermissions` has no appeal — `ask` is disqualified by
constraint 2 — so the agent either self-corrects, thrashes against a repeated
deny until its budget is gone, or does the worst thing available, which is
running `koto init` for a plan it is not executing and binding itself to a
hash-locked template it will not follow. Porous: a gate matching Edit/Write is
bypassed by a Bash heredoc, and matching Bash puts you squarely in the footgun
niwa already documented at `materialize.go:592-603`, where a non-zero exit blocks
every call and a stale binary bricks the session. The mandated fail-open posture
means the gate's own failure mode is "allow," so its reliability ceiling is its
happy path.

**4. The predicate is satisfiable by ritual.** This is the deepest objection and
it comes straight from the koto lead's own finding. Koto's guarantees are
bookkeeping: the substrate-spawn primitive is a logging stub, and review gates,
CI monitoring, and PR finalization are directive text koto never verifies. So a
deny that forces `koto init` buys a record. An agent can `koto init`, satisfy the
predicate permanently, and then implement all six issues inline exactly as
incident 2 did — and the gate falls silent, because the record now exists. A gate
around a token teaches ritual compliance, and it teaches it to the one actor
sophisticated enough to notice.

In fairness, forcing entry is not *purely* a record. The state machine's ordered
transitions, template hash lock, and command gates (which koto runs itself and
records the exit code of, `worktree_discipline_check` among them) are real
enforcement. But the agent only gets those by continuing to drive the loop, and
continuing is precisely what incident 2 declined to do after getting *further*
than the gate would have pushed it.

**5. Two independent silent-no-op paths.** Unknown TOML fields warn and continue
(`config.go:545-547`), so an older niwa ignores a declared mandate. And the
injected command must swallow non-zero, so an older `shirabe` lacking the
subcommand fails open. A declared policy can therefore do nothing, twice over,
without anyone noticing. For a setting whose entire purpose is to change
behavior, silent-ignore is the wrong failure mode, and it is worse here than for
the env-var policies the design is modeled on.

**6. n = 2.** Both incidents are from one user, one machine, one month. Building
a configurable org-wide policy surface on that is a proportionality question that
the alternatives file does not raise. It also has a clean answer, which I put in
the conditions: the detector is what turns n=2 into a measured rate, and you
cannot responsibly choose an enforcement level without a base rate.

## Risks

The hot-path cost is real: a `find` over `~/.claude/projects` on every Edit, on a
machine carrying 1,210 koto session directories and 65 workflow records, is a
per-edit latency tax that needs memoization — write a sentinel once the check
passes for a session and short-circuit thereafter.

The duplicate-project-dir behavior is reproduced, not theorized: one Claude Code
session id can appear under two encoded project dirs when cwd changes mid-session,
and the copies disagree. Worktree entry is exactly such a change, and this
workspace mandates worktrees for background jobs. A checker that takes the first
match instead of the freshest by mtime will deny work in the isolation setup the
harness itself requires.

The predicate depends on a third tool's user-settable default. `workflows.native
= true` is koto configuration. Set it false and the record stops being written,
the predicate reads NO-KOTO forever, and a `gate` denies everything. A gate whose
condition can be silently inverted by a toggle in an unrelated tool's config is
fragile in a way that no amount of shirabe-side care fixes.

Coupling and release ordering: niwa cannot usefully inject a hook calling a
`shirabe` subcommand that does not exist yet, and the fail-open guard hides the
mismatch rather than reporting it.

Finally, whether hooks fire in subagent contexts is still open
(`lead-hook-surfaces` unlanded). It does not change the ranking — the predicate
is evaluated on the main session's tool calls either way — but it does bound how
much of the `/work-on` child layer any of this can see.

## Conditions under which this is the right choice

It is right if detection-without-self-report is treated as the hard constraint it
is written as, because on that axis nothing else in the field is standing.

It is right if the org-owner configurability requirement is genuine rather than
an aside, since 3 is the only alternative that offers it at all.

It is right if somebody will actually read the detector's output. A detector
nobody looks at is worse than no detector, because it manufactures the feeling of
coverage.

And it is right only once the left conjunct has a definition that does not fire
on ordinary sessions. Until then the mechanism has no safe trigger, at any rung.

On the tombstone question specifically, I do not think it should veto the
org-owner placement, and I think the research already contains the reason. An
overlay **can already install an executable PreToolUse gate today** through
`[claude.hooks]`, whose scripts land in `.claude/hooks/` unimpeded, even though
`isProtectedDestination` blocks the `[files]` route. So treating the tombstone as
a veto on `[claude.skills]` would block the declarative, inspectable,
off-switchable path while leaving the imperative, opaque path wide open. That is
strictly worse for the value the tombstone protects.

The principled resolution is to make **readability the requirement rather than
placement**. Every rung above `off` must emit its declaration into generated
context the contributor can read in the instance they are working in, and every
reminder or deny message must name the config that declared it. The rungs are
already drafted cumulatively — `remind` is advertise-plus, `gate` is
remind-plus — so this promotes an existing property to an invariant. The *source*
of the policy stays private; its *text and effect* are visible where the
contributor is. That satisfies what `config.go:312-320` is actually protecting,
which is un-auditable behavior change, not private authorship.

## Recommendation

**Adopt with conditions**, where the conditions remove the policy surface and the
`gate` rung from the first release.

1. **Ship the predicate as a detector first.** A `shirabe` subcommand plus a Stop
   hook that reports "no koto record for this session over execute/work-on." This
   is the load-bearing deliverable, it is the only thing in the field that
   satisfies constraint 4, and it is roughly 25 lines of verified bash. If only
   one thing ships, it is this.

2. **Ship `remind` alongside it, and sell it honestly as a probability play.**
   Its advantage over a SessionStart banner is that it is conditional on observed
   state and re-fires interactively; it has essentially no advantage on the
   dispatch path, and the recommendation should say so.

3. **Do not build `[claude.skills]` yet.** Ship default-on-with-off-switch on the
   existing `work_summary_hooks` / `pr_body_hook` pattern, which needs no new TOML,
   no `ClaudeOverride` field, no `OverlayClaudeConfig` merge logic, and no
   answer to the placement question at all. Add the configuration surface when
   there is a second policy to configure, or when a real repo needs a different
   level. Shirabe has never shipped a policy surface, and the first one should
   not be speculative.

4. **Do not commit to `gate` as the promotion target.** `P5: Strictness tracks
   blast radius` is cited in support of staging toward it; read straight, it
   points the other way. The blast radius of the *loss* is a visibility and
   bookkeeping gap — in both incidents the work got done, correctly. The blast
   radius of the *gate misfiring* is a headless agent bricked mid-run with no
   appeal. The intervention's radius exceeds the loss's radius, and P5 licenses
   `remind` and forbids `gate` at current evidence. Revisit only if the detector
   shows a rate that justifies it and the koto record has become load-bearing for
   something that actually enforces.

5. **Define the left conjunct before anything fires automatically**, and pick one
   mechanism for it rather than listing candidates.

6. **Engineering guards, non-negotiable:** fail open, memoize per session,
   redirect stderr, scan all project dirs and take the freshest by mtime, and
   detect `workflows.native = false` as "cannot evaluate" rather than as a
   negative.

So constructed, this remains the best answer in the field — not because it is the
strongest push, but because it is the only one that can *see*. What I cannot
defend is the version in the alternatives file: a new configuration system and a
deny gate, justified by a predicate whose trigger half is undefined, protecting a
record that the agent can produce in one line without changing anything it does.
