#!/usr/bin/env bash

run_privileged() {
    local result=0
    if [ "$USER_ID" -eq 0 ]; then
        "$@" || result=$?
    elif [ "$HAS_SUDO" -eq 0 ]; then
        log_warn "无法运行 $1：需要 root 或 sudo 权限。"
        return 2
    elif [ "$INTERACTIVE" -eq 1 ]; then
        sudo "$@" || result=$?
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@" || result=$?
    else
        log_warn "无法运行 $1：当前非交互模式下 sudo 不可用。"
        return 2
    fi
    if [ "$result" -ne 0 ]; then
        log_error "命令失败（退出码 ${result}）：$*"
        return 1
    fi
    return 0
}

ensure_packages() {
    local cmd package executable missing=() commands=() result=0 index
    local phase='安装软件包' reason='' action=''
    for cmd in "$@"; do
        case "$cmd" in
            rg) package=ripgrep ;;
            fd)
                case "$PACKAGE_MANAGER" in
                    apt-get|dnf|yum) package=fd-find ;;
                    *) package=fd ;;
                esac
                ;;
            *) package=$cmd ;;
        esac
        executable=''
        if have "$cmd"; then executable=$cmd
        elif [ "$cmd" = bat ] && have batcat; then executable=batcat
        elif [ "$cmd" = fd ] && have fdfind; then executable=fdfind
        fi
        if [ -n "$executable" ]; then
            if [ "${RECORD_PACKAGE_RESULTS:-1}" -eq 1 ]; then
                record_result ready "$cmd" "检测到 $executable 命令，复用当前安装。"
            fi
            continue
        fi
        missing+=("$package")
        commands+=("$cmd")
    done
    if [ "${#missing[@]}" -eq 0 ]; then return 0; fi
    if [ "$PACKAGE_MANAGER" = none ]; then
        result=2
        reason='未找到支持的包管理器。'
        action='请先准备系统包管理器，或手动安装缺少的命令后重试。'
    elif [ "$PACKAGE_MANAGER" = brew ] && [ "$USER_ID" -eq 0 ]; then
        result=2
        reason='Homebrew 不支持以 root 身份安装软件包。'
        action='请使用普通用户运行，或在容器中使用系统包管理器。'
    else
        log_info "使用 $PACKAGE_MANAGER 安装：${missing[*]}"
        case "$PACKAGE_MANAGER" in
            apt-get)
                if [ "$PACKAGES_REFRESHED" -eq 0 ]; then
                    phase='刷新软件包索引'
                    run_privileged apt-get update || result=$?
                    if [ "$result" -eq 0 ]; then PACKAGES_REFRESHED=1; fi
                fi
                if [ "$result" -eq 0 ]; then
                    phase='安装软件包'
                    run_privileged apt-get install -y "${missing[@]}" || result=$?
                fi
                ;;
            dnf|yum) run_privileged "$PACKAGE_MANAGER" install -y "${missing[@]}" || result=$? ;;
            pacman) run_privileged pacman -S --needed --noconfirm "${missing[@]}" || result=$? ;;
            zypper) run_privileged zypper --non-interactive install "${missing[@]}" || result=$? ;;
            apk) run_privileged apk add "${missing[@]}" || result=$? ;;
            brew) brew install "${missing[@]}" || result=1 ;;
        esac
        if [ "$result" -eq 2 ]; then
            if [ "$HAS_SUDO" -eq 0 ]; then
                reason='当前用户不是 root，且没有 sudo。'
                action='请由具备权限的账户安装所需软件包后重试。'
            else
                reason='非交互模式下 sudo 不可用。'
                action='请在终端中去掉 --non-interactive 后重试，以便输入 sudo 密码。'
            fi
        elif [ "$result" -ne 0 ]; then
            reason="$PACKAGE_MANAGER ${phase}失败，未确认该包安装完成。"
            action='请查看上方包管理器错误，处理权限、软件源或网络问题后重试本模块。'
        fi
    fi
    for ((index=0; index<${#missing[@]}; index++)); do
        cmd=${commands[$index]}
        package=${missing[$index]}
        case "$result" in
            0)
                if [ "${RECORD_PACKAGE_RESULTS:-1}" -eq 1 ]; then
                    record_result installed "$cmd" "$PACKAGE_MANAGER 已完成软件包 $package 的安装。"
                fi
                ;;
            2) record_result skipped "$cmd" "${reason}所需软件包：${package}。" "$action" ;;
            *) record_result failed "$cmd" "${reason}软件包：${package}。" "$action" ;;
        esac
    done
    return "$result"
}
