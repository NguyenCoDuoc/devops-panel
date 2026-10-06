# DevOps Panel - bảng điều khiển WSL, PostgreSQL, K3s, Docker, ứng dụng dev, sức khỏe máy
# Chạy: DevOpsPanel.exe (bản cài) hoặc powershell -NoProfile -ExecutionPolicy Bypass -File DevOpsPanel.ps1
$ErrorActionPreference = 'SilentlyContinue'
$env:WSL_UTF8 = '1'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Chỉ cho chạy 1 cửa sổ panel
$mutex = New-Object System.Threading.Mutex($false, 'Local\DevOpsPanel')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('DevOps Panel đang chạy (xem icon ở khay hệ thống).', 'DevOps Panel') | Out-Null
    exit
}

. (Join-Path $PSScriptRoot 'DevOpsCore.ps1')
$IconFile    = Join-Path $PSScriptRoot 'icon.ico'
$AppIcon     = if (Test-Path $IconFile) { New-Object System.Drawing.Icon($IconFile) } else { [System.Drawing.SystemIcons]::Application }
$LauncherExe = Find-FirstPath @((Join-Path $PSScriptRoot 'DevOpsPanel.exe'), (Join-Path $PSScriptRoot 'DUOCNC DevOps.exe'))
$HasWebPanel = Test-Path (Join-Path $PSScriptRoot 'WebPanel.ps1')     # bản cài phát cho người khác không kèm Web Panel

# ---------- Settings (config.json trong %APPDATA%\DevOpsPanel) ----------
function Get-Settings { $PanelConfig }
function Save-Settings($s) { Save-PanelConfig $s }

# ---------- Shortcut: tìm theo đích (exe của panel) nên đổi tên app vẫn nhận ra ----------
$ShortcutFolders = @{
    Programs = [Environment]::GetFolderPath('Programs')
    Desktop  = [Environment]::GetFolderPath('Desktop')
    Startup  = [Environment]::GetFolderPath('Startup')
}
function Get-OwnShortcuts([string]$folder) {
    $sh = New-Object -ComObject WScript.Shell
    Get-ChildItem $folder -Filter '*.lnk' -File | Where-Object {
        $t = $sh.CreateShortcut($_.FullName)
        ($LauncherExe -and $t.TargetPath -eq $LauncherExe) -or ($t.Arguments -like "*$PSCommandPath*")
    }
}
function New-OwnShortcut([string]$path) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    if ($LauncherExe) {
        $lnk.TargetPath = $LauncherExe
    } else {
        $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    }
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.Description = $AppName
    if (Test-Path $IconFile) { $lnk.IconLocation = "$IconFile,0" }
    $lnk.Save()
}
function Test-RunAtLogon { [bool](Get-OwnShortcuts $ShortcutFolders.Startup) }
function Set-RunAtLogon([bool]$on) {
    if ($on) { if (-not (Test-RunAtLogon)) { New-OwnShortcut (Join-Path $ShortcutFolders.Startup "$AppName.lnk") } }
    else { Get-OwnShortcuts $ShortcutFolders.Startup | Remove-Item -Force }
}
# Đổi tên app: đổi luôn tên các shortcut Start Menu / Desktop / Startup đang trỏ tới panel
function Rename-OwnShortcuts([string]$newName) {
    $safe = ($newName -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $safe) { return }
    foreach ($folder in $ShortcutFolders.Values) {
        foreach ($s in @(Get-OwnShortcuts $folder)) {
            $target = Join-Path $folder "$safe.lnk"
            if ($s.FullName -ne $target) { Remove-Item $s.FullName -Force; New-OwnShortcut $target }
        }
    }
}

# ---------- Desktop-only ----------
function Open-UbuntuTerminal([string]$extra = '') {
    $wtArgs = "wsl.exe -d $Distro $extra".Trim()
    if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList $wtArgs }
    else { Start-Process wsl.exe -ArgumentList "-d $Distro $extra".Trim() }
}

# ---------- UI ----------
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(560, 650)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = $font
$form.Icon = $AppIcon

function New-Button($text, $x, $y, $w, $parent, $onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 32)
    $b.Add_Click($onClick)
    $parent.Controls.Add($b)
    $b
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(8, 8)
$tabs.Size = New-Object System.Drawing.Size(530, 535)
$pageMain   = New-Object System.Windows.Forms.TabPage('Dịch vụ')
$pageHealth = New-Object System.Windows.Forms.TabPage('Sức khỏe')
$pageK3s    = New-Object System.Windows.Forms.TabPage('K3s')
$pageApps   = New-Object System.Windows.Forms.TabPage('Ứng dụng')
$pageSettings = New-Object System.Windows.Forms.TabPage('Cài đặt')
$tabs.TabPages.AddRange(@($pageMain, $pageApps, $pageHealth, $pageK3s, $pageSettings))
$form.Controls.Add($tabs)

function New-Group($text, $y, $h, $parent = $pageMain) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text
    $g.Location = New-Object System.Drawing.Point(6, $y)
    $g.Size = New-Object System.Drawing.Size(510, $h)
    $parent.Controls.Add($g)
    $g
}

# Trạng thái
$gStatus = New-Group 'Trạng thái (chọn một dòng rồi bấm Start / Stop / Restart)' 10 262
$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'
$list.FullRowSelect = $true
$list.MultiSelect = $false
$list.HideSelection = $false
$list.Location = New-Object System.Drawing.Point(12, 26)
$list.Size = New-Object System.Drawing.Size(486, 186)
[void]$list.Columns.Add('Thành phần', 240)
[void]$list.Columns.Add('Port', 70)
[void]$list.Columns.Add('Trạng thái', 160)
foreach ($c in $Components) {
    $item = New-Object System.Windows.Forms.ListViewItem($c.Name)
    $item.UseItemStyleForSubItems = $false
    [void]$item.SubItems.Add([string]$c.Port)
    [void]$item.SubItems.Add('...')
    $item.Tag = $c
    [void]$list.Items.Add($item)
}
$gStatus.Controls.Add($list)

function Get-Selected {
    if ($list.SelectedItems.Count -eq 0) { Set-Status 'Hãy chọn một dòng trong bảng trạng thái.'; return $null }
    $list.SelectedItems[0].Tag
}
function Invoke-Busy([string]$msg, [scriptblock]$action) {
    $form.Cursor = 'WaitCursor'; Set-Status $msg; [System.Windows.Forms.Application]::DoEvents()
    & $action
    $form.Cursor = 'Default'; Update-Status
}

$svcStart   = { $c = Get-Selected; if ($c) { Invoke-Busy "Đang khởi động $($c.Name)..." { Start-Component $c }; Set-Status "Đã gửi lệnh khởi động $($c.Name)." } }
$svcStop    = { $c = Get-Selected; if ($c) { Invoke-Busy "Đang dừng $($c.Name)..." { Stop-Component $c }; Set-Status "Đã gửi lệnh dừng $($c.Name)." } }
$svcRestart = { $c = Get-Selected; if ($c) { Invoke-Busy "Đang khởi động lại $($c.Name)..." { Stop-Component $c; Start-Sleep 2; Start-Component $c }; Set-Status "Đã khởi động lại $($c.Name)." } }
$svcRefresh = { Update-Status; Set-Status 'Đã làm mới.' }
New-Button 'Start' 12 218 120 $gStatus $svcStart | Out-Null
New-Button 'Stop' 140 218 120 $gStatus $svcStop | Out-Null
New-Button 'Restart' 268 218 120 $gStatus $svcRestart | Out-Null
New-Button 'Làm mới' 396 218 112 $gStatus $svcRefresh | Out-Null
$svcMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miSvcStart = $svcMenu.Items.Add('Start', $null, $svcStart)
$miSvcStop  = $svcMenu.Items.Add('Stop', $null, $svcStop)
[void]$svcMenu.Items.Add('Restart', $null, $svcRestart)
[void]$svcMenu.Items.Add('-')
[void]$svcMenu.Items.Add('Làm mới', $null, $svcRefresh)
$svcMenu.Add_Opening({
    param($s, $e)
    if (-not $list.SelectedItems.Count) { $e.Cancel = $true; return }
    $running = $list.SelectedItems[0].SubItems[2].Text -like '●*'
    $miSvcStart.Enabled = -not $running; $miSvcStop.Enabled = $running
})
$list.ContextMenuStrip = $svcMenu

# Ubuntu
$gUbuntu = New-Group $(if ($Distro) { "WSL: $Distro" } else { 'WSL (máy này chưa cài distro Ubuntu)' }) 278 70
New-Button 'Khởi động' 12 26 160 $gUbuntu { Invoke-Busy "Đang khởi động $Distro..." { Start-Ubuntu }; Set-Status "$Distro đang chạy." } | Out-Null
New-Button 'Tắt' 180 26 120 $gUbuntu { Invoke-Busy "Đang tắt $Distro..." { Stop-Ubuntu }; Set-Status "Đã tắt $Distro." } | Out-Null
New-Button 'Mở terminal' 308 26 200 $gUbuntu { Open-UbuntuTerminal } | Out-Null
if (-not $Distro) { $gUbuntu.Enabled = $false }

# PostgreSQL trong WSL (bật bằng port ở tab Cài đặt)
$gPg = New-Group $(if ($Distro -and $PgUbuntuPort -gt 0) { "PostgreSQL trong $Distro (localhost:$PgUbuntuPort, user admin)" } else { 'PostgreSQL trong WSL (chưa cấu hình - xem tab Cài đặt)' }) 352 70
if (-not ($Distro -and $PgUbuntuPort -gt 0)) { $gPg.Enabled = $false }
New-Button 'Hiện mật khẩu' 12 26 160 $gPg {
    $pw = Get-PgPassword
    if ($pw) {
        [System.Windows.Forms.Clipboard]::SetText($pw)
        [System.Windows.Forms.MessageBox]::Show("Mật khẩu user admin:`n`n$pw`n`n(Đã copy vào clipboard)", 'PostgreSQL Ubuntu') | Out-Null
    } else { Set-Status 'Không đọc được /root/.pgpass trong Ubuntu.' }
} | Out-Null
New-Button 'Copy chuỗi kết nối' 180 26 170 $gPg {
    $pw = Get-PgPassword
    if ($pw) {
        [System.Windows.Forms.Clipboard]::SetText("Host=localhost;Port=$PgUbuntuPort;Database=admin;Username=admin;Password=$pw")
        Set-Status 'Đã copy chuỗi kết nối vào clipboard.'
    } else { Set-Status 'Không đọc được /root/.pgpass trong Ubuntu.' }
} | Out-Null
New-Button 'Mở psql' 358 26 150 $gPg { Start-Ubuntu; Open-UbuntuTerminal "-u root psql -h localhost -p $PgUbuntuPort -U admin -d admin" } | Out-Null

# Khác
$gOther = New-Group 'Khác' 426 70
New-Button 'Mở Docker Desktop' 12 26 180 $gOther { if ($DockerExe) { Start-Process $DockerExe; Set-Status 'Đang mở Docker Desktop...' } else { Set-Status 'Chưa cài Docker Desktop.' } } | Out-Null
New-Button 'Thư mục dữ liệu' 200 26 170 $gOther { Start-Process explorer.exe $DataDir } | Out-Null
if ($HasWebPanel) {
    New-Button 'Web Panel' 378 26 130 $gOther {
        $t = Get-TailscaleInfo
        # Port 8443 vì 443 đã bị IIS chiếm. Từ chính máy này không mở được (chỉ thiết bị khác trong tailnet) -> mở bản local
        Start-Process "http://localhost:8787/"
        if ($t -and $t.DNSName) { [System.Windows.Forms.Clipboard]::SetText("https://$($t.DNSName):8443/"); Set-Status "Đã copy link cho điện thoại: https://$($t.DNSName):8443/" }
    } | Out-Null
} else {
    New-Button 'Cài đặt' 378 26 130 $gOther { $tabs.SelectedTab = $pageSettings } | Out-Null
}

# Tuỳ chọn
$settings = Get-Settings
$chkLogon = New-Object System.Windows.Forms.CheckBox
$chkLogon.Text = 'Mở panel khi Windows khởi động'
$chkLogon.Location = New-Object System.Drawing.Point(16, 552)
$chkLogon.AutoSize = $true
$chkLogon.Checked = (Test-RunAtLogon)
$chkLogon.Add_CheckedChanged({ Set-RunAtLogon $chkLogon.Checked; Set-Status ('Chạy cùng Windows: ' + $(if ($chkLogon.Checked) { 'BẬT' } else { 'TẮT' })) })
$form.Controls.Add($chkLogon)

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Tự khởi động WSL khi mở panel'
$chkAuto.Location = New-Object System.Drawing.Point(280, 552)
$chkAuto.AutoSize = $true
$chkAuto.Checked = $settings.autoStartUbuntu
$chkAuto.Add_CheckedChanged({ $settings.autoStartUbuntu = $chkAuto.Checked; Save-Settings $settings })
$form.Controls.Add($chkAuto)

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Location = New-Object System.Drawing.Point(16, 582)
$statusLbl.Size = New-Object System.Drawing.Size(516, 22)
$statusLbl.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($statusLbl)
function Set-Status([string]$t) { $statusLbl.Text = $t }

function Update-Status {
    foreach ($item in $list.Items) {
        $ok = Get-ComponentState $item.Tag
        $sub = $item.SubItems[2]
        if ($ok) { $sub.Text = '● Đang chạy'; $sub.ForeColor = [System.Drawing.Color]::ForestGreen }
        else     { $sub.Text = '○ Đã dừng';  $sub.ForeColor = [System.Drawing.Color]::Firebrick }
    }
}

# ---------- Tab Sức khỏe ----------
function New-Label($text, $x, $y, $w, $parent, [switch]$Bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 22)
    if ($Bold) { $l.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold) }
    $parent.Controls.Add($l)
    $l
}

$meters = @{}
$y = 12
foreach ($m in @(@('cpu', 'CPU'), @('ram', 'RAM'), @('wsl', 'WSL (Ubuntu+Docker)'), @('bat', 'Pin'))) {
    New-Label $m[1] 12 $y 150 $pageHealth -Bold | Out-Null
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(165, ($y + 2))
    $bar.Size = New-Object System.Drawing.Size(200, 18)
    $bar.Maximum = 100
    $pageHealth.Controls.Add($bar)
    $val = New-Label '...' 375 $y 140 $pageHealth
    $meters[$m[0]] = @{ Bar = $bar; Label = $val }
    $y += 28
}
$lblInfo = New-Label '' 12 $y 500 $pageHealth
$lblInfo.ForeColor = [System.Drawing.Color]::DimGray

# Biểu đồ CPU (xanh) / RAM (cam) 60 mẫu gần nhất
$chart = New-Object System.Windows.Forms.Panel
$chart.Location = New-Object System.Drawing.Point(12, ($y + 26))
$chart.Size = New-Object System.Drawing.Size(498, 110)
$chart.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$chart.BorderStyle = 'FixedSingle'
$chart.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($chart, $true, $null)
$pageHealth.Controls.Add($chart)
$histCpu = New-Object System.Collections.Generic.List[int]
$histRam = New-Object System.Collections.Generic.List[int]
$HistMax = 60

$chart.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $w = $chart.ClientSize.Width; $h = $chart.ClientSize.Height
    $grid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240))
    foreach ($p in 25, 50, 75) { $yy = $h - $h * $p / 100; $g.DrawLine($grid, 0, $yy, $w, $yy) }
    $f = New-Object System.Drawing.Font('Segoe UI', 8)
    $g.DrawString('CPU', $f, [System.Drawing.Brushes]::RoyalBlue, 4, 2)
    $g.DrawString('RAM', $f, [System.Drawing.Brushes]::DarkOrange, 36, 2)
    $g.DrawString('3 phút gần nhất', $f, [System.Drawing.Brushes]::Gray, ($w - 90), 2)
    foreach ($series in @(@($histCpu, [System.Drawing.Color]::RoyalBlue), @($histRam, [System.Drawing.Color]::DarkOrange))) {
        $data = $series[0]
        if ($data.Count -lt 2) { continue }
        $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
        $step = $w / ($HistMax - 1)
        $offset = $HistMax - $data.Count
        for ($i = 0; $i -lt $data.Count; $i++) {
            $pts.Add([System.Drawing.PointF]::new(($offset + $i) * $step, $h - 2 - ($h - 4) * $data[$i] / 100))
        }
        $pen = New-Object System.Drawing.Pen($series[1], 2)
        $g.DrawLines($pen, $pts.ToArray())
    }
})

$lblWarn = New-Label '' 12 ($y + 142) 500 $pageHealth -Bold
$lblWarn.ForeColor = [System.Drawing.Color]::Firebrick

function New-TopList($title, $x, $y) {
    New-Label $title $x $y 245 $pageHealth -Bold | Out-Null
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HeaderStyle = 'Nonclickable'
    $lv.Location = New-Object System.Drawing.Point($x, ($y + 24))
    $lv.Size = New-Object System.Drawing.Size(245, 128)
    [void]$lv.Columns.Add('Tiến trình', 125)
    [void]$lv.Columns.Add('CPU', 50)
    [void]$lv.Columns.Add('RAM', 66)
    $pageHealth.Controls.Add($lv)
    $lv
}
$topY = $y + 168
$lvCpu = New-TopList 'Ăn CPU nhiều nhất' 12 $topY
$lvRam = New-TopList 'Ăn RAM nhiều nhất' 265 $topY

function Format-MB([double]$mb) { if ($mb -ge 1024) { '{0:0.0} GB' -f ($mb / 1024) } else { '{0:0} MB' -f $mb } }

function Set-Meter($key, [int]$pct, [string]$text) {
    $meters[$key].Bar.Value = [math]::Min(100, [math]::Max(0, $pct))
    $meters[$key].Label.Text = $text
}

function Fill-TopList($lv, $rows) {
    $lv.BeginUpdate(); $lv.Items.Clear()
    foreach ($r in $rows) {
        $name = if ($r.Count -gt 1) { "$($r.Name) ($($r.Count))" } else { $r.Name }
        $it = New-Object System.Windows.Forms.ListViewItem($name)
        [void]$it.SubItems.Add(('{0:0.#}%' -f $r.Cpu))
        [void]$it.SubItems.Add((Format-MB $r.RamMB))
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
}

# Thu thập dữ liệu ở runspace nền để giao diện không bị đơ (mỗi lần đo ~1.5s)
# Fast = đang mở tab Sức khỏe -> đo mỗi 3s; ngược lại 60s/lần (chỉ để cảnh báo ở khay)
$healthSync = [hashtable]::Synchronized(@{ Data = $null; Seq = 0; Run = $true; Fast = $false })
$healthRs = [runspacefactory]::CreateRunspace()
$healthRs.Open()
$healthRs.SessionStateProxy.SetVariable('sync', $healthSync)
$healthRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1'))
$healthPs = [powershell]::Create()
$healthPs.Runspace = $healthRs
[void]$healthPs.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'
    . $corePath
    while ($sync.Run) {
        try { $sync.Data = Get-HealthInfo; $sync.Seq++ } catch { }
        $wasFast = $sync.Fast
        $ticks = if ($wasFast) { 10 } else { 200 }     # 10 x 300ms = 3s, 200 x 300ms = 60s
        # Thoát chờ sớm khi người dùng vừa mở tab Sức khỏe
        for ($i = 0; $i -lt $ticks -and $sync.Run -and ($sync.Fast -eq $wasFast -or $wasFast); $i++) { Start-Sleep -Milliseconds 300 }
    }
})
[void]$healthPs.BeginInvoke()

$script:lastSeq = 0
$script:shownWarn = @{}
function Update-Health {
    if ($healthSync.Seq -eq $script:lastSeq) { return }
    $script:lastSeq = $healthSync.Seq
    $h = $healthSync.Data
    if (-not $h) { return }

    if ($healthSync.Fast) {
        $histCpu.Add($h.Cpu); $histRam.Add($h.RamPct)
        while ($histCpu.Count -gt $HistMax) { $histCpu.RemoveAt(0); $histRam.RemoveAt(0) }
    }

    Set-Meter 'cpu' $h.Cpu ("$($h.Cpu)%  ($($h.Cores) luồng)")
    Set-Meter 'ram' $h.RamPct ("$($h.RamPct)%  ($($h.RamUsedGB)/$($h.RamTotalGB) GB)")
    $wslPct = if ($h.RamTotalGB) { [int]($h.WslMB / 1024 * 100 / $h.RamTotalGB) } else { 0 }
    Set-Meter 'wsl' $wslPct (Format-MB $h.WslMB)
    if ($h.Battery) {
        Set-Meter 'bat' $h.Battery.Percent ("$($h.Battery.Percent)%  " + $(if ($h.Battery.Charging) { '⚡ đang sạc' } else { 'dùng pin' }))
    } else { Set-Meter 'bat' 0 'Không có pin' }

    $up = $h.Uptime -replace '^(\d+)\.', '$1 ngày '
    $lblInfo.Text = "Mạng ↓ $($h.NetDownKB) KB/s  ↑ $($h.NetUpKB) KB/s     Máy đã bật: $up"
    $lblWarn.Text = if ($h.Warnings.Count) { '⚠ ' + ($h.Warnings -join '   ⚠ ') } else { '✓ Mọi chỉ số bình thường' }
    $lblWarn.ForeColor = if ($h.Warnings.Count) { [System.Drawing.Color]::Firebrick } else { [System.Drawing.Color]::ForestGreen }
    if ($tabs.SelectedTab -eq $pageHealth -and $form.Visible) {
        Fill-TopList $lvCpu $h.TopCpu
        Fill-TopList $lvRam $h.TopRam
        $chart.Invalidate()
    }

    # Cảnh báo mới -> balloon ở khay hệ thống (mỗi cảnh báo báo 1 lần cho tới khi hết)
    $tray.Text = ("DevOps - CPU $($h.Cpu)% RAM $($h.RamPct)%")
    foreach ($w in $h.Warnings) {
        $key = ($w -replace '[\d\.,]+', '#')
        if (-not $script:shownWarn.ContainsKey($key)) {
            $script:shownWarn[$key] = $true
            $tray.ShowBalloonTip(5000, 'DevOps - Cảnh báo', $w, 'Warning')
        }
    }
    foreach ($k in @($script:shownWarn.Keys)) {
        if (-not ($h.Warnings | Where-Object { ($_ -replace '[\d\.,]+', '#') -eq $k })) { $script:shownWarn.Remove($k) }
    }
}
# ---------- Tab K3s ----------
$lblK3s = New-Label 'Đang tải...' 12 12 500 $pageK3s -Bold
$lvPods = New-Object System.Windows.Forms.ListView
$lvPods.View = 'Details'; $lvPods.FullRowSelect = $true; $lvPods.MultiSelect = $false; $lvPods.HideSelection = $false
$lvPods.Location = New-Object System.Drawing.Point(12, 40)
$lvPods.Size = New-Object System.Drawing.Size(498, 380)
foreach ($col in @(@('Namespace', 95), @('Pod', 170), @('Trạng thái', 105), @('Ready', 45), @('Restart', 50), @('Tuổi', 40))) {
    [void]$lvPods.Columns.Add($col[0], $col[1])
}
$pageK3s.Controls.Add($lvPods)

function Get-SelectedPod {
    if ($lvPods.SelectedItems.Count -eq 0) { Set-Status 'Hãy chọn một pod trong danh sách.'; return $null }
    $lvPods.SelectedItems[0].Tag
}
function Open-K3sTerminal([string]$cmd) {
    Start-Ubuntu
    Open-UbuntuTerminal "-u root -e env KUBECONFIG=/etc/rancher/k3s/k3s.yaml $cmd"
}

$podRefresh = { $k3sSync.Seq0 = $k3sSync.Seq; $k3sSync.Kick = $true; Set-Status 'Đang tải lại danh sách pod...' }
$podLog = {
    $p = Get-SelectedPod
    if ($p -and (Test-K8sName $p.Namespace) -and (Test-K8sName $p.Name)) {
        Open-K3sTerminal "k3s kubectl logs -f -n $($p.Namespace) $($p.Name) --all-containers --tail=200"
    }
}
$podRestart = {
    $p = Get-SelectedPod
    if (-not $p) { return }
    if (-not $p.Owner -or $p.Owner -eq 'Job') { Set-Status 'Pod này không có controller (hoặc là Job đã chạy xong) - không restart.'; return }
    $ok = [System.Windows.Forms.MessageBox]::Show("Khởi động lại pod $($p.Namespace)/$($p.Name)?`n`nPod sẽ bị xoá và Kubernetes tạo pod mới.", 'K3s', 'YesNo', 'Question')
    if ($ok -eq 'Yes') {
        $r = Restart-K3sPod $p.Namespace $p.Name
        Set-Status ($r.Trim())
        $k3sSync.Kick = $true
    }
}
New-Button 'Làm mới' 12 428 110 $pageK3s $podRefresh | Out-Null
New-Button 'Xem log' 128 428 110 $pageK3s $podLog | Out-Null
New-Button 'Restart pod' 244 428 120 $pageK3s $podRestart | Out-Null
New-Button 'Mở k9s' 370 428 140 $pageK3s { Open-K3sTerminal 'k9s' } | Out-Null
$podMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miPodLog = $podMenu.Items.Add('Xem log', $null, $podLog)
$miPodLog.Font = New-Object System.Drawing.Font($podMenu.Font, [System.Drawing.FontStyle]::Bold)
$miPodRestart = $podMenu.Items.Add('Restart pod', $null, $podRestart)
$miPodDescribe = $podMenu.Items.Add('Describe', $null, {
    $p = Get-SelectedPod
    if ($p -and (Test-K8sName $p.Namespace) -and (Test-K8sName $p.Name)) { Open-K3sTerminal "sh -c `"k3s kubectl describe pod -n $($p.Namespace) $($p.Name) | less`"" }
})
$miPodCopy = $podMenu.Items.Add('Copy tên pod', $null, { $p = Get-SelectedPod; if ($p) { [System.Windows.Forms.Clipboard]::SetText($p.Name); Set-Status "Đã copy $($p.Name)" } })
[void]$podMenu.Items.Add('-')
[void]$podMenu.Items.Add('Làm mới', $null, $podRefresh)
[void]$podMenu.Items.Add('Mở k9s', $null, { Open-K3sTerminal 'k9s' })
$podMenu.Add_Opening({
    $has = [bool]$lvPods.SelectedItems.Count
    foreach ($m in @($miPodLog, $miPodRestart, $miPodDescribe, $miPodCopy)) { $m.Enabled = $has }
})
$lvPods.ContextMenuStrip = $podMenu
$lvPods.Add_DoubleClick({ & $podLog })

$k3sSync = [hashtable]::Synchronized(@{ Data = $null; Seq = 0; Seq0 = 0; Run = $true; Active = $false; Kick = $false })
$k3sRs = [runspacefactory]::CreateRunspace()
$k3sRs.Open()
$k3sRs.SessionStateProxy.SetVariable('sync', $k3sSync)
$k3sRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1'))
$k3sPs = [powershell]::Create()
$k3sPs.Runspace = $k3sRs
[void]$k3sPs.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'
    . $corePath
    while ($sync.Run) {
        if ($sync.Active -or $sync.Kick) {
            $sync.Kick = $false
            try { $sync.Data = Get-K3sInfo; $sync.Seq++ } catch { }
            # 10s/lần khi đang mở tab; bấm Làm mới/Restart thì chạy ngay
            for ($i = 0; $i -lt 33 -and $sync.Run -and $sync.Active -and -not $sync.Kick; $i++) { Start-Sleep -Milliseconds 300 }
        } else { Start-Sleep -Milliseconds 300 }
    }
})
[void]$k3sPs.BeginInvoke()

$script:k3sSeq = 0
function Update-K3s {
    if ($k3sSync.Seq -eq $script:k3sSeq) { return }
    $script:k3sSeq = $k3sSync.Seq
    $k = $k3sSync.Data
    if (-not $k) { return }
    if (-not $k.Running) {
        $lblK3s.Text = "K3s không chạy: $($k.Reason) (bật ở tab Dịch vụ)"
        $lblK3s.ForeColor = [System.Drawing.Color]::Firebrick
        $lvPods.Items.Clear(); return
    }
    $node = $k.Nodes | Select-Object -First 1
    $lblK3s.Text = "Node $($node.Name): $($node.Status) · $($node.Version) · Pod OK $($k.Healthy)/$($k.Total)" + $(if ($k.Unhealthy) { " · $($k.Unhealthy) pod lỗi" } else { '' })
    $lblK3s.ForeColor = if ($k.Unhealthy) { [System.Drawing.Color]::Firebrick } else { [System.Drawing.Color]::ForestGreen }

    $sel = if ($lvPods.SelectedItems.Count) { $lvPods.SelectedItems[0].Tag.Name } else { $null }
    $lvPods.BeginUpdate(); $lvPods.Items.Clear()
    foreach ($p in $k.Pods) {
        $it = New-Object System.Windows.Forms.ListViewItem($p.Namespace)
        $it.UseItemStyleForSubItems = $false
        foreach ($v in @($p.Name, $p.Status, $p.Ready, [string]$p.Restarts, $p.Age)) { [void]$it.SubItems.Add($v) }
        $it.SubItems[2].ForeColor = if ($p.Healthy) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Firebrick }
        $it.Tag = $p
        [void]$lvPods.Items.Add($it)
        if ($p.Name -eq $sel) { $it.Selected = $true }
    }
    $lvPods.EndUpdate()
    Set-Status ("K3s cập nhật lúc " + (Get-Date).ToString('HH:mm:ss'))
}

# ---------- Tab Ứng dụng (backend/frontend dev) ----------
$lblApps = New-Label 'Đang quét các port...' 12 12 500 $pageApps -Bold
$lvApps = New-Object System.Windows.Forms.ListView
$lvApps.View = 'Details'; $lvApps.FullRowSelect = $true; $lvApps.MultiSelect = $true; $lvApps.HideSelection = $false; $lvApps.ShowItemToolTips = $true
$lvApps.Location = New-Object System.Drawing.Point(12, 40)
$lvApps.Size = New-Object System.Drawing.Size(498, 258)
$AppsCols = @(@('Nhóm', 70), @('Ứng dụng', 150), @('Loại', 70), @('Port', 50), @('Trạng thái', 190), @('PID', 60))
foreach ($col in $AppsCols) { [void]$lvApps.Columns.Add($col[0], $col[1]) }
$pageApps.Controls.Add($lvApps)

# Chọn nhiều dòng (Ctrl/Shift + click, Ctrl+A) -> Start / Stop / Restart cả loạt
function Get-SelectedApps([switch]$Quiet) {
    $sel = @($lvApps.SelectedItems | ForEach-Object { $_.Tag })
    if (-not $sel.Count -and -not $Quiet) { Set-Status 'Hãy chọn ứng dụng trong danh sách (Ctrl/Shift + click để chọn nhiều).' }
    $sel
}

# Chạy lệnh ở runspace nền: Start nhiều app (mỗi app phải quét port) hoặc Stop (có chờ dọn tiến trình) mất vài giây
$script:appsBatchBusy = $false
function Invoke-AppsBatch([string]$act, $apps) {
    $apps = @($apps)
    if (-not $apps.Count) { Set-Status 'Hãy chọn ứng dụng trong danh sách (Ctrl/Shift + click để chọn nhiều).'; return }
    if ($script:appsBatchBusy) { Set-Status 'Lệnh trước vẫn đang chạy, chờ chút rồi thử lại.'; return }
    if ($act -ne 'stop') {
        $unknown = @($apps | Where-Object { -not $_.Known })
        $apps = @($apps | Where-Object Known)
        if (-not $apps.Count) { Set-Status 'App ngoài apps.json - không biết lệnh chạy.'; return }
        if ($act -eq 'start') { $apps = @($apps | Where-Object { -not $_.Running -and -not $script:appsPending[$_.Id] }) }
        if (-not $apps.Count) { Set-Status 'Các app đã chọn đều đang chạy hoặc đang khởi động.'; return }
    }
    if ($act -eq 'stop') {
        $apps = @($apps | Where-Object { $_.Running -or $_.Known })
        if (-not $apps.Count) { Set-Status 'Không có app nào đang chạy để dừng.'; return }
    }
    $names = ($apps | Select-Object -First 12 | ForEach-Object { "  • $($_.Name)" }) -join "`n"
    if ($apps.Count -gt 12) { $names += "`n  … và $($apps.Count - 12) app khác" }
    $verb = @{ start = 'Khởi động'; stop = 'Dừng'; restart = 'Khởi động lại' }[$act]
    if ($act -ne 'start' -and [System.Windows.Forms.MessageBox]::Show("$verb $($apps.Count) ứng dụng?`n`n$names", 'Ứng dụng', 'YesNo', 'Question') -ne 'Yes') { return }

    $script:appsBatchBusy = $true
    $form.Cursor = 'AppStarting'
    Set-Status "$verb $($apps.Count) ứng dụng..."
    foreach ($a in $apps) {
        $script:appsPending[$a.Id] = @{ Act = $act; Since = Get-Date; DoneAt = $null; Tool = -not $a.Port }
        $script:appsFailed.Remove($a.Id)
    }
    Update-AppsPending
    $code = {
        $ErrorActionPreference = 'SilentlyContinue'     # taskkill 2>&1 khi EAP=Stop bị coi là lỗi; lỗi thật vẫn throw
        $msgs = New-Object System.Collections.ArrayList
        if ($p.Act -ne 'start') {
            foreach ($id in $p.Ids) { try { [void]$msgs.Add([string](Stop-DevApp $id)) } catch { [void]$msgs.Add("✗ ${id}: $($_.Exception.Message)") } }
        }
        if ($p.Act -eq 'restart') { Start-Sleep 2; $msgs.Clear() }
        if ($p.Act -ne 'stop') {
            foreach ($id in $p.Ids) { try { [void]$msgs.Add([string](Start-DevApp $id)) } catch { [void]$msgs.Add("✗ ${id}: $($_.Exception.Message)") } }
        }
        , $msgs.ToArray()
    }.ToString()
    Start-CoreAsync $code @{ Ids = @($apps.Id); Act = $act } {
        param($r, $ctx)
        $script:appsBatchBusy = $false
        $form.Cursor = 'Default'
        $appsSync.Kick = $true
        if (-not $r.Ok) { foreach ($id in $ctx.Ids) { $script:appsPending.Remove($id) }; Update-AppsPending; Set-Status "Lỗi: $($r.Value)"; return }
        $msgs = @($r.Value)
        $errs = @($msgs | Where-Object { $_ -like '✗*' })
        # Lệnh đã gửi xong: start/restart còn chờ app nghe port, stop chờ lần quét sau xác nhận đã tắt
        foreach ($id in $ctx.Ids) { if ($script:appsPending[$id]) { $script:appsPending[$id].DoneAt = Get-Date } }
        foreach ($e in $errs) {
            if ($e -match '^✗ ([a-z0-9-]+): (.*)$') { $script:appsPending.Remove($Matches[1]); $script:appsFailed[$Matches[1]] = $Matches[2] }
        }
        Update-AppsPending
        if ($msgs.Count -eq 1) { Set-Status $msgs[0] }
        else { Set-Status ("$($ctx.Verb) $($msgs.Count) ứng dụng: $($msgs.Count - $errs.Count) OK" + $(if ($errs.Count) { ", $($errs.Count) lỗi" } else { '' })) }
        if ($errs.Count) { [System.Windows.Forms.MessageBox]::Show(($errs -join "`n`n"), "$($ctx.Verb) - có lỗi", 'OK', 'Warning') | Out-Null }
    } @{ Verb = $verb; Ids = @($apps.Id) }
}

# ---------- Trạng thái đang xử lý trên từng dòng (biểu tượng xoay) ----------
$script:appsPending = @{}     # id -> @{ Act; Since; DoneAt; Tool }
$script:appsFailed  = @{}     # id -> lý do (hiện "✗ Lỗi" cho tới lần thao tác sau / app chạy được)
$script:spinIdx = 0
$SpinFrames = '◐', '◓', '◑', '◒'
$PendingText = @{ start = 'Đang khởi động'; restart = 'Đang khởi động lại'; stop = 'Đang dừng' }
$StartTimeoutSec = 180

function Get-AppStateCell($a) {
    $pd = $script:appsPending[$a.Id]
    if ($pd) {
        $sec = [int]((Get-Date) - $pd.Since).TotalSeconds
        $color = if ($pd.Act -eq 'stop') { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::RoyalBlue }
        return @{ Text = "$($SpinFrames[$script:spinIdx % 4]) $($PendingText[$pd.Act])… ${sec}s"; Color = $color; Tip = '' }
    }
    if ($script:appsFailed.ContainsKey($a.Id) -and -not $a.Running) {
        return @{ Text = '✗ Lỗi - xem log'; Color = [System.Drawing.Color]::Firebrick; Tip = $script:appsFailed[$a.Id] }
    }
    if ($a.Running) { return @{ Text = '● Đang chạy'; Color = [System.Drawing.Color]::ForestGreen; Tip = '' } }
    if ($a.Busy)    { return @{ Text = "⚠ Port bị $($a.Process) chiếm"; Color = [System.Drawing.Color]::DarkOrange; Tip = '' } }
    @{ Text = '○ Đã dừng'; Color = [System.Drawing.Color]::Gray; Tip = '' }
}

function Test-RootAlive([string]$id) {
    $pidFile = Join-Path $AppsLogDir "$id.pid"
    if (-not (Test-Path $pidFile)) { return $false }
    [bool](Get-Process -Id ([int](Get-Content $pidFile | Select-Object -First 1)) -ErrorAction SilentlyContinue)
}

# Gọi khi có dữ liệu quét mới: xác định app đã lên / đã tắt / bị lỗi
function Resolve-AppsPending {
    foreach ($id in @($script:appsPending.Keys)) {
        $pd = $script:appsPending[$id]
        if (-not $pd.DoneAt -or $appsSync.At -le $pd.DoneAt) { continue }      # dữ liệu quét trước lúc lệnh xong
        $a = $script:appsData | Where-Object Id -eq $id | Select-Object -First 1
        if (-not $a) { $script:appsPending.Remove($id); continue }
        if ($pd.Act -eq 'stop') { if (-not $a.Running) { $script:appsPending.Remove($id) }; continue }
        if ($a.Running -and -not $pd.Tool) { $script:appsPending.Remove($id); $script:appsFailed.Remove($id); continue }
        if (-not (Test-RootAlive $id)) {
            $script:appsPending.Remove($id)
            # tool (migrator...) chạy xong tự thoát là bình thường
            if (-not $pd.Tool -and -not $a.Running) { $script:appsFailed[$id] = 'Tiến trình đã thoát trước khi app nghe port - xem log' }
            continue
        }
        if (-not $pd.Tool -and ((Get-Date) - $pd.DoneAt).TotalSeconds -gt $StartTimeoutSec) {
            $script:appsPending.Remove($id)
            $script:appsFailed[$id] = "Sau $StartTimeoutSec giây vẫn chưa thấy app nghe port $($a.Port) - xem log"
        }
    }
}

# Chỉ cập nhật ô Trạng thái (không dựng lại danh sách) -> chạy được 4 lần/giây
function Update-AppsPending {
    foreach ($it in $lvApps.Items) {
        $c = Get-AppStateCell $it.Tag
        $sub = $it.SubItems[4]
        if ($sub.Text -ne $c.Text) { $sub.Text = $c.Text; $sub.ForeColor = $c.Color }
        if ($it.ToolTipText -ne $c.Tip) { $it.ToolTipText = $c.Tip }
    }
}
$spinTimer = New-Object System.Windows.Forms.Timer
$spinTimer.Interval = 250
$spinTimer.Add_Tick({
    if (-not $script:appsPending.Count -or -not $form.Visible -or $tabs.SelectedTab -ne $pageApps) { return }
    $script:spinIdx++
    if ($script:spinIdx % 8 -eq 0) { $appsSync.Kick = $true }      # đang chờ app lên: quét port mỗi 2s thay vì 5s
    Update-AppsPending
})
$spinTimer.Start()

function Open-AppWeb($apps) {
    $urls = @($apps | Where-Object Url | ForEach-Object Url)
    if (-not $urls.Count) { Set-Status 'App đã chọn không có địa chỉ web.'; return }
    foreach ($u in $urls) { Start-Process $u }
}
function Open-AppLog($apps) {
    $miss = @()
    foreach ($a in $apps) {
        $log = Join-Path $AppsLogDir "$($a.Id).log"
        if (-not (Test-Path $log)) { $miss += $a.Name; continue }
        $cmd = "powershell -NoProfile -NoExit -Command Get-Content -LiteralPath '$log' -Wait -Tail 150 -Encoding UTF8"
        if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList "--title `"$($a.Name)`" $cmd" } else { Start-Process powershell.exe -ArgumentList ($cmd -replace '^powershell ', '') }
    }
    if ($miss.Count) { Set-Status "Chưa có log (chưa khởi động từ panel): $($miss -join ', ')" }
}
function Get-AppFolder($a) { if ($a.Dir) { $a.Dir } elseif ($a.Path) { Split-Path $a.Path } else { $null } }

New-Button 'Start' 12 304 74 $pageApps { Invoke-AppsBatch 'start' (Get-SelectedApps) } | Out-Null
New-Button 'Stop' 90 304 74 $pageApps { Invoke-AppsBatch 'stop' (Get-SelectedApps) } | Out-Null
New-Button 'Restart' 168 304 74 $pageApps { Invoke-AppsBatch 'restart' (Get-SelectedApps) } | Out-Null
New-Button 'Mở web' 246 304 74 $pageApps { $s = Get-SelectedApps; if ($s) { Open-AppWeb $s } } | Out-Null
New-Button 'Xem log' 324 304 74 $pageApps { $s = Get-SelectedApps; if ($s) { Open-AppLog $s } } | Out-Null
New-Button 'Quét project' 402 304 108 $pageApps { Invoke-ProjectScan } | Out-Null

# Menu chuột phải
$appsMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miAppStart   = $appsMenu.Items.Add('Start', $null, { Invoke-AppsBatch 'start' (Get-SelectedApps) })
$miAppStop    = $appsMenu.Items.Add('Stop', $null, { Invoke-AppsBatch 'stop' (Get-SelectedApps) })
$miAppRestart = $appsMenu.Items.Add('Restart', $null, { Invoke-AppsBatch 'restart' (Get-SelectedApps) })
[void]$appsMenu.Items.Add('-')
$miAppWeb     = $appsMenu.Items.Add('Mở web', $null, { Open-AppWeb (Get-SelectedApps) })
$miAppLog     = $appsMenu.Items.Add('Xem log', $null, { Open-AppLog (Get-SelectedApps) })
[void]$appsMenu.Items.Add('-')
$miAppFolder  = $appsMenu.Items.Add('Mở thư mục project', $null, { foreach ($a in Get-SelectedApps) { $d = Get-AppFolder $a; if ($d) { Start-Process explorer.exe "`"$d`"" } } })
$miAppTerm    = $appsMenu.Items.Add('Mở terminal tại thư mục', $null, {
    foreach ($a in Get-SelectedApps) {
        $d = Get-AppFolder $a
        if (-not $d) { continue }
        if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList "-d `"$($d.TrimEnd('\'))`"" } else { Start-Process powershell.exe -WorkingDirectory $d }
    }
})
$CodeCmd = (Get-Command code.cmd).Source
$miAppCode    = $appsMenu.Items.Add('Mở bằng VS Code', $null, { foreach ($a in Get-SelectedApps) { $d = Get-AppFolder $a; if ($d) { Start-Process $CodeCmd -ArgumentList "`"$d`"" -WindowStyle Hidden } } })
$miAppCopy    = New-Object System.Windows.Forms.ToolStripMenuItem('Copy')
[void]$miAppCopy.DropDownItems.Add('Tên', $null, { [System.Windows.Forms.Clipboard]::SetText((@(Get-SelectedApps).Name -join "`r`n")) })
$miCopyUrl = $miAppCopy.DropDownItems.Add('URL', $null, { [System.Windows.Forms.Clipboard]::SetText((@(Get-SelectedApps | Where-Object Url).Url -join "`r`n")) })
$miCopyDir = $miAppCopy.DropDownItems.Add('Đường dẫn thư mục', $null, { [System.Windows.Forms.Clipboard]::SetText((@(Get-SelectedApps | ForEach-Object { Get-AppFolder $_ } | Where-Object { $_ }) -join "`r`n")) })
[void]$miAppCopy.DropDownItems.Add('Lệnh start', $null, { [System.Windows.Forms.Clipboard]::SetText((@(Get-SelectedApps | Where-Object Known | ForEach-Object { ((Get-AppsConfig).Apps | Where-Object id -eq $_.Id).start }) -join "`r`n")) })
[void]$appsMenu.Items.Add($miAppCopy)
[void]$appsMenu.Items.Add('-')
$script:menuGroup = $null
function Get-GroupApps { @($lvApps.Items | ForEach-Object { $_.Tag } | Where-Object { $_.Group -eq $script:menuGroup }) }
$miGroupStart = $appsMenu.Items.Add('Start cả nhóm', $null, { Invoke-AppsBatch 'start' (Get-GroupApps) })
$miGroupStop  = $appsMenu.Items.Add('Stop cả nhóm', $null, { Invoke-AppsBatch 'stop' @(Get-GroupApps | Where-Object Running) })
$miGroupSel   = $appsMenu.Items.Add('Chọn cả nhóm', $null, { foreach ($it in $lvApps.Items) { $it.Selected = ($it.Tag.Group -eq $script:menuGroup) } })
[void]$appsMenu.Items.Add('-')
[void]$appsMenu.Items.Add('Chọn tất cả (Ctrl+A)', $null, { foreach ($it in $lvApps.Items) { $it.Selected = $true } })
[void]$appsMenu.Items.Add('Làm mới', $null, { $appsSync.Kick = $true; Set-Status 'Đang quét lại các port...' })
$miAppStart.Font = New-Object System.Drawing.Font($appsMenu.Font, [System.Drawing.FontStyle]::Bold)

$appsMenu.Add_Opening({
    param($s, $e)
    $sel = @(Get-SelectedApps -Quiet)
    $n = $sel.Count
    $suffix = if ($n -gt 1) { " ($n app)" } else { '' }
    $canStart = @($sel | Where-Object { $_.Known -and -not $_.Running -and -not $script:appsPending[$_.Id] }).Count
    $miAppStart.Text = "Start$suffix";   $miAppStart.Enabled = [bool]$canStart
    $miAppStop.Text = "Stop$suffix";     $miAppStop.Enabled = [bool]@($sel | Where-Object { $_.Running -or $_.Known }).Count
    $miAppRestart.Text = "Restart$suffix"; $miAppRestart.Enabled = [bool]@($sel | Where-Object Known).Count
    $miAppWeb.Enabled = [bool]@($sel | Where-Object Url).Count
    $miAppLog.Enabled = [bool]$n
    $hasDir = [bool]@($sel | Where-Object { Get-AppFolder $_ }).Count
    $miAppFolder.Enabled = $hasDir; $miAppTerm.Enabled = $hasDir
    $miAppCode.Visible = [bool]$CodeCmd; $miAppCode.Enabled = $hasDir
    $miAppCopy.Enabled = [bool]$n; $miCopyUrl.Enabled = $miAppWeb.Enabled; $miCopyDir.Enabled = $hasDir
    foreach ($m in @($miAppStart, $miAppStop, $miAppRestart)) { $m.Enabled = $m.Enabled -and -not $script:appsBatchBusy }
    # Nhóm của dòng đang trỏ chuột (hoặc dòng đang chọn)
    $pt = $lvApps.PointToClient([System.Windows.Forms.Cursor]::Position)
    $hit = $lvApps.GetItemAt($pt.X, $pt.Y)
    $script:menuGroup = if ($hit) { $hit.Tag.Group } elseif ($n) { $sel[0].Group } else { $null }
    $okGroup = $script:menuGroup -and $script:menuGroup -ne 'Khác (đang chạy)'
    foreach ($m in @($miGroupStart, $miGroupStop, $miGroupSel)) { $m.Visible = [bool]$okGroup }
    if ($okGroup) {
        $miGroupStart.Text = "Start cả nhóm $($script:menuGroup)"
        $miGroupStop.Text = "Stop cả nhóm $($script:menuGroup)"
        $miGroupSel.Text = "Chọn cả nhóm $($script:menuGroup)"
        $miGroupStart.Enabled = -not $script:appsBatchBusy; $miGroupStop.Enabled = -not $script:appsBatchBusy
    }
})
$lvApps.ContextMenuStrip = $appsMenu
$lvApps.Add_KeyDown({
    param($s, $e)
    if ($e.Control -and $e.KeyCode -eq 'A') { foreach ($it in $lvApps.Items) { $it.Selected = $true }; $e.Handled = $true }
    elseif ($e.KeyCode -eq 'F5') { $appsSync.Kick = $true }
    elseif ($e.KeyCode -eq 'Enter') { Open-AppWeb (Get-SelectedApps) }
})

# Bấm tiêu đề cột để sắp xếp (bấm lại để đảo chiều)
$script:appsSort = @{ Col = -1; Desc = $false }
$lvApps.Add_ColumnClick({
    param($s, $e)
    if ($script:appsSort.Col -eq $e.Column) { $script:appsSort.Desc = -not $script:appsSort.Desc }
    else { $script:appsSort.Col = $e.Column; $script:appsSort.Desc = $false }
    for ($i = 0; $i -lt $AppsCols.Count; $i++) {
        $lvApps.Columns[$i].Text = $AppsCols[$i][0] + $(if ($i -eq $script:appsSort.Col) { if ($script:appsSort.Desc) { ' ▼' } else { ' ▲' } } else { '' })
    }
    Render-Apps
})

# ---------- Git của project đang chọn ----------
# Chạy hàm của core ở runspace riêng (git fetch/pull có thể mất vài giây) -> healthTimer gọi Update-AsyncJobs để nhận kết quả
$script:asyncJobs = New-Object System.Collections.ArrayList
function Start-CoreAsync([string]$code, [hashtable]$params, [scriptblock]$onDone, [hashtable]$ctx = @{}) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1'))
    $rs.SessionStateProxy.SetVariable('p', $params)
    $rs.SessionStateProxy.SetVariable('code', $code)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        $ErrorActionPreference = 'Stop'
        . $corePath
        try { [pscustomobject]@{ Ok = $true; Value = (& ([scriptblock]::Create($code))) } }
        catch { [pscustomobject]@{ Ok = $false; Value = $_.Exception.Message } }
    })
    [void]$script:asyncJobs.Add(@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $onDone; Ctx = $ctx })
}
function Update-AsyncJobs {
    foreach ($j in @($script:asyncJobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        $r = $j.PS.EndInvoke($j.Handle) | Select-Object -Last 1
        $j.PS.Dispose(); $j.RS.Dispose()
        $script:asyncJobs.Remove($j)
        & $j.OnDone $r $j.Ctx
    }
}

$gGit = New-Group 'Git' 344 130 $pageApps
$lblGit1 = New-Label 'Chọn một ứng dụng để xem git.' 12 22 488 $gGit -Bold
$lblGit2 = New-Label '' 12 44 488 $gGit
$lblGit3 = New-Label '' 12 66 488 $gGit
$lblGit3.ForeColor = [System.Drawing.Color]::DimGray
foreach ($l in @($lblGit1, $lblGit2, $lblGit3)) { $l.AutoEllipsis = $true }
$cbBranch = New-Object System.Windows.Forms.ComboBox
$cbBranch.DropDownStyle = 'DropDownList'
$cbBranch.Location = New-Object System.Drawing.Point(160, 95)
$cbBranch.Size = New-Object System.Drawing.Size(150, 28)
$gGit.Controls.Add($cbBranch)
$script:gitFor = $null
$script:gitInfo = $null

function Show-GitInfo($g) {
    $script:gitInfo = $g
    $cbBranch.Items.Clear()
    if (-not $g.IsRepo) {
        $lblGit1.Text = 'Thư mục này không nằm trong git repo.'; $lblGit1.ForeColor = [System.Drawing.Color]::DimGray
        $lblGit2.Text = $g.Dir; $lblGit3.Text = ''
        return
    }
    $sync = if ($g.Upstream) { "→ $($g.Upstream) · ↓$($g.Behind) ↑$($g.Ahead)" } else { '· chưa có upstream' }
    $lblGit1.Text = "⎇ $($g.Branch)  $sync · $($g.Dirty) file đang sửa"
    $lblGit1.ForeColor = if ($g.Behind) { [System.Drawing.Color]::Firebrick } elseif ($g.Dirty) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::ForestGreen }
    $lblGit2.Text = "$($g.LastHash)  $($g.LastMsg) — $($g.LastAuthor), $($g.LastWhen)"
    $lblGit3.Text = "$($g.Root)  ·  $($g.Remote)" + $(if ($g.LastFetch) { "  ·  fetch lúc $($g.LastFetch)" } else { '' })
    foreach ($b in $g.Branches) { [void]$cbBranch.Items.Add($b) }
    $cbBranch.SelectedItem = $g.Branch
}

function Load-GitInfo([string]$id) {
    $script:gitFor = $id
    $lblGit1.Text = 'Đang đọc git...'; $lblGit1.ForeColor = [System.Drawing.Color]::DimGray
    $lblGit2.Text = ''; $lblGit3.Text = ''
    Start-CoreAsync 'Get-AppGitInfo $p.Id' @{ Id = $id } {
        param($r, $ctx)
        if ($ctx.Id -ne $script:gitFor) { return }       # người dùng đã chọn app khác
        if ($r.Ok) { Show-GitInfo $r.Value } else { $lblGit1.Text = "Lỗi git: $($r.Value)"; $lblGit1.ForeColor = [System.Drawing.Color]::Firebrick }
    } @{ Id = $id }
}

function Invoke-GitAction([string]$act, [string]$branch = '') {
    $id = $script:gitFor
    if (-not $id -or -not $script:gitInfo.IsRepo) { Set-Status 'Hãy chọn một ứng dụng nằm trong git repo.'; return }
    Set-Status "git $act đang chạy..."
    $form.Cursor = 'AppStarting'
    Start-CoreAsync 'Invoke-AppGit $p.Id $p.Act $p.Branch' @{ Id = $id; Act = $act; Branch = $branch } {
        param($r, $ctx)
        $form.Cursor = 'Default'
        $first = (([string]$r.Value) -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        Set-Status ($(if ($r.Ok) { "✓ " } else { "✗ " }) + $first)
        if (-not $r.Ok) { [System.Windows.Forms.MessageBox]::Show([string]$r.Value, "git $($ctx.Act)", 'OK', 'Warning') | Out-Null }
        if ($ctx.Id -eq $script:gitFor) { Load-GitInfo $ctx.Id }
    } @{ Id = $id; Act = $act }
}

New-Button 'Fetch' 12 94 70 $gGit { Invoke-GitAction 'fetch' } | Out-Null
New-Button 'Pull' 86 94 70 $gGit { Invoke-GitAction 'pull' } | Out-Null
New-Button 'Chuyển nhánh' 316 94 100 $gGit {
    $b = [string]$cbBranch.SelectedItem
    if (-not $b -or $b -eq $script:gitInfo.Branch) { Set-Status 'Chọn nhánh khác nhánh hiện tại trong ô bên cạnh.'; return }
    if ([System.Windows.Forms.MessageBox]::Show("Chuyển $($script:gitInfo.Root) sang nhánh '$b'?", 'Git', 'YesNo', 'Question') -eq 'Yes') { Invoke-GitAction 'switch' $b }
} | Out-Null
New-Button 'Thư mục' 422 94 80 $gGit { if ($script:gitInfo) { Start-Process explorer.exe $(if ($script:gitInfo.Root) { $script:gitInfo.Root } else { $script:gitInfo.Dir }) } } | Out-Null

$script:appsRendering = $false
$lvApps.Add_SelectedIndexChanged({
    if ($script:appsRendering -or $lvApps.SelectedItems.Count -eq 0) { return }
    # Chọn nhiều dòng: khung Git hiện dòng vừa bấm (dòng có focus)
    $f = $lvApps.FocusedItem
    $a = if ($f -and $f.Selected) { $f.Tag } else { $lvApps.SelectedItems[0].Tag }
    if (-not $a.Known) { $script:gitFor = $null; $script:gitInfo = $null; $lblGit1.Text = 'App ngoài danh mục - không biết thư mục project.'; $lblGit2.Text = ''; $lblGit3.Text = ''; $cbBranch.Items.Clear(); return }
    if ($a.Id -ne $script:gitFor) { Load-GitInfo $a.Id }
})

$appsSync = [hashtable]::Synchronized(@{ Data = $null; At = [datetime]::MinValue; Seq = 0; Run = $true; Active = $false; Kick = $false })
$appsRs = [runspacefactory]::CreateRunspace()
$appsRs.Open()
$appsRs.SessionStateProxy.SetVariable('sync', $appsSync)
$appsRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1'))
$appsPs = [powershell]::Create()
$appsPs.Runspace = $appsRs
[void]$appsPs.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'
    . $corePath
    while ($sync.Run) {
        if ($sync.Active -or $sync.Kick) {
            $sync.Kick = $false
            try { $t = Get-Date; $sync.Data = @(Get-DevApps); $sync.At = $t; $sync.Seq++ } catch { }
            for ($i = 0; $i -lt 16 -and $sync.Run -and $sync.Active -and -not $sync.Kick; $i++) { Start-Sleep -Milliseconds 300 }   # ~5s
        } else { Start-Sleep -Milliseconds 300 }
    }
})
[void]$appsPs.BeginInvoke()

$script:appsSeq = 0
$script:appsData = $null
function Update-Apps {
    if ($appsSync.Seq -eq $script:appsSeq) { return }
    $script:appsSeq = $appsSync.Seq
    if ($null -eq $appsSync.Data) { return }
    $script:appsData = $appsSync.Data
    Resolve-AppsPending
    $run = @($script:appsData | Where-Object Running).Count
    $lblApps.Text = "$run ứng dụng đang chạy · $(@($script:appsData | Where-Object Known).Count) trong danh mục apps.json" +
        $(if ($script:appsPending.Count) { " · đang xử lý $($script:appsPending.Count)" } else { '' })
    Render-Apps
}

function Get-SortedApps {
    $apps = @($script:appsData)
    $col = $script:appsSort.Col
    if ($col -lt 0) { return $apps }      # chưa bấm cột nào: giữ thứ tự apps.json
    $key = switch ($col) {
        0 { { $_.Group } }
        1 { { $_.Name } }
        2 { { $_.Type } }
        3 { { [int]$_.Port } }
        4 { { if ($script:appsPending[$_.Id]) { 0 } elseif ($_.Running) { 1 } elseif ($_.Busy) { 2 } else { 3 } } }
        5 { { [int]$_.Pid } }
    }
    $apps | Sort-Object @{ Expression = $key; Descending = $script:appsSort.Desc }, @{ Expression = 'Group' }, @{ Expression = 'Name' }
}

function Render-Apps {
    if ($null -eq $script:appsData) { return }
    $selIds = @($lvApps.SelectedItems | ForEach-Object { $_.Tag.Id })
    $focusId = if ($lvApps.FocusedItem) { $lvApps.FocusedItem.Tag.Id } else { $null }
    $top = if ($lvApps.TopItem) { $lvApps.TopItem.Index } else { 0 }
    $script:appsRendering = $true
    $lvApps.BeginUpdate(); $lvApps.Items.Clear()
    foreach ($a in (Get-SortedApps)) {
        $it = New-Object System.Windows.Forms.ListViewItem($a.Group)
        $it.UseItemStyleForSubItems = $false
        $state = Get-AppStateCell $a
        foreach ($v in @($a.Name, $a.Type, $(if ($a.Port) { [string]$a.Port } else { '' }), $state.Text, $(if ($a.Pid) { [string]$a.Pid } else { '' }))) { [void]$it.SubItems.Add($v) }
        $it.SubItems[4].ForeColor = $state.Color
        $it.ToolTipText = $state.Tip
        $it.Tag = $a
        [void]$lvApps.Items.Add($it)
        if ($selIds -contains $a.Id) { $it.Selected = $true }
        if ($a.Id -eq $focusId) { $it.Focused = $true }
    }
    $lvApps.EndUpdate()
    if ($lvApps.Items.Count) { try { $lvApps.TopItem = $lvApps.Items[[math]::Min($top, $lvApps.Items.Count - 1)] } catch { } }
    $script:appsRendering = $false
}

function Sync-HealthMode {
    $healthSync.Fast = ($form.Visible -and $tabs.SelectedTab -eq $pageHealth)
    $k3sSync.Active  = ($form.Visible -and $tabs.SelectedTab -eq $pageK3s)
    $appsSync.Active = ($form.Visible -and $tabs.SelectedTab -eq $pageApps)
}
$tabs.Add_SelectedIndexChanged({
    Sync-HealthMode; $script:lastSeq = -1; Update-Health
    if ($tabs.SelectedTab -eq $pageK3s)  { $k3sSync.Kick = $true }
    if ($tabs.SelectedTab -eq $pageApps) { $appsSync.Kick = $true }
})
$form.Add_VisibleChanged({ Sync-HealthMode })

# ---------- Tab Cài đặt ----------
function Invoke-ProjectScan {
    $roots = @($PanelConfig.scanRoots)
    if (-not $roots.Count) {
        $tabs.SelectedTab = $pageSettings
        Set-Status 'Chưa có thư mục gốc để quét - thêm ở tab Cài đặt (vd E:\SUNHOUSE\supperapp).'
        return
    }
    $form.Cursor = 'WaitCursor'; Set-Status 'Đang quét project...'; [System.Windows.Forms.Application]::DoEvents()
    try {
        $n = Update-AppsCatalog $roots
        Set-Status "Đã quét $($roots.Count) thư mục: tìm thấy $n project (backend / BFF / frontend / tool)."
    } catch { Set-Status "Lỗi khi quét: $($_.Exception.Message)" }
    $form.Cursor = 'Default'
    $appsSync.Kick = $true
}

$gGeneral = New-Group 'Chung' 10 70 $pageSettings
New-Label 'Tên hiển thị' 12 30 110 $gGeneral | Out-Null
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(125, 27); $txtName.Size = New-Object System.Drawing.Size(240, 26)
$txtName.Text = $AppName
$gGeneral.Controls.Add($txtName)
New-Button 'Đổi tên' 375 24 120 $gGeneral {
    $new = $txtName.Text.Trim()
    if (-not $new) { Set-Status 'Tên không được để trống.'; return }
    $PanelConfig.appName = $new; Save-PanelConfig $PanelConfig
    Rename-OwnShortcuts $new
    $script:AppName = $new
    $form.Text = $new
    $tray.Text = $(if ($new.Length -gt 60) { $new.Substring(0, 60) } else { $new })
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DevOpsPanel'
    if (Test-Path $uninstallKey) { Set-ItemProperty $uninstallKey -Name DisplayName -Value $new }
    Set-Status "Đã đổi tên thành '$new' (cửa sổ, khay hệ thống, shortcut)."
} | Out-Null

$gWsl = New-Group 'WSL / PostgreSQL (áp dụng sau khi mở lại panel)' 88 100 $pageSettings
New-Label 'Distro WSL' 12 30 110 $gWsl | Out-Null
$cbDistro = New-Object System.Windows.Forms.ComboBox
$cbDistro.DropDownStyle = 'DropDownList'
$cbDistro.Location = New-Object System.Drawing.Point(125, 27); $cbDistro.Size = New-Object System.Drawing.Size(240, 28)
[void]$cbDistro.Items.Add('(tự chọn)')
foreach ($d in $WslDistros) { [void]$cbDistro.Items.Add($d) }
$cbDistro.SelectedItem = $(if ($PanelConfig.distro -and $WslDistros -contains $PanelConfig.distro) { $PanelConfig.distro } else { '(tự chọn)' })
$gWsl.Controls.Add($cbDistro)
if (-not $WslDistros.Count) { New-Label '(chưa cài WSL / distro nào)' 375 30 130 $gWsl | Out-Null }
New-Label 'Port PostgreSQL' 12 64 110 $gWsl | Out-Null
$numPg = New-Object System.Windows.Forms.NumericUpDown
$numPg.Location = New-Object System.Drawing.Point(125, 61); $numPg.Size = New-Object System.Drawing.Size(100, 26)
$numPg.Maximum = 65535; $numPg.Value = [int]$PanelConfig.pgUbuntuPort
$gWsl.Controls.Add($numPg)
New-Label '0 = không dùng PostgreSQL trong WSL' 235 64 270 $gWsl | Out-Null

$gScan = New-Group 'Tab Ứng dụng: thư mục gốc để quét project' 196 250 $pageSettings
$lbRoots = New-Object System.Windows.Forms.ListBox
$lbRoots.Location = New-Object System.Drawing.Point(12, 26); $lbRoots.Size = New-Object System.Drawing.Size(360, 110)
foreach ($r in $PanelConfig.scanRoots) { [void]$lbRoots.Items.Add($r) }
$gScan.Controls.Add($lbRoots)
New-Button 'Thêm thư mục...' 380 26 118 $gScan {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Chọn thư mục chứa các project (vd E:\SUNHOUSE\supperapp)'
    if ($dlg.ShowDialog() -eq 'OK' -and -not $lbRoots.Items.Contains($dlg.SelectedPath)) { [void]$lbRoots.Items.Add($dlg.SelectedPath) }
} | Out-Null
New-Button 'Xoá' 380 62 118 $gScan { if ($lbRoots.SelectedItem) { $lbRoots.Items.Remove($lbRoots.SelectedItem) } } | Out-Null
New-Button 'Sửa apps.json' 380 98 118 $gScan { Start-Process notepad.exe $AppsFile } | Out-Null
New-Label 'Dải port tự phát hiện app đang chạy' 12 146 250 $gScan | Out-Null
$txtRanges = New-Object System.Windows.Forms.TextBox
$txtRanges.Location = New-Object System.Drawing.Point(265, 143); $txtRanges.Size = New-Object System.Drawing.Size(233, 26)
$txtRanges.Text = ((Get-AppsConfig).Ranges | ForEach-Object { "$($_[0])-$($_[1])" }) -join ', '
$gScan.Controls.Add($txtRanges)
$lblScanHint = New-Label 'Tìm project .NET (đọc launchSettings.json) và Vite (đọc port trong vite.config). App thêm tay trong apps.json với "manual": true được giữ nguyên khi quét lại.' 12 178 486 $gScan
$lblScanHint.Size = New-Object System.Drawing.Size(486, 36); $lblScanHint.ForeColor = [System.Drawing.Color]::DimGray
New-Button 'Lưu và quét ngay' 12 212 160 $gScan { Save-SettingsTab; Invoke-ProjectScan } | Out-Null

function Save-SettingsTab {
    $PanelConfig.distro = $(if ($cbDistro.SelectedItem -and $cbDistro.SelectedItem -ne '(tự chọn)') { [string]$cbDistro.SelectedItem } else { '' })
    $PanelConfig.pgUbuntuPort = [int]$numPg.Value
    $PanelConfig.scanRoots = @($lbRoots.Items | ForEach-Object { [string]$_ })
    Save-PanelConfig $PanelConfig
    $ranges = @($txtRanges.Text -split '[,;\s]+' | Where-Object { $_ -match '^(\d+)-(\d+)$' } |
        ForEach-Object { , @([int]$Matches[1], [int]$Matches[2]) })
    if ($ranges.Count) { Save-AppsConfig $ranges (Get-AppsConfig).Apps }
}

New-Button 'Lưu và mở lại panel' 6 456 200 $pageSettings {
    Save-SettingsTab
    $script:restartRequested = $true; $script:exiting = $true; $form.Close()
} | Out-Null
$lblDataDir = New-Label "Dữ liệu: $DataDir" 214 462 300 $pageSettings
$lblDataDir.ForeColor = [System.Drawing.Color]::DimGray; $lblDataDir.AutoEllipsis = $true

# ---------- Khay hệ thống ----------
$script:exiting = $false
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $AppIcon
$tray.Text = $(if ($AppName.Length -gt 60) { $AppName.Substring(0, 60) } else { $AppName })
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Mở panel', $null, { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
if ($Distro) {
    [void]$menu.Items.Add("Khởi động $Distro", $null, { Start-Ubuntu; Update-Status })
    [void]$menu.Items.Add("Tắt $Distro", $null, { Stop-Ubuntu; Update-Status })
    [void]$menu.Items.Add('Mở k9s', $null, { Start-Ubuntu; Open-UbuntuTerminal '-u root -e env KUBECONFIG=/etc/rancher/k3s/k3s.yaml k9s' })
}
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Thoát panel', $null, { $script:exiting = $true; $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })

$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:exiting -and $e.CloseReason -eq 'UserClosing') {
        $e.Cancel = $true
        $form.Hide()
        $tray.ShowBalloonTip(2000, 'DevOps Panel', 'Panel vẫn chạy ở khay hệ thống. Chuột phải để Thoát.', 'Info')
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ if ($form.Visible -and $tabs.SelectedTab -eq $pageMain) { Update-Status } })

$healthTimer = New-Object System.Windows.Forms.Timer
$healthTimer.Interval = 1000
$healthTimer.Add_Tick({ Update-Health; Update-K3s; Update-Apps; Update-AsyncJobs })

function Start-WebPanel {
    if ($HasWebPanel -and -not (Test-Port 8787)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'WebPanel.ps1')`""
    }
}

$form.Add_Shown({
    Start-WebPanel
    Update-Status
    if ($settings.autoStartUbuntu -and -not (Get-KeepAlive)) {
        Invoke-Busy 'Đang tự khởi động Ubuntu...' { Start-Ubuntu }
        Set-Status 'Ubuntu đã được tự khởi động.'
    } else { Set-Status 'Sẵn sàng.' }
    $timer.Start()
    $healthTimer.Start()
})

# ---------- Co giãn theo cửa sổ ----------
# Bố cục ở trên thiết kế cho bề rộng 560; neo (Anchor) trước rồi mới phóng form để control giãn theo.
# Phải làm trong Load: trước đó TabPage chưa có kích thước thật (mặc định 200px) -> khoảng neo bị âm, control tràn ra ngoài.
$form.Add_Load({
foreach ($pg in $tabs.TabPages) { $pg.Bounds = $tabs.DisplayRectangle }   # tab chưa chọn cũng phải có kích thước thật
$tabs.Anchor = 'Top, Bottom, Left, Right'
$chkLogon.Anchor = 'Bottom, Left'; $chkAuto.Anchor = 'Bottom, Left'
$statusLbl.Anchor = 'Bottom, Left, Right'
foreach ($g in $pageMain.Controls) { if ($g -is [System.Windows.Forms.GroupBox]) { $g.Anchor = 'Top, Left, Right' } }
$list.Anchor = 'Top, Left, Right'
foreach ($m in $meters.Values) { $m.Bar.Anchor = 'Top, Left, Right'; $m.Label.Anchor = 'Top, Right' }
foreach ($c in @($lblInfo, $lblWarn, $chart, $lblK3s, $lblApps)) { $c.Anchor = 'Top, Left, Right' }
$lvCpu.Anchor = 'Top, Bottom, Left'; $lvRam.Anchor = 'Top, Bottom, Left'
$gGit.Anchor = 'Bottom, Left, Right'
foreach ($l in @($lblGit1, $lblGit2, $lblGit3)) { $l.Anchor = 'Top, Left, Right' }
foreach ($page in @($pageK3s, $pageApps)) {
    foreach ($c in $page.Controls) {
        if ($c -is [System.Windows.Forms.Button])   { $c.Anchor = 'Bottom, Left' }
        if ($c -is [System.Windows.Forms.ListView]) { $c.Anchor = 'Top, Bottom, Left, Right' }
    }
}

# Hai bảng "Ăn CPU / Ăn RAM" chia đôi bề ngang
$script:ramTitle = $pageHealth.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -eq 'Ăn RAM nhiều nhất' }
$pageHealth.Add_Resize({
    $half = [int](($pageHealth.ClientSize.Width - 36) / 2)
    $lvCpu.Width = $half
    $lvRam.Left = 24 + $half; $lvRam.Width = $half
    if ($script:ramTitle) { $script:ramTitle.Left = $lvRam.Left }
})

# Cột tên tự lấp phần bề ngang còn trống
function Set-FillColumn($lv, [int]$idx) {
    $lv.Add_Resize({
        param($s, $e)
        $others = 0
        for ($i = 0; $i -lt $s.Columns.Count; $i++) { if ($i -ne $idx) { $others += $s.Columns[$i].Width } }
        $s.Columns[$idx].Width = [math]::Max(80, $s.ClientSize.Width - $others - 4)
    }.GetNewClosure())
}
Set-FillColumn $list 0
Set-FillColumn $lvApps 1
Set-FillColumn $lvPods 1
Set-FillColumn $lvCpu 0
Set-FillColumn $lvRam 0
foreach ($g in @($gGeneral, $gWsl, $gScan, $lblDataDir)) { $g.Anchor = 'Top, Left, Right' }

# Lần chạy đầu trên máy mới: chưa có thư mục quét và danh mục trống -> mở tab Cài đặt
if (-not @($PanelConfig.scanRoots).Count -and -not @((Get-AppsConfig).Apps).Count) {
    $tabs.SelectedTab = $pageSettings
    Set-Status 'Chào mừng! Thêm thư mục chứa project rồi bấm "Lưu và quét ngay" để có danh sách ứng dụng.'
}

$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.MinimumSize = New-Object System.Drawing.Size(560, 650)
$wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
$form.Size = New-Object System.Drawing.Size([math]::Min(980, $wa.Width), [math]::Min(720, $wa.Height))
$form.Location = New-Object System.Drawing.Point(($wa.Left + ($wa.Width - $form.Width) / 2), ($wa.Top + ($wa.Height - $form.Height) / 2))
})

[System.Windows.Forms.Application]::Run($form)
$timer.Stop(); $healthTimer.Stop(); $spinTimer.Stop(); $healthSync.Run = $false; $k3sSync.Run = $false; $appsSync.Run = $false
$tray.Visible = $false; $tray.Dispose()
$mutex.ReleaseMutex()

# "Lưu và mở lại panel" ở tab Cài đặt
if ($script:restartRequested) {
    if ($LauncherExe) { Start-Process $LauncherExe -WorkingDirectory $PSScriptRoot }
    else { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
}
