#!/usr/bin/env bash
# ABOUTME: Layer 1 of the demo's three-layer pipeline guardrails — PreToolUse hook.
# ABOUTME: Denies WRITE kubectl ops against production, registry pushes, and direct prod file edits.

set -euo pipefail

# Read tool-call JSON payload from stdin
INPUT=$(cat)

tool_name=$(echo "$INPUT" | jq -r '.tool_name // ""')
command=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input // ""')

# Verbs that read state in kubectl. Anything else against production is a write.
READ_VERBS_RE='\b(get|list|watch|describe|explain|auth|version|diff|wait|api-resources|api-versions|top|logs|port-forward|kustomize|cluster-info|config)\b'

# Pattern 1: kubectl + production + NOT a pure read verb = WRITE against production
if echo "$command" | grep -qE '\bkubectl\b' \
   && echo "$command" | grep -qE '(-n[[:space:]]+production|--namespace[[:space:]=]+production|[[:space:]]production\b)' \
   && ! echo "$command" | grep -qE "$READ_VERBS_RE"; then
  cat >&2 <<EOF
PRETOOLUSE_HOOK_DENY: Direct kubectl WRITE against the production namespace
is not allowed from agent sessions.

Tool blocked:  ${tool_name:-Bash}
Pattern hit:   kubectl write op against production
Path forward:  stage the change in staging, sign the artifact, and let the
               ArgoCD/MLOps pipeline promote it. Open a PR through gitops-prod
               for human review.
EOF
  exit 2
fi

# Pattern 2: direct registry push
if echo "$command" | grep -qE '(docker[[:space:]]+push|crane[[:space:]]+push|skopeo[[:space:]]+copy.*://|podman[[:space:]]+push)'; then
  cat >&2 <<EOF
PRETOOLUSE_HOOK_DENY: Direct registry pushes are not allowed from agent sessions.
Build artifacts must be signed and promoted via the supply-chain pipeline.
EOF
  exit 2
fi

# Pattern 3: direct file edit on infrastructure/production
if echo "$command" | grep -qE '(infrastructure/production/|infrastructure\.production)'; then
  cat >&2 <<EOF
PRETOOLUSE_HOOK_DENY: Edits under infrastructure/production/ require a PR from a
human reviewer in the mlops-platform group. Agent commits are not permitted on
this path.
EOF
  exit 2
fi

# Safe by default
exit 0
