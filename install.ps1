# Cài Develop Workspace thành app Windows (chỉ cho user hiện tại, không cần quyền Admin)
#   - Build "Develop Workspace.exe" bằng csc.exe có sẵn trong Windows
#   - Shortcut Start Menu + Desktop, Startup (nếu đang bật chạy cùng Windows)
#   - Đăng ký trong Settings > Apps để gỡ được
# Chạy: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$AppName = 'Develop Workspace'
$exe     = Join-Path $here "$AppName.exe"
$icon    = Join-Path $here 'icon.ico'
$src     = Join-Path $here 'app\PegasusApp.cs'
$csc     = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$sma     = Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation" -Recurse -Filter System.Management.Automation.dll |
           Select-Object -First 1 -ExpandProperty FullName

# Đóng app đang chạy để ghi đè được file exe
Get-Process -Name 'Develop Workspace', 'Pegasus Control Center', 'SH Dev Panel', 'PegasusPanel' -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*PegasusPanel.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

Write-Host "== Build $exe"
& $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$icon" "/r:$sma" /r:System.Windows.Forms.dll $src
if ($LASTEXITCODE -ne 0) { throw "Build lỗi (csc exit $LASTEXITCODE)" }
Copy-Item $exe (Join-Path $here 'PegasusPanel.exe') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $here 'Pegasus Control Center.exe'), (Join-Path $here 'SH Dev Panel.exe') -Force -ErrorAction SilentlyContinue

function New-Shortcut([string]$path) {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($path)
    $l.TargetPath = $exe
    $l.WorkingDirectory = $here
    $l.IconLocation = "$exe,0"
    $l.Description = 'Bảng điều khiển Ubuntu, PostgreSQL, Docker, sức khỏe máy'
    $l.Save()
    Write-Host "   shortcut: $path"
}

Write-Host '== Shortcuts'
$programs = [Environment]::GetFolderPath('Programs')
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($folder in @($programs, $desktop)) {
    Remove-Item (Join-Path $folder 'Pegasus Control Center.lnk'), (Join-Path $folder 'SH Dev Panel.lnk'), (Join-Path $folder 'Develop Workspace Panel.lnk') -Force -ErrorAction SilentlyContinue
    New-Shortcut (Join-Path $folder "$AppName.lnk")
}
$startupDir = [Environment]::GetFolderPath('Startup')
$startup = Join-Path $startupDir "$AppName.lnk"
$oldStartup = @('Pegasus Control Center.lnk', 'SH Dev Panel.lnk', 'Develop Workspace Panel.lnk') | ForEach-Object { Join-Path $startupDir $_ }
if ((Test-Path $startup) -or @($oldStartup | Where-Object { Test-Path $_ }).Count) { New-Shortcut $startup }
Remove-Item $oldStartup -Force -ErrorAction SilentlyContinue   # giữ trạng thái chạy cùng Windows, đổi shortcut sang tên mới
Write-Host '== Đăng ký Settings > Apps'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PegasusControlCenter'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName     = $AppName
    DisplayVersion  = '1.0.7'
    Publisher       = 'Develop Workspace'
    DisplayIcon     = "$exe,0"
    InstallLocation = $here
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here 'uninstall.ps1')`""
}
foreach ($k in $props.Keys) { Set-ItemProperty -Path $key -Name $k -Value $props[$k] }
Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name EstimatedSize -Value ([int]((Get-ChildItem $here -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)) -Type DWord

Write-Host "== Xong. Mở app..."
Start-Process $exe
