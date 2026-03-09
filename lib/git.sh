#!/usr/bin/env bash

repo_name_from_url()
{
    local url="$1"
    local name
    name=$(basename "${url%/}")
    echo "${name%.git}"
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
