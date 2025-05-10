# Auto-elevate if not running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting as Administrator..."
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Disable GameInput Service
$serviceName = "GameInputSvc"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    Write-Host "Disabling GameInput Service..."
    if ($service.Status -ne "Stopped") {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    }
    Set-Service -Name $serviceName -StartupType Disabled
    Write-Host "✅ GameInput Service has been disabled."
} else {
    Write-Host "⚠️ GameInput Service not found."
}

Write-Host "`nPress any key to exit..."
[void][System.Console]::ReadKey($true)
