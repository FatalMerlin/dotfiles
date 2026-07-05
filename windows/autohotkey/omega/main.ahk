#Requires AutoHotkey v2.0
#SingleInstance Force

; Control Alt R
^!r::
{
    Reload()
    TrayTip("Reloaded", A_ScriptName)
}

; Create (or update) a shortcut in the startup / autostart folder
; This makes sure that the script runs on startup
FileCreateShortcut(A_ScriptFullPath, A_Startup '\' A_ScriptName '.lnk')

; load child scripts here
; for better organization
#Include ./tarkov.ahk
; #Include ./other_file.ahk

; loops in child scripts would block execution of the main script
; but also prevent other child loops from ever running, so instead
; we use a central loop in the main script to call the child loop
; functions instead.
loop {
    Sleep(1000)

    ; loop through the child script loop functions
    ; wrapped in try-catch to prevent crashes
    try {
        TarkovLoop()
    } catch Error as e {
        TrayTip("Error in Loop: " e.Message, A_ScriptName)
    }
}
