#!/usr/bin/env bash

# Check the descriptor actually used by each caller, including >&2 redirects.
print_styled() {
    local color=$1 text=$2
    if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
        printf '\033[%sm%s\033[0m' "$color" "$text"
    else
        printf '%s' "$text"
    fi
}

module_label() {
    case "$1" in
        base) printf '基础工具' ;;
        homebrew) printf 'Homebrew' ;;
        zsh) printf 'Zsh Augmented' ;;
        powerlevel10k) printf 'Powerlevel10k' ;;
        tools) printf '开发工具' ;;
        dotfiles) printf '配置部署' ;;
    esac
}

print_status() {
    case "$1" in
        installed) print_styled '32' '[已安装]' ;;
        ready) print_styled '36' '[已就绪]' ;;
        configured) print_styled '32' '[已部署]' ;;
        backup) print_styled '36' '[已备份]' ;;
        complete) print_styled '32' '[完成]' ;;
        partial) print_styled '33' '[部分完成]' ;;
        skipped) print_styled '33' '[跳过]' ;;
        failed) print_styled '31' '[失败]' ;;
    esac
}

reset_results() {
    RESULT_COUNT=0
    RESULT_MODULES=() RESULT_STATES=() RESULT_LABELS=() RESULT_DETAILS=() RESULT_ACTIONS=()
    CURRENT_MODULE=''
}

# These records describe actual operations in this run; stdout may carry data.
record_result() {
    RESULT_MODULES[$RESULT_COUNT]=$CURRENT_MODULE
    RESULT_STATES[$RESULT_COUNT]=$1
    RESULT_LABELS[$RESULT_COUNT]=$2
    RESULT_DETAILS[$RESULT_COUNT]=$3
    RESULT_ACTIONS[$RESULT_COUNT]=${4:-}
    RESULT_COUNT=$((RESULT_COUNT + 1))
    {
        printf '  '
        print_status "$1"
        printf ' %s：%s\n' "$2" "$3"
    } >&2
}

reset_results
