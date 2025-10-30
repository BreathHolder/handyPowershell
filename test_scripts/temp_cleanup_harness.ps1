<#
.SYNOPSIS
    Exercises tempFolderCleanout.ps1 with both success and failure scenarios.

.DESCRIPTION
    Creates throwaway directories under the system TEMP path, populates them with
    files older than the retention window, then invokes the cleanup script twice:
      * Success case: files are deleted as expected.
      * Failure case: one file is locked to force a deletion error.

.NOTES
    Run from an elevated PowerShell session so the cleanup script can write to the event log.
#>

[CmdletBinding()]
param(
    [string]$CleanupScriptPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\temp-folder-cleanout\tempFolderCleanout.ps1'),
    [string]$TestRoot = (Join-Path -Path $env:TEMP -ChildPath 'TempCleanupHarness'),
    [int]$RetentionDays = 1
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-TestArea {
    param(
        [string]$RootPath
    )

    if (Test-Path -Path $RootPath) {
        Remove-Item -Path $RootPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
}

function New-OldFile {
    param(
        [string]$FilePath,
        [string]$Content = 'placeholder'
    )

    $directory = Split-Path -Path $FilePath -Parent
    if (-not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $FilePath -Value $Content -Encoding UTF8
    (Get-Item -LiteralPath $FilePath).LastWriteTime = (Get-Date).AddDays(-30)
}

if (-not (Test-IsAdministrator)) {
    throw 'This harness must be run from an elevated PowerShell session.'
}

if (-not (Test-Path -Path $CleanupScriptPath -PathType Leaf)) {
    throw "Cleanup script not found at path: $CleanupScriptPath"
}

Initialize-TestArea -RootPath $TestRoot

$successDir = Join-Path -Path $TestRoot -ChildPath 'SuccessCase'
$failureDir = Join-Path -Path $TestRoot -ChildPath 'FailureCase'

New-OldFile -FilePath (Join-Path -Path $successDir -ChildPath 'old-success.txt') -Content 'Delete me'

$lockedFilePath = Join-Path -Path $failureDir -ChildPath 'old-locked.txt'
New-OldFile -FilePath $lockedFilePath -Content 'Locked file'
$lockedStream = [System.IO.File]::Open($lockedFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)

try {
    Write-Host '--- Running success scenario ---'
    & $CleanupScriptPath -RetentionDays $RetentionDays -AdditionalPaths $successDir -Confirm:$false -Verbose:$false

    $successRemoved = -not (Test-Path -Path (Join-Path -Path $successDir -ChildPath 'old-success.txt'))
    if ($successRemoved) {
        Write-Host 'Success scenario: PASSED (file removed)'
    }
    else {
        Write-Warning 'Success scenario: FAILED (file still present)'
    }

    Write-Host '--- Running failure scenario (locked file) ---'
    & $CleanupScriptPath -RetentionDays $RetentionDays -AdditionalPaths $failureDir -Confirm:$false -Verbose:$false

    $failureStillExists = Test-Path -Path $lockedFilePath
    if ($failureStillExists) {
        Write-Host 'Failure scenario: PASSED (locked file remained and should log event 2002)'
    }
    else {
        Write-Warning 'Failure scenario: FAILED (locked file was unexpectedly removed)'
    }
}
finally {
    if ($lockedStream) {
        $lockedStream.Dispose()
    }
}

Write-Host ''
Write-Host 'Cleanup of test directories is left in place for manual inspection:'
Write-Host "  $successDir"
Write-Host "  $failureDir"
Write-Host 'Remove them when finished testing.'
