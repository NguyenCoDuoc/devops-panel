# Đóng gói DevOps Panel thành một file cài: dist\DevOpsPanel-Setup.exe
# Bản phát cho người khác KHÔNG kèm Web Panel (WebPanel.ps1 / webpanel.html) và dữ liệu riêng của máy này
# (apps.json, settings.json, logs). Chỉ dùng công cụ có sẵn trong Windows (csc.exe của .NET Framework 4).
# Chạy: powershell -NoProfile -ExecutionPolicy Bypass -File build-setup.ps1
$ErrorActionPreference = 'Stop'
$here  = $PSScriptRoot
$out   = Join-Path $here 'dist'
$stage = Join-Path $out 'payload'
$zip   = Join-Path $out 'payload.zip'
$setup = Join-Path $out 'DevOpsPanel-Setup.exe'
$csc   = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$fx    = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
$sma   = Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation" -Recurse -Filter System.Management.Automation.dll |
         Select-Object -First 1 -ExpandProperty FullName

Remove-Item $stage, $zip, $setup -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage, (Join-Path $stage 'wsl') | Out-Null

Write-Host '== 1/3 Launcher DevOpsPanel.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$stage\DevOpsPanel.exe" "/win32icon:$here\icon.ico" "/r:$sma" /r:System.Windows.Forms.dll "$here\app\DevOpsApp.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build launcher lỗi' }

Write-Host '== 2/3 Payload'
Copy-Item "$here\DevOpsPanel.ps1", "$here\DevOpsCore.ps1", "$here\icon.ico" $stage
Copy-Item "$here\installer\uninstall.ps1" $stage
Copy-Item "$here\wsl\install-k9s.sh" (Join-Path $stage 'wsl')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)

Write-Host '== 3/3 DevOpsPanel-Setup.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$setup" "/win32icon:$here\icon.ico" "/resource:$zip,payload.zip" `
    "/r:$fx\System.IO.Compression.dll" "/r:$fx\System.IO.Compression.FileSystem.dll" `
    /r:System.Windows.Forms.dll /r:Microsoft.CSharp.dll /r:System.Core.dll "$here\installer\Setup.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build setup lỗi' }

Remove-Item $stage, $zip -Recurse -Force
$size = [math]::Round((Get-Item $setup).Length / 1KB)
Write-Host "Xong: $setup ($size KB)"
