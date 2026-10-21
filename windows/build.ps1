# Builds dist\Sightline-Windows.zip. Run from any folder: powershell -File windows\build.ps1
# Needs Python 3.10-3.12 on PATH.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

python -m pip install --upgrade pip | Out-Null
python -m pip install -e ".[build]"

# The MediaPipe face model (Apache-2.0) ships inside the app so the first launch needs no download.
$model = "sightline\face_landmarker.task"
if (-not (Test-Path $model)) {
    Invoke-WebRequest "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task" -OutFile $model
}

python -c "from PIL import Image; Image.open('sightline/assets/icon.png').save('icon.ico', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])"

python -m PyInstaller --noconfirm --clean --windowed --name Sightline --icon icon.ico `
    --collect-all mediapipe `
    --add-data "sightline\face_landmarker.task;." `
    --add-data "sightline\assets;assets" `
    run.py

# Smoke test: the packaged app imports everything, finds the model and passes the gaze checks.
# The windowed .exe has no console, so it writes its report to a file; a timeout guards against hangs.
$report = Join-Path $PWD "dist\selfcheck.txt"
$check = Start-Process -FilePath "dist\Sightline\Sightline.exe" -ArgumentList "--selfcheck", "`"$report`"" -PassThru
$null = $check.Handle   # keeps the handle so ExitCode is available after the process exits
if (-not $check.WaitForExit(180000)) {
    Stop-Process -Id $check.Id -Force
    throw "Packaged self-check did not finish within 3 minutes"
}
if (Test-Path $report) { Get-Content $report | Write-Host }
if ($check.ExitCode -ne 0) { throw "Packaged self-check failed with exit code $($check.ExitCode)" }

Compress-Archive -Path "dist\Sightline" -DestinationPath "dist\Sightline-Windows.zip" -Force
Write-Host "Built dist\Sightline-Windows.zip"
