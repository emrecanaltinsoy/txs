# Sourced by bin/txs -- not meant to be executed directly

TXS_POPUP_WIDTH="${TXS_POPUP_WIDTH:-80%}"
TXS_POPUP_HEIGHT="${TXS_POPUP_HEIGHT:-70%}"

is_inside_tmux()
{
    [[ -n ${TMUX:-} ]]
}
check_relaunch_in_popup()
{
    local extra_args="${1:-}"
    if is_inside_tmux && [[ -z ${TXS_POPUP:-} ]]; then
        local self cmd
        self="${TXS_ROOT%/lib/txs}/bin/txs"
        cmd="TXS_POPUP=1 bash $(printf '%q' "$self")"
        [[ -n $extra_args ]] && cmd+=" $(printf '%q' "$extra_args")"
        tmux display-popup -E -w "$TXS_POPUP_WIDTH" -h "$TXS_POPUP_HEIGHT" "$cmd"
        return 0
    fi
    return 1
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
declare -gA SESSION_WINDOWS=()
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
find_window_by_path()
{
    local session="$1"
    local worktree_path="$2"

    local win_index pane_path
    while IFS='|' read -r win_index pane_path; do
        [[ -z $win_index || -z $pane_path ]] && continue
        if [[ $pane_path == "$worktree_path" || $pane_path == "$worktree_path"/* ]]; then
            echo "$win_index"
            return 0
        fi
    done < <(tmux list-panes -t "=$session" -a -F "#{window_index}|#{pane_current_path}" 2> /dev/null || true)
    return 1
}

tmux_attach_or_switch_window()
{
    local session="$1"
    local win_index="$2"
    local target="=$session:$win_index"

    if is_inside_tmux; then
        tmux switch-client -t "$target"
        return 0
    fi

    local has_tty=false
    [[ -t 0 && -t 1 ]] && has_tty=true

    if $has_tty; then
        tmux attach-session -t "$target"
        return 0
    fi

    local client_tty=""
    while IFS= read -r client_tty; do
        [[ -n $client_tty ]] && break
    done < <(tmux list-clients -F "#{client_tty}" 2> /dev/null || true)

    if [[ -n $client_tty ]]; then
        tmux switch-client -c "$client_tty" -t "$target"
        return 0
    fi

    error "Cannot attach to tmux: no interactive terminal or tmux client available."
    return 1
}

open_worktree_in_session()
{
    local session="$1"
    local worktree_path="$2"

    local matched_win
    matched_win=$(find_window_by_path "$session" "$worktree_path")

    if [[ -n $matched_win ]]; then
        tmux_attach_or_switch_window "$session" "$matched_win"
        return $?
    fi

    echo "No existing window found for worktree. Creating a new one..."
    local new_win
    new_win=$(tmux new-window -a -t "=$session" -n "$(basename "$worktree_path")" -c "$worktree_path" -P -F "#{window_index}")
    tmux_attach_or_switch_window "$session" "$new_win"
}
