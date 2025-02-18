$monitorWidth1 = 2560
$monitorHeight1 = 1440
$monitorWidth2 = 2560
$monitorHeight2 = 1440

Start-Process -FilePath "C:\Tools\NirCmd\nircmd.exe" -ArgumentList "setdisplay monitor:0 $monitorWidth1 $monitorHeight1 32" -Wait
Start-Process -FilePath "C:\Tools\NirCmd\nircmd.exe" -ArgumentList "setdisplay monitor:1 $monitorWidth2 $monitorHeight2 32" -Wait
