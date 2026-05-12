#!/bin/bash
# ABOUTME: PreToolUse hook that blocks git commits containing AI/Claude references.
# ABOUTME: Enforces professional commit messages by scanning for attribution patterns.
#
# HOW THIS HOOK WORKS:
# =====================
# Claude Code runs this script BEFORE every Bash tool call executes.
# It receives JSON on stdin describing what Claude wants to do:
#   {"tool_name": "Bash", "tool_input": {"command": "git commit -m 'message'"}}
#
# The hook extracts ONLY the commit message (from -m, heredoc, or --message)
# and checks for references to Claude, Claude Code, AI, Anthropic, or similar
# attribution. If found, it blocks the commit by exiting with code 2 and
# suggests a corrected message. File paths in the command are not scanned.
#
# EXIT CODES:
#   0 = allow the command to proceed
#   2 = BLOCK the command (Claude sees the error message and cannot execute it)
#
# WHAT IT CATCHES:
#   - "Claude Code", "Claude", "Anthropic" (case-insensitive)
#   - "Generated with", "Co-Authored-By.*Claude", "AI assistant"
#   - "LLM", "language model" in commit context
#
# REGISTERED IN: ~/.claude/settings.json under hooks.PreToolUse
# MATCHER: "Bash" (only runs for Bash tool calls)

# --- Step 1: Read the JSON input from Claude Code ---
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# --- Step 2: Only process Bash tool calls ---
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# --- Step 3: Extract the command ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# --- Step 4: Only check git commit commands ---
# Match "git commit" anywhere in the command (handles chained commands with &&)
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0  # Not a git commit - allow it
fi

# --- Step 5: Extract the commit message, not the full command ---
# The full command may contain file paths (e.g., git add claude-config/)
# that would false-positive on pattern matching. Extract only the message.
MSG=""

# Heredoc style: git commit -m "$(cat <<'EOF' ... EOF)"
if echo "$COMMAND" | grep -qE "<<'?\"?EOF"; then
    MSG=$(echo "$COMMAND" | awk "/<<['\"]?EOF['\"]?/{found=1; next} /^[[:space:]]*EOF/{found=0} found{print}")
fi

# -m "message" or -m 'message' style (if heredoc extraction found nothing)
if [ -z "$MSG" ]; then
    MSG=$(echo "$COMMAND" | grep -oP "git\s+commit\s+.*?-m\s+['\"]?\K[^'\"]*" | head -1)
fi

# --message="message" style
if [ -z "$MSG" ]; then
    MSG=$(echo "$COMMAND" | grep -oP -- "--message=['\"]?\K[^'\"]*" | head -1)
fi

# If extraction failed entirely, skip check rather than false-positive
if [ -z "$MSG" ]; then
    exit 0
fi

# --- Step 6: Check for AI/Claude references in the commit message ---
# Case-insensitive patterns that indicate AI attribution
AI_PATTERNS=(
    'claude[[:space:]]*code'
    '\bclaude\b'
    '\banthropic\b'
    'generated[[:space:]]+with'
    'co-authored-by.*claude'
    'co-authored-by.*anthropic'
    '\bai[[:space:]]+assistant\b'
    '\bai-generated\b'
    '\bllm\b'
    'language[[:space:]]+model'
)

for pattern in "${AI_PATTERNS[@]}"; do
    if echo "$MSG" | grep -qiE "$pattern"; then
        MATCHED=$(echo "$MSG" | grep -oiE "$pattern" | head -1)
        echo "BLOCKED: Commit message contains AI/Claude reference: \"$MATCHED\"" >&2
        echo "" >&2
        echo "Rule: NEVER include references to Claude Code, Claude, or AI in commit messages." >&2
        echo "Commit messages should be professional and describe the technical changes only." >&2
        echo "" >&2
        echo "Please rewrite the commit message without AI attribution." >&2
        exit 2  # EXIT 2 = block the command
    fi
done

# Commit message is clean - allow it
exit 0
