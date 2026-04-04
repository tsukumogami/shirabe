# Security Review: DESIGN-work-on-koto-unification

**Reviewer**: architect-reviewer (security analysis)
**Date**: 2026-04-04
**Document**: docs/designs/DESIGN-work-on-koto-unification.md
**Section under review**: Security Considerations

---

## Assessment of Existing Security Considerations

The design identifies three security-relevant aspects: gate overrides, script
execution, and context store contents. Each is evaluated below.

### 1. Gate Overrides

**Design claim**: Override mechanism requires rationale; all overrides remain
auditable.

**Assessment**: Sufficient for the threat model. Overrides are a user-initiated
action in a local development workflow. The design actually strengthens the
security posture by moving from ad-hoc review skipping to koto's formal override
system with mandatory rationale. No issue here.

### 2. Script Execution (`plan-queue.sh`)

**Design claim**: Script reads/writes a manifest JSON file, doesn't execute
arbitrary commands, and only processes PLAN doc content authored by the same user.

**Assessment**: Partially sufficient. The claim that input is "authored by the
same user" is correct for the direct invocation path. However, there is a
nuance worth noting:

- **PLAN doc parsing happens in SKILL.md, not the script.** The script receives
  a pre-built manifest. The actual parsing of potentially complex markdown into
  structured JSON occurs in the skill layer (prose-based, agent-executed). If
  the PLAN doc contains adversarial markdown (e.g., in a public repo where
  contributors submit PLAN docs), the agent doing the parsing could
  misinterpret structure. This is a prompt injection surface, not a code
  injection surface.
- **The script uses `jq` for JSON processing.** This is safe -- jq is a
  read-only query language for JSON. No shell expansion of manifest content
  occurs as long as values are passed through jq rather than interpolated into
  shell strings.
- **No validation of manifest schema.** The script's four subcommands
  read/write the manifest file. If the manifest is malformed (truncated write,
  concurrent access), the script's behavior is undefined. This is a reliability
  concern, not a security concern, given the single-user local execution model.

### 3. Context Store

**Design claim**: No credentials or secrets stored in context.

**Assessment**: Correct for the designed data flow. Context keys store
summaries, plans, review results, and baselines. The design doesn't introduce
any path where secrets would flow into context. However, this is a behavioral
constraint, not an enforced one -- nothing prevents an agent from writing
sensitive data to a context key during implementation. This is acceptable
because the same agent already has full filesystem access.

---

## Attack Vectors Not Considered

### A. Command Injection via Template Variables (Low Risk)

The koto template uses variable interpolation: `{{ISSUE_NUMBER}}` appears in
the staleness check gate command:

```yaml
command: "check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e ..."
```

If `ISSUE_NUMBER` is not sanitized at `koto init` time, a malicious value
(e.g., `; rm -rf /`) could inject into the shell command. However:

- ISSUE_NUMBER is set by the SKILL.md at init time, not by external input
- Koto likely handles variable interpolation safely (this should be verified
  in koto's implementation)
- The new design adds `PLAN_DOC` as a variable, which is a file path -- same
  risk profile

**Recommendation**: Verify that koto's variable interpolation in gate commands
is shell-safe (quoted or escaped). If it does raw string substitution into
shell commands, this is a real injection vector. Not a design problem per se,
but a dependency assumption that should be documented.

### B. Manifest File Race Condition (Not Applicable)

The manifest file (`wip/work-on-plan_<topic>_manifest.json`) is read and
written by the queue script. In the designed single-agent execution model,
there's no concurrent access. If future designs introduce parallel issue
execution (multiple agents working different issues simultaneously), the
manifest becomes a shared mutable resource without locking. The design
correctly scopes to sequential execution, so this is not currently applicable.

### C. Prompt Injection via PLAN Documents (Low Risk, Out of Scope)

In plan-backed mode, the SKILL.md parses a PLAN document and extracts issue
descriptions, dependencies, and agent types. If a PLAN document contains
adversarial content (instructions disguised as issue descriptions), the parsing
agent could be manipulated. This is:

- A general LLM agent security concern, not specific to this design
- Mitigated by the fact that PLAN docs are authored by the same user or team
- Not addressable at the workflow architecture level

This is correctly out of scope for a design document.

### D. Review Panel Agent Collusion (Not Applicable)

The 3-agent review panels could theoretically all agree to pass flawed code.
This is an inherent limitation of LLM-based review, not a design flaw. The
design's approach (persisting results to koto context for audit trail) is the
correct mitigation at this abstraction level.

---

## "Not Applicable" Justification Review

The Security Considerations section doesn't explicitly mark anything as "not
applicable." Instead, it implicitly scopes itself to three concerns and omits
others. The implicit "not applicable" items:

1. **Authentication/authorization**: Correct to omit. This is a local
   development workflow. The user is the only actor.
2. **Network security**: Correct to omit. No new network calls introduced.
   Existing `gh` CLI calls use the user's authenticated session.
3. **Data persistence security**: Correct to omit. Koto context and manifest
   files have the same permission model as the rest of the working directory.
4. **Supply chain**: Correct to omit. No new dependencies beyond the existing
   jq requirement.

All omissions are justified.

---

## Residual Risk Assessment

| Risk | Severity | Residual After Mitigation |
|------|----------|--------------------------|
| Template variable injection in gate commands | Low | Depends on koto's interpolation safety -- verify |
| Manifest corruption on interrupted write | Low | Reconciliation check in SKILL.md mitigates |
| PLAN doc prompt injection | Low | Same-user authorship mitigates; general LLM risk |
| Review panel false pass | Low | Audit trail in koto context enables post-hoc review |

**No residual risk requires escalation.** The design operates in a single-user,
local development context where the user already has full system access. The
threat model is appropriate for this scope.

The one item worth verifying during implementation: koto's handling of variable
interpolation in gate `command` fields. If koto does raw string substitution
(e.g., replacing `{{ISSUE_NUMBER}}` with the literal value before passing to
`sh -c`), then a variable containing shell metacharacters would be interpreted.
This should be confirmed against koto's source and documented as an assumption
if it's safe, or mitigated (e.g., validating ISSUE_NUMBER is numeric) if it's
not.

---

## Summary

The Security Considerations section is adequate for this design's threat model.
The design introduces no new attack surfaces beyond what the existing workflow
already exposes. The identified concerns (overrides, script execution, context
store) are addressed proportionally. One gap: the design assumes koto's
variable interpolation is shell-safe in gate commands but doesn't state this
assumption explicitly. Recommend adding a note about this dependency or
adding input validation for template variables at init time.
