#!/usr/bin/env bash
# legacy-import_test.sh -- runs the legacy importer's suite, which lives with
# the importer in ../legacy-import/, so run-tests.sh, check-skill.sh and the
# bash-floor leg run it with this skill's other suites.
# Usage: bash skills/coordinate/scripts/legacy-import_test.sh
exec bash "$(cd "$(dirname "$0")/../legacy-import" && pwd)/legacy-import_test.sh"
