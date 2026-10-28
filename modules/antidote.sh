#!/usr/bin/env bash

module_antidote() {
    local antidote_dir="$XDG_DATA_HOME/oh-my-devboom/antidote"
    local antidote_commit=9bb69ab99c6f05d6e6ae237f7ce222eeeb5b4a14
    local plugins="${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
    local cache="$XDG_CACHE_HOME/oh-my-devboom"
    local staging result=0 RECORD_PACKAGE_RESULTS=0

    ensure_packages zsh git || return $?
    if [[ -e "$antidote_dir" || -L "$antidote_dir" ]]; then
        if [[ ! -f "$antidote_dir/antidote.zsh" || ! -f "$antidote_dir/functions/antidote-load" ]] ||
            [[ "$(git -C "$antidote_dir" rev-parse HEAD 2>/dev/null)" != "$antidote_commit" ]]; then
            record_result skipped Antidote "现有目录不完整或与固定版本 v2.3.0 不符，已保留：$antidote_dir" '检查并自行整理现有目录后，重试 antidote 模块。'
            return 2
        fi
        record_result ready Antidote "v2.3.0，固定提交 ${antidote_commit:0:7}；$antidote_dir"
    fi
    # 清单只初始化一次；已有文件软链接保留当前内容并转为普通文件。
    if [[ ! -e "$plugins" && ! -L "$plugins" ]] || [[ -L "$plugins" && -f "$plugins" ]]; then
        deploy_config "$ROOT_DIR/config/zsh/zsh_plugins.txt" "$plugins" || return $?
        # 不继承仓库旧时间戳，让 Antidote 识别新清单。
        touch "$plugins" || return 1
    fi
    if [[ ! -f "$plugins" || ! -r "$plugins" ]]; then
        record_result failed 'Zsh 插件清单' "不是可读文件，已保留原路径：$plugins" '修复插件清单后重试。'
        return 1
    fi
    if [[ -d "$antidote_dir" && -f "$cache/plugins.zsh" && "$cache/plugins.zsh" -nt "$plugins" ]]; then
        record_result ready 'Zsh 插件' "静态配置已就绪；后续由 Antidote 管理：$plugins"
        return 0
    fi
    approve_remote "Antidote v2.3.0 与 Zsh 插件" \
        "https://github.com/mattmc3/antidote/tree/${antidote_commit}；插件源及固定提交见 $plugins" || return $?
    mkdir -p "$XDG_DATA_HOME/oh-my-devboom" "$cache" || {
        record_result failed 'Zsh 插件' "无法创建安装或缓存目录：$XDG_DATA_HOME/oh-my-devboom、$cache" '检查目录权限和可用磁盘空间。'
        return 1
    }
    if [[ ! -d "$antidote_dir" ]]; then
        staging="$(mktemp -d "$XDG_DATA_HOME/oh-my-devboom/antidote.XXXXXX")" || {
            record_result failed Antidote "无法在 $XDG_DATA_HOME/oh-my-devboom 创建临时目录。" '检查目录权限和可用磁盘空间。'
            return 1
        }
        if ! run_git_download git clone --depth 1 --branch v2.3.0 \
            https://github.com/mattmc3/antidote.git "$staging"; then
            rm -rf -- "$staging"
            record_result failed Antidote '下载 v2.3.0 失败或超时，尚未安装插件管理器。' '检查上方 Git 错误、网络和 github_proxy；下载过慢时可调整 git_timeout。'
            return 1
        fi
        if [[ "$(git -C "$staging" rev-parse HEAD)" != "$antidote_commit" ]]; then
            record_result failed Antidote "下载内容与预期提交 $antidote_commit 不符，已停止安装。" '核对上游版本及代理返回的内容。'
            rm -rf -- "$staging"
            return 1
        fi
        mv -- "$staging" "$antidote_dir" || {
            record_result failed Antidote "无法将下载内容部署到 ${antidote_dir}；临时目录：$staging" '检查目录权限和可用磁盘空间。'
            return 1
        }
        record_result installed Antidote "v2.3.0，固定提交 ${antidote_commit:0:7}；$antidote_dir"
    fi
    staging="$(mktemp "$cache/plugins.XXXXXX")" || {
        record_result failed 'Zsh 插件' "无法在 $cache 创建临时配置文件。" '检查缓存目录权限和可用磁盘空间。'
        return 1
    }
    result=0
    # Bash 重定向后直接执行 Antidote，避免嵌套 Zsh 重置 SIGTTOU 处理。
    ANTIDOTE_HOME="$XDG_DATA_HOME/oh-my-devboom/plugins" \
        run_git_download bash -c 'exec zsh -f "$1/antidote.zsh" bundle < "$2"' \
        oh-my-devboom "$antidote_dir" "$plugins" > "$staging" || result=$?
    if [[ "$result" != 0 ]]; then
        rm -f -- "$staging"
        record_result failed 'Zsh 插件' "下载插件或生成静态配置失败；插件清单：$plugins" '检查上方 Zsh / Git 错误、插件清单和网络；下载过慢时可调整 git_timeout。'
        return 1
    fi
    mv -- "$staging" "$cache/plugins.zsh" || {
        record_result failed 'Zsh 插件' "静态配置已生成，但无法部署到 $cache/plugins.zsh；临时文件：$staging" '检查缓存目录权限。'
        return 1
    }
    record_result configured 'Zsh 插件' "初始静态配置已准备；启动文件由 dotfiles 部署，后续由 Antidote 管理：$plugins"
}
