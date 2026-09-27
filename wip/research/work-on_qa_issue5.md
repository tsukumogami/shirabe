# QA: Issue 5 (sealed reconcile pass and the reconcile state)

Branch `docs/coordinate-reconcile` at 7349b85. koto 0.13.0 (b4db451). All
runs were outside the worktree (scratch dir under the job's tmp); no git
writes in the worktree. Harnesses: `harnessA.sh` (real koto) and
`harnessB.sh` (`--test-entry` with a clock file), both independent of the
branch's own tests.

Result: 140 scenarios run, 140 passed, 0 failed. No defects found.

Agreed deviations treated as intended: the pass in its own `reconcile_pass`
state gated by `coord-verdict.sh` exit 140; the digest check as a gate on
`reconcile`; the seal line `reconciled <sha256> sealed:<seq>:<hash>`; no
environment scrub (koto#261, named in SKILL.md Known Limitations and in the
pass's header).

## Committed modes and the branch's own suites

| Scenario | Result | Evidence |
|---|---|---|
| `reconcile-pass.sh` committed executable | PASS | `git ls-files -s`: 100755 |
| `reconcile-report-get.sh` committed executable | PASS | 100755 |
| `coord-verdict.sh` committed executable | PASS | 100755 |
| `coord-log.sh` committed executable | PASS | 100755 |
| `reconcile-pass_test.sh` | PASS | 76 passed, 0 failed |
| `reconcile-pass_engine_test.sh` | PASS | 27 passed, 0 failed (includes the 31 s listing wait) |

The scripts the pass starts as children (`reconcile-read.sh`,
`reconcile-check.sh`, `reconcile-report.sh`) run through `$BASH`, so their
mode doesn't matter; they are 100755 anyway. `reconcile-deps.sh` is sourced
and is 100644, which is correct.

## A. Real koto, skeleton template

The `reconcile_pass` and `reconcile` blocks and directives were lifted
verbatim from `coordinate.md` into a skeleton with a sealing
`start_posture`; real `coord-log.sh` and `coord-verdict.sh`, stand-in
`reconcile-read.sh` and `reconcile-check.sh`, copied with `cp -p` so the
committed modes carry through.

| Area | Scenario | Result | Evidence |
|---|---|---|---|
| blocked | read exit 3: held in `reconcile_pass`, capture `blocked:none`, `reconcile/refusal` `case: none`, no `report.json`, second tick still held | PASS (5) | engine-captured `RECONCILE_SEAL` read back through `coord-log.sh capture` |
| blocked | read exit 4 and exit 6: same, `blocked:unreadable` | PASS (10) | |
| pending | first tick with a re-check outliving the budget: held, capture `pending:7:1:<64 hex>`, pass returned in 20 s (under koto's 30 s), `reconcile/progress` set | PASS (4) | budget-exhaustion path, distinct from the engine test's listing-wait path |
| evidence | `{"reconciled":"reported"}` and `{}` in `reconcile_pass` | PASS (2) | both `precondition_failed`, state unchanged |
| sealed | next tick seals, auto-advances to `reconcile`; line shape; seal digest equals sha256 of stored `report.json`; progress cleared | PASS (4) | |
| report-get | `--check` exit 0; JSON mode `directed_transitions: []` for an ordinary run | PASS (2) | |
| `--md` | exit 0, starts `# Reconcile report`, byte-equal to stored `reconcile/report.md`, names the holding | PASS (4) | |
| gate | absent report: evidence held, report-get exit 2 | PASS (2) | |
| gate | agent-written report (`holdings = []`): evidence held, report-get exit 1 | PASS (2) | |
| gate | edited report (one trailing byte; one character changed): evidence held | PASS (2) | |
| gate | sealed bytes restored: evidence moves to `pick_facts` | PASS | |
| earlier visit | `--to reconcile_pass` from `reconcile` refused by koto (undeclared target); `koto rewind` re-enters; visit-1 report replayed is refused (exit 1) both before and after a visit-2 pass; the visit-2 pass removed the old `report.json`; after `--to reconcile` the replayed report holds the evidence | PASS (9) | |
| `--to` jump | blocked, then `koto next --to reconcile`: evidence held by `reconcile_report`; report-get exit 1 with "no sealed reconcile capture from the latest visit to reconcile_pass" | PASS (4) | |
| `--to` named | after rewind and a real seal, JSON mode gives `["20 reconcile_pass->reconcile"]`: exactly one, `<seq> <from>-><to>`; evidence then passes | PASS (5) | |
| template | `reconcile` no polling; `reconcile_pass` no accepts, one transition; every gate in both states `overridable: false`; no gate names reasoning; `PLUGIN_ROOT` no `rebind`; directive/details don't name `RECONCILE_SEAL` | PASS (7) | compiled `coordinate.md` |

A total: 64 passed.

## B. `--test-entry` with a clock file

Stand-ins: `reconcile-read.sh`, `reconcile-check.sh` (advances the clock by
a per-kind cost, marks itself running to measure concurrency, emits stderr
noise and `RAWMARK-*` fields), `coord-log.sh` (seal/capture), and `koto` and
`git` on PATH, all logging every call. The test plays the engine by writing
each printed line back as the capture.

| Area | Scenario | Result | Evidence |
|---|---|---|---|
| budget | 12 holdings with PRs, cost 3 s per read: first pass `pending:3:20:<hex>` | PASS | |
| budget | at most four at once | PASS (2) | max observed 4, first pass and across all six passes |
| budget | no launch at or after 20 s | PASS (2) | last launch in pass 1 `h2.pr +18s with 6s` |
| budget | every budget clipped by 24 s; clip observed | PASS (3) | `launch + budget <= 24` for every launch in every pass |
| budget | deadlines handed to reads never exceed own (D <= 8, BD <= 26) | PASS | |
| budget | later passes seal; all 12 PRs read | PASS (2) | 13 PR reads: one read the injected clock pushed past launch+budget+2 was stopped and relaunched, which is the documented behaviour |
| re-read | miss leaves the pass pending; re-read due past the cutoff is not made yet | PASS (3) | |
| re-read | second read >= 30 s after the first | PASS | clock 5002 -> 5034 |
| re-read | two misses: "not found on this read", entry under "Exists nowhere else", "inventory could not be taken", no inventory read | PASS (5) | |
| re-read | none of gone/dead/lost in `report.md` or `report.json` | PASS (2) | word-bounded grep |
| re-read | miss then match: "worker found", inventory taken, no "not found" | PASS (3) | |
| re-read | re-read due before the cutoff is made within the same pass | PASS (2) | two host reads in the pass; drives to "worker found" |
| side effects | verdicts: merge confirmed, `Close owner/repo#44` confirmed, close of held PR confirmed, teardown confirmed, notify `not_rechecked`, merge with a malformed target `not_verified` with its reason | PASS | |
| side effects | merge read uses holding repo, PR 12 and verified head; `acme/other#44` read as an issue in that repo; `#12` read as a pr | PASS (3) | stub call log |
| side effects | teardown: two listing reads, 37 s apart | PASS (2) | |
| side effects | notify triggers no read | PASS | |
| deferrals | each checked with `--run-start`; only the undisposed one reported; md lists it; md lists all six side effects | PASS (5) | |
| bound | 1 holding + 6 side effects + 2 deferrals: 30 lines <= 94 | PASS | |
| discipline | reasoning written to `reconcile/reasoning.md` byte-identical to the handoff; not inlined in the report; report says "The previous rotation's reasoning is in reconcile/reasoning.md, as its view"; header "as it wrote them on 2026-09-25"; rows marked as the previous rotation's; JSON `{"status":"present","key":"reconcile/reasoning.md"}` | PASS (8) | |
| discipline | reasoning absent: no key; "No reasoning was received" | PASS (2) | |
| bound / raw | 10 holdings (half with legs, workers missed twice) + 3 side effects + 2 deferrals: 45 lines <= 130 (and <= 100 for holdings alone) | PASS (2) | |
| bound / raw | no `RAWMARK-*`/`RAWSTDERR-*` in `report.md` or `report.json`; no JSON fragments in md; leg return paths read | PASS (3) | |
| context | every `koto context add/remove` across all B cases is a `reconcile/` key; only `context add/remove/get` used | PASS (2) | |
| context | no stored value carries the session id, instance path (`/home/qauser/ws/ws+qa_topic-9f8e7d6`) or job id (`job-7f3e9a21`) planted in host facts; no printed line does either | PASS (2) | |
| context | git limited to `rev-parse --show-toplevel` | PASS | |
| placement | toplevel is the plugin tree: `inside`, md "ran from inside"; toplevel a parent: `inside`; unrelated dir: `outside`, md "ran from outside"; sibling sharing a name prefix: `outside`; no repository: `null` | PASS (7) | |
| grammar | every line printed across all B cases matches `pending:`, `blocked:` or `reconciled ... sealed:` | PASS | |
| clock | `--clock-file` without `--test-entry` exits 64 | PASS | the pass assigns `CLOCK_FILE`, `CUTOFF`, `PARALLEL`, `RELISTEN` itself; no environment variable reaches the clock or sleep |

B total: 70 passed.

## Notes

- koto's `--to` only accepts a target the current state declares a
  transition to, so re-entering `reconcile_pass` from `reconcile` needs
  `koto rewind`. That limits a directed transition's reach here to
  `reconcile_pass -> reconcile`, which the `reconcile_report` gate holds.
- A directed transition doesn't make `reconcile-report-get.sh` refuse; it's
  named in JSON mode for the reader, as specified.
- My first drafts had wrong expectations in six places: in A, using `--to
  reconcile_pass` to re-enter the state (koto refuses it; now asserted, with
  `rewind` used instead); in B, the exact PR-read count under an injected
  clock, a re-read due 1 s into the next pass counted as early (it's
  correctly waited for in-pass), the in-pass re-read sealing at once (the
  found worker's inventory still follows), and the code for a malformed merge
  target (`not_verified`, with its reason). Each was checked against the code
  and the behaviour was correct; the assertions changed, not the product.
