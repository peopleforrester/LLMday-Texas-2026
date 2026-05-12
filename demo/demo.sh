#!/usr/bin/env bash
# demo.sh — LLMday Austin scripted demo runner
# Usage: bash demo.sh [--dry-run] [--resume-beat=N]
#
# The agent dialogue is scripted. The enforcement is real.
# Spacebar advances at major beat transitions.
#
# Resolves $DEMO_ROOT from the script location, so this works from
# wherever the repo is cloned.

set -euo pipefail

# Resolve repo-relative paths
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
export DEMO_ROOT DEMO_LOCAL

# Load primitives
# shellcheck source=lib/colors.sh
source "$DEMO_ROOT/lib/colors.sh"
# shellcheck source=lib/say.sh
source "$DEMO_ROOT/lib/say.sh"
# shellcheck source=lib/pause.sh
source "$DEMO_ROOT/lib/pause.sh"

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
export DRY_RUN TYPE_DELAY_MS

# Sanity check that setup.sh has run
if [[ $DRY_RUN -eq 0 && ! -f "$DEMO_LOCAL/kubeconfig" ]]; then
  echo ""
  echo "ERROR: $DEMO_LOCAL/kubeconfig not found." >&2
  echo "Run 'bash $DEMO_ROOT/setup.sh' first." >&2
  echo ""
  exit 1
fi

# ============================================================
# Banner that mimics Claude Code's startup
# ============================================================
print_banner() {
  clear
  # Box width: 65 chars between borders. Truncate kubeconfig path to fit.
  local box_inner=63
  local kube_label="Kubeconfig: "
  local kube_path="${DEMO_LOCAL/#$HOME/~}/kubeconfig"
  local content="  ${kube_label}${kube_path}"
  # Truncate if too long
  if (( ${#content} > box_inner )); then
    content="${content:0:$((box_inner - 3))}..."
  fi
  # Pad to fill
  local pad_count=$(( box_inner - ${#content} ))
  (( pad_count < 0 )) && pad_count=0
  local pad
  pad=$(printf '%*s' "$pad_count" '')

  local region="${AWS_REGION:-us-east-2}"
  echo -e "${DIM}╭─────────────────────────────────────────────────────────────────╮${RESET}"
  echo -e "${DIM}│  Claude Code 1.2.3                                              │${RESET}"
  echo -e "${DIM}│  Connected: EKS Auto Mode ($region)                              │${RESET}"
  echo -e "${DIM}│${content}${pad}│${RESET}"
  echo -e "${DIM}╰─────────────────────────────────────────────────────────────────╯${RESET}"
  echo ""
}

# ============================================================
# Dialogue file parser
# ============================================================
play_dialogue() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo -e "${RED}Dialogue file not found: $file${RESET}" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "@say:user "*)
        local text="${line#@say:user }"
        text="${text//::thinking::/${DIM}}"
        text="${text//::deny::/${RED_BOLD}}"
        # The dialogue convention already includes the leading "> " on user
        # lines (the visible prompt marker). Don't double-prefix it.
        type_out "${GREEN}${text}${RESET}" 25
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
        # Detect a heredoc on this @run line and slurp subsequent dialogue
        # lines into the command until we hit the terminator on its own
        # line. Without this, multi-line heredocs (Beat 3's YAML write)
        # would only get the first line eval'd; the heredoc body would
        # arrive at bash on later iterations of this while loop, garbled.
        if [[ "$cmd" =~ \<\<-?[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]? ]]; then
          local heredoc_tag="${BASH_REMATCH[1]}"
          local heredoc_line
          while IFS= read -r heredoc_line; do
            cmd+=$'\n'"$heredoc_line"
            if [[ "$heredoc_line" == "$heredoc_tag" ]]; then
              break
            fi
          done
        fi
        # Expand $DEMO_ROOT and $DEMO_LOCAL in the command (literals in dialogue)
        cmd="${cmd//\$DEMO_ROOT/$DEMO_ROOT}"
        cmd="${cmd//\$DEMO_LOCAL/$DEMO_LOCAL}"
        # Print the command. Multi-line commands get a "$ " on the first
        # line; continuation lines print as-is so the audience sees the
        # heredoc body in natural form.
        if [[ "$cmd" == *$'\n'* ]]; then
          local first_line="${cmd%%$'\n'*}"
          local rest="${cmd#*$'\n'}"
          echo -e "${BLUE}\$ ${first_line}${RESET}"
          echo -e "${BLUE}${rest}${RESET}"
        else
          echo -e "${BLUE}\$ ${cmd}${RESET}"
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
          echo "  [DRY RUN — command not executed]"
        else
          # Allow command to fail — we WANT it to fail at hook/policy points
          eval "$cmd" || true
        fi
        ;;
      "@pause"*)
        local msg="${line#@pause}"
        msg="${msg# }"
        pause "${msg:-press SPACE to continue}"
        ;;
      "")
        echo ""
        ;;
      \#*)
        # Comment — skip
        ;;
      *)
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
  clear
  print_banner
  play_dialogue "$DEMO_ROOT/dialogue/beat1-pretooluse.txt"
fi

if [[ $RESUME_BEAT -le 2 ]]; then
  echo ""
  pause "press SPACE to begin Beat 2 — Git hook"
  clear
  print_banner
  play_dialogue "$DEMO_ROOT/dialogue/beat2-githook.txt"
fi

if [[ $RESUME_BEAT -le 3 ]]; then
  echo ""
  pause "press SPACE to begin Beat 3 — K8s admission"
  clear
  print_banner
  play_dialogue "$DEMO_ROOT/dialogue/beat3-vap.txt"
fi

echo ""
echo -e "${DIM}End of demo. Return to slides.${RESET}"
echo ""
# Hold the final frame so the speaker isn't dumped to the shell prompt
# mid-thought. Press SPACE to actually exit.
pause "press SPACE to exit the demo"
