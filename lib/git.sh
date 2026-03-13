# Sourced by bin/txs -- not meant to be executed directly

is_bare_repo()
{
    local path="$1"
    # Our clone-bare layout: .bare/ directory with .git file pointing to it
    if [[ -d "$path/.bare" ]]; then
        return 0
    fi
    # Standard bare repo check
    if git -C "$path" rev-parse --is-bare-repository 2> /dev/null | grep -q true; then
        return 0
    fi
    return 1
}

_list_worktree_paths()
{
    # Parse git worktree list --porcelain and output one worktree path per line.
    # Skips bare entries. Usage: _list_worktree_paths <git-dir>
    local path="$1"
    local line wt_path is_bare
    wt_path=""
    is_bare=false
    while IFS= read -r line; do
        if [[ -z $line ]]; then
            [[ -n $wt_path && $is_bare == false ]] && printf '%s\n' "$wt_path"
            wt_path=""
            is_bare=false
            continue
        fi
        case "$line" in
            worktree\ *) wt_path="${line#worktree }" ;;
            bare) is_bare=true ;;
        esac
    done < <(git -C "$path" worktree list --porcelain 2> /dev/null || true)
    # Flush last entry if output lacked a trailing blank line
    [[ -n $wt_path && $is_bare == false ]] && printf '%s\n' "$wt_path"
}

get_project_worktrees()
{
    local path="$1"
    local wt_path
    while IFS= read -r wt_path; do
        [[ -z $wt_path ]] && continue
        printf '%s\t%s\n' "$wt_path" "$(basename "$wt_path")"
    done < <(_list_worktree_paths "$path")
}

get_repo_info()
{
    # Detect repo root and type from the current directory.
    # Output: <root>\t<type>   (type = "bare" or "normal")
    # Returns 1 if not inside a git repo.
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not inside a git repository."
        return 1
    fi

    local root

    # Check for our bare layout (.bare/ directory)
    local common_dir
    common_dir=$(git rev-parse --git-common-dir 2> /dev/null) || true
    if [[ -n $common_dir ]]; then
        [[ $common_dir != /* ]] && common_dir=$(cd "$common_dir" && pwd -P)
        if [[ $(basename "$common_dir") == ".bare" ]]; then
            root=$(cd "$(dirname "$common_dir")" && pwd -P)
            printf '%s\t%s\n' "$root" "bare"
            return 0
        fi
    fi

    # Normal repo
    root=$(git rev-parse --show-toplevel 2> /dev/null) || {
        error "Could not determine repository root."
        return 1
    }
    root=$(cd "$root" && pwd -P)
    printf '%s\t%s\n' "$root" "normal"
}

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

repo_name_from_url()
{
    local url="$1"
    local name
    name=$(basename "${url%/}")
    printf '%s\n' "${name%.git}"
}

get_active_worktrees()
{
    declare -A seen=()
    local pane_path session
    while IFS='|' read -r session pane_path; do
        [[ -z $session || -z $pane_path ]] && continue
        git -C "$pane_path" rev-parse --git-dir > /dev/null 2>&1 || continue

        local git_dir repo_name origin_url
        git_dir=$(git -C "$pane_path" rev-parse --git-dir 2> /dev/null || true)
        [[ -z $git_dir ]] && continue

        origin_url=$(git -C "$pane_path" config --get remote.origin.url 2> /dev/null || true)
        if [[ -n $origin_url ]]; then
            repo_name=$(repo_name_from_url "$origin_url")
        else
            if [[ $git_dir != /* ]]; then
                git_dir=$(cd "$pane_path/$git_dir" 2> /dev/null && pwd -P) || true
            fi
            [[ -z $git_dir ]] && continue
            case "$(basename "$git_dir")" in
                .bare | .git) repo_name=$(basename "$(dirname "$git_dir")") ;;
                *) repo_name=$(basename "$git_dir") ;;
            esac
        fi

        local wt_path
        while IFS= read -r wt_path; do
            [[ -z $wt_path || -n ${seen[$wt_path]:-} ]] && continue
            seen[$wt_path]=1
            printf '%s\t%s\t%s - %s\n' "$session" "$wt_path" "$repo_name" "$(basename "$wt_path")"
        done < <(_list_worktree_paths "$pane_path")
    done < <(tmux list-panes -a -F "#{session_name}|#{pane_current_path}" 2> /dev/null || true)
}
