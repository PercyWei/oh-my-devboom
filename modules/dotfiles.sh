#!/usr/bin/env bash

module_dotfiles() {
    local pair source destination ready result status=0
    local config_dir="$XDG_CONFIG_HOME/oh-my-devboom/zsh"
    local data_dir="$XDG_DATA_HOME/oh-my-devboom"
    local daemon_os=$OS daemon_arch=$ARCH
    if [[ "$OS" == macos ]]; then
        daemon_os=darwin
        [[ "$ARCH" != aarch64 ]] || daemon_arch=arm64
    fi
    for pair in zshrc git plugin-list powerlevel10k-preset homebrew clash eza bat fd zellij fzf zoxide plugins powerlevel10k-instant powerlevel10k; do
        source="$ROOT_DIR/config/zsh/modules/$pair.zsh"
        destination="$config_dir/$pair.zsh"
        ready=0
        case "$pair" in
            zshrc)
                source="$ROOT_DIR/config/zsh/zshrc"; destination="${ZDOTDIR:-$HOME}/.zshrc"; ready=1 ;;
            git)
                source="$ROOT_DIR/config/git/gitconfig"; destination="$HOME/.gitconfig"; ready=1 ;;
            plugin-list|plugins)
                if [[ "$pair" == plugin-list ]]; then
                    source="$ROOT_DIR/config/zsh/zsh_plugins.txt"
                    destination="$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt"
                fi
                if [[ -r "$XDG_CACHE_HOME/oh-my-devboom/zsh_plugins.zsh" ]]; then ready=1; fi
                ;;
            powerlevel10k-preset|powerlevel10k-instant|powerlevel10k)
                if [[ "$pair" == powerlevel10k-preset ]]; then
                    source="$ROOT_DIR/config/powerlevel10k/p10k.zsh"; destination="${ZDOTDIR:-$HOME}/.p10k.zsh"
                fi
                if [[ -r "$data_dir/powerlevel10k/powerlevel10k.zsh-theme" &&
                      -r "$data_dir/powerlevel10k/config/p10k-lean.zsh" &&
                      -x "$XDG_CACHE_HOME/oh-my-devboom/gitstatus/gitstatusd-$daemon_os-$daemon_arch" ]]; then ready=1; fi
                ;;
            homebrew)
                if [[ "$USER_ID" != 0 ]] && have brew; then ready=1; fi ;;
            clash)
                if [[ -r "$XDG_DATA_HOME/clashctl/scripts/cmd/clashctl.sh" &&
                      -r "$XDG_DATA_HOME/clashctl/.clashctl-format" &&
                      "$(cat "$XDG_DATA_HOME/clashctl/.clashctl-format")" == 1 ]]; then ready=1; fi
                ;;
            eza|zoxide|zellij) if have "$pair"; then ready=1; fi ;;
            bat) if ! have bat && have batcat; then ready=1; fi ;;
            fd) if ! have fd && have fdfind; then ready=1; fi ;;
            fzf) if have fzf && [[ -r "$data_dir/fzf/init.zsh" ]]; then ready=1; fi ;;
        esac
        # 未就绪组件不新增配置；已有文件软链接仍按原内容迁移。
        if [[ "$ready" == 0 ]] && ! { [[ -L "$destination" ]] && [[ -f "$destination" ]]; }; then continue; fi
        result=0
        deploy_config "$source" "$destination" || result=$?
        if [[ "$result" == 1 ]]; then
            status=1
        elif [[ "$result" == 2 && "$status" == 0 ]]; then
            status=2
        fi
    done
    return "$status"
}
