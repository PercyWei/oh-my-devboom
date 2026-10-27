if ! (( $+commands[bat] )) && (( $+commands[batcat] )); then
    alias bat=batcat
fi
