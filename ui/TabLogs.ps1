# Pegasus Control Center - Tab 📜 Log Viewer Engine
# Trình xem log nâng cao với:
#   - Syntax Highlighting (ERROR đỏ / WARN vàng / INFO xanh)
#   - Lọc & tìm kiếm realtime
#   - Chọn file log từ thư mục logs/ hoặc theo App
#   - Live tail (tự động tải lại mỗi 3 giây)
#   - Dọn log tự động: cắt file cũ sau mỗi ngày (giữ 200 dòng cuối)

function Build-TabLogs($page) {
    $page.Controls.Clear()
    $page.AutoScroll = $false

    # ── Toolbar phía trên ───────────────────────────────────────────────────
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock   = 'Top'
    $pnlTop.Height = 46
    $pnlTop.Name   = 'bg:Header'
    $pnlTop.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($Theme.Border)
        $e.Graphics.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $pen.Dispose()
    })
    $page.Controls.Add($pnlTop)

    # Label "App:"
    $lblApp = New-Object System.Windows.Forms.Label
    $lblApp.Text      = 'App:'
    $lblApp.Location  = New-Object System.Drawing.Point(10, 14)
    $lblApp.Size      = New-Object System.Drawing.Size(30, 18)
    $lblApp.ForeColor = $Theme.Muted
    $pnlTop.Controls.Add($lblApp)

    # ComboBox chọn app
    $cmbApps = New-Object System.Windows.Forms.ComboBox
    $cmbApps.DropDownStyle = 'DropDownList'
    $cmbApps.Location      = New-Object System.Drawing.Point(42, 10)
    $cmbApps.Size          = New-Object System.Drawing.Size(160, 26)
    $pnlTop.Controls.Add($cmbApps)

    # TextBox lọc realtime (ThemedInput với icon kính lúp E721)
    $txtSearch = if (Get-Command New-ThemedInput -ErrorAction SilentlyContinue) {
        New-ThemedInput $pnlTop 212 8 160 30 'Lọc log...' 'E721'
    } else {
        $tbFallback = New-Object System.Windows.Forms.TextBox
        $tbFallback.Location = New-Object System.Drawing.Point(212, 10)
        $tbFallback.Size = New-Object System.Drawing.Size(160, 26)
        $pnlTop.Controls.Add($tbFallback)
        $tbFallback
    }

    # Nút "Tải lại"
    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text      = 'Tải lại'
    $btnRefresh.Location  = New-Object System.Drawing.Point(380, 8)
    $btnRefresh.Size      = New-Object System.Drawing.Size(74, 30)
    $btnRefresh.FlatStyle = 'Flat'
    $pnlTop.Controls.Add($btnRefresh)

    # Toggle Live Tail
    $chkLive = New-Object System.Windows.Forms.CheckBox
    $chkLive.Text      = 'Live'
    $chkLive.Checked   = $false
    $chkLive.Location  = New-Object System.Drawing.Point(462, 13)
    $chkLive.Size      = New-Object System.Drawing.Size(50, 20)
    $chkLive.ForeColor = $Theme.Text
    $pnlTop.Controls.Add($chkLive)

    # Nút "Dọn log" — bên phải
    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Text      = 'Dọn log'
    $btnClean.Location  = New-Object System.Drawing.Point(516, 8)
    $btnClean.Size      = New-Object System.Drawing.Size(80, 30)
    $btnClean.FlatStyle = 'Flat'
    $btnClean.ForeColor = $Theme.Warn
    $pnlTop.Controls.Add($btnClean)

    # ── Panel thông tin dung lượng log (dải dưới toolbar) ─────────────────
    $pnlInfo = New-Object System.Windows.Forms.Panel
    $pnlInfo.Dock   = 'Top'
    $pnlInfo.Height = 26
    $pnlInfo.Name   = 'bg:Alt'
    $pnlInfo.Add_Paint({
        param($s, $e)
        $e.Graphics.Clear($Theme.Alt)
    })
    $page.Controls.Add($pnlInfo)

    $lblDiskInfo = New-Object System.Windows.Forms.Label
    $lblDiskInfo.Location  = New-Object System.Drawing.Point(10, 5)
    $lblDiskInfo.Size      = New-Object System.Drawing.Size(600, 16)
    $lblDiskInfo.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
    $lblDiskInfo.ForeColor = $Theme.Muted
    $lblDiskInfo.Text      = 'Đang tính dung lượng...'
    $pnlInfo.Controls.Add($lblDiskInfo)

    # ── StatusBar nhỏ ────────────────────────────────────────────────────────
    $pnlStatus = New-Object System.Windows.Forms.Panel
    $pnlStatus.Dock   = 'Bottom'
    $pnlStatus.Height = 22
    $pnlStatus.Name   = 'bg:Header'
    $page.Controls.Add($pnlStatus)

    $lblLogStatus = New-Object System.Windows.Forms.Label
    $lblLogStatus.Location  = New-Object System.Drawing.Point(10, 4)
    $lblLogStatus.Size      = New-Object System.Drawing.Size(600, 15)
    $lblLogStatus.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
    $lblLogStatus.ForeColor = $Theme.Muted
    $lblLogStatus.Text      = 'Chọn ứng dụng để xem log.'
    $pnlStatus.Controls.Add($lblLogStatus)

    # ── RichTextBox log thích ứng theo theme ──────────────────────────────
    $rtbLog = New-Object System.Windows.Forms.RichTextBox
    $rtbLog.Dock       = 'Fill'
    $rtbLog.Font       = New-Object System.Drawing.Font('Consolas', 9)
    $rtbLog.ReadOnly   = $true
    $rtbLog.WordWrap   = $false
    $rtbLog.BackColor  = $Theme.Surface
    $rtbLog.ForeColor  = $Theme.Text
    $rtbLog.BorderStyle = 'None'
    $rtbLog.ScrollBars = 'Both'
    Set-DoubleBuffered $rtbLog
    $page.Controls.Add($rtbLog)
    $rtbLog.BringToFront()

    # ── Hàm tính & hiển thị dung lượng thư mục log ───────────────────────
    function Update-DiskInfo {
        try {
            if (-not (Test-Path $AppsLogDir)) { $lblDiskInfo.Text = 'Thư mục log chưa có.'; return }
            $files = @(Get-ChildItem $AppsLogDir -Filter '*.log' -File -ErrorAction SilentlyContinue)
            if (-not $files.Count) { $lblDiskInfo.Text = 'Chưa có file log nào.'; return }
            $totalKB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1KB, 1)
            $totalMB = [math]::Round($totalKB / 1024, 2)
            $sizeText = if ($totalMB -ge 1) { "$totalMB MB" } else { "$totalKB KB" }
            $oldest  = ($files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime.ToString('dd/MM/yyyy')
            $newest  = ($files | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime.ToString('dd/MM HH:mm')
            # Kiểm tra marker dọn hôm nay
            $today   = (Get-Date).ToString('yyyy-MM-dd')
            $cleaned = Test-Path (Join-Path $AppsLogDir ".cleanup-$today")
            $cleanText = if ($cleaned) { ' · ✓ Đã dọn hôm nay' } else { ' · Chưa dọn hôm nay' }
            $lblDiskInfo.Text = "$($files.Count) file log  ·  $sizeText  ·  $oldest → $newest$cleanText"
        } catch {
            $lblDiskInfo.Text = 'Không đọc được thông tin log.'
        }
    }

    # ── Nạp danh sách App ───────────────────────────────────────────────────
    $cfgApps = (Get-AppsConfig).Apps
    foreach ($a in $cfgApps) { [void]$cmbApps.Items.Add($a.id) }
    if ($cmbApps.Items.Count -gt 0) { $cmbApps.SelectedIndex = 0 }
    Update-DiskInfo

    # ── Render log ──────────────────────────────────────────────────────────
    function Render-LogContent {
        if (-not $cmbApps.SelectedItem) { return }
        $appId  = $cmbApps.SelectedItem.ToString()
        $filter = $txtSearch.Text.Trim()

        $rawText = Get-DevAppLog $appId 500
        if (-not $rawText) {
            $rtbLog.Clear()
            $rtbLog.SelectionColor = $Theme.Muted
            $rtbLog.AppendText("(Chưa có dữ liệu log cho '$appId')`n")
            $lblLogStatus.Text = "Không tìm thấy log cho $appId"
            return
        }

        $lines = @($rawText -split "`n")
        if ($filter) {
            $lines = @($lines | Where-Object { $_ -like "*$filter*" })
        }

        $rtbLog.Clear()
        $rtbLog.BackColor = $Theme.Surface
        $rtbLog.BeginUpdate()

        # Màu sắc cú pháp thích ứng Light và Dark theme
        $isDark = ($script:ThemeName -ne 'light')
        $clrDefault = if ($isDark) { [System.Drawing.Color]::FromArgb(226, 232, 240) } else { [System.Drawing.Color]::FromArgb(30, 41, 59) }
        $clrError   = if ($isDark) { $Theme.Err } else { [System.Drawing.Color]::FromArgb(225, 29, 72) }
        $clrWarn    = if ($isDark) { $Theme.Warn } else { [System.Drawing.Color]::FromArgb(180, 83, 9) }
        $clrInfo    = if ($isDark) { $Theme.Ok } else { [System.Drawing.Color]::FromArgb(5, 150, 105) }
        $clrDebug   = if ($isDark) { $Theme.Info } else { [System.Drawing.Color]::FromArgb(2, 132, 199) }
        $clrTime    = $Theme.Muted
        $clrClean   = $Theme.Accent

        try {
            foreach ($line in $lines) {
                $color = $clrDefault

                # Dòng marker tự dọn log
                if     ($line -match '^\={4}.+Log đã được dọn')                                    { $color = $clrClean }
                elseif ($line -match '\[?(CRIT|FATAL|crit|fatal)\]?|Exception:|StackTrace')        { $color = $clrError }
                elseif ($line -match '\[?(ERR|ERROR|Err|error|FAIL|fail|sập|lỗi)\]?')             { $color = $clrError }
                elseif ($line -match '\[?(WARN|warn|Warning|warning|cảnh báo)\]?')                 { $color = $clrWarn }
                elseif ($line -match '\[?(INFO|info|INF|Information|thành công|OK|ok)\]?')         { $color = $clrInfo }
                elseif ($line -match '\[?(DBG|DEBUG|debug|TRACE|trace|Verbose)\]?')                { $color = $clrDebug }
                elseif ($line -match '^\d{4}-\d{2}-\d{2}|\d{2}:\d{2}:\d{2}')                     { $color = $clrTime }

                $rtbLog.SelectionStart  = $rtbLog.TextLength
                $rtbLog.SelectionLength = 0
                $rtbLog.SelectionColor  = $color
                $rtbLog.AppendText($line + "`n")
            }

            # Cuộn xuống dòng cuối
            $rtbLog.SelectionStart = $rtbLog.TextLength
            $rtbLog.ScrollToCaret()
        } finally {
            $rtbLog.EndUpdate()
        }

        $shown = $lines.Count
        $total = ($rawText -split "`n").Count
        $lblLogStatus.Text = "$(Get-Date -Format 'HH:mm:ss')  ·  $shown/$total dòng" + $(if ($filter) { "  ·  lọc: '$filter'" } else { '' })
    }

    # ── Dọn log thủ công ──────────────────────────────────────────────────
    function Invoke-ManualCleanup {
        try {
            if (-not (Test-Path $AppsLogDir)) { $lblLogStatus.Text = 'Thư mục log chưa có.'; return }
            $files   = @(Get-ChildItem $AppsLogDir -Filter '*.log' -File -ErrorAction SilentlyContinue)
            $keepLines = 200
            $cleaned = 0; $savedKB = 0
            foreach ($f in $files) {
                try {
                    $sizeBefore = $f.Length
                    $lines = @(Get-Content $f.FullName -Encoding UTF8 -ErrorAction Stop)
                    if ($lines.Count -le $keepLines) { continue }
                    $today = (Get-Date).ToString('yyyy-MM-dd')
                    $kept = $lines[($lines.Count - $keepLines)..($lines.Count - 1)]
                    $header = "==== $today  [Dọn thủ công - giữ $keepLines dòng cuối] ===="
                    ($header, '') + $kept | Set-Content $f.FullName -Encoding UTF8 -ErrorAction Stop
                    $newSize = (Get-Item $f.FullName).Length
                    $savedKB += [math]::Round(($sizeBefore - $newSize) / 1KB, 1)
                    $cleaned++
                } catch { }
            }
            # Ghi marker hôm nay
            $today = (Get-Date).ToString('yyyy-MM-dd')
            $today | Set-Content (Join-Path $AppsLogDir ".cleanup-$today") -Encoding UTF8
            $msg = if ($cleaned -gt 0) { "✓ Đã dọn $cleaned file log, tiết kiệm $savedKB KB." } else { "Các file log đều nhỏ (≤ $keepLines dòng), không cần dọn." }
            $lblLogStatus.Text = $msg
            Update-DiskInfo
            Render-LogContent
        } catch {
            $lblLogStatus.Text = "Lỗi khi dọn log: $($_.Exception.Message)"
        }
    }

    # ── Timer live tail (3 giây) ─────────────────────────────────────────────
    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 3000
    $liveTimer.Add_Tick({ if ($chkLive.Checked -and $page.Parent -and $tabs.SelectedTab -eq $page) { Render-LogContent } })

    # ── Wire events ──────────────────────────────────────────────────────────
    $btnRefresh.Add_Click({ Render-LogContent; Update-DiskInfo })
    $btnClean.Add_Click({ Invoke-ManualCleanup })
    $cmbApps.Add_SelectedIndexChanged({ Render-LogContent })
    $txtSearch.Add_TextChanged({ Render-LogContent })
    $chkLive.Add_CheckedChanged({
        if ($chkLive.Checked) {
            $liveTimer.Start()
            $lblLogStatus.Text = 'Live tail đang chạy...'
        } else {
            $liveTimer.Stop()
        }
    })

    # Stop timer khi rời tab
    $page.Add_VisibleChanged({
        if (-not $page.Visible) { $liveTimer.Stop() }
        else { Update-DiskInfo }
    })

    # Render lần đầu
    Render-LogContent
}
