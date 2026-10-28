#!/usr/bin/env bash

activate_brew() {
    local brew_bin=''
    if have brew; then
        brew_bin=$(command -v brew)
    elif [ "$OS" = macos ]; then
        if [ -x /opt/homebrew/bin/brew ]; then brew_bin=/opt/homebrew/bin/brew
        elif [ -x /usr/local/bin/brew ]; then brew_bin=/usr/local/bin/brew; fi
    else
        if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then brew_bin=/home/linuxbrew/.linuxbrew/bin/brew
        elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then brew_bin=$HOME/.linuxbrew/bin/brew; fi
    fi
    [ -n "$brew_bin" ] || return 2
    local brew_env
    brew_env=$("$brew_bin" shellenv) || return 1
    eval "$brew_env"
}

detect_system() {
    case "$(uname -s)" in
        Linux) OS=linux ;;
        Darwin) OS=macos ;;
        *) log_error 'Unsupported platform: only Linux and macOS are supported.'; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) ARCH=x86_64 ;;
        arm64|aarch64) ARCH=aarch64 ;;
        *) ARCH=$(uname -m) ;;
    esac
    DISTRO=$OS
    if [ "$OS" = linux ] && [ -r "${OS_RELEASE_FILE:-/etc/os-release}" ]; then
        DISTRO=$(
            # shellcheck source=/dev/null
            . "${OS_RELEASE_FILE:-/etc/os-release}"
            printf '%s' "${ID:-linux}"
        )
    fi
    USER_ID=$(id -u)
    HAS_SUDO=0
    if have sudo; then HAS_SUDO=1; fi
    IN_CONTAINER=0
    if [ -e /.dockerenv ] || [ -e /run/.containerenv ] || [ -n "${container:-}" ] ||
        { [ "$OS" = linux ] && have systemd-detect-virt && systemd-detect-virt --container --quiet; }; then
        IN_CONTAINER=1
    fi
    activate_brew || true
    PACKAGE_MANAGER=none
    if [ "$OS" = macos ]; then
        if have brew; then PACKAGE_MANAGER=brew; fi
    else
        local manager
        for manager in apt-get dnf yum pacman zypper apk brew; do
            if have "$manager"; then PACKAGE_MANAGER=$manager; break; fi
        done
    fi
    PACKAGES_REFRESHED=0
}
