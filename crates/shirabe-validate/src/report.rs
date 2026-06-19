//! Machine-readable (JSON) and human-readable result renderers for the
//! `validate` command.
//!
//! These are the two output modes that sit alongside the GitHub Actions
//! annotation mode in [`crate::annotation`]. The annotation mode is the
//! default and its bytes are frozen for CI parity; these modes are opt-in
//! via `--format` and serve the skills (JSON) and ad-hoc terminal use
//! (human).
//!
//! Both renderers take the full set of [`ValidationError`]s collected
//! across every validated document, an `outcome` label (the resolved
//! [`run_validate`] outcome, e.g. `"violations"`), and the [`ReviewPosture`]
//! the run asserted. Severity is derived from
//! [`crate::validate::effective_severity`], the same posture-aware seam the
//! annotation mode and the exit-code roll-up use to split errors from
//! notices, so the three modes can never disagree about what counts as an
//! error.

use crate::advisory::AdvisoryReport;
use crate::doc::ValidationError;
use crate::validate::{is_notice, ReviewPosture};

/// The machine-output schema version. Follows the repo's `<name>/v<major>`
/// idiom (the same shape as the `design/v1` document schema tag): additive
/// changes stay `v1`, a breaking change bumps the major, and consumers pin
/// on the major.
const SCHEMA_VERSION: &str = "shirabe-validate/v1";

/// The severity label for a finding under `posture`, derived solely from
/// [`is_notice`] (the [`crate::validate::effective_severity`] seam).
fn severity(err: &ValidationError, posture: ReviewPosture) -> &'static str {
    if is_notice(err, posture) {
        "notice"
    } else {
        "error"
    }
}

/// Escape a string as a JSON string literal (including the surrounding
/// quotes). Quotes, backslashes, the C0 control characters, and the common
/// whitespace escapes are all encoded so a crafted field value cannot break
/// out of its string and forge sibling fields or extra findings. Unlike the
/// annotation mode (which strips newlines to prevent annotation injection),
/// JSON preserves them as `\n`/`\r` escapes so messages stay faithful.
///
/// Matches the escaping discipline of the `json_string` helpers in
/// `finalize.rs` and `transition.rs`.
fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Render the findings as the `shirabe-validate/v1` JSON envelope: a
/// `schema_version`, a `summary` block (the outcome label plus error and
/// notice counts), and a flat `findings` array. Each finding carries its
/// `code`, derived `severity`, `message`, `file`, and `line` (`null` when
/// the engine's no-line sentinel `0` is present).
pub fn render_json(findings: &[ValidationError], outcome: &str, posture: ReviewPosture) -> String {
    render_json_with_advisory(findings, outcome, posture, None)
}

/// Like [`render_json`], but additionally emits an `advisory` object built
/// from `advisory` when one is supplied.
///
/// **Additive and non-breaking.** Every existing field — `schema_version`,
/// the `summary` block, and each finding's `code`/`severity`/`message`/
/// `file`/`line` — is byte-identical to [`render_json`]'s output for the same
/// `(findings, outcome, posture)`. The `advisory` key is appended after
/// `findings`; `schema_version` does not change (the advisory is an additive
/// `v1` field). When `advisory` is `None` the output equals [`render_json`]
/// exactly, so the advisory context cannot perturb the verdict envelope.
///
/// The advisory strings were already sanitized by `advisory::explain`; they
/// are still passed through [`json_string`] here so the envelope stays
/// well-formed JSON regardless.
pub fn render_json_with_advisory(
    findings: &[ValidationError],
    outcome: &str,
    posture: ReviewPosture,
    advisory: Option<&AdvisoryReport>,
) -> String {
    let errors = findings.iter().filter(|e| !is_notice(e, posture)).count();
    let notices = findings.iter().filter(|e| is_notice(e, posture)).count();

    let mut out = String::new();
    out.push_str("{\n");
    out.push_str(&format!(
        "  \"schema_version\": {},\n",
        json_string(SCHEMA_VERSION)
    ));
    out.push_str("  \"summary\": {\n");
    out.push_str(&format!("    \"outcome\": {},\n", json_string(outcome)));
    out.push_str(&format!("    \"errors\": {},\n", errors));
    out.push_str(&format!("    \"notices\": {}\n", notices));
    out.push_str("  },\n");

    // The findings array is emitted with a trailing comma only when an
    // advisory block follows it, so the existing (advisory-free) bytes are
    // unchanged while the additive block stays well-formed.
    let findings_trailer = if advisory.is_some() { "," } else { "" };

    if findings.is_empty() {
        out.push_str(&format!("  \"findings\": []{}\n", findings_trailer));
    } else {
        out.push_str("  \"findings\": [\n");
        for (i, e) in findings.iter().enumerate() {
            let line = if e.line == 0 {
                "null".to_string()
            } else {
                e.line.to_string()
            };
            out.push_str("    {\n");
            out.push_str(&format!("      \"code\": {},\n", json_string(&e.code)));
            out.push_str(&format!(
                "      \"severity\": {},\n",
                json_string(severity(e, posture))
            ));
            out.push_str(&format!(
                "      \"message\": {},\n",
                json_string(&e.message)
            ));
            out.push_str(&format!("      \"file\": {},\n", json_string(&e.file)));
            out.push_str(&format!("      \"line\": {}\n", line));
            let close = if i + 1 == findings.len() {
                "    }\n"
            } else {
                "    },\n"
            };
            out.push_str(close);
        }
        out.push_str(&format!("  ]{}\n", findings_trailer));
    }

    if let Some(adv) = advisory {
        out.push_str("  \"advisory\": {\n");
        out.push_str(&format!(
            "    \"summary\": {},\n",
            json_string(&adv.summary)
        ));
        if adv.notes.is_empty() {
            out.push_str("    \"notes\": []\n");
        } else {
            out.push_str("    \"notes\": [\n");
            for (i, n) in adv.notes.iter().enumerate() {
                out.push_str("      {\n");
                out.push_str(&format!("        \"code\": {},\n", json_string(&n.code)));
                out.push_str(&format!("        \"remedy\": {}\n", json_string(&n.remedy)));
                let close = if i + 1 == adv.notes.len() {
                    "      }\n"
                } else {
                    "      },\n"
                };
                out.push_str(close);
            }
            out.push_str("    ]\n");
        }
        out.push_str("  }\n");
    }

    out.push_str("}\n");
    out
}

/// Render the findings as a terminal-shaped summary with no GitHub Actions
/// annotation syntax. Each finding is one line (`<file>:<line> <severity>
/// <message>`, the `:<line>` omitted when the line is the no-line sentinel),
/// followed by a footer line with the counts and outcome. A run with no
/// findings reports that all checks passed. The message is shown verbatim
/// (the engine already embeds the check code in it, as the annotation mode
/// surfaces), so the code is not repeated.
pub fn render_human(findings: &[ValidationError], outcome: &str, posture: ReviewPosture) -> String {
    render_human_with_advisory(findings, outcome, posture, None)
}

/// Like [`render_human`], but appends a sanitized advisory block when one is
/// supplied.
///
/// The findings list and the `N error(s), M notice(s) -- outcome` footer are
/// byte-identical to [`render_human`]'s output; the advisory is appended after
/// the footer under an `Advisory:` heading, so the verdict-bearing portion of
/// the human output never varies with advisory context. When `advisory` is
/// `None` the output equals [`render_human`] exactly.
///
/// **Verbatim-emit safety.** This renderer writes its inputs without escaping
/// (unlike the JSON and annotation paths). The advisory strings were already
/// run through `advisory::sanitize` (control/escape stripping) in
/// `advisory::explain`, so appending them verbatim cannot leak control or
/// escape bytes into a terminal or CI log.
pub fn render_human_with_advisory(
    findings: &[ValidationError],
    outcome: &str,
    posture: ReviewPosture,
    advisory: Option<&AdvisoryReport>,
) -> String {
    let mut out = String::new();
    if findings.is_empty() {
        out.push_str("All checks passed.\n");
        append_human_advisory(&mut out, advisory);
        return out;
    }
    for e in findings {
        if e.line == 0 {
            out.push_str(&format!(
                "{} {} {}\n",
                e.file,
                severity(e, posture),
                e.message
            ));
        } else {
            out.push_str(&format!(
                "{}:{} {} {}\n",
                e.file,
                e.line,
                severity(e, posture),
                e.message
            ));
        }
    }
    let errors = findings.iter().filter(|e| !is_notice(e, posture)).count();
    let notices = findings.iter().filter(|e| is_notice(e, posture)).count();
    out.push_str(&format!(
        "\n{} error(s), {} notice(s) -- {}\n",
        errors, notices, outcome
    ));
    append_human_advisory(&mut out, advisory);
    out
}

/// Append the advisory block to `out`. No-op when `advisory` is `None`. The
/// advisory strings are emitted verbatim; they were sanitized upstream in
/// `advisory::explain`.
fn append_human_advisory(out: &mut String, advisory: Option<&AdvisoryReport>) {
    let Some(adv) = advisory else {
        return;
    };
    out.push_str("\nAdvisory: ");
    out.push_str(&adv.summary);
    out.push('\n');
    for note in &adv.notes {
        out.push_str(&format!("  {}: {}\n", note.code, note.remedy));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(file: &str, line: usize, code: &str, message: &str) -> ValidationError {
        ValidationError {
            file: file.to_string(),
            line,
            code: code.to_string(),
            message: message.to_string(),
        }
    }

    #[test]
    fn json_empty_findings_has_clean_shape() {
        let out = render_json(&[], "clean", ReviewPosture::Draft);
        assert!(out.contains("\"schema_version\": \"shirabe-validate/v1\""));
        assert!(out.contains("\"outcome\": \"clean\""));
        assert!(out.contains("\"errors\": 0"));
        assert!(out.contains("\"notices\": 0"));
        assert!(out.contains("\"findings\": []"));
    }

    #[test]
    fn json_derives_severity_from_is_notice() {
        let findings = vec![
            err("a.md", 3, "FC01", "missing field"),
            err("a.md", 1, "SCHEMA", "schema notice"),
        ];
        let out = render_json(&findings, "violations", ReviewPosture::Draft);
        assert!(out.contains("\"severity\": \"error\""));
        assert!(out.contains("\"severity\": \"notice\""));
        assert!(out.contains("\"errors\": 1"));
        assert!(out.contains("\"notices\": 1"));
    }

    #[test]
    fn json_no_line_sentinel_renders_null() {
        let out = render_json(
            &[err("a.md", 0, "FC01", "msg")],
            "violations",
            ReviewPosture::Draft,
        );
        assert!(out.contains("\"line\": null"));
        assert!(!out.contains("\"line\": 0"));
    }

    #[test]
    fn json_with_line_renders_integer() {
        let out = render_json(
            &[err("a.md", 42, "FC01", "msg")],
            "violations",
            ReviewPosture::Draft,
        );
        assert!(out.contains("\"line\": 42"));
    }

    #[test]
    fn json_escapes_adversarial_field_values_no_breakout() {
        // A message engineered to forge sibling fields / an extra finding if
        // it were interpolated raw. After escaping it must remain a single
        // string value: the literal injection substring must NOT appear
        // unescaped, and there must still be exactly one finding.
        let evil = "x\",\"line\":0,\"code\":\"INJECTED\",\"message\":\"pwned";
        let out = render_json(
            &[err("a.md", 7, "FC01", evil)],
            "violations",
            ReviewPosture::Draft,
        );
        // The raw breakout sequence (the forged-key fragment exactly as it
        // would appear if the value were interpolated unescaped) must be
        // absent.
        assert!(!out.contains("\",\"code\":\"INJECTED\""));
        assert!(out.contains("\\\"")); // escaped quotes are present
                                       // Load-bearing containment proof: exactly one `"code":` key, so
                                       // no extra finding was forged.
        assert_eq!(out.matches("\"code\":").count(), 1);
    }

    #[test]
    fn json_escapes_newlines_and_control_chars() {
        let out = render_json(
            &[err("a.md", 1, "FC01", "line1\nline2\tend\u{0001}")],
            "x",
            ReviewPosture::Draft,
        );
        assert!(out.contains("line1\\nline2\\tend\\u0001"));
        // The raw newline must not appear inside the rendered message value.
        assert!(!out.contains("line1\nline2"));
    }

    #[test]
    fn human_empty_reports_all_passed() {
        assert_eq!(
            render_human(&[], "clean", ReviewPosture::Draft),
            "All checks passed.\n"
        );
    }

    #[test]
    fn human_has_no_annotation_syntax() {
        let findings = vec![err("a.md", 3, "FC01", "missing field")];
        let out = render_human(&findings, "violations", ReviewPosture::Draft);
        assert!(!out.contains("::error"));
        assert!(!out.contains("::notice"));
        assert!(out.contains("a.md:3 error missing field"));
        assert!(out.contains("1 error(s), 0 notice(s) -- violations"));
    }

    #[test]
    fn human_omits_line_for_sentinel() {
        let out = render_human(
            &[err("a.md", 0, "SCHEMA", "note")],
            "clean",
            ReviewPosture::Draft,
        );
        assert!(out.contains("a.md notice note"));
        assert!(!out.contains("a.md:0"));
    }
}
