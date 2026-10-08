# Pegasus Control Center - Tab 🐙 Git
# Bổ sung hàm cho tab Git: Open-GitRepo, GitLab MR helpers
# Tab Git chính đã được dựng trong PegasusPanel.ps1 (lvRepos, lvLog, gitBtns...)

function New-ProjectGitBranch($roots, $type, $name) {
    return New-RepoFlowBranch $roots $type $name $false
}

function Open-GitLabMergeRequest($root) {
    return Push-RepoBranchForMr $root
}

# Shortcut: mở repo trong tab Git
function Open-GitRepo([string]$root) {
    if (-not $root -or -not (Test-Path $root)) { return }
    $tabs.SelectedTab = $pageGit
    if ($script:reposLoaded) {
        foreach ($it in $lvRepos.Items) {
            if ($it.Tag.Root -eq $root) { $it.Selected = $true; $it.EnsureVisible(); break }
        }
    } else {
        $script:gitWantApp = (Split-Path $root -Leaf)
        Load-Repos
    }
}

# Tạo nhanh MR URL để copy (không push)
function Get-MrUrl([string]$root) {
    $url = Get-RepoWebUrl $root
    if (-not $url) { return $null }
    $branch = (Invoke-Git $root @('rev-parse', '--abbrev-ref', 'HEAD') 3000).Trim()
    if (-not $branch) { return $null }
    $target = if ($branch -like 'hotfix/*') { 'production' } else { 'main' }
    $enc = [System.Uri]::EscapeDataString($branch)
    return "$url/-/merge_requests/new?merge_request%5Bsource_branch%5D=$enc&merge_request%5Btarget_branch%5D=$target"
}

# Copy MR URL vào clipboard
function Copy-MrUrl([string]$root) {
    $url = Get-MrUrl $root
    if ($url) {
        [System.Windows.Forms.Clipboard]::SetText($url)
        Set-Status "Đã copy link MR: $url"
    } else {
        Set-Status 'Không tạo được URL MR (chưa có remote hoặc chưa ở nhánh feature/fix/hotfix)'
    }
}
