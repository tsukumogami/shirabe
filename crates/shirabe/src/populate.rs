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
use std::sync::LazyLock;

use regex::Regex;

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

    /// Issueless render mode. Skips `gh issue create` entirely (no GitHub
    /// calls) and renders both reserved sections from feature context: a
    /// feature-keyed Implementation Issues table (rows keyed `F1`, `F2`,
    /// ...) and an `F<n>`-node Dependency Graph. Set by the roadmap skill
    /// when the repo declares `## Roadmap Issues: optional`.
    #[arg(long = "no-issues")]
    pub no_issues: bool,
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

    // Issueless mode renders both sections from feature context and makes
    // no GitHub calls. It shares the section-replacement writer and the
    // Features parser with the issue-creating path; only issue creation and
    // the table/diagram keying differ. The R14 approval gate (in the calling
    // skill phase) is irrelevant here -- nothing is created to approve.
    if args.no_issues {
        return run_issueless(args, &roadmap, &features);
    }

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

/// Issueless render path: fills both reserved sections from feature context
/// with no `gh` invocations. The Implementation Issues table is feature-keyed
/// (each row keyed `F1`, `F2`, ... so the bare-key Dependencies cells
/// reconcile under FC06), and the Dependency Graph uses `F<n>` nodes labeled
/// with the feature names. Writes via the same structural section-replacement
/// writer the issue-creating path uses.
fn run_issueless(args: &PopulateArgs, roadmap: &Path, features: &[Feature]) -> Result<(), String> {
    let table = render_issueless_table(features, &args.milestone);
    let diagram = render_issueless_diagram(features);

    let table_body = wrap_section_body(&table);
    let diagram_body = wrap_section_body(&diagram);

    replace_section(roadmap, "## Implementation Issues", &table_body)?;
    replace_section(roadmap, "## Dependency Graph", &diagram_body)?;

    // Issueless mode creates no issues, so the mapping is empty; emit the
    // same summary shape the issue-creating path does for caller-state
    // parity (an empty `mapping` object signals the issueless run).
    let mapping = IssueMap::new();
    if !args.output_map.is_empty() {
        write_mapping_json(&PathBuf::from(&args.output_map), &mapping)?;
    }
    let summary = format_summary_json(&args.roadmap_path, args.dry_run, &mapping);
    println!("{}", summary);

    Ok(())
}

/// Render the feature-keyed Implementation Issues table for issueless mode.
///
/// The roadmap profile (`Feature | Issues | Dependencies | Status`) is
/// preserved so the validator selects the roadmap branch. The first column
/// carries the feature key (`F1`, `F2`, ...) so the row key equals the bare
/// dependency token a depending feature references; the Issues column carries
/// the feature's `needs-*` label (or `None` when absent); the Dependencies
/// column holds bare feature keys with NO parenthetical annotations (those
/// trip FC06); the Status column comes from the feature's `**Status:**`. Each
/// entity row is followed by an italic description row, matching the
/// issue-creating renderer and FC05's row-shape requirement.
pub fn render_issueless_table(features: &[Feature], milestone: &str) -> String {
    let mut s = String::new();
    if !milestone.is_empty() {
        s.push_str("### Milestone: ");
        s.push_str(milestone);
        s.push_str("\n\n");
    }
    s.push_str("| Feature | Issues | Dependencies | Status |\n");
    s.push_str("|---------|--------|--------------|--------|\n");
    for f in features {
        let key = format!("F{}", f.id);
        // A delivered feature no longer awaits an upstream artifact, so its
        // Issues cell is `None`, never a leftover `needs-*` label.
        let issue_cell = if feature_is_terminal(f) {
            "None".to_string()
        } else {
            match extract_needs_label(&f.needs) {
                Some(label) => label,
                None => "None".to_string(),
            }
        };
        let deps_cell = bare_feature_deps(&f.dependencies);
        let status_cell = pick_status_cell(f);
        let desc = concise_description(&f.description);
        if feature_is_terminal(f) {
            s.push_str(&format!(
                "| ~~{}~~ | ~~{}~~ | ~~{}~~ | ~~{}~~ |\n",
                key, issue_cell, deps_cell, status_cell
            ));
            s.push_str(&format!("| ~~_{}_~~ | | | |\n", desc));
        } else {
            s.push_str(&format!(
                "| {} | {} | {} | {} |\n",
                key, issue_cell, deps_cell, status_cell
            ));
            s.push_str(&format!("| _{}_ | | | |\n", desc));
        }
    }
    s
}

/// Render the `F<n>`-node Dependency Graph for issueless mode.
///
/// Nodes are `F<n>` labeled with the (truncated) feature name; edges derive
/// from each feature's stated dependencies (`F1 --> F2`). The status-class
/// palette and Legend mirror the issue-creating diagram so a reader sees the
/// same `needs-*` coloring in both modes.
pub fn render_issueless_diagram(features: &[Feature]) -> String {
    let mut s = String::new();
    s.push_str("```mermaid\n");
    s.push_str("graph TD\n");

    for f in features {
        let clean = strip_label_decoration(&f.label);
        s.push_str(&format!("    F{}[\"{}\"]\n", f.id, truncate_label(&clean)));
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

    let mut assigned: Vec<&'static str> = Vec::new();
    for f in features {
        let class = pick_class(f, features);
        if !assigned.contains(&class) {
            assigned.push(class);
        }
    }
    s.push('\n');
    render_class_defs(&assigned, &mut s);

    s.push('\n');
    for f in features {
        s.push_str(&format!(
            "    class F{} {}\n",
            f.id,
            pick_class(f, features)
        ));
    }

    s.push_str("```\n\n");
    s.push_str(&render_legend(&assigned));
    s
}

/// Convert a feature's raw Dependencies value into a bare-key cell.
///
/// `Feature 1` -> `F1`, `Feature 1, Feature 2` -> `F1, F2`, `None`/empty ->
/// `None`. NO parenthetical annotations are emitted -- `F1 (soft)` and
/// `None (ext: ...)` trip the validator's FC06 check, so the soft/hard and
/// external nuance stays in the feature prose, not the cell. Cross-repo refs
/// in the source (e.g. `tsukumogami/koto#65`) carry no `Feature N` token and
/// so contribute no bare key; when a feature lists only such refs the cell
/// collapses to `None`.
fn bare_feature_deps(deps: &str) -> String {
    let refs = feature_refs_in(deps);
    if refs.is_empty() {
        return "None".to_string();
    }
    refs.iter()
        .map(|n| format!("F{}", n))
        .collect::<Vec<_>>()
        .join(", ")
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

/// Build the [`ManifestEntry`] for one feature.
///
/// The entry's `title` is `feat: <clean_label>`, complexity is hard-coded
/// to `"simple"` (R13 in the PRD), `needs_label` is extracted from the
/// `**Needs:**` line, and `body` carries the `Roadmap:`/`Feature:`
/// traceability lines. Cross-feature edges are NOT pushed into the
/// manifest's `dependencies` array because the canonical
/// `create-issues-batch.sh` shape uses internal-id dependencies, and a
/// feature dependency like "Feature 1" is a label, not an issue id. The
/// dependency edges live in the rendered table's `Dependencies` cell,
/// where they are semantically correct.
fn manifest_entry_for(f: &Feature, roadmap_path: &str) -> ManifestEntry {
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

/// Resolve the id -> GitHub issue number mapping for a populate run.
///
/// Any `--mapping` input seeds the result: it references features whose
/// tracking work already exists (delivered or in flight), so those
/// features are never re-created. Fresh issues are minted only for
/// features that are BOTH absent from the seed AND not already terminal --
/// an already-`Done` feature never gets a new open issue (issue #233), it
/// is struck through in the table with an `Issues = None` (or seed-mapped)
/// cell instead. Under `--dry-run` the same selection is made but the
/// numbers are synthesized rather than created on GitHub.
fn obtain_mapping(args: &PopulateArgs, features: &[Feature]) -> Result<IssueMap, String> {
    let mut map = IssueMap::new();
    if !args.mapping.is_empty() {
        let raw = fs::read_to_string(&args.mapping)
            .map_err(|e| format!("read mapping file {}: {}", args.mapping, e))?;
        map = parse_mapping_json(&raw)?;
    }

    // Features still needing a fresh tracking issue.
    let to_create: Vec<&Feature> = features
        .iter()
        .filter(|f| !map.contains_key(&f.id.to_string()) && !feature_is_terminal(f))
        .collect();

    if args.dry_run {
        for f in &to_create {
            map.insert(f.id.to_string(), 1000_u64 + f.id as u64);
        }
        return Ok(map);
    }

    let created = create_issues_with_gh(args, &to_create)?;
    for (k, v) in created {
        map.insert(k, v);
    }
    Ok(map)
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
    let s = s
        .strip_prefix('{')
        .ok_or("mapping JSON must start with `{`")?;
    let s = s
        .strip_suffix('}')
        .ok_or("mapping JSON must end with `}`")?;
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

/// Create one GitHub issue per feature in `features` (the subset selected
/// by [`obtain_mapping`] -- never an already-terminal or already-mapped
/// feature) and return the id -> issue-number mapping for those creations.
fn create_issues_with_gh(args: &PopulateArgs, features: &[&Feature]) -> Result<IssueMap, String> {
    let mut map = IssueMap::new();
    let entries: Vec<ManifestEntry> = features
        .iter()
        .map(|f| manifest_entry_for(f, &args.roadmap_path))
        .collect();

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
        return Ok(args
            .repo
            .strip_prefix("https://github.com/")
            .unwrap_or(&args.repo)
            .to_string());
    }
    if args.dry_run {
        // Best-effort gh lookup, tolerate failure for sandboxed dry-runs.
        return Ok(gh_repo_owner_repo().unwrap_or_else(|_| "owner/repo".to_string()));
    }
    gh_repo_owner_repo()
}

fn gh_repo_owner_repo() -> Result<String, String> {
    let output = Command::new("gh")
        .args([
            "repo",
            "view",
            "--json",
            "nameWithOwner",
            "--jq",
            ".nameWithOwner",
        ])
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
        let deps_cell = render_deps_cell(&f.dependencies, features);
        let status_cell = pick_status_cell(f);
        let desc = concise_description(&f.description);
        if feature_is_terminal(f) {
            // A delivered feature's rows are struck through per
            // `references/issues-table.md`; the entity row and its
            // description row are struck together.
            s.push_str(&format!(
                "| ~~{}~~ | ~~{}~~ | ~~{}~~ | ~~{}~~ |\n",
                clean, issue_cell, deps_cell, status_cell
            ));
            s.push_str(&format!("| ~~_{}_~~ | | | |\n", desc));
        } else {
            s.push_str(&format!(
                "| {} | {} | {} | {} |\n",
                clean, issue_cell, deps_cell, status_cell
            ));
            s.push_str(&format!("| _{}_ | | | |\n", desc));
        }
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
/// `references/dependency-diagram.md` convention.
///
/// Nodes use `I<issue-number>` ids so they bind to the `#n` links in the
/// Implementation Issues table's Issues column (the FC07 roadmap
/// bijection). Only features that decomposed into an issue (present in
/// `mapping`) contribute a node; a delivered feature that was not given a
/// tracking issue has an `Issues = None` row and therefore no node, exactly
/// as the reference requires. Edges run blocker-to-dependent between
/// issue-keyed nodes; class assignments come from [`pick_class`]; the
/// `classDef` block and Legend name only the classes actually assigned so
/// FC08 stays clean.
pub fn render_diagram(features: &[Feature], mapping: &IssueMap) -> String {
    let mut s = String::new();
    s.push_str("```mermaid\n");
    s.push_str("graph LR\n");

    // Nodes: one per feature that decomposed into an issue.
    for f in features {
        if let Some(n) = mapping.get(&f.id.to_string()) {
            let clean = strip_label_decoration(&f.label);
            let label_text = format!("#{}: {}", n, clean);
            s.push_str(&format!(
                "    I{}[\"{}\"]\n",
                n,
                truncate_label(&label_text)
            ));
        }
    }

    // Edges: blocker --> dependent, only between issue-keyed nodes.
    s.push('\n');
    for f in features {
        let Some(dependent) = mapping.get(&f.id.to_string()) else {
            continue;
        };
        for id in feature_refs_in(&f.dependencies) {
            if let Some(dep) = features.iter().find(|g| g.id == id) {
                if let Some(blocker) = mapping.get(&dep.id.to_string()) {
                    s.push_str(&format!("    I{} --> I{}\n", blocker, dependent));
                }
            }
        }
    }

    // Class definitions and assignments, restricted to assigned classes.
    let mut assigned: Vec<&'static str> = Vec::new();
    for f in features {
        if mapping.contains_key(&f.id.to_string()) {
            let class = pick_class(f, features);
            if !assigned.contains(&class) {
                assigned.push(class);
            }
        }
    }
    s.push('\n');
    render_class_defs(&assigned, &mut s);

    s.push('\n');
    for f in features {
        if let Some(n) = mapping.get(&f.id.to_string()) {
            s.push_str(&format!("    class I{} {}\n", n, pick_class(f, features)));
        }
    }

    s.push_str("```\n\n");
    s.push_str(&render_legend(&assigned));
    s
}

/// Choose the diagram Status/pipeline class for a feature node.
///
/// A terminal feature is `done`; a feature awaiting an upstream artifact
/// carries its pipeline-stage class (`needsDesign`, ...); otherwise the
/// node is `ready` or `blocked` per its dependencies. The ready/blocked
/// decision is dependency-aware and mirrors FC07's `expected_class`: a
/// feature is `blocked` only while a dependency is still open (or a
/// cross-repo dependency's state cannot be observed), and becomes `ready`
/// once every local dependency is terminal. This keeps the emitted class
/// consistent with the validator, including when a feature's only blocker
/// has already shipped.
fn pick_class(f: &Feature, features: &[Feature]) -> &'static str {
    if feature_is_terminal(f) {
        return "done";
    }
    if let Some(label) = extract_needs_label(&f.needs) {
        return match label.as_str() {
            "needs-design" => "needsDesign",
            "needs-prd" => "needsPrd",
            "needs-spike" => "needsSpike",
            "needs-decision" => "needsDecision",
            "needs-planning" => "needsPlanning",
            "needs-explore" => "needsExplore",
            _ => ready_or_blocked(f, features),
        };
    }
    ready_or_blocked(f, features)
}

/// Resolve `ready` vs `blocked` from a feature's dependencies. Blocked
/// while any local dependency is not yet terminal, or a cross-repo
/// dependency is present (its state is unobservable from this doc);
/// otherwise ready. Dependency ids that name no feature in this roadmap
/// are ignored -- `render_deps_cell` drops them too, so the diagram and
/// table stay in agreement.
fn ready_or_blocked(f: &Feature, features: &[Feature]) -> &'static str {
    if has_cross_repo_dep(&f.dependencies) {
        return "blocked";
    }
    for id in feature_refs_in(&f.dependencies) {
        if let Some(dep) = features.iter().find(|g| g.id == id) {
            if !feature_is_terminal(dep) {
                return "blocked";
            }
        }
    }
    "ready"
}

/// Truncate a node label to 40 chars at the last word boundary, replacing
/// `[`/`]` with `(`/`)` per the diagram convention.
fn truncate_label(label: &str) -> String {
    let cleaned: String = label
        .chars()
        .map(|c| match c {
            '[' => '(',
            ']' => ')',
            '`' => ' ',
            _ => c,
        })
        .collect();
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

/// Derive a concise 1-sentence description for an entity row's italic
/// description cell.
///
/// The Features-section parser collapses a feature's entire prose body
/// into one string. Rendering that verbatim produces a multi-hundred-word
/// cell (issue #232 defect b). Instead we prefer the feature's
/// `**Functional outcome:**` sentence when present -- the single sentence
/// stating what the feature delivers -- and fall back to the first
/// sentence of the body otherwise, matching `issues-table.md`'s "1-3
/// sentences" guideline for description rows.
fn concise_description(desc: &str) -> String {
    let text = desc.trim();
    if text.is_empty() {
        return String::new();
    }
    let body = match find_ci(text, "**functional outcome:**") {
        Some(idx) => text[idx + "**functional outcome:**".len()..].trim_start(),
        None => text,
    };
    let sentence = first_sentence(body);
    if sentence.is_empty() {
        text.to_string()
    } else {
        sentence
    }
}

/// Case-insensitive ASCII substring search. `needle` must be lowercase
/// ASCII. Returns the byte offset in `haystack` of the first match, which
/// -- because the needle matches only ASCII bytes -- is always on a UTF-8
/// character boundary. Total over arbitrary UTF-8 input.
fn find_ci(haystack: &str, needle_lower: &str) -> Option<usize> {
    let h = haystack.as_bytes();
    let n = needle_lower.as_bytes();
    if n.is_empty() || h.len() < n.len() {
        return None;
    }
    (0..=h.len() - n.len()).find(|&i| {
        h[i..i + n.len()]
            .iter()
            .zip(n)
            .all(|(a, b)| a.to_ascii_lowercase() == *b)
    })
}

/// Return the first sentence of `text` -- everything up to and including
/// the first `.`, `!`, or `?` that is followed by whitespace or the end of
/// the string. When no terminator is found, the whole (trimmed) string is
/// returned. Sentence terminators are single-byte ASCII, so slicing on
/// their index never splits a multi-byte character.
fn first_sentence(text: &str) -> String {
    let text = text.trim();
    let bytes = text.as_bytes();
    for (i, &c) in bytes.iter().enumerate() {
        if c == b'.' || c == b'!' || c == b'?' {
            let at_end = i + 1 >= bytes.len();
            let followed_by_space = !at_end && bytes[i + 1].is_ascii_whitespace();
            if at_end || followed_by_space {
                return text[..=i].trim().to_string();
            }
        }
    }
    text.to_string()
}

/// Render an issue-creating-mode Dependencies cell that names actual table
/// row keys.
///
/// Each `Feature N` reference resolves to that feature's clean label -- the
/// same text the entity row's key column carries -- so FC06's
/// cross-reference existence check passes (the raw `Feature N` token names
/// no row; the label does). Cross-repo references (`owner/repo#N`) are
/// preserved verbatim: FC06 treats them as non-local and skips them, and
/// the roadmap corpus expects them to round-trip. Returns `None` when the
/// cell resolves to no references.
fn render_deps_cell(deps: &str, features: &[Feature]) -> String {
    let mut parts: Vec<String> = Vec::new();
    for id in feature_refs_in(deps) {
        if let Some(f) = features.iter().find(|f| f.id == id) {
            let label = strip_label_decoration(&f.label);
            if !parts.contains(&label) {
                parts.push(label);
            }
        }
    }
    for tok in deps.split(',') {
        let tok = tok.trim();
        if tok.is_empty() || tok.eq_ignore_ascii_case("none") {
            continue;
        }
        if tok.contains('/') && !parts.iter().any(|p| p == tok) {
            parts.push(tok.to_string());
        }
    }
    if parts.is_empty() {
        "None".to_string()
    } else {
        parts.join(", ")
    }
}

/// The canonical diagram class palette: `(class name, classDef style,
/// legend color)` in the fixed order of `references/dependency-diagram.md`.
/// Both diagram renderers emit `classDef` lines and a Legend line derived
/// from this table, restricted to the classes actually assigned to nodes.
/// Emitting only assigned classes keeps FC08 clean: every declared
/// `classDef` outside the Status palette is named in the Legend (Sub-B),
/// and the Legend names each class by its camelCase `classDef` identifier
/// (Sub-C), never the kebab-case form.
const CLASS_PALETTE: &[(&str, &str, &str)] = &[
    ("done", "fill:#c8e6c9", "Green"),
    ("ready", "fill:#bbdefb", "Blue"),
    ("blocked", "fill:#fff9c4", "Yellow"),
    ("needsDesign", "fill:#e1bee7", "Purple"),
    ("needsPrd", "fill:#b3e5fc", "Cyan"),
    ("needsSpike", "fill:#ffcdd2", "Red"),
    ("needsDecision", "fill:#d1c4e9", "Indigo"),
    ("needsPlanning", "fill:#fff9c4", "Yellow"),
    ("needsExplore", "fill:#ffe0b2", "Orange"),
    (
        "tracksDesign",
        "fill:#FFE0B2,stroke:#F57C00,color:#000",
        "Orange",
    ),
    (
        "tracksPlan",
        "fill:#FFE0B2,stroke:#F57C00,color:#000",
        "Orange",
    ),
];

/// Emit the `classDef` block and the Legend line for the diagram, covering
/// exactly the classes in `assigned` (in canonical palette order). A class
/// assigned to a node but absent from [`CLASS_PALETTE`] is skipped -- the
/// renderers only ever assign palette classes, so this cannot drop a class
/// a node actually uses.
fn render_class_defs(assigned: &[&str], out: &mut String) {
    for (name, style, _color) in CLASS_PALETTE {
        if assigned.contains(name) {
            out.push_str(&format!("    classDef {} {}\n", name, style));
        }
    }
}

/// Build the Legend line naming each assigned class by its `classDef`
/// identifier (camelCase for pipeline-stage classes), so FC08's
/// Legend-vs-classDef reconciliation passes.
fn render_legend(assigned: &[&str]) -> String {
    let entries: Vec<String> = CLASS_PALETTE
        .iter()
        .filter(|(name, _, _)| assigned.contains(name))
        .map(|(name, _, color)| format!("{} = {}", color, name))
        .collect();
    format!("**Legend**: {}\n", entries.join(", "))
}

/// Matches a `**Dependencies:**` reference to one or more features. The
/// keyword is `Feature` or `Features` (case-insensitive), followed by a
/// list of feature-index integers separated by commas, whitespace, or the
/// word `and`. The capture group holds the raw number list, from which
/// [`feature_refs_in`] extracts each integer. Cross-repo refs such as
/// `tsukumogami/koto#65` carry no `Feature` keyword and so contribute no
/// captures, keeping them out of the diagram edges.
static FEATURE_DEP_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)features?\s+(\d+(?:[\s,]+(?:and[\s,]+)?\d+)*)").unwrap());

/// Matches a run of ASCII digits, used to pull each integer out of a
/// [`FEATURE_DEP_RE`] number list.
static DIGITS_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d+").unwrap());

/// Extract feature-id integers from a Dependencies cell.
///
/// Handles every standard `**Dependencies:**` shape: the singular
/// `Feature N`, the plural `Features N, M`, comma lists (`Feature 1,
/// Feature 2`), and `and` variants (`Features 2 and 3`, `Feature 1, 2 and
/// 3`). Cross-repo refs like `tsukumogami/koto#65` carry no `Feature`
/// keyword, so their trailing digits are never mistaken for feature
/// indices. The returned ids preserve first-seen order and are
/// de-duplicated, so a cell that names the same feature twice yields one
/// edge.
fn feature_refs_in(deps: &str) -> Vec<usize> {
    let mut out: Vec<usize> = Vec::new();
    for cap in FEATURE_DEP_RE.captures_iter(deps) {
        for m in DIGITS_RE.find_iter(&cap[1]) {
            if let Ok(n) = m.as_str().parse::<usize>() {
                if !out.contains(&n) {
                    out.push(n);
                }
            }
        }
    }
    out
}

/// Reports whether a roadmap feature has reached a terminal (delivered)
/// state. Mirrors `is_terminal_roadmap_status` in `shirabe-validate`'s
/// table parser: `Done` and `Closed` (case-insensitive, trimmed) are
/// terminal; every other Status value is open.
fn feature_is_terminal(f: &Feature) -> bool {
    let s = f.status.trim();
    s.eq_ignore_ascii_case("Done") || s.eq_ignore_ascii_case("Closed")
}

/// Reports whether a Dependencies cell names at least one cross-repo
/// reference (a comma-separated token containing `/`, such as
/// `owner/repo#N`). The local diagram cannot observe a cross-repo
/// dependency's state, so its presence forces the dependent node to
/// `blocked` -- matching FC07's `expected_class` treatment.
fn has_cross_repo_dep(deps: &str) -> bool {
    deps.split(',').any(|tok| tok.trim().contains('/'))
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
    let original =
        fs::read_to_string(file).map_err(|e| format!("read {}: {}", file.display(), e))?;

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
        format!(
            "atomic rename {} -> {}: {}",
            temp_path.display(),
            target.display(),
            e
        )
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

    fn make_feature(
        id: usize,
        label: &str,
        needs: &str,
        deps: &str,
        status: &str,
        desc: &str,
    ) -> Feature {
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

    /// Build a full id -> `1000 + id` mapping for a feature slice, matching
    /// the dry-run number scheme. Test helper for exercising the renderers
    /// with every feature carrying an issue number.
    fn synthesize_mapping(features: &[Feature]) -> IssueMap {
        let mut map = IssueMap::new();
        for f in features {
            map.insert(f.id.to_string(), 1000_u64 + f.id as u64);
        }
        map
    }

    #[test]
    fn manifest_entry_for_carries_traceability() {
        let feature = make_feature(
            1,
            "Foundation — [#5](url)",
            "`needs-design`",
            "None",
            "Not started",
            "Foundation body.",
        );
        let e = manifest_entry_for(&feature, "docs/roadmaps/ROADMAP-x.md");
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
            make_feature(
                1,
                "Foundation",
                "`needs-design`",
                "None",
                "Not started",
                "Foundation.",
            ),
            make_feature(
                2,
                "Caching",
                "`needs-spike`",
                "Feature 1",
                "Not started",
                "Caching.",
            ),
        ];
        let map = synthesize_mapping(&features);
        let table = render_table(&features, &map, "owner/repo", "M1");
        assert!(table.contains("### Milestone: M1"));
        assert!(table.contains("| Feature | Issues | Dependencies | Status |"));
        assert!(table.contains(
            "| Foundation | [#1001](https://github.com/owner/repo/issues/1001) | None | needs-design |"
        ));
        assert!(table.contains("| _Foundation._ | | | |"));
        // The Dependencies cell names the depended-on feature's row key
        // (its label), not the raw `Feature 1` token (which would trip FC06).
        assert!(table.contains(
            "| Caching | [#1002](https://github.com/owner/repo/issues/1002) | Foundation | needs-spike |"
        ));
    }

    #[test]
    fn render_diagram_emits_full_palette_and_edges() {
        let features = vec![
            make_feature(
                1,
                "Foundation",
                "`needs-design`",
                "None",
                "Not started",
                "x.",
            ),
            make_feature(
                2,
                "Caching",
                "`needs-spike`",
                "Feature 1",
                "Not started",
                "x.",
            ),
            make_feature(3, "Done thing", "None", "Feature 1", "Done", "x."),
        ];
        let map = synthesize_mapping(&features);
        let diagram = render_diagram(&features, &map);
        assert!(diagram.contains("graph LR"));
        // Nodes are keyed `I<issue-number>` so they bind to the `#n` links
        // in the table's Issues column (FC07 roadmap bijection).
        assert!(diagram.contains("I1001[\"#1001: Foundation\"]"));
        assert!(diagram.contains("I1001 --> I1002"));
        assert!(diagram.contains("I1001 --> I1003"));
        // Only assigned classes get a classDef; unused palette entries
        // (needsPrd, needsDecision, tracks*) are omitted so FC08 Sub-B
        // stays clean.
        assert!(diagram.contains("classDef done fill:#c8e6c9"));
        assert!(diagram.contains("classDef needsSpike fill:#ffcdd2"));
        assert!(diagram.contains("classDef needsDesign fill:#e1bee7"));
        assert!(!diagram.contains("classDef needsDecision"));
        assert!(!diagram.contains("classDef tracksPlan"));
        assert!(diagram.contains("class I1001 needsDesign"));
        assert!(diagram.contains("class I1002 needsSpike"));
        assert!(diagram.contains("class I1003 done"));
        // The Legend names classes by their camelCase classDef id (FC08
        // Sub-C), never the kebab-case form.
        assert!(diagram.contains("**Legend**:"));
        assert!(diagram.contains("= needsSpike"));
        assert!(!diagram.contains("needs-design"));
    }

    #[test]
    fn bare_feature_deps_strips_to_keys_or_none() {
        assert_eq!(bare_feature_deps("None"), "None");
        assert_eq!(bare_feature_deps(""), "None");
        assert_eq!(bare_feature_deps("Feature 1"), "F1");
        assert_eq!(bare_feature_deps("Feature 1, Feature 2"), "F1, F2");
        // A cross-repo-only dependency carries no `Feature N` token, so the
        // cell collapses to `None` (the nuance lives in feature prose).
        assert_eq!(bare_feature_deps("tsukumogami/koto#65"), "None");
        // Mixed: only the local feature tokens survive as bare keys.
        assert_eq!(bare_feature_deps("tsukumogami/koto#65, Feature 1"), "F1");
    }

    #[test]
    fn render_issueless_table_is_feature_keyed_with_bare_deps() {
        let features = vec![
            make_feature(
                1,
                "Foundation",
                "`needs-design` -- pending",
                "None",
                "Not started",
                "Foundation.",
            ),
            make_feature(
                2,
                "Caching",
                "`needs-spike`",
                "Feature 1",
                "Not started",
                "Caching.",
            ),
        ];
        let table = render_issueless_table(&features, "M1");
        assert!(table.contains("### Milestone: M1"));
        assert!(table.contains("| Feature | Issues | Dependencies | Status |"));
        // Rows are keyed F1/F2 (NOT the feature name, NOT an issue link), the
        // Issues column carries the needs-* label, deps are bare keys.
        assert!(table.contains("| F1 | needs-design | None | needs-design |"));
        assert!(table.contains("| _Foundation._ | | | |"));
        assert!(table.contains("| F2 | needs-spike | F1 | needs-spike |"));
        assert!(table.contains("| _Caching._ | | | |"));
        // No GitHub issue links leak into the issueless table.
        assert!(!table.contains("https://github.com"));
        assert!(!table.contains("[#"));
    }

    #[test]
    fn render_issueless_table_no_needs_label_renders_none_issue_cell() {
        let features = vec![make_feature(
            1,
            "Plain",
            "None",
            "None",
            "In Progress",
            "Plain feature.",
        )];
        let table = render_issueless_table(&features, "");
        // No `### Milestone:` line when the milestone is empty.
        assert!(!table.contains("### Milestone"));
        // A feature with no needs-* label gets a `None` Issues cell and keeps
        // its declared Status.
        assert!(table.contains("| F1 | None | None | In Progress |"));
    }

    #[test]
    fn render_issueless_diagram_uses_feature_nodes_and_edges() {
        let features = vec![
            make_feature(
                1,
                "Foundation",
                "`needs-design`",
                "None",
                "Not started",
                "x.",
            ),
            make_feature(
                2,
                "Caching",
                "`needs-spike`",
                "Feature 1",
                "Not started",
                "x.",
            ),
            make_feature(3, "Done thing", "None", "Feature 1", "Done", "x."),
        ];
        let diagram = render_issueless_diagram(&features);
        assert!(diagram.contains("graph TD"));
        // F<n> nodes labeled with the feature name (no `#<issue>:` prefix).
        assert!(diagram.contains("F1[\"Foundation\"]"));
        assert!(diagram.contains("F2[\"Caching\"]"));
        assert!(!diagram.contains("#1001"));
        // Edges derive from the feature deps.
        assert!(diagram.contains("F1 --> F2"));
        assert!(diagram.contains("F1 --> F3"));
        assert!(diagram.contains("classDef needsSpike fill:#ffcdd2"));
        assert!(diagram.contains("class F1 needsDesign"));
        assert!(diagram.contains("class F2 needsSpike"));
        assert!(diagram.contains("class F3 done"));
        assert!(diagram.contains("**Legend**:"));
    }

    #[test]
    fn no_issues_flag_parses() {
        use clap::Parser;
        // Parse through the binary's clap surface to confirm the flag wires
        // up. A minimal standalone parser mirroring the subcommand shape.
        #[derive(Parser)]
        struct Probe {
            #[command(flatten)]
            args: PopulateArgs,
        }
        let p = Probe::parse_from(["x", "ROADMAP.md", "--no-issues"]);
        assert!(p.args.no_issues);
        let p = Probe::parse_from(["x", "ROADMAP.md"]);
        assert!(!p.args.no_issues);
    }

    #[test]
    fn run_issueless_writes_sections_and_makes_no_github_calls() {
        // A non-existent `gh` on PATH would make any GitHub call fail loudly;
        // we instead assert the rendered sections never reference GitHub and
        // that the writer fills both reserved sections. The issueless path
        // never constructs a `Command::new("gh")`, so this run is hermetic.
        let dir = tempdir();
        let path = dir.join("ROADMAP-x.md");
        let original = concat!(
            "---\n",
            "schema: roadmap/v1\n",
            "status: Active\n",
            "---\n\n",
            "# ROADMAP: x\n\n",
            "## Status\n\nActive\n\n",
            "## Features\n\n",
            "### Feature 1: Foundation\n",
            "**Needs:** `needs-design` -- pending\n",
            "**Dependencies:** None\n",
            "**Status:** Not started\n\n",
            "The foundation layer.\n\n",
            "### Feature 2: Caching\n",
            "**Needs:** `needs-spike`\n",
            "**Dependencies:** Feature 1\n",
            "**Status:** Not started\n\n",
            "Adds a cache.\n\n",
            "## Implementation Issues\n\n",
            "<!-- placeholder -->\n\n",
            "## Dependency Graph\n\n",
            "<!-- placeholder -->\n",
        );
        fs::write(&path, original).unwrap();

        let args = PopulateArgs {
            roadmap_path: path.to_string_lossy().to_string(),
            milestone: String::new(),
            milestone_description: String::new(),
            mapping: String::new(),
            output_map: String::new(),
            repo: String::new(),
            dry_run: false,
            no_issues: true,
        };
        let code = run(&args);
        assert_eq!(code, ExitCode::SUCCESS);

        let updated = fs::read_to_string(&path).unwrap();
        // Both reserved sections are filled, feature-keyed, no GitHub refs.
        assert!(updated.contains("| F1 | needs-design | None | needs-design |"));
        assert!(updated.contains("| F2 | needs-spike | F1 | needs-spike |"));
        assert!(updated.contains("graph TD"));
        assert!(updated.contains("F1 --> F2"));
        assert!(!updated.contains("https://github.com"));
        // The other prose is preserved untouched.
        assert!(updated.contains("## Features"));
        assert!(updated.contains("The foundation layer."));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn run_issueless_render_validates_clean() {
        // Render the issueless sections into a full roadmap and run the
        // validator over it; the feature-keyed shape with bare-key deps must
        // produce zero error-level findings (FC05/FC06/FC07 all pass).
        use shirabe_validate::{detect_format, validate_file, Config};

        let dir = tempdir();
        let path = dir.join("ROADMAP-clean.md");
        // A complete roadmap: required frontmatter (theme, scope) and the
        // required sections (Theme, Sequencing Rationale, Progress) so the
        // only thing under test is the issueless-rendered Implementation
        // Issues table and Dependency Graph.
        let original = concat!(
            "---\n",
            "schema: roadmap/v1\n",
            "status: Active\n",
            "theme: |\n  theme.\n",
            "scope: |\n  scope.\n",
            "---\n\n",
            "# ROADMAP: clean\n\n",
            "## Status\n\nActive\n\n",
            "## Theme\n\nThe theme.\n\n",
            "## Features\n\n",
            "### Feature 1: Foundation\n",
            "**Needs:** `needs-design`\n",
            "**Dependencies:** None\n",
            "**Status:** Not started\n\n",
            "The foundation layer.\n\n",
            "### Feature 2: Caching\n",
            "**Needs:** `needs-spike`\n",
            "**Dependencies:** Feature 1\n",
            "**Status:** Not started\n\n",
            "Adds a cache.\n\n",
            "## Implementation Issues\n\n",
            "<!-- placeholder -->\n\n",
            "## Dependency Graph\n\n",
            "<!-- placeholder -->\n\n",
            "## Sequencing Rationale\n\nFoundation precedes caching.\n\n",
            "## Progress\n\nNot started.\n",
        );
        fs::write(&path, original).unwrap();

        let args = PopulateArgs {
            roadmap_path: path.to_string_lossy().to_string(),
            milestone: String::new(),
            milestone_description: String::new(),
            mapping: String::new(),
            output_map: String::new(),
            repo: String::new(),
            dry_run: false,
            no_issues: true,
        };
        assert_eq!(run(&args), ExitCode::SUCCESS);

        let path_str = path.to_string_lossy().to_string();
        let doc = parse_doc(&path_str).expect("re-parse populated roadmap");
        let spec = detect_format("ROADMAP-clean.md").expect("roadmap format detected");
        let cfg = Config {
            custom_statuses: Default::default(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let findings = validate_file(&doc, &spec, &cfg);
        let errors: Vec<_> = findings
            .iter()
            .filter(|e| !shirabe_validate::is_notice(e, shirabe_validate::ReviewPosture::Draft))
            .collect();
        assert!(
            errors.is_empty(),
            "expected clean validation, got: {:?}",
            errors
        );
        let _ = fs::remove_dir_all(&dir);
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
    fn feature_refs_in_handles_plural_comma_and_variants() {
        // issue #232 defect a: the plural `Features N, M` form and `and`
        // variants must each map to the right feature ids. The old
        // `Feature ` byte-scan dropped every one of these silently.
        assert_eq!(feature_refs_in("Features 2, 3"), vec![2, 3]);
        assert_eq!(feature_refs_in("Features 2 and 3"), vec![2, 3]);
        assert_eq!(feature_refs_in("Feature 1, 2 and 3"), vec![1, 2, 3]);
        assert_eq!(feature_refs_in("Feature 1 and Feature 2"), vec![1, 2]);
        assert_eq!(feature_refs_in("features 4, features 5"), vec![4, 5]);
        // De-duplicates while preserving first-seen order.
        assert_eq!(
            feature_refs_in("Feature 2, Feature 2, Feature 1"),
            vec![2, 1]
        );
        // A cross-repo issue number is never mistaken for a feature id.
        assert_eq!(feature_refs_in("owner/repo#7"), Vec::<usize>::new());
    }

    #[test]
    fn concise_description_prefers_functional_outcome_sentence() {
        // issue #232 defect b: the whole prose body must NOT land in the
        // description cell. The Functional outcome sentence is preferred.
        let body = "**Functional outcome:** Users get the base abstractions. \
                    The foundation layer delivers the base abstractions and much \
                    more rambling prose that should not appear in the cell.";
        assert_eq!(
            concise_description(body),
            "Users get the base abstractions."
        );
        // No Functional outcome marker: fall back to the first sentence.
        assert_eq!(
            concise_description("Adds a cache. More detail follows here."),
            "Adds a cache."
        );
        // A single-sentence body with no terminator round-trips whole.
        assert_eq!(concise_description("Just one clause"), "Just one clause");
    }

    #[test]
    fn render_deps_cell_maps_features_to_row_keys_and_keeps_cross_repo() {
        let features = vec![
            make_feature(1, "Foundation layer", "", "None", "Not started", "x."),
            make_feature(2, "Caching layer", "", "Feature 1", "Not started", "x."),
            make_feature(3, "Metrics", "", "Feature 1", "Not started", "x."),
        ];
        // A plural reference resolves to each depended-on feature's label
        // (its row key) so FC06 passes.
        let f4 = make_feature(4, "Dash", "", "Features 2, 3", "Not started", "x.");
        assert_eq!(
            render_deps_cell(&f4.dependencies, &features),
            "Caching layer, Metrics"
        );
        // Cross-repo refs are preserved verbatim alongside resolved labels.
        assert_eq!(
            render_deps_cell("tsukumogami/koto#65, Feature 1", &features),
            "Foundation layer, tsukumogami/koto#65"
        );
        assert_eq!(render_deps_cell("None", &features), "None");
    }

    #[test]
    fn pick_class_is_dependency_aware_and_terminal_aware() {
        // A blocker that has already shipped makes the dependent `ready`,
        // not `blocked` -- matching FC07's expected_class.
        let features = vec![
            make_feature(1, "Done dep", "None", "None", "Done", "x."),
            make_feature(2, "Open dep", "None", "None", "Not started", "x."),
            make_feature(3, "On done", "None", "Feature 1", "Not started", "x."),
            make_feature(4, "On open", "None", "Feature 2", "Not started", "x."),
            make_feature(5, "Cross", "None", "owner/repo#9", "Not started", "x."),
        ];
        assert_eq!(pick_class(&features[0], &features), "done");
        assert_eq!(pick_class(&features[2], &features), "ready");
        assert_eq!(pick_class(&features[3], &features), "blocked");
        // A cross-repo dependency's state is unobservable here -> blocked.
        assert_eq!(pick_class(&features[4], &features), "blocked");
    }

    #[test]
    fn render_table_strikes_through_done_feature_rows() {
        // issue #233: a delivered feature's rows are struck through.
        let features = vec![make_feature(
            1,
            "Shipped",
            "None",
            "None",
            "Done",
            "**Functional outcome:** It shipped. Trailing prose.",
        )];
        let mut map = IssueMap::new();
        map.insert("1".to_string(), 900);
        let table = render_table(&features, &map, "owner/repo", "");
        assert!(table.contains(
            "| ~~Shipped~~ | ~~[#900](https://github.com/owner/repo/issues/900)~~ | ~~None~~ | ~~Done~~ |"
        ));
        assert!(table.contains("| ~~_It shipped._~~ | | | |"));
    }

    #[test]
    fn status_cell_passes_rich_multi_clause_status_through_faithfully() {
        // issue #232 defect c: a rich, multi-clause Status value must reach
        // the Status column verbatim -- never truncated mid-clause.
        let rich = "In progress -- designed, implemented, and in review as a \
                    single PR off main; becomes Done at merge.";
        let f = make_feature(1, "Caching", "`needs-spike`", "None", rich, "x.");
        assert_eq!(pick_status_cell(&f), rich);
        let map = {
            let mut m = IssueMap::new();
            m.insert("1".to_string(), 42);
            m
        };
        let table = render_table(&[f], &map, "owner/repo", "");
        assert!(
            table.contains(rich),
            "rich status must appear verbatim in the table:\n{}",
            table
        );
    }

    #[test]
    fn render_issueless_table_done_feature_has_no_needs_label_and_is_struck() {
        // issue #232 defect c + #233: a Done feature must not carry a
        // `needs-*` label in the Issues column, and its rows are struck.
        let features = vec![make_feature(
            1,
            "Shipped",
            "`needs-design`",
            "None",
            "Done",
            "Body.",
        )];
        let table = render_issueless_table(&features, "");
        assert!(table.contains("| ~~F1~~ | ~~None~~ | ~~None~~ | ~~Done~~ |"));
        assert!(!table.contains("needs-design"));
    }

    #[test]
    fn obtain_mapping_skips_done_and_honors_seed() {
        // issue #233: a seed maps already-delivered work; fresh numbers are
        // synthesized only for non-terminal, non-seeded features. A Done
        // feature absent from the seed gets NO fresh issue.
        let dir = tempdir();
        let seed_path = dir.join("seed.json");
        fs::write(&seed_path, r#"{"2": 500}"#).unwrap();
        let features = vec![
            make_feature(1, "Done thing", "None", "None", "Done", "x."),
            make_feature(2, "Seeded", "None", "None", "In Progress", "x."),
            make_feature(3, "Fresh", "None", "None", "Not started", "x."),
        ];
        let args = PopulateArgs {
            roadmap_path: "ROADMAP.md".to_string(),
            milestone: String::new(),
            milestone_description: String::new(),
            mapping: seed_path.to_string_lossy().to_string(),
            output_map: String::new(),
            repo: String::new(),
            dry_run: true,
            no_issues: false,
        };
        let map = obtain_mapping(&args, &features).unwrap();
        assert_eq!(map.get("1"), None, "Done feature must not be created");
        assert_eq!(map.get("2"), Some(&500), "seed entry preserved");
        assert_eq!(map.get("3"), Some(&1003), "fresh feature synthesized");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn run_issue_creating_render_validates_clean() {
        // Round-trip: feed the issue-creating renderer's own output through
        // the validator. FC05/FC06/FC07/FC08 must all be clean so the
        // renderer cannot drift from its own validator. Covers a plural
        // dependency, a Done feature (struck, no fresh issue), and a
        // feature whose only blocker is Done (ready, not blocked).
        use shirabe_validate::{detect_format, validate_file, Config};

        let dir = tempdir();
        let path = dir.join("ROADMAP-ic.md");
        let original = concat!(
            "---\n",
            "schema: roadmap/v1\n",
            "status: Active\n",
            "theme: |\n  theme.\n",
            "scope: |\n  scope.\n",
            "---\n\n",
            "# ROADMAP: ic\n\n",
            "## Status\n\nActive\n\n",
            "## Theme\n\nThe theme.\n\n",
            "## Features\n\n",
            "### Feature 1: Foundation\n",
            "**Needs:** None\n",
            "**Dependencies:** None\n",
            "**Status:** Done\n\n",
            "**Functional outcome:** Delivers the base. Rambling trailer.\n\n",
            "### Feature 2: Caching\n",
            "**Needs:** `needs-spike`\n",
            "**Dependencies:** Feature 1\n",
            "**Status:** Not started\n\n",
            "**Functional outcome:** Adds a cache. Trailer prose.\n\n",
            "### Feature 3: Metrics\n",
            "**Needs:** None\n",
            "**Dependencies:** Feature 1\n",
            "**Status:** Not started\n\n",
            "**Functional outcome:** Emits metrics. Trailer prose.\n\n",
            "### Feature 4: Dashboard\n",
            "**Needs:** None\n",
            "**Dependencies:** Features 2, 3\n",
            "**Status:** Not started\n\n",
            "**Functional outcome:** Shows a dashboard. Trailer prose.\n\n",
            "## Sequencing Rationale\n\nFoundation first.\n\n",
            "## Progress\n\nFeature 1 done.\n\n",
            "## Implementation Issues\n\n",
            "<!-- placeholder -->\n\n",
            "## Dependency Graph\n\n",
            "<!-- placeholder -->\n",
        );
        fs::write(&path, original).unwrap();

        let args = PopulateArgs {
            roadmap_path: path.to_string_lossy().to_string(),
            milestone: String::new(),
            milestone_description: String::new(),
            mapping: String::new(),
            output_map: String::new(),
            repo: "owner/repo".to_string(),
            dry_run: true,
            no_issues: false,
        };
        assert_eq!(run(&args), ExitCode::SUCCESS);

        let path_str = path.to_string_lossy().to_string();
        let doc = parse_doc(&path_str).expect("re-parse populated roadmap");
        let spec = detect_format("ROADMAP-ic.md").expect("roadmap format detected");
        let cfg = Config {
            custom_statuses: Default::default(),
            visibility: "public".to_string(),
            allow_untracked_acs: false,
        };
        let findings = validate_file(&doc, &spec, &cfg);
        // Assert the table/diagram reconciliation checks are all clean --
        // including the notice-level FC07/FC08 that the round-trip is meant
        // to guard (the error-only filter would miss those).
        let relevant: Vec<_> = findings
            .iter()
            .filter(|e| matches!(e.code.as_str(), "FC05" | "FC06" | "FC07" | "FC08"))
            .collect();
        assert!(
            relevant.is_empty(),
            "expected clean FC05/FC06/FC07/FC08, got: {:?}",
            relevant
        );
        let _ = fs::remove_dir_all(&dir);
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
        assert_eq!(truncate_label("[Foo] `bar`"), "(Foo)  bar ");
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

    fn make_doc_with_sections(
        body: Vec<&str>,
        sections: Vec<(&str, usize)>,
    ) -> shirabe_validate::Doc {
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
