export ANTIDOTE_HOME="$XDG_DATA_HOME/oh-my-devboom/plugins"
export ZSH="$ANTIDOTE_HOME/github.com/ohmyzsh/ohmyzsh"
zstyle ':omz:update' mode disabled
zstyle ':antidote:bundle' file "${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
zstyle ':antidote:static' file "$XDG_CACHE_HOME/oh-my-devboom/plugins.zsh"
source "$XDG_DATA_HOME/oh-my-devboom/antidote/antidote.zsh"
antidote load
