#!/usr/bin/env bash
# ABOUTME: PostCompact hook — re-anchors context after compaction to prevent instruction amnesia.
# ABOUTME: Reads CLAUDE.md, PROJECT_STATE.md, git state, and outputs orientation block.

set -euo pipefail

# Find repo root (if in a git repo)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$REPO_ROOT" ]; then
    echo "Not in a git repository — skipping re-anchor." >&2
    exit 0
fi

REPO_NAME=$(basename "$REPO_ROOT")
BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "detached")
STATUS=$(git -C "$REPO_ROOT" status --short 2>/dev/null | head -10)
RECENT=$(git -C "$REPO_ROOT" log --oneline -3 2>/dev/null || echo "no commits")

# Check for project state
STATE_FILE="$REPO_ROOT/PROJECT_STATE.md"
HAS_STATE="no"
NEXT_STEP=""
if [ -f "$STATE_FILE" ]; then
    HAS_STATE="yes"
    NEXT_STEP=$(grep -A1 "Next step" "$STATE_FILE" 2>/dev/null | tail -1 | sed 's/^- //' || echo "")
fi

# Check for execution state (plan-execute)
EXEC_STATE=""
if [ -f "$REPO_ROOT/_execution-state.md" ]; then
    EXEC_STATE="Active execution state found — read _execution-state.md"
fi

# Check for active task in tasks.yaml (GUPP recovery)
ACTIVE_TASK=""
if [ -f "$REPO_ROOT/tasks.yaml" ] && command -v yq >/dev/null 2>&1; then
    CLAIMED=$(yq '.tasks[] | select(.status == "claimed") | .id + " — " + .title' "$REPO_ROOT/tasks.yaml" 2>/dev/null || true)
    INTERRUPTED=$(yq '.tasks[] | select(.status == "interrupted") | .id + " — " + .title' "$REPO_ROOT/tasks.yaml" 2>/dev/null || true)
    if [ -n "$CLAIMED" ]; then
        ACTIVE_TASK="ACTIVE TASK (resume): $CLAIMED"
    elif [ -n "$INTERRUPTED" ]; then
        ACTIVE_TASK="INTERRUPTED TASK (check before resuming): $INTERRUPTED"
    fi
fi

# Check for CLAUDE.md
HAS_CLAUDE_MD="no"
[ -f "$REPO_ROOT/CLAUDE.md" ] && HAS_CLAUDE_MD="yes"
[ -f "$REPO_ROOT/claude-config/CLAUDE.md" ] && HAS_CLAUDE_MD="yes"

# Output orientation block
cat >&2 <<EOF
--- POST-COMPACTION RE-ANCHOR ---
Repo: $REPO_NAME | Branch: $BRANCH | CLAUDE.md: $HAS_CLAUDE_MD | PROJECT_STATE.md: $HAS_STATE
Recent commits: $RECENT
$([ -n "$STATUS" ] && echo "Dirty files: $STATUS" || echo "Working tree clean")
$([ -n "$NEXT_STEP" ] && echo "Next step: $NEXT_STEP")
$([ -n "$EXEC_STATE" ] && echo "$EXEC_STATE")
$([ -n "$ACTIVE_TASK" ] && echo "$ACTIVE_TASK")
ACTION: Re-read CLAUDE.md and PROJECT_STATE.md now to restore full context.$([ -n "$ACTIVE_TASK" ] && echo " Check tasks.yaml for current task state.")
---
EOF

exit 0
