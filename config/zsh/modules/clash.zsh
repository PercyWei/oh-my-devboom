_devboom_clash_home="$XDG_DATA_HOME/clashctl"
if [[ -r "$_devboom_clash_home/scripts/cmd/clashctl.sh" &&
      -r "$_devboom_clash_home/.clashctl-format" &&
      "$(<"$_devboom_clash_home/.clashctl-format")" == 1 ]]; then
    export CLASHCTL_HOME="${_devboom_clash_home:A}"
    source "$CLASHCTL_HOME/scripts/cmd/clashctl.sh"
fi
unset _devboom_clash_home
