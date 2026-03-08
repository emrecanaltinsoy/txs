#!/usr/bin/env bash
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
            repo_name=$(basename "${origin_url%/}")
            repo_name="${repo_name%.git}"
        else
            [[ $git_dir != /* ]] && git_dir=$(realpath "$pane_path/$git_dir" 2> /dev/null || true)
            [[ -z $git_dir ]] && continue
            case "$(basename "$git_dir")" in
                .bare) repo_name=$(basename "$(dirname "$git_dir")") ;;
                .git) repo_name=$(basename "$(dirname "$git_dir")") ;;
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
cmd_clone_bare()
{
    local repo_url="$1"
    local folder_name="${2:-}"

    if [[ -z $repo_url ]]; then
        error "Missing repository URL."
        echo "Usage: txs clone-bare <repo-url> [folder-name]"
        return 1
    fi

    if [[ -z $folder_name ]]; then
        folder_name=$(basename "${repo_url%/}")
        folder_name="${folder_name%.git}"
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
