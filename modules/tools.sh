#!/usr/bin/env bash

install_zellij() {
    if have brew && [[ "$USER_ID" != 0 ]]; then
        PACKAGE_MANAGER=brew ensure_packages zellij
        return $?
    fi
    if [[ "$PACKAGE_MANAGER" == pacman ]]; then
        ensure_packages zellij
        return $?
    fi
    local target sha256 url staging checksum result=0
    case "$OS:$ARCH" in
        linux:x86_64)
            target=x86_64-unknown-linux-musl
            sha256=40bcc2e03f5d5ae8e054e39f676081fe12ab70871506996ba595834c3718eefc ;;
        linux:aarch64)
            target=aarch64-unknown-linux-musl
            sha256=05f0802afadd53f8db9514e7cae53c9ae8432fed1b35b8294aa816ee3044a16b ;;
        macos:x86_64)
            target=x86_64-apple-darwin
            sha256=8e8bea22737d1652278c51fc5c26c7c22c9855d0ebb9634a84b8873823093114 ;;
        macos:aarch64)
            target=aarch64-apple-darwin
            sha256=c029ba4fe1927b79ad9f0cdd59155c4dff80777863c85857d4d09b88b56f9891 ;;
        *) log_warn "Zellij 发布包不支持当前平台：$OS/$ARCH"; return 2 ;;
    esac
    if [[ -e "$HOME/.local/bin/zellij" || -L "$HOME/.local/bin/zellij" ]]; then
        log_warn "保留现有文件，跳过 Zellij：$HOME/.local/bin/zellij"
        return 2
    fi
    url="https://github.com/zellij-org/zellij/releases/download/v0.45.1/zellij-$target.tar.gz"
    approve_remote 'Zellij v0.45.1' "$url" || return $?
    ensure_packages tar || return $?
    if ! have sha256sum && ! have shasum; then
        log_warn '安装 Zellij 发布包需要 sha256sum 或 shasum 校验 SHA256。'
        return 2
    fi
    mkdir -p "$XDG_CACHE_HOME/oh-my-devboom" "$HOME/.local/bin" || return 1
    staging=$(mktemp -d "$XDG_CACHE_HOME/oh-my-devboom/zellij.XXXXXX") || return 1
    download_file "$url" "$staging/archive.tar.gz" || result=$?
    if [[ "$result" != 0 ]]; then rm -rf -- "$staging"; return "$result"; fi
    if have sha256sum; then
        checksum=$(sha256sum "$staging/archive.tar.gz") || result=1
    else
        checksum=$(shasum -a 256 "$staging/archive.tar.gz") || result=1
    fi
    if [[ "$result" != 0 || "${checksum%% *}" != "$sha256" ]]; then
        log_error 'Zellij SHA256 校验失败，停止安装。'
        rm -rf -- "$staging"
        return 1
    fi
    if ! tar -xzf "$staging/archive.tar.gz" -C "$staging" zellij ||
        ! chmod +x "$staging/zellij" ||
        ! mv -- "$staging/zellij" "$HOME/.local/bin/zellij"; then
        rm -rf -- "$staging"
        return 1
    fi
    rm -rf -- "$staging"
    log_info 'Zellij 已安装到 ~/.local/bin；运行 zellij 启动会话。'
}

module_tools() {
    local tool result status=0
    for tool in $TOOLS; do
        if have "$tool" || { [[ "$tool" == bat ]] && have batcat; } ||
            { [[ "$tool" == fd ]] && have fdfind; }; then
            log_info "$tool 已安装。"
            continue
        fi
        result=0
        if [[ "$tool" == uv ]]; then
            if have brew && [[ "$USER_ID" != 0 ]]; then
                PACKAGE_MANAGER=brew ensure_packages uv || result=$?
            else
                UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 \
                    run_remote_installer uv https://astral.sh/uv/install.sh || result=$?
                if [[ "$result" == 0 ]]; then
                    export PATH="$HOME/.local/bin:$PATH"
                    have uv || { log_error "安装后未找到 uv。"; result=1; }
                fi
            fi
        elif [[ "$tool" == zellij ]]; then
            install_zellij || result=$?
        elif [[ "$tool" == nvtop && "$OS" == macos && "$ARCH" != aarch64 ]]; then
            log_warn 'NVTOP 的 macOS 后端仅支持 Apple GPU；当前架构跳过安装。'
            result=2
        else
            ensure_packages "$tool" || result=$?
        fi
        if [[ "$result" == 1 ]]; then
            status=1
        elif [[ "$result" == 2 && "$status" == 0 ]]; then
            status=2
        fi
    done
    return "$status"
}
