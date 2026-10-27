#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/system.sh"
source "$ROOT_DIR/lib/packages.sh"
source "$ROOT_DIR/lib/config.sh"

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options]

Set up a personal development environment on Linux or macOS (Bash 3.2+).

  --modules LIST    Comma-separated: base,homebrew,zsh,powerlevel10k,tools,dotfiles
                    Default: base,homebrew,zsh,powerlevel10k,dotfiles
  --tools LIST      Comma-separated: uv,fzf,rg,bat,eza,zoxide,zellij,nvtop,jq,fd
                    Default: all (unsupported tools are reported and skipped)
                    Used only when the tools module is selected.
  --yes             Run without prompts; required when stdin is not a terminal
  --allow-remote    Authorize remote installers, plugins and downloaded binaries
  --conflict POLICY Existing config: skip (default) or backup before linking
  --list-modules    Describe modules and exit
  -h, --help        Show this help and exit

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --yes --modules dotfiles
  ./bootstrap.sh --yes --allow-remote --modules base,zsh,powerlevel10k,tools,dotfiles
  ./bootstrap.sh --yes --modules dotfiles --conflict backup
EOF
}

list_modules() {
    cat <<'EOF'
base       Install git, curl, wget, vim, unzip and zsh
homebrew   Install Homebrew when its host requirements are met
zsh        Install zsh and the Antidote plugin bundle
powerlevel10k Install the Powerlevel10k Zsh prompt
tools      Install selected optional developer tools
dotfiles   Link Zsh, Git, Powerlevel10k and plugin configuration
EOF
}

parse_args() {
    MODULES='base homebrew zsh powerlevel10k dotfiles'
    TOOLS='uv fzf rg bat eza zoxide zellij nvtop jq fd'
    INTERACTIVE=1
    ALLOW_REMOTE=0
    CONFLICT_POLICY=skip
    MODULES_EXPLICIT=0
    ACTION=install
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --modules|--tools|--conflict)
                if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ $2 == --* ]]; then
                    log_error "$1 requires a value"; return 1
                fi
                case "$1" in
                    --modules|--tools)
                        local item values=$2
                        case "$values" in
                            ,*|*,|*,,*|*[!a-z0-9,]*) log_error "Invalid list: $values"; return 1 ;;
                        esac
                        local selected=''
                        for item in ${values//,/ }; do
                            case "$1:$item" in
                                --modules:base|--modules:homebrew|--modules:zsh|--modules:powerlevel10k|--modules:tools|--modules:dotfiles|--tools:uv|--tools:fzf|--tools:rg|--tools:bat|--tools:eza|--tools:zoxide|--tools:zellij|--tools:nvtop|--tools:jq|--tools:fd) ;;
                                *) log_error "Unknown selection for $1: $item"; return 1 ;;
                            esac
                            case " $selected " in *" $item "*) ;; *) selected="${selected:+$selected }$item" ;; esac
                        done
                        if [ "$1" = --modules ]; then MODULES=$selected; MODULES_EXPLICIT=1; else TOOLS=$selected; fi
                        ;;
                    --conflict)
                        case "$2" in skip|backup) CONFLICT_POLICY=$2 ;; *) log_error "Unknown conflict policy: $2"; return 1 ;; esac
                        ;;
                esac
                shift 2
                ;;
            --yes) INTERACTIVE=0; shift ;;
            --allow-remote) ALLOW_REMOTE=1; shift ;;
            --list-modules) ACTION=list; shift ;;
            -h|--help) ACTION=help; shift ;;
            *) log_error "Unknown argument: $1 (see --help)"; return 1 ;;
        esac
    done
}

main() {
    parse_args "$@" || return 1
    case "$ACTION" in help) usage; return 0 ;; list) list_modules; return 0 ;; esac
    if [ "$INTERACTIVE" -eq 1 ] && [ ! -t 0 ]; then
        log_error 'Non-interactive input requires --yes. See --help.'
        return 1
    fi
    XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
    XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
    XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
    export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    detect_system || return 1
    log_info "Host: $OS / $DISTRO / $ARCH; uid=$USER_ID; packages=$PACKAGE_MANAGER; container=$IN_CONTAINER"
    if [ "$INTERACTIVE" -eq 1 ] && [ "$MODULES_EXPLICIT" -eq 0 ]; then
        list_modules
        local defaults=$MODULES module answer
        MODULES=''
        for module in base homebrew zsh powerlevel10k tools dotfiles; do
            local hint=N
            case " $defaults " in *" $module "*) hint=Y ;; esac
            printf 'Install %s? [%s/%s] ' "$module" "$hint" "$(if [ "$hint" = Y ]; then printf n; else printf y; fi)"
            IFS= read -r answer || return 1
            case "$answer:$hint" in y:*|Y:*|yes:*|YES:*|:Y) MODULES="${MODULES:+$MODULES }$module" ;; esac
        done
    fi
    local module result failed=0 completed='' skipped='' failures=''
    local execution_order='base homebrew zsh powerlevel10k tools dotfiles'
    if [ "$OS" = macos ]; then execution_order='homebrew base zsh powerlevel10k tools dotfiles'; fi
    for module in $execution_order; do
        case " $MODULES " in *" $module "*) ;; *) continue ;; esac
        source "$ROOT_DIR/modules/$module.sh"
        log_info "Starting $module"
        result=0
        "module_$module" || result=$?
        case "$result" in
            0) completed="${completed:+$completed, }$module" ;;
            2) skipped="${skipped:+$skipped, }$module" ;;
            *) failures="${failures:+$failures, }$module"; failed=1; log_error "$module failed; continuing with other modules" ;;
        esac
    done
    log_info "Completed: ${completed:-none}"
    log_info "Skipped or incomplete: ${skipped:-none}"
    log_info "Failed: ${failures:-none}"
    return "$failed"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
