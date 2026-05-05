<!-- decision:start id="go-frontmatter-extraction" status="assumed" -->
### Decision: Go approach for YAML frontmatter and Markdown heading extraction

**Context**

The shirabe Go CLI validates Markdown doc files across five formats (Design, PRD,
VISION, Roadmap, Plan). Each file has YAML frontmatter between `---` delimiters and a
body with `## `-level section headings. The CLI checks required frontmatter fields,
valid status values, schema version, upstream path presence, and required section
names.

What makes this technically constrained is the GitHub Actions annotation requirement.
GHA inline PR annotations use `::error file=<path>,line=<N>::`, which means the
validator must return not just whether a field is missing or invalid, but exactly which
line that field key appears on. A frontmatter parser that returns `map[string]string`
with no position data cannot fulfill this requirement without additional passes.

The implementation also runs on files modified in a PR (typically 1–10 files), so
performance is not a factor. Correctness, error safety, and maintainability dominate.

**Assumptions**

- The shirabe Go module is new; no existing go.mod constrains the dependency choice.
  If yaml.v3 is already present, this decision is reinforced. If another YAML library
  is already imported, that should be factored in.
- Shirabe's doc format frontmatter uses single-line scalar YAML values only — no
  nested mappings, no block scalars. This is consistent with all five existing formats.
  If formats evolve to use nested YAML, yaml.v3 handles it correctly; the naive scanner
  would break.
- Section headings requiring validation are H2 (`## `) only. If H1 or H3 headings
  require checking, the same line scan handles them with a trivially modified prefix
  check.

**Chosen: Manual byte scan + yaml.v3**

Scan the file for opening and closing `---` delimiters to identify the frontmatter
block, recording the absolute start line number. Pass the extracted frontmatter string
to `gopkg.in/yaml.v3` decoded into a `yaml.Node` tree. Each node in the tree carries
`Line` and `Column` fields relative to the start of the input string; adding the
frontmatter block offset yields absolute file line numbers for any key. For section
headings, scan the body line-by-line with a `strings.HasPrefix(line, "## ")` check
and a running line counter — this gives accurate line numbers for each heading with
no additional dependencies.

**Rationale**

yaml.v3's `yaml.Node` type is the only approach in the evaluated set that provides
accurate key-level line numbers for YAML content without requiring additional code.
The other library-based options (goldmark-meta, adrg/frontmatter) return frontmatter
as position-less maps; using them for line number tracking would require extracting the
frontmatter separately and doing a manual scan anyway — adding a dependency without
reducing the custom code. The pure-stdlib line scanner avoids dependencies but parses
YAML with string splitting, which is fragile on quoted strings, values containing
colons, and block scalars. yaml.v3 is the canonical Go YAML library: small (~100KB
binary contribution), well-maintained, and widely used. The `yaml.Node` API requires
understanding one additional type over map-based decoding, but the trade-off is
correct line numbers and correct YAML semantics — both required for this tool.

**Alternatives Considered**

- **goldmark + goldmark-meta**: A full CommonMark parser with a frontmatter extension.
  goldmark provides AST-level line numbers for Heading nodes, but goldmark-meta returns
  frontmatter as a position-less `map[string]interface{}`. Getting line numbers for
  frontmatter keys still requires yaml.v3 or a manual scan. This means two external
  dependencies (goldmark + yaml.v3) and significant binary size for a capability
  (H2 prefix detection) that strings.HasPrefix handles in two lines. Rejected because
  it doesn't solve the frontmatter line number problem and adds disproportionate weight.

- **adrg/frontmatter library**: A small library that splits frontmatter from body but
  returns no position information. Section headings still need a separate scan. Line
  numbers for frontmatter keys require custom tracking on top. Adds a dependency
  without simplifying the problem. Rejected because it covers one sub-task (delimiter
  detection) while yaml.v3 covers both that sub-task (via the delimiter scan feeding
  it) and the line number requirement.

- **bufio.Scanner line-by-line (no YAML library)**: Pure stdlib; line numbers are
  naturally accurate. Works for the simple scalar frontmatter values shirabe currently
  uses. Rejected because it parses YAML with string splitting on `": "`, which fails
  silently on quoted values containing colons, multi-line block scalars, and other
  valid YAML. This creates a maintenance trap: future format changes, or docs authored
  by users with YAML habits like quoted strings, would produce wrong results without
  any error. The correctness risk outweighs the benefit of zero dependencies.

**Consequences**

- go.mod gains one dependency: `gopkg.in/yaml.v3`. This is the canonical Go YAML
  library and would likely appear in go.mod regardless of this decision (upstream
  references in VISION/Plan formats need checking too).
- Frontmatter parsing code is ~50 lines: a delimiter scan that finds and extracts the
  frontmatter block, plus a yaml.Node tree traversal that maps field names to values
  and line numbers.
- Body heading extraction is trivial: a `bufio.Scanner` loop over the body with
  `strings.HasPrefix` and a line counter. No additional library needed.
- Malformed or absent frontmatter: the delimiter scan returns a structured error before
  any YAML call; yaml.Unmarshal returns an error (not a panic) on invalid YAML. Both
  paths are straightforward to test.
- Tests use standard `go test` with table-driven cases on inline document strings.
  No external test infrastructure or temp file setup required.
<!-- decision:end -->
