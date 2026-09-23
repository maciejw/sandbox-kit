Describe 'Update-ToolState helpers' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\Update-ToolState.ps1')
    }

    It 'extracts the semantic version from a tagged GitHub release' {
        Get-ReleaseVersion -Tag 'rust-v0.154.0' | Should -Be '0.154.0'
        Get-ReleaseVersion -Tag 'jq-1.8.2' | Should -Be '1.8.2'
    }

    It 'selects the asset matching the configured Linux artifact name' {
        $assets = @(
            [pscustomobject]@{ name = 'tool-windows-amd64.zip'; browser_download_url = 'https://example.invalid/windows' }
            [pscustomobject]@{ name = 'tool-linux-amd64.tar.gz'; browser_download_url = 'https://example.invalid/linux' }
        )

        $asset = Select-ReleaseAsset -Assets $assets -AssetName 'tool-linux-amd64.tar.gz'

        $asset.name | Should -Be 'tool-linux-amd64.tar.gz'
    }

    It 'builds a yq expression that changes only release fields' {
        $expression = Get-YqUpdateExpression -Updates @{
            sample = [pscustomobject]@{
                Version = '1.1.0'
                Source = 'https://example.invalid/new'
                Checksum = 'new'
            }
        }

        $expression | Should -Match 'select\(\.name == "sample"\)\.properties\.version\) = "1\.1\.0"'
        $expression | Should -Match 'select\(\.name == "sample"\)\.properties\.source\) = "https://example\.invalid/new"'
        $expression | Should -Match 'select\(\.name == "sample"\)\.properties\.checksum\) = "new"'
        $expression | Should -Not -Match 'algorithm'
        $expression | Should -Not -Match 'commands'
    }

    It 'keeps the GitHub API token off artifact download requests' {
        $previousToken = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = 'test-token'
        try {
            $apiHeaders = Get-GitHubApiHeaders
            $downloadHeaders = Get-DownloadHeaders

            $apiHeaders.Authorization | Should -Be 'Bearer test-token'
            $downloadHeaders.Authorization | Should -BeNullOrEmpty
        }
        finally {
            if ($null -eq $previousToken) {
                Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            }
            else {
                $env:GITHUB_TOKEN = $previousToken
            }
        }
    }

    It 'marks unchanged versions as current and upgrades as available' {
        $current = Get-ToolVersionStatus -CurrentVersion '1.2.3' -LatestVersion '1.2.3'
        $upgrade = Get-ToolVersionStatus -CurrentVersion '1.2.3' -LatestVersion '1.3.0'

        $current.IsUpdateAvailable | Should -BeFalse
        $current.Symbol | Should -Be '✅'
        $current.Color | Should -Be 'Green'

        $upgrade.IsUpdateAvailable | Should -BeTrue
        $upgrade.Symbol | Should -Be '🔼'
        $upgrade.Color | Should -Be 'Yellow'
    }

    It 'skips GitHub artifact downloads when resolving a preview update' {
        Mock Get-JsonResource {
            [pscustomobject]@{
                tag_name = 'v1.2.0'
                assets = @(
                    [pscustomobject]@{
                        name = 'tool-linux-amd64.tar.gz'
                        browser_download_url = 'https://github.com/example/tool/releases/download/v1.2.0/tool-linux-amd64.tar.gz'
                    }
                )
            }
        }
        Mock Get-DownloadedChecksum { throw 'artifact download should not run during preview' }

        $tool = [pscustomobject]@{
            source = 'https://github.com/example/tool/releases/download/v1.1.0/tool-linux-amd64.tar.gz'
            version = '1.1.0'
            checksum = 'old-checksum'
            algorithm = 'sha256'
        }

        $update = Get-GitHubToolUpdate -Tool $tool -SkipChecksum

        $update.Version | Should -Be '1.2.0'
        $update.Checksum | Should -Be 'old-checksum'
        Should -Invoke Get-DownloadedChecksum -Times 0
    }

    It 'reads every configured tool from the inventory' {
        $inventoryPath = Join-Path $PSScriptRoot '..\ansible\inventory\group_vars\sandbox\tools.yml'
        $entries = Get-ToolInventoryEntries -Text (Get-Content -Raw -LiteralPath $inventoryPath)

        $entries.Count | Should -Be 14
        $entries | ForEach-Object {
            $_.source | Should -Not -BeNullOrEmpty
            $_.checksum | Should -Not -BeNullOrEmpty
        }
    }
}
