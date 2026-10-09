# Pegasus Control Center - Tab 🤖 AI Code Assistant
# Sidebar trái: danh sách phiên group theo thư mục làm việc
# Folder picker: nút duyệt thư mục + danh sách gần đây
# Gọi Install-AiSidebar sau khi layout AI tab đã được dựng xong trong PegasusPanel.ps1

function Install-AiSidebar {
    # ── Kích thước sidebar ──────────────────────────────────────────────────
    $SideW  = 200
    $ColHdr = 26   # chiều cao dòng header group
    $ColRow = 42   # hai dòng: tên session và công cụ / thời gian

    # ── Panel bao toàn bộ sidebar (Dock Left) ───────────────────────────────
    $script:aiSide = New-Object System.Windows.Forms.Panel
    $script:aiSide.Dock    = 'Left'
    $script:aiSide.Width   = $SideW
    $script:aiSide.Name    = 'bg:Card'
    $script:aiSide.Cursor  = 'Default'
    Set-DoubleBuffered $script:aiSide

    # Viền phải sidebar
    $script:aiSide.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($Theme.Border)
        $e.Graphics.DrawLine($pen, ($s.Width - 1), 0, ($s.Width - 1), $s.Height)
        $pen.Dispose()
    })

    # ── Header sidebar: "Phiên làm việc" + nút [+] ──────────────────────────
    $pnlSideHdr = New-Object System.Windows.Forms.Panel
    $pnlSideHdr.Dock   = 'Top'
    $pnlSideHdr.Height = 44
    $pnlSideHdr.Name   = 'bg:Header'
    $pnlSideHdr.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($Theme.Border)
        $e.Graphics.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $pen.Dispose()
    })

    $lblSideTitle = New-Object System.Windows.Forms.Label
    $lblSideTitle.Text      = 'Phiên làm việc'
    $lblSideTitle.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $lblSideTitle.Location  = New-Object System.Drawing.Point(10, 12)
    $lblSideTitle.Size      = New-Object System.Drawing.Size(110, 20)
    $lblSideTitle.ForeColor = $Theme.Text
    $pnlSideHdr.Controls.Add($lblSideTitle)

    # Nút "Phiên mới" mini
    $btnSideNew = New-Object System.Windows.Forms.Button
    $btnSideNew.Text        = '+'
    $btnSideNew.Font        = New-Object System.Drawing.Font('Segoe UI', 12)
    $btnSideNew.Location    = New-Object System.Drawing.Point(($SideW - 48), 8)
    $btnSideNew.Size        = New-Object System.Drawing.Size(28, 28)
    $btnSideNew.FlatStyle   = 'Flat'
    $btnSideNew.FlatAppearance.BorderSize = 0
    $btnSideNew.BackColor   = [System.Drawing.Color]::Transparent
    $btnSideNew.ForeColor   = $Theme.Accent
    $btnSideNew.Cursor      = 'Hand'
    $tipDoc.SetToolTip($btnSideNew, 'Bắt đầu phiên mới')
    $btnSideNew.Add_Click({
        $script:ai.Session = $null; $script:ai.Key = ''; $script:ai.Title = $null
        Clear-AiChat; Show-AiWelcome; Update-AiUi
    })
    $pnlSideHdr.Controls.Add($btnSideNew)

    # ── Panel cuộn chứa danh sách sessions ─────────────────────────────────
    $pnlSideList = New-Object System.Windows.Forms.Panel
    $pnlSideList.Dock       = 'Fill'
    $pnlSideList.AutoScroll = $true
    $pnlSideList.Name       = 'bg:Card'
    Set-DoubleBuffered $pnlSideList

    # ── Section "Thư mục" cuối sidebar ─────────────────────────────────────
    $pnlSideDir = New-Object System.Windows.Forms.Panel
    $pnlSideDir.Dock   = 'Bottom'
    $pnlSideDir.Height = 80
    $pnlSideDir.Name   = 'bg:Header'
    $pnlSideDir.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($Theme.Border)
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })

    $lblDirHdr = New-Object System.Windows.Forms.Label
    $lblDirHdr.Text      = 'Thư mục làm việc'
    $lblDirHdr.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $lblDirHdr.Location  = New-Object System.Drawing.Point(10, 8)
    $lblDirHdr.Size      = New-Object System.Drawing.Size(160, 16)
    $lblDirHdr.ForeColor = $Theme.Muted
    $pnlSideDir.Controls.Add($lblDirHdr)

    # Label hiển thị thư mục đang chọn
    $script:lblSideCurDir = New-Object System.Windows.Forms.Label
    $script:lblSideCurDir.Font        = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $script:lblSideCurDir.Location    = New-Object System.Drawing.Point(10, 26)
    $script:lblSideCurDir.Size        = New-Object System.Drawing.Size(178, 16)
    $script:lblSideCurDir.ForeColor   = $Theme.Text
    $script:lblSideCurDir.AutoEllipsis = $true
    $script:lblSideCurDir.Text        = '(chưa chọn)'
    $pnlSideDir.Controls.Add($script:lblSideCurDir)

    # Nút "Duyệt thư mục..."
    $btnBrowseDir = New-Object System.Windows.Forms.Button
    $btnBrowseDir.Text      = 'Duyệt thư mục…'
    $btnBrowseDir.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $btnBrowseDir.Location  = New-Object System.Drawing.Point(10, 46)
    $btnBrowseDir.Size      = New-Object System.Drawing.Size(($SideW - 20), 26)
    $btnBrowseDir.FlatStyle = 'Flat'
    $btnBrowseDir.FlatAppearance.BorderColor = $Theme.Border
    $btnBrowseDir.BackColor = $Theme.Surface
    $btnBrowseDir.ForeColor = $Theme.Text
    $btnBrowseDir.Cursor    = 'Hand'
    $btnBrowseDir.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description  = 'Chọn thư mục project để AI làm việc'
        $dlg.ShowNewFolderButton = $false
        $cur = Get-AiDir
        if ($cur -and (Test-Path $cur)) { $dlg.SelectedPath = $cur }
        if ($dlg.ShowDialog($form) -eq 'OK') {
            $picked = $dlg.SelectedPath
            # Thêm vào danh sách aiDirs gần đây
            $PanelConfig.aiDirs = @($picked) + @($PanelConfig.aiDirs | Where-Object { $_ -and $_ -ne $picked }) | Select-Object -First 20
            Save-PanelConfig $PanelConfig
            Update-AiDirs $picked
            Refresh-AiSidebar
        }
        $dlg.Dispose()
    })
    $pnlSideDir.Controls.Add($btnBrowseDir)

    # Lắp vào page AI
    $script:aiSide.Controls.AddRange(@($pnlSideList, $pnlSideHdr, $pnlSideDir))
    $pageAi.Controls.Add($script:aiSide)
    $script:aiSide.BringToFront()

    # Đảm bảo aiTop, aiChat, aiBottom không đè lên sidebar
    foreach ($c in @($aiTop, $aiChat, $aiBottom, $aiChooser)) {
        if ($c.Dock -ne 'None') { continue }   # Dock controls tự xếp
    }

    # ── Hàm vẽ lại danh sách sessions ───────────────────────────────────────
    function script:Refresh-AiSidebar {
        $pnlSideList.SuspendLayout()
        $pnlSideList.Controls.Clear()

        $sessions = @($PanelConfig.aiSessions | Where-Object {
            $_.Tool -in $AiTools.Keys -and
            $_.Id   -match '^[\w.:-]+$' -and
            (Test-Path $_.Dir)
        })

        if (-not $sessions.Count) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text     = 'Chưa có phiên nào.`nBắt đầu chat để lưu phiên.'
            $lbl.Font     = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $lbl.ForeColor = $Theme.Muted
            $lbl.Location = New-Object System.Drawing.Point(10, 12)
            $lbl.Size     = New-Object System.Drawing.Size(($SideW - 20), 48)
            $pnlSideList.Controls.Add($lbl)
            $pnlSideList.ResumeLayout()
            return
        }

        $groups = @($sessions | Group-Object Dir | Sort-Object Name)
        $y = 4

        foreach ($grp in $groups) {
            $folderName = Split-Path $grp.Name -Leaf

            # ── Header nhóm folder ──
            $hdrPanel = New-Object System.Windows.Forms.Panel
            $hdrPanel.SetBounds(0, $y, $SideW, $ColHdr)
            $hdrPanel.BackColor = $Theme.Header
            $hdrPanel.Cursor    = 'Default'
            Set-DoubleBuffered $hdrPanel

            $hdrLbl = New-Object System.Windows.Forms.Label
            $hdrLbl.Text      = "📁 $folderName"
            $hdrLbl.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
            $hdrLbl.ForeColor = $Theme.Muted
            $hdrLbl.Location  = New-Object System.Drawing.Point(8, 5)
            $hdrLbl.Size      = New-Object System.Drawing.Size(($SideW - 16), 16)
            $hdrLbl.AutoEllipsis = $true
            $hdrPanel.Controls.Add($hdrLbl)
            # Tooltip: đường dẫn đầy đủ
            $tipDoc.SetToolTip($hdrPanel, $grp.Name)
            $tipDoc.SetToolTip($hdrLbl, $grp.Name)
            $pnlSideList.Controls.Add($hdrPanel)
            $y += $ColHdr

            # ── Các session trong nhóm ──
            foreach ($entry in @($grp.Group | Sort-Object Updated -Descending)) {
                $sess     = $entry
                $rowPanel = New-Object System.Windows.Forms.Panel
                $rowPanel.SetBounds(0, $y, $SideW, $ColRow)
                $rowPanel.BackColor = $Theme.Card
                $rowPanel.Cursor    = 'Hand'
                $rowPanel.Tag       = $sess
                Set-DoubleBuffered $rowPanel

                $rowLbl = New-Object System.Windows.Forms.Label
                $title  = if ($sess.Title) { $sess.Title } else { 'Phiên mới' }
                $date   = try { ([datetime]$sess.Updated).ToString('MM/dd HH:mm') } catch { '' }
                $tool   = [string]$sess.Tool
                $rowLbl.Text      = "$title"
                $rowLbl.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
                $rowLbl.ForeColor = $Theme.Text
                $rowLbl.Location  = New-Object System.Drawing.Point(12, 4)
                $rowLbl.Size      = New-Object System.Drawing.Size(($SideW - 24), 18)
                $rowLbl.AutoEllipsis = $true
                $rowPanel.Controls.Add($rowLbl)

                $rowDate = New-Object System.Windows.Forms.Label
                $rowDate.Text      = "$tool  ·  $date"
                $rowDate.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
                $rowDate.ForeColor = $Theme.Muted
                $rowDate.Location  = New-Object System.Drawing.Point(12, 23)
                $rowDate.Size      = New-Object System.Drawing.Size(($SideW - 24), 15)
                $rowPanel.Controls.Add($rowDate)

                $tipDoc.SetToolTip($rowPanel, "$title`n$($grp.Name)`n$date")
                $tipDoc.SetToolTip($rowLbl, "$title`n$($grp.Name)`n$date")

                # Highlight khi active session
                $isActive = ($script:ai.Session -eq $sess.Id -and $script:ai.Key -like "*$($sess.Dir)*")
                if ($isActive) {
                    $rowPanel.BackColor = $Theme.Sel
                    $rowLbl.ForeColor   = $Theme.Accent
                }

                # Hover effect
                $rowPanel.Add_MouseEnter({
                    param($s, $e)
                    if ($s.BackColor -ne $Theme.Sel) { $s.BackColor = $Theme.Hi }
                })
                $rowPanel.Add_MouseLeave({
                    param($s, $e)
                    $isAct = ($script:ai.Session -eq $s.Tag.Id -and $script:ai.Key -like "*$($s.Tag.Dir)*")
                    $s.BackColor = if ($isAct) { $Theme.Sel } else { $Theme.Card }
                })

                # Click: mở session
                # Panel không có PerformClick -> label (chiếm gần hết dòng) gọi thẳng Open-AiSession bằng Tag của dòng
                $rowPanel.Add_Click({ param($s, $e) Open-AiSession $s.Tag; Refresh-AiSidebar })
                foreach ($ctrl in $rowPanel.Controls) {
                    $ctrl.Cursor = 'Hand'
                    $ctrl.Add_Click({ param($s, $e) Open-AiSession $s.Parent.Tag; Refresh-AiSidebar })
                }

                $pnlSideList.Controls.Add($rowPanel)
                $y += $ColRow

                # Đường kẻ ngăn
                $sep = New-Object System.Windows.Forms.Panel
                $sep.SetBounds(12, $y, $SideW - 24, 1)
                $sep.BackColor = $Theme.Border
                $pnlSideList.Controls.Add($sep)
                $y += 1
            }

            $y += 4   # khoảng cách giữa các nhóm
        }

        $pnlSideList.ResumeLayout()

        # Cập nhật label thư mục hiện tại
        $curDir = Get-AiDir
        $script:lblSideCurDir.Text = if ($curDir) { Split-Path $curDir -Leaf } else { '(chưa chọn)' }
        $tipDoc.SetToolTip($script:lblSideCurDir, $(if ($curDir) { $curDir } else { '' }))
    }

    # Gọi lần đầu
    Refresh-AiSidebar

    # Móc vào Save-AiSession để tự refresh sau mỗi phiên lưu
    # (dùng Add_Click không được; thay vào đó hook Update-AiSessionsButton)
    $origUpdateBtn = (Get-Item function:Update-AiSessionsButton -ErrorAction SilentlyContinue)
}

# ── Gọi từ PegasusPanel.ps1 sau khi AI layout dựng xong ──────────────────────
# Hàm này được tự động chạy khi tab AI được nạp module
if (Get-Command Install-AiSidebar -ErrorAction SilentlyContinue) {
    # Trì hoãn đến khi form Load để đảm bảo $pageAi, $aiTop, v.v. đã tồn tại
    # Gọi qua event Form_Load hoặc trực tiếp nếu form đã load
}
