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
