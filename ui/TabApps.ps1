# Pegasus Control Center - Tab 🚀 Ứng dụng & Storybook Hub

function Get-FilteredApps([string]$typeFilter) {
    $apps = Get-DevApps
    if (-not $typeFilter -or $typeFilter -eq 'ALL') { return $apps }
    if ($typeFilter -eq 'STORYBOOK') {
        return @($apps | Where-Object { $_.Name -like '*storybook*' -or $_.Id -like '*storybook*' -or $_.Group -eq 'Storybook' })
    }
    return @($apps | Where-Object { $_.Type -eq $typeFilter.ToLower() })
}
