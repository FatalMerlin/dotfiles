#Requires AutoHotkey v2.0
#SingleInstance Force

;; Enable Umlauts without US Intl layout

; RAlt P -> oe
>!p::
{
    SendText("ö")
}

; Shift RAlt P -> OE
+>!p::
{
    SendText("Ö")
}

; RAlt Y -> ue
>!y::
{
    SendInput("ü")
}

; Shift RAlt Y -> UE
+>!y::
{
    SendInput("Ü")
}

; RAlt Q -> ae
>!q::
{
    SendInput("ä")
}

; Shift RAlt Q -> AE
+>!q::
{
    SendInput("Ä")
}

; RAlt S -> SZ
>!s::
{
    SendInput("ß")
}

; Shift RAlt S -> SZ (no uppercase)
+>!s::
{
    SendInput("ß")
}

; RAlt W -> š
>!w::
{
    SendInput("š")
}

; RAlt W -> Š
+>!w::
{
    SendInput("Š")
}

; RAlt 5 -> Euro
>!5::
{
    SendInput("€")
}

>!0::
{
    SendInput("°")
}
