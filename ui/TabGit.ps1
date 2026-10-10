# Pegasus Control Center - Tab 🐙 Git
# Git browser nhúng trong tab, tái sử dụng graph, diff và Commit của PegasusPanel.ps1.

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
    if ($script:gitRepoPicker) {
        Start-CoreAsync 'Get-RepoGitInfo $p.Root' @{ Root = $root } {
            param($r, $ctx)
            if (-not $r.Ok -or -not $r.Value.IsRepo) { Set-Status 'Không mở được repository Git tại thư mục đã chọn.'; return }
            $repo = $r.Value
            $repo | Add-Member NoteProperty Name (Split-Path $repo.Root -Leaf)
            $repo | Add-Member NoteProperty Apps ''
            if ($repo.Root -notin @($script:repos.Root)) { $script:repos += $repo }
            if ($repo.Root -notin @($script:gitManualRoots)) { $script:gitManualRoots += $repo.Root }
            $script:gitWantRoot = $repo.Root; Sync-GitRepoPicker; Update-GitTabBrowser
        }
        return
    }
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

# Shared by the embedded tab and the standalone browser; controls belong to their own repository.
function Get-GitBrowserState($control) {
    while ($control) {
        if ($control.Tag -is [hashtable] -and $control.Tag.Root -and $control.Tag.Form) { return $control.Tag }
        $control = $control.Parent
    }
}

function Enable-GitTreeTheme($tree) {
    $tree.DrawMode = 'OwnerDrawAll'
    $tree.Add_DrawNode({ param($s, $e)
        $bounds = New-Object System.Drawing.Rectangle(0, $e.Bounds.Y, $s.ClientSize.Width, $e.Bounds.Height)
        $color = if ($e.Node -eq $s.SelectedNode) { $Theme.Sel } else { $s.BackColor }
        $brush = New-Object System.Drawing.SolidBrush($color)
        try { $e.Graphics.FillRectangle($brush, $bounds) } finally { $brush.Dispose() }
        $textBounds = New-Object System.Drawing.Rectangle($e.Node.Bounds.Left, $bounds.Y, ([math]::Max(0, $bounds.Width - $e.Node.Bounds.Left)), $bounds.Height)
        $foreground = if ($e.Node.Tag.Current) { $Theme.Info } else { $Theme.Text }
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Node.Text, $s.Font, $textBounds, $foreground, ([System.Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis'))
        if ($e.Node.Nodes.Count) {
            $glyph = if ($e.Node.IsExpanded) { '▾' } else { '▸' }
            $arrow = New-Object System.Drawing.Rectangle(($e.Node.Bounds.Left - 16), $bounds.Y, 16, $bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $glyph, $s.Font, $arrow, $Theme.Muted, ([System.Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter'))
        }
    })
}

function Initialize-GitTab {
    $script:gitManualRoots = @()
    foreach ($control in $pageGit.Controls) { $control.Visible = $false }
    $script:gitBrowserHost = New-Object System.Windows.Forms.Panel
    $script:gitBrowserHost.Dock = 'Fill'; $pageGit.Controls.Add($script:gitBrowserHost)
    $row = New-Object System.Windows.Forms.Panel; $row.Dock = 'Top'; $row.Height = 42
    $script:gitRepoPicker = New-Object System.Windows.Forms.ComboBox
    $script:gitRepoPicker.DropDownStyle = 'DropDownList'; $script:gitRepoPicker.DisplayMember = 'Name'
    $script:gitRepoPicker.AccessibleName = 'Repository đang mở'; $script:gitRepoPicker.DropDownWidth = 620
    $script:gitRepoPicker.SetBounds(88, 6, 500, 30); $script:gitRepoPicker.Anchor = 'Top, Left, Right'
    $script:gitRepoPicker.ContextMenuStrip = $repoMenu; $row.Controls.Add($script:gitRepoPicker)
    New-Label 'Repository' 12 10 74 $row | Out-Null
    $open = New-Button 'Mở repo…' 596 6 120 $row {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Chọn repository Git'
        try { if ($dialog.ShowDialog() -eq 'OK') { Open-GitRepo $dialog.SelectedPath } } finally { $dialog.Dispose() }
    }
    $reload = New-Button 'Quét repo' 724 6 120 $row { Load-Repos }
    $open.Anchor = 'Top, Right'; $reload.Anchor = 'Top, Right'
    $row.Width = $pageGit.ClientSize.Width
    $pageGit.Controls.Add($row); $script:gitBrowserHost.BringToFront()
    $pickerLayout = { param($s, $e)
        $buttons = @($s.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | Sort-Object Left)
        $buttons[1].Left = $s.Width - $buttons[1].Width - 8
        $buttons[0].Left = $buttons[1].Left - $buttons[0].Width - 8
        $script:gitRepoPicker.Width = [math]::Max(100, $buttons[0].Left - 96)
    }
    $row.Add_Resize($pickerLayout); & $pickerLayout $row $null
    $script:gitRepoPicker.Add_SelectedIndexChanged({ if (-not $script:syncingGitPicker) { Update-GitTabBrowser } })
    $empty = New-Label 'Chọn hoặc mở repository để xem nhánh, lịch sử và diff.' 16 16 600 $script:gitBrowserHost
    $empty.AutoSize = $true
    Set-ControlTheme $pageGit $Theme $Theme; Add-IconsTo $row
}

function Sync-GitRepoPicker {
    $root = if ($script:gitWantRoot) { $script:gitWantRoot } elseif ($script:gitRepoPicker.SelectedItem) { $script:gitRepoPicker.SelectedItem.Root } elseif ($lvRepos.SelectedItems.Count) { $lvRepos.SelectedItems[0].Tag.Root }
    if ($script:gitWantApp) { $wanted = $script:repos | Where-Object { $_.IsRepo -and $script:gitWantApp -in @($_.Apps -split ', ') } | Select-Object -First 1; if ($wanted) { $root = $wanted.Root } }
    $script:syncingGitPicker = $true
    try {
        $script:gitRepoPicker.Items.Clear()
        foreach ($repo in @($script:repos | Where-Object IsRepo)) { [void]$script:gitRepoPicker.Items.Add($repo) }
        for ($i = 0; $i -lt $script:gitRepoPicker.Items.Count; $i++) { if ($script:gitRepoPicker.Items[$i].Root -eq $root) { $script:gitRepoPicker.SelectedIndex = $i; break } }
        if ($script:gitRepoPicker.SelectedIndex -lt 0 -and $script:gitRepoPicker.Items.Count) { $script:gitRepoPicker.SelectedIndex = 0 }
    } finally { $script:syncingGitPicker = $false; $script:gitWantRoot = $null }
}

function Update-GitTabBrowser([switch]$Force) {
    $repo = $script:gitRepoPicker.SelectedItem
    if (-not $repo) { return }
    $tipDoc.SetToolTip($script:gitRepoPicker, $repo.Root)
    $st = $script:gitTabBrowser
    if ($st -and -not $st.Form.IsDisposed -and $st.Root -eq $repo.Root) { if ($Force) { GitB-Refresh $st }; return }
    foreach ($control in @($script:gitBrowserHost.Controls)) { $control.Dispose() }
    $script:gitTabBrowser = Show-GitBrowser $repo.Root $script:gitBrowserHost
}

function Initialize-GitDetails($st, $right, $bottom, $bar, $info) {
    $details = New-Object System.Windows.Forms.TabControl; $details.Dock = 'Fill'; $st.Details = $details
    foreach ($name in 'Commit', 'Diff', 'File tree', 'Console') { $details.TabPages.Add((New-Object System.Windows.Forms.TabPage($name))) }
    $info.Parent.Controls.Remove($info); $info.Dock = 'Fill'; $info.Font = $font
    $details.TabPages[0].Controls.Add($info)
    $bottom.Parent.Controls.Remove($bottom); $details.TabPages[1].Controls.Add($bottom)
    $right.Panel2.Controls.Add($details)
    $details.DrawMode = 'OwnerDrawFixed'; $details.ItemSize = New-Object System.Drawing.Size(88, 30)
    $details.Add_DrawItem({ param($s, $e)
        $selected = $e.Index -eq $s.SelectedIndex
        $color = if ($selected) { $Theme.Sel } else { $Theme.Card }
        $brush = New-Object System.Drawing.SolidBrush($color)
        try { $e.Graphics.FillRectangle($brush, $e.Bounds) } finally { $brush.Dispose() }
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $s.TabPages[$e.Index].Text, $s.Font, $e.Bounds, $Theme.Text, ([System.Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter'))
        if ($selected) { $pen = New-Object System.Drawing.Pen($Theme.Accent, 2); try { $e.Graphics.DrawLine($pen, $e.Bounds.Left, $e.Bounds.Bottom - 2, $e.Bounds.Right, $e.Bounds.Bottom - 2) } finally { $pen.Dispose() } }
    })
    $fileSplit = New-Object System.Windows.Forms.SplitContainer; $fileSplit.Dock = 'Fill'
    $st.FileTree = New-Object System.Windows.Forms.TreeView; $st.FileTree.Dock = 'Fill'; $st.FileTree.HideSelection = $false
    $st.FileTree.BorderStyle = 'None'; $st.FileTree.ShowNodeToolTips = $true
    Enable-GitTreeTheme $st.Tree; Enable-GitTreeTheme $st.FileTree
    $st.FileContent = New-RtbView
    $fileSplit.Panel1.Controls.Add($st.FileTree); $fileSplit.Panel2.Controls.Add($st.FileContent)
    $details.TabPages[2].Controls.Add($fileSplit); $st.FileSplit = $fileSplit
    $st.FileTree.Add_AfterSelect({ param($s, $e) $st = Get-GitBrowserState $s; if ($e.Node.Tag -is [string]) { GitB-LoadFileContent $st $e.Node.Tag } })
    $st.Console = New-RtbView; $st.Console.WordWrap = $true; $details.TabPages[3].Controls.Add($st.Console)
    $searchGroup = New-Object System.Windows.Forms.Panel; $searchGroup.Size = New-Object System.Drawing.Size(270, 36); $searchGroup.Margin = New-Object System.Windows.Forms.Padding(8, 2, 4, 0); $bar.Controls.Add($searchGroup)
    $searchLabel = New-Object System.Windows.Forms.Label; $searchLabel.Text = 'Tìm commit'; $searchLabel.SetBounds(0, 8, 80, 24); $searchGroup.Controls.Add($searchLabel)
    $st.Search = New-Object System.Windows.Forms.TextBox; $st.Search.Width = 180
    $st.Search.SetBounds(84, 5, 180, 28); $st.Search.AccessibleName = 'Tìm commit theo nội dung, tác giả, ref hoặc mã; Enter để tìm'
    $searchGroup.Controls.Add($st.Search)
    $tipDoc.SetToolTip($st.Search, 'Tìm nội dung, tác giả, nhánh, tag hoặc mã commit. Enter: kết quả tiếp theo.')
    $st.Search.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; Find-GitCommit (Get-GitBrowserState $s) $s.Text } })
    $st.LblBranch.AutoSize = $false; $st.LblBranch.Width = 240; $st.LblBranch.Height = 24; $st.LblBranch.AutoEllipsis = $true
    $bar.WrapContents = $true; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'
}

function Set-CommitDialogLayout($cs, [switch]$Initial) {
    if (-not $cs.Main -or $cs.Form.IsDisposed) { return }
    if ($Initial) {
        $cs.Main.Panel1MinSize = 240; $cs.Main.Panel2MinSize = 360
        $cs.Main.SplitterDistance = [int]($cs.Main.Width * 0.38)
        $cs.Left.SplitterDistance = [int]($cs.Left.Height * 0.5)
        $cs.Right.SplitterDistance = [math]::Max(100, $cs.Right.Height - 280)
    }
    $cs.StageBar.MaximumSize = New-Object System.Drawing.Size($cs.Left.Panel2.ClientSize.Width, 0)
    $cs.CommitBar.MaximumSize = New-Object System.Drawing.Size($cs.Right.Panel2.ClientSize.Width, 0)
    foreach ($lv in @($cs.LvW, $cs.LvS)) { $lv.Columns[1].Width = [math]::Max(100, $lv.ClientSize.Width - 32) }
}

function Set-GitBrowserLayout($st, [switch]$Initial) {
    if (-not $st.Split -or $st.Form.IsDisposed) { return }
    if ($Initial) {
        $st.Split.SplitterDistance = [math]::Min(230, [int]($st.Split.Width * 0.24))
        $st.Right.SplitterDistance = [int]($st.Right.Height * 0.52)
        $st.Bottom.SplitterDistance = [int]($st.Bottom.Width * 0.28)
        $st.FileSplit.SplitterDistance = [int]($st.FileSplit.Width * 0.28)
    }
    $st.Bar.MaximumSize = New-Object System.Drawing.Size($st.Form.ClientSize.Width, 0)
    $st.LvC.Columns[1].Width = [math]::Max(120, $st.LvC.ClientSize.Width - $st.LvC.Columns[0].Width - 150 - 130 - 80 - 6)
    $st.LvF.Columns[1].Width = [math]::Max(100, $st.LvF.ClientSize.Width - 30)
}

function Fill-GitBranchTree($st, $data) {
    $tree = $st.Tree; $tree.BeginUpdate(); $tree.Nodes.Clear()
    foreach ($group in @(@('local', 'Branches'), @('remote', 'Remotes'), @('tag', 'Tags'))) {
        $node = $tree.Nodes.Add($group[1]); $parents = @{}
        if ($group[0] -eq 'remote') { foreach ($name in $data.Remotes) { $parents[$name] = $node.Nodes.Add($name) } }
        foreach ($branch in @($data.Branches | Where-Object Kind -eq $group[0])) {
            $parent = $node; $parts = $branch.Name -split '/'
            for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                $key = $parts[0..$i] -join '/'
                if (-not $parents.ContainsKey($key)) { $parents[$key] = $parent.Nodes.Add($parts[$i]) }
                $parent = $parents[$key]
            }
            $child = $parent.Nodes.Add($(if ($branch.Current) { '● ' } else { '' }) + $parts[-1]); $child.Tag = $branch
            $child.ToolTipText = "$($branch.Name) $($branch.Upstream) $($branch.Track)"
            if ($branch.Current) { $child.ForeColor = $Theme.Info }
        }
        if ($group[0] -ne 'tag') { $node.ExpandAll() }
    }
    $modules = $tree.Nodes.Add('Submodules'); foreach ($path in $data.Submodules) { [void]$modules.Nodes.Add($path) }
    $modules.Expand(); $tree.EndUpdate()
}

function GitB-NavigateRef($st, $node) {
    if (-not $node.Tag -or -not $node.Tag.Kind) { return }
    $st.SyncingRefs = $true
    try { $st.ChkAll.Checked = $false } finally { $st.SyncingRefs = $false }
    $st.Revision = $node.Tag.Name; $st.Hash = $null; GitB-LoadCommits $st
}

function Get-GitDisplayRows($st) {
    foreach ($kind in 'working', 'index') {
        $changes = @($st.Changes | Where-Object { $_.Staged -eq ($kind -eq 'index') })
        [pscustomobject]@{ Kind = $kind; Hash = $kind; Short = ''; Author = ''; Date = ''; Refs = ''; Subject = $(if ($kind -eq 'working') { 'Working directory' } else { 'Commit index' }) + " · $($changes.Count) file"; Merge = $false; Col = 0; Color = 0; Lanes = 1; Segs = @() }
    }
    $st.Rows
}

function Show-GitPendingRevision($st, $row) {
    $st.Hash = $row.Kind; $st.ShownHash = $row.Kind; $st.Snapshot = $row.Kind; $st.DiffKey = ''
    $st.Diff.Clear(); $st.LvF.Items.Clear()
    $files = @($st.Changes | Where-Object { $_.Staged -eq ($row.Kind -eq 'index') })
    $st.Info.Text = "$($row.Subject)`r`nRepository: $($st.Root)`r`nNhánh đang làm việc: $($st.Branch)`r`n`r`n" + $(if ($row.Kind -eq 'index') { 'Các thay đổi đã stage, sẽ được đưa vào commit kế tiếp.' } else { 'Các thay đổi chưa stage. Mở Commit để chọn file và stage trước khi commit.' })
    foreach ($file in $files) {
        $item = New-Object System.Windows.Forms.ListViewItem($file.Code); [void]$item.SubItems.Add($file.Path); $item.Tag = $file
        $item.UseItemStyleForSubItems = $false; $item.SubItems[0].ForeColor = Get-CodeColor $file.Code; [void]$st.LvF.Items.Add($item)
    }
    if ($st.LvF.Items.Count) { $st.LvF.Items[0].Selected = $true; GitB-ShowFileDiff $st $st.LvF.Items[0].Tag }
    else { $st.Diff.Text = 'Không có thay đổi trong vùng này.' }
    GitB-LoadFileTree $st
}

function Find-GitCommit($st, [string]$query) {
    if (-not $query.Trim()) { return }
    $start = if ($st.LvC.SelectedIndices.Count) { $st.LvC.SelectedIndices[0] + 1 } else { 0 }
    for ($i = 0; $i -lt $st.LvC.Items.Count; $i++) {
        $item = $st.LvC.Items[($start + $i) % $st.LvC.Items.Count]; $c = $item.Tag
        if (($c.Subject, $c.Author, $c.Hash, $c.Refs -join ' ').IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $st.LvC.SelectedItems.Clear(); $item.Selected = $true; $item.Focused = $true; $item.EnsureVisible(); GitB-ShowCommit $st $c; return
        }
    }
    GitB-SetStatus $st "Không tìm thấy '$query' trong lịch sử đã tải."
}

function GitB-LoadFileTree($st) {
    $st.TreeRequest = [guid]::NewGuid().ToString(); $st.FileTree.Nodes.Clear(); $st.FileContent.Clear()
    $st.ContentRequest = [guid]::NewGuid().ToString()
    Start-CoreAsync '@(Get-RepoFileTree $p.Root $p.Revision)' @{ Root = $st.Root; Revision = $st.Snapshot } {
        param($r, $ctx) $st = $ctx.St
        if ($st.Form.IsDisposed -or $st.TreeRequest -ne $ctx.Request) { return }
        if (-not $r.Ok) { $st.FileContent.Text = "Lỗi: $($r.Value)"; return }
        $nodes = @{}; $st.FileTree.BeginUpdate()
        foreach ($path in @($r.Value)) {
            $parent = $st.FileTree.Nodes; $parts = $path -split '/'
            for ($i = 0; $i -lt $parts.Count; $i++) {
                $key = $parts[0..$i] -join '/'
                if (-not $nodes.ContainsKey($key)) { $nodes[$key] = $parent.Add($parts[$i]) }
                $node = $nodes[$key]; $parent = $node.Nodes
            }
            $node.Tag = [string]$path; $node.ToolTipText = $path
        }
        $st.FileTree.EndUpdate()
    } @{ St = $st; Request = $st.TreeRequest }
}

function GitB-LoadFileContent($st, [string]$path) {
    $st.ContentRequest = [guid]::NewGuid().ToString(); $st.FileContent.Text = "Đang đọc $path..."
    Start-CoreAsync 'Get-RepoFileContent $p.Root $p.Revision $p.Path' @{ Root = $st.Root; Revision = $st.Snapshot; Path = $path } {
        param($r, $ctx) $st = $ctx.St
        if ($st.Form.IsDisposed -or $st.ContentRequest -ne $ctx.Request) { return }
        $st.FileContent.Text = if ($r.Ok) { [string]$r.Value } else { "Lỗi: $($r.Value)" }
    } @{ St = $st; Request = $st.ContentRequest }
}
