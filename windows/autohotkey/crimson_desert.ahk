#Requires AutoHotkey v2.0
#SingleInstance Force

;; Crimson Desert - hands-free auto-follow latch.
;;
;; Why: the game auto-follows an NPC (on foot or horseback) only while the run
;; key is physically held, and ships no toggle for it. Long ride-along and
;; walk-along quest sequences - cutscenes in all but name - therefore need Shift
;; held down for minutes at a time. F8 latches it so those sequences play out
;; unattended, including while tabbed out to another window.
;;
;; The known community workaround is to hold Shift and then open the Steam
;; overlay (Shift+Tab), which swallows the key-up so the game keeps running.
;; That is evidence the game does not reset its input state when focus shifts;
;; this script reproduces the same latch without occupying the screen.

CRIMSON_DESERT_WINDOW_FILTER := "ahk_exe CrimsonDesert.exe"

; Latch state. Global rather than static because CrimsonDesertLoop() - driven by
; the central loop in main.ahk - has to read it too.
crimsonDesertRiding := false

/**
 * Latches or releases the run key.
 *
 * Uses Send (SendInput) rather than ControlSend: ControlSend posts window
 * messages via PostMessage, which DirectInput/Raw Input titles typically
 * ignore, whereas SendInput goes through the driver-level input path the game
 * actually reads.
 *
 * @param riding {Boolean} true to hold the run key down, false to release it.
 */
CrimsonDesertSetRiding(riding) {
    global crimsonDesertRiding

    crimsonDesertRiding := riding
    Send(riding ? "{Shift down}" : "{Shift up}")
}

/**
 * Releases a latched run key on script exit.
 *
 * SendInput mutates the real OS keyboard state, so a latched Shift outlives the
 * script being reloaded (Ctrl+Alt+R) or killed - leaving Shift stuck down
 * system-wide until the user notices and taps it. Always unwind on the way out.
 */
CrimsonDesertRelease(*) {
    if (crimsonDesertRiding) {
        CrimsonDesertSetRiding(false)
    }
}

OnExit(CrimsonDesertRelease)

/**
 * Per-tick upkeep, called from the central loop in main.ahk.
 *
 * Covers the case the Steam-overlay evidence does not: the overlay is an
 * in-process hook and leaves the game focused, whereas a real alt-tab delivers
 * WM_KILLFOCUS and *may* make the game drop the held key. Re-posting the key
 * down directly to the window each tick re-asserts the latch if so, and is a
 * harmless repeat if not.
 *
 * Also fails safe: if the game exits while latched, drop the latch rather than
 * leave Shift held.
 */
CrimsonDesertLoop() {
    if (!crimsonDesertRiding) {
        return
    }

    if (!WinExist(CRIMSON_DESERT_WINDOW_FILTER)) {
        CrimsonDesertRelease()
        return
    }

    ; Focused: the SendInput latch is already in effect, nothing to do.
    if (WinActive(CRIMSON_DESERT_WINDOW_FILTER)) {
        return
    }

    ControlSend("{Shift down}", , CRIMSON_DESERT_WINDOW_FILTER)
}

; Claim F8 only while the game is running, so the key stays free otherwise.
; WinExist rather than WinActive on purpose: the latch must stay releasable
; after tabbing away from the game, which is the entire point of the feature.
#HotIf WinExist(CRIMSON_DESERT_WINDOW_FILTER)

; F8 - toggle hands-free auto-follow.
F8::
{
    CrimsonDesertSetRiding(!crimsonDesertRiding)
    TrayTip(crimsonDesertRiding ? "Auto-follow ON" : "Auto-follow OFF", A_ScriptName)
}

#HotIf
