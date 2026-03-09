#!/usr/bin/env zsh
# Zsh completion for txs

_txs_projects() {
	local config="${XDG_CONFIG_HOME:-$HOME/.config}/txs/projects.conf"
	[[ -f "$config" ]] || return
	# Extract [section] names, excluding [DEFAULT]
	sed -n 's/^\[\([a-zA-Z0-9_.-]*\)\]$/\1/p' "$config" | grep -v '^DEFAULT$'
}

_txs_sessions() {
	tmux list-sessions -F '#{session_name}' 2>/dev/null
}

_txs() {
	local -a subcommands=(
		'list:List active tmux sessions'
		'worktrees:List git worktrees in active tmux sessions'
		'projects:List configured projects'
		'create:Create/attach session for a project'
		'add:Add a directory to the config'
		'remove:Remove a project from the config'
		'clone-bare:Clone repo as bare with worktree'
		'config:Open config file in $EDITOR'
		'kill:Kill a tmux session'
		'help:Show help message'
		'version:Show version'
	)

	if (( CURRENT == 2 )); then
		_describe 'command' subcommands
		return
	fi

	case "${words[2]}" in
	create)
		local -a projects
		projects=("${(@f)$(_txs_projects)}")
		[[ ${#projects[@]} -gt 0 ]] && _describe 'project' projects
		;;
	worktrees)
		local -a sessions
		sessions=("${(@f)$(_txs_sessions)}")
		[[ ${#sessions[@]} -gt 0 ]] && _describe 'session' sessions
		;;
	add | clone-bare)
		_path_files -/
		;;
	remove)
		local -a projects
		projects=("${(@f)$(_txs_projects)}")
		[[ ${#projects[@]} -gt 0 ]] && _describe 'project' projects
		;;
	kill)
		local -a sessions
		sessions=("${(@f)$(_txs_sessions)}")
		[[ ${#sessions[@]} -gt 0 ]] && _describe 'session' sessions
		;;
	esac
}

compdef _txs txs
