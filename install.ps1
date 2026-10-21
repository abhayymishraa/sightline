# Sightline installer for Windows 10 and 11.
#
#   Install or update:  irm https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.ps1 | iex
#   Uninstall:          & ([scriptblock]::Create((irm https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.ps1))) -Uninstall
#
# Installs for the current user only (no administrator rights): %LOCALAPPDATA%\Programs\Sightline,
# plus a Start menu shortcut.
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is much faster without the progress bar

$Repo = "abhayymishraa/sightline"
$Url = "https://github.com/$Repo/releases/latest/download/Sightline-Windows.zip"
$Dir = Join-Path $env:LOCALAPPDATA "Programs\Sightline"
$Shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Sightline.lnk"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

function Step($text) { Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $text }

function Stop-Sightline {
    Get-Process -Name Sightline -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

if ($Uninstall) {
    Step "Quitting Sightline"
    Stop-Sightline
    Step "Removing the app, shortcut and autostart entry"
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $Shortcut -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $RunKey -Name "Sightline" -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:APPDATA "Sightline") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Sightline is uninstalled." -ForegroundColor Green
    return
}

if ([Environment]::OSVersion.Version.Major -lt 10) { throw "Sightline needs Windows 10 or 11." }

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("sightline-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    Step "Downloading the latest Sightline"
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $Tmp "Sightline.zip") -UseBasicParsing
    Expand-Archive -Path (Join-Path $Tmp "Sightline.zip") -DestinationPath $Tmp -Force
    $Payload = Join-Path $Tmp "Sightline"
    if (-not (Test-Path (Join-Path $Payload "Sightline.exe"))) { throw "The download did not contain Sightline.exe." }

    Step "Installing to $Dir"
    Stop-Sightline
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path (Split-Path $Dir) -Force | Out-Null
    Move-Item $Payload $Dir
    Get-ChildItem $Dir -Recurse | Unblock-File

    Step "Adding a Start menu shortcut"
    $Shell = New-Object -ComObject WScript.Shell
    $Link = $Shell.CreateShortcut($Shortcut)
    $Link.TargetPath = Join-Path $Dir "Sightline.exe"
    $Link.WorkingDirectory = $Dir
    $Link.Description = "Type where you look"
    $Link.Save()

    Step "Starting Sightline"
    Start-Process (Join-Path $Dir "Sightline.exe")
}
finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Sightline is installed." -ForegroundColor Green
Write-Host "Find it in the notification area next to the clock. The Getting Started window sets up your screens."
Write-Host "Update: run this command again. Uninstall: see the README." -ForegroundColor DarkGray
