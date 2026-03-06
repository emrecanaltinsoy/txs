#!/usr/bin/env bash
# txs/commands.sh - Core command implementations

cmd_list() {
	local sessions
	sessions=$(get_active_sessions)

	if [[ -z "$sessions" ]]; then
		echo -e "${DIM}No active tmux sessions.${RESET}"
		return 0
	fi

	fetch_session_windows

	echo -e "${BOLD}Active tmux sessions:${RESET}"
	echo ""
	while IFS= read -r session; do
		local windows="${SESSION_WINDOWS[$session]:-}"
		echo -e "  ${GREEN}${session}${RESET}  ${DIM}[${windows}]${RESET}"
	done <<<"$sessions"
}

cmd_projects() {
	parse_config || return 1

	if [[ ${#PROJECT_ORDER[@]} -eq 0 ]]; then
		echo -e "${DIM}No projects configured in ${CONFIG_FILE}${RESET}"
		return 0
	fi

	local active_sessions
	active_sessions=$(get_active_sessions)

	echo -e "${BOLD}Configured projects:${RESET}"
	echo ""
	for project in "${PROJECT_ORDER[@]}"; do
		local path session_name on_create status
		path=$(get_project_prop "$project" "path")
		session_name=$(get_project_prop "$project" "session_name")
		on_create=$(get_project_prop "$project" "on_create")

		# Check if session is active
		if echo "$active_sessions" | grep -qx "$session_name"; then
			status="${GREEN}active${RESET}"
		else
			status="${DIM}inactive${RESET}"
		fi

		echo -e "  ${CYAN}${project}${RESET}  [${status}]"
		echo -e "    path:    ${path}"
		[[ "$session_name" != "$project" ]] && echo -e "    session: ${session_name}"
		if [[ -n "$on_create" ]]; then
			local first=true
			while IFS= read -r cmd; do
				[[ -z "$cmd" ]] && continue
				if $first; then
					echo -e "    run:     ${cmd}"
					first=false
				else
					echo -e "             ${cmd}"
				fi
			done <<<"$on_create"
		fi
		echo ""
	done
}

cmd_create() {
	local project="$1"

	parse_config || return 1

	# Check if project exists in config
	if [[ -z "${PROJECT_PATH[$project]:-}" ]]; then
		error "Project '${project}' not found in config."
		echo "Available projects:"
		for p in "${PROJECT_ORDER[@]}"; do
			echo "  - $p"
		done
		return 1
	fi

	local path session_name on_create
	path=$(expand_path "$(get_project_prop "$project" "path")")
	session_name=$(get_project_prop "$project" "session_name")
	on_create=$(get_project_prop "$project" "on_create")

	# Validate path
	if [[ ! -d "$path" ]]; then
		error "Directory does not exist: ${path}"
		return 1
	fi

	# If session already exists, just attach/switch
	if tmux_session_exists "$session_name"; then
		echo -e "${DIM}Session '${session_name}' already exists. Switching...${RESET}"
		tmux_attach_or_switch "$session_name"
		return 0
	fi

	echo -e "Creating session ${GREEN}${session_name}${RESET} at ${path}..."

	# Create the session
	tmux new-session -d -s "$session_name" -c "$path"

	# Run on_create commands if specified (before attach, since attach blocks)
	# on_create may contain multiple newline-separated commands
	if [[ -n "$on_create" ]]; then
		while IFS= read -r cmd; do
			[[ -z "$cmd" ]] && continue
			tmux send-keys -t "=$session_name:" "$cmd" Enter
		done <<<"$on_create"
	fi

	# Attach or switch
	tmux_attach_or_switch "$session_name"
}

cmd_kill() {
	local target="$1"

	if ! tmux_session_exists "$target"; then
		error "Session '${target}' does not exist."
		return 1
	fi

	tmux kill-session -t "=$target"
	echo -e "Killed session ${GREEN}${target}${RESET}."
}

cmd_help() {
	cat <<EOF
txs - Manage tmux sessions from predefined project directories

USAGE:
    txs                  Interactive fzf picker
    txs list             List active tmux sessions
    txs projects         List configured projects
    txs create <name>    Create/attach session for a project
    txs kill <name>      Kill a tmux session
    txs help             Show this help message
    txs version          Show version

INTERACTIVE MODE:
    When run with no arguments, an fzf picker shows:
      * = active sessions (select to switch)
      + = configured projects (select to create & attach)

CONFIG FILE:
    ${CONFIG_FILE}

    INI-style format where each [section] defines a project:

        [DEFAULT]
        on_create = echo "ready"  # Default command for all projects

        [my-project]
        path = ~/projects/foo     # Required: project directory
        session_name = foo        # Optional: tmux session name (default: section name)
        on_create = nvm use       # Optional: command to run after session creation

    Multi-line on_create (indented continuation lines):

        [my-project]
        path = ~/projects/foo
        on_create = tmux split-window -v -l 20
            tmux select-pane -t 1
            nvim .

    Each continuation line is sent as a separate tmux send-keys command.

CONTEXT:
    Works both inside and outside tmux:
      - Outside: creates/attaches sessions directly
      - Inside:  switches client to the target session

DEPENDENCIES:
    Required: tmux, bash
    Optional: fzf (interactive mode)
EOF
}
