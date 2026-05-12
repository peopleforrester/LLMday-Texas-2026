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

  # Box border auto-sized to terminal width
  local term_width
  term_width=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
  local box_inner=$((term_width - 2))
  (( box_inner < 40 )) && box_inner=40
  local border
  border=$(printf '─%.0s' $(seq 1 "$box_inner"))
  local heavy
  heavy=$(printf '━%.0s' $(seq 1 "$box_inner"))

  clear
  # Section banner — magenta border, white-on-cyan title bar
  echo -e "${MAGENTA}╭${border}╮${RESET}"
  printf "${MAGENTA}│${RESET} ${BADGE_DENIED:-${RED}} ${beat} ${RESET} ${BOLD}${CYAN}%-*s${RESET} ${MAGENTA}│${RESET}\n" "$((box_inner - ${#beat} - 5))" "$title"
  echo -e "${MAGENTA}╰${border}╯${RESET}"
  echo ""

  # Metadata block — bold yellow labels, bright values
  echo -e "${YELLOW}┃ Where this lives:${RESET}  ${WHITE}${path/$DEMO_ROOT/\$DEMO_ROOT}${RESET}"
  echo -e "${YELLOW}┃ What it enforces:${RESET} ${CYAN}${oneliner}${RESET}"
  echo ""

  # File content divider — magenta heavy bars
  echo -e "${MAGENTA}${heavy}${RESET}"
  echo -e "${ORANGE}  file content${RESET}"
  echo -e "${MAGENTA}${heavy}${RESET}"
  slow_print_file "$path"
  echo -e "${MAGENTA}${heavy}${RESET}"
  echo -e "${ORANGE}  end of file${RESET}"
  echo -e "${MAGENTA}${heavy}${RESET}"
  echo ""
}

# ============================================================
# Intro
# ============================================================
clear
_term_w=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
_inner=$((_term_w - 2))
(( _inner < 40 )) && _inner=40
_bd=$(printf '─%.0s' $(seq 1 "$_inner"))
echo -e "${MAGENTA}╭${_bd}╮${RESET}"
printf "${MAGENTA}│${RESET} ${BOLD}${WHITE}%-*s${RESET} ${MAGENTA}│${RESET}\n" "$((_inner - 2))" "Five layers — the actual rule, setting, manifest"
printf "${MAGENTA}│${RESET} ${CYAN}%-*s${RESET} ${MAGENTA}│${RESET}\n" "$((_inner - 2))" "Each beat shown as its enforcement file on disk"
echo -e "${MAGENTA}╰${_bd}╯${RESET}"
echo ""
echo -e "  ${CYAN}Beat 1${RESET} — ${WHITE}Claude Code PreToolUse hook${RESET} ${DIM}(bash, on this host)${RESET}"
echo -e "  ${GREEN}Beat 2${RESET} — ${WHITE}Git pre-commit hook${RESET} ${DIM}(bash, inside the IaC repo)${RESET}"
echo -e "  ${YELLOW}Beat 3${RESET} — ${WHITE}Kubernetes ValidatingAdmissionPolicy${RESET} ${DIM}(YAML, in the cluster)${RESET}"
echo -e "  ${ORANGE}Beat 4${RESET} — ${WHITE}Falco custom rule + Talon binding${RESET} ${DIM}(YAML, runtime detection-and-response)${RESET}"
echo -e "  ${MAGENTA}Beat 5${RESET} — ${WHITE}NetworkPolicy egress allowlist${RESET} ${DIM}(YAML, enforced by the CNI)${RESET}"
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
auto_pause

# ============================================================
# Beat 4 — Falco custom rule + Talon binding
# ============================================================
show_file \
  "Beat 4a" \
  "Falco custom rule (mounted into every DaemonSet pod)" \
  "$DEMO_ROOT/gitops/values/falco-values.yaml" \
  "Helm values for the Falco chart. The customRules.llmday-rules.yaml entry becomes a file at /etc/falco/rules.d/llmday-rules.yaml in every Falco pod. Two rules defined: 'Agent exec in production' fires on a shell binary (sh, bash, ksh, ...) spawned inside a production-namespace pod with containerd-shim as its parent — the syscall signature of a kubectl exec. 'Read sensitive file in production' fires on /etc/shadow / /etc/sudoers reads. Falco emits the event; falcosidekick (also configured in this file) forwards it to Talon."
auto_pause

show_file \
  "Beat 4b" \
  "Falco Talon rule bindings (response engine)" \
  "$DEMO_ROOT/gitops/values/falco-talon-values.yaml" \
  "Helm values for falco-talon. config.rulesOverride binds the Falco rule names above to the kubernetes:terminate actionner. When a matching event arrives over HTTP from falcosidekick, Talon calls the K8s API to delete the originating pod (grace_period 5s). The ReplicaSet self-heals immediately. No human in the loop, no admission webhook involved — this is post-admission runtime response."
auto_pause

# ============================================================
# Beat 5 — NetworkPolicy egress allowlist
# ============================================================
show_file \
  "Beat 5a" \
  "EKS Auto Mode NetworkPolicy enable knob" \
  "$DEMO_ROOT/gitops/manifests/cluster-config/vpc-cni-network-policy.yaml" \
  "ConfigMap in kube-system that turns the cluster's Network Policy Controller ON. Without this, EKS Auto Mode accepts NetworkPolicy resources but generates zero PolicyEndpoints and zero packet filtering. The embedded Auto Mode CNI watches this ConfigMap directly — no aws-node DaemonSet, no node restart required."
auto_pause

show_file \
  "Beat 5b" \
  "Production egress allowlist (NetworkPolicy)" \
  "$DEMO_ROOT/gitops/manifests/networkpolicies/netpol.yaml" \
  "Default-deny egress from every pod in the production namespace, with explicit allow rules: DNS (port 53 to the cluster service CIDR via ipBlock — Auto Mode runs DNS on the node OS, not as a kube-system pod, so the namespaceSelector idiom does NOT match here), intra-namespace production traffic, and the kubeflow (model registry) namespace. Anything not on the list is dropped at the wire. Falco doesn't fire, Talon doesn't run — the pod stays alive; the destination just isn't allowed."

# ============================================================
# Close
# ============================================================
echo ""
echo -e "${BOLD}Five files. Five layers. Same agent gets caught five different ways.${RESET}"
echo ""
echo -e "${DIM}  Beat 1 file:  $DEMO_ROOT/claude-hooks/pretool-use-block-prod.sh${RESET}"
echo -e "${DIM}  Beat 2 file:  $DEMO_ROOT/iac-repo-template/hooks/pre-commit${RESET}"
echo -e "${DIM}  Beat 3 file:  $DEMO_ROOT/gitops/manifests/vap/vap.yaml${RESET}"
echo -e "${DIM}  Beat 4 files: $DEMO_ROOT/gitops/values/falco-values.yaml${RESET}"
echo -e "${DIM}                $DEMO_ROOT/gitops/values/falco-talon-values.yaml${RESET}"
echo -e "${DIM}  Beat 5 files: $DEMO_ROOT/gitops/manifests/cluster-config/vpc-cni-network-policy.yaml${RESET}"
echo -e "${DIM}                $DEMO_ROOT/gitops/manifests/networkpolicies/netpol.yaml${RESET}"
echo ""
echo -e "${BOLD}Layers 1 through 5 keep the agent from breaking the system.${RESET}"
echo -e "${BOLD}Layer 6 keeps the system from saying things it shouldn't.${RESET}"
echo ""
auto_pause 10
