# Gỡ Develop Workspace khỏi Windows: đóng app, xoá exe, shortcut, mục Settings > Apps.
# Giữ nguyên các script trong thư mục, Ubuntu, PostgreSQL và cấu hình Tailscale.
$ErrorActionPreference = 'SilentlyContinue'
$here    = $PSScriptRoot
$AppName = 'Develop Workspace'

Get-Process -Name 'Develop Workspace', 'SH Dev Panel', 'PegasusPanel' -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*PegasusPanel.ps1*' -or $_.CommandLine -like '*WebPanel.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

Remove-Item (Join-Path $here 'Develop Workspace.exe'), (Join-Path $here 'SH Dev Panel.exe'), (Join-Path $here 'PegasusPanel.exe') -Force
foreach ($folder in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'))) {
    Remove-Item (Join-Path $folder "$AppName.lnk"), (Join-Path $folder 'SH Dev Panel.lnk'), (Join-Path $folder 'Develop Workspace Panel.lnk') -Force
}
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PegasusControlCenter' -Recurse -Force
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PegasusPanel' -Recurse -Force

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("Đã gỡ $AppName.`n`nCác script vẫn còn trong:`n$here", $AppName) | Out-Null
