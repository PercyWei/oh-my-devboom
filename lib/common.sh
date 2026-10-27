#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/output.sh"

log_info() { print_styled '36' '[信息]'; printf ' %s\n' "$*"; }
log_warn() { { print_styled '33' '[警告]'; printf ' %s\n' "$*"; } >&2; }
log_error() { { print_styled '31' '[错误]'; printf ' %s\n' "$*"; } >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Bound Git and Antidote's child Git processes without requiring GNU timeout.
run_git_download() (
    local download_pid='' timer_pid='' helper_pid pid git_timeout=$GIT_TIMEOUT
    local -x GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1 GIT_HTTP_LOW_SPEED_TIME=30
    if [[ -n "${GITHUB_PROXY:-}" ]]; then
        local config_count=${GIT_CONFIG_COUNT:-0}
        if [[ ! "$config_count" =~ ^[0-9]+$ ]]; then
            log_error 'GIT_CONFIG_COUNT must be a non-negative integer.'
            return 1
        fi
        config_count=$((10#$config_count))
        export "GIT_CONFIG_KEY_$config_count=url.${GITHUB_PROXY}https://github.com/.insteadOf"
        export "GIT_CONFIG_VALUE_$config_count=https://github.com/"
        export GIT_CONFIG_COUNT=$((config_count + 1))
        if [[ "$(git ls-remote --get-url https://github.com/)" != "${GITHUB_PROXY}https://github.com/" ]]; then
            log_error 'Cannot apply GitHub proxy; use Git 2.31+, resolve conflicting Git URL rewrites, or leave github_proxy empty.'
            return 1
        fi
        log_info "GitHub Git 加速前缀：$GITHUB_PROXY" >&2
    fi
    helper_pid=$(exec /bin/sh -c 'printf "%s\n" "$PPID"')
    trap '
        trap "" HUP INT TERM ALRM
        for pid in $download_pid $timer_pid; do
            kill -TERM -- "-$pid" 2>/dev/null || :
        done
        sleep 1
        for pid in $download_pid $timer_pid; do
            kill -KILL -- "-$pid" 2>/dev/null || :
            wait "$pid" 2>/dev/null || :
        done
    ' EXIT
    trap 'exit 1' HUP INT TERM
    trap 'log_error "Git download timed out after $git_timeout seconds; adjust git_timeout or check network/proxy access."; exit 1' ALRM
    # Separate process groups let cleanup include grandchildren, not just git itself.
    set -m
    (
        # Zsh read -d changes terminal attributes even when reading a file.
        trap '' TTOU
        exec "$@"
    ) </dev/null &
    download_pid=$!
    (
        trap - EXIT HUP INT TERM ALRM
        set +m
        sleep "$git_timeout"
        kill -ALRM "$helper_pid" 2>/dev/null || :
    ) &
    timer_pid=$!
    set +m
    wait "$download_pid" 2>/dev/null || return 1
)

download_file() {
    local total_timeout=${3:-300} url=$1
    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*)
            if [[ -n "${GITHUB_PROXY:-}" ]]; then
                log_info "下载来源：$url"
                url="$GITHUB_PROXY$url"
                log_info "加速请求：$url"
            fi
            ;;
    esac
    if have curl; then
        curl --fail --location --proto '=https' --tlsv1.2 \
            --connect-timeout 15 --speed-limit 1 --speed-time 60 \
            --max-time "$total_timeout" --retry 2 --retry-max-time 300 \
            --output "$2" "$url" || { log_error "Download failed or timed out: $url"; return 1; }
    elif have wget; then
        # -T/-t also work with BusyBox wget (-t is ignored there; it does not retry).
        wget -T 30 -t 3 -O "$2" "$url" || { log_error "Download failed or timed out: $url"; return 1; }
    else
        log_warn 'Download requires curl or wget; select the base module first.'
        return 2
    fi
}

approve_remote() {
    local label=$1 source_url=$2 answer
    log_info "$label 来源：$source_url"
    if [ "$ALLOW_REMOTE" -eq 1 ]; then return 0; fi
    if [ "$INTERACTIVE" -eq 0 ]; then
        record_result skipped "$label" '未授权直接上游下载。' \
            '确认所列来源后，使用 allow_remote=true 或 --allow-remote 重试对应模块。'
        return 2
    fi
    printf '允许从上述来源安装 %s？[y/N] ' "$label"
    if ! IFS= read -r answer; then
        record_result skipped "$label" '未读取到授权确认，未执行安装。'
        return 2
    fi
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) record_result skipped "$label" '本次未授权安装。'; return 2 ;;
    esac
}

run_remote_installer() {
    local label=$1 source_url=$2 installer checksum result=0
    shift 2
    if [ "$INTERACTIVE" -eq 0 ] && [ "$ALLOW_REMOTE" -eq 0 ]; then
        approve_remote "$label" "$source_url"
        return $?
    fi
    mkdir -p "$XDG_CACHE_HOME/oh-my-devboom" || {
        record_result failed "$label" "无法创建安装器缓存：$XDG_CACHE_HOME/oh-my-devboom" '检查缓存目录的权限和可用空间。'
        return 1
    }
    installer=$(mktemp "$XDG_CACHE_HOME/oh-my-devboom/installer.XXXXXX") || {
        record_result failed "$label" "无法在 $XDG_CACHE_HOME/oh-my-devboom 创建临时安装器。" '检查缓存目录的权限和可用空间。'
        return 1
    }
    download_file "$source_url" "$installer" || result=$?
    if [[ "$result" != 0 ]]; then
        rm -f "$installer"
        if [[ "$result" == 2 ]]; then
            record_result skipped "$label" '缺少 curl 或 wget，无法下载安装器。' '先完成 base 模块。'
        else
            record_result failed "$label" "安装器下载失败：$source_url" '检查上方下载错误、网络和代理设置后重试。'
        fi
        return "$result"
    fi
    log_info "可检查 $label 安装脚本：$installer"
    if have sha256sum; then
        checksum=$(sha256sum "$installer") || {
            record_result failed "$label" "无法计算安装器 SHA256：$installer"
            return 1
        }
        log_info "SHA256: ${checksum%% *}"
    elif have shasum; then
        checksum=$(shasum -a 256 "$installer") || {
            record_result failed "$label" "无法计算安装器 SHA256：$installer"
            return 1
        }
        log_info "SHA256: ${checksum%% *}"
    else
        log_warn '缺少 SHA256 工具；请在授权前检查已下载的安装脚本。'
    fi
    approve_remote "$label" "$source_url" || return $?
    /bin/bash "$installer" "$@" || {
        result=$?
        record_result failed "$label" "上游安装器退出码 ${result}；脚本保留在 $installer" \
            '检查上方安装器输出，处理对应错误后重试该模块。'
        return 1
    }
}
