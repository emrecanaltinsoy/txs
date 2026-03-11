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
	if (( CURRENT == 2 )); then
		local -a session_cmds=(
			'attach:Attach to a session / open a worktree'
			'kill:Kill a session'
			'ls:List sessions, projects, and/or worktrees'
		)
		local -a worktree_cmds=(
			'wt:Manage worktrees (add, remove, list)'
		)
		local -a config_cmds=(
			'add:Add a directory to the config'
			'remove:Remove a project from the config'
			'clone-bare:Clone repo as bare with worktree'
			'config:Open config file in $EDITOR'
		)
		local -a other_cmds=(
			'help:Show help message'
			'version:Show version'
		)
		_describe 'session commands' session_cmds
		_describe 'worktree commands' worktree_cmds
		_describe 'config commands' config_cmds
		_describe 'other commands' other_cmds
		return
	fi

	case "${words[2]}" in
	attach)
		local -a projects
		projects=("${(@f)$(_txs_projects)}")
		[[ ${#projects[@]} -gt 0 ]] && _describe 'project' projects
		;;
	wt)
		if (( CURRENT == 3 )); then
			local -a subcmds=(
				'add:Create a worktree and branch'
				'remove:Remove a worktree and delete branch'
				'list:List worktrees'
			)
			_describe 'wt subcommand' subcmds
		elif (( CURRENT >= 4 )); then
			local -a projects
			projects=("${(@f)$(_txs_projects)}")
			[[ ${#projects[@]} -gt 0 ]] && _describe 'project' projects
		fi
		;;
	ls | list)
		local -a filters=(
			'sessions:List active tmux sessions'
			'projects:List configured projects'
			'worktrees:List worktrees from bare repos'
		)
		_describe 'filter' filters
		;;
	add | clone-bare)
		_path_files -/
		;;
	config)
		local -a targets=(
			'projects:Open project config'
			'settings:Open txs settings'
		)
		_describe 'config file' targets
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
