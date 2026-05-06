# Sourced by bin/txs -- not meant to be executed directly

# ---------------------------------------------------------------------------
# Reusable fzf pickers
# ---------------------------------------------------------------------------
pick_worktree()
{
    local repo_root="$1"
    local repo_type="${2:-bare}"
    if ! command -v fzf &> /dev/null; then
        error "fzf is required for interactive mode."
        return 1
    fi
    local repo_name
    repo_name=$(basename "$repo_root")
    local worktrees
    worktrees=$(get_project_worktrees "$repo_root" | sort -t$'\t' -k2)

    # For normal repos, filter out the main worktree (path == repo_root)
    if [[ $repo_type == "normal" ]]; then
        local filtered=""
        local wt_path wt_name
        while IFS=$'\t' read -r wt_path wt_name; do
            [[ -z $wt_path ]] && continue
            local resolved
            resolved=$(cd "$wt_path" && pwd -P) 2> /dev/null || continue
            [[ $resolved == "$repo_root" ]] && continue
            filtered+="$(printf '%s\t%s\n' "$wt_path" "$wt_name")"$'\n'
        done <<< "$worktrees"
        worktrees="${filtered%$'\n'}"
    fi

    if [[ -z $worktrees ]]; then
        error "No worktrees found."
        return 1
    fi
    local selected
    selected=$(printf '%s\n' "$worktrees" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --header="Pick a worktree (ESC to cancel)" \
        --prompt="worktree> " \
        --height="$TXS_FZF_HEIGHT" \
        --layout=reverse \
        --border \
        --ansi) || return 1
    [[ -z $selected ]] && return 1
    # Return the branch name (strip <reponame>. prefix from directory basename)
    local wt_name
    IFS=$'\t' read -r _ wt_name <<< "$selected"
    printf '%s\n' "${wt_name#"$repo_name".}"
}

# ---------------------------------------------------------------------------
# Interactive session picker
# ---------------------------------------------------------------------------
cmd_interactive()
{
    if ! command -v fzf &> /dev/null; then
        error "fzf is required for interactive mode."
        printf '%s\n' "Install fzf or use subcommands directly (e.g., txs ls)"
        return 1
    fi
    parse_config || return 1

    local active_sessions
    active_sessions=$(get_active_sessions)
    fetch_session_windows

    # Map session names back to project names (non-depth projects)
    local -A session_to_project=()
    for project in "${PROJECT_ORDER[@]}"; do
        local depth
        depth=$(get_project_prop "$project" "max_depth")
        [[ $depth -gt 0 ]] 2> /dev/null && continue   # handled separately
        local sname
        sname=$(get_project_prop "$project" "session_name")
        session_to_project[$sname]="$project"
    done

    # Map session names to parent project for depth-discovered repos
    # session basename → parent project name
    local -A session_to_depth_project=()
    local -A session_to_depth_path=()
    for project in "${PROJECT_ORDER[@]}"; do
        local depth
        depth=$(get_project_prop "$project" "max_depth")
        [[ $depth -gt 0 ]] 2> /dev/null || continue
        local root
        root=$(expand_path "$(get_project_prop "$project" "path")")
        local dp_path dp_name
        while IFS=$'\t' read -r dp_path dp_name; do
            [[ -z $dp_path ]] && continue
            if [[ -n ${session_to_depth_project[$dp_name]:-} ]]; then
                warn "Depth project basename collision: '$dp_name' in both '${session_to_depth_project[$dp_name]}' and '$project'. '$project' will take precedence."
            fi
            session_to_depth_project[$dp_name]="$project"
            session_to_depth_path[$dp_name]="$dp_path"
        done < <(get_depth_projects "$root" "$depth")
    done

    # Collect entries: marker \t session_name \t project_name \t worktree_path \t display_label
    # Use "-" as placeholder for empty fields (IFS read collapses consecutive delimiters)
    local entries=()
    local -A seen_projects=()
    local -A seen_depth_sessions=()

    # --- Active sessions ---
    if [[ -n $active_sessions ]]; then
        while IFS= read -r session; do
            local proj="${session_to_project[$session]:-}"
            local depth_proj="${session_to_depth_project[$session]:-}"

            # Depth-discovered active session
            if [[ -z $proj && -n $depth_proj ]]; then
                seen_depth_sessions[$session]=1
                local dp_path="${session_to_depth_path[$session]:-}"
                if [[ -n $dp_path && -d $dp_path ]] && is_bare_repo "$dp_path"; then
                    # Depth-discovered bare repo: expand per worktree with * / space markers
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
                        label=$(printf '%s %-20s %s' "$marker" "[$depth_proj] $session - $wt_name" "[active]")
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "$marker" "$session" "$depth_proj" "$wt_path" "$label")")
                    done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
                else
                    local windows="${SESSION_WINDOWS[$session]:-}"
                    local label
                    label=$(printf '* %-20s [%s]' "[$depth_proj] $session" "$windows")
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "-" "$label")")
                fi
                continue
            fi

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
        local depth
        depth=$(get_project_prop "$project" "max_depth")
        local path
        path=$(expand_path "$(get_project_prop "$project" "path")")

        if [[ $depth -gt 0 ]] 2> /dev/null; then
            # Depth project: expand into individual repos, skip already-active ones
            local dp_path dp_name
            while IFS=$'\t' read -r dp_path dp_name; do
                [[ -z $dp_path ]] && continue
                [[ -n ${seen_depth_sessions[$dp_name]:-} ]] && continue
                if [[ -d $dp_path ]] && is_bare_repo "$dp_path"; then
                    # Depth-discovered bare repo: expand per worktree
                    local wt_path wt_name
                    while IFS=$'\t' read -r wt_path wt_name; do
                        [[ -z $wt_path ]] && continue
                        local label
                        label=$(printf '+ [%s] %s - %s' "$project" "$dp_name" "$wt_name")
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$wt_path" "$label")")
                    done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
                else
                    local label
                    label=$(printf '+ [%s] %s' "$project" "$dp_name")
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$dp_path" "$label")")
                fi
            done < <(get_depth_projects "$path" "$depth")
            continue
        fi

        [[ -n ${seen_projects[$project]:-} ]] && continue

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
        printf '%b\n' "${DIM}No sessions or projects available.$RESET"
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
            # Inactive project or depth-discovered repo
            if [[ -n $sel_wt_path ]]; then
                local basename_sel
                basename_sel=$(basename "$sel_wt_path")
                # Check if this entry belongs to a direct bare repo project
                local proj_path
                proj_path=$(expand_path "$(get_project_prop "$sel_project" "path")")
                if [[ -d $proj_path ]] && is_bare_repo "$proj_path"; then
                    # Direct bare repo project worktree
                    cmd_attach "$sel_project" "$basename_sel"
                else
                    # Depth-discovered repo (normal or bare worktree)
                    # For bare worktrees, sel_wt_path is the worktree itself;
                    # the bare root is the dir whose worktrees include sel_wt_path.
                    # We can just create the session at sel_wt_path directly.
                    local on_create
                    on_create=$(get_project_prop "$sel_project" "on_create")
                    local session_name
                    session_name=$(basename "$sel_wt_path")
                    _ensure_session "$session_name" "$sel_wt_path" "$on_create" > /dev/null
                    tmux_attach_or_switch "$session_name"
                fi
            else
                cmd_attach "$sel_project"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Switch: pick from open sessions / windows only
# ---------------------------------------------------------------------------
cmd_switch()
{
    if ! command -v fzf &> /dev/null; then
        error "fzf is required for interactive mode."
        printf '%s\n' "Install fzf or use subcommands directly (e.g., txs attach)"
        return 1
    fi

    local active_sessions
    active_sessions=$(get_active_sessions)

    if [[ -z $active_sessions ]]; then
        error "No active tmux sessions."
        return 1
    fi

    parse_config || return 1
    fetch_session_windows

    # Map session names back to project names (non-depth)
    local -A session_to_project=()
    for project in "${PROJECT_ORDER[@]}"; do
        local depth
        depth=$(get_project_prop "$project" "max_depth")
        [[ $depth -gt 0 ]] 2> /dev/null && continue
        local sname
        sname=$(get_project_prop "$project" "session_name")
        session_to_project[$sname]="$project"
    done

    # Map session basenames to parent depth project
    local -A session_to_depth_project=()
    local -A session_to_depth_path=()
    for project in "${PROJECT_ORDER[@]}"; do
        local depth
        depth=$(get_project_prop "$project" "max_depth")
        [[ $depth -gt 0 ]] 2> /dev/null || continue
        local root
        root=$(expand_path "$(get_project_prop "$project" "path")")
        local dp_path dp_name
        while IFS=$'\t' read -r dp_path dp_name; do
            [[ -z $dp_path ]] && continue
            session_to_depth_project[$dp_name]="$project"
            session_to_depth_path[$dp_name]="$dp_path"
        done < <(get_depth_projects "$root" "$depth")
    done

    # Collect entries: marker \t session_name \t project_name \t worktree_path \t display_label
    local entries=()

    while IFS= read -r session; do
        local proj="${session_to_project[$session]:-}"
        local depth_proj="${session_to_depth_project[$session]:-}"

        # Depth-discovered active session
        if [[ -z $proj && -n $depth_proj ]]; then
            local dp_path="${session_to_depth_path[$session]:-}"
            if [[ -n $dp_path && -d $dp_path ]] && is_bare_repo "$dp_path"; then
                # Depth-discovered bare repo: only open windows
                local wt_path wt_name
                while IFS=$'\t' read -r wt_path wt_name; do
                    [[ -z $wt_path ]] && continue
                    local matched_win
                    matched_win=$(find_window_by_path "$session" "$wt_path") || true
                    [[ -z $matched_win ]] && continue
                    local label
                    label=$(printf '* %-20s %s' "[$depth_proj] $session - $wt_name" "[active]")
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "$wt_path" "$label")")
                done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
            else
                local windows="${SESSION_WINDOWS[$session]:-}"
                local label
                label=$(printf '* %-20s [%s]' "[$depth_proj] $session" "$windows")
                entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "-" "$label")")
            fi
            continue
        fi

        local display_name="${proj:-$session}"

        if [[ -n $proj ]]; then
            local path
            path=$(expand_path "$(get_project_prop "$proj" "path")")

            if [[ -d $path ]] && is_bare_repo "$path"; then
                # Bare repo: only show worktrees that have an open window
                local wt_path wt_name
                while IFS=$'\t' read -r wt_path wt_name; do
                    [[ -z $wt_path ]] && continue
                    local matched_win
                    matched_win=$(find_window_by_path "$session" "$wt_path") || true
                    [[ -z $matched_win ]] && continue   # skip worktrees with no open window
                    local label
                    label=$(printf '* %-20s %s' "$display_name - $wt_name" "[active]")
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s' "*" "$session" "$proj" "$wt_path" "$label")")
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

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf '%b\n' "${DIM}No open sessions found.$RESET"
        return 0
    fi

    local selected
    selected=$(printf '%s\n' "${entries[@]}" | fzf \
        --delimiter=$'\t' \
        --with-nth=5 \
        --header="Open sessions | ESC to cancel" \
        --prompt="switch> " \
        --height="$TXS_FZF_HEIGHT" \
        --layout=reverse \
        --border \
        --ansi) || return 0

    local sel_session sel_wt_path
    IFS=$'\t' read -r _ sel_session _ sel_wt_path _ <<< "$selected"
    [[ $sel_wt_path == "-" ]] && sel_wt_path=""

    if [[ -n $sel_wt_path ]]; then
        open_worktree_in_session "$sel_session" "$sel_wt_path"
    else
        tmux_attach_or_switch "$sel_session"
    fi
}
