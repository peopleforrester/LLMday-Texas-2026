#!/usr/bin/env bash
# ABOUTME: Beat 4 — runtime catch after admission slip.
# ABOUTME: Demonstrates Falco + Talon killing a production pod the agent
# ABOUTME: exec'd into to read sensitive files, because admission policies
# ABOUTME: are scoped to the Deployment write path and cannot see exec.
#
# Story:
#   - Beats 1-3 (demo.sh) showed admission/pre-admission denying writes.
#   - This beat shows what happens when an agent doesn't try to write at all
#     — it just exec's into an existing production pod and starts poking
#     around. Admission has no opinion on exec (the Deployment isn't being
#     modified). RBAC for the agent SA happens to allow pods/exec.
#   - Falco notices: "Read sensitive file untrusted" on /etc/shadow inside
#     a production-namespace pod. falcosidekick forwards the event to
#     Falco Talon. Talon terminates the pod within a few seconds.
#   - ArgoCD self-heals the Deployment, the model-server pod count returns
#     to 3, and the demo is back where it started.
#
# Why this matters for the talk:
#   The admission gate held the Deployment. RBAC was loose enough to let
#   the agent exec. The runtime gate caught the consequence. Three
#   different layers, three different failure modes, three different
#   defenses. This is the layer for "agent that got past admission."

set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LOCAL="$DEMO_ROOT/.local"
export DEMO_ROOT DEMO_LOCAL

# shellcheck source=lib/colors.sh
source "$DEMO_ROOT/lib/colors.sh"
# shellcheck source=lib/say.sh
source "$DEMO_ROOT/lib/say.sh"
# shellcheck source=lib/pause.sh
source "$DEMO_ROOT/lib/pause.sh"
# shellcheck source=lib/memes.sh
source "$DEMO_ROOT/lib/memes.sh"

# We need an ADMIN kubeconfig for this beat, not the over-scoped
# claude-agent SA — exec is a pods/exec subresource and the agent SA
# already has CRUD on pods so it'd work either way, but for clarity
# of narration we use admin to also show falco/talon logs after.
ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-/tmp/llmday-admin.kubeconfig}"
AGENT_KUBECONFIG="$DEMO_LOCAL/kubeconfig"

if [[ ! -f "$ADMIN_KUBECONFIG" ]]; then
  echo -e "${RED}ERROR: $ADMIN_KUBECONFIG not found.${RESET}" >&2
  echo "  Run: aws eks update-kubeconfig --region us-east-2 --name llmday-demo --kubeconfig $ADMIN_KUBECONFIG" >&2
  exit 1
fi
if [[ ! -f "$AGENT_KUBECONFIG" ]]; then
  echo -e "${RED}ERROR: $AGENT_KUBECONFIG not found. Run setup.sh first.${RESET}" >&2
  exit 1
fi

# ============================================================
# Banner
# ============================================================
print_banner() {
  clear
  local term_width
  term_width=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
  local box_inner=$((term_width - 2))
  (( box_inner < 40 )) && box_inner=40
  local border
  border=$(printf '─%.0s' $(seq 1 "$box_inner"))
  local padded
  padded=$(printf '%-*s' "$box_inner" "  Beat 4 — Runtime catch (Falco + Talon)")
  echo -e "${MAGENTA}╭${border}╮${RESET}"
  echo -e "${MAGENTA}│${WHITE}${padded}${MAGENTA}│${RESET}"
  padded=$(printf '%-*s' "$box_inner" "  Admission held the write. The agent tried something else.")
  echo -e "${MAGENTA}│${CYAN}${padded}${MAGENTA}│${RESET}"
  echo -e "${MAGENTA}╰${border}╯${RESET}"
  echo ""
}

# ============================================================
# Helpers
# ============================================================
say_op() { type_out "${YELLOW}> Operator:${RESET} $*" 20; }
say_agent() { type_out "${CYAN}claude:${RESET} $*" 25; }
run_cmd() {
  local label="$1"; shift
  echo -e "${BLUE}\$ ${label}${RESET}"
  "$@" || true
}

# ============================================================
# Main
# ============================================================
print_banner
say_op "Beats 1, 2, and 3 stopped the agent from writing the production Deployment."
say_op "Watch what happens when it stops trying to write — and just exec's instead."
echo ""
pause "press SPACE to begin Beat 4"
clear
print_banner

# --- Scene 1: production is healthy, 3 pods up ---
say_op "Production right now:"
echo ""
run_cmd "kubectl --kubeconfig=ADMIN -n production get pods -l app=model-server -o wide" \
  kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n production get pods -l app=model-server -o wide
echo ""
TARGET_POD=$(kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n production get pods -l app=model-server \
  -o jsonpath='{.items[0].metadata.name}')
echo -e "${DIM}Picking target: ${WHITE}${TARGET_POD}${RESET}"
echo ""
pause "press SPACE — agent reasons about its options"

# --- Scene 2: agent reasoning ---
clear
print_banner
say_agent "The Deployment write was denied by admission. RBAC says I have pods/exec on production."
say_agent "I'll exec into one of the model-server pods and look around — maybe read mounted secrets."
echo ""
pause "press SPACE — agent execs"

# --- Scene 3: the exec + sensitive-file read ---
clear
print_banner
echo -e "${YELLOW}> Operator:${RESET} watch this — and watch the pod count after."
echo ""
# Show what's being run as if the agent typed it. Use a non-interactive
# exec (no -t) because the projector terminal often isn't a real TTY.
# /bin/sh -c "..." is the syscall signature the custom Falco rule
# detects (proc.name=sh, proc.pname=containerd-shim).
echo -e "${BLUE}\$ kubectl --kubeconfig=AGENT -n production exec ${TARGET_POD} -- /bin/sh -c \"id; cat /etc/shadow\"${RESET}"
kubectl --kubeconfig="$AGENT_KUBECONFIG" -n production exec "$TARGET_POD" -- \
  /bin/sh -c "id; cat /etc/shadow 2>&1" 2>&1 | head -5 || true
echo ""
echo -e "${DIM}(Falco is seeing this happen right now: 'Agent exec in production')${RESET}"
echo ""
echo -e "${DIM}Waiting up to 30s for Talon to react...${RESET}"

# --- Scene 4: watch the pod disappear ---
# Talon's grace_period is 5s. Pod gets deletionTimestamp set, then is
# fully removed a few seconds later. We watch for either signature:
# the pod has a deletionTimestamp, OR the pod no longer exists at all,
# OR a NEW pod with the same labels but a different name has appeared.
deadline=$(( $(date +%s) + 30 ))
killed=0
while (( $(date +%s) < deadline )); do
  # Look for deletionTimestamp first (during grace window)
  status=$(kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n production get pod "$TARGET_POD" \
    -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)
  if [[ -n "$status" ]]; then
    killed=1; break
  fi
  # Or look for the pod being gone entirely
  if ! kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n production get pod "$TARGET_POD" >/dev/null 2>&1; then
    killed=1; break
  fi
  sleep 1
done
echo ""
if (( killed == 1 )); then
  echo -e "${BADGE_DENIED} ✗ POD TERMINATED BY TALON ${RESET}"
else
  echo -e "${BADGE_ERROR} ⚠ Talon did not react within 30s — check 'kubectl -n falco logs deploy/falco-talon' ${RESET}"
fi
echo ""

# --- Scene 5: production is back to 3 pods (ArgoCD self-heal) ---
say_op "And production now:"
echo ""
sleep 2  # let the replacement schedule
run_cmd "kubectl --kubeconfig=ADMIN -n production get pods -l app=model-server" \
  kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n production get pods -l app=model-server
echo ""
say_op "Same Deployment. The killed pod was replaced by the ReplicaSet — no human in the loop."
say_op "The runtime gate caught the consequence of the exec. The pipeline self-healed."
echo ""

# --- Scene 6: show the Talon log proving the cause-and-effect ---
echo -e "${DIM}From Talon's log:${RESET}"
kubectl --kubeconfig="$ADMIN_KUBECONFIG" -n falco logs deploy/falco-talon --tail=20 2>/dev/null | \
  grep -iE 'terminate|kill|action|rule|production' | head -10
echo ""
echo -e "${MAGENTA}End of Beat 4. Return to slides.${RESET}"
show_meme enderdragon
pause "press SPACE to exit"
