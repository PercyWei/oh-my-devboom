#!/usr/bin/env bash

AVAILABLE_MODULES='base homebrew zsh powerlevel10k tools dotfiles shell'
AVAILABLE_TOOLS='uv fzf rg bat eza zoxide zellij nvtop jq fd'

load_install_config() {
    local file=$1 line section='' key value line_number=0 seen=' '
    MODULES=''
    TOOLS=''
    ALLOW_REMOTE=0
    CONFLICT_POLICY=skip
    GITHUB_PROXY=''
    GIT_TIMEOUT=600
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        log_error "Cannot read installation config: $file"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -n "$line" ]] || continue
        case "$line" in
            '[modules]'|'[tools]'|'[options]')
                section=${line#\[}
                section=${section%\]}
                continue
                ;;
            \[*\]) log_error "$file:$line_number: Unknown section: $line"; return 1 ;;
        esac
        if [[ -z "$section" || "$line" != *=* ]]; then
            log_error "$file:$line_number: Expected [section] or key=value"
            return 1
        fi
        key=${line%%=*}
        value=${line#*=}
        key=${key#"${key%%[![:space:]]*}"}
        key=${key%"${key##*[![:space:]]}"}
        value=${value#"${value%%[![:space:]]*}"}
        value=${value%"${value##*[![:space:]]}"}
        case "$key" in
            ''|*[!a-z0-9_]*) log_error "$file:$line_number: Invalid key: $key"; return 1 ;;
        esac
        case "$section" in
            modules)
                [[ " $AVAILABLE_MODULES " == *" $key "* ]] || {
                    log_error "$file:$line_number: Unknown module: $key"; return 1;
                }
                ;;
            tools)
                [[ " $AVAILABLE_TOOLS " == *" $key "* ]] || {
                    log_error "$file:$line_number: Unknown tool: $key"; return 1;
                }
                ;;
            options)
                case "$key" in
                    allow_remote|conflict|github_proxy|git_timeout) ;;
                    *) log_error "$file:$line_number: Unknown option: $key"; return 1 ;;
                esac
                ;;
        esac
        if [[ "$seen" == *" $section.$key "* ]]; then
            log_error "$file:$line_number: Duplicate key: $section.$key"
            return 1
        fi
        seen="$seen$section.$key "
        if [[ "$section:$key" == options:conflict ]]; then
            case "$value" in
                skip|backup) CONFLICT_POLICY=$value ;;
                *) log_error "$file:$line_number: conflict must be skip or backup"; return 1 ;;
            esac
        elif [[ "$section:$key" == options:github_proxy ]]; then
            if [[ -n "$value" && ! "$value" =~ ^https://[^/:@?[:space:]]+(:[0-9]+)?/([^@?[:space:]]*/)?$ ]]; then
                log_error "$file:$line_number: github_proxy must be empty or an HTTPS URL prefix ending in /, without credentials, spaces or query parameters"
                return 1
            fi
            GITHUB_PROXY=$value
        elif [[ "$section:$key" == options:git_timeout ]]; then
            if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
                log_error "$file:$line_number: git_timeout must be a positive integer in seconds"
                return 1
            fi
            GIT_TIMEOUT=$value
        else
            case "$value" in
                true)
                    case "$section" in
                        modules) MODULES="${MODULES:+$MODULES }$key" ;;
                        tools) TOOLS="${TOOLS:+$TOOLS }$key" ;;
                        options) ALLOW_REMOTE=1 ;;
                    esac
                    ;;
                false) ;;
                *) log_error "$file:$line_number: $section.$key must be true or false"; return 1 ;;
            esac
        fi
    done < "$file" || return 1
}
