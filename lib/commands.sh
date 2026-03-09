#!/usr/bin/env bash
cmd_list()
{
    local sessions
    sessions=$(get_active_sessions)
    if [[ -z $sessions ]]; then
        echo -e "${DIM}No active tmux sessions.$RESET"
        return 0
    fi
    fetch_session_windows
    echo -e "${BOLD}Active tmux sessions:$RESET"
    echo ""
    while IFS= read -r session; do
        local windows="${SESSION_WINDOWS[$session]:-}"
        echo -e "  $GREEN$session$RESET  ${DIM}[$windows]$RESET"
    done <<< "$sessions"
}
cmd_worktrees()
{
    local selector="${1:-}"
    local worktrees
    worktrees=$(get_active_worktrees)

    if [[ -z $worktrees ]]; then
        echo -e "${DIM}No worktrees found.$RESET"
        return 0
    fi

    if [[ -n $selector ]]; then
        local session wt_path label
        while IFS=$'\t' read -r session wt_path label; do
            if [[ $selector == "$label" || $selector == "$(basename "$wt_path")" ]]; then
                open_worktree_in_session "$session" "$wt_path"
                return $?
            fi
        done <<< "$worktrees"

        error "No worktree found: $selector"
        return 1
    fi

    check_relaunch_in_popup "worktrees" && return 0

    if ! command -v fzf &> /dev/null; then
        local session wt_path label
        while IFS=$'\t' read -r session wt_path label; do
            echo -e "  $GREEN$label$RESET"
        done <<< "$worktrees"
        return 0
    fi

    local selected
    selected=$(printf '%s\n' "$worktrees" | fzf \
        --delimiter=$'\t' \
        --with-nth=3 \
        --header="Pick a worktree (ESC to cancel)" \
        --prompt="worktree> " \
        --layout=reverse \
        --border \
        --ansi) || return 0

    local chosen_session chosen_path
    IFS=$'\t' read -r chosen_session chosen_path _ <<< "$selected"
    [[ -z $chosen_session || -z $chosen_path ]] && return 0

    open_worktree_in_session "$chosen_session" "$chosen_path"
}
cmd_projects()
{
    parse_config || return 1
    if [[ ${#PROJECT_ORDER[@]} -eq 0 ]]; then
        echo -e "${DIM}No projects configured in $CONFIG_FILE$RESET"
        return 0
    fi
    local active_sessions
    active_sessions=$(get_active_sessions)
    echo -e "${BOLD}Configured projects:$RESET"
    echo ""
    for project in "${PROJECT_ORDER[@]}"; do
        local path session_name on_create status
        path=$(get_project_prop "$project" "path")
        session_name=$(get_project_prop "$project" "session_name")
        on_create=$(get_project_prop "$project" "on_create")
        if echo "$active_sessions" | grep -qx "$session_name"; then
            status="${GREEN}active$RESET"
        else
            status="${DIM}inactive$RESET"
        fi
        echo -e "  $CYAN$project$RESET  [$status]"
        echo -e "    path:    $path"
        [[ $session_name != "$project" ]] && echo -e "    session: $session_name"
        if [[ -n $on_create ]]; then
            local first=true
            while IFS= read -r cmd; do
                [[ -z $cmd ]] && continue
                if $first; then
                    echo -e "    run:     $cmd"
                    first=false
                else
                    echo -e "             $cmd"
                fi
            done <<< "$on_create"
        fi
        echo ""
    done
}
cmd_create()
{
    local project="$1"
    parse_config || return 1
    if [[ -z ${PROJECT_PATH[$project]:-} ]]; then
        error "Project '$project' not found in config."
        echo "Available projects:"
        for p in "${PROJECT_ORDER[@]}"; do
            echo "  - $p"
        done
        return 1
    fi
    local path session_name on_create
    path=$(expand_path "$(get_project_prop "$project" "path")")
    session_name=$(get_project_prop "$project" "session_name")
    on_create=$(get_project_prop "$project" "on_create")
    if [[ ! -d $path ]]; then
        error "Directory does not exist: $path"
        return 1
    fi
    if tmux_session_exists "$session_name"; then
        echo -e "${DIM}Session '$session_name' already exists. Switching...$RESET"
        tmux_attach_or_switch "$session_name"
        return 0
    fi
    echo -e "Creating session $GREEN$session_name$RESET at $path..."
    if ! tmux new-session -d -s "$session_name" -c "$path"; then
        error "Failed to create tmux session '$session_name'"
        return 1
    fi
    if [[ -n $on_create ]]; then
        while IFS= read -r cmd; do
            [[ -z $cmd ]] && continue
            tmux send-keys -t "=$session_name:" "$cmd" Enter
        done <<< "$on_create"
    fi
    tmux_attach_or_switch "$session_name"
}
cmd_kill()
{
    local target="$1"
    if ! tmux_session_exists "$target"; then
        error "Session '$target' does not exist."
        return 1
    fi
    tmux kill-session -t "=$target"
    echo -e "Killed session $GREEN$target$RESET."
}
cmd_add()
{
    local raw_path="${1:-.}"
    local resolved
    resolved=$(realpath "$raw_path" 2> /dev/null) || {
        error "Could not resolve path: $raw_path"
        return 1
    }
    if [[ ! -d $resolved ]]; then
        error "Directory does not exist: $resolved"
        return 1
    fi
    local name
    name=$(basename "$resolved")
    # Sanitise: only keep characters valid in INI section names
    name="${name//[^a-zA-Z0-9_.-]/-}"
    if [[ -z $name ]]; then
        error "Could not derive a project name from path."
        return 1
    fi
    # Check for duplicate section
    if [[ -f $CONFIG_FILE ]] && grep -q "^\[$name\]$" "$CONFIG_FILE"; then
        error "Project '$name' already exists in $CONFIG_FILE"
        return 1
    fi
    # Ensure config dir and file exist
    mkdir -p "$(dirname "$CONFIG_FILE")"
    # Append the new project
    {
        echo ""
        echo "[$name]"
        echo "path = $resolved"
    } >> "$CONFIG_FILE"
    info "Added project ${GREEN}$name${RESET} ($resolved)"
}
cmd_remove()
{
    local project="$1"
    if [[ ! -f $CONFIG_FILE ]]; then
        error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    # Check if section exists
    if ! grep -q "^\[$project\]$" "$CONFIG_FILE"; then
        error "Project '$project' not found in $CONFIG_FILE"
        return 1
    fi
    # Remove the section header and all following key=value / continuation lines
    # until the next section header or end of file
    local tmpfile
    tmpfile=$(mktemp)
    awk -v section="$project" '
        BEGIN { skip = 0 }
        /^\[/ {
            if ($0 == "[" section "]") { skip = 1; next }
            else { skip = 0 }
        }
        !skip { print }
    ' "$CONFIG_FILE" > "$tmpfile"
    # Remove trailing blank lines left behind
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmpfile"
    cp "$tmpfile" "$CONFIG_FILE"
    rm -f "$tmpfile"
    info "Removed project ${GREEN}$project${RESET}"
}
cmd_config()
{
    local editor="${EDITOR:-vi}"
    if [[ ! -f $CONFIG_FILE ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        touch "$CONFIG_FILE"
    fi
    exec "$editor" "$CONFIG_FILE"
}
cmd_help()
{
    cat << EOF
txs - Manage tmux sessions from predefined project directories

USAGE:
    txs                  Interactive fzf picker
    txs list             List active tmux sessions
    txs worktrees [name] List/switch git worktrees in active tmux sessions
    txs projects         List configured projects
    txs create <name>    Create/attach session for a project
    txs add [path]       Add a directory to the config (default: .)
    txs remove <name>    Remove a project from the config
    txs clone-bare <url> [name]
                         Clone a repo as bare + create default worktree
    txs config           Open the config file in \$EDITOR
    txs kill <name>      Kill a tmux session
    txs help             Show this help message
    txs version          Show version

INTERACTIVE MODE:
    When run with no arguments, an fzf picker shows:
      * = active sessions (select to switch)
      + = configured projects (select to create & attach)

CONFIG FILE:
    $CONFIG_FILE

    INI-style format where each [section] defines a project:

        [DEFAULT]
        on_create = echo "ready"  # Default command for all projects

        [my-project]
        path = ~/projects/foo     # Required: project directory
        session_name = foo        # Optional: tmux session name (default: section name)
        on_create = nvm use       # Optional: command to run after session creation

    Multi-line on_create (indented continuation lines):

        [my-project]
        path = ~/projects/foo
        on_create = tmux split-window -v -l 20
            tmux select-pane -t 1
            nvim .

    Each continuation line is sent as a separate tmux send-keys command.

CONTEXT:
    Works both inside and outside tmux:
      - Outside: creates/attaches sessions directly
      - Inside:  switches client to the target session

DEPENDENCIES:
    Required: tmux, bash
    Optional: fzf (interactive mode)
EOF
}
cmd_clone_bare()
{
    local repo_url="$1"
    local folder_name="${2:-}"

    if [[ -z $folder_name ]]; then
        folder_name=$(repo_name_from_url "$repo_url")
    fi

    if [[ -z $folder_name ]]; then
        error "Could not derive destination folder from URL: $repo_url"
        return 1
    fi

    if [[ -e $folder_name ]]; then
        error "Destination already exists: $folder_name"
        return 1
    fi

    mkdir "$folder_name"
    (
        cd "$folder_name" || exit

        git clone --bare "$repo_url" .bare
        printf 'gitdir: ./.bare\n' > .git

        git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        git fetch origin

        local default_branch=""
        if git show-ref --verify --quiet refs/remotes/origin/HEAD; then
            default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD)
            default_branch="${default_branch#origin/}"
        elif git show-ref --verify --quiet refs/remotes/origin/main; then
            default_branch="main"
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            default_branch="master"
        else
            default_branch=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed -n 's#^origin/##p' | sed '/^HEAD$/d' | head -n 1)
        fi

        if [[ -z $default_branch ]]; then
            error "Could not detect a default remote branch from origin."
            exit 1
        fi

        if git show-ref --verify --quiet "refs/heads/$default_branch"; then
            git worktree add "$default_branch" "$default_branch"
        else
            git worktree add -b "$default_branch" "$default_branch" "origin/$default_branch"
        fi

        echo "---------------------------------------------------"
        info "Success! Setup complete in: $folder_name"
        echo "Your repo data is hidden in .bare/"
        echo "Your active worktree is in ./$default_branch"
    )
}
