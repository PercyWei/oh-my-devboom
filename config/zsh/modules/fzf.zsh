if [[ -r "$XDG_DATA_HOME/oh-my-devboom/fzf/init.zsh" ]]; then
    source "$XDG_DATA_HOME/oh-my-devboom/fzf/init.zsh"
else
    print -u2 -- '[warn] fzf 的 Zsh 集成尚未准备；请运行 bootstrap.sh --non-interactive --modules tools --tools fzf。'
fi
