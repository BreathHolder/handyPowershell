# CheckAndStartJumpDesktop.ps1

$serviceName = "JumpConnect"

# Try to get the service
try {
    $service = Get-Service -Name $serviceName -ErrorAction Stop
} catch {
    # If the service is not found, write an event or message (optional)
    Write-Host "Service $serviceName not found."
    exit 1
}

# If the service is not running, start it
if ($service.Status -ne "Running") {
    Start-Service -Name $serviceName
    Write-Host "Service $serviceName was stopped and has been started."
} else {
    Write-Host "Service $serviceName is already running."
}
