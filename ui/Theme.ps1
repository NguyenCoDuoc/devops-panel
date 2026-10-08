# Pegasus Control Center - Theme, Design System & Drawing Engine
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function New-Rgb([int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }

$script:ThemePalettes = @{
    light = @{
        Back = (New-Rgb 243 245 249); Card = (New-Rgb 255 255 255); Surface = (New-Rgb 255 255 255); Alt = (New-Rgb 248 250 252); Header = (New-Rgb 241 244 248)
        Text = (New-Rgb 30 37 50); Muted = (New-Rgb 100 110 130); Gray = (New-Rgb 150 158 172)
        Ok = (New-Rgb 22 163 74); Err = (New-Rgb 220 38 38); Warn = (New-Rgb 217 119 6)
        Info = (New-Rgb 37 99 235); ErrBg = (New-Rgb 253 236 236); Link = (New-Rgb 79 70 229)
        ChartBg = (New-Rgb 250 251 253); Grid = (New-Rgb 228 232 239)
        Button = (New-Rgb 255 255 255); Border = (New-Rgb 214 219 228); Hi = (New-Rgb 238 241 248)
        Sel = (New-Rgb 224 231 255); SelInactive = (New-Rgb 234 238 245)
        Accent = (New-Rgb 79 70 229); Accent2 = (New-Rgb 14 165 233); AccentHi = (New-Rgb 99 91 240); AccentText = (New-Rgb 255 255 255)
    }
    dark = @{
        Back = (New-Rgb 21 23 28); Card = (New-Rgb 29 32 39); Surface = (New-Rgb 25 28 34); Alt = (New-Rgb 30 33 40); Header = (New-Rgb 34 38 46)
        Text = (New-Rgb 230 232 237); Muted = (New-Rgb 152 160 176); Gray = (New-Rgb 120 128 142)
        Ok = (New-Rgb 74 222 128); Err = (New-Rgb 248 113 113); Warn = (New-Rgb 251 191 36)
        Info = (New-Rgb 96 165 250); ErrBg = (New-Rgb 74 35 38); Link = (New-Rgb 139 146 255)
        ChartBg = (New-Rgb 25 28 34); Grid = (New-Rgb 46 51 61)
        Button = (New-Rgb 38 42 51); Border = (New-Rgb 54 60 72); Hi = (New-Rgb 48 53 64)
        Sel = (New-Rgb 48 56 96); SelInactive = (New-Rgb 42 47 57)
        Accent = (New-Rgb 124 131 255); Accent2 = (New-Rgb 34 184 207); AccentHi = (New-Rgb 142 149 255); AccentText = (New-Rgb 255 255 255)
    }
}

$script:LaneColors = @((New-Rgb 79 142 247), (New-Rgb 242 95 92), (New-Rgb 46 194 126), (New-Rgb 245 165 36), (New-Rgb 169 112 255),
                       (New-Rgb 23 195 206), (New-Rgb 255 122 182), (New-Rgb 139 195 74), (New-Rgb 255 138 61), (New-Rgb 92 124 250))

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [math]::Min($r * 2, [math]::Min($w, $h))
    if ($d -le 1) { $p.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h))); return $p }
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $p.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90); $p.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure(); $p
}

function Set-DoubleBuffered($c) {
    try { $c.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($c, $true, $null) } catch {}
}

function Get-Alpha([int]$a, [System.Drawing.Color]$c) { [System.Drawing.Color]::FromArgb($a, $c) }

function Get-WindowsPrefersDark {
    try { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0 } catch { $false }
}

$script:darkNativeLoaded = $false
function Initialize-DarkNative {
    if ($script:darkNativeLoaded) { return $true }
    try {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Runtime.InteropServices; using System.Windows.Forms;
public static class DarkNative {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string app, string idList);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    public static void TitleBar(IntPtr h, bool dark) { int v = dark ? 1 : 0; if (DwmSetWindowAttribute(h, 20, ref v, 4) != 0) DwmSetWindowAttribute(h, 19, ref v, 4); }
    public static void Control(IntPtr h, bool dark) { SetWindowTheme(h, dark ? "DarkMode_Explorer" : null, null); }
    public static void ListView(IntPtr h, bool dark) {
        SetWindowTheme(h, dark ? "DarkMode_Explorer" : null, null);
        IntPtr hd = SendMessage(h, 0x101F, IntPtr.Zero, IntPtr.Zero);
        if (hd != IntPtr.Zero) SetWindowTheme(hd, dark ? "DarkMode_ItemsView" : null, null);
    }
}
"@
        $script:darkNativeLoaded = $true
    } catch { }
    $script:darkNativeLoaded
}

# Fonts & Icons
$script:IconFontName = @('Segoe Fluent Icons', 'Segoe MDL2 Assets') | Where-Object { (New-Object System.Drawing.Font($_, 10)).Name -eq $_ } | Select-Object -First 1
$script:iconCache = @{}
$script:iconTargets = New-Object System.Collections.ArrayList

$script:IconRules = @(
    @('Start cả nhóm', 'E768', 'Ok'), @('Stop cả nhóm', 'E71A', 'Err'), @('Start theo thứ tự', 'E768', 'Ok'), @('Start tất cả', 'E768', 'Ok'), @('Stop cả bộ', 'E71A', 'Err'),
    @('Start', 'E768', 'Ok'), @('Stop', 'E71A', 'Err'), @('Restart pod', 'E777', 'Text'), @('Restart', 'E777', 'Text'),
    @('Khởi động', 'E768', 'Ok'), @('Tắt', 'E71A', 'Err'), @('Làm mới', 'E72C', 'Text'), @('Tải lại log', 'E72C', 'Text'),
    @('Mở web', 'E774', 'Text'), @('Web Panel', 'E774', 'Text'), @('Xem log', 'E8A5', 'Text'), @('Gỡ khỏi panel', 'E74D', 'Err'), @('Gỡ', 'E74D', 'Text'),
    @('Quét project', 'E721', 'Text'), @('Lưu và quét ngay', 'E721', 'Text'), @('Fetch', 'E895', 'Text'), @('Pull', 'E896', 'Text'),
    @('Push + MR', 'E898', 'Text'), @('Commit Push', 'E898', 'Text'), @('Commit', 'E73E', 'Ok'), @('Tạo nhánh', 'F003', 'Info'), @('Nhánh mới', 'F003', 'Info'),
    @('Chuyển nhánh', 'E8AB', 'Text'), @('Checkout', 'E8AB', 'Text'), @('Mở cửa sổ Git', 'F003', 'Info'), @('Mở trong tab Git', 'F003', 'Info'),
    @('Mở trên GitLab', 'E8A7', 'Text'), @('Mở thư mục', 'E8B7', 'Text'), @('Thư mục', 'E8B7', 'Text'), @('Thêm thư mục', 'E8F4', 'Text'),
    @('Mở terminal', 'E756', 'Text'), @('Mở psql', 'E756', 'Text'), @('Mở bằng VS Code', 'E943', 'Text'), @('Mở k9s', 'E7F4', 'Text'),
    @('Mở Docker', 'E7B8', 'Text'), @('Mở panel', 'E8A7', 'Text'), @('Copy email', 'E715', 'Text'), @('Copy', 'E8C8', 'Text'),
    @('Tự khởi động lại', 'E777', 'Text'), @('Giải phóng port', 'EC7A', 'Warn'), @('Bộ app', 'E8F1', 'Text'), @('Lưu các app', 'E710', 'Text'),
    @('Chọn', 'E762', 'Text'), @('Khôi phục', 'E81C', 'Text'), @('Hiện cột', 'E9D9', 'Text'), @('Describe', 'E946', 'Text'),
    @('Chẩn đoán', 'E9D9', 'Text'), @('Xuất danh mục', 'E898', 'Text'), @('Nhập danh mục', 'E896', 'Text'), @('Sửa apps.json', 'E70F', 'Text'),
    @('Đổi tên', 'E70F', 'Text'), @('Xoá', 'E74D', 'Text'), @('Lưu và mở lại', 'E73E', 'Text'), @('Trợ giúp', 'E9CE', 'Text'),
    @('Thoát', 'E711', 'Text'), @('Cài đặt', 'E713', 'Text'), @('Hiện mật khẩu', 'E8D7', 'Text'), @('Thêm', 'E710', 'Ok'), @('Lưu mục tiêu', 'E73E', 'Ok'), @('Sửa', 'E70F', 'Text'),
    @('Chạy Migration', 'E768', 'Ok'), @('Seed Data', 'E710', 'Info'), @('Reset Local DB', 'E74D', 'Warn'), @('Log Viewer', 'E8A5', 'Text')
)

$script:TabIcons = @{
    'Dịch vụ' = 'E9F5'; 'Ứng dụng' = 'E74C'; 'Git' = 'F003'; 'DB Helper' = 'E756'; 'Log Viewer' = 'E8A5'
    'Sức khỏe' = 'E95E'; 'K3s' = 'E7B8'; 'Cài đặt' = 'E713'; 'Trợ giúp' = 'E9CE'; 'AI Code' = 'E99A'
}

function Get-IconBitmap([string]$code, [System.Drawing.Color]$color, [int]$px = 16) {
    $key = "$code|$($color.ToArgb())|$px"
    if ($script:iconCache.ContainsKey($key)) { return $script:iconCache[$key] }
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $f = New-Object System.Drawing.Font($script:IconFontName, [float]($px - 2), [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $br = New-Object System.Drawing.SolidBrush($color)
    $g.DrawString([string][char][Convert]::ToInt32($code, 16), $f, $br, (New-Object System.Drawing.RectangleF(0, 1, $px, $px)), $sf)
    $g.Dispose(); $f.Dispose(); $br.Dispose()
    $script:iconCache[$key] = $bmp
    $bmp
}

function Find-IconRule([string]$text) {
    $t = ($text -replace '^[^\p{L}\p{N}]+\s*', '').Trim()
    foreach ($r in $script:IconRules) { if ($t.StartsWith($r[0])) { return $r } }
    $null
}

function Set-ObjIcon($obj, [string]$code, [string]$colorKey) {
    if (-not $script:IconFontName) { return }
    $img = Get-IconBitmap $code $Theme[$colorKey]
    if ($obj -is [System.Windows.Forms.Button]) {
        $obj.Image = $img; $obj.ImageAlign = 'MiddleLeft'; $obj.TextImageRelation = 'ImageBeforeText'
        $obj.Text = ($obj.Text -replace '^[^\p{L}\p{N}]+\s+', '')
        if (-not $obj.AutoSize) { $w = $obj.GetPreferredSize([System.Drawing.Size]::Empty).Width; if ($w -gt $obj.Width) { $obj.Width = $w } }
    } else { $obj.Image = $img }
    [void]$script:iconTargets.Add(@{ Obj = $obj; Code = $code; Color = $colorKey })
}

function Enable-Card($g) {
    Set-DoubleBuffered $g
    $cardPaint = {
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        $p = New-RoundRect 0 0 ($s.Width - 1) ($s.Height - 1) 10
        $b = New-Object System.Drawing.SolidBrush($Theme.Card); $g.FillPath($b, $p); $b.Dispose()
        $pen = New-Object System.Drawing.Pen($Theme.Border); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
        $bar = New-RoundRect 12 7 4 13 2
        $b = New-Object System.Drawing.SolidBrush($Theme.Accent); $g.FillPath($b, $bar); $b.Dispose(); $bar.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $CardFont, (New-Object System.Drawing.Point(20, 4)), $Theme.Text)
    }
    $g.Add_Paint($cardPaint)
    $g.Add_Resize({ param($s, $e) $s.Invalidate() })
}

function New-Group($text, $y, $h, $parent) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text
    $g.Location = New-Object System.Drawing.Point(6, $y)
    $g.Size = New-Object System.Drawing.Size(510, $h)
    Enable-Card $g
    $parent.Controls.Add($g)
    $g
}

function New-CardHost($x, $y, $w, $h, $parent) {
    $p = New-Object System.Windows.Forms.Panel
    $p.SetBounds($x, $y, $w, $h)
    Set-DoubleBuffered $p
    $hostPaint = {
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        $p = New-RoundRect 0 0 ($s.Width - 1) ($s.Height - 1) 10
        $b = New-Object System.Drawing.SolidBrush($Theme.Surface); $g.FillPath($b, $p); $b.Dispose()
        $pen = New-Object System.Drawing.Pen($(if ($s.ContainsFocus) { $Theme.Accent } else { $Theme.Border }), $(if ($s.ContainsFocus) { 1.6 } else { 1 })); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
    }
    $p.Add_Paint($hostPaint); $p.Add_Resize({ param($s, $e) $s.Invalidate() })
    $parent.Controls.Add($p)
    $p
}
