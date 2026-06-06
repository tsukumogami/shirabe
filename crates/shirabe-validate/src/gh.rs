//! GitHub client surface for the FC09 doc-vs-GitHub reconciliation check.
//!
//! The module declares the [`IssueStateClient`] trait FC09 consumes
//! polymorphically, the [`IssueState`] and [`ClientError`] data types,
//! the production [`GhSubprocessClient`] that shells out to `gh api`,
//! the test-only [`MockIssueStateClient`] stand-in (cfg(test)), and the
//! [`detect_pr_context`] env-var reader.
//!
//! The transport choice is documented in
//! `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`
//! Decision 1: the production client shells out to `gh api`, so the
//! validator process never holds the GitHub token bytes. The trait
//! surface (Decision 2) keeps the test path independent of `gh` itself
//! -- every FC09 test consumes the [`MockIssueStateClient`] and runs in
//! offline CI.
//!
//! Per-request timeout is 5 seconds (Decision 5), enforced via the
//! user-space poll-and-kill loop in
//! [`GhSubprocessClient::run_gh_api`]. Subprocess stdout is capped at
//! 4 MiB; overshoot returns
//! [`ClientError::Malformed`]. The retry-on-rate-limit policy lives at
//! the call site in `check_fc09`, not inside the client (Decision 5).
//!
//! [`ClientError::Malformed`] carries a `String` payload for
//! in-crate debugging; the payload is **never** embedded in a notice
//! body, log message, or any user-visible surface. The R17
//! public-cleanliness scan verifies this invariant; future changes that
//! move the payload into user-visible output require a follow-up
//! review.

use std::process::{Command, Stdio};
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use regex::Regex;

/// The state of a GitHub issue or pull request, narrowed to the two
/// outcomes FC09 reconciles against.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IssueState {
    Open,
    Closed,
}

/// The failure modes [`IssueStateClient`] surfaces to its caller.
///
/// `Malformed` carries a `String` payload used by unit-test assertions
/// only; production code paths discard the payload (see the module
/// doc-comment).
#[derive(Clone, Debug)]
pub enum ClientError {
    /// `gh auth status` reported no usable token at construction; every
    /// subsequent `fetch_*` returns this variant.
    Auth,
    /// The issue or PR does not exist, or the `(owner, repo, number)`
    /// triple failed the argument-validation gate.
    NotFound,
    /// The token cannot read the target repo (cross-repo private access
    /// or org-restricted ref).
    Forbidden,
    /// `gh api` reported a rate-limit defect (primary or secondary).
    RateLimit,
    /// Subprocess spawn failure, timeout, or any other nonzero exit not
    /// matching a recognised pattern.
    Network,
    /// Output failed defensive parsing (unexpected JSON shape,
    /// truncated stream, or response exceeded the 4 MiB ceiling). The
    /// payload is for in-crate debugging only and is never emitted to a
    /// user-visible surface.
    Malformed(String),
}

/// PR-context derived from environment variables. FC09's Sub-check C
/// engages only when [`detect_pr_context`] resolves a `Some` value.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PrContext {
    pub owner: String,
    pub repo: String,
    pub number: u64,
}

/// The trait FC09 calls into to read GitHub issue and PR state. The
/// production impl is [`GhSubprocessClient`]; tests construct a
/// [`MockIssueStateClient`] with canned responses per
/// `(owner, repo, number)` tuple.
pub trait IssueStateClient {
    fn fetch_issue_state(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<IssueState, ClientError>;

    fn fetch_pr_body(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<String, ClientError>;
}

/// Per-request timeout for `gh api` calls, in seconds. Matches DESIGN
/// Decision 5.
const SUBPROCESS_TIMEOUT_SECS: u64 = 5;

/// Stdout byte ceiling per `gh api` call. Matches DESIGN Security
/// Considerations / "Subprocess output byte bound".
const SUBPROCESS_OUTPUT_CEILING_BYTES: usize = 4 * 1024 * 1024;

/// Poll interval for the timeout-enforcement loop.
const SUBPROCESS_POLL_INTERVAL_MS: u64 = 50;

/// GitHub's documented limits for owner and repo names.
static OWNER_REPO_VALIDATOR: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$").unwrap());

/// Matches the GHA pull-request ref shape `refs/pull/<n>/merge`.
static GITHUB_REF_PR_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^refs/pull/(\d+)/merge$").unwrap());

/// Validates that an `owner` or `repo` substring conforms to GitHub's
/// documented character set. Used in every source path before the
/// substring reaches `gh api` or a notice body (DESIGN Security
/// Considerations / "Subprocess spawning and argument validation").
pub fn is_valid_owner_or_repo(s: &str) -> bool {
    OWNER_REPO_VALIDATOR.is_match(s)
}

/// Resolves the PR context from environment variables.
///
/// Priority order (DESIGN Decision 7):
///
/// 1. `SHIRABE_PR_NUMBER` parsed as `u64`. On parse failure, treated as
///    absent.
/// 2. `GITHUB_REF` matched against `^refs/pull/(\d+)/merge$`. Other
///    shapes are silently ignored.
///
/// `owner` and `repo` come from `GITHUB_REPOSITORY` of form
/// `<owner>/<repo>`. If `GITHUB_REPOSITORY` is unset or malformed, the
/// context is `None` regardless of whether a PR number resolved.
///
/// `owner` and `repo` substrings are validated against the same
/// character-set gate every other source path uses (Sub-check C
/// cross-repo references, row Dependencies cell cross-repo refs).
pub fn detect_pr_context() -> Option<PrContext> {
    // Resolve the PR number first; either source must produce a usable
    // u64 or the function returns None.
    let number: u64 = if let Some(raw) = read_nonempty_env("SHIRABE_PR_NUMBER") {
        match raw.parse::<u64>() {
            Ok(n) => n,
            Err(_) => return resolve_pr_from_github_ref().and_then(|n| build_pr_context(n)),
        }
    } else if let Some(n) = resolve_pr_from_github_ref() {
        n
    } else {
        return None;
    };

    build_pr_context(number)
}

fn build_pr_context(number: u64) -> Option<PrContext> {
    let repo_env = read_nonempty_env("GITHUB_REPOSITORY")?;
    let (owner, repo) = repo_env.split_once('/')?;
    if owner.is_empty() || repo.is_empty() {
        return None;
    }
    if !is_valid_owner_or_repo(owner) || !is_valid_owner_or_repo(repo) {
        return None;
    }
    // Reject any owner/repo string that itself contains a path
    // separator beyond the first split; GitHub never includes one but
    // a malformed env var could.
    if repo.contains('/') {
        return None;
    }
    Some(PrContext {
        owner: owner.to_string(),
        repo: repo.to_string(),
        number,
    })
}

fn resolve_pr_from_github_ref() -> Option<u64> {
    let raw = read_nonempty_env("GITHUB_REF")?;
    let caps = GITHUB_REF_PR_RE.captures(&raw)?;
    caps.get(1)?.as_str().parse::<u64>().ok()
}

fn read_nonempty_env(name: &str) -> Option<String> {
    match std::env::var(name) {
        Ok(v) if !v.is_empty() => Some(v),
        _ => None,
    }
}

/// Production [`IssueStateClient`] backed by `gh api`. The `auth_ok`
/// field is set once at construction by running `gh auth status`; when
/// the probe exits non-zero, every subsequent `fetch_*` short-circuits
/// to `Err(ClientError::Auth)` without spawning `gh api`.
pub struct GhSubprocessClient {
    timeout: Duration,
    gh_bin: String,
    auth_ok: bool,
}

impl GhSubprocessClient {
    /// Constructs a new client. Runs `gh auth status` once; the exit
    /// code determines `auth_ok`. The `gh` binary path is the literal
    /// `"gh"` (resolved via `$PATH`); there is no attacker-controllable
    /// surface that re-points the binary.
    pub fn new() -> Self {
        let gh_bin = "gh".to_string();
        let auth_ok = probe_auth(&gh_bin);
        Self {
            timeout: Duration::from_secs(SUBPROCESS_TIMEOUT_SECS),
            gh_bin,
            auth_ok,
        }
    }

    /// Run `gh api <path>` and return its stdout as a `String`. Returns
    /// `Err(ClientError::Auth)` immediately when `auth_ok` is false.
    fn run_gh_api(&self, path: &str) -> Result<String, ClientError> {
        if !self.auth_ok {
            return Err(ClientError::Auth);
        }
        let mut child = Command::new(&self.gh_bin)
            .args(["api", path])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|_| ClientError::Network)?;

        let deadline = Instant::now() + self.timeout;
        let exit_status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {
                    if Instant::now() >= deadline {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Err(ClientError::Network);
                    }
                    std::thread::sleep(Duration::from_millis(SUBPROCESS_POLL_INTERVAL_MS));
                }
                Err(_) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(ClientError::Network);
                }
            }
        };

        // Drain stdout under the 4 MiB ceiling.
        let stdout = drain_capped(child.stdout.take())?;
        let stderr = drain_capped(child.stderr.take()).unwrap_or_default();

        if exit_status.success() {
            return Ok(stdout);
        }

        Err(classify_stderr(&stderr))
    }
}

impl Default for GhSubprocessClient {
    fn default() -> Self {
        Self::new()
    }
}

impl IssueStateClient for GhSubprocessClient {
    fn fetch_issue_state(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<IssueState, ClientError> {
        if !is_valid_owner_or_repo(owner) || !is_valid_owner_or_repo(repo) {
            return Err(ClientError::NotFound);
        }
        let path = format!("repos/{}/{}/issues/{}", owner, repo, number);
        let body = self.run_gh_api(&path)?;
        let state = extract_top_level_string(&body, "state").map_err(ClientError::Malformed)?;
        match state.as_str() {
            "open" => Ok(IssueState::Open),
            "closed" => Ok(IssueState::Closed),
            other => Err(ClientError::Malformed(format!(
                "unexpected state value: {}",
                other
            ))),
        }
    }

    fn fetch_pr_body(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<String, ClientError> {
        if !is_valid_owner_or_repo(owner) || !is_valid_owner_or_repo(repo) {
            return Err(ClientError::NotFound);
        }
        let path = format!("repos/{}/{}/pulls/{}", owner, repo, number);
        let body = self.run_gh_api(&path)?;
        extract_top_level_string(&body, "body").map_err(ClientError::Malformed)
    }
}

/// Reads from the optional stream into a `String`, capping at the
/// 4 MiB ceiling. Returns `ClientError::Malformed` on overshoot.
fn drain_capped(stream: Option<impl std::io::Read>) -> Result<String, ClientError> {
    let mut buf = Vec::with_capacity(4096);
    let mut tmp = [0u8; 8192];
    if let Some(mut s) = stream {
        loop {
            match s.read(&mut tmp) {
                Ok(0) => break,
                Ok(n) => {
                    if buf.len() + n > SUBPROCESS_OUTPUT_CEILING_BYTES {
                        return Err(ClientError::Malformed(
                            "response exceeded 4 MiB ceiling".to_string(),
                        ));
                    }
                    buf.extend_from_slice(&tmp[..n]);
                }
                Err(_) => return Err(ClientError::Network),
            }
        }
    }
    String::from_utf8(buf).map_err(|e| ClientError::Malformed(format!("invalid utf-8: {}", e)))
}

/// Maps `gh api` stderr to the appropriate `ClientError` variant. The
/// rate-limit patterns are pinned against the current `gh` wording; an
/// unrecognised non-zero exit downgrades to `Network` rather than
/// reporting a false rate-limit (DESIGN Consequences / Mitigations).
fn classify_stderr(stderr: &str) -> ClientError {
    let lc = stderr.to_lowercase();
    if lc.contains("api rate limit exceeded") || lc.contains("secondary rate limit") {
        return ClientError::RateLimit;
    }
    if lc.contains("http 403") || lc.contains("403 forbidden") {
        return ClientError::Forbidden;
    }
    if lc.contains("http 404") || lc.contains("404 not found") {
        return ClientError::NotFound;
    }
    ClientError::Network
}

/// Runs `gh auth status` and returns true on a zero exit code.
fn probe_auth(gh_bin: &str) -> bool {
    Command::new(gh_bin)
        .arg("auth")
        .arg("status")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Extract the value of a top-level JSON string field from a JSON
/// object body, ignoring nested fields with the same name.
///
/// The algorithm: locate the outermost `{...}` via brace-depth
/// counting (no recursion), then at depth-1 attempt to match
/// `"<name>"\s*:\s*"<value>"` where the value may contain JSON
/// `\"`/`\\` escapes. Returns the unescaped value on success or an
/// error message string on failure (the caller wraps in
/// `ClientError::Malformed`).
fn extract_top_level_string(body: &str, name: &str) -> Result<String, String> {
    let bytes = body.as_bytes();
    let mut depth: usize = 0;
    let mut i: usize = 0;
    while i < bytes.len() {
        let b = bytes[i];
        match b {
            b'{' => {
                depth += 1;
                i += 1;
            }
            b'}' => {
                depth = depth.saturating_sub(1);
                i += 1;
            }
            b'"' if depth == 1 => {
                // Try to match `"<name>" : "value"` starting at i.
                if let Some((value, _after)) = try_match_kv(bytes, i, name) {
                    return Ok(value);
                } else {
                    i = skip_string_literal(bytes, i)?;
                }
            }
            b'"' => {
                // Skip over string literals at any depth so braces inside
                // strings do not perturb the depth counter.
                i = skip_string_literal(bytes, i)?;
            }
            _ => i += 1,
        }
    }
    Err(format!("top-level field {:?} not found", name))
}

/// If `bytes` at offset `i` begins with `"<name>"`, then optional
/// whitespace, a colon, optional whitespace, and a `"..."` JSON string
/// value, return the unescaped value and the byte offset after the
/// closing quote. Otherwise return `None`.
fn try_match_kv(bytes: &[u8], i: usize, name: &str) -> Option<(String, usize)> {
    let name_with_quotes = format!("\"{}\"", name);
    let name_bytes = name_with_quotes.as_bytes();
    if i + name_bytes.len() > bytes.len() {
        return None;
    }
    if &bytes[i..i + name_bytes.len()] != name_bytes {
        return None;
    }
    let mut j = i + name_bytes.len();
    // Skip whitespace, expect colon.
    while j < bytes.len() && matches!(bytes[j], b' ' | b'\t' | b'\n' | b'\r') {
        j += 1;
    }
    if j >= bytes.len() || bytes[j] != b':' {
        return None;
    }
    j += 1;
    while j < bytes.len() && matches!(bytes[j], b' ' | b'\t' | b'\n' | b'\r') {
        j += 1;
    }
    if j >= bytes.len() {
        return None;
    }
    // Value must be a JSON string literal.
    if bytes[j] != b'"' {
        return None;
    }
    j += 1;
    let mut out = String::new();
    while j < bytes.len() {
        let b = bytes[j];
        if b == b'\\' {
            // Escape sequence.
            if j + 1 >= bytes.len() {
                return None;
            }
            match bytes[j + 1] {
                b'"' => out.push('"'),
                b'\\' => out.push('\\'),
                b'/' => out.push('/'),
                b'n' => out.push('\n'),
                b't' => out.push('\t'),
                b'r' => out.push('\r'),
                b'b' => out.push('\u{0008}'),
                b'f' => out.push('\u{000C}'),
                b'u' => {
                    // \uXXXX -- take next 4 hex chars, decode as BMP.
                    if j + 6 > bytes.len() {
                        return None;
                    }
                    let hex = std::str::from_utf8(&bytes[j + 2..j + 6]).ok()?;
                    let cp = u32::from_str_radix(hex, 16).ok()?;
                    if let Some(c) = char::from_u32(cp) {
                        out.push(c);
                    } else {
                        // Surrogate or invalid; substitute replacement.
                        out.push('\u{FFFD}');
                    }
                    j += 6;
                    continue;
                }
                other => {
                    // Unknown escape -- pass through literally.
                    out.push('\\');
                    out.push(other as char);
                }
            }
            j += 2;
        } else if b == b'"' {
            // Closing quote.
            return Some((out, j + 1));
        } else {
            // UTF-8 multi-byte sequences pass through unchanged. The
            // string was already validated as UTF-8 before this scan.
            out.push(b as char);
            j += 1;
        }
    }
    None
}

/// Skip past a JSON string literal starting at `bytes[i]` (where
/// `bytes[i] == '"'`), accounting for `\\` and `\"` escapes. Returns
/// the offset after the closing quote, or an error message string if
/// the literal is unterminated.
fn skip_string_literal(bytes: &[u8], i: usize) -> Result<usize, String> {
    let mut j = i + 1;
    while j < bytes.len() {
        let b = bytes[j];
        if b == b'\\' {
            if j + 1 >= bytes.len() {
                return Err("unterminated string escape".to_string());
            }
            j += 2;
        } else if b == b'"' {
            return Ok(j + 1);
        } else {
            j += 1;
        }
    }
    Err("unterminated string literal".to_string())
}

// ----------------------------------------------------------------------
// Test stand-in
// ----------------------------------------------------------------------

#[cfg(test)]
pub(crate) struct MockIssueStateClient {
    pub issues: std::collections::HashMap<(String, String, u64), Result<IssueState, ClientError>>,
    pub prs: std::collections::HashMap<(String, String, u64), Result<String, ClientError>>,
}

#[cfg(test)]
impl MockIssueStateClient {
    pub fn new() -> Self {
        Self {
            issues: std::collections::HashMap::new(),
            prs: std::collections::HashMap::new(),
        }
    }

    pub fn with_issue(
        mut self,
        owner: &str,
        repo: &str,
        number: u64,
        result: Result<IssueState, ClientError>,
    ) -> Self {
        self.issues
            .insert((owner.to_string(), repo.to_string(), number), result);
        self
    }

    pub fn with_pr(
        mut self,
        owner: &str,
        repo: &str,
        number: u64,
        result: Result<String, ClientError>,
    ) -> Self {
        self.prs
            .insert((owner.to_string(), repo.to_string(), number), result);
        self
    }
}

#[cfg(test)]
impl IssueStateClient for MockIssueStateClient {
    fn fetch_issue_state(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<IssueState, ClientError> {
        self.issues
            .get(&(owner.to_string(), repo.to_string(), number))
            .cloned()
            .unwrap_or(Err(ClientError::NotFound))
    }

    fn fetch_pr_body(
        &self,
        owner: &str,
        repo: &str,
        number: u64,
    ) -> Result<String, ClientError> {
        self.prs
            .get(&(owner.to_string(), repo.to_string(), number))
            .cloned()
            .unwrap_or(Err(ClientError::NotFound))
    }
}

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // --- detect_pr_context env-var matrix (Decision 7) ---

    /// RAII guard restoring an env var to its pre-test value (or
    /// removing it if previously unset) on drop. Lets each test set
    /// vars without leaking state into adjacent tests.
    struct EnvGuard {
        names: Vec<String>,
        prior: Vec<Option<String>>,
    }

    impl EnvGuard {
        fn new(names: &[&str]) -> Self {
            let prior = names.iter().map(|n| std::env::var(n).ok()).collect();
            for n in names {
                std::env::remove_var(n);
            }
            Self {
                names: names.iter().map(|s| s.to_string()).collect(),
                prior,
            }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            for (name, prior) in self.names.iter().zip(self.prior.iter()) {
                match prior {
                    Some(v) => std::env::set_var(name, v),
                    None => std::env::remove_var(name),
                }
            }
        }
    }

    // The env tests share a static mutex so they cannot run concurrently
    // and stomp on each other's env state. Standard library mutex; no
    // external dep.
    static ENV_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn detect_pr_context_override_only() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("SHIRABE_PR_NUMBER", "42");
        std::env::set_var("GITHUB_REPOSITORY", "tsukumogami/shirabe");
        let ctx = detect_pr_context().expect("expected Some");
        assert_eq!(
            ctx,
            PrContext {
                owner: "tsukumogami".to_string(),
                repo: "shirabe".to_string(),
                number: 42,
            }
        );
    }

    #[test]
    fn detect_pr_context_github_ref_only() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("GITHUB_REF", "refs/pull/153/merge");
        std::env::set_var("GITHUB_REPOSITORY", "tsukumogami/shirabe");
        let ctx = detect_pr_context().expect("expected Some");
        assert_eq!(ctx.number, 153);
        assert_eq!(ctx.owner, "tsukumogami");
        assert_eq!(ctx.repo, "shirabe");
    }

    #[test]
    fn detect_pr_context_both_set_override_wins() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("SHIRABE_PR_NUMBER", "99");
        std::env::set_var("GITHUB_REF", "refs/pull/100/merge");
        std::env::set_var("GITHUB_REPOSITORY", "tsukumogami/shirabe");
        let ctx = detect_pr_context().expect("expected Some");
        assert_eq!(ctx.number, 99);
    }

    #[test]
    fn detect_pr_context_neither_set_returns_none() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        assert!(detect_pr_context().is_none());
    }

    #[test]
    fn detect_pr_context_malformed_github_ref_ignored() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("GITHUB_REF", "refs/heads/main");
        std::env::set_var("GITHUB_REPOSITORY", "tsukumogami/shirabe");
        assert!(detect_pr_context().is_none());
    }

    #[test]
    fn detect_pr_context_malformed_repository_returns_none() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("SHIRABE_PR_NUMBER", "42");
        std::env::set_var("GITHUB_REPOSITORY", "not-a-slash-separated-string");
        assert!(detect_pr_context().is_none());
    }

    #[test]
    fn detect_pr_context_malformed_override_falls_through_to_ref() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("SHIRABE_PR_NUMBER", "not-a-number");
        std::env::set_var("GITHUB_REF", "refs/pull/77/merge");
        std::env::set_var("GITHUB_REPOSITORY", "tsukumogami/shirabe");
        let ctx = detect_pr_context().expect("expected Some");
        assert_eq!(ctx.number, 77);
    }

    #[test]
    fn detect_pr_context_repository_with_invalid_chars_returns_none() {
        let _lock = ENV_MUTEX.lock().unwrap();
        let _g = EnvGuard::new(&["SHIRABE_PR_NUMBER", "GITHUB_REF", "GITHUB_REPOSITORY"]);
        std::env::set_var("SHIRABE_PR_NUMBER", "42");
        std::env::set_var("GITHUB_REPOSITORY", "bad name/with spaces");
        assert!(detect_pr_context().is_none());
    }

    // --- is_valid_owner_or_repo ---

    #[test]
    fn owner_repo_validator_accepts_canonical_shapes() {
        assert!(is_valid_owner_or_repo("tsukumogami"));
        assert!(is_valid_owner_or_repo("shirabe"));
        assert!(is_valid_owner_or_repo("dot-niwa-overlay"));
        assert!(is_valid_owner_or_repo("Repo.Name_With-Mix"));
        assert!(is_valid_owner_or_repo("a"));
    }

    #[test]
    fn owner_repo_validator_rejects_malformed() {
        assert!(!is_valid_owner_or_repo(""));
        assert!(!is_valid_owner_or_repo("-leading-dash"));
        assert!(!is_valid_owner_or_repo(".leading-dot"));
        assert!(!is_valid_owner_or_repo("has space"));
        assert!(!is_valid_owner_or_repo("has/slash"));
        // 40 characters exceeds GitHub's 39-char limit.
        let too_long = "a".repeat(40);
        assert!(!is_valid_owner_or_repo(&too_long));
    }

    // --- Mock client ---

    #[test]
    fn mock_returns_canned_open_for_known_issue() {
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 42, Ok(IssueState::Open));
        assert_eq!(
            mock.fetch_issue_state("tsukumogami", "shirabe", 42).unwrap(),
            IssueState::Open
        );
    }

    #[test]
    fn mock_returns_canned_closed_for_known_issue() {
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 42, Ok(IssueState::Closed));
        assert_eq!(
            mock.fetch_issue_state("tsukumogami", "shirabe", 42).unwrap(),
            IssueState::Closed
        );
    }

    #[test]
    fn mock_returns_not_found_for_unknown_issue() {
        let mock = MockIssueStateClient::new();
        assert!(matches!(
            mock.fetch_issue_state("tsukumogami", "shirabe", 99),
            Err(ClientError::NotFound)
        ));
    }

    #[test]
    fn mock_returns_canned_rate_limit() {
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "shirabe", 1, Err(ClientError::RateLimit));
        assert!(matches!(
            mock.fetch_issue_state("tsukumogami", "shirabe", 1),
            Err(ClientError::RateLimit)
        ));
    }

    #[test]
    fn mock_returns_canned_forbidden() {
        let mock = MockIssueStateClient::new()
            .with_issue("tsukumogami", "private", 1, Err(ClientError::Forbidden));
        assert!(matches!(
            mock.fetch_issue_state("tsukumogami", "private", 1),
            Err(ClientError::Forbidden)
        ));
    }

    #[test]
    fn mock_returns_canned_malformed() {
        let mock = MockIssueStateClient::new().with_issue(
            "tsukumogami",
            "shirabe",
            1,
            Err(ClientError::Malformed("test".to_string())),
        );
        assert!(matches!(
            mock.fetch_issue_state("tsukumogami", "shirabe", 1),
            Err(ClientError::Malformed(_))
        ));
    }

    #[test]
    fn mock_pr_body_round_trip() {
        let mock = MockIssueStateClient::new().with_pr(
            "tsukumogami",
            "shirabe",
            153,
            Ok("Closes #42\n".to_string()),
        );
        assert_eq!(
            mock.fetch_pr_body("tsukumogami", "shirabe", 153).unwrap(),
            "Closes #42\n"
        );
    }

    // --- extract_top_level_string ---

    #[test]
    fn extract_top_level_state_open() {
        let body = r#"{"id":1,"state":"open","milestone":{"state":"closed"}}"#;
        assert_eq!(extract_top_level_string(body, "state").unwrap(), "open");
    }

    #[test]
    fn extract_top_level_state_closed() {
        let body = r#"{"id":1,"state":"closed"}"#;
        assert_eq!(extract_top_level_string(body, "state").unwrap(), "closed");
    }

    #[test]
    fn extract_top_level_skips_nested_state() {
        // The nested `state` must NOT match; only the top-level one does.
        let body = r#"{"milestone":{"state":"open"},"state":"closed"}"#;
        assert_eq!(extract_top_level_string(body, "state").unwrap(), "closed");
    }

    #[test]
    fn extract_top_level_body_with_escapes() {
        let body = r#"{"body":"line one\nline two\nCloses #42"}"#;
        let extracted = extract_top_level_string(body, "body").unwrap();
        assert_eq!(extracted, "line one\nline two\nCloses #42");
    }

    #[test]
    fn extract_top_level_field_missing() {
        let body = r#"{"id":1}"#;
        assert!(extract_top_level_string(body, "state").is_err());
    }

    #[test]
    fn extract_top_level_handles_strings_with_braces() {
        // Braces inside JSON strings must not perturb the depth counter.
        let body = r#"{"body":"text with } brace","state":"open"}"#;
        assert_eq!(extract_top_level_string(body, "state").unwrap(), "open");
    }

    // --- classify_stderr ---

    #[test]
    fn classify_rate_limit_primary() {
        assert!(matches!(
            classify_stderr("gh: API rate limit exceeded for ..."),
            ClientError::RateLimit
        ));
    }

    #[test]
    fn classify_rate_limit_secondary() {
        assert!(matches!(
            classify_stderr("gh: You have exceeded a secondary rate limit"),
            ClientError::RateLimit
        ));
    }

    #[test]
    fn classify_forbidden() {
        assert!(matches!(
            classify_stderr("HTTP 403: Resource not accessible"),
            ClientError::Forbidden
        ));
    }

    #[test]
    fn classify_not_found() {
        assert!(matches!(
            classify_stderr("HTTP 404: Not Found"),
            ClientError::NotFound
        ));
    }

    #[test]
    fn classify_unknown_falls_back_to_network() {
        assert!(matches!(
            classify_stderr("some other error"),
            ClientError::Network
        ));
    }

    // --- GhSubprocessClient::new() ---

    #[test]
    fn gh_subprocess_client_constructs_without_panicking() {
        // The `gh auth status` probe should not panic regardless of
        // whether gh is on the PATH.
        let _client = GhSubprocessClient::new();
    }

    #[test]
    fn gh_subprocess_client_auth_failure_short_circuits_fetch() {
        // Force auth_ok false by constructing the struct with an
        // intentionally-missing gh binary path. Note: this exercises
        // the auth_ok short-circuit; a missing gh binary triggers
        // ClientError::Auth from the `!auth_ok` check at the top of
        // run_gh_api.
        let client = GhSubprocessClient {
            timeout: Duration::from_secs(SUBPROCESS_TIMEOUT_SECS),
            gh_bin: "/does/not/exist/gh".to_string(),
            auth_ok: false,
        };
        assert!(matches!(
            client.fetch_issue_state("tsukumogami", "shirabe", 1),
            Err(ClientError::Auth)
        ));
    }

    #[test]
    fn gh_subprocess_client_rejects_invalid_owner() {
        // Even with auth_ok true, an invalid owner/repo string must
        // short-circuit to NotFound before spawning gh.
        let client = GhSubprocessClient {
            timeout: Duration::from_secs(SUBPROCESS_TIMEOUT_SECS),
            gh_bin: "/does/not/exist/gh".to_string(),
            auth_ok: true,
        };
        assert!(matches!(
            client.fetch_issue_state("has space", "shirabe", 1),
            Err(ClientError::NotFound)
        ));
        assert!(matches!(
            client.fetch_issue_state("tsukumogami", "has/slash", 1),
            Err(ClientError::NotFound)
        ));
    }
}
