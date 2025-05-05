param (
    [string]$ConfigFile = ".\tech_config.json",
    [string]$LogDir     = ".\logs"
)

# Resolve relative paths to script directory
if (-not [IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $PSScriptRoot $ConfigFile
}
if (-not [IO.Path]::IsPathRooted($LogDir)) {
    $LogDir = Join-Path $PSScriptRoot $LogDir
}

# Self-elevation block
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator in script folder..."
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -WorkingDirectory $PSScriptRoot -Verb RunAs
    exit
}

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

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

# Load config file
try {
    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $appConfigs = Get-Content $ConfigFile | ConvertFrom-Json
} catch {
    Log-Error -Context "Loading Config File" -ErrorObj $_
    exit 1
}

# Gather global info
$computerName = $env:COMPUTERNAME
$userName     = $env:USERNAME
$discoveries  = @()

# Define startTime for event lookup (last 24 hours)
$startTime = (Get-Date).AddDays(-1)

foreach ($app in $appConfigs) {
    try {
        $installFound = @()
        $exeVersions  = @() 
        $regEntries   = @()
        $lastRunTime  = $null

        # Check install paths
        foreach ($path in $app.InstallPaths) {
            try {
                if (Test-Path $path) {
                    $file = Get-Item $path -ErrorAction Stop
                    $installFound += (Get-Item $path -ErrorAction Stop).FullName

                    $ver = $file.VersionInfo.ProductVersion
                    if ($ver) {
                        $exeVersions += "$($file.FullName): $ver"
                    }
                }
            } catch {
                Log-Error -Context "InstallPath [$path] for $($app.AppName)" -ErrorObj $_
            }
        }

        # Check registry values if specified in config
        $regEntries = @()

        if ($app.PSObject.Properties.Name -contains 'RegistryValueNames') {
            $wanted = $app.RegistryValueNames

            foreach ($regPath in $app.RegistryPaths) {
                if (-not (Test-Path $regPath)) { continue }

                # Read the key once
                $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                # Build a list of property objects to process:
                if ($wanted -contains '*') {
                    # All properties except the standard PS ones
                    $toProcess = $props.PSObject.Properties |
                                Where-Object { $_.Name -notmatch '^PS(ParentPath|Path|ChildName|Drive|Provider)$' }
                } else {
                    # Only the named ones that actually exist
                    $toProcess = $props.PSObject.Properties |
                                Where-Object { $wanted -contains $_.Name }
                }

                foreach ($prop in $toProcess) {
                    $valName = $prop.Name
                    $valData = $prop.Value -as [string]
                    $tokens  = if ($valData) {
                                $valData -split '[,; ]+' |
                                Where-Object { $_ } |
                                Select-Object -Unique
                            } else { @() }

                    $regEntries += [PSCustomObject]@{
                        KeyPath   = $regPath
                        ValueName = $valName
                        Tokens    = $tokens -join '; '
                    }
                }
            }
        }

        # grouping reg entries by key path
        $regEntries = $regEntries |
        Sort-Object KeyPath,ValueName,Tokens -Unique

        # Group by KeyPath
        $grouped = $regEntries |
        Group-Object KeyPath | ForEach-Object {
            [PSCustomObject]@{
                KeyPath = $_.Name
                Values  = $_.Group |
                        Select-Object ValueName,Tokens
            }
        }

        # Determine executable path
        if ($installFound.Count -gt 0) {
            $exeFullPath = $installFound[0]
        } else {
            $exeFullPath = $null
        }

        # Lookup last run time via Security log
        if ($exeFullPath) {
            try {
                $evt = Get-WinEvent -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4688
                    StartTime = $startTime
                } -MaxEvents 10000 |
                Where-Object { $_.Properties[5].Value -ieq $exeFullPath } |
                Sort-Object TimeCreated -Descending |
                Select-Object -First 1

                if ($evt) {
                    $lastRunTime = $evt.TimeCreated.ToString("s")
                }
            } catch {
                Log-Error -Context "ProcessEventLog for $($app.AppName)" -ErrorObj $_
            }
        }

        $found = ($installFound.Count -gt 0) -or ($regEntries.Count -gt 0)

        # Build per-app entry
        $appEntry = [PSCustomObject]@{
            AppName         = $app.AppName
            ExeVersions     = $exeVersions    -join "; "
            InstallPaths    = $installFound  -join "; "
            RegistryEntries = if ($grouped) { $grouped } else { $null }
            LastRunTime     = $lastRunTime
            Found           = $found
        }

        $discoveries += $appEntry

    } catch {
        Log-Error -Context "Discovery for $($app.AppName)" -ErrorObj $_
    }
}

# Build final report
$report = [PSCustomObject]@{
    Timestamp    = (Get-Date).ToString("s")
    ComputerName = $computerName
    UserName     = $userName
    Apps         = $discoveries
}

# Write report to log
$report | ConvertTo-Json -Depth 4 | Add-Content -Path $logFile
