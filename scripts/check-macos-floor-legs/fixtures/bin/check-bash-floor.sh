#!/usr/bin/env bash
# Stand-in for scripts/check-bash-floor.sh in check-macos-floor-legs_test.sh:
# answers the two registry queries the lint makes, for the fixture suites.
case "${1:-}" in
    --suites)
        echo demo
        echo other
        ;;
    --scripts)
        case "${2:-}" in
            demo)
                echo "skills/demo/scripts/one_test.sh"
                echo "skills/demo/scripts/two_test.sh"
                echo "scripts/demo-scan.sh"
                ;;
            other)
                echo "scripts/other-scan.sh"
                ;;
            *)
                echo "check-bash-floor: unknown suite: ${2:-}" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "stand-in check-bash-floor.sh: unexpected $*" >&2
        exit 2
        ;;
esac
