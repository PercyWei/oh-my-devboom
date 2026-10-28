#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/update-pins.sh COMMAND [arguments]

  zellij TAG             Pin a stable release and verify all four archives
  powerlevel10k REF      Pin a commit/tag and its matching gitstatusd archives
  antidote TAG           Pin a stable release tag and its actual commit
  plugin OWNER/REPO REF  Update one existing entry in the default plugin list

Examples:
  bash scripts/update-pins.sh zellij v0.45.1
  bash scripts/update-pins.sh powerlevel10k d05a1b00f9a61f9578bf9dc19b8451942dde8734
  bash scripts/update-pins.sh antidote v2.3.0
  bash scripts/update-pins.sh plugin zsh-users/zsh-syntax-highlighting 0.8.0

Requires Bash 3.2+, Git, curl, jq, shasum and tar. The target file must be clean.
Only repository pins are updated; installed software and user files are untouched.
Review the resulting diff and validate installation before committing an upgrade.
EOF
}

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
download() {
    curl -q --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 180 --retry 2 --output "$2" "$1"
}

action=${1:-}
case "$action" in
    -h|--help) usage; exit 0 ;;
    zellij|antidote)
        [[ $# == 2 && $2 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { usage >&2; exit 1; }
        ref=$2
        ;;
    powerlevel10k)
        [[ $# == 2 ]] || { usage >&2; exit 1; }
        ref=$2
        ;;
    plugin)
        [[ $# == 3 && $2 =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || { usage >&2; exit 1; }
        plugin=$2 ref=$3
        ;;
    *) usage >&2; exit 1 ;;
esac
[[ -n "$ref" && "$ref" != -* && "$ref" != *[!a-zA-Z0-9_./-]* ]] || fail 'Git 引用只能包含字母、数字、_、.、/、-，且不能以 - 开头。'

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case "$action" in
    zellij) target=modules/tools.sh ;;
    powerlevel10k) target=modules/powerlevel10k.sh ;;
    antidote) target=modules/antidote.sh ;;
    plugin)
        target=config/zsh/zsh_plugins.txt
        [[ "$(awk -v repo="$plugin" '$1 == repo { n++ } END { print n+0 }' "$root_dir/$target")" == 1 ]] ||
            fail '只允许更新默认插件清单中已有的唯一仓库。'
        ;;
esac
require_clean() {
    [[ -z "$(git -C "$root_dir" status --porcelain -- "$target")" ]] ||
        fail "请先保存或提交目标文件的已有变更：$target"
}
require_clean
for tool in git curl jq shasum tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "缺少命令：$tool"
done

umask 077
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/devboom-update-pins.XXXXXX")
staged_file=''
trap 'rm -rf -- "$work_dir"; [[ -z "$staged_file" ]] || rm -f -- "$staged_file"' EXIT
hashes_file="$work_dir/hashes"
: > "$hashes_file"
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
    ' "$root_dir/$target" > "$updated_file" || fail '插件清单格式已变化，请先人工审查。'
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
    ' "$root_dir/$target" > "$updated_file" || fail '安装模块格式已变化，请先人工审查。'
    /bin/bash -n "$updated_file"
fi
require_clean
if cmp -s "$updated_file" "$root_dir/$target"; then
    printf '固定值已相同，无需修改：%s\n' "$target"
    exit 0
fi
staged_file=$(mktemp "$root_dir/$target.tmp.XXXXXX")
cp -p "$root_dir/$target" "$staged_file"
cat "$updated_file" > "$staged_file"
mv -- "$staged_file" "$root_dir/$target"
staged_file=''
printf '已更新 %s；请审阅 git diff 并在干净环境验证安装。\n' "$target"
