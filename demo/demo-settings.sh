#!/usr/bin/env bash
# ABOUTME: Walk through the three enforcement files behind the demo.
# ABOUTME: For each beat, show the file path and the actual rule content.

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEMO_ROOT

source "$DEMO_ROOT/lib/colors.sh"
source "$DEMO_ROOT/lib/say.sh"

# Hands-free pacing: auto-advance after a few seconds, or skip ahead
# with any keypress (NOT specifically SPACE — any key, so the one
# hand not holding the mic can mash without aiming).
SECTION_PAUSE="${SECTION_PAUSE:-25}"
auto_pause() {
  local seconds="${1:-$SECTION_PAUSE}"
  echo ""
  echo -e "${DIM}[advancing in ${seconds}s — or tap any key to skip]${RESET}"
  if [[ -r /dev/tty ]]; then
    read -t "$seconds" -rsn1 < /dev/tty 2>/dev/null || true
  else
    sleep "$seconds"
  fi
}

# ============================================================
# Helpers
# ============================================================
# Scroll speed: seconds per line as the file content prints.
# 0.15s × ~60 lines ≈ 9 seconds of slow scroll per file.
# Tune with SETTINGS_LINE_DELAY=0.30 (slower) or 0.05 (faster).
LINE_DELAY="${SETTINGS_LINE_DELAY:-0.15}"

# Highlight deny keywords red and key tool names blue, in-place per line.
_highlight_line() {
  local line="$1"
  # Deny / forbid / failure terms → bold bright red
  line=$(printf '%s' "$line" | sed -E "s/(DENY|denied|Forbidden|HOOK_DENY|deny:|Sigkill|FailedCreate|exit 1|exit 2)/$(printf '\033[1;91m')\1$(printf '\033[0m')/gI")
  # Tool / command names as standalone words → bold bright blue
  line=$(printf '%s' "$line" | sed -E "s/\\b(kubectl|git|grep|sed|jq|chmod|mkdir|bash)\\b/$(printf '\033[1;94m')\1$(printf '\033[0m')/g")
  # YAML keys (lines like "  name:" or "  expression:") → bold cyan on the key only
  line=$(printf '%s' "$line" | sed -E "s/^([[:space:]]*)([a-zA-Z][a-zA-Z0-9_-]*:)/\1$(printf '\033[1;96m')\2$(printf '\033[0m')/")
  printf '%s\n' "$line"
}

# Print a file line by line with highlighting + per-line delay.
slow_print_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo -e "${RED}ERROR: $path not found${RESET}" >&2
    return 1
  fi
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    # Print line number (gray) + highlighted content
    printf "${DIM}%3d${RESET}  " "$line_no"
    _highlight_line "$line"
    sleep "$LINE_DELAY"
  done < "$path"
}

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
  slow_print_file "$path"
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
auto_pause 6

# ============================================================
# Beat 1 — PreToolUse hook
# ============================================================
show_file \
  "Beat 1" \
  "Claude Code PreToolUse hook" \
  "$DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh" \
  "Reads tool-call JSON on stdin. Exits 2 with stderr deny on three patterns: kubectl WRITE verbs against the production namespace; direct registry push; direct edits to infrastructure/production/. Registered to Claude Code via .claude/settings.json (matcher: Bash)."
auto_pause

# ============================================================
# Beat 2 — Git pre-commit hook
# ============================================================
show_file \
  "Beat 2" \
  "Git pre-commit hook (in the IaC repo)" \
  "$DEMO_ROOT/iac-repo-template/hooks/pre-commit" \
  "Two checks. (1) Non-human committer email patterns: claude-agent, anthropic.local, @bot, agent@, noreply@. (2) Staged files under infrastructure/production/. Either check failing exits 1 with GIT_HOOK_DENY. setup.sh installs this hook into .git/hooks/ AND sets core.hooksPath so the host's global hooksPath cannot bypass it."
auto_pause

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
auto_pause 10
