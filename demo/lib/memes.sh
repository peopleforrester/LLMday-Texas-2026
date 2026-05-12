#!/usr/bin/env bash
# ABOUTME: Shared ASCII meme art for the demos.
# ABOUTME: Sourced by demo.sh and demo-claude.sh. Calls colors.sh vars.

show_meme() {
  local name="$1"
  echo ""
  case "$name" in
    creeper)
      echo -e "${GREEN}"
      cat <<'EOF'
                ┌─────────────────────┐
                │                     │
                │    ████       ████  │
                │    ████       ████  │
                │                     │
                │        █████        │
                │        █████        │
                │     ███████████     │
                │     ████   ████     │
                │     ████   ████     │
                │                     │
                └─────────────────────┘
                        S  S  S  S  .  .  .
EOF
      echo -e "${RESET}"
      echo ""
      echo -e "                   ${YELLOW}\"Aw, man.\"${RESET}"
      echo -e "    ${WHITE}— every agent after the PreToolUse hook fires${RESET}"
      ;;
    enderdragon)
      echo -e "${MAGENTA}"
      cat <<'EOF'
                  __----~~~~~~~~~~~~----__
            __--~~                          ~~--__
         /~                                        ~\
        |       ●                            ●       |
        |                                            |
        |                ╲                ╱          |
         \                ╲    ━━━━━    ╱           /
          \                ╲___________╱           /
           ~~___                                ___~~
                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

              T H E   E N D E R   D R A G O N
EOF
      echo -e "${RESET}"
      echo ""
      echo -e "          ${CYAN}server-side enforcement: the final gate${RESET}"
      echo -e "         ${WHITE}RBAC said yes. The cluster said no.${RESET}"
      ;;
  esac
  echo ""
}
