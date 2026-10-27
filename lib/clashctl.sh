#!/usr/bin/env bash

# 独立 Bash 运行上游实现，避免它的函数、变量和 Shell 选项影响 bootstrap。
set +e +u
set -o pipefail
umask 077

main() (
    if [[ "$1" == --stop ]]; then
        export CLASHCTL_HOME=$2 CLASHCTL_INSTALL_RUNNING=1
        # 失败安装可能尚未写入 format；清理时只加载命令，不触发数据迁移。
        source "$CLASHCTL_HOME/scripts/cmd/clashctl.sh" || return 1
        _service_check_conflict || return 1
        clashctl off --stop || return 1
        local state
        state=$(service_state) || return 1
        case "$state" in
            stopped|failed) return 0 ;;
            *) printf 'Clash 停止后状态未确认：%s\n' "$state" >&2; return 1 ;;
        esac
    fi
    export CLASHCTL_HOME=$1
    local config_file=$2 env_file=$3 source_file="$1/data/devboom-source.yaml"
    local pending_file="$1/data/.devboom-pending" retry_apply=0
    local staged_file current profile_path profile_url runtime_mode key
    local proxy_names=(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY)
    # shellcheck source=/dev/null
    source "$CLASHCTL_HOME/scripts/cmd/clashctl.sh" || return 1
    current=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META") || return 1
    if [[ -n "$current" && "$current" != devboom ]]; then
        printf 'Clash 当前选中了其他配置：%s；请自行切换至 devboom 后重试。\n' "$current" >&2
        return 1
    fi
    if ! "$BIN_YQ" -e '.tun.enable == false and .allow-lan == false and .external-ui == "" and .external-ui-url == ""' \
        "$CLASH_CONFIG_MIXIN" >/dev/null; then
        printf 'Clash Mixin 必须关闭 TUN、局域网访问和面板下载，请检查后重试；现有设置已保留。\n' >&2
        return 1
    fi
    if [[ -L "$CLASH_DATA_DIR" || ! -d "$CLASH_DATA_DIR" || -L "$source_file" ]]; then
        printf 'Clash 私有配置路径不可用：%s\n' "$source_file" >&2
        return 1
    fi
    profile_path=$("$BIN_YQ" '.profiles // [] | .[] | select(.name == "devboom") | .path' "$CLASH_PROFILES_META") || return 1
    profile_url=$("$BIN_YQ" '.profiles // [] | .[] | select(.name == "devboom") | .url' "$CLASH_PROFILES_META") || return 1
    # 安装路径限定为 URL 安全的 ASCII 字符；原始 YAML 路径可以含空格或中文。
    if [[ -n "$profile_path" && "$profile_url" != "file://$source_file" ]]; then
        printf '已存在其他来源的 devboom 配置，请自行整理后重试；现有配置已保留。\n' >&2
        return 1
    fi
    staged_file=$(mktemp "$CLASH_DATA_DIR/.devboom-source.XXXXXX") || return 1
    trap 'rm -f -- "$staged_file"' EXIT
    cp -- "$config_file" "$staged_file" && chmod 600 "$staged_file" || return 1
    # --raw 也会去 BOM/CRLF 并处理编码，比较相同的规范化内容才能避免重复更新。
    _normalize_sub_config "$staged_file" || return 1
    mv -f -- "$staged_file" "$source_file" || return 1
    trap - EXIT
    [[ ! -e "$pending_file" ]] || retry_apply=1
    if [[ -z "$profile_path" ]]; then
        touch "$pending_file" || return 1
        clashctl sub add --raw --name devboom --use "file://$source_file" || return 1
        retry_apply=0
    elif ! cmp -s -- "$source_file" "$profile_path"; then
        touch "$pending_file" || return 1
        clashctl sub update devboom --raw || return 1
        retry_apply=0
    fi
    # 上游可能已写入配置但未成功重启旧进程；保留标记，重试时重新应用。
    if [[ "$retry_apply" == 1 || "$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")" != devboom ]] ||
        ! cmp -s -- "$source_file" "$CLASH_CONFIG_BASE"; then
        touch "$pending_file" || return 1
        clashctl sub use devboom || return 1
    fi
    [[ -s "$CLASH_CONFIG_BASE" ]] || return 1
    clashctl on || return 1
    runtime_mode=$("$BIN_YQ" '.mode // "rule"' "$CLASH_CONFIG_RUNTIME") || return 1
    if [[ "$runtime_mode" == direct ]]; then
        printf 'Clash 当前为 direct 模式，请调整本地 YAML 或 Mixin 后重试。\n' >&2
        return 1
    fi
    rm -f -- "$pending_file" || return 1
    [[ -n "${https_proxy:-}" ]] || return 1
    curl --silent --show-error --proxy "$https_proxy" --noproxy '' \
        --head --fail --location --connect-timeout 10 --max-time 30 https://github.com/ >/dev/null || return 1
    for key in "${proxy_names[@]}"; do printf '%s\0' "${!key}"; done > "$env_file"
)

main "$@"
