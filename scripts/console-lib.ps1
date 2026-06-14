#!/usr/bin/env pwsh
# Grimdex console helpers — label the window and place it on a chosen display.
# Everything here is best-effort: headless/service contexts have no window, and under
# Windows Terminal (pty) the conhost HWND move may be a no-op. Failures return $false.
Set-StrictMode -Version Latest

function Get-GrimdexDisplayBounds {
    # Working area of Windows display N (\\.\DISPLAYN). Falls back to the first
    # non-primary display, then the primary, so routine windows land on a secondary
    # screen when one exists. $null when screens can't be enumerated.
    param([int]$Display = 1)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $screens = [System.Windows.Forms.Screen]::AllScreens
        if (-not $screens) { return $null }
        $target = $screens | Where-Object { $_.DeviceName -like "*DISPLAY$Display" } | Select-Object -First 1
        if (-not $target) { $target = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1 }
        if (-not $target) { $target = $screens | Where-Object Primary | Select-Object -First 1 }
        return $target.WorkingArea
    } catch { return $null }
}

function Set-GrimdexConsoleWindow {
    # Titles the current console and moves it onto the requested display.
    param(
        [string]$Title,
        [int]$Display = 1,
        [int]$Width = 1100,
        [int]$Height = 720
    )
    try {
        if ($Title) { $Host.UI.RawUI.WindowTitle = $Title }
        $bounds = Get-GrimdexDisplayBounds -Display $Display
        if (-not $bounds) { return $false }
        if (-not ('GrimdexWin32.Native' -as [type])) {
            Add-Type -Namespace GrimdexWin32 -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool MoveWindow(System.IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
'@
        }
        $hwnd = [GrimdexWin32.Native]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return $false }
        $x = $bounds.X + [int](($bounds.Width - $Width) / 2)
        $y = $bounds.Y + [int](($bounds.Height - $Height) / 2)
        return [GrimdexWin32.Native]::MoveWindow($hwnd, $x, $y, $Width, $Height, $true)
    } catch { return $false }
}
