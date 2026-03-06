#!/usr/bin/env bash
# txs/log.sh - Colors and logging helpers

# ---------------------------------------------------------------------------
# Colors (only when outputting to a terminal)
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # used by sourcing scripts
if [[ -t 1 ]]; then
	BOLD='\033[1m'
	DIM='\033[2m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	CYAN='\033[0;36m'
	RED='\033[0;31m'
	RESET='\033[0m'
else
	BOLD='' DIM='' GREEN='' YELLOW='' CYAN='' RED='' RESET=''
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

info() { echo -e "${GREEN}>${RESET} $*"; }
warn() { echo -e "${YELLOW}Warning:${RESET} $*" >&2; }
error() { echo -e "${RED}Error:${RESET} $*" >&2; }
