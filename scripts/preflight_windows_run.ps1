param(
  [switch]$SkipClean
)

$ErrorActionPreference = "Stop"

function Step([string]$message) {
  Write-Host ""
  Write-Host "==> $message" -ForegroundColor Cyan
}

function Install-NuGet {
  $nugetDir = Join-Path $PSScriptRoot "..\.tools\nuget"
  $nugetExe = Join-Path $nugetDir "nuget.exe"
  $nugetDir = [System.IO.Path]::GetFullPath($nugetDir)
  $nugetExe = [System.IO.Path]::GetFullPath($nugetExe)

  if (!(Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
  }

  if (!(Test-Path $nugetExe)) {
    Step "Downloading NuGet CLI"
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetExe
  }

  $env:PATH = "$nugetDir;$env:PATH"
  return $nugetExe
}

function Test-AtlMfc {
  $msvcRoot = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC"
  if (!(Test-Path $msvcRoot)) {
    return $false
  }

  $latest = Get-ChildItem $msvcRoot | Sort-Object Name -Descending | Select-Object -First 1
  if ($null -eq $latest) {
    return $false
  }

  $atlBase = Join-Path $latest.FullName "atlmfc\include\atlbase.h"
  $atlStr = Join-Path $latest.FullName "atlmfc\include\atlstr.h"
  return (Test-Path $atlBase) -and (Test-Path $atlStr)
}

function Stop-LockingProcesses {
  $names = @("ml_smart_expense_track", "flutter_tester")
  foreach ($name in $names) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
      Step "Stopping $name process(es)"
      $procs | Stop-Process -Force
    }
  }
}

Step "Windows Flutter preflight"

if (-not $IsWindows) {
  throw "This script is intended for Windows only."
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Set-Location $projectRoot

$nugetExe = Install-NuGet
Write-Host "NuGet: $nugetExe" -ForegroundColor Green

if (-not (Test-AtlMfc)) {
  Write-Host ""
  Write-Host "ATL/MFC headers are missing from VS Build Tools 2019." -ForegroundColor Red
  Write-Host "Install these components in Visual Studio Installer (Build Tools 2019):" -ForegroundColor Yellow
  Write-Host " - C++ ATL for latest v142 build tools (x86 & x64)" -ForegroundColor Yellow
  Write-Host " - C++ MFC for latest v142 build tools (x86 & x64)" -ForegroundColor Yellow
  throw "Cannot continue without ATL/MFC headers."
}

Step "Stopping stale app/build processes"
Stop-LockingProcesses

if (-not $SkipClean) {
  Step "Cleaning Flutter and stale Windows build cache"
  flutter clean
  $x64BuildDir = Join-Path $projectRoot "build\windows\x64"
  if (Test-Path $x64BuildDir) {
    Remove-Item $x64BuildDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Step "Resolving Dart dependencies"
flutter pub get

Step "Launching app on Windows"
flutter run -d windows
