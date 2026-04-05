# Security Review Audit: artifact-traceability

## Scope

Independent review of the Phase 5 security assessment against the design
document at `docs/designs/DESIGN-artifact-traceability.md`. Evaluates
whether the N/A determination is correct and whether any vectors were
missed.

## Question 1: Are there attack vectors not considered?

### Path traversal via upstream field values

The Phase 5 report states the upstream field is "a path string written to
YAML frontmatter by the creating agent -- not fetched, resolved, or
executed." This is accurate today. However, the design introduces a new
convention (`owner/repo:path`) that future tooling might resolve
programmatically. If any downstream tool ever resolves these paths (to
validate links, generate indexes, or render navigation), a crafted
upstream value like `../../private/vision:docs/secrets.md` or
`owner/repo:../../../../etc/passwd` could be a traversal vector.

**Assessment:** Not a current vulnerability. The design is purely
documentation and markdown. But the convention creates a pattern that
future tooling consumers should sanitize. This is a latent risk, not an
active one.

### Information leakage via cross-repo reference strings

A public repo artifact containing `tsukumogami/vision:docs/visions/VISION-cloud-strategy.md`
reveals the existence of a private repo, its directory structure, and
artifact names. The design documents the directional visibility rule
("public repos must not reference private artifacts") but enforcement is
purely convention-based -- agents or humans could violate it.

**Assessment:** Low severity. The Phase 5 report acknowledged this under
"Data exposure" and called it a "content governance concern." That
framing is accurate. The risk is information disclosure (existence of
private artifacts), not data exfiltration. Convention-based enforcement
is consistent with how this system works -- there are no programmatic
guards anywhere in the skill system.

### Upstream field injection in YAML frontmatter

The upstream field value is written into YAML frontmatter. A malicious
or malformed value could break YAML parsing if it contains special
characters (colons, newlines, quotes). For example, an upstream value
of `foo: bar\nmalicious_field: true` could inject additional frontmatter
fields.

**Assessment:** Minimal practical risk. The value is set by the creating
agent from explicit arguments, not from untrusted external input. The
attack surface would require a compromised agent or a user deliberately
passing malformed --upstream arguments. Standard YAML quoting would
mitigate this anyway.

### No additional vectors identified beyond these three edge cases.

## Question 2: Are mitigations sufficient for identified risks?

The Phase 5 report identified zero risks and therefore proposed zero
mitigations. Given the three edge cases above:

- **Path traversal (latent):** No mitigation needed now. The design
  should note that any future tooling that resolves upstream paths must
  sanitize them. The design document's "Security Considerations" section
  could add a single sentence: "Any future tooling that programmatically
  resolves upstream paths should validate them against directory
  traversal." This is advisory, not blocking.

- **Information leakage:** The directional visibility rule is documented.
  Convention-based enforcement is the right level for this system. No
  additional mitigation needed.

- **YAML injection:** Not worth mitigating. The input source (agent or
  --upstream flag) is trusted.

**Verdict:** Mitigations are sufficient. The risks are genuinely low and
convention-based controls are proportionate to the threat model.

## Question 3: Are any "not applicable" justifications actually applicable?

The Phase 5 report assessed four dimensions as N/A:

### External artifact handling: N/A -- Correct

The design doesn't process external inputs. Upstream values are written
by agents from explicit arguments. No fetching, downloading, or
execution occurs. The N/A justification holds.

### Permission scope: N/A -- Correct

No new permissions are introduced. All changes are markdown edits to
existing skill instruction files. The transition script isn't modified
and ignores unknown frontmatter fields. The N/A justification holds.

### Supply chain or dependency trust: N/A -- Correct

No new dependencies. The cross-repo reference format is a documentation
convention, not a resolution mechanism. The N/A justification holds.

### Data exposure: N/A -- Borderline but acceptable

This is the one dimension where a case could be made for "Applies: Low."
Cross-repo references in public repos can reveal private artifact names
and directory structures. The Phase 5 report acknowledged this but
classified it as content governance rather than data exposure. That's a
reasonable interpretation given:
- The information disclosed is metadata (file paths), not content
- The directional visibility rule exists specifically to prevent this
- Enforcement is convention-based, consistent with all other governance
  in this system
- No tooling resolves these references, so there's no automated leak path

**Verdict:** The N/A classification is defensible. Reclassifying data
exposure as "Applies: Low" would be equally valid but wouldn't change the
outcome or require additional mitigations.

## Question 4: Is there residual risk that should be escalated?

No. The residual risks are:

1. **Convention violation (visibility rule):** An agent or human writes a
   cross-repo reference to a private artifact from a public repo. Impact
   is limited to revealing the artifact's existence and path. Probability
   is low because agents follow skill instructions, and the convention
   will be documented. This doesn't warrant escalation.

2. **Future tooling consumers:** If someone later builds a tool that
   resolves upstream paths, they'll need to add path sanitization. This
   is a standard software engineering concern, not a security escalation.

3. **Deferred /plan integration:** The /prd -> roadmap upstream link via
   /plan is deferred to Feature 5. This means some artifacts won't have
   traceability links. This is a completeness gap, not a security gap.

**Verdict:** No residual risk requires escalation. The design's threat
profile is genuinely minimal -- markdown template changes with no
external inputs, no new permissions, and no executable logic.

## Overall Assessment

The Phase 5 security report's N/A determination is correct. The design
modifies skill markdown instructions and format specs without introducing
attack surface. The three edge cases identified in this review (path
traversal latency, information leakage via cross-repo references, YAML
injection) are all low-severity, low-probability, and adequately
addressed by existing or documented controls.

### Recommendations

1. **Advisory note (non-blocking):** Add one sentence to the design's
   Security Considerations section noting that future tooling resolving
   upstream paths should validate against directory traversal. This costs
   nothing and prevents a latent risk from becoming an actual one.

2. **No changes required** to the Phase 5 security assessment's N/A
   outcome.

3. **No escalation needed.** Risk profile is consistent with all prior
   skill-change designs in this system.
