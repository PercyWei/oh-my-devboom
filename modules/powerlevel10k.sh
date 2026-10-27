#!/usr/bin/env bash

module_powerlevel10k() {
    local theme_dir="$XDG_DATA_HOME/oh-my-devboom/powerlevel10k"
    local theme_commit=d05a1b00f9a61f9578bf9dc19b8451942dde8734
    local cache="$XDG_CACHE_HOME/oh-my-devboom/gitstatus"
    local platform sha256 daemon daemon_url staging checksum result=0 RECORD_PACKAGE_RESULTS=0

    ensure_packages zsh git || return $?
    if ! zsh -f -c '[[ $ZSH_VERSION == (5.<1->*|<6->.*) ]]'; then
        record_result skipped Powerlevel10k '当前 Zsh 不满足 5.1 或更新版本的要求。' '升级 Zsh 后重试 powerlevel10k 模块。'
        return 2
    fi
    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        if [[ ! -f "$theme_dir/powerlevel10k.zsh-theme" ]] ||
            [[ "$(git -C "$theme_dir" rev-parse HEAD 2>/dev/null)" != "$theme_commit" ]]; then
            record_result skipped Powerlevel10k "现有目录与固定提交 ${theme_commit:0:7} 不符，已保留：$theme_dir" '检查并自行整理现有目录后，重试 powerlevel10k 模块。'
            return 2
        fi
        record_result ready Powerlevel10k "固定提交 ${theme_commit:0:7}；$theme_dir"
    fi
    # SHA256 comes from gitstatus/install.info at the pinned Powerlevel10k commit.
    case "$OS:$ARCH" in
        macos:aarch64)
            platform=darwin-arm64
            sha256=eae979e990ca37c56ee39fadd0c3f392cbbd0c6bdfb9a603010be60d9e48910a
            ;;
        macos:x86_64)
            platform=darwin-x86_64
            sha256=9fd3913ec1b6b856ab6e08a99a2343f0e8e809eb6b62ca4b0963163656c668e6
            ;;
        linux:aarch64)
            platform=linux-aarch64
            sha256=32b57eb28bf6d80b280e4020a0045184f8ca897b20b570c12948aa6838673225
            ;;
        linux:x86_64)
            platform=linux-x86_64
            sha256=9633816e7832109e530c9e2532b11a1edae08136d63aa7e40246c0339b7db304
            ;;
        *)
            record_result skipped gitstatusd "当前平台没有配置预编译包，无法完成主题安装：$OS/$ARCH"
            return 2
            ;;
    esac
    daemon=gitstatusd-$platform
    daemon_url="https://github.com/romkatv/gitstatus/releases/download/v1.5.4/$daemon.tar.gz"
    if [[ -d "$theme_dir" && -x "$cache/$daemon" ]]; then
        record_result ready gitstatusd "缓存已就绪：$cache/$daemon"
        return 0
    fi
    if [[ -e "$cache/$daemon" || -L "$cache/$daemon" ]] && [[ ! -x "$cache/$daemon" ]]; then
        record_result skipped gitstatusd "现有缓存不可执行，已保留：$cache/$daemon" '检查缓存文件来源与执行权限后重试。'
        return 2
    fi
    if [[ ! -x "$cache/$daemon" ]]; then
        ensure_packages tar || return $?
        if ! have sha256sum && ! have shasum; then
            record_result skipped gitstatusd '缺少 SHA-256 校验工具，尚未下载发布包。' '安装 sha256sum 或 shasum 后重试。'
            return 2
        fi
    fi
    approve_remote 'Powerlevel10k 与 gitstatusd' \
        "https://github.com/romkatv/powerlevel10k/tree/${theme_commit}；$daemon_url" || return $?
    mkdir -p "$XDG_DATA_HOME/oh-my-devboom" "$cache" || {
        record_result failed Powerlevel10k "无法创建安装或缓存目录：$XDG_DATA_HOME/oh-my-devboom、$cache" '检查目录权限和可用磁盘空间。'
        return 1
    }
    if [[ ! -d "$theme_dir" ]]; then
        staging="$(mktemp -d "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k.XXXXXX")" || {
            record_result failed Powerlevel10k "无法在 $XDG_DATA_HOME/oh-my-devboom 创建临时目录。" '检查目录权限和可用磁盘空间。'
            return 1
        }
        if ! git init -q "$staging" ||
            ! git -C "$staging" remote add origin https://github.com/romkatv/powerlevel10k.git ||
            ! run_git_download git -C "$staging" fetch --depth 1 origin "$theme_commit" ||
            ! git -C "$staging" checkout -q --detach "$theme_commit"; then
            rm -rf -- "$staging"
            record_result failed Powerlevel10k "获取或检出固定提交 ${theme_commit:0:7} 失败。" '检查上方 Git 错误、网络和 github_proxy；下载过慢时可调整 git_timeout。'
            return 1
        fi
        mv -- "$staging" "$theme_dir" || {
            rm -rf -- "$staging"
            record_result failed Powerlevel10k "无法将下载内容部署到 ${theme_dir}。" '检查目录权限和可用磁盘空间。'
            return 1
        }
        record_result installed Powerlevel10k "固定提交 ${theme_commit:0:7}；$theme_dir"
    fi
    if [[ ! -x "$cache/$daemon" ]]; then
        staging="$(mktemp -d "$cache/install.XXXXXX")" || {
            record_result failed gitstatusd "无法在 $cache 创建临时目录。" '检查缓存目录权限和可用磁盘空间。'
            return 1
        }
        result=0
        download_file "$daemon_url" "$staging/archive.tar.gz" || result=$?
        if [[ "$result" != 0 ]]; then
            rm -rf -- "$staging"
            if [[ "$result" == 2 ]]; then
                record_result skipped gitstatusd '缺少 curl 或 wget，尚未下载发布包。' '先完成 base 模块或安装下载工具。'
            else
                record_result failed gitstatusd "发布包下载失败或超时：$daemon_url" '检查上方下载错误、网络和 github_proxy。'
            fi
            return "$result"
        fi
        if have sha256sum; then
            checksum="$(sha256sum "$staging/archive.tar.gz")" || result=1
        else
            checksum="$(shasum -a 256 "$staging/archive.tar.gz")" || result=1
        fi
        if [[ "$result" != 0 || "${checksum%% *}" != "$sha256" ]]; then
            record_result failed gitstatusd '发布包 SHA-256 校验失败，已停止安装并清理下载文件。' '核对上游发布包及代理返回的内容后重试。'
            rm -rf -- "$staging"
            return 1
        fi
        if ! tar -xzf "$staging/archive.tar.gz" -C "$staging" "$daemon" ||
            ! chmod +x "$staging/$daemon" ||
            ! mv -- "$staging/$daemon" "$cache/$daemon"; then
            rm -rf -- "$staging"
            record_result failed gitstatusd "解压、设置执行权限或部署失败；目标：$cache/$daemon" '检查上方命令错误、缓存目录权限和可用磁盘空间。'
            return 1
        fi
        rm -rf -- "$staging"
        record_result installed gitstatusd "v1.5.4，SHA-256 校验通过；$cache/$daemon"
    else
        record_result ready gitstatusd "缓存已就绪：$cache/$daemon"
    fi
    log_info 'Powerlevel10k 与 gitstatusd 已就绪；dotfiles 模块部署提示符预设。'
}
