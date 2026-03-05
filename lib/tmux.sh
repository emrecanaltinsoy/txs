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
