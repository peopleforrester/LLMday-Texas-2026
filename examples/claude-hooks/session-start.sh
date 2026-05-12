#!/usr/bin/env bash
# ABOUTME: SessionStart hook — detects pending work and uncommitted changes.
# ABOUTME: Outputs a directive to read PROJECT_STATE.md and reconcile before new work.

set -euo pipefail

# ---------------------------------------------------------------------------
# Read hook input (JSON on stdin)
# ---------------------------------------------------------------------------
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Opt-out: .skip-session-resume suppresses the directive for this repo
# ---------------------------------------------------------------------------
if [ -f "$CWD/.skip-session-resume" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Detect pending state
# ---------------------------------------------------------------------------
FINDINGS=()

# Check PROJECT_STATE.md for pending tasks (unchecked items)
if [ -f "$CWD/PROJECT_STATE.md" ]; then
    PENDING_COUNT=$(grep -c '^\- \[ \]' "$CWD/PROJECT_STATE.md" 2>/dev/null || true)
    if [ "$PENDING_COUNT" -gt 0 ]; then
        # Extract the next step line if present
        NEXT_STEP=$(grep -A1 '^\*\*Next step\*\*' "$CWD/PROJECT_STATE.md" 2>/dev/null | tail -1 | sed 's/^- //' || true)
        if [ -n "$NEXT_STEP" ]; then
            FINDINGS+=("PROJECT_STATE.md: $PENDING_COUNT pending tasks. Next: $NEXT_STEP")
        else
            FINDINGS+=("PROJECT_STATE.md: $PENDING_COUNT pending tasks")
        fi
    fi
fi

# Check for Ralph loop state
if [ -f "$CWD/.claude/ralph-loop.local.md" ]; then
    FINDINGS+=("Ralph loop state detected (.claude/ralph-loop.local.md)")
fi

# Check for tasks.yaml state
if [ -f "$CWD/tasks.yaml" ] && command -v yq >/dev/null 2>&1; then
    INTERRUPTED_COUNT=$(yq '[.tasks[] | select(.status == "interrupted")] | length' "$CWD/tasks.yaml" 2>/dev/null || echo "0")
    READY_COUNT=$(yq '[.tasks[] | select(.status == "ready")] | length' "$CWD/tasks.yaml" 2>/dev/null || echo "0")
    CLAIMED_COUNT=$(yq '[.tasks[] | select(.status == "claimed")] | length' "$CWD/tasks.yaml" 2>/dev/null || echo "0")
    if [ "$INTERRUPTED_COUNT" -gt 0 ]; then
        INTERRUPTED_TITLES=$(yq '.tasks[] | select(.status == "interrupted") | .id + " — " + .title' "$CWD/tasks.yaml" 2>/dev/null || true)
        FINDINGS+=("tasks.yaml: $INTERRUPTED_COUNT interrupted task(s): $INTERRUPTED_TITLES")
    fi
    if [ "$CLAIMED_COUNT" -gt 0 ]; then
        FINDINGS+=("tasks.yaml: $CLAIMED_COUNT task(s) still claimed from previous session")
    fi
    if [ "$READY_COUNT" -gt 0 ]; then
        FINDINGS+=("tasks.yaml: $READY_COUNT task(s) ready to work on")
    fi
fi

# Check for uncommitted changes
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
    DIRTY_COUNT=$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY_COUNT" -gt 0 ]; then
        FINDINGS+=("$DIRTY_COUNT uncommitted/untracked files")
    fi
fi

# ---------------------------------------------------------------------------
# If no state found, exit silently
# ---------------------------------------------------------------------------
if [ ${#FINDINGS[@]} -eq 0 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Build the directive message
# ---------------------------------------------------------------------------
SUMMARY="Session state detected:"
for finding in "${FINDINGS[@]}"; do
    SUMMARY="$SUMMARY\n  - $finding"
done

DIRECTIVE="$SUMMARY\n\nRead PROJECT_STATE.md NOW and reconcile before starting new work. Run /continue if resuming."

# Output as plain text (SessionStart hooks add this as context)
echo -e "$DIRECTIVE"

exit 0
