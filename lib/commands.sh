# Sourced by bin/txs -- not meant to be executed directly
cmd_ls()
{
    local filter="${1:-}"
    case "$filter" in
        sessions) _ls_sessions ;;
        projects) _ls_projects ;;
        worktrees) _ls_worktrees ;;
        "")
            _ls_sessions
            printf '\n'
            _ls_projects
            printf '\n'
            _ls_worktrees
            ;;
        *)
            error "Unknown filter '$filter'. Use: sessions, projects, worktrees"
            return 1
            ;;
    esac
}
_ls_sessions()
{
    local sessions
    sessions=$(get_active_sessions)
    if [[ -z $sessions ]]; then
        printf '%b\n' "${DIM}No active tmux sessions.$RESET"
        return 0
    fi
    fetch_session_windows
    printf '%b\n' "${BOLD}Active sessions:$RESET"
    printf '\n'
    while IFS= read -r session; do
        local windows="${SESSION_WINDOWS[$session]:-}"
        printf '%b\n' "  $GREEN$session$RESET  ${DIM}[$windows]$RESET"
    done <<< "$sessions"
}
_ls_projects()
{
    parse_config || return 1
    if [[ ${#PROJECT_ORDER[@]} -eq 0 ]]; then
        printf '%b\n' "${DIM}No projects configured in $CONFIG_FILE$RESET"
        return 0
    fi
    local active_sessions
    active_sessions=$(get_active_sessions)
    printf '%b\n' "${BOLD}Configured projects:$RESET"
    printf '\n'
    for project in "${PROJECT_ORDER[@]}"; do
        local path session_name status
        path=$(get_project_prop "$project" "path")
        session_name=$(get_project_prop "$project" "session_name")
        if printf '%s\n' "$active_sessions" | grep -Fqx "$session_name"; then
            status="${GREEN}active$RESET"
        else
            status="${DIM}inactive$RESET"
        fi
        printf '%b\n' "  $CYAN$project$RESET  [$status]  $path"
    done
}
_ls_worktrees()
{
    parse_config || return 1
    local found=false
    for project in "${PROJECT_ORDER[@]}"; do
        local path
        path=$(expand_path "$(get_project_prop "$project" "path")")
        [[ -d $path ]] || continue
        local wt_path wt_name
        while IFS=$'\t' read -r wt_path wt_name; do
            [[ -z $wt_path ]] && continue
            if [[ $found == false ]]; then
                printf '%b\n' "${BOLD}Worktrees:$RESET"
                printf '\n'
                found=true
            fi
            printf '%b\n' "  $CYAN$project$RESET - $wt_name  ${DIM}$wt_path$RESET"
        done < <(get_project_worktrees "$path" | sort -t$'\t' -k2)
    done
    if [[ $found == false ]]; then
        printf '%b\n' "${DIM}No worktrees found.$RESET"
    fi
}
cmd_attach()
{
    local project="${1:-}"
    local worktree_selector="${2:-}"

    # No args → interactive picker
    if [[ -z $project ]]; then
        cmd_interactive
        return $?
    fi

    parse_config || return 1
    if [[ -z ${PROJECT_PATH[$project]:-} ]]; then
        error "Project '$project' not found in config."
        printf '%s\n' "Available projects:"
        for p in "${PROJECT_ORDER[@]}"; do
            printf '%s\n' "  - $p"
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

    # Ensure session exists (create if needed)
    local just_created=false
    if ! tmux_session_exists "$session_name"; then
        just_created=true
        printf '%b\n' "Creating session $GREEN$session_name$RESET at $path..."
        if ! tmux new-session -d -s "$session_name" -c "$path"; then
            error "Failed to create tmux session '$session_name'"
            return 1
        fi
        # For bare repos, defer on_create until we cd into the worktree
        if [[ -n $on_create ]] && ! is_bare_repo "$path"; then
            while IFS= read -r cmd; do
                [[ -z $cmd ]] && continue
                tmux send-keys -t "=$session_name:" "$cmd" Enter
            done <<< "$on_create"
        fi
    fi

    # For bare repos, handle worktree selection
    if is_bare_repo "$path"; then
        local target_wt_path=""

        if [[ -n $worktree_selector ]]; then
            # Direct worktree by basename
            local wt_path wt_name
            while IFS=$'\t' read -r wt_path wt_name; do
                [[ -z $wt_path ]] && continue
                if [[ $wt_name == "$worktree_selector" ]]; then
                    target_wt_path="$wt_path"
                    break
                fi
            done < <(get_project_worktrees "$path")
            if [[ -z $target_wt_path ]]; then
                error "Worktree '$worktree_selector' not found in project '$project'."
                return 1
            fi
        else
            # Interactive worktree picker
            local picked
            picked=$(pick_worktree "$path") || {
                tmux_attach_or_switch "$session_name"
                return 0
            }
            # Resolve full path from branch name
            target_wt_path=$(_wt_path "$path" "bare" "$picked")
        fi

        [[ -z $target_wt_path ]] && return 0

        if [[ $just_created == true ]]; then
            # Session was just created -- move window 0 to the worktree path
            # instead of leaving it at the bare repo root
            tmux send-keys -t "=$session_name:" "cd $(printf '%q' "$target_wt_path")" Enter
            tmux rename-window -t "=$session_name:" "$(basename "$target_wt_path")"
            if [[ -n $on_create ]]; then
                while IFS= read -r cmd; do
                    [[ -z $cmd ]] && continue
                    tmux send-keys -t "=$session_name:" "$cmd" Enter
                done <<< "$on_create"
            fi
            tmux_attach_or_switch "$session_name"
        else
            open_worktree_in_session "$session_name" "$target_wt_path"
        fi
        return $?
    fi

    # Normal / non-git project: just switch to the session
    tmux_attach_or_switch "$session_name"
}
cmd_kill()
{
    local target="${1:-}"

    if [[ -z $target ]]; then
        # Interactive picker
        local sessions
        sessions=$(get_active_sessions)
        if [[ -z $sessions ]]; then
            printf '%b\n' "${DIM}No active tmux sessions.$RESET"
            return 0
        fi

        if ! command -v fzf &> /dev/null; then
            error "fzf is required for interactive kill. Usage: txs kill <session-name>"
            return 1
        fi

        target=$(printf '%s\n' "$sessions" | fzf \
            --header="Pick a session to kill (ESC to cancel)" \
            --prompt="kill> " \
            --height="$TXS_FZF_HEIGHT" \
            --layout=reverse \
            --border \
            --ansi) || return 0

        [[ -z $target ]] && return 0
    fi

    if ! tmux_session_exists "$target"; then
        error "Session '$target' does not exist."
        return 1
    fi

    # If killing the current session from inside tmux, switch away first
    if is_inside_tmux; then
        local current_session
        current_session=$(tmux display-message -p "#{session_name}" 2> /dev/null || true)
        if [[ $current_session == "$target" ]]; then
            local remaining
            remaining=$(get_active_sessions | grep -Fxv "$target" || true)
            if [[ -n $remaining ]]; then
                # Switch parent client to the first remaining session
                local next
                next=$(head -n 1 <<< "$remaining")
                tmux switch-client -t "=$next" 2> /dev/null || true
            fi
        fi
    fi

    tmux kill-session -t "=$target"
    printf '%b\n' "Killed session $GREEN$target$RESET."
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
    if [[ -f $CONFIG_FILE ]] && grep -Eq "^\[$name\][[:space:]]*$" "$CONFIG_FILE"; then
        error "Project '$name' already exists in $CONFIG_FILE"
        return 1
    fi
    # Ensure config dir and file exist
    mkdir -p "$(dirname "$CONFIG_FILE")"
    # Append the new project
    {
        printf '\n'
        printf '%s\n' "[$name]"
        printf '%s\n' "path = $resolved"
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
    if ! grep -Eq "^\[$project\][[:space:]]*$" "$CONFIG_FILE"; then
        error "Project '$project' not found in $CONFIG_FILE"
        return 1
    fi
    # Remove the section header and all following key=value / continuation lines
    # until the next section header or end of file
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN
    awk -v section="$project" '
        BEGIN { skip = 0 }
        /^\[/ {
            gsub(/[[:space:]]+$/, "")
            if ($0 == "[" section "]") { skip = 1; next }
            else { skip = 0 }
        }
        !skip { print }
    ' "$CONFIG_FILE" > "$tmpfile"
    # Remove trailing blank lines (portable across GNU/BSD)
    awk '/[^[:space:]]/ { blank = 0 } { lines[++n] = $0; if (/[^[:space:]]/) last = n } END { for (i = 1; i <= last; i++) print lines[i] }' "$tmpfile" > "$CONFIG_FILE"
    info "Removed project ${GREEN}$project${RESET}"
}
cmd_config()
{
    local target="${1:-}"
    local file
    case "$target" in
        settings) file="$TXS_SETTINGS_FILE" ;;
        projects | "") file="$CONFIG_FILE" ;;
        *)
            error "Unknown config target '$target'. Use: projects, settings"
            return 1
            ;;
    esac
    local editor="${EDITOR:-vi}"
    if [[ ! -f $file ]]; then
        mkdir -p "$(dirname "$file")"
        touch "$file"
    fi
    exec "$editor" "$file"
}
cmd_help()
{
    cat << EOF
txs - Manage tmux sessions from predefined project directories

USAGE:
    txs                          Interactive picker (sessions, worktrees, projects)

  Session management:
    txs attach [name] [worktree] Attach to a session / open a worktree
    txs kill [name]              Kill a session (interactive picker when no arg)
    txs ls [sessions|projects|worktrees]
                                 List sessions, projects, and/or worktrees

  Worktree management (run from any git repo):
    txs wt add [branch]          Create a worktree (prompts if omitted)
    txs wt remove [branch]       Remove a worktree (picker if omitted)
    txs wt list                  List worktrees

    Bare repos: worktrees created inside the repo directory.
    Normal repos: worktrees created as siblings (<repo>.<branch>).
    Use --keep-branch (-k) with remove to keep the branch.

  Project configuration:
    txs add [path]               Add a directory to the config (default: .)
    txs remove <name>            Remove a project from the config
    txs clone-bare <url> [name]  Clone a repo as bare + create default worktree
    txs config [projects|settings] Open a config file in \$EDITOR

  Other:
    txs version                  Show version
    txs help                     Show this help

ALIASES:
    list      -> ls

INTERACTIVE MODE:
    When run with no arguments, an fzf picker shows:
      * = active sessions / worktrees with open windows
        = worktrees in active sessions (no window yet)
      + = configured projects (select to create & attach)

    For bare repos, each worktree is listed as a separate entry.

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

SETTINGS FILE:
    $TXS_SETTINGS_FILE

    Simple key = value format for tool-level settings:

        auto_add_clone = true   # Add cloned repos to project config
        fzf_height = 50%        # Height of fzf picker

    For additional fzf customization, use the FZF_DEFAULT_OPTS env var.

CONTEXT:
    Works both inside and outside tmux:
      - Outside: creates/attaches sessions directly
      - Inside:  switches client to the target session

DEPENDENCIES:
    Required: tmux, bash
    Optional: fzf (interactive mode)
EOF
}
# ---------------------------------------------------------------------------
# Worktree management: txs wt (operates on current directory's git repo)
# ---------------------------------------------------------------------------
_wt_path()
{
    # Compute the worktree directory path for a branch.
    # Usage: _wt_path <root> <repo_type> <branch>
    # Bare:   $root/<reponame>.<branch>
    # Normal: $(dirname $root)/<reponame>.<branch>
    local root="$1" repo_type="$2" branch="$3"
    local dir_name
    dir_name="$(basename "$root").$branch"
    if [[ $repo_type == "bare" ]]; then
        printf '%s\n' "$root/$dir_name"
    else
        printf '%s\n' "$(dirname "$root")/$dir_name"
    fi
}
_wt_add()
{
    local branch="${1:-}"

    local repo_info root repo_type
    repo_info=$(get_repo_info) || return 1
    IFS=$'\t' read -r root repo_type <<< "$repo_info"

    if [[ -z $branch ]]; then
        if [[ ! -t 0 ]]; then
            error "Missing branch name."
            printf '%s\n' "Usage: txs wt add <branch>" >&2
            return 1
        fi
        printf '%s' "Branch name: "
        read -r branch
        if [[ -z $branch ]]; then
            error "Missing branch name."
            return 1
        fi
    fi

    if ! git check-ref-format --branch "$branch" > /dev/null 2>&1; then
        error "Invalid branch name: $branch"
        return 1
    fi

    local wt_path
    wt_path=$(_wt_path "$root" "$repo_type" "$branch")

    if [[ -d $wt_path ]]; then
        error "Worktree path already exists: $wt_path"
        return 1
    fi

    info "Fetching from origin..."
    if ! git -C "$root" fetch origin 2> /dev/null; then
        warn "Could not fetch from origin. Continuing with local refs."
    fi

    if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        # Remote branch exists
        if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
            # Local branch also exists -- just link it
            git -C "$root" worktree add "$wt_path" "$branch"
        else
            # Create local branch tracking remote
            git -C "$root" worktree add -b "$branch" "$wt_path" "origin/$branch"
            git -C "$root" branch --set-upstream-to="origin/$branch" "$branch"
        fi
    else
        # No remote branch -- create new branch from HEAD
        git -C "$root" worktree add -b "$branch" "$wt_path"
    fi

    info "Created worktree ${GREEN}$branch${RESET} at $wt_path"
}
_wt_remove()
{
    local keep_branch=false
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --keep-branch | -k) keep_branch=true ;;
            *) args+=("$arg") ;;
        esac
    done

    local branch="${args[0]:-}"

    local repo_info root repo_type
    repo_info=$(get_repo_info) || return 1
    IFS=$'\t' read -r root repo_type <<< "$repo_info"

    if [[ -z $branch ]]; then
        if [[ ! -t 0 ]]; then
            error "Missing branch name."
            printf '%s\n' "Usage: txs wt remove [--keep-branch] <branch>" >&2
            return 1
        fi
        branch=$(pick_worktree "$root" "$repo_type") || return 1
    fi

    local wt_path
    wt_path=$(_wt_path "$root" "$repo_type" "$branch")

    if [[ ! -d $wt_path ]]; then
        error "Worktree '$branch' not found at $wt_path"
        return 1
    fi

    if ! git -C "$root" worktree remove "$wt_path"; then
        error "Failed to remove worktree '$branch'. It may have uncommitted changes."
        return 1
    fi
    info "Removed worktree ${GREEN}$branch${RESET}"

    if [[ $keep_branch == true ]]; then
        # Explicitly asked to keep branch -- skip deletion
        :
    elif [[ -t 0 ]] && [[ ${#args[@]} -eq 0 ]]; then
        # Interactive mode -- ask for confirmation
        printf '%s' "Keep branch '$branch'? (y/N) "
        local ans
        read -r ans
        if [[ $ans != [yY]* ]]; then
            if git -C "$root" branch -D "$branch" 2> /dev/null; then
                info "Deleted branch ${GREEN}$branch${RESET}"
            fi
        fi
    else
        # Non-interactive default: delete branch
        if git -C "$root" branch -D "$branch" 2> /dev/null; then
            info "Deleted branch ${GREEN}$branch${RESET}"
        fi
    fi
}
_wt_list()
{
    local repo_info root repo_type
    repo_info=$(get_repo_info) || return 1
    IFS=$'\t' read -r root repo_type <<< "$repo_info"

    local found=false
    local wt_path wt_name
    while IFS=$'\t' read -r wt_path wt_name; do
        [[ -z $wt_path ]] && continue
        if [[ $found == false ]]; then
            printf '%b\n' "${BOLD}Worktrees for ${CYAN}$(basename "$root")$RESET:"
            printf '\n'
            found=true
        fi
        printf '%b\n' "  $wt_name  ${DIM}$wt_path$RESET"
    done < <(get_project_worktrees "$root" | sort -t$'\t' -k2)

    if [[ $found == false ]]; then
        printf '%b\n' "${DIM}No worktrees found.$RESET"
    fi
}
cmd_wt()
{
    local subcmd="${1:-}"
    case "$subcmd" in
        add) _wt_add "${2:-}" ;;
        remove)
            shift
            _wt_remove "$@"
            ;;
        list) _wt_list ;;
        "") _wt_list ;;
        *)
            error "Unknown wt subcommand '$subcmd'."
            printf '%s\n' "Usage: txs wt [add|remove|list]" >&2
            return 1
            ;;
    esac
}
cmd_clone_bare()
{
    # Argument validation done in bin/txs via require_arg
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
            git worktree add "$folder_name.$default_branch" "$default_branch"
        else
            git worktree add -b "$default_branch" "$folder_name.$default_branch" "origin/$default_branch"
        fi

        git branch --set-upstream-to="origin/$default_branch" "$default_branch"
        git worktree lock "$folder_name.$default_branch"

        printf '%s\n' "---------------------------------------------------"
        info "Success! Setup complete in: $folder_name"
        printf '%s\n' "Your repo data is hidden in .bare/"
        printf '%s\n' "Your active worktree is in ./$default_branch"
    ) || return $?

    # Auto-add to project config if enabled
    local auto_add
    auto_add=$(get_txs_setting "auto_add_clone")
    if [[ $auto_add == "true" ]]; then
        cmd_add "$folder_name"
    fi
}
