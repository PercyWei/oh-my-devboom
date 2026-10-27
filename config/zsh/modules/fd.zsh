if ! (( $+commands[fd] )) && (( $+commands[fdfind] )); then
    alias fd=fdfind
fi
