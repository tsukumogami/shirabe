# Security Review: completion-cascade

## Dimension Analysis

### External Artifact Handling

**Applies:** Yes

The script processes external inputs in several places, and the risk profile varies by source.

**`upstream` field — path traversal**

The `upstream` frontmatter field is read from a local markdown file and used as a filesystem path without any validation shown in the design. A crafted document with a value like `upstream: ../../../etc/passwd` or `upstream: /tmp/attacker-controlled.md` would cause the script to read an arbitrary file. Because the script then branches on `basename "$next"` to decide what transition handler to call, a value like `upstream: /tmp/DESIGN-evil.md` passes the `DESIGN-*` pattern and routes to `handle_design`, which runs `awk` to strip a section and calls a transition script — all against the attacker-supplied path. If the path points outside the working tree, the script operates on files it should never touch.

Severity: **Medium**. Exploitation requires a crafted document already in the repo. The main realistic threat is an accidentally misconfigured `upstream` field that causes the script to corrupt or delete an unrelated file rather than a direct remote attack vector.

Mitigations:
- Canonicalize the resolved path and assert it falls inside the repository root before use. In Bash: `realpath --relative-to="$REPO_ROOT" "$next"` and reject paths that start with `..` or are absolute outside `$REPO_ROOT`.
- Reject any `upstream` value that is an absolute path outside the repository.
- Apply the same guard before passing the path to `git rm`.

**GitHub URL in `check_issue_closed`**

The GitHub URL is read from frontmatter and passed to `gh api`. A crafted value like `upstream` or an embedded issue URL of `https://github.com/attacker/repo/issues/1` would query an entirely different repository. More concretely, if the URL field contains shell metacharacters and the script interpolates it without quoting (e.g., `gh api $url` rather than `gh api "$url"`), command injection is possible.

Severity: **Medium** if interpolated unquoted; **Low** if properly quoted. Unquoted variable expansion with a URL like `https://x.com/; rm -rf ~/.tsuku` is a classic injection.

Mitigations:
- Always double-quote variables passed to `gh api`: `gh api "$url"`.
- Validate the URL matches the expected GitHub API pattern (`^https://api.github.com/repos/[^/]+/[^/]+/issues/[0-9]+$` or similar) before use.
- Use `gh issue view` with explicit `--repo` and issue number extracted separately, rather than passing a raw URL.

### Permission Scope

**Applies:** Yes

The script acquires a broad set of permissions:

- **Filesystem writes**: It calls `git rm` on the PLAN doc, writes modified DESIGN and ROADMAP files, and calls `git commit` and `git push`. A path traversal in `upstream` (above) could expand this to arbitrary deletions or overwrites.
- **Network access**: `gh api` is authenticated with the user's stored GitHub token. If a crafted URL causes it to query a different repo, the token is sent to GitHub for that request — but GitHub's own auth controls prevent accessing repos the token does not have permission to.
- **Process execution**: The script calls per-skill `transition-status.sh` scripts via `case`/`handle_*` dispatch. The script locates these by convention (path relative to skill directory), so they are not external. However, if `upstream` traversal is exploited to route to an unexpected file that matches a `*` glob in a future `case` extension, unintended scripts could be invoked.
- **Git push**: Pushing inside the script without user confirmation means a single run can permanently alter remote history. A bug or crafted input causing the wrong files to be staged and committed would be pushed immediately.

Severity: **Medium**. The push-on-success behavior amplifies the blast radius of any path confusion or input handling bug.

Mitigations:
- Separate the commit/push step: perform a dry-run first that prints what would be staged, then require explicit confirmation or a `--commit` flag before pushing.
- Scope filesystem operations to a validated working-tree boundary.
- Log every file touched before any `git rm` or write operation.

### Supply Chain or Dependency Trust

**Applies:** No

The script does not download binaries, install packages, or fetch remote code at runtime. All dependencies (`git`, `gh`, `awk`, `sed`, `bash`) are system tools expected to be pre-installed. The per-skill `transition-status.sh` scripts are co-located in the repository, so they are under the same version-control provenance as the rest of the codebase.

The one indirect supply-chain note: `gh` delegates authentication to the user's stored credentials. If the user's GitHub token is scoped too broadly (write access to many repos), a crafted cross-repo URL could cause `gh api` to make authenticated write calls elsewhere. This is a configuration concern rather than a design flaw, but it warrants documentation.

### Data Exposure

**Applies:** Yes

**What is accessed:**

- Local markdown files (PLAN, DESIGN, PRD, ROADMAP) — these may contain internal project metadata, issue URLs, and feature descriptions.
- The GitHub token stored by `gh` — used to query issue state.
- Repository commit history — the script constructs and pushes a commit.

**Transmission:**

- `gh api` sends the GitHub token in HTTP headers to `api.github.com`. This is the intended behavior, but a malformed or crafted URL (see above) could direct an authenticated request to a different GitHub repo, leaking that the caller's token has access to it (via a 200 vs. 404 response).
- No file contents are transmitted to external services; only issue-state queries go over the network.

**Severity: Low** for the normal case. The only realistic exposure scenario is the crafted-URL token-probe described above, which reveals access scope rather than actual data.

Mitigations:
- Validate GitHub URLs against the current repository's slug before calling `gh api`.
- Avoid logging the `Authorization` header or any token value; `gh` already handles this, but any wrapper script should not echo the raw `gh` invocation with credentials.

**`awk` strip operation on DESIGN docs**

The `awk` command strips `## Implementation Issues` from a file whose path came from `upstream`. If the path is traversal-exploited to point to a different file, `awk` will silently rewrite it. There is no injection risk from `awk` processing file *contents* (awk reads the file, it does not execute it), but data loss from operating on the wrong file is a real concern already covered under Permission Scope.

**Text substitution on ROADMAP entries**

The design describes updating ROADMAP feature status via text substitution (likely `sed -i`). If the substitution pattern is built from frontmatter-derived values without escaping, a feature name containing `/` or `&` could corrupt the `sed` expression. More critically, a feature name containing a newline could cause sed to interpret additional commands. This is low severity in practice (an attacker would need to control a ROADMAP feature name already committed to the repo), but the design should specify that substitution targets are literals, not regex patterns derived from input.

Mitigations:
- Use fixed-string substitution (`sed 's/literal/replacement/'` with properly escaped arguments, or a Python/awk equivalent that treats both sides as literals).
- Never interpolate frontmatter-derived values directly into `sed` expressions without escaping special characters.

---

## Recommended Outcome

**OPTION 1 - Design changes needed:**

The design should be updated to specify:

1. `upstream` path validation: resolved paths must fall within the repository working tree. Add a `validate_upstream_path` helper that calls `realpath` and rejects out-of-tree results before any file operation.
2. GitHub URL validation: `check_issue_closed` must validate the URL matches the repo's own GitHub slug before invoking `gh api`. Extract owner, repo, and issue number separately rather than passing the full URL as an opaque string.
3. Deferred push: the `git push` step must be separated from the staging/commit step. The script should print a summary of changes and require a `--push` flag or a confirmation prompt before pushing.
4. Literal-safe substitution: ROADMAP text substitution must use fixed-string matching, not a regex derived from frontmatter values.

These are design-level constraints, not implementation details, so they belong in the design doc before implementation begins.

---

## Summary

The primary risks are path traversal via the `upstream` frontmatter field and command injection via unquoted GitHub URL interpolation; both stem from trusting document-derived values without validation before using them as filesystem paths or shell arguments. The design's automatic `git push` on completion amplifies the blast radius of any input-handling mistake, since a single crafted document could cause the script to delete, modify, and push the wrong files. The `awk` and text substitution operations carry lower risk but should use literal rather than regex-derived patterns to avoid corruption from special characters in frontmatter values.
