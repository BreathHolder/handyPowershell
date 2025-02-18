# Run with Admin Privileges

# createHealthCheckLog
$logPath = "$HOME\WindowsUpdateHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Start-Transcript -Path $logPath -Append

# Check Windows Update Service Status
Write-Output "Checking Windows Update Service Status..."
$service = Get-Service -Name wuauserv
if ($service.Status -ne 'Running') {
    Write-Output "Windows Update service is not running."
} else {
    Write-Output "Windows Update service is running."
}

# Check for Windows Update Errors using Get-WinEvent
Write-Output "`nChecking Windows Update Errors..."
$updateLog = Get-WinEvent -LogName 'System' | Where-Object {
    $_.ProviderName -eq 'Microsoft-Windows-WindowsUpdateClient' -and $_.LevelDisplayName -eq 'Error'
}

if ($updateLog) {
    Write-Output "Windows Update Errors Found:"
    $updateLog | Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-Table -AutoSize
} else {
    Write-Output "No Windows Update errors found."
}

# Install and Import PSWindowsUpdate for PowerShell 7
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Output "`nInstalling PSWindowsUpdate module..."
    Install-PackageProvider -Name NuGet -Force
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber
}
Import-Module PSWindowsUpdate -Force

# Check for Available Updates
Write-Output "`nChecking for Available Updates..."
$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
if ($updates) {
    Write-Output "Available Updates:"
    $updates | Select-Object KBArticle, Title, MsrcSeverity, IsDownloaded, IsInstalled | Format-Table -AutoSize
} else {
    Write-Output "No updates available."
}

# Check for Driver Updates
Write-Output "`nChecking for Driver Updates..."
try {
    $driverUpdates = Get-WindowsUpdate -MicrosoftUpdate -Category Drivers -Verbose -ErrorAction Stop
    if ($driverUpdates) {
        Write-Output "Driver Updates Found:"
        $driverUpdates | Select-Object Title, DriverClass, Manufacturer, Version | Format-Table -AutoSize
    } else {
        Write-Output "No driver updates found."
    }
} catch {
    Write-Output "Error retrieving driver updates: $_"
}

Stop-Transcript
