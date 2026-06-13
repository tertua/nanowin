# edit_env_helper.ps1 - Show provider context for edit_env.bat
$ErrorActionPreference = 'SilentlyContinue'
$c = Get-Content 'data\config.json' -Raw | ConvertFrom-Json
$p = $c.agents.defaults.provider
if ($p) {
    Write-Output ('Provider: ' + $p)
    $pf = $c.providers.$p
    if ($pf) {
        $pf.PSObject.Properties | ForEach-Object {
            if ($_.Value -match '\$\{([^}]+)\}') {
                Write-Output ('  uses: ' + $Matches[1])
            }
        }
    }
}
