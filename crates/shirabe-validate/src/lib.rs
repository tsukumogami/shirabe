//! shirabe-validate — internal-shaped library crate.
//!
//! Public exports are unstable across shirabe versions. Treat as
//! `pub(crate)` at all call sites that are not the shirabe binary
//! crate; the visibility is `pub` only because Rust's crate boundary
//! requires it. Stability locks the moment a concrete external caller
//! (e.g. koto's Rust substrate) commits to linking; see DESIGN
//! Decision 4 for the rationale.

pub mod advisory;
pub mod annotation;
pub mod checks;
pub mod coordination;
pub mod doc;
pub mod features;
pub mod finalize;
pub mod formats;
pub mod frontmatter;
pub mod gh;
pub mod lifecycle;
pub mod merge_gate;
pub mod mermaid;
pub mod report;
pub mod table;
pub mod transition;
pub mod validate;

// Crate root re-exports. This list mirrors the design's intended public
// surface (DESIGN §"crates/shirabe-validate (library)"). Every export is
// internal-shaped and unstable; see the crate-level doc comment above.
pub use advisory::{explain as explain_advisory, AdvisoryNote, AdvisoryReport, PrPosture};
pub use annotation::{format_error, format_notice};
pub use checks::{check_slug_prefix, detect_slug_prefix, SlugPrefixCheck};
pub use coordination::{
    decide_gate, decide_visibility_guard, escape_inline, parse_cross_repo_ref, redacted_label,
    render_index_line, render_sync_body, seed_body, CrossRepoRef, GateDecision, GatePrStatus,
    GateUpstreamStatus, GuardIndexNode, IndexedPr, SeedInputs, Visibility, VisibilityGuardDecision,
    VisibilityResolver,
};
pub use doc::{Config, Doc, FieldValue, Section, ValidationError};
pub use features::{extract_needs_label, parse_features, strip_label_decoration, Feature};
pub use finalize::{
    verify_cross_repo_upstream_terminal, walk_chain, walk_chain_mode, CrossRepoVerification, Mode,
    NodeAction, NodeEntry, Report, VerifyError, WalkError,
};
pub use formats::{detect_format, formats, FormatSpec};
pub use frontmatter::{parse_doc, ParseError};
pub use gh::{
    detect_pr_context, detect_pr_draft, ClientError, GhSubprocessClient, IssueState,
    IssueStateClient, PrContext,
};
pub use lifecycle::{
    run_lifecycle_chain_check, run_lifecycle_check, target_state_for, Posture, TargetState,
};
pub use merge_gate::{
    check_index_visibility, coordination_pr_visibility, run_merge_gate, split_pr_arg,
    GhVisibilityResolver, MergeGateOutcome,
};
pub use report::{
    render_human, render_human_with_advisory, render_json, render_json_with_advisory,
};
pub use table::{parse_issues_table, Profile, Row, RowKind, Table};
pub use transition::{
    run_transition, transition_spec, transition_table, BodyTemplate, ExtraInput, Flags, Moves,
    Outcome, Precondition, ResultFields, Rule, TransitionError, TransitionSpec,
};
pub use validate::{
    effective_severity, is_known_check_code, is_notice, posture_class, validate_file, PostureClass,
    ReviewPosture, Severity,
};
