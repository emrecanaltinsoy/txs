#!/usr/bin/env bash
# Bash completion for txs

_txs_projects() {
	local config="${XDG_CONFIG_HOME:-$HOME/.config}/txs/projects.conf"
	[[ -f "$config" ]] || return
	sed -n 's/^\[\([a-zA-Z0-9_.-]*\)\]$/\1/p' "$config" | grep -v '^DEFAULT$'
}

_txs_sessions() {
	tmux list-sessions -F '#{session_name}' 2>/dev/null
}

_txs() {
	local cur prev
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD - 1]}"

	# Completing the subcommand (first argument)
	if [[ $COMP_CWORD -eq 1 ]]; then
		# Primary commands + hidden aliases
		mapfile -t COMPREPLY < <(compgen -W "attach ls kill add remove clone-bare config help version list sessions projects" -- "$cur")
		return
	fi

	# Completing arguments to subcommands
	case "$prev" in
	attach)
		mapfile -t COMPREPLY < <(compgen -W "$(_txs_projects)" -- "$cur")
		;;
	ls | list)
		mapfile -t COMPREPLY < <(compgen -W "sessions projects worktrees" -- "$cur")
		;;
	add | clone-bare)
		mapfile -t COMPREPLY < <(compgen -d -- "$cur")
		;;
	config)
		mapfile -t COMPREPLY < <(compgen -W "projects settings" -- "$cur")
		;;
	remove)
		mapfile -t COMPREPLY < <(compgen -W "$(_txs_projects)" -- "$cur")
		;;
	kill)
		mapfile -t COMPREPLY < <(compgen -W "$(_txs_sessions)" -- "$cur")
		;;
	esac
}

complete -F _txs txs
