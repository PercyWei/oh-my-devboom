#!/usr/bin/env bash

module_homebrew() {
    local prefix parent result=0
    if [[ "$USER_ID" == 0 ]]; then
        record_result skipped Homebrew '当前以 root 身份运行。' '使用系统包管理器；如需 Homebrew，请在受支持的宿主机上以普通用户运行。'
        return 2
    fi
    activate_brew || result=$?
    if [[ "$result" == 0 ]]; then
        if [[ "$OS" == macos || "$PACKAGE_MANAGER" == none ]]; then PACKAGE_MANAGER=brew; fi
        record_result ready Homebrew "已复用 $(command -v brew)，PATH 已在本次执行中生效。"
        return 0
    fi
    if [[ "$result" == 1 ]]; then
        record_result failed Homebrew '已有 brew 的 shellenv 执行失败，无法加载环境。' '检查 brew shellenv 的错误输出并修复现有 Homebrew。'
        return 1
    fi
    if [[ "$OS" == linux && "$IN_CONTAINER" == 1 ]]; then
        record_result skipped Homebrew '当前为 Linux 容器。' '使用容器的系统包管理器或用户目录中的工具。'
        return 2
    fi
    case "$ARCH" in
        x86_64|aarch64) ;;
        *) record_result skipped Homebrew "安装模块不支持当前架构：${ARCH}。"; return 2 ;;
    esac
    if ! have git || ! have curl; then
        record_result skipped Homebrew '缺少安装依赖 git 或 curl。' '先完成 base 模块，或手动安装 git 和 curl。'
        return 2
    fi
    if [[ "$OS" == macos ]]; then
        if ! xcode-select -p >/dev/null 2>&1; then
            record_result skipped Homebrew '未找到 Xcode Command Line Tools。' '运行 xcode-select --install，完成后重试 Homebrew 模块。'
            return 2
        fi
        if [[ "$ARCH" == aarch64 ]]; then
            prefix=/opt/homebrew
        else
            prefix=/usr/local
        fi
    else
        if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
            record_result skipped Homebrew '未检测到所需的 glibc 环境。' 'musl/Alpine 等环境请使用系统包管理器。'
            return 2
        fi
        if ! have make || { ! have gcc && ! have clang; }; then
            record_result skipped Homebrew '缺少 make 或 C 编译器（gcc / clang）。' '先通过发行版包管理器安装开发工具。'
            return 2
        fi
        prefix=/home/linuxbrew/.linuxbrew
    fi
    parent="$prefix"
    while [[ ! -e "$parent" && "$parent" != / ]]; do
        parent="${parent%/*}"
        [[ -n "$parent" ]] || parent=/
    done
    if [[ ! -w "$parent" && "$HAS_SUDO" == 0 ]]; then
        record_result skipped Homebrew "无法写入 ${prefix}，且未找到 sudo。" '使用有安装权限的普通用户重试。'
        return 2
    fi
    if [[ ! -w "$parent" && "$INTERACTIVE" == 0 ]] && ! sudo -n true 2>/dev/null; then
        record_result skipped Homebrew "$prefix 需要提权，但非交互 sudo 不可用。" '去掉 --non-interactive，以便输入 sudo 密码。'
        return 2
    fi
    if [[ "$INTERACTIVE" == 0 ]]; then
        NONINTERACTIVE=1 run_remote_installer Homebrew \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || return $?
    else
        run_remote_installer Homebrew \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || return $?
    fi
    activate_brew || {
        record_result failed Homebrew '上游安装器已退出，但 brew 环境仍无法加载。' "检查上方安装输出及安装目录 ${prefix}。"
        return 1
    }
    if [[ "$OS" == macos || "$PACKAGE_MANAGER" == none ]]; then PACKAGE_MANAGER=brew; fi
    record_result installed Homebrew "$(command -v brew)；PATH 已在本次执行中生效，后续 Zsh 会话由 dotfiles 配置。"
}
