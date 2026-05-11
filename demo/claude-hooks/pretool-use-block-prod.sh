#!/usr/bin/env bash
# ABOUTME: Layer 1 of the demo's three-layer pipeline guardrails — PreToolUse hook.
# ABOUTME: Denies tool calls that touch production directly. Reads tool-call JSON on stdin.

set -euo pipefail

# Read tool-call JSON payload from stdin
INPUT=$(cat)

# Extract tool name and command. Claude Code's PreToolUse contract sends
# {"tool_name": "Bash", "tool_input": {"command": "..."}}. Older shapes may
# use top-level .tool_input as a string. Handle both.
tool_name=$(echo "$INPUT" | jq -r '.tool_name // ""')
command=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input // ""')

# Pattern 1: direct kubectl against production
if echo "$command" | grep -qE '(\bkubectl\b[^|;&]*(-n[[:space:]]+production|--namespace[[:space:]=]+production|[[:space:]]production\b))'; then
  cat >&2 <<EOF
PRETOOLUSE_HOOK_DENY: Direct kubectl operations against the production namespace
are not allowed from agent sessions.

Tool blocked:  ${tool_name:-Bash}
Pattern hit:   kubectl against production namespace
Path forward:  stage the change in staging, sign the artifact, and let the
               ArgoCD/MLOps pipeline promote it. Open a PR through gitops-prod
               for human review.
EOF
  exit 2
fi

# Pattern 2: direct registry push
if echo "$command" | grep -qE '(docker[[:space:]]+push|crane[[:space:]]+push|skopeo[[:space:]]+copy.*://|podman[[:space:]]+push)'; then
  cat >&2 <<'EOF'
PRETOOLUSE_HOOK_DENY: Direct registry pushes are not allowed from agent sessions.
Build artifacts must be signed and promoted via the supply-chain pipeline.
EOF
  exit 2
fi

# Pattern 3: direct file edit on infrastructure/production
if echo "$command" | grep -qE '(infrastructure/production/|infrastructure\.production)'; then
  cat >&2 <<'EOF'
PRETOOLUSE_HOOK_DENY: Edits under infrastructure/production/ require a PR from a
human reviewer in the mlops-platform group. Agent commits are not permitted on
this path.
EOF
  exit 2
fi

# Safe by default
exit 0
