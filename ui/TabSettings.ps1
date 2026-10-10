# Pegasus Control Center - Tab ⚙️ Cài đặt & Chẩn đoán
function Save-PegasusSettings($cfg) {
    Save-PanelConfig $cfg
}

function Set-AppearancePreference([string]$name, [string]$colorScheme) {
    if ($script:updatingAppearance) { return }
    if (-not $ThemeModes.Contains($name)) { return }
    $colorScheme = $colorScheme.ToLowerInvariant()
    if (-not $ColorSchemes.Contains($colorScheme)) { $colorScheme = 'indigo' }
    if ($name -eq $script:ThemeName -and $colorScheme -eq $PanelConfig.colorScheme) { return }
    $next = $PanelConfig.PSObject.Copy()
    $next.theme = $name; $next.colorScheme = $colorScheme
    try { Save-PanelConfig $next }
    catch {
        $script:updatingAppearance = $true
        try {
            $cbTheme.SelectedIndex = [array]::IndexOf($ThemeModeKeys, [string]$script:ThemeName)
            $cbColorScheme.SelectedIndex = [array]::IndexOf($colorSchemeKeys, [string]$PanelConfig.colorScheme)
        } finally { $script:updatingAppearance = $false }
        Set-Status "Không lưu được giao diện: $($_.Exception.Message)"
        return
    }
    $PanelConfig.theme = $name; $PanelConfig.colorScheme = $colorScheme
    Set-Theme $name
    Set-Status ("Đã lưu giao diện {0}." -f $ThemeModes[$name].Name)
}
