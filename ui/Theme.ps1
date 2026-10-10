# Pegasus Control Center - Theme, Design System & Drawing Engine
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function New-Rgb([int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }

$script:ThemePalettes = @{
    light = @{
        Back = (New-Rgb 246 248 251); Card = (New-Rgb 255 255 255); Surface = (New-Rgb 255 255 255); Alt = (New-Rgb 248 250 252); Header = (New-Rgb 241 245 249)
        Text = (New-Rgb 15 23 42); Muted = (New-Rgb 71 85 105); Gray = (New-Rgb 148 163 184)
        Ok = (New-Rgb 16 185 129); Err = (New-Rgb 190 18 60); Warn = (New-Rgb 217 119 6)
        Info = (New-Rgb 2 132 199); ErrBg = (New-Rgb 255 241 242); Link = (New-Rgb 79 70 229)
        ChartBg = (New-Rgb 255 255 255); Grid = (New-Rgb 226 232 240)
        Button = (New-Rgb 255 255 255); Border = (New-Rgb 226 232 240); Hi = (New-Rgb 239 242 247)
        Sel = (New-Rgb 224 231 255); SelInactive = (New-Rgb 241 245 249)
        Accent = (New-Rgb 79 70 229); Accent2 = (New-Rgb 14 165 233); AccentHi = (New-Rgb 67 56 202); AccentText = (New-Rgb 255 255 255)
    }
    dark = @{
        Back = (New-Rgb 20 21 24); Card = (New-Rgb 28 30 35); Surface = (New-Rgb 24 26 30); Alt = (New-Rgb 31 33 39); Header = (New-Rgb 33 36 43)
        Text = (New-Rgb 241 245 249); Muted = (New-Rgb 156 163 175); Gray = (New-Rgb 107 114 128)
        Ok = (New-Rgb 52 211 153); Err = (New-Rgb 248 113 113); Warn = (New-Rgb 251 191 36)
        Info = (New-Rgb 96 165 250); ErrBg = (New-Rgb 69 26 31); Link = (New-Rgb 129 140 248)
        ChartBg = (New-Rgb 24 26 30); Grid = (New-Rgb 44 48 58)
        Button = (New-Rgb 35 38 46); Border = (New-Rgb 48 52 62); Hi = (New-Rgb 44 48 58)
        Sel = (New-Rgb 45 52 76); SelInactive = (New-Rgb 36 40 52)
        Accent = (New-Rgb 99 102 241); Accent2 = (New-Rgb 56 189 248); AccentHi = (New-Rgb 129 140 248); AccentText = (New-Rgb 255 255 255)
    }
    modern = @{
        Back = (New-Rgb 242 244 252); Card = (New-Rgb 255 255 255); Surface = (New-Rgb 255 255 255); Alt = (New-Rgb 247 248 254); Header = (New-Rgb 237 240 252)
        Text = (New-Rgb 17 24 39); Muted = (New-Rgb 75 85 99); Gray = (New-Rgb 148 156 176)
        Ok = (New-Rgb 5 150 105); Err = (New-Rgb 190 18 60); Warn = (New-Rgb 217 119 6)
        Info = (New-Rgb 2 132 199); ErrBg = (New-Rgb 255 228 236); Link = (New-Rgb 79 70 229)
        ChartBg = (New-Rgb 255 255 255); Grid = (New-Rgb 228 231 245)
        Button = (New-Rgb 255 255 255); Border = (New-Rgb 220 224 241); Hi = (New-Rgb 238 240 255)
        Sel = (New-Rgb 224 228 255); SelInactive = (New-Rgb 237 239 250)
        Accent = (New-Rgb 79 70 229); Accent2 = (New-Rgb 147 51 234); AccentHi = (New-Rgb 67 56 202); AccentText = (New-Rgb 255 255 255)
    }
}

$script:ThemeModes = [ordered]@{
    light = @{ Name = 'Sáng · Light'; Description = 'Nền sáng trung tính, nội dung rõ ràng.' }
    dark = @{ Name = 'Tối · Dark'; Description = 'Nền graphite, ít chói khi làm việc buổi tối.' }
    modern = @{ Name = 'Hiện đại · Modern'; Description = 'Nền sáng dịu, điều hướng chuyển sắc rực rỡ và thẻ bo mềm có bóng.' }
    atelier = @{ Name = 'Atelier · giấy & mực'; Description = 'Giấy ấm, mực xanh, thẻ nét kẻ và tiêu đề serif.' }
    aurora = @{ Name = 'Aurora · đêm cực quang'; Description = 'Xanh đêm, mint, điều hướng và thẻ có lớp sáng chuyển sắc.' }
}
$script:ThemeModeKeys = @($ThemeModes.Keys)
$script:ThemePalettes.atelier = @{
    Back = (New-Rgb 243 239 230); Card = (New-Rgb 255 253 248); Surface = (New-Rgb 255 254 251); Alt = (New-Rgb 245 242 234); Header = (New-Rgb 237 231 218)
    Text = (New-Rgb 39 51 45); Muted = (New-Rgb 91 96 80); Gray = (New-Rgb 112 115 99)
    Ok = (New-Rgb 32 110 72); Err = (New-Rgb 172 48 54); Warn = (New-Rgb 139 82 19); Info = (New-Rgb 38 98 129); ErrBg = (New-Rgb 255 234 229)
    Link = (New-Rgb 139 70 35); ChartBg = (New-Rgb 255 253 248); Grid = (New-Rgb 223 215 199)
    Button = (New-Rgb 250 247 238); Border = (New-Rgb 199 190 171); Hi = (New-Rgb 239 231 212); Sel = (New-Rgb 232 222 196); SelInactive = (New-Rgb 240 233 216)
    Accent = (New-Rgb 140 70 35); Accent2 = (New-Rgb 37 85 66); AccentHi = (New-Rgb 111 53 26); AccentText = (New-Rgb 255 253 248)
}
$script:ThemePalettes.aurora = @{
    Back = (New-Rgb 9 25 33); Card = (New-Rgb 16 38 48); Surface = (New-Rgb 12 31 40); Alt = (New-Rgb 19 43 54); Header = (New-Rgb 22 47 60)
    Text = (New-Rgb 232 247 245); Muted = (New-Rgb 162 192 197); Gray = (New-Rgb 131 165 176)
    Ok = (New-Rgb 117 230 176); Err = (New-Rgb 255 155 156); Warn = (New-Rgb 244 205 135); Info = (New-Rgb 139 211 242); ErrBg = (New-Rgb 67 38 48)
    Link = (New-Rgb 123 233 207); ChartBg = (New-Rgb 12 31 40); Grid = (New-Rgb 42 75 88)
    Button = (New-Rgb 24 52 63); Border = (New-Rgb 53 88 100); Hi = (New-Rgb 28 61 72); Sel = (New-Rgb 34 70 79); SelInactive = (New-Rgb 23 49 59)
    Accent = (New-Rgb 123 233 207); Accent2 = (New-Rgb 139 211 242); AccentHi = (New-Rgb 93 211 186); AccentText = (New-Rgb 8 35 39)
}
foreach ($mode in $ThemeModes.Keys) {
    $palette = $ThemePalettes[$mode]
    $palette.NavBack = $palette.Card; $palette.NavText = $palette.Text; $palette.NavMuted = $palette.Muted
    $palette.NavSel = $palette.Sel; $palette.NavSelText = $palette.Text; $palette.NavAccent = $palette.Accent
    $palette.NavHi = $palette.Hi
    $palette.Chrome = $palette.Back; $palette.ChromeText = $palette.Text; $palette.ChromeMuted = $palette.Muted
    $palette.NavChip = $palette.NavBack; $palette.NavLine = $palette.Border
    $palette.CardRadius = 8; $palette.CardStyle = 'standard'
}
$ThemePalettes.atelier.NavBack = New-Rgb 28 53 45; $ThemePalettes.atelier.Chrome = $ThemePalettes.atelier.NavBack
$ThemePalettes.atelier.NavText = New-Rgb 248 244 233; $ThemePalettes.atelier.NavMuted = New-Rgb 195 206 187
$ThemePalettes.atelier.ChromeText = $ThemePalettes.atelier.NavText; $ThemePalettes.atelier.ChromeMuted = $ThemePalettes.atelier.NavMuted
$ThemePalettes.atelier.NavSel = New-Rgb 237 229 204; $ThemePalettes.atelier.NavSelText = New-Rgb 28 53 45
$ThemePalettes.atelier.NavHi = New-Rgb 42 76 61
$ThemePalettes.atelier.NavAccent = New-Rgb 226 183 116; $ThemePalettes.atelier.CardRadius = 3; $ThemePalettes.atelier.CardStyle = 'paper'
$ThemePalettes.aurora.NavBack = New-Rgb 7 22 30; $ThemePalettes.aurora.Chrome = $ThemePalettes.aurora.NavBack
$ThemePalettes.aurora.CardRadius = 14; $ThemePalettes.aurora.CardStyle = 'aurora'
$script:EditorialCardFont = New-Object System.Drawing.Font('Georgia', 9.5, ([System.Drawing.FontStyle]::Bold))

$script:ColorSchemes = [ordered]@{
    indigo   = @{ Name = 'Indigo · chàm'; Light = '#4F46E5'; LightHover = '#4338CA'; Dark = '#A5B4FC'; DarkHover = '#818CF8'; Nav = @('#4338CA', '#9333EA') }
    ocean    = @{ Name = 'Ocean · xanh biển'; Light = '#0369A1'; LightHover = '#075985'; Dark = '#7DD3FC'; DarkHover = '#38BDF8'; Nav = @('#075985', '#0E7490') }
    teal     = @{ Name = 'Teal · xanh ngọc'; Light = '#0F766E'; LightHover = '#115E59'; Dark = '#5EEAD4'; DarkHover = '#2DD4BF'; Nav = @('#134E4A', '#0E7490') }
    violet   = @{ Name = 'Violet · tím'; Light = '#7C3AED'; LightHover = '#6D28D9'; Dark = '#C4B5FD'; DarkHover = '#A78BFA'; Nav = @('#6D28D9', '#DB2777') }
    graphite = @{ Name = 'Graphite · xám'; Light = '#475569'; LightHover = '#334155'; Dark = '#CBD5E1'; DarkHover = '#94A3B8'; Nav = @('#1E293B', '#475569') }
}

function Get-ThemePalette([string]$name, [string]$colorScheme = 'indigo') {
    if (-not $ThemeModes.Contains($name)) { $name = 'modern' }
    if (-not $ColorSchemes.Contains($colorScheme)) { $colorScheme = 'indigo' }
    $palette = $ThemePalettes[$name].Clone()
    if ($name -in 'atelier', 'aurora') { return $palette }
    $scheme = $ColorSchemes[$colorScheme]
    $dark = $name -eq 'dark'
    $palette.Accent = [System.Drawing.ColorTranslator]::FromHtml($(if ($dark) { $scheme.Dark } else { $scheme.Light }))
    $palette.AccentHi = [System.Drawing.ColorTranslator]::FromHtml($(if ($dark) { $scheme.DarkHover } else { $scheme.LightHover }))
    $palette.AccentText = if ($dark) { $ThemePalettes.light.Text } else { [System.Drawing.Color]::White }
    $palette.Link = $palette.Accent; $palette.Accent2 = $palette.AccentHi
    $tints = @{ Back = 0.04; Card = 0.01; Surface = 0.02; Alt = 0.04; Header = 0.06; Button = 0.04; Hi = 0.08; Border = 0.08; Grid = 0.08; SelInactive = 0.08; Sel = 0.12 }
    foreach ($key in $tints.Keys) {
        $base = if ($key -in 'Sel', 'SelInactive', 'Hi') { $ThemePalettes[$name].Surface } else { $ThemePalettes[$name][$key] }
        $amount = $tints[$key]
        $palette[$key] = New-Rgb ([int]($base.R * (1 - $amount) + $palette.Accent.R * $amount)) `
                                ([int]($base.G * (1 - $amount) + $palette.Accent.G * $amount)) `
                                ([int]($base.B * (1 - $amount) + $palette.Accent.B * $amount))
    }
    $palette.NavSel = $palette.Sel; $palette.NavAccent = $palette.Accent
    $palette.NavHi = $palette.Hi
    $palette.NavSelText = $palette.Text
    if ($name -eq 'modern') {
        # Navbar chuyển sắc theo màu nhấn: mục chọn là viên trắng, chữ trắng trên nền màu
        $palette.NavBack = [System.Drawing.ColorTranslator]::FromHtml($scheme.Nav[0]); $palette.NavBack2 = [System.Drawing.ColorTranslator]::FromHtml($scheme.Nav[1])
        $palette.Chrome = $palette.NavBack; $palette.Accent2 = $palette.NavBack2
        $palette.NavText = [System.Drawing.Color]::White; $palette.NavMuted = New-Rgb 224 226 255
        $palette.ChromeText = $palette.NavText; $palette.ChromeMuted = $palette.NavMuted
        $palette.NavSel = [System.Drawing.Color]::White; $palette.NavSelText = $palette.AccentHi
        $palette.NavHi = [System.Drawing.Color]::FromArgb(40, 255, 255, 255)
        $palette.NavChip = [System.Drawing.Color]::FromArgb(36, 255, 255, 255); $palette.NavLine = [System.Drawing.Color]::FromArgb(70, 255, 255, 255)
        $palette.CardRadius = 12; $palette.CardStyle = 'modern'
    }
    if ($name -in 'light', 'modern') { $palette.Ok = New-Rgb 21 115 71; $palette.Warn = New-Rgb 151 82 15; $palette.Info = New-Rgb 3 105 161 }
    $palette
}

function Paint-ThemeCard($s, $g) {
    $g.SmoothingMode = 'AntiAlias'; $g.Clear($s.Parent.BackColor)
    $paper = $Theme.CardStyle -eq 'paper'; $modern = $Theme.CardStyle -eq 'modern'
    $inset = if ($paper -or $modern) { 3 } else { 1 }
    $path = New-RoundRect 0 0 ($s.Width - $inset) ($s.Height - $inset) $Theme.CardRadius
    if ($paper) {
        $shadow = New-Object System.Drawing.SolidBrush($Theme.Grid)
        $g.FillRectangle($shadow, 3, 3, ($s.Width - 3), ($s.Height - 3)); $shadow.Dispose()
    }
    if ($modern) {
        # bóng mềm: vài lớp mờ dần lệch xuống dưới
        foreach ($d in 3, 2, 1) {
            $sp = New-RoundRect $d ($d + 1) ($s.Width - 4) ($s.Height - 4) ($Theme.CardRadius + $d)
            $shadow = New-Object System.Drawing.SolidBrush((Get-Alpha (10 + 6 * (3 - $d)) $Theme.NavBack)); $g.FillPath($shadow, $sp); $shadow.Dispose(); $sp.Dispose()
        }
    }
    $brush = New-Object System.Drawing.SolidBrush($Theme.Card); $g.FillPath($brush, $path); $brush.Dispose()
    $pen = New-Object System.Drawing.Pen($Theme.Border); $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
    $font = $CardFont; $x = 22
    if ($paper) {
        $font = $EditorialCardFont; $x = 14
        $pen = New-Object System.Drawing.Pen($Theme.Accent, 2); $g.DrawLine($pen, 14, 1, ($s.Width - 17), 1); $pen.Dispose()
    } elseif ($Theme.CardStyle -eq 'aurora') {
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(14, 1)), (New-Object System.Drawing.Point(($s.Width - 14), 1)), $Theme.Accent, $Theme.Accent2)
        $pen = New-Object System.Drawing.Pen($brush, 2); $g.DrawLine($pen, 14, 1, ($s.Width - 14), 1); $pen.Dispose(); $brush.Dispose()
        $brush = New-Object System.Drawing.SolidBrush($Theme.Accent); $g.FillEllipse($brush, 12, 10, 5, 5); $brush.Dispose()
    } elseif ($modern) {
        $bar = New-RoundRect 12 7 4 15 2
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(12, 6, 4, 17)), $Theme.NavBack, $Theme.NavBack2, ([single]90))
        $g.FillPath($brush, $bar); $brush.Dispose(); $bar.Dispose()
    } else {
        $brush = New-Object System.Drawing.SolidBrush($Theme.Accent); $g.FillRectangle($brush, 12, 8, 3, 13); $brush.Dispose()
    }
    [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $font, (New-Object System.Drawing.Rectangle($x, 3, ($s.Width - $x - 12), 21)), $Theme.Text, [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix')
}

function Paint-NavBackground($g, $bounds, [bool]$header = $false) {
    $color = if ($header) { $Theme.Chrome } else { $Theme.NavBack }
    $g.Clear($color)
    if ($Theme.CardStyle -eq 'aurora' -and $bounds.Width -gt 0 -and $bounds.Height -gt 0) {
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bounds, $color, $Theme.Card, ([single]45))
        $g.FillRectangle($brush, $bounds); $brush.Dispose()
    }
    if ($Theme.CardStyle -eq 'modern' -and $bounds.Width -gt 0 -and $bounds.Height -gt 0) {
        # header ngang: chuyển sắc trái -> phải; sidebar dọc: trên -> dưới, thêm quầng sáng nhẹ ở góc
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bounds, $Theme.NavBack, $Theme.NavBack2, ([single]$(if ($header) { 0 } else { 70 })))
        $g.FillRectangle($brush, $bounds); $brush.Dispose()
        $glow = New-Object System.Drawing.SolidBrush((Get-Alpha 22 ([System.Drawing.Color]::White)))
        $gw = [math]::Max(120, [int]($bounds.Width * 0.9))
        $g.FillEllipse($glow, ($bounds.Right - [int]($gw * 0.6)), (-[int]($gw * 0.5)), $gw, $gw); $glow.Dispose()
    }
    if ($Theme.CardStyle -eq 'paper') {
        $pen = New-Object System.Drawing.Pen($Theme.NavAccent, 2)
        $g.DrawLine($pen, 1, 1, ($bounds.Width - 1), 1); $pen.Dispose()
    }
}

$script:LaneColors = @((New-Rgb 99 102 241), (New-Rgb 244 63 94), (New-Rgb 16 185 129), (New-Rgb 245 158 11), (New-Rgb 168 85 247),
                       (New-Rgb 14 165 233), (New-Rgb 236 72 153), (New-Rgb 132 204 22), (New-Rgb 249 115 22), (New-Rgb 96 165 250))

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
    $cardPaint = { param($s, $e) Paint-ThemeCard $s $e.Graphics }
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
        $p = New-RoundRect 0 0 ($s.Width - 1) ($s.Height - 1) 8
        $b = New-Object System.Drawing.SolidBrush($Theme.Surface); $g.FillPath($b, $p); $b.Dispose()
        $pen = New-Object System.Drawing.Pen($(if ($s.ContainsFocus) { $Theme.Accent } else { $Theme.Border }), $(if ($s.ContainsFocus) { 1.5 } else { 1 })); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
    }
    $p.Add_Paint($hostPaint); $p.Add_Resize({ param($s, $e) $s.Invalidate() })
    $parent.Controls.Add($p)
    $p
}
