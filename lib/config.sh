#!/usr/bin/env bash
# txs/config.sh - Configuration, colors, and INI config parser

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

TXS_VERSION="0.0.0"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/txs"
CONFIG_FILE="${CONFIG_DIR}/projects.conf"

# ---------------------------------------------------------------------------
# Colors (only when outputting to a terminal)
# ---------------------------------------------------------------------------

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
# INI Config Parser
# ---------------------------------------------------------------------------

# Associative arrays to hold parsed config
declare -A PROJECT_PATH
declare -A PROJECT_SESSION_NAME
declare -A PROJECT_ON_CREATE
declare -a PROJECT_ORDER=()

# Defaults (populated from [DEFAULT] section; supported keys: on_create, session_name)
declare -A DEFAULTS

parse_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error:${RESET} Config file not found: ${CONFIG_FILE}"
    echo "Create it with example projects, or run: txs help"
    return 1
  fi

  local current_section=""
  local last_key=""
  local line_num=0

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    ((line_num++))

    # Detect continuation lines: starts with whitespace, not blank, not a comment
    # Continuation lines are appended (newline-separated) to the last key's value
    if [[ -n "$last_key" && -n "$current_section" && "$raw_line" =~ ^[[:space:]]+[^[:space:]] ]]; then
      local cont_value="${raw_line#"${raw_line%%[![:space:]]*}"}"
      cont_value="${cont_value%"${cont_value##*[![:space:]]}"}"

      # Skip blank continuation or comment-only continuation
      if [[ -z "$cont_value" || "$cont_value" == \#* ]]; then
        continue
      fi

      # Strip trailing comments
      if [[ "$cont_value" != \"*\" && "$cont_value" != \'*\' ]]; then
        cont_value="${cont_value%%#*}"
        cont_value="${cont_value%"${cont_value##*[![:space:]]}"}"
      fi

      if [[ "$current_section" == "DEFAULT" ]]; then
        case "$last_key" in
        on_create) DEFAULTS[$last_key]+=$'\n'"$cont_value" ;;
        *)
          echo -e "${YELLOW}Warning:${RESET} Continuation line ignored for '${last_key}' at line ${line_num}" >&2
          ;;
        esac
      else
        case "$last_key" in
        on_create) PROJECT_ON_CREATE[$current_section]+=$'\n'"$cont_value" ;;
        *)
          echo -e "${YELLOW}Warning:${RESET} Continuation line ignored for '${last_key}' at line ${line_num}" >&2
          ;;
        esac
      fi
      continue
    fi

    # Strip leading/trailing whitespace for non-continuation lines
    local line="${raw_line#"${raw_line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip empty lines and comments
    if [[ -z "$line" || "$line" == \#* ]]; then
      # Reset continuation on blank/comment lines
      last_key=""
      continue
    fi

    # Section header
    if [[ "$line" =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      last_key=""
      if [[ "$current_section" != "DEFAULT" ]]; then
        PROJECT_ORDER+=("$current_section")
      fi
      continue
    fi

    # Key = Value
    if [[ "$line" =~ ^([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Strip trailing comments (but not inside quoted values)
      if [[ "$value" != \"*\" && "$value" != \'*\' ]]; then
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
      fi

      last_key="$key"

      if [[ "$current_section" == "DEFAULT" ]]; then
        case "$key" in
        on_create | session_name) DEFAULTS[$key]="$value" ;;
        path)
          echo -e "${YELLOW}Warning:${RESET} 'path' in [DEFAULT] is not supported (line ${line_num})" >&2
          last_key=""
          ;;
        *)
          last_key=""
          echo -e "${YELLOW}Warning:${RESET} Unknown key '${key}' at line ${line_num}" >&2
          ;;
        esac
      elif [[ -n "$current_section" ]]; then
        case "$key" in
        path) PROJECT_PATH[$current_section]="$value" ;;
        session_name) PROJECT_SESSION_NAME[$current_section]="$value" ;;
        on_create) PROJECT_ON_CREATE[$current_section]="$value" ;;
        *)
          last_key=""
          echo -e "${YELLOW}Warning:${RESET} Unknown key '${key}' at line ${line_num}" >&2
          ;;
        esac
      fi
      continue
    fi

    last_key=""
    echo -e "${YELLOW}Warning:${RESET} Could not parse line ${line_num}: ${line}" >&2
  done <"$CONFIG_FILE"
}

# Get a project property with DEFAULT fallback
get_project_prop() {
  local project="$1"
  local prop="$2"

  case "$prop" in
  path)
    echo "${PROJECT_PATH[$project]:-}"
    ;;
  session_name)
    local name="${PROJECT_SESSION_NAME[$project]:-${DEFAULTS[session_name]:-}}"
    # Default to section name if empty
    [[ -z "$name" ]] && name="$project"
    # Replace dots with dashes (tmux doesn't like dots in session names)
    echo "${name//./-}"
    ;;
  on_create)
    echo "${PROJECT_ON_CREATE[$project]:-${DEFAULTS[on_create]:-}}"
    ;;
  esac
}

# Expand ~ in paths
expand_path() {
  local path="$1"
  echo "${path/#\~/$HOME}"
}
