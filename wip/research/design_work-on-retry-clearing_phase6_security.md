# Security review: DESIGN-work-on-retry-clearing.md (Phase 6, security focus)

All claims below were checked against real koto (`/home/dgazineu/.tsuku/tools/current/koto`)
run inside an isolated `$HOME` (`/tmp/koto_sec_test/home`) driven by shell scripts
written to disk and executed with `bash script.sh` (never inline `HOME=...` on a
command line). A minimal template (`/tmp/koto_sec_test/tmpl.yaml`) reproduces the
one gate shape under test: a `context-matches` gate with the exact pattern from
the design, `key: results.json`, referenced from a `passed` transition and not
from a `blocking_retry` transition — structurally identical to the three panel
gates the design converts.

## 1. The emitted shell block

```bash
CLEARED='{"cleared": true, "superseded_by": "blocking_retry"}'
for KEY in scrutiny_results.json review_results.json qa_results.json; do
  koto context exists <WF> "$KEY" >/dev/null 2>&1 || continue
  printf '%s' "$CLEARED" | koto context add <WF> "$KEY" 2>/dev/null
  BACK=$(koto context get <WF> "$KEY" 2>/dev/null)
  if [ "$BACK" != "$CLEARED" ]; then
    echo "$KEY NOT cleared: read back [$BACK]"
    echo "do NOT submit a passed outcome on the next pass -- the previous round's verdict is still in place"
    exit 1
  fi
done
koto next <WF> --with-data '{"scrutiny_outcome": "blocking_retry"}'
```

- `"$KEY"` is quoted at every one of its three uses (`exists`, `add`, `get`).
  The loop's word list is a fixed three-token literal with no shell
  metacharacters, so there is no word-splitting or glob-expansion hazard even
  unquoted, but it is quoted anyway.
- `"$BACK"` and `"$CLEARED"` are quoted on both sides of `[ "$BACK" != "$CLEARED" ]`.
  Neither operand can be misread as a test-primary flag (`-n`, `-z`, etc.)
  because both are quoted; this holds regardless of content.
- `printf '%s' "$CLEARED"` is correct: `%s` is the *format*, `$CLEARED` is the
  *argument*, so even if `$CLEARED` contained `%` characters they would not be
  interpreted as format directives (unlike the classic `printf "$VAR"` bug,
  which this is not). Verified no trailing newline is emitted, and separately
  verified command substitution (`$(...)`) strips trailing newlines regardless,
  so a hypothetical trailing newline in the stored value would not have caused
  a false mismatch either way.
- `$BACK` is never used as a bare command-line word — only inside a quoted
  `[ ... ]` comparison and inside a double-quoted `echo "...[$BACK]"` string.
  There is no path from an arbitrary read-back value to an unquoted shell word,
  hence no injection vector through this variable.
- `<WF>` is unquoted in the shown block, but this is the pre-existing
  documentation convention used identically by every other koto command in
  these phase files (verified in `phase-4a-scrutiny.md` lines 35/38/45, e.g.
  `koto context add <WF> scrutiny_results.json`). The design does not change
  this convention and does not introduce a new untrusted source for it — the
  workflow name is agent-derived from a slug (`issue_<N>` / `task_<slug>`) the
  same way it already is on every existing line. Not a regression introduced
  by this design.
- The sentinel and key list are literals in the phase files; nothing
  interpolates caller- or issue-controlled content into these commands. No
  injection path was found.

**Verdict on this section: correct as claimed.** Quoting is sound everywhere
it matters, and `printf '%s'` does exactly what the design says.

One incidental finding, not a defect: koto's own `context add` error JSON
(e.g. `{"command":"context add","error":"failed to write content file: ..."}`)
is written to **stdout**, not stderr, verified by separating the two streams
under a `chmod 0444` write-failure. This is consistent with, and reinforces,
the design's reliance on stdout for diagnostics — it is not something the
design needs to account for, just a confirming observation.

## 2. The regex

Pattern: `(?s)^\{.*"passed" *: *true.*\}\s*$`, evaluated via `Regex::is_match`.

Verified directly against real koto (values below all piped through
`koto context add` then evaluated via the compiled gate):

| input | gate result | expected |
|---|---|---|
| `{"cleared": true, "superseded_by": "blocking_retry"}` (the actual CLEARED sentinel) | no match | no match — confirmed |
| `{"cleared": true, "note": "prev had \"passed\": true here"}` (escaped token inside a string) | no match | no match — confirmed (the literal backslash before/after the embedded quotes breaks the exact `"passed"` substring) |
| `{"passed": true, "scenarios_run": 3, "scenarios_passed": 3}` (real qa shape) | match | match — confirmed |
| `{"passed": true, "round": 1}\n` (trailing newline, heredoc-style) | match | match — confirmed, `\s*$` tolerance works |
| `x{"passed": true}` (leading garbage) | no match | no match — confirmed, `^\{` anchor holds |
| `{"passed": true}junk` (trailing garbage) | no match | no match — confirmed, `\}\s*$` anchor holds |

`(?s)` enables DOTALL only; it does not enable multi-line mode, so `^`/`$`
anchor to the whole-string start/end (not line boundaries), which is what
makes the anchoring real rather than cosmetic. No case was found where a
value that should be rejected still matches, including the specific
adversarial case the rubric asked about (a cleared sentinel containing the
token). **The regex claims in the design are accurate.**

## 3. Fail-open vs fail-closed — the central finding

The design's Security Considerations section states unconditionally: *"The
failure mode is fail-closed. With the store unreadable the gate reports
`matches: false`... the run cannot advance past a phase carrying a stale
verdict."*

This is **true of the gate in isolation**, verified directly:

- Key absent: `matches: false` (fail-closed).
- Key present but ctx directory `chmod 0000` (simulated unreadable store) at
  gate-evaluation time: `matches: false` (fail-closed).
- Malformed/truncated JSON in the key: `matches: false` (fail-closed, the
  anchors simply don't match).
- `chmod 0444` on the key file so `koto context add` cannot overwrite it: the
  write fails (`exit 3`, error JSON on stdout as noted above), but the
  read-back (`BACK`) still returns the **old** value, so `BACK != CLEARED`,
  the block prints the diagnostic and exits 1 before ever calling `koto next`
  — so the transition to `blocking_retry`/`implementation` never fires and the
  run simply sits where it is. This exact scenario (from the design's own
  "Case 0 injection" test plan, `chmod 0444` on the key file) was reproduced
  and behaves exactly as claimed.

**It is not true of the combined invalidation-then-gate mechanism under a
transient store failure**, which is the scenario the rubric asked to be
tested. The retry-clearing block's per-key guard is:

```bash
koto context exists <WF> "$KEY" >/dev/null 2>&1 || continue
```

Verified against real koto: `koto context exists` returns **exit 1 with no
distinguishing stderr** both when a key genuinely was never written *and*
when the key exists but the store is transiently unreadable (ctx directory
`chmod 0000`). `koto context get` was also checked as a possible
disambiguator and has the same problem: on a genuinely-absent key it returns
exit 3 with `{"command":"context get","error":"failed to read context key
'results.json' for session '...': .../ctx/results.json"}`, and on an
unreadable-but-present key it returns **exit 3 with the identical message**
(no OS-level errno text, no distinct wording). koto's CLI surface currently
gives the shell script no way to tell "never written" apart from "read
failed."

Consequence, reproduced end to end: if the ctx directory is unreadable only
during the `exists` check for one key (a transient permission blip, a lock
file contention window — koto does hold a `<key>.lock` per context key, seen
directly in the session directory — or any short-lived I/O hiccup) and
becomes readable again before the phase is re-entered, the loop's `|| continue`
treats that key exactly like "never written," silently skips clearing it, and
proceeds to submit `blocking_retry` for the other keys. The untouched key
still holds **the real previous-round `"passed": true` verdict** (not a
sentinel). When the run later re-enters that phase, the gate re-evaluates
against that still-present real verdict and reports `matches: true` — the
exact stale-pass-through defect this design exists to close, reopened through
the one failure path the Security Considerations section claims is closed.

This was demonstrated directly:
1. Write a real `{"passed": true, "round": 1}` value.
2. `chmod 0000` the ctx directory, run the guard — `exists` reports "false",
   block takes the `continue` path exactly as it would for a genuinely absent
   key.
3. `chmod 0755` the ctx directory back (simulating the transient condition
   clearing).
4. `koto context get` shows the original `{"passed": true, "round": 1}` is
   still there, untouched.
5. `koto next ... --with-data '{"outcome":"passed"}'` against the gate:
   `"advanced":true` — the stale verdict is silently accepted.

This is narrower than a persistent outage (it requires the unreadable window
to land on the `exists` check specifically and resolve before the next gate
evaluation, plausibly minutes later given `implementation` runs in between),
but it is real, reproducible, not merely theoretical, and it directly
contradicts an unconditional claim in the section the rubric asked to be
verified. The design already has a precedent for naming exactly this kind of
qualification (the `koto overrides record` residual, see below) — this
deserves the same treatment rather than the current unqualified "fail-closed"
statement.

## 4. The `koto overrides record` residual

Verified directly: on a gate with **no `override_default` declared** (as is
now the case for all three panel gates per this design, which explicitly
drops `override_default:`), `koto overrides record <WF> --gate results_ok
--rationale "..."` returned `{"status":"recorded"}` (exit 0), and the
subsequent `koto next` advanced past the still-failing gate to the next state
without ever satisfying the underlying `context-matches` condition. Confirmed
`koto overrides list` reflects the override with `override_applied: {"matches":
true}`, i.e. the override is recorded and later visible while the session is
active. The design's Known-Limitation claim — that `override_default`'s
presence or absence has no bearing on whether `koto overrides record` can be
used to advance — **is true, verified**.

## 5. Other observations (not blocking)

- Overrides are recorded into the session's own state; a session that reaches
  a terminal state and is cleaned up (default behavior, no `--no-cleanup`)
  loses its `koto overrides list` visibility along with the rest of the
  session directory (`no state file found for workflow`). The design's claim
  that the override is "auditable through `koto overrides list`" is true
  during the run but doesn't address whether that audit trail survives past
  workflow completion; this is a pre-existing property of `koto overrides`
  generally (not something this design changes) and arguably out of this
  design's scope, but it's adjacent to the residual risk paragraph and worth
  the author knowing about.
- The partial-loop-failure case (one key clears, the next key's write fails)
  is handled correctly: `exit 1` fires before `koto next` is ever called, so
  no transition happens and the run stays in place. This is the fail-closed
  path and it works as designed. It's a different code path from the finding
  above (`|| continue`, not the `BACK != CLEARED` branch).
