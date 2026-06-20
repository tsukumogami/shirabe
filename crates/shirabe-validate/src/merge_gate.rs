//! The coordination merge-last gate, resolved live and folded into the
//! `shirabe validate --merge-gate` mode.
//!
//! This module carries the live-`gh` resolution that drives the merge-last
//! gate (F4 / Decision D). It was lifted out of the `shirabe coordination
//! gate`/`verify` verbs so the gate becomes a posture-aware **validate mode**
//! like every other merge-gating check, rather than an asymmetric separate
//! subcommand. The pure cores it routes through ([`decide_gate`],
//! [`decide_visibility_guard`], [`verify_cross_repo_upstream_terminal`],
//! [`redacted_label`]) are unchanged — this module is the live-resolution
//! glue plus the outcome type the CLI renders.
//!
//! The contract lives in `references/coordination-strategy.md`. The security
//! model is the same as the coordination read path:
//!
//! - **Coordination-PR Visibility Rule front door** ([`check_index_visibility`]):
//!   a public coordination PR refuses fail-closed to gate over a private
//!   indexed repo, before any merge state is recomputed.
//! - **F4**: per-PR merge status is recomputed LIVE via `gh` at gate time,
//!   never read from the editable PR body. The only status input the decision
//!   core accepts is the live flag resolved here.
//! - **F1**: every cross-repo identifier is routed through [`redacted_label`]
//!   before it reaches a diagnostic; a private (or unresolvable) ref surfaces
//!   only its opaque node id.
//! - **F5 / R21**: the `gh` reads are read-only; any unresolvable PR/upstream
//!   is folded into not-merged / not-terminal (fail closed).

use crate::coordination::{
    decide_gate, decide_visibility_guard, parse_cross_repo_ref, redacted_label, CrossRepoRef,
    GateDecision, GatePrStatus, GateUpstreamStatus, GuardIndexNode, Visibility,
    VisibilityGuardDecision, VisibilityResolver,
};
use crate::finalize::verify_cross_repo_upstream_terminal;
use crate::gh::{ClientError, GhSubprocessClient, IssueState, IssueStateClient};
use crate::validate::ReviewPosture;

/// Bridges the `gh` client's `fetch_repo_is_public` into the F1
/// [`VisibilityResolver`] trait. Fail-closed: any non-public result, or any
/// resolution error, yields [`Visibility::Private`] so diagnostics redact.
pub struct GhVisibilityResolver<'a> {
    client: &'a GhSubprocessClient,
}

impl<'a> GhVisibilityResolver<'a> {
    /// Construct a resolver backed by a `gh` client.
    pub fn new(client: &'a GhSubprocessClient) -> Self {
        Self { client }
    }
}

impl VisibilityResolver for GhVisibilityResolver<'_> {
    fn visibility(&self, slug: &str) -> Visibility {
        // `slug` is the validated `owner/repo` from a `CrossRepoRef`, so the
        // split is infallible; treat any unexpected shape as private.
        let Some((owner, repo)) = slug.split_once('/') else {
            return Visibility::Private;
        };
        match self.client.fetch_repo_is_public(owner, repo) {
            Ok(true) => Visibility::Public,
            // Non-public or any error: fail closed to private (F1).
            Ok(false) | Err(_) => Visibility::Private,
        }
    }
}

/// Map the `--visibility` flag string onto the coordination PR's own
/// [`Visibility`]. Only the literal `private` declares a private coordination
/// PR; everything else (including the empty default) is treated as public,
/// matching the workspace `--visibility` convention where unset means public.
///
/// Defaulting unset to **public** keeps the strict direction of the
/// Coordination-PR Visibility Rule: an effort that touches a private repo must
/// *opt in* with `--visibility private`, so forgetting the flag fails closed
/// into a refusal rather than silently gating a private repo from a public PR.
pub fn coordination_pr_visibility(flag: &str) -> Visibility {
    if flag.eq_ignore_ascii_case("private") {
        Visibility::Private
    } else {
        Visibility::Public
    }
}

/// The Coordination-PR Visibility Rule front-door check, shared by every path
/// that gates over per-repo PRs. Resolves each indexed PR's repo visibility
/// live (fail-closed to private when unresolvable), builds an F1-redacted label
/// for each node, and routes the set through the pure [`decide_visibility_guard`]
/// decision.
///
/// On `Refuse` the diagnostic is already F1-safe (each label was produced by
/// [`redacted_label`], so a private node surfaces only its opaque node id) — the
/// refusal itself cannot leak a private identifier. Returns the decision so the
/// caller can halt fail-closed before any gate recompute.
pub fn check_index_visibility(
    coordination_visibility: Visibility,
    refs: &[(CrossRepoRef, u64)],
    resolver: &dyn VisibilityResolver,
) -> VisibilityGuardDecision {
    let nodes: Vec<GuardIndexNode> = refs
        .iter()
        .map(|(reference, number)| {
            let node_id = format!("pr-{}", number);
            GuardIndexNode {
                // F1: the label is already redacted — a private node surfaces
                // only its opaque node id, never the raw owner/repo:path.
                label: redacted_label(reference, *number, &node_id, resolver),
                visibility: resolver.visibility(&reference.slug()),
            }
        })
        .collect();
    decide_visibility_guard(coordination_visibility, &nodes)
}

/// Split a `--pr` / `--upstream` argument of shape `owner/repo:path#number`
/// into its `owner/repo:path` reference and the parsed `number`. The `#number`
/// suffix is taken from the **last** `#`, so a path containing `#` is tolerated.
/// Returns `Err` with a diagnostic when the suffix is missing or not a `u64`.
pub fn split_pr_arg(raw: &str) -> Result<(&str, u64), String> {
    let hash = raw
        .rfind('#')
        .ok_or_else(|| "missing `#number` PR suffix".to_string())?;
    let (ref_str, num_str) = (&raw[..hash], &raw[hash + 1..]);
    let number = num_str
        .parse::<u64>()
        .map_err(|_| format!("PR number is not a non-negative integer: {:?}", num_str))?;
    Ok((ref_str, number))
}

/// The resolved outcome of a merge-gate run, mapped by the CLI onto an exit
/// code and a posture-aware message.
///
/// The variants separate the three classes of outcome the gate distinguishes:
///
/// - [`MergeGateOutcome::Pass`] — every indexed PR merged and every upstream
///   terminal. Exit 0 in every posture.
/// - [`MergeGateOutcome::Refused`] — the Coordination-PR Visibility Rule front
///   door refused (a public coordination PR over a private indexed repo). This
///   is a hard, posture-independent refusal: it is fail-closed in every posture
///   (a draft does not soften a visibility leak).
/// - [`MergeGateOutcome::InputError`] — a malformed reference or an
///   authentication failure: a hard input error, posture-independent.
/// - [`MergeGateOutcome::Blocked`] — the gate blocked because an indexed PR is
///   unmerged or an upstream non-terminal. This is the **posture-aware** case,
///   mirroring `effective_severity` for a draft-tolerable code: under `Ready`
///   it enforces (non-zero); under `Draft` it is a notice (exit 0).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MergeGateOutcome {
    /// All indexed PRs merged and all upstreams terminal.
    Pass {
        pr_count: usize,
        upstream_count: usize,
    },
    /// Coordination-PR Visibility Rule refusal; each reason is F1-redacted.
    Refused(Vec<String>),
    /// A hard input error (malformed reference, gh auth failure).
    InputError(String),
    /// The gate blocked; each reason names the offending (redacted) node.
    Blocked(Vec<String>),
}

/// Resolve the merge-last gate live and return its [`MergeGateOutcome`].
///
/// `pr_args` and `upstream_args` are `owner/repo:path#number` strings (the
/// durable index of refs); `visibility_flag` is the coordination PR's own
/// visibility (`--visibility`). The function:
///
/// 1. Parses and validates every `--pr` reference (F2). A malformed reference
///    is a hard [`MergeGateOutcome::InputError`].
/// 2. Applies the Coordination-PR Visibility Rule front door
///    ([`check_index_visibility`]) — a public coordination PR over a private
///    indexed repo is [`MergeGateOutcome::Refused`] before any merge state is
///    read.
/// 3. Recomputes each indexed PR's live merge state via `gh` (F4): `Closed` =>
///    merged, `Open`/any error => not-merged (fail closed). An auth failure is a
///    hard input error.
/// 4. Verifies each upstream terminal via [`verify_cross_repo_upstream_terminal`].
/// 5. Routes the resolved statuses through the pure [`decide_gate`] core and
///    maps `Pass`/`Block` onto the outcome.
///
/// The `resolver` is injected so tests can exercise the visibility front door
/// offline; production passes a [`GhVisibilityResolver`] backed by the same
/// client used for the live reads.
///
/// **Empty index, posture-aware (fail closed under ready).** A ready
/// coordination PR with no indexed PRs and no upstreams must NOT pass: a ready
/// PR asserts the effort is complete, but an empty index means the gate has
/// nothing to prove merge-last against, so it fails closed
/// ([`MergeGateOutcome::Blocked`]) — matching the contract ("the gate is the
/// authority; fail closed") and the lifecycle.yml shell guard. Under `Draft`
/// the index is legitimately empty before any per-repo PR exists, so an empty
/// index stays a pass/notice (exit 0).
pub fn run_merge_gate(
    pr_args: &[String],
    upstream_args: &[String],
    visibility_flag: &str,
    posture: ReviewPosture,
    client: &dyn IssueStateClient,
    resolver: &dyn VisibilityResolver,
) -> MergeGateOutcome {
    // Empty index under ready posture: fail closed. A ready coordination PR
    // with nothing indexed has no merge-last invariant to satisfy, which under
    // the "gate is the authority; fail closed" contract must block rather than
    // vacuously pass. Under draft the empty index is legitimate (no per-repo
    // PRs exist yet), so fall through to the normal vacuous pass.
    if pr_args.is_empty() && upstream_args.is_empty() && posture == ReviewPosture::Ready {
        return MergeGateOutcome::Blocked(vec![
            "ready coordination PR has an empty PR-index; merge-last gate blocks".to_string(),
        ]);
    }

    // Parse + validate every indexed PR reference (F2) up front so the
    // Coordination-PR Visibility Rule front door can run before any live read.
    let mut refs: Vec<(CrossRepoRef, u64)> = Vec::with_capacity(pr_args.len());
    for raw in pr_args {
        let (ref_str, number) = match split_pr_arg(raw) {
            Ok(pair) => pair,
            Err(msg) => {
                return MergeGateOutcome::InputError(format!("invalid --pr {:?}: {}", raw, msg));
            }
        };
        // F2: parse + validate every component before any read. A malformed
        // reference is a hard input error (R21), not a fail-closed block.
        let reference = match parse_cross_repo_ref(ref_str) {
            Ok(r) => r,
            Err(msg) => {
                return MergeGateOutcome::InputError(format!("invalid reference: {}", msg));
            }
        };
        refs.push((reference, number));
    }

    // Coordination-PR Visibility Rule front door: a public coordination PR must
    // not gate over a private repo (Public -> Private is forbidden). Refuse
    // fail-closed before recomputing any merge state. The diagnostic is already
    // F1-redacted.
    let coordination_visibility = coordination_pr_visibility(visibility_flag);
    if let VisibilityGuardDecision::Refuse(reasons) =
        check_index_visibility(coordination_visibility, &refs, resolver)
    {
        return MergeGateOutcome::Refused(reasons);
    }

    // Resolve each indexed PR's live merge state (F4). The blocker diagnostic is
    // a render path under F1: each label is routed through `redacted_label`,
    // which fails closed to the opaque node id for a private — or unresolvable —
    // repo. The gate diagnostic never names a private ref in the clear.
    let mut pr_statuses: Vec<GatePrStatus> = Vec::with_capacity(refs.len());
    for (reference, number) in &refs {
        // F4: recompute live merge state through the read-only issue client.
        // `Closed` => merged; `Open` => not merged; ANY error => not merged
        // (fail closed). The PR body is never consulted.
        let merged = match client.fetch_issue_state(&reference.owner, &reference.repo, *number) {
            Ok(IssueState::Closed) => true,
            Ok(IssueState::Open) => false,
            Err(ClientError::Auth) => {
                return MergeGateOutcome::InputError(
                    "gh is not authenticated; cannot recompute live PR state. \
                     Run `gh auth login`."
                        .to_string(),
                );
            }
            // Any other read failure: fail closed to not-merged.
            Err(_) => false,
        };

        // Node id mirrors the sync render's opaque identity (`pr-<number>`); it
        // is the fail-closed label for a private/unresolvable repo.
        let node_id = format!("pr-{}", number);
        pr_statuses.push(GatePrStatus {
            label: redacted_label(reference, *number, &node_id, resolver),
            merged,
        });
    }

    // Resolve each upstream's live terminal state via the read-only verifier.
    // A malformed reference is a hard input error (halt); a non-terminal or
    // unresolvable upstream is folded into `terminal == false` (fail closed).
    let mut upstream_statuses: Vec<GateUpstreamStatus> = Vec::with_capacity(upstream_args.len());
    for raw in upstream_args {
        let (ref_str, number) = match split_pr_arg(raw) {
            Ok(pair) => pair,
            Err(msg) => {
                return MergeGateOutcome::InputError(format!(
                    "invalid --upstream {:?}: {}",
                    raw, msg
                ));
            }
        };

        // Validate the reference up front so a malformed upstream halts (R21)
        // rather than being folded into a fail-closed block.
        let reference = match parse_cross_repo_ref(ref_str) {
            Ok(r) => r,
            Err(msg) => {
                return MergeGateOutcome::InputError(format!(
                    "invalid upstream reference: {}",
                    msg
                ));
            }
        };

        // F1: the upstream blocker diagnostic redacts a private/unresolvable
        // ref to its opaque node id, same as the indexed-PR labels above.
        let node_id = format!("upstream-{}", number);
        let label = redacted_label(&reference, number, &node_id, resolver);
        let terminal = verify_cross_repo_upstream_terminal(ref_str, number, client).is_ok();
        upstream_statuses.push(GateUpstreamStatus { label, terminal });
    }

    // The decision is pure: it reads only the live-resolved flags above.
    match decide_gate(&pr_statuses, &upstream_statuses) {
        GateDecision::Pass => MergeGateOutcome::Pass {
            pr_count: pr_statuses.len(),
            upstream_count: upstream_statuses.len(),
        },
        GateDecision::Block(reasons) => MergeGateOutcome::Blocked(reasons),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gh::MockIssueStateClient;

    /// Stub resolver returning a fixed verdict, mirroring the F1 test idiom so
    /// the gate resolution path is exercised without `gh`.
    struct StubResolver(Visibility);
    impl VisibilityResolver for StubResolver {
        fn visibility(&self, _slug: &str) -> Visibility {
            self.0
        }
    }

    #[test]
    fn coordination_pr_visibility_defaults_to_public() {
        assert_eq!(coordination_pr_visibility(""), Visibility::Public);
        assert_eq!(coordination_pr_visibility("public"), Visibility::Public);
        assert_eq!(coordination_pr_visibility("private"), Visibility::Private);
        assert_eq!(coordination_pr_visibility("PRIVATE"), Visibility::Private);
        // Any unrecognized value fails closed to public (strict direction).
        assert_eq!(coordination_pr_visibility("secret"), Visibility::Public);
    }

    #[test]
    fn split_pr_arg_parses_ref_and_number() {
        let (r, n) = split_pr_arg("tsukumogami/shirabe:docs/plans/PLAN-x.md#196").unwrap();
        assert_eq!(r, "tsukumogami/shirabe:docs/plans/PLAN-x.md");
        assert_eq!(n, 196);
    }

    #[test]
    fn split_pr_arg_rejects_missing_suffix() {
        assert!(split_pr_arg("tsukumogami/shirabe:docs/x.md").is_err());
    }

    #[test]
    fn check_index_visibility_refuses_public_pr_indexing_private() {
        let private_ref =
            parse_cross_repo_ref("acme/secret-repo:docs/plans/PLAN-classified.md").unwrap();
        let resolver = StubResolver(Visibility::Private);
        let decision = check_index_visibility(Visibility::Public, &[(private_ref, 7)], &resolver);
        match decision {
            VisibilityGuardDecision::Refuse(reasons) => {
                let joined = reasons.join("\n");
                assert!(joined.contains("pr-7"));
                assert!(!joined.contains("secret-repo"));
                assert!(!joined.contains("acme"));
                assert!(!joined.contains("PLAN-classified.md"));
            }
            VisibilityGuardDecision::Allow => panic!("expected Refuse"),
        }
    }

    // run_merge_gate: a malformed --pr is a hard input error (posture-independent).
    #[test]
    fn run_merge_gate_malformed_pr_is_input_error() {
        let client = MockIssueStateClient::new();
        let resolver = StubResolver(Visibility::Public);
        let outcome = run_merge_gate(
            &["no-hash-suffix".to_string()],
            &[],
            "",
            ReviewPosture::Ready,
            &client,
            &resolver,
        );
        assert!(matches!(outcome, MergeGateOutcome::InputError(_)));
    }

    // run_merge_gate: a public coordination PR over a private indexed repo
    // refuses fail-closed, and the refusal is F1-redacted.
    #[test]
    fn run_merge_gate_public_pr_private_repo_refuses_redacted() {
        let client = MockIssueStateClient::new();
        let resolver = StubResolver(Visibility::Private);
        let outcome = run_merge_gate(
            &["acme/secret-repo:docs/plans/PLAN-classified.md#7".to_string()],
            &[],
            "", // public coordination PR (unset == public)
            ReviewPosture::Ready,
            &client,
            &resolver,
        );
        match outcome {
            MergeGateOutcome::Refused(reasons) => {
                let joined = reasons.join("\n");
                assert!(joined.contains("pr-7"));
                assert!(!joined.contains("secret-repo"));
                assert!(!joined.contains("acme"));
                assert!(!joined.contains("PLAN-classified.md"));
            }
            other => panic!("expected Refused, got {:?}", other),
        }
    }

    // run_merge_gate: an unmerged indexed PR blocks (the decision core's Block).
    #[test]
    fn run_merge_gate_unmerged_pr_blocks() {
        let client = MockIssueStateClient::new().with_issue(
            "tsukumogami",
            "shirabe",
            196,
            Ok(IssueState::Open),
        );
        let resolver = StubResolver(Visibility::Public);
        let outcome = run_merge_gate(
            &["tsukumogami/shirabe:docs/plans/PLAN-x.md#196".to_string()],
            &[],
            "",
            ReviewPosture::Ready,
            &client,
            &resolver,
        );
        match outcome {
            MergeGateOutcome::Blocked(reasons) => {
                assert!(reasons.iter().any(|r| r.contains("196")));
            }
            other => panic!("expected Blocked, got {:?}", other),
        }
    }

    // run_merge_gate: all merged passes.
    #[test]
    fn run_merge_gate_all_merged_passes() {
        let client = MockIssueStateClient::new().with_issue(
            "tsukumogami",
            "shirabe",
            196,
            Ok(IssueState::Closed),
        );
        let resolver = StubResolver(Visibility::Public);
        let outcome = run_merge_gate(
            &["tsukumogami/shirabe:docs/plans/PLAN-x.md#196".to_string()],
            &[],
            "",
            ReviewPosture::Ready,
            &client,
            &resolver,
        );
        assert_eq!(
            outcome,
            MergeGateOutcome::Pass {
                pr_count: 1,
                upstream_count: 0
            }
        );
    }

    // run_merge_gate: an empty index under READY posture fails closed (Blocked).
    // A ready coordination PR with nothing to gate against must not vacuously
    // pass — the merge-last gate is the authority and fails closed.
    #[test]
    fn run_merge_gate_empty_index_under_ready_blocks() {
        let client = MockIssueStateClient::new();
        let resolver = StubResolver(Visibility::Public);
        let outcome = run_merge_gate(&[], &[], "", ReviewPosture::Ready, &client, &resolver);
        match outcome {
            MergeGateOutcome::Blocked(reasons) => {
                assert!(reasons.iter().any(|r| r.contains("empty PR-index")));
            }
            other => panic!("expected Blocked, got {:?}", other),
        }
    }

    // run_merge_gate: an empty index under DRAFT posture is a vacuous pass
    // (exit 0). The index is legitimately empty before per-repo PRs exist.
    #[test]
    fn run_merge_gate_empty_index_under_draft_passes() {
        let client = MockIssueStateClient::new();
        let resolver = StubResolver(Visibility::Public);
        let outcome = run_merge_gate(&[], &[], "", ReviewPosture::Draft, &client, &resolver);
        assert_eq!(
            outcome,
            MergeGateOutcome::Pass {
                pr_count: 0,
                upstream_count: 0
            }
        );
    }
}
