# AC Discriminability Taxonomy

This file documents the 7 AC failure patterns used by Category C review (Phase 3).
Review agents use these entries verbatim when evaluating acceptance criteria.

Phase 3 runs two passes:

1. **Pattern pass** — scans AC text for automatable signals (patterns 1, 3, 7)
2. **Adversarial pass** — prompts the review agent to reason taxonomically for ACs
   that did not match in the pattern pass (patterns 2, 4, 5, 6)

---

## Pattern 1 — Fixture-anchored

**Pattern number:** 1

**Failure mode:** The AC passes because test data is pre-populated before the command
runs. A wrong implementation that skips the initialization step still satisfies the
criterion because the expected data was already present.

**Why it fails to discriminate:** The AC measures the presence of data, not whether
the implementation produced that data. Any implementation — correct or wrong — sees
the same pre-populated state and passes.

**Detection method:** Pattern pass (automatable)

**Detection trigger:** The AC text contains "all fixture", "fixture data", "test data",
"sample data", "seed data", or "pre-populated" AND the issue body contains no AC
that mentions a clean-state scenario (e.g., "empty the registry", "fresh state",
"no prior data").

**False-positive guard:** If the issue body contains at least one AC with a clean-state
scenario, do not flag — the clean-state AC provides the discrimination.

**Concrete example:**

> AC: "The binaries table contains all fixture data after running the init command."

This passes even if the init command does nothing, because the fixture was loaded
before the test ran. A discriminating AC would add: "Empty the registry. Run the
init command. Verify the table now contains the expected rows."

**Correction hint template:** "Add a clean-state scenario — empty the [registry/store/table]
before running the command and verify the initial state is empty, then run the command
and verify it contains the expected [data/rows/entries]."

---

## Pattern 2 — Mock-swallowed

**Pattern number:** 2

**Failure mode:** The AC passes against a mock dependency that does not reproduce
the failure mode of the real dependency. The wrong implementation satisfies the AC
in the test environment while failing against the real system.

**Why it fails to discriminate:** The mock is configured to return success regardless
of whether the implementation handles the dependency correctly. A wrong implementation
that ignores errors or assumes success looks indistinguishable from a correct
implementation in the mocked context.

**Detection method:** Adversarial pass (semantic reasoning required)

**Adversarial prompt:** Does this AC's observable outcome depend on a dependency
(network call, database write, external service, file system operation) that a test
would typically mock? If a mock always returns success, would a wrong implementation
that ignores error responses still satisfy this AC?

**Concrete example:**

> AC: "The config file is written to disk after running the setup command."

If the test mocks `os.WriteFile` to always succeed, a wrong implementation that
calls `WriteFile` with empty content passes — the mock returns success regardless
of what was written.

**Correction hint template:** "Verify that the written [file/record/entry] contains
the expected [content/fields/values], not just that the write operation returned
success."

---

## Pattern 3 — Happy-path only

**Pattern number:** 3

**Failure mode:** No AC in the issue mentions a failure case, error condition, or
edge case. A wrong implementation that handles only the happy path — ignoring errors,
panicking on invalid input, or silently corrupting state — passes all acceptance
criteria.

**Why it fails to discriminate:** The AC set is incomplete. A correct implementation
handles failure cases; the criteria only verify the success path and cannot distinguish
between a correct implementation and an incomplete one.

**Detection method:** Pattern pass (automatable, issue-level check)

**Detection trigger:** Scan the entire issue body. If no AC contains any of:
"fail", "failure", "error", "invalid", "edge case", "empty", "missing", "not found",
"rejected", "unauthorized", "timeout", "concurrent", "conflict", "duplicate" —
flag the issue as happy-path-only.

This is a per-issue check, not per-AC. One finding covers all ACs in the issue.

**False-positive guard:** If the issue body contains at least one failure/error AC,
do not flag — the issue has some negative-path coverage even if incomplete.

**Concrete example:**

A five-AC issue that verifies install, list, uninstall, and upgrade in the success
path, with no AC for "install fails when network is unavailable" or "uninstall fails
when the tool is in use."

**Correction hint template:** "Add at least one AC for the failure path — for example,
what happens when [the input is invalid / the dependency is unavailable / the resource
already exists / the user lacks permission]."

---

## Pattern 4 — State-without-transition

**Pattern number:** 4

**Failure mode:** The AC checks the final state of a system without verifying the
operation that produced it. A wrong implementation that starts in the target state —
or that sets the state directly without performing the required operation — satisfies
the criterion.

**Why it fails to discriminate:** The AC measures the outcome, not the causal chain.
A correct implementation performs the operation and reaches the state; a wrong
implementation sets the state directly (or is initialized in the target state) and
appears identical from the AC's perspective.

**Detection method:** Adversarial pass (semantic reasoning required)

**Adversarial prompt:** Does this AC check only the final state of a system (e.g.,
"the table contains X", "the field is set to Y", "the file exists")? If the system
were pre-initialized in that final state without running the described operation,
would this AC still pass?

**Concrete example:**

> AC: "After running `tsuku install ripgrep`, the `~/.tsuku/bin/rg` symlink exists."

A wrong implementation that creates the symlink unconditionally during startup — not
during install — passes this AC. A discriminating AC would verify: "Before install,
`~/.tsuku/bin/rg` does not exist. After install, it exists and resolves to a valid
binary."

**Correction hint template:** "Add a precondition — verify the [state/file/entry]
does not exist before the operation, then verify it exists with the expected
[content/value/properties] after the operation."

---

## Pattern 5 — Integration scope gap

**Pattern number:** 5

**Failure mode:** The behavior under test can only be observed at integration scope
(across multiple components, or through a real dependency), but the AC is written
at unit scope in a way that a unit test cannot detect the actual failure. A wrong
implementation passes unit-level verification while failing at integration.

**Why it fails to discriminate:** The unit boundary excludes the interaction that
reveals the bug. Two components might each pass their unit ACs while producing
incorrect behavior at the boundary.

**Detection method:** Adversarial pass (semantic reasoning required)

**Adversarial prompt:** Does this AC describe behavior that requires interaction
between multiple components, or behavior at a real dependency boundary (network,
database, file system)? If the AC can only be verified end-to-end, would a unit
test satisfy it even if the integration behavior is wrong?

**False-positive guard (critical):** Only flag when integration scope is the *only*
observable path. Do not flag every unit AC. A unit AC for a function that produces
a return value is fine; an AC that says "the registry is updated" when the registry
is in a separate component with its own service boundary is a scope gap.

Ask: could a unit test catch the wrong behavior? If yes, do not flag.

**Concrete example:**

> AC: "Running `tsuku list` shows all installed tools."

If the listing logic and the installation state are in separate components, and the
AC cannot be verified without the components interacting, a unit test of the list
command that mocks the state store cannot catch a mismatch in how state is keyed.

**Correction hint template:** "Verify [the behavior] end-to-end: [describe the
specific integration scenario] rather than only checking the [function/method]
return value in isolation."

---

## Pattern 6 — Interface name drift

**Pattern number:** 6

**Failure mode:** The AC references an interface name, method name, or function
signature that differs from the name in the upstream design doc. A correct
implementation using the design doc name fails this AC; a wrong implementation using
the AC's name passes.

**Why it fails to discriminate:** The AC and the design doc disagree on the name.
An implementer following the design doc produces a correct implementation that fails
the AC. An implementer following the AC produces an incorrect implementation (wrong
name) that passes.

**Detection method:** Adversarial pass (semantic reasoning required; requires the
upstream design doc)

**Adversarial prompt:** Does this AC mention a specific interface name, method name,
type name, or function signature? If so, look up that name in the upstream design
doc. If the design doc uses a different name for the same entity, flag this as
interface name drift.

**Skip condition:** If the input type is `topic` (no upstream design doc), skip this
pattern.

**Concrete example:**

> Design doc section 3: "The registry is queried via `LookupRegistry(name string)`"
> Design doc section 7: "The client calls `RegistryLookup(name string)` to resolve tools"
> AC: "The `RegistryLookup` function returns the tool metadata for a known tool name."

An implementer following section 3 implements `LookupRegistry` — the AC fails. An
implementer following section 7 implements `RegistryLookup` — the design is inconsistent
and the plan has inherited that inconsistency.

**Correction hint template:** "Reconcile the interface name: the design doc uses both
`[name A]` (section X) and `[name B]` (section Y). The AC should reference the
canonical name after the contradiction is resolved in Phase 1."

---

## Pattern 7 — Existence-without-correctness

**Pattern number:** 7

**Failure mode:** The AC checks that something exists or was created, but not that
it contains correct content. A wrong implementation that creates an empty, malformed,
or placeholder artifact satisfies the criterion.

**Why it fails to discriminate:** Creating an artifact is easier than creating a
correct artifact. The existence check rewards any implementation that produces *some*
output — including an implementation that ignores the required content entirely.

**Detection method:** Pattern pass (automatable)

**Detection trigger:** The AC text contains "exists", "is created", "is populated",
"is not empty", "was created", or "has been created" AND the AC contains no assertion
about content, fields, values, structure, or specific data.

Content assertions (do not flag if present): "contains the expected rows", "matches
the config schema", "includes the required field", "equals the expected value",
"has the correct [property]".

**False-positive guard:** If the AC sentence or an immediately adjacent AC in the
same issue body includes a content assertion about the same artifact, do not flag.

**Concrete example:**

> AC: "The `~/.tsuku/registry/ripgrep.toml` file exists after installation."

A wrong implementation that creates an empty TOML file passes this AC. A discriminating
AC would add: "The file contains a `[recipe]` block with the `name`, `version`, and
`source` fields matching the installed recipe."

**Correction hint template:** "Verify [the artifact] contains the expected [content/fields/values],
not just that it exists. For example: assert that [specific field or content property]
has the expected value."
