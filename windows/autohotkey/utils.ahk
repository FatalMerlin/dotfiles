#Requires AutoHotkey v2.0
#SingleInstance Force

UTILS_CONSOLE_HANDLE := ""

EnsureConsole() {
    global UTILS_CONSOLE_HANDLE

    if (UTILS_CONSOLE_HANDLE) {
        return UTILS_CONSOLE_HANDLE
    }

    DllCall("AllocConsole")
    UTILS_CONSOLE_HANDLE := DllCall("GetConsoleWindow", "ptr")
    WinHide("ahk_id " UTILS_CONSOLE_HANDLE)
}

RunWaitOne(command) {
    EnsureConsole()
    shell := ComObject("WScript.Shell")
    ; Execute a single command via cmd.exe
    exec := shell.Exec(A_ComSpec " /C " command)
    ; Read and return the command's output
    return exec.StdOut.ReadAll()
}

RunWaitMany(commands) {
    EnsureConsole()
    shell := ComObject("WScript.Shell")
    ; Open cmd.exe with echoing of commands disabled
    exec := shell.Exec(A_ComSpec " /Q /K echo off")
    ; Send the commands to execute, separated by newline
    exec.StdIn.WriteLine(commands "`nexit")  ; Always exit at the end!
    ; Read and return the output of all commands
    return exec.StdOut.ReadAll()
}

/**
 * Retrieves a secret from 1Password.
 * OTPs are automatically returned as the current token instead of the OTP secret.
 * 
 * @param accountSignInAddress the 1Password account sign-in address, e.g. "your-team.1password.com"
 * @param itemId the 1Password item id
 * @param fieldNames comma separated field names
 * 
 * @returns an array of secret values, in the same order as the field names
 */
GetOpSecret(accountSignInAddress, itemId, fieldNames) {
    opResult := RunWaitOne(
        "pwsh.exe -NonInteractive -NoProfile -Command `"op item get " itemId " --account " accountSignInAddress " --format json --fields '" fieldNames "' | ConvertFrom-Json | ForEach-Object { $_.type -eq 'OTP' ? $_.totp : $_.value }`""
    )

    opResultArray := StrSplit(opResult, '`r`n')
    if (opResultArray[-1] == "") {
        opResultArray.RemoveAt(-1)
    }

    return opResultArray
}
