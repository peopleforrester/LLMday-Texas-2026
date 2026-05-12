#!/bin/bash
# ABOUTME: Post-edit validation hook for Claude Code.
# ABOUTME: Validates Python syntax, formatting, indentation, line-length, and naming conventions via ruff. YAML via yamllint.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Exit silently if no file path
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

case "$FILE_PATH" in
    *.py)
        # Syntax check (fast, catches parse errors)
        python3 -m py_compile "$FILE_PATH" 2>&1

        # Style checks: indentation (4-space), line length (100), naming conventions
        # E111: indentation not a multiple of 4
        # W191: indentation contains tabs
        # E501: line too long (>100 chars)
        # N801: class names should use CapWords
        # N802: function names should be lowercase
        # N803: argument names should be lowercase
        # N806: variable in function should be lowercase
        if command -v ruff &> /dev/null; then
            ruff check --preview --select E111,W191,E501,N801,N802,N803,N806 \
                --line-length 100 "$FILE_PATH" 2>&1
        fi
        ;;
    *.yaml|*.yml)
        if command -v yamllint &> /dev/null; then
            yamllint -d relaxed "$FILE_PATH" 2>&1
        fi
        ;;
esac
