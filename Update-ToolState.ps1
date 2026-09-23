[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InventoryPath = (Join-Path $PSScriptRoot 'ansible/inventory/group_vars/sandbox/tools.yml'),
    [string]$YqPath = 'yq',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

function Get-ReleaseVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Tag)

    $match = [regex]::Match($Tag, '(?<version>\d+\.\d+(?:\.\d+){0,2}(?:[-+][0-9A-Za-z.-]+)?)')
    if (-not $match.Success) {
        throw "Release tag '$Tag' does not contain a semantic version."
    }

    $match.Groups['version'].Value
}

function Select-ReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Assets,
        [Parameter(Mandatory)][string]$AssetName
    )

    $asset = @($Assets | Where-Object name -eq $AssetName)
    if ($asset.Count -ne 1) {
        $available = @($Assets | ForEach-Object name) -join ', '
        throw "Expected exactly one release asset named '$AssetName'; found $($asset.Count). Available assets: $available"
    }

    $asset[0]
}

function Get-ToolVersionStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrentVersion,
        [Parameter(Mandatory)][string]$LatestVersion
    )

    $isUpdateAvailable = $CurrentVersion -ne $LatestVersion
    [pscustomobject]@{
        IsUpdateAvailable = $isUpdateAvailable
        Symbol = if ($isUpdateAvailable) { '🔼' } else { '✅' }
        Color = if ($isUpdateAvailable) { 'Yellow' } else { 'Green' }
    }
}

function Write-ToolVersionStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrentVersion,
        [Parameter(Mandatory)][string]$LatestVersion
    )

    $status = Get-ToolVersionStatus -CurrentVersion $CurrentVersion -LatestVersion $LatestVersion
    $message = if ($status.IsUpdateAvailable) {
        "  $($status.Symbol) $CurrentVersion -> $LatestVersion"
    }
    else {
        "  $($status.Symbol) $CurrentVersion (current)"
    }

    Write-Host $message -ForegroundColor $status.Color
}

function Get-ToolInventoryEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $entries = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^  - name: (?<name>[^\s]+)\s*$') {
            if ($null -ne $current) { $entries.Add([pscustomobject]$current) }
            $current = [ordered]@{ Name = $Matches.name }
            continue
        }

        if ($null -ne $current -and $line -match '^      (?<key>version|source|checksum|algorithm|format):\s*(?<value>.*)$') {
            $current[$Matches.key] = $Matches.value.Trim()
        }
    }

    if ($null -ne $current) { $entries.Add([pscustomobject]$current) }
    @($entries)
}

function Get-YqUpdateExpression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Updates
    )

    $expressions = foreach ($toolName in $Updates.Keys) {
        $update = $Updates[$toolName]
        $nameLiteral = ConvertTo-Json -InputObject ([string]$toolName) -Compress
        $versionLiteral = ConvertTo-Json -InputObject ([string]$update.Version) -Compress
        $sourceLiteral = ConvertTo-Json -InputObject ([string]$update.Source) -Compress
        $checksumLiteral = ConvertTo-Json -InputObject ([string]$update.Checksum) -Compress

        @(
            "(.sandboxkit_tools[] | select(.name == $nameLiteral).properties.version) = $versionLiteral"
            "(.sandboxkit_tools[] | select(.name == $nameLiteral).properties.source) = $sourceLiteral"
            "(.sandboxkit_tools[] | select(.name == $nameLiteral).properties.checksum) = $checksumLiteral"
        ) -join ' | '
    }

    $expressions -join ' | '
}

function Resolve-YqExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommandName)

    $command = Get-Command -Name $CommandName -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "The yq executable '$CommandName' was not found. Install mikefarah/yq or pass -YqPath with its path."
    }

    $item = Get-Item -LiteralPath $command.Source -ErrorAction Stop
    if ($item.LinkType -eq 'SymbolicLink' -and $item.Target) {
        $target = if ([IO.Path]::IsPathRooted($item.Target)) { $item.Target } else { Join-Path $item.DirectoryName $item.Target }
        if (Test-Path -LiteralPath $target -PathType Leaf) { return (Resolve-Path -LiteralPath $target).Path }
    }

    $command.Source
}

function Invoke-YqInventoryUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Updates,
        [Parameter(Mandatory)][string]$YqPath
    )

    $expression = Get-YqUpdateExpression -Updates $Updates
    if ([string]::IsNullOrWhiteSpace($expression)) { return }

    $executable = Resolve-YqExecutable -CommandName $YqPath
    $output = & $executable --inplace $expression (Resolve-Path -LiteralPath $Path).Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($output | ForEach-Object ToString) -join [Environment]::NewLine
        throw "yq failed to update '$Path' (exit code $LASTEXITCODE).$([Environment]::NewLine)$details"
    }
}

function Get-DownloadHeaders {
    @{ 'User-Agent' = 'SandboxKit-ToolStateUpdater/1.0' }
}

function Get-GitHubApiHeaders {
    $headers = @{ 'User-Agent' = 'SandboxKit-ToolStateUpdater/1.0' }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
    }
    $headers
}

function Get-JsonResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [switch]$GitHubApi
    )

    $headers = if ($GitHubApi) { Get-GitHubApiHeaders } else { Get-DownloadHeaders }
    $resource = Invoke-RestMethod -Uri $Uri -Headers $headers -ErrorAction Stop
    if ($resource -is [Array]) {
        foreach ($item in $resource) { Write-Output $item }
    }
    else {
        $resource
    }
}

function Test-ToolUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri)

    try {
        Invoke-WebRequest -Uri $Uri -Method Head -MaximumRedirection 5 -Headers (Get-DownloadHeaders) -ErrorAction Stop | Out-Null
    }
    catch {
        throw "URL check failed for $Uri`: $($_.Exception.Message)"
    }
}

function Get-DownloadedChecksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][ValidateSet('SHA256', 'SHA512')][string]$Algorithm
    )

    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ('sandboxkit-tool-' + [Guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $temporaryPath -Headers (Get-DownloadHeaders) -MaximumRedirection 5 -ErrorAction Stop
        (Get-FileHash -LiteralPath $temporaryPath -Algorithm $Algorithm).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -WhatIf:$false -ErrorAction SilentlyContinue
    }
}

function Get-GitHubToolUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Tool,
        [switch]$SkipChecksum
    )

    $uri = [uri]$Tool.source
    $segments = $uri.AbsolutePath.Trim('/').Split('/')
    if ($segments.Count -lt 6 -or $segments[2] -ne 'releases' -or $segments[3] -ne 'download') {
        throw "GitHub source URL is not a release asset URL: $($Tool.source)"
    }

    $owner = $segments[0]
    $repository = $segments[1]
    $assetName = [Uri]::UnescapeDataString($segments[-1])
    $release = Get-JsonResource -Uri "https://api.github.com/repos/$owner/$repository/releases/latest" -GitHubApi
    $asset = Select-ReleaseAsset -Assets @($release.assets) -AssetName $assetName
    $version = Get-ReleaseVersion -Tag $release.tag_name
    $source = [uri]$asset.browser_download_url

    $checksum = if ($SkipChecksum) {
        $Tool.checksum
    }
    else {
        Get-DownloadedChecksum -Uri $source -Algorithm $Tool.algorithm.ToUpperInvariant()
    }

    [pscustomobject]@{
        Version = $version
        Source = $source.AbsoluteUri
        Checksum = $checksum
    }
}

function Get-NodeToolUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Tool)

    $currentVersion = [Version]$Tool.version
    $releases = @(Get-JsonResource -Uri 'https://nodejs.org/dist/index.json')
    $latest = @(
        $releases |
            Where-Object {
                $_.version -match '^v(?<version>\d+\.\d+\.\d+)$' -and
                ([Version]$Matches.version).Major -eq $currentVersion.Major
            } |
            Sort-Object { [Version]$_.version.TrimStart('v') } -Descending
    ) | Select-Object -First 1

    if ($null -eq $latest) {
        throw "No stable Node.js release was found for major $($currentVersion.Major)."
    }

    $version = $latest.version.TrimStart('v')
    $assetName = "node-$($latest.version)-linux-x64.tar.xz"
    $baseUri = "https://nodejs.org/dist/$($latest.version)/"
    $source = [uri]($baseUri + $assetName)
    $checksumText = (Invoke-WebRequest -Uri ($baseUri + 'SHASUMS256.txt') -Headers (Get-DownloadHeaders) -ErrorAction Stop).Content
    $escapedAssetName = [regex]::Escape($assetName)
    $match = [regex]::Match($checksumText, "(?m)^(?<checksum>[0-9a-fA-F]{64})\s+\*?$escapedAssetName\s*$")
    if (-not $match.Success) { throw "No SHA-256 entry was found for Node.js asset '$assetName'." }

    [pscustomobject]@{ Version = $version; Source = $source.AbsoluteUri; Checksum = $match.Groups['checksum'].Value.ToLowerInvariant() }
}

function Get-DotnetToolUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Tool)

    $currentVersion = [Version]$Tool.version
    $channel = '{0}.{1}' -f $currentVersion.Major, $currentVersion.Minor
    $index = Get-JsonResource -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json'
    $channelMetadata = @($index.'releases-index' | Where-Object 'channel-version' -eq $channel)
    if ($channelMetadata.Count -ne 1) { throw "No unique .NET SDK release channel '$channel' was found." }

    $metadata = Get-JsonResource -Uri ([uri]$channelMetadata[0].'releases.json')
    $sdk = @(
        foreach ($release in @($metadata.releases)) {
            @($release.sdks) | Where-Object version | ForEach-Object {
                [pscustomobject]@{ Version = $_.version; Files = @($_.files) }
            }
        }
    ) |
        Where-Object Version -match '^\d+\.\d+\.\d+$' |
        Sort-Object { [Version]$_.Version } -Descending |
        Select-Object -First 1
    if ($null -eq $sdk) { throw "No .NET SDK release was found for channel '$channel'." }

    $file = @($sdk.Files | Where-Object { $_.rid -eq 'linux-x64' -and $_.name -like '*.tar.gz' })
    if ($file.Count -ne 1) { throw "No unique Linux x64 .NET SDK archive was found for version $($sdk.Version)." }

    [pscustomobject]@{ Version = $sdk.Version; Source = $file[0].url; Checksum = $file[0].hash.ToLowerInvariant() }
}

function Get-ToolReleaseUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Tool,
        [switch]$SkipChecksum
    )

    $hostName = ([uri]$Tool.source).Host
    if ($hostName -eq 'github.com') { return Get-GitHubToolUpdate -Tool $Tool -SkipChecksum:$SkipChecksum }
    if ($hostName -eq 'nodejs.org') { return Get-NodeToolUpdate -Tool $Tool }
    if ($hostName -eq 'builds.dotnet.microsoft.com') { return Get-DotnetToolUpdate -Tool $Tool }
    throw "No release provider is registered for '$($Tool.source)'."
}

function Invoke-ToolStateUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$YqPath = 'yq',
        [switch]$CheckOnly,
        [switch]$Preview
    )

    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    $tools = Get-ToolInventoryEntries -Text $text
    if ($tools.Count -eq 0) { throw "No tools were found in '$Path'." }

    $updates = @{}
    foreach ($tool in $tools) {
        Write-Host "Checking $($tool.Name) ..."
        Test-ToolUrl -Uri ([uri]$tool.source)
        if ($CheckOnly) { continue }

        $update = Get-ToolReleaseUpdate -Tool $tool -SkipChecksum:$Preview
        Write-ToolVersionStatus -CurrentVersion $tool.version -LatestVersion $update.Version
        $updates[$tool.Name] = $update
    }

    if ($CheckOnly) {
        Write-Host "All configured tool URLs responded successfully."
        return
    }

    $expression = Get-YqUpdateExpression -Updates $updates
    if ([string]::IsNullOrWhiteSpace($expression)) {
        Write-Host 'Inventory is already current.'
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Update tool release fields with yq')) {
        Invoke-YqInventoryUpdate -Path $Path -Updates $updates -YqPath $YqPath
        Write-Host "Updated $Path"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ToolStateUpdate -Path $InventoryPath -YqPath $YqPath -CheckOnly:$CheckOnly -Preview:$WhatIfPreference
}
