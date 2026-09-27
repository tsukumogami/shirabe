# A change under .github/workflows/ or .github/actions/ is a note, never a reason.
# expect: verified
# check: .notes == [{code: "workflows-changed", paths: [".github/actions/setup/action.yml", ".github/workflows/ci.yml"]}] and .reasons == []
include "lib";
.files += [{filename: ".github/workflows/ci.yml", status: "modified"}, {filename: ".github/actions/setup/action.yml", status: "added"}]
