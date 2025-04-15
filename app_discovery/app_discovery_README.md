# 🔍 PowerShell Application Discovery Script

This PowerShell script is designed to help technology owners in your organization discover the presence and details of installed applications across company workstations. It reads from a centralized configuration file, performs local discovery using file system and registry data, and logs structured output for ingestion by platforms like **Splunk**.

---

## 📁 File Structure

```
.
├── discover.ps1                # Main PowerShell app
├── tech_config.json            # Config file with apps, paths, registry entries
└── logs\
    └── discovery_YYYYMMDD.log  # Log file for Splunk ingestion
```

---

## ⚙️ How It Works

1. **Reads from** `tech_config.json` for:
   - App name
   - One or more installation path candidates
   - One or more registry key paths

2. **Scans local machine** for:
   - Installed EXEs
   - Registry entries in both `HKLM` and `HKCU`

3. **Logs structured discovery results** to:
   - `logs/discovery_YYYYMMDD.log` (JSON format, Splunk-ready)
   - `logs/error_YYYYMMDD.log` (errors captured per app/path with context)

---

## 🧪 Sample Entry (discovery log)

```json
{
  "Timestamp": "2025-04-14T12:17:43",
  "ComputerName": "ACME-WS-1011",
  "UserName": "bwilson",
  "AppName": "NotePad++",
  "InstallPaths": "C:\\Program Files\\Notepad++\\Notepad++.exe",
  "RegistryPaths": "",
  "LastAccessed": "2025-04-12T14:55:03",
  "ExeVersions": "C:\\Program Files\\Notepad++\\Notepad++.exe: 8.6.3",
  "Found": true
}
```

---

## 🛠️ Setup Instructions

1. Edit `tech_config.json` to define the applications you want to track. Here's a sample:
    ```json
    [
        {
            "AppName": "Mozilla Firefox",
            "InstallPaths": [
            "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
            "C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe"
            ],
            "RegistryPaths": [
            "HKLM:\\Software\\Mozilla\\Mozilla Firefox",
            "HKLM:\\Software\\WOW6432Node\\Mozilla\\Mozilla Firefox",
            "HKCU:\\Software\\Mozilla\\Mozilla Firefox"
            ]
        }
    ]
    ```
2. Run the Script `.\discover.ps1`.
   - Optionally, you can provide a config path or log directory:
     ```powershell
     .\discover.ps1 -ConfigFile ".\my_config.json" -LogDir "C:\MyLogs"
     ```

---

## 🧯 Error Logging

All errors are logged to logs/error_YYYYMMDD.log with:
- Timestamp
- Context of error (which app/path)
- Error message
- Stack trace (if available)

---

## ✅ Output Formats

All logs are written in JSON for easy Splunk/Logstash ingestion

Fields include:
- AppName
- InstallPaths
- RegistryPaths
- ExeVersions
- LastAccessed
- Found (boolean)

---

## 🔒 Notes

- File LastAccessed may not always be available (depends on NTFS config)
- Registry access may require elevated permissions
- Version detection works for EXEs with standard version metadata

---

## 🚀 Future Enhancements (Ideas)

- Scan all user profiles' HKCU registry
- Extract ProductName, CompanyName from EXEs
- Upload logs to central share or API
- Email alerts on certain findings