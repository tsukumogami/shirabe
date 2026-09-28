# lib.jq -- builders for the board fixtures. Every case under cases/ starts
# from base.jq's passing board and changes one thing, the way merge-verdict's
# cases start from one mergeable fixture.
def H: "0123456789abcdef0123456789abcdef01234567";
def OTHER: "fedcba9876543210fedcba9876543210fedcba98";
def MOVED: "1111111111111111111111111111111111111111";
def run(id; status; conclusion; attempt):
  {id: id, name: "wf-\(id)", event: "pull_request", head_branch: "feat/x", head_sha: H,
   status: status, conclusion: conclusion, run_attempt: attempt};
def step(c): {name: "step", conclusion: c};
def job(id; name; conclusion; runner; steps):
  {id: id, name: name, status: "completed", conclusion: conclusion, run_attempt: 1,
   runner_name: runner, runner_id: (if runner == null then null else 1 end), steps: steps};
def skipped_job(id; name): job(id; name; "skipped"; null; []);
def runs(list): {total_count: (list | length), workflow_runs: list};
def jobs(list): {total_count: (list | length), jobs: list};
def check(name; status; conclusion; req):
  {__typename: "CheckRun", name: name, status: status, conclusion: conclusion, isRequired: req,
   checkSuite: {app: {databaseId: 15368}}};
def status_ctx(name; state; req): {__typename: "StatusContext", context: name, state: state, isRequired: req};
def snapshot(ms; contexts):
  {data: {repository: {pullRequest: {state: "OPEN", isDraft: false, headRefOid: H, headRefName: "feat/x",
    headRepository: {nameWithOwner: "acme/widgets"}, baseRefName: "main", mergeStateStatus: ms,
    commits: {nodes: [{commit: {oid: H, statusCheckRollup: {contexts: {totalCount: (contexts | length),
      pageInfo: {hasNextPage: false, endCursor: null}, nodes: contexts}}}}]}}}}};
# ctx(f): apply f to the snapshot's context list, keeping totalCount honest.
def ctx(f): .snapshot.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts
  |= (.nodes |= f | .totalCount = (.nodes | length));
def pr(f): .snapshot.data.repository.pullRequest |= f;
def protection(contexts): {protected: true, protection: {enabled: true, required_status_checks:
  {enforcement_level: "non_admins", contexts: contexts, checks: [contexts[] | {context: ., app_id: null}]}}};
# The token can't read checks: GitHub refuses the snapshot's rollup query the
# way gh reports a GraphQL refusal (no HTTP status).
def refuse_rollup: .__rc.rollup = 1 | .__err.rollup = "gh: Resource not accessible by personal access token";
# The commit's check runs refused, as REST reports it.
def refuse_checkruns: .__rc.checkruns = 1 | .__err.checkruns = "gh: Resource not accessible by personal access token (HTTP 403)";
