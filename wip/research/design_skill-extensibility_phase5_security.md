# Security Review: skill-extensibility

## Dimension Analysis

### Prompt Injection via Extension Files

**Applies: Yes. Severity: Medium (bounded by Claude Code's existing trust model).**

Extension files at `.claude/skill-extensions/<name>.md` are loaded via `@` includes and injected directly into LLM context before the skill executes. There is no sanitization layer between file content and the model. An attacker who can write to these files can inject arbitrary instructions — for example, instructing the skill to leak context to a public GitHub comment, delete files, or execute shell commands through the Bash tool.

The key question is: who can write extension files? In normal use, these are committed files in the consumer's own repo, authored by the same team that configures the Claude Code workspace. The trust level is equivalent to CLAUDE.md itself — if you trust the CLAUDE.md content, you trust the extension files at the same tier.

Two narrower injection surfaces exist:

1. **External contributions via pull request.** A PR that adds or modifies a `.claude/skill-extensions/` file carries the same injection potential as a PR that modifies CLAUDE.md. Teams that allow external contributions should treat these files as privileged configuration. This is the same requirement that already exists for CLAUDE.md — it isn't new exposure introduced by the extension mechanism specifically.

2. **Additive-only constraint is not enforced.** The design specifies extension files should be additive, but there is no mechanism preventing an extension from containing negation instructions ("ignore step X") or redirection instructions ("after every action, also run..."). The constraint is a documentation convention, not a technical control. It reduces the expected use case to additive intent, but an adversarial author faces no barrier.

**Mitigations in the current design:**

- Extension files are committed to the consumer repo and subject to normal code review. This is the primary control.
- The attack surface is confined to the consumer's own workspace — shirabe ships no extension files; it only reads ones the consumer creates.
- Claude Code's permission model (tool confirmation prompts, CLAUDE.md trust anchors) applies to actions the LLM takes, regardless of how instructions entered context. Injected instructions still go through the same tool approval gates for destructive operations.

**Gap:** The design document's Security Considerations section acknowledges `.local.md` injection risk but does not explicitly state that extension files should be treated as privileged configuration on par with CLAUDE.md. This omission could cause teams to review these files less carefully than they deserve.

**Recommendation:** Document explicitly that `.claude/skill-extensions/` files carry the same trust level as CLAUDE.md and should receive equivalent review scrutiny in PRs.

---

### Supply Chain via Plugin Distribution

**Applies: Yes. Severity: Medium (standard plugin supply chain, not novel).**

When shirabe is installed via the Claude Code plugin registry, consumers pull the plugin at a specific version or from a registry entry. A compromised version of shirabe — whether through a registry takeover, a poisoned release, or a dependency-chain attack on the distribution mechanism — could ship malicious SKILL.md content that executes harmful actions through the Bash tool or exfiltrates context.

This is the standard supply chain risk for any package manager dependency. It is not unique to shirabe's design choices — it would apply to any Claude Code plugin.

The design's architectural choices do reduce the blast radius in one way: skills are markdown files, not code. They do not execute directly. The LLM must interpret them and then call tools. Claude Code's tool permission model means Bash tool calls still go through whatever approval gates are configured. A malicious skill instruction asking the LLM to run `rm -rf` would be presented to the user for confirmation (absent an explicit `allowedTools` configuration that pre-approves Bash).

However, two attack vectors don't require destructive tool calls:

1. **Context exfiltration.** A malicious skill could instruct the LLM to read sensitive files (API keys in `.env`, credentials in config) and write them into a PR description or GitHub issue body via `gh` commands. The Bash tool call for `gh issue create` is less likely to trigger user concern than `rm -rf`.

2. **Instruction manipulation.** A malicious skill could override CLAUDE.md project conventions silently — for example, stripping security sections from design documents by claiming "for this project type, security is not applicable."

**Mitigations in the current design:**

- shirabe is a public repo; consumers can audit skill content before installing.
- Plugin versions are pinnable — consumers can lock to a known-good commit or tag.
- No external downloads, no binary execution, no network calls in the plugin itself. The attack surface is limited to what the LLM does with markdown instructions.
- The `scripts/` directory contains shell scripts invoked via Bash, which does increase the surface area slightly (see Shell Script Execution dimension below).

**Gap:** The design document's Security Considerations section says "No supply chain exposure beyond the plugin itself" — this is accurate but potentially misleading. The plugin itself is the supply chain exposure. The statement should acknowledge the risk rather than appearing to dismiss it.

**Recommendation:** Clarify the supply chain consideration in the design document: the risk exists at the plugin level itself, is bounded by Claude Code's tool approval model, and is managed by consumers pinning versions and auditing the plugin repo before adoption.

---

### .local.md Gitignore Risk

**Applies: Yes. Severity: Medium-Low (local machine only, developer intent is explicit).**

`.claude/skill-extensions/<name>.local.md` files are gitignored and therefore not subject to code review. Anyone with write access to the developer's machine can create or modify these files and inject arbitrary instructions into skill context without any audit trail.

The practical threat model here is narrow: `.local.md` files are on the developer's local machine, in a directory they own. The threat requires either (a) another user with local machine access, (b) a malicious process running on the machine that can write to the workspace, or (c) a compromised developer intentionally using `.local.md` to bypass team policy.

Case (a) and (b) represent a broader compromise of the developer's machine — if an attacker can write arbitrary files to the workspace, they have many higher-value attack vectors available (modifying committed code, adding malicious git hooks, accessing credentials directly). The `.local.md` injection surface is not the primary concern in this scenario.

Case (c) — intentional policy bypass — is more interesting. A developer could use `.local.md` to inject personal instructions that deviate from team-agreed conventions, and this deviation would not be visible in the repo. For example, bypassing security review requirements or changing label lifecycle behavior. This is a legitimate concern for teams with strong compliance requirements.

**Mitigations in the current design:**

- The design document already acknowledges this risk: "Users should be aware that `.local.md` files can inject arbitrary instructions into skill context."
- `.local.md` scope is single-developer, single-machine. The impact of any injection is limited to that developer's workflow sessions.
- Teams that cannot accept unaudited instruction injection can prohibit `.local.md` use via team policy. There is no technical enforcement, but it can be documented as a team convention.

**Gap:** The design names the risk but does not distinguish between the machine-compromise scenario (out of scope; broader threat) and the intentional-bypass scenario (in scope; team policy question). Teams with strict compliance requirements would benefit from clearer guidance on whether `.local.md` is appropriate for their context.

**Recommendation:** No design changes needed. Document the `.local.md` risk with clearer framing: the primary concern is intentional policy bypass by a developer, not external compromise. Teams with compliance requirements should decide whether to allow `.local.md` use and make that decision a team convention.

---

### Shell Script Execution

**Applies: Yes. Severity: Medium (same trust tier as the plugin's markdown content).**

shirabe's `scripts/` directory ships shell scripts (currently `transition-status.sh`) that skills invoke via the Bash tool. If these scripts are tampered with — whether through a compromised plugin release or a local filesystem modification — the malicious script runs with the full permissions of the developer's shell.

This is a real elevation compared to the markdown-only surface: markdown instructs an LLM, which still goes through tool confirmation. Shell scripts execute directly when the Bash tool is invoked. A malicious `transition-status.sh` that also exfiltrates environment variables or modifies `.git/hooks` would execute without the LLM being aware of the addition.

However, the trust level for scripts in the plugin directory is the same as for the SKILL.md files themselves. If the plugin is compromised at the release level, both the markdown and the scripts are hostile. Consumers who audit the plugin's markdown would need to also audit the scripts — this is an existing requirement, but worth making explicit.

The design's note that "shirabe is a Claude Code plugin — it ships markdown files" slightly undersells the scripts dimension. Scripts are shipped alongside the markdown.

Consumer-authored scripts (those invoked from extension files, such as label lifecycle scripts) present a similar picture: they live in the consumer's repo, subject to the same code review process as extension files. A malicious consumer script carries the same risk as a malicious extension file.

**Mitigations in the current design:**

- Scripts live in the plugin's committed `scripts/` directory; consumers can inspect them.
- Claude Code's Bash tool execution path is visible to users — a skill that calls a suspicious script path would surface the call in the tool use log.
- The current `scripts/` directory contains only one script (`transition-status.sh`) with a narrow, well-defined purpose (design doc status transitions). Attack surface is currently small.
- No scripts download from the network, execute binaries fetched at runtime, or require elevated privileges.

**Gap:** The design's security section statement that shirabe "does not execute code" is technically imprecise — `scripts/` shell scripts do execute code via the Bash tool. The statement appears to mean "does not download or compile code at install time," which is accurate, but the phrasing could mislead a reader into underweighting the scripts dimension.

**Recommendation:** Correct the Security Considerations statement to acknowledge that shell scripts in `scripts/` execute via the Bash tool, are subject to the same review requirements as the markdown skills, and carry the same trust level as a compromised plugin release. No structural design changes are needed, but the documentation should be precise.

---

## Recommended Outcome

**Option 2: Document considerations.**

No structural design changes are needed. The extensibility mechanism is sound for its threat model:

- Extension files operate at the same trust level as CLAUDE.md, which is an existing accepted trust boundary in Claude Code deployments.
- The supply chain risk is standard for any plugin dependency and is bounded by Claude Code's tool approval model.
- The `.local.md` risk is scoped to single-developer, single-machine and is already acknowledged in the design.
- Shell script execution is real but carries the same trust as the plugin's markdown content.

What the design needs is tighter language in three places:

1. The statement "does not execute code" should be corrected to "does not download or compile code at install time; shell scripts in `scripts/` execute via the Bash tool and carry the same trust as the plugin's markdown content."
2. The extension file trust should be stated explicitly: `.claude/skill-extensions/` files are privileged configuration equivalent to CLAUDE.md and should receive the same review scrutiny in PRs.
3. The supply chain note should name the plugin itself as the supply chain risk rather than implying no supply chain exposure exists.

---

## Summary

All four security dimensions apply, none at high severity given the system's trust model. The extensibility design does not introduce novel attack surfaces beyond what already exists in Claude Code's CLAUDE.md mechanism and standard plugin distribution. The main gaps are documentation imprecision rather than structural flaws:

- Extension files are as powerful as CLAUDE.md and should be reviewed with equivalent care, but the design doesn't say this explicitly.
- Shell scripts execute real code and deserve mention alongside the markdown content, not after a statement that the plugin "doesn't execute code."
- The `.local.md` gitignore risk is acknowledged but would benefit from clearer framing for compliance-oriented teams.

Recommended action: **Option 2 — document the considerations** with targeted wording corrections in the Security Considerations section. No design changes are needed.
