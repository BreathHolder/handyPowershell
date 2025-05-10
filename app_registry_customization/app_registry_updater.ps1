param (
    [string]$AppJsonDirectory = ".\Apps"
)

Get-ChildItem -Path $AppJsonDirectory -Filter *.json | ForEach-Object {
    $jsonPath = $_.FullName
    try {
        $appData = Get-Content $jsonPath | ConvertFrom-Json
        $appName = $appData.AppName
        $registryBlocks = $appData.CustomRegistry

        foreach ($block in $registryBlocks) {
            if (-not $block.Path) {
                Write-Error "Missing 'Path' in CustomRegistry block for '$appName' in file '$jsonPath'. Skipping this block."
                continue
            }

            $regPath = $block.Path
            $entries = $block.Entries

            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }

            foreach ($key in $entries.PSObject.Properties.Name) {
                $value = $entries.$key
                $type = switch ($value.GetType().Name) {
                    'Int32' { 'DWord' }
                    'Boolean' { 'DWord' }
                    default { 'String' }
                }

                Set-ItemProperty -Path $regPath -Name $key -Value $value -Type $type
                Write-Host "Set $key = $value ($type) under $regPath"
            }
        }
    } catch {
        Write-Warning "Error processing `${jsonPath}:` $_"
    }
}
