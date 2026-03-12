#!/usr/bin/env bash
# Bash completion for txs

_txs_projects() {
	local config="${XDG_CONFIG_HOME:-$HOME/.config}/txs/projects.conf"
	[[ -f "$config" ]] || return
	sed -n 's/^\[\([a-zA-Z0-9_.-]*\)\]$/\1/p' "$config" | grep -v '^DEFAULT$'
}

_txs_bare_projects() {
	local config="${XDG_CONFIG_HOME:-$HOME/.config}/txs/projects.conf"
	[[ -f "$config" ]] || return
	local section="" line value
	while IFS= read -r line; do
		if [[ $line =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
			section="${BASH_REMATCH[1]}"
			continue
		fi
		[[ $section == "DEFAULT" || -z $section ]] && continue
		if [[ $line =~ ^path[[:space:]]*=[[:space:]]*(.*) ]]; then
			value="${BASH_REMATCH[1]}"
			value="${value/#\~/$HOME}"
			[[ -d "$value/.bare" ]] && printf '%s\n' "$section"
		fi
	done <"$config"
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
		mapfile -t COMPREPLY < <(compgen -W "attach ls kill wt add remove clone-bare config help version list sessions projects" -- "$cur")
		return
	fi

	# Completing arguments to subcommands
	case "$prev" in
	attach)
		mapfile -t COMPREPLY < <(compgen -W "$(_txs_projects)" -- "$cur")
		;;
	wt)
		mapfile -t COMPREPLY < <(compgen -W "add remove list" -- "$cur")
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
	*)
		# Handle deeper completions for: txs wt <subcmd> [branch] [project]
		if [[ ${COMP_WORDS[1]} == "wt" ]]; then
			local subcmd="${COMP_WORDS[2]}"
			case "$subcmd" in
			add | remove)
				# Position 4 = branch (no completion), position 5 = project
				if [[ $COMP_CWORD -eq 4 ]]; then
					mapfile -t COMPREPLY < <(compgen -W "$(_txs_bare_projects)" -- "$cur")
				fi
				;;
			list)
				# Position 4 = project
				if [[ $COMP_CWORD -eq 3 ]]; then
					mapfile -t COMPREPLY < <(compgen -W "$(_txs_bare_projects)" -- "$cur")
				fi
				;;
			esac
		fi
		;;
	esac
}

complete -F _txs txs
