#!/usr/bin/env bash

module_clash() {
    local clash_dir="$XDG_DATA_HOME/clashctl"
    local cache="$XDG_CACHE_HOME/oh-my-devboom" staging checksum service=auto
    local commit=e38d643725594c38c3fb02f355a2c89eba9c296c
    local source_url="https://gitee.com/back_door/clashctl/repository/archive/$commit.tar.gz"
    local archive_sha256=172e68840d6b81e454950f90e81439fc0ca424e589b1f2f5de36aa9a39d12fef
    local mihomo_version=v1.19.33 yq_version=v4.54.1
    local packages_url="https://gitee.com/back_door/clashctl/releases/download/mihomo-$mihomo_version-yq-$yq_version"
    local mihomo_file yq_file mihomo_sha256 yq_sha256 component package_file package_sha256 archive_file
    local complete=0 result=0 RECORD_PACKAGE_RESULTS=0
    local env_file name value proxy_values=() dependencies=(curl tar gzip unzip sha256sum shuf od timeout)
    local proxy_names=(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY)
    CLASH_PROXY_ACTIVE=0

    if [[ "$OS" != linux ]]; then
        record_result skipped Clash 'clashctl 仅支持 Linux，当前平台保留已有网络设置。'
        return 2
    fi
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        record_result failed Clash 'clashctl 需要 Bash 4 或更高版本。' '升级 Bash 后重试 clash 模块。'
        return 1
    fi
    if [[ "${CLASH_CONFIG_FILE:-}" != /* || ! -f "$CLASH_CONFIG_FILE" || ! -r "$CLASH_CONFIG_FILE" ]]; then
        record_result failed Clash '[clash] config_file 必须指向可读的本地 Clash/Mihomo YAML 文件，且使用绝对路径。'
        return 1
    fi
    if [[ "$clash_dir" != /* || "$clash_dir" == *[^a-zA-Z0-9_./-]* ]]; then
        record_result failed Clash "clashctl 安装路径不支持空格或特殊字符：$clash_dir" \
            '请将 XDG_DATA_HOME 设为只含英文字母、数字、/、_、.、- 的绝对路径。'
        return 1
    fi
    if [[ -L "$clash_dir" || ( -e "$clash_dir" && ! -f "$clash_dir/.clashctl-install" ) ]]; then
        record_result failed Clash "保留无法确认归属的安装路径：$clash_dir" '检查并自行备份或移走冲突目录后重试。'
        return 1
    fi
    if [[ -L "$clash_dir/.clashctl-format" ||
          ( -e "$clash_dir/.clashctl-format" && "$(cat "$clash_dir/.clashctl-format")" != 1 ) ]]; then
        record_result failed Clash "现有 clashctl 数据格式与已审查版本不符，已保留：$clash_dir" \
            '请自行处理现有安装，不会自动迁移或加载该版本。'
        return 1
    fi
    if [[ -f "$clash_dir/.env" && -f "$clash_dir/.clashctl-format" &&
          ! -e "$clash_dir/.clashctl-incomplete" && ! -e "$clash_dir/.clashctl-uninitialized" &&
          -f "$clash_dir/scripts/cmd/clashctl.sh" && -x "$clash_dir/bin/mihomo" ]]; then
        if [[ -x "$clash_dir/bin/yq" ]] || { have yq && [[ "$(yq --version)" == *mikefarah*v4.* ]]; }; then
            complete=1
        fi
    fi
    if [[ "$complete" == 0 ]]; then
        case "$ARCH" in
            x86_64)
                mihomo_file="mihomo-linux-amd64-v1-$mihomo_version.gz"
                mihomo_sha256=8ec92e7b2fdc6b853ba00156bab7e4e965c8b0d843b8c4ac8ab98795f02ad524
                yq_file=yq_linux_amd64.tar.gz
                yq_sha256=e68a456f90c577af3fe4960184b3a3cf5c461e0348407c10f107da3a5fec8972
                ;;
            aarch64)
                mihomo_file="mihomo-linux-arm64-$mihomo_version.gz"
                mihomo_sha256=ba408b317080ee265c46cb923a50018c1b82cbd708551cdd46a1e3e307396187
                yq_file=yq_linux_arm64.tar.gz
                yq_sha256=8c27f6e7476fb5acefb9352e3d30f6bc2dc93f1956eb92e8da727173fb7ec6d3
                ;;
            *) record_result failed Clash "Gitee 安装包不支持当前架构：$ARCH"; return 1 ;;
        esac
        approve_remote "clashctl、Mihomo $mihomo_version 和 yq $yq_version" \
            "$source_url；$packages_url/$mihomo_file；$packages_url/$yq_file" || return 1
    fi

    # 代理建立前只准备它自身所需的系统命令；Alpine 的 BusyBox 不能替代 GNU 工具。
    if [[ "$PACKAGE_MANAGER" == apk ]] && ! apk info -e coreutils tar >/dev/null 2>&1; then
        run_privileged apk add coreutils tar || {
            record_result failed Clash '无法准备 clashctl 所需的 GNU coreutils 和 tar。'
            return 1
        }
    fi
    have ss || have netstat || dependencies+=(ss)
    have ip || have hostname || dependencies+=(ip)
    ensure_packages "${dependencies[@]}" || {
        record_result failed Clash '代理前置依赖尚未准备完成。' '先解决上方系统软件包或权限错误，再重试。'
        return 1
    }
    clash_dir=$(readlink -m -- "$clash_dir") || return 1
    mkdir -p "$cache" "$(dirname "$clash_dir")" || {
        record_result failed Clash '无法创建 clashctl 安装或缓存目录。'
        return 1
    }
    # 安装器和配置导入都可能启动内核；即使中途失败，入口也负责关闭。
    CLASH_CLEANUP_HOME=$clash_dir
    if [[ "$complete" == 0 ]]; then
        staging=$(mktemp -d "$cache/clashctl.XXXXXX") || return 1
        [[ "$IN_CONTAINER" != 1 ]] || service=nohup
        if ! (
            trap 'rm -rf -- "$staging"' EXIT
            download_file "$source_url" "$staging/source.tar.gz" || exit 1
            checksum=$(sha256sum "$staging/source.tar.gz") || exit 1
            if [[ "${checksum%% *}" != "$archive_sha256" ]]; then
                log_error 'clashctl 源码 SHA256 校验失败，未运行安装器。'
                exit 1
            fi
            mkdir -m 700 "$staging/archives" || exit 1
            for component in mihomo yq; do
                case "$component" in
                    mihomo) package_file=$mihomo_file; package_sha256=$mihomo_sha256; archive_file=$mihomo_file ;;
                    yq) package_file=$yq_file; package_sha256=$yq_sha256; archive_file="yq-$yq_version-$ARCH.tar.gz" ;;
                esac
                log_info "下载 $component 安装包：$packages_url/$package_file"
                download_file "$packages_url/$package_file" "$staging/archives/$archive_file" || exit 1
                checksum=$(sha256sum "$staging/archives/$archive_file") || exit 1
                if [[ "${checksum%% *}" != "$package_sha256" ]]; then
                    log_error "$component 安装包 SHA256 校验失败，未运行安装器。"
                    exit 1
                fi
            done
            mkdir "$staging/source" &&
                tar -xzf "$staging/source.tar.gz" --strip-components=1 -C "$staging/source" || exit 1
            # 本仓库管理 rc，控制接口仅本地，并关闭自动面板下载。
            awk '
                /^detect_rc\(\) \{$/ {
                    print
                    print "    # oh-my-devboom manages Shell configuration."
                    print "    SHELL_RC_BASH= SHELL_RC_ZSH= SHELL_RC_FISH="
                    print "    return 0"
                    next
                }
                { print }
            ' "$staging/source/scripts/lib/common.sh" > "$staging/common.sh" &&
                mv "$staging/common.sh" "$staging/source/scripts/lib/common.sh" || exit 1
            # 仅本次安装使用已校验归档，跳过 yq 的 GitHub 最新版本查询。
            awk -v yq_version="$yq_version" '
                /^ZIP_BASE_DIR=/ {
                    print "ZIP_BASE_DIR=\"${CLASHCTL_BOOTSTRAP_ARCHIVES:-${CLASHCTL_SRC}/archives}\""
                    next
                }
                /^_resolve_version\(\) \{$/ {
                    print
                    print "    if [ \"$1\" = VERSION_YQ ] && [ -n \"${CLASHCTL_BOOTSTRAP_ARCHIVES:-}\" ]; then"
                    print "        VERSION_YQ=" yq_version
                    print "        VERSION_YQ_SOURCE=\"Gitee 镜像\""
                    print "        return 0"
                    print "    fi"
                    next
                }
                { print }
            ' "$staging/source/scripts/preflight.sh" > "$staging/preflight.sh" &&
                mv "$staging/preflight.sh" "$staging/source/scripts/preflight.sh" || exit 1
            sed -i 's/^external-controller:.*/external-controller: "127.0.0.1:9090"/; s/^external-ui-url:.*/external-ui-url: ""/; s/^external-ui:.*/external-ui: ""/' \
                "$staging/source/resources/mixin.yaml.example" || exit 1
            CI=1 CLASHCTL_DOWNLOAD_TIMEOUT=300 CLASHCTL_BOOTSTRAP_ARCHIVES="$staging/archives" \
                bash "$staging/source/install.sh" --local \
                --home "$clash_dir" --kernel mihomo --service "$service" --gh-proxy "${GITHUB_PROXY:-}" || exit 1
        ); then
            record_result failed Clash "clashctl 安装未完成：$clash_dir" '检查上方下载、权限或服务错误后重试，已安装的数据会保留。'
            return 1
        fi
        record_result installed Clash "clashctl ${commit:0:7}、Mihomo 和 yq 已准备；$clash_dir"
    else
        record_result ready Clash "复用现有 clashctl：$clash_dir"
    fi

    env_file=$(mktemp "$cache/clash-env.XXXXXX") || return 1
    chmod 600 "$env_file" || { rm -f -- "$env_file"; return 1; }
    bash "$ROOT_DIR/lib/clashctl.sh" "$clash_dir" "$CLASH_CONFIG_FILE" "$env_file" || result=$?
    if [[ "$result" == 0 ]]; then
        while IFS= read -r -d '' value; do proxy_values+=("$value"); done < "$env_file"
    fi
    rm -f -- "$env_file"
    if [[ "$result" != 0 || "${#proxy_values[@]}" != "${#proxy_names[@]}" ]]; then
        record_result failed Clash '代理配置、服务启动或联网检查失败，后续模块尚未启用代理。' \
            '检查上方错误与本地 YAML；修复后重新运行安装入口。'
        return 1
    fi
    for name in "${!proxy_names[@]}"; do
        export "${proxy_names[$name]}=${proxy_values[$name]}"
    done
    CLASH_PROXY_ACTIVE=1
    GITHUB_PROXY=''
    record_result configured Clash '代理已就绪；后续 GitHub 下载不再添加加速前缀，安装结束后自动关闭内核。'
}

cleanup_clash() {
    local clash_dir=$CLASH_CLEANUP_HOME result=0 CURRENT_MODULE=clash
    if [[ -f "$clash_dir/.env" && -f "$clash_dir/scripts/cmd/clashctl.sh" ]]; then
        bash "$ROOT_DIR/lib/clashctl.sh" --stop "$clash_dir" || result=$?
        if [[ "$result" == 0 ]]; then
            record_result configured Clash '代理内核已停止，程序及配置保留。'
        else
            record_result failed Clash "无法确认代理内核已停止：$clash_dir" \
                '加载该目录的 clashctl 后，运行 clashctl off --stop 检查并关闭。'
        fi
    fi
    CLASH_CLEANUP_HOME=''
    if [[ "${CLASH_PROXY_ACTIVE:-0}" == 1 ]]; then
        unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        CLASH_PROXY_ACTIVE=0
    fi
    return "$result"
}
