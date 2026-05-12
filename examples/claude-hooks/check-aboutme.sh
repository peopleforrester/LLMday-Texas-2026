#!/bin/bash
# ABOUTME: PostToolUse hook that warns when a .py file is missing the ABOUTME header.
# ABOUTME: Runs after Write/Edit operations; warns but does not block.
#
# HOW THIS HOOK WORKS:
# =====================
# Claude Code runs this script AFTER every Write or Edit tool call completes.
# It receives JSON on stdin describing what just happened:
#   {"tool_name": "Write", "tool_input": {"file_path": "/path/to/file.py"}}
#
# The hook checks if the written/edited file is a .py file and whether it
# has the required ABOUTME header comment in the first 3 lines. If missing,
# it prints a warning. It NEVER blocks (always exits 0) because missing
# ABOUTME is a style issue, not a correctness issue.
#
# EXIT CODES:
#   0 = always (PostToolUse hooks can only warn, not block)
#
# REGISTERED IN: ~/.claude/settings.json under hooks.PostToolUse
# MATCHER: "Edit|Write" (only runs for these two tools)

# --- Step 1: Read the JSON input from Claude Code ---
# Claude Code pipes tool call details to stdin as JSON
INPUT=$(cat)

# --- Step 2: Extract which tool was used and what file was affected ---
# jq -r extracts raw strings; '// empty' returns empty string if field is missing
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# --- Step 3: Early exit if this isn't a Write/Edit on a .py file ---
# The matcher in settings.json should filter to Edit|Write, but we double-check
case "$TOOL_NAME" in
    Write|Edit) ;;        # These are the tools we care about - continue
    *) exit 0 ;;          # Anything else - silently allow
esac

# Only check Python files; other file types don't need ABOUTME headers
case "$FILE_PATH" in
    *.py) ;;              # Python file - continue checking
    *) exit 0 ;;          # Not Python - silently allow
esac

# --- Step 4: Handle edge cases ---
# File might not exist if it was deleted or if the path is invalid
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# __init__.py files are often empty or contain only __all__ declarations.
# Requiring ABOUTME headers in them would be noisy and unhelpful.
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" = "__init__.py" ]; then
    exit 0
fi

# --- Step 5: Check for ABOUTME header ---
# We look in the first 3 lines because the file might start with a shebang
# line (#!/usr/bin/env python3) before the ABOUTME comments.
# The pattern "^# ABOUTME:" matches lines starting with a comment + ABOUTME.
FOUND=$(head -n 3 "$FILE_PATH" | grep -c "^# ABOUTME:")

# If no ABOUTME line found, print a warning to stdout.
# Claude Code will display this warning to the user.
if [ "$FOUND" -lt 1 ]; then
    echo "WARNING: $FILE_PATH is missing ABOUTME header comment in the first 3 lines."
    echo "Expected format:"
    echo '  # ABOUTME: Brief description of this file'"'"'s purpose'
    echo '  # ABOUTME: What it does or provides'
    # Exit 0 = warn only, do not block the operation
    exit 0
fi

# File has ABOUTME header - all good, exit silently
exit 0
