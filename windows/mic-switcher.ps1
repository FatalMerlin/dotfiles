# mic-switcher.ps1
#Requires -Modules AudioDeviceCmdlets

# --- Config ---
$studioMicName = "FOX"        # Partial name match, adjust to your device
$headsetMicName = "LIGHTSPEED"          # Partial name match
$pollInterval = 500                # ms between polls
$ttsVolume = 50

# --- Helpers ---
function Get-DeviceByPartialName($partialName) {
    Get-AudioDevice -List | Where-Object { $_.Type -eq 'Recording' -and $_.Name -like "*$partialName*" } | Select-Object -First 1
}

function Set-DefaultRecordingDevice($device) {
    Write-Host "Setting default recording device to: $($device.Name)"
    Set-AudioDevice -Index $device.Index | Out-Null
}


function Get-MicPeak($device) {
    return $device.Device.AudioMeterInformation.MasterPeakValue
}

# --- Main loop ---
$studioMic = Get-DeviceByPartialName $studioMicName
$headsetMic = Get-DeviceByPartialName $headsetMicName

if (-not $studioMic -or -not $headsetMic) {
    Write-Error "Could not find one or both devices. Check partial name config."
    exit 1
}

Add-Type -AssemblyName System.Speech
$SpeechSynthesizer = New-Object -TypeName System.Speech.Synthesis.SpeechSynthesizer
$SpeechSynthesizer.SetOutputToDefaultAudioDevice()
$SpeechSynthesizer.Volume = $ttsVolume

Write-Host "Studio:  $($studioMic.Name)"
Write-Host "Headset: $($headsetMic.Name)"

# AudioMeterInformation.MasterPeakValue only returns real values when the audio
# engine has an active capture session on the device. Open one via the Windows
# WASAPI COM interfaces directly — no NAudio dependency, just the OS APIs.
# Guard prevents re-registering on subsequent runs in the same PS session
# (Add-Type types are permanent for the session lifetime).
if (-not ('WasapiKeepAlive' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

// Calls WASAPI via raw vtable function pointers rather than [ComImport]
// interfaces. This avoids GUID conflicts with the COM types AudioDeviceCmdlets
// registers in the same AppDomain.
public class WasapiKeepAlive : IDisposable {
    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(
        ref Guid rclsid, IntPtr pUnkOuter, int dwClsCtx,
        ref Guid riid, out IntPtr ppv);

    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr ptr);

    // Vtable slot helpers
    private static T Fn<T>(IntPtr comPtr, int slot) where T : Delegate {
        IntPtr fn = Marshal.ReadIntPtr(Marshal.ReadIntPtr(comPtr), slot * IntPtr.Size);
        return Marshal.GetDelegateForFunctionPointer<T>(fn);
    }

    // IUnknown::Release  (slot 2)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate uint ReleaseFn(IntPtr self);

    // IMMDeviceEnumerator::GetDevice  (slot 5)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetDeviceFn(IntPtr self,
        [MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IntPtr ppDevice);

    // IMMDevice::Activate  (slot 3)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int ActivateFn(IntPtr self,
        ref Guid riid, int dwClsCtx, IntPtr pParams, out IntPtr ppInterface);

    // IAudioClient::GetMixFormat  (slot 8)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetMixFormatFn(IntPtr self, out IntPtr ppFormat);

    // IAudioClient::Initialize  (slot 3)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int InitializeFn(IntPtr self,
        int shareMode, int streamFlags, long bufDuration, long periodicity,
        IntPtr pFormat, IntPtr sessionGuid);

    // IAudioClient::Start  (slot 10)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int StartFn(IntPtr self);

    // IAudioClient::Stop  (slot 11)
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int StopFn(IntPtr self);

    private IntPtr _enumPtr  = IntPtr.Zero;
    private IntPtr _clientPtr = IntPtr.Zero;

    public WasapiKeepAlive(string deviceId) {
        var clsid = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"); // MMDeviceEnumerator
        var iidEnum = new Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"); // IMMDeviceEnumerator
        Marshal.ThrowExceptionForHR(CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iidEnum, out _enumPtr));

        IntPtr devicePtr;
        Marshal.ThrowExceptionForHR(Fn<GetDeviceFn>(_enumPtr, 5)(_enumPtr, deviceId, out devicePtr));

        var iidClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"); // IAudioClient
        int hr = Fn<ActivateFn>(devicePtr, 3)(devicePtr, ref iidClient, 1, IntPtr.Zero, out _clientPtr);
        Fn<ReleaseFn>(devicePtr, 2)(devicePtr);
        Marshal.ThrowExceptionForHR(hr);

        IntPtr fmtPtr;
        Marshal.ThrowExceptionForHR(Fn<GetMixFormatFn>(_clientPtr, 8)(_clientPtr, out fmtPtr));
        // Shared mode (0), no flags (0), 1-second buffer (10 000 000 × 100 ns), periodicity 0
        hr = Fn<InitializeFn>(_clientPtr, 3)(_clientPtr, 0, 0, 10000000, 0, fmtPtr, IntPtr.Zero);
        CoTaskMemFree(fmtPtr);
        Marshal.ThrowExceptionForHR(hr);

        Marshal.ThrowExceptionForHR(Fn<StartFn>(_clientPtr, 10)(_clientPtr));
    }

    public void Dispose() {
        if (_clientPtr != IntPtr.Zero) {
            try { Fn<StopFn>(_clientPtr, 11)(_clientPtr); } catch { }
            Fn<ReleaseFn>(_clientPtr, 2)(_clientPtr);
            _clientPtr = IntPtr.Zero;
        }
        if (_enumPtr != IntPtr.Zero) {
            Fn<ReleaseFn>(_enumPtr, 2)(_enumPtr);
            _enumPtr = IntPtr.Zero;
        }
    }
}
'@
} # end if (-not ('WasapiKeepAlive' -as [type]))

$headsetKeepAlive = [WasapiKeepAlive]::new($headsetMic.ID)
Write-Host "Headset mic audio session opened (keeps peak meter active)"

$currentActive = "studio"

# Start on studio mic
Write-Host "Starting with studio mic as default"
Set-DefaultRecordingDevice $studioMic
$SpeechSynthesizer.SpeakAsync("Using $currentActive") | Out-Null

try {
    while ($true) {
        $peak = Get-MicPeak $headsetMic
        $now = Get-Date

        Write-Host "[$now] Headset mic peak: $peak"
        if ($peak -eq 0 -and $currentActive -ne "studio") {
            Write-Host "[$now] Headset muted, switching to studio mic"
            Set-DefaultRecordingDevice $studioMic
            $currentActive = "studio"
            $SpeechSynthesizer.SpeakAsync("Using $currentActive") | Out-Null
        }
        elseif ($peak -gt 0 -and $currentActive -ne "headset") {
            Write-Host "[$now] Headset unmuted, switching to headset mic"
            Set-DefaultRecordingDevice $headsetMic
            $currentActive = "headset"
            $SpeechSynthesizer.SpeakAsync("Using $currentActive") | Out-Null
        }

        Start-Sleep -Milliseconds $pollInterval
    }
} finally {
    if ($headsetKeepAlive) { $headsetKeepAlive.Dispose() }
}