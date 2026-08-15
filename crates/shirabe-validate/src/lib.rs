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
pub mod pr_body;
pub mod prose;
pub mod report;
pub mod rules;
pub mod table;
pub mod transition;
pub mod upstream;
pub mod validate;
pub mod visibility;

// Crate root re-exports. This list mirrors the design's intended public
// surface (DESIGN §"crates/shirabe-validate (library)"). Every export is
// internal-shaped and unstable; see the crate-level doc comment above.
pub use advisory::{explain as explain_advisory, AdvisoryNote, AdvisoryReport, PrPosture};
pub use annotation::{format_error, format_notice};
pub use checks::{check_slug_prefix, detect_slug_prefix, SlugPrefixCheck, SCHEMA_SKIP_CODE};
pub use coordination::{
    check_coordination_body, decide_gate, decide_visibility_guard, is_acyclic_order,
    parse_cross_repo_ref, redacted_label, CoordinationBodyFinding, CrossRepoRef, GateDecision,
    GatePrStatus, GateUpstreamStatus, GuardIndexNode, IndexedPr, Visibility,
    VisibilityGuardDecision, VisibilityResolver, COORDINATION_DECLARATION_MARKER,
};
pub use doc::{Config, Doc, FieldEntries, FieldValue, Section, ValidationError};
pub use features::{extract_needs_label, parse_features, strip_label_decoration, Feature};
pub use finalize::{
    verify_cross_repo_upstream_terminal, walk_chain, walk_chain_mode, BlockingReferrer,
    CrossRepoVerification, Mode, NodeAction, NodeEntry, Report, VerifyError, WalkError,
};
pub use formats::{detect_format, formats, FormatSpec};
pub use frontmatter::{parse_doc, parse_doc_bytes, ParseError};
pub use gh::{
    detect_pr_context, detect_pr_draft, ClientError, GhSubprocessClient, IssueState,
    IssueStateClient, PrContext,
};
pub use lifecycle::{
    root_has_artifact_dirs, run_lifecycle_chain_check, run_lifecycle_check, target_state_for,
    Posture, TargetState, ARTIFACT_DIRS,
};
pub use merge_gate::{
    check_index_visibility, coordination_pr_visibility, run_merge_gate, split_pr_arg,
    GhVisibilityResolver, MergeGateOutcome,
};
pub use pr_body::{check_pr_body, check_pr_title, PrBodyFinding};
pub use report::{
    render_human, render_human_with_advisory, render_json, render_json_with_advisory,
};
pub use table::{
    is_stable_table_key, parse_issue_outlines, parse_issues_table, parse_outline_acs,
    NonconformingHeading, OutlineAc, OutlineBlock, OutlineSection, Profile, Row, RowKind, Table,
};
pub use transition::{
    run_transition, transition_spec, transition_table, BodyTemplate, ExtraInput, Flags, Moves,
    Outcome, Precondition, ResultFields, Rule, TransitionError, TransitionSpec,
};
pub use upstream::{field_entries, is_cross_repo_reference, upstream_entries, UpstreamEntry};
pub use validate::{
    effective_severity, is_known_check_code, is_notice, posture_class, validate_file, PostureClass,
    ReviewPosture, Severity,
};
pub use visibility::resolve_doc_visibility;
