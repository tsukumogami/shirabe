# Phase 6 Security Review: shirabe-cli-rust-rewrite

## Review questions

1. Are there attack vectors not considered?
2. Are mitigations sufficient for identified risks?
3. Are any "not applicable" justifications actually applicable?
4. Is there residual risk that should be escalated?

## Findings

### Attack vectors not considered

The Phase 5 security review covered: GHA annotation injection,
YAML parser exploitation, path traversal via `upstream:`, file
system access, git subprocess invocation, supply chain
(saphyr 0.0.x pinning), FC03 body echo as data exposure, and
panic-to-stderr.

One vector to add: **cargo build script execution at install
time**. saphyr or its transitive deps may have `build.rs`
files. Build scripts execute arbitrary code during `cargo
build`. Severity: low — saphyr is pure Rust with no documented
build script; clap's build path is well-vetted. But the Cargo
workspace ships `Cargo.lock`; the implementer should run
`cargo deny check bans` or equivalent during SR1 to surface
any unexpected build-script dependencies.

This is implementer-time hygiene, not a design change. Worth a
note in the supply-chain subsection.

### Mitigations sufficiency

The mitigations as documented are sufficient for the risks
named. The two-layer fixture (Decision 3 restructured)
strengthens annotation-injection mitigation: the synthetic
corpus exercises sanitize-path edge cases on every PR, not
just on real-corpus inputs.

### "Not applicable" claims

Data Exposure is documented as "Limited," not "Not
applicable." The FC03 body-echo path is correctly identified
as an inherited behavior, severity low. No N/A claims that
should be reclassified.

### Residual risk for escalation

None. The residual risks documented (saphyr 0.0.x advisory,
panic on malicious input) are bounded and have explicit
recovery paths (patch pin, parity fixture catches divergence).

## Recommendations

1. **Add cargo build-script note** to Supply Chain subsection.
   One sentence: "Implementer runs `cargo deny check bans`
   during Phase 1 to surface unexpected build-script
   dependencies in the saphyr/clap dependency tree."

2. **No design changes required** beyond the build-script note.

## Verdict

PASS with one minor addition. The security analysis is
complete; the build-script note is hygiene for the implementer.
