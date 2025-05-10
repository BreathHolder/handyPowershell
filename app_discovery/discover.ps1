[CmdletBinding()]
param (
    [string]$ConfigFile = ".\tech_config.json",
    [string]$LogDir     = ".\logs",
    [switch]$EnableEventScan
)
##################################################################################################
# Timer helpers
# Description: This section defines helper functions to measure the time taken for various operations
#              in the script. The `Start-Timer` function starts a stopwatch, and the `Show-Duration`
#              function stops the stopwatch and displays the elapsed time along with a label.
##################################################################################################
function Start-Timer { [System.Diagnostics.Stopwatch]::StartNew() }
function Show-Duration ($label, $sw) {
    $sw.Stop()
    Write-Host "$label took $($sw.Elapsed.TotalSeconds) seconds"
}

##################################################################################################
# Resolve relative paths
# Description: This section resolves the relative paths for the configuration file and log directory.
#              If the paths are not absolute, they are combined with the script root directory.
##################################################################################################
if (-not [IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $PSScriptRoot $ConfigFile
}
if (-not [IO.Path]::IsPathRooted($LogDir)) {
    $LogDir = Join-Path $PSScriptRoot $LogDir
}

##################################################################################################
# Self-elevation
# Description: This section checks if the script is running with administrative privileges. If not, it
#              attempts to re-launch itself with elevated privileges.
##################################################################################################
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator in script folder..."
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -WorkingDirectory $PSScriptRoot -Verb RunAs
    exit
}

##################################################################################################
# Ensure log directory
# Description: This section sets the log directory to a default value if not provided. It also
#              checks if the log directory exists. If not, it creates the directory.
##################################################################################################
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$logFile   = Join-Path $LogDir ("discovery_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$errorFile = Join-Path $LogDir ("error_{0}.log"     -f (Get-Date -Format "yyyyMMdd"))
$warnFile = Join-Path $LogDir ("warnings_{0}.log" -f (Get-Date -Format "yyyyMMdd"))

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

##################################################################################################
# Load config
# Description: This section sets the execution policy to bypass and loads the configuration file.
#              It checks if the file exists and attempts to read its contents. If the file is not
#              found or cannot be read, it logs the error and exits.
##################################################################################################
Write-Host "Loading config file..."
try {
    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }
    $appConfigs = Get-Content $ConfigFile | ConvertFrom-Json
} catch {
    Log-Error -Context "Loading Config File" -ErrorObj $_
    exit 1
}

##################################################################################################
# Global info
# Description: This section initializes some global variables and prepares to process each
#              application configuration. It sets up the computer name, username, and a list to
#              store discoveries.
##################################################################################################
$computerName = $env:COMPUTERNAME
$userName     = $env:USERNAME
$discoveries  = @()
# $startTime    = (Get-Date).AddDays(-1) # original config and it took a long time for some apps.
$startTime    = (Get-Date).AddHours(-1) # 1 hours back

foreach ($app in $appConfigs) {
    $totalTimer = Start-Timer
    Write-Host "`nProcessing: $($app.AppName)"
    
    

    try {
        $installFound = @()
        $regEntries   = @()
        $appVersion = $null 
        $lastRunTime  = $null

##################################################################################################        
# --- Install Path Check ---
# Description: This section checks the installation paths specified in the application configuration.
#              It verifies if the paths exist and retrieves the file information for each path.
#              The file information includes the full path and product version of the executable.
##################################################################################################        
        $sw = Start-Timer
        foreach ($path in $app.InstallPaths) {
            try {
                if (Test-Path $path) {
                    $file = Get-Item $path -ErrorAction Stop
                    $installFound += $file.FullName

                    $ver = $file.VersionInfo.ProductVersion
                    if (-not $appVersion -and $ver) {
                        $appVersion = $ver
                    }                    
                }
            } catch {
                Log-Error -Context "InstallPath [$path] for $($app.AppName)" -ErrorObj $_
            }
        }
        Show-Duration "Install path check" $sw

##################################################################################################
# --- Registry Check ---
# Description: This section checks the registry for specific values related to the application.
#              It retrieves the registry paths and value names specified in the application
#              configuration. It then checks if the registry paths exist and retrieves the values
#              for the specified value names. The values are stored in a custom object for later
#              processing.
#              The registry entries are grouped by their key path and value name.
##################################################################################################
        $sw = Start-Timer

        $wanted = if ($app.PSObject.Properties.Name -contains 'RegistryValueNames') {
            $app.RegistryValueNames
        } else {
            @("*")
        }

        foreach ($regPath in $app.RegistryPaths) {
            if (-not (Test-Path $regPath)) { continue }

            try {
                $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $toProcess = if ($wanted -contains '*') {
                    $props.PSObject.Properties |
                        Where-Object { $_.Name -notmatch '^PS(ParentPath|Path|ChildName|Drive|Provider)$' }
                } else {
                    $props.PSObject.Properties |
                        Where-Object { $wanted -contains $_.Name }
                }

                foreach ($prop in $toProcess) {
                    $valName = $prop.Name
                    $rawVal  = $prop.Value
                    $valData = try { [string]$rawVal } catch { $null }

                    $tokens = if ($valData -and $valData.Trim()) {
                        # Keep entire string as a token + any splits
                        @($valData) + ($valData -split '[,; ]+' |
                            Where-Object { $_ -ne $valData -and $_ -ne "" }) |
                            Select-Object -Unique
                    } else {
                        @("<<non-string: $($rawVal.GetType().Name)>>")
                    }
                    Write-Host "`n--- DEBUG: Registry Value ---"
                    Write-Host "KeyPath  : $regPath"
                    Write-Host "Name     : $($prop.Name)"
                    Write-Host "Raw Value: $($prop.Value)"
                    Write-Host "Type     : $($prop.Value.GetType().Name)"
                    Write-Host "ValData  : $valData"
                    Write-Host "Tokens   : $($tokens -join '; ')"

                    # If we see a version-like value, save it for AppVersion
                    if ($valName -match '^(DisplayVersion|CurrentVersion)$' -and $valData) {
                        $appVersion = $valData
                    }


                    $regEntries += [PSCustomObject]@{
                        KeyPath   = $regPath
                        ValueName = $valName
                        Tokens    = $tokens -join '; '
                    }
                }
            } catch {
                Log-Error -Context "RegistryRead [$regPath] for $($app.AppName)" -ErrorObj $_
            }
        }

        Show-Duration "Registry check" $sw

##################################################################################################
# --- Group Registry Entries ---
# Description: This section groups the registry entries by their key path and value name.
##################################################################################################        
        $sw = Start-Timer

        if ($regEntries.Count -gt 0) {
            $regEntries = $regEntries | Sort-Object KeyPath,ValueName,Tokens -Unique
            $grouped = $regEntries |
            Group-Object KeyPath | ForEach-Object {
                $values = $_.Group | ForEach-Object {
                    [pscustomobject]@{
                        ValueName = $_.ValueName
                        Tokens    = $_.Tokens
                    }
                }

                [pscustomobject]@{
                    KeyPath = $_.Name
                    Values  = $values
                }
            }
        } else {
            $grouped = $null
        }

        Show-Duration "Registry grouping" $sw

##################################################################################################
# --- Get Last Run Time (Event Log) ---
# Description: This section retrieves the last run time of the application from the Windows
#              Event Log (if enabled). It filters the events based on the executable path and
#              the specified time range.
##################################################################################################
        $sw = Start-Timer
        if ($EnableEventScan -and $installFound.Count -gt 0) {
            $exeFullPath = $installFound[0]
            try {
                $evt = Get-WinEvent -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4688
                    StartTime = $startTime
                } -MaxEvents 1000 |
                Where-Object { $_.Properties[5].Value -like "*$($exeFullPath.Split('\')[-1])" } |
                Sort-Object TimeCreated -Descending |
                Select-Object -First 1
                if ($evt -and $events -and $events.Count -eq 1000) {
                    $warningText = "[{0}] Hit MaxEvents limit — older entries may be missed" -f (Get-Date).ToString("s")
                    Write-Warning $warningText
                    Add-Content -Path $warnFile -Value $warningText
                }

                if ($evt) {
                    $lastRunTime = $evt.TimeCreated.ToString("s")
                }
            } catch {
                Log-Error -Context "ProcessEventLog for $($app.AppName)" -ErrorObj $_
            }
        }
        Show-Duration "Event log scan" $sw

##################################################################################################
# --- Final Object Build ---
# Description: This section builds the final object that contains all the information gathered
#              during the discovery process. It includes the application name, executable versions,
#              install paths, registry entries, last run time, and whether the application was found.
##################################################################################################
        $sw = Start-Timer
        $found = ($installFound.Count -gt 0) -or ($regEntries.Count -gt 0)
        $appEntry = [PSCustomObject]@{
            AppName         = $app.AppName
            AppVersion      = $appVersion
            InstallPaths    = $installFound -join "; "
            RegistryEntries = if ($grouped) { $grouped } else { $null }
            LastRunTime     = $lastRunTime
            Found           = $found
        }
        $discoveries += $appEntry
        Show-Duration "Object build" $sw

    } catch {
        Log-Error -Context "Discovery for $($app.AppName)" -ErrorObj $_
    }

    Show-Duration "Total time for $($app.AppName)" $totalTimer
}

##################################################################################################
# Export Full App Discovery Report to CSV
# Description: Flattens the entire app-level summary into one row per app, including a summary of
#              the registry keys found. Useful for auditing or sharing full discovery results.
##################################################################################################

Write-Host "`nExporting full app summary report to CSV..."

$flatApps = foreach ($app in $discoveries) {
    $regSummary = @()

    if ($app.RegistryEntries) {
        foreach ($entry in $app.RegistryEntries) {
            foreach ($val in $entry.Values) {
                $regSummary += "$($val.ValueName)=$($val.Tokens)"
            }
        }
    }

    [pscustomobject]@{
        AppName          = $app.AppName
        AppVersion       = $app.AppVersion
        InstallPaths     = $app.InstallPaths
        LastRunTime      = $app.LastRunTime
        Found            = $app.Found
        RegistrySummary  = $regSummary -join " | "
    }
}

$csvAppPath = Join-Path $LogDir ("discovery_apps_{0}.csv" -f (Get-Date -Format "yyyyMMdd"))
$flatApps | Export-Csv -Path $csvAppPath -NoTypeInformation -Encoding UTF8

Write-Host "Full app discovery CSV saved to $csvAppPath"
