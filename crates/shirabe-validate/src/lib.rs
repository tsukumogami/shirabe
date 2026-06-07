//! shirabe-validate — internal-shaped library crate.
//!
//! Public exports are unstable across shirabe versions. Treat as
//! `pub(crate)` at all call sites that are not the shirabe binary
//! crate; the visibility is `pub` only because Rust's crate boundary
//! requires it. Stability locks the moment a concrete external caller
//! (e.g. koto's Rust substrate) commits to linking; see DESIGN
//! Decision 4 for the rationale.

pub mod annotation;
pub mod checks;
pub mod doc;
pub mod features;
pub mod finalize;
pub mod formats;
pub mod frontmatter;
pub mod gh;
pub mod lifecycle;
pub mod mermaid;
pub mod table;
pub mod transition;
pub mod validate;

// Crate root re-exports. This list mirrors the design's intended public
// surface (DESIGN §"crates/shirabe-validate (library)"). Every export is
// internal-shaped and unstable; see the crate-level doc comment above.
pub use annotation::{format_error, format_notice};
pub use checks::{check_slug_prefix, detect_slug_prefix, SlugPrefixCheck};
pub use doc::{Config, Doc, FieldValue, Section, ValidationError};
pub use features::{extract_needs_label, parse_features, strip_label_decoration, Feature};
pub use finalize::{walk_chain, walk_chain_mode, Mode, NodeAction, NodeEntry, Report, WalkError};
pub use formats::{detect_format, formats, FormatSpec};
pub use frontmatter::{parse_doc, ParseError};
pub use lifecycle::{run_lifecycle_check, target_state_for, Posture, TargetState};
pub use table::{parse_issues_table, Profile, Row, RowKind, Table};
pub use transition::{
    run_transition, transition_spec, transition_table, BodyTemplate, ExtraInput, Flags, Moves,
    Outcome, Precondition, ResultFields, Rule, TransitionError, TransitionSpec,
};
pub use validate::{is_notice, validate_file};
