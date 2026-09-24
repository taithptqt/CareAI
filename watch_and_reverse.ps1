$adb = "C:\Users\DELL\AppData\Local\Android\Sdk\platform-tools\adb.exe"
while ($true) {
    try {
        $devs = & $adb devices
        if ($devs -match "R5CY10M8BZN\s+device") {
            & $adb -s R5CY10M8BZN reverse tcp:5097 tcp:5097 2>$null
        }
    } catch {
        # ignore
    }
    Start-Sleep -Seconds 2
}
