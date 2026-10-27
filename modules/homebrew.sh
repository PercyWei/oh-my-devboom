#!/usr/bin/env bash

module_homebrew() {
    local prefix parent result=0
    if [[ "$USER_ID" == 0 ]]; then
        log_warn "Homebrew 不以 root 身份安装或运行；跳过。容器可使用系统包管理器。"
        return 2
    fi
    activate_brew || result=$?
    if [[ "$result" == 0 ]]; then
        if [[ "$OS" == macos || "$PACKAGE_MANAGER" == none ]]; then PACKAGE_MANAGER=brew; fi
        log_info "Homebrew 已安装。"
        return 0
    fi
    if [[ "$result" == 1 ]]; then log_error '无法加载已有 Homebrew 环境。'; return 1; fi
    if [[ "$OS" == linux && "$IN_CONTAINER" == 1 ]]; then
        log_warn "Linux 容器默认跳过 Homebrew；使用系统包管理器或用户目录中的工具。"
        return 2
    fi
    case "$ARCH" in
        x86_64|aarch64) ;;
        *) log_warn "Homebrew 模块不支持架构 $ARCH；跳过。"; return 2 ;;
    esac
    if ! have git || ! have curl; then
        log_warn "安装 Homebrew 需要 git 和 curl；请先完成 base 模块或手动安装。"
        return 2
    fi
    if [[ "$OS" == macos ]]; then
        if ! xcode-select -p >/dev/null 2>&1; then
            log_warn "未找到 Xcode Command Line Tools；请先运行 xcode-select --install，再重试 Homebrew。"
            return 2
        fi
        if [[ "$ARCH" == aarch64 ]]; then
            prefix=/opt/homebrew
        else
            prefix=/usr/local
        fi
    else
        if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
            log_warn "Homebrew Linux 安装需要 glibc；musl/Alpine 等环境请使用系统包管理器。"
            return 2
        fi
        if ! have make || { ! have gcc && ! have clang; }; then
            log_warn "Homebrew Linux 安装需要 make 和 C 编译器；请先安装发行版的开发工具。"
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
        log_warn "无法写入 Homebrew 默认路径 $prefix，且无 sudo 权限；跳过。"
        return 2
    fi
    if [[ ! -w "$parent" && "$INTERACTIVE" == 0 ]] && ! sudo -n true 2>/dev/null; then
        log_warn "Homebrew 默认路径 $prefix 需要提权，但非交互 sudo 不可用；跳过。"
        return 2
    fi
    if [[ "$INTERACTIVE" == 0 ]]; then
        NONINTERACTIVE=1 run_remote_installer Homebrew \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || return $?
    else
        run_remote_installer Homebrew \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || return $?
    fi
    activate_brew || { log_error "Homebrew 安装完成后仍未找到 brew。"; return 1; }
    if [[ "$OS" == macos || "$PACKAGE_MANAGER" == none ]]; then PACKAGE_MANAGER=brew; fi
    log_info "Homebrew PATH 已在本次执行中生效；dotfiles 模块为后续 Zsh 会话配置 PATH。"
}
