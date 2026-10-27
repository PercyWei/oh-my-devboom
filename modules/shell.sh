#!/usr/bin/env bash

read_login_shell() {
    local entry
    case "$OS" in
        linux)
            if have getent; then
                entry=$(getent passwd "$USER_ID") || return 1
            else
                entry=$(awk -F: -v uid="$USER_ID" '$3 == uid { print; exit }' /etc/passwd) || return 1
            fi
            [[ -n "$entry" ]] || return 1
            printf '%s\n' "${entry##*:}"
            ;;
        macos)
            entry=$(dscl . -read "/Users/$1" UserShell) || return 1
            printf '%s\n' "$entry" | awk '$1 == "UserShell:" { print $2; found=1; exit } END { exit !found }'
            ;;
    esac
}

module_shell() {
    local account current_shell candidate target='' result=0
    local shells_file=${SHELLS_FILE:-/etc/shells}
    account=$(id -un) || {
        record_result failed '登录 Shell' '无法识别当前执行账户。'
        return 1
    }
    current_shell=$(read_login_shell "$account") || {
        record_result failed '登录 Shell' "无法读取账户 ${account} 的登录 Shell。" '检查系统账户信息后重试 shell 模块。'
        return 1
    }
    if [[ "$current_shell" == */zsh && -f "$current_shell" && -x "$current_shell" ]]; then
        record_result ready '登录 Shell' "${account} 已使用 ${current_shell}。"
        return 0
    fi
    if [[ ! -r "$shells_file" ]]; then
        record_result skipped '登录 Shell' "无法读取已登记的 Shell 列表：$shells_file" '请由管理员检查系统 Shell 登记文件。'
        return 2
    fi
    while IFS= read -r candidate || [[ -n "$candidate" ]]; do
        candidate=${candidate%%#*}
        candidate=${candidate#"${candidate%%[![:space:]]*}"}
        candidate=${candidate%"${candidate##*[![:space:]]}"}
        if [[ "$candidate" == /* && "$candidate" == */zsh && -f "$candidate" && -x "$candidate" ]]; then
            target=$candidate
            break
        fi
    done < "$shells_file"
    if [[ -z "$target" ]]; then
        record_result skipped '登录 Shell' "未在 ${shells_file} 中找到已登记且可执行的 Zsh。" '先安装并登记 Zsh，再重试 shell 模块。'
        return 2
    fi
    if ! have chsh; then
        record_result skipped '登录 Shell' '未找到 chsh 命令。' '请由管理员安装 chsh，或使用系统提供的账户管理工具。'
        return 2
    fi
    if [[ "$INTERACTIVE" == 1 ]]; then
        chsh -s "$target" "$account" || result=1
    elif [[ "$USER_ID" == 0 ]]; then
        chsh -s "$target" "$account" </dev/null || result=1
    else
        run_privileged chsh -s "$target" "$account" </dev/null || result=$?
    fi
    if [[ "$result" == 2 ]]; then
        record_result skipped '登录 Shell' '非交互模式下没有可用的免密 sudo 权限。' '去掉 --non-interactive 后重试 shell 模块，或由管理员修改登录 Shell。'
        return 2
    elif [[ "$result" != 0 ]]; then
        record_result failed '登录 Shell' "chsh 未能将账户 ${account} 的登录 Shell 设置为 ${target}。" '检查上方 chsh 错误及账户权限后重试 shell 模块。'
        return 1
    fi
    current_shell=$(read_login_shell "$account") || {
        record_result failed '登录 Shell' "chsh 执行后无法读取账户 ${account} 的登录 Shell，未确认修改结果。"
        return 1
    }
    if [[ "$current_shell" != "$target" ]]; then
        record_result failed '登录 Shell' "chsh 执行后账户 ${account} 的登录 Shell 仍为 ${current_shell:-空}，未确认修改成功。"
        return 1
    fi
    record_result configured '登录 Shell' "${account} 的登录 Shell 已设为 ${target}，重新登录后生效。"
}
