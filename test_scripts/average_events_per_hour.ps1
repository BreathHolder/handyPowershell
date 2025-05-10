function Show-Spinner {
    param (
        [scriptblock]$ScriptToRun,
        [string]$Message = "Working"
    )

    $spinner = "|/—\\"
    $job = Start-Job $ScriptToRun
    $i = 0

    while ($job.State -eq 'Running') {
        $char = $spinner[$i % $spinner.Length]
        Write-Host -NoNewline "`r$Message $char"
        Start-Sleep -Milliseconds 100
        $i++
    }

    Write-Host "`r$Message done.`n"
    $result = Receive-Job $job
    Remove-Job $job
    return $result
}

# Start the clock
$hourlyCounts = Show-Spinner -Message "Scanning Security Log" -ScriptToRun {
    $startTime = (Get-Date).AddHours(-8)
    Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4688
        StartTime = $startTime
    } | Group-Object { $_.TimeCreated.ToString("yyyy-MM-dd HH") }
}

$totalHours = $hourlyCounts.Count
$totalEvents = ($hourlyCounts | Measure-Object Count -Sum).Sum
$averagePerHour = if ($totalHours -gt 0) { [math]::Round($totalEvents / $totalHours, 2) } else { 0 }

Write-Host "Average Event ID 4688s per hour over the last $totalHours hour(s): $averagePerHour"
