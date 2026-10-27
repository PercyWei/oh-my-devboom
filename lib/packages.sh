#!/usr/bin/env bash

run_privileged() {
    if [ "$USER_ID" -eq 0 ]; then
        "$@" || return 1
    elif [ "$HAS_SUDO" -eq 0 ]; then
        log_warn "Cannot run $1: root or sudo access is required."
        return 2
    elif [ "$INTERACTIVE" -eq 1 ]; then
        sudo "$@" || return 1
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@" || return 1
    else
        log_warn "Cannot run $1: non-interactive sudo access is unavailable."
        return 2
    fi
}

ensure_packages() {
    local cmd package missing=() result=0
    for cmd in "$@"; do
        if have "$cmd" || { [ "$cmd" = bat ] && have batcat; } ||
            { [ "$cmd" = fd ] && have fdfind; }; then continue; fi
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
        missing+=("$package")
    done
    if [ "${#missing[@]}" -eq 0 ]; then return 0; fi
    if [ "$PACKAGE_MANAGER" = none ]; then
        log_warn "No supported package manager; missing: ${missing[*]}"
        return 2
    fi
    log_info "Installing with $PACKAGE_MANAGER: ${missing[*]}"
    case "$PACKAGE_MANAGER" in
        apt-get)
            if [ "$PACKAGES_REFRESHED" -eq 0 ]; then
                run_privileged apt-get update || return $?
                PACKAGES_REFRESHED=1
            fi
            run_privileged apt-get install -y "${missing[@]}" || result=$?
            ;;
        dnf|yum) run_privileged "$PACKAGE_MANAGER" install -y "${missing[@]}" || result=$? ;;
        pacman) run_privileged pacman -S --needed --noconfirm "${missing[@]}" || result=$? ;;
        zypper) run_privileged zypper --non-interactive install "${missing[@]}" || result=$? ;;
        apk) run_privileged apk add "${missing[@]}" || result=$? ;;
        brew)
            if [ "$USER_ID" -eq 0 ]; then log_warn 'Homebrew cannot install packages as root.'; return 2; fi
            brew install "${missing[@]}" || result=1
            ;;
    esac
    return "$result"
}
