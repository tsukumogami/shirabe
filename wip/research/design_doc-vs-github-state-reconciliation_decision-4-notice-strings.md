# Decision 4: Notice-message wording

## Question

Exact strings for the three defect notices (one per sub-check, with Sub C's asymmetric directions counted) and the four self-disable notices, in FC05/FC06/FC07 voice.

## Chosen

All FC09 notices begin with the `[FC09]` prefix and name the entity (row key, diagram node id, issue number, or PR body line where applicable) plus observed and expected state where applicable.

### Sub A -- doc claims terminal/`done`, GitHub observes open

```
[FC09] row "#42" (node I42) claims done; GitHub observes issue #42 still open
```

Variables: row key (`#42`), node id (`I42`), issue number (`#42`). The phrasing "claims done" covers both plan-profile strikethrough and roadmap-profile `Status: Done`; the four-word "GitHub observes ... still open" identifies the external truth without leaking environment state.

### Sub B -- doc claims non-`done`, GitHub observes closed

```
[FC09] row "#42" (node I42) claims open with class ready; GitHub observes issue #42 closed (expected done)
```

Variables: row key, node id, declared class (`ready` or `blocked`), issue number. The terminal "(expected done)" mirrors FC07's four-field class-vs-Status form (declared, observed, expected).

### Sub C -- PR over-claims (PR body has `Closes #N` for an N the doc shows non-`done`)

```
[FC09] PR body line "Closes #42" claims a closure the doc still shows non-done (row "#42", node I42, class ready)
```

Variables: PR body literal (`Closes #42`), row key, node id, declared class. Quoting the literal PR body line gives the PR author a mechanical fix path (either remove the `Closes` line or update the doc).

### Sub C -- doc anticipates closure no PR delivers (`done`-claimed row, issue observed open, no matching `Closes` line)

```
[FC09] row "#42" (node I42) claims done but GitHub observes issue #42 open and no "Closes #42" appears in this PR
```

Variables: row key, node id, issue number. The three-clause shape ("claims X but observes Y and no Z") parallels Sub B but adds the absent-`Closes` clue that distinguishes the failure mode.

### Self-disable -- missing credentials (R6)

```
[FC09] skipped: no GitHub credentials available (set GITHUB_TOKEN or run `gh auth login`)
```

The parenthetical hint names the two recovery paths without leaking which the validator was actively searching for. The skip notice fires once per `shirabe validate` invocation on the first FC09-eligible doc; subsequent docs in the same invocation do not re-emit it (the check short-circuits without re-attempting auth detection).

### Self-disable -- missing PR context (R7)

```
[FC09] Sub-check C skipped: no PR context (set GITHUB_REF=refs/pull/<n>/merge, GITHUB_REPOSITORY, or SHIRABE_PR_NUMBER)
```

Sub A and B still run; Sub C is the only skipped surface. The hint names the three env vars the detector reads.

### Self-disable -- rate-limit exhausted (R8)

```
[FC09] skipped: GitHub rate limit exhausted after one retry (subsequent rows in this run will not be reconciled)
```

The parenthetical sets the partial-engagement expectation: rows already-reconciled keep their notices; rows not-yet-reached are silently skipped (no per-row repeat of this notice). PRD's R8 explicitly preserves the earlier notices.

### Self-disable -- per-row cross-repo access denied (R9)

```
[FC09] row "#42" (cross-repo "tsukumogami/koto#65") skipped: GitHub returned access denied (token cannot read tsukumogami/koto)
```

The notice names the cross-repo reference verbatim and identifies the running token's gap. Other rows in the same doc proceed.

## Alternatives considered

- **Use a single grouped notice for all FC09 defects in a doc.** Rejected.
  - FC07's Decision 2 already rejected grouping for the same reasons (loss of per-line targeting, GHA-annotation surface uses line numbers, per-defect voice matches the existing FC05/FC06/FC07 pattern). FC09 inherits the same rationale.

- **Embed the `gh api` URL in the notice body.** Rejected.
  - PRD R12 explicitly says "Notices identify nodes by their diagram id, not by a URL or external identifier." A URL would leak environment state (the running repo, the running token's read paths) and increase the public-cleanliness surface.

- **Vary the wording per profile (Plan vs Roadmap).** Rejected.
  - The notice text is identical across profiles because the defect is identical -- a row claims X and GitHub observes Y. Profile-specific wording would multiply the notice set without adding signal. The "claims open with class <X>" phrasing covers both profiles because Sub B fires only on non-terminal rows and on `ready`/`blocked` classes, which is the same set in both profiles.

## Public-cleanliness review

- No notice quotes the GitHub token or any environment variable's value.
- No notice quotes a private repo name. The example string in the cross-repo case uses `tsukumogami/koto`, which is public; the production string substitutes whatever the running doc's Dependencies cell actually contains. PRD R17 binds the rule prose and notice bodies; the notice forms above are public-clean by construction (they name only the entity the doc itself already names).
- No notice mentions a pre-announcement feature, a private file path, or a private issue number. The PR body line in Sub C's over-claims notice is quoted from the PR body itself -- which is itself public for any PR opened against a public repo.

## Citation

- PRD R12 (notice voice, four self-disable distinct strings), R13 (Sub C asymmetry), R17 (public-cleanliness of notice messages).
- FC07 sub-DESIGN Decision 2 (per-defect over grouped) and the four-field class-vs-Status notice voice the FC07 implementation actually uses (the `[FC07] table row "#X" has no matching diagram node` family).
- FC07 `class_status_notice` implementation (the existing voice this design mirrors).
