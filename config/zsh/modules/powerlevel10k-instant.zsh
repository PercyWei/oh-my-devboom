typeset -g GITSTATUS_AUTO_INSTALL=0
typeset -g GITSTATUS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-devboom/gitstatus"
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
