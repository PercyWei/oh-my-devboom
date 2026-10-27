#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/system.sh"
source "$ROOT_DIR/lib/packages.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/install_config.sh"

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options]

Set up a personal development environment on Linux or macOS (Bash 3.2+).

  --config FILE     Installation settings (default: config/default.conf)
  --modules LIST    Override modules: base,homebrew,zsh,powerlevel10k,tools,dotfiles
                    Comma-separated names, or all.
  --tools LIST      Override tools: uv,fzf,rg,bat,eza,zoxide,zellij,nvtop,jq,fd
                    Comma-separated names, or all. Requires the tools module.
  --non-interactive Run without prompts; required when stdin is not a terminal
  --allow-remote    Authorize direct upstream downloads and execution:
                    Homebrew/uv installers; Antidote and Zsh plugins;
                    Powerlevel10k theme, gitstatusd and Zellij release binaries.
                    Package-manager installs and local config links are unaffected.
  --conflict POLICY Override config conflicts: skip or backup before linking
  --list-modules    Describe modules and exit
  -h, --help        Show this help and exit

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --config config/local.conf
  ./bootstrap.sh --non-interactive --modules dotfiles
  ./bootstrap.sh --non-interactive --allow-remote --modules all --tools all
  ./bootstrap.sh --non-interactive --modules dotfiles --conflict backup

Command-line options override the selected config regardless of argument order.
Interactive runs show the installation plan and ask for confirmation.
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
    local modules_override='' tools_override='' conflict_override='' remote_override=0
    CONFIG_FILE="$ROOT_DIR/config/default.conf"
    INTERACTIVE=1
    ACTION=install
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config|--modules|--tools|--conflict)
                if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ $2 == --* ]]; then
                    log_error "$1 requires a value"; return 1
                fi
                case "$1" in
                    --config) CONFIG_FILE=$2 ;;
                    --modules|--tools)
                        local item values=$2 choices
                        if [[ "$1" == --modules ]]; then choices=$AVAILABLE_MODULES; else choices=$AVAILABLE_TOOLS; fi
                        [[ "$values" != all ]] || values=${choices// /,}
                        case "$values" in
                            ,*|*,|*,,*|*[!a-z0-9,]*) log_error "Invalid list: $values"; return 1 ;;
                        esac
                        local selected=''
                        for item in ${values//,/ }; do
                            case " $choices " in
                                *" $item "*) ;;
                                *) log_error "Unknown selection for $1: $item"; return 1 ;;
                            esac
                            case " $selected " in *" $item "*) ;; *) selected="${selected:+$selected }$item" ;; esac
                        done
                        if [ "$1" = --modules ]; then modules_override=$selected; else tools_override=$selected; fi
                        ;;
                    --conflict)
                        case "$2" in skip|backup) conflict_override=$2 ;; *) log_error "Unknown conflict policy: $2"; return 1 ;; esac
                        ;;
                esac
                shift 2
                ;;
            --non-interactive) INTERACTIVE=0; shift ;;
            --allow-remote) remote_override=1; shift ;;
            --list-modules) ACTION=list; shift ;;
            -h|--help) ACTION=help; shift ;;
            *) log_error "Unknown argument: $1 (see --help)"; return 1 ;;
        esac
    done
    [[ "$ACTION" == install ]] || return 0
    load_install_config "$CONFIG_FILE" || return 1
    [[ -z "$modules_override" ]] || MODULES=$modules_override
    [[ -z "$tools_override" ]] || TOOLS=$tools_override
    [[ -z "$conflict_override" ]] || CONFLICT_POLICY=$conflict_override
    [[ "$remote_override" == 0 ]] || ALLOW_REMOTE=1
    return 0
}

print_install_plan() {
    local module
    log_info "安装配置：$CONFIG_FILE"
    log_info '本次安装清单（已安装的组件会按模块规则复用或补齐配置）：'
    for module in $1; do
        case " $MODULES " in *" $module "*) ;; *) continue ;; esac
        case "$module" in
            base) printf '  base: git、curl、wget、vim、unzip、zsh\n' ;;
            homebrew) printf '  homebrew: Homebrew（不满足安装条件时跳过）\n' ;;
            zsh) printf '  zsh: Antidote、补全、自动建议、语法高亮插件\n' ;;
            powerlevel10k) printf '  powerlevel10k: Powerlevel10k、gitstatusd\n' ;;
            tools) printf '  tools: %s\n' "${TOOLS:-未选择工具}" ;;
            dotfiles) printf '  dotfiles: 部署 Shell / Git / 主题配置及插件列表\n' ;;
        esac
    done
    case " $MODULES " in *' tools '*) ;; *) log_info '可选开发工具：未启用 tools 模块。' ;; esac
    log_info "配置冲突策略：$CONFLICT_POLICY"
    log_info '上游下载授权范围：Homebrew/uv 安装脚本；Antidote 与 Zsh 补全、自动建议、语法高亮插件；Powerlevel10k 主题、gitstatusd 和 Zellij 发布包。'
    if [[ "$ALLOW_REMOTE" == 1 ]]; then
        log_info '上述内容：已授权直接下载并执行或加载。'
    else
        log_info '上述内容：未预先授权；交互时确认来源，非交互时跳过对应的直接下载安装步骤。'
    fi
    log_info '包管理器安装、本地配置部署不受此授权限制；已安装的组件仍可复用。'
}

main() {
    parse_args "$@" || return 1
    case "$ACTION" in help) usage; return 0 ;; list) list_modules; return 0 ;; esac
    if [ "$INTERACTIVE" -eq 1 ] && [ ! -t 0 ]; then
        log_error 'Non-interactive input requires --non-interactive. See --help.'
        return 1
    fi
    XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
    XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
    XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
    export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    detect_system || return 1
    log_info "Host: $OS / $DISTRO / $ARCH; uid=$USER_ID; packages=$PACKAGE_MANAGER; container=$IN_CONTAINER"
    local module answer result failed=0 completed='' skipped='' failures=''
    local execution_order='base homebrew zsh powerlevel10k tools dotfiles'
    if [ "$OS" = macos ]; then execution_order='homebrew base zsh powerlevel10k tools dotfiles'; fi
    print_install_plan "$execution_order"
    if [[ -z "$MODULES" ]]; then log_info '未选择安装模块，无需执行。'; return 0; fi
    if [ "$INTERACTIVE" -eq 1 ]; then
        printf '按以上配置继续安装？[y/N] '
        IFS= read -r answer || return 1
        case "$answer" in
            y|Y|yes|YES) ;;
            *) log_info '已取消安装。'; return 0 ;;
        esac
    fi
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
