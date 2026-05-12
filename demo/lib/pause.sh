#!/usr/bin/env bash
# ABOUTME: Spacebar-advance pause primitive for the LLMday demo runner.
# ABOUTME: Prints a dimmed [msg] prompt, waits for SPACE, then cleans up.

pause() {
  local msg="${1:-press SPACE to continue}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[PAUSE: $msg]"
    return
  fi

  echo ""
  echo -e "${DIM}[${msg}]${RESET}"

  # IMPORTANT: read from /dev/tty, NOT inherited stdin. play_dialogue
  # calls this function from inside `while ... done < "$file"`, which
  # redirects stdin to the dialogue file. Without /dev/tty, this read
  # would consume bytes from the dialogue file and the demo would
  # auto-advance + skip dialogue lines.
  local key
  while true; do
    IFS= read -rsn1 key < /dev/tty
    [[ "$key" == " " ]] && break
  done

  # Move cursor up 2 lines and clear from there to end of screen.
  # This wipes the blank line and the [msg] line cleanly and returns
  # the cursor to the line where pause() was invoked.
  printf "\033[2A\033[J"
}
