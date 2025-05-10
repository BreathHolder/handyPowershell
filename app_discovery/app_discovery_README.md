# 🔍 PowerShell Application Discovery Script

This PowerShell script is designed to help technology owners in your organization discover the presence and details of installed applications across company workstations. It reads from a centralized configuration file, performs local discovery using data on the file system as well as registry data to build structured, human-readable CSV reports and error logs.

---

## 📁 File Structure

```
.
├── discover.ps1                # Main PowerShell app
├── tech_config.json            # Config file with apps, paths, registry entries
└── logs\
    └── discovery_YYYYMMDD.csv  # CSV file for System Ingest
```

---

## ⚙️ How It Works

1. **Loads** `tech_config.json` containing:
   - App name
   - EXE path candidates
   - Registry paths to check
   - Optional registry value names to look for

2. **Scans** the local system:
   - Verifies EXE paths exist
   - Pulls matching registry values from `HKLM` and `HKCU`
   - Uses `DisplayVersion` or `CurrentVersion` as the primary version identifier
   - Optionally checks the Event Log for last-run info (`Event ID 4688`)

3. **Outputs results** to:
   - `discovery_apps_YYYYMMDD.csv` for easy review or ingestion into Excel, Splunk, etc.
   - `error_YYYYMMDD.log` if any paths or registry reads fail
   - `warnings_YYYYMMDD.log` if `Get-WinEvent` hits a limit (default max is 1000 events)

---

## 🧪 Sample Output (CSV)

| AppName         | AppVersion             | InstallPaths                                  | LastRunTime         | Found | RegistrySummary                                                                                                  |
|-----------------|------------------------|-----------------------------------------------|----------------------|--------|------------------------------------------------------------------------------------------------------------------|
| Mozilla Firefox | 138.0.1 (x64 en-US)    | C:\Program Files\Mozilla Firefox\firefox.exe  | 2025-05-10T17:44:09  | True   | CurrentVersion=138.0.1 (x64 en-US); 138.0.1; (x64; en-US) \| Acme_Inc_SW_Tech_Owner=Elmer Fudd \| ...          |
| Notepad++       | 8.8.1                  | F:\Program Files\Notepad++\Notepad++.exe      | 2025-05-10T17:28:31  | True   | DisplayVersion=8.8.1 \| DisplayName=Notepad++ (64-bit x64); Notepad++; (64-bit; x64)                            |

---

## 🛠️ Setup Instructions

1. **Edit `tech_config.json`** to define applications. Example:
    ```json
    [
        {
            "AppName": "Mozilla Firefox",
            "InstallPaths": [
                "C:\\Program Files\\Mozilla Firefox\\firefox.exe"
            ],
            "RegistryPaths": [
                "HKLM:\\Software\\Mozilla\\Mozilla Firefox",
                "HKCU:\\Software\\Mozilla\\Mozilla Firefox"
            ],
            "RegistryValueNames": [ "*" ]
        }
    ]
    ```

2. **Run the script**:
    ```powershell
    .\discover.ps1 -EnableEventScan
    ```

    Optional:
    ```powershell
    .\discover.ps1 -ConfigFile ".\alternate_config.json" -LogDir "C:\Logs"
    ```

---

## ⚠️ Event Log Notes

- If `-EnableEventScan` is set, the script checks for recent `Event ID 4688` entries in the Security log.
- By default, it searches the **last hour** and limits results to **1000 events**.
- If the max is hit, a warning is logged to `warnings_YYYYMMDD.log`.

---

## 📤 Output Summary

- **CSV Report**: One row per app
- **AppVersion**: Pulled from registry (`DisplayVersion` or `CurrentVersion`) or EXE fallback
- **RegistrySummary**: All matching values (name=value) from the specified keys
- **InstallPaths**: First matched EXE path
- **LastRunTime**: Most recent matching Security log entry (if enabled)

---

## ❌ Error Logging

All script exceptions are captured in `error_YYYYMMDD.log`, including:
- Registry access errors
- Missing EXEs
- Script bugs or misconfigured inputs

---

## 🔒 Requirements

- Must be run with **elevated privileges**
- Requires access to the Windows Security event log
- Works best with PowerShell 7+

---

## 🚀 Ideas for Future Enhancements

- [ ] Support for checking `UninstallString` values
- [ ] Scan all user profiles for HKCU keys
- [ ] Compare results with a baseline and report deltas
- [ ] Inclusion in automated system and data collection tool to trend in the long term