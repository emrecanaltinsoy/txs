# Sourced by bin/txs -- not meant to be executed directly
cmd_interactive()
{
    if ! command -v fzf &> /dev/null; then
        error "fzf is required for interactive mode."
        echo "Install fzf or use subcommands directly (e.g., txs ls)"
        return 1
    fi
    parse_config || return 1

    local active_sessions
    active_sessions=$(get_active_sessions)
    fetch_session_windows

    # Map session names back to project names
    local -A session_to_project=()
    for project in "${PROJECT_ORDER[@]}"; do
        local sname
        sname=$(get_project_prop "$project" "session_name")
        session_to_project[$sname]="$project"
    done

    # Collect entries: marker \t session_name \t project_name \t worktree_path \t display_label
    # Use "-" as placeholder for empty fields (IFS read collapses consecutive delimiters)
    local entries=()
    local -A seen_projects=()

    # --- Active sessions ---
    if [[ -n $active_sessions ]]; then
        while IFS= read -r session; do
            local proj="${session_to_project[$session]:-}"
            local display_name="${proj:-$session}"

            if [[ -n $proj ]]; then
                seen_projects[$proj]=1
                local path
                path=$(expand_path "$(get_project_prop "$proj" "path")")

                if [[ -d $path ]] && is_bare_repo "$path"; then
                    # Bare repo: list worktrees with * or space marker
                    local wt_path wt_name
                    while IFS=$'\t' read -r wt_path wt_name; do
                        [[ -z $wt_path ]] && continue
                        local marker=" "
                        local matched_win
                        matched_win=$(find_window_by_path "$session" "$wt_path") || true
                        if [[ -n $matched_win ]]; then
                            marker="*"
                        fi
                        local label
                        label=$(printf '%s %-20s %s' "$marker" "$display_name - $wt_name" "[active]")
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "$marker" "$session" "$proj" "$wt_path" "$label")")
                    done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
                    continue
                fi
            fi

            # Normal project or non-configured session
            local windows="${SESSION_WINDOWS[$session]:-}"
            local label
            label=$(printf '* %-20s [%s]' "$display_name" "$windows")
            entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "*" "$session" "${proj:--}" "-" "$label")")
        done <<< "$active_sessions"
    fi

    # --- Inactive projects ---
    for project in "${PROJECT_ORDER[@]}"; do
        [[ -n ${seen_projects[$project]:-} ]] && continue
        local path
        path=$(expand_path "$(get_project_prop "$project" "path")")

        if [[ -d $path ]] && is_bare_repo "$path"; then
            # Bare repo: list worktrees with + marker
            local wt_path wt_name
            while IFS=$'\t' read -r wt_path wt_name; do
                [[ -z $wt_path ]] && continue
                local label
                label=$(printf '+ %s' "$project - $wt_name")
                entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$wt_path" "$label")")
            done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
        else
            local label
            label=$(printf '+ %s' "$project")
            entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "-" "$label")")
        fi
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo -e "${DIM}No sessions or projects available.$RESET"
        return 0
    fi

    local header="* = active  + = project | ESC to cancel"
    local selected
    selected=$(printf '%s\n' "${entries[@]}" | fzf \
        --delimiter=$'\t' \
        --with-nth=5 \
        --header="$header" \
        --prompt="session> " \
        --height="$TXS_FZF_HEIGHT" \
        --layout=reverse \
        --border \
        --ansi) || return 0

    # Parse selected entry ("-" is placeholder for empty fields)
    local sel_marker sel_session sel_project sel_wt_path
    IFS=$'\t' read -r sel_marker sel_session sel_project sel_wt_path _ <<< "$selected"
    [[ $sel_session == "-" ]] && sel_session=""
    [[ $sel_project == "-" ]] && sel_project=""
    [[ $sel_wt_path == "-" ]] && sel_wt_path=""

    case "$sel_marker" in
        '*')
            # Active session with worktree window open → switch to that window
            if [[ -n $sel_wt_path ]]; then
                open_worktree_in_session "$sel_session" "$sel_wt_path"
            else
                tmux_attach_or_switch "$sel_session"
            fi
            ;;
        ' ')
            # Worktree in active session, no window → open it
            if [[ -n $sel_wt_path && -n $sel_session ]]; then
                open_worktree_in_session "$sel_session" "$sel_wt_path"
            fi
            ;;
        '+')
            # Inactive project
            if [[ -n $sel_wt_path ]]; then
                # Bare repo worktree → attach with worktree selector
                cmd_attach "$sel_project" "$(basename "$sel_wt_path")"
            else
                cmd_attach "$sel_project"
            fi
            ;;
    esac
}
