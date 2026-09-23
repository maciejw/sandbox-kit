# PowerShell is optional; DSC tool installation does not depend on this profile.
$env:DOTNET_ROOT = Join-Path $HOME '.local/share/sbx-tools/dotnet/current'
$env:NPM_CONFIG_PREFIX = "$HOME/.local"
$env:EDITOR = 'edit'
$env:VISUAL = 'edit'
$env:PATH = "$HOME/.local/bin:$HOME/.dotnet/tools:$env:PATH"
oh-my-posh init pwsh --config "$HOME/.config/sbx-dev/kali.omp.json" | Invoke-Expression
Invoke-Expression (& zoxide init powershell | Out-String)
# Keep PowerShell's object-oriented ls/cat aliases. Use eza/bat explicitly.
