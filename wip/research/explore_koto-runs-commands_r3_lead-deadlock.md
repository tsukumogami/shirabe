# Lead: How exposed is shirabe to koto's 64KB output deadlock today, and what does fixing it cost?

## Findings

### 1. The mechanism, confirmed in source

`run_shell_command` in `koto/src/action.rs:26-107` is the single shared path for both gate evaluation and default-action execution. The sequence is exactly the reported defect:

```rust
// src/action.rs:33-38
let mut cmd = Command::new("sh");
cmd.arg("-c").arg(command).current_dir(working_dir)
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());
...
// src/action.rs:60
match child.wait_timeout(timeout) {
    Ok(Some(status)) => {
        // src/action.rs:62-79 -- pipes are read ONLY here, after wait returns
        let stdout = child.stdout.take().map(|mut s| { ... read_to_string(&mut s, &mut buf) ... });
        let stderr = child.stderr.take().map(|mut s| { ... read_to_string(&mut s, &mut buf) ... });
```

Nothing reads the pipes while `wait_timeout` is blocked. A child that writes past the kernel pipe buffer (64KB on Linux) blocks on `write()`, never exits, `wait_timeout` returns `Ok(None)` at the deadline, and `src/action.rs:86-99` kills the process group and returns `exit_code: -1, stdout: "", stderr: "command timed out..."` — the full output is discarded, not truncated.

The **64KB truncation constant lives in a completely different place**: `MAX_ACTION_OUTPUT_BYTES = 64 * 1024` at `src/cli/mod.rs:61`, applied only to the default-action path via `truncate_output()` at `src/cli/mod.rs:4025-4026`, *after* `run_shell_command` has already returned. It has nothing to do with the pipe-buffer deadlock — it's coincidentally the same size, which makes the symptom read like "truncation broke," when actually truncation never got a chance to run. **Gate evaluation (`gate.rs`) doesn't even call `truncate_output` at all** — `evaluate_command_gate` (`src/gate.rs:206-230`) never touches `output.stdout`, only `exit_code` and `stderr` (to distinguish timeout from a spawn error at line 211). So a gate's stdout is thrown away today regardless of the deadlock; only the deadlock's stderr/exit-code corruption is visible to gates.

Grepping `src/` confirms `run_shell_command` is the *only* piped-and-waited child process in the non-test codebase: `Stdio::piped()` appears twice more, at `src/session/local.rs:1814-1815`, but that's a test harness spawning koto's own test binary and reading its stdout line-by-line with `BufRead::read_line` *while the child runs* (`src/session/local.rs:1822-1830`) — no `wait_timeout`, no deadlock shape. Batch child spawning (`src/cli/batch.rs`) doesn't shell out via `Command` at all — no `Stdio`/`Command::new` hits there. So the exposure is fully bounded to `run_shell_command`'s two callers: `gate.rs:207` (gate evaluation) and `cli/mod.rs:1022` / `cli/mod.rs:4021` (the polling loop and default-action execution, respectively — same function, same bug, both call sites).

### 2. Sweep of all 11 `type: command` gates

8 in `work-on.md`, 3 in `execute.md`:

| Gate | Command | Stdout path | Realistic volume | Exposure |
|---|---|---|---|---|
| `on_feature_branch` (×3: `setup_issue_backed`, `setup_free_form`, `setup_plan_backed`) | `test "$(git rev-parse --abbrev-ref HEAD)" != "main"` (work-on.md:163,195,293) | `git rev-parse` output is consumed by `$(...)` command substitution *inside* the script; the only thing that reaches the outer `sh -c`'s real stdout is `test`'s own output, which is none | ~0 bytes | Unlikely |
| `on_feature_branch_impl` | same pattern (work-on.md:435) | same | ~0 bytes | Unlikely |
| `has_commits` | `test "$(git log --oneline main..HEAD | wc -l)" -gt 0` (work-on.md:438) | `git log`/`wc` output is captured inside `$(...)`, never reaches outer stdout | ~0 bytes | Unlikely |
| `tests_passing` | `[ ! -f go.mod ] || go test ./... 2>/dev/null` (work-on.md:441) | **Direct** — not wrapped in substitution or a pipe sink. `2>/dev/null` protects stderr only | Measured on the actual `tsuku` monorepo (63 packages, 784 `.go` files): `go test ./... 2>/dev/null \| wc -c` = **3,793 bytes**, ~60 bytes/package. Passing-path output is nowhere near 64KB at this repo's current size — you'd need ~1,000+ packages of clean pass/fail lines to breach it on the happy path. It rises fast the moment tests use `t.Log`/`fmt.Println` (Go buffers per-test output and dumps it in full on any failure) or `-v` is added | **Plausible, not certain** — real measurement lowers this from the initial hypothesis. Certain only for large or verbose/failing suites |
| `staleness_fresh` | `check-staleness.sh --issue {{ISSUE_NUMBER}} \| jq -e '.introspection_recommended == false'` (work-on.md:325) | Piped to `jq -e`, which prints only `true`/`false` (~5 bytes) to the outer stdout; the script's own stdout is consumed by `jq` as stdin, not leaked. The script's **stderr** is not redirected and bypasses the pipe (pipes only join stdout→stdin) | stdout: negligible by construction. stderr: unmeasured (script implementation not in scope for this public-only exploration) | Unlikely on stdout; stderr risk not ruled out |
| `ci_passing` (×2, identical in work-on.md:735 and execute.md:241) | `gh pr checks $(...) --json bucket --jq '...' \| grep -q true` | Final sink is `grep -q`, which prints nothing on match or no-match — stdout is empty by construction regardless of how many checks the PR has | stdout: ~0 bytes always, independent of check count. stderr: `gh pr checks`'s stderr is *not* captured by the pipe (same reasoning as above) and could carry rate-limit/auth warnings, but not proportional to check count | Unlikely |
| `merge_state_clean` | `[ "$(gh pr view --json mergeStateStatus --jq .mergeStateStatus)" != "DIRTY" ]` (execute.md:244) | Captured inside `$(...)`, `[` produces no stdout | ~0 bytes | Unlikely |
| `impact_classified` | `test -f wip/work-on_{{PLAN_SLUG}}_impact.json` (execute.md:109) | `test -f` produces no output | 0 bytes | Unlikely |

Net: of 11 gates, **9 are structurally immune** by shell mechanics alone — command substitution and pipe-to-a-silent-sink (`test`, `grep -q`, `[`) keep the outer process's own stdout at zero regardless of how much the *inner* commands produce, because that inner output never reaches the pipe `run_shell_command` reads. Only `tests_passing` writes directly to the captured stdout, and real measurement on this workspace's own Go monorepo puts it well under the 64KB line today — exposure there is real but conditional on suite size/verbosity, not "certain" as hypothesized going in. `staleness_fresh` and both `ci_passing` gates have an unclosed stderr side-channel (pipe stages don't redirect the upstream command's stderr) that this sweep can rank as low-probability but not rule out, since `gh`/the staleness script's stderr behavior wasn't independently measured.

### 3. Accidental protection

None of the 11 gates has an explicit `2>/dev/null` on the specific subcommand that risks large output *and* whose stdout is the one that's captured — `tests_passing`'s `2>/dev/null` protects `go test`'s stderr (irrelevant to the deadlock since stdout is the risk there), and it's the only redirect present across all 11 commands. The other 8 gates' safety comes entirely from shell composition (substitution/pipe-to-silent-sink) written for other reasons (capturing a value, gating on a grep match), not from any deliberate deadlock mitigation. Nobody has redirected against this defect; the gates that are safe are safe by accident of how their authors happened to compose the shell command.

### 4. Size of the fix

The fix is confined to `koto/src/action.rs`'s `run_shell_command` — neither `gate.rs` nor `cli/mod.rs` needs to change since `CommandOutput`'s shape is unaffected. The standard pattern for this in Rust with `std::process`:

1. `take()` both `child.stdout` and `child.stderr` immediately after spawn (before calling `wait_timeout`).
2. Spawn two `std::thread`s, each draining one pipe into a `String` via `read_to_string` in a loop — this is what actually prevents the pipe buffer from filling.
3. Call `child.wait_timeout(timeout)` on the main thread as today.
4. On `Ok(Some(status))`: join both reader threads (they'll have hit EOF once the child exited) and use their results instead of the current post-wait read.
5. On `Ok(None)` (timeout): kill the process group as today, then join the reader threads — they'll unblock quickly since `killpg` closes the child's fds and the pipes see EOF. Now real partial output (everything the child wrote before it was killed) is available instead of being discarded, though the timeout path is free to keep returning empty output if preserving today's "timeout wins over showing you what leaked out" behavior is preferred.

This is a single-function rewrite, roughly 40-60 changed lines including the added thread-join and error-handling wiring — no dependency change needed (`wait-timeout = "0.2"` in `Cargo.toml:48` stays; `std::thread` needs no new crate). `MAX_ACTION_OUTPUT_BYTES`/`truncate_output` (`cli/mod.rs:61,833`) are untouched and continue to apply post-hoc to the now-always-complete string — truncation is fully preserved, it just finally gets a complete buffer to truncate instead of racing a deadlock.

Test cost: there is **no existing test to update** — `tests/integration_test.rs` (9,003 lines) has no scenario exercising >64KB output or truncation at all; the only related scenario is `gate_timeout_returns_gate_blocked` (`tests/integration_test.rs:2063-2080`, "scenario-36"), which tests a genuine timeout (`sleep 60`, 1s limit), not a large-output false-timeout. The fix should add: one `action.rs` unit test alongside the existing five (`src/action.rs:117-164`) asserting a command that writes >64KB in well under its timeout returns `exit_code: 0` with full output (e.g. `yes x | head -c 100000`), and one or two new integration scenarios — a gate variant (mirroring scenario-36's structure) proving a >64KB-output command gate now passes instead of reporting `timed_out`, and a default-action variant proving output over 64KB is captured and then truncated with the `[output truncated]` marker rather than lost. Total estimated diff: ~100-150 lines across `action.rs` (implementation + unit test) and `tests/integration_test.rs` (1-2 scenarios). Contained and low-risk — no public API or template-facing behavior changes except that timeouts on genuinely-long-running commands now return partial output instead of empty output, which is a behavior improvement, not a breaking one.

### 5. The second, independent defect

`eprintln!("koto: migration skipped {}: session already exists at {}", ...)` lives at `src/session/local.rs:693-696`, inside `migrate_if_needed` (`src/session/local.rs:657-720`), called unconditionally from `LocalBackend::new()` at `src/session/local.rs:43` — i.e. on every session-touching koto invocation. `koto version` never constructs a `LocalBackend`, hence zero lines, matching the given scenario.

The mechanism: the function walks old-layout `base/<repo-id>/<session>` directories left over from a prior flat-namespace migration. For each session name, if `base/<session>` already exists (line 665), it prints the skip line and leaves the stale copy in place (lines 666-671) instead of moving or deleting it. `migrated_count` never increments for these, so `fs::remove_dir(&old_dir)` at line 718 fails silently (directory non-empty) and the same old-layout directory — with the same colliding session names — is rediscovered and re-reported on the *next* invocation too. There is no completion marker and no dedup: this is a permanent, self-repeating cost, not a one-time migration tax, for any install where the same session name was reused across more than one repo (this only breaks in the "collision" case; unique names migrate and vanish cleanly).

**This is already an open, well-documented koto issue: [#193](https://github.com/tsukumogami/koto/issues/193)**, "Session migration never converges: name collisions strand 1000+ sessions and reprint 1091 skip lines on every invocation," filed by the same author who gave this exploration its empirical numbers. It independently reproduces the exact ~100KB-per-invocation shape (1091 lines measured there vs. ~1250-session/~106KB in this lead's brief) and traces the same code path and root cause. It was *not* filed with any connection to the pipe-deadlock defect — its context is a workflow driving `koto` directly from the shell, where 1091 stderr lines are just noise a human or script has to filter (as its predecessor, closed issue #185, describes). Nobody has yet connected #193 to the fact that when a `koto` invocation is nested *inside* a `run_shell_command`-executed gate or default-action script — the scenario this whole exploration is evaluating — that ~100KB of stderr is exactly the payload that trips the 64KB pipe-buffer deadlock in `action.rs` and turns a log-noise annoyance into a silent 30-second false failure. Fixing #193's own recommended remedy (converge the migration, or at minimum summarize instead of enumerate per-session) would incidentally close this compounding path too, since it eliminates the >64KB stderr payload at the source rather than requiring the drain fix to save it.

Cost to fix #193 as scoped there: the issue's own "Expected" section lists three items (converge/cleanup, handle collisions, summarize instead of enumerate) — the third alone (replace the per-session `eprintln!` loop with one summary line, e.g. `koto: migration: N sessions skipped (name collisions)`) is a small, contained change to `migrate_if_needed`, on the order of a dozen lines. The first two (actually resolving collisions or marking completion so the scan doesn't repeat) are larger and involve a real data-safety decision (is it safe to discard/rename the stale duplicate), which is why #193 lists them as separate, higher-cost items rather than folding them into the noise fix.

### 6. Real-world impact so far

No koto or shirabe issue currently describes the pipe-buffer deadlock itself — searches across both repos for "timeout," "timed_out," "deadlock," "pipe buffer," "flaky," and "stall" turned up nothing matching this signature. The closest shirabe hits (`#155`/`#189`, a release-workflow race condition; `#255`, unasserted judgment gates; `#258`, eval-suite quota exhaustion) are unrelated mechanisms. The koto hits for "timeout" are all feature-implementation issues (the gate-timeout feature being built, not a bug in it).

That absence is consistent with the exposure sweep above: 9 of 11 gates can't trigger the deadlock by construction, and the two gates that touch it directly (`tests_passing`, on a 63-package repo) or indirectly (`ci_passing`'s unredirected `gh` stderr) haven't yet produced output large enough in practice, based on this workspace's own measurement. The defect is real and would produce exactly the reported symptom (`{"status":"timed_out",...}` on a command that actually exited 0) the moment either condition changes: a Go suite crosses roughly a thousand packages or starts emitting verbose/failure output, or — the scenario this exploration is actually about — a gate or default-action script starts shelling out to `koto` itself and picks up defect #5's ~100KB stderr tax on an install with enough accumulated sessions. Nothing in the current 11 gates does that today, so the compounding case is prospective, not yet observed, but it's the one this exploration's central question (should koto run these commands via `default_action`) would directly create exposure to.

## Implications

- The deadlock is real and confirmed at the source-code level, but today's actual exposure across shirabe's 11 shipped gates is much narrower than "any gate could hit this" — it's concentrated in one gate (`tests_passing`) whose real-repo measurement came in ~17x under the 64KB line, plus a stderr side-channel on two others that wasn't independently ruled out.
- The fix is genuinely small and localized (one function, ~100-150 lines including new tests), with no template-facing or API-shape changes, and it doesn't touch the already-working 64KB truncation — that stays exactly where it is.
- The second defect is already tracked upstream (#193) with the same author's numbers corroborating this lead's brief. This exploration's contribution is the connection nobody's made yet: that defect's stderr payload is sized to *trigger* the first defect the moment koto commands get nested inside koto-executed shell commands — which is precisely the design question this exploration is evaluating (should `default_action` run these commands itself). That's a concrete argument for sequencing: fix or at least connect #193 before or alongside expanding what `default_action` is trusted to run, since the nesting scenario is the one place in this whole sweep where the deadlock moves from "theoretical" to "self-inflicted and reproducible."

## Surprises

- The 64KB truncation constant (`cli/mod.rs:61`) and the deadlock's ~64KB pipe-buffer trigger size are unrelated numbers that happen to coincide — one is a Linux kernel default, the other is an application-level cap chosen after the fact. That coincidence is what makes the bug read as "truncation is broken" when the real story is "truncation never runs."
- Gate evaluation discards `stdout` entirely regardless of this bug (`gate.rs:206-230` never reads `output.stdout`) — the deadlock's damage to gates is entirely through corrupting `exit_code`/`stderr`, not through losing stdout content gates never used anyway.
- 9 of 11 gates are safe not because anyone defended against this, but because `test`, `[`, and `grep -q` happen to produce no stdout — an accidental property of idiomatic shell gate-writing, not a mitigation.
- Issue #193 already exists with almost exactly this lead's numbers (1091 vs. ~1250 sessions, both ~100KB) but was filed from a completely different angle (log noise from direct `koto` CLI use) and has zero mention of the deadlock connection this exploration surfaces.
- Real measurement (3,793 bytes for 63 Go packages) meaningfully undercuts the "certain" exposure hypothesis for `tests_passing` in the brief — worth flagging since it changes the honest severity ranking from what was assumed going in.

## Open Questions

- What does `check-staleness.sh` actually write to stderr on a large/stale-issue set? (Script lives in a private repo, out of scope for this public-only exploration — someone with access should measure it directly rather than relying on this lead's shell-mechanics inference.)
- Does `gh pr checks`/`gh pr view` ever write substantial stderr (rate-limit backoff messages, deprecation notices) in practice, or is that channel effectively always small? Not measured here.
- Should the timeout path in the fixed `run_shell_command` return the partial output collected before the kill, or preserve today's "empty output on timeout" contract? This is a real behavior decision, not just an implementation detail, and affects gate/default-action consumers' expectations.

## Summary
The 64KB pipe-buffer deadlock is confirmed in `koto/src/action.rs:26-107` (`wait_timeout` before any read) and is real, but only 1 of shirabe's 11 shipped gates (`tests_passing`) writes captured output directly, and real measurement on the tsuku monorepo (3.8KB for 63 Go packages) puts current exposure well under the trigger size — this is a live but not-yet-triggered defect at today's scale, not an active outage. The fix is a contained ~100-150 line change (concurrent pipe-draining threads in one function, plus new tests; the existing 64KB truncation is unaffected), and the independently-tracked session-migration defect (koto issue #193, already reproduced with near-identical numbers) is the mechanism that would make the deadlock self-inflicted the moment koto commands get nested inside koto-executed gates or default actions — the exact expansion this exploration is weighing.
