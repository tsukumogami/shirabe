---
schema: execute-state/v1
---

```yaml
topic: settled-branch-record
last_updated: 2026-08-15T19:30:00Z
phase_pointer: plan_completion
exit: UNSET
exit_artifacts: []
execution_mode: single-pr
autonomy: auto
home_pr: 306
settled_branch: docs/settled-branch-record
setup_path: override
setup_path_reason: >-
  Entered on docs/settled-branch-record, a non-main branch with open PR #306
  (the /scope chain's PR). Adopted as the home PR: no second PR opened, none
  linked. Branch creation skipped, which is why the settled branch has to be
  recorded rather than derived.
child_execution_note: >-
  The four PLAN issues were executed in-process on the shared branch rather than
  as koto-materialized /work-on children, because agent dispatch is not
  available in this session. Dependency order from the PLAN was preserved:
  write, then gate, then the test, then the prose and evals.
children:
  - issue: 1
    title: "fix: record the settled branch with a command that exists"
    commit: 995637d
    outcome: done
  - issue: 2
    title: "fix: gate orchestrator_setup on the recorded branch"
    commit: eb27a72
    outcome: done
  - issue: 3
    title: "test: prove the round trip and the fail-closed stop"
    commit: 4187d84
    outcome: done
  - issue: 4
    title: "docs: reconcile SKILL prose and evals with the gate"
    commit: 8324130
    outcome: done
findings_reported_upstream:
  - id: 304
    what: >-
      /work-on's scrutiny phase instructs `koto context remove`, which does not
      exist. Same defect class as #279, different skill. Filed rather than fixed
      because PRD R9 confines this change to /execute's orchestrator_setup and
      spawn_and_await.
findings_recorded_in_design:
  - >-
    koto context get writes its error as JSON to stdout (not stderr) and exits 3,
    so the shipped `|| echo` read idiom captures a two-line value on a missing
    key and only the existing case guard rescues it. This is why the new
    verification compares rather than testing for emptiness.
  - >-
    A failed context-matches gate is NOT a bare exit code: koto returns
    advanced:false with a blocking_conditions entry naming the gate. The
    silent-gate note in the template applies to command gates, whose output koto
    discards. An earlier draft of the DESIGN generalized it wrongly; corrected.
  - >-
    The recording block reads HEAD but was printed before the creation script,
    so an agent reading top to bottom on the create path would record `main` --
    a well-formed value neither the pattern nor the read-back can reject.
    Ordering is now stated explicitly in the directive.
```
