#!/usr/bin/env bash
# shellcheck disable=SC2034  # used by sourcing scripts
TXS_VERSION="0.2.1"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/txs"
CONFIG_FILE="$CONFIG_DIR/projects.conf"
declare -A PROJECT_PATH
declare -A PROJECT_SESSION_NAME
declare -A PROJECT_ON_CREATE
declare -a PROJECT_ORDER=()
declare -A DEFAULTS
parse_config()
{
    if [[ ! -f $CONFIG_FILE ]]; then
        error "Config file not found: $CONFIG_FILE"
        echo "Create it with example projects, or run: txs help"
        return 1
    fi
    local current_section=""
    local last_key=""
    local line_num=0
    while IFS= read -r raw_line || [[ -n $raw_line ]]; do
        ((line_num++))
        if [[ -n $last_key && -n $current_section && $raw_line =~ ^[[:space:]]+[^[:space:]] ]]; then
            local cont_value="${raw_line#"${raw_line%%[![:space:]]*}"}"
            cont_value="${cont_value%"${cont_value##*[![:space:]]}"}"
            if [[ -z $cont_value || $cont_value == \#* ]]; then
                continue
            fi
            if [[ $cont_value != \"*\" && $cont_value != \'*\' ]]; then
                cont_value="${cont_value%%#*}"
                cont_value="${cont_value%"${cont_value##*[![:space:]]}"}"
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
        local line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z $line || $line == \#* ]]; then
            last_key=""
            continue
        fi
        if [[ $line =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
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
                value="${value%"${value##*[![:space:]]}"}"
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
}
get_project_prop()
{
    local project="$1"
    local prop="$2"
    case "$prop" in
        path)
            echo "${PROJECT_PATH[$project]:-}"
            ;;
        session_name)
            local name="${PROJECT_SESSION_NAME[$project]:-${DEFAULTS[session_name]:-}}"
            [[ -z $name ]] && name="$project"
            echo "${name//./-}"
            ;;
        on_create) echo "${PROJECT_ON_CREATE[$project]:-${DEFAULTS[on_create]:-}}" ;;
    esac
}
expand_path()
{
    local path="$1"
    echo "${path/#\~/$HOME}"
}
