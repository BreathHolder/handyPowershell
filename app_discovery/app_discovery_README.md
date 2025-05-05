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

4. **Logging in verbose mode** by:
   - on the command line, run `.\discover.ps1 -Verbose`

---

## 🧪 Sample Entry (discovery log)

```json
{
    "Timestamp":  "2025-05-05T14:44:44",
    "ComputerName":  "ACME-WS-1011",
    "UserName":  "bwilson",
    "Apps":  [
                 {
                     "AppName":  "Mozilla Firefox",
                     "ExeVersions":  "137.0.2",
                     "InstallPaths":  "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
                     "RegistryEntries":  [
                                             {
                                                 "KeyPath":  "HKCU:\\Software\\Mozilla\\Mozilla Firefox",
                                                 "Values":  "@{ValueName=CurrentVersion; Tokens=137.0.2; (x64; en-US)}"
                                             },
                                             {
                                                 "KeyPath":  "HKLM:\\Software\\Mozilla\\Mozilla Firefox",
                                                 "Values":  "@{ValueName=CurrentVersion; Tokens=137.0.2; (x64; en-US)}"
                                             }
                                         ],
                     "LastRunTime":  "2025-05-05T14:48:59",
                     "Found":  true
                 },
                 {
                     "AppName":  "NotePad++",
                     "ExeVersions":  "8.6.5",
                     "InstallPaths":  "C:\\Program Files\\Notepad++\\Notepad++.exe",
                     "RegistryEntries":  {
                                             "KeyPath":  "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Notepad++",
                                             "Values":  [
                                                            "@{ValueName=DisplayName; Tokens=Notepad++; (64-bit; x64)}",
                                                            "@{ValueName=DisplayVersion; Tokens=8.6.5}"
                                                        ]
                                         },
                     "LastRunTime":  "2025-05-05T15:20:02",
                     "Found":  true
                 }
             ]
}
```

---

## 🛠️ Setup Instructions

1. Edit `tech_config.json` to define the applications you want to track. Using `"RegistryValueNames": [ "*" ]` will return all registry value items. Here's a sample:
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
            ],
            "RegistryValueNames": [
                "CurrentVersion"
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
- AppVersion
- InstallPaths
- RegistryPaths & Values
- LastAccessed
- Found (boolean)

---

## 🔒 Notes

- File LastAccessed may not always be available if the software hasn't been used since logging began. It needs to be used once since logging began to find the software
- Running this script **absolutely requires** elevated privileges
- Version detection works for EXEs with standard version metadata
---

## 🚀 Future Enhancements (Ideas)

- Scan all user profiles' HKCU registry
- Upload logs to central share or API
- Email alerts on certain findings