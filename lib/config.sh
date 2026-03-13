# Sourced by bin/txs -- not meant to be executed directly
# shellcheck disable=SC2034  # used by sourcing scripts
TXS_VERSION="0.5.0"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/txs"
CONFIG_FILE="$CONFIG_DIR/projects.conf"
TXS_SETTINGS_FILE="$CONFIG_DIR/config"
declare -gA PROJECT_PATH
declare -gA PROJECT_SESSION_NAME
declare -gA PROJECT_ON_CREATE
declare -ga PROJECT_ORDER=()
declare -gA DEFAULTS
_trim()
{
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
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
    PROJECT_PATH=()
    PROJECT_SESSION_NAME=()
    PROJECT_ON_CREATE=()
    PROJECT_ORDER=()
    DEFAULTS=()
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
                    on_create) DEFAULTS[$last_key]+=$'\n'"$cont_value" ;;
                    *) warn "Continuation line ignored for '$last_key' at line $line_num" ;;
                esac
            else
                case "$last_key" in
                    on_create) PROJECT_ON_CREATE[$current_section]+=$'\n'"$cont_value" ;;
                    *) warn "Continuation line ignored for '$last_key' at line $line_num" ;;
                esac
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
                PROJECT_ORDER+=("$current_section")
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
                    on_create | session_name) DEFAULTS[$key]="$value" ;;
                    path)
                        warn "'path' in [DEFAULT] is not supported (line $line_num)"
                        last_key=""
                        ;;
                    *)
                        last_key=""
                        warn "Unknown key '$key' at line $line_num"
                        ;;
                esac
            elif [[ -n $current_section ]]; then
                case "$key" in
                    path) PROJECT_PATH[$current_section]="$value" ;;
                    session_name) PROJECT_SESSION_NAME[$current_section]="$value" ;;
                    on_create) PROJECT_ON_CREATE[$current_section]="$value" ;;
                    *)
                        last_key=""
                        warn "Unknown key '$key' at line $line_num"
                        ;;
                esac
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
    case "$prop" in
        path)
            printf '%s\n' "${PROJECT_PATH[$project]:-}"
            ;;
        session_name)
            local name="${PROJECT_SESSION_NAME[$project]:-${DEFAULTS[session_name]:-}}"
            [[ -z $name ]] && name="$project"
            printf '%s\n' "${name//[.:]/-}"
            ;;
        on_create) printf '%s\n' "${PROJECT_ON_CREATE[$project]:-${DEFAULTS[on_create]:-}}" ;;
    esac
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
