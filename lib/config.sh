# Sourced by bin/txs -- not meant to be executed directly
# shellcheck disable=SC2034  # used by sourcing scripts
TXS_VERSION="0.7.1"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/txs"
CONFIG_FILE="$CONFIG_DIR/projects.conf"
TXS_SETTINGS_FILE="$CONFIG_DIR/config"

# Use indexed arrays for bash 3.2 compatibility (macOS)
PROJECT_NAMES=()
PROJECT_PATHS=()
PROJECT_SESSION_NAMES=()
PROJECT_ON_CREATES=()
PROJECT_DEPTHS=()
PROJECT_ORDER=()  # Maintain order of projects for iteration
DEFAULT_SESSION_NAME=""
DEFAULT_ON_CREATE=""

_trim()
{
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

_find_project_index()
{
    local project="$1"
    local i
    for ((i = 0; i < ${#PROJECT_NAMES[@]}; i++)); do
        if [[ ${PROJECT_NAMES[$i]} == "$project" ]]; then
            printf '%s' "$i"
            return 0
        fi
    done
    printf '%s' "-1"
    return 1
}

_CONFIG_LOADED=false
parse_config()
{
    if [[ $_CONFIG_LOADED == true ]]; then
        return 0
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        error "Config file not found: $CONFIG_FILE"
        printf '%s\n' "Create it with example projects, or run: txs help"
        return 1
    fi
    # Reset state
    PROJECT_NAMES=()
    PROJECT_PATHS=()
    PROJECT_SESSION_NAMES=()
    PROJECT_ON_CREATES=()
    PROJECT_DEPTHS=()
    PROJECT_ORDER=()
    DEFAULT_SESSION_NAME=""
    DEFAULT_ON_CREATE=""
    
    local current_section=""
    local last_key=""
    local line_num=0
    while IFS= read -r raw_line || [[ -n $raw_line ]]; do
        ((line_num++))
        if [[ -n $last_key && -n $current_section && $raw_line =~ ^[[:space:]]+[^[:space:]] ]]; then
            local cont_value
            cont_value=$(_trim "$raw_line")
            if [[ -z $cont_value || $cont_value == \#* ]]; then
                continue
            fi
            if [[ $cont_value != \"*\" && $cont_value != \'*\' ]]; then
                cont_value="${cont_value%%#*}"
                cont_value=$(_trim "$cont_value")
            fi
            if [[ $current_section == "DEFAULT" ]]; then
                case "$last_key" in
                    on_create) DEFAULT_ON_CREATE+=$'\n'"$cont_value" ;;
                    *) warn "Continuation line ignored for '$last_key' at line $line_num" ;;
                esac
            else
                local idx
                idx=$(_find_project_index "$current_section")
                if [[ $idx -ge 0 ]]; then
                    case "$last_key" in
                        on_create) PROJECT_ON_CREATES[$idx]+=$'\n'"$cont_value" ;;
                        *) warn "Continuation line ignored for '$last_key' at line $line_num" ;;
                    esac
                fi
            fi
            continue
        fi
        local line
        line=$(_trim "$raw_line")
        if [[ -z $line || $line == \#* ]]; then
            last_key=""
            continue
        fi
        if [[ $line =~ ^\[[[:space:]]*([a-zA-Z0-9_.-]+)[[:space:]]*\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            last_key=""
            if [[ $current_section != "DEFAULT" ]]; then
                # Check if project already exists
                if [[ $(_find_project_index "$current_section") -lt 0 ]]; then
                    PROJECT_NAMES+=("$current_section")
                    PROJECT_ORDER+=("$current_section")
                    PROJECT_PATHS+=("") 
                    PROJECT_SESSION_NAMES+=("") 
                    PROJECT_ON_CREATES+=("")
                    PROJECT_DEPTHS+=("0")
                fi
            fi
            continue
        fi
        if [[ $line =~ ^([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            if [[ $value != \"*\" && $value != \'*\' ]]; then
                value="${value%%#*}"
                value=$(_trim "$value")
            fi
            last_key="$key"
            if [[ $current_section == "DEFAULT" ]]; then
                case "$key" in
                    on_create) DEFAULT_ON_CREATE="$value" ;;
                    session_name) DEFAULT_SESSION_NAME="$value" ;;
                    path)
                        warn "'path' in [DEFAULT] is not supported (line $line_num)"
                        last_key=""
                        ;;
                    max_depth)
                        warn "'max_depth' in [DEFAULT] is not supported (line $line_num)"
                        last_key=""
                        ;;
                    *)
                        last_key=""
                        warn "Unknown key '$key' at line $line_num"
                        ;;
                esac
            elif [[ -n $current_section ]]; then
                local idx
                idx=$(_find_project_index "$current_section")
                if [[ $idx -ge 0 ]]; then
                    case "$key" in
                        path) PROJECT_PATHS[$idx]="$value" ;;
                        session_name) PROJECT_SESSION_NAMES[$idx]="$value" ;;
                        on_create) PROJECT_ON_CREATES[$idx]="$value" ;;
                        max_depth) PROJECT_DEPTHS[$idx]="$value" ;;
                        *)
                            last_key=""
                            warn "Unknown key '$key' at line $line_num"
                            ;;
                    esac
                fi
            fi
            continue
        fi
        last_key=""
        warn "Could not parse line $line_num: $line"
    done < "$CONFIG_FILE"
    _CONFIG_LOADED=true
}

get_project_prop()
{
    local project="$1"
    local prop="$2"
    local idx
    idx=$(_find_project_index "$project")
    
    if [[ $idx -lt 0 ]]; then
        return 1
    fi
    
    case "$prop" in
        path)
            printf '%s\n' "${PROJECT_PATHS[$idx]}"
            ;;
        session_name)
            local name="${PROJECT_SESSION_NAMES[$idx]}"
            if [[ -z $name ]]; then
                name="$DEFAULT_SESSION_NAME"
            fi
            if [[ -z $name ]]; then
                name="$project"
            fi
            printf '%s\n' "${name//[.:]/_}"
            ;;
        on_create)
            local on_create="${PROJECT_ON_CREATES[$idx]}"
            if [[ -z $on_create ]]; then
                on_create="$DEFAULT_ON_CREATE"
            fi
            printf '%s\n' "$on_create"
            ;;
        max_depth)
            printf '%s\n' "${PROJECT_DEPTHS[$idx]:-0}"
            ;;
    esac
}

# Returns the project name whose session_name matches the given session, or empty
find_project_for_session()
{
    local session="$1"
    local i
    for ((i = 0; i < ${#PROJECT_NAMES[@]}; i++)); do
        local depth="${PROJECT_DEPTHS[$i]:-0}"
        [[ $depth -gt 0 ]] 2>/dev/null && continue
        local sname
        sname=$(get_project_prop "${PROJECT_NAMES[$i]}" "session_name")
        if [[ $sname == "$session" ]]; then
            printf '%s' "${PROJECT_NAMES[$i]}"
            return 0
        fi
    done
    return 1
}

# Returns true (0) if the given resolved path belongs to a non-depth project
is_explicit_project_path()
{
    local path="$1"
    local i
    for ((i = 0; i < ${#PROJECT_NAMES[@]}; i++)); do
        local depth="${PROJECT_DEPTHS[$i]:-0}"
        [[ $depth -gt 0 ]] 2>/dev/null && continue
        local epath
        epath=$(expand_path "${PROJECT_PATHS[$i]}")
        if [[ $epath == "$path" ]]; then
            return 0
        fi
    done
    return 1
}

# For a depth-discovered repo basename, find the owning depth project and its path.
# Outputs: <project_name>\t<dp_path>  or nothing if not found.
# Last-writer-wins (mirrors the original declare -A assignment order).
find_depth_owner()
{
    local dp_name="$1"
    local result_project="" result_path=""
    local project
    for project in "${PROJECT_ORDER[@]}"; do
        local depth root dp_path name
        depth=$(get_project_prop "$project" "max_depth")
        [[ $depth -gt 0 ]] 2>/dev/null || continue
        root=$(expand_path "$(get_project_prop "$project" "path")")
        while IFS=$'\t' read -r dp_path name; do
            [[ -z $dp_path ]] && continue
            is_explicit_project_path "$dp_path" && continue
            if [[ $name == "$dp_name" ]]; then
                result_project="$project"
                result_path="$dp_path"
            fi
        done < <(get_depth_projects "$root" "$depth")
    done
    if [[ -n $result_project ]]; then
        printf '%s\t%s' "$result_project" "$result_path"
        return 0
    fi
    return 1
}

# Returns 0 if needle is in the indexed array passed as remaining args
_in_array()
{
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ $item == "$needle" ]] && return 0
    done
    return 1
}

expand_path()
{
    local path="$1"
    printf '%s\n' "${path/#\~/$HOME}"
}

get_txs_setting()
{
    local key="$1"
    [[ -f $TXS_SETTINGS_FILE ]] || return 0
    local line
    while IFS= read -r line; do
        line=$(_trim "$line")
        [[ -z $line || $line == \#* ]] && continue
        if [[ $line =~ ^([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local k v
            k="${BASH_REMATCH[1]}"
            v="${BASH_REMATCH[2]}"
            v="${v%%#*}"
            v=$(_trim "$v")
            if [[ $k == "$key" ]]; then
                printf '%s\n' "$v"
                return 0
            fi
        fi
    done < "$TXS_SETTINGS_FILE"
}

# Resolve settings that are used in hot paths (fzf calls)
_fzf_height=$(get_txs_setting "fzf_height")
# shellcheck disable=SC2034  # used by sourcing scripts
TXS_FZF_HEIGHT="${_fzf_height:-50%}"
unset _fzf_height
