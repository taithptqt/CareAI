$adb = "C:\Users\DELL\AppData\Local\Android\Sdk\platform-tools\adb.exe"
while ($true) {
    try {
        & $adb wait-for-device
        & $adb reverse tcp:5097 tcp:5097 2>$null
    } catch {
        # ignore transient errors
    }
    Start-Sleep -Seconds 2
}
