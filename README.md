# PowerShell Scripts Collection

A collection of PowerShell scripts for Windows system maintenance, automation, and more.

---

## Scripts Overview

### 1. `Windows11UpdateAndDriversChecker.ps1`
**Description:**  
Checks to see if there are:
- Errors Preventing Windows Updates
- Windows Updates
- Driver Updates

**Variables:**  
- `$monitorWidth1` – Width of monitor 1
- ` $monitorHeight1` - Height of monitor 1
- `$monitorWidth2` – Width of monitor 2
- ` $monitorHeight2` - Height of monitor 2

**Prerequisites:**  
- PowerShell 7.5.0 or higher.
- PSWindowsUpdate module installed:
  ```powershell
  Install-Module -Name PSWindowsUpdate -Force
- Windows 11

### 2. `FixResolution.ps1`
**Description:**
Resets the screen resolution on a Windows 11 machine. Used when I return to my PC from remote apps like Jump Desktop. Setup is for 2 monitors but it can be for 1 or more than 2.

**Variables:**  
- `$logPath` – Path for the log file (default is the user’s home directory).

**Prerequisites:**
- [NirSoft's NirCMD](https://www.nirsoft.net/utils/nircmd.html)
- Windows 11

###  3. `CheckAndStartJumpDesktop`

**Description:**
Script which checks for the `JumpConnect` service state. If it is started, it logs a message to say it is already running. If not, it starts the service. This script is designed to run as part of a scheduled task.

**Variables:**
Most of the variables we are going to set are within the new schedule task you will build. This is designed to work on Windows 10/11.

- *Security Options:* 
  - Select `Run whether user is logged on or not`
  - Select `Run with highest privileges`
- *Configure for:*
  - Select `Windows 10`
- *Triggers:* Select New Trigger

**Prerequisites:**
