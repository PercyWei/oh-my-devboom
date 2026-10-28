#!/usr/bin/env bash

deploy_config() {
    local source_file=$1 destination=$2 copy_source=$1 staging backup stamp suffix=0 migrating=0
    if [ ! -f "$source_file" ]; then
        record_result failed "$destination" "配置源文件不存在或不是普通文件：$source_file" '请检查仓库文件是否完整后重试。'
        return 1
    fi
    if [ -L "$destination" ] && [ -f "$destination" ]; then
        # 先保留链接当前指向的内容，本次不替换为仓库预设。
        copy_source=$destination
        migrating=1
    elif [ -f "$destination" ] && cmp -s "$source_file" "$destination"; then
        record_result ready "$destination" '内容与仓库配置相同，无需重复部署。'
        return 0
    elif { [ -e "$destination" ] || [ -L "$destination" ]; } && [ "$CONFLICT_POLICY" = skip ]; then
        record_result skipped "$destination" '目标已存在，本次保留原配置。' \
            '如需备份后部署，请使用摘要中的重试命令，并将 --conflict 改为 backup。'
        return 2
    fi
    if ! mkdir -p "$(dirname "$destination")"; then
        record_result failed "$destination" '无法创建配置目标目录。' '请检查目标目录权限和上方文件操作错误后重试。'
        return 1
    fi
    staging=$(mktemp "$destination.tmp.XXXXXX") || {
        record_result failed "$destination" '无法创建临时配置文件。' '请检查目标目录权限后重试。'
        return 1
    }
    if ! cp -pL "$copy_source" "$staging"; then
        rm -f "$staging"
        record_result failed "$destination" "无法复制配置：$copy_source；原目标保持不变。" '请检查文件权限和可用磁盘空间后重试。'
        return 1
    fi
    if [ "$migrating" = 0 ] && { [ -e "$destination" ] || [ -L "$destination" ]; }; then
        stamp=$(date +%Y%m%d-%H%M%S)
        backup=$destination.backup.$stamp
        while [ -e "$backup" ] || [ -L "$backup" ]; do
            suffix=$((suffix + 1)); backup=$destination.backup.$stamp.$suffix
        done
        if ! mv "$destination" "$backup"; then
            rm -f "$staging"
            record_result failed "$destination" "无法将已有配置备份到 ${backup}。" '请检查目标目录权限和上方文件操作错误后重试。'
            return 1
        fi
        record_result backup "$destination" "原配置已备份到 ${backup}。"
    fi
    if ! mv -f "$staging" "$destination"; then
        rm -f "$staging"
        record_result failed "$destination" '无法部署配置文件。' '请检查目标路径与目录权限后重试；如已有备份，可从摘要中的备份路径恢复。'
        return 1
    fi
    if [ "$migrating" = 1 ]; then
        record_result configured "$destination" '已将软链接转换为普通文件，保留原链接指向的内容。'
    else
        record_result configured "$destination" "已复制配置：$source_file"
    fi
}
