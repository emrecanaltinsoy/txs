#!/usr/bin/env bash
# txs/tmux.sh - Tmux helper functions

is_inside_tmux() {
  [[ -n "${TMUX:-}" ]]
}

tmux_session_exists() {
  tmux has-session -t "=$1" 2>/dev/null
}

tmux_attach_or_switch() {
  local session_name="$1"
  if is_inside_tmux; then
    tmux switch-client -t "=$session_name"
  else
    tmux attach-session -t "=$session_name"
  fi
}

get_active_sessions() {
  tmux list-sessions -F "#{session_name}" 2>/dev/null || true
}

# Fetch all session:window mappings in one tmux call.
# Populates the SESSION_WINDOWS associative array: session_name -> "win1, win2, ..."
declare -A SESSION_WINDOWS=()

fetch_session_windows() {
  SESSION_WINDOWS=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local session="${line%%:*}"
    local window="${line#*:}"
    if [[ -n "${SESSION_WINDOWS[$session]:-}" ]]; then
      SESSION_WINDOWS[$session]+=", ${window}"
    else
      SESSION_WINDOWS[$session]="$window"
    fi
  done < <(tmux list-windows -a -F "#{session_name}:#{window_name}" 2>/dev/null || true)
}
