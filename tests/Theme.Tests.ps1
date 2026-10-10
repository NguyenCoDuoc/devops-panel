param([string]$PreviewDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'ui/Controls.ps1')
. (Join-Path $root 'ui/Theme.ps1')
. (Join-Path $root 'ui/TabSettings.ps1')
. (Join-Path $root 'ui/TabAi.ps1')
. (Join-Path $root 'ui/TabDbTools.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
function Get-Luminance($color) {
    $channels = @($color.R, $color.G, $color.B) | ForEach-Object {
        $v = $_ / 255.0
        if ($v -le 0.04045) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) }
    }
    0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
}
function Get-Contrast($a, $b) {
    $x = Get-Luminance $a; $y = Get-Luminance $b
    ([math]::Max($x, $y) + 0.05) / ([math]::Min($x, $y) + 0.05)
}
function Import-Functions([string]$path, [string[]]$names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "Syntax errors in $path"
    foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($node.Name -in $names) { . ([scriptblock]::Create(($node.Extent.Text -replace '^function ', 'function script:'))) }
    }
    $ast
}
$null = Import-Functions (Join-Path $root 'PegasusCore.ps1') @('Get-PanelConfig', 'Save-PanelConfig')
$panelAst = Import-Functions (Join-Path $root 'PegasusPanel.ps1') @('New-Label', 'New-Button', 'New-ThemedInput', 'New-DocLink', 'Set-ButtonRow', 'Set-SettingsLayout', 'Convert-ThemeColor', 'Set-ControlTheme', 'Test-PrimaryButton', 'Set-Theme', 'Update-IconColors', 'Get-IconBitmap', 'Find-IconRule', 'Add-IconsTo', 'Add-MenuIcons', 'Set-ObjIcon', 'Enable-ThemedComboBox', 'Enable-ThemedListView', 'Set-RowHeight', 'Get-RowBack', 'Draw-SideItem')
$panelSource = $panelAst.Extent.Text
$null = Import-Functions (Join-Path $root 'PegasusPanel.ps1') @('Get-ButtonContentWidth', 'Initialize-DarkNative', 'Set-NativeTheme', 'Set-MenuTheme')
$start = $panelSource.IndexOf('$IconRules = @('); $end = $panelSource.IndexOf('$TabIcons =', $start)
. ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
foreach ($file in 'ui/Controls.ps1', 'ui/Theme.ps1', 'ui/TabSettings.ps1', 'ui/TabAi.ps1', 'ui/TabDbTools.ps1', 'tests/Theme.Tests.ps1') {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "Syntax errors in $file"
}
foreach ($mode in $ThemeModeKeys) {
    foreach ($name in $ColorSchemes.Keys) {
        $p = Get-ThemePalette $mode $name
        foreach ($key in 'Back', 'Card', 'Surface', 'Sel', 'Hi', 'Header', 'Button') {
            Assert ((Get-Contrast $p.Text $p[$key]) -ge 4.5) "Text contrast $name/$mode/$key"
            Assert ((Get-Contrast $p.Muted $p[$key]) -ge 4.5) "Muted contrast $name/$mode/$key"
        }
        Assert ((Get-Contrast $p.Link $p.Surface) -ge 4.5) "Link contrast $name/$mode"
        Assert ((Get-Contrast $p.AccentText $p.Accent) -ge 4.5) "Button contrast $name/$mode"
        Assert ((Get-Contrast $p.AccentText $p.AccentHi) -ge 4.5) "Hover contrast $name/$mode"
        Assert ((Get-Contrast $p.NavMuted $p.NavBack) -ge 4.5) "Nav contrast $name/$mode"
        Assert ((Get-Contrast $p.NavSelText $p.NavSel) -ge 4.5) "Selected nav contrast $name/$mode"
        foreach ($token in 'Ok', 'Err', 'Warn', 'Info') { Assert ((Get-Contrast $p[$token] $p.Button) -ge 4.5) "Status contrast $name/$mode/$token" }
    }
}
$AiSmall = New-Object System.Drawing.Font('Segoe UI', 9)
foreach ($width in 340, 520, 710, 1000) {
    $layout = Get-AiContextLayout $width 30 'D:\Projects\very-long-workspace-folder-name' @{ Repo = $true; Branch = 'feature/reward-wallet-and-transactions-with-very-long-name'; Add = 12345; Del = 123; New = 45 }
    foreach ($segment in $layout.Segments) { Assert ($segment.Bounds.Right -lt $layout.Link.Bounds.Left -and $segment.Bounds.Width -ge 0) "Git overlap at $width" }
    Assert ($layout.Link.Bounds.Right -le $width) 'Git link overflow'
}
# Build real controls with temporary config; no service callbacks are invoked.
$DataDir = Join-Path ([IO.Path]::GetTempPath()) ('PegasusThemeTest-' + [guid]::NewGuid().ToString('N'))
$ConfigFile = Join-Path $DataDir 'config.json'
New-Item -ItemType Directory $DataDir | Out-Null
$form = New-Object System.Windows.Forms.Form
try {
    '{"appName":"Develop Workspace","theme":"modern","navLayout":"side","scanRoots":["D:\\Projects\\platform"],"noLockOnSleep":true}' | Set-Content $ConfigFile -Encoding UTF8
    $PanelConfig = Get-PanelConfig
    Assert ($PanelConfig.colorScheme -eq 'indigo') 'Legacy config fallback'
    $PanelConfig.colorScheme = 'invalid'; Save-PanelConfig $PanelConfig
    $PanelConfig = Get-PanelConfig
    Assert ($PanelConfig.colorScheme -eq 'indigo') 'Invalid config fallback'
    $script:ThemeName = 'modern'; $Theme = Get-ThemePalette 'light' 'indigo'
    $AppName = $PanelConfig.appName; $PanelVersion = '1.0.7'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.FormBorderStyle = 'None'
    $form.ClientSize = New-Object System.Drawing.Size(1200, 840)
    $form.ShowInTaskbar = $false; $form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(-32000, -32000)
    $tabs = New-Object System.Windows.Forms.TabControl; $tabs.SetBounds(196, 56, 1004, 784)
    $pageSettings = New-Object System.Windows.Forms.TabPage('Cài đặt'); $pageSettings.Name = 'settings'
    $pageDbTools = New-Object System.Windows.Forms.TabPage('DB Helper'); $pageDbTools.Name = 'db'
    $tabs.TabPages.AddRange(@($pageSettings, $pageDbTools)); $form.Controls.Add($tabs)
    $tipDoc = New-Object System.Windows.Forms.ToolTip
    $CardFont = New-Object System.Drawing.Font('Segoe UI Semibold', 9.75)
    $TabFont = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $TabFontBold = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $WslDistros = @()
    function Set-Status($text) { $script:lastStatus = $text }
    function Get-AppsConfig { @{ Apps = @(); Ranges = @(,@(5000, 5099)) } }
    function Update-AiTheme {}
    function Get-Greeting { 'Chào buổi chiều, hieuvm!' }
    $start = $panelSource.IndexOf('$gGeneral = New-Group'); $end = $panelSource.IndexOf('# ---------- Tab Trợ giúp', $start)
    . ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
    $AppIcon = New-Object System.Drawing.Icon((Join-Path $root 'icon.ico'))
    Build-TabDbTools $pageDbTools
    Assert (-not $pageDbTools.Tag.List.OwnerDraw) 'Fixture must reproduce early-built table'
    $start = $panelSource.IndexOf('$HeaderFontLv ='); $end = $panelSource.IndexOf('$AllListViews =', $start)
    . ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
    $start = $panelSource.IndexOf('$HeaderH ='); $end = $panelSource.IndexOf('function Get-HeaderTabAt', $start)
    . ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
    $form.Controls.Add($header)
    $script:hdrChips = @('6 app đang chạy', 'RAM 54%', 'CPU 15%')
    $start = $panelSource.IndexOf('$SideW ='); $end = $panelSource.IndexOf('function Get-SideAt', $start)
    . ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
    $sideNav.SetBounds(0, 56, 196, 784)
    $chart = New-Object System.Windows.Forms.Panel; $lvLog = New-Object System.Windows.Forms.ListView
    $AllListViews = @($pageDbTools.Tag.List)
    $appsMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miAppProfiles = New-Object System.Windows.Forms.ToolStripMenuItem('Bộ app'); [void]$appsMenu.Items.Add($miAppProfiles)
    Add-IconsTo $form
    $disabledButton = New-Button 'Khởi động' 12 70 130 $gGeneral {}; $disabledButton.Enabled = $false; $disabledButton.Visible = $false
    $pageUiChecks = New-Object System.Windows.Forms.TabPage('Kiểm tra UI'); $pageUiChecks.Name = 'text-checks'
    $tabs.TabPages.Add($pageUiChecks)
    $gWslCheck = New-Group 'WSL · trạng thái chưa cài distro' 10 95 $pageUiChecks
    foreach ($text in 'Khởi động', 'Tắt', 'Mở terminal') {
        $button = New-Button $text 12 36 130 $gWslCheck {}; $button.Enabled = $false
    }
    Add-IconsTo $gWslCheck; [void](Set-ButtonRow $gWslCheck 36)
    $gAiCheck = New-Group 'AI Code · tên thư mục và nhánh dài' 120 95 $pageUiChecks; $gAiCheck.Width = 760
    $aiCtx = New-Object System.Windows.Forms.Panel; $aiCtx.SetBounds(12, 36, 710, 34); $gAiCheck.Controls.Add($aiCtx)
    function Get-AiDir { 'D:\Projects\workspace-with-a-very-long-folder-name' }
    $script:aiCtxInfo = @{ Repo = $true; Branch = 'feature/reward-wallet-and-transactions-with-a-very-long-name'; Add = 1234; Del = 67; New = 3 }
    $start = $panelSource.IndexOf('$aiCtx.Add_Paint('); $end = $panelSource.IndexOf('$aiCtx.Add_MouseMove(', $start)
    . ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $dr = $tabs.DisplayRectangle
    $tabs.Location = New-Object System.Drawing.Point((196 - $dr.X), (64 - $dr.Y))
    $tabs.Region = New-Object System.Drawing.Region($tabs.DisplayRectangle)
    if ($PreviewDirectory) { $null = New-Item -ItemType Directory -Path $PreviewDirectory -Force }
    foreach ($mode in $ThemeModeKeys) {
        $cbTheme.SelectedIndex = [array]::IndexOf($ThemeModeKeys, $mode)
        if ($mode -eq 'modern') { Set-Theme $mode }
        Assert ((Get-PanelConfig).theme -eq $mode -and $PanelConfig.noLockOnSleep) "Persist $mode preserving other settings"
        Assert ($pageDbTools.Tag.List.OwnerDraw) 'Early-built ListView headers themed'
        Assert ($disabledButton.DisabledTextColor.ToArgb() -eq $Theme.Muted.ToArgb()) 'Disabled text follows theme'
        Assert ($cbColorScheme.Enabled -eq ($mode -notin 'atelier', 'aurora')) 'Signature palette'
        foreach ($width in 540, 760, 1180) {
            $tabs.Width = $width; Set-SettingsLayout; Set-DbToolsLayout $pageDbTools
            Assert (-not $gAppearance.Bounds.IntersectsWith($gWsl.Bounds) -and -not $gAppearance.Bounds.IntersectsWith($gScan.Bounds)) 'Settings cards overlap'
            Assert (-not $txtName.Parent.Bounds.IntersectsWith($btnRename.Bounds)) 'Name overlaps rename'
            $wslLabels = @($gWsl.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })
            foreach ($label in $wslLabels) {
                $measured = [System.Windows.Forms.TextRenderer]::MeasureText($label.Text, $label.Font, (New-Object System.Drawing.Size($label.Width, 1000)), [System.Windows.Forms.TextFormatFlags]'WordBreak, NoPrefix')
                Assert ($measured.Height -le $label.Height) "WSL label clipped: $($label.Text) at $width"
                foreach ($other in $gWsl.Controls) { if ($other -ne $label) { Assert (-not $label.Bounds.IntersectsWith($other.Bounds)) "WSL label overlaps another control: $($label.Text) at $width" } }
            }
            foreach ($button in @($btnAddScanRoot, $btnRemoveScanRoot, $btnEditApps, $btnRename)) {
                Assert ($button.Width -ge (Get-ButtonContentWidth $button)) "Clipped $($button.Text)"
                Assert ($button.Right -le $button.Parent.Width - 10) "Overflow $($button.Text)"
            }
            Assert ($pageSettings.AutoScrollMinSize.Height -ge $btnSaveSettings.Bottom) 'Save button unreachable'
            foreach ($group in @($pageDbTools.Tag.Migration, $pageDbTools.Tag.Seed, $pageDbTools.Tag.Connections, $pageDbTools.Tag.Tools)) {
                $buttons = @($group.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
                foreach ($button in $buttons) {
                    Assert ($button.Right -le $group.Width - 10) "DB button overflow $($button.Text)"
                    foreach ($other in $buttons) { if ($other -ne $button) { Assert (-not $button.Bounds.IntersectsWith($other.Bounds)) 'DB buttons overlap' } }
                }
                $sizes = @($buttons | ForEach-Object { $_.Width })
                Set-DbToolsLayout $pageDbTools
                Assert (($sizes -join ',') -eq (($buttons | ForEach-Object { $_.Width }) -join ',')) 'Repeated layout grows buttons'
            }
        }
        if ($PreviewDirectory) {
            $tabs.Width = 1004; [System.Windows.Forms.Application]::DoEvents()
            $tabs.Region = New-Object System.Drawing.Region($tabs.DisplayRectangle)
            Set-SettingsLayout; Set-DbToolsLayout $pageDbTools
            foreach ($page in @($pageSettings, $pageDbTools, $pageUiChecks)) {
                $tabs.SelectedTab = $page; [System.Windows.Forms.Application]::DoEvents(); $form.Refresh()
                $bitmap = New-Object System.Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
                try { $form.DrawToBitmap($bitmap, $form.ClientRectangle); $bitmap.Save((Join-Path $PreviewDirectory "$mode-$($page.Name).png"), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
            }
        }
    }
    if ($PreviewDirectory) {
        Set-AppearancePreference 'light' 'indigo'
        $form.ClientSize = New-Object System.Drawing.Size(1527, 840); $header.Width = 1527; $tabs.Width = 1330
        $tabs.SelectedTab = $pageSettings; [System.Windows.Forms.Application]::DoEvents()
        $tabs.Region = New-Object System.Drawing.Region($tabs.DisplayRectangle)
        Set-SettingsLayout; $form.Refresh()
        $bitmap = New-Object System.Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
        try { $form.DrawToBitmap($bitmap, $form.ClientRectangle); $bitmap.Save((Join-Path $PreviewDirectory 'light-settings-wide.png'), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    }
    foreach ($scheme in $ColorSchemes.Keys) {
        Set-AppearancePreference 'modern' $scheme
        Assert ((Get-PanelConfig).colorScheme -eq $scheme -and $Theme.Accent.ToArgb() -eq (Get-ThemePalette 'modern' $scheme).Accent.ToArgb()) "Apply and persist accent $scheme"
    }
    Set-AppearancePreference 'modern' 'ocean'
    $null = $btnResetColors.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($btnResetColors, @([EventArgs]::Empty))
    Assert ($PanelConfig.colorScheme -eq 'indigo' -and $script:ThemeName -eq 'modern') 'Reset preserves mode'
    $validConfigFile = $ConfigFile; $ConfigFile = $DataDir
    $cbTheme.SelectedIndex = 3
    Assert ($script:ThemeName -eq 'modern' -and $cbTheme.SelectedIndex -eq 2 -and $lastStatus -like 'Không lưu được*') 'Failed save rolls back'
    $ConfigFile = $validConfigFile
    Assert $script:darkNativeLoaded 'Native theme helpers compile'
    Write-Host 'PASS: PS 5.1 syntax, five modes, contrast, long Git labels, persistence, save failure, disabled buttons, table headers, real Settings/DB layout and WSL labels at three widths.'
} finally {
    $form.Close(); $form.Dispose(); $AiSmall.Dispose()
    # Remove only this test config.
    if (Test-Path -LiteralPath (Join-Path $DataDir 'config.json')) { Remove-Item -LiteralPath (Join-Path $DataDir 'config.json') }
    Remove-Item -LiteralPath $DataDir
}
