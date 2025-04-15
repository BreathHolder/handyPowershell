param (
    [string]$ConfigFile = ".\tech_config.json",
    [string]$LogDir = ".\logs"
)

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

# Log files
$logFile   = Join-Path $LogDir ("discovery_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$errorFile = Join-Path $LogDir ("error_{0}.log"     -f (Get-Date -Format "yyyyMMdd"))

function Log-Error {
    param (
        [string]$Context,
        [System.Exception]$ErrorObj
    )
    $errorEntry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        Context   = $Context
        Error     = $ErrorObj.Exception.Message
        Stack     = $ErrorObj.ScriptStackTrace
    }
    $errorEntry | ConvertTo-Json -Depth 3 | Add-Content -Path $errorFile
}

try {
    # Load config
    if (-Not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $appConfigs = Get-Content $ConfigFile | ConvertFrom-Json
} catch {
    Log-Error -Context "Loading Config File" -ErrorObj $_
    exit 1
}

# Begin discovery loop
foreach ($app in $appConfigs) {
    try {
        $appName = $app.AppName
        $installFound = @()
        $regFound = @()
        $lastAccessed = $null

        # Check Install Paths
        foreach ($path in $app.InstallPaths) {
            try {
                if (Test-Path $path) {
                    $file = Get-Item $path -ErrorAction Stop
                    $installFound += $file.FullName
                    if (-not $lastAccessed -or ($file.LastAccessTime -gt $lastAccessed)) {
                        $lastAccessed = $file.LastAccessTime
                    }
                }
            } catch {
                Log-Error -Context "InstallPath [$path] for $appName" -ErrorObj $_
            }
        }

        # Check Registry Paths
        foreach ($regPath in $app.RegistryPaths) {
            try {
                if (Test-Path $regPath) {
                    $regFound += $regPath
                }
            } catch {
                Log-Error -Context "RegistryPath [$regPath] for $appName" -ErrorObj $_
            }
        }

        # Compose discovery log entry
        $entry = [PSCustomObject]@{
            Timestamp     = (Get-Date).ToString("s")
            ComputerName  = $env:COMPUTERNAME
            UserName      = $env:USERNAME
            AppName       = $appName
            InstallPaths  = $installFound -join "; "
            RegistryPaths = $regFound -join "; "
            LastAccessed  = if ($lastAccessed) { $lastAccessed.ToString("s") } else { $null }
            Found         = (($installFound.Count -gt 0) -or ($regFound.Count -gt 0))
        }

        # Log the result
        $entry | ConvertTo-Json -Depth 3 | Add-Content -Path $logFile

    } catch {
        Log-Error -Context "Main Discovery Block for $($app.AppName)" -ErrorObj $_
    }
}
