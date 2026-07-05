#Requires AutoHotkey v2.0
#SingleInstance Force

YT_MUSIC_WINDOW_AHK_CLASS := "Chrome_WidgetWin_1"
YT_MUSIC_WINDOW_TITLE_PREFIX := "YouTube Music"
; YT_MUSIC_WINDOW_CONTROL_CLASS_NN := "Intermediate D3D Window1"
YT_MUSIC_WINDOW_CONTROL_CLASS_NN := "Chrome_RenderWidgetHostHWND1"

YT_MUSIC_WINDOW_FILTER := YT_MUSIC_WINDOW_TITLE_PREFIX " ahk_class " YT_MUSIC_WINDOW_AHK_CLASS

; See: https://www.autohotkey.com/docs/v2/misc/Styles.htm#Common
WS_MINIMIZE := 0x20000000

/**
 * Sends a keyboard shortcut to the YouTube Music PWA Window.
 * @param shortcut {string} The keyboard shortcut to send. Available shortcuts can be displayed by pressing `?` (`Shift + /`) in YT Music.
 */
yt_music_send_keyboard_shortcut(shortcut, self_call := false) {
    try {
        SetTitleMatchMode(1)
        win_hwnd := WinGetID(YT_MUSIC_WINDOW_FILTER)
        win_hwnd_filter := 'ahk_id ' win_hwnd
        ; Focus Control of desired Window FIRST, explicitly specifying the control AND the window filter
        ControlFocus(YT_MUSIC_WINDOW_CONTROL_CLASS_NN, win_hwnd_filter)
        ; DO NOT specificy the control in ControlSend, it doesn't work
        ; Instead we just rely on the focussed control
        ControlSend(
            shortcut,
            , ; intentionally empty
            win_hwnd_filter
        )
    } catch Error as e {
        if (!self_call ; prevent infinite recursion
            && win_hwnd != "" ; ensure that the window exists
            && win_hwnd != 0  ; and win_hwnd was set
            && WinGetStyle(win_hwnd_filter) & WS_MINIMIZE
        ) {
            ; YT Music was minimized, let's restore it and immediately
            ; move it to the background, then send the shortcut again
            WinRestore(win_hwnd_filter)
            WinMoveBottom(win_hwnd_filter)
            yt_music_send_keyboard_shortcut(shortcut, true)
        }
        ; YT Music was not open
    }
}

F17::
{
    yt_music_send_keyboard_shortcut("{+}")
}

F18::
{
    yt_music_send_keyboard_shortcut("_")
}
