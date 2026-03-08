#!/usr/bin/env bash
is_inside_tmux()
{
    [[ -n ${TMUX:-} ]]
}
tmux_session_exists()
{
    tmux has-session -t "=$1" 2> /dev/null
}
tmux_attach_or_switch()
{
    local session_name="$1"
    if is_inside_tmux; then
        tmux switch-client -t "=$session_name"
    else
        tmux attach-session -t "=$session_name"
    fi
}
get_active_sessions()
{
    tmux list-sessions -F "#{session_name}" 2> /dev/null || true
}
declare -A SESSION_WINDOWS=()
fetch_session_windows()
{
    SESSION_WINDOWS=()
    local line
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        local session="${line%%:*}"
        local window="${line#*:}"
        if [[ -n ${SESSION_WINDOWS[$session]:-} ]]; then
            SESSION_WINDOWS[$session]+=", $window"
        else
            SESSION_WINDOWS[$session]="$window"
        fi
    done < <(tmux list-windows -a -F "#{session_name}:#{window_name}" 2> /dev/null || true)
}
open_worktree_in_session()
{
    local session="$1"
    local worktree_path="$2"

    # Check terminal interactivity before entering the loop, because
    # the while-read loop redirects stdin from a process substitution
    # which makes `-t 0` false inside the loop body.
    local has_tty=false
    [[ -t 0 && -t 1 ]] && has_tty=true

    local matched_win=""
    local win_index pane_path
    while IFS='|' read -r win_index pane_path; do
        [[ -z $win_index || -z $pane_path ]] && continue
        if [[ $pane_path == "$worktree_path" || $pane_path == "$worktree_path"/* ]]; then
            matched_win="$win_index"
            break
        fi
    done < <(tmux list-panes -t "=$session" -a -F "#{window_index}|#{pane_current_path}" 2> /dev/null || true)

    if [[ -n $matched_win ]]; then
        if is_inside_tmux; then
            tmux select-window -t "=$session:$matched_win"
            tmux switch-client -t "=$session"
        else
            if $has_tty; then
                tmux attach-session -t "=$session:$matched_win"
            else
                local client_tty
                client_tty=""
                while IFS= read -r client_tty; do
                    [[ -n $client_tty ]] && break
                done < <(tmux list-clients -F "#{client_tty}" 2> /dev/null || true)
                if [[ -n $client_tty ]]; then
                    tmux switch-client -c "$client_tty" -t "=$session:$matched_win"
                else
                    error "Cannot attach to tmux: no interactive terminal or tmux client available."
                    return 1
                fi
            fi
        fi
        return 0
    fi

    echo "No existing window found for worktree. Creating a new one..."
    tmux new-window -a -t "=$session" -n "$(basename "$worktree_path")" -c "$worktree_path"
    tmux_attach_or_switch "$session"
}
