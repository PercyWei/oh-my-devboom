#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/update-pins.sh COMMAND [arguments]

  check [COMPONENT]       Compare pins with current upstream targets
                         COMPONENT: all (default), zellij, powerlevel10k,
                         antidote, clash, or plugin OWNER/REPO
  update COMPONENT [REF] [COMPONENT [REF] ...]
                         Update selected components after confirmation
  update all             Update Zellij, Powerlevel10k, Antidote and all default
                         plugins; gitstatusd follows the selected theme

Components:
  zellij [TAG]           Latest stable release, or an explicit vX.Y.Z tag
  powerlevel10k [REF]    Upstream HEAD, or an explicit commit/tag/branch
  antidote [TAG]         Latest stable release, or an explicit vX.Y.Z tag
  plugin OWNER/REPO [REF]
                         Upstream HEAD, or an explicit Git reference

Examples:
  bash scripts/update-pins.sh check all
  bash scripts/update-pins.sh update zellij powerlevel10k
  bash scripts/update-pins.sh update zellij v0.45.1 antidote v2.3.0
  bash scripts/update-pins.sh update plugin zsh-users/zsh-syntax-highlighting 0.8.0
  bash scripts/update-pins.sh update all

A component name starts the next selection. For a branch with the same name,
use its full reference, such as refs/heads/zellij. Explicit versions may be
older than the latest release; they must still satisfy installation checks.
Check requires Bash 3.2+, Git, curl and jq and does not modify repository files.
Updates also require shasum, tar and clean target files. All sources and archives
are verified before the plan and [y/N] confirmation; unchanged files are skipped.
Clash mirror publishing remains in scripts/update-clash.sh and is not in update all.
Installed software and user files are untouched. Review the diff before committing.
EOF
}

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
download() {
    curl -q --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 180 --retry 2 --output "$2" "$1"
}

latest_release() {
    download "https://api.github.com/repos/$1/releases/latest" - |
        jq -er 'select(.draft == false and .prerelease == false) | .tag_name | select(type == "string" and length > 0)'
}

remote_commit() {
    local repo=$1 git_ref=$2
    GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 \
        ls-remote --exit-code "https://github.com/$repo.git" "$git_ref" "$git_ref^{}" |
        awk -v ref="$git_ref" '
            $2 == ref { direct=$1 }
            $2 == ref "^{}" { peeled=$1 }
            END {
                commit=(peeled != "" ? peeled : direct)
                if (commit !~ /^[0-9a-f]+$/ || length(commit) != 40) exit 1
                print commit
            }
        '
}

read_pin() {
    awk -v name="$2" '
        $0 ~ "^    local " name "=" { sub("^    local " name "=", ""); value=$0; n++ }
        END { if (n != 1 || value == "") exit 1; print value }
    ' "$root_dir/$1"
}

plugin_pin() {
    awk -v repo="$1" '
        $1 == repo { for (i=2; i<=NF; i++) if ($i ~ /^pin:/) { value=substr($i,5); n++ } }
        END {
            if (n != 1 || value !~ /^[0-9a-f]+$/ || length(value) != 40) exit 1
            print value
        }
    ' "$root_dir/config/zsh/zsh_plugins.txt"
}

display_pin() {
    local value=$1
    if [[ "$value" == *@* ]]; then
        printf '%s@%.12s' "${value%@*}" "${value##*@}"
    elif [[ "$value" =~ ^[0-9a-f]{40}$ ]]; then
        printf '%.12s' "$value"
    else
        printf '%s' "$value"
    fi
}

report_pin() {
    printf '%-42s %-24s %-24s %s\n' "$1" "$(display_pin "$2")" "$(display_pin "$3")" "$4"
}

check_pin() {
    local component=$1 repo file variable mode current latest current_tag latest_tag commit
    case "$component" in
        zellij) repo=zellij-org/zellij; file=modules/tools.sh; variable=version; mode=release ;;
        powerlevel10k) repo=romkatv/powerlevel10k; file=modules/powerlevel10k.sh; variable=theme_commit; mode='head' ;;
        gitstatus) repo=romkatv/gitstatus; file=modules/powerlevel10k.sh; variable=gitstatus_version; mode=release ;;
        antidote) repo=mattmc3/antidote; file=modules/antidote.sh; variable=antidote_commit; mode=antidote ;;
        clashctl) repo=nelvko/clashctl; file=modules/clash.sh; variable=commit; mode='head' ;;
        mihomo) repo=MetaCubeX/mihomo; file=modules/clash.sh; variable=mihomo_version; mode=release ;;
        yq) repo=mikefarah/yq; file=modules/clash.sh; variable=yq_version; mode=release ;;
        plugin) repo=$2; mode=plugin ;;
    esac
    case "$mode" in
        plugin) current=$(plugin_pin "$repo") ;;
        antidote)
            commit=$(read_pin "$file" "$variable") &&
                current_tag=$(read_pin "$file" antidote_version) && current="$current_tag@$commit"
            ;;
        *) current=$(read_pin "$file" "$variable") ;;
    esac || { report_pin "$repo" - - '读取失败'; return 1; }
    case "$mode" in
        head|plugin) latest=$(remote_commit "$repo" HEAD) ;;
        antidote)
            latest_tag=$(latest_release "$repo") &&
                commit=$(remote_commit "$repo" "refs/tags/$latest_tag") && latest="$latest_tag@$commit"
            ;;
        release) latest=$(latest_release "$repo") ;;
    esac || { report_pin "$repo" "$current" - '查询失败'; return 1; }
    if [[ "$current" == "$latest" ]]; then
        report_pin "$repo" "$current" "$latest" '相同'
    else
        report_pin "$repo" "$current" "$latest" '不同'
    fi
}

check_components() {
    local selected=$1 component repo repositories check_result=0
    printf '%-42s %-24s %-24s %s\n' REPOSITORY PINNED UPSTREAM STATUS
    case "$selected" in
        all)
            for component in zellij powerlevel10k gitstatus antidote clashctl mihomo yq; do
                check_pin "$component" || check_result=1
            done
            if repositories=$(awk '$1 !~ /^#/ { for (i=2; i<=NF; i++) if ($i ~ /^pin:/) print $1 }' "$root_dir/config/zsh/zsh_plugins.txt"); then
                for repo in $repositories; do check_pin plugin "$repo" || check_result=1; done
            else
                printf '错误：无法读取默认插件清单。\n' >&2
                check_result=1
            fi
            ;;
        powerlevel10k)
            check_pin powerlevel10k || check_result=1
            check_pin gitstatus || check_result=1
            ;;
        clash)
            for component in clashctl mihomo yq; do check_pin "$component" || check_result=1; done
            ;;
        plugin) check_pin plugin "$plugin" || check_result=1 ;;
        *) check_pin "$selected" || check_result=1 ;;
    esac
    printf '\n不同仅表示上游目标不一致；gitstatus 实际更新仍服从主题声明。\n'
    return "$check_result"
}

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
require_plugin() {
    [[ "$1" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || fail "插件仓库格式应为 OWNER/REPO：$1"
    [[ "$(awk -v repo="$1" '$1 == repo { n++ } END { print n+0 }' "$root_dir/config/zsh/zsh_plugins.txt")" == 1 ]] ||
        fail "只允许选择默认插件清单中已有的唯一仓库：$1"
}

command_name=${1:-}
plugin=''
case "$command_name" in
    -h|--help) usage; exit 0 ;;
    check)
        [[ $# -le 3 ]] || { usage >&2; exit 1; }
        component=${2-all}
        case "$component" in
            all|zellij|powerlevel10k|antidote|clash) [[ $# -le 2 ]] || { usage >&2; exit 1; } ;;
            plugin)
                [[ $# == 3 ]] || { usage >&2; exit 1; }
                plugin=$3
                require_plugin "$plugin"
                ;;
            *) usage >&2; exit 1 ;;
        esac
        for tool in git curl jq; do
            command -v "$tool" >/dev/null 2>&1 || fail "缺少命令：$tool"
        done
        check_components "$component"
        exit $?
        ;;
    update) shift ;;
    '') usage >&2; exit 1 ;;
    *) fail "未知命令：${command_name}；请使用 check 或 update。" ;;
esac

is_component() {
    case "$1" in zellij|powerlevel10k|antidote|plugin|all|update|check) return 0 ;; *) return 1 ;; esac
}

selection_count=0 file_count=0
selection_actions=() selection_plugins=() selection_refs=() selection_targets=() files=()
add_selection() {
    local action=$1 selected_plugin=$2 ref=$3 target index found=0
    case "$action" in
        zellij|antidote)
            [[ -z "$ref" || "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
                fail "$action 的版本应为 vX.Y.Z：$ref"
            ;;
    esac
    [[ -z "$ref" || ( "$ref" != -* && "$ref" != *[!a-zA-Z0-9_./-]* ) ]] ||
        fail 'Git 引用只能包含字母、数字、_、.、/、-，且不能以 - 开头。'
    for ((index=0; index<selection_count; index++)); do
        [[ "${selection_actions[$index]}" != "$action" || "${selection_plugins[$index]}" != "$selected_plugin" ]] ||
            fail "重复选择组件：$action${selected_plugin:+ $selected_plugin}"
    done
    case "$action" in
        zellij) target=modules/tools.sh ;;
        powerlevel10k) target=modules/powerlevel10k.sh ;;
        antidote) target=modules/antidote.sh ;;
        plugin) require_plugin "$selected_plugin"; target=config/zsh/zsh_plugins.txt ;;
    esac
    selection_actions[$selection_count]=$action
    selection_plugins[$selection_count]=$selected_plugin
    selection_refs[$selection_count]=$ref
    selection_targets[$selection_count]=$target
    selection_count=$((selection_count + 1))
    for ((index=0; index<file_count; index++)); do
        if [[ "${files[$index]}" == "$target" ]]; then found=1; break; fi
    done
    if [[ "$found" == 0 ]]; then
        files[$file_count]=$target
        file_count=$((file_count + 1))
    fi
}

update_all=0
[[ $# -gt 0 ]] || { usage >&2; exit 1; }
if [[ "$1" == all ]]; then
    [[ $# == 1 ]] || fail 'all 只能单独用于 update all。'
    update_all=1
    add_selection zellij '' ''
    add_selection powerlevel10k '' ''
    add_selection antidote '' ''
    repositories=$(awk '$1 !~ /^#/ { for (i=2; i<=NF; i++) if ($i ~ /^pin:/) print $1 }' "$root_dir/config/zsh/zsh_plugins.txt")
    for repo in $repositories; do add_selection plugin "$repo" ''; done
else
    while [[ $# -gt 0 ]]; do
        action=$1 plugin='' ref=''
        shift
        case "$action" in
            zellij|powerlevel10k|antidote) ;;
            plugin)
                [[ $# -gt 0 ]] || fail 'plugin 后需要指定 OWNER/REPO。'
                plugin=$1
                shift
                ;;
            *) fail "未知更新组件：${action}；可用 zellij、powerlevel10k、antidote、plugin，或 update all。" ;;
        esac
        if [[ $# -gt 0 ]] && ! is_component "$1"; then
            [[ -n "$1" ]] || fail '版本或 Git 引用不能为空。'
            ref=$1
            shift
        fi
        add_selection "$action" "$plugin" "$ref"
    done
fi
for tool in git curl jq shasum tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "缺少命令：$tool"
done

require_clean() {
    local status
    status=$(git -C "$root_dir" status --porcelain -- "$1") || fail "无法检查目标文件状态：$1"
    [[ -z "$status" ]] || fail "请先保存或提交目标文件的已有变更：$1"
}
for ((index=0; index<file_count; index++)); do require_clean "${files[$index]}"; done

umask 077
batch_dir=$(mktemp -d "${TMPDIR:-/tmp}/devboom-update-pins.XXXXXX")
replacement_count=0 replacements=()
cleanup() {
    local index
    rm -rf -- "$batch_dir"
    for ((index=0; index<replacement_count; index++)); do rm -f -- "${replacements[$index]}"; done
}
trap cleanup EXIT
for ((index=0; index<file_count; index++)); do
    target=${files[$index]}
    mkdir -p "$batch_dir/original/$(dirname "$target")" "$batch_dir/files/$(dirname "$target")"
    cp -p "$root_dir/$target" "$batch_dir/original/$target"
    cp -p "$root_dir/$target" "$batch_dir/files/$target"
done
: > "$batch_dir/plan"
platforms=(linux:x86_64 linux:aarch64 macos:x86_64 macos:aarch64)

fetch_source() {
    local repo=$1 git_ref=$2
    git init -q "$work_dir/source"
    git -C "$work_dir/source" remote add origin "https://github.com/$repo.git"
    GIT_TERMINAL_PROMPT=0 git -C "$work_dir/source" -c http.lowSpeedLimit=1 \
        -c http.lowSpeedTime=60 fetch --quiet --depth 1 origin "$git_ref"
    source_commit=$(git -C "$work_dir/source" rev-parse --verify 'FETCH_HEAD^{commit}')
    [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail '上游提交不符合当前 40 位 SHA-1 固定格式。'
    git -C "$work_dir/source" checkout --quiet --detach "$source_commit"
    printf '已核实 %s：%s -> %s\n' "$repo" "$git_ref" "$source_commit"
}

verify_archive() {
    local url=$1 expected=$2 binary=$3 archive="$work_dir/$3.tar.gz" actual
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "上游摘要格式错误：$binary"
    printf '下载并校验：%s\n' "$url"
    download "$url" "$archive"
    actual=$(shasum -a 256 "$archive"); actual=${actual%% *}
    [[ "$actual" == "$expected" ]] || fail "SHA-256 不符：$binary"
    tar -tzf "$archive" | awk -v name="$binary" '$0 == name { found=1 } END { exit !found }' ||
        fail "归档缺少安装器要求的文件：$binary"
}

plan_pin() {
    local status='相同'
    if [[ "$4" == 1 ]]; then
        if [[ "$2" == "$3" ]]; then status='内容变化'; else status='更新'; fi
    fi
    report_pin "$1" "$2" "$3" "$status" >> "$batch_dir/plan"
}

prepare_update() (
    action=$1 plugin=$2 ref=$3 target=$4
    work_dir="$batch_dir/item-$5"
    input_file="$batch_dir/files/$target"
    mkdir "$work_dir"
    hashes_file="$work_dir/hashes"
    : > "$hashes_file"
    case "$action" in
        zellij) repo=zellij-org/zellij ;;
        powerlevel10k) repo=romkatv/powerlevel10k ;;
        antidote) repo=mattmc3/antidote ;;
        plugin) repo=$plugin ;;
    esac
    if [[ -z "$ref" ]]; then
        case "$action" in
            zellij|antidote)
                ref=$(latest_release "$repo") || fail "无法查询 $repo 的最新稳定 Release。"
                [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "上游 Release tag 格式不符合当前安装器要求：$ref"
                ;;
            powerlevel10k|plugin) ref=HEAD ;;
        esac
    fi
    version_name='' version_value='' commit_name='' commit_value=''
    case "$action" in
        zellij)
            download "https://api.github.com/repos/zellij-org/zellij/releases/tags/$ref" "$work_dir/release.json"
            jq -e --arg tag "$ref" '.tag_name == $tag and .draft == false and .prerelease == false' \
                "$work_dir/release.json" >/dev/null || fail '目标必须是已发布的稳定 Zellij Release。'
            assets=(x86_64-unknown-linux-musl aarch64-unknown-linux-musl x86_64-apple-darwin aarch64-apple-darwin)
            for ((index=0; index<4; index++)); do
                asset="zellij-${assets[$index]}.tar.gz"
                digest=$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .digest | capture("^sha256:(?<hash>[0-9a-f]{64})$").hash' "$work_dir/release.json") ||
                    fail "官方 Release 缺少有效 SHA-256：$asset"
                url=$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url' "$work_dir/release.json") ||
                    fail "官方 Release 缺少下载地址：$asset"
                verify_archive "$url" "$digest" zellij
                printf '%s\t%s\n' "${platforms[$index]}" "$digest" >> "$hashes_file"
            done
            version_name=version version_value=$ref
            ;;
        powerlevel10k)
            fetch_source romkatv/powerlevel10k "$ref"
            [[ -f "$work_dir/source/powerlevel10k.zsh-theme" && -f "$work_dir/source/config/p10k-lean.zsh" &&
               -f "$work_dir/source/gitstatus/install.info" ]] || fail 'Powerlevel10k 安装接口已变化，请先人工审查。'
            kernels=(linux linux darwin darwin)
            machines=(x86_64 aarch64 x86_64 arm64)
            gitstatus_version=''
            for ((index=0; index<4; index++)); do
                metadata=$(awk -F '"' -v kernel="${kernels[$index]}" -v machine="${machines[$index]}" '
                    $1 == "uname_s_glob=" && $2 == kernel && $4 == machine {
                        if (NF != 11 || $6 != "gitstatusd-${uname_s}-${uname_m}" ||
                            $8 !~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ || $10 !~ /^[0-9a-f]+$/ || length($10) != 64) exit 1
                        n++; print $8 "\t" $10
                    }
                    END { if (n != 1) exit 1 }
                ' "$work_dir/source/gitstatus/install.info") || fail 'gitstatus/install.info 格式已变化，请先人工审查。'
                IFS=$'\t' read -r daemon_version digest <<< "$metadata"
                [[ -z "$gitstatus_version" || "$gitstatus_version" == "$daemon_version" ]] ||
                    fail '四个平台的 gitstatusd 版本不一致，当前安装器需要人工调整。'
                gitstatus_version=$daemon_version
                binary="gitstatusd-${kernels[$index]}-${machines[$index]}"
                verify_archive "https://github.com/romkatv/gitstatus/releases/download/$daemon_version/$binary.tar.gz" "$digest" "$binary"
                printf '%s\t%s\n' "${platforms[$index]}" "$digest" >> "$hashes_file"
            done
            version_name=gitstatus_version version_value=$gitstatus_version
            commit_name=theme_commit commit_value=$source_commit
            ;;
        antidote)
            fetch_source mattmc3/antidote "refs/tags/$ref"
            [[ -f "$work_dir/source/antidote.zsh" && -f "$work_dir/source/functions/antidote-load" ]] ||
                fail 'Antidote 安装接口已变化，请先人工审查。'
            version_name=antidote_version version_value=$ref
            commit_name=antidote_commit commit_value=$source_commit
            ;;
        plugin)
            fetch_source "$plugin" "$ref"
            ;;
    esac

    updated_file="$work_dir/updated"
    if [[ "$action" == plugin ]]; then
        awk -v repo="$plugin" -v commit="$source_commit" '
            $1 == repo {
                for (i=2; i<=NF; i++) if ($i ~ /^pin:/) {
                    old=substr($i,5)
                    if (old !~ /^[0-9a-f]+$/ || length(old) != 40) exit 1
                    sub("pin:" old, "pin:" commit); n++
                }
            }
            { print }
            END { if (n != 1) exit 1 }
        ' "$input_file" > "$updated_file" || fail '插件清单格式已变化，请先人工审查。'
    else
        awk -v hashes_file="$hashes_file" -v version_name="$version_name" -v version="$version_value" \
            -v commit_name="$commit_name" -v commit="$commit_value" '
            BEGIN {
                while ((getline < hashes_file) > 0) { hashes[$1]=$2; expected_hashes++ }
                close(hashes_file)
            }
            version_name != "" && $0 ~ "^    local " version_name "=" {
                print "    local " version_name "=" version; versions++; next
            }
            commit_name != "" && $0 ~ "^    local " commit_name "=" {
                print "    local " commit_name "=" commit; commits++; next
            }
            /^        (linux|macos):(x86_64|aarch64)\)/ { platform=$1; sub(/\)$/, "", platform) }
            /^[[:space:]]*sha256=/ && platform in hashes {
                if (length(substr($1,8)) != 64 || !sub(/sha256=[0-9a-f]+/, "sha256=" hashes[platform])) exit 1
                changed_hashes++
            }
            { print }
            END {
                if (versions != (version_name != "") || commits != (commit_name != "") ||
                    changed_hashes != expected_hashes) exit 1
            }
        ' "$input_file" > "$updated_file" || fail '安装模块格式已变化，请先人工审查。'
        /bin/bash -n "$updated_file"
    fi
    changed=0
    if ! cmp -s "$input_file" "$updated_file"; then changed=1; fi
    case "$action" in
        zellij)
            current=$(read_pin "$target" version)
            plan_pin "$repo" "$current" "$version_value" "$changed"
            ;;
        powerlevel10k)
            current=$(read_pin "$target" theme_commit)
            plan_pin "$repo" "$current" "$commit_value" "$changed"
            current=$(read_pin "$target" gitstatus_version)
            report_pin romkatv/gitstatus "$current" "$version_value" '随主题' >> "$batch_dir/plan"
            ;;
        antidote)
            current_version=$(read_pin "$target" antidote_version)
            current_commit=$(read_pin "$target" antidote_commit)
            plan_pin "$repo" "$current_version@$current_commit" "$version_value@$commit_value" "$changed"
            ;;
        plugin)
            current=$(plugin_pin "$plugin")
            plan_pin "$repo" "$current" "$source_commit" "$changed"
            ;;
    esac
    mv -- "$updated_file" "$input_file"
)

if [[ "$update_all" == 1 ]]; then
    printf '更新范围：Zellij、Powerlevel10k（含配套 gitstatus）、Antidote 和默认插件。\n'
    printf 'Clash 镜像发布需单独使用 scripts/update-clash.sh。\n'
fi
for ((index=0; index<selection_count; index++)); do
    prepare_update "${selection_actions[$index]}" "${selection_plugins[$index]}" \
        "${selection_refs[$index]}" "${selection_targets[$index]}" "$index"
done

require_unchanged() {
    local index target
    for ((index=0; index<file_count; index++)); do
        target=${files[$index]}
        require_clean "$target"
        cmp -s "$batch_dir/original/$target" "$root_dir/$target" ||
            fail "准备期间目标文件发生变化，请重新运行：$target"
    done
}
require_unchanged
changed_count=0 changed_targets=()
for ((index=0; index<file_count; index++)); do
    target=${files[$index]}
    if ! cmp -s "$batch_dir/original/$target" "$batch_dir/files/$target"; then
        changed_targets[$changed_count]=$target
        changed_count=$((changed_count + 1))
    fi
done
printf '\n更新计划（来源与归档已核对）：\n'
printf '%-42s %-24s %-24s %s\n' REPOSITORY CURRENT TARGET STATUS
cat "$batch_dir/plan"
if [[ "$changed_count" == 0 ]]; then
    printf '\n固定值与校验信息已相同，无需修改。\n'
    exit 0
fi
printf '\n将更新 %s 个仓库文件。是否写入以上更新？[y/N] ' "$changed_count"
answer=''
if ! IFS= read -r answer; then answer=''; fi
case "$answer" in
    y|Y|[Yy][Ee][Ss]) ;;
    *) printf '已取消，仓库文件未修改。\n' >&2; exit 1 ;;
esac
require_unchanged
# 先准备好所有同目录替换文件，再逐个原子替换；磁盘故障仍可能留下部分更新。
for ((index=0; index<changed_count; index++)); do
    target=${changed_targets[$index]}
    replacement=$(mktemp "$root_dir/$target.tmp.XXXXXX")
    replacements[$replacement_count]=$replacement
    replacement_count=$((replacement_count + 1))
    cp -p "$root_dir/$target" "$replacement"
    cat "$batch_dir/files/$target" > "$replacement"
done
require_unchanged
for ((index=0; index<changed_count; index++)); do
    mv -- "${replacements[$index]}" "$root_dir/${changed_targets[$index]}"
    printf '已更新 %s\n' "${changed_targets[$index]}"
done
printf '请审阅 git diff 并在干净环境验证安装；变更尚未提交。\n'
