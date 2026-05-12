#!/usr/bin/env bash
# ABOUTME: ANSI color constants for the LLMday demo runner.
# ABOUTME: Sourced by demo.sh, setup.sh, and other demo scripts.
#
# shellcheck disable=SC2034
# All variables in this file are intentionally defined for use by callers
# that source this file. Disable the "unused variable" warning for the
# whole file rather than annotating each constant.

# Guard against double-sourcing
if [[ -n "${__DEMO_COLORS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
__DEMO_COLORS_LOADED=1

# Bold + bright variants for projector visibility. Black-background
# terminals + washed-out venue projectors need maximum contrast; subtle
# colors disappear. DIM is no longer ANSI dim (which fades to grey or
# invisible on a pale projector) — it's regular white now, so borders
# and secondary text are still readable.
RESET=$'\033[0m'
DIM=$'\033[37m'
BOLD=$'\033[1m'
CYAN=$'\033[1;96m'
GREEN=$'\033[1;92m'
BLUE=$'\033[1;94m'
YELLOW=$'\033[1;93m'
RED=$'\033[1;91m'
RED_BOLD=$'\033[1;91m'
WHITE=$'\033[1;97m'
