# Managed by SandboxKit's developer profile package.
[[ -z ${SBX_DEV_BASH_LOADED:-} ]] || return
SBX_DEV_BASH_LOADED=1
export PATH="$HOME/.local/bin:$HOME/.dotnet/tools:$PATH"
export DOTNET_ROOT="$HOME/.local/share/sbx-tools/dotnet/current"
export NPM_CONFIG_PREFIX="$HOME/.local"
export EDITOR=edit
export VISUAL=edit
if [[ -f /etc/sandbox-persistent.sh ]]; then source /etc/sandbox-persistent.sh; fi
[[ $- == *i* ]] || return
alias ls='eza -l --git-ignore --git -T -L1 --time-style relative'
alias cat='bat'
eval "$(zoxide init bash)"
eval "$(fzf --bash)"
eval "$(oh-my-posh init bash --config "$HOME/.config/sbx-dev/kali.omp.json")"
