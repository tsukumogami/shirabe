# koto facts for this design, probed rather than assumed

Version under test: `koto 0.11.5 (386af8d 2026-08-16T17:34:42Z)` — the released
build tsuku installs and the one CI gets through the project tool manifest.

## `koto context remove`

| Case | Result |
|---|---|
| Remove a present key | exit 0; the `context-exists` gate then holds the state on `passed` |
| The failure edge with the gate failing | still reachable — no gate reference on it |
| Remove a key never written | exit 0 (idempotent) |
| Remove with the ctx directory unwritable | **exit 3**, error JSON on **stdout**, key still present |
| `context exists` after a successful remove | exit 1 |

## The finding that shapes the design

**A failed removal is silently fatal.** With the ctx directory unwritable the
removal exits 3 and the key survives, and submitting the phase's `passed`
outcome then advances the workflow on the stale artifact. Verified directly: the
probe's case D advances to the terminal state after a failed removal. So the
step needs a check, exactly as the overwrite-based predecessor did.

## Why the check is better here than it was before

`koto context exists` calls `store.ctx_exists(session, key)`. The
`context-exists` gate evaluator calls `store.ctx_exists(sess, &gate.key)`
(`src/gate.rs:135`). **They are the same function.** So `context exists`
returning 1 is not a proxy for "the gate will fail" — it is the gate's own
predicate, evaluated the same way against the same state.

That is a materially stronger position than the mechanism this design replaces.
The overwrite-based predecessor verified with a string comparison while the gate
evaluated a regex: two different operations over the same value, which is
precisely what created the drift hazard where a sentinel and a pattern could
wander into agreement and the gate would start accepting cleared values. With
one predicate there is nothing to drift.

Consequences for the design:

- The post-check is `koto context exists <WF> <KEY>`, required to exit 1.
- No sentinel value is introduced, so nothing has to be kept in sync with a
  pattern, and the artifact namespace gains no vocabulary.
- `remove`'s own exit status is a useful signal but not the authority. Its
  implementation removes the content file, then the lock file, then updates the
  manifest under lock; a failure after the content file is gone would exit
  non-zero on a removal whose gate-relevant effect had already landed. The
  effect is what matters, so the effect is what is checked.

## The ambiguity that does not bite here

`ctx_exists` collapses "absent" and "unreadable" into `false` in both backends
(local via `Path::exists()`, cloud via `unwrap_or(false)`). That is a real trap
in general — a guard treating exit 1 as "safe to skip" will skip a key that is
really there — and it is documented in koto's own `koto-user` skill.

It does not bite this design, because the collapse runs in the safe direction
here: if the store is unreadable, `exists` reports absent AND the gate reports
absent, so the phase refuses to advance. The two agree because they are the same
call. The trap only bites a caller that uses `exists` to decide whether to *skip*
work; this design uses it to confirm work took.

## `context_assignments:` is still a no-op

koto's `Transition` struct carries `target` and `when` only; a
`context_assignments:` block is dropped at compile time and the store is empty
after a transition carrying one fires. Every `failure_reason` assignment in
`work-on.md` therefore does nothing. Unchanged by v0.11.5, out of scope here,
recorded so the design does not build on it.
