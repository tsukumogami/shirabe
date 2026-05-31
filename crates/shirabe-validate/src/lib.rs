//! shirabe-validate — internal-shaped library crate.
//!
//! Public exports are unstable across shirabe versions. Treat as
//! `pub(crate)` at all call sites that are not the shirabe binary
//! crate; the visibility is `pub` only because Rust's crate boundary
//! requires it. Stability locks the moment a concrete external caller
//! (e.g. koto's Rust substrate) commits to linking; see DESIGN
//! Decision 4 for the rationale.

pub mod checks;
pub mod doc;
pub mod formats;
pub mod frontmatter;
pub mod table;
