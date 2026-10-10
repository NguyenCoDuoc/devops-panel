param([string]$PreviewDirectory)
$ErrorActionPreference = 'Stop'
$gitPreviewDirectory = $PreviewDirectory
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::SetUnhandledExceptionMode('ThrowException')
. (Join-Path $PSScriptRoot 'Theme.Tests.ps1')
. (Join-Path $root 'ui/TabGit.ps1')
$null = Import-Functions (Join-Path $root 'PegasusCore.ps1') @('Invoke-Git', 'Get-RepoBranches', 'Get-RepoChanges', 'Get-RepoCommits', 'Get-CommitDetail', 'Get-CommitFileDiff', 'Get-WorkingDiff', 'Invoke-RepoStage', 'Invoke-RepoCommit', 'Get-RepoBrowserData', 'Get-RepoFileTree', 'Get-RepoFileContent', 'Get-RepoGitInfo', 'Hide-UrlSecret')
$null = Import-Functions (Join-Path $root 'PegasusPanel.ps1') @('Show-GitBrowser', 'New-GitListView', 'New-RtbView', 'New-ToolButton', 'Get-CodeColor', 'Get-LanePen', 'Fill-CommitList', 'GitB-SetStatus', 'GitB-Refresh', 'GitB-LoadCommits', 'GitB-ShowCommit', 'GitB-ShowFileDiff', 'GitB-Checkout', 'Show-DiffText', 'Show-CommitDialog', 'Update-CommitChanges', 'Show-CommitFileDiff', 'Set-CommitStatus', 'Invoke-CommitStage', 'Invoke-CommitNow', 'Get-SelectedRepos', 'Set-DoubleBuffered', 'ConvertTo-NoDiacritics')
$start = $panelSource.IndexOf('$script:gitWindows ='); $end = $panelSource.IndexOf('function Show-DiffText', $start)
. ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
$start = $panelSource.IndexOf('$script:lanePens ='); $end = $panelSource.IndexOf('# Đổ danh sách commit', $start)
. ([scriptblock]::Create($panelSource.Substring($start, $end - $start)))
$GitExe = (Get-Command git.exe).Source
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('PegasusGitTest-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $scratch
$repoRoot = Join-Path $scratch 'demo'; $otherRoot = Join-Path $scratch 'other'
function Run-Git($dir, $arguments) { $r = Invoke-Git $dir $arguments; Assert ($r.Code -eq 0) $r.Err; $r.Out }
foreach ($dir in $repoRoot, $otherRoot) {
    $null = New-Item -ItemType Directory $dir
    $null = Run-Git $dir @('init', '-b', 'main')
    $null = Run-Git $dir @('config', 'user.name', 'Git UI Test')
    $null = Run-Git $dir @('config', 'user.email', 'test@example.invalid')
    'first line' | Set-Content (Join-Path $dir 'sample file.txt') -Encoding UTF8
    $null = Run-Git $dir @('add', '.')
    $null = Run-Git $dir @('commit', '-m', 'Initial repository')
}
$null = Run-Git $repoRoot @('switch', '-c', 'feature/graph')
'feature' | Set-Content (Join-Path $repoRoot 'feature.txt') -Encoding UTF8
$null = Run-Git $repoRoot @('add', '.')
$null = Run-Git $repoRoot @('commit', '-m', 'Add developer workflow')
$featureHash = Run-Git $repoRoot @('rev-parse', 'HEAD')
$null = Run-Git $repoRoot @('switch', 'main')
'main change' | Set-Content (Join-Path $repoRoot 'main.txt') -Encoding UTF8
$null = Run-Git $repoRoot @('add', '.')
$null = Run-Git $repoRoot @('commit', '-m', 'Improve workspace')
$null = Run-Git $repoRoot @('merge', '--no-ff', 'feature/graph', '-m', 'Merge developer workflow')
$null = Run-Git $repoRoot @('tag', 'v1.0.0')
$null = Run-Git $repoRoot @('remote', 'add', 'origin', 'https://example.invalid/demo.git')
$null = Run-Git $repoRoot @('update-ref', 'refs/remotes/origin/main', 'HEAD')
$null = Run-Git $repoRoot @('switch', '-c', 'feature/current-work')
'staged version' | Set-Content (Join-Path $repoRoot 'sample file.txt') -Encoding UTF8
$null = Run-Git $repoRoot @('add', 'sample file.txt')
'working version' | Set-Content (Join-Path $repoRoot 'sample file.txt') -Encoding UTF8
'new file' | Set-Content (Join-Path $repoRoot 'notes with spaces.txt') -Encoding UTF8
$pending = @(Get-RepoChanges $repoRoot)
Assert (@($pending | Where-Object Path -eq 'sample file.txt').Count -eq 2) 'MM file must have both staged and unstaged entries'
Assert (@(Get-RepoCommits $repoRoot 300 $true | Where-Object Merge).Count -eq 1) 'Merge graph'
Assert ((Get-RepoFileContent $repoRoot $featureHash 'feature.txt') -like '*feature*') 'Historical file content'
Assert ('notes with spaces.txt' -in @(Get-RepoFileTree $repoRoot 'working') -and 'notes with spaces.txt' -notin @(Get-RepoFileTree $repoRoot 'index')) 'File tree distinguishes worktree and index'
$large = Join-Path $repoRoot 'large.dat'; [IO.File]::WriteAllBytes($large, (New-Object byte[] (513KB)))
Assert ((Get-RepoFileContent $repoRoot 'working' 'large.dat') -like '*512 KB*') 'Large file preview limit'
Remove-Item -LiteralPath $large
$binary = Join-Path $repoRoot 'binary.dat'; [IO.File]::WriteAllBytes($binary, [byte[]]@(1, 0, 2))
Assert ((Get-RepoFileContent $repoRoot 'working' 'binary.dat') -like '*nhị phân*') 'Binary file preview'
Remove-Item -LiteralPath $binary
$escaped = $false; try { Get-RepoFileContent $repoRoot 'working' '../outside.txt' | Out-Null } catch { $escaped = $true }; Assert $escaped 'Path cannot escape repository'
$script:gitQueue = New-Object System.Collections.ArrayList
$unbornRoot = Join-Path $scratch 'unborn'; $null = New-Item -ItemType Directory $unbornRoot
$null = Run-Git $unbornRoot @('init', '-b', 'main')
Assert (@(Get-RepoCommits $unbornRoot 300 $false).Count -eq 0 -and (Get-RepoBrowserData $unbornRoot).Branch -eq 'main') 'Repository before first commit'
function Start-CoreAsync($code, $params, $onDone, $ctx = @{}) { [void]$script:gitQueue.Add(@{ Code = $code; Params = $params; Callback = $onDone; Context = $ctx }) }
function Load-Repos { }
function Pump-Git {
    [System.Windows.Forms.Application]::DoEvents()
    $steps = 0
    while ($script:gitQueue.Count) {
        Assert ($steps++ -lt 100) 'Unexpected async loop'
        $job = $script:gitQueue[0]; $script:gitQueue.RemoveAt(0); $p = $job.Params
        try { $result = [pscustomobject]@{ Ok = $true; Value = (& ([scriptblock]::Create($job.Code))) } }
        catch { $result = [pscustomobject]@{ Ok = $false; Value = $_.Exception.Message } }
        & $job.Callback $result $job.Context
        [System.Windows.Forms.Application]::DoEvents()
    }
}
$form = New-Object System.Windows.Forms.Form
$form.Font = $font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.ClientSize = New-Object System.Drawing.Size(1400, 820); $form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(-32000, -32000)
$tabs = New-Object System.Windows.Forms.TabControl; $tabs.Dock = 'Fill'; $form.Controls.Add($tabs)
$pageGit = New-Object System.Windows.Forms.TabPage('Git'); $tabs.TabPages.Add($pageGit)
$script:gitTabBrowser = $null; $script:gitManualRoots = @(); $script:reposBusy = $false
$script:repos = @([pscustomobject]@{ Root = $repoRoot; Name = 'demo'; IsRepo = $true; Apps = 'Demo' }, [pscustomobject]@{ Root = $otherRoot; Name = 'other'; IsRepo = $true; Apps = '' })
$script:reposLoaded = $true; $lvRepos = New-Object System.Windows.Forms.ListView
$repoMenu = New-Object System.Windows.Forms.ContextMenuStrip
try {
    Initialize-GitTab; Sync-GitRepoPicker; $form.Show()
    Update-GitTabBrowser
    $old = $script:gitTabBrowser
    $script:gitRepoPicker.SelectedIndex = 1
    Pump-Git
    Assert $old.Form.IsDisposed 'Previous repository host must be disposed'
    Assert ($script:gitTabBrowser.Root -eq $otherRoot -and $script:gitTabBrowser.Rows.Count -eq 1) 'Old callbacks must not populate the new repository'
    $script:gitRepoPicker.SelectedIndex = 0; Pump-Git
    $st = $script:gitTabBrowser
    Assert ($st.LvC.Items.Count -eq 6) 'Four real commits plus Working directory and Commit index'
    Assert ($st.Tree.Nodes[0].Text -eq 'Branches' -and $st.Tree.Nodes[1].Text -eq 'Remotes') 'Repository navigation tree'
    Assert ($st.Details.TabPages.Count -eq 4) 'Commit, Diff, File tree, Console tabs'
    GitB-ShowCommit $st $st.LvC.Items[0].Tag; Pump-Git
    Assert ($st.LvF.Items.Count -eq 2) 'Working directory shows only unstaged changes'
    GitB-ShowCommit $st $st.LvC.Items[1].Tag; Pump-Git
    Assert ($st.LvF.Items.Count -eq 1 -and $st.Diff.Text -like '*staged version*') 'Index diff uses cached content'
    $headBefore = Run-Git $repoRoot @('rev-parse', 'HEAD')
    Find-GitCommit $st 'developer workflow'; Pump-Git
    Assert ($st.Info.Text -like '*developer workflow*') 'Search navigates to actual commit details'
    Assert ($st.Diff.Text -like '*diff --git*') 'Commit diff loads even while Diff tab is hidden'
    $st.Details.SelectedIndex = 2; [System.Windows.Forms.Application]::DoEvents()
    $leaf = $st.FileTree.Nodes | Where-Object { $_.Tag -eq 'feature.txt' } | Select-Object -First 1
    $st.FileTree.SelectedNode = $leaf; Pump-Git
    Assert ($st.FileContent.Text -like '*feature*') "Selecting file tree leaf loads snapshot content: leaf=$($leaf.Text), revision=$($st.Snapshot), content=$($st.FileContent.Text)"
    $branchNode = $st.Tree.Nodes[0].Nodes | Where-Object { $_.Tag.Name -eq 'main' } | Select-Object -First 1
    $st.Tree.SelectedNode = $branchNode; Pump-Git
    Assert ((Run-Git $repoRoot @('rev-parse', 'HEAD')) -eq $headBefore) 'Selecting a branch must not checkout'
    Assert (-not $st.ChkAll.Checked -and $st.Revision -eq 'main') 'Branch filter is reflected in toolbar'
    $st.Details.SelectedIndex = 0
    if ($gitPreviewDirectory) { $null = New-Item -ItemType Directory $gitPreviewDirectory -Force }
    foreach ($mode in $ThemeModeKeys) {
        $oldPalette = $Theme; $Theme = Get-ThemePalette $mode; $script:ThemeName = $mode
        Set-ControlTheme $form $oldPalette $Theme; Update-IconColors
        foreach ($width in 760, 1400) {
            $form.ClientSize = New-Object System.Drawing.Size($width, 820)
            [System.Windows.Forms.Application]::DoEvents(); Set-GitBrowserLayout $st
            foreach ($control in $st.Bar.Controls) { Assert ($control.Right -le $st.Bar.ClientSize.Width -and $control.Bottom -le $st.Bar.Height) "Toolbar overflow: $($control.Text) at $width/$mode" }
        }
        if ($gitPreviewDirectory) {
            foreach ($tabIndex in 0, 1) {
                $st.Details.SelectedIndex = $tabIndex; [System.Windows.Forms.Application]::DoEvents(); $form.Refresh()
                $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                try { $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bitmap.Save((Join-Path $gitPreviewDirectory "git-$mode-$tabIndex.png"), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
            }
        }
    }
    Show-CommitDialog $repoRoot $st; Pump-Git
    $dialog = [System.Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -like 'Commit -*' } | Select-Object -First 1
    $cs = $dialog.Tag
    Assert ($cs.LvW.Items.Count -eq 2 -and $cs.LvS.Items.Count -eq 1) "Commit dialog separates staged and unstaged files: working=$($cs.LvW.Items.Count), staged=$($cs.LvS.Items.Count), status=$($cs.Status.Text), queue=$($script:gitQueue.Count), dialog=$($dialog.Text)"
    foreach ($width in 760, 1180) {
        $dialog.Size = New-Object System.Drawing.Size($width, 740); [System.Windows.Forms.Application]::DoEvents(); Set-CommitDialogLayout $cs
        foreach ($bar in $cs.StageBar, $cs.CommitBar) { foreach ($control in $bar.Controls) { Assert ($control.Left -ge 0 -and $control.Right -le $bar.ClientSize.Width -and $control.Bottom -le $bar.Height) "Commit toolbar overflow: $($control.Text) at $width" } }
        Assert ($cs.Msg.Height -ge 80) "Commit message clipped at $width"
    }
    $item = $cs.LvW.Items | Where-Object { $_.Tag.Path -eq 'notes with spaces.txt' } | Select-Object -First 1; $item.Selected = $true
    Invoke-CommitStage $cs $true $false; $queued = $script:gitQueue.Count
    Invoke-CommitStage $cs $true $false
    Assert ($script:gitQueue.Count -eq $queued) 'Duplicate stage is blocked'
    Pump-Git
    Assert (@(Get-RepoChanges $repoRoot | Where-Object { $_.Path -eq 'notes with spaces.txt' -and $_.Staged }).Count -eq 1) 'Stage path with spaces'
    $cs.Msg.Text = 'Commit selected changes from UI test'
    Invoke-CommitNow $cs $false; $queued = $script:gitQueue.Count; Invoke-CommitNow $cs $false
    Assert ($script:gitQueue.Count -eq $queued) 'Duplicate commit is blocked'
    Pump-Git
    Assert ((Run-Git $repoRoot @('log', '-1', '--format=%s')) -eq 'Commit selected changes from UI test') 'Commit records the entered message'
    Assert (@(Get-RepoChanges $repoRoot | Where-Object { -not $_.Staged }).Count -eq 1) 'Commit leaves unstaged changes intact'
    $dialog.Close(); $dialog.Dispose()
    Show-GitBrowser $otherRoot; Pump-Git
    $standalone = $script:gitWindows[$otherRoot]
    Assert ($standalone.Tag.Rows.Count -eq 1 -and $standalone.Tag.Details.TabPages.Count -eq 4) 'Standalone browser callers still work'
    $standalone.Close(); $standalone.Dispose()
    Write-Host 'PASS: Git graph, merge, ref navigation, pending/index diffs, file tree, search, repo switching, stale callbacks, toolbar layout, stage and commit on temporary repositories.'
} finally {
    $form.Close(); $form.Dispose()
    # Both targets are unique temporary repositories created above.
    $resolvedScratch = [IO.Path]::GetFullPath($scratch)
    Assert ($resolvedScratch.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedScratch -Leaf) -like 'PegasusGitTest-*') 'Unsafe cleanup target'
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
}
