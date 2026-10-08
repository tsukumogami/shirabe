#!/usr/bin/env bash
# greet: print a greeting. --name <n> greets someone by name.
name="world"
if [ "${1:-}" = "--name" ] && [ -n "${2:-}" ]; then
    name="$2"
fi
echo "hello, $name"
