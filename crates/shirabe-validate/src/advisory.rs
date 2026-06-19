//! Context-aware advisory explanation layer for the `validate` command.
//!
//! The advisory layer answers "why this verdict, and what changes it" in
//! posture terms. It is the explanation surface DESIGN Decision 3 / Solution
//! Architecture component 5 describe: a module that composes human-facing
//! prose and additive JSON fields from the validator's own finding data plus
//! a single typed bit of ambient PR context (the `draft` boolean read by
//! [`crate::gh::detect_pr_draft`]).
//!
//! ## The advisory-never-gates invariant
//!
//! This layer is **read-only with respect to the verdict**. Nothing it reads
//! — not the PR context, not the draft bit — can move the exit code or change
//! a finding's enforced severity. The verdict is computed solely from the
//! documents and the declared posture via
//! [`crate::validate::effective_severity`]; the advisory only *describes* the
//! already-resolved findings. `report.rs` wires the advisory into the human
//! output and adds non-breaking JSON fields, leaving every existing verdict
//! field byte-identical regardless of advisory context.
//!
//! ## Rendering-channel safety
//!
//! `report.rs::render_human` emits text verbatim (unlike the annotation and
//! JSON paths, which sanitize/escape). The advisory layer therefore composes
//! text only from the typed draft bit and the validator's own finding data
//! (codes, file paths already in the envelope), never from a free-form string
//! lifted out of the event payload. As a defence in depth, every line of
//! advisory text is passed through [`sanitize`], which strips ASCII control
//! characters and ANSI escape sequences, before it can be emitted. So the
//! rendering channel carries no attacker-controlled bytes even if a future
//! change widened the inputs.

use crate::doc::ValidationError;
use crate::validate::{effective_severity, posture_class, PostureClass, ReviewPosture, Severity};

/// The ambient PR context the advisory phrasing distinguishes. Resolved
/// from [`crate::gh::detect_pr_draft`]: `None` when no draft signal is
/// available (no event payload, or not a PR event), `Some(true)` on a draft
/// PR, `Some(false)` on a ready (non-draft) PR.
///
/// This is the *only* ambient input to the advisory, and it feeds phrasing
/// alone — never the verdict.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrPosture {
    /// No PR context available (local run, or a non-PR GitHub event).
    NoPr,
    /// A draft pull request (`pull_request.draft == true`).
    Draft,
    /// A ready, non-draft pull request (`pull_request.draft == false`).
    Ready,
}

impl PrPosture {
    /// Resolve the advisory PR posture from the typed draft bit produced by
    /// [`crate::gh::detect_pr_draft`].
    pub fn from_draft_bit(draft: Option<bool>) -> Self {
        match draft {
            None => PrPosture::NoPr,
            Some(true) => PrPosture::Draft,
            Some(false) => PrPosture::Ready,
        }
    }
}

/// One advisory note about a single draft-tolerable finding: its code and a
/// short remedy phrase. Composed only from the finding's own `code` (a fixed
/// validator-emitted token) — no payload-derived string.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdvisoryNote {
    /// The finding code (e.g. `L02`). Sanitized.
    pub code: String,
    /// What this finding needs before the chain is ready. Sanitized.
    pub remedy: String,
}

/// The advisory explanation for a run: a posture-aware summary line plus a
/// per-finding note list. Rendered into the human output and surfaced as
/// additive JSON fields by `report.rs`.
///
/// Every string in this struct has already passed through [`sanitize`], so a
/// renderer that emits them verbatim cannot leak control or escape bytes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdvisoryReport {
    /// A single human-readable summary line describing the verdict in posture
    /// terms. Sanitized.
    pub summary: String,
    /// Per-finding notes (one per draft-tolerable finding relevant to the
    /// phrasing). Empty when there is nothing posture-specific to say.
    pub notes: Vec<AdvisoryNote>,
}

impl AdvisoryReport {
    /// True when the report carries no posture-specific content worth
    /// rendering as a notes block (the summary still renders).
    pub fn has_notes(&self) -> bool {
        !self.notes.is_empty()
    }
}

/// A fixed, code-keyed remedy phrase for a draft-tolerable finding. The
/// phrase names what the finding needs before the chain is review-ready.
/// Returns a generic phrase for any unrecognised draft-tolerable code so
/// new draft-tolerable codes degrade gracefully rather than panicking.
fn remedy_for(code: &str) -> &'static str {
    match code {
        "L02" => {
            "connect this artifact into a chain (add its upstream/downstream link) before ready"
        }
        "L06" => "tick every outline acceptance criterion before ready",
        "L07" => "move the design to its canonical location before ready",
        _ => "resolve this finding before ready",
    }
}

/// Compose the advisory explanation from the already-resolved findings, the
/// declared review posture, and the ambient PR context.
///
/// This function is pure with respect to the verdict: it reads `findings`,
/// `posture`, and `pr` only to *phrase* an explanation. The two posture
/// inputs play distinct roles:
///
/// - `posture` is the **declared** review posture (`--mode`), which already
///   drove the verdict via [`effective_severity`].
/// - `pr` is the **ambient** PR context, used only to choose phrasing
///   (no-PR vs draft-PR vs ready-PR). It NEVER affects which findings count.
///
/// Phrasing branches:
///
/// - **In-flight pass** (declared `Draft`, no error-level finding): name each
///   draft-tolerable finding by code and what it needs before ready.
/// - **Ready failure on a draft-tolerable finding** (declared `Ready`, at
///   least one draft-tolerable finding resolved to an error): state that
///   reverting to draft would pass, and name what to fix to stay ready.
/// - Otherwise: a posture-only summary with no notes.
pub fn explain(
    findings: &[ValidationError],
    posture: ReviewPosture,
    pr: PrPosture,
) -> AdvisoryReport {
    // The set of draft-tolerable findings present in this run, in finding
    // order. Composed from finding codes only.
    let draft_tolerable: Vec<&ValidationError> = findings
        .iter()
        .filter(|e| posture_class(&e.code) == PostureClass::DraftTolerable)
        .collect();

    let has_error = findings
        .iter()
        .any(|e| effective_severity(&e.code, posture) == Severity::Error);

    let (summary, notes) = match posture {
        ReviewPosture::Draft if !has_error && !draft_tolerable.is_empty() => {
            // In-flight pass: tolerated findings are notices now but block at
            // ready. Name each by code + remedy.
            let summary = match pr {
                PrPosture::Draft => {
                    "Draft posture: tolerated now on this draft PR, but the findings \
                     below must be resolved before this PR is marked ready."
                }
                PrPosture::Ready => {
                    "Draft posture asserted on a PR already marked ready: the findings \
                     below are tolerated by the declared posture but block a ready run."
                }
                PrPosture::NoPr => {
                    "Draft posture: the findings below are tolerated now but must be \
                     resolved before a ready run."
                }
            };
            let notes = draft_tolerable
                .iter()
                .map(|e| AdvisoryNote {
                    code: sanitize(&e.code),
                    remedy: sanitize(remedy_for(&e.code)),
                })
                .collect();
            (summary.to_string(), notes)
        }
        ReviewPosture::Ready if has_error && !draft_tolerable.is_empty() => {
            // Ready failure. If the only error-level findings are
            // draft-tolerable ones, reverting to draft would pass; name the
            // fix list to stay ready.
            let all_errors_draft_tolerable = findings
                .iter()
                .filter(|e| effective_severity(&e.code, posture) == Severity::Error)
                .all(|e| posture_class(&e.code) == PostureClass::DraftTolerable);
            let summary = if all_errors_draft_tolerable {
                "Ready posture failed only on draft-tolerable findings: reverting to \
                 draft (--mode=draft) would pass. To stay ready, fix the findings below."
            } else {
                "Ready posture failed. Some findings are draft-tolerable (listed below) \
                 and would pass under draft, but other always-enforced findings remain."
            };
            let notes = draft_tolerable
                .iter()
                .map(|e| AdvisoryNote {
                    code: sanitize(&e.code),
                    remedy: sanitize(remedy_for(&e.code)),
                })
                .collect();
            (summary.to_string(), notes)
        }
        ReviewPosture::Draft => (
            sanitize("Draft posture: no draft-tolerable findings to flag."),
            Vec::new(),
        ),
        ReviewPosture::Ready => (
            sanitize("Ready posture: no draft-tolerable findings to flag."),
            Vec::new(),
        ),
    };

    AdvisoryReport {
        summary: sanitize(&summary),
        notes,
    }
}

/// Strip ASCII control characters and ANSI/CSI escape sequences from `s`.
///
/// This is the rendering-channel guard: `report.rs::render_human` emits
/// advisory text verbatim, so any control or escape byte that reached it
/// would land in CI logs / a terminal. The advisory composes text only from
/// fixed validator tokens, so in practice the input is already clean; this
/// pass is defence in depth that holds even if a future change widened the
/// inputs.
///
/// The algorithm: drop every byte below `0x20` and the `0x7f` DEL byte
/// (this removes the ESC `0x1b` that introduces ANSI sequences, so a CSI
/// like `ESC [ 31 m` cannot survive intact), and drop the lone non-ESC
/// remainder of a CSI defensively. Printable ASCII and multi-byte UTF-8
/// pass through unchanged.
pub fn sanitize(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        let cp = ch as u32;
        // Drop C0 controls (incl. ESC 0x1b, TAB, NL, CR), DEL, and the C1
        // control range 0x80..=0x9f (which includes the 8-bit CSI 0x9b).
        if cp < 0x20 || cp == 0x7f || (0x80..=0x9f).contains(&cp) {
            continue;
        }
        out.push(ch);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(code: &str) -> ValidationError {
        ValidationError {
            file: "docs/x.md".to_string(),
            line: 0,
            code: code.to_string(),
            message: format!("[{}] something", code),
        }
    }

    // --- PrPosture mapping ---

    #[test]
    fn pr_posture_from_draft_bit() {
        assert_eq!(PrPosture::from_draft_bit(None), PrPosture::NoPr);
        assert_eq!(PrPosture::from_draft_bit(Some(true)), PrPosture::Draft);
        assert_eq!(PrPosture::from_draft_bit(Some(false)), PrPosture::Ready);
    }

    // --- in-flight pass names each tolerated finding by code + remedy ---

    #[test]
    fn in_flight_pass_names_each_tolerated_finding() {
        let findings = vec![err("L02"), err("L06")];
        let rep = explain(&findings, ReviewPosture::Draft, PrPosture::Draft);
        assert!(rep.has_notes());
        let codes: Vec<&str> = rep.notes.iter().map(|n| n.code.as_str()).collect();
        assert!(codes.contains(&"L02"));
        assert!(codes.contains(&"L06"));
        // Each note carries a non-empty remedy phrase.
        for n in &rep.notes {
            assert!(!n.remedy.is_empty(), "remedy for {} must be set", n.code);
        }
        // The summary speaks in before-ready terms.
        assert!(rep.summary.to_lowercase().contains("ready"));
    }

    // --- ready failure on a draft-tolerable finding names the escape hatch ---

    #[test]
    fn ready_failure_on_draft_tolerable_states_draft_would_pass() {
        let findings = vec![err("L02")];
        let rep = explain(&findings, ReviewPosture::Ready, PrPosture::Ready);
        assert!(
            rep.summary.to_lowercase().contains("draft"),
            "summary must name the draft escape hatch: {}",
            rep.summary
        );
        assert!(
            rep.summary.contains("--mode=draft"),
            "summary must name the concrete flag: {}",
            rep.summary
        );
        let codes: Vec<&str> = rep.notes.iter().map(|n| n.code.as_str()).collect();
        assert!(codes.contains(&"L02"));
    }

    #[test]
    fn ready_failure_mixed_does_not_promise_draft_pass() {
        // A draft-tolerable L02 plus an always-enforced L04: draft would NOT
        // pass, so the summary must not promise it.
        let findings = vec![err("L02"), err("L04")];
        let rep = explain(&findings, ReviewPosture::Ready, PrPosture::Ready);
        assert!(
            !rep.summary.contains("--mode=draft"),
            "mixed failure must not promise a draft pass: {}",
            rep.summary
        );
        // The draft-tolerable finding is still listed.
        let codes: Vec<&str> = rep.notes.iter().map(|n| n.code.as_str()).collect();
        assert!(codes.contains(&"L02"));
    }

    // --- no draft-tolerable findings: posture-only phrasing ---

    #[test]
    fn clean_draft_run_has_no_notes() {
        let rep = explain(&[], ReviewPosture::Draft, PrPosture::NoPr);
        assert!(!rep.has_notes());
        assert!(!rep.summary.is_empty());
    }

    #[test]
    fn no_pr_context_still_explains() {
        // Absent PR context degrades to posture-only phrasing, no crash.
        let findings = vec![err("L02")];
        let rep = explain(&findings, ReviewPosture::Draft, PrPosture::NoPr);
        assert!(rep.has_notes());
        assert!(!rep.summary.is_empty());
    }

    // --- sanitize ---

    #[test]
    fn sanitize_strips_ansi_escape() {
        // A CSI red-color sequence: ESC [ 3 1 m ... ESC [ 0 m
        let evil = "\u{1b}[31mRED\u{1b}[0m";
        let clean = sanitize(evil);
        assert!(!clean.contains('\u{1b}'), "ESC byte must be stripped");
        assert_eq!(clean, "[31mRED[0m");
    }

    #[test]
    fn sanitize_strips_control_chars() {
        let evil = "a\u{0007}b\u{0000}c\tnewline\nhere\r";
        let clean = sanitize(evil);
        for bad in ['\u{0007}', '\u{0000}', '\t', '\n', '\r'] {
            assert!(!clean.contains(bad), "control char {:?} must be gone", bad);
        }
        assert_eq!(clean, "abcnewlinehere");
    }

    #[test]
    fn sanitize_strips_del_and_c1() {
        let evil = "a\u{007f}b\u{009b}c"; // DEL and 8-bit CSI
        let clean = sanitize(evil);
        assert_eq!(clean, "abc");
    }

    #[test]
    fn sanitize_preserves_printable_and_utf8() {
        let s = "L02 needs upstream — café 日本語";
        assert_eq!(sanitize(s), s);
    }

    #[test]
    fn advisory_report_text_is_always_sanitized() {
        // Every string the report exposes is control/escape-free.
        let findings = vec![err("L02"), err("L06")];
        for pr in [PrPosture::NoPr, PrPosture::Draft, PrPosture::Ready] {
            for posture in [ReviewPosture::Draft, ReviewPosture::Ready] {
                let rep = explain(&findings, posture, pr);
                assert_eq!(rep.summary, sanitize(&rep.summary));
                for n in &rep.notes {
                    assert_eq!(n.code, sanitize(&n.code));
                    assert_eq!(n.remedy, sanitize(&n.remedy));
                }
            }
        }
    }
}
