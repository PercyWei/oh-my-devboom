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
  --modules LIST    Override modules: base,homebrew,zsh,powerlevel10k,tools,dotfiles,shell
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
zsh        Zsh Augmented: Antidote, completions, suggestions and highlighting
powerlevel10k Install the Powerlevel10k Zsh prompt
tools      Install selected optional developer tools
dotfiles   Link Zsh, Git, Powerlevel10k and plugin configuration
shell      Set the current account's login shell to Zsh
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
    printf '配置    %s\n' "$CONFIG_FILE"
    printf '\n'
    print_styled '1' '安装清单'
    printf '（已有组件按模块规则复用或补齐配置）\n'
    for module in $1; do
        case " $MODULES " in *" $module "*) ;; *) continue ;; esac
        case "$module" in
            base) printf '  base: git、curl、wget、vim、unzip、zsh\n' ;;
            homebrew) printf '  homebrew: Homebrew（不满足安装条件时跳过）\n' ;;
            zsh) printf '  zsh: Zsh Augmented · Antidote、补全、自动建议、语法高亮\n' ;;
            powerlevel10k) printf '  powerlevel10k: Powerlevel10k、gitstatusd\n' ;;
            tools) printf '  tools: %s\n' "${TOOLS:-未选择工具}" ;;
            dotfiles) printf '  dotfiles: 部署 Shell / Git / 主题配置及插件列表\n' ;;
            shell) printf '  shell: 将当前执行账户的默认登录 Shell 设为 Zsh（chsh）\n' ;;
        esac
    done
    case " $MODULES " in *' tools '*) ;; *) log_info '可选开发工具：未启用 tools 模块。' ;; esac
    printf '\n配置冲突策略：%s' "$CONFLICT_POLICY"
    case "$CONFLICT_POLICY" in
        skip) printf '（保留已有文件）\n' ;;
        backup) printf '（备份后部署）\n' ;;
    esac
    if [[ -n "$GITHUB_PROXY" ]]; then
        log_info "GitHub 加速前缀：$GITHUB_PROXY"
    else
        log_info 'GitHub 下载：直连。'
    fi
    log_info "Git 下载超时：${GIT_TIMEOUT} 秒"
    log_info '上游下载授权范围：Homebrew/uv 安装脚本；Antidote 与 Zsh 补全、自动建议、语法高亮插件；Powerlevel10k 主题、gitstatusd 和 Zellij 发布包。'
    if [[ "$ALLOW_REMOTE" == 1 ]]; then
        log_info '上述内容：已授权直接下载并执行或加载。'
    else
        log_info '上述内容：未预先授权；交互时确认来源，非交互时跳过对应的直接下载安装步骤。'
    fi
    log_info '包管理器安装、本地配置部署不受此授权限制；已安装的组件仍可复用。'
}

print_install_summary() {
    local elapsed=$1 index item state completed=0 partial=0 skipped=0 failures=0
    local retry_modules='' zsh_config_ready=0 git_config_ready=0
    for ((index=0; index<MODULE_COUNT; index++)); do
        case "${MODULE_STATES[$index]}" in
            complete) completed=$((completed + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            skipped) skipped=$((skipped + 1)) ;;
            failed) failures=$((failures + 1)) ;;
        esac
    done
    printf '\n'
    print_styled '1' "执行结果 · 总耗时 ${elapsed}s"
    printf '\n完成 %s · 部分完成 %s · 跳过 %s · 失败 %s\n' "$completed" "$partial" "$skipped" "$failures"
    for ((index=0; index<MODULE_COUNT; index++)); do
        printf '\n'
        state=${MODULE_STATES[$index]}
        print_status "$state"
        printf ' %s (%s) · %ss\n' "$(module_label "${MODULE_IDS[$index]}")" "${MODULE_IDS[$index]}" "${MODULE_TIMES[$index]}"
        for ((item=0; item<RESULT_COUNT; item++)); do
            [[ "${RESULT_MODULES[$item]}" == "${MODULE_IDS[$index]}" ]] || continue
            printf '  '
            print_status "${RESULT_STATES[$item]}"
            printf ' %s：%s\n' "${RESULT_LABELS[$item]}" "${RESULT_DETAILS[$item]}"
            if [[ -n "${RESULT_ACTIONS[$item]}" ]]; then
                printf '    建议：%s\n' "${RESULT_ACTIONS[$item]}"
            fi
        done
        case "$state" in
            partial|failed) retry_modules="${retry_modules:+$retry_modules,}${MODULE_IDS[$index]}" ;;
        esac
    done
    for ((item=0; item<RESULT_COUNT; item++)); do
        case "${RESULT_STATES[$item]}" in ready|configured) ;; *) continue ;; esac
        [[ "${RESULT_LABELS[$item]}" != "${ZDOTDIR:-$HOME}/.zshrc" ]] || zsh_config_ready=1
        [[ "${RESULT_LABELS[$item]}" != "$HOME/.gitconfig" ]] || git_config_ready=1
    done
    if [[ "$zsh_config_ready" == 1 ]] && have zsh; then
        printf '\n下一步：运行 exec zsh 使用当前配置；配置软链接依赖当前仓库目录，请保留该目录。\n'
    fi
    if [[ "$git_config_ready" == 1 ]] && have git; then
        local git_name='' git_email=''
        git_name=$(git config --global --includes --get user.name 2>/dev/null) || :
        git_email=$(git config --global --includes --get user.email 2>/dev/null) || :
        if [[ -z "$git_name" || -z "$git_email" ]]; then
            printf '\nGit 身份尚未配置完整，可写入个人配置：\n'
            [[ -n "$git_name" ]] || printf '  git config --file %q user.name "Your Name"\n' "$HOME/.gitconfig.local"
            [[ -n "$git_email" ]] || printf '  git config --file %q user.email "you@example.com"\n' "$HOME/.gitconfig.local"
        fi
    fi
    if [[ -n "$retry_modules" ]]; then
        local config_path=$CONFIG_FILE
        [[ "$config_path" == /* ]] || config_path="$PWD/$config_path"
        printf '\n处理上述问题后，可按本次选项重试相关模块：\n  bash %q --config %q --modules %q' \
            "$ROOT_DIR/bootstrap.sh" "$config_path" "$retry_modules"
        case ",$retry_modules," in
            *,tools,*) [[ -z "$TOOLS" ]] || printf ' --tools %q' "${TOOLS// /,}" ;;
        esac
        printf ' --conflict %q' "$CONFLICT_POLICY"
        [[ "$ALLOW_REMOTE" != 1 ]] || printf ' --allow-remote'
        [[ "$INTERACTIVE" != 0 ]] || printf ' --non-interactive'
        printf '\n'
    fi
    printf '\n'
    if [[ "$failures" != 0 ]]; then
        print_styled '31' '存在安装错误，退出码 1；其他模块的已完成结果保留。'
    elif [[ "$partial" != 0 || "$skipped" != 0 ]]; then
        print_styled '33' '本次无安装错误，退出码 0；仍有跳过或未完成项，请查看上述原因。'
    else
        print_styled '32' '所选模块均已完成，退出码 0。'
    fi
    printf '\n'
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
    local module answer result failed=0 total=0 started module_started first item successful pending errors state elapsed
    local execution_order='base homebrew zsh powerlevel10k tools dotfiles shell'
    if [ "$OS" = macos ]; then execution_order='homebrew base zsh powerlevel10k tools dotfiles shell'; fi
    printf '\n'
    print_styled '1;36' 'oh-my-devboom'
    printf '\n开发环境初始化\n\n环境    %s / %s / %s · uid=%s · 包管理器=%s · 容器=%s\n' \
        "$OS" "$DISTRO" "$ARCH" "$USER_ID" "$PACKAGE_MANAGER" "$IN_CONTAINER"
    print_install_plan "$execution_order"
    printf '\n'
    if [[ -z "$MODULES" ]]; then log_info '未选择安装模块，无需执行。'; return 0; fi
    if [ "$INTERACTIVE" -eq 1 ]; then
        printf '按以上配置继续安装？[y/N] '
        IFS= read -r answer || return 1
        case "$answer" in
            y|Y|yes|YES) ;;
            *) log_info '已取消安装。'; return 0 ;;
        esac
    fi
    reset_results
    MODULE_COUNT=0
    MODULE_IDS=() MODULE_STATES=() MODULE_TIMES=()
    for module in $MODULES; do total=$((total + 1)); done
    started=$SECONDS
    for module in $execution_order; do
        case " $MODULES " in *" $module "*) ;; *) continue ;; esac
        source "$ROOT_DIR/modules/$module.sh"
        CURRENT_MODULE=$module
        first=$RESULT_COUNT
        module_started=$SECONDS
        {
            printf '\n'
            print_styled '1;34' "[$((MODULE_COUNT + 1))/$total] $(module_label "$module") ($module)"
            printf ' · 开始\n'
        } >&2
        result=0
        "module_$module" || result=$?
        elapsed=$((SECONDS - module_started))
        successful=0 pending=0 errors=0
        for ((item=first; item<RESULT_COUNT; item++)); do
            case "${RESULT_STATES[$item]}" in
                installed|ready|configured) successful=$((successful + 1)) ;;
                skipped) pending=$((pending + 1)) ;;
                failed) errors=$((errors + 1)) ;;
            esac
        done
        if [[ "$result" != 0 && "$result" != 2 ]]; then
            state=failed
            failed=1
            if [[ "$errors" == 0 ]]; then
                record_result failed "$(module_label "$module")" "执行失败，退出码 ${result}。" '检查上方命令错误，处理后重试该模块。'
            fi
        elif [[ "$result" == 2 || "$pending" != 0 ]]; then
            if [[ "$successful" == 0 ]]; then state=skipped; else state=partial; fi
        else
            state=complete
        fi
        MODULE_IDS[$MODULE_COUNT]=$module
        MODULE_STATES[$MODULE_COUNT]=$state
        MODULE_TIMES[$MODULE_COUNT]=$elapsed
        MODULE_COUNT=$((MODULE_COUNT + 1))
        {
            print_status "$state"
            printf ' %s · %ss\n' "$(module_label "$module")" "$elapsed"
        } >&2
    done
    CURRENT_MODULE=''
    print_install_summary "$((SECONDS - started))" >&2
    return "$failed"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
