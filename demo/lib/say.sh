#!/usr/bin/env bash
# ABOUTME: Typing-animation primitive for the LLMday demo runner.
# ABOUTME: Prints text one character at a time; honors DRY_RUN to skip animation.

type_out() {
  local text="$1"
  local delay_ms="${2:-${TYPE_DELAY_MS:-30}}"
  local delay_s
  delay_s=$(awk "BEGIN {print $delay_ms / 1000}")

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo -e "$text"
    return
  fi

  local len=${#text}
  local i
  for (( i=0; i<len; i++ )); do
    printf "%s" "${text:$i:1}"
    sleep "$delay_s"
  done
  printf "\n"
}
