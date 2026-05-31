//! `shirabe roadmap populate` -- roadmap-native populate path.
//!
//! Reads a roadmap's `## Features` section, builds a per-feature manifest
//! in the shape the canonical `create-issues-batch.sh` primitive consumes,
//! creates one planning issue per feature on GitHub (via discrete `gh
//! issue create` invocations), then renders the feature-keyed Implementation
//! Issues table and the dependency diagram and writes both into the
//! reserved sections by structural section replacement -- the body between
//! each section's heading and the next `## ` heading is replaced; the
//! heading itself is preserved.
//!
//! The R14 approval gate lives in the calling skill phase
//! (`skills/roadmap/SKILL.md`), NOT in this subcommand. The subcommand is
//! the primitive that creates issues when invoked; the caller decides
//! whether to invoke it under interactive vs `--auto` semantics.
//!
//! Security invariants this module enforces:
//!
//! - `gh` arguments are passed via `Command::arg(...)`, which Rust hands to
//!   the OS as a `posix_spawn` argv array. No shell, no string-template
//!   interpolation, no `sh -c`. Feature labels containing shell
//!   metacharacters round-trip verbatim into the issue title and the
//!   rendered table.
//! - Section-replacement writes are atomic: render into a temp file inside
//!   the roadmap's parent directory, then `std::fs::rename` over the
//!   original. A failed run leaves the roadmap unchanged byte-for-byte.

use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

use shirabe_validate::{
    extract_needs_label, parse_doc, parse_features, strip_label_decoration, Feature,
};

/// Clap-parsed args for `shirabe roadmap populate`.
#[derive(clap::Args, Debug)]
pub struct PopulateArgs {
    /// Path to the roadmap document to populate.
    pub roadmap_path: String,

    /// Milestone name to assign to all created issues.
    #[arg(long, default_value = "")]
    pub milestone: String,

    /// Milestone description (used only when the milestone is being created).
    #[arg(long = "milestone-description", default_value = "")]
    pub milestone_description: String,

    /// Pre-existing id -> github_number mapping (skip issue creation).
    #[arg(long, default_value = "")]
    pub mapping: String,

    /// Write the final id -> github_number mapping to this path.
    #[arg(long = "output-map", default_value = "")]
    pub output_map: String,

    /// Owner/repo (e.g. `tsukumogami/shirabe`) used when rendering issue
    /// links. When unset, the subcommand queries `gh repo view`.
    #[arg(long, default_value = "")]
    pub repo: String,

    /// Skip `gh` invocations; synthesize a deterministic mapping for
    /// rendering. Used by the calling skill phase to preview and by tests.
    #[arg(long = "dry-run")]
    pub dry_run: bool,
}

/// Entry point used by `main.rs`. Returns an `ExitCode` so the binary can
/// short-circuit on failure without panicking.
pub fn run(args: &PopulateArgs) -> ExitCode {
    match run_inner(args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {}", err);
            ExitCode::FAILURE
        }
    }
}

fn run_inner(args: &PopulateArgs) -> Result<(), String> {
    let roadmap = PathBuf::from(&args.roadmap_path);
    if !roadmap.is_file() {
        return Err(format!("roadmap not found: {}", roadmap.display()));
    }

    let doc = parse_doc(&args.roadmap_path).map_err(|e| format!("parse roadmap: {}", e))?;
    let features = parse_features(&doc);
    if features.is_empty() {
        return Err(format!(
            "no features parsed from {} (Features section empty or missing)",
            roadmap.display()
        ));
    }

    // Reserved sections must exist before we attempt to write into them;
    // failing fast here guarantees the atomic-write invariant
    // (no partial mutation) when the doc is malformed.
    require_section(&doc, "Implementation Issues")?;
    require_section(&doc, "Dependency Graph")?;

    let mapping = obtain_mapping(args, &features)?;
    let owner_repo = resolve_owner_repo(args)?;

    let table = render_table(&features, &mapping, &owner_repo, &args.milestone);
    let diagram = render_diagram(&features, &mapping);

    let table_body = wrap_section_body(&table);
    let diagram_body = wrap_section_body(&diagram);

    replace_section(&roadmap, "## Implementation Issues", &table_body)?;
    replace_section(&roadmap, "## Dependency Graph", &diagram_body)?;

    if !args.output_map.is_empty() {
        write_mapping_json(&PathBuf::from(&args.output_map), &mapping)?;
    }

    // Summary JSON on stdout so the calling skill phase can capture state.
    let summary = format_summary_json(&args.roadmap_path, args.dry_run, &mapping);
    println!("{}", summary);

    Ok(())
}

/// One entry in the per-feature manifest, in the shape
/// `skills/plan/scripts/create-issues-batch.sh` consumes. Kept as a struct
/// so the integration tests can assert against fields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestEntry {
    pub issue_id: String,
    pub title: String,
    pub complexity: String,
    pub status: String,
    pub dependencies: Vec<String>,
    pub needs_label: Option<String>,
    /// Issue body text. Carries `Roadmap:` and `Feature:` traceability
    /// lines so a future reader can navigate from issue back to source.
    pub body: String,
}

/// Build the per-feature manifest from parsed features.
///
/// Each entry's `title` is `feat: <clean_label>`, complexity is hard-coded
/// to `"simple"` (R13 in the PRD), `needs_label` is extracted from the
/// `**Needs:**` line, and `body` carries the `Roadmap:`/`Feature:`
/// traceability lines. Cross-feature edges are NOT pushed into the
/// manifest's `dependencies` array because the canonical
/// `create-issues-batch.sh` shape uses internal-id dependencies, and a
/// feature dependency like "Feature 1" is a label, not an issue id. The
/// dependency edges live in the rendered table's `Dependencies` cell,
/// where they are semantically correct.
pub fn build_manifest_entries(features: &[Feature], roadmap_path: &str) -> Vec<ManifestEntry> {
    features
        .iter()
        .map(|f| {
            let clean = strip_label_decoration(&f.label);
            let needs_label = extract_needs_label(&f.needs);
            let body = build_issue_body(&f.description, roadmap_path, &clean, &f.dependencies);
            ManifestEntry {
                issue_id: f.id.to_string(),
                title: format!("feat: {}", clean),
                complexity: "simple".to_string(),
                status: "PASS".to_string(),
                dependencies: Vec::new(),
                needs_label,
                body,
            }
        })
        .collect()
}

fn build_issue_body(description: &str, roadmap: &str, label: &str, deps: &str) -> String {
    let mut s = String::new();
    s.push_str("# ");
    s.push_str(label);
    s.push_str("\n\n");
    if !description.is_empty() {
        s.push_str(description);
        s.push_str("\n\n");
    }
    s.push_str("Roadmap: `");
    s.push_str(roadmap);
    s.push_str("`\n");
    s.push_str("Feature: ");
    s.push_str(label);
    s.push('\n');
    if !deps.is_empty() && deps != "None" {
        s.push_str("Roadmap dependencies: ");
        s.push_str(deps);
        s.push('\n');
    }
    s
}

/// id -> GitHub issue number mapping. BTreeMap so the JSON output is
/// deterministically sorted.
pub type IssueMap = BTreeMap<String, u64>;

fn obtain_mapping(args: &PopulateArgs, features: &[Feature]) -> Result<IssueMap, String> {
    if !args.mapping.is_empty() {
        let raw = fs::read_to_string(&args.mapping)
            .map_err(|e| format!("read mapping file {}: {}", args.mapping, e))?;
        return parse_mapping_json(&raw);
    }
    if args.dry_run {
        return Ok(synthesize_mapping(features));
    }
    create_issues_with_gh(args, features)
}

/// Synthesize a deterministic dry-run mapping so the renderer can exercise
/// the full path without any `gh` side effects. Maps feature id N to
/// GitHub number `1000 + N` (so id 1 -> #1001, id 2 -> #1002).
pub fn synthesize_mapping(features: &[Feature]) -> IssueMap {
    let mut map = IssueMap::new();
    for f in features {
        map.insert(f.id.to_string(), 1000_u64 + f.id as u64);
    }
    map
}

/// Parse a JSON object of `{"<id>": <github_number>, ...}` into an
/// [`IssueMap`]. Total over malformed input: returns an `Err` rather than
/// panicking.
pub fn parse_mapping_json(raw: &str) -> Result<IssueMap, String> {
    let mut map = IssueMap::new();
    let s = raw.trim();
    if s.is_empty() || s == "{}" {
        return Ok(map);
    }
    let s = s.strip_prefix('{').ok_or("mapping JSON must start with `{`")?;
    let s = s.strip_suffix('}').ok_or("mapping JSON must end with `}`")?;
    for pair in s.split(',') {
        let pair = pair.trim();
        if pair.is_empty() {
            continue;
        }
        let (k_raw, v_raw) = pair
            .split_once(':')
            .ok_or_else(|| format!("malformed pair: {}", pair))?;
        let key = k_raw.trim().trim_matches('"').to_string();
        let val: u64 = v_raw
            .trim()
            .parse()
            .map_err(|e| format!("malformed number in pair {}: {}", pair, e))?;
        if !key.is_empty() {
            map.insert(key, val);
        }
    }
    Ok(map)
}

/// Serialize an [`IssueMap`] to a canonical, sorted JSON object string.
pub fn render_mapping_json(map: &IssueMap) -> String {
    let mut s = String::from("{");
    for (i, (k, v)) in map.iter().enumerate() {
        if i > 0 {
            s.push_str(", ");
        }
        s.push('"');
        s.push_str(k);
        s.push_str("\": ");
        s.push_str(&v.to_string());
    }
    s.push('}');
    s
}

fn write_mapping_json(path: &Path, map: &IssueMap) -> Result<(), String> {
    fs::write(path, render_mapping_json(map))
        .map_err(|e| format!("write mapping {}: {}", path.display(), e))
}

fn create_issues_with_gh(args: &PopulateArgs, features: &[Feature]) -> Result<IssueMap, String> {
    let mut map = IssueMap::new();
    let entries = build_manifest_entries(features, &args.roadmap_path);

    for entry in &entries {
        // Discrete-args invocation. Each .arg(...) call hands the OS a
        // separate argv element via posix_spawn; no shell ever sees the
        // feature title or body.
        let mut cmd = Command::new("gh");
        cmd.arg("issue").arg("create");
        cmd.arg("--title").arg(&entry.title);
        cmd.arg("--body").arg(&entry.body);
        if !args.milestone.is_empty() {
            cmd.arg("--milestone").arg(&args.milestone);
        }
        if let Some(label) = &entry.needs_label {
            cmd.arg("--label").arg(label);
        }
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        let output = cmd
            .output()
            .map_err(|e| format!("invoke gh issue create: {}", e))?;
        if !output.status.success() {
            return Err(format!(
                "gh issue create failed for feature {}: {}",
                entry.issue_id,
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        let number = extract_issue_number(stdout.trim())
            .ok_or_else(|| format!("could not parse issue number from gh output: {}", stdout))?;
        map.insert(entry.issue_id.clone(), number);
    }
    Ok(map)
}

/// Pull a numeric issue id out of `gh issue create`'s stdout. The CLI
/// prints a URL like `https://github.com/owner/repo/issues/42`.
pub fn extract_issue_number(stdout: &str) -> Option<u64> {
    let idx = stdout.rfind("/issues/")?;
    let tail = &stdout[idx + "/issues/".len()..];
    let digits: String = tail.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

fn resolve_owner_repo(args: &PopulateArgs) -> Result<String, String> {
    if !args.repo.is_empty() {
        return Ok(args.repo.strip_prefix("https://github.com/").unwrap_or(&args.repo).to_string());
    }
    if args.dry_run {
        // Best-effort gh lookup, tolerate failure for sandboxed dry-runs.
        return Ok(gh_repo_owner_repo().unwrap_or_else(|_| "owner/repo".to_string()));
    }
    gh_repo_owner_repo()
}

fn gh_repo_owner_repo() -> Result<String, String> {
    let output = Command::new("gh")
        .args(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
        .output()
        .map_err(|e| format!("invoke gh repo view: {}", e))?;
    if !output.status.success() {
        return Err(format!(
            "gh repo view failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Render the canonical roadmap-profile Implementation Issues table.
///
/// Per `references/issues-table.md` (the shared roadmap profile from
/// Slice A): `Feature | Issues | Dependencies | Status`, with an italic
/// description row immediately following each entity row.
pub fn render_table(
    features: &[Feature],
    mapping: &IssueMap,
    owner_repo: &str,
    milestone: &str,
) -> String {
    let mut s = String::new();
    if !milestone.is_empty() {
        s.push_str("### Milestone: ");
        s.push_str(milestone);
        s.push_str("\n\n");
    }
    s.push_str("| Feature | Issues | Dependencies | Status |\n");
    s.push_str("|---------|--------|--------------|--------|\n");
    for f in features {
        let clean = strip_label_decoration(&f.label);
        let issue_cell = match mapping.get(&f.id.to_string()) {
            Some(n) => format!("[#{}](https://github.com/{}/issues/{})", n, owner_repo, n),
            None => "None".to_string(),
        };
        let deps_cell = if f.dependencies.is_empty() {
            "None"
        } else {
            &f.dependencies
        };
        let status_cell = pick_status_cell(f);
        s.push_str(&format!(
            "| {} | {} | {} | {} |\n",
            clean, issue_cell, deps_cell, status_cell
        ));
        s.push_str(&format!("| _{}_ | | | |\n", f.description));
    }
    s
}

fn pick_status_cell(f: &Feature) -> String {
    if !f.status.is_empty() && f.status != "Not started" {
        return f.status.clone();
    }
    if let Some(label) = extract_needs_label(&f.needs) {
        return label;
    }
    if f.status.is_empty() {
        "Not started".to_string()
    } else {
        f.status.clone()
    }
}

/// Render the dependency diagram per the shared
/// `references/dependency-diagram.md` convention -- feature node IDs F1,
/// F2, ...; `graph LR`; the fixed status-class palette; class assignments
/// driven by Status and Needs annotations.
pub fn render_diagram(features: &[Feature], mapping: &IssueMap) -> String {
    let mut s = String::new();
    s.push_str("```mermaid\n");
    s.push_str("graph LR\n");

    for f in features {
        let clean = strip_label_decoration(&f.label);
        let label_text = match mapping.get(&f.id.to_string()) {
            Some(n) => format!("#{}: {}", n, clean),
            None => clean,
        };
        s.push_str(&format!("    F{}[\"{}\"]\n", f.id, truncate_label(&label_text)));
    }

    s.push('\n');
    for f in features {
        if f.dependencies.is_empty() || f.dependencies == "None" {
            continue;
        }
        for n in feature_refs_in(&f.dependencies) {
            s.push_str(&format!("    F{} --> F{}\n", n, f.id));
        }
    }

    s.push('\n');
    s.push_str("    classDef done fill:#c8e6c9\n");
    s.push_str("    classDef ready fill:#bbdefb\n");
    s.push_str("    classDef blocked fill:#fff9c4\n");
    s.push_str("    classDef needsDesign fill:#e1bee7\n");
    s.push_str("    classDef needsPrd fill:#b3e5fc\n");
    s.push_str("    classDef needsSpike fill:#ffcdd2\n");
    s.push_str("    classDef needsDecision fill:#d1c4e9\n");
    s.push_str("    classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000\n");
    s.push_str("    classDef tracksPlan fill:#FFE0B2,stroke:#F57C00,color:#000\n");

    s.push('\n');
    for f in features {
        let class_name = pick_class(f);
        s.push_str(&format!("    class F{} {}\n", f.id, class_name));
    }

    s.push_str("```\n\n");
    s.push_str("**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design/tracks-plan\n");
    s
}

fn pick_class(f: &Feature) -> &'static str {
    if f.status == "Done" {
        return "done";
    }
    if let Some(label) = extract_needs_label(&f.needs) {
        return match label.as_str() {
            "needs-design" => "needsDesign",
            "needs-prd" => "needsPrd",
            "needs-spike" => "needsSpike",
            "needs-decision" => "needsDecision",
            _ => {
                if f.dependencies.is_empty() || f.dependencies == "None" {
                    "ready"
                } else {
                    "blocked"
                }
            }
        };
    }
    if f.dependencies.is_empty() || f.dependencies == "None" {
        "ready"
    } else {
        "blocked"
    }
}

/// Truncate a node label to 40 chars at the last word boundary, replacing
/// `[`/`]` with `(`/`)` per the diagram convention.
fn truncate_label(label: &str) -> String {
    let cleaned: String = label.chars().map(|c| match c {
        '[' => '(',
        ']' => ')',
        '`' => ' ',
        _ => c,
    }).collect();
    if cleaned.chars().count() <= 40 {
        return cleaned;
    }
    // Take first 40 chars by char count, then trim back to a word boundary.
    let mut truncated: String = cleaned.chars().take(40).collect();
    if let Some(last_space) = truncated.rfind(char::is_whitespace) {
        truncated.truncate(last_space);
    }
    truncated.push_str("...");
    truncated
}

/// Extract feature-id integers from a Dependencies cell. Matches the
/// pattern `Feature <N>` so cross-repo refs like `tsukumogami/koto#65` are
/// preserved without becoming diagram edges.
fn feature_refs_in(deps: &str) -> Vec<usize> {
    let mut out = Vec::new();
    let bytes = deps.as_bytes();
    let needle = b"Feature ";
    let mut i = 0;
    while i + needle.len() < bytes.len() {
        if &bytes[i..i + needle.len()] == needle {
            let start = i + needle.len();
            let mut end = start;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
            if end > start {
                if let Ok(n) = std::str::from_utf8(&bytes[start..end]).unwrap().parse::<usize>() {
                    out.push(n);
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }
    out
}

fn wrap_section_body(body: &str) -> String {
    let mut s = String::new();
    s.push_str("<!-- Populated by `shirabe roadmap populate`. Do not fill manually. -->\n\n");
    s.push_str(body);
    if !body.ends_with('\n') {
        s.push('\n');
    }
    s
}

fn require_section(doc: &shirabe_validate::Doc, name: &str) -> Result<(), String> {
    if doc.sections.iter().any(|s| s.name == name) {
        Ok(())
    } else {
        Err(format!("reserved section not found: ## {}", name))
    }
}

/// Replace the body of one `## <heading>` section by structural replacement.
/// Heading line is preserved; the body between the heading and the next
/// `## ` (or end-of-file) is replaced with `new_body`. The write is atomic:
/// renders into a temp file in the same parent directory, then renames over
/// the original.
pub fn replace_section(file: &Path, heading: &str, new_body: &str) -> Result<(), String> {
    let original = fs::read_to_string(file)
        .map_err(|e| format!("read {}: {}", file.display(), e))?;

    let mut rendered = String::with_capacity(original.len() + new_body.len());
    let mut state = ReplaceState::Before;
    let mut found = false;

    for line in original.split_inclusive('\n') {
        // `split_inclusive` keeps the trailing '\n' on each piece; we
        // compare the line without the newline to match against headings.
        let line_no_nl = line.strip_suffix('\n').unwrap_or(line);

        match state {
            ReplaceState::Before => {
                rendered.push_str(line);
                if line_no_nl == heading {
                    found = true;
                    state = ReplaceState::Inside;
                    rendered.push('\n');
                    rendered.push_str(new_body);
                }
            }
            ReplaceState::Inside => {
                if line_no_nl.starts_with("## ") {
                    state = ReplaceState::After;
                    rendered.push_str(line);
                }
                // else: drop the line (was part of the old body)
            }
            ReplaceState::After => {
                rendered.push_str(line);
            }
        }
    }

    if !found {
        return Err(format!("section heading not found: {}", heading));
    }

    atomic_write(file, &rendered)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ReplaceState {
    Before,
    Inside,
    After,
}

fn atomic_write(target: &Path, contents: &str) -> Result<(), String> {
    let parent = target
        .parent()
        .ok_or_else(|| format!("target has no parent dir: {}", target.display()))?;
    // Generate a temp file in the same directory so rename is atomic on POSIX.
    let temp_path = temp_sibling(target);
    {
        let mut f = fs::File::create(&temp_path)
            .map_err(|e| format!("create temp file {}: {}", temp_path.display(), e))?;
        f.write_all(contents.as_bytes())
            .and_then(|()| f.sync_all())
            .map_err(|e| format!("write temp file {}: {}", temp_path.display(), e))?;
    }
    // sync_all on the parent directory is best-effort; failing it
    // shouldn't roll back the rename, just emit a warning.
    let _ = fs::File::open(parent).and_then(|d| d.sync_all());
    fs::rename(&temp_path, target).map_err(|e| {
        // Clean up temp on rename failure.
        let _ = fs::remove_file(&temp_path);
        format!("atomic rename {} -> {}: {}", temp_path.display(), target.display(), e)
    })
}

fn temp_sibling(target: &Path) -> PathBuf {
    let mut name = target.file_name().unwrap_or_default().to_os_string();
    name.push(".populate.tmp.");
    // Best-effort pid + ts to disambiguate parallel runs.
    name.push(std::process::id().to_string());
    name.push(".");
    name.push(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos().to_string())
            .unwrap_or_else(|_| "0".to_string()),
    );
    let mut path = target.to_path_buf();
    path.set_file_name(name);
    path
}

fn format_summary_json(roadmap: &str, dry_run: bool, mapping: &IssueMap) -> String {
    let mut s = String::new();
    s.push_str("{\"roadmap\":\"");
    s.push_str(&json_escape(roadmap));
    s.push_str("\",\"dry_run\":");
    s.push_str(if dry_run { "true" } else { "false" });
    s.push_str(",\"mapping\":");
    s.push_str(&render_mapping_json(mapping));
    s.push_str(",\"sections_written\":[\"Implementation Issues\",\"Dependency Graph\"]}");
    s
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out
}

// Compatibility shim: `io::Write` is brought in for `write_all`. The
// unused-import lint passes because `write_all` is a method call rather
// than a direct symbol reference; the `use` line keeps it explicit.
#[allow(unused_imports)]
use io as _io_marker;

#[cfg(test)]
mod tests {
    use super::*;
    use shirabe_validate::doc::Section;

    fn make_feature(id: usize, label: &str, needs: &str, deps: &str, status: &str, desc: &str) -> Feature {
        Feature {
            id,
            label: label.to_string(),
            needs: needs.to_string(),
            dependencies: deps.to_string(),
            status: status.to_string(),
            description: desc.to_string(),
            heading_line: 0,
        }
    }

    #[test]
    fn synthesize_mapping_assigns_thousand_plus_id() {
        let features = vec![
            make_feature(1, "A", "", "None", "Not started", "A."),
            make_feature(2, "B", "", "Feature 1", "Not started", "B."),
        ];
        let map = synthesize_mapping(&features);
        assert_eq!(map.get("1"), Some(&1001));
        assert_eq!(map.get("2"), Some(&1002));
    }

    #[test]
    fn build_manifest_entries_carries_traceability() {
        let features = vec![make_feature(
            1,
            "Foundation — [#5](url)",
            "`needs-design`",
            "None",
            "Not started",
            "Foundation body.",
        )];
        let entries = build_manifest_entries(&features, "docs/roadmaps/ROADMAP-x.md");
        assert_eq!(entries.len(), 1);
        let e = &entries[0];
        assert_eq!(e.issue_id, "1");
        assert_eq!(e.title, "feat: Foundation");
        assert_eq!(e.complexity, "simple");
        assert_eq!(e.needs_label.as_deref(), Some("needs-design"));
        assert!(e.body.contains("# Foundation"));
        assert!(e.body.contains("Roadmap: `docs/roadmaps/ROADMAP-x.md`"));
        assert!(e.body.contains("Feature: Foundation"));
    }

    #[test]
    fn render_table_emits_canonical_shape() {
        let features = vec![
            make_feature(1, "Foundation", "`needs-design`", "None", "Not started", "Foundation."),
            make_feature(2, "Caching", "`needs-spike`", "Feature 1", "Not started", "Caching."),
        ];
        let map = synthesize_mapping(&features);
        let table = render_table(&features, &map, "owner/repo", "M1");
        assert!(table.contains("### Milestone: M1"));
        assert!(table.contains("| Feature | Issues | Dependencies | Status |"));
        assert!(table.contains(
            "| Foundation | [#1001](https://github.com/owner/repo/issues/1001) | None | needs-design |"
        ));
        assert!(table.contains("| _Foundation._ | | | |"));
        assert!(table.contains(
            "| Caching | [#1002](https://github.com/owner/repo/issues/1002) | Feature 1 | needs-spike |"
        ));
    }

    #[test]
    fn render_diagram_emits_full_palette_and_edges() {
        let features = vec![
            make_feature(1, "Foundation", "`needs-design`", "None", "Not started", "x."),
            make_feature(2, "Caching", "`needs-spike`", "Feature 1", "Not started", "x."),
            make_feature(3, "Done thing", "None", "Feature 1", "Done", "x."),
        ];
        let map = synthesize_mapping(&features);
        let diagram = render_diagram(&features, &map);
        assert!(diagram.contains("graph LR"));
        assert!(diagram.contains("F1[\"#1001: Foundation\"]"));
        assert!(diagram.contains("F1 --> F2"));
        assert!(diagram.contains("F1 --> F3"));
        assert!(diagram.contains("classDef done fill:#c8e6c9"));
        assert!(diagram.contains("classDef needsSpike fill:#ffcdd2"));
        assert!(diagram.contains("class F1 needsDesign"));
        assert!(diagram.contains("class F2 needsSpike"));
        assert!(diagram.contains("class F3 done"));
        assert!(diagram.contains("**Legend**:"));
    }

    #[test]
    fn extract_issue_number_parses_url_form() {
        assert_eq!(
            extract_issue_number("https://github.com/owner/repo/issues/42"),
            Some(42)
        );
        assert_eq!(
            extract_issue_number("https://github.com/owner/repo/issues/12345\n"),
            Some(12345)
        );
        assert_eq!(extract_issue_number("no issue url here"), None);
    }

    #[test]
    fn parse_and_render_mapping_json_round_trip() {
        let mut map = IssueMap::new();
        map.insert("1".to_string(), 1000);
        map.insert("2".to_string(), 1001);
        let rendered = render_mapping_json(&map);
        let parsed = parse_mapping_json(&rendered).unwrap();
        assert_eq!(parsed, map);
    }

    #[test]
    fn feature_refs_in_extracts_only_feature_tokens() {
        assert_eq!(feature_refs_in("None"), Vec::<usize>::new());
        assert_eq!(feature_refs_in("Feature 1"), vec![1]);
        assert_eq!(
            feature_refs_in("tsukumogami/koto#65, Feature 1, Feature 22"),
            vec![1, 22]
        );
    }

    #[test]
    fn truncate_label_under_40_chars_passes_through() {
        let s = "short label";
        assert_eq!(truncate_label(s), s);
    }

    #[test]
    fn truncate_label_long_truncates_at_word_boundary() {
        let s = "This label is intentionally longer than forty characters total";
        let out = truncate_label(s);
        assert!(out.ends_with("..."));
        assert!(out.chars().count() <= 43);
        // The truncated label keeps whole words.
        assert!(!out.contains("intent..."));
    }

    #[test]
    fn truncate_label_replaces_brackets_and_backticks() {
        assert_eq!(
            truncate_label("[Foo] `bar`"),
            "(Foo)  bar "
        );
    }

    #[test]
    fn replace_section_replaces_body_atomically() {
        let dir = tempdir();
        let path = dir.join("roadmap.md");
        fs::write(
            &path,
            "# title\n\n## Implementation Issues\n\nOLD\n\n## Dependency Graph\n\nOLD\n",
        )
        .unwrap();
        let original_hash = sha256_of(&path);
        replace_section(&path, "## Implementation Issues", "NEW BODY\n").unwrap();
        let updated = fs::read_to_string(&path).unwrap();
        assert!(updated.contains("## Implementation Issues\n\nNEW BODY\n"));
        assert!(updated.contains("## Dependency Graph"));
        assert!(!updated.contains("OLD\n\n## Dependency"));
        assert_ne!(sha256_of(&path), original_hash);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn replace_section_missing_heading_leaves_file_unchanged() {
        let dir = tempdir();
        let path = dir.join("roadmap.md");
        let original = "# title\n\n## Other\n\nbody\n";
        fs::write(&path, original).unwrap();
        let before_hash = sha256_of(&path);
        let res = replace_section(&path, "## Implementation Issues", "NEW\n");
        assert!(res.is_err());
        let after_hash = sha256_of(&path);
        assert_eq!(before_hash, after_hash);
        let _ = fs::remove_dir_all(&dir);
    }

    fn tempdir() -> PathBuf {
        let base = std::env::temp_dir();
        let dir = base.join(format!(
            "shirabe-populate-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn sha256_of(path: &Path) -> Vec<u8> {
        // Minimal hash for change-detection in tests: read file and run a
        // simple FNV-1a accumulator. We don't need cryptographic strength
        // here -- only "did the bytes change".
        let bytes = fs::read(path).unwrap();
        let mut h: u64 = 0xcbf29ce484222325;
        for b in bytes {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        h.to_le_bytes().to_vec()
    }

    fn make_doc_with_sections(body: Vec<&str>, sections: Vec<(&str, usize)>) -> shirabe_validate::Doc {
        shirabe_validate::Doc {
            path: "t.md".into(),
            schema: "roadmap/v1".into(),
            status: "Draft".into(),
            fields: Default::default(),
            sections: sections
                .into_iter()
                .map(|(name, line)| Section {
                    name: name.into(),
                    line,
                })
                .collect(),
            body: body.into_iter().map(str::to_string).collect(),
        }
    }

    #[test]
    fn require_section_succeeds_when_present() {
        let doc = make_doc_with_sections(
            vec!["## Implementation Issues", "", "## Dependency Graph"],
            vec![("Implementation Issues", 1), ("Dependency Graph", 3)],
        );
        assert!(require_section(&doc, "Implementation Issues").is_ok());
        assert!(require_section(&doc, "Dependency Graph").is_ok());
    }

    #[test]
    fn require_section_errors_when_absent() {
        let doc = make_doc_with_sections(vec!["## Other"], vec![("Other", 1)]);
        assert!(require_section(&doc, "Implementation Issues").is_err());
    }
}
