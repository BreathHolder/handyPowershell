<#
.SYNOPSIS
    Removes stale files from system and user temp directories.

.DESCRIPTION
    Deletes files older than a configurable retention period from
    C:\Temp and the current user's local temp directory. Files that
    are in use or protected are skipped with a recorded failure.

.NOTES
    Run this script from an elevated PowerShell session (Administrator).
    Designed for Windows PowerShell 5.x compatibility.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$RetentionDays = 28,

    [string[]]$AdditionalPaths
)

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Determines whether the current session has administrative rights.
    #>
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultTempPaths {
    <#
    .SYNOPSIS
        Resolves the default temp directories to clean.
    #>
    $paths = @('C:\Temp')

    $userTemp = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'Temp'
    if ($userTemp) {
        $paths += $userTemp
    }

    return $paths
}

function Resolve-TargetPaths {
    <#
    .SYNOPSIS
        Combines default and user-provided paths, removing duplicates.
    #>
    param(
        [string[]]$Defaults,
        [string[]]$Extras
    )

    $all = @($Defaults + $Extras) | Where-Object { $_ } | Sort-Object -Unique
    return $all
}

function Invoke-TempCleanup {
    <#
    .SYNOPSIS
        Removes files older than the specified cutoff date.
    #>
    param(
        [string[]]$Paths,
        [DateTime]$CutoffDate
    )

    $summary = [ordered]@{
        PathsProcessed  = 0
        CandidatesFound = 0
        Removed         = 0
        Failed          = 0
        BytesRemoved    = 0L
    }

    $failures = @()

    foreach ($path in $Paths) {
        if (-not (Test-Path -Path $path -PathType Container)) {
            Write-Verbose "Skipping missing path: $path"
            continue
        }

        $summary.PathsProcessed++

        try {
            $candidates = Get-ChildItem -Path $path -File -Recurse -ErrorAction Stop |
                Where-Object { $_.LastWriteTime -lt $CutoffDate }
        }
        catch {
            $failures += [pscustomobject]@{
                Path    = $path
                Reason  = 'EnumerationFailed'
                Message = $_.Exception.Message
            }
            $summary.Failed++
            continue
        }

        $summary.CandidatesFound += $candidates.Count

        foreach ($item in $candidates) {
            try {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove')) {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    $summary.Removed++
                    $summary.BytesRemoved += [long]$item.Length
                }
            }
            catch {
                $failures += [pscustomobject]@{
                    Path    = $item.FullName
                    Reason  = $_.Exception.GetType().Name
                    Message = $_.Exception.Message
                }
                $summary.Failed++
            }
        }
    }

    [pscustomobject]@{
        Summary  = $summary
        Failures = $failures
    }
}

function Ensure-EventSource {
    <#
    .SYNOPSIS
        Ensures the event source exists for logging.
    #>
    param(
        [string]$LogName,
        [string]$Source
    )

    if ([System.Diagnostics.EventLog]::SourceExists($Source)) {
        return
    }

    $newEventLogCmd = Get-Command -Name New-EventLog -ErrorAction SilentlyContinue
    if ($null -ne $newEventLogCmd) {
        New-EventLog -LogName $LogName -Source $Source
        return
    }

    $creationData = New-Object System.Diagnostics.EventSourceCreationData($Source, $LogName)
    [System.Diagnostics.EventLog]::CreateEventSource($creationData)
}

function Write-CleanupEvent {
    <#
    .SYNOPSIS
        Writes an event log entry for cleanup results.
    #>
    param(
        [int]$EventId,
        [System.Diagnostics.EventLogEntryType]$EntryType,
        [string]$Message,
        [string]$LogName,
        [string]$Source
    )

    $writeEventLogCmd = Get-Command -Name Write-EventLog -ErrorAction SilentlyContinue
    if ($null -ne $writeEventLogCmd) {
        Write-EventLog -LogName $LogName -Source $Source -EventId $EventId -EntryType $EntryType -Message $Message
        return
    }

    [System.Diagnostics.EventLog]::WriteEntry($Source, $Message, $EntryType, $EventId)
}

if (-not (Test-IsAdministrator)) {
    throw 'Administrator privileges are required to run this script.'
}

$eventLogName = 'Application'
$eventSource = 'TempFolderCleanout'

Ensure-EventSource -LogName $eventLogName -Source $eventSource

try {
    $defaultPaths = Get-DefaultTempPaths
    $targetPaths = Resolve-TargetPaths -Defaults $defaultPaths -Extras $AdditionalPaths

    if (-not $targetPaths) {
        Write-Warning 'No target paths were resolved. Nothing to do.'

        $noTargetMessage = 'Temp cleanup skipped: no target paths were resolved.'
        Write-CleanupEvent -EventId 2001 -EntryType ([System.Diagnostics.EventLogEntryType]::Information) -Message $noTargetMessage -LogName $eventLogName -Source $eventSource
        return
    }

    $cutoffDate = (Get-Date).AddDays(-1 * $RetentionDays)
    Write-Verbose ("Preparing to delete files last modified before {0}" -f $cutoffDate.ToString('u'))

    $cleanupResult = Invoke-TempCleanup -Paths $targetPaths -CutoffDate $cutoffDate

    Write-Host 'Cleanup complete. Summary:'
    $cleanupResult.Summary.GetEnumerator() | ForEach-Object {
        Write-Host ("  {0}: {1}" -f $_.Key, $_.Value)
    }
    $bytesRemovedKB = [Math]::Round(($cleanupResult.Summary.BytesRemoved / 1KB), 2)
    Write-Host ("  BytesRemovedKB: {0}" -f $bytesRemovedKB)

    $summaryData = $cleanupResult.Summary
    $successMessage = 'Temp cleanup completed. Paths processed: {0}; Candidates found: {1}; Removed: {2}; Failures: {3}.' -f `
        $summaryData.PathsProcessed, `
        $summaryData.CandidatesFound, `
        $summaryData.Removed, `
        $summaryData.Failed
    $successMessage += " Kilobytes removed: {0:N2} KB." -f $bytesRemovedKB

    Write-CleanupEvent -EventId 2001 -EntryType ([System.Diagnostics.EventLogEntryType]::Information) -Message $successMessage -LogName $eventLogName -Source $eventSource

    if ($cleanupResult.Failures.Count -gt 0) {
        Write-Warning 'Some files could not be removed. Review details below.'
        $cleanupResult.Failures | Format-Table -AutoSize

        $maxFailuresToLog = 5
        $failureLines = $cleanupResult.Failures |
            Select-Object -First $maxFailuresToLog |
            ForEach-Object { "* $($_.Path) -> $($_.Reason): $($_.Message)" }

        $failureMessage = "Temp cleanup encountered failures. Total failures: $($cleanupResult.Failures.Count)."
        if ($failureLines) {
            $failureMessage += [Environment]::NewLine + ($failureLines -join [Environment]::NewLine)

            if ($cleanupResult.Failures.Count -gt $maxFailuresToLog) {
                $remaining = $cleanupResult.Failures.Count - $maxFailuresToLog
                $failureMessage += [Environment]::NewLine + "(Additional $remaining failures not listed.)"
            }
        }

        $failureMessage += [Environment]::NewLine + ("Kilobytes removed before failure: {0:N2} KB." -f $bytesRemovedKB)

        Write-CleanupEvent -EventId 2002 -EntryType ([System.Diagnostics.EventLogEntryType]::Error) -Message $failureMessage -LogName $eventLogName -Source $eventSource
    }
}
catch {
    $exceptionMessage = $_.Exception.Message
    $errorMessage = "Temp cleanup terminated unexpectedly: $exceptionMessage"
    if ($cleanupResult -and $cleanupResult.Summary -and $cleanupResult.Summary.Contains("BytesRemoved")) {
        $errorBytesRemovedKB = [Math]::Round(($cleanupResult.Summary.BytesRemoved / 1KB), 2)
        $errorMessage += " Kilobytes removed before error: {0:N2} KB." -f $errorBytesRemovedKB
    }

    try {
        Write-CleanupEvent -EventId 2002 -EntryType ([System.Diagnostics.EventLogEntryType]::Error) -Message $errorMessage -LogName $eventLogName -Source $eventSource
    }
    catch {
        Write-Warning ("Unable to write to event log: {0}" -f $_.Exception.Message)
    }

    throw
}
