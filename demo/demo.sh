#!/usr/bin/env bash
# demo.sh — LLMday Austin scripted demo runner
# Usage: bash demo.sh [--dry-run] [--resume-beat=N]
#
# The agent dialogue is scripted. The enforcement is real.
# Spacebar advances at major beat transitions.

set -euo pipefail

DEMO_DIR="${DEMO_DIR:-/tmp/llmday-demo}"
TYPE_DELAY_MS="${TYPE_DELAY_MS:-30}"
DRY_RUN=0
RESUME_BEAT=1

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --resume-beat=*) RESUME_BEAT="${arg#*=}" ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# ============================================================
# Colors
# ============================================================
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RED_BOLD=$'\033[1;31m'
WHITE=$'\033[97m'

# ============================================================
# Typing animation
# ============================================================
type_out() {
  local text="$1"
  local delay_ms="${2:-$TYPE_DELAY_MS}"
  local delay_s
  delay_s=$(awk "BEGIN {print $delay_ms / 1000}")

  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "$text"
    return
  fi

  local len=${#text}
  for (( i=0; i<len; i++ )); do
    printf "%s" "${text:$i:1}"
    sleep "$delay_s"
  done
  printf "\n"
}

# ============================================================
# Pause for spacebar
# ============================================================
pause() {
  local msg="${1:-press SPACE to continue}"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[PAUSE: $msg]"
    return
  fi
  echo ""
  echo -e "${DIM}[${msg}]${RESET}"
  # Disable echo, read one char at a time, wait for space
  local key
  while true; do
    IFS= read -rsn1 key
    [[ "$key" == " " ]] && break
  done
  # Move up one line and clear the pause prompt
  printf "\033[2A\033[2K\033[1B\033[2K\033[1A"
}

# ============================================================
# Banner that mimics Claude Code's startup
# ============================================================
print_banner() {
  clear
  echo -e "${DIM}╭─────────────────────────────────────────────────────────────╮${RESET}"
  echo -e "${DIM}│  Claude Code 1.2.3                                          │${RESET}"
  echo -e "${DIM}│  Connected: local k3d cluster (kubeconfig: agent-kubeconfig) │${RESET}"
  echo -e "${DIM}│  Workspace: /tmp/llmday-demo                                │${RESET}"
  echo -e "${DIM}╰─────────────────────────────────────────────────────────────╯${RESET}"
  echo ""
}

# ============================================================
# Dialogue file parser
# ============================================================
play_dialogue() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "${RED}Dialogue file not found: $file${RESET}" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace for marker detection
    case "$line" in
      "@say:user "*)
        local text="${line#@say:user }"
        # Substitute thinking markers
        text="${text//::thinking::/${DIM}}"
        text="${text//::deny::/${RED_BOLD}}"
        type_out "${GREEN}> ${text}${RESET}" 25
        ;;
      "@say:agent "*)
        local text="${line#@say:agent }"
        text="${text//::thinking::/${DIM}}"
        type_out "${CYAN}claude: ${text}${RESET}" "$TYPE_DELAY_MS"
        ;;
      "@say:hook "*)
        local text="${line#@say:hook }"
        type_out "${RED_BOLD}${text}${RESET}" 25
        ;;
      "@say:system "*)
        local text="${line#@say:system }"
        type_out "${DIM}${text}${RESET}" 20
        ;;
      "@run "*)
        local cmd="${line#@run }"
        echo -e "${BLUE}\$ ${cmd}${RESET}"
        if [[ $DRY_RUN -eq 1 ]]; then
          echo "  [DRY RUN — command not executed]"
        else
          # Allow the command to fail (we WANT it to fail for hook/policy demos)
          eval "$cmd" || true
        fi
        ;;
      "@pause"*)
        local msg="${line#@pause}"
        msg="${msg# }"  # trim leading space
        pause "${msg:-press SPACE to continue}"
        ;;
      "")
        echo ""
        ;;
      \#*)
        # Comment — skip
        ;;
      *)
        # Raw text — print as-is
        echo "$line"
        ;;
    esac
  done < "$file"
}

# ============================================================
# Main
# ============================================================
print_banner

if [[ $RESUME_BEAT -le 1 ]]; then
  type_out "${DIM}Starting demo. Three beats. Scripted dialogue. Real enforcement.${RESET}" 15
  echo ""
  pause "press SPACE to begin Beat 1 — PreToolUse hook"

  play_dialogue "$DEMO_DIR/dialogue/beat1-pretooluse.txt"
fi

if [[ $RESUME_BEAT -le 2 ]]; then
  echo ""
  pause "press SPACE to begin Beat 2 — Git hook"
  play_dialogue "$DEMO_DIR/dialogue/beat2-githook.txt"
fi

if [[ $RESUME_BEAT -le 3 ]]; then
  echo ""
  pause "press SPACE to begin Beat 3 — K8s admission"
  play_dialogue "$DEMO_DIR/dialogue/beat3-vap.txt"
fi

echo ""
echo -e "${DIM}End of demo. Return to slides.${RESET}"
