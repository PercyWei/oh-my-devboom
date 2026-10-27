#!/usr/bin/env bash

module_dotfiles() {
    local pair source destination result status=0
    for pair in zshrc plugins git powerlevel10k; do
        case "$pair" in
            zshrc) source="$ROOT_DIR/config/zsh/zshrc"; destination="${ZDOTDIR:-$HOME}/.zshrc" ;;
            plugins) source="$ROOT_DIR/config/zsh/zsh_plugins.txt"; destination="$XDG_CONFIG_HOME/oh-my-devboom/zsh_plugins.txt" ;;
            git) source="$ROOT_DIR/config/git/gitconfig"; destination="$HOME/.gitconfig" ;;
            powerlevel10k) source="$ROOT_DIR/config/powerlevel10k/p10k.zsh"; destination="${ZDOTDIR:-$HOME}/.p10k.zsh" ;;
        esac
        result=0
        link_config "$source" "$destination" || result=$?
        if [[ "$result" == 1 ]]; then
            status=1
        elif [[ "$result" == 2 && "$status" == 0 ]]; then
            status=2
        fi
    done
    return "$status"
}
