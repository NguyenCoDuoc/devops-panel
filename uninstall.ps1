# Gỡ DUOCNC DevOps khỏi Windows: đóng app, xoá exe, shortcut, mục Settings > Apps.
# Giữ nguyên các script trong thư mục, Ubuntu, PostgreSQL và cấu hình Tailscale.
$ErrorActionPreference = 'SilentlyContinue'
$here    = $PSScriptRoot
$AppName = 'DUOCNC DevOps'

Get-Process -Name $AppName | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*DevOpsPanel.ps1*' -or $_.CommandLine -like '*WebPanel.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

Remove-Item (Join-Path $here "$AppName.exe") -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk") -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk") -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'DUOCNC DevOps Panel.lnk') -Force
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DUOCNC.DevOps' -Recurse -Force

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("Đã gỡ $AppName.`n`nCác script vẫn còn trong:`n$here", $AppName) | Out-Null
