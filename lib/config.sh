#!/usr/bin/env bash

link_config() {
    local source_file=$1 destination=$2 backup stamp suffix=0
    if [ ! -e "$source_file" ]; then
        record_result failed "$destination" "配置源文件不存在：$source_file" '请检查仓库文件是否完整后重试。'
        return 1
    fi
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source_file" ]; then
        record_result ready "$destination" "已链接到 ${source_file}，无需重复部署。"
        return 0
    fi
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        case "$CONFLICT_POLICY" in
            skip)
                record_result skipped "$destination" '目标已存在，本次保留原文件。' \
                    '如需备份后部署，请使用 --modules dotfiles --conflict backup 重跑安装入口。'
                return 2
                ;;
            backup)
                stamp=$(date +%Y%m%d-%H%M%S)
                backup=$destination.backup.$stamp
                while [ -e "$backup" ] || [ -L "$backup" ]; do
                    suffix=$((suffix + 1)); backup=$destination.backup.$stamp.$suffix
                done
                if ! mv "$destination" "$backup"; then
                    record_result failed "$destination" "无法将已有配置备份到 ${backup}。" '请检查目标目录权限和上方文件操作错误后重试。'
                    return 1
                fi
                record_result backup "$destination" "原配置已备份到 ${backup}。"
                ;;
        esac
    fi
    if ! mkdir -p "$(dirname "$destination")"; then
        record_result failed "$destination" '无法创建配置目标目录。' '请检查目标目录权限和上方文件操作错误后重试。'
        return 1
    fi
    if ! ln -s "$source_file" "$destination"; then
        record_result failed "$destination" "无法创建指向 $source_file 的软链接。" '请检查目标路径与目录权限后重试；如已有备份，可从摘要中的备份路径恢复。'
        return 1
    fi
    record_result configured "$destination" "已创建软链接 → $source_file"
}
