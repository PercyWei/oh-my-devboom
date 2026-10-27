#!/usr/bin/env bash

module_zsh() {
    local antidote_dir="$XDG_DATA_HOME/oh-my-devboom/antidote"
    local antidote_commit=9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14
    local plugins="$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt"
    local cache="$XDG_CACHE_HOME/oh-my-devboom"
    local staging result

    ensure_packages zsh git || return $?
    [[ -f "$plugins" ]] || plugins="$ROOT_DIR/config/zsh/zsh_plugins.txt"
    if [[ -e "$antidote_dir" || -L "$antidote_dir" ]]; then
        if [[ ! -f "$antidote_dir/antidote.zsh" ]] ||
            [[ "$(git -C "$antidote_dir" rev-parse HEAD 2>/dev/null)" != "$antidote_commit" ]]; then
            log_warn "Antidote 目录与固定版本不符，保留现有内容：$antidote_dir"
            return 2
        fi
        if [[ -f "$cache/zsh_plugins.zsh" && "$cache/zsh_plugins.zsh" -nt "$plugins" ]]; then
            log_info "Zsh、Antidote 与静态插件配置已就绪。"
            return 0
        fi
    fi
    approve_remote "Antidote v2.3.0 与 Zsh 插件" \
        "https://github.com/mattmc3/antidote/tree/$antidote_commit；插件源及固定提交见 $plugins" || return $?
    mkdir -p "$XDG_DATA_HOME/oh-my-devboom" "$cache" || return 1
    if [[ ! -d "$antidote_dir" ]]; then
        staging="$(mktemp -d "$XDG_DATA_HOME/oh-my-devboom/antidote.XXXXXX")" || return 1
        if ! run_git_download git clone --depth 1 --branch v2.3.0 \
            https://github.com/mattmc3/antidote.git "$staging"; then
            rm -rf -- "$staging"
            return 1
        fi
        if [[ "$(git -C "$staging" rev-parse HEAD)" != "$antidote_commit" ]]; then
            log_error "Antidote v2.3.0 与预期提交不符，停止安装。"
            rm -rf -- "$staging"
            return 1
        fi
        mv -- "$staging" "$antidote_dir" || return 1
    fi
    staging="$(mktemp "$cache/zsh_plugins.XXXXXX")" || return 1
    result=0
    ANTIDOTE_HOME="$XDG_DATA_HOME/oh-my-devboom/plugins" \
        run_git_download zsh -f -c 'source "$1/antidote.zsh" && antidote bundle < "$2"' \
        oh-my-devboom "$antidote_dir" "$plugins" > "$staging" || result=$?
    if [[ "$result" != 0 ]]; then
        rm -f -- "$staging"
        return 1
    fi
    mv -- "$staging" "$cache/zsh_plugins.zsh" || return 1
    log_info "Zsh 插件已固定提交并生成静态配置；dotfiles 模块部署启动文件。默认登录 Shell 不自动修改。"
}
