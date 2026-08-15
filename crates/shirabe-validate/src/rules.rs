//! The writing-style rule source, read at enforcement time.
//!
//! One authoritative representation of the rules lives at
//! `skills/writing-style/rules.yaml`. This module resolves and parses it.
//! Nothing here embeds a rule at build time: `include_str!` would satisfy a
//! "single source" reading while reproducing the exact defect the rule
//! source exists to end, which is the shipped `FC10_BANNED_WORDS` constant
//! diverging from the reference the design told it to read.
//!
//! ## Resolution
//!
//! Flag, then environment, then an ancestor walk:
//!
//! 1. `--rules <path>` (the CI reusable workflow passes a path into its
//!    `.shirabe-src/` checkout, so the rules and the binary come from one
//!    commit).
//! 2. `SHIRABE_RULES` (the test harness sets this, because the parity tests
//!    run with cwd inside `tests/fixtures/golden/corpus`, where the walk
//!    would escape the crate).
//! 3. An ancestor walk from the working directory for
//!    `skills/writing-style/rules.yaml`.
//!
//! A missing or unparseable source is a tool error. The validator never
//! proceeds over an empty rule set: a checking surface that reports success
//! because its rules failed to load is the failure mode this whole
//! capability exists to end.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use saphyr::{LoadableYamlNode, Yaml};

/// The conventional location, relative to a repository root.
pub const RULES_RELATIVE_PATH: &str = "skills/writing-style/rules.yaml";

/// Environment variable consulted after the flag and before the walk.
pub const RULES_ENV_VAR: &str = "SHIRABE_RULES";

/// A banned-word category with its terms and the guidance an author reads.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WordCategory {
    pub category: String,
    pub guidance: String,
    pub terms: Vec<String>,
}

/// A rule that evaluates a rate against a threshold.
///
/// Every field is required rather than defaulted. The threshold,
/// denominator, unit, and finding-line convention are decisions the design
/// records; a defaulted field would let an implementation quietly choose one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrequencyRule {
    pub id: String,
    pub guidance: String,
    pub pattern: String,
    pub threshold_per_thousand: u32,
    pub denominator: String,
    pub unit: String,
    pub finding_line: String,
    pub message: String,
    /// Minimum scoped words before the rule reports.
    ///
    /// A rate needs enough denominator to be a rate: at 98 words one em
    /// dash is 10.2 per thousand, which crosses a threshold of 10 while
    /// saying nothing about density.
    pub min_words: usize,
}

/// A rule the rulebook carries that no matcher can decide.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JudgmentOnlyRule {
    pub rule: String,
    pub guidance: String,
}

/// The parsed rule source.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Rules {
    pub words: Vec<WordCategory>,
    pub frequency: Vec<FrequencyRule>,
    pub judgment_only: Vec<JudgmentOnlyRule>,
}

impl Rules {
    /// Every banned term across all categories, lowercased, deduplicated.
    ///
    /// Deduplicated because a term appearing in two categories is a rule
    /// source defect, not a reason to report the same word twice.
    pub fn all_terms(&self) -> Vec<String> {
        let set: BTreeSet<String> = self
            .words
            .iter()
            .flat_map(|c| c.terms.iter())
            .map(|t| t.to_lowercase())
            .collect();
        set.into_iter().collect()
    }

    /// The category whose terms include `term`, if any. Used to attach the
    /// author-facing guidance to a finding.
    pub fn category_for(&self, term: &str) -> Option<&WordCategory> {
        let needle = term.to_lowercase();
        self.words
            .iter()
            .find(|c| c.terms.iter().any(|t| t.to_lowercase() == needle))
    }
}

/// Why a rule source could not be produced.
///
/// Every variant is a tool error at the CLI boundary, distinct from a
/// content violation, and each names the path it tried so the operator can
/// see which resolution step failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RulesError {
    /// No candidate path existed. Carries the paths tried, in order.
    NotFound { tried: Vec<String> },
    /// The file existed but could not be read.
    Unreadable { path: String, detail: String },
    /// The file parsed as YAML but did not match the expected shape, or did
    /// not parse at all.
    Malformed { path: String, detail: String },
}

impl std::fmt::Display for RulesError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RulesError::NotFound { tried } => write!(
                f,
                "writing-style rule source not found; tried: {}",
                tried.join(", ")
            ),
            RulesError::Unreadable { path, detail } => {
                write!(
                    f,
                    "writing-style rule source unreadable at {path}: {detail}"
                )
            }
            RulesError::Malformed { path, detail } => {
                write!(f, "writing-style rule source malformed at {path}: {detail}")
            }
        }
    }
}

/// Resolve the rule source path: explicit, then environment, then walk.
///
/// `start` is the directory the walk begins from, normally the working
/// directory. The walk is bounded by the filesystem root and stops at the
/// first candidate that exists.
pub fn resolve_rules_path(explicit: Option<&str>, start: &Path) -> Result<PathBuf, RulesError> {
    let mut tried: Vec<String> = Vec::new();

    if let Some(p) = explicit {
        let path = PathBuf::from(p);
        if path.is_file() {
            return Ok(path);
        }
        tried.push(p.to_string());
        // An explicit path that does not exist is an error rather than a
        // fall-through: an operator who named a path meant that path, and
        // silently checking somewhere else is how the wrong rules load.
        return Err(RulesError::NotFound { tried });
    }

    if let Ok(env_path) = std::env::var(RULES_ENV_VAR) {
        if !env_path.is_empty() {
            let path = PathBuf::from(&env_path);
            if path.is_file() {
                return Ok(path);
            }
            tried.push(env_path);
            return Err(RulesError::NotFound { tried });
        }
    }

    let mut dir = Some(start);
    while let Some(d) = dir {
        let candidate = d.join(RULES_RELATIVE_PATH);
        if candidate.is_file() {
            return Ok(candidate);
        }
        tried.push(candidate.display().to_string());
        dir = d.parent();
    }

    Err(RulesError::NotFound { tried })
}

/// Read and parse the rule source at `path`.
pub fn load_rules(path: &Path) -> Result<Rules, RulesError> {
    let text = std::fs::read_to_string(path).map_err(|e| RulesError::Unreadable {
        path: path.display().to_string(),
        detail: e.to_string(),
    })?;
    parse_rules(&text, &path.display().to_string())
}

/// Parse rule-source text. Separated from IO so tests drive it directly.
pub fn parse_rules(text: &str, path: &str) -> Result<Rules, RulesError> {
    let docs = Yaml::load_from_str(text).map_err(|e| RulesError::Malformed {
        path: path.to_string(),
        detail: e.to_string(),
    })?;

    let root = docs.first().ok_or_else(|| RulesError::Malformed {
        path: path.to_string(),
        detail: "empty document".to_string(),
    })?;

    let map = root.as_mapping().ok_or_else(|| RulesError::Malformed {
        path: path.to_string(),
        detail: "top level is not a mapping".to_string(),
    })?;

    let get = |key: &str| -> Option<&Yaml> {
        map.iter()
            .find(|(k, _)| k.as_str() == Some(key))
            .map(|(_, v)| v)
    };

    let mut rules = Rules::default();

    if let Some(words) = get("words") {
        let seq = words.as_sequence().ok_or_else(|| RulesError::Malformed {
            path: path.to_string(),
            detail: "`words` is not a sequence".to_string(),
        })?;
        for entry in seq {
            let m = entry.as_mapping().ok_or_else(|| RulesError::Malformed {
                path: path.to_string(),
                detail: "a `words` entry is not a mapping".to_string(),
            })?;
            let field = |key: &str| -> Option<String> {
                m.iter()
                    .find(|(k, _)| k.as_str() == Some(key))
                    .and_then(|(_, v)| v.as_str())
                    .map(|s| s.to_string())
            };
            let terms = m
                .iter()
                .find(|(k, _)| k.as_str() == Some("terms"))
                .and_then(|(_, v)| v.as_sequence())
                .map(|s| {
                    s.iter()
                        .filter_map(|t| t.as_str().map(|x| x.to_string()))
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();

            if terms.is_empty() {
                return Err(RulesError::Malformed {
                    path: path.to_string(),
                    detail: format!(
                        "`words` category `{}` has no terms",
                        field("category").unwrap_or_else(|| "<unnamed>".into())
                    ),
                });
            }

            rules.words.push(WordCategory {
                category: field("category").unwrap_or_default(),
                guidance: field("guidance").unwrap_or_default(),
                terms,
            });
        }
    }

    if let Some(freq) = get("frequency") {
        let seq = freq.as_sequence().ok_or_else(|| RulesError::Malformed {
            path: path.to_string(),
            detail: "`frequency` is not a sequence".to_string(),
        })?;
        for entry in seq {
            let m = entry.as_mapping().ok_or_else(|| RulesError::Malformed {
                path: path.to_string(),
                detail: "a `frequency` entry is not a mapping".to_string(),
            })?;
            let field = |key: &str| -> Option<String> {
                m.iter()
                    .find(|(k, _)| k.as_str() == Some(key))
                    .and_then(|(_, v)| v.as_str())
                    .map(|s| s.to_string())
            };
            let threshold = m
                .iter()
                .find(|(k, _)| k.as_str() == Some("threshold_per_thousand"))
                .and_then(|(_, v)| v.as_integer());

            // Every field is required. A frequency rule missing its
            // threshold or its unit is a rule whose behavior the source
            // does not pin, which is what R7 forbids.
            let required = |name: &str, val: Option<String>| -> Result<String, RulesError> {
                val.ok_or_else(|| RulesError::Malformed {
                    path: path.to_string(),
                    detail: format!("frequency rule is missing required field `{name}`"),
                })
            };

            let id = required("id", field("id"))?;
            rules.frequency.push(FrequencyRule {
                guidance: field("guidance").unwrap_or_default(),
                pattern: required("pattern", field("pattern"))?,
                threshold_per_thousand: threshold.ok_or_else(|| RulesError::Malformed {
                    path: path.to_string(),
                    detail: format!(
                        "frequency rule `{id}` is missing required field `threshold_per_thousand`"
                    ),
                })? as u32,
                denominator: required("denominator", field("denominator"))?,
                unit: required("unit", field("unit"))?,
                finding_line: required("finding_line", field("finding_line"))?,
                message: required("message", field("message"))?,
                min_words: m
                    .iter()
                    .find(|(k, _)| k.as_str() == Some("min_words"))
                    .and_then(|(_, v)| v.as_integer())
                    .unwrap_or(0) as usize,
                id,
            });
        }
    }

    if let Some(jo) = get("judgment_only") {
        if let Some(seq) = jo.as_sequence() {
            for entry in seq {
                if let Some(m) = entry.as_mapping() {
                    let field = |key: &str| -> String {
                        m.iter()
                            .find(|(k, _)| k.as_str() == Some(key))
                            .and_then(|(_, v)| v.as_str())
                            .unwrap_or_default()
                            .to_string()
                    };
                    rules.judgment_only.push(JudgmentOnlyRule {
                        rule: field("rule"),
                        guidance: field("guidance"),
                    });
                }
            }
        }
    }

    if rules.words.is_empty() && rules.frequency.is_empty() {
        return Err(RulesError::Malformed {
            path: path.to_string(),
            detail: "rule source declares no word or frequency rules".to_string(),
        });
    }

    Ok(rules)
}

/// Process-wide rule source, resolved once per run.
///
/// Resolved lazily rather than at startup so a caller that never runs a
/// prose check pays nothing, and cached so a run over hundreds of files
/// reads the source once. The cache holds the resolution *result*: a run
/// that could not find its rules keeps reporting that rather than retrying
/// per file and producing different findings for different documents.
static RULES_CACHE: std::sync::OnceLock<Option<Rules>> = std::sync::OnceLock::new();

/// Install an explicit rule source for this process.
///
/// Returns `false` when the cache was already set, since the first
/// resolution wins for the whole run.
pub fn set_rules(rules: Rules) -> bool {
    RULES_CACHE.set(Some(rules)).is_ok()
}

/// The resolved rule source, or `None` when resolution failed.
///
/// Callers that need the failure *reason* (the CLI, which turns it into a
/// tool error) call `resolve_rules_path` and `load_rules` directly. This
/// accessor exists for check functions, which have no error channel.
pub fn cached_rules() -> Option<Rules> {
    RULES_CACHE
        .get_or_init(|| {
            let cwd = std::env::current_dir().ok()?;
            let path = resolve_rules_path(None, &cwd).ok()?;
            load_rules(&path).ok()
        })
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> &'static str {
        r#"
schema: writing-style-rules/v1
words:
  - category: organizing
    guidance: Prefer level.
    terms:
      - alphaterm
      - betaterm
  - category: verbs
    guidance: Prefer the plain verb.
    terms:
      - gammaterm
frequency:
  - id: em-dash-density
    guidance: Document-level property.
    pattern: "—"
    threshold_per_thousand: 10
    denominator: scoped-prose-words
    unit: document
    finding_line: first-occurrence
    message: too many
judgment_only:
  - rule: synonym cycling
    guidance: Repeat the word.
"#
    }

    #[test]
    fn parses_words_frequency_and_judgment_only() {
        let r = parse_rules(sample(), "test").expect("parses");
        assert_eq!(r.words.len(), 2);
        assert_eq!(r.frequency.len(), 1);
        assert_eq!(r.judgment_only.len(), 1);
        assert_eq!(r.all_terms(), vec!["alphaterm", "betaterm", "gammaterm"]);
    }

    #[test]
    fn frequency_rule_carries_all_four_recorded_values() {
        let r = parse_rules(sample(), "test").expect("parses");
        let f = &r.frequency[0];
        assert_eq!(f.threshold_per_thousand, 10);
        assert_eq!(f.denominator, "scoped-prose-words");
        assert_eq!(f.unit, "document");
        assert_eq!(f.finding_line, "first-occurrence");
    }

    #[test]
    fn category_for_finds_the_owning_category() {
        let r = parse_rules(sample(), "test").expect("parses");
        assert_eq!(
            r.category_for("Alphaterm").map(|c| c.category.as_str()),
            Some("organizing")
        );
        assert_eq!(r.category_for("nope"), None);
    }

    #[test]
    fn missing_frequency_field_is_malformed() {
        let text = r#"
words:
  - category: c
    guidance: g
    terms: [alphaterm]
frequency:
  - id: em-dash-density
    pattern: "—"
    denominator: scoped-prose-words
    unit: document
    finding_line: first-occurrence
    message: too many
"#;
        let err = parse_rules(text, "test").expect_err("threshold is required");
        match err {
            RulesError::Malformed { detail, .. } => {
                assert!(detail.contains("threshold_per_thousand"), "got: {detail}")
            }
            other => panic!("expected Malformed, got {other:?}"),
        }
    }

    #[test]
    fn empty_rule_set_is_malformed_rather_than_silently_accepted() {
        let err = parse_rules("schema: writing-style-rules/v1\n", "test")
            .expect_err("an empty rule set must not load");
        assert!(matches!(err, RulesError::Malformed { .. }));
    }

    #[test]
    fn unparseable_yaml_is_malformed() {
        let err = parse_rules("words:\n  - [unclosed\n", "test").expect_err("bad yaml");
        assert!(matches!(err, RulesError::Malformed { .. }));
    }

    #[test]
    fn explicit_path_that_does_not_exist_errors_rather_than_falling_through() {
        let err = resolve_rules_path(Some("/nonexistent/rules.yaml"), Path::new("/"))
            .expect_err("explicit path must not fall through to the walk");
        match err {
            RulesError::NotFound { tried } => {
                assert_eq!(tried, vec!["/nonexistent/rules.yaml".to_string()])
            }
            other => panic!("expected NotFound, got {other:?}"),
        }
    }

    #[test]
    fn the_shipped_rule_source_resolves_and_parses() {
        // The ancestor walk from the crate directory must find the real
        // file. This is the acceptance criterion for reading at enforcement
        // time: if this test needs a rebuild to see a rule change, the
        // rules were embedded, which R1 forbids.
        let start = Path::new(env!("CARGO_MANIFEST_DIR"));
        let path = resolve_rules_path(None, start).expect("walk finds the shipped rule source");
        let rules = load_rules(&path).expect("the shipped rule source parses");

        assert_eq!(rules.all_terms().len(), 47, "the rulebook carries 47 terms");
        assert_eq!(rules.words.len(), 5, "five word categories");
        assert_eq!(rules.frequency.len(), 1, "one frequency rule");

        // The seven words the superseded constant carried must all survive
        // the move, or the migration silently narrowed enforcement.
        for legacy in [
            "tier",
            "tiered",
            "robust",
            "leverage",
            "comprehensive",
            "holistic",
            "facilitate",
        ] {
            assert!(
                rules.all_terms().iter().any(|t| t == legacy),
                "term `{legacy}` from the superseded constant is missing"
            );
        }
    }

    #[test]
    fn parse_is_total_over_arbitrary_input() {
        // The rule source is shirabe's own file, but a parser that panics
        // on malformed input turns an operator's typo into a crash.
        for probe in [
            "",
            "\0\0\0",
            "words: 3",
            "words:\n  - 5",
            "frequency: {}",
            &"a: ".repeat(10_000),
        ] {
            let _ = parse_rules(probe, "probe");
        }
    }
}
