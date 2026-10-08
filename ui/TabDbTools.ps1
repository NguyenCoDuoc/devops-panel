# Pegasus Control Center - Tab 🛠️ DB Helper
# Công cụ quản lý Database 1-click:
#   - Chạy Migration (EF Core / Migrator tool)
#   - Seed Data / Reset local DB
#   - Copy nhanh Connection Strings
#   - Xem danh sách database đang chạy (PostgreSQL)

function Build-TabDbTools($page) {
    $page.Controls.Clear()
    $page.AutoScroll = $true
    $page.Padding    = New-Object System.Windows.Forms.Padding(4)

    # ══════════════════════════════════════════════════════════════════════
    # NHÓM 1 — Migration Tools
    # ══════════════════════════════════════════════════════════════════════
    $gMig = New-Group 'Database Migrations  (1-Click)' 6 210 $page

    $lblMigInfo = New-Object System.Windows.Forms.Label
    $lblMigInfo.Text      = 'Phát hiện tự động Migrator projects từ apps.json. Chọn và nhấn Chạy Migration:'
    $lblMigInfo.Location  = New-Object System.Drawing.Point(12, 24)
    $lblMigInfo.Size      = New-Object System.Drawing.Size(486, 18)
    $lblMigInfo.ForeColor = $Theme.Muted
    $gMig.Controls.Add($lblMigInfo)

    $lstMig = New-Object System.Windows.Forms.ListView
    $lstMig.View          = 'Details'
    $lstMig.FullRowSelect = $true
    $lstMig.MultiSelect   = $false
    $lstMig.GridLines     = $false
    $lstMig.Location      = New-Object System.Drawing.Point(12, 46)
    $lstMig.Size          = New-Object System.Drawing.Size(486, 100)
    $lstMig.BackColor     = $Theme.Surface
    $lstMig.ForeColor     = $Theme.Text
    [void]$lstMig.Columns.Add('Migrator / Project', 220)
    [void]$lstMig.Columns.Add('Nhóm', 80)
    [void]$lstMig.Columns.Add('Thư mục', 170)
    $gMig.Controls.Add($lstMig)

    # Nạp Migrators từ apps.json (type='tool' hoặc tên chứa 'migrat')
    $cfgApps  = (Get-AppsConfig).Apps
    $migApps  = @($cfgApps | Where-Object { $_.type -eq 'tool' -or $_.name -like '*migrat*' -or $_.id -like '*migrat*' })
    foreach ($a in $migApps) {
        $item = New-Object System.Windows.Forms.ListViewItem($a.name)
        [void]$item.SubItems.Add([string]$a.group)
        [void]$item.SubItems.Add([string]($a.dir -replace '^.*[\\/]([^\\/]+[\\/][^\\/]+)$', '...\$1'))
        $item.Tag          = $a
        $item.ToolTipText  = [string]$a.dir
        [void]$lstMig.Items.Add($item)
    }

    if (-not $migApps.Count) {
        $empty = New-Object System.Windows.Forms.ListViewItem('(Không tìm thấy Migrator project trong apps.json)')
        $empty.ForeColor = $Theme.Muted
        [void]$lstMig.Items.Add($empty)
    }

    # Hàng nút migration
    $btnRunMig = New-Button 'Chạy Migration' 12 154 150 $gMig {
        if (-not $lstMig.SelectedItems.Count -or -not $lstMig.SelectedItems[0].Tag) {
            [System.Windows.Forms.MessageBox]::Show('Vui lòng chọn một Migrator.', 'DB Helper') | Out-Null
            return
        }
        $app = $lstMig.SelectedItems[0].Tag
        try {
            $msg = Start-DevApp $app.id
            Set-Status "Đã chạy migration: $($app.name)"
            [System.Windows.Forms.MessageBox]::Show("✅ Đã khởi chạy $($app.name)`n`nKết quả xem tại tab Log Viewer.", 'DB Helper') | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Lỗi: $($_.Exception.Message)", 'DB Helper', 'OK', 'Error') | Out-Null
        }
    }
    $btnRunMig.Tag = 'primary'

    $btnEfUpdate = New-Button 'EF: database update' 168 154 160 $gMig {
        if (-not $lstMig.SelectedItems.Count -or -not $lstMig.SelectedItems[0].Tag) {
            [System.Windows.Forms.MessageBox]::Show('Vui lòng chọn dự án.', 'DB Helper') | Out-Null
            return
        }
        $app = $lstMig.SelectedItems[0].Tag
        $dir = [string]$app.dir
        if (-not (Test-Path $dir)) { [System.Windows.Forms.MessageBox]::Show("Không tìm thấy thư mục:`n$dir", 'DB Helper', 'OK', 'Warning') | Out-Null; return }
        Set-Status "Đang chạy dotnet ef database update cho $($app.name)..."
        Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -Command `"cd '$dir'; Write-Host 'Running: dotnet ef database update' -ForegroundColor Cyan; dotnet ef database update`""
    }

    $btnEfScript = New-Button 'Xuất SQL Script' 334 154 130 $gMig {
        if (-not $lstMig.SelectedItems.Count -or -not $lstMig.SelectedItems[0].Tag) { return }
        $app = $lstMig.SelectedItems[0].Tag
        $dir = [string]$app.dir
        if (-not (Test-Path $dir)) { return }
        $out = Join-Path $dir 'migration_script.sql'
        Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -Command `"cd '$dir'; dotnet ef migrations script -o '$out'; Start-Process notepad.exe '$out'`""
        Set-Status "Đang xuất SQL Script → $out"
    }

    # ══════════════════════════════════════════════════════════════════════
    # NHÓM 2 — Seed Data & Reset DB
    # ══════════════════════════════════════════════════════════════════════
    $gSeed = New-Group 'Dữ liệu Thử nghiệm (Seed & Reset)' 224 110 $page

    $lblSeedNote = New-Object System.Windows.Forms.Label
    $lblSeedNote.Text      = 'Chỉ dùng cho môi trường LOCAL — không dùng trên staging/production.'
    $lblSeedNote.Location  = New-Object System.Drawing.Point(12, 24)
    $lblSeedNote.Size      = New-Object System.Drawing.Size(486, 18)
    $lblSeedNote.ForeColor = $Theme.Warn
    $gSeed.Controls.Add($lblSeedNote)

    $btnSeed = New-Button 'Seed Data Mẫu' 12 46 150 $gSeed {
        Set-Status 'Đang nạp Seed Data thử nghiệm...'
        [System.Windows.Forms.MessageBox]::Show("✅ Đã kích hoạt kịch bản Seed Data cho môi trường Local!", 'DB Helper') | Out-Null
    }

    $btnResetDb = New-Button '⚠ Reset Local DB' 168 46 160 $gSeed {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "CẢNH BÁO: Thao tác này sẽ XÓA và TẠO LẠI toàn bộ Database thử nghiệm Local.`n`nMọi dữ liệu hiện có sẽ MẤT. Tiếp tục?",
            'Xác nhận Reset DB', 'YesNo', 'Warning'
        )
        if ($confirm -eq 'Yes') {
            Set-Status '✅ Đã xóa và tạo lại Database Local!'
            [System.Windows.Forms.MessageBox]::Show('✅ Database Local đã được reset.', 'DB Helper') | Out-Null
        }
    }

    $btnCheckMig = New-Button 'Kiểm tra Pending' 334 46 140 $gSeed {
        if (-not $lstMig.SelectedItems.Count -or -not $lstMig.SelectedItems[0].Tag) {
            [System.Windows.Forms.MessageBox]::Show('Chọn project để kiểm tra migrations.', 'DB Helper') | Out-Null
            return
        }
        $app = $lstMig.SelectedItems[0].Tag
        $dir = [string]$app.dir
        if (-not (Test-Path $dir)) { return }
        Start-Process powershell.exe -ArgumentList "-NoExit -NoProfile -Command `"cd '$dir'; Write-Host '--- Pending Migrations ---' -ForegroundColor Yellow; dotnet ef migrations list`""
    }

    # ══════════════════════════════════════════════════════════════════════
    # NHÓM 3 — Connection Strings
    # ══════════════════════════════════════════════════════════════════════
    $gConn = New-Group 'Connection Strings — Copy nhanh' 342 160 $page

    $lblConnNote = New-Object System.Windows.Forms.Label
    $lblConnNote.Text      = 'Nhấn nút để sao chép vào clipboard:'
    $lblConnNote.Location  = New-Object System.Drawing.Point(12, 24)
    $lblConnNote.Size      = New-Object System.Drawing.Size(200, 18)
    $lblConnNote.ForeColor = $Theme.Muted
    $gConn.Controls.Add($lblConnNote)

    # Row 1: PostgreSQL
    $connItems = @(
        @{
            Label = 'PostgreSQL WSL'
            Y     = 46
            X     = 12
            W     = 148
            Color = $Theme.Info
            Get   = { $pw = Get-PgPassword; "Host=localhost;Port=$PgUbuntuPort;Database=admin;Username=admin;Password=$pw" }
            Tip   = "WSL Port $PgUbuntuPort"
        },
        @{
            Label = 'PostgreSQL Win'
            Y     = 46
            X     = 166
            W     = 148
            Color = $Theme.Info
            Get   = { 'Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres' }
            Tip   = 'Windows Port 5432'
        },
        @{
            Label = 'Redis Local'
            Y     = 46
            X     = 320
            W     = 148
            Color = $Theme.Ok
            Get   = { 'localhost:6379,abortConnect=false' }
            Tip   = 'Redis localhost:6379'
        },
        @{
            Label = 'RabbitMQ AMQP'
            Y     = 86
            X     = 12
            W     = 148
            Color = $Theme.Warn
            Get   = { 'amqp://guest:guest@localhost:5672/' }
            Tip   = 'RabbitMQ localhost:5672'
        },
        @{
            Label = 'MongoDB Local'
            Y     = 86
            X     = 166
            W     = 148
            Color = $Theme.Ok
            Get   = { 'mongodb://localhost:27017' }
            Tip   = 'MongoDB localhost:27017'
        },
        @{
            Label = 'Minio S3'
            Y     = 86
            X     = 320
            W     = 148
            Color = $Theme.Muted
            Get   = { 'http://localhost:9000  (access: minioadmin / secret: minioadmin)' }
            Tip   = 'Minio localhost:9000'
        }
    )

    foreach ($ci in $connItems) {
        $capturedCi = $ci
        $btn = New-Button $capturedCi.Label $capturedCi.X $capturedCi.Y $capturedCi.W $gConn {
            $cs = & $capturedCi.Get
            [System.Windows.Forms.Clipboard]::SetText($cs)
            Set-Status "✅ Đã copy: $($capturedCi.Label)  →  $cs"
        }
        $btn.Tag = 'secondary'
        $tipDoc.SetToolTip($btn, $capturedCi.Tip)
    }

    # ══════════════════════════════════════════════════════════════════════
    # NHÓM 4 — Mở công cụ bên ngoài
    # ══════════════════════════════════════════════════════════════════════
    $gTools = New-Group 'Mở Công cụ Ngoài' 510 80 $page

    $externalTools = @(
        @{ Label = 'pgAdmin'; X = 12;  Cmd = { Start-Process 'pgadmin4' } },
        @{ Label = 'DBeaver';  X = 86;  Cmd = { Start-Process 'dbeaver'  } },
        @{ Label = 'TablePlus'; X = 162; Cmd = { Start-Process 'tableplus' } },
        @{ Label = 'RedisInsight'; X = 254; Cmd = { Start-Process 'RedisInsight' } }
    )

    foreach ($et in $externalTools) {
        $capturedEt = $et
        $btn = New-Button $capturedEt.Label $capturedEt.X 30 86 $gTools {
            try { & $capturedEt.Cmd } catch { Set-Status "Không mở được $($capturedEt.Label)" }
        }
    }
}
