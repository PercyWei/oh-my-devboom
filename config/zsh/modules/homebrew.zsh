for _devboom_brew in "${commands[brew]}" /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [[ -x "$_devboom_brew" && $EUID != 0 ]]; then
        eval "$("$_devboom_brew" shellenv)"
        break
    fi
done
unset _devboom_brew
