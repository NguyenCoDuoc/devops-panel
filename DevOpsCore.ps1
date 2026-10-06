# DevOps Panel - logic dùng chung cho DevOpsPanel.ps1 (desktop) và WebPanel.ps1 (web qua Tailscale, chỉ có khi cài từ mã nguồn)
$env:WSL_UTF8 = '1'

# ---------- Cấu hình theo người dùng ----------
# Nằm ở %APPDATA% (không phải thư mục cài) để cài lại / nâng cấp bản mới không mất cấu hình, danh mục app, log.
$DataDir    = Join-Path $env:APPDATA 'DevOpsPanel'
$ConfigFile = Join-Path $DataDir 'config.json'
New-Item -ItemType Directory -Force $DataDir | Out-Null

function Get-PanelConfig {
    $cfg = [ordered]@{
        appName         = 'DevOps Panel'
        distro          = ''          # rỗng = tự chọn distro Ubuntu đầu tiên
        pgUbuntuPort    = 0           # 0 = không có PostgreSQL trong WSL
        autoStartUbuntu = $false
        scanRoots       = @()         # thư mục gốc để quét project cho tab Ứng dụng
    }
    if (Test-Path $ConfigFile) {
        $j = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($cfg.Keys)) { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } }
    } else {
        # Máy đã dùng bản cũ (cài từ mã nguồn): mang settings.json sang
        $legacy = Join-Path $PSScriptRoot 'settings.json'
        if (Test-Path $legacy) {
            $j = Get-Content $legacy -Raw | ConvertFrom-Json
            $cfg.appName = 'DUOCNC DevOps Panel'
            if ($null -ne $j.autoStartUbuntu) { $cfg.autoStartUbuntu = [bool]$j.autoStartUbuntu }
            $cfg.distro = 'Ubuntu'
            $cfg.pgUbuntuPort = 5434
        }
        Save-PanelConfig ([pscustomobject]$cfg)
    }
    $cfg.scanRoots = @($cfg.scanRoots | Where-Object { $_ })
    [pscustomobject]$cfg
}
function Save-PanelConfig($cfg) {
    $cfg | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8
}

function Get-WslDistros {
    @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim([char]0, ' ') } |
        Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
}

function Find-FirstPath([string[]]$candidates) {
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

$PanelConfig  = Get-PanelConfig
$AppName      = [string]$PanelConfig.appName
$WslDistros   = Get-WslDistros
$Distro       = if ($PanelConfig.distro -and $WslDistros -contains $PanelConfig.distro) { $PanelConfig.distro }
                elseif ($WslDistros -contains 'Ubuntu') { 'Ubuntu' }
                else { $WslDistros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1 }
$PgUbuntuPort = [int]$PanelConfig.pgUbuntuPort
$DockerExe    = Find-FirstPath @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe")
$TailscaleExe = Find-FirstPath @("$env:ProgramFiles\Tailscale\tailscale.exe")

# ---------- Helpers ----------
function Test-Port([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(250)) { $c.EndConnect($ar); return $true }
        return $false
    } catch { return $false } finally { $c.Close() }
}

function Get-KeepAlive {
    Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" |
        Where-Object { $_.CommandLine -like "*-d $Distro*sleep infinity*" }
}

function Test-UbuntuRunning {
    $running = wsl.exe --list --running --quiet 2>$null | ForEach-Object { $_.Trim([char]0, ' ') }
    return ($running -contains $Distro)
}

function Invoke-Wsl([string]$cmd) {
    wsl.exe -d $Distro -u root -e bash -c $cmd 2>&1
}

function Start-Ubuntu {
    if (-not (Get-KeepAlive)) {
        # Giữ một tiến trình chạy ngầm để WSL không tự tắt khi rảnh
        Start-Process wsl.exe -ArgumentList "-d $Distro -u root -e sleep infinity" -WindowStyle Hidden
    }
    for ($i = 0; $i -lt 20 -and -not (Test-UbuntuRunning); $i++) { Start-Sleep -Milliseconds 500 }
}

function Stop-Ubuntu {
    Get-KeepAlive | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    wsl.exe --terminate $Distro | Out-Null
}

function Invoke-Elevated([string]$command) {
    try {
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait `
            -ArgumentList "-NoProfile -Command $command" -ErrorAction Stop
        return $true
    } catch {
        if (Get-Command Set-Status -ErrorAction SilentlyContinue) { Set-Status 'Đã huỷ (cần quyền Administrator).' }
        return $false
    }
}

function Get-PgPassword {
    if (-not (Test-UbuntuRunning)) { Start-Ubuntu }
    $line = Invoke-Wsl "cat /root/.pgpass" | Select-Object -First 1
    if ($line -and ($line -split ':').Count -ge 5) { return ($line -split ':', 5)[4] }
    return $null
}

function Get-TailscaleInfo {
    if (-not $TailscaleExe) { return $null }
    $j = & $TailscaleExe status --json 2>$null | Out-String | ConvertFrom-Json
    if (-not $j) { return $null }
    [pscustomobject]@{
        Running = ($j.BackendState -eq 'Running')
        IP      = ($j.Self.TailscaleIPs | Where-Object { $_ -like '100.*' } | Select-Object -First 1)
        DNSName = ([string]$j.Self.DNSName).TrimEnd('.')
    }
}

function Get-DiskInfo {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        [pscustomobject]@{
            Drive  = $_.DeviceID
            FreeGB = [math]::Round($_.FreeSpace / 1GB, 1)
            SizeGB = [math]::Round($_.Size / 1GB, 1)
            UsedPct = if ($_.Size) { [math]::Round(100 - $_.FreeSpace * 100 / $_.Size) } else { 0 }
        }
    }
}

# ---------- Components ----------
# Tự dò theo máy: distro WSL, các service PostgreSQL trên Windows (port đọc từ postgresql.conf), Docker, Tailscale.
# Remote = có cho điều khiển từ web không (dịch vụ Windows cần UAC nên chỉ xem trạng thái)
function Get-PgWindowsServices {
    Get-CimInstance Win32_Service -Filter "Name LIKE 'postgresql%'" | Sort-Object Name | ForEach-Object {
        $ver = if ($_.Name -match '(\d+)$') { $Matches[1] } else { '' }     # postgresql-x64-15 -> 15 (không lấy 64)
        $port = 5432
        if ($_.PathName -match '-D\s+"([^"]+)"') {
            $conf = Join-Path $Matches[1] 'postgresql.conf'
            $m = Select-String -Path $conf -Pattern '^\s*port\s*=\s*(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m) { $port = [int]$m.Matches[0].Groups[1].Value }
        }
        [pscustomobject]@{ Id = "pg$ver"; Name = "PostgreSQL $ver (Windows)"; Port = $port; Kind = 'pg-win'; Remote = $false; Service = $_.Name }
    }
}

$Components = @(
    if ($Distro) {
        [pscustomobject]@{ Id = 'ubuntu'; Name = "$Distro (WSL)"; Port = ''; Kind = 'ubuntu'; Remote = $true }
        if ($PgUbuntuPort -gt 0) {
            [pscustomobject]@{ Id = 'pgubuntu'; Name = "PostgreSQL ($Distro)"; Port = $PgUbuntuPort; Kind = 'pg-ubuntu'; Remote = $true }
        }
        [pscustomobject]@{ Id = 'k3s'; Name = "K3s ($Distro)"; Port = 6443; Kind = 'k3s'; Remote = $true }
    }
    Get-PgWindowsServices
    if ($DockerExe)    { [pscustomobject]@{ Id = 'docker';    Name = 'Docker Desktop'; Port = ''; Kind = 'docker';    Remote = $true } }
    if ($TailscaleExe) { [pscustomobject]@{ Id = 'tailscale'; Name = 'Tailscale';      Port = ''; Kind = 'tailscale'; Remote = $false } }
)

function Get-ComponentState($c) {
    switch ($c.Kind) {
        'ubuntu'    { return (Test-UbuntuRunning) }
        'pg-ubuntu' { return (Test-Port $c.Port) }
        'pg-win'    { return ((Get-Service $c.Service).Status -eq 'Running') }
        'k3s'       { return (Test-Port $c.Port) }
        'docker'    { return [bool](Get-Process 'Docker Desktop') }
        'tailscale' { $t = Get-TailscaleInfo; return [bool]($t -and $t.Running) }
    }
}

function Start-Component($c) {
    switch ($c.Kind) {
        'ubuntu'    { Start-Ubuntu }
        'pg-ubuntu' { Start-Ubuntu; Invoke-Wsl 'systemctl start postgresql' | Out-Null }
        'pg-win'    { Invoke-Elevated "Start-Service '$($c.Service)'" | Out-Null }
        'k3s'       { Start-Ubuntu; Invoke-Wsl 'systemctl start k3s' | Out-Null }
        'docker'    { if ($DockerExe) { Start-Process $DockerExe } }
        'tailscale' { & $TailscaleExe up | Out-Null }
    }
}

function Stop-Component($c) {
    switch ($c.Kind) {
        'ubuntu'    { Stop-Ubuntu }
        'pg-ubuntu' { if (Test-UbuntuRunning) { Invoke-Wsl 'systemctl stop postgresql' | Out-Null } }
        'pg-win'    { Invoke-Elevated "Stop-Service '$($c.Service)'" | Out-Null }
        'k3s'       { if (Test-UbuntuRunning) { Invoke-Wsl 'systemctl stop k3s' | Out-Null } }
        'docker'    { Stop-Process -Name 'Docker Desktop', 'com.docker.backend' -Force; wsl.exe --terminate docker-desktop | Out-Null }
        'tailscale' { & $TailscaleExe down | Out-Null }
    }
}

# ---------- K3s ----------
$KubeEnv = 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml;'
# Tên namespace/pod theo chuẩn Kubernetes (RFC 1123) - bắt buộc kiểm tra trước khi ghép vào lệnh bash
function Test-K8sName([string]$s) { return ($s -cmatch '^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$') }

function Test-K3sActive {
    if (-not (Test-UbuntuRunning)) { return $false }   # không gọi wsl khi Ubuntu tắt (tránh tự bật Ubuntu)
    return ((Invoke-Wsl 'systemctl is-active k3s' | Select-Object -First 1) -eq 'active')
}

function Format-Age([datetime]$t) {
    $d = (Get-Date) - $t
    if ($d.TotalDays -ge 1) { return '{0}d' -f [int][math]::Floor($d.TotalDays) }
    if ($d.TotalHours -ge 1) { return '{0}h' -f [int][math]::Floor($d.TotalHours) }
    return '{0}m' -f [int][math]::Max(0, [math]::Floor($d.TotalMinutes))
}

function Get-K3sInfo {
    if (-not (Test-UbuntuRunning)) { return [pscustomobject]@{ Running = $false; Reason = 'Ubuntu chưa chạy' } }

    # Gộp 1 lần gọi wsl (mỗi lần gọi ~0.7s): trạng thái service, pods, nodes - ngăn cách bằng dòng ###
    $cols = 'NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,WAIT:.status.containerStatuses[*].state.waiting.reason,' +
            'READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,' +
            'OWNER:.metadata.ownerReferences[0].kind,START:.status.startTime,DEL:.metadata.deletionTimestamp'
    $out = @(Invoke-Wsl ("$KubeEnv systemctl is-active k3s; echo '###';" +
        " k3s kubectl get pods -A --no-headers -o custom-columns='$cols' 2>/dev/null; echo '###';" +
        " k3s kubectl get nodes --no-headers 2>/dev/null"))
    if (([string]$out[0]).Trim() -ne 'active') { return [pscustomobject]@{ Running = $false; Reason = 'k3s đã dừng' } }
    $sep = @(for ($i = 0; $i -lt $out.Count; $i++) { if (([string]$out[$i]).Trim() -eq '###') { $i } })
    $lines     = if ($sep.Count -ge 2) { $out[($sep[0] + 1)..($sep[1] - 1)] } else { @() }
    $nodeLines = if ($sep.Count -ge 2 -and $sep[1] -lt $out.Count - 1) { $out[($sep[1] + 1)..($out.Count - 1)] } else { @() }
    if ($sep.Count -ge 2 -and $sep[1] - $sep[0] -le 1) { $lines = @() }

    $pods = foreach ($l in $lines) {
        $f = ([string]$l).Trim() -split '\s+'
        if ($f.Count -lt 9) { continue }
        $ready = @($f[4] -split ',' | Where-Object { $_ -ne '<none>' })
        $readyN = @($ready | Where-Object { $_ -eq 'true' }).Count
        $restarts = (@($f[5] -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }) | Measure-Object -Sum).Sum
        $status = if ($f[8] -ne '<none>') { 'Terminating' }
                  elseif ($f[3] -ne '<none>') { ($f[3] -split ',')[0] }
                  elseif ($f[2] -eq 'Succeeded') { 'Completed' }
                  elseif ($f[2] -eq 'Running' -and $readyN -lt $ready.Count) { 'NotReady' }
                  else { $f[2] }
        [pscustomobject]@{
            Namespace = $f[0]
            Name      = $f[1]
            Status    = $status
            Healthy   = ($status -in 'Running', 'Completed')
            Ready     = "$readyN/$($ready.Count)"
            Restarts  = [int]$restarts
            Owner     = if ($f[6] -ne '<none>') { $f[6] } else { '' }
            Age       = if ($f[7] -ne '<none>') { Format-Age ([datetime]$f[7]) } else { '' }
        }
    }
    $pods = @($pods | Sort-Object @{ e = { $_.Healthy } }, Namespace, Name)   # pod lỗi lên đầu

    $nodes = @($nodeLines | ForEach-Object {
        $f = ([string]$_).Trim() -split '\s+'
        if ($f.Count -ge 5) { [pscustomobject]@{ Name = $f[0]; Status = $f[1]; Version = $f[4] } }
    })

    [pscustomobject]@{
        Running   = $true
        Nodes     = $nodes
        Pods      = $pods
        Total     = $pods.Count
        Healthy   = @($pods | Where-Object Healthy).Count
        Unhealthy = @($pods | Where-Object { -not $_.Healthy }).Count
        Namespaces = @($pods.Namespace | Sort-Object -Unique).Count
    }
}

function Restart-K3sPod([string]$ns, [string]$pod) {
    if (-not ((Test-K8sName $ns) -and (Test-K8sName $pod))) { throw 'Tên namespace/pod không hợp lệ' }
    Invoke-Wsl "$KubeEnv k3s kubectl delete pod -n $ns $pod --wait=false 2>&1" | Out-String
}

function Get-K3sLogs([string]$ns, [string]$pod, [int]$tail = 200, [switch]$Previous) {
    if (-not ((Test-K8sName $ns) -and (Test-K8sName $pod))) { throw 'Tên namespace/pod không hợp lệ' }
    $tail = [math]::Min([math]::Max($tail, 10), 2000)
    $prev = if ($Previous) { '--previous' } else { '' }
    (Invoke-Wsl "$KubeEnv k3s kubectl logs -n $ns $pod --all-containers --tail=$tail $prev 2>&1") -join "`n"
}

# ---------- Ứng dụng dev (backend 70xx, frontend 50xx...) ----------
$AppsFile    = Join-Path $DataDir 'apps.json'
$AppsLogDir  = Join-Path $DataDir 'logs'
$SystemProcs = @('System', 'Idle', 'svchost', 'lsass', 'services', 'wininit', 'spoolsv', 'smss', 'csrss', 'winlogon')
$DefaultScanRanges = @(@(5000, 5099), @(7000, 7199))

$legacyLogs = Join-Path $PSScriptRoot 'logs'                  # log + pid của bản cài từ mã nguồn
if (-not (Test-Path $AppsLogDir) -and (Test-Path $legacyLogs)) { Copy-Item $legacyLogs $AppsLogDir -Recurse }

if (-not (Test-Path $AppsFile)) {
    $legacyApps = Join-Path $PSScriptRoot 'apps.json'        # bản cài từ mã nguồn để apps.json cạnh script
    if (Test-Path $legacyApps) { Copy-Item $legacyApps $AppsFile }
    else { [pscustomobject]@{ scanRanges = $DefaultScanRanges; apps = @() } | ConvertTo-Json -Depth 5 | Set-Content $AppsFile -Encoding UTF8 }
}

function Get-AppsConfig {
    $cfg = Get-Content $AppsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $ranges = if ($cfg.scanRanges) { @($cfg.scanRanges) } else { $DefaultScanRanges }
    [pscustomobject]@{ Ranges = $ranges; Apps = @($cfg.apps | Where-Object { $_ }) }
}

function Save-AppsConfig($ranges, $apps) {
    [pscustomobject]@{ scanRanges = @($ranges); apps = @($apps) } | ConvertTo-Json -Depth 5 | Set-Content $AppsFile -Encoding UTF8
}

# ---------- Quét thư mục tìm project (.NET Web/Worker/console + frontend Vite) ----------
$ScanSkipDirs = @('node_modules', 'bin', 'obj', 'dist', 'build', 'coverage', 'packages', 'wwwroot', '@mf-types', 'TestResults')

function Get-ProjectFiles([string]$root, [int]$maxDepth = 6) {
    # Tự duyệt (không dùng Get-ChildItem -Recurse): bỏ qua node_modules/bin/obj ngay từ đầu nên nhanh hơn rất nhiều
    $stack = New-Object System.Collections.Stack
    $stack.Push([pscustomobject]@{ Dir = $root; Depth = 0 })
    while ($stack.Count) {
        $item = $stack.Pop()
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($item.Dir)) {
                $n = [IO.Path]::GetFileName($f)
                if ($n -like '*.csproj' -or $n -eq 'package.json') { $f }
            }
        } catch { }
        if ($item.Depth -ge $maxDepth) { continue }
        try {
            foreach ($sub in [IO.Directory]::EnumerateDirectories($item.Dir)) {
                $sn = [IO.Path]::GetFileName($sub)
                if ($sn.StartsWith('.') -or $ScanSkipDirs -contains $sn) { continue }
                $stack.Push([pscustomobject]@{ Dir = $sub; Depth = $item.Depth + 1 })
            }
        } catch { }
    }
}

function Get-GroupName([string]$root, [string]$dir) {
    $rel = $dir.Substring($root.TrimEnd('\').Length).TrimStart('\')
    $seg = ($rel -split '\\')[0]
    if (-not $seg -or $seg -eq $rel) { $seg = Split-Path $root -Leaf }     # project nằm ngay dưới thư mục gốc
    ($seg -replace '^sh\.', '' -replace '\.projects?$', '').ToUpper()
}

function Get-DotnetProject([string]$csproj) {
    $x = [IO.File]::ReadAllText($csproj)
    if ($x -match 'Microsoft\.NET\.Test\.Sdk|xunit|NUnit|MSTest') { return $null }
    $isWeb = $x -match 'Sdk="Microsoft\.NET\.Sdk\.(Web|Worker)"'
    $isExe = $x -match '<OutputType>\s*Exe\s*</OutputType>'
    if (-not ($isWeb -or $isExe)) { return $null }

    $dir = Split-Path $csproj -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($csproj)
    $port = 0; $profile = $null; $baseUrl = ''
    $ls = Join-Path $dir 'Properties\launchSettings.json'
    if ($isWeb -and (Test-Path $ls)) {
        try {
            $j = Get-Content $ls -Raw | ConvertFrom-Json
            $profiles = @($j.profiles.PSObject.Properties | Where-Object { $_.Value.commandName -eq 'Project' -and $_.Value.applicationUrl })
            $pick = ($profiles | Where-Object Name -eq 'https' | Select-Object -First 1)
            if (-not $pick) { $pick = $profiles | Select-Object -First 1 }
            if ($pick) {
                $profile = $pick.Name
                $urls = @($pick.Value.applicationUrl -split ';' | Where-Object { $_ })
                $baseUrl = ($urls | Where-Object { $_ -like 'https*' } | Select-Object -First 1)
                if (-not $baseUrl) { $baseUrl = $urls[0] }
                if ($baseUrl -match ':(\d+)') { $port = [int]$Matches[1] }
            }
        } catch { }
    }
    if ($isWeb -and $port) {
        [pscustomobject]@{
            name = $name; type = $(if ($name -match 'bff') { 'bff' } else { 'backend' }); port = $port
            url = "$($baseUrl.TrimEnd('/'))/swagger"; dir = $dir; start = "dotnet run --launch-profile $profile"
        }
    } elseif (-not $isWeb) {
        [pscustomobject]@{ name = $name; type = 'tool'; port = 0; url = ''; dir = $dir; start = 'dotnet run' }
    }
}

function Get-ViteProject([string]$packageJson) {
    $dir = Split-Path $packageJson -Parent
    $vc = Get-ChildItem $dir -Filter 'vite.config.*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vc) { return $null }
    try { $pkg = Get-Content $packageJson -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $pkg.scripts.dev) { return $null }
    $text = [IO.File]::ReadAllText($vc.FullName)
    $port = if ($text -match 'port:\s*(\d+)') { [int]$Matches[1] } else { 5173 }
    $scheme = if ($text -match 'mkcert|https:\s*(true|\{)') { 'https' } else { 'http' }
    [pscustomobject]@{
        name = (Split-Path $dir -Leaf); type = 'frontend'; port = $port
        url = "${scheme}://localhost:$port"; dir = $dir; start = 'npm run dev'
    }
}

function New-AppId([string]$name, $taken) {
    $base = ($name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $base) { $base = 'app' }
    $id = $base; $n = 2
    while ($taken.Contains($id)) { $id = "$base-$n"; $n++ }
    [void]$taken.Add($id)
    $id
}

<#
  Quét các thư mục gốc -> cập nhật apps.json. Giữ nguyên:
    - app thêm tay (manual = true) hoặc nằm ngoài các thư mục gốc,
    - id cũ của project đã có (log / pid / Git không bị đứt), các chỉnh tay start/url/group.
  Trả về số app tìm được.
#>
function Update-AppsCatalog([string[]]$roots) {
    $roots = @($roots | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object { (Resolve-Path $_).Path.TrimEnd('\') })
    $cfg = Get-AppsConfig
    $existing = @{}; foreach ($a in $cfg.Apps) { if ($a.dir) { $existing[$a.dir.TrimEnd('\').ToLower()] = $a } }
    $inRoots = { param($d) foreach ($r in $roots) { if ($d.ToLower().StartsWith($r.ToLower() + '\')) { return $true } }; $false }

    $keep = @($cfg.Apps | Where-Object { $_.manual -or -not $_.dir -or -not (& $inRoots $_.dir) })
    $taken = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($a in $keep) { [void]$taken.Add($a.id) }

    $found = foreach ($root in $roots) {
        foreach ($f in Get-ProjectFiles $root) {
            $p = if ($f -like '*.csproj') { Get-DotnetProject $f } else { Get-ViteProject $f }
            if ($p) { $p | Add-Member group (Get-GroupName $root $p.dir) -PassThru }
        }
    }
    $scanned = foreach ($p in ($found | Sort-Object group, type, name)) {
        $old = $existing[$p.dir.TrimEnd('\').ToLower()]
        if ($old -and -not $taken.Contains($old.id)) {
            [void]$taken.Add($old.id)
            $old.port = $p.port; $old.type = $p.type     # cập nhật theo code hiện tại, giữ chỉnh tay khác
            $old
        } else {
            [pscustomobject]@{
                id = (New-AppId $p.name $taken); group = $p.group; name = $p.name; type = $p.type; port = $p.port
                url = $p.url; dir = $p.dir; start = $p.start
            }
        }
    }
    Save-AppsConfig $cfg.Ranges (@($keep) + @($scanned))
    @($scanned).Count
}

function Test-InRanges([int]$port, $ranges) {
    foreach ($r in $ranges) { if ($port -ge $r[0] -and $port -le $r[1]) { return $true } }
    return $false
}

# netstat nhanh hơn Get-NetTCPConnection rất nhiều trên PowerShell 5.1 (~0.1s so với 2-4s)
function Get-ListeningPorts {
    foreach ($l in (netstat.exe -ano -p TCP) + (netstat.exe -ano -p TCPv6)) {
        if ($l -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+LISTENING\s+(\d+)') {
            [pscustomobject]@{ LocalPort = [int]$Matches[2]; OwningProcess = [int]$Matches[3] }
        }
    }
}

function Get-DevApps {
    $cfg = Get-AppsConfig
    $catPorts = @($cfg.Apps | Where-Object { $_.port } | ForEach-Object { [int]$_.port })
    $conns = @(Get-ListeningPorts | Where-Object { (Test-InRanges $_.LocalPort $cfg.Ranges) -or ($catPorts -contains $_.LocalPort) })

    $pids = @($conns.OwningProcess | Sort-Object -Unique)
    $procs = @{}
    if ($pids.Count) {
        Get-CimInstance Win32_Process -Filter (($pids | ForEach-Object { "ProcessId=$_" }) -join ' OR ') -Property ProcessId, Name, ExecutablePath, CommandLine |
            ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
    }
    # port -> tiến trình đang giữ (1 port có thể nghe cả IPv4 và IPv6, cùng PID)
    $byPort = @{}
    foreach ($c in $conns) { if (-not $byPort.ContainsKey([int]$c.LocalPort)) { $byPort[[int]$c.LocalPort] = $procs[[int]$c.OwningProcess] } }

    # App không có port (tool/migrator): nhận diện qua tiến trình chạy exe nằm trong thư mục project
    $toolApps = @($cfg.Apps | Where-Object { -not $_.port })
    $toolProcs = @()
    if ($toolApps.Count) {
        $toolProcs = @(Get-CimInstance Win32_Process -Filter "Name<>'cmd.exe'" -Property ProcessId, Name, ExecutablePath | Where-Object { $_.ExecutablePath })
    }

    $claimed = @{}
    $rows = foreach ($a in $cfg.Apps) {
        if (-not $a.port) {
            $tp = $toolProcs | Where-Object { $_.ExecutablePath -like "$($a.dir)\*" } | Select-Object -First 1
            [pscustomobject]@{
                Id = $a.id; Group = $a.group; Name = $a.name; Type = $a.type; Port = 0; Url = $a.url; Dir = $a.dir
                Known = $true; Running = [bool]$tp; Busy = $false
                Pid = if ($tp) { [int]$tp.ProcessId } else { 0 }
                Process = if ($tp) { $tp.Name -replace '\.exe$', '' } else { '' }
            }
            continue
        }
        $p = $byPort[[int]$a.port]
        $mine = $false
        if ($p) {
            $sameport = @($cfg.Apps | Where-Object { $_.port -eq $a.port })
            $where = "$($p.ExecutablePath) $($p.CommandLine)"
            # Nhiều app chung port -> chỉ nhận khi đường dẫn tiến trình nằm trong thư mục project
            $mine = if ($sameport.Count -gt 1) { $where -like "*$($a.dir)*" } else { $true }
        }
        if ($mine) { $claimed[[int]$a.port] = $true }
        [pscustomobject]@{
            Id = $a.id; Group = $a.group; Name = $a.name; Type = $a.type; Port = [int]$a.port; Url = $a.url; Dir = $a.dir
            Known = $true; Running = [bool]$mine
            Busy = [bool]($p -and -not $mine)          # port bị app khác chiếm
            Pid = if ($mine) { [int]$p.ProcessId } else { 0 }
            Process = if ($p) { $p.Name -replace '\.exe$', '' } else { '' }
        }
    }
    # Port đang nghe nhưng không có trong danh mục (bỏ qua tiến trình hệ thống)
    $extra = foreach ($port in ($byPort.Keys | Sort-Object)) {
        if ($claimed[$port]) { continue }
        $p = $byPort[$port]
        if (-not $p) { continue }
        $pn = $p.Name -replace '\.exe$', ''
        if ($SystemProcs -contains $pn -or ([string]$p.ExecutablePath) -like "$env:WINDIR\*") { continue }
        if (@($cfg.Apps | Where-Object { $_.port -eq $port }).Count -and -not (Test-InRanges $port $cfg.Ranges)) { continue }
        [pscustomobject]@{
            Id = "port-$port"; Group = 'Khác (đang chạy)'; Name = $pn
            Type = if ($pn -match '^(node|bun|deno)$') { 'frontend' } else { 'backend' }
            Port = $port; Url = "http://localhost:$port"; Known = $false; Running = $true; Busy = $false; Dir = ''
            Pid = [int]$p.ProcessId; Process = $pn; Path = [string]$p.ExecutablePath
        }
    }
    @($rows) + @($extra)
}

function Stop-ProcessTree([int]$procId) {
    if ($procId -gt 4) { taskkill.exe /PID $procId /T /F 2>&1 | Out-Null }
}

function Stop-DevApp([string]$id) {
    if ($id -notmatch '^[a-z0-9-]+$') { throw 'id không hợp lệ' }
    $a = Get-DevApps | Where-Object Id -eq $id | Select-Object -First 1
    if (-not $a) { throw "Không có app $id" }
    # 1) Tiến trình gốc (cmd /c ...) TRƯỚC: nếu giết tiến trình nghe port trước, cmd chạy tiếp lệnh sau
    #    (vd "(vite preview & npm run build:watch)" -> build:watch mọc ra sau khi taskkill đã liệt kê cây, bị sót,
    #    giữ file log + dist -> lần Start sau báo "being used by another process").
    #    Kiểm tra commandline để không giết nhầm PID đã bị tái sử dụng.
    $pidFile = Join-Path $AppsLogDir "$id.pid"
    if (Test-Path $pidFile) {
        $root = [int](Get-Content $pidFile | Select-Object -First 1)
        $rp = Get-CimInstance Win32_Process -Filter "ProcessId=$root"
        if ($rp -and $rp.CommandLine -like "*$id.log*") { Stop-ProcessTree $root }
        Remove-Item $pidFile -Force
    }
    # 2) Tiến trình đang nghe port (kể cả app chạy ngoài panel)
    if ($a.Running -and $a.Pid) { Stop-ProcessTree $a.Pid }
    # 3) Quét dọn tiến trình còn sót của project (node/cmd/dotnet chạy từ thư mục project, exe build trong thư mục)
    $cfgApp = (Get-AppsConfig).Apps | Where-Object id -eq $id | Select-Object -First 1
    if ($cfgApp -and $cfgApp.dir) {
        $dir = $cfgApp.dir.TrimEnd('\')
        for ($round = 0; $round -lt 2; $round++) {
            Start-Sleep -Milliseconds 600
            Get-CimInstance Win32_Process -Property ProcessId, Name, ExecutablePath, CommandLine | Where-Object {
                ($_.Name -in 'node.exe', 'cmd.exe', 'dotnet.exe' -and $_.CommandLine -like "*$dir\*") -or
                ($_.ExecutablePath -like "$dir\*")
            } | ForEach-Object { Stop-ProcessTree ([int]$_.ProcessId) }
        }
    }
    if ($a.Port) { "Đã dừng $($a.Name) (port $($a.Port))" } else { "Đã dừng $($a.Name)" }
}

function Start-DevApp([string]$id) {
    $a = (Get-AppsConfig).Apps | Where-Object id -eq $id | Select-Object -First 1
    if (-not $a) { throw "Không có app $id trong apps.json" }
    if (-not (Test-Path $a.dir)) { throw "Không thấy thư mục $($a.dir)" }
    $cur = Get-DevApps | Where-Object Id -eq $id
    if ($cur.Running) { return "$($a.name) đang chạy rồi" }
    if ($cur.Busy) { throw "Port $($a.port) đang bị $($cur.Process) chiếm" }
    $portText = if ($a.port) { "port $($a.port)" } else { 'tool' }
    New-Item -ItemType Directory -Force $AppsLogDir | Out-Null
    $log = Join-Path $AppsLogDir "$id.log"
    try { "==== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($a.start)  ($($a.dir))" | Set-Content $log -Encoding UTF8 -ErrorAction Stop }
    catch { throw "File log $id.log đang bị tiến trình khác giữ - bấm Stop để dọn tiến trình cũ rồi Start lại" }
    $p = Start-Process cmd.exe -ArgumentList "/c $($a.start) >> `"$log`" 2>&1" -WorkingDirectory $a.dir -WindowStyle Hidden -PassThru
    Set-Content (Join-Path $AppsLogDir "$id.pid") $p.Id
    "Đang khởi động $($a.name) ($portText)..."
}

function Get-DevAppLog([string]$id, [int]$tail = 200) {
    if ($id -notmatch '^[a-z0-9-]+$') { throw 'id không hợp lệ' }
    $log = Join-Path $AppsLogDir "$id.log"
    if (-not (Test-Path $log)) { return '(Chưa có log - app này chưa được khởi động từ panel)' }
    (Get-Content $log -Tail ([math]::Min([math]::Max($tail, 10), 2000)) -Encoding UTF8) -join "`n"
}

# ---------- Git của project ----------
# Gọi git qua Process để ép UTF-8 (commit tiếng Việt) và có timeout; không bao giờ hỏi mật khẩu (tránh treo khi chạy nền)
function Invoke-Git([string]$dir, [string[]]$gitArgs, [int]$timeoutMs = 60000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.Arguments = ($gitArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutMs)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = -1; Out = ''; Err = "git quá thời gian $([int]($timeoutMs / 1000))s" } }
    [pscustomobject]@{ Code = $p.ExitCode; Out = $outTask.Result.TrimEnd(); Err = $errTask.Result.TrimEnd() }
}

function Get-AppDir([string]$id) {
    if ($id -notmatch '^[a-z0-9-]+$') { throw 'id không hợp lệ' }
    $a = (Get-AppsConfig).Apps | Where-Object id -eq $id | Select-Object -First 1
    if (-not $a) { throw "Không có app $id trong apps.json" }
    if (-not (Test-Path $a.dir)) { throw "Không thấy thư mục $($a.dir)" }
    $a.dir
}

# Ẩn user/token nếu remote URL có dạng https://user:token@host/...
function Hide-UrlSecret([string]$url) { $url -replace '://[^/@\s]+@', '://***@' }

function Get-AppGitInfo([string]$id) {
    $dir = Get-AppDir $id
    $top = Invoke-Git $dir @('rev-parse', '--show-toplevel') 10000
    if ($top.Code -ne 0) { return [pscustomobject]@{ IsRepo = $false; Dir = $dir } }

    $branch   = (Invoke-Git $dir @('rev-parse', '--abbrev-ref', 'HEAD')).Out
    $upstream = Invoke-Git $dir @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    $ahead = 0; $behind = 0
    if ($upstream.Code -eq 0) {
        $c = (Invoke-Git $dir @('rev-list', '--left-right', '--count', 'HEAD...@{u}')).Out -split '\s+'
        if ($c.Count -ge 2) { $ahead = [int]$c[0]; $behind = [int]$c[1] }
    }
    $status = (Invoke-Git $dir @('status', '--porcelain')).Out
    $dirty = @($status -split "`n" | Where-Object { $_.Trim() }).Count
    $last = (Invoke-Git $dir @('log', '-1', '--format=%h%x1f%s%x1f%an%x1f%cr')).Out -split [char]0x1f
    $branches = @((Invoke-Git $dir @('branch', '--format=%(refname:short)')).Out -split "`n" | Where-Object { $_ })
    $fetchHead = Join-Path $top.Out '.git\FETCH_HEAD'

    [pscustomobject]@{
        IsRepo    = $true
        Dir       = $dir
        Root      = $top.Out -replace '/', '\'
        Remote    = Hide-UrlSecret (Invoke-Git $dir @('remote', 'get-url', 'origin')).Out
        Branch    = $branch
        Upstream  = if ($upstream.Code -eq 0) { $upstream.Out } else { '' }
        Ahead     = $ahead
        Behind    = $behind
        Dirty     = $dirty
        Changes   = @($status -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 15)
        LastHash  = $last[0]
        LastMsg   = if ($last.Count -gt 1) { $last[1] } else { '' }
        LastAuthor = if ($last.Count -gt 2) { $last[2] } else { '' }
        LastWhen  = if ($last.Count -gt 3) { $last[3] } else { '' }
        Branches  = $branches
        LastFetch = if (Test-Path $fetchHead) { (Get-Item $fetchHead).LastWriteTime.ToString('HH:mm dd/MM') } else { '' }
    }
}

function Invoke-AppGit([string]$id, [string]$action, [string]$branch = '') {
    $dir = Get-AppDir $id
    switch ($action) {
        'fetch' { $r = Invoke-Git $dir @('fetch', '--prune') 120000 }
        'pull'  { $r = Invoke-Git $dir @('pull', '--ff-only') 180000 }   # chỉ fast-forward, không tự tạo merge commit
        'switch' {
            if ($branch -notmatch '^[A-Za-z0-9._/-]+$' -or $branch -match '\.\.|^-|/$') { throw 'Tên nhánh không hợp lệ' }
            $dirty = @((Invoke-Git $dir @('status', '--porcelain')).Out -split "`n" | Where-Object { $_.Trim() }).Count
            if ($dirty) { throw "Còn $dirty file chưa commit - commit hoặc stash trước khi đổi nhánh" }
            $r = Invoke-Git $dir @('switch', $branch) 60000
        }
        default { throw "Lệnh git không hỗ trợ: $action" }
    }
    $msg = (@($r.Out, $r.Err) | Where-Object { $_ }) -join "`n"
    if ($r.Code -ne 0) { throw ("git $action lỗi: " + $msg) }
    if (-not $msg) { $msg = "git $action xong" }
    $msg
}

# ---------- Sức khỏe máy ----------
# Ngưỡng cảnh báo (%)
$HealthLimits = @{ Cpu = 90; Ram = 90; Disk = 90; Battery = 20 }
$script:prevCpu  = @{}      # PID -> TotalProcessorTime lần đo trước
$script:prevTime = $null
$script:prevNet  = $null

function Get-HealthInfo {
    $os    = Get-CimInstance Win32_OperatingSystem
    $cores = [Environment]::ProcessorCount
    $cpu   = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $ramFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramPct   = if ($ramTotal) { [math]::Round(($ramTotal - $ramFree) * 100 / $ramTotal) } else { 0 }

    # CPU từng tiến trình = chênh lệch thời gian CPU giữa 2 lần đo
    $now = Get-Date
    # Win32_Process: 1 truy vấn, không bị lỗi quyền như Get-Process.TotalProcessorTime (nhanh hơn ~10 lần)
    $procs = Get-CimInstance Win32_Process -Property ProcessId, Name, KernelModeTime, UserModeTime, WorkingSetSize |
        Where-Object { $_.ProcessId -gt 4 }
    $elapsed = if ($script:prevTime) { ($now - $script:prevTime).TotalSeconds } else { 0 }
    $cur = @{}
    $rows = foreach ($p in $procs) {
        $t = ([double]$p.KernelModeTime + [double]$p.UserModeTime) / 1e7   # đơn vị 100ns -> giây
        $cur[$p.ProcessId] = $t
        $pct = 0
        if ($elapsed -gt 0 -and $script:prevCpu.ContainsKey($p.ProcessId)) {
            $pct = [math]::Round(($t - $script:prevCpu[$p.ProcessId]) * 100 / $elapsed / $cores, 1)
        }
        [pscustomobject]@{ Name = ($p.Name -replace '\.exe$', ''); Cpu = [math]::Max(0, $pct); RamMB = [math]::Round($p.WorkingSetSize / 1MB) }
    }
    $script:prevCpu = $cur; $script:prevTime = $now

    # Gộp theo tên tiến trình (chrome, code... có nhiều tiến trình con)
    $grouped = $rows | Where-Object { $_.Name -ne 'Memory Compression' } | Group-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name  = $_.Name
            Count = $_.Count
            Cpu   = [math]::Round(($_.Group | Measure-Object Cpu -Sum).Sum, 1)
            RamMB = [math]::Round(($_.Group | Measure-Object RamMB -Sum).Sum)
        }
    }

    # Bộ nhớ máy ảo WSL (Ubuntu + Docker)
    $wslMB = [math]::Round((($rows | Where-Object { $_.Name -like 'vmmem*' }) | Measure-Object RamMB -Sum).Sum)

    # Mạng: tổng tốc độ tải lên / xuống của các card thật
    $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface |
        Where-Object { $_.Name -notmatch 'isatap|Teredo|Loopback|vEthernet' } |
        Measure-Object BytesReceivedPersec, BytesSentPersec -Sum
    $downKB = [math]::Round(($net | Where-Object Property -eq 'BytesReceivedPersec').Sum / 1KB)
    $upKB   = [math]::Round(($net | Where-Object Property -eq 'BytesSentPersec').Sum / 1KB)

    $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
    $battery = $null
    if ($bat) {
        $battery = [pscustomobject]@{
            Percent  = [int]$bat.EstimatedChargeRemaining
            Charging = ($bat.BatteryStatus -in 2, 6, 7, 8, 9)   # 2 = đang cắm sạc
        }
    }

    $disks = @(Get-DiskInfo)
    $warnings = @()
    if ($cpu -ge $HealthLimits.Cpu)    { $warnings += "CPU cao: $cpu%" }
    if ($ramPct -ge $HealthLimits.Ram) { $warnings += "RAM cao: $ramPct%" }
    foreach ($d in $disks) { if ($d.UsedPct -ge $HealthLimits.Disk) { $warnings += "Ổ $($d.Drive) sắp đầy: còn $($d.FreeGB) GB" } }
    if ($battery -and -not $battery.Charging -and $battery.Percent -le $HealthLimits.Battery) { $warnings += "Pin yếu: $($battery.Percent)%" }

    [pscustomobject]@{
        Cpu       = [int]$cpu
        Cores     = $cores
        RamPct    = $ramPct
        RamUsedGB = [math]::Round($ramTotal - $ramFree, 1)
        RamTotalGB = $ramTotal
        WslMB     = $wslMB
        NetDownKB = $downKB
        NetUpKB   = $upKB
        Battery   = $battery
        Uptime    = ((Get-Date) - $os.LastBootUpTime).ToString('d\.hh\:mm')
        TopCpu    = @($grouped | Sort-Object Cpu -Descending | Select-Object -First 5)
        TopRam    = @($grouped | Sort-Object RamMB -Descending | Select-Object -First 5)
        Disks     = $disks
        Warnings  = @($warnings)
    }
}

# ---------- Nguồn máy tính ----------
function Invoke-PowerAction([string]$action) {
    switch ($action) {
        'sleep'    { Add-Type -AssemblyName System.Windows.Forms
                     [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false) | Out-Null }
        'restart'  { shutdown.exe /r /t 15 /c "${AppName}: khởi động lại sau 15 giây" }
        'shutdown' { shutdown.exe /s /t 15 /c "${AppName}: tắt máy sau 15 giây" }
        'cancel'   { shutdown.exe /a }
    }
}
