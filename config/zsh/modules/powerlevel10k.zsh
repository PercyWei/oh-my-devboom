if [[ -r "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
    typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
    source "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k/powerlevel10k.zsh-theme"
    [[ ! -r "${ZDOTDIR:-$HOME}/.p10k.zsh" ]] || source "${ZDOTDIR:-$HOME}/.p10k.zsh"
fi
