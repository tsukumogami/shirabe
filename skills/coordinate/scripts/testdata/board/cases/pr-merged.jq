# A pull request that isn't open.
# expect: error:pr-state
include "lib";
pr(.state = "MERGED")
