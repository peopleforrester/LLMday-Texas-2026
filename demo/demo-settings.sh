#!/usr/bin/env bash
# ABOUTME: Walk through the three enforcement files behind the demo.
# ABOUTME: For each beat, show the file path and the actual rule content.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEMO_ROOT

source "$DEMO_ROOT/lib/colors.sh"
source "$DEMO_ROOT/lib/say.sh"
source "$DEMO_ROOT/lib/pause.sh"

# ============================================================
# Helpers
# ============================================================
show_file() {
  local beat="$1"
  local title="$2"
  local path="$3"
  local oneliner="$4"

  clear
  echo -e "${DIM}╭─────────────────────────────────────────────────────────────────╮${RESET}"
  printf "${DIM}│  ${BOLD}${WHITE}%-61s${RESET}${DIM}    │${RESET}\n" "$beat — $title"
  echo -e "${DIM}╰─────────────────────────────────────────────────────────────────╯${RESET}"
  echo ""
  echo -e "${YELLOW}Where this lives:${RESET} ${path/$DEMO_ROOT/\$DEMO_ROOT}"
  echo -e "${YELLOW}What it enforces:${RESET} ${oneliner}"
  echo ""
  echo -e "${DIM}─── file content ─────────────────────────────────────────────────${RESET}"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo -e "${RED}ERROR: $path not found${RESET}" >&2
  fi
  echo -e "${DIM}─── end of file ──────────────────────────────────────────────────${RESET}"
  echo ""
}

# ============================================================
# Intro
# ============================================================
clear
echo -e "${DIM}╭─────────────────────────────────────────────────────────────────╮${RESET}"
echo -e "${DIM}│  ${BOLD}${WHITE}Three layers — the actual rule, setting, manifest${RESET}${DIM}             │${RESET}"
echo -e "${DIM}│  ${CYAN}Each beat shown as its enforcement file on disk${RESET}${DIM}                │${RESET}"
echo -e "${DIM}╰─────────────────────────────────────────────────────────────────╯${RESET}"
echo ""
echo "  Beat 1 — Claude Code PreToolUse hook (bash, on this host)"
echo "  Beat 2 — Git pre-commit hook (bash, inside the IaC repo)"
echo "  Beat 3 — Kubernetes ValidatingAdmissionPolicy (YAML, in the cluster)"
echo ""
pause "press SPACE to see Beat 1's hook"

# ============================================================
# Beat 1 — PreToolUse hook
# ============================================================
show_file \
  "Beat 1" \
  "Claude Code PreToolUse hook" \
  "$DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh" \
  "Reads tool-call JSON on stdin. Exits 2 with stderr deny on three patterns: kubectl WRITE verbs against the production namespace; direct registry push; direct edits to infrastructure/production/. Registered to Claude Code via .claude/settings.json (matcher: Bash)."
pause "press SPACE to see Beat 2's hook"

# ============================================================
# Beat 2 — Git pre-commit hook
# ============================================================
show_file \
  "Beat 2" \
  "Git pre-commit hook (in the IaC repo)" \
  "$DEMO_ROOT/iac-repo-template/hooks/pre-commit" \
  "Two checks. (1) Non-human committer email patterns: claude-agent, anthropic.local, @bot, agent@, noreply@. (2) Staged files under infrastructure/production/. Either check failing exits 1 with GIT_HOOK_DENY. setup.sh installs this hook into .git/hooks/ AND sets core.hooksPath so the host's global hooksPath cannot bypass it."
pause "press SPACE to see Beat 3's policy"

# ============================================================
# Beat 3 — VAP
# ============================================================
show_file \
  "Beat 3" \
  "Kubernetes ValidatingAdmissionPolicy (in the cluster)" \
  "$DEMO_ROOT/gitops/manifests/vap/vap.yaml" \
  "Native admission policy (GA in K8s 1.30+). CEL expression, no webhook, no controller. matchConditions narrow to (a) writes to the production namespace AND (b) the claude-agent ServiceAccount specifically. validations.expression is 'false' — when both matchConditions hit, the request is denied. Bound to the production namespace via the matching ValidatingAdmissionPolicyBinding."

# ============================================================
# Close
# ============================================================
echo ""
echo -e "${BOLD}Three files. Three layers. Same agent gets caught three times.${RESET}"
echo ""
echo -e "${DIM}  Beat 1 file:  $DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh${RESET}"
echo -e "${DIM}  Beat 2 file:  $DEMO_ROOT/iac-repo-template/hooks/pre-commit${RESET}"
echo -e "${DIM}  Beat 3 file:  $DEMO_ROOT/gitops/manifests/vap/vap.yaml${RESET}"
echo ""
pause "press SPACE to exit"
