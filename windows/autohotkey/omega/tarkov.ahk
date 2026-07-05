#Requires AutoHotkey v2.0
#SingleInstance Force

tarkovExeName := "tarkov.exe"
monitorExeName := "tarkovmonitor.exe"
ratscannerExeName := "ratscanner.exe"

Launch(exeName) {
    try {
        Run(exeName)
    } catch Error as e {
        TrayTip("Error launching " exeName " (" e.Message ")", A_ScriptName)
    }
}

TarkovLoop() {
    tarkovPID := ProcessExist(tarkovExeName)

    if (tarkovPID == 0) {
        return
    }

    monitorPID := ProcessExist(monitorExeName)
    scannerPID := ProcessExist(ratscannerExeName)

    if (monitorPID == 0) {
        Launch(monitorExeName)
    }

    if (scannerPID == 0) {
        Launch(ratscannerExeName)
    }
}
