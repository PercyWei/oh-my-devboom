export ANTIDOTE_HOME="$XDG_DATA_HOME/oh-my-devboom/plugins"
if [[ -r "$XDG_CACHE_HOME/oh-my-devboom/zsh_plugins.zsh" ]]; then
    export ZSH="$ANTIDOTE_HOME/github.com/ohmyzsh/ohmyzsh"
    zstyle ':omz:update' mode disabled
    source "$XDG_CACHE_HOME/oh-my-devboom/zsh_plugins.zsh"
fi
