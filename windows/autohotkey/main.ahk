#Requires AutoHotkey v2.0
#SingleInstance Force

; Control Alt R
^!r::
{
    Reload()
    TrayTip("Reloaded", A_ScriptName)
}

#Include ./vpn.ahk
#Include ./thinlinc.ahk
#Include ./yt_music.ahk
#Include ./umlaut.ahk

loop {
    Sleep(1000)
    VPNLoop()
    ; ThinLincLoop()
}
