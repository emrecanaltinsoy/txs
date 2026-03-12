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

get_project_worktrees()
{
    local path="$1"
    is_bare_repo "$path" || return 0

    local line wt_path is_bare
    wt_path=""
    is_bare=false
    while IFS= read -r line; do
        if [[ -z $line ]]; then
            if [[ -n $wt_path && $is_bare == false ]]; then
                printf '%s\t%s\n' "$wt_path" "$(basename "$wt_path")"
            fi
            wt_path=""
            is_bare=false
            continue
        fi
        case "$line" in
            worktree\ *) wt_path="${line#worktree }" ;;
            bare) is_bare=true ;;
        esac
    done < <(git -C "$path" worktree list --porcelain 2> /dev/null || true)
}

resolve_project_from_cwd()
{
    # Find the bare repo root from $PWD (works from any worktree or subdirectory)
    local bare_root=""

    # Try git first: --git-common-dir returns the shared git dir (e.g. /path/.bare)
    local common_dir
    common_dir=$(git rev-parse --git-common-dir 2> /dev/null) || true
    if [[ -n $common_dir ]]; then
        # Resolve to absolute path
        [[ $common_dir != /* ]] && common_dir=$(cd "$common_dir" && pwd -P)
        # .bare dir is inside the project root
        if [[ $(basename "$common_dir") == ".bare" ]]; then
            bare_root=$(dirname "$common_dir")
        fi
    fi

    # Fallback: walk up from $PWD looking for .bare/
    if [[ -z $bare_root ]]; then
        local dir="$PWD"
        while [[ $dir != "/" ]]; do
            if [[ -d "$dir/.bare" ]]; then
                bare_root="$dir"
                break
            fi
            dir=$(dirname "$dir")
        done
    fi

    if [[ -z $bare_root ]]; then
        error "Not inside a bare repo worktree."
        return 1
    fi

    local resolved
    resolved=$(cd "$bare_root" && pwd -P)

    parse_config || return 1
    for project in "${PROJECT_ORDER[@]}"; do
        local project_path
        project_path=$(expand_path "$(get_project_prop "$project" "path")")
        # Resolve symlinks for comparison
        project_path=$(cd "$project_path" && pwd -P) 2> /dev/null || continue
        if [[ $project_path == "$resolved" ]]; then
            printf '%s\n' "$project"
            return 0
        fi
    done
    error "Directory '$resolved' is not a configured project."
    return 1
}

get_bare_projects()
{
    # List configured projects that are bare repos (one name per line)
    # Requires: parse_config called beforehand
    for project in "${PROJECT_ORDER[@]}"; do
        local path
        path=$(expand_path "$(get_project_prop "$project" "path")")
        [[ -d $path ]] && is_bare_repo "$path" && printf '%s\n' "$project"
    done
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
            [[ $git_dir != /* ]] && git_dir=$(realpath "$pane_path/$git_dir" 2> /dev/null || true)
            [[ -z $git_dir ]] && continue
            case "$(basename "$git_dir")" in
                .bare | .git) repo_name=$(basename "$(dirname "$git_dir")") ;;
                *) repo_name=$(basename "$git_dir") ;;
            esac
        fi

        local line wt_path is_bare
        wt_path=""
        is_bare=false
        while IFS= read -r line; do
            if [[ -z $line ]]; then
                if [[ -n $wt_path && $is_bare == false && -z ${seen[$wt_path]:-} ]]; then
                    seen[$wt_path]=1
                    printf '%s\t%s\t%s - %s\n' "$session" "$wt_path" "$repo_name" "$(basename "$wt_path")"
                fi
                wt_path=""
                is_bare=false
                continue
            fi
            case "$line" in
                worktree\ *) wt_path="${line#worktree }" ;;
                bare) is_bare=true ;;
            esac
        done < <(git -C "$pane_path" worktree list --porcelain 2> /dev/null || true)
    done < <(tmux list-panes -a -F "#{session_name}|#{pane_current_path}" 2> /dev/null || true)
}
