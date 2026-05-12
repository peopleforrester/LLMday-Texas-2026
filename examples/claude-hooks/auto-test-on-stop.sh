#!/usr/bin/env bash
# ABOUTME: Runs project tests after Claude finishes a response, if a test runner is detected.
# ABOUTME: Non-blocking — reports results but never fails the hook (exit 0 always).

set -uo pipefail

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "end_turn"')

# Only run on normal completion, not on interrupts or errors
if [[ "$STOP_REASON" != "end_turn" ]]; then
    exit 0
fi

# Detect project type and run appropriate tests quietly
if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    if command -v pytest &>/dev/null && [[ -d "tests" ]]; then
        RESULT=$(pytest tests/ --ignore=tests/e2e/ -q --tb=no --no-header 2>&1 | tail -1)
        echo "Tests: $RESULT"
    fi
elif [[ -f "package.json" ]]; then
    if grep -q '"test"' package.json 2>/dev/null; then
        RESULT=$(npm test --silent 2>&1 | tail -1)
        echo "Tests: $RESULT"
    fi
elif [[ -f "Cargo.toml" ]]; then
    if command -v cargo &>/dev/null; then
        RESULT=$(cargo test --quiet 2>&1 | tail -1)
        echo "Tests: $RESULT"
    fi
fi

# Never block — this is informational only
exit 0
