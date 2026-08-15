#!/usr/bin/env bash
# Reproduces what the live execute.md site actually captures when
# `koto context get` fails. Probe only.
PLAN_SLUG=demo
SETTLED_BRANCH=$(koto context get no-such-session-xyz settled_branch 2>/dev/null || echo "impl/$PLAN_SLUG")
printf 'RAW CAPTURE >>>%s<<<\n' "$SETTLED_BRANCH"
case "$SETTLED_BRANCH" in
  *[!A-Za-z0-9._/-]*|"") printf 'SANITIZER FIRED -> reset to impl/%s\n' "$PLAN_SLUG" ;;
  *) printf 'SANITIZER DID NOT FIRE -> value used as-is\n' ;;
esac
