<!-- decision:start id="eval-rubric-honest-vs-reflexive" status="assumed" -->
### Decision: Eval Rubric for Honest vs Reflexive Assessment

**Context**

Issue #9 requires the adversarial lead design to include eval criteria that measure whether the lead produces honest assessments rather than reflexive negativity. gstack's plan-ceo-review has no such rubric — its eval only checks that the skill ran and produced output. The core challenge: measuring "honest" requires knowing whether a topic actually has real demand, which requires ground truth. The eval infrastructure supports fixture files via `fixture_dir`, which copies synthetic artifacts into `inputs/` before each eval run. The with-skill vs without-skill comparison is the baseline evaluation pattern.

Research confirmed that demand signals in a code-oriented repo are citable, fixture-reproducible artifacts: number of distinct issue reporters, presence or absence of maintainer-assigned labels, linked merged PRs, PR rejection history with explicit reasoning. These can all be encoded in synthetic fixture files. Three scenario types cover the key behavioral branches: (1) strong demand with multiple citable signals, (2) absent demand with positive evidence of rejection or no signals, and (3) a diagnostic topic where the adversarial lead should recognize demand validation doesn't apply.

**Assumptions**

- The adversarial lead reads fixture files from `inputs/` when present (consistent with how review-plan evals work).
- Fixture files can simulate GitHub issue metadata, PR references, and code search results in a format the lead will read and cite.
- Three eval cases is sufficient to cover the non-overlapping behavioral scenarios without redundancy.
- The with-skill vs without-skill comparison remains the baseline, but the primary assertions target the with-skill output against fixture ground truth rather than comparing the two outputs against each other.

**Chosen: Composite — A (fixture ground truth) + C (anti-reflexivity assertions) + D (confidence calibration)**

Three eval cases, each using a `fixture_dir` with synthetic demand signals:

**Eval case 1: strong-demand**
- Fixture: synthetic issue files from 4 distinct reporters, a maintainer-assigned `needs-design` label, and a linked merged PR that attempted a related feature. No prior rejection in PR history.
- Ground truth: demand is real and well-evidenced.
- Assertions:
  - The adversarial lead does NOT output a "don't pursue" or "demand is absent" recommendation.
  - The lead cites at least two distinct demand signals from the fixture (issue reporters, maintainer label, or linked PR).
  - Reported confidence for "is demand real?" is high, not medium, low, or absent.

**Eval case 2: absent-demand**
- Fixture: no issue files, a closed PR with an explicit maintainer comment ("not building this — adds complexity without user benefit") and no workarounds in docs.
- Ground truth: demand is validated as absent (positive rejection evidence, not just thin evidence).
- Assertions:
  - The adversarial lead outputs a demand-gap finding, citing the PR rejection.
  - The lead distinguishes "demand validated as absent" (positive rejection evidence) from "demand not validated" (thin evidence gap).
  - Reported confidence for "is demand real?" is absent or low with a specific citation.

**Eval case 3: diagnostic-topic**
- Fixture: a topic framed as a constraint-analysis question ("what are the performance limits of X?"), not a feature request. No issue files expected.
- Ground truth: the adversarial lead is not the right agent for this topic — demand validation doesn't apply.
- Assertions:
  - The lead explicitly notes that demand validation is not applicable for this topic type.
  - The lead does NOT produce a false demand-gap finding (i.e., does not say "no demand for this topic" when the question is diagnostic).
  - Output does not force a proceed/don't-pursue recommendation onto a non-demand question.

**Rationale**

Option A (fixture design) is necessary infrastructure — without fixture-encoded ground truth, there's no objective basis for any assertion. Options C and D together cover the two failure modes: C catches reflexive negativity (false "don't pursue" on a strong-demand fixture) and false positivity (missing a clear rejection signal on an absent-demand fixture); D adds precision by requiring calibrated confidence levels that match the fixture signals, not just a directionally correct verdict. Option B (comparative assertion) is subsumed: if C passes, the with-skill output is already demonstrably more specific and accurate than any baseline could be. The three-case structure covers the complete behavioral space without redundancy — strong demand, positive rejection evidence, and non-demand topic — matching the three scenarios named in the acceptance criteria context.

**Alternatives Considered**

- **Option B (comparative assertion only)**: Checks that the with-skill output is more specific than the without-skill baseline, but specificity alone doesn't measure correctness. A reflexively negative output can cite specific fixture files while still reaching the wrong conclusion. Rejected because it doesn't test against ground truth.
- **Option C alone (anti-reflexivity without fixtures)**: Anti-reflexivity assertions require a fixture to define what "clearly good idea" and "clearly bad idea" mean. Without encoded ground truth, the grader has no anchor for what the lead should find. Rejected as insufficient without Option A.
- **Option D alone (confidence calibration only)**: Calibration checks require knowing the correct confidence level, which requires ground truth from fixtures. Also, calibration is a precision check — it doesn't catch the case where a lead reaches the right confidence but gives the wrong direction. Rejected as incomplete without A and C.
- **Minimum viable (A + C only, no D)**: Viable but weaker. Anti-reflexivity assertions check direction; without calibration, a lead that says "proceed with confidence" on a weak-demand fixture (where confidence should be medium) would pass C but miss the calibration failure. Option D is worth adding because evals.json assertions are cheap to write and directly testable.

**Consequences**

- Eval authors must create fixture files that credibly simulate repo artifacts — synthetic issue files need realistic structure (reporter handles, AC text, labels) so the lead can parse them as it would real issues.
- The diagnostic-topic case (eval case 3) prevents an over-eager implementation from treating every non-demand question as a demand gap, which would be a form of reflexive negativity applied to topic type rather than topic merit.
- Calibration assertions (Option D) mean the skill must produce explicit per-question confidence outputs — this feeds back as a design constraint on the adversarial lead's output format.
- Three cases is a deliberate minimum; a fourth case (thin-evidence, "demand not validated" distinct from "demand validated as absent") could be added if the distinction proves hard to test in the absent-demand fixture alone.
<!-- decision:end -->
