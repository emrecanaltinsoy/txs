# Sourced by bin/txs -- not meant to be executed directly

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# depth_project_tag ROOT DP_PATH
# Returns the relative parent path from ROOT to DP_PATH, e.g.:
#   ROOT=~/Projects  DP_PATH=~/Projects/proj1          -> Projects
#   ROOT=~/Projects  DP_PATH=~/Projects/PROJ2/api       -> PROJ2
#   ROOT=~/Projects  DP_PATH=~/Projects/PROJ2/back/api  -> PROJ2/back
depth_project_tag()
{
    local root="$1" dp_path="$2"
    local relative="${dp_path#"$root"/}"
    local parent
    parent=$(dirname "$relative")
    if [[ $parent == "." ]]; then
        basename "$root"
    else
        printf '%s' "$parent"
    fi
}

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
# Reads picker entries (marker, session, project, path, name, state; tab-separated)
# and prints them for fzf with the names padded to a common width, so the states
# line up in one column. fzf shows field 5, which is "<marker> <name>  <state>".
_picker_format()
{
    awk -F'\t' -v OFS='\t' '
        { rows[NR] = $0; if (length($5) > w) w = length($5) }
        END {
            fmt = "%s\t%s\t%s\t%s\t%s %-" w "s  %s\n"
            for (i = 1; i <= NR; i++) {
                split(rows[i], f, "\t")
                printf fmt, f[1], f[2], f[3], f[4], f[1], f[5], f[6]
            }
        }'
}

cmd_interactive()
{
    if ! command -v fzf &> /dev/null; then
        error "fzf is required for interactive mode."
        printf '%s\n' "Install fzf or use subcommands directly (e.g., txs ls)"
        return 1
    fi
    parse_config || return 1
    _build_depth_index

    local active_sessions
    active_sessions=$(get_active_sessions)
    fetch_session_windows

    # Collect entries: marker \t session_name \t project_name \t worktree_path \t name \t state
    # Use "-" as placeholder for empty fields (IFS read collapses consecutive delimiters)
    local entries=()
    local seen_projects=()
    local seen_depth_sessions=()

    # --- Active sessions ---
    if [[ -n $active_sessions ]]; then
        while IFS= read -r session; do
            local proj depth_owner_info depth_proj dp_path
            proj=$(find_project_for_session "$session") || proj=""
            depth_owner_info=$(find_depth_owner "$session") || depth_owner_info=""
            depth_proj=""
            dp_path=""
            if [[ -n $depth_owner_info ]]; then
                IFS=$'\t' read -r depth_proj dp_path <<< "$depth_owner_info"
            fi

            # Depth-discovered active session
            if [[ -z $proj && -n $depth_proj ]]; then
                seen_depth_sessions+=("$session")
                local _tag_root
                _tag_root=$(expand_path "$(get_project_prop "$depth_proj" "path")")
                local tag
                tag=$(depth_project_tag "$_tag_root" "$dp_path")
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
                        local state_label="[active]"
                        [[ $marker == " " ]] && state_label="[no window]"
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$marker" "$session" "$depth_proj" "$wt_path" "[$tag] $session - $wt_name" "$state_label")")
                    done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
                else
                    local windows
                    windows="$(get_session_windows "$session")"
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "-" "[$tag] $session" "[$windows]")")
                fi
                continue
            fi

            local display_name="${proj:-$session}"

            if [[ -n $proj ]]; then
                seen_projects+=("$proj")
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
                        local state_label="[active]"
                        [[ $marker == " " ]] && state_label="[no window]"
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$marker" "$session" "$proj" "$wt_path" "$display_name - $wt_name" "$state_label")")
                    done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
                    continue
                fi
            fi

            # Normal project or non-configured session
            local windows
            windows="$(get_session_windows "$session")"
            entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "${proj:--}" "-" "$display_name" "[$windows]")")
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
                _in_array "$dp_name" "${seen_depth_sessions[@]+"${seen_depth_sessions[@]}"}" && continue
                # Skip if this path is also an explicit (non-depth) project
                is_explicit_project_path "$dp_path" && continue
                # Only emit if this project is the designated owner for this name (last wins)
                local _owner_info _owner
                _owner_info=$(find_depth_owner "$dp_name") || _owner_info=""
                _owner=$(cut -f1 <<< "$_owner_info")
                [[ $_owner != "$project" ]] && continue
                local tag
                tag=$(depth_project_tag "$path" "$dp_path")
                if [[ -d $dp_path ]] && is_bare_repo "$dp_path"; then
                    # Depth-discovered bare repo: expand per worktree
                    local wt_path wt_name
                    while IFS=$'\t' read -r wt_path wt_name; do
                        [[ -z $wt_path ]] && continue
                        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$wt_path" "[$tag] $dp_name - $wt_name" "")")
                    done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
                else
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$dp_path" "[$tag] $dp_name" "")")
                fi
            done < <(get_depth_projects "$path" "$depth")
            continue
        fi

        _in_array "$project" "${seen_projects[@]+"${seen_projects[@]}"}" && continue
        [[ -d $path ]] || continue

        if [[ -d $path ]] && is_bare_repo "$path"; then
            # Bare repo: list worktrees with + marker
            local wt_path wt_name
            while IFS=$'\t' read -r wt_path wt_name; do
                [[ -z $wt_path ]] && continue
                entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "$wt_path" "$project - $wt_name" "")")
            done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
        else
            entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "+" "-" "$project" "-" "$project" "")")
        fi
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf '%b\n' "${DIM}No sessions or projects available.$RESET"
        return 0
    fi

    local header="* = active  + = project | ESC to cancel"
    local selected
    selected=$(printf '%s\n' "${entries[@]}" | _picker_format | fzf \
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
                    local on_create
                    on_create=$(get_project_prop "$sel_project" "on_create")
                    local session_name
                    session_name=$(sanitize_session_name "$(depth_session_name "$sel_wt_path")")
                    if is_bare_repo "$(dirname "$sel_wt_path")"; then
                        # Bare layout: session is the repo root, the worktree is a window in it
                        local bare_root created=false
                        bare_root=$(dirname "$sel_wt_path")
                        [[ $(_ensure_session "$session_name" "$bare_root" "$on_create") == created ]] && created=true
                        _attach_bare_repo "$sel_project" "$bare_root" "$session_name" "$on_create" "$(basename "$sel_wt_path")" "$created"
                    else
                        _ensure_session "$session_name" "$sel_wt_path" "$on_create" > /dev/null
                        tmux_attach_or_switch "$session_name"
                    fi
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
    _build_depth_index
    fetch_session_windows

    # Collect entries: marker \t session_name \t project_name \t worktree_path \t name \t state
    local entries=()

    while IFS= read -r session; do
        local proj depth_owner_info depth_proj dp_path
        proj=$(find_project_for_session "$session") || proj=""
        depth_owner_info=$(find_depth_owner "$session") || depth_owner_info=""
        depth_proj=""
        dp_path=""
        if [[ -n $depth_owner_info ]]; then
            IFS=$'\t' read -r depth_proj dp_path <<< "$depth_owner_info"
        fi

        # Depth-discovered active session
        if [[ -z $proj && -n $depth_proj ]]; then
            local _tag_root
            _tag_root=$(expand_path "$(get_project_prop "$depth_proj" "path")")
            local tag
            tag=$(depth_project_tag "$_tag_root" "$dp_path")
            if [[ -n $dp_path && -d $dp_path ]] && is_bare_repo "$dp_path"; then
                # Depth-discovered bare repo: only open windows
                local wt_path wt_name
                while IFS=$'\t' read -r wt_path wt_name; do
                    [[ -z $wt_path ]] && continue
                    local matched_win
                    matched_win=$(find_window_by_path "$session" "$wt_path") || true
                    [[ -z $matched_win ]] && continue
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "$wt_path" "[$tag] $session - $wt_name" "[active]")")
                done < <(get_project_worktrees "$dp_path" | sort -t$'\t' -k2)
            else
                local windows
                windows="$(get_session_windows "$session")"
                entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "$depth_proj" "-" "[$tag] $session" "[$windows]")")
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
                    [[ -z $matched_win ]] && continue # skip worktrees with no open window
                    entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "$proj" "$wt_path" "$display_name - $wt_name" "[active]")")
                done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
                continue
            fi
        fi

        # Normal project or non-configured session
        local windows
        windows="$(get_session_windows "$session")"
        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "*" "$session" "${proj:--}" "-" "$display_name" "[$windows]")")
    done <<< "$active_sessions"

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf '%b\n' "${DIM}No open sessions found.$RESET"
        return 0
    fi

    local selected
    selected=$(printf '%s\n' "${entries[@]}" | _picker_format | fzf \
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
