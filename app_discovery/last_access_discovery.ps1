# Define the application you want to search for
$appExe = "notepad++.exe"

# Define the start time (e.g., 24 hours ago) to limit the search range
$startTime = (Get-Date).AddDays(-1)

# Query the Security log for process creation events (ID 4688)
$processEvents = Get-WinEvent -FilterHashtable @{
    LogName    = 'Security'
    Id         = 4688
    StartTime  = $startTime
} -MaxEvents 5000

# Filter the events to find those that reference Notepad++.exe in the event message.
$notepadEvents = $processEvents | Where-Object { $_.Message -like "*$appExe*" }

if ($notepadEvents) {
    # Sort events by their TimeCreated property descending to get the most recent one first.
    $lastNotepadEvent = $notepadEvents | Sort-Object TimeCreated -Descending | Select-Object -First 1
    Write-Host "Notepad++.exe last run time:" $lastNotepadEvent.TimeCreated
} else {
    Write-Host "No process creation events for Notepad++.exe were found."
}
