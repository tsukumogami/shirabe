# Lifecycle Posture

How `shirabe validate --lifecycle` decides whether an artifact chain passes,
and how that verdict shifts between in-flight drafting and review-ready work.
Covers the posture model, the `--mode` interface, and the per-finding
classification that determines what fails the check in each posture.

## The posture model

A lifecycle check runs in one of two postures:

- **Draft (in-flight).** The chain is still being assembled. An agent is
  drafting locally before any PR exists, or a PR is open but marked draft.
  Mid-PR chain states are expected and tolerated: a fresh BRIEF with no
  downstream artifact yet, a PLAN whose acceptance criteria are not all ticked,
  a DESIGN not yet moved to its terminal location. These are work-in-progress
  signals, not defects.
- **Ready (review-ready).** The chain is being asked to merge. Every chain must
  be at its terminal passing state — the PLAN deleted, BRIEF and PRD at Done,
  the DESIGN at Current. Findings that the draft posture tolerated now fail the
  check, because a reviewer is being asked to approve a finished chain.

The default is **draft**. The verdict treats the chain as in-flight unless a
positive ready signal is present. There is no auto-detection: ready posture is
asserted explicitly on the command line, never inferred from ambient state. A
caller that wants the ready verdict must say so. This keeps the verdict a pure
function of the documents and the declared posture — the same command yields the
same result in any environment, so the validator stays trustworthy as a gate and
as an audit trail.

The shirabe-side callers wire the ready signal as follows:

- `.github/workflows/lifecycle.yml` passes `--mode=ready` only when
  `github.event.pull_request.draft == false` (a PR marked ready-for-review).
  Draft PRs pass no mode flag, so the default draft posture applies.
- `skills/execute/scripts/run-cascade.sh` passes `--mode=ready` on its
  chain probes. The cascade asserts the terminal posture as a forcing
  function: before transitions, the ready probe is expected to fail (the PLAN
  is still present); after transitions, it is expected to pass.

## The `--mode` interface

```bash
shirabe validate --lifecycle . --mode=draft   # in-flight (this is the default)
shirabe validate --lifecycle . --mode=ready   # review-ready
shirabe validate --lifecycle .                # draft, by default
```

`--mode` takes `draft` or `ready`. Omitting it is the same as `--mode=draft`.
An invalid value (anything other than `draft` or `ready`) is a clap usage error
and exits 2.

### Deprecated `--strict` alias

`--strict` is a deprecated alias retained for one migration window. When set, it
resolves to `--mode=ready` and prints a one-line notice to stderr:

```
warning: --strict is deprecated; use --mode=ready
```

`--strict` wins when both are present (it resolves to ready regardless of the
`--mode` value). Migrate any remaining `--strict` callers to `--mode=ready`.

## Finding classification

Each lifecycle finding is either **draft-tolerable** or **always-enforced**. A
draft-tolerable finding is a notice under draft posture (exit 0) and an error
under ready posture (exit 2). An always-enforced finding is an error in both
postures.

| Code | Meaning | Classification |
|------|---------|----------------|
| L01 | Single-pr posture re-target | Always-enforced (posture-sensitive) |
| L02 | Orphan / connectivity | Draft-tolerable |
| L03 | Cycle | Always-enforced |
| L04 | Missing reference | Always-enforced |
| L05 | Parse failure | Always-enforced |
| L06 | Outline acceptance-criteria | Draft-tolerable |
| L07 | Design location | Draft-tolerable |
| FC-family | Frontmatter / convention checks | Always-enforced |

The draft-tolerable set is **L02, L06, L07**. Everything else — L03, L04, L05,
and the entire FC-family — is always-enforced.

L01 is a special case: it is always-enforced, but it is also posture-sensitive.
The single-pr re-target fires only under ready posture, because a single-pr
chain with its PLAN still present is a valid mid-PR state in draft but a defect
at merge.

A document set whose only findings are draft-tolerable exits 0 under draft and 2
under ready. A document set with any always-enforced finding exits 2 in both
postures.

## The advisory layer

A check run renders an advisory explanation alongside the verdict: which
findings were tolerated and what they need before ready, or — on a ready failure
caused by a draft-tolerable finding — that draft posture would have passed and
what to fix to stay ready.

The advisory layer explains but never gates. It reads only the typed draft bit
from the local PR context for phrasing; it never moves the exit code or a
finding's enforced status. Identical documents and posture yield an identical
exit code and JSON result regardless of ambient PR context. The verdict is
reachable only from the finding code and the declared posture, never from the
advisory layer's context.
