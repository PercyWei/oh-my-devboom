#!/usr/bin/env bash

module_powerlevel10k() {
    local theme_dir="$XDG_DATA_HOME/oh-my-devboom/powerlevel10k"
    local theme_commit=d05a1b00f9a61f9578bf9dc19b8451942dde8734
    local cache="$XDG_CACHE_HOME/oh-my-devboom/gitstatus"
    local platform sha256 daemon daemon_url staging checksum result

    ensure_packages zsh git || return $?
    if ! zsh -f -c '[[ $ZSH_VERSION == (5.<1->*|<6->.*) ]]'; then
        log_warn 'Powerlevel10k 需要 Zsh 5.1 或更新版本。'
        return 2
    fi
    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        if [[ ! -f "$theme_dir/powerlevel10k.zsh-theme" ]] ||
            [[ "$(git -C "$theme_dir" rev-parse HEAD 2>/dev/null)" != "$theme_commit" ]]; then
            log_warn "Powerlevel10k 目录与固定版本不符，保留现有内容：$theme_dir"
            return 2
        fi
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
            log_warn "当前平台没有配置 gitstatusd 预编译包，跳过 Powerlevel10k：$OS/$ARCH"
            return 2
            ;;
    esac
    daemon=gitstatusd-$platform
    daemon_url="https://github.com/romkatv/gitstatus/releases/download/v1.5.4/$daemon.tar.gz"
    if [[ -d "$theme_dir" && -x "$cache/$daemon" ]]; then
        log_info 'Powerlevel10k 固定版本与 gitstatusd 已就绪。'
        return 0
    fi
    if [[ -e "$cache/$daemon" || -L "$cache/$daemon" ]] && [[ ! -x "$cache/$daemon" ]]; then
        log_warn "gitstatusd 缓存不可执行，保留现有内容：$cache/$daemon"
        return 2
    fi
    if [[ ! -x "$cache/$daemon" ]]; then
        ensure_packages tar || return $?
        if ! have sha256sum && ! have shasum; then
            log_warn '下载 gitstatusd 需要 sha256sum 或 shasum 校验 SHA256。'
            return 2
        fi
    fi
    approve_remote 'Powerlevel10k 与 gitstatusd' \
        "https://github.com/romkatv/powerlevel10k/tree/$theme_commit；$daemon_url" || return $?
    mkdir -p "$XDG_DATA_HOME/oh-my-devboom" "$cache" || return 1
    if [[ ! -d "$theme_dir" ]]; then
        staging="$(mktemp -d "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k.XXXXXX")" || return 1
        if ! git init -q "$staging" ||
            ! git -C "$staging" remote add origin https://github.com/romkatv/powerlevel10k.git ||
            ! run_git_download git -C "$staging" fetch --depth 1 origin "$theme_commit" ||
            ! git -C "$staging" checkout -q --detach "$theme_commit"; then
            rm -rf -- "$staging"
            return 1
        fi
        mv -- "$staging" "$theme_dir" || { rm -rf -- "$staging"; return 1; }
    fi
    if [[ ! -x "$cache/$daemon" ]]; then
        staging="$(mktemp -d "$cache/install.XXXXXX")" || return 1
        result=0
        download_file "$daemon_url" "$staging/archive.tar.gz" || result=$?
        if [[ "$result" != 0 ]]; then
            rm -rf -- "$staging"
            return "$result"
        fi
        if have sha256sum; then
            checksum="$(sha256sum "$staging/archive.tar.gz")" || result=1
        else
            checksum="$(shasum -a 256 "$staging/archive.tar.gz")" || result=1
        fi
        if [[ "$result" != 0 || "${checksum%% *}" != "$sha256" ]]; then
            log_error 'gitstatusd SHA256 校验失败，停止安装。'
            rm -rf -- "$staging"
            return 1
        fi
        if ! tar -xzf "$staging/archive.tar.gz" -C "$staging" "$daemon" ||
            ! chmod +x "$staging/$daemon" ||
            ! mv -- "$staging/$daemon" "$cache/$daemon"; then
            rm -rf -- "$staging"
            return 1
        fi
        rm -rf -- "$staging"
    fi
    log_info 'Powerlevel10k 与 gitstatusd 已安装；dotfiles 模块部署现有提示符预设，Shell 启动时不下载。'
}
