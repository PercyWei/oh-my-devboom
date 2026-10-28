typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k/powerlevel10k.zsh-theme"
source "$XDG_DATA_HOME/oh-my-devboom/powerlevel10k/config/p10k-lean.zsh"
[[ ! -r "${ZDOTDIR:-$HOME}/.p10k.zsh" ]] || source "${ZDOTDIR:-$HOME}/.p10k.zsh"
# 模板会将向导目标设为自身；始终写入用户配置。
typeset -g POWERLEVEL9K_CONFIG_FILE="${ZDOTDIR:-$HOME}/.p10k.zsh"
p10k reload
