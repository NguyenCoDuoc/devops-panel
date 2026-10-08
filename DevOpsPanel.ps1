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
# Kết quả dò máy (wsl.exe, WMI) chuyển cho các runspace nền để chúng khỏi dò lại mỗi lần nạp core
$CoreShared = @{ WslDistros = $WslDistros; Distro = $Distro; Components = $Components }
$IconFile    = Join-Path $PSScriptRoot 'icon.ico'
$AppIcon     = if (Test-Path $IconFile) { New-Object System.Drawing.Icon($IconFile) } else { [System.Drawing.SystemIcons]::Application }
$LauncherExe = Find-FirstPath @((Join-Path $PSScriptRoot 'DevOpsPanel.exe'), (Join-Path $PSScriptRoot 'DUOCNC DevOps.exe'))
$HasWebPanel = Test-Path (Join-Path $PSScriptRoot 'WebPanel.ps1')     # Web Panel là bản trả phí: chỉ có khi đặt WebPanel.ps1 cạnh script

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

# ---------- Giao diện Sáng / Tối ----------
# $Theme là bảng màu đang dùng; mọi chỗ tô màu đọc từ đây nên đổi theme chỉ cần đổi bảng rồi tô lại control.
# Back = nền cửa sổ, Card = nền các khung (GroupBox vẽ thành thẻ bo góc), Surface = nền bảng / ô nhập, Alt = dòng kẻ sọc,
# Accent / Accent2 = màu nhấn (tab đang chọn, nút chính, dải tiêu đề chuyển màu)
function New-Rgb([int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }
$ThemePalettes = @{
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
# Màu các làn graph git: tươi, đủ tương phản trên nền sáng lẫn tối
$LaneColors = @((New-Rgb 79 142 247), (New-Rgb 242 95 92), (New-Rgb 46 194 126), (New-Rgb 245 165 36), (New-Rgb 169 112 255),
                (New-Rgb 23 195 206), (New-Rgb 255 122 182), (New-Rgb 139 195 74), (New-Rgb 255 138 61), (New-Rgb 92 124 250))

# Hình chữ nhật bo góc (thẻ, nút trạng thái, nhãn nhánh, thanh đo)
function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [math]::Min($r * 2, [math]::Min($w, $h))
    if ($d -le 1) { $p.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h))); return $p }
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $p.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90); $p.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure(); $p
}
function Set-DoubleBuffered($c) { $c.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($c, $true, $null) }
function Get-Alpha([int]$a, [System.Drawing.Color]$c) { [System.Drawing.Color]::FromArgb($a, $c) }
function Get-WindowsPrefersDark {
    try { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0 } catch { $false }
}
$script:ThemeName = if ($PanelConfig.theme -in 'light', 'dark') { $PanelConfig.theme } elseif (Get-WindowsPrefersDark) { 'dark' } else { 'light' }
$Theme = @{}
foreach ($k in $ThemePalettes.light.Keys) { $Theme[$k] = $ThemePalettes.light[$k] }     # control tạo bằng màu sáng, theme tối áp sau khi form hiện

# Thanh tiêu đề tối, scrollbar / header ListView tối, menu chuột phải tối: cần Win32 + lớp con -> chỉ biên dịch khi dùng theme tối
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
        IntPtr hd = SendMessage(h, 0x101F, IntPtr.Zero, IntPtr.Zero);       // LVM_GETHEADER
        if (hd != IntPtr.Zero) SetWindowTheme(hd, dark ? "DarkMode_ItemsView" : null, null);
    }
}
public class DarkMenuColors : ProfessionalColorTable {
    Color bg, hi, border;
    public DarkMenuColors(Color bg, Color hi, Color border) { this.bg = bg; this.hi = hi; this.border = border; UseSystemColors = false; }
    public override Color ToolStripDropDownBackground { get { return bg; } }
    public override Color ImageMarginGradientBegin { get { return bg; } }
    public override Color ImageMarginGradientMiddle { get { return bg; } }
    public override Color ImageMarginGradientEnd { get { return bg; } }
    public override Color MenuItemSelected { get { return hi; } }
    public override Color MenuItemSelectedGradientBegin { get { return hi; } }
    public override Color MenuItemSelectedGradientEnd { get { return hi; } }
    public override Color MenuItemBorder { get { return hi; } }
    public override Color MenuBorder { get { return border; } }
    public override Color SeparatorDark { get { return border; } }
    public override Color SeparatorLight { get { return bg; } }
}
"@
        $script:darkNativeLoaded = $true
    } catch { }
    $script:darkNativeLoaded
}

# ---------- Icon outline (font icon có sẵn của Windows: Segoe Fluent Icons / Segoe MDL2 Assets) ----------
# Vẽ glyph ra Bitmap theo màu chữ của theme; đổi theme thì vẽ lại. Gắn theo chữ trên nút / mục menu / thẻ tab.
$IconFontName = @('Segoe Fluent Icons', 'Segoe MDL2 Assets') | Where-Object { (New-Object System.Drawing.Font($_, 10)).Name -eq $_ } | Select-Object -First 1
$script:iconCache = @{}
$script:iconTargets = New-Object System.Collections.ArrayList
# (đầu chữ, mã glyph, màu) - mục đầu tiên khớp được dùng; chữ dài đặt trước chữ ngắn
$IconRules = @(
    @('Start cả nhóm', 'E768', 'Ok'), @('Stop cả nhóm', 'E71A', 'Err'), @('Start theo thứ tự', 'E768', 'Ok'), @('Start tất cả', 'E768', 'Ok'), @('Stop cả bộ', 'E71A', 'Err'),
    @('Start', 'E768', 'Ok'), @('Stop', 'E71A', 'Err'), @('Restart pod', 'E777', 'Text'), @('Restart', 'E777', 'Text'),
    @('Khởi động', 'E768', 'Ok'), @('Tắt', 'E71A', 'Err'), @('Làm mới', 'E72C', 'Text'), @('Tải lại log', 'E72C', 'Text'),
    @('Mở web', 'E774', 'Text'), @('Web Panel', 'E774', 'Text'), @('Xem log', 'E8A5', 'Text'), @('Gỡ khỏi panel', 'E74D', 'Err'), @('Gỡ', 'E74D', 'Text'),
    @('Quét project', 'E721', 'Text'), @('Lưu và quét ngay', 'E721', 'Text'), @('Fetch', 'E895', 'Text'), @('Pull', 'E896', 'Text'),
    @('Push + MR', 'E898', 'Text'), @('Commit && Push', 'E898', 'Text'), @('Commit', 'E73E', 'Ok'), @('Tạo nhánh', 'F003', 'Info'), @('Nhánh mới', 'F003', 'Info'),
    @('Chuyển nhánh', 'E8AB', 'Text'), @('Checkout', 'E8AB', 'Text'), @('Mở cửa sổ Git', 'F003', 'Info'), @('Mở trong tab Git', 'F003', 'Info'),
    @('Mở trên GitLab', 'E8A7', 'Text'), @('Mở thư mục', 'E8B7', 'Text'), @('Thư mục', 'E8B7', 'Text'), @('Thêm thư mục', 'E8F4', 'Text'),
    @('Mở terminal', 'E756', 'Text'), @('Mở psql', 'E756', 'Text'), @('Mở bằng VS Code', 'E943', 'Text'), @('Mở k9s', 'E7F4', 'Text'),
    @('Mở Docker', 'E7B8', 'Text'), @('Mở panel', 'E8A7', 'Text'), @('Copy email', 'E715', 'Text'), @('Copy', 'E8C8', 'Text'),
    @('Tự khởi động lại', 'E777', 'Text'), @('Giải phóng port', 'EC7A', 'Warn'), @('Bộ app', 'E8F1', 'Text'), @('Lưu các app', 'E710', 'Text'),
    @('Chọn', 'E762', 'Text'), @('Khôi phục', 'E81C', 'Text'), @('Hiện cột', 'E9D9', 'Text'), @('Describe', 'E946', 'Text'),
    @('Chẩn đoán', 'E9D9', 'Text'), @('Xuất danh mục', 'E898', 'Text'), @('Nhập danh mục', 'E896', 'Text'), @('Sửa apps.json', 'E70F', 'Text'),
    @('Đổi tên', 'E70F', 'Text'), @('Xoá', 'E74D', 'Text'), @('Lưu và mở lại', 'E73E', 'Text'), @('Trợ giúp', 'E9CE', 'Text'),
    @('Thoát', 'E711', 'Text'), @('Cài đặt', 'E713', 'Text'), @('Hiện mật khẩu', 'E8D7', 'Text'), @('Thêm', 'E710', 'Ok'), @('Lưu mục tiêu', 'E73E', 'Ok'), @('Sửa…', 'E70F', 'Text'), @('Để sang ngày mai', 'E72A', 'Text'), @('Kiểm tra cập nhật', 'E895', 'Text'), @('Cài bản mới', 'E896', 'Ok'), @('Xem trên GitHub', 'E8A7', 'Text'), @('Cập nhật', 'E896', 'Ok'),
    @('Gửi', 'E724', 'Text'), @('Dừng', 'E71A', 'Err'), @('Phiên mới', 'E710', 'Text'), @('Xem thay đổi', 'E890', 'Text'), @('Cài / cập nhật CLI', 'E896', 'Text'),
    @('Code với AI', 'E99A', 'Info'), @('Mở bằng AI', 'E99A', 'Info')
)
$TabIcons = @{ 'Dịch vụ' = 'E9F5'; 'Ứng dụng' = 'E74C'; 'Git' = 'F003'; 'Sức khỏe' = 'E95E'; 'K3s' = 'E7B8'; 'Cài đặt' = 'E713'; 'Trợ giúp' = 'E9CE'; 'AI Code' = 'E99A' }

function Get-IconBitmap([string]$code, [System.Drawing.Color]$color, [int]$px = 16) {
    $key = "$code|$($color.ToArgb())|$px"
    if ($script:iconCache.ContainsKey($key)) { return $script:iconCache[$key] }
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $f = New-Object System.Drawing.Font($IconFontName, [float]($px - 2), [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $br = New-Object System.Drawing.SolidBrush($color)
    $g.DrawString([string][char][Convert]::ToInt32($code, 16), $f, $br, (New-Object System.Drawing.RectangleF(0, 1, $px, $px)), $sf)
    $g.Dispose(); $f.Dispose(); $br.Dispose()
    $script:iconCache[$key] = $bmp
    $bmp
}
function Find-IconRule([string]$text) {
    $t = ($text -replace '^[^\p{L}\p{N}]+\s*', '').Trim()           # bỏ ký hiệu cũ ở đầu (⟳ ✔ ↓ ...)
    foreach ($r in $IconRules) { if ($t.StartsWith($r[0])) { return $r } }
    $null
}
# Gắn icon cho 1 nút / mục menu (ghi nhớ để đổi màu khi đổi theme)
function Set-ObjIcon($obj, [string]$code, [string]$colorKey) {
    if (-not $IconFontName) { return }
    $img = Get-IconBitmap $code $Theme[$colorKey]
    if ($obj -is [System.Windows.Forms.Button]) {
        $obj.Image = $img; $obj.ImageAlign = 'MiddleLeft'; $obj.TextImageRelation = 'ImageBeforeText'
        $obj.Text = ($obj.Text -replace '^[^\p{L}\p{N}]+\s+', '')
        if (-not $obj.AutoSize) { $w = $obj.GetPreferredSize([System.Drawing.Size]::Empty).Width; if ($w -gt $obj.Width) { $obj.Width = $w } }
    } else { $obj.Image = $img }
    [void]$script:iconTargets.Add(@{ Obj = $obj; Code = $code; Color = $colorKey })
}
# Duyệt control / menu và gắn icon theo chữ
function Add-IconsTo($root) {
    if (-not $IconFontName) { return }
    $stack = New-Object System.Collections.Stack; $stack.Push($root)
    while ($stack.Count) {
        $c = $stack.Pop()
        if ($c -is [System.Windows.Forms.Button] -and -not $c.Image) { $r = Find-IconRule $c.Text; if ($r) { Set-ObjIcon $c $r[1] $(if (Test-PrimaryButton $c) { 'AccentText' } else { $r[2] }) } }
        if ($c.ContextMenuStrip) { Add-MenuIcons $c.ContextMenuStrip.Items }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
}
# Nút chính (tô màu nhấn): đánh dấu Tag = 'primary', hoặc nút AcceptButton của hộp thoại
function Test-PrimaryButton($b) { $f = $b.FindForm(); $b.Tag -eq 'primary' -or ($f -and $f.AcceptButton -eq $b) }
function Add-MenuIcons($items) {
    if (-not $IconFontName) { return }
    foreach ($i in $items) {
        if ($i -isnot [System.Windows.Forms.ToolStripMenuItem]) { continue }
        if (-not $i.Image) { $r = Find-IconRule $i.Text; if ($r) { Set-ObjIcon $i $r[1] $r[2] } }
        if ($i.DropDownItems.Count) { Add-MenuIcons $i.DropDownItems }
    }
}
# Đổi theme -> vẽ lại icon theo màu mới
function Update-IconColors {
    foreach ($t in @($script:iconTargets)) {
        $o = $t.Obj
        if (($o -is [System.Windows.Forms.Control] -and $o.IsDisposed) -or ($o -is [System.Windows.Forms.ToolStripItem] -and $o.IsDisposed)) { $script:iconTargets.Remove($t); continue }
        $o.Image = Get-IconBitmap $t.Code $Theme[$t.Color]
    }
    $sideNav.Invalidate()
}
# Xếp lại 1 hàng nút sau khi thêm icon (nút rộng ra): đặt liền nhau từ trái sang
function Set-ButtonRow($parent, [int]$top, [int]$x0 = 12, [int]$gap = 4) {
    $x = $x0
    foreach ($b in @($parent.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Top -eq $top } | Sort-Object Left)) { $b.Left = $x; $x += $b.Width + $gap }
    $x
}

# ---------- UI ----------
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName  v$PanelVersion"
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
$pageGit    = New-Object System.Windows.Forms.TabPage('Git')
$pageHelp   = New-Object System.Windows.Forms.TabPage('Trợ giúp')
$pageAi     = New-Object System.Windows.Forms.TabPage('AI Code')
$tabs.TabPages.AddRange(@($pageMain, $pageApps, $pageGit, $pageHealth, $pageK3s, $pageSettings, $pageAi, $pageHelp))
$form.Controls.Add($tabs)

# Dải tiêu đề chuyển màu ở trên cùng: icon, tên app, lời chào + các chip CPU / RAM / số app đang chạy
# (tab được đẩy xuống trong Load, sau khi đã neo control để không lệch bố cục thiết kế)
$HeaderH = 56
$HeaderFont = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$HeaderSub = New-Object System.Drawing.Font('Segoe UI', 9)
$TabFont = New-Object System.Drawing.Font('Segoe UI', 10)
$TabFontSel = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$CardFont = New-Object System.Drawing.Font('Segoe UI Semibold', 9.75)
$script:hdrChips = @()
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, $form.ClientSize.Width, $HeaderH)
Set-DoubleBuffered $header
$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $r = $s.ClientRectangle
    if ($r.Width -lt 2) { return }
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $Theme.Accent, $Theme.Accent2, [single]0)
    $g.FillRectangle($br, $r); $br.Dispose()
    $g.DrawIcon($AppIcon, (New-Object System.Drawing.Rectangle(16, 12, 32, 32)))
    $white = [System.Drawing.Color]::White
    [System.Windows.Forms.TextRenderer]::DrawText($g, $AppName, $HeaderFont, (New-Object System.Drawing.Point(56, 7)), $white)
    $sub = "v$PanelVersion  ·  $((Get-Greeting) -replace '^\W+\s*', '')"
    [System.Windows.Forms.TextRenderer]::DrawText($g, $sub, $HeaderSub, (New-Object System.Drawing.Point(58, 32)), (Get-Alpha 225 $white))
    $navEnd = 56 + [math]::Max([System.Windows.Forms.TextRenderer]::MeasureText($AppName, $HeaderFont).Width, [System.Windows.Forms.TextRenderer]::MeasureText($sub, $HeaderSub).Width)
    $script:hdrTabs = @()
    if ($PanelConfig.navLayout -ne 'side') {
        # Menu tab dạng pill trắng trên dải màu; không đủ chỗ thì chỉ hiện icon (rê chuột để xem tên)
        $x = $navEnd + 28
        $ws = @(foreach ($pg in $tabs.TabPages) { [System.Windows.Forms.TextRenderer]::MeasureText($pg.Text, $TabFontSel).Width + 46 })
        $iconOnly = ($x + ($ws | Measure-Object -Sum).Sum + 4 * $ws.Count) -gt ($r.Right - 14)
        $rects = @()
        for ($i = 0; $i -lt $tabs.TabCount; $i++) {
            $pg = $tabs.TabPages[$i]; $sel = $i -eq $tabs.SelectedIndex
            $w = if ($iconOnly) { 38 } else { $ws[$i] }
            $rc = New-Object System.Drawing.Rectangle($x, 12, $w, 32)
            $rects += $rc
            if ($sel -or $i -eq $script:hdrHover) {
                $p = New-RoundRect $rc.X $rc.Y $rc.Width $rc.Height 10
                $fill = New-Object System.Drawing.SolidBrush((Get-Alpha $(if ($sel) { 70 } else { 32 }) $white)); $g.FillPath($fill, $p); $fill.Dispose(); $p.Dispose()
            }
            $code = $TabIcons[$pg.Text]
            $ix = if ($iconOnly) { $rc.X + 11 } else { $rc.X + 12 }
            if ($code -and $IconFontName) { $g.DrawImage((Get-IconBitmap $code $white), $ix, ($rc.Y + 8), 16, 16) }
            if (-not $iconOnly) {
                [System.Windows.Forms.TextRenderer]::DrawText($g, $pg.Text, $(if ($sel) { $TabFontSel } else { $TabFont }), (New-Object System.Drawing.Rectangle(($rc.X + 34), $rc.Y, ($w - 36), $rc.Height)), $(if ($sel) { $white } else { Get-Alpha 220 $white }),
                    [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, NoPadding')
            }
            $x += $w + 4
        }
        $script:hdrTabs = $rects; $script:hdrIconOnly = $iconOnly
        $navEnd = $x
    }
    $x = $r.Right - 14
    foreach ($chip in @($script:hdrChips)) {
        $w = [System.Windows.Forms.TextRenderer]::MeasureText($chip, $HeaderSub).Width + 14
        if ($x - $w -lt $navEnd + 10) { break }          # chip chỉ hiện khi còn chỗ
        $x -= $w
        $p = New-RoundRect $x 15 $w 26 13
        $fill = New-Object System.Drawing.SolidBrush((Get-Alpha 48 $white)); $g.FillPath($fill, $p); $fill.Dispose(); $p.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $chip, $HeaderSub, (New-Object System.Drawing.Rectangle([int]$x, 15, [int]$w, 26)), $white, [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine')
        $x -= 8
    }
})
$header.Add_Resize({ param($s, $e) $s.Invalidate() })
$script:hdrTabs = @(); $script:hdrHover = -1; $script:hdrIconOnly = $false
function Get-HeaderTabAt($pt) { for ($i = 0; $i -lt $script:hdrTabs.Count; $i++) { if ($script:hdrTabs[$i].Contains($pt)) { return $i } }; -1 }
$header.Add_MouseDown({ param($s, $e) $i = Get-HeaderTabAt $e.Location; if ($i -ge 0) { $tabs.SelectedIndex = $i } })
$header.Add_MouseMove({
    param($s, $e)
    $i = Get-HeaderTabAt $e.Location
    if ($i -ne $script:hdrHover) {
        $script:hdrHover = $i; $s.Cursor = $(if ($i -ge 0) { 'Hand' } else { 'Default' }); $s.Invalidate()
        $tipDoc.SetToolTip($s, $(if ($i -ge 0 -and $script:hdrIconOnly) { $tabs.TabPages[$i].Text } else { '' }))
    }
})
$header.Add_MouseLeave({ param($s, $e) $script:hdrHover = -1; $s.Invalidate() })
$form.Controls.Add($header)
$script:hdr = @{ Cpu = $null; Ram = $null; Apps = $null }
function Update-HeaderChips {
    $c = @()
    if ($null -ne $script:hdr.Cpu) { $c += "CPU $($script:hdr.Cpu)%" }
    if ($null -ne $script:hdr.Ram) { $c += "RAM $($script:hdr.Ram)%" }
    if ($null -ne $script:hdr.Apps) { $c += "▶ $($script:hdr.Apps) app đang chạy" }
    $script:hdrChips = $c
    $header.Invalidate()
}

# GroupBox vẽ thành thẻ bo góc: nền Card, viền mảnh, tiêu đề đậm có vạch màu nhấn
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
function Enable-Card($g) { Set-DoubleBuffered $g; $g.Add_Paint($cardPaint); $g.Add_Resize({ param($s, $e) $s.Invalidate() }) }

function New-Group($text, $y, $h, $parent = $pageMain) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text
    $g.Location = New-Object System.Drawing.Point(6, $y)
    $g.Size = New-Object System.Drawing.Size(510, $h)
    Enable-Card $g
    $parent.Controls.Add($g)
    $g
}

# Thanh đo bo tròn thay ProgressBar: Tag = phần trăm; Name 'load' = đổi màu khi cao (CPU / RAM), 'goal' = xanh lá
$meterPaint = {
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $g.Clear($s.Parent.BackColor)
    $v = [math]::Min(100, [math]::Max(0, [double]$s.Tag))
    $h = $s.Height - 1
    $p = New-RoundRect 0 0 ($s.Width - 1) $h ($h / 2)
    $b = New-Object System.Drawing.SolidBrush($Theme.Grid); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
    if ($v -le 0) { return }
    $c = if ($s.Name -eq 'goal') { $Theme.Ok } elseif ($s.Name -eq 'load' -and $v -ge 90) { $Theme.Err } elseif ($s.Name -eq 'load' -and $v -ge 75) { $Theme.Warn } else { $Theme.Accent }
    $w = [math]::Max($h, ($s.Width - 1) * $v / 100)
    $p = New-RoundRect 0 0 $w $h ($h / 2)
    $b = New-Object System.Drawing.SolidBrush($c); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
}
function New-Meter([string]$kind, $x, $y, $w, $h, $parent) {
    $m = New-Object System.Windows.Forms.Panel
    $m.Name = $kind; $m.Tag = 0
    $m.SetBounds($x, $y, $w, $h)
    Set-DoubleBuffered $m
    $m.Add_Paint($meterPaint)
    $parent.Controls.Add($m)
    $m
}
function Set-MeterValue($m, [double]$pct) { if ([double]$m.Tag -ne $pct) { $m.Tag = $pct; $m.Invalidate() } }

# Lớp phủ trong bảng: vòng xoay + chữ khi đang tải (kèm số giây), hoặc chỉ dòng thông báo giữa bảng
$OverlayFont = New-Object System.Drawing.Font('Segoe UI', 10)
$script:overlays = New-Object System.Collections.ArrayList
$overlayPaint = {
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $g.Clear($Theme.Surface)
    $st = $s.Tag
    $cx = [single]($s.Width / 2); $cy = [single]($s.Height / 2 - 14)
    $text = $st.Text
    if ($st.Spin) {
        $ms = ((Get-Date) - $st.Since).TotalMilliseconds
        $rc = New-Object System.Drawing.RectangleF(($cx - 15), ($cy - 15), 30, 30)
        $p = New-Object System.Drawing.Pen($Theme.Grid, 4); $g.DrawEllipse($p, $rc); $p.Dispose()
        $p = New-Object System.Drawing.Pen($Theme.Accent, 4); $p.StartCap = 'Round'; $p.EndCap = 'Round'
        $g.DrawArc($p, $rc, [single](($ms * 0.36) % 360), [single](70 + 40 * [math]::Sin($ms / 400))); $p.Dispose()
        $text += "  ·  $([int]($ms / 1000))s"
        $ty = [int]($cy + 26)
    } else { $ty = [int]($s.Height / 2 - 12) }
    [System.Windows.Forms.TextRenderer]::DrawText($g, $text, $OverlayFont, (New-Object System.Drawing.Rectangle(0, $ty, $s.Width, 24)), $(if ($st.Spin) { $Theme.Text } else { $Theme.Muted }),
        [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, EndEllipsis')
}
$overlayTimer = New-Object System.Windows.Forms.Timer
$overlayTimer.Interval = 40
$overlayTimer.Add_Tick({
    $any = $false
    foreach ($o in $script:overlays) { if ($o.Visible -and $o.Tag.Spin) { $o.Invalidate(); $any = $true } }
    if (-not $any) { $overlayTimer.Stop() }
})
function New-Overlay($parent) {
    $o = New-Object System.Windows.Forms.Panel
    $o.Dock = 'Fill'; $o.Visible = $false; $o.Tag = @{ Text = ''; Spin = $false; Since = Get-Date }
    Set-DoubleBuffered $o
    $o.Add_Paint($overlayPaint)
    $parent.Controls.Add($o); $o.BringToFront()
    [void]$script:overlays.Add($o)
    $o
}
function Set-Overlay($o, [string]$text, [bool]$spin = $false) {
    if ($spin -and -not ($o.Visible -and $o.Tag.Spin)) { $o.Tag.Since = Get-Date }
    $o.Tag.Text = $text; $o.Tag.Spin = $spin
    $o.Visible = [bool]$text; $o.Invalidate()
    if ($spin) { $overlayTimer.Start() }
}

# Khung bo góc chứa ô chữ không viền (khung chat, ô nhập AI): viền đổi màu nhấn khi ô bên trong có focus
$hostPaint = {
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $g.Clear($s.Parent.BackColor)
    $p = New-RoundRect 0 0 ($s.Width - 1) ($s.Height - 1) 10
    $b = New-Object System.Drawing.SolidBrush($Theme.Surface); $g.FillPath($b, $p); $b.Dispose()
    $pen = New-Object System.Drawing.Pen($(if ($s.ContainsFocus) { $Theme.Accent } else { $Theme.Border }), $(if ($s.ContainsFocus) { 1.6 } else { 1 })); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
}
function New-CardHost($x, $y, $w, $h, $parent) {
    $p = New-Object System.Windows.Forms.Panel
    $p.SetBounds($x, $y, $w, $h)
    Set-DoubleBuffered $p
    $p.Add_Paint($hostPaint); $p.Add_Resize({ param($s, $e) $s.Invalidate() })
    $parent.Controls.Add($p)
    $p
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
(New-Button 'Start' 12 218 120 $gStatus $svcStart).Tag = 'primary'
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
New-Button 'Khởi động' 12 26 110 $gUbuntu { Invoke-Busy "Đang khởi động $Distro..." { Start-Ubuntu }; Set-Status "$Distro đang chạy." } | Out-Null
New-Button 'Tắt' 128 26 84 $gUbuntu { Invoke-Busy "Đang tắt $Distro..." { Stop-Ubuntu }; Set-Status "Đã tắt $Distro." } | Out-Null
New-Button 'Mở terminal' 218 26 128 $gUbuntu { Open-UbuntuTerminal } | Out-Null
# Link tài liệu (mở trình duyệt)
function New-DocLink([string]$text, [string]$url, $parent, [int]$x, [int]$y) {
    $l = New-Object System.Windows.Forms.LinkLabel
    $l.Text = "$text ↗"; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Tag = $url
    $l.LinkBehavior = 'HoverUnderline'
    $l.Add_LinkClicked({ param($sender, $e) Start-Process $sender.Tag })
    $tipDoc.SetToolTip($l, $url)
    $parent.Controls.Add($l)
    $l
}
$tipDoc = New-Object System.Windows.Forms.ToolTip
$lnkWsl1 = New-DocLink 'Hướng dẫn cài WSL' 'https://learn.microsoft.com/vi-vn/windows/wsl/install' $gUbuntu 360 24
$lnkWsl2 = New-DocLink 'Lệnh WSL cơ bản' 'https://learn.microsoft.com/vi-vn/windows/wsl/basic-commands' $gUbuntu 360 44
if (-not $Distro) { foreach ($c in $gUbuntu.Controls) { if ($c -isnot [System.Windows.Forms.LinkLabel]) { $c.Enabled = $false } } }      # chưa cài WSL: vẫn bấm được link hướng dẫn cài

# PostgreSQL trong WSL (bật bằng port ở tab Cài đặt)
$gPg = New-Group $(if ($Distro -and $PgUbuntuPort -gt 0) { "PostgreSQL trong $Distro (localhost:$PgUbuntuPort, user admin)" } else { 'PostgreSQL trong WSL (chưa cấu hình - xem tab Cài đặt)' }) 352 70
$script:pgReady = [bool]($Distro -and $PgUbuntuPort -gt 0)
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

# ---------- Thu gọn nhóm PostgreSQL trong WSL (ít dùng) ----------
foreach ($c in $gPg.Controls) { $c.Enabled = $script:pgReady }
$script:pgCollapsed = [bool]$PanelConfig.pgCollapsed
$lnkPgExpand = New-Object System.Windows.Forms.LinkLabel
$lnkPgExpand.Text = "▸ $($gPg.Text)"; $lnkPgExpand.AutoSize = $true; $lnkPgExpand.LinkBehavior = 'HoverUnderline'
$lnkPgExpand.Add_LinkClicked({ Set-PgCollapsed $false })
$pageMain.Controls.Add($lnkPgExpand)
$lnkPgCollapse = New-Object System.Windows.Forms.LinkLabel
$lnkPgCollapse.Text = 'thu gọn ▴'; $lnkPgCollapse.AutoSize = $true; $lnkPgCollapse.LinkBehavior = 'HoverUnderline'
$lnkPgCollapse.Location = New-Object System.Drawing.Point(($gPg.Width - 76), 0); $lnkPgCollapse.Anchor = 'Top, Right'
$lnkPgCollapse.Add_LinkClicked({ Set-PgCollapsed $true })
$gPg.Controls.Add($lnkPgCollapse); $lnkPgCollapse.BringToFront()
function Set-PgCollapsed([bool]$c) {
    $script:pgCollapsed = $c
    $gPg.Visible = -not $c; $lnkPgExpand.Visible = $c
    $PanelConfig.pgCollapsed = $c; Save-PanelConfig $PanelConfig
    Update-MainLayout
}

# ---------- Mục tiêu hôm nay (góc phải tab Dịch vụ) ----------
# Lưu ở %APPDATA%\DevOpsPanel\goals.json: danh sách { date, text, done }, giữ 90 ngày
$GoalsFile = Join-Path $DataDir 'goals.json'
$script:goals = New-Object System.Collections.ArrayList
$script:goalsDay = ''
$script:goalsRendering = $false
function Get-Today { (Get-Date).ToString('yyyy-MM-dd') }
function Load-Goals {
    $script:goals.Clear()
    if (-not (Test-Path $GoalsFile)) { return }
    # PS 5.1: ConvertFrom-Json trả cả mảng như 1 object -> gán vào biến rồi foreach mới duyệt từng phần tử
    try { $data = Get-Content $GoalsFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($g in $data) { if ($g.text) { [void]$script:goals.Add([pscustomobject]@{ date = [string]$g.date; text = [string]$g.text; done = [bool]$g.done }) } } } catch { }
}
function Save-Goals {
    $cut = (Get-Date).AddDays(-90).ToString('yyyy-MM-dd')
    ConvertTo-Json -InputObject @($script:goals | Where-Object { $_.date -ge $cut }) -Depth 3 | Set-Content $GoalsFile -Encoding UTF8
}
function Get-TodayGoals { @($script:goals | Where-Object { $_.date -eq (Get-Today) }) }
# Mục tiêu chưa xong của ngày gần nhất trước hôm nay (để gợi ý mang sang)
function Get-CarryGoals {
    $prev = @($script:goals | Where-Object { $_.date -lt (Get-Today) } | Sort-Object date -Descending | Select-Object -First 1).date
    if (-not $prev) { return @() }
    @($script:goals | Where-Object { $_.date -eq $prev -and -not $_.done })
}
# Tên gọi thân thiện: tên trong git (Nguyen Co Duoc -> Duoc), không có thì tên đăng nhập Windows
$script:userName = [Environment]::UserName
if ($GitExe) { $gn = (Invoke-Git $env:USERPROFILE @('config', '--global', 'user.name') 3000).Out.Trim(); if ($gn) { $script:userName = ($gn -split '\s+')[-1] } }
function Get-Greeting {
    $h = (Get-Date).Hour
    if ($h -lt 11) { "☀ Chào buổi sáng, $($script:userName)!" } elseif ($h -lt 13) { "☀ Chào buổi trưa, $($script:userName)!" }
    elseif ($h -lt 18) { "☁ Chào buổi chiều, $($script:userName)!" } else { "☾ Chào buổi tối, $($script:userName)!" }
}

$gGoals = New-Object System.Windows.Forms.GroupBox
$gGoals.Text = 'Mục tiêu hôm nay'
$gGoals.Location = New-Object System.Drawing.Point(530, 10); $gGoals.Size = New-Object System.Drawing.Size(300, 480)
Enable-Card $gGoals
$pageMain.Controls.Add($gGoals)
$lblGreet = New-Object System.Windows.Forms.Label
$lblGreet.Location = New-Object System.Drawing.Point(12, 26); $lblGreet.Size = New-Object System.Drawing.Size(276, 24)
$lblGreet.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$lblGreet.AutoEllipsis = $true
$lblAsk = New-Object System.Windows.Forms.Label
$lblAsk.Location = New-Object System.Drawing.Point(12, 48); $lblAsk.Size = New-Object System.Drawing.Size(276, 40)
$txtGoal = New-Object System.Windows.Forms.TextBox
$txtGoal.Location = New-Object System.Drawing.Point(12, 92); $txtGoal.Size = New-Object System.Drawing.Size(206, 26)
$btnGoalAdd = New-Object System.Windows.Forms.Button
$btnGoalAdd.Text = 'Thêm'; $btnGoalAdd.Location = New-Object System.Drawing.Point(224, 89); $btnGoalAdd.Size = New-Object System.Drawing.Size(64, 30)
$clbGoals = New-Object System.Windows.Forms.CheckedListBox
$clbGoals.CheckOnClick = $true; $clbGoals.IntegralHeight = $false; $clbGoals.HorizontalScrollbar = $false
$clbGoals.Location = New-Object System.Drawing.Point(12, 126); $clbGoals.Size = New-Object System.Drawing.Size(276, 280)
$pbGoals = New-Meter 'goal' 12 414 276 8 $gGoals
$lblGoalProg = New-Object System.Windows.Forms.Label
$lblGoalProg.Location = New-Object System.Drawing.Point(12, 426); $lblGoalProg.Size = New-Object System.Drawing.Size(150, 22)
$lnkGoalAsk = New-Object System.Windows.Forms.LinkLabel
$lnkGoalAsk.Text = 'Đặt mục tiêu…'; $lnkGoalAsk.AutoSize = $true; $lnkGoalAsk.Location = New-Object System.Drawing.Point(190, 428)
$lnkGoalAsk.Add_LinkClicked({ Show-GoalsDialog })
$lnkGoalClear = New-Object System.Windows.Forms.LinkLabel
$lnkGoalClear.Text = 'Xoá mục đã xong'; $lnkGoalClear.AutoSize = $true; $lnkGoalClear.Location = New-Object System.Drawing.Point(12, 452)
$lnkGoalClear.Add_LinkClicked({ foreach ($g in @(Get-TodayGoals | Where-Object done)) { $script:goals.Remove($g) }; Save-Goals; Render-Goals })
$gGoals.Controls.AddRange(@($lblGreet, $lblAsk, $txtGoal, $btnGoalAdd, $clbGoals, $lblGoalProg, $lnkGoalAsk, $lnkGoalClear))
# neo theo kích thước ô (ô đổi cỡ theo cửa sổ)
foreach ($c in @($lblGreet, $lblAsk, $txtGoal)) { $c.Anchor = 'Top, Left, Right' }
$btnGoalAdd.Anchor = 'Top, Right'; $clbGoals.Anchor = 'Top, Bottom, Left, Right'
$pbGoals.Anchor = 'Bottom, Left, Right'; $lblGoalProg.Anchor = 'Bottom, Left'; $lnkGoalAsk.Anchor = 'Bottom, Right'; $lnkGoalClear.Anchor = 'Bottom, Left'

function Render-Goals {
    $script:goalsDay = Get-Today
    $items = @(Get-TodayGoals)
    $done = @($items | Where-Object done).Count
    $script:goalsRendering = $true
    $clbGoals.BeginUpdate(); $clbGoals.Items.Clear()
    foreach ($g in $items) { [void]$clbGoals.Items.Add($g.text, [bool]$g.done) }
    $clbGoals.EndUpdate()
    $script:goalsRendering = $false
    $lblGreet.Text = Get-Greeting
    $lblAsk.Text = if (-not $items.Count) { 'Hôm nay bạn muốn hoàn thành điều gì? Ghi vài mục tiêu nhỏ, xong thì tick nhé.' }
                   elseif ($done -eq $items.Count) { "✨ Tuyệt vời! Đã xong cả $($items.Count) mục tiêu hôm nay." }
                   else { "Còn $($items.Count - $done) mục tiêu - từng bước một, cố lên nhé!" }
    $lblAsk.ForeColor = if ($items.Count -and $done -eq $items.Count) { $Theme.Ok } else { $Theme.Muted }
    Set-MeterValue $pbGoals $(if ($items.Count) { 100 * $done / $items.Count } else { 0 })
    $lblGoalProg.Text = if ($items.Count) { "Đã xong $done/$($items.Count)" } else { '' }
    $lnkGoalClear.Visible = [bool]$done
}
function Add-Goal([string]$t) {
    $t = $t.Trim()
    if (-not $t) { return }
    if (@(Get-TodayGoals | Where-Object { $_.text -eq $t }).Count) { Set-Status 'Mục tiêu này đã có rồi.'; return }
    [void]$script:goals.Add([pscustomobject]@{ date = Get-Today; text = $t; done = $false })
    Save-Goals; Render-Goals
}
$btnGoalAdd.Add_Click({ Add-Goal $txtGoal.Text; $txtGoal.Clear(); [void]$txtGoal.Focus() })
$txtGoal.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; Add-Goal $txtGoal.Text; $txtGoal.Clear() } })
$clbGoals.Add_ItemCheck({
    param($sender, $e)
    if ($script:goalsRendering) { return }
    $g = @(Get-TodayGoals)[$e.Index]
    if (-not $g) { return }
    $g.done = ($e.NewValue -eq 'Checked')
    Save-Goals
    # ItemCheck chạy trước khi ô đổi trạng thái -> vẽ lại sau khi xong
    $form.BeginInvoke([Action]{ Render-Goals }) | Out-Null
    if ($g.done -and @(Get-TodayGoals | Where-Object { -not $_.done }).Count -eq 0) { Set-Status '✨ Đã hoàn thành tất cả mục tiêu hôm nay!' }
})
$clbGoals.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq 'Delete' -and $clbGoals.SelectedIndex -ge 0) { $g = @(Get-TodayGoals)[$clbGoals.SelectedIndex]; $script:goals.Remove($g); Save-Goals; Render-Goals } })
$goalMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$goalMenu.Items.Add('Sửa…', $null, {
    $i = $clbGoals.SelectedIndex; if ($i -lt 0) { return }
    $g = @(Get-TodayGoals)[$i]
    $t = [Microsoft.VisualBasic.Interaction]::InputBox('Sửa mục tiêu:', 'Mục tiêu hôm nay', $g.text)
    if ($t.Trim()) { $g.text = $t.Trim(); Save-Goals; Render-Goals }
})
[void]$goalMenu.Items.Add('Để sang ngày mai', $null, {
    $i = $clbGoals.SelectedIndex; if ($i -lt 0) { return }
    $g = @(Get-TodayGoals)[$i]; $g.date = (Get-Date).AddDays(1).ToString('yyyy-MM-dd'); Save-Goals; Render-Goals
    Set-Status "Đã để \"$($g.text)\" sang ngày mai."
})
[void]$goalMenu.Items.Add('Xoá', $null, { $i = $clbGoals.SelectedIndex; if ($i -ge 0) { $script:goals.Remove(@(Get-TodayGoals)[$i]); Save-Goals; Render-Goals } })
$clbGoals.ContextMenuStrip = $goalMenu
$clbGoals.Add_MouseDown({ param($sender, $e) if ($e.Button -eq 'Right') { $i = $clbGoals.IndexFromPoint($e.Location); if ($i -ge 0) { $clbGoals.SelectedIndex = $i } } })

# Hộp thoại "trợ lý" hỏi mục tiêu đầu ngày (mỗi dòng một mục, gợi ý mang sang việc hôm qua chưa xong)
function Show-GoalsDialog([switch]$Morning) {
    $carry = @(Get-CarryGoals | Where-Object { $t = $_.text; -not @(Get-TodayGoals | Where-Object { $_.text -eq $t }).Count })
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Trợ lý DevOps'; $d.Icon = $AppIcon; $d.Font = $font
    $d.Size = New-Object System.Drawing.Size(500, 430); $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'; $d.MinimizeBox = $false; $d.MaximizeBox = $false
    $l1 = New-Label (Get-Greeting) 18 16 450 $d
    $l1.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold); $l1.Height = 30
    $l2 = New-Label '' 18 50 450 $d
    $l2.Height = 64
    $l2.Text = "Hôm nay bạn sẽ làm gì? Ghi vài mục tiêu, mỗi dòng một mục - mình sẽ để ở góc phải tab Dịch vụ để bạn tick khi xong." +
               $(if ($carry.Count) { "`r`n(Đã điền sẵn $($carry.Count) việc hôm trước chưa xong.)" } else { '' })
    $l2.ForeColor = $Theme.Muted
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.AcceptsReturn = $true; $tb.ScrollBars = 'Vertical'
    $tb.Location = New-Object System.Drawing.Point(18, 118); $tb.Size = New-Object System.Drawing.Size(450, 192)
    $tb.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $tb.Text = ((@(Get-TodayGoals | ForEach-Object text) + @($carry | ForEach-Object text)) -join "`r`n")
    $d.Controls.Add($tb)
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'Hỏi mỗi ngày khi mở panel'; $chk.Checked = [bool]$PanelConfig.goalsAsk; $chk.AutoSize = $true
    $chk.Location = New-Object System.Drawing.Point(18, 322)
    $d.Controls.Add($chk)
    $bOk = New-Object System.Windows.Forms.Button; $bOk.Text = 'Lưu mục tiêu'; $bOk.DialogResult = 'OK'
    $bOk.Location = New-Object System.Drawing.Point(238, 346); $bOk.Size = New-Object System.Drawing.Size(130, 34)
    $bLater = New-Object System.Windows.Forms.Button; $bLater.Text = 'Để sau'; $bLater.DialogResult = 'Cancel'
    $bLater.Location = New-Object System.Drawing.Point(374, 346); $bLater.Size = New-Object System.Drawing.Size(94, 34)
    $d.Controls.AddRange(@($bOk, $bLater)); $d.CancelButton = $bLater
    Set-ControlTheme $d $Theme $Theme
    $d.Add_Shown({ param($sender, $e) Set-NativeTheme $sender; $t = $sender.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }; [void]$t.Focus(); $t.SelectionStart = $t.TextLength })
    $res = $d.ShowDialog($form)
    $PanelConfig.goalsAsk = $chk.Checked; $PanelConfig.goalsAskedOn = Get-Today; Save-PanelConfig $PanelConfig
    if ($res -ne 'OK') { return }
    # Thay danh sách hôm nay theo nội dung ô nhập, giữ trạng thái đã xong của mục trùng tên
    $old = @(Get-TodayGoals)
    foreach ($g in $old) { $script:goals.Remove($g) }
    foreach ($line in ($tb.Text -split "`r?`n" | ForEach-Object { $_.Trim() -replace '^[-*•]\s*', '' } | Where-Object { $_ } | Select-Object -Unique)) {
        $was = $old | Where-Object { $_.text -eq $line } | Select-Object -First 1
        [void]$script:goals.Add([pscustomobject]@{ date = Get-Today; text = $line; done = [bool]($was -and $was.done) })
    }
    Save-Goals; Render-Goals
    $n = @(Get-TodayGoals).Count
    if ($n) { Set-Status "Đã lưu $n mục tiêu hôm nay - chúc một ngày làm việc hiệu quả!" }
}
# Mở panel lần đầu trong ngày -> hỏi; chiều tối còn việc chưa xong -> nhắc nhẹ 1 lần ở khay
function Test-GoalsDaily {
    if ($script:goalsDay -ne (Get-Today)) { Render-Goals }
    if ($PanelConfig.goalsAsk -and $PanelConfig.goalsAskedOn -ne (Get-Today) -and -not @(Get-TodayGoals).Count -and $form.Visible) {
        $PanelConfig.goalsAskedOn = Get-Today; Save-PanelConfig $PanelConfig
        $tabs.SelectedTab = $pageMain
        Show-GoalsDialog -Morning
    }
    $left = @(Get-TodayGoals | Where-Object { -not $_.done })
    if ((Get-Date).Hour -ge 17 -and $left.Count -and $PanelConfig.goalsRemindedOn -ne (Get-Today)) {
        $PanelConfig.goalsRemindedOn = Get-Today; Save-PanelConfig $PanelConfig
        $tray.ShowBalloonTip(6000, 'Mục tiêu hôm nay', "Còn $($left.Count) mục tiêu chưa xong: " + (($left | Select-Object -First 3 | ForEach-Object text) -join ' · '), 'Info')
    }
}
Load-Goals
Render-Goals

# ---------- Bố cục tab Dịch vụ: các nhóm bên trái, Mục tiêu bên phải; bảng trạng thái giãn theo chiều cao ----------
function Update-MainLayout {
    $w = $pageMain.ClientSize.Width; $h = $pageMain.ClientSize.Height
    if ($w -lt 400 -or $h -lt 300) { return }
    $gw = [math]::Min(360, [math]::Max(260, [int]($w * 0.32)))
    $lw = $w - $gw - 20
    $pgH = if ($script:pgCollapsed) { 26 } else { 74 }
    $sh = [math]::Max(200, $h - 10 - (74 + $pgH + 74) - 8)
    $y = 10
    $gStatus.SetBounds(6, $y, $lw, $sh); $y += $sh + 4
    $gUbuntu.SetBounds(6, $y, $lw, 70); $y += 74
    if ($script:pgCollapsed) { $lnkPgExpand.Location = New-Object System.Drawing.Point(12, ($y + 3)) } else { $gPg.SetBounds(6, $y, $lw, 70) }
    $y += $pgH
    $gOther.SetBounds(6, $y, $lw, 70)
    $gGoals.SetBounds(($lw + 12), 10, $gw, ($h - 18))
}
$gPg.Visible = -not $script:pgCollapsed; $lnkPgExpand.Visible = $script:pgCollapsed

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
$statusLbl.ForeColor = $Theme.Muted
$form.Controls.Add($statusLbl)
function Set-Status([string]$t) { $statusLbl.Text = $t }
$lnkUpdate = New-Object System.Windows.Forms.LinkLabel
$lnkUpdate.AutoSize = $true; $lnkUpdate.Visible = $false; $lnkUpdate.LinkBehavior = 'HoverUnderline'
$lnkUpdate.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$lnkUpdate.Location = New-Object System.Drawing.Point(330, 582)
$lnkUpdate.Add_LinkClicked({ Show-UpdateDialog })
$form.Controls.Add($lnkUpdate); $lnkUpdate.BringToFront()

function Update-Status {
    foreach ($item in $list.Items) {
        $ok = Get-ComponentState $item.Tag
        $sub = $item.SubItems[2]
        if ($ok) { $sub.Text = '● Đang chạy'; $sub.ForeColor = $Theme.Ok }
        else     { $sub.Text = '○ Đã dừng';  $sub.ForeColor = $Theme.Err }
    }
    if ($script:lvSort) { Sort-ListView $list }
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
    New-Label $m[1] 12 $y 170 $pageHealth -Bold | Out-Null
    $bar = New-Meter $(if ($m[0] -eq 'bat') { 'plain' } else { 'load' }) 185 ($y + 6) 180 10 $pageHealth
    $val = New-Label '...' 375 $y 140 $pageHealth
    $meters[$m[0]] = @{ Bar = $bar; Label = $val }
    $y += 28
}
$lblInfo = New-Label '' 12 $y 500 $pageHealth
$lblInfo.ForeColor = $Theme.Muted

# Biểu đồ CPU (xanh) / RAM (cam) 60 mẫu gần nhất
$chart = New-Object System.Windows.Forms.Panel
$chart.Location = New-Object System.Drawing.Point(12, ($y + 26))
$chart.Size = New-Object System.Drawing.Size(498, 110)
$chart.BackColor = $Theme.ChartBg
Set-DoubleBuffered $chart
$pageHealth.Controls.Add($chart)
$histCpu = New-Object System.Collections.Generic.List[int]
$histRam = New-Object System.Collections.Generic.List[int]
$HistMax = 60

$chart.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $w = $chart.ClientSize.Width; $h = $chart.ClientSize.Height
    $grid = New-Object System.Drawing.Pen($Theme.Grid)
    foreach ($p in 25, 50, 75) { $yy = $h - $h * $p / 100; $g.DrawLine($grid, 0, $yy, $w, $yy) }
    $f = New-Object System.Drawing.Font('Segoe UI', 8)
    $g.DrawString('CPU', $f, (New-Object System.Drawing.SolidBrush($Theme.Info)), 4, 2)
    $g.DrawString('RAM', $f, (New-Object System.Drawing.SolidBrush($Theme.Warn)), 36, 2)
    $g.DrawString('3 phút gần nhất', $f, (New-Object System.Drawing.SolidBrush($Theme.Muted)), ($w - 90), 2)
    foreach ($series in @(@($histCpu, $Theme.Info), @($histRam, $Theme.Warn))) {
        $data = $series[0]
        if ($data.Count -lt 2) { continue }
        $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
        $step = $w / ($HistMax - 1)
        $offset = $HistMax - $data.Count
        for ($i = 0; $i -lt $data.Count; $i++) {
            $pts.Add([System.Drawing.PointF]::new(($offset + $i) * $step, $h - 2 - ($h - 4) * $data[$i] / 100))
        }
        $area = New-Object System.Drawing.Drawing2D.GraphicsPath
        $area.AddLines($pts.ToArray())
        $area.AddLine($pts[$pts.Count - 1].X, $h, $pts[0].X, $h); $area.CloseFigure()
        $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $w, ($h + 1))), (Get-Alpha 70 $series[1]), (Get-Alpha 0 $series[1]), [single]90)
        $g.FillPath($fill, $area); $fill.Dispose(); $area.Dispose()
        $pen = New-Object System.Drawing.Pen($series[1], 2); $pen.LineJoin = 'Round'
        $g.DrawLines($pen, $pts.ToArray()); $pen.Dispose()
    }
})

$lblWarn = New-Label '' 12 ($y + 142) 500 $pageHealth -Bold
$lblWarn.ForeColor = $Theme.Err

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
    Set-MeterValue $meters[$key].Bar $pct
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
    if ($script:lvSort) { Sort-ListView $lv }
}

# Thu thập dữ liệu ở runspace nền để giao diện không bị đơ (mỗi lần đo ~1.5s)
# Fast = đang mở tab Sức khỏe -> đo mỗi 3s; ngược lại 60s/lần (chỉ để cảnh báo ở khay)
$healthSync = [hashtable]::Synchronized(@{ Data = $null; Seq = 0; Run = $true; Fast = $false })
$healthRs = [runspacefactory]::CreateRunspace()
$healthRs.Open()
$healthRs.SessionStateProxy.SetVariable('sync', $healthSync)
$healthRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1')); $healthRs.SessionStateProxy.SetVariable('CoreShared', $CoreShared)
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
    $lblWarn.ForeColor = if ($h.Warnings.Count) { $Theme.Err } else { $Theme.Ok }
    if ($tabs.SelectedTab -eq $pageHealth -and $form.Visible) {
        Fill-TopList $lvCpu $h.TopCpu
        Fill-TopList $lvRam $h.TopRam
        $chart.Invalidate()
    }

    # Cảnh báo mới -> balloon ở khay hệ thống (mỗi cảnh báo báo 1 lần cho tới khi hết)
    $tray.Text = ("DevOps - CPU $($h.Cpu)% RAM $($h.RamPct)%")
    $script:hdr.Cpu = $h.Cpu; $script:hdr.Ram = $h.RamPct; Update-HeaderChips
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
$lblK3s = New-Label 'Đang tải...' 12 12 200 $pageK3s -Bold
$lblK3s.AutoEllipsis = $true
$flK3s = New-Object System.Windows.Forms.FlowLayoutPanel
$flK3s.Location = New-Object System.Drawing.Point(218, 10); $flK3s.Size = New-Object System.Drawing.Size(292, 24); $flK3s.WrapContents = $false
$flK3s.FlowDirection = 'RightToLeft'
$pageK3s.Controls.Add($flK3s)
foreach ($d in @(@('k9s', 'https://k9scli.io/topics/commands/'), @('kubectl', 'https://kubernetes.io/vi/docs/reference/kubectl/cheatsheet/'), @('Tài liệu K3s', 'https://docs.k3s.io/'), @('Cài K3s', 'https://docs.k3s.io/quick-start'))) {
    $l = New-DocLink $d[0] $d[1] $flK3s 0 0
    $l.Margin = New-Object System.Windows.Forms.Padding(8, 3, 0, 0)
}
# Dòng mạng: IP WSL hiện tại / IP k3s đang giữ / ingress - đổi Wi-Fi làm hai IP lệch nhau thì ingress chết
$lblK3sNet = New-Label '' 12 44 370 $pageK3s
$lblK3sNet.AutoEllipsis = $true
$btnK3sFix = New-Button 'Sửa mạng K3s' 390 38 120 $pageK3s {
    $ok = [System.Windows.Forms.MessageBox]::Show("Khởi động lại k3s để nhận IP mới rồi tạo lại pod ingress?`n`nCác app trong k3s sẽ gián đoạn khoảng 30 giây.", 'K3s', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { return }
    $btnK3sFix.Enabled = $false
    Set-Status 'Đang khởi động lại k3s và ingress (khoảng 30 giây)...'
    Start-CoreAsync 'Repair-K3sNetwork' @{} {
        param($r)
        $btnK3sFix.Enabled = $true
        Set-Status $(if ($r.Ok) { 'Đã khởi động lại k3s và ingress. ' + ([string]$r.Value -replace '\s+', ' ') } else { "Lỗi sửa mạng K3s: $($r.Value)" })
        $k3sSync.Kick = $true
    }
}
$lvPods = New-Object System.Windows.Forms.ListView
$lvPods.View = 'Details'; $lvPods.FullRowSelect = $true; $lvPods.MultiSelect = $false; $lvPods.HideSelection = $false
$lvPods.Location = New-Object System.Drawing.Point(12, 74)
$lvPods.Size = New-Object System.Drawing.Size(498, 346)
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
$k3sRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1')); $k3sRs.SessionStateProxy.SetVariable('CoreShared', $CoreShared)
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
        $lblK3s.Text = "K3s không chạy: $($k.Reason) (bật ở tab Dịch vụ, chưa cài thì xem link Cài K3s)"
        $lblK3s.ForeColor = $Theme.Err
        $lblK3sNet.Text = ''
        $lvPods.Items.Clear(); return
    }
    $node = $k.Nodes | Select-Object -First 1
    $lblK3s.Text = "Node $($node.Name): $($node.Status) · $($node.Version) · Pod OK $($k.Healthy)/$($k.Total)" + $(if ($k.Unhealthy) { " · $($k.Unhealthy) pod lỗi" } else { '' })
    $lblK3s.ForeColor = if ($k.Unhealthy) { $Theme.Err } else { $Theme.Ok }

    $n = $k.Network; $ing = $n.Ingress
    $ingText = if (-not $ing) { 'không có ingress' }
               else { "ingress $($ing.Status)" + $(if ($ing.Port) { " · cổng $($ing.Port) " + $(if ($ing.Open) { 'mở' } else { 'ĐÓNG' }) } else { '' }) }
    $bad = $n.Mismatch -or ($ing -and $ing.Port -and -not $ing.Open)
    $lblK3sNet.Text = "IP WSL $(if ($n.WslIp) { $n.WslIp } else { '?' }) · IP k3s $(if ($n.NodeIp) { $n.NodeIp } else { '?' })" +
        $(if ($n.Mismatch) { ' (LỆCH - đã đổi mạng)' } else { '' }) + " · $ingText"
    $lblK3sNet.ForeColor = if ($bad) { $Theme.Err } else { $Theme.Muted }
    $tipDoc.SetToolTip($lblK3sNet, $(if ($bad) { "Đổi Wi-Fi / khởi động lại máy làm IP đổi nhưng k3s vẫn giữ IP cũ -> ingress khởi động lại liên tục, app gọi vào cổng $($ing.Port) bị từ chối. Bấm 'Sửa mạng K3s'." } else { 'IP WSL và IP k3s khớp nhau.' }))

    $sel = if ($lvPods.SelectedItems.Count) { $lvPods.SelectedItems[0].Tag.Name } else { $null }
    $lvPods.BeginUpdate(); $lvPods.Items.Clear()
    foreach ($p in $k.Pods) {
        $it = New-Object System.Windows.Forms.ListViewItem($p.Namespace)
        $it.UseItemStyleForSubItems = $false
        foreach ($v in @($p.Name, $p.Status, $p.Ready, [string]$p.Restarts, $p.Age)) { [void]$it.SubItems.Add($v) }
        $it.SubItems[2].ForeColor = if ($p.Healthy) { $Theme.Ok } else { $Theme.Err }
        $it.Tag = $p
        [void]$lvPods.Items.Add($it)
        if ($p.Name -eq $sel) { $it.Selected = $true }
    }
    $lvPods.EndUpdate()
    Sort-ListView $lvPods
    Set-Status ("K3s cập nhật lúc " + (Get-Date).ToString('HH:mm:ss'))
}

# ---------- Tab Ứng dụng (backend/frontend dev) ----------
$lblApps = New-Label 'Đang quét các port...' 12 12 160 $pageApps -Bold
$lblApps.AutoEllipsis = $true
# Ô tìm kiếm: lọc theo tên / nhóm / loại / port / trạng thái, nhiều từ = phải khớp tất cả, gõ không dấu cũng được
$lblSearch = New-Label 'Tìm' 280 12 30 $pageApps
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(310, 9); $txtSearch.Size = New-Object System.Drawing.Size(200, 26)
$pageApps.Controls.Add($txtSearch)
$tipSearch = New-Object System.Windows.Forms.ToolTip
$tipSearch.SetToolTip($txtSearch, "Tìm theo tên, nhóm, loại, port hoặc trạng thái (Ctrl+F, Esc để xoá)`nVí dụ: hrm · frontend · đang chạy · dung · lỗi · 7003`nNhiều từ = phải khớp tất cả; gõ không dấu cũng được.")
$lvApps = New-Object System.Windows.Forms.ListView
$lvApps.View = 'Details'; $lvApps.FullRowSelect = $true; $lvApps.MultiSelect = $true; $lvApps.HideSelection = $false; $lvApps.ShowItemToolTips = $true
$lvApps.Location = New-Object System.Drawing.Point(12, 40)
$lvApps.Size = New-Object System.Drawing.Size(498, 258)
$AppsCols = @(@('Nhóm', 110), @('Ứng dụng', 150), @('Loại', 70), @('Port', 50), @('Trạng thái', 190), @('PID', 60), @('CPU', 55), @('RAM', 70), @('Phản hồi', 95))
# 3 cột cuối (CPU / RAM / Phản hồi) là tuỳ chọn: chuột phải -> "Hiện CPU / RAM / Phản hồi"
$script:showStats = [bool]$PanelConfig.showStats
foreach ($col in $AppsCols[0..$(if ($script:showStats) { 8 } else { 5 })]) { [void]$lvApps.Columns.Add($col[0], $col[1]) }
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
        if ($act -in 'start', 'startseq') { $apps = @($apps | Where-Object { -not $_.Running -and -not $script:appsPending[$_.Id] }) }
        if (-not $apps.Count) { Set-Status 'Các app đã chọn đều đang chạy hoặc đang khởi động.'; return }
    }
    if ($act -eq 'stop') {
        $apps = @($apps | Where-Object { $_.Running -or $_.Known })
        if (-not $apps.Count) { Set-Status 'Không có app nào đang chạy để dừng.'; return }
    }
    $names = ($apps | Select-Object -First 12 | ForEach-Object { "  • $($_.Name)" }) -join "`n"
    if ($apps.Count -gt 12) { $names += "`n  … và $($apps.Count - 12) app khác" }
    $verb = @{ start = 'Khởi động'; startseq = 'Khởi động theo thứ tự'; stop = 'Dừng'; restart = 'Khởi động lại' }[$act]
    if ($act -notin 'start', 'startseq' -and [System.Windows.Forms.MessageBox]::Show("$verb $($apps.Count) ứng dụng?`n`n$names", 'Ứng dụng', 'YesNo', 'Question') -ne 'Yes') { return }

    $script:appsBatchBusy = $true
    $form.Cursor = 'AppStarting'
    Set-Status "$verb $($apps.Count) ứng dụng..."
    foreach ($a in $apps) {
        $script:appsPending[$a.Id] = @{ Act = $act; Since = Get-Date; DoneAt = $null; Tool = -not $a.Port }
        if ($act -in 'stop', 'restart') { $script:expectStop[$a.Id] = Get-Date }
        $script:appsFailed.Remove($a.Id)
    }
    Update-AppsPending
    $code = {
        $ErrorActionPreference = 'SilentlyContinue'     # taskkill 2>&1 khi EAP=Stop bị coi là lỗi; lỗi thật vẫn throw
        $msgs = New-Object System.Collections.ArrayList
        if ($p.Act -eq 'startseq') { , @(Start-DevAppsOrdered $p.Ids); return }   # tool -> backend -> BFF -> frontend
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
$PendingText = @{ start = 'Đang khởi động'; startseq = 'Đang khởi động'; restart = 'Đang khởi động lại'; stop = 'Đang dừng' }
$script:expectStop = @{}     # id -> lúc người dùng bấm dừng: app tắt sau đó không phải sập
$script:restartLog = @{}     # id -> các lần tự khởi động lại (giới hạn 3 lần / 10 phút)
$script:restartQueue = New-Object System.Collections.ArrayList
$StartTimeoutSec = 180

function Get-AppStateCell($a) {
    $pd = $script:appsPending[$a.Id]
    if ($pd) {
        $sec = [int]((Get-Date) - $pd.Since).TotalSeconds
        $color = if ($pd.Act -eq 'stop') { $Theme.Warn } else { $Theme.Info }
        return @{ Text = "$($SpinFrames[$script:spinIdx % 4]) $($PendingText[$pd.Act])… ${sec}s"; Color = $color; Tip = '' }
    }
    if ($script:appsFailed.ContainsKey($a.Id) -and -not $a.Running) {
        return @{ Text = '✗ Lỗi - xem log'; Color = $Theme.Err; Tip = $script:appsFailed[$a.Id] }
    }
    if ($a.Running) { return @{ Text = '● Đang chạy' + $(if ($a.AutoRestart) { '  ↻' } else { '' }); Color = $Theme.Ok; Tip = $(if ($a.AutoRestart) { 'Tự khởi động lại khi sập' } else { '' }) } }
    if ($a.Busy)    { return @{ Text = "⚠ Port bị $($a.Process) chiếm"; Color = $Theme.Warn; Tip = '' } }
    @{ Text = '○ Đã dừng'; Color = $Theme.Gray; Tip = '' }
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
            if (-not $pd.Tool -and -not $a.Running) { $script:appsFailed[$id] = 'Tiến trình đã thoát trước khi app nghe port - xem log'; Show-AppAlert "$($a.Name) khởi động lỗi" $script:appsFailed[$id] }
            continue
        }
        if (-not $pd.Tool -and ((Get-Date) - $pd.DoneAt).TotalSeconds -gt $StartTimeoutSec) {
            $script:appsPending.Remove($id)
            $script:appsFailed[$id] = "Sau $StartTimeoutSec giây vẫn chưa thấy app nghe port $($a.Port) - xem log"; Show-AppAlert "$($a.Name) chưa lên" $script:appsFailed[$id]
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

(New-Button 'Start' 12 304 62 $pageApps { Invoke-AppsBatch 'start' (Get-SelectedApps) }).Tag = 'primary'
New-Button 'Stop' 78 304 62 $pageApps { Invoke-AppsBatch 'stop' (Get-SelectedApps) } | Out-Null
New-Button 'Restart' 144 304 68 $pageApps { Invoke-AppsBatch 'restart' (Get-SelectedApps) } | Out-Null
New-Button 'Mở web' 216 304 68 $pageApps { $s = Get-SelectedApps; if ($s) { Open-AppWeb $s } } | Out-Null
New-Button 'Xem log' 288 304 68 $pageApps { $s = Get-SelectedApps; if ($s) { Open-AppLog $s } } | Out-Null
New-Button 'Gỡ' 360 304 50 $pageApps { Remove-PanelApps (Get-SelectedApps) } | Out-Null
New-Button 'Quét project' 414 304 96 $pageApps { Invoke-ProjectScan } | Out-Null

# Gỡ app khỏi panel (chỉ bỏ khỏi danh mục, không xoá code). Có thể khôi phục lại.
function Remove-PanelApps($apps) {
    $apps = @($apps)
    if (-not $apps.Count) { Set-Status 'Hãy chọn ứng dụng cần gỡ.'; return }
    $known = @($apps | Where-Object Known)
    if (-not $known.Count) { Set-Status 'App ngoài danh mục (nhóm "Khác") không cần gỡ - nó tự biến mất khi tắt.'; return }
    if ($script:appsBatchBusy) { Set-Status 'Lệnh trước vẫn đang chạy, chờ chút rồi thử lại.'; return }
    $names = ($known | Select-Object -First 12 | ForEach-Object { "  • $($_.Name)" }) -join "`n"
    if ($known.Count -gt 12) { $names += "`n  … và $($known.Count - 12) app khác" }
    $running = @($known | Where-Object { $_.Running -or $script:appsPending[$_.Id] })
    $msg = "Gỡ $($known.Count) ứng dụng khỏi panel?`n`n$names`n`nChỉ bỏ khỏi danh sách, KHÔNG xoá code. Quét project sẽ bỏ qua các app này; khôi phục được bằng chuột phải → Khôi phục app đã gỡ."
    $stop = $false
    if ($running.Count) {
        $ans = [System.Windows.Forms.MessageBox]::Show("$msg`n`n$($running.Count) app đang chạy - dừng luôn trước khi gỡ?`n  Yes = dừng rồi gỡ   ·   No = gỡ, để app chạy tiếp", 'Gỡ ứng dụng', 'YesNoCancel', 'Warning')
        if ($ans -eq 'Cancel') { return }
        $stop = ($ans -eq 'Yes')
    } elseif ([System.Windows.Forms.MessageBox]::Show($msg, 'Gỡ ứng dụng', 'YesNo', 'Question') -ne 'Yes') { return }

    $ids = @($known.Id)
    foreach ($id in $ids) { $script:appsPending.Remove($id); $script:appsFailed.Remove($id); $script:expectStop[$id] = Get-Date }
    if ($ids -contains $script:gitFor) { $script:gitFor = $null; $script:gitInfo = $null; $lblGit1.Text = 'Chọn một ứng dụng để xem git.'; $lblGit2.Text = ''; $lblGit3.Text = ''; $cbBranch.Items.Clear() }
    $script:appsBatchBusy = $true
    $form.Cursor = 'AppStarting'
    Set-Status "Đang gỡ $($ids.Count) ứng dụng..."
    $code = {
        $ErrorActionPreference = 'SilentlyContinue'
        if ($p.Stop) { foreach ($id in $p.StopIds) { try { Stop-DevApp $id | Out-Null } catch { } } }
        $ErrorActionPreference = 'Stop'
        Remove-DevApps $p.Ids
    }.ToString()
    Start-CoreAsync $code @{ Ids = $ids; Stop = $stop; StopIds = @($running.Id) } {
        param($r, $ctx)
        $script:appsBatchBusy = $false
        $form.Cursor = 'Default'
        Set-Status $(if ($r.Ok) { [string]$r.Value } else { "Lỗi khi gỡ: $($r.Value)" })
        $appsSync.Kick = $true
    }
}

function Show-RestoreAppsDialog {
    $removed = @((Get-AppsConfig).Removed)
    if (-not $removed.Count) { Set-Status 'Chưa có app nào bị gỡ.'; return }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Khôi phục app đã gỡ'; $dlg.Font = $font; $dlg.Icon = $AppIcon
    $dlg.Size = New-Object System.Drawing.Size(560, 380); $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false; $dlg.FormBorderStyle = 'Sizable'; $dlg.MinimumSize = $dlg.Size
    $lst = New-Object System.Windows.Forms.CheckedListBox
    $lst.CheckOnClick = $true; $lst.IntegralHeight = $false
    $lst.Location = New-Object System.Drawing.Point(12, 12); $lst.Size = New-Object System.Drawing.Size(520, 270)
    $lst.Anchor = 'Top, Bottom, Left, Right'
    foreach ($a in $removed) { [void]$lst.Items.Add(("{0}  ·  {1}  ·  {2}" -f $a.group, $a.name, $a.dir)) }
    $dlg.Controls.Add($lst)
    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = 'Chọn tất cả'; $btnAll.Location = New-Object System.Drawing.Point(12, 292); $btnAll.Size = New-Object System.Drawing.Size(120, 32); $btnAll.Anchor = 'Bottom, Left'
    $btnAll.Add_Click({ for ($i = 0; $i -lt $lst.Items.Count; $i++) { $lst.SetItemChecked($i, $true) } }.GetNewClosure())
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Khôi phục'; $btnOk.DialogResult = 'OK'; $btnOk.Location = New-Object System.Drawing.Point(316, 292); $btnOk.Size = New-Object System.Drawing.Size(110, 32); $btnOk.Anchor = 'Bottom, Right'
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Đóng'; $btnCancel.DialogResult = 'Cancel'; $btnCancel.Location = New-Object System.Drawing.Point(432, 292); $btnCancel.Size = New-Object System.Drawing.Size(100, 32); $btnCancel.Anchor = 'Bottom, Right'
    $dlg.Controls.AddRange(@($btnAll, $btnOk, $btnCancel))
    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    Set-ControlTheme $dlg $Theme $Theme
    $dlg.Add_Shown({ param($s, $e) Set-NativeTheme $s })
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    $ids = @($lst.CheckedIndices | ForEach-Object { $removed[$_].id })
    if (-not $ids.Count) { Set-Status 'Chưa tick app nào để khôi phục.'; return }
    try { Set-Status (Restore-DevApps $ids) } catch { Set-Status "Lỗi: $($_.Exception.Message)" }
    $appsSync.Kick = $true
}

# ---------- Bộ app (profile) ----------
Add-Type -AssemblyName Microsoft.VisualBasic
function New-ThemedMenuItem([string]$text, [scriptblock]$onClick) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $mi.ForeColor = $Theme.Text
    if ($onClick) { $mi.Add_Click($onClick) }
    $mi
}
function Get-AppsByIds([string[]]$ids) { @($script:appsData | Where-Object { $ids -contains $_.Id }) }
# Dựng menu "Bộ app" (dùng cho nút "Bộ app ▾" và menu chuột phải)
function Build-ProfileMenu($items, $owner) {
    $items.Clear()
    $profiles = @((Get-AppsConfig).Profiles)
    foreach ($p in $profiles) {
        $ids = @($p.ids); $name = [string]$p.name
        $apps = @(Get-AppsByIds $ids)
        $run = @($apps | Where-Object Running).Count
        $mi = New-ThemedMenuItem "$name   ($run/$($apps.Count) đang chạy)" $null
        $mi.DropDown.Renderer = $owner.Renderer; $mi.DropDown.BackColor = $Theme.Surface
        # Handler dùng $s.Tag (không dùng closure: closure không gọi được hàm của panel)
        $ctx = @{ Ids = $ids; Name = $name }
        $sub = @(
            (New-ThemedMenuItem 'Start theo thứ tự (tool → backend → BFF → frontend)' { param($s, $e) Invoke-AppsBatch 'startseq' (Get-AppsByIds $s.Tag.Ids) }),
            (New-ThemedMenuItem 'Start tất cả cùng lúc' { param($s, $e) Invoke-AppsBatch 'start' (Get-AppsByIds $s.Tag.Ids) }),
            (New-ThemedMenuItem 'Stop cả bộ' { param($s, $e) Invoke-AppsBatch 'stop' @(Get-AppsByIds $s.Tag.Ids | Where-Object Running) }),
            (New-ThemedMenuItem 'Chọn các app trong bộ' { param($s, $e) foreach ($it in $lvApps.Items) { $it.Selected = ($s.Tag.Ids -contains $it.Tag.Id) } }),
            (New-Object System.Windows.Forms.ToolStripSeparator),
            (New-ThemedMenuItem 'Thay bằng các app đang chọn' { param($s, $e) $sa = @(Get-SelectedApps | Where-Object Known); if ($sa.Count) { Set-Status (Save-AppsProfile $s.Tag.Name @($sa.Id)) } else { Set-Status 'Hãy chọn app trước.' } }),
            (New-ThemedMenuItem 'Xoá bộ này' { param($s, $e) if ([System.Windows.Forms.MessageBox]::Show("Xoá bộ '$($s.Tag.Name)'? (không ảnh hưởng app)", 'Bộ app', 'YesNo', 'Question') -eq 'Yes') { Set-Status (Remove-AppsProfile $s.Tag.Name) } })
        )
        foreach ($x in $sub) { $x.Tag = $ctx }
        $sub[0].Font = New-Object System.Drawing.Font($owner.Font, [System.Drawing.FontStyle]::Bold)
        $mi.DropDownItems.AddRange($sub)
        [void]$items.Add($mi)
    }
    if ($profiles.Count) { [void]$items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }
    $save = New-ThemedMenuItem 'Lưu các app đang chọn thành bộ mới…' {
        $s = @(Get-SelectedApps | Where-Object Known)
        if (-not $s.Count) { Set-Status 'Hãy chọn các app muốn gom thành bộ (Ctrl/Shift + click) rồi lưu.'; return }
        $name = [Microsoft.VisualBasic.Interaction]::InputBox("Tên bộ cho $($s.Count) app:`n$((@($s.Name)) -join ', ')", 'Lưu bộ app', $(if ($s[0].Group) { "$($s[0].Group) đầy đủ" } else { 'Bộ mới' }))
        if ($name.Trim()) { try { Set-Status (Save-AppsProfile $name @($s.Id)) } catch { Set-Status "Lỗi: $($_.Exception.Message)" } }
    }
    [void]$items.Add($save)
    Add-MenuIcons $items
}
$profMenu = New-Object System.Windows.Forms.ContextMenuStrip
$profMenu.Add_Opening({ Build-ProfileMenu $profMenu.Items $profMenu })
$btnProfiles = New-Button 'Bộ app ▾' 262 8 80 $pageApps { $profMenu.Show($btnProfiles, (New-Object System.Drawing.Point(0, $btnProfiles.Height))) }
$btnProfiles.Height = 26

# ---------- Cảnh báo ở khay + theo dõi app sập ----------
function Show-AppAlert([string]$title, [string]$text) {
    try { $tray.ShowBalloonTip(6000, $title, $text, 'Warning') } catch { }
}
# So sánh 2 lần quét: app đang chạy -> tắt mà không do người dùng bấm dừng = sập
function Watch-AppsCrash($old, $new) {
    if (-not $old) { return }
    $now = Get-Date
    foreach ($o in @($old | Where-Object { $_.Running -and $_.Known })) {
        $n = $new | Where-Object Id -eq $o.Id | Select-Object -First 1
        if (-not $n -or $n.Running -or $script:appsPending[$o.Id]) { continue }
        $exp = $script:expectStop[$o.Id]
        if ($exp -and ($now - $exp).TotalSeconds -lt 120) { continue }
        if ($o.Type -eq 'tool') { continue }                 # tool chạy xong tự thoát
        $script:appsFailed[$o.Id] = "Tắt bất ngờ lúc $($now.ToString('HH:mm:ss')) - xem log"
        if ($n.AutoRestart) {
            $hist = @($script:restartLog[$o.Id] | Where-Object { $_ -and ($now - $_).TotalMinutes -lt 10 })
            if ($hist.Count -lt 3) {
                $script:restartLog[$o.Id] = @($hist) + $now
                if (-not $script:restartQueue.Contains($o.Id)) { [void]$script:restartQueue.Add($o.Id) }
                Show-AppAlert "$($o.Name) bị sập" "Đang tự khởi động lại (lần $($hist.Count + 1)/3 trong 10 phút)."
                continue
            }
            Show-AppAlert "$($o.Name) sập liên tục" 'Đã tự khởi động lại 3 lần trong 10 phút - dừng tự khởi động lại, hãy xem log.'
            continue
        }
        Show-AppAlert "$($o.Name) đã tắt" 'App đang chạy thì tắt (sập hoặc bị tắt từ ngoài panel). Xem log ở tab Ứng dụng.'
    }
}

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
$miAppAuto = $appsMenu.Items.Add('Tự khởi động lại khi sập', $null, {
    $sel = @(Get-SelectedApps | Where-Object Known)
    if (-not $sel.Count) { return }
    $on = -not (@($sel | Where-Object AutoRestart).Count -eq $sel.Count)
    try { Set-DevAppAutoRestart @($sel.Id) $on; Set-Status ("Tự khởi động lại khi sập: " + $(if ($on) { 'BẬT' } else { 'TẮT' }) + " cho $($sel.Count) app") } catch { Set-Status "Lỗi: $($_.Exception.Message)" }
    $appsSync.Kick = $true
})
$miAppFreePort = $appsMenu.Items.Add('Giải phóng port', $null, {
    $a = @(Get-SelectedApps)[0]
    if (-not $a -or -not $a.Busy) { return }
    if ([System.Windows.Forms.MessageBox]::Show("Port $($a.Port) đang bị $($a.Process) (PID $($a.BusyPid)) chiếm nên $($a.Name) không chạy được.`n`nTắt tiến trình $($a.Process) (cả các tiến trình con)?", 'Giải phóng port', 'YesNo', 'Warning') -ne 'Yes') { return }
    try { Set-Status (Stop-PortOwner $a.Port) } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Giải phóng port', 'OK', 'Warning') | Out-Null }
    $appsSync.Kick = $true
})
$miAppProfiles = New-Object System.Windows.Forms.ToolStripMenuItem('Bộ app')
[void]$appsMenu.Items.Add($miAppProfiles)
$miAppGit = $appsMenu.Items.Add('Mở trong tab Git (nhánh, log, merge request)', $null, { $a = @(Get-SelectedApps)[0]; if ($a) { Show-GitTabFor $a } })
[void]$appsMenu.Items.Add('-')
$script:menuGroup = $null
function Get-GroupApps { @($lvApps.Items | ForEach-Object { $_.Tag } | Where-Object { $_.Group -eq $script:menuGroup }) }
$miGroupStart = $appsMenu.Items.Add('Start cả nhóm', $null, { Invoke-AppsBatch 'start' (Get-GroupApps) })
$miGroupStop  = $appsMenu.Items.Add('Stop cả nhóm', $null, { Invoke-AppsBatch 'stop' @(Get-GroupApps | Where-Object Running) })
$miGroupSel   = $appsMenu.Items.Add('Chọn cả nhóm', $null, { foreach ($it in $lvApps.Items) { $it.Selected = ($it.Tag.Group -eq $script:menuGroup) } })
[void]$appsMenu.Items.Add('-')
$miAppRemove  = $appsMenu.Items.Add('Gỡ khỏi panel… (Delete)', $null, { Remove-PanelApps (Get-SelectedApps) })
$miAppRemove.ForeColor = $Theme.Err
$miAppRestore = $appsMenu.Items.Add('Khôi phục app đã gỡ…', $null, { Show-RestoreAppsDialog })
[void]$appsMenu.Items.Add('-')
[void]$appsMenu.Items.Add('Chọn tất cả (Ctrl+A)', $null, { foreach ($it in $lvApps.Items) { $it.Selected = $true } })
[void]$appsMenu.Items.Add('Làm mới', $null, { $appsSync.Kick = $true; Set-Status 'Đang quét lại các port...' })
$miAppStats = $appsMenu.Items.Add('Hiện cột CPU / RAM / Phản hồi', $null, { Set-AppsStatsVisible (-not $script:showStats) })
$miAppStats.Checked = $script:showStats
function Set-AppsStatsVisible([bool]$on) {
    $script:showStats = $on; $miAppStats.Checked = $on
    $appsSync.Stats = $on
    $PanelConfig.showStats = $on; Save-PanelConfig $PanelConfig
    $lvApps.BeginUpdate()
    if ($on) { foreach ($col in $AppsCols[6..8]) { [void]$lvApps.Columns.Add($col[0], $col[1]) } }
    else {
        while ($lvApps.Columns.Count -gt 6) { $lvApps.Columns.RemoveAt(6) }
        if ($script:appsSort.Col -ge 6) { $script:appsSort.Col = 4; $script:appsSort.Desc = $false }
    }
    $lvApps.EndUpdate()
    Update-AppsSortHeader
    $lvApps.Width++; $lvApps.Width--          # cột Ứng dụng tự giãn lại
    Render-Apps
    $appsSync.Kick = $true
    Set-Status $(if ($on) { 'Đã bật cột CPU / RAM / Phản hồi.' } else { 'Đã ẩn cột CPU / RAM / Phản hồi (không đo nữa).' })
}
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
    $nKnown = @($sel | Where-Object Known).Count
    $miAppRemove.Text = 'Gỡ khỏi panel' + $(if ($nKnown -gt 1) { " ($nKnown app)" } else { '' }) + '… (Delete)'
    $miAppRemove.Enabled = [bool]$nKnown -and -not $script:appsBatchBusy
    $nRemoved = @((Get-AppsConfig).Removed).Count
    $miAppRestore.Text = "Khôi phục app đã gỡ ($nRemoved)…"; $miAppRestore.Enabled = [bool]$nRemoved
    $kn = @($sel | Where-Object Known)
    $miAppAuto.Enabled = [bool]$kn.Count
    $miAppAuto.Checked = $kn.Count -and (@($kn | Where-Object AutoRestart).Count -eq $kn.Count)
    $busy = if ($n -eq 1 -and $sel[0].Busy) { $sel[0] } else { $null }
    $miAppFreePort.Visible = [bool]$busy
    if ($busy) { $miAppFreePort.Text = "Giải phóng port $($busy.Port) (tắt $($busy.Process) · PID $($busy.BusyPid))" }
    $miAppGit.Enabled = [bool]@($sel | Where-Object { $_.Known -and $_.Dir }).Count
    Build-ProfileMenu $miAppProfiles.DropDownItems $appsMenu
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
    elseif ($e.KeyCode -eq 'Delete') { Remove-PanelApps (Get-SelectedApps); $e.Handled = $true }
    elseif ($e.KeyCode -eq 'Enter') { Open-AppWeb (Get-SelectedApps) }
})

# Bấm tiêu đề cột để sắp xếp (bấm lại để đảo chiều)
# Mặc định sắp theo Trạng thái: đang xử lý -> đang chạy -> port bị chiếm -> đã dừng
$script:appsSort = @{ Col = 4; Desc = $false }
function Update-AppsSortHeader {
    for ($i = 0; $i -lt $lvApps.Columns.Count; $i++) {
        $lvApps.Columns[$i].Text = $AppsCols[$i][0] + $(if ($i -eq $script:appsSort.Col) { if ($script:appsSort.Desc) { ' ▼' } else { ' ▲' } } else { '' })
    }
}
Update-AppsSortHeader
$lvApps.Add_ColumnClick({
    param($s, $e)
    if ($script:appsSort.Col -eq $e.Column) { $script:appsSort.Desc = -not $script:appsSort.Desc }
    else { $script:appsSort.Col = $e.Column; $script:appsSort.Desc = $false }
    Update-AppsSortHeader
    Render-Apps
})

# ---------- Git của project đang chọn ----------
# Chạy hàm của core ở runspace riêng (git fetch/pull có thể mất vài giây) -> healthTimer gọi Update-AsyncJobs để nhận kết quả
$script:asyncJobs = New-Object System.Collections.ArrayList
function Start-CoreAsync([string]$code, [hashtable]$params, [scriptblock]$onDone, [hashtable]$ctx = @{}) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1')); $rs.SessionStateProxy.SetVariable('CoreShared', $CoreShared)
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
$lblGit3.ForeColor = $Theme.Muted
foreach ($l in @($lblGit1, $lblGit2, $lblGit3)) { $l.AutoEllipsis = $true }
$cbBranch = New-Object System.Windows.Forms.ComboBox
$cbBranch.DropDownStyle = 'DropDownList'
$cbBranch.Location = New-Object System.Drawing.Point(160, 94)
$cbBranch.Size = New-Object System.Drawing.Size(170, 32)
# DropDownList không cho đặt chiều cao trực tiếp -> tự vẽ item, ItemHeight quyết định chiều cao ô
$cbBranch.DrawMode = 'OwnerDrawFixed'; $cbBranch.ItemHeight = 26
$cbBranch.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $bg = if ($sel) { $Theme.Sel } else { $sender.BackColor }
    $fg = $Theme.Text
    $b = New-Object System.Drawing.SolidBrush($bg); $e.Graphics.FillRectangle($b, $e.Bounds); $b.Dispose()
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 4), $e.Bounds.Y, ($e.Bounds.Width - 4), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Items[$e.Index], $sender.Font, $r, $fg, [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, SingleLine, NoPrefix')
})
$gGit.Controls.Add($cbBranch)
$script:gitFor = $null
$script:gitInfo = $null
$script:askedSafe = @{}

function Show-GitInfo($g) {
    $script:gitInfo = $g
    $cbBranch.Items.Clear()
    if (-not $g.IsRepo) {
        if ($g.Error) { $lblGit1.Text = "⚠ $($g.Error)"; $lblGit1.ForeColor = $Theme.Err }
        else { $lblGit1.Text = 'Thư mục này không nằm trong git repo.'; $lblGit1.ForeColor = $Theme.Muted }
        $lblGit2.Text = $g.Dir; $lblGit3.Text = ''
        if ($g.UnsafePath) {
            $lblGit3.Text = 'Repo do user Windows khác clone/copy sang - cần đánh dấu tin cậy (safe.directory).'
            if (-not $script:askedSafe.ContainsKey($g.UnsafePath)) {
                $script:askedSafe[$g.UnsafePath] = $true
                $q = "Git từ chối đọc repo:`n$($g.UnsafePath)`n`nvì thư mục thuộc user Windows khác (thường do copy repo từ máy/ổ khác hoặc clone bằng tài khoản Admin).`n`nThêm repo này vào danh sách tin cậy của Git?`n(git config --global --add safe.directory ...)"
                if ([System.Windows.Forms.MessageBox]::Show($q, 'Git', 'YesNo', 'Question') -eq 'Yes') {
                    Start-CoreAsync 'Add-GitSafeDirectory $p.Path' @{ Path = $g.UnsafePath } {
                        param($r, $ctx)
                        Set-Status ([string]$r.Value)
                        if ($r.Ok -and $script:gitFor) { Load-GitInfo $script:gitFor }
                    }
                }
            }
        }
        return
    }
    $sync = if ($g.Upstream) { "→ $($g.Upstream) · ↓$($g.Behind) ↑$($g.Ahead)" } else { '· chưa có upstream' }
    $lblGit1.Text = "⎇ $($g.Branch)  $sync · $($g.Dirty) file đang sửa"
    $lblGit1.ForeColor = if ($g.Behind) { $Theme.Err } elseif ($g.Dirty) { $Theme.Warn } else { $Theme.Ok }
    $lblGit2.Text = "$($g.LastHash)  $($g.LastMsg) — $($g.LastAuthor), $($g.LastWhen)"
    $lblGit3.Text = "$($g.Root)  ·  $($g.Remote)" + $(if ($g.LastFetch) { "  ·  fetch lúc $($g.LastFetch)" } else { '' })
    foreach ($b in $g.Branches) { [void]$cbBranch.Items.Add($b) }
    $cbBranch.SelectedItem = $g.Branch
}

function Load-GitInfo([string]$id) {
    $script:gitFor = $id
    $lblGit1.Text = 'Đang đọc git...'; $lblGit1.ForeColor = $Theme.Muted
    $lblGit2.Text = ''; $lblGit3.Text = ''
    Start-CoreAsync 'Get-AppGitInfo $p.Id' @{ Id = $id } {
        param($r, $ctx)
        if ($ctx.Id -ne $script:gitFor) { return }       # người dùng đã chọn app khác
        if ($r.Ok) { Show-GitInfo $r.Value } else { $lblGit1.Text = "Lỗi git: $($r.Value)"; $lblGit1.ForeColor = $Theme.Err }
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

$appsSync = [hashtable]::Synchronized(@{ Data = $null; At = [datetime]::MinValue; Seq = 0; Run = $true; Active = $false; Kick = $false; Stats = $script:showStats })
$appsRs = [runspacefactory]::CreateRunspace()
$appsRs.Open()
$appsRs.SessionStateProxy.SetVariable('sync', $appsSync)
$appsRs.SessionStateProxy.SetVariable('corePath', (Join-Path $PSScriptRoot 'DevOpsCore.ps1')); $appsRs.SessionStateProxy.SetVariable('CoreShared', $CoreShared)
$appsPs = [powershell]::Create()
$appsPs.Runspace = $appsRs
[void]$appsPs.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'
    . $corePath
    while ($sync.Run) {
        $active = $sync.Active
        $sync.Kick = $false
        try {
            $t = Get-Date
            $rows = @(Get-DevApps)
            if ($active -and $sync.Stats) { Add-DevAppStats $rows }      # CPU / RAM / gọi thử HTTP: chỉ khi bật cột và đang xem tab
            $sync.Data = $rows; $sync.At = $t; $sync.Seq++
        } catch { }
        # đang mở tab: ~5s/lần; chạy nền: 15s/lần (đủ để báo app sập)
        $ticks = if ($active) { 16 } else { 50 }
        for ($i = 0; $i -lt $ticks -and $sync.Run -and -not $sync.Kick -and ($sync.Active -eq $active); $i++) { Start-Sleep -Milliseconds 300 }
    }
})
[void]$appsPs.BeginInvoke()

$script:appsSeq = 0
$script:appsData = $null
function Update-Apps {
    if ($appsSync.Seq -eq $script:appsSeq) { return }
    $script:appsSeq = $appsSync.Seq
    if ($null -eq $appsSync.Data) { return }
    $prev = $script:appsData
    $script:appsData = $appsSync.Data
    Watch-AppsCrash $prev $script:appsData
    Resolve-AppsPending
    if ($script:restartQueue.Count -and -not $script:appsBatchBusy) {
        $q = @(Get-AppsByIds @($script:restartQueue)); $script:restartQueue.Clear()      # @(): 1 app sập vẫn là mảng
        if ($q.Count) { Invoke-AppsBatch 'start' $q }
    }
    $script:hdr.Apps = @($script:appsData | Where-Object Running).Count; Update-HeaderChips
    if ($form.Visible -and $tabs.SelectedTab -eq $pageApps) { Render-Apps }
}

# Bỏ dấu tiếng Việt để "dang chay" khớp "Đang chạy"
function ConvertTo-SearchText([string]$t) {
    $n = $t.ToLowerInvariant().Replace('đ', 'd').Normalize([Text.NormalizationForm]::FormD)
    -join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
}
function Test-AppMatch($a, [string[]]$terms) {
    if (-not $terms.Count) { return $true }
    $state = (Get-AppStateCell $a).Text -replace '^\S+\s', '' -replace '…\s*\d+s$', ''     # bỏ biểu tượng và số giây
    $hay = ConvertTo-SearchText "$($a.Group) $($a.Name) $($a.Type) $(if ($a.Port) { $a.Port }) $state $($a.Process)"
    foreach ($t in $terms) { if (-not $hay.Contains($t)) { return $false } }
    $true
}
$txtSearch.Add_TextChanged({ Render-Apps })
$txtSearch.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Escape') { $txtSearch.Clear(); $e.SuppressKeyPress = $true }
    elseif ($e.KeyCode -eq 'Down' -and $lvApps.Items.Count) { $lvApps.Focus(); if (-not $lvApps.SelectedItems.Count) { $lvApps.Items[0].Selected = $true; $lvApps.Items[0].Focused = $true }; $e.SuppressKeyPress = $true }
    elseif ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true }
})
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($s, $e)
    if ($e.Control -and $e.KeyCode -eq 'F' -and $tabs.SelectedTab -eq $pageApps) { $txtSearch.Focus(); $txtSearch.SelectAll(); $e.SuppressKeyPress = $true }
    elseif ($e.KeyCode -eq 'F1') { $tabs.SelectedTab = $pageHelp; $e.SuppressKeyPress = $true }
})

function Get-SortedApps {
    $apps = @($script:appsData)
    $col = $script:appsSort.Col
    if ($col -lt 0) { return $apps }      # không sắp: giữ thứ tự apps.json
    $key = switch ($col) {
        0 { { $_.Group } }
        1 { { $_.Name } }
        2 { { $_.Type } }
        3 { { [int]$_.Port } }
        4 { { if ($script:appsPending[$_.Id]) { 0 } elseif ($_.Running) { 1 } elseif ($_.Busy) { 2 } else { 3 } } }
        5 { { [int]$_.Pid } }
        6 { { if ($null -ne $_.CpuPct) { [double]$_.CpuPct } else { -1 } } }
        7 { { [int]$_.RamMB } }
        8 { { if (-not $_.Running -or $null -eq $_.HealthOk) { 999999 } elseif (-not $_.HealthOk) { 99999 } else { [int]$_.HealthMs } } }
    }
    $apps | Sort-Object @{ Expression = $key; Descending = $script:appsSort.Desc }, @{ Expression = 'Group' }, @{ Expression = 'Name' }
}

# Ô "Phản hồi": app nghe port nhưng có trả lời HTTP không (404 vẫn tính là sống)
function Get-AppHealthCell($a) {
    if (-not $a.Running -or -not $a.Port -or $null -eq $a.HealthOk) { return @{ Text = ''; Color = $Theme.Text } }
    if (-not $a.HealthOk) {
        if ($a.HealthCode) { return @{ Text = "✗ HTTP $($a.HealthCode)"; Color = $Theme.Err } }
        return @{ Text = '✗ không phản hồi'; Color = $Theme.Err }
    }
    @{ Text = "$($a.HealthMs) ms"; Color = $(if ($a.HealthMs -gt 1000) { $Theme.Warn } else { $Theme.Muted }) }
}

function Render-Apps {
    if ($null -eq $script:appsData) { return }
    $selIds = @($lvApps.SelectedItems | ForEach-Object { $_.Tag.Id })
    $focusId = if ($lvApps.FocusedItem) { $lvApps.FocusedItem.Tag.Id } else { $null }
    $top = if ($lvApps.TopItem) { $lvApps.TopItem.Index } else { 0 }
    $script:appsRendering = $true
    $terms = @((ConvertTo-SearchText $txtSearch.Text.Trim()) -split '\s+' | Where-Object { $_ })
    $all = @(Get-SortedApps)
    $lvApps.BeginUpdate(); $lvApps.Items.Clear()
    foreach ($a in $all) {
        if (-not (Test-AppMatch $a $terms)) { continue }
        $it = New-Object System.Windows.Forms.ListViewItem($a.Group)
        $it.UseItemStyleForSubItems = $false
        $state = Get-AppStateCell $a
        $cpu = if ($a.Running -and $null -ne $a.CpuPct) { '{0:0.#}%' -f $a.CpuPct } else { '' }
        $ram = if ($a.Running -and $a.RamMB) { Format-MB $a.RamMB } else { '' }
        $hc = Get-AppHealthCell $a
        foreach ($v in @($a.Name, $a.Type, $(if ($a.Port) { [string]$a.Port } else { '' }), $state.Text, $(if ($a.Pid) { [string]$a.Pid } else { '' }), $cpu, $ram, $hc.Text)) { [void]$it.SubItems.Add($v) }
        $it.SubItems[4].ForeColor = $state.Color
        $it.SubItems[8].ForeColor = $hc.Color
        if ($a.CpuPct -ge 50) { $it.SubItems[6].ForeColor = $Theme.Warn }
        $it.ToolTipText = $state.Tip
        $it.Tag = $a
        [void]$lvApps.Items.Add($it)
        if ($selIds -contains $a.Id) { $it.Selected = $true }
        if ($a.Id -eq $focusId) { $it.Focused = $true }
    }
    $lvApps.EndUpdate()
    if ($lvApps.Items.Count) { try { $lvApps.TopItem = $lvApps.Items[[math]::Min($top, $lvApps.Items.Count - 1)] } catch { } }
    $script:appsRendering = $false

    $run = @($all | Where-Object Running).Count
    $lblApps.Text = "$run đang chạy · $(@($all | Where-Object Known).Count) trong apps.json" +
        $(if ($script:appsPending.Count) { " · đang xử lý $($script:appsPending.Count)" } else { '' }) +
        $(if ($terms.Count) { " · tìm thấy $($lvApps.Items.Count)/$($all.Count)" } else { '' })
    $txtSearch.BackColor = if ($terms.Count -and -not $lvApps.Items.Count) { $Theme.ErrBg } else { $Theme.Surface }
}

function Sync-HealthMode {
    $healthSync.Fast = ($form.Visible -and $tabs.SelectedTab -eq $pageHealth)
    $k3sSync.Active  = ($form.Visible -and $tabs.SelectedTab -eq $pageK3s)
    $appsSync.Active = ($form.Visible -and $tabs.SelectedTab -eq $pageApps)
}
$tabs.Add_SelectedIndexChanged({
    Sync-HealthMode; $script:lastSeq = -1; Update-Health
    if ($tabs.SelectedTab -eq $pageK3s)  { $k3sSync.Kick = $true }
    if ($tabs.SelectedTab -eq $pageApps) { $appsSync.Kick = $true; Render-Apps }
    if ($tabs.SelectedTab -eq $pageGit -and -not $script:reposLoaded) { Load-Repos }
    if ($tabs.SelectedTab -eq $pageAi) { Enter-AiTab }
})
$form.Add_VisibleChanged({ Sync-HealthMode })

# ---------- Tab Git: tất cả repo trong danh mục ----------
$lblFlow = New-Label '' 12 6 498 $pageGit
$lblFlow.Height = 40
$lblFlow.Text = "Git-flow Sunhouse:  feature/ · fix/ · bugfix/  tách từ main → push → Merge Request vào main`n" +
                "hotfix/  (chỉ khi lỗi đang ảnh hưởng production)  tách từ production → MR vào production → cherry-pick sang main"
$lblFlow.ForeColor = $Theme.Muted
$lvRepos = New-Object System.Windows.Forms.ListView
$lvRepos.View = 'Details'; $lvRepos.FullRowSelect = $true; $lvRepos.MultiSelect = $true; $lvRepos.HideSelection = $false; $lvRepos.ShowItemToolTips = $true
$lvRepos.Location = New-Object System.Drawing.Point(12, 50); $lvRepos.Size = New-Object System.Drawing.Size(498, 180)
foreach ($col in @(@('Repo', 120), @('Nhánh', 170), @('↓', 34), @('↑', 34), @('Sửa', 38), @('Fetch lúc', 96), @('Ứng dụng', 120))) { [void]$lvRepos.Columns.Add($col[0], $col[1]) }
$pageGit.Controls.Add($lvRepos)
$ovRepos = New-Overlay $lvRepos
$script:repos = @(); $script:reposLoaded = $false; $script:reposBusy = $false; $script:gitWantApp = $null; $script:logFor = $null

# Lưu ý PowerShell 5.1: hàm trả 1 phần tử thì nơi gọi nhận object đơn (không có .Count) -> luôn gọi dạng @(Get-SelectedRepos)
function Get-SelectedRepos([switch]$AllIfNone) {
    $s = @($lvRepos.SelectedItems | ForEach-Object { $_.Tag } | Where-Object IsRepo)
    if (-not $s.Count -and $AllIfNone) { $s = @($script:repos | Where-Object IsRepo) }
    $s
}
function Render-Repos {
    $sel = @($lvRepos.SelectedItems | ForEach-Object { $_.Tag.Root })
    $lvRepos.BeginUpdate(); $lvRepos.Items.Clear()
    foreach ($r in $script:repos) {
        $it = New-Object System.Windows.Forms.ListViewItem($r.Name)
        $it.UseItemStyleForSubItems = $false
        if ($r.IsRepo) {
            $vals = @($r.Branch, $(if ($r.Upstream) { [string]$r.Behind } else { '-' }), $(if ($r.Upstream) { [string]$r.Ahead } else { '-' }), [string]$r.Dirty, $r.LastFetch, $r.Apps)
        } else {
            $vals = @($(if ($r.Error) { "⚠ $($r.Error)" } else { 'không phải git repo' }), '', '', '', '', $r.Apps)
        }
        foreach ($v in $vals) { [void]$it.SubItems.Add([string]$v) }
        $it.SubItems[1].ForeColor = if (-not $r.IsRepo) { $Theme.Err } elseif ($r.Branch -like 'hotfix/*') { $Theme.Err } elseif ($r.Branch -in 'main', 'production') { $Theme.Info } else { $Theme.Text }
        if ($r.Behind) { $it.SubItems[2].ForeColor = $Theme.Err }
        if ($r.Ahead) { $it.SubItems[3].ForeColor = $Theme.Warn }
        if ($r.Dirty) { $it.SubItems[4].ForeColor = $Theme.Warn }
        $it.ToolTipText = "$($r.Root)" + $(if ($r.Upstream) { "`n→ $($r.Upstream)" } else { '' })
        $it.Tag = $r
        [void]$lvRepos.Items.Add($it)
        if ($sel -contains $r.Root) { $it.Selected = $true }
    }
    $lvRepos.EndUpdate()
    Sort-ListView $lvRepos
    if ($script:gitWantApp) {
        foreach ($it in $lvRepos.Items) { $it.Selected = (@($it.Tag.Apps -split ', ') -contains $script:gitWantApp) }
        $first = @($lvRepos.SelectedItems)[0]; if ($first) { $first.EnsureVisible(); $first.Focused = $true }
        $script:gitWantApp = $null
    }
    Update-RepoLog
}
function Load-Repos {
    if ($script:reposBusy) { return }
    $script:reposBusy = $true
    if ($lvRepos.Items.Count) { $lblGitTab.Text = '⟳ Đang làm mới danh sách repo...' }
    else { Set-Overlay $ovRepos 'Đang đọc git của các repo trong danh mục' $true; $lblGitTab.Text = '' }
    Start-CoreAsync 'Get-AllReposGitInfo' @{} {
        param($r, $ctx)
        $script:reposBusy = $false
        if (-not $r.Ok) { $lblGitTab.Text = "Lỗi: $($r.Value)"; if (-not $lvRepos.Items.Count) { Set-Overlay $ovRepos "Không đọc được git: $($r.Value)" }; return }
        $script:repos = @($r.Value); $script:reposLoaded = $true
        $behind = @($script:repos | Where-Object Behind).Count; $dirty = @($script:repos | Where-Object Dirty).Count
        $lblGitTab.Text = "Double-click repo để mở cửa sổ Git · $($script:repos.Count) repo" + $(if ($behind) { " · $behind repo chậm hơn remote" } else { '' }) + $(if ($dirty) { " · $dirty repo có file đang sửa" } else { '' }) + " · cập nhật $((Get-Date).ToString('HH:mm:ss'))"
        Render-Repos
        Set-Overlay $ovRepos $(if ($script:repos.Count) { '' } else { 'Chưa có repo nào - thêm thư mục ở tab Cài đặt rồi Quét project.' })
    }
}
# Chạy 1 thao tác git cho nhiều repo ở nền rồi báo kết quả
function Invoke-ReposAction([string]$code, [hashtable]$params, [string]$title, $after = $null, $afterArg = $null) {
    if ($script:reposBusy) { Set-Status 'Git đang chạy lệnh khác, chờ chút.'; return }
    $script:reposBusy = $true; $form.Cursor = 'AppStarting'; Set-Status "$title..."
    Start-CoreAsync $code $params {
        param($r, $ctx)
        $script:reposBusy = $false; $form.Cursor = 'Default'
        $lines = @(if ($r.Ok) { $r.Value } else { "✗ $($r.Value)" })
        $err = @($lines | Where-Object { $_ -like '✗*' }).Count
        Set-Status ("$($ctx.Title): $($lines.Count - $err) OK" + $(if ($err) { ", $err lỗi" } else { '' }))
        # Cập nhật giao diện trước, rồi mới hiện hộp thông báo (hộp thông báo chặn tới khi bấm OK)
        Load-Repos
        if ($script:gitFor) { Load-GitInfo $script:gitFor }
        if ($ctx.After) { & $ctx.After $ctx.AfterArg }
        if ($err -or $lines.Count -le 20) { [System.Windows.Forms.MessageBox]::Show(($lines -join "`n"), $ctx.Title, 'OK', $(if ($err) { 'Warning' } else { 'Information' })) | Out-Null }
    } @{ Title = $title; After = $after; AfterArg = $afterArg }
}

$btnY = 236
$gitBtns = @(
    @('Làm mới', 72, { Load-Repos }),
    @('Fetch', 60, { $s = @(Get-SelectedRepos -AllIfNone); if ($s.Count) { Invoke-ReposAction 'Invoke-ReposGit $p.Roots fetch' @{ Roots = @($s.Root) } "Fetch $($s.Count) repo" } }),
    @('Pull', 54, { $s = @(Get-SelectedRepos -AllIfNone); if ($s.Count) { Invoke-ReposAction 'Invoke-ReposGit $p.Roots pull' @{ Roots = @($s.Root) } "Pull (fast-forward) $($s.Count) repo" } }),
    @('Tạo nhánh…', 96, { Show-NewBranchDialog }),
    @('Commit…', 78, { $r = @(Get-SelectedRepos)[0]; if ($r) { Show-CommitDialog $r.Root } else { Set-Status 'Chọn một repo.' } }),
    @('Push + MR', 88, { Invoke-PushMr })
)
$x = 12
foreach ($b in $gitBtns) { New-Button $b[0] $x $btnY $b[1] $pageGit $b[2] | Out-Null; $x += $b[1] + 4 }
$lblGitTab = New-Label 'Mở tab để đọc git các repo.' 12 274 274 $pageGit
$lblGitTab.ForeColor = $Theme.Muted; $lblGitTab.AutoEllipsis = $true
$chkLogAll = New-Object System.Windows.Forms.CheckBox
$chkLogAll.Text = 'Tất cả nhánh'; $chkLogAll.Checked = $true; $chkLogAll.AutoSize = $true
$chkLogAll.Location = New-Object System.Drawing.Point(290, 273)
$pageGit.Controls.Add($chkLogAll)
$cbLogN = New-Object System.Windows.Forms.ComboBox
$cbLogN.DropDownStyle = 'DropDownList'; [void]$cbLogN.Items.AddRange(@('100 commit', '300 commit', '1000 commit')); $cbLogN.SelectedIndex = 0
$cbLogN.Location = New-Object System.Drawing.Point(395, 270); $cbLogN.Size = New-Object System.Drawing.Size(115, 26)
$pageGit.Controls.Add($cbLogN)
# Lịch sử commit dạng graph: cùng kiểu vẽ với cửa sổ Git (đường cong theo làn, chấm commit, nhãn nhánh)
$lvLog = New-Object System.Windows.Forms.ListView
$lvLog.View = 'Details'; $lvLog.FullRowSelect = $true; $lvLog.HideSelection = $false; $lvLog.MultiSelect = $false
$lvLog.Location = New-Object System.Drawing.Point(12, 300); $lvLog.Size = New-Object System.Drawing.Size(498, 195)
foreach ($c in @(@('Graph', 60), @('Commit', 220), @('Tác giả', 120), @('Ngày', 135), @('Mã', 75))) { [void]$lvLog.Columns.Add($c[0], $c[1]) }
$pageGit.Controls.Add($lvLog)
$ovLog = New-Overlay $lvLog
function Set-LogMessage([string]$t, [switch]$Spin) { Set-Overlay $ovLog $t $Spin; if ($t) { $lvLog.Items.Clear() } }
Set-LogMessage 'Chọn một repo để xem lịch sử commit dạng graph.'
function Update-RepoLog([switch]$Force) {
    $s = @(Get-SelectedRepos)
    if ($s.Count -ne 1) { if (-not $s.Count) { $script:logFor = $null; Set-LogMessage 'Chọn một repo để xem lịch sử commit dạng graph.' }; return }
    $root = $s[0].Root
    $n = @(100, 300, 1000)[$cbLogN.SelectedIndex]
    $key = "$root|$n|$($chkLogAll.Checked)"
    if ($key -eq $script:logFor -and -not $Force) { return }
    $script:logFor = $key
    Set-LogMessage "Đang đọc lịch sử commit của $($s[0].Name)" -Spin
    Start-CoreAsync '@(Get-RepoCommits $p.Root $p.N $p.All)' @{ Root = $root; N = $n; All = $chkLogAll.Checked } {
        param($r, $ctx)
        if ($ctx.Key -ne $script:logFor) { return }
        if (-not $r.Ok) { Set-LogMessage "Lỗi: $($r.Value)"; return }
        Set-LogMessage ''
        Fill-CommitList $lvLog @($r.Value) $null
    } @{ Key = $key }
}
$lvLog.Add_DoubleClick({ $r = @(Get-SelectedRepos)[0]; if ($r) { Show-GitBrowser $r.Root } })
$lvRepos.Add_SelectedIndexChanged({ Update-RepoLog })
$chkLogAll.Add_CheckedChanged({ Update-RepoLog })
$cbLogN.Add_SelectedIndexChanged({ Update-RepoLog })

function Invoke-PushMr($repos = $null, $after = $null, $afterArg = $null) {
    $s = @(if ($repos) { $repos } else { Get-SelectedRepos })      # @() ngoài cùng: 1 repo vẫn là mảng (PSCustomObject đơn không có .Count)
    if (-not $s.Count) { Set-Status 'Chọn repo cần push.'; return }
    $bad = @($s | Where-Object { $_.Branch -in 'main', 'production', 'master' })
    if ($bad.Count) { [System.Windows.Forms.MessageBox]::Show("Không push thẳng nhánh main / production:`n$((@($bad.Name)) -join ', ')`n`nTạo nhánh feature/ fix/ hotfix/ trước (nút Tạo nhánh…).", 'Push + MR', 'OK', 'Warning') | Out-Null; return }
    $list = ($s | ForEach-Object { "  • $($_.Name): $($_.Branch) → MR vào $(if ($_.Branch -like 'hotfix/*') { 'production' } else { 'main' })" + $(if ($_.Dirty) { "  (còn $($_.Dirty) file chưa commit - không được push)" } else { '' }) }) -join "`n"
    if ([System.Windows.Forms.MessageBox]::Show("Push nhánh hiện tại lên origin rồi mở trang tạo Merge Request?`n`n$list", 'Push + Merge Request', 'YesNo', 'Question') -ne 'Yes') { return }
    if ($script:reposBusy) { Set-Status 'Git đang chạy lệnh khác, chờ chút.'; return }
    $script:reposBusy = $true; $form.Cursor = 'AppStarting'; Set-Status 'Đang push...'
    $code = { , @(foreach ($root in $p.Roots) { try { Push-RepoBranchForMr $root } catch { [pscustomobject]@{ Msg = "✗ $(Split-Path $root -Leaf): $($_.Exception.Message)"; Url = $null } } }) }.ToString()
    Start-CoreAsync $code @{ Roots = @($s.Root) } {
        param($r, $ctx)
        $script:reposBusy = $false; $form.Cursor = 'Default'
        if (-not $r.Ok) { Set-Status "Lỗi: $($r.Value)"; return }
        $res = @($r.Value)
        foreach ($x in $res) { if ($x.Url) { Start-Process $x.Url } }
        $msg = ($res | ForEach-Object Msg) -join "`n"
        Set-Status (($res | Select-Object -Last 1).Msg)
        if (@($res | Where-Object { $_.Msg -like '✗*' }).Count -or $res.Count -gt 1) { [System.Windows.Forms.MessageBox]::Show($msg, 'Push + Merge Request', 'OK', 'Information') | Out-Null }
        Load-Repos
        if ($ctx.After) { & $ctx.After $ctx.AfterArg }
    } @{ After = $after; AfterArg = $afterArg }
}

# Hộp thoại tạo nhánh theo git-flow
function Show-NewBranchDialog($repos = $null, $after = $null, $afterArg = $null, [bool]$carry = $false) {
    $s = @(if ($repos) { $repos } else { Get-SelectedRepos })      # @() ngoài cùng: 1 repo vẫn là mảng (PSCustomObject đơn không có .Count)
    if (-not $s.Count) { [System.Windows.Forms.MessageBox]::Show('Chọn (các) repo cần tạo nhánh trong danh sách trước.', 'Tạo nhánh', 'OK', 'Information') | Out-Null; return }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Tạo nhánh mới - $($s.Count) repo"; $dlg.Font = $font; $dlg.Icon = $AppIcon
    $dlg.Size = New-Object System.Drawing.Size(640, 520); $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
    $l1 = New-Label 'Loại nhánh' 14 18 100 $dlg
    $cbType = New-Object System.Windows.Forms.ComboBox
    $cbType.DropDownStyle = 'DropDownList'; $cbType.Location = New-Object System.Drawing.Point(120, 15); $cbType.Size = New-Object System.Drawing.Size(490, 28)
    [void]$cbType.Items.AddRange(@('feature   —  tính năng mới  (tách từ main)', 'fix   —  sửa lỗi thường  (tách từ main)', 'bugfix   —  sửa lỗi thường  (tách từ main)', 'hotfix   —  lỗi GẤP đang ảnh hưởng production  (tách từ production)'))
    $cbType.SelectedIndex = 0
    $dlg.Controls.Add($cbType)
    $l2 = New-Label 'Tên' 14 56 100 $dlg
    $txtB = New-Object System.Windows.Forms.TextBox
    $txtB.Location = New-Object System.Drawing.Point(120, 53); $txtB.Size = New-Object System.Drawing.Size(490, 26)
    $dlg.Controls.Add($txtB)
    $lblPrev = New-Label '' 120 86 490 $dlg
    $lblPrev.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $note = New-Object System.Windows.Forms.TextBox
    $note.Multiline = $true; $note.ReadOnly = $true; $note.TabStop = $false; $note.ScrollBars = 'Vertical'
    $note.Location = New-Object System.Drawing.Point(14, 116); $note.Size = New-Object System.Drawing.Size(596, 290)
    $note.Text = @"
QUY TRÌNH GIT-FLOW SUNHOUSE (chỉ có 2 nhánh dài hạn: main và production, KHÔNG dùng dev)

• feature/  ·  fix/  ·  bugfix/
   1. Tách từ main bản mới nhất (panel tự fetch rồi tách từ origin/main)
   2. Làm việc, commit
   3. Push + MR (nút ở tab Git) → Merge Request vào main
   4. main build xanh → MR main → production

• hotfix/   — CHỈ khi lỗi đang ảnh hưởng người dùng trên production
   1. Tách từ production (panel tách từ origin/production)
   2. Sửa, commit, Push + MR → Merge Request vào production, merge xong là deploy
   3. Cherry-pick commit sang main - quên bước này lần merge main → production sau sẽ đè mất fix

• Tên nhánh: chữ thường, nối bằng gạch ngang, mô tả việc gì
   vd  feature/prepare-load-goods-stock-status  ·  fix/barcode-packaging-selection  ·  hotfix/redis-hintpath

$(if ($carry) { 'Các file đang sửa (chưa commit) sẽ được MANG SANG nhánh mới.' } else { 'Repo phải sạch (không có file chưa commit).' }) Nhánh mới chỉ tạo ở máy, chưa push.
Repo: $((@($s.Name)) -join ', ')
"@ -replace '\r?\n', "`r`n"
    $dlg.Controls.Add($note)
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = 'Tạo nhánh'; $btnOk.DialogResult = 'OK'
    $btnOk.Location = New-Object System.Drawing.Point(400, 420); $btnOk.Size = New-Object System.Drawing.Size(110, 32)
    $btnNo = New-Object System.Windows.Forms.Button; $btnNo.Text = 'Huỷ'; $btnNo.DialogResult = 'Cancel'
    $btnNo.Location = New-Object System.Drawing.Point(516, 420); $btnNo.Size = New-Object System.Drawing.Size(94, 32)
    $dlg.Controls.AddRange(@($btnOk, $btnNo)); $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnNo
    $types = @('feature', 'fix', 'bugfix', 'hotfix')
    $upd = {
        $t = $types[$cbType.SelectedIndex]
        $nm = ((ConvertTo-SearchText $txtB.Text) -replace '[^a-z0-9]+', '-').Trim('-')
        $base = if ($t -eq 'hotfix') { 'production' } else { 'main' }
        $lblPrev.Text = if ($nm) { "$t/$nm   ←  origin/$base   →  MR vào $base" } else { "Gõ tên nhánh (tự đổi thành chữ thường, gạch ngang)" }
        $lblPrev.ForeColor = if ($t -eq 'hotfix') { $Theme.Err } else { $Theme.Ok }
        $btnOk.Enabled = [bool]$nm
    }      # chạy trong ShowDialog của hàm này nên thấy biến cục bộ, không cần closure
    $cbType.Add_SelectedIndexChanged($upd); $txtB.Add_TextChanged($upd)
    Set-ControlTheme $dlg $Theme $Theme
    & $upd
    $dlg.Add_Shown({ param($sd, $e) Set-NativeTheme $sd; [void]$txtB.Focus() })
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    $type = $types[$cbType.SelectedIndex]
    $name = ((ConvertTo-SearchText $txtB.Text) -replace '[^a-z0-9]+', '-').Trim('-')
    if ($type -eq 'hotfix' -and [System.Windows.Forms.MessageBox]::Show("hotfix/ chỉ dùng khi lỗi ĐANG ảnh hưởng production.`nLỗi không gấp thì dùng fix/ (tách từ main).`n`nTiếp tục tạo hotfix/$name từ production?", 'Hotfix', 'YesNo', 'Warning') -ne 'Yes') { return }
    Invoke-ReposAction 'New-RepoFlowBranch $p.Roots $p.Type $p.Name $p.Carry' @{ Roots = @($s.Root); Type = $type; Name = $name; Carry = $carry } "Tạo nhánh $type/$name" $after $afterArg
}

# Menu chuột phải tab Git
$repoMenu = New-Object System.Windows.Forms.ContextMenuStrip
foreach ($b in ($gitBtns | Select-Object -Skip 1)) { [void]$repoMenu.Items.Add($b[0], $null, $b[2]) }
[void]$repoMenu.Items.Add('-')
$miOpenGitx = $repoMenu.Items.Add('Mở cửa sổ Git (nhánh, lịch sử, diff)', $null, { $r = @(Get-SelectedRepos)[0]; if ($r) { Show-GitBrowser $r.Root } })
$miOpenGitx.Font = New-Object System.Drawing.Font($repoMenu.Font, [System.Drawing.FontStyle]::Bold)
$repoMenu.Items.Insert(0, $miOpenGitx)
[void]$repoMenu.Items.Add('Thư mục', $null, { foreach ($r in Get-SelectedRepos) { Start-Process explorer.exe "`"$($r.Root)`"" } })
[void]$repoMenu.Items.Add('Mở trên GitLab', $null, { foreach ($r in Get-SelectedRepos) { $u = Get-RepoWebUrl $r.Root; if ($u) { Start-Process $u } } })
[void]$repoMenu.Items.Add('Mở terminal tại repo', $null, { foreach ($r in Get-SelectedRepos) { if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList "-d `"$($r.Root)`"" } else { Start-Process powershell.exe -WorkingDirectory $r.Root } } })
[void]$repoMenu.Items.Add('Copy đường dẫn', $null, { [System.Windows.Forms.Clipboard]::SetText((@(Get-SelectedRepos).Root -join "`r`n")) })
[void]$repoMenu.Items.Add('Tải lại log', $null, { Update-RepoLog -Force })
[void]$repoMenu.Items.Add('Code với AI tại repo này', $null, { $r = @(Get-SelectedRepos)[0]; if ($r) { Show-AiFor $r.Root } })
$lvRepos.ContextMenuStrip = $repoMenu
$lvRepos.Add_DoubleClick({ $r = @(Get-SelectedRepos)[0]; if ($r) { Show-GitBrowser $r.Root } })

# Từ tab Ứng dụng: mở tab Git và chọn repo của app
function Show-GitTabFor($a) {
    $script:gitWantApp = $a.Name
    $tabs.SelectedTab = $pageGit
    if ($script:reposLoaded) { Render-Repos } else { Load-Repos }
}


# =====================================================================
# ---------- Cửa sổ Git kiểu Git Extensions ----------
# Mỗi cửa sổ giữ trạng thái trong $form.Tag ($st); handler lấy lại qua $sender.FindForm().Tag
# (handler chạy ngoài hàm tạo cửa sổ nên không thấy biến cục bộ).
$script:gitWindows = @{}
$MonoFont  = New-Object System.Drawing.Font('Consolas', 9.5)
$RefFont   = New-Object System.Drawing.Font('Segoe UI Semibold', 8.25)
$LaneW = 16          # bề rộng 1 làn graph (px)

function ConvertTo-NoDiacritics([string]$t) {
    $n = $t.Replace('đ', 'd').Replace('Đ', 'D').Normalize([Text.NormalizationForm]::FormD)
    (-join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })).Normalize([Text.NormalizationForm]::FormC)
}

# Diff có màu: + xanh, - đỏ, @@ xanh dương, phần đầu xám
function Show-DiffText($rtb, [string]$text) {
    $lines = @(($text -replace "`r", '') -split "`n")
    if ($lines.Count -gt 4000) { $lines = $lines[0..3999] + "… (diff dài, chỉ hiện 4000 dòng đầu)" }
    $text = $lines -join "`n"
    $rtb.SuspendLayout()
    $rtb.Text = $text
    $rtb.SelectAll(); $rtb.SelectionColor = $Theme.Text
    $pos = 0
    foreach ($l in $lines) {
        $c = $null
        if ($l.StartsWith('diff --git') -or $l.StartsWith('index ') -or $l.StartsWith('+++') -or $l.StartsWith('---') -or $l.StartsWith('new file') -or $l.StartsWith('deleted file') -or $l.StartsWith('similarity') -or $l.StartsWith('rename ')) { $c = $Theme.Muted }
        elseif ($l.StartsWith('+')) { $c = $Theme.Ok }
        elseif ($l.StartsWith('-')) { $c = $Theme.Err }
        elseif ($l.StartsWith('@@')) { $c = $Theme.Info }
        if ($c -and $l.Length) { $rtb.Select($pos, $l.Length); $rtb.SelectionColor = $c }
        $pos += $l.Length + 1
    }
    $rtb.Select(0, 0); $rtb.ResumeLayout()
}

function New-GitListView([string[][]]$cols) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.Dock = 'Fill'; $lv.MultiSelect = $true
    foreach ($c in $cols) { [void]$lv.Columns.Add($c[0], [int]$c[1]) }
    $lv
}
# ListView thường: theme tối thì tự vẽ header + dòng chọn (giống các bảng khác)
function Enable-ThemedListView($lv) {
    $lv.Add_DrawColumnHeader($lvDrawHeader); $lv.Add_DrawItem($lvDrawItem); $lv.Add_DrawSubItem($lvDrawSubItem)
    $lv.OwnerDraw = $true; Set-RowHeight $lv 24; Set-DoubleBuffered $lv
}
function New-RtbView {
    $r = New-Object System.Windows.Forms.RichTextBox
    $r.ReadOnly = $true; $r.WordWrap = $false; $r.ScrollBars = 'Both'; $r.DetectUrls = $false; $r.Dock = 'Fill'
    $r.Font = $MonoFont; $r.BackColor = $Theme.Surface; $r.BorderStyle = 'None'
    $r
}
function New-ToolButton([string]$text, $parent, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.AutoSize = $true; $b.Height = 30; $b.Margin = New-Object System.Windows.Forms.Padding(2, 4, 2, 2)
    $b.Add_Click($onClick); $parent.Controls.Add($b); $b
}
function Get-CodeColor([string]$code) {
    switch ($code) { 'A' { $Theme.Ok } 'D' { $Theme.Err } 'U' { $Theme.Err } '?' { $Theme.Info } 'R' { $Theme.Info } 'C' { $Theme.Info } default { $Theme.Warn } }
}

# ---- Danh sách commit: graph tự vẽ (đường cong theo làn, chấm commit) + nhãn nhánh / tag bo góc ----
$script:lanePens = @{}
function Get-LanePen([int]$i) {
    $k = $i % $LaneColors.Count
    if (-not $script:lanePens.ContainsKey($k)) {
        $p = New-Object System.Drawing.Pen($LaneColors[$k], 2); $p.StartCap = 'Round'; $p.EndCap = 'Round'
        $script:lanePens[$k] = $p
    }
    $script:lanePens[$k]
}
$commitDrawHeader = { param($sender, $e) & $lvDrawHeader $sender $e }
$commitDrawSubItem = {
    param($sender, $e)
    $c = $e.Item.Tag
    $g = $e.Graphics; $b = $e.Bounds
    $bg = Get-RowBack $sender $e.Item
    $br = New-Object System.Drawing.SolidBrush($bg); $g.FillRectangle($br, $b); $br.Dispose()
    $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, SingleLine, NoPrefix'
    switch ($e.ColumnIndex) {
        0 {
            $g.SmoothingMode = 'AntiAlias'
            $g.SetClip($b)
            $x0 = $b.Left + 10; $top = [single]$b.Top; $bot = [single]$b.Bottom; $mid = [single]($b.Top + $b.Height / 2)
            foreach ($sg in $c.Segs) {
                $pen = Get-LanePen $sg[3]
                $xa = [single]($x0 + $sg[1] * $LaneW); $xb = [single]($x0 + $sg[2] * $LaneW)
                if ($sg[0] -eq 0) { $g.DrawLine($pen, $xa, $top, $xa, $bot); continue }
                $ya = if ($sg[0] -eq 1) { $top } else { $mid }; $yb = if ($sg[0] -eq 1) { $mid } else { $bot }
                if ($xa -eq $xb) { $g.DrawLine($pen, $xa, $ya, $xb, $yb) }
                else { $ym = ($ya + $yb) / 2; $g.DrawBezier($pen, $xa, $ya, $xa, $ym, $xb, $ym, $xb, $yb) }
            }
            # Chấm commit: viền màu nền tách khỏi đường; commit merge = vòng rỗng; HEAD có quầng sáng
            $lc = $LaneColors[$c.Color % $LaneColors.Count]
            $cx = [single]($x0 + $c.Col * $LaneW)
            if ($c.Refs -match '(^|, )HEAD') { $hb = New-Object System.Drawing.SolidBrush((Get-Alpha 70 $lc)); $g.FillEllipse($hb, ($cx - 9), ($mid - 9), 18, 18); $hb.Dispose() }
            $rb = New-Object System.Drawing.SolidBrush($bg); $g.FillEllipse($rb, ($cx - 7), ($mid - 7), 14, 14); $rb.Dispose()
            if ($c.Merge) {
                $mp = New-Object System.Drawing.Pen($lc, 2); $g.DrawEllipse($mp, ($cx - 4.5), ($mid - 4.5), 9, 9); $mp.Dispose()
            } else {
                $db = New-Object System.Drawing.SolidBrush($lc); $g.FillEllipse($db, ($cx - 5), ($mid - 5), 10, 10); $db.Dispose()
            }
            $g.ResetClip()
        }
        1 {
            $x = [single]($b.Left + 4)
            if ($c.Refs) {
                $g.SmoothingMode = 'AntiAlias'
                foreach ($ref in ($c.Refs -split ', ')) {
                    $t = $ref; $rc = $Theme.Ok; $solid = $false
                    if ($t -like 'HEAD -> *') { $t = $t.Substring(8); $rc = $Theme.Accent; $solid = $true }
                    elseif ($t -eq 'HEAD') { $rc = $Theme.Err; $solid = $true }
                    elseif ($t -like 'tag: *') { $t = '◆ ' + $t.Substring(5); $rc = $Theme.Warn }
                    elseif ($t -like 'origin/*') { $rc = $Theme.Info }
                    if ($t -eq 'origin/HEAD') { continue }
                    $w = [single]([System.Windows.Forms.TextRenderer]::MeasureText($t, $RefFont).Width + 4)
                    if ($x + $w -gt $b.Right - 60) { break }
                    $p = New-RoundRect $x ($b.Top + 4) $w ($b.Height - 9) 6
                    $fb = New-Object System.Drawing.SolidBrush($(if ($solid) { $rc } else { Get-Alpha 38 $rc })); $g.FillPath($fb, $p); $fb.Dispose()
                    if (-not $solid) { $pp = New-Object System.Drawing.Pen((Get-Alpha 140 $rc)); $g.DrawPath($pp, $p); $pp.Dispose() }
                    $p.Dispose()
                    $rr = New-Object System.Drawing.Rectangle([int]$x, ($b.Top + 3), [int]$w, ($b.Height - 7))
                    [System.Windows.Forms.TextRenderer]::DrawText($g, $t, $RefFont, $rr, $(if ($solid) { $Theme.AccentText } else { $rc }), [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix')
                    $x += $w + 4
                }
            }
            $r = New-Object System.Drawing.Rectangle([int]$x, $b.Top, [math]::Max(0, $b.Right - [int]$x), $b.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $c.Subject, $sender.Font, $r, $(if ($c.Merge) { $Theme.Muted } else { $Theme.Text }), $flags)
        }
        default {
            $txt = switch ($e.ColumnIndex) { 2 { $c.Author } 3 { $c.Date } 4 { $c.Short } }
            $r = New-Object System.Drawing.Rectangle(($b.Left + 4), $b.Top, ($b.Width - 5), $b.Height)
            $fnt = if ($e.ColumnIndex -eq 4) { $MonoFont } else { $sender.Font }
            $fc = switch ($e.ColumnIndex) { 2 { $Theme.Text } 3 { $Theme.Muted } 4 { $Theme.Info } }
            [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$txt, $fnt, $r, $fc, $flags)
        }
    }
}
# Đổ danh sách commit vào bảng (tab Git và cửa sổ Git); trả về dòng có mã $selHash nếu có
function Fill-CommitList($lv, $rows, [string]$selHash) {
    $maxL = [int]($rows | Measure-Object -Property Lanes -Maximum).Maximum
    $lv.BeginUpdate(); $lv.Items.Clear()
    $sel = $null
    foreach ($c in $rows) {
        $it = New-Object System.Windows.Forms.ListViewItem('')
        foreach ($i in 1..4) { [void]$it.SubItems.Add('') }
        $it.Tag = $c
        [void]$lv.Items.Add($it)
        if ($selHash -and $c.Hash -eq $selHash) { $sel = $it }
    }
    $lv.Columns[0].Width = [math]::Min(340, [math]::Max(40, $maxL * $LaneW + 14))
    $lv.EndUpdate()
    $others = 0; for ($i = 0; $i -lt $lv.Columns.Count; $i++) { if ($i -ne 1) { $others += $lv.Columns[$i].Width } }
    $lv.Columns[1].Width = [math]::Max(200, $lv.ClientSize.Width - $others - 4)      # sau EndUpdate: ClientSize đã trừ thanh cuộn dọc
    $sel
}

function Show-GitBrowser([string]$root) {
    $existing = $script:gitWindows[$root]
    if ($existing -and -not $existing.IsDisposed) { $existing.WindowState = 'Normal'; $existing.Activate(); return }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Git - $(Split-Path $root -Leaf)"; $f.Icon = $AppIcon; $f.Font = $font
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $f.Size = New-Object System.Drawing.Size([math]::Min(1280, $wa.Width - 40), [math]::Min(820, $wa.Height - 40)); $f.StartPosition = 'CenterScreen'
    $st = @{ Root = $root; Form = $f; Hash = $null; File = $null; Branch = ''; Dirty = 0 }
    $f.Tag = $st
    $script:gitWindows[$root] = $f

    # Thanh công cụ
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.Height = 40; $bar.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 2); $bar.WrapContents = $false
    New-ToolButton '⟳ Làm mới' $bar { param($sender, $e) GitB-Refresh $sender.FindForm().Tag } | Out-Null
    New-ToolButton 'Fetch' $bar { param($sender, $e) $st = $sender.FindForm().Tag; Invoke-ReposAction 'Invoke-ReposGit $p.Roots fetch' @{ Roots = @($st.Root) } 'Fetch' { param($x) GitB-Refresh $x } $st } | Out-Null
    New-ToolButton 'Pull' $bar { param($sender, $e) $st = $sender.FindForm().Tag; Invoke-ReposAction 'Invoke-ReposGit $p.Roots pull' @{ Roots = @($st.Root) } 'Pull (fast-forward)' { param($x) GitB-Refresh $x } $st } | Out-Null
    $st.BtnCommit = New-ToolButton '✔ Commit…' $bar { param($sender, $e) $st = $sender.FindForm().Tag; Show-CommitDialog $st.Root $st }
    $st.BtnCommit.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
    New-ToolButton 'Push + MR' $bar { param($sender, $e) $st = $sender.FindForm().Tag; Invoke-PushMr @([pscustomobject]@{ Root = $st.Root; Name = (Split-Path $st.Root -Leaf); Branch = $st.Branch; Dirty = $st.Dirty }) { param($x) GitB-Refresh $x } $st } | Out-Null
    New-ToolButton 'Nhánh mới…' $bar { param($sender, $e) $st = $sender.FindForm().Tag; Show-NewBranchDialog @([pscustomobject]@{ Root = $st.Root; Name = (Split-Path $st.Root -Leaf) }) { param($x) GitB-Refresh $x } $st } | Out-Null
    New-ToolButton 'Thư mục' $bar { param($sender, $e) Start-Process explorer.exe "`"$($sender.FindForm().Tag.Root)`"" } | Out-Null
    $st.ChkAll = New-Object System.Windows.Forms.CheckBox
    $st.ChkAll.Text = 'Tất cả nhánh'; $st.ChkAll.Checked = $true; $st.ChkAll.AutoSize = $true; $st.ChkAll.Margin = New-Object System.Windows.Forms.Padding(14, 10, 4, 0)
    $st.ChkAll.Add_CheckedChanged({ param($sender, $e) GitB-LoadCommits $sender.FindForm().Tag })
    $bar.Controls.Add($st.ChkAll)
    $st.CbN = New-Object System.Windows.Forms.ComboBox
    $st.CbN.DropDownStyle = 'DropDownList'; [void]$st.CbN.Items.AddRange(@('300 commit', '1000 commit', '3000 commit')); $st.CbN.SelectedIndex = 0
    $st.CbN.Width = 110; $st.CbN.Margin = New-Object System.Windows.Forms.Padding(4, 7, 4, 0)
    $st.CbN.Add_SelectedIndexChanged({ param($sender, $e) GitB-LoadCommits $sender.FindForm().Tag })
    $bar.Controls.Add($st.CbN)
    $st.LblBranch = New-Object System.Windows.Forms.Label
    $st.LblBranch.AutoSize = $true; $st.LblBranch.Margin = New-Object System.Windows.Forms.Padding(14, 11, 4, 0)
    $st.LblBranch.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
    $bar.Controls.Add($st.LblBranch)

    $status = New-Object System.Windows.Forms.Label
    $status.Dock = 'Bottom'; $status.Height = 22; $status.Padding = New-Object System.Windows.Forms.Padding(8, 3, 0, 0); $status.ForeColor = $Theme.Muted
    $st.Status = $status

    # Trái: cây nhánh | Phải: danh sách commit / (thông tin + file | diff)
    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'; $split.SplitterDistance = 250; $split.FixedPanel = 'Panel1'
    $tree = New-Object System.Windows.Forms.TreeView
    $tree.Dock = 'Fill'; $tree.HideSelection = $false; $tree.ShowLines = $false; $tree.FullRowSelect = $true; $tree.ItemHeight = 26; $tree.BorderStyle = 'None'
    $st.Tree = $tree
    $split.Panel1.Controls.Add($tree)
    $tree.Add_NodeMouseDoubleClick({ param($sender, $e) GitB-Checkout $sender.FindForm().Tag $e.Node })
    $treeMenu = New-Object System.Windows.Forms.ContextMenuStrip
    [void]$treeMenu.Items.Add('Checkout nhánh này', $null, { param($sender, $e) $t = $sender.Owner.SourceControl; GitB-Checkout $t.FindForm().Tag $t.SelectedNode })
    $tree.ContextMenuStrip = $treeMenu
    $tree.Add_NodeMouseClick({ param($sender, $e) if ($e.Button -eq 'Right') { $sender.SelectedNode = $e.Node } })
    $st.TreeMenu = $treeMenu

    $right = New-Object System.Windows.Forms.SplitContainer
    $right.Dock = 'Fill'; $right.Orientation = 'Horizontal'
    $split.Panel2.Controls.Add($right)
    $lvC = New-GitListView @(@('Graph', 110), @('Commit', 560), @('Tác giả', 150), @('Ngày', 130), @('Mã', 80))
    $lvC.MultiSelect = $false; $lvC.OwnerDraw = $true; Set-RowHeight $lvC 28; Set-DoubleBuffered $lvC
    $lvC.Add_DrawColumnHeader($commitDrawHeader); $lvC.Add_DrawItem({ param($s2, $e) }); $lvC.Add_DrawSubItem($commitDrawSubItem)
    $lvC.Add_SelectedIndexChanged({ param($sender, $e) $st = $sender.FindForm().Tag; if ($sender.SelectedItems.Count) { GitB-ShowCommit $st $sender.SelectedItems[0].Tag } })
    $lvC.Add_GotFocus({ param($sender, $e) $sender.Invalidate() }); $lvC.Add_LostFocus({ param($sender, $e) $sender.Invalidate() })
    $st.LvC = $lvC
    $right.Panel1.Controls.Add($lvC)

    $bottom = New-Object System.Windows.Forms.SplitContainer
    $bottom.Dock = 'Fill'
    $right.Panel2.Controls.Add($bottom)
    $info = New-Object System.Windows.Forms.TextBox
    $info.Multiline = $true; $info.ReadOnly = $true; $info.ScrollBars = 'Vertical'; $info.Dock = 'Top'; $info.Height = 120; $info.Font = $MonoFont; $info.BorderStyle = 'None'
    $st.Info = $info
    $lvF = New-GitListView @(@('', 26), @('File thay đổi trong commit', 400))
    $lvF.MultiSelect = $false
    $lvF.Add_SelectedIndexChanged({ param($sender, $e) $st = $sender.FindForm().Tag; if ($sender.SelectedItems.Count) { GitB-ShowFileDiff $st $sender.SelectedItems[0].Tag } })
    $st.LvF = $lvF
    $bottom.Panel1.Controls.Add($lvF); $bottom.Panel1.Controls.Add($info); $lvF.BringToFront()
    $diff = New-RtbView
    $st.Diff = $diff
    $bottom.Panel2.Controls.Add($diff)

    $f.Controls.Add($split); $f.Controls.Add($bar); $f.Controls.Add($status)
    $split.BringToFront()

    Set-ControlTheme $f $Theme $Theme
    Add-IconsTo $f; Add-MenuIcons $treeMenu.Items
    foreach ($lv in @($lvF)) { Enable-ThemedListView $lv }
    $diff.BackColor = $Theme.Surface; $tree.BackColor = $Theme.Surface; $tree.ForeColor = $Theme.Text
    if ($script:ThemeName -eq 'dark') { Set-MenuTheme $treeMenu $Theme $Theme $true }
    $f.Add_Shown({ param($sender, $e)
        $st = $sender.Tag
        Set-NativeTheme $sender
        $sp = $sender.Controls | Where-Object { $_ -is [System.Windows.Forms.SplitContainer] }
        $sp.SplitterDistance = 250
        $r2 = $sp.Panel2.Controls[0]; $r2.SplitterDistance = [int]($r2.Height * 0.55)
        $b2 = $r2.Panel2.Controls[0]; $b2.SplitterDistance = [int]($b2.Width * 0.38)
        $st.LvC.Columns[1].Width = [math]::Max(300, $st.LvC.ClientSize.Width - 110 - 150 - 130 - 80 - 6)
        $st.LvF.Columns[1].Width = [math]::Max(200, $st.LvF.ClientSize.Width - 30)
        GitB-Refresh $st
    })
    $f.Add_FormClosed({ param($sender, $e) $script:gitWindows.Remove($sender.Tag.Root) })
    $f.Show()
}

function GitB-SetStatus($st, [string]$t) { if (-not $st.Form.IsDisposed) { $st.Status.Text = $t } }

function GitB-Refresh($st) {
    if ($st.Form.IsDisposed) { return }
    GitB-SetStatus $st 'Đang đọc nhánh và lịch sử...'
    Start-CoreAsync '[pscustomobject]@{ Branches = @(Get-RepoBranches $p.Root); Changes = @(Get-RepoChanges $p.Root) }' @{ Root = $st.Root } {
        param($r, $ctx)
        $st = $ctx.St
        if ($st.Form.IsDisposed) { return }
        if (-not $r.Ok) { GitB-SetStatus $st "Lỗi: $($r.Value)"; return }
        $br = @($r.Value.Branches); $ch = @($r.Value.Changes)
        $cur = $br | Where-Object { $_.Kind -eq 'local' -and $_.Current } | Select-Object -First 1
        $st.Branch = if ($cur) { $cur.Name } else { 'HEAD (detached)' }
        $st.Dirty = @($ch | ForEach-Object Path | Sort-Object -Unique).Count
        $st.LblBranch.Text = "⎇ $($st.Branch)" + $(if ($cur.Track) { "  $($cur.Track)" } else { '' })
        $st.LblBranch.ForeColor = if ($st.Branch -like 'hotfix/*') { $Theme.Err } elseif ($st.Branch -in 'main', 'production') { $Theme.Info } else { $Theme.Ok }
        $st.BtnCommit.Text = "Commit… ($($st.Dirty))"
        $t = $st.Tree; $t.BeginUpdate(); $t.Nodes.Clear()
        $bold = New-Object System.Drawing.Font($t.Font, [System.Drawing.FontStyle]::Bold)
        foreach ($grp in @(@('local', 'Nhánh local'), @('remote', 'Remote'), @('tag', 'Tag'))) {
            $items = @($br | Where-Object Kind -eq $grp[0])
            if (-not $items.Count) { continue }
            $n = $t.Nodes.Add("$($grp[1]) ($($items.Count))"); $n.NodeFont = $bold
            foreach ($b in $items) {
                $txt = $(if ($b.Current) { '✓ ' } else { '   ' }) + $b.Name + $(if ($b.Track) { "  $($b.Track)" } else { '' })
                $c = $n.Nodes.Add($txt); $c.Tag = $b
                if ($b.Current) { $c.NodeFont = $bold; $c.ForeColor = $Theme.Ok }
                elseif ($b.Name -in 'main', 'production', 'origin/main', 'origin/production') { $c.ForeColor = $Theme.Info }
            }
            if ($grp[0] -ne 'tag') { $n.Expand() }
        }
        $t.EndUpdate(); $bold = $null
        GitB-LoadCommits $st
    } @{ St = $st }
}

function GitB-LoadCommits($st) {
    if ($st.Form.IsDisposed) { return }
    $n = @(300, 1000, 3000)[$st.CbN.SelectedIndex]
    GitB-SetStatus $st 'Đang đọc lịch sử commit...'
    Start-CoreAsync '@(Get-RepoCommits $p.Root $p.N $p.All)' @{ Root = $st.Root; N = $n; All = $st.ChkAll.Checked } {
        param($r, $ctx)
        $st = $ctx.St
        if ($st.Form.IsDisposed) { return }
        if (-not $r.Ok) { GitB-SetStatus $st "Lỗi: $($r.Value)"; return }
        $rows = @($r.Value)
        $lv = $st.LvC
        $sel = Fill-CommitList $lv $rows $st.Hash
        if (-not $sel -and $lv.Items.Count) { $sel = $lv.Items[0] }
        if ($sel) { $sel.Selected = $true; $sel.Focused = $true; $sel.EnsureVisible() }
        GitB-SetStatus $st ("$($rows.Count) commit · " + $(if ($st.ChkAll.Checked) { 'tất cả nhánh' } else { 'nhánh hiện tại' }) + " · $($st.Root) · cập nhật $((Get-Date).ToString('HH:mm:ss'))")
    } @{ St = $st }
}

function GitB-ShowCommit($st, $c) {
    if (-not $c.Hash -or $c.Hash -eq $st.ShownHash) { return }
    $st.Hash = $c.Hash; $st.ShownHash = $c.Hash
    $st.Info.Text = "Đang đọc commit $($c.Short)..."
    Start-CoreAsync 'Get-CommitDetail $p.Root $p.Hash' @{ Root = $st.Root; Hash = $c.Hash } {
        param($r, $ctx)
        $st = $ctx.St
        if ($st.Form.IsDisposed -or $st.Hash -ne $ctx.Hash) { return }
        if (-not $r.Ok) { $st.Info.Text = "Lỗi: $($r.Value)"; return }
        $st.Info.Text = ([string]$r.Value.Info).Trim() -replace "`r?`n", "`r`n"
        $lv = $st.LvF; $lv.BeginUpdate(); $lv.Items.Clear()
        foreach ($fl in $r.Value.Files) {
            $it = New-Object System.Windows.Forms.ListViewItem($fl.Code)
            $it.UseItemStyleForSubItems = $false
            [void]$it.SubItems.Add($(if ($fl.Old) { "$($fl.Old) → $($fl.Path)" } else { $fl.Path }))
            $it.SubItems[0].ForeColor = Get-CodeColor $fl.Code
            $it.Tag = $fl
            [void]$lv.Items.Add($it)
        }
        $lv.EndUpdate()
        if ($lv.Items.Count) { $lv.Items[0].Selected = $true } else { $st.Diff.Text = '(Commit không đổi file nào)' }
    } @{ St = $st; Hash = $c.Hash }
}

function GitB-ShowFileDiff($st, $fl) {
    $key = "$($st.Hash)|$($fl.Path)"
    $st.DiffKey = $key
    Start-CoreAsync 'Get-CommitFileDiff $p.Root $p.Hash $p.Path' @{ Root = $st.Root; Hash = $st.Hash; Path = $fl.Path } {
        param($r, $ctx)
        $st = $ctx.St
        if ($st.Form.IsDisposed -or $st.DiffKey -ne $ctx.Key) { return }
        Show-DiffText $st.Diff $(if ($r.Ok) { [string]$r.Value } else { "Lỗi: $($r.Value)" })
    } @{ St = $st; Key = $key }
}

function GitB-Checkout($st, $node) {
    $b = $node.Tag
    if (-not $b -or $b.Kind -eq 'tag' -or $b.Current) { return }
    if ([System.Windows.Forms.MessageBox]::Show("Chuyển $(Split-Path $st.Root -Leaf) sang nhánh '$($b.Name)'?" + $(if ($b.Kind -eq 'remote') { "`n(tạo nhánh local theo dõi $($b.Name))" } else { '' }), 'Checkout', 'YesNo', 'Question') -ne 'Yes') { return }
    Invoke-ReposAction 'Switch-RepoBranch $p.Root $p.Name $p.Remote' @{ Root = $st.Root; Name = $b.Name; Remote = ($b.Kind -eq 'remote') } "Checkout $($b.Name)" { param($x) GitB-Refresh $x } $st
}

# =====================================================================
# ---------- Cửa sổ Commit: stage / unstage / diff / commit ----------
function Show-CommitDialog([string]$root, $browserSt = $null) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = "Commit - $(Split-Path $root -Leaf)"; $d.Icon = $AppIcon; $d.Font = $font
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $d.Size = New-Object System.Drawing.Size([math]::Min(1200, $wa.Width - 40), [math]::Min(780, $wa.Height - 40)); $d.StartPosition = 'CenterScreen'
    $cs = @{ Root = $root; Form = $d; Browser = $browserSt; DiffKey = ''; Branch = '' }
    $d.Tag = $cs

    $main = New-Object System.Windows.Forms.SplitContainer; $main.Dock = 'Fill'
    # Trái: chưa stage / đã stage
    $left = New-Object System.Windows.Forms.SplitContainer; $left.Dock = 'Fill'; $left.Orientation = 'Horizontal'
    $main.Panel1.Controls.Add($left)
    $lblW = New-Object System.Windows.Forms.Label; $lblW.Dock = 'Top'; $lblW.Height = 24; $lblW.Padding = New-Object System.Windows.Forms.Padding(4, 4, 0, 0)
    $lblW.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
    $lvW = New-GitListView @(@('', 26), @('File', 380))
    $left.Panel1.Controls.Add($lvW); $left.Panel1.Controls.Add($lblW); $lvW.BringToFront()
    $mid = New-Object System.Windows.Forms.FlowLayoutPanel; $mid.Dock = 'Top'; $mid.Height = 40; $mid.WrapContents = $false
    New-ToolButton '↓ Stage' $mid { param($sender, $e) $cs = $sender.FindForm().Tag; Invoke-CommitStage $cs $true $false } | Out-Null
    New-ToolButton '⇊ Stage tất cả' $mid { param($sender, $e) $cs = $sender.FindForm().Tag; Invoke-CommitStage $cs $true $true } | Out-Null
    New-ToolButton '↑ Unstage' $mid { param($sender, $e) $cs = $sender.FindForm().Tag; Invoke-CommitStage $cs $false $false } | Out-Null
    New-ToolButton '⇈ Unstage tất cả' $mid { param($sender, $e) $cs = $sender.FindForm().Tag; Invoke-CommitStage $cs $false $true } | Out-Null
    $lblS = New-Object System.Windows.Forms.Label; $lblS.Dock = 'Top'; $lblS.Height = 24; $lblS.Padding = New-Object System.Windows.Forms.Padding(4, 4, 0, 0)
    $lblS.Font = $lblW.Font
    $lvS = New-GitListView @(@('', 26), @('File', 380))
    $left.Panel2.Controls.Add($lvS); $left.Panel2.Controls.Add($lblS); $left.Panel2.Controls.Add($mid); $lvS.BringToFront()
    $cs.LvW = $lvW; $cs.LvS = $lvS; $cs.LblW = $lblW; $cs.LblS = $lblS
    foreach ($lv in @($lvW, $lvS)) {
        $lv.Add_SelectedIndexChanged({ param($sender, $e) $cs = $sender.FindForm().Tag; if ($sender.SelectedItems.Count -eq 1 -and $sender.Focused) { Show-CommitFileDiff $cs $sender.SelectedItems[0].Tag } })
        $lv.Add_GotFocus({ param($sender, $e) $cs = $sender.FindForm().Tag; if ($sender.SelectedItems.Count -eq 1) { Show-CommitFileDiff $cs $sender.SelectedItems[0].Tag } })
    }
    $lvW.Add_DoubleClick({ param($sender, $e) Invoke-CommitStage $sender.FindForm().Tag $true $false })
    $lvS.Add_DoubleClick({ param($sender, $e) Invoke-CommitStage $sender.FindForm().Tag $false $false })
    $lvW.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -in 'Space', 'Enter') { Invoke-CommitStage $sender.FindForm().Tag $true $false; $e.Handled = $true } })
    $lvS.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -in 'Space', 'Enter', 'Delete') { Invoke-CommitStage $sender.FindForm().Tag $false $false; $e.Handled = $true } })

    # Phải: diff / commit message
    $right = New-Object System.Windows.Forms.SplitContainer; $right.Dock = 'Fill'; $right.Orientation = 'Horizontal'
    $main.Panel2.Controls.Add($right)
    $diff = New-RtbView; $cs.Diff = $diff
    $right.Panel1.Controls.Add($diff)
    $hint = New-Object System.Windows.Forms.Label; $hint.Dock = 'Top'; $hint.Height = 22; $hint.Padding = New-Object System.Windows.Forms.Padding(4, 4, 0, 0)
    $hint.Text = 'Commit message: dòng đầu ngắn, nói rõ thay đổi gì (tiếng Việt không dấu hoặc tiếng Anh). Ctrl+Enter = Commit'
    $hint.ForeColor = $Theme.Muted
    $msg = New-Object System.Windows.Forms.TextBox
    $msg.Multiline = $true; $msg.AcceptsReturn = $true; $msg.ScrollBars = 'Vertical'; $msg.Dock = 'Fill'; $msg.Font = New-Object System.Drawing.Font('Consolas', 10.5)
    $msg.Add_KeyDown({ param($sender, $e) if ($e.Control -and $e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; Invoke-CommitNow $sender.FindForm().Tag $false } })
    $cs.Msg = $msg
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel; $btns.Dock = 'Bottom'; $btns.Height = 42; $btns.FlowDirection = 'RightToLeft'; $btns.WrapContents = $false
    New-ToolButton 'Đóng' $btns { param($sender, $e) $sender.FindForm().Close() } | Out-Null
    New-ToolButton 'Commit && Push + MR' $btns { param($sender, $e) Invoke-CommitNow $sender.FindForm().Tag $true } | Out-Null
    $bc = New-ToolButton '✔ Commit' $btns { param($sender, $e) Invoke-CommitNow $sender.FindForm().Tag $false }
    New-ToolButton '⎇ Nhánh mới…' $btns { param($sender, $e) Show-CommitNewBranch $sender.FindForm().Tag } | Out-Null
    $bc.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
    $chk = New-Object System.Windows.Forms.CheckBox; $chk.Text = 'Bỏ dấu tiếng Việt'; $chk.Checked = $true; $chk.AutoSize = $true; $chk.Margin = New-Object System.Windows.Forms.Padding(10, 11, 10, 0)
    $btns.Controls.Add($chk); $cs.ChkNoAccent = $chk
    $lblB = New-Object System.Windows.Forms.Label; $lblB.AutoSize = $true; $lblB.Margin = New-Object System.Windows.Forms.Padding(10, 12, 10, 0)
    $lblB.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
    $btns.Controls.Add($lblB); $cs.LblBranch = $lblB
    $right.Panel2.Controls.Add($msg); $right.Panel2.Controls.Add($hint); $right.Panel2.Controls.Add($btns); $msg.BringToFront()

    $status = New-Object System.Windows.Forms.Label; $status.Dock = 'Bottom'; $status.Height = 22; $status.Padding = New-Object System.Windows.Forms.Padding(8, 3, 0, 0); $status.ForeColor = $Theme.Muted
    $cs.Status = $status
    $d.Controls.Add($main); $d.Controls.Add($status); $main.BringToFront()

    Set-ControlTheme $d $Theme $Theme
    Add-IconsTo $d
    foreach ($lv in @($lvW, $lvS)) { Enable-ThemedListView $lv }
    $diff.BackColor = $Theme.Surface
    $d.Add_Shown({ param($sender, $e)
        $cs = $sender.Tag
        Set-NativeTheme $sender
        $m = $sender.Controls | Where-Object { $_ -is [System.Windows.Forms.SplitContainer] }
        $m.SplitterDistance = [int]($m.Width * 0.38)
        $m.Panel1.Controls[0].SplitterDistance = [int]($m.Height * 0.5)
        $m.Panel2.Controls[0].SplitterDistance = [math]::Max(100, $m.Height - 200)
        foreach ($lv in @($cs.LvW, $cs.LvS)) { $lv.Columns[1].Width = [math]::Max(200, $lv.ClientSize.Width - 30) }
        Update-CommitChanges $cs
        [void]$cs.Msg.Focus()
    })
    $d.Add_FormClosed({ param($sender, $e) $b = $sender.Tag.Browser; if ($b -and -not $b.Form.IsDisposed) { GitB-Refresh $b }; if ($script:reposLoaded) { Load-Repos } })
    $d.Show($(if ($browserSt) { $browserSt.Form } else { $form }))
}

# Tạo nhánh từ cửa sổ Commit: mang theo thay đổi đang làm, xong cập nhật lại nhánh / danh sách file
function Show-CommitNewBranch($cs) {
    Show-NewBranchDialog @([pscustomobject]@{ Root = $cs.Root; Name = (Split-Path $cs.Root -Leaf) }) {
        param($x)
        if ($x.Form.IsDisposed) { return }
        $x.DiffKey = ''; Update-CommitChanges $x
        if ($x.Browser -and -not $x.Browser.Form.IsDisposed) { GitB-Refresh $x.Browser }
    } $cs $true
}

function Set-CommitStatus($cs, [string]$t) { if (-not $cs.Form.IsDisposed) { $cs.Status.Text = $t } }

function Update-CommitChanges($cs) {
    Start-CoreAsync '[pscustomobject]@{ Changes = @(Get-RepoChanges $p.Root); Branch = (Invoke-Git $p.Root @(''rev-parse'', ''--abbrev-ref'', ''HEAD'')).Out.Trim() }' @{ Root = $cs.Root } {
        param($r, $ctx)
        $cs = $ctx.Cs
        if ($cs.Form.IsDisposed) { return }
        if (-not $r.Ok) { Set-CommitStatus $cs "Lỗi: $($r.Value)"; return }
        $cs.Branch = $r.Value.Branch
        $cs.LblBranch.Text = "⎇ $($cs.Branch)"
        $cs.LblBranch.ForeColor = if ($cs.Branch -in 'main', 'production') { $Theme.Err } elseif ($cs.Branch -like 'hotfix/*') { $Theme.Warn } else { $Theme.Ok }
        $all = @($r.Value.Changes)
        foreach ($pair in @(@($cs.LvW, $false, $cs.LblW, 'Chưa stage'), @($cs.LvS, $true, $cs.LblS, 'Đã stage (sẽ commit)'))) {
            $lv = $pair[0]
            $keep = @($lv.SelectedItems | ForEach-Object { $_.Tag.Path })
            $items = @($all | Where-Object { $_.Staged -eq $pair[1] } | Sort-Object Path)
            $lv.BeginUpdate(); $lv.Items.Clear()
            foreach ($c in $items) {
                $it = New-Object System.Windows.Forms.ListViewItem($c.Code)
                $it.UseItemStyleForSubItems = $false
                [void]$it.SubItems.Add($(if ($c.Old) { "$($c.Old) → $($c.Path)" } else { $c.Path }))
                $it.SubItems[0].ForeColor = Get-CodeColor $c.Code
                $it.ToolTipText = switch ($c.Code) { 'M' { 'Sửa' } 'A' { 'Thêm' } 'D' { 'Xoá' } 'R' { 'Đổi tên' } '?' { 'File mới chưa track' } 'U' { 'Xung đột' } default { $c.Code } }
                $it.Tag = $c
                [void]$lv.Items.Add($it)
                if ($keep -contains $c.Path) { $it.Selected = $true }
            }
            $lv.EndUpdate()
            $pair[2].Text = "$($pair[3]) ($($items.Count))"
        }
        $nS = $cs.LvS.Items.Count
        Set-CommitStatus $cs $(if ($all.Count) { "$($cs.LvW.Items.Count) file chưa stage · $nS file đã stage · double-click / Space để chuyển qua lại" } else { 'Không có thay đổi nào để commit.' })
        if (-not $cs.LvW.SelectedItems.Count -and -not $cs.LvS.SelectedItems.Count) {
            $first = @($cs.LvW.Items) + @($cs.LvS.Items) | Select-Object -First 1
            if ($first) { Show-CommitFileDiff $cs $first.Tag } else { $cs.Diff.Text = '' }
        }
    } @{ Cs = $cs }
}

function Show-CommitFileDiff($cs, $c) {
    $key = "$($c.Staged)|$($c.Path)"
    if ($key -eq $cs.DiffKey) { return }
    $cs.DiffKey = $key
    Start-CoreAsync 'Get-WorkingDiff $p.Root $p.Path $p.Staged $p.Code' @{ Root = $cs.Root; Path = $c.Path; Staged = $c.Staged; Code = $c.Code } {
        param($r, $ctx)
        $cs = $ctx.Cs
        if ($cs.Form.IsDisposed -or $cs.DiffKey -ne $ctx.Key) { return }
        $t = if ($r.Ok) { [string]$r.Value } else { "Lỗi: $($r.Value)" }
        if (-not $t.Trim()) { $t = '(Không có nội dung diff - file nhị phân hoặc chỉ đổi quyền)' }
        Show-DiffText $cs.Diff $t
    } @{ Cs = $cs; Key = $key }
}

function Invoke-CommitStage($cs, [bool]$stage, [bool]$all) {
    $lv = if ($stage) { $cs.LvW } else { $cs.LvS }
    $paths = @($lv.SelectedItems | ForEach-Object { $_.Tag.Path } | Sort-Object -Unique)
    if (-not $all -and -not $paths.Count) { Set-CommitStatus $cs 'Chọn file trước (Ctrl/Shift + click để chọn nhiều).'; return }
    $cs.DiffKey = ''
    Start-CoreAsync 'Invoke-RepoStage $p.Root $p.Paths $p.Stage -All:$p.All' @{ Root = $cs.Root; Paths = $paths; Stage = $stage; All = $all } {
        param($r, $ctx)
        $cs = $ctx.Cs
        if ($cs.Form.IsDisposed) { return }
        if (-not $r.Ok) { [System.Windows.Forms.MessageBox]::Show([string]$r.Value, 'Git', 'OK', 'Warning') | Out-Null }
        Update-CommitChanges $cs
    } @{ Cs = $cs }
}

function Invoke-CommitNow($cs, [bool]$push) {
    $m = $cs.Msg.Text.Trim()
    if (-not $m) { Set-CommitStatus $cs 'Nhập commit message trước.'; [void]$cs.Msg.Focus(); return }
    if (-not $cs.LvS.Items.Count) { Set-CommitStatus $cs 'Chưa có file nào được stage (chọn file ở trên rồi bấm ↓ Stage).'; return }
    if ($cs.ChkNoAccent.Checked) { $m = ConvertTo-NoDiacritics $m }
    if ($cs.Branch -in 'main', 'production') {
        $ans = [System.Windows.Forms.MessageBox]::Show("Đang ở nhánh $($cs.Branch).`nQuy trình Sunhouse: mọi thay đổi vào main / production phải qua Merge Request, không commit thẳng.`n`nYes = tạo nhánh mới trước (mang theo các thay đổi)`nNo = vẫn commit lên $($cs.Branch)`nCancel = huỷ", 'Commit', 'YesNoCancel', 'Warning')
        if ($ans -eq 'Yes') { Show-CommitNewBranch $cs; return }
        if ($ans -ne 'No') { return }
    }
    Set-CommitStatus $cs 'Đang commit...'
    $code = { $out = Invoke-RepoCommit $p.Root $p.Msg; if ($p.Push) { $pr = Push-RepoBranchForMr $p.Root; [pscustomobject]@{ Msg = "$out · $($pr.Msg)"; Url = $pr.Url } } else { [pscustomobject]@{ Msg = $out; Url = $null } } }.ToString()
    Start-CoreAsync $code @{ Root = $cs.Root; Msg = $m; Push = $push } {
        param($r, $ctx)
        $cs = $ctx.Cs
        if ($cs.Form.IsDisposed) { return }
        if (-not $r.Ok) { Set-CommitStatus $cs 'Lỗi.'; [System.Windows.Forms.MessageBox]::Show([string]$r.Value, 'Commit', 'OK', 'Warning') | Out-Null; Update-CommitChanges $cs; return }
        $cs.Msg.Clear()
        Set-CommitStatus $cs ("✓ " + $r.Value.Msg)
        Set-Status ("✓ " + $r.Value.Msg)
        if ($r.Value.Url) { Start-Process $r.Value.Url }
        $cs.DiffKey = ''
        Update-CommitChanges $cs
        if ($cs.Browser -and -not $cs.Browser.Form.IsDisposed) { GitB-Refresh $cs.Browser }
    } @{ Cs = $cs }
}

# ---------- Sắp xếp cột dùng chung cho các bảng (Dịch vụ, Sức khỏe, K3s, Git) ----------
# Bấm tiêu đề cột: tăng dần, bấm lại: giảm dần. Số (port, %, MB/GB, ms, tuổi 5d/3h) so theo giá trị; ô trống luôn xuống cuối.
# Bảng tự làm mới thì gọi lại Sort-ListView để giữ thứ tự đã chọn.
$script:lvSort = @{}
function Get-CellSortKey([string]$t) {
    $t = ($t -replace '^[^\p{L}\p{N}]+', '').Trim()           # bỏ ký hiệu đầu dòng (● ○ ⚠ ✓)
    if (-not $t) { return @(2, 0, '') }
    if ($t -match '^(-?[\d]+(?:[.,]\d+)?)\s*(%|ms|KB|MB|GB)?$') {
        $n = [double]($Matches[1] -replace ',', '.')
        switch ($Matches[2]) { 'GB' { $n *= 1024 } 'KB' { $n /= 1024 } }
        return @(0, $n, '')
    }
    if ($t -match '^(\d+)([smhd])$') { return @(0, [double]$Matches[1] * @{ s = 1; m = 60; h = 3600; d = 86400 }[$Matches[2]], '') }
    if ($t -match '^(\d+)/(\d+)$') { return @(0, [double]$Matches[1] + [double]$Matches[2] / 1000, '') }      # Ready 1/2
    @(1, 0, $t.ToLowerInvariant())
}
function Sort-ListView($lv) {
    $st = $script:lvSort[$lv]
    if (-not $st -or $st.Col -lt 0 -or $st.Col -ge $lv.Columns.Count -or $lv.Items.Count -lt 2) { return }
    $sel = @($lv.SelectedItems); $foc = $lv.FocusedItem
    $col = $st.Col
    $rows = foreach ($it in $lv.Items) {
        $txt = if ($col -lt $it.SubItems.Count) { $it.SubItems[$col].Text } else { '' }
        $k = Get-CellSortKey $txt
        [pscustomobject]@{ It = $it; R = $k[0]; N = $k[1]; T = $k[2]; Name = $it.Text }
    }
    $sorted = @($rows | Sort-Object @{ Expression = 'R' }, @{ Expression = 'N'; Descending = $st.Desc }, @{ Expression = 'T'; Descending = $st.Desc }, @{ Expression = 'Name' })
    $lv.BeginUpdate()
    $lv.Items.Clear()
    $lv.Items.AddRange([System.Windows.Forms.ListViewItem[]]@($sorted | ForEach-Object It))
    foreach ($it in $sel) { $it.Selected = $true }
    if ($foc) { $foc.Focused = $true }
    $lv.EndUpdate()
}
function Enable-ColumnSort($lv) {
    $lv.HeaderStyle = 'Clickable'
    $script:lvSort[$lv] = @{ Col = -1; Desc = $false; Titles = @($lv.Columns | ForEach-Object Text) }
    $lv.Add_ColumnClick({
        param($sender, $e)
        $st = $script:lvSort[$sender]
        if ($st.Col -eq $e.Column) { $st.Desc = -not $st.Desc } else { $st.Col = $e.Column; $st.Desc = $false }
        for ($i = 0; $i -lt $sender.Columns.Count -and $i -lt $st.Titles.Count; $i++) {
            $sender.Columns[$i].Text = $st.Titles[$i] + $(if ($i -eq $st.Col) { if ($st.Desc) { ' ▼' } else { ' ▲' } } else { '' })
        }
        Sort-ListView $sender
    })
}

foreach ($lv in @($list, $lvPods, $lvCpu, $lvRam, $lvRepos)) { Enable-ColumnSort $lv }

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

$gGeneral = New-Group 'Chung (tên hiển thị · giao diện · menu)' 10 104 $pageSettings
New-Label 'Tên hiển thị' 12 30 110 $gGeneral | Out-Null
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(125, 27); $txtName.Size = New-Object System.Drawing.Size(150, 26)
$txtName.Text = $AppName
$gGeneral.Controls.Add($txtName)
New-Button 'Đổi tên' 281 24 80 $gGeneral {
    $new = $txtName.Text.Trim()
    if (-not $new) { Set-Status 'Tên không được để trống.'; return }
    $PanelConfig.appName = $new; Save-PanelConfig $PanelConfig
    Rename-OwnShortcuts $new
    $script:AppName = $new
    $form.Text = "$new  v$PanelVersion"
    $tray.Text = $(if ($new.Length -gt 60) { $new.Substring(0, 60) } else { $new })
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DevOpsPanel'
    if (Test-Path $uninstallKey) { Set-ItemProperty $uninstallKey -Name DisplayName -Value $new }
    Set-Status "Đã đổi tên thành '$new' (cửa sổ, khay hệ thống, shortcut)."
} | Out-Null
$cbTheme = New-Object System.Windows.Forms.ComboBox
$cbTheme.DropDownStyle = 'DropDownList'
$cbTheme.Location = New-Object System.Drawing.Point(369, 27); $cbTheme.Size = New-Object System.Drawing.Size(128, 28)
[void]$cbTheme.Items.AddRange(@('Giao diện sáng', 'Giao diện tối'))
$cbTheme.SelectedIndex = $(if ($script:ThemeName -eq 'dark') { 1 } else { 0 })
$cbTheme.Add_SelectedIndexChanged({
    $name = if ($cbTheme.SelectedIndex -eq 1) { 'dark' } else { 'light' }
    if ($name -eq $script:ThemeName) { return }
    $PanelConfig.theme = $name; Save-PanelConfig $PanelConfig
    Set-Theme $name
    Set-Status ('Đã chuyển sang ' + $cbTheme.SelectedItem.ToString().ToLower() + '.')
})
$gGeneral.Controls.Add($cbTheme)
New-Label 'Menu tab' 12 64 110 $gGeneral | Out-Null
$cbNav = New-Object System.Windows.Forms.ComboBox
$cbNav.DropDownStyle = 'DropDownList'
$cbNav.Location = New-Object System.Drawing.Point(125, 61); $cbNav.Size = New-Object System.Drawing.Size(236, 28)
[void]$cbNav.Items.AddRange(@('Trên dải tiêu đề (gọn)', 'Bên trái (thu gọn được)'))
$cbNav.SelectedIndex = $(if ($PanelConfig.navLayout -eq 'side') { 1 } else { 0 })
$cbNav.Add_SelectedIndexChanged({
    $PanelConfig.navLayout = @('top', 'side')[$cbNav.SelectedIndex]; Save-PanelConfig $PanelConfig
    Set-NavLayout
    Set-Status ('Menu tab: ' + $cbNav.SelectedItem)
})
$gGeneral.Controls.Add($cbNav)

$gWsl = New-Group 'WSL / PostgreSQL (áp dụng sau khi mở lại panel)' 122 100 $pageSettings
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

$gScan = New-Group 'Tab Ứng dụng: thư mục gốc để quét project' 230 250 $pageSettings
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
$lblScanHint.Size = New-Object System.Drawing.Size(486, 36); $lblScanHint.ForeColor = $Theme.Muted
New-Button 'Lưu và quét ngay' 12 212 160 $gScan { Save-SettingsTab; Invoke-ProjectScan } | Out-Null
New-Button 'Xuất danh mục…' 180 212 150 $gScan {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Danh mục app (*.json)|*.json'; $dlg.FileName = "devops-apps-$($env:COMPUTERNAME.ToLower()).json"
    if ($dlg.ShowDialog() -eq 'OK') { try { Set-Status (Export-AppsCatalog $dlg.FileName) } catch { Set-Status "Lỗi: $($_.Exception.Message)" } }
} | Out-Null
New-Button 'Nhập danh mục…' 338 212 150 $gScan {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Danh mục app (*.json)|*.json'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try { $msg = Import-AppsCatalog $dlg.FileName; Set-Status $msg; [System.Windows.Forms.MessageBox]::Show($msg, 'Nhập danh mục', 'OK', 'Information') | Out-Null }
    catch { [System.Windows.Forms.MessageBox]::Show("Không nhập được: $($_.Exception.Message)", 'Nhập danh mục', 'OK', 'Warning') | Out-Null }
    $appsSync.Kick = $true
} | Out-Null

function Save-SettingsTab {
    $PanelConfig.distro = $(if ($cbDistro.SelectedItem -and $cbDistro.SelectedItem -ne '(tự chọn)') { [string]$cbDistro.SelectedItem } else { '' })
    $PanelConfig.pgUbuntuPort = [int]$numPg.Value
    $PanelConfig.scanRoots = @($lbRoots.Items | ForEach-Object { [string]$_ })
    Save-PanelConfig $PanelConfig
    $ranges = @($txtRanges.Text -split '[,;\s]+' | Where-Object { $_ -match '^(\d+)-(\d+)$' } |
        ForEach-Object { , @([int]$Matches[1], [int]$Matches[2]) })
    if ($ranges.Count) { Save-AppsConfig $ranges (Get-AppsConfig).Apps }
}

New-Button 'Lưu và mở lại panel' 6 490 200 $pageSettings {
    Save-SettingsTab
    $script:restartRequested = $true; $script:exiting = $true; $form.Close()
} | Out-Null
New-Button 'Chẩn đoán tốc độ' 212 490 150 $pageSettings {
    Set-Status 'Đang đo từng bước (có thể mất 10-30 giây)...'
    $form.Cursor = 'AppStarting'
    Start-CoreAsync 'Get-PerfDiagnostics' @{} {
        param($r, $ctx)
        $form.Cursor = 'Default'
        $txt = [string]$r.Value
        [System.Windows.Forms.Clipboard]::SetText($txt)
        Set-Status 'Đã đo xong - kết quả đã copy vào clipboard.'
        [System.Windows.Forms.MessageBox]::Show($txt + "`r`n`r`n(Đã copy vào clipboard)", 'Chẩn đoán tốc độ', 'OK', 'Information') | Out-Null
    }
} | Out-Null
$lblDataDir = New-Label "Dữ liệu: $DataDir" 370 496 145 $pageSettings
$lblDataDir.ForeColor = $Theme.Muted; $lblDataDir.AutoEllipsis = $true

# ---------- Tab Trợ giúp ----------
$lblHelpTitle = New-Label $AppName 12 10 490 $pageHelp
$lblHelpTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHelpTitle.Height = 30
$lblHelpVer = New-Label "PowerShell $($PSVersionTable.PSVersion)  ·  Windows $([Environment]::OSVersion.Version)  ·  $env:COMPUTERNAME" 12 42 490 $pageHelp      # số phiên bản nằm ở dòng cập nhật bên dưới
# Dòng phiên bản: chữ thường + các link (phiên bản mới nhất -> trang GitHub, Cài bản mới, Kiểm tra lại)
$lnkUpd = New-Object System.Windows.Forms.LinkLabel
$lnkUpd.Location = New-Object System.Drawing.Point(12, 66); $lnkUpd.Size = New-Object System.Drawing.Size(498, 22)
$lnkUpd.LinkBehavior = 'HoverUnderline'
$lnkUpd.Add_LinkClicked({
    param($sender, $e)
    switch ([string]$e.Link.LinkData) {
        'release'  { Start-Process $(if ($script:latestRel) { $script:latestRel.Url } else { "https://github.com/$UpdateRepo/releases" }) }
        'releases' { Start-Process "https://github.com/$UpdateRepo/releases" }
        'install'  { Show-UpdateDialog }
        'check'    { Start-UpdateCheck -Manual }
    }
})
$pageHelp.Controls.Add($lnkUpd)
# Ghép dòng từ các phần @(chữ, dữ liệu link hoặc $null)
function Set-UpdLine([object[]]$parts, $color) {
    $text = ''; $links = @()
    foreach ($pt in $parts) {
        if ($pt[1]) { $links += , @($text.Length, $pt[0].Length, $pt[1]) }
        $text += $pt[0]
    }
    $lnkUpd.Links.Clear(); $lnkUpd.Text = $text; $lnkUpd.Links.Clear()
    foreach ($l in $links) { [void]$lnkUpd.Links.Add($l[0], $l[1], $l[2]) }
    $lnkUpd.ForeColor = $color
}
$lblHelpVer.ForeColor = $Theme.Muted

# RichTextBox thay TextBox: dòng dài tự cuộn nhưng vẫn thẳng hàng với chữ phía trên (hanging indent), link bấm được
$txtHelp = New-Object System.Windows.Forms.RichTextBox
$txtHelp.ReadOnly = $true; $txtHelp.ScrollBars = 'Vertical'; $txtHelp.DetectUrls = $true
$txtHelp.BackColor = $Theme.Surface
$txtHelp.Location = New-Object System.Drawing.Point(12, 96); $txtHelp.Size = New-Object System.Drawing.Size(498, 314)
$txtHelp.Add_LinkClicked({ param($sender, $e) Start-Process $e.LinkText })
$HelpText = @"
DỊCH VỤ
  Bật / tắt WSL, PostgreSQL, K3s, Docker, Tailscale. Chuột phải một dòng để Start / Stop / Restart.
  Nhóm PostgreSQL trong WSL thu gọn sẵn - bấm "▸ PostgreSQL…" để mở.
  Mục tiêu hôm nay (bên phải): gõ rồi Enter để thêm, tick khi xong; chuột phải để sửa / để sang ngày mai / xoá.
  Mỗi ngày lần đầu mở panel, trợ lý hỏi mục tiêu (tắt được trong hộp thoại); chiều tối còn việc chưa xong sẽ nhắc ở khay.

ỨNG DỤNG
  • Chọn nhiều app: Ctrl / Shift + click, Ctrl+A. Start / Stop / Restart chạy cho cả loạt.
  • Chuột phải: mở web, xem log, mở thư mục / terminal / VS Code, copy URL, Start / Stop cả nhóm.
  • Cột Trạng thái: biểu tượng xoay ◐ = đang khởi động / dừng; ✗ Lỗi = app không lên được
    (rê chuột vào dòng để xem lý do, bấm Xem log để xem chi tiết).
  • Bấm tiêu đề cột để sắp xếp (mặc định theo Trạng thái), bấm lại để đảo chiều.
  • Ô Tìm (Ctrl+F): theo tên, nhóm, loại, port, trạng thái; gõ không dấu được, nhiều từ = khớp tất cả.
    Ví dụ: hrm · frontend · dang chay · loi · 7003.   Esc để xoá.
  • Khung Git: nhánh hiện tại, Fetch, Pull (chỉ fast-forward), chuyển nhánh.
  • Danh mục app ở apps.json (tab Cài đặt → Sửa apps.json), hoặc bấm Quét project.
  • Cột CPU / RAM / Phản hồi (mặc định ẩn): chuột phải → "Hiện cột CPU / RAM / Phản hồi".
  • Bộ app ▾: lưu các app hay chạy cùng nhau; "Start theo thứ tự" chạy tool → backend → BFF → frontend, đợi từng đợt lên.
  • App đang chạy bị tắt bất ngờ → báo ở khay. Chuột phải → "Tự khởi động lại khi sập" (tối đa 3 lần / 10 phút).
  • Port bị app khác chiếm → chuột phải → "Giải phóng port".
  • Gỡ app khỏi panel: nút Gỡ / phím Delete / chuột phải (không xoá code, quét lại không thêm lại).
    Gỡ nhầm: chuột phải → Khôi phục app đã gỡ.

GIT
  Tất cả repo trong danh mục: nhánh, chậm/nhanh hơn remote (↓ ↑), số file sửa; Fetch / Pull nhiều repo một lúc.
  Tạo nhánh theo git-flow Sunhouse:
    feature/ · fix/ · bugfix/  tách từ main → Push + MR → Merge Request vào main
    hotfix/ (chỉ lỗi gấp trên production)  tách từ production → MR vào production → cherry-pick sang main
  Chọn 1 repo để xem lịch sử commit dạng graph (tất cả nhánh hoặc nhánh hiện tại): mỗi nhánh một màu riêng,
    chấm tròn = commit, vòng rỗng = merge commit, quầng sáng = HEAD; nhãn nhánh local xanh lá, remote xanh dương, tag cam.
  Double-click repo → cửa sổ Git (kiểu Git Extensions): cây nhánh (double-click để checkout), graph commit có màu,
    nhãn nhánh / tag, thông tin + file + diff của commit.
  Commit…: danh sách Chưa stage / Đã stage, ↓ Stage · ↑ Unstage (double-click / Space), diff từng file,
    commit message (tự bỏ dấu), Commit hoặc Commit & Push + mở Merge Request.
    Nút "⎇ Nhánh mới…" trong màn hình Commit: tạo nhánh mới mang theo các file đang sửa (lỡ sửa trên main).

AI CODE
  Làm việc với Claude Code, Codex hoặc Gemini CLI ngay trong panel (cần cài CLI tương ứng, bấm "Cài / cập nhật CLI").
  • Chip thư mục ở thanh trên: chọn repo / thư mục project. Chip trong ô soạn: công cụ (Claude / Codex / Gemini), quyền, model.
  • Quyền: Chỉ đọc = hỏi đáp / lên kế hoạch; Cho phép sửa file = AI sửa code trong thư mục; Toàn quyền = sửa file + chạy lệnh.
  • Gõ yêu cầu, Enter để gửi (Shift+Enter xuống dòng). Các lượt sau tiếp tục cùng phiên; "Phiên mới" để bắt đầu lại;
    nút tròn chuyển thành ■ khi AI đang chạy - bấm để dừng. Dòng "▸ đọc 2 file, sửa 1 file" bấm vào để xem chi tiết.
  • Dải phía trên ô soạn: nhánh git, số dòng thêm / bớt; bấm "Xem thay đổi / Commit" để review diff rồi commit.
  • "Xem thay đổi / Commit…" mở màn hình Commit để review diff của AI rồi commit / push.
  • "Mở terminal" mở CLI ở chế độ tương tác (đăng nhập lần đầu, hoặc tiếp tục phiên đang chat).
  Từ tab Git: chuột phải repo → "Code với AI tại repo này".

SỨC KHỎE
  CPU, RAM, WSL, pin, mạng, tiến trình nặng nhất. Cảnh báo hiện ở khay hệ thống.

K3S
  Danh sách pod; double-click hoặc chuột phải để xem log, describe, restart pod; mở k9s.
  Dòng Mạng: IP WSL hiện tại, IP k3s đang giữ, ingress và cổng của nó. Đổi Wi-Fi / khởi động lại máy làm IP đổi
    nhưng k3s vẫn giữ IP cũ → ingress chết, app gọi vào báo "actively refused". Dòng chuyển đỏ → bấm "Sửa mạng K3s".

CÀI ĐẶT
  Tên hiển thị, giao diện sáng / tối, distro WSL, port PostgreSQL, thư mục gốc để quét project.
  Menu tab: trên dải tiêu đề (mặc định, gọn - thiếu chỗ thì chỉ hiện icon) hoặc bên trái (bấm "Thu gọn menu" để chỉ còn icon).
  Xuất / nhập danh mục app (kèm bộ app) để chia sẻ cho người trong team - tự đổi đường dẫn theo máy.
  Máy chạy chậm / không load được Git → bấm "Chẩn đoán tốc độ" rồi gửi kết quả cho người hỗ trợ.

TÀI LIỆU
  WSL: cài đặt https://learn.microsoft.com/vi-vn/windows/wsl/install · lệnh cơ bản https://learn.microsoft.com/vi-vn/windows/wsl/basic-commands
  K3s: cài nhanh https://docs.k3s.io/quick-start · tài liệu https://docs.k3s.io/
  kubectl: https://kubernetes.io/vi/docs/reference/kubectl/cheatsheet/ · k9s: https://k9scli.io/topics/commands/

CẬP NHẬT
  Panel tự kiểm tra bản mới trên GitHub (lúc mở và 12 giờ / lần). Có bản mới: link dưới cùng cửa sổ → Cài bản mới.

PHÍM TẮT
  F1 Trợ giúp · Ctrl+F tìm app · F5 làm mới danh sách app · Enter mở web app đang chọn · Delete gỡ app

KHAY HỆ THỐNG
  Bấm X chỉ thu panel xuống khay. Chuột phải icon → Thoát panel để tắt hẳn.

DỮ LIỆU
  $DataDir
"@
# Mỗi dòng là 1 đoạn: dấu cách đầu dòng -> SelectionIndent; dòng "• " cuộn xuống thẳng hàng sau dấu •;
# dòng tiếp nối (thụt sâu hơn dòng • phía trên) thẳng hàng với chữ của dòng • đó; tiêu đề viết hoa in đậm
function Show-HelpText {
    $f = $txtHelp.Font
    $nf = [System.Windows.Forms.TextFormatFlags]::NoPadding
    $sp = ([System.Windows.Forms.TextRenderer]::MeasureText('a        a', $f, [System.Drawing.Size]::Empty, $nf).Width -
           [System.Windows.Forms.TextRenderer]::MeasureText('aa', $f, [System.Drawing.Size]::Empty, $nf).Width) / 8
    $bulletW = $null   # bề rộng "• " đo ngay trong RichTextBox (TextRenderer đo khác cách RichTextBox vẽ)
    $bold = New-Object System.Drawing.Font($f, [System.Drawing.FontStyle]::Bold)
    $txtHelp.Clear()
    $prev = $null      # dòng • gần nhất: @{ Lvl; TextAt }
    foreach ($line in ($HelpText -split '\r?\n')) {
        $m = [regex]::Match($line, '^( *)(• )?(.*)$')
        $lvl = $m.Groups[1].Length; $isBullet = $m.Groups[2].Success; $body = $m.Groups[3].Value
        $indent = [int]($lvl * $sp)
        if (-not $body -or $isBullet) { $prev = $null }
        elseif ($prev -and $lvl -gt $prev.Lvl) { $indent = $prev.TextAt }
        else { $prev = $null }
        $start = $txtHelp.TextLength
        $txtHelp.AppendText($m.Groups[2].Value + $body + "`n")
        $txtHelp.Select($start, $txtHelp.TextLength - $start)
        $txtHelp.SelectionFont = if ($lvl -eq 0 -and $body -and $body -ceq $body.ToUpper()) { $bold } else { $f }
        $txtHelp.SelectionIndent = $indent
        $txtHelp.SelectionHangingIndent = 0
        if ($isBullet) {
            if ($null -eq $bulletW) { $bulletW = $txtHelp.GetPositionFromCharIndex($start + 2).X - $txtHelp.GetPositionFromCharIndex($start).X }
            $txtHelp.SelectionHangingIndent = $bulletW
            $prev = @{ Lvl = $lvl; TextAt = $indent + $bulletW }
        }
    }
    $txtHelp.Select(0, 0)
}
$txtHelp.TabStop = $false
$pageHelp.Controls.Add($txtHelp)
Show-HelpText      # sau khi gắn vào tab mới có font Segoe UI của form để đo
$pageHelp.Add_Enter({ $txtHelp.Select(0, 0) })     # ô chữ nhận focus thì có thể bôi đen - bỏ chọn

$lblContact = New-Label 'Hỗ trợ / góp ý:' 12 420 105 $pageHelp
$lnkEmail = New-Object System.Windows.Forms.LinkLabel
$lnkEmail.Text = $SupportEmail
$lnkEmail.Location = New-Object System.Drawing.Point(117, 420); $lnkEmail.AutoSize = $true
$lnkEmail.Add_LinkClicked({
    $subject = [Uri]::EscapeDataString("[$AppName v$PanelVersion] ")
    try { Start-Process "mailto:${SupportEmail}?subject=$subject" } catch { Set-Status 'Máy chưa có ứng dụng email mặc định - dùng nút Copy email.' }
})
$pageHelp.Controls.Add($lnkEmail)
New-Button 'Copy email' 12 448 110 $pageHelp { [System.Windows.Forms.Clipboard]::SetText($SupportEmail); Set-Status "Đã copy $SupportEmail" } | Out-Null
New-Button 'Copy thông tin máy' 128 448 160 $pageHelp {
    $info = "$AppName v$PanelVersion`r`nMáy: $env:COMPUTERNAME · Windows $([Environment]::OSVersion.Version) · PowerShell $($PSVersionTable.PSVersion)`r`nWSL: $(if ($Distro) { $Distro } else { 'không có' }) · Git: $(if ($GitExe) { $GitExe } else { 'không có' })`r`nThư mục cài: $PSScriptRoot`r`nDữ liệu: $DataDir"
    [System.Windows.Forms.Clipboard]::SetText($info)
    Set-Status 'Đã copy thông tin máy - dán vào email khi cần hỗ trợ.'
} | Out-Null
New-Button 'Thư mục dữ liệu' 294 448 140 $pageHelp { Start-Process explorer.exe $DataDir } | Out-Null

# ---------- Tab AI Code: làm việc với Claude Code / Codex / Gemini CLI ngay trong panel ----------
# Mỗi lần Gửi chạy CLI ở chế độ không tương tác tại thư mục đã chọn: prompt đi qua stdin (khỏi lo escape dòng lệnh),
# kết quả là JSON từng dòng. Runspace nền đọc stdout vào hàng đợi, timer giao diện vẽ ra khung chat.
# Lượt sau nối tiếp phiên cũ bằng session id CLI trả về; "Mở terminal" mở đúng phiên đó ở chế độ tương tác.
$AiTools = [ordered]@{
    claude = @{ Name = 'Claude Code'; Exe = 'claude'; Color = (New-Rgb 217 119 87); Pkg = '@anthropic-ai/claude-code'; Models = @('sonnet', 'opus', 'haiku') }
    codex  = @{ Name = 'Codex';       Exe = 'codex';  Color = (New-Rgb 16 163 127); Pkg = '@openai/codex';            Models = @() }
    gemini = @{ Name = 'Gemini CLI';  Exe = 'gemini'; Color = (New-Rgb 66 133 244); Pkg = '@google/gemini-cli';       Models = @('gemini-2.5-pro', 'gemini-2.5-flash') }
}
$AiModes = @('plan', 'edit', 'full')
$AiFont = New-Object System.Drawing.Font('Segoe UI', 10.5)
$AiHead = New-Object System.Drawing.Font('Segoe UI Semibold', 11.5)
$AiMonoSmall = New-Object System.Drawing.Font('Consolas', 9)
$AiBold = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$AiSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$AiMono = New-Object System.Drawing.Font('Consolas', 9.5)
$script:ai = @{ Key = ''; Session = $null; FullOk = $false; Buf = ''; Title = $null }
$script:aiRun = $null

function Find-AiExe([string]$name) {
    $c = Get-Command "$name.exe", "$name.cmd" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    Find-FirstPath @("$env:APPDATA\npm\$name.cmd", "$env:USERPROFILE\.local\bin\$name.exe")
}
# Tham số dòng lệnh: chỉ gồm từ khoá cố định + model / session đã kiểm tra -> không cần escape
function Get-AiArgs([string]$tool, [string]$mode, [string]$model, [string]$session, [switch]$Interactive) {
    $a = New-Object System.Collections.ArrayList
    switch ($tool) {
        'claude' {
            if (-not $Interactive) { [void]$a.AddRange(@('-p', '--output-format', 'stream-json', '--verbose', '--permission-mode', @{ plan = 'plan'; edit = 'acceptEdits'; full = 'bypassPermissions' }[$mode])) }
            if ($model) { [void]$a.AddRange(@('--model', $model)) }
            if ($session) { [void]$a.AddRange(@('--resume', $session)) }
        }
        'codex' {
            if ($Interactive) { if ($session) { [void]$a.AddRange(@('resume', $session)) }; break }
            [void]$a.AddRange(@('exec', '--json', '--skip-git-repo-check'))
            [void]$a.AddRange(@{ plan = @('-s', 'read-only'); edit = @('--full-auto'); full = @('--dangerously-bypass-approvals-and-sandbox') }[$mode])
            if ($model) { [void]$a.AddRange(@('-m', $model)) }
            if ($session) { [void]$a.AddRange(@('resume', $session)) }
            [void]$a.Add('-')                          # đọc prompt từ stdin
        }
        'gemini' {
            if (-not $Interactive) { [void]$a.AddRange(@('--output-format', 'stream-json', '--approval-mode', @{ plan = 'default'; edit = 'auto_edit'; full = 'yolo' }[$mode])) }
            if ($model) { [void]$a.AddRange(@('-m', $model)) }
            if ($session) { [void]$a.AddRange(@('--resume', $session)) }
        }
    }
    @($a)
}
# .cmd (cài bằng npm) phải chạy qua cmd.exe
function Get-AiCommand([string]$exe, [string[]]$cliArgs) {
    $joined = $cliArgs -join ' '
    if ($exe -like '*.cmd') { @{ File = "$env:WINDIR\System32\cmd.exe"; Args = "/d /s /c `"`"$exe`" $joined`"" } }
    else { @{ File = $exe; Args = $joined } }
}

# ---- Khung chat kiểu Claude desktop: mỗi phần tử là 1 control xếp dọc trong cột giữa ($aiChat) ----
#   user = bong bóng bên phải · md = câu trả lời (RichTextBox chọn / copy được) · act = nhóm thao tác tool (bấm để mở)
#   note = dòng chú thích nhỏ · err = khung lỗi
# Control có Name 'bg:<màu theme>' thì Set-ControlTheme tô nền theo màu đó; chữ của câu trả lời lưu lại để vẽ lại khi đổi theme.
$script:aiItems = New-Object System.Collections.ArrayList
$script:aiRtb = $null
$script:aiLaying = $false; $script:aiRelayout = $false; $script:aiStick = $true
function Test-AiAtBottom { (-$aiChat.AutoScrollPosition.Y + $aiChat.ClientSize.Height) -ge ($aiChat.AutoScrollMinSize.Height - 60) }
function Add-AiItem([string]$kind, $ctl) {
    $script:aiStick = Test-AiAtBottom
    $aiChat.Controls.Add($ctl)
    [void]$script:aiItems.Add(@{ Kind = $kind; Ctl = $ctl })
    Update-AiLayout -Scroll:$script:aiStick
}
function Clear-AiChat {
    foreach ($it in @($script:aiItems)) { $aiChat.Controls.Remove($it.Ctl); $it.Ctl.Dispose() }
    $script:aiItems.Clear(); $script:aiRtb = $null
    Update-AiLayout
}
function Move-AiScroll([int]$d) { $aiChat.AutoScrollPosition = New-Object System.Drawing.Point(0, [math]::Max(0, -$aiChat.AutoScrollPosition.Y + $d)) }

# Ghi 1 đoạn chữ vào câu trả lời đang viết (tạo mới nếu phần tử cuối không phải câu trả lời)
function Add-AiRun([string]$text, $color, $fnt, [int]$indent = 0, [switch]$NoLog, $rtb = $null) {
    if (-not $rtb) {
        $last = if ($script:aiItems.Count) { $script:aiItems[$script:aiItems.Count - 1] } else { $null }
        if (-not $last -or $last.Kind -ne 'md') {
            $r = New-Object System.Windows.Forms.RichTextBox
            $r.Name = 'bg:Back'; $r.BackColor = $Theme.Back; $r.BorderStyle = 'None'; $r.ReadOnly = $true; $r.ScrollBars = 'None'
            $r.DetectUrls = $true; $r.WordWrap = $true; $r.Font = $AiFont; $r.TabStop = $false; $r.Width = 600
            $r.Tag = @{ H = 20; Runs = New-Object System.Collections.ArrayList }
            $r.Add_ContentsResized({ param($s, $e) if ($s.Tag.H -ne $e.NewRectangle.Height) { $s.Tag.H = $e.NewRectangle.Height; Update-AiLayout -Scroll:$script:aiStick } })
            $r.Add_LinkClicked({ param($s, $e) Start-Process $e.LinkText })
            $r.Add_MouseWheel({ param($s, $e) Move-AiScroll (-$e.Delta) })
            Add-AiItem 'md' $r
            [void]$r.Handle
            $script:aiRtb = $r
        }
        $rtb = $script:aiRtb
    }
    if (-not $NoLog) { [void]$rtb.Tag.Runs.Add(@($text, $color, $fnt, $indent)) }
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $rtb.SelectionFont = $fnt
    $rtb.SelectionColor = $(if ($color -is [string]) { $Theme[$color] } else { $color })
    $rtb.SelectionIndent = $indent
    $rtb.SelectedText = $text
}
function New-AiLabel([string]$text, [string]$colorKey, $fnt) {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $true; $l.Text = $text; $l.Font = $fnt; $l.ForeColor = $Theme[$colorKey]; $l.UseMnemonic = $false
    $l
}
function Add-AiUser([string]$text) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Name = 'bg:Back'; Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.Clear($s.Parent.BackColor)
        $path = New-RoundRect 0 0 ($s.Width - 1) ($s.Height - 1) 14
        $b = New-Object System.Drawing.SolidBrush($Theme.Sel); $g.FillPath($b, $path); $b.Dispose(); $path.Dispose()
    })
    $l = New-AiLabel $text 'Text' $AiFont
    $l.Name = 'bg:Sel'; $l.BackColor = $Theme.Sel
    $p.Controls.Add($l)
    Add-AiItem 'user' $p
}
function Add-AiNote([string]$t) { Add-AiItem 'note' (New-AiLabel $t 'Muted' $AiSmall) }
function Add-AiError([string]$t) {
    $l = New-AiLabel "✗  $t" 'Err' $AiSmall
    $l.Name = 'bg:ErrBg'; $l.BackColor = $Theme.ErrBg; $l.Padding = New-Object System.Windows.Forms.Padding(10, 7, 10, 7)
    Add-AiItem 'err' $l
}
# Thao tác tool liên tiếp gom thành 1 dòng tóm tắt (như "Ran 2 commands, read X" của Claude desktop), bấm để xem chi tiết
$AiToolVerb = @{ Read = 'đọc'; Glob = 'đọc'; Grep = 'tìm'; LS = 'đọc'; read_file = 'đọc'; list_directory = 'đọc'; search_file_content = 'tìm'
                 Edit = 'sửa'; MultiEdit = 'sửa'; Write = 'sửa'; NotebookEdit = 'sửa'; replace = 'sửa'; write_file = 'sửa'; 'Sửa file' = 'sửa'
                 Bash = 'chạy'; 'Chạy lệnh' = 'chạy'; run_shell_command = 'chạy'; PowerShell = 'chạy' }
function Add-AiTool([string]$name, [string]$detail) {
    $last = if ($script:aiItems.Count) { $script:aiItems[$script:aiItems.Count - 1] } else { $null }
    if (-not $last -or $last.Kind -ne 'act') {
        $p = New-Object System.Windows.Forms.Panel
        $p.Name = 'bg:Back'
        $hd = New-AiLabel '' 'Muted' $AiSmall; $hd.Cursor = 'Hand'
        $dt = New-AiLabel '' 'Muted' $AiMonoSmall; $dt.Visible = $false
        $p.Controls.AddRange(@($hd, $dt))
        $p.Tag = @{ Hd = $hd; Dt = $dt; Lines = New-Object System.Collections.ArrayList; Open = $false }
        $hd.Add_Click({ param($s, $e) $st = $s.Parent.Tag; $st.Open = -not $st.Open; Update-AiActivity $s.Parent; Update-AiLayout })
        Add-AiItem 'act' $p
        $last = $script:aiItems[$script:aiItems.Count - 1]
    }
    [void]$last.Ctl.Tag.Lines.Add(@($name, $detail))
    Update-AiActivity $last.Ctl
    Update-AiLayout -Scroll:$script:aiStick
}
function Update-AiActivity($p) {
    $st = $p.Tag
    $cnt = [ordered]@{ chạy = 0; đọc = 0; tìm = 0; sửa = 0; khác = 0 }
    foreach ($ln in $st.Lines) { $v = $AiToolVerb[$ln[0]]; if (-not $v) { $v = 'khác' }; $cnt[$v]++ }
    $parts = @()
    if ($cnt['chạy']) { $parts += "chạy $($cnt['chạy']) lệnh" }
    if ($cnt['đọc']) { $parts += "đọc $($cnt['đọc']) file" }
    if ($cnt['tìm']) { $parts += "tìm $($cnt['tìm']) lần" }
    if ($cnt['sửa']) { $parts += "sửa $($cnt['sửa']) file" }
    if ($cnt['khác']) { $parts += "$($cnt['khác']) thao tác khác" }
    $sum = ($parts -join ', ')
    if ($st.Lines.Count -eq 1 -and $st.Lines[0][1]) { $sum += ":  $($st.Lines[0][1])" }
    $st.Hd.Text = $(if ($st.Open) { '▾  ' } else { '▸  ' }) + $sum.Substring(0, 1).ToUpper() + $sum.Substring(1)
    $st.Dt.Text = (@($st.Lines | ForEach-Object { "$($_[0])  $($_[1])" }) -join "`n")
    $st.Dt.Visible = $st.Open
}
# Xếp các phần tử vào cột giữa (rộng tối đa 780px), cuộn theo nội dung
function Get-AiCol { $w = $aiChat.ClientSize.Width; $cw = [math]::Max(240, [math]::Min(780, $w - 64)); @([int](($w - $cw) / 2), [int]$cw) }
function Update-AiLayout([switch]$Scroll) {
    if ($script:aiLaying) { $script:aiRelayout = $true; return }
    $script:aiLaying = $true
    $n = 0
    do {
        $script:aiRelayout = $false
        $col = Get-AiCol; $cx = $col[0]; $cw = $col[1]
        $oy = $aiChat.AutoScrollPosition.Y
        $y = 22
        $empty = -not $script:aiItems.Count
        foreach ($l in @($lblAiEmptyIcon, $lblAiEmptyTitle, $lblAiEmptySub)) { $l.Visible = $empty }
        if ($empty) {
            # AutoSize label co theo MaximumSize ngay khi gán -> dùng Width / Height thật để căn giữa (không tràn ngang)
            $lblAiEmptySub.MaximumSize = New-Object System.Drawing.Size($cw, 0); $lblAiEmptyTitle.MaximumSize = New-Object System.Drawing.Size($cw, 0)
            $hh = 40 + $lblAiEmptyTitle.Height + 10 + $lblAiEmptySub.Height
            $y = [math]::Max(30, [int](($aiChat.ClientSize.Height - $hh) / 2) - 30)
            $lblAiEmptyIcon.Location = New-Object System.Drawing.Point(([int]($aiChat.ClientSize.Width / 2) - 16), $y)
            $lblAiEmptyTitle.Location = New-Object System.Drawing.Point(($cx + [int](($cw - $lblAiEmptyTitle.Width) / 2)), ($y + 42))
            $lblAiEmptySub.Location = New-Object System.Drawing.Point(($cx + [int](($cw - $lblAiEmptySub.Width) / 2)), ($y + 52 + $lblAiEmptyTitle.Height))
            $y += $hh
        }
        foreach ($it in $script:aiItems) {
            $c = $it.Ctl
            switch ($it.Kind) {
                'user' {
                    $l = $c.Controls[0]
                    $l.MaximumSize = New-Object System.Drawing.Size(([int]($cw * 0.8) - 32), 0)
                    $sz = $l.PreferredSize
                    $l.Location = New-Object System.Drawing.Point(16, 10)
                    $c.SetBounds(($cx + $cw - $sz.Width - 32), ($oy + $y), ($sz.Width + 32), ($sz.Height + 20))
                }
                'md' { $c.SetBounds($cx, ($oy + $y), $cw, ([math]::Max(18, [int]$c.Tag.H) + 4)) }
                'act' {
                    $st = $c.Tag
                    $st.Hd.MaximumSize = New-Object System.Drawing.Size($cw, 0); $st.Hd.Location = New-Object System.Drawing.Point(0, 2)
                    $h = $st.Hd.PreferredHeight + 4
                    if ($st.Open) { $st.Dt.MaximumSize = New-Object System.Drawing.Size(($cw - 20), 0); $st.Dt.Location = New-Object System.Drawing.Point(20, $h); $h += $st.Dt.PreferredSize.Height + 4 }
                    $c.SetBounds($cx, ($oy + $y), $cw, $h)
                }
                default { $c.MaximumSize = New-Object System.Drawing.Size($cw, 0); $c.Location = New-Object System.Drawing.Point($cx, ($oy + $y)) }
            }
            $y += $c.Height + $(if ($it.Kind -eq 'user') { 18 } else { 8 })
        }
        $lblAiState.Visible = [bool]$lblAiState.Text
        if ($lblAiState.Visible) { $lblAiState.Location = New-Object System.Drawing.Point($cx, ($oy + $y + 4)); $y += 34 }
        $aiChat.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($y + 20))
    } while ($script:aiRelayout -and ++$n -lt 3)
    $script:aiLaying = $false
    if ($Scroll) { $aiChat.AutoScrollPosition = New-Object System.Drawing.Point(0, ($y + 200)) }
}
# Đổi theme: chữ trong câu trả lời có màu cố định -> vẽ lại từ các đoạn đã lưu
function Update-AiTheme {
    foreach ($it in $script:aiItems) {
        if ($it.Kind -ne 'md') { continue }
        $r = $it.Ctl; $r.Clear()
        foreach ($x in @($r.Tag.Runs)) { Add-AiRun $x[0] $x[1] $x[2] $x[3] -NoLog -rtb $r }
    }
    Update-AiChips
    foreach ($c in @($aiTop, $aiCtx, $aiInBox)) { $c.Invalidate() }
}
function Add-AiInline([string]$line, [int]$indent) {
    foreach ($part in [regex]::Split($line, '(\*\*[^*]+\*\*|`[^`]+`)')) {
        if (-not $part) { continue }
        if ($part.Length -gt 4 -and $part.StartsWith('**') -and $part.EndsWith('**')) { Add-AiRun $part.Substring(2, $part.Length - 4) 'Text' $AiBold $indent }
        elseif ($part.Length -gt 2 -and $part.StartsWith('`') -and $part.EndsWith('`')) { Add-AiRun $part.Substring(1, $part.Length - 2) 'Info' $AiMono $indent }
        else { Add-AiRun $part 'Text' $AiFont $indent }
    }
}
# Markdown tối giản: khối ```code```, tiêu đề #, gạch đầu dòng, **đậm**, `code`
function Add-AiMarkdown([string]$text) {
    $code = $false
    foreach ($ln in (($text -replace "`r", '').Trim("`n") -split "`n")) {
        if ($ln -match '^\s*```') { $code = -not $code; continue }
        if ($code) { Add-AiRun "$ln`n" 'Text' $AiMono 16; continue }
        if ($ln -match '^\s{0,3}#{1,6}\s+(.*)$') { Add-AiRun "$($Matches[1])`n" 'Text' $AiHead 0; continue }
        $ind = 0
        if ($ln -match '^(\s*)[-*+]\s+(.*)$') { $ind = 6 + 10 * [math]::Min(4, $Matches[1].Length); $rest = $Matches[2]; Add-AiRun '•  ' 'Accent' $AiFont $ind; $ln = $rest }
        Add-AiInline $ln $ind
        Add-AiRun "`n" 'Text' $AiFont $ind
    }
}
function Flush-AiBuffer { if ($script:ai.Buf) { Add-AiMarkdown $script:ai.Buf; $script:ai.Buf = '' } }
function Get-AiShort($v, [int]$max = 160) {
    $t = if ($v -is [string]) { $v } else { (@($v) | ForEach-Object { if ($_.text) { $_.text } elseif ($_ -is [string]) { $_ } }) -join ' ' }
    $t = [string](([string]$t) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($t.Length -gt $max) { $t.Substring(0, $max) + '…' } else { $t }
}
function Get-AiRel([string]$path) { if ($script:aiRun) { $path -replace [regex]::Escape($script:aiRun.Dir.TrimEnd('\') + '\'), '' } else { $path } }
# Tóm tắt tham số của tool: file / lệnh / mẫu tìm...; đường dẫn trong thư mục làm việc thì rút gọn
function Get-AiToolSummary($in) {
    if (-not $in) { return '' }
    foreach ($k in 'file_path', 'path', 'command', 'pattern', 'url', 'query', 'description', 'prompt') {
        if ($in.$k) { return (Get-AiShort (Get-AiRel ([string]$in.$k)) 140) }
    }
    ''
}
function Get-AiId([string]$id) { $id.Substring(0, [math]::Min(8, $id.Length)) }

function Show-ClaudeEvent($j) {
    switch ($j.type) {
        'system' {
            if ($j.subtype -eq 'init' -and $j.session_id) { $script:ai.Session = $j.session_id }
        }
        'assistant' {
            foreach ($c in @($j.message.content)) {
                if ($c.type -eq 'text' -and $c.text) { Add-AiMarkdown $c.text }
                elseif ($c.type -eq 'tool_use') { Add-AiTool $c.name (Get-AiToolSummary $c.input) }
            }
        }
        'user' {
            foreach ($c in @($j.message.content)) { if ($c.type -eq 'tool_result' -and $c.is_error) { Add-AiError (Get-AiShort $c.content) } }
        }
        'result' {
            if ($j.session_id) { $script:ai.Session = $j.session_id }
            $info = @("$([math]::Round([double]$j.duration_ms / 1000))s")
            if ($j.num_turns) { $info += "$($j.num_turns) lượt" }
            if ($j.total_cost_usd) { $info += ('${0:0.000}' -f [double]$j.total_cost_usd) }
            if ($j.is_error -or $j.subtype -ne 'success') { Add-AiError "Kết thúc lỗi ($($j.subtype)) · $($info -join ' · ')" } else { Add-AiNote "✓ Xong · $($info -join ' · ')" }
            $den = @($j.permission_denials | Where-Object { $_ }).Count
            if ($den) { Add-AiNote "$den thao tác bị chặn do chế độ quyền hiện tại - chọn quyền cao hơn ở ô Quyền nếu muốn cho phép." }
        }
    }
}
function Show-CodexEvent($j) {
    if ($j.msg) {        # định dạng JSON của các bản codex cũ
        switch ($j.msg.type) {
            'agent_message' { Add-AiMarkdown $j.msg.message }
            'exec_command_begin' { Add-AiTool 'Chạy lệnh' (Get-AiShort (@($j.msg.command) -join ' ')) }
            'error' { Add-AiError $j.msg.message }
        }
        return
    }
    switch ($j.type) {
        'thread.started' { $script:ai.Session = $j.thread_id }
        'item.started' { if ($j.item.type -eq 'command_execution') { Add-AiTool 'Chạy lệnh' (Get-AiShort $j.item.command) } }
        'item.completed' {
            $it = $j.item
            switch ($it.type) {
                'agent_message' { Add-AiMarkdown $it.text }
                'reasoning' { Add-AiNote "Suy nghĩ: $(Get-AiShort ($it.text -replace '\*', ''))" }
                'command_execution' { if ($null -ne $it.exit_code -and $it.exit_code -ne 0) { Add-AiError "lệnh thoát mã $($it.exit_code): $(Get-AiShort $it.aggregated_output)" } }
                'file_change' { Add-AiTool 'Sửa file' ((@($it.changes) | ForEach-Object { "$($_.kind) $(Get-AiRel $_.path)" }) -join ', ') }
                'mcp_tool_call' { Add-AiTool "$($it.server) · $($it.tool)" '' }
                'web_search' { Add-AiTool 'Tìm web' $it.query }
                'error' { Add-AiError $it.message }
            }
        }
        'turn.completed' { $u = $j.usage; Add-AiNote ('✓ Xong' + $(if ($u) { " · $($u.input_tokens) token vào · $($u.output_tokens) token ra" } else { '' })) }
        'turn.failed' { Add-AiError $j.error.message }
        'error' { Add-AiError $j.message }
    }
}
function Show-GeminiEvent($j) {
    if ($j.type -eq 'message') {
        if ($j.role -eq 'assistant') { $script:ai.Buf += [string]$j.content; if ($j.delta -eq $false) { Flush-AiBuffer } }
        return
    }
    Flush-AiBuffer
    switch ($j.type) {
        'init' { if ($j.session_id) { $script:ai.Session = $j.session_id } }
        'tool_use' { Add-AiTool $j.tool_name (Get-AiToolSummary $j.parameters) }
        'tool_result' { if ($j.status -eq 'error') { Add-AiError (Get-AiShort $(if ($j.error.message) { $j.error.message } else { $j.output })) } }
        'error' { Add-AiError $j.message }
        'result' {
            if ($j.status -eq 'error') { Add-AiError (Get-AiShort $j.error.message) }
            else { Add-AiNote ('✓ Xong' + $(if ($j.stats.duration_ms) { " · $([math]::Round($j.stats.duration_ms / 1000))s" } else { '' })) }
        }
    }
}
function Show-AiEvent([string]$line) {
    $t = $line.Trim()
    if (-not $t) { return }
    $j = $null
    if ($t.StartsWith('{')) { try { $j = $t | ConvertFrom-Json } catch { } }
    if (-not $j) { Flush-AiBuffer; Add-AiNote $line; return }
    switch ($script:aiRun.Tool) { 'claude' { Show-ClaudeEvent $j } 'codex' { Show-CodexEvent $j } 'gemini' { Show-GeminiEvent $j } }
}

# ---- Giao diện tab (bố cục kiểu Claude desktop) ----
#   trên: tiêu đề phiên + chip thư mục | Phiên mới · Mở terminal · ⋯
#   giữa: khung chat cột giữa          dưới: dải repo (nhánh, +/-) và ô soạn có chip công cụ / quyền / model + nút gửi tròn
# Lựa chọn công cụ / thư mục / quyền / model vẫn nằm trong các ComboBox ẩn (giữ logic cũ); chip chỉ là mặt hiển thị.
$cbAiTool = New-Object System.Windows.Forms.ComboBox
$cbAiTool.DropDownStyle = 'DropDownList'
foreach ($t in $AiTools.Values) { [void]$cbAiTool.Items.Add($t.Name) }
$cbAiDir = New-Object System.Windows.Forms.ComboBox
$cbAiDir.DropDownStyle = 'DropDownList'
$cbAiMode = New-Object System.Windows.Forms.ComboBox
$cbAiMode.DropDownStyle = 'DropDownList'
[void]$cbAiMode.Items.AddRange(@('Chỉ đọc', 'Cho sửa file', 'Toàn quyền'))
$cbAiMode.SelectedIndex = [math]::Min(2, [math]::Max(0, [int]$PanelConfig.aiMode))
$cbAiModel = New-Object System.Windows.Forms.ComboBox
$cbAiModel.DropDownStyle = 'DropDown'
foreach ($c in @($cbAiTool, $cbAiDir, $cbAiMode, $cbAiModel)) { $c.Visible = $false; $pageAi.Controls.Add($c) }

# Chip: nút phẳng không viền, nền theo nền cha, sáng lên khi rê chuột (Set-ControlTheme nhận ra nhờ Tag 'chip')
function New-AiChip([string]$text, $parent, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Tag = 'chip'; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'; $b.Font = $AiSmall
    $b.Padding = New-Object System.Windows.Forms.Padding(6, 3, 6, 3); $b.ImageAlign = 'MiddleLeft'; $b.TextImageRelation = 'ImageBeforeText'
    $b.Add_Click($onClick); $parent.Controls.Add($b)
    $b
}
function Get-DotBitmap([System.Drawing.Color]$c) {
    $k = "dot|$($c.ToArgb())"
    if (-not $script:iconCache.ContainsKey($k)) {
        $bmp = New-Object System.Drawing.Bitmap(16, 16); $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
        $b = New-Object System.Drawing.SolidBrush($c); $g.FillEllipse($b, 3, 3, 10, 10); $b.Dispose(); $g.Dispose()
        $script:iconCache[$k] = $bmp
    }
    $script:iconCache[$k]
}
# Menu xổ từ chip: mỗi mục @{ Text; Click; Arg; Checked }, chuỗi '-' = vạch ngăn
function Show-AiMenu($btn, $items, [switch]$Up) {
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    foreach ($i in $items) {
        if ($i -is [string]) { [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)); continue }
        $mi = New-ThemedMenuItem $i.Text $i.Click
        $mi.Tag = $i.Arg; $mi.Checked = [bool]$i.Checked
        [void]$m.Items.Add($mi)
    }
    Set-MenuTheme $m $Theme $Theme ($script:ThemeName -eq 'dark')
    $y = if ($Up) { -$m.GetPreferredSize([System.Drawing.Size]::Empty).Height } else { $btn.Height }
    $m.Show($btn, (New-Object System.Drawing.Point(0, $y)))
}

# Thanh trên
$aiTop = New-Object System.Windows.Forms.Panel
$aiTop.Dock = 'Top'; $aiTop.Height = 52; $aiTop.Name = 'bg:Back'
$aiTop.Add_Paint({ param($s, $e) $p = New-Object System.Drawing.Pen($Theme.Border); $e.Graphics.DrawLine($p, 0, ($s.Height - 1), $s.Width, ($s.Height - 1)); $p.Dispose() })
$lblAiTitle = New-AiLabel 'Phiên mới' 'Text' (New-Object System.Drawing.Font('Segoe UI Semibold', 11.5))
$aiTop.Controls.Add($lblAiTitle)
$btnAiDir = New-AiChip 'Chọn thư mục' $aiTop {
    $items = @(for ($i = 0; $i -lt $cbAiDir.Items.Count; $i++) {
        if ($i -eq $cbAiDir.Items.Count - 1) { '-' }
        @{ Text = [string]$cbAiDir.Items[$i]; Arg = $i; Checked = ($i -eq $cbAiDir.SelectedIndex); Click = { param($s, $e) $cbAiDir.SelectedIndex = [int]$s.Tag } }
    })
    Show-AiMenu $btnAiDir $items
}
$btnAiNew = New-AiChip 'Phiên mới' $aiTop { $script:ai.Session = $null; $script:ai.Key = ''; $script:ai.Title = $null; Clear-AiChat; Show-AiWelcome; Update-AiUi }
$btnAiTerm = New-AiChip 'Mở terminal' $aiTop { Open-AiTerminal }
$btnAiMore = New-AiChip '•••' $aiTop {
    $items = @(
        @{ Text = 'Xem thay đổi / Commit…'; Click = { Show-AiChanges } },
        @{ Text = 'Mở thư mục'; Click = { $d = Get-AiDir; if ($d) { Start-Process explorer.exe "`"$d`"" } } }
    )
    if ($CodeCmd) { $items += @{ Text = 'Mở bằng VS Code'; Click = { $d = Get-AiDir; if ($d) { Start-Process $CodeCmd -ArgumentList "`"$d`"" -WindowStyle Hidden } } } }
    $items += '-'
    $items += @{ Text = 'Cài / cập nhật CLI…'; Click = { Install-AiCli } }
    Show-AiMenu $btnAiMore $items
}
function Update-AiTop {
    $lblAiTitle.MaximumSize = New-Object System.Drawing.Size([math]::Max(100, $aiTop.Width - 520), 0); $lblAiTitle.AutoEllipsis = $true
    $lblAiTitle.Location = New-Object System.Drawing.Point(22, [int](($aiTop.Height - $lblAiTitle.Height) / 2))
    $btnAiDir.Location = New-Object System.Drawing.Point(($lblAiTitle.Right + 10), [int](($aiTop.Height - $btnAiDir.Height) / 2))
    $x = $aiTop.Width - 16
    foreach ($b in @($btnAiMore, $btnAiTerm, $btnAiNew)) { $x -= $b.Width; $b.Location = New-Object System.Drawing.Point($x, [int](($aiTop.Height - $b.Height) / 2)); $x -= 4 }
}
$aiTop.Add_Resize({ Update-AiTop })

# Khung chat
$aiChat = New-Object System.Windows.Forms.Panel
$aiChat.Dock = 'Fill'; $aiChat.Name = 'bg:Back'
# chỉ cuộn dọc: nội dung luôn xếp vừa bề ngang
$aiChat.HorizontalScroll.Enabled = $false; $aiChat.HorizontalScroll.Visible = $false; $aiChat.HorizontalScroll.Maximum = 0
$aiChat.AutoScroll = $true
Set-DoubleBuffered $aiChat
$aiChat.Add_Resize({ Update-AiLayout })
$lblAiEmptyIcon = New-Object System.Windows.Forms.Label
$lblAiEmptyIcon.Size = New-Object System.Drawing.Size(32, 32)
$lblAiEmptyTitle = New-AiLabel 'Hôm nay mình code gì nào?' 'Text' (New-Object System.Drawing.Font('Segoe UI Semibold', 17))
$lblAiEmptySub = New-AiLabel '' 'Muted' $AiFont
$lblAiEmptySub.TextAlign = 'TopCenter'
$lblAiState = New-AiLabel '' 'Info' $AiSmall
$aiChat.Controls.AddRange(@($lblAiEmptyIcon, $lblAiEmptyTitle, $lblAiEmptySub, $lblAiState))

# Phần dưới: dải repo + ô soạn
$aiBottom = New-Object System.Windows.Forms.Panel
$aiBottom.Dock = 'Bottom'; $aiBottom.Height = 140; $aiBottom.Name = 'bg:Back'
$aiInBox = New-CardHost 0 32 600 100 $aiBottom
$aiInBox.Name = 'bg:Surface'
$aiCtx = New-Object System.Windows.Forms.Panel
$aiCtx.Name = 'bg:Back'; Set-DoubleBuffered $aiCtx
$aiBottom.Controls.Add($aiCtx); $aiInBox.BringToFront()
$script:aiCtxInfo = $null; $script:aiCtxLink = $null
$aiCtx.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.Clear($s.Parent.BackColor)
    $p = New-RoundRect 0 0 ($s.Width - 1) ($s.Height + 10) 10
    $b = New-Object System.Drawing.SolidBrush($Theme.Header); $g.FillPath($b, $p); $b.Dispose()
    $pen = New-Object System.Drawing.Pen($Theme.Border); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
    $h = $s.Height - 4; $x = 12
    $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, NoPadding, EndEllipsis'
    function Seg([string]$t, $c, [string]$icon) {
        if ($icon -and $IconFontName) { $g.DrawImage((Get-IconBitmap $icon $Theme.Muted), $x, [int](($h - 16) / 2), 16, 16); $script:segX = $x + 20 } else { $script:segX = $x }
        $w = [System.Windows.Forms.TextRenderer]::MeasureText($t, $AiSmall, [System.Drawing.Size]::Empty, [System.Windows.Forms.TextFormatFlags]::NoPadding).Width
        [System.Windows.Forms.TextRenderer]::DrawText($g, $t, $AiSmall, (New-Object System.Drawing.Rectangle($script:segX, 0, ($w + 2), $h)), $c, $flags)
        $script:segX + $w + 14
    }
    $d = Get-AiDir
    $x = Seg $(if ($d) { Split-Path $d -Leaf } else { 'Chưa chọn thư mục' }) $Theme.Text 'E8B7'
    $ci = $script:aiCtxInfo
    if ($ci -and $ci.Repo) {
        $x = Seg $ci.Branch $Theme.Text 'F003'
        if ($ci.Add -or $ci.Del) { $x = Seg "+$($ci.Add)" $Theme.Ok ''; $x -= 8; $x = Seg "−$($ci.Del)" $Theme.Err '' }
        if ($ci.New) { $x = Seg "$($ci.New) file mới" $Theme.Muted '' }
        if (-not ($ci.Add -or $ci.Del -or $ci.New)) { $x = Seg 'không có thay đổi' $Theme.Muted '' }
        $lt = 'Xem thay đổi / Commit  ›'
        $lw = [System.Windows.Forms.TextRenderer]::MeasureText($lt, $AiSmall).Width
        $script:aiCtxLink = New-Object System.Drawing.Rectangle(($s.Width - $lw - 12), 0, $lw, $h)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $lt, $AiSmall, $script:aiCtxLink, $Theme.Accent, $flags)
    } elseif ($ci) { [void](Seg 'không phải git repo' $Theme.Muted ''); $script:aiCtxLink = $null }
})
$aiCtx.Add_MouseMove({ param($s, $e) $s.Cursor = $(if ($script:aiCtxLink -and $script:aiCtxLink.Contains($e.Location)) { 'Hand' } else { 'Default' }) })
$aiCtx.Add_MouseDown({ param($s, $e) if ($script:aiCtxLink -and $script:aiCtxLink.Contains($e.Location)) { Show-AiChanges } })

$txtAiIn = New-Object System.Windows.Forms.TextBox
$txtAiIn.Multiline = $true; $txtAiIn.AcceptsReturn = $true; $txtAiIn.BorderStyle = 'None'; $txtAiIn.WordWrap = $true
$txtAiIn.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
$aiInBox.Controls.Add($txtAiIn)
$lblAiHint = New-AiLabel 'Giao việc cho AI, vd: "Thêm API lọc đơn hàng theo trạng thái"   (Enter gửi · Shift+Enter xuống dòng)' 'Muted' $txtAiIn.Font
$lblAiHint.Location = New-Object System.Drawing.Point(1, 1); $lblAiHint.Cursor = 'IBeam'
$lblAiHint.Add_Click({ [void]$txtAiIn.Focus() })
$txtAiIn.Controls.Add($lblAiHint)
$script:aiInLines = 0
$txtAiIn.Add_TextChanged({
    $lblAiHint.Visible = -not $txtAiIn.TextLength
    $n = $txtAiIn.GetLineFromCharIndex($txtAiIn.TextLength) + 1
    if ($n -ne $script:aiInLines) { $script:aiInLines = $n; Update-AiBottom }
})
$txtAiIn.Add_GotFocus({ $aiInBox.Invalidate() }); $txtAiIn.Add_LostFocus({ $aiInBox.Invalidate() })
$txtAiIn.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq 'Enter' -and -not $e.Shift) { $e.SuppressKeyPress = $true; Send-AiPrompt } })
$btnAiTool = New-AiChip 'Claude Code' $aiInBox {
    $items = @(for ($i = 0; $i -lt $cbAiTool.Items.Count; $i++) {
        $t = @($AiTools.Values)[$i]
        @{ Text = $t.Name + $(if (Find-AiExe $t.Exe) { '' } else { '   (chưa cài)' }); Arg = $i; Checked = ($i -eq $cbAiTool.SelectedIndex); Click = { param($s, $e) $cbAiTool.SelectedIndex = [int]$s.Tag } }
    })
    $items += '-'
    $items += @{ Text = 'Cài / cập nhật CLI…'; Click = { Install-AiCli } }
    Show-AiMenu $btnAiTool $items -Up
}
$btnAiMode = New-AiChip 'Cho sửa file' $aiInBox {
    $desc = @('Chỉ đọc  —  hỏi đáp, lên kế hoạch, không sửa file', 'Cho sửa file  —  AI sửa code trong thư mục, không chạy lệnh', 'Toàn quyền  —  sửa file và chạy mọi lệnh không hỏi lại')
    Show-AiMenu $btnAiMode @(for ($i = 0; $i -lt 3; $i++) { @{ Text = $desc[$i]; Arg = $i; Checked = ($i -eq $cbAiMode.SelectedIndex); Click = { param($s, $e) $cbAiMode.SelectedIndex = [int]$s.Tag; Update-AiChips } } }) -Up
}
$btnAiModel = New-AiChip 'Model mặc định' $aiInBox {
    $setModel = { param($s, $e) $cbAiModel.Text = [string]$s.Tag; $PanelConfig.aiModel = $cbAiModel.Text; Save-PanelConfig $PanelConfig; Update-AiChips }
    $items = @(@{ Text = 'Mặc định của CLI'; Arg = ''; Checked = (-not $cbAiModel.Text); Click = $setModel })
    foreach ($m in @($AiTools[(Get-AiToolKey)].Models)) { $items += @{ Text = $m; Arg = $m; Checked = ($cbAiModel.Text -eq $m); Click = $setModel } }
    $items += '-'
    $items += @{ Text = 'Nhập tên model khác…'; Click = {
        $v = [Microsoft.VisualBasic.Interaction]::InputBox('Tên model (để trống = mặc định của CLI):', 'Model', $cbAiModel.Text)
        if ($v -match '^[\w.:/@-]*$') { $cbAiModel.Text = $v.Trim(); $PanelConfig.aiModel = $cbAiModel.Text; Save-PanelConfig $PanelConfig; Update-AiChips }
    } }
    Show-AiMenu $btnAiModel $items -Up
}
# Nút gửi / dừng tròn màu nhấn ở góc phải ô soạn
$btnAiSend = New-Button '' 0 0 34 $aiInBox { Send-AiPrompt }
$btnAiStop = New-Button '' 0 0 34 $aiInBox { Stop-AiRun }
foreach ($b in @($btnAiSend, $btnAiStop)) {
    $b.Tag = 'primary'; $b.Height = 34
    $ep = New-Object System.Drawing.Drawing2D.GraphicsPath; $ep.AddEllipse(0, 0, 34, 34); $b.Region = New-Object System.Drawing.Region($ep)
}
Set-ObjIcon $btnAiSend 'E724' 'AccentText'; Set-ObjIcon $btnAiStop 'E71A' 'AccentText'
foreach ($b in @($btnAiSend, $btnAiStop)) { $b.ImageAlign = 'MiddleCenter'; $b.Width = 34 }
$btnAiStop.Visible = $false
$tipDoc.SetToolTip($btnAiSend, 'Gửi (Enter)'); $tipDoc.SetToolTip($btnAiStop, 'Dừng')
$pageAi.Controls.AddRange(@($aiChat, $aiBottom, $aiTop))
$aiChat.BringToFront()        # Dock Fill phải xếp sau Top / Bottom

function Update-AiBottom {
    $w = $aiBottom.ClientSize.Width
    if ($w -lt 100) { return }
    $cw = [math]::Max(240, [math]::Min(780, $w - 64)); $cx = [int](($w - $cw) / 2)
    $lines = [math]::Min(8, [math]::Max(2, $txtAiIn.GetLineFromCharIndex($txtAiIn.TextLength) + 1))
    $th = $lines * $txtAiIn.Font.Height + 4
    $ih = $th + 60
    $aiCtx.SetBounds(($cx + 16), 4, ($cw - 32), 34)
    $aiInBox.SetBounds($cx, 34, $cw, $ih)
    $aiBottom.Height = 34 + $ih + 16
    $txtAiIn.SetBounds(18, 14, ($cw - 36), $th)
    $ry = 14 + $th + 10
    $btnAiTool.Location = New-Object System.Drawing.Point(10, $ry)
    $btnAiMode.Location = New-Object System.Drawing.Point(($btnAiTool.Right + 2), $ry)
    foreach ($b in @($btnAiSend, $btnAiStop)) { $b.Location = New-Object System.Drawing.Point(($cw - 46), ($ry - 3)) }
    $btnAiModel.Location = New-Object System.Drawing.Point(($btnAiSend.Left - $btnAiModel.Width - 6), $ry)
    $aiCtx.Invalidate(); $aiInBox.Invalidate()
}
$aiBottom.Add_Resize({ Update-AiBottom })

function Get-AiToolKey { @($AiTools.Keys)[[math]::Max(0, $cbAiTool.SelectedIndex)] }
function Get-AiDir { if ($cbAiDir.SelectedIndex -ge 0 -and $cbAiDir.SelectedIndex -lt $cbAiDir.Items.Count - 1) { [string]$cbAiDir.SelectedItem } else { $null } }
$AiPickDir = 'Chọn thư mục khác…'
$script:aiDirFilling = $false
# Thư mục: dùng gần đây -> repo trong tab Git -> thư mục app trong danh mục; mục cuối mở hộp chọn thư mục
function Update-AiDirs([string]$want) {
    if (-not $want) { $want = Get-AiDir }
    $dirs = New-Object System.Collections.ArrayList
    foreach ($d in (@($PanelConfig.aiDirs) + @($script:repos | ForEach-Object { $_.Root }) + @((Get-AppsConfig).Apps | ForEach-Object { $_.dir }))) {
        if ($d -and -not ($dirs -contains [string]$d) -and (Test-Path $d)) { [void]$dirs.Add([string]$d) }
    }
    if ($want -and -not ($dirs -contains $want)) { $dirs.Insert(0, $want) }
    $script:aiDirFilling = $true
    $cbAiDir.Items.Clear()
    foreach ($d in $dirs) { [void]$cbAiDir.Items.Add($d) }
    [void]$cbAiDir.Items.Add($AiPickDir)
    $i = -1
    if ($want) { for ($k = 0; $k -lt $dirs.Count; $k++) { if ($dirs[$k] -eq $want) { $i = $k; break } } }      # -eq không phân biệt hoa thường
    $cbAiDir.SelectedIndex = $(if ($i -ge 0) { $i } elseif ($dirs.Count) { 0 } else { -1 })
    $script:aiDirFilling = $false
    Update-AiChips; Update-AiContext
}
$cbAiDir.Add_SelectedIndexChanged({
    if ($script:aiDirFilling) { return }
    if ($cbAiDir.SelectedIndex -ne $cbAiDir.Items.Count - 1) { Update-AiChips; Update-AiContext; return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Chọn thư mục project để AI làm việc'
    $pick = if ($dlg.ShowDialog() -eq 'OK') { $dlg.SelectedPath } else { $null }
    Update-AiDirs $pick
})
# Dải repo: nhánh + số dòng thêm / bớt so với HEAD + file mới (đọc ở nền)
function Update-AiContext([switch]$Note) {
    $d = Get-AiDir
    $script:aiCtxInfo = $null; $aiCtx.Invalidate()
    if (-not $d) { return }
    Start-CoreAsync 'Get-RepoWorkSummary $p.Dir' @{ Dir = $d } {
        param($r, $ctx)
        if ($ctx.Dir -ne (Get-AiDir) -or -not $r.Ok) { return }
        $script:aiCtxInfo = $r.Value; $aiCtx.Invalidate()
        $v = $r.Value
        if ($ctx.Note -and $v.Repo -and ($v.Add -or $v.Del -or $v.New)) { Add-AiNote "Thư mục đang có thay đổi: +$($v.Add) −$($v.Del)$(if ($v.New) { " · $($v.New) file mới" }) - bấm ""Xem thay đổi / Commit"" ở dưới để review." }
    } @{ Dir = $d; Note = [bool]$Note }
}
function Update-AiChips {
    $t = $AiTools[(Get-AiToolKey)]
    $btnAiTool.Text = "$($t.Name) ▾"; $btnAiTool.Image = Get-DotBitmap $t.Color
    $mi = [math]::Max(0, $cbAiMode.SelectedIndex)
    $btnAiMode.Text = "$(@('Chỉ đọc', 'Cho sửa file', 'Toàn quyền')[$mi]) ▾"
    if ($IconFontName) { $btnAiMode.Image = Get-IconBitmap @('E7B3', 'E70F', 'E7BA')[$mi] $(if ($mi -eq 2) { $Theme.Warn } else { $Theme.Muted }) }
    $btnAiModel.Text = $(if ($cbAiModel.Text) { $cbAiModel.Text } else { 'Model mặc định' }) + ' ▾'
    $d = Get-AiDir
    $btnAiDir.Text = $(if ($d) { Split-Path $d -Leaf } else { 'Chọn thư mục' }) + ' ▾'
    if ($IconFontName) { $btnAiDir.Image = Get-IconBitmap 'E8B7' $Theme.Muted; $lblAiEmptyIcon.Image = Get-IconBitmap 'E99A' $Theme.Accent 32 }
    $tipDoc.SetToolTip($btnAiDir, $(if ($d) { $d } else { '' }))
    $lblAiTitle.Text = $(if ($script:ai.Title) { $script:ai.Title } else { 'Phiên mới' })
    Update-AiTop; Update-AiBottom
}
function Update-AiModels {
    $cbAiModel.Items.Clear()
    foreach ($m in @($AiTools[(Get-AiToolKey)].Models)) { [void]$cbAiModel.Items.Add($m) }
}
# Màn hình trống / trạng thái cài đặt CLI
function Show-AiWelcome {
    $t = $AiTools[(Get-AiToolKey)]
    $exe = Find-AiExe $t.Exe
    $lblAiEmptySub.Text = if ($exe) {
        "$($t.Name) sẵn sàng. Chọn thư mục ở trên, giao việc ở ô bên dưới - AI đọc / sửa code ngay trong thư mục đó.`n" +
        "Lần đầu dùng: bấm ""Mở terminal"" để đăng nhập CLI.  Sửa xong: ""Xem thay đổi / Commit"" để review diff rồi commit."
    } else { "Máy này chưa cài $($t.Name).`nBấm chip ""$($t.Name)"" ở ô soạn → ""Cài / cập nhật CLI"" (cần Node.js), hoặc chạy: npm install -g $($t.Pkg)" }
    $lblAiEmptySub.ForeColor = $(if ($exe) { $Theme.Muted } else { $Theme.Warn })
    if (-not $exe -and $script:aiItems.Count) { Add-AiError "Chưa cài $($t.Name) - chọn chip công cụ → Cài / cập nhật CLI." }
    Update-AiChips; Update-AiLayout
}
function Update-AiUi {
    $busy = [bool]$script:aiRun
    $btnAiSend.Visible = -not $busy; $btnAiStop.Visible = $busy
    foreach ($c in @($btnAiTool, $btnAiMode, $btnAiModel, $btnAiDir)) { $c.Enabled = -not $busy }
    if (-not $busy -and $lblAiState.Text) { $lblAiState.Text = ''; Update-AiLayout }
}
$cbAiTool.Add_SelectedIndexChanged({
    $PanelConfig.aiTool = Get-AiToolKey; Save-PanelConfig $PanelConfig
    Update-AiModels
    if ($script:aiShown) { Show-AiWelcome } else { Update-AiChips }
})
$cbAiMode.Add_SelectedIndexChanged({ $PanelConfig.aiMode = $cbAiMode.SelectedIndex; Save-PanelConfig $PanelConfig })
# Lần đầu mở tab: nạp danh sách thư mục + màn hình chào
$script:aiShown = $false
function Enter-AiTab {
    if (-not $script:aiShown) { $script:aiShown = $true; Update-AiDirs ''; Show-AiWelcome } else { Update-AiContext }
    Update-AiBottom; Update-AiLayout
    [void]$txtAiIn.Focus()
}

function Send-AiPrompt {
    $prompt = $txtAiIn.Text.Trim()
    if (-not $prompt -or $script:aiRun) { return }
    $tool = Get-AiToolKey; $t = $AiTools[$tool]
    $exe = Find-AiExe $t.Exe
    if (-not $exe) { Show-AiWelcome; return }
    $dir = Get-AiDir
    if (-not $dir -or -not (Test-Path $dir)) { Set-Status 'Chọn thư mục project cho AI trước.'; return }
    $mode = $AiModes[$cbAiMode.SelectedIndex]
    if ($mode -eq 'full' -and -not $script:ai.FullOk) {
        if ([System.Windows.Forms.MessageBox]::Show("Toàn quyền: $($t.Name) được sửa file và chạy mọi lệnh trong`n$dir`nmà không hỏi lại.`n`nChỉ dùng với repo đã commit / có thể khôi phục. Tiếp tục?", 'AI Code', 'YesNo', 'Warning') -ne 'Yes') { return }
        $script:ai.FullOk = $true
    }
    $model = $cbAiModel.Text.Trim()
    if ($model -notmatch '^[\w.:/@-]*$') { Set-Status 'Tên model không hợp lệ.'; return }
    $key = "$tool|$dir"
    if ($script:ai.Key -ne $key) {
        if ($script:ai.Session) { Add-AiNote '— phiên mới (đổi công cụ / thư mục) —' }
        $script:ai.Session = $null; $script:ai.Key = $key
    }
    $sess = if ($script:ai.Session -match '^[\w.:-]+$') { $script:ai.Session } else { $null }
    $cmd = Get-AiCommand $exe (Get-AiArgs $tool $mode $model $sess)

    if (-not $sess) { $first = ($prompt -split "`r?`n")[0]; $script:ai.Title = $(if ($first.Length -gt 70) { $first.Substring(0, 70) + '…' } else { $first }) }
    Add-AiUser $prompt
    $txtAiIn.Clear()
    $lblAiState.Text = "◐ $($t.Name) đang làm việc…"
    Update-AiChips; Update-AiLayout -Scroll
    $PanelConfig.aiModel = $model
    $PanelConfig.aiDirs = @(@($dir) + @($PanelConfig.aiDirs | Where-Object { $_ -ne $dir }) | Select-Object -First 8)
    Save-PanelConfig $PanelConfig

    $sync = [hashtable]::Synchronized(@{ Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'; Done = $false; Exit = $null; Err = ''; Pid = 0 })
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('job', @{ File = $cmd.File; Args = $cmd.Args; Dir = $dir; Prompt = $prompt })
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $job.File; $psi.Arguments = $job.Args; $psi.WorkingDirectory = $job.Dir
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
            $psi.EnvironmentVariables['NO_COLOR'] = '1'
            $p = [System.Diagnostics.Process]::Start($psi)
            $sync.Pid = $p.Id
            $errTask = $p.StandardError.ReadToEndAsync()
            try {
                $b = (New-Object System.Text.UTF8Encoding($false)).GetBytes($job.Prompt)
                $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close()
            } catch { }        # CLI thoát sớm (sai tham số...) -> lỗi nằm ở stderr
            while ($null -ne ($l = $p.StandardOutput.ReadLine())) { $sync.Q.Enqueue($l) }
            $p.WaitForExit()
            $sync.Err = $errTask.Result; $sync.Exit = $p.ExitCode
        } catch { $sync.Err = $_.Exception.Message; $sync.Exit = -1 }
        $sync.Done = $true
    })
    $script:aiRun = @{ PS = $ps; RS = $rs; Sync = $sync; Handle = $ps.BeginInvoke(); Tool = $tool; Name = $t.Name; Dir = $dir; Started = Get-Date; Stopped = $false }
    $script:ai.Buf = ''
    Update-AiUi
    $aiTimer.Start()
}
function Stop-AiRun {
    $r = $script:aiRun
    if (-not $r) { return }
    $r.Stopped = $true
    if ($r.Sync.Pid) { Start-Process taskkill.exe -ArgumentList "/PID $($r.Sync.Pid) /T /F" -WindowStyle Hidden }      # cả cây tiến trình (cmd -> node)
}
function Complete-AiRun {
    $r = $script:aiRun; $script:aiRun = $null
    $aiTimer.Stop()
    Flush-AiBuffer
    $s = $r.Sync
    if ($r.Stopped) { Add-AiNote '■ Đã dừng.' }
    elseif ($s.Exit -ne 0) {
        $err = (($s.Err -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 12) -join "`n")
        Add-AiError ("CLI thoát mã $($s.Exit)" + $(if ($err) { ":`n$err" } else { '' }))
        if ($s.Err -match 'log ?in|auth|API key|unauthori|401|credential') { Add-AiNote 'Có vẻ CLI chưa đăng nhập - bấm "Mở terminal" chạy một lần để đăng nhập.' }
        if ($s.Err -match 'Unknown (argument|option)|unexpected argument|unrecognized|invalid value') { Add-AiNote 'CLI có thể là bản cũ chưa hỗ trợ tham số này - bấm "Cài / cập nhật CLI".' }
    }
    try { $r.PS.EndInvoke($r.Handle) | Out-Null } catch { }
    $r.PS.Dispose(); $r.RS.Dispose()
    Update-AiUi
    Update-AiContext -Note        # dải repo cập nhật +/- ; có thay đổi thì nhắc review
    if (-not $form.ContainsFocus) { $tray.ShowBalloonTip(4000, $r.Name, 'Đã trả lời xong.', 'Info') }
}
$aiTimer = New-Object System.Windows.Forms.Timer
$aiTimer.Interval = 150
$aiTimer.Add_Tick({
    $r = $script:aiRun
    if (-not $r) { $aiTimer.Stop(); return }
    $l = $null; $n = 0
    while ($n -lt 300 -and $r.Sync.Q.TryDequeue([ref]$l)) { Show-AiEvent $l; $n++ }
    $ms = ((Get-Date) - $r.Started).TotalMilliseconds
    $lblAiState.Text = "$($SpinFrames[[int]($ms / 250) % 4])  $($r.Name) đang làm việc…  $([int]($ms / 1000))s"
    if (-not $lblAiState.Visible) { Update-AiLayout -Scroll:$script:aiStick }
    if ($r.Sync.Done -and $r.Sync.Q.IsEmpty) { Complete-AiRun }
})

function Show-AiChanges {
    $dir = Get-AiDir
    if (-not $dir) { return }
    $top = Invoke-Git $dir @('rev-parse', '--show-toplevel') 10000
    if ($top.Code -ne 0) { Set-Status 'Thư mục này không phải git repo - mở thư mục để xem file.'; Start-Process explorer.exe "`"$dir`""; return }
    Show-CommitDialog ($top.Out -replace '/', '\')
}
function Open-AiTerminal {
    $tool = Get-AiToolKey; $t = $AiTools[$tool]
    $exe = Find-AiExe $t.Exe
    if (-not $exe) { Install-AiCli; return }
    $dir = Get-AiDir
    if (-not $dir) { $dir = $env:USERPROFILE }
    $sess = if ($script:ai.Key -eq "$tool|$dir" -and $script:ai.Session -match '^[\w.:-]+$') { $script:ai.Session } else { $null }
    $model = $cbAiModel.Text.Trim(); if ($model -notmatch '^[\w.:/@-]*$') { $model = '' }
    $line = ("`"$exe`" " + ((Get-AiArgs $tool 'edit' $model $sess -Interactive) -join ' ')).Trim()
    if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList "-d `"$($dir.TrimEnd('\'))`" --title `"$($t.Name)`" cmd /k $line" }
    else { Start-Process cmd.exe -ArgumentList "/k $line" -WorkingDirectory $dir }
}
function Install-AiCli {
    $t = $AiTools[(Get-AiToolKey)]
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        if ([System.Windows.Forms.MessageBox]::Show("Cần Node.js (npm) để cài $($t.Name).`n`nMở trang tải Node.js?", 'AI Code', 'YesNo', 'Information') -eq 'Yes') { Start-Process 'https://nodejs.org/' }
        return
    }
    $line = "npm install -g $($t.Pkg)@latest"
    if (Get-Command wt.exe) { Start-Process wt.exe -ArgumentList "--title `"Cài $($t.Name)`" cmd /k $line" } else { Start-Process cmd.exe -ArgumentList "/k $line" }
    Set-Status "Đang cài $($t.Name) trong cửa sổ terminal - xong thì bấm Phiên mới."
}
# Từ tab Git: mở tab AI tại thư mục repo
function Show-AiFor([string]$dir) { $tabs.SelectedTab = $pageAi; Update-AiDirs $dir }

$cbAiTool.SelectedIndex = [math]::Max(0, @($AiTools.Keys).IndexOf([string]$PanelConfig.aiTool))
$cbAiModel.Text = [string]$PanelConfig.aiModel
Update-AiUi

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
$miTrayUpd = $menu.Items.Add('Cập nhật', $null, { $form.Show(); $form.WindowState = 'Normal'; $form.Activate(); Show-UpdateDialog })
$miTrayUpd.Available = $false
[void]$menu.Items.Add("Trợ giúp (v$PanelVersion)", $null, { $form.Show(); $form.WindowState = 'Normal'; $tabs.SelectedTab = $pageHelp; $form.Activate() })
[void]$menu.Items.Add('Thoát panel', $null, { $script:exiting = $true; $form.Close() })
$tray.ContextMenuStrip = $menu

# ---------- Gắn icon outline ----------
Add-IconsTo $form
foreach ($m in @($menu, $profMenu)) { Add-MenuIcons $m.Items }
[void](Set-ButtonRow $pageApps 304)                 # Start / Stop / ... / Quét project
[void](Set-ButtonRow $pageGit $btnY)                # Làm mới / Fetch / Pull / ...
[void](Set-ButtonRow $gScan 212)                    # Lưu và quét ngay / Xuất / Nhập
$xs = Set-ButtonRow $pageSettings 490 6 8           # Lưu và mở lại / Chẩn đoán
$lblDataDir.Left = $xs + 4; $lblDataDir.Width = [math]::Max(80, 516 - $xs - 10)      # bề rộng thiết kế; neo phải sẽ giãn theo cửa sổ
[void](Set-ButtonRow $pageHelp 448)
$xw = Set-ButtonRow $gUbuntu 26 12 6                # nút WSL có icon rộng ra -> link hướng dẫn đặt ngay sau nút cuối
foreach ($l in @($lnkWsl1, $lnkWsl2)) { $l.Left = $xw + 8 }
$x = 12
foreach ($c in @($gGit.Controls | Where-Object { ($_ -is [System.Windows.Forms.Button] -or $_ -eq $cbBranch) -and $_.Top -ge 90 } | Sort-Object Left)) {
    $c.Left = $x; $c.Top = 94; $x += $c.Width + 6
}
$btnProfiles.Left = $lblSearch.Left - $btnProfiles.Width - 6
$lblApps.Width = [math]::Max(80, $btnProfiles.Left - $lblApps.Left - 6)
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })

# ---------- Áp dụng theme ----------
# Tô lại 1 control và các con: màu ngữ nghĩa (OK / lỗi / cảnh báo...) đổi theo bảng màu, còn lại dùng màu nền / chữ
function Convert-ThemeColor($c, $old, $new, [string]$fallback = 'Text') {
    foreach ($k in 'Ok', 'Err', 'Warn', 'Info', 'Muted', 'Gray', 'ErrBg', 'Accent') { if ($c.ToArgb() -eq $old[$k].ToArgb()) { return $new[$k] } }
    $new[$fallback]
}
function Set-ControlTheme($c, $old, $new) {
    switch ($c) {
        { $_ -is [System.Windows.Forms.Button] } {
            $c.UseVisualStyleBackColor = $false; $c.FlatStyle = 'Flat'; $c.Cursor = 'Hand'; $c.FlatAppearance.BorderSize = 1
            if ($c.Tag -eq 'chip') {
                $c.BackColor = $c.Parent.BackColor; $c.ForeColor = $new.Muted; $c.FlatAppearance.BorderSize = 0
                $c.FlatAppearance.MouseOverBackColor = $new.Hi; $c.FlatAppearance.MouseDownBackColor = $new.Sel
            } elseif (Test-PrimaryButton $c) {
                $c.BackColor = $new.Accent; $c.ForeColor = $new.AccentText
                $c.FlatAppearance.BorderColor = $new.Accent; $c.FlatAppearance.MouseOverBackColor = $new.AccentHi; $c.FlatAppearance.MouseDownBackColor = $new.Accent
            } else {
                $c.BackColor = $new.Button; $c.ForeColor = $new.Text
                $c.FlatAppearance.BorderColor = $new.Border; $c.FlatAppearance.MouseOverBackColor = $new.Hi; $c.FlatAppearance.MouseDownBackColor = $new.Sel
            }
            break
        }
        { $_ -is [System.Windows.Forms.ListView] } {
            $c.BackColor = $new.Surface; $c.ForeColor = $new.Text; $c.BorderStyle = 'FixedSingle'
            foreach ($it in $c.Items) { foreach ($sub in $it.SubItems) { $sub.ForeColor = Convert-ThemeColor $sub.ForeColor $old $new } }
            break
        }
        { $_ -is [System.Windows.Forms.TextBoxBase] -or $_ -is [System.Windows.Forms.ListBox] -or $_ -is [System.Windows.Forms.NumericUpDown] } {
            $c.BackColor = Convert-ThemeColor $c.BackColor $old $new 'Surface'; $c.ForeColor = $new.Text
            if ($c.BorderStyle -eq 'Fixed3D') { $c.BorderStyle = 'FixedSingle' }
            break
        }
        { $_ -is [System.Windows.Forms.ComboBox] } { $c.BackColor = $new.Surface; $c.ForeColor = $new.Text; $c.FlatStyle = 'Flat'; break }
        { $_ -is [System.Windows.Forms.LinkLabel] } { $c.LinkColor = $new.Link; $c.ActiveLinkColor = $new.Accent; $c.ForeColor = $new.Text; break }
        { $_ -is [System.Windows.Forms.Label] -or $_ -is [System.Windows.Forms.CheckBox] } { $c.ForeColor = Convert-ThemeColor $c.ForeColor $old $new; break }
        { $_ -eq $chart } { $c.BackColor = $new.ChartBg; $c.Invalidate(); break }
        { $_ -is [System.Windows.Forms.TabPage] } { $c.UseVisualStyleBackColor = $false; $c.BackColor = $new.Back; $c.ForeColor = $new.Text; break }
        { $_ -is [System.Windows.Forms.GroupBox] } { $c.BackColor = $new.Card; $c.ForeColor = $new.Text; $c.Invalidate(); break }
        { $_ -is [System.Windows.Forms.TreeView] } { $c.BackColor = $new.Surface; $c.ForeColor = $new.Text; break }
        default { $c.BackColor = $new.Back; $c.ForeColor = $new.Text; if ($c -is [System.Windows.Forms.Panel]) { $c.Invalidate() } }
    }
    if ($c.Name -like 'bg:*') { $c.BackColor = $new[$c.Name.Substring(3)] }      # nền theo tên màu theme (khung chat AI...)
    foreach ($ch in $c.Controls) { Set-ControlTheme $ch $old $new }
}
function Set-MenuTheme($m, $old, $new, [bool]$dark) {
    if ($dark -and (Initialize-DarkNative)) { $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object DarkMenuColors($new.Surface, $new.Hi, $new.Border))) }
    else { $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer }
    $items = @($m.Items) + @($m.Items | Where-Object { $_ -is [System.Windows.Forms.ToolStripMenuItem] } | ForEach-Object { @($_.DropDownItems) })
    foreach ($i in $items) { $i.ForeColor = Convert-ThemeColor $i.ForeColor $old $new }
    foreach ($i in @($m.Items | Where-Object { $_ -is [System.Windows.Forms.ToolStripMenuItem] -and $_.DropDownItems.Count })) {
        $i.DropDown.Renderer = $m.Renderer; $i.DropDown.BackColor = $new.Surface
    }
}
# Thanh tiêu đề, scrollbar, header ListView: phải có handle (gọi sau khi form hiện)
function Set-NativeTheme($root) {
    $dark = $script:ThemeName -eq 'dark'
    if (-not $dark -and -not $script:darkNativeLoaded) { return }     # chưa từng bật tối -> giao diện gốc của Windows, khỏi làm gì
    if (-not (Initialize-DarkNative)) { return }
    if ($root -is [System.Windows.Forms.Form] -and $root.IsHandleCreated) { [DarkNative]::TitleBar($root.Handle, $dark); if ($root.Visible) { $root.Width++; $root.Width-- } }   # ép vẽ lại khung
    $stack = New-Object System.Collections.Stack; $stack.Push($root)
    while ($stack.Count) {
        $c = $stack.Pop()
        if ($c.IsHandleCreated) {
            if ($c -is [System.Windows.Forms.ListView]) { [DarkNative]::ListView($c.Handle, $dark) }
            elseif ($c -is [System.Windows.Forms.TextBoxBase] -or $c -is [System.Windows.Forms.ListBox]) { [DarkNative]::Control($c.Handle, $dark) }
        }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
}

# Thanh điều hướng dọc bên trái (TabControl vẫn lo chuyển trang, Ctrl+Tab...; dải tab gốc bị ẩn bằng Region):
# mục đang chọn nền màu nhấn nhạt + vạch nhấn bên trái, rê chuột thì sáng nhẹ; dưới cùng là nút đổi giao diện sáng / tối
$SideW = 210; $SideWMin = 60
$SideFont = $TabFont
$SideFontSel = $TabFontSel
$sideNav = New-Object System.Windows.Forms.Panel
$sideNav.Cursor = 'Hand'
Set-DoubleBuffered $sideNav
$form.Controls.Add($sideNav)
$script:sideRects = @(); $script:sideHover = -1; $script:sideTheme = $null
function Draw-SideItem($g, $r, [string]$code, [string]$text, [bool]$sel, [bool]$hover, [bool]$mini = $false) {
    if ($sel -or $hover) {
        $p = New-RoundRect $r.X $r.Y $r.Width $r.Height 10
        $b = New-Object System.Drawing.SolidBrush($(if ($sel) { $Theme.Sel } else { $Theme.Hi })); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
    }
    if ($sel) { $p = New-RoundRect $r.X ($r.Y + 10) 4 ($r.Height - 20) 2; $b = New-Object System.Drawing.SolidBrush($Theme.Accent); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose() }
    $fc = if ($sel) { $Theme.Accent } else { $Theme.Text }
    $ix = if ($mini) { $r.X + [int](($r.Width - 16) / 2) } else { $r.X + 16 }
    if ($code -and $IconFontName) { $g.DrawImage((Get-IconBitmap $code $(if ($sel) { $Theme.Accent } else { $Theme.Muted })), $ix, ($r.Y + [int](($r.Height - 16) / 2)), 16, 16) }
    if ($mini) { return }
    [System.Windows.Forms.TextRenderer]::DrawText($g, $text, $(if ($sel) { $SideFontSel } else { $SideFont }), (New-Object System.Drawing.Rectangle(($r.X + 44), $r.Y, ($r.Width - 48), $r.Height)), $fc,
        [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPadding')
}
$sideNav.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $g.Clear($Theme.Card)
    $pen = New-Object System.Drawing.Pen($Theme.Border); $g.DrawLine($pen, ($s.Width - 1), 0, ($s.Width - 1), $s.Height)
    $rects = @(); $y = 14; $mini = [bool]$PanelConfig.navCollapsed
    for ($i = 0; $i -lt $tabs.TabCount; $i++) {
        $pg = $tabs.TabPages[$i]
        $r = New-Object System.Drawing.Rectangle(10, $y, ($s.Width - 21), 40)
        $rects += $r
        Draw-SideItem $g $r $TabIcons[$pg.Text] $pg.Text ($i -eq $tabs.SelectedIndex) ($i -eq $script:sideHover) $mini
        $y += 44
    }
    $script:sideRects = $rects
    $dark = $script:ThemeName -eq 'dark'
    $r = New-Object System.Drawing.Rectangle(10, ($s.Height - 98), ($s.Width - 21), 40)
    $g.DrawLine($pen, 18, ($r.Y - 8), ($s.Width - 19), ($r.Y - 8)); $pen.Dispose()
    Draw-SideItem $g $r $(if ($mini) { 'E76C' } else { 'E76B' }) 'Thu gọn menu' $false ($script:sideHover -eq 98) $mini
    $script:sideCollapse = $r
    $r = New-Object System.Drawing.Rectangle(10, ($s.Height - 54), ($s.Width - 21), 40)
    Draw-SideItem $g $r $(if ($dark) { 'E706' } else { 'E708' }) $(if ($dark) { 'Giao diện sáng' } else { 'Giao diện tối' }) $false ($script:sideHover -eq 99) $mini
    $script:sideTheme = $r
})
function Get-SideAt($pt) {
    for ($i = 0; $i -lt $script:sideRects.Count; $i++) { if ($script:sideRects[$i].Contains($pt)) { return $i } }
    if ($script:sideTheme -and $script:sideTheme.Contains($pt)) { return 99 }
    if ($script:sideCollapse -and $script:sideCollapse.Contains($pt)) { return 98 }
    -1
}
# Vị trí menu tab: 'top' = trên dải tiêu đề (mặc định, gọn), 'side' = thanh bên trái (thu gọn được còn icon).
# Đặt lại vị trí trang tab + các control dưới cùng; gọi lúc mở panel và khi đổi trong tab Cài đặt / bấm thu gọn.
function Set-NavLayout {
    $side = $PanelConfig.navLayout -eq 'side'
    $sw = if (-not $side) { 0 } elseif ($PanelConfig.navCollapsed) { $SideWMin } else { $SideW }
    $cw = $form.ClientSize.Width
    $sideNav.Visible = $side
    $sideNav.SetBounds(0, $HeaderH, $sw, ($form.ClientSize.Height - $HeaderH))
    $dr = $tabs.DisplayRectangle
    $tl = $sw + 10 - $dr.X; $tt = $HeaderH + 8 - $dr.Y
    $tabs.SetBounds($tl, $tt, ($cw - 10 + ($tabs.Width - $dr.Right) - $tl), ($tabs.Bottom - $tt))
    $chkLogon.Left = 16 + $sw; $chkAuto.Left = 280 + $sw
    $right = $statusLbl.Right; $statusLbl.Left = 16 + $sw; $statusLbl.Width = [math]::Max(100, $right - $statusLbl.Left)
    Update-TabsRegion
    $header.Invalidate(); $sideNav.Invalidate()
}
$sideNav.Add_MouseDown({
    param($s, $e)
    $i = Get-SideAt $e.Location
    if ($i -eq 99) { $cbTheme.SelectedIndex = 1 - $cbTheme.SelectedIndex }        # như chọn ở tab Cài đặt (lưu cấu hình)
    elseif ($i -eq 98) { $PanelConfig.navCollapsed = -not $PanelConfig.navCollapsed; Save-PanelConfig $PanelConfig; $script:sideHover = -1; Set-NavLayout }
    elseif ($i -ge 0) { $tabs.SelectedIndex = $i }
})
$sideNav.Add_MouseMove({
    param($s, $e)
    $i = Get-SideAt $e.Location
    if ($i -ne $script:sideHover) {
        $script:sideHover = $i; $s.Invalidate()
        $tip = if (-not $PanelConfig.navCollapsed -or $i -lt 0) { '' } elseif ($i -eq 98) { 'Mở rộng menu' } elseif ($i -eq 99) { 'Đổi giao diện sáng / tối' } else { $tabs.TabPages[$i].Text }
        $tipDoc.SetToolTip($s, $tip)
    }
})
$sideNav.Add_MouseLeave({ param($s, $e) $script:sideHover = -1; $s.Invalidate() })
# Chỉ vẽ vùng trang: dải tab và khung viền hệ thống (theme tối vẽ màu sáng) bị cắt bỏ
# (TabControl chỉ tính lại DisplayRectangle SAU khi chạy các handler Resize -> đặt Region ở lượt sau)
function Update-TabsRegion { $tabs.Region = New-Object System.Drawing.Region($tabs.DisplayRectangle) }
$tabs.Add_Resize({ if ($form.IsHandleCreated) { [void]$form.BeginInvoke([Action]{ Update-TabsRegion }) } else { Update-TabsRegion } })
# control ở tab chưa mở chưa có handle lúc áp theme -> mở tab nào thì áp scrollbar / header tối cho tab đó
$tabs.Add_SelectedIndexChanged({ $sideNav.Invalidate(); $header.Invalidate(); if ($script:ThemeName -eq 'dark') { Set-NativeTheme $tabs.SelectedTab } })

# Bảng (ListView) tự vẽ ở cả 2 theme: header phẳng, dòng kẻ sọc, dòng chọn màu nhấn nhạt,
# ô trạng thái có ký hiệu đầu (● ○ ✗ ⚠ ✓ ◐) vẽ thành "pill" màu
$HeaderFontLv = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
function Set-RowHeight($lv, [int]$h = 26) { $il = New-Object System.Windows.Forms.ImageList; $il.ImageSize = New-Object System.Drawing.Size(1, $h); $lv.SmallImageList = $il }
function Get-RowBack($lv, $item) {
    if ($item.Selected) { if ($lv.Focused) { $Theme.Sel } else { $Theme.SelInactive } }
    elseif ($item.Index % 2) { $Theme.Alt } else { $Theme.Surface }
}
$lvDrawHeader = {
    param($s, $e)
    $g = $e.Graphics; $bd = $e.Bounds
    $b = New-Object System.Drawing.SolidBrush($Theme.Header); $g.FillRectangle($b, $bd); $b.Dispose()
    $p = New-Object System.Drawing.Pen($Theme.Border)
    $g.DrawLine($p, ($bd.Right - 1), ($bd.Top + 6), ($bd.Right - 1), ($bd.Bottom - 6))
    $g.DrawLine($p, $bd.Left, ($bd.Bottom - 1), $bd.Right, ($bd.Bottom - 1)); $p.Dispose()
    $r = New-Object System.Drawing.Rectangle(($bd.X + 4), $bd.Y, ($bd.Width - 6), $bd.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $e.Header.Text, $HeaderFontLv, $r, $Theme.Muted, [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, SingleLine')
}
$lvDrawItem = { param($s, $e) }          # Details view: vẽ từng ô ở DrawSubItem
$lvDrawSubItem = {
    param($s, $e)
    $g = $e.Graphics; $bd = $e.Bounds
    $b = New-Object System.Drawing.SolidBrush((Get-RowBack $s $e.Item)); $g.FillRectangle($b, $bd); $b.Dispose()
    $t = $e.SubItem.Text
    if (-not $t) { return }
    $fc = $e.SubItem.ForeColor
    $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, SingleLine, NoPrefix'
    if ($t -match '^[●○✗⚠✓◐◓◑◒] ' -and $fc.ToArgb() -ne $Theme.Text.ToArgb()) {
        $g.SmoothingMode = 'AntiAlias'
        $w = [math]::Min([System.Windows.Forms.TextRenderer]::MeasureText($t, $s.Font).Width + 8, $bd.Width - 6)
        $h = $bd.Height - 8
        $p = New-RoundRect ($bd.X + 3) ($bd.Y + 4) $w $h ($h / 2)
        $b = New-Object System.Drawing.SolidBrush((Get-Alpha 36 $fc)); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
        $r = New-Object System.Drawing.Rectangle(($bd.X + 7), $bd.Y, ($w - 6), $bd.Height)
    } else {
        if ($e.Item.Selected -and $fc.ToArgb() -eq $Theme.Gray.ToArgb()) { $fc = $Theme.Text }
        $r = New-Object System.Drawing.Rectangle(($bd.X + 4), $bd.Y, ($bd.Width - 6), $bd.Height)
    }
    [System.Windows.Forms.TextRenderer]::DrawText($g, $t, $s.Font, $r, $fc, $flags)
}
$AllListViews = @($list, $lvApps, $lvPods, $lvCpu, $lvRam, $lvRepos)
foreach ($lv in $AllListViews) {
    $lv.Add_DrawColumnHeader($lvDrawHeader); $lv.Add_DrawItem($lvDrawItem); $lv.Add_DrawSubItem($lvDrawSubItem)
    $lv.OwnerDraw = $true; Set-RowHeight $lv 26; Set-DoubleBuffered $lv
}
$lvLog.Add_DrawColumnHeader($commitDrawHeader); $lvLog.Add_DrawItem($lvDrawItem); $lvLog.Add_DrawSubItem($commitDrawSubItem)
$lvLog.OwnerDraw = $true; Set-RowHeight $lvLog 26; Set-DoubleBuffered $lvLog
foreach ($lv in $AllListViews + @($lvLog)) { $lv.Add_GotFocus({ param($s, $e) $s.Invalidate() }); $lv.Add_LostFocus({ param($s, $e) $s.Invalidate() }) }

function Set-Theme([string]$name) {
    $old = @{}; foreach ($k in $Theme.Keys) { $old[$k] = $Theme[$k] }
    $new = $ThemePalettes[$name]
    $script:ThemeName = $name
    foreach ($k in $new.Keys) { $Theme[$k] = $new[$k] }      # sửa tại chỗ: code đang giữ $Theme thấy màu mới ngay
    $dark = $name -eq 'dark'
    $form.SuspendLayout()
    Set-ControlTheme $form $old $Theme
    $form.BackColor = $Theme.Back; $form.ForeColor = $Theme.Text
    $sideNav.Invalidate()
    foreach ($m in @($appsMenu, $svcMenu, $podMenu, $menu, $profMenu, $repoMenu)) { if ($m) { Set-MenuTheme $m $old $Theme $dark } }
    $miAppProfiles.DropDown.Renderer = $appsMenu.Renderer; $miAppProfiles.DropDown.BackColor = $Theme.Surface
    Update-IconColors
    foreach ($lv in $AllListViews + @($lvLog)) { $lv.Invalidate() }
    Update-AiTheme
    if ($cbTheme.SelectedIndex -ne [int]$dark) { $cbTheme.SelectedIndex = [int]$dark }
    $form.ResumeLayout()
    Set-NativeTheme $form
    $chart.Invalidate(); $header.Invalidate()
}

# ---------- Cập nhật: so bản đang cài với bản mới nhất trên GitHub ----------
$script:latestRel = $null
$script:updNotified = $false
$script:updChecking = $false
function Update-UpdateUi {
    $r = $script:latestRel
    $new = [bool]($r -and $r.IsNewer)
    if (-not $r) {
        Set-UpdLine @(@("Đang dùng $PanelVersion  ·  ", $null), @('Mới nhất trên GitHub', 'releases'), @('  ·  ', $null), @('Kiểm tra lại', 'check')) $Theme.Muted
    } else {
        $relText = "$($r.Version)" + $(if ($r.Published) { " ($($r.Published))" } else { '' })
        $parts = @(@("Đang dùng $PanelVersion  ·  Mới nhất trên GitHub: ", $null), @($relText, 'release'))
        if ($new) { $parts += , @('  ·  ', $null); $parts += , @('⬆ Cài bản mới', 'install') } else { $parts += , @('  ✓ đang dùng bản mới nhất', $null) }
        $parts += , @('  ·  ', $null); $parts += , @('Kiểm tra lại', 'check')
        Set-UpdLine $parts $(if ($new) { $Theme.Warn } else { $Theme.Text })
    }
    $lnkUpdate.Visible = $new
    if ($new) {
        $lnkUpdate.Text = "⬆ Có bản mới $($r.Version) - bấm để cập nhật"
        $lnkUpdate.LinkColor = $Theme.Ok; $lnkUpdate.ActiveLinkColor = $Theme.Ok
        $lnkUpdate.Left = $form.ClientSize.Width - $lnkUpdate.PreferredWidth - 16
        $statusLbl.Width = [math]::Max(120, $lnkUpdate.Left - $statusLbl.Left - 8)
        $form.Text = "$AppName  v$PanelVersion  (có bản mới $($r.Version))"
        $miTrayUpd.Text = "⬆ Cập nhật lên $($r.Version)…"; $miTrayUpd.Available = $true
        if (-not $script:updNotified) {
            $script:updNotified = $true
            $tray.ShowBalloonTip(6000, "$AppName - có bản mới $($r.Version)", "Đang dùng $PanelVersion. Bấm link dưới cùng cửa sổ hoặc tab Trợ giúp để cập nhật.", 'Info')
        }
    } else {
        $statusLbl.Width = $form.ClientSize.Width - $statusLbl.Left - 16
        $form.Text = "$AppName  v$PanelVersion"
        $miTrayUpd.Available = $false
    }
}
function Start-UpdateCheck([switch]$Manual) {
    if ($script:updChecking) { return }
    $script:updChecking = $true
    if ($Manual) { Set-Status 'Đang kiểm tra bản mới trên GitHub...'; Set-UpdLine @(, @("Đang dùng $PanelVersion  ·  đang kiểm tra bản mới trên GitHub...", $null)) $Theme.Muted }
    Start-CoreAsync 'Get-LatestRelease' @{} {
        param($r, $ctx)
        $script:updChecking = $false
        if (-not $r.Ok) {
            if ($ctx.Manual) {
                Set-Status "Không kiểm tra được bản mới: $($r.Value)"
                Set-UpdLine @(@("Đang dùng $PanelVersion  ·  không kết nối được GitHub  ·  ", $null), @('Thử lại', 'check'), @('  ·  ', $null), @('Mở trang GitHub', 'releases')) $Theme.Muted
            }
            return
        }
        $script:latestRel = $r.Value
        $script:latestRel.IsNewer = [bool](($v = ConvertTo-PanelVersion $r.Value.Version) -and $v -gt [version]$PanelVersion)
        Update-UpdateUi
        if ($ctx.Manual) { Set-Status $(if ($r.Value.IsNewer) { "Có bản mới $($r.Value.Version) (đang dùng $PanelVersion)." } else { "Đang dùng bản mới nhất ($PanelVersion)." }) }
    } @{ Manual = [bool]$Manual }
}

function Show-UpdateDialog {
    $r = $script:latestRel
    if (-not $r) { Start-UpdateCheck -Manual; return }
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Cập nhật DevOps Panel'; $d.Icon = $AppIcon; $d.Font = $font
    $d.Size = New-Object System.Drawing.Size(620, 480); $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'; $d.MinimizeBox = $false; $d.MaximizeBox = $false
    $l1 = New-Label $(if ($r.IsNewer) { "Có bản mới: $($r.Version)" } else { "Đang dùng bản mới nhất" }) 16 14 570 $d -Bold
    $l1.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold); $l1.Height = 30
    $l1.ForeColor = if ($r.IsNewer) { $Theme.Ok } else { $Theme.Text }
    $l2 = New-Label ("Đang dùng: $PanelVersion   →   Mới nhất: $($r.Version)" + $(if ($r.Published) { "  (phát hành $($r.Published))" } else { '' })) 16 48 570 $d
    $l3 = New-Label "Ghi chú phát hành ($($r.Name)):" 16 78 570 $d
    $l3.ForeColor = $Theme.Muted
    $notes = New-Object System.Windows.Forms.TextBox
    $notes.Multiline = $true; $notes.ReadOnly = $true; $notes.ScrollBars = 'Vertical'; $notes.TabStop = $false
    $notes.Location = New-Object System.Drawing.Point(16, 102); $notes.Size = New-Object System.Drawing.Size(572, 260)
    $notes.Text = $(if ($r.Notes.Trim()) { $r.Notes.Trim() -replace "`r?`n", "`r`n" } else { '(Không có ghi chú)' })
    $d.Controls.Add($notes)
    $hint = New-Label $(if ($r.SetupUrl) { "Cài bản mới: tải bộ cài ($([math]::Round($r.SetupSize / 1KB)) KB) từ GitHub, panel tự đóng rồi mở lại." } else { 'Bản phát hành này chưa đính kèm DevOpsPanel-Setup.exe - mở trang GitHub để tải.' }) 16 368 572 $d
    $hint.ForeColor = $Theme.Muted; $hint.Height = 22
    $bInstall = New-Object System.Windows.Forms.Button; $bInstall.Text = 'Cài bản mới'; $bInstall.Size = New-Object System.Drawing.Size(130, 34); $bInstall.Location = New-Object System.Drawing.Point(16, 396)
    $bInstall.Enabled = [bool]($r.IsNewer -and $r.SetupUrl)
    $bInstall.Add_Click({ param($sender, $e) $sender.FindForm().DialogResult = 'Yes' })
    $bWeb = New-Object System.Windows.Forms.Button; $bWeb.Text = 'Xem trên GitHub'; $bWeb.Size = New-Object System.Drawing.Size(150, 34); $bWeb.Location = New-Object System.Drawing.Point(152, 396)
    $bWeb.Add_Click({ param($sender, $e) Start-Process $script:latestRel.Url })
    $bLater = New-Object System.Windows.Forms.Button; $bLater.Text = 'Để sau'; $bLater.Size = New-Object System.Drawing.Size(100, 34); $bLater.Location = New-Object System.Drawing.Point(488, 396); $bLater.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($bInstall, $bWeb, $bLater)); $d.CancelButton = $bLater
    Set-ControlTheme $d $Theme $Theme
    Add-IconsTo $d
    $d.Add_Shown({ param($sender, $e) Set-NativeTheme $sender })
    if ($d.ShowDialog($form) -eq 'Yes') { Install-PanelUpdate $r }
}

# Tải bộ cài ở nền rồi chạy; bộ cài tự tắt panel đang chạy, ghi đè và mở lại
function Install-PanelUpdate($r) {
    $installed = $PSScriptRoot -like (Join-Path $env:LOCALAPPDATA 'Programs\DevOpsPanel*')
    if (-not $installed) {
        $q = "Panel đang chạy từ thư mục mã nguồn:`n$PSScriptRoot`n`nBộ cài sẽ cài bản $($r.Version) vào %LOCALAPPDATA%\Programs\DevOpsPanel (không sửa thư mục mã nguồn). Tiếp tục?"
        if ([System.Windows.Forms.MessageBox]::Show($q, 'Cập nhật', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    Set-Status "Đang tải bộ cài $($r.Version)..."
    $form.Cursor = 'AppStarting'
    Start-CoreAsync 'Save-UpdateInstaller $p.Url $p.Ver $p.Size' @{ Url = $r.SetupUrl; Ver = $r.Version; Size = $r.SetupSize } {
        param($res, $ctx)
        $form.Cursor = 'Default'
        if (-not $res.Ok) {
            Set-Status "Không tải được bộ cài: $($res.Value)"
            if ([System.Windows.Forms.MessageBox]::Show("Không tải được bộ cài:`n$($res.Value)`n`nMở trang GitHub để tải thủ công?", 'Cập nhật', 'YesNo', 'Warning') -eq 'Yes') { Start-Process $script:latestRel.Url }
            return
        }
        Set-Status "Đã tải bộ cài $($ctx.Ver) - đang chạy..."
        try {
            Start-Process -FilePath ([string]$res.Value)
            $script:exiting = $true; $form.Close()          # bộ cài cũng tự tắt panel trước khi ghi đè
        } catch { Set-Status "Không chạy được bộ cài: $($_.Exception.Message)" }
    } @{ Ver = $r.Version }
}
Update-UpdateUi      # dòng phiên bản ở tab Trợ giúp trước khi kiểm tra xong
$updTimer = New-Object System.Windows.Forms.Timer
$updTimer.Interval = 12 * 3600 * 1000          # 12 giờ kiểm tra lại 1 lần
$updTimer.Add_Tick({ Start-UpdateCheck })

$form.Add_Activated({ if ($script:goalsDay -and $script:goalsDay -ne (Get-Today)) { Test-GoalsDaily } })
$goalsTimer = New-Object System.Windows.Forms.Timer; $goalsTimer.Interval = 10 * 60 * 1000
$goalsTimer.Add_Tick({ Test-GoalsDaily }); $goalsTimer.Start()

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
    Set-Theme $script:ThemeName
    Start-WebPanel
    Update-Status
    if ($settings.autoStartUbuntu -and -not (Get-KeepAlive)) {
        Invoke-Busy 'Đang tự khởi động Ubuntu...' { Start-Ubuntu }
        Set-Status 'Ubuntu đã được tự khởi động.'
    } else { Set-Status 'Sẵn sàng.' }
    $timer.Start()
    Update-MainLayout
    $goalT = New-Object System.Windows.Forms.Timer; $goalT.Interval = 1500
    $goalT.Add_Tick({ param($sender, $e) $sender.Stop(); Test-GoalsDaily }); $goalT.Start()
    $firstUpd = New-Object System.Windows.Forms.Timer; $firstUpd.Interval = 4000
    $firstUpd.Add_Tick({ param($sender, $e) $sender.Stop(); Start-UpdateCheck; $updTimer.Start() }); $firstUpd.Start()
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
foreach ($g in $pageMain.Controls) { if ($g -is [System.Windows.Forms.GroupBox]) { $g.Anchor = 'Top, Left' } }      # vị trí do Update-MainLayout đặt
$list.Anchor = 'Top, Bottom, Left, Right'
foreach ($c in $gStatus.Controls) { if ($c -is [System.Windows.Forms.Button]) { $c.Anchor = 'Bottom, Left' } }
$pageMain.Add_Resize({ Update-MainLayout })
foreach ($m in $meters.Values) { $m.Bar.Anchor = 'Top, Left, Right'; $m.Label.Anchor = 'Top, Right' }
foreach ($c in @($lblInfo, $lblWarn, $chart, $lblK3s, $lblApps)) { $c.Anchor = 'Top, Left, Right' }
$flK3s.Anchor = 'Top, Right'
foreach ($l in @($lnkWsl1, $lnkWsl2)) { $l.Anchor = 'Top, Left' }
$lblSearch.Anchor = 'Top, Right'; $txtSearch.Anchor = 'Top, Right'
foreach ($c in @($lblHelpTitle, $lblHelpVer)) { $c.Anchor = 'Top, Left, Right' }
$lnkUpdate.Anchor = 'Bottom, Right'
$lnkUpd.Anchor = 'Top, Left, Right'
$txtHelp.Anchor = 'Top, Bottom, Left, Right'
foreach ($c in $pageHelp.Controls) { if ($c -is [System.Windows.Forms.Button] -or $c -eq $lnkEmail -or $c -eq $lblContact) { $c.Anchor = 'Bottom, Left' } }
$lvCpu.Anchor = 'Top, Bottom, Left'; $lvRam.Anchor = 'Top, Bottom, Left'
$gGit.Anchor = 'Bottom, Left, Right'
foreach ($l in @($lblGit1, $lblGit2, $lblGit3)) { $l.Anchor = 'Top, Left, Right' }
foreach ($page in @($pageK3s, $pageApps)) {
    foreach ($c in $page.Controls) {
        if ($c -is [System.Windows.Forms.Button])   { $c.Anchor = 'Bottom, Left' }
        if ($c -is [System.Windows.Forms.ListView]) { $c.Anchor = 'Top, Bottom, Left, Right' }
    }
}
$lblK3sNet.Anchor = 'Top, Left, Right'; $btnK3sFix.Anchor = 'Top, Right'

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
        $s.Columns[$idx].Width = [math]::Max(80, $s.ClientSize.Width - $others - 4 - $(if ($s.Items.Count) { 0 } else { [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth }))
    }.GetNewClosure())
}
Set-FillColumn $list 0
Set-FillColumn $lvApps 1
Set-FillColumn $lvPods 1
Set-FillColumn $lvRepos 6
$lblFlow.Anchor = 'Top, Left, Right'; $lvRepos.Anchor = 'Top, Left, Right'
foreach ($c in $pageGit.Controls) { if ($c -is [System.Windows.Forms.Button]) { $c.Anchor = 'Top, Left' } }
$lblGitTab.Anchor = 'Top, Left, Right'; $chkLogAll.Anchor = 'Top, Right'; $cbLogN.Anchor = 'Top, Right'
$lvLog.Anchor = 'Top, Bottom, Left, Right'
Set-FillColumn $lvLog 1
$cbAiDir.Anchor = 'Top, Left, Right'; $lblAiModel.Anchor = 'Top, Right'; $cbAiModel.Anchor = 'Top, Right'
$btnProfiles.Anchor = 'Top, Right' 
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
$form.MinimumSize = New-Object System.Drawing.Size((760 + $SideW), (650 + $HeaderH))
$wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
$form.Size = New-Object System.Drawing.Size([math]::Min(1200, $wa.Width), [math]::Min(800, $wa.Height))
$form.Location = New-Object System.Drawing.Point(($wa.Left + ($wa.Width - $form.Width) / 2), ($wa.Top + ($wa.Height - $form.Height) / 2))

# Bố cục cuối: dải tiêu đề trên cùng, thanh điều hướng bên trái, trang bên phải. Làm SAU khi đã neo control và phóng
# cửa sổ (trang không bao giờ nhỏ hơn bố cục thiết kế) - đặt vị trí bằng code thì khoảng neo được tính lại theo chỗ mới.
$cw = $form.ClientSize.Width
$header.SetBounds(0, 0, $cw, $HeaderH); $header.Anchor = 'Top, Left, Right'
$sideNav.Anchor = 'Top, Bottom, Left'
Set-NavLayout
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
