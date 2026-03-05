#!/usr/bin/env bash
# txs/ui.sh - Interactive fzf picker with tmux popup support

cmd_interactive() {
  if ! command -v fzf &>/dev/null; then
    echo -e "${RED}Error:${RESET} fzf is required for interactive mode."
    echo "Install fzf or use subcommands directly (e.g., txs list)"
    return 1
  fi

  # When inside tmux and NOT already in a popup, re-launch inside display-popup
  if is_inside_tmux && [[ -z "${TXS_POPUP:-}" ]]; then
    local self
    self=$(readlink -f "$0")
    tmux display-popup -E -w 80% -h 70% "TXS_POPUP=1 bash \"${self}\""
    return 0
  fi

  parse_config || return 1

  local active_sessions
  active_sessions=$(get_active_sessions)

  fetch_session_windows

  # Build reverse map: session_name -> project name
  local -A session_to_project=()
  for project in "${PROJECT_ORDER[@]}"; do
    local sname
    sname=$(get_project_prop "$project" "session_name")
    session_to_project[$sname]="$project"
  done

  # Build fzf input: combine active sessions and configured projects
  local entries=()
  local -A seen_projects=()

  # Active sessions first
  if [[ -n "$active_sessions" ]]; then
    while IFS= read -r session; do
      local windows="${SESSION_WINDOWS[$session]:-}"

      if [[ -n "${session_to_project[$session]:-}" ]]; then
        # Known project - show project name with session info
        local proj="${session_to_project[$session]}"
        entries+=("* ${proj}  [${windows}]")
        seen_projects[$proj]=1
      else
        # Unmanaged session - show raw session name
        entries+=("* ${session}  [${windows}]")
      fi
    done <<<"$active_sessions"
  fi

  # Configured projects that aren't already active
  for project in "${PROJECT_ORDER[@]}"; do
    if [[ -z "${seen_projects[$project]:-}" ]]; then
      local path
      path=$(get_project_prop "$project" "path")
      entries+=("+ ${project}  (${path})")
    fi
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo -e "${DIM}No sessions or projects available.${RESET}"
    return 0
  fi

  # fzf options: full height inside popup, partial height in terminal
  local fzf_height_opt=()
  if [[ -z "${TXS_POPUP:-}" ]]; then
    fzf_height_opt=(--height=50%)
  fi

  # Run fzf
  local header="* = active  + = project | ESC to cancel"
  local selected
  selected=$(
    printf '%s\n' "${entries[@]}" | fzf \
      --header="$header" \
      --prompt="session> " \
      "${fzf_height_opt[@]}" \
      --layout=reverse \
      --border \
      --ansi
  ) || return 0 # User cancelled

  # Parse selection
  local marker name
  marker="${selected:0:1}"
  # Extract the name (second field, before any whitespace)
  name=$(echo "$selected" | awk '{print $2}')

  case "$marker" in
  '*')
    # Active session - could be a session name or a project name
    # Try direct session name first
    if tmux_session_exists "$name"; then
      tmux_attach_or_switch "$name"
    else
      # Might be a project name whose session has a different name
      if [[ -n "${PROJECT_PATH[$name]:-}" ]]; then
        local session_name
        session_name=$(get_project_prop "$name" "session_name")
        tmux_attach_or_switch "$session_name"
      fi
    fi
    ;;
  '+')
    # Configured project - create and attach
    cmd_create "$name"
    ;;
  esac
}
