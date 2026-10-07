# Cài DUOCNC DevOps thành app Windows (chỉ cho user hiện tại, không cần quyền Admin)
#   - Build "DUOCNC DevOps.exe" bằng csc.exe có sẵn trong Windows
#   - Shortcut Start Menu + Desktop, Startup (nếu đang bật chạy cùng Windows)
#   - Đăng ký trong Settings > Apps để gỡ được
# Chạy: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$AppName = 'DUOCNC DevOps'
$exe     = Join-Path $here "$AppName.exe"
$icon    = Join-Path $here 'icon.ico'
$src     = Join-Path $here 'app\DevOpsApp.cs'
$csc     = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$sma     = Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation" -Recurse -Filter System.Management.Automation.dll |
           Select-Object -First 1 -ExpandProperty FullName

# Đóng app đang chạy để ghi đè được file exe
Get-Process -Name $AppName -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*DevOpsPanel.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

Write-Host "== Build $exe"
& $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$icon" "/r:$sma" /r:System.Windows.Forms.dll $src
if ($LASTEXITCODE -ne 0) { throw "Build lỗi (csc exit $LASTEXITCODE)" }

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
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk")
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk")
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'DUOCNC DevOps Panel.lnk'
if (Test-Path $startup) { New-Shortcut $startup }   # đang bật chạy cùng Windows -> trỏ sang exe

Write-Host '== Đăng ký Settings > Apps'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DUOCNC.DevOps'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName     = $AppName
    DisplayVersion  = '1.0.2'
    Publisher       = 'DUOCNC'
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
