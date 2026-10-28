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
    local target sha256 url staging checksum result=0 RECORD_PACKAGE_RESULTS=0
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
        *) record_result skipped Zellij "官方发布包未配置当前平台：$OS/$ARCH"; return 2 ;;
    esac
    if [[ -e "$HOME/.local/bin/zellij" || -L "$HOME/.local/bin/zellij" ]]; then
        record_result skipped Zellij "保留现有文件：$HOME/.local/bin/zellij" \
            '检查现有文件及其执行权限，处理后重新运行 tools 模块。'
        return 2
    fi
    url="https://github.com/zellij-org/zellij/releases/download/v0.45.1/zellij-$target.tar.gz"
    approve_remote 'Zellij v0.45.1' "$url" || return $?
    ensure_packages tar || return $?
    if ! have sha256sum && ! have shasum; then
        record_result skipped Zellij '缺少 SHA256 校验工具，发布包未安装。' \
            '安装 sha256sum 或 shasum 后重试。'
        return 2
    fi
    mkdir -p "$XDG_CACHE_HOME/oh-my-devboom" "$HOME/.local/bin" || {
        record_result failed Zellij "无法创建缓存目录或安装目录：$XDG_CACHE_HOME/oh-my-devboom、$HOME/.local/bin" \
            '检查目录权限及磁盘空间后重试。'
        return 1
    }
    staging=$(mktemp -d "$XDG_CACHE_HOME/oh-my-devboom/zellij.XXXXXX") || {
        record_result failed Zellij "无法在 $XDG_CACHE_HOME/oh-my-devboom 创建下载临时目录。"
        return 1
    }
    download_file "$url" "$staging/archive.tar.gz" 1800 || result=$?
    if [[ "$result" != 0 ]]; then
        if [[ "$result" == 2 ]]; then
            record_result skipped Zellij '缺少 curl 或 wget，未下载发布包。' '完成 base 模块后重试。'
        else
            record_result failed Zellij "发布包下载失败或超时：$url" '检查网络和 GitHub 加速配置后重试。'
        fi
        rm -rf -- "$staging"
        return "$result"
    fi
    if have sha256sum; then
        checksum=$(sha256sum "$staging/archive.tar.gz") || result=1
    else
        checksum=$(shasum -a 256 "$staging/archive.tar.gz") || result=1
    fi
    if [[ "$result" != 0 || "${checksum%% *}" != "$sha256" ]]; then
        record_result failed Zellij '发布包 SHA256 校验失败，未安装二进制文件。' \
            '检查下载来源与网络代理后重新下载。'
        rm -rf -- "$staging"
        return 1
    fi
    if ! tar -xzf "$staging/archive.tar.gz" -C "$staging" zellij; then
        record_result failed Zellij '发布包解压失败，未安装二进制文件。' '检查上方 tar 错误及磁盘空间后重试。'
        rm -rf -- "$staging"
        return 1
    fi
    if ! chmod +x "$staging/zellij"; then
        record_result failed Zellij '无法为解压出的二进制文件设置执行权限。'
        rm -rf -- "$staging"
        return 1
    fi
    if ! mv -- "$staging/zellij" "$HOME/.local/bin/zellij"; then
        record_result failed Zellij "无法将二进制文件安装到 $HOME/.local/bin/zellij。" \
            '检查安装目录权限及磁盘空间后重试。'
        rm -rf -- "$staging"
        return 1
    fi
    rm -rf -- "$staging"
    record_result installed Zellij "v0.45.1 已校验并安装到 $HOME/.local/bin/zellij。"
}

prepare_fzf_shell_integration() {
    local target="$XDG_DATA_HOME/oh-my-devboom/fzf" version fzf_path package_version
    local scripts=/usr/share/doc/fzf/examples staging='' result=0 archives
    version=$(fzf --version) || {
        record_result failed 'fzf Zsh 集成' '无法读取 fzf 版本，未准备补全和快捷键。' '检查 fzf --version 的输出后重试。'
        return 1
    }
    if [[ -L "$target" || ( -e "$target" && ! -f "$target/fzf-version" ) ]]; then
        record_result skipped 'fzf Zsh 集成' "保留不属于当前安装流程的目录：$target" \
            '检查并自行备份或移走冲突目录后重试。'
        return 2
    fi
    if [[ -r "$target/fzf-version" && "$(cat "$target/fzf-version")" == "$version" &&
          -r "$target/init.zsh" ]]; then
        record_result ready 'fzf Zsh 集成' "复用与 fzf $version 匹配的初始化脚本：$target/init.zsh"
        return 0
    fi
    # 启动时不再检查版本；刷新失败时也不能继续加载已过期的脚本。
    if ! rm -f "$target/init.zsh"; then
        record_result failed 'fzf Zsh 集成' "无法清除旧初始化脚本：$target/init.zsh" '检查目录权限后重试。'
        return 1
    fi
    mkdir -p "$XDG_DATA_HOME/oh-my-devboom" || {
        record_result failed 'fzf Zsh 集成' "无法创建数据目录：$XDG_DATA_HOME/oh-my-devboom" \
            '检查目录权限及磁盘空间后重试。'
        return 1
    }
    staging=$(mktemp -d "$XDG_DATA_HOME/oh-my-devboom/.fzf.XXXXXX") || {
        record_result failed 'fzf Zsh 集成' "无法在 $XDG_DATA_HOME/oh-my-devboom 创建临时目录。"
        return 1
    }
    mkdir "$staging/runtime" || {
        rm -rf -- "$staging"
        record_result failed 'fzf Zsh 集成' '无法创建初始化脚本临时目录。' '检查目录权限和磁盘空间后重试。'
        return 1
    }
    # 新版导出脚本；旧版从原包提取。两者使用相同的启动入口。
    if ! fzf --zsh > "$staging/runtime/init.zsh" 2>/dev/null; then
        fzf_path=$(command -v fzf)
        if ! have apt-get || ! have dpkg-query || ! have dpkg-deb ||
            [[ "$(dpkg-query -S "$fzf_path" 2>/dev/null)" != "fzf: $fzf_path" ]]; then
            rm -rf -- "$staging"
            record_result skipped 'fzf Zsh 集成' '当前旧版 fzf 无法通过 APT 提取匹配的集成脚本。' \
                '将 fzf 升级到支持 --zsh 的版本，以启用补全和快捷键。'
            return 2
        fi
        package_version=$(dpkg-query -W -f='${Version}' fzf) || {
            rm -rf -- "$staging"
            record_result failed 'fzf Zsh 集成' '无法读取已安装 fzf 的 APT 包版本。'
            return 1
        }
        if [[ ! -r "$scripts/completion.zsh" || ! -r "$scripts/key-bindings.zsh" ]]; then
            # APT 校验来源并提取已安装版本，补齐精简容器缺失的文档文件。
            log_info "从 APT 仓库下载 fzf=${package_version}，提取匹配的 Zsh 集成脚本。"
            if (cd "$staging" && apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
                download "fzf=$package_version"); then
                archives=("$staging"/*.deb)
                dpkg-deb -x "${archives[0]}" "$staging/package" || {
                    record_result failed 'fzf Zsh 集成' "无法解压 fzf=$package_version 的 APT 包。" \
                        '检查上方 dpkg-deb 错误及磁盘空间后重试。'
                    result=1
                }
                scripts="$staging/package/usr/share/doc/fzf/examples"
            else
                record_result failed 'fzf Zsh 集成' "无法从 APT 仓库下载已安装版本 fzf=${package_version}。" \
                    '检查 APT 仓库是否仍提供该版本，以及网络连接后重试。'
                result=1
            fi
        fi
        if [[ "$result" == 0 ]]; then
            { cat "$scripts/completion.zsh" && printf '\n' && cat "$scripts/key-bindings.zsh"; } \
                > "$staging/runtime/init.zsh" || {
                    record_result failed 'fzf Zsh 集成' "无法从 $scripts 准备匹配版本的补全和快捷键脚本。" \
                        '检查脚本是否完整，以及目录权限和磁盘空间后重试。'
                    result=1
                }
        fi
    fi
    if [[ "$result" == 0 ]]; then
        printf '%s\n' "$version" > "$staging/runtime/fzf-version" || {
            record_result failed 'fzf Zsh 集成' '无法记录初始化脚本对应的 fzf 版本。' '检查目录权限和磁盘空间后重试。'
            result=1
        }
    fi
    if [[ "$result" == 0 ]]; then
        if [[ -d "$target" ]]; then
            mv "$staging/runtime/init.zsh" "$target/init.zsh" &&
                mv "$staging/runtime/fzf-version" "$target/fzf-version" || result=1
        else
            # Publish a complete directory on the same filesystem on first install.
            mv "$staging/runtime" "$target" || result=1
        fi
        if [[ "$result" != 0 ]]; then
            record_result failed 'fzf Zsh 集成' "无法将集成脚本完整部署到 ${target}。" \
                '检查目录权限及磁盘空间，修复后重试以补齐脚本。'
        fi
    fi
    rm -rf -- "$staging"
    if [[ "$result" == 0 ]]; then
        record_result configured 'fzf Zsh 集成' "已部署与 fzf $version 匹配的初始化脚本：$target/init.zsh"
    fi
    return "$result"
}

module_tools() {
    local tool command_name result status=0
    if [[ -z "$TOOLS" ]]; then
        record_result skipped tools '未选择工具，无需执行。'
        return 0
    fi
    for tool in $TOOLS; do
        result=0
        command_name=$tool
        case "$tool" in
            modelscope-hub) command_name=ms-hub ;;
            huggingface-hub) command_name=hf ;;
            bat) if ! have bat && have batcat; then command_name=batcat; fi ;;
            fd) if ! have fd && have fdfind; then command_name=fdfind; fi ;;
        esac
        if have "$command_name"; then
            record_result ready "$tool" "复用现有命令 ${command_name}。"
        elif [[ "$tool" == uv ]]; then
            if have brew && [[ "$USER_ID" != 0 ]]; then
                PACKAGE_MANAGER=brew ensure_packages uv || result=$?
            else
                UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 \
                    run_remote_installer uv https://astral.sh/uv/install.sh || result=$?
                if [[ "$result" == 0 ]]; then
                    export PATH="$HOME/.local/bin:$PATH"
                    if have uv; then
                        record_result installed uv "已通过 Astral 安装器安装，命令路径：$(command -v uv)"
                    else
                        record_result failed uv "安装器已退出，但 PATH 中未找到 uv；预期目录：$HOME/.local/bin" \
                            '检查安装器输出和安装目录后重试。'
                        result=1
                    fi
                fi
            fi
        elif [[ "$tool" == modelscope-hub || "$tool" == huggingface-hub ]]; then
            if ! have uv; then
                record_result skipped "$tool" '缺少 uv，未安装。' '先完成 uv 安装后重试 tools 模块。'
                result=2
            elif UV_TOOL_BIN_DIR="$HOME/.local/bin" uv tool install --python '>=3.10' "$tool"; then
                if have "$command_name"; then
                    record_result installed "$tool" "已通过 uv 隔离安装，命令路径：$(command -v "$command_name")"
                else
                    record_result failed "$tool" "uv 安装已退出，但未找到命令 ${command_name}；预期目录：$HOME/.local/bin" \
                        '检查 uv 输出和命令安装目录后重试。'
                    result=1
                fi
            else
                record_result failed "$tool" 'uv 安装失败。' '检查上方 uv 错误、网络和现有命令冲突后重试。'
                result=1
            fi
        elif [[ "$tool" == zellij ]]; then
            install_zellij || result=$?
        elif [[ "$tool" == nvtop && "$OS" == macos && "$ARCH" != aarch64 ]]; then
            record_result skipped NVTOP "macOS 后端仅支持 Apple GPU，当前架构为 ${ARCH}。"
            result=2
        else
            ensure_packages "$tool" || result=$?
        fi
        if [[ "$tool" == fzf && "$result" == 0 ]]; then
            prepare_fzf_shell_integration || result=$?
        fi
        if [[ "$result" == 1 ]]; then
            status=1
        elif [[ "$result" == 2 && "$status" == 0 ]]; then
            status=2
        fi
    done
    return "$status"
}
