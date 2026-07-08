$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$flutterDir = Join-Path $root "frontend_flutter"
$releaseDir = Join-Path $flutterDir "build\windows\x64\runner\Release"
$outputDir = Join-Path $root "WINDOWS_INSTALLER_FINAL"
$workDir = Join-Path $env:TEMP "AppyraAdminInstallerWork"
$payloadZip = Join-Path $workDir "appyra_admin_windows_release.zip"
$setupExe = Join-Path $outputDir "Setup_Appyra_Admin_1.0.0.exe"
$portableZip = Join-Path $outputDir "Appyra_Admin_Windows_Portable_1.0.0.zip"
$tempSetupExe = Join-Path $workDir "Setup_Appyra_Admin_1.0.0.exe"
$sedFile = Join-Path $workDir "appyra_admin_installer.sed"
$installPs1 = Join-Path $workDir "install.ps1"
$installCmd = Join-Path $workDir "install.cmd"

Write-Host "Building Appyra Admin for Windows..."
Push-Location $flutterDir
try {
  flutter pub get
  flutter build windows --release
}
finally {
  Pop-Location
}

if (-not (Test-Path (Join-Path $releaseDir "appyra_admin.exe"))) {
  throw "Windows release executable was not found: $releaseDir"
}

if (Test-Path $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workDir, $outputDir | Out-Null

if (Test-Path $payloadZip) {
  Remove-Item -LiteralPath $payloadZip -Force
}

Write-Host "Packaging release files..."
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $payloadZip -Force

@'
param(
  [Parameter(Mandatory = $true)]
  [string]$ZipPath
)

$ErrorActionPreference = "Stop"
$appName = "Appyra Admin"
$exeName = "appyra_admin.exe"
$installDir = Join-Path $env:ProgramFiles $appName
$startMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Appyra"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Appyra Admin.lnk"
$startShortcut = Join-Path $startMenuDir "Appyra Admin.lnk"

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "`"$ZipPath`""
  )
  $process = Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs -Wait -PassThru
  exit $process.ExitCode
}

Get-Process -Name "appyra_admin" -ErrorAction SilentlyContinue | Stop-Process -Force

$tempDir = Join-Path $env:TEMP ("AppyraAdminInstall_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempDir -Force

  if (Test-Path $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Copy-Item -Path (Join-Path $tempDir "*") -Destination $installDir -Recurse -Force

  $exePath = Join-Path $installDir $exeName
  if (-not (Test-Path $exePath)) {
    throw "Installed executable was not found: $exePath"
  }

  New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
  $shell = New-Object -ComObject WScript.Shell

  foreach ($shortcutPath in @($desktopShortcut, $startShortcut)) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = "$exePath,0"
    $shortcut.Save()
  }
}
finally {
  if (Test-Path $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
  }
}

Write-Host "Appyra Admin was installed successfully."
'@ | Set-Content -LiteralPath $installPs1 -Encoding UTF8

@'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" "%~dp0appyra_admin_windows_release.zip"
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath $installCmd -Encoding ASCII

$sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=Appyra Admin se instalo correctamente.
TargetName=$tempSetupExe
FriendlyName=Appyra Admin Installer
AppLaunched=install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0=install.cmd
FILE1=install.ps1
FILE2=appyra_admin_windows_release.zip
[SourceFiles]
SourceFiles0=$workDir
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@

$sedContent | Set-Content -LiteralPath $sedFile -Encoding ASCII

if (Test-Path $setupExe) {
  Remove-Item -LiteralPath $setupExe -Force
}

Write-Host "Creating installer..."
$iexpress = Start-Process `
  -FilePath (Join-Path $env:WINDIR "System32\iexpress.exe") `
  -ArgumentList @("/N", "/Q", (Split-Path -Leaf $sedFile)) `
  -WorkingDirectory $workDir `
  -Wait `
  -PassThru

if (-not (Test-Path $tempSetupExe)) {
  throw "Installer was not created: $tempSetupExe. IExpress exit code: $($iexpress.ExitCode)"
}

Copy-Item -LiteralPath $tempSetupExe -Destination $setupExe -Force
Copy-Item -LiteralPath $payloadZip -Destination $portableZip -Force

$installerInfo = Get-Item $setupExe
Write-Host "Installer ready:"
Write-Host $installerInfo.FullName
Write-Host ("Size: {0:N2} MB" -f ($installerInfo.Length / 1MB))
Write-Host "Portable ZIP ready:"
Write-Host $portableZip
