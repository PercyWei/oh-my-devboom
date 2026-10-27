#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/update-clash.sh COMMAND [versions]

  sync                         Sync upstream master to GitHub and Gitee
  source COMMIT                Sync and pin a reviewed 40-character commit
  packages MIHOMO_VERSION YQ_VERSION
                               Mirror stable releases, then update local pins

Examples:
  bash scripts/update-clash.sh sync
  bash scripts/update-clash.sh source e38d643725594c38c3fb02f355a2c89eba9c296c
  bash scripts/update-clash.sh packages v1.19.33 v4.54.1

Requires gh and gitee login, Git, jq, curl and shasum.
GITEE_BIN selects the CLI executable; CLASHCTL_REPO_DIR selects the local clone
(default: ../clashctl). Existing assets are verified and reused, never replaced.
The script does not install software, delete releases or commit local changes.
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
    sync) [[ $# == 1 ]] || { usage >&2; exit 1; } ;;
    source)
        [[ $# == 2 && $2 =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 1; }
        source_commit=$2
        ;;
    packages)
        [[ $# == 3 && $2 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && $3 =~ ^v4\.[0-9]+\.[0-9]+$ ]] || { usage >&2; exit 1; }
        mihomo_version=$2 yq_version=$3
        ;;
    *) usage >&2; exit 1 ;;
esac

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pins_file="$root_dir/modules/clash.sh"
github_repo=PercyWei/clashctl
gitee_repo=back_door/clashctl
mirror_dir=${CLASHCTL_REPO_DIR:-$root_dir/../clashctl}
GITEE_BIN=${GITEE_BIN:-gitee}
for tool in git gh "$GITEE_BIN" jq curl shasum; do
    command -v "$tool" >/dev/null 2>&1 || fail "缺少命令：$tool"
done
GITEE_BIN=$(command -v "$GITEE_BIN")
export GITEE_BIN
[[ "$(gh api user --jq .login)" == PercyWei ]] || fail '请使用 gh 登录 PercyWei。'
[[ "$("$GITEE_BIN" api /user --hostname gitee.com | jq -er .login)" == back_door ]] || fail '请使用 gitee 登录 back_door。'
if [[ "$action" != sync ]]; then
    [[ -z "$(git -C "$root_dir" status --porcelain -- modules/clash.sh README.md config/default.conf)" ]] ||
        fail '请先保存或提交安装模块、README 和默认配置的已有变更。'
fi

umask 077
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/devboom-clash-update.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

sync_source() {
    gh repo sync "$github_repo" --source nelvko/clashctl --branch master
    if [[ ! -d "$mirror_dir" ]]; then
        git clone --no-checkout "https://github.com/$github_repo.git" "$mirror_dir"
    fi
    git -C "$mirror_dir" fetch "https://github.com/$github_repo.git" master
    cat > "$work_dir/askpass" <<'EOF'
#!/bin/sh
case "$1" in
    *Username*) printf '%s\n' back_door ;;
    *Password*) exec "$GITEE_BIN" auth token --hostname gitee.com ;;
    *) exit 1 ;;
esac
EOF
    chmod 700 "$work_dir/askpass"
    GIT_ASKPASS="$work_dir/askpass" GIT_TERMINAL_PROMPT=0 LC_ALL=C \
        git -C "$mirror_dir" -c credential.helper= push \
        "https://gitee.com/$gitee_repo.git" FETCH_HEAD:refs/heads/master
}

if [[ "$action" == sync || "$action" == source ]]; then
    sync_source
    if [[ "$action" == sync ]]; then
        printf '源码镜像已同步；本项目固定版本未修改。\n'
        exit 0
    fi
    git -C "$mirror_dir" merge-base --is-ancestor "$source_commit" FETCH_HEAD || fail '指定提交不在上游 master 历史中。'
    download "https://gitee.com/$gitee_repo/repository/archive/$source_commit.tar.gz" "$work_dir/source.tar.gz"
    source_sha256=$(shasum -a 256 "$work_dir/source.tar.gz"); source_sha256=${source_sha256%% *}
    mkdir "$work_dir/source"
    tar -xzf "$work_dir/source.tar.gz" --strip-components=1 -C "$work_dir/source"
    # 固定安装器适配依赖这些入口；行为变化仍需人工审查。
    grep -q '^detect_rc() {$' "$work_dir/source/scripts/lib/common.sh" &&
        grep -q '^ZIP_BASE_DIR=' "$work_dir/source/scripts/preflight.sh" &&
        grep -q '^_resolve_version() {$' "$work_dir/source/scripts/preflight.sh" || fail '上游安装接口已变化，请先调整适配。'
    old_commit=$(awk -F= '/^    local commit=/{print $2}' "$pins_file")
    awk -v commit="$source_commit" -v sha="$source_sha256" '
        /^    local commit=/ { print "    local commit=" commit; next }
        /^    local archive_sha256=/ { print "    local archive_sha256=" sha; next }
        { print }
    ' "$pins_file" > "$work_dir/clash.sh"
    awk -v old="$old_commit" -v new="$source_commit" '{
        gsub(old, new)
        gsub("`" substr(old, 1, 7) "`", "`" substr(new, 1, 7) "`")
        print
    }' "$root_dir/README.md" > "$work_dir/README.md"
    cp "$work_dir/clash.sh" "$pins_file"
    cp "$work_dir/README.md" "$root_dir/README.md"
    printf '已固定 clashctl %s；请审阅安装器适配和 git diff，再用新容器复核。变更尚未提交。\n' "$source_commit"
    exit 0
fi

gh api "repos/MetaCubeX/mihomo/releases/tags/$mihomo_version" > "$work_dir/mihomo.json"
gh api "repos/mikefarah/yq/releases/tags/$yq_version" > "$work_dir/yq.json"
files=("mihomo-linux-amd64-v1-$mihomo_version.gz" "mihomo-linux-arm64-$mihomo_version.gz"
       yq_linux_amd64.tar.gz yq_linux_arm64.tar.gz)
for file in "${files[@]}"; do
    case "$file" in mihomo-*) metadata="$work_dir/mihomo.json" ;; *) metadata="$work_dir/yq.json" ;; esac
    url=$(jq -er --arg name "$file" '.assets[] | select(.name == $name) | .browser_download_url' "$metadata")
    expected=$(jq -er --arg name "$file" '.assets[] | select(.name == $name) | .digest | capture("^sha256:(?<hash>[0-9a-f]{64})$").hash' "$metadata")
    printf '下载上游安装包：%s\n' "$file"
    download "$url" "$work_dir/$file"
    actual=$(shasum -a 256 "$work_dir/$file"); actual=${actual%% *}
    [[ "$actual" == "$expected" ]] || fail "上游安装包 SHA-256 不符：$file"
done
source_file="mihomo-$mihomo_version-source.tar.gz"
download "https://github.com/MetaCubeX/mihomo/archive/refs/tags/$mihomo_version.tar.gz" "$work_dir/$source_file"
gh api "repos/MetaCubeX/mihomo/contents/LICENSE?ref=$mihomo_version" -H 'Accept: application/vnd.github.raw+json' > "$work_dir/LICENSE.mihomo"
gh api "repos/mikefarah/yq/contents/LICENSE?ref=$yq_version" -H 'Accept: application/vnd.github.raw+json' > "$work_dir/LICENSE.yq"
files+=("$source_file" LICENSE.mihomo LICENSE.yq)
(cd "$work_dir" && shasum -a 256 "${files[@]}" > SHA256SUMS)
files+=(SHA256SUMS)

tag="mihomo-$mihomo_version-yq-$yq_version"
release_id='' page=1
while :; do
    releases=$("$GITEE_BIN" api "/repos/$gitee_repo/releases?per_page=100&page=$page" --hostname gitee.com)
    release_id=$(printf '%s' "$releases" | jq -r --arg tag "$tag" '.[] | select(.tag_name == $tag) | .id')
    [[ -z "$release_id" && "$(printf '%s' "$releases" | jq length)" == 100 ]] || break
    page=$((page + 1))
done
if [[ -z "$release_id" ]]; then
    target=$(awk -F= '/^    local commit=/{print $2}' "$pins_file")
    notes="Clash 首次安装依赖：Mihomo $mihomo_version、yq $yq_version，支持 Linux x86_64/aarch64。
安装包与 GitHub Release asset digest 核对；附 SHA256SUMS、许可文件及对应 Mihomo 源码。
上游：https://github.com/MetaCubeX/mihomo/releases/tag/$mihomo_version
https://github.com/mikefarah/yq/releases/tag/$yq_version"
    "$GITEE_BIN" release create --repo "$gitee_repo" --hostname gitee.com --tag "$tag" \
        --target "$target" --name "Clash bootstrap: Mihomo $mihomo_version + yq $yq_version" --body "$notes"
    release_id=$("$GITEE_BIN" release view "$tag" --repo "$gitee_repo" --hostname gitee.com --json=id | jq -er .id)
fi
"$GITEE_BIN" api "/repos/$gitee_repo/releases/$release_id/attach_files?per_page=100" \
    --hostname gitee.com > "$work_dir/attachments.json"
for file in "${files[@]}"; do
    if ! jq -e --arg name "$file" 'any(.[]; .name == $name)' "$work_dir/attachments.json" >/dev/null; then
        printf '上传 Gitee：%s\n' "$file"
        # 凭据只经标准输入传给 curl，不写入参数、日志或临时文件。
        "$GITEE_BIN" auth token --hostname gitee.com | tr -d '\r\n' |
            curl -q --fail --silent --show-error --connect-timeout 15 --max-time 300 \
                --form 'access_token=<-' --form "file=@$work_dir/$file" \
                "https://gitee.com/api/v5/repos/$gitee_repo/releases/$release_id/attach_files" \
                > "$work_dir/upload.json"
        jq -e '.id' "$work_dir/upload.json" >/dev/null
    fi
    download "https://gitee.com/$gitee_repo/releases/download/$tag/$file" "$work_dir/mirror-$file"
    cmp -s "$work_dir/$file" "$work_dir/mirror-$file" || fail "Gitee 附件内容不同，已保留原文件：$file"
done

old_mihomo=$(awk -F= '/^    local mihomo_version=/{print $2}' "$pins_file")
old_yq=$(awk -F= '/^    local yq_version=/{print $2}' "$pins_file")
awk -v m="$mihomo_version" -v y="$yq_version" '
    NR == FNR { hashes[$2] = $1; next }
    /^    local mihomo_version=/ { print "    local mihomo_version=" m; next }
    /^    local yq_version=/ { print "    local yq_version=" y; next }
    /^    local mihomo_amd64_sha256=/ { print "    local mihomo_amd64_sha256=" hashes["mihomo-linux-amd64-v1-" m ".gz"]; next }
    /^    local mihomo_arm64_sha256=/ { print "    local mihomo_arm64_sha256=" hashes["mihomo-linux-arm64-" m ".gz"]; next }
    /^    local yq_amd64_sha256=/ { print "    local yq_amd64_sha256=" hashes["yq_linux_amd64.tar.gz"]; next }
    /^    local yq_arm64_sha256=/ { print "    local yq_arm64_sha256=" hashes["yq_linux_arm64.tar.gz"]; next }
    { print }
' "$work_dir/SHA256SUMS" "$pins_file" > "$work_dir/clash.sh"
for doc in README.md config/default.conf; do
    sed "s/${old_mihomo//./\\.}/$mihomo_version/g; s/${old_yq//./\\.}/$yq_version/g" \
        "$root_dir/$doc" > "$work_dir/$(basename "$doc")"
done
cp "$work_dir/clash.sh" "$pins_file"
cp "$work_dir/README.md" "$root_dir/README.md"
cp "$work_dir/default.conf" "$root_dir/config/default.conf"
printf '已发布并核对 %s，固定版本与文档已更新。请审阅 git diff 并用新容器复核；变更尚未提交。\n' "$tag"
