# Gỡ DevOps Panel (bản cài bằng DevOpsPanel-Setup.exe). Được gọi từ Settings > Apps > Uninstall.
# Gỡ im lặng: uninstall.ps1 -Quiet  (thêm -RemoveData để xoá cả cấu hình)
param([switch]$Quiet, [switch]$RemoveData)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
$here    = $PSScriptRoot
$exe     = Join-Path $here 'DevOpsPanel.exe'
$dataDir = Join-Path $env:APPDATA 'DevOpsPanel'

$answer = if ($Quiet) { if ($RemoveData) { 'No' } else { 'Yes' } } else { [System.Windows.Forms.MessageBox]::Show(
    "Gỡ DevOps Panel khỏi máy này?`n`n" +
    "Yes  - gỡ, GIỮ cấu hình và danh mục ứng dụng ($dataDir)`n" +
    "No   - gỡ và XOÁ luôn cấu hình`n" +
    "Cancel - không gỡ`n`n" +
    "Ứng dụng dev đang chạy (dotnet / npm) không bị tắt.",
    'Gỡ DevOps Panel', 'YesNoCancel', 'Question') }
if ([string]$answer -eq 'Cancel') { exit 1 }

Get-Process -Name 'DevOpsPanel' | Stop-Process -Force
Start-Sleep -Milliseconds 800

# Shortcut trỏ tới panel ở Start Menu / Desktop / Startup (kể cả đã đổi tên)
$sh = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'))) {
    Get-ChildItem $folder -Filter '*.lnk' -File | Where-Object { $sh.CreateShortcut($_.FullName).TargetPath -eq $exe } | Remove-Item -Force
}

Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DevOpsPanel' -Recurse -Force
if ([string]$answer -eq 'No') { Remove-Item $dataDir -Recurse -Force }

Set-Location $env:TEMP
Remove-Item $here -Recurse -Force

if (-not $Quiet) { [System.Windows.Forms.MessageBox]::Show('Đã gỡ DevOps Panel.', 'Gỡ DevOps Panel') | Out-Null }
