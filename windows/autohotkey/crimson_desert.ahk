#Requires AutoHotkey v2.0
#SingleInstance Force

;; Crimson Desert - hands-free auto-follow latch.
;;
;; Why: the game auto-follows an NPC (on foot or horseback) only while the run
;; key is physically held, and ships no toggle for it. Long ride-along and
;; walk-along quest sequences - cutscenes in all but name - therefore need Shift
;; held down for minutes at a time. F8 latches it so they play out hands-free.
;;
;; SCOPE - the game must stay focused. Tabbing out stops the character, and
;; that is not fixable from here. Two mechanisms were tried and measured:
;;
;;   1. A latched Send (below). Works, but Windows routes keyboard input only
;;      to the focused window, so it stops the moment focus moves elsewhere.
;;   2. Re-posting the key down with ControlSend each tick while unfocused.
;;      ControlSend delivers via PostMessage, and this game ignores posted
;;      keyboard messages entirely - measured in-game, the character stopped
;;      while the re-assert was firing once a second with no error. Removed.
;;      Do not reintroduce it; it does nothing here.
;;
;; The community Steam-overlay trick (hold Shift, then Shift+Tab) is not a
;; counter-example: the overlay is an in-process hook that leaves the game
;; focused, which is exactly why the held key survives it.
;;
;; Reaching a genuinely unfocused game would need input that bypasses window
;; focus altogether - i.e. a virtual XInput pad via ViGEmBus - and is only
;; worth the driver install if a real controller's held button is observed to
;; survive alt-tab first.

CRIMSON_DESERT_WINDOW_FILTER := "ahk_exe CrimsonDesert.exe"

; Latch state. Global rather than static because CrimsonDesertLoop() - driven by
; the central loop in main.ahk - has to read it too.
crimsonDesertRiding := false

/**
 * Latches or releases the run key.
 *
 * Send (SendInput) goes through the driver-level input path the game reads.
 * See the ControlSend note in the file header before reaching for that instead.
 *
 * @param riding {Boolean} true to hold the run key down, false to release it.
 */
CrimsonDesertSetRiding(riding) {
    global crimsonDesertRiding

    crimsonDesertRiding := riding
    Send(riding ? "{Shift down}" : "{Shift up}")
}

/**
 * Releases a latched run key.
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
 * Fail-safe, called once per tick by the central loop in main.ahk: if the game
 * exits while the latch is engaged, drop the latch instead of leaving Shift
 * held down across the whole desktop.
 */
CrimsonDesertLoop() {
    if (crimsonDesertRiding && !WinExist(CRIMSON_DESERT_WINDOW_FILTER)) {
        CrimsonDesertRelease()
    }
}

; Claim F8 only while the game is running, so the key stays free otherwise.
; WinExist rather than WinActive on purpose: alt-tabbing stops the ride but does
; NOT clear the latch, so F8 has to stay live outside the game to release it.
#HotIf WinExist(CRIMSON_DESERT_WINDOW_FILTER)

; F8 - toggle hands-free auto-follow.
F8::
{
    CrimsonDesertSetRiding(!crimsonDesertRiding)
    TrayTip(crimsonDesertRiding ? "Auto-follow ON" : "Auto-follow OFF", A_ScriptName)
}

#HotIf
