#!/usr/bin/env bash

link_config() {
    local source_file=$1 destination=$2 backup stamp suffix=0
    if [ ! -e "$source_file" ]; then log_error "Missing config source: $source_file"; return 1; fi
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source_file" ]; then
        log_info "Already linked: $destination"
        return 0
    fi
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        case "$CONFLICT_POLICY" in
            skip) log_warn "Config exists; skipped: $destination (use --conflict backup to replace)"; return 2 ;;
            backup)
                stamp=$(date +%Y%m%d-%H%M%S)
                backup=$destination.backup.$stamp
                while [ -e "$backup" ] || [ -L "$backup" ]; do
                    suffix=$((suffix + 1)); backup=$destination.backup.$stamp.$suffix
                done
                mv "$destination" "$backup" || return 1
                log_info "Backed up: $destination -> $backup"
                ;;
        esac
    fi
    mkdir -p "$(dirname "$destination")" || return 1
    ln -s "$source_file" "$destination" || return 1
    log_info "Linked: $destination"
}
