typeset -g GITSTATUS_AUTO_INSTALL=0
typeset -g GITSTATUS_CACHE_DIR="$XDG_DATA_HOME/oh-my-devboom/gitstatus"
if [[ -r "$XDG_CACHE_HOME/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "$XDG_CACHE_HOME/p10k-instant-prompt-${(%):-%n}.zsh"
fi
