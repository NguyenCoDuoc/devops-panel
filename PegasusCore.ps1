# Develop Workspace - logic dùng chung cho PegasusPanel.ps1 (desktop) và Web Panel (bản trả phí, không nằm trong repo)
$env:WSL_UTF8 = '1'

# Phiên bản: chỉ sửa ở đây - build-setup.ps1 đọc số này để ghi vào exe, bộ cài và mục gỡ cài đặt
$PanelVersion = '1.0.5'
$SupportEmail = 'coduoc2502@gmail.com'
$UpdateRepo   = 'NguyenCoDuoc/devops-panel'      # kiểm tra bản mới qua GitHub Releases

# ---------- Cấu hình theo người dùng ----------
# Nằm ở %APPDATA% (không phải thư mục cài) để cài lại / nâng cấp bản mới không mất cấu hình, danh mục app, log.
$DataDir    = if ($env:DEVOPS_PANEL_DATA) { $env:DEVOPS_PANEL_DATA } else { Join-Path $env:APPDATA 'PegasusPanel' }     # biến môi trường: chạy thử với dữ liệu riêng
$ConfigFile = Join-Path $DataDir 'config.json'
New-Item -ItemType Directory -Force $DataDir | Out-Null

function Get-PanelConfig {
    $cfg = [ordered]@{
        appName         = 'Develop Workspace'
        distro          = ''          # rỗng = tự chọn distro Ubuntu đầu tiên
        pgUbuntuPort    = 0           # 0 = không có PostgreSQL trong WSL
        autoStartUbuntu = $false
        theme           = ''          # light | dark; rỗng = theo Windows lần đầu
        showStats       = $false      # tab Ứng dụng: hiện cột CPU / RAM / Phản hồi
        pgCollapsed     = $true       # tab Dịch vụ: thu gọn nhóm PostgreSQL trong WSL (ít dùng)
        goalsAsk        = $true       # mỗi ngày hỏi mục tiêu khi mở panel
        goalsAskedOn    = ''          # ngày đã hỏi gần nhất (yyyy-MM-dd)
        goalsRemindedOn = ''          # ngày đã nhắc mục tiêu chưa xong lúc chiều
        scanRoots       = @()         # thư mục gốc để quét project cho tab Ứng dụng
        aiTool          = 'claude'    # tab AI Code: claude | codex | gemini
        aiMode          = 1           # 0 = chỉ đọc, 1 = cho sửa file, 2 = toàn quyền
        aiModel         = ''          # rỗng = model mặc định của CLI
        aiDirs          = @()         # thư mục làm việc dùng gần đây
        aiSessions      = @()         # các phiên AI gần đây, nhóm theo thư mục
        navLayout       = 'top'       # menu tab: top = trên dải tiêu đề, side = thanh bên trái
        navCollapsed    = $false      # thanh bên trái thu gọn chỉ còn icon
        noLockOnSleep   = $false      # không yêu cầu đăng nhập sau khi thức dậy
    }
    if (Test-Path $ConfigFile) {
        $j = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($cfg.Keys)) { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } }
    } else {
        # Máy đã dùng bản cũ (cài từ mã nguồn): mang settings.json sang
        $legacy = Join-Path $PSScriptRoot 'settings.json'
        if (Test-Path $legacy) {
            $j = Get-Content $legacy -Raw | ConvertFrom-Json
            $cfg.appName = 'Develop Workspace'
            if ($null -ne $j.autoStartUbuntu) { $cfg.autoStartUbuntu = [bool]$j.autoStartUbuntu }
            $cfg.distro = 'Ubuntu'
            $cfg.pgUbuntuPort = 5434
        }
        Save-PanelConfig ([pscustomobject]$cfg)
    }
    # Migrate tên thương hiệu cũ, giữ nguyên tên tuỳ chỉnh trong Cài đặt.
    if ($cfg.appName -in @('SH Dev Panel', 'DevOps Panel', 'DUOCNC DevOps Panel', 'Pegasus Control Center', 'Pegasus Control Center Panel', 'Develop Workspace Panel', 'DEV SH Panel')) { $cfg.appName = 'Develop Workspace'; Save-PanelConfig ([pscustomobject]$cfg) }
    $cfg.scanRoots = @($cfg.scanRoots | Where-Object { $_ })
    $cfg.aiDirs = @($cfg.aiDirs | Where-Object { $_ })
    $cfg.aiSessions = @($cfg.aiSessions | Where-Object { $_.Id -and $_.Dir -and $_.Tool })
    [pscustomobject]$cfg
}
function Save-PanelConfig($cfg) {
    $cfg | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8
}

# Chạy exe có timeout: máy chưa cài / bị chặn WSL thì wsl.exe có thể treo rất lâu
function Invoke-NativeTimeout([string]$exe, [string]$arguments, [int]$timeoutMs = 8000) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo($exe, $arguments)
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($timeoutMs)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = -1; Out = ''; TimedOut = $true } }
        [pscustomobject]@{ Code = $p.ExitCode; Out = $outTask.Result; TimedOut = $false }
    } catch { [pscustomobject]@{ Code = -2; Out = ''; TimedOut = $false } }
}

function Get-WslDistros {
    $wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (-not (Test-Path $wsl)) { return @() }
    $r = Invoke-NativeTimeout $wsl '--list --quiet' 8000
    if ($r.Code -ne 0) { return @() }       # chưa cài WSL: wsl.exe in hướng dẫn cài ra stdout, exit code khác 0
    @($r.Out -split "`r?`n" | ForEach-Object { $_.Trim([char]0, ' ') } | Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
}

function Set-SleepLockPreference([bool]$NoLock) {
    $value = if ($NoLock) { 0 } else { 1 }
    $command = "powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK $value && powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK $value && powercfg.exe /setactive SCHEME_CURRENT"
    $args = "/d /c `"$command`""
    # Windows protects wake-lock policy; request elevation only when the user changes this opt-in setting.
    $p = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -ArgumentList $args -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Windows không đổi được yêu cầu khóa sau Sleep (mã $($p.ExitCode))." }
}

function Find-FirstPath([string[]]$candidates) {
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

$PanelConfig  = Get-PanelConfig
$AppName      = [string]$PanelConfig.appName
# Runspace nền (PegasusPanel.ps1 truyền $CoreShared) dùng lại kết quả dò của luồng chính
$WslDistros   = if ($CoreShared) { $CoreShared.WslDistros } else { Get-WslDistros }
$Distro       = if ($CoreShared) { $CoreShared.Distro }
                elseif ($PanelConfig.distro -and $WslDistros -contains $PanelConfig.distro) { $PanelConfig.distro }
                elseif ($WslDistros -contains 'Ubuntu') { 'Ubuntu' }
                else { $WslDistros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1 }
$PgUbuntuPort = [int]$PanelConfig.pgUbuntuPort
$DockerExe    = Find-FirstPath @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe")
$TailscaleExe = Find-FirstPath @("$env:ProgramFiles\Tailscale\tailscale.exe")
# git.exe: PATH của app chạy từ shortcut có thể thiếu Git -> thử thêm chỗ cài mặc định
$GitExe       = Find-FirstPath @((Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
                                 "$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")

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
    if (-not $Distro) { return $false }
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

$Components = if ($CoreShared) { $CoreShared.Components } else { @(
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
) }

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
$IngressSelector = 'app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller'
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
    $ingCols = 'NS:.metadata.namespace,PHASE:.status.phase,WAIT:.status.containerStatuses[0].state.waiting.reason,' +
               'RESTARTS:.status.containerStatuses[0].restartCount,HN:.spec.hostNetwork,PORT:.spec.containers[0].ports[0].containerPort,HP:.spec.containers[0].ports[0].hostPort'
    $cols = 'NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,WAIT:.status.containerStatuses[*].state.waiting.reason,' +
            'READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,' +
            'OWNER:.metadata.ownerReferences[0].kind,START:.status.startTime,DEL:.metadata.deletionTimestamp'
    # Thêm IP hiện tại của WSL và pod ingress để phát hiện lỗi đổi mạng (đổi Wi-Fi -> k3s giữ IP cũ, ingress khởi động lại liên tục)
    $out = @(Invoke-Wsl ("$KubeEnv systemctl is-active k3s; echo '###';" +
        " k3s kubectl get pods -A --no-headers -o custom-columns='$cols' 2>/dev/null; echo '###';" +
        " k3s kubectl get nodes -o wide --no-headers 2>/dev/null; echo '###';" +
        " ip -4 route get 1.1.1.1 2>/dev/null | head -1; echo '###';" +
        " k3s kubectl get pods -A -l $IngressSelector --no-headers -o custom-columns='$ingCols' 2>/dev/null"))
    if (([string]$out[0]).Trim() -ne 'active') { return [pscustomobject]@{ Running = $false; Reason = 'k3s đã dừng' } }
    # Tách theo dòng ### thành các phần: 0 trạng thái, 1 pods, 2 nodes, 3 route, 4 ingress
    $parts = @(, (New-Object System.Collections.ArrayList))
    foreach ($l in $out) {
        if (([string]$l).Trim() -eq '###') { $parts += , (New-Object System.Collections.ArrayList) }
        elseif (([string]$l).Trim()) { [void]$parts[-1].Add([string]$l) }
    }
    while ($parts.Count -lt 5) { $parts += , (New-Object System.Collections.ArrayList) }
    $lines = $parts[1]; $nodeLines = $parts[2]

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
        if ($f.Count -ge 5) { [pscustomobject]@{ Name = $f[0]; Status = $f[1]; Version = $f[4]; Ip = $(if ($f.Count -ge 6) { $f[5] } else { '' }) } }
    })

    $wslIp = if (([string]$parts[3][0]) -match '\bsrc\s+(\S+)') { $Matches[1] } else { '' }
    $nodeIp = if ($nodes.Count) { $nodes[0].Ip } else { '' }
    $ing = $null
    $f = if ($parts[4].Count) { ([string]$parts[4][0]).Trim() -split '\s+' } else { @() }
    if ($f.Count -ge 7) {
        $port = if ($f[6] -match '^\d+$') { [int]$f[6] } elseif ($f[4] -eq 'true' -and $f[5] -match '^\d+$') { [int]$f[5] } else { 0 }
        $ing = [pscustomobject]@{
            Namespace = $f[0]
            Status    = if ($f[2] -ne '<none>') { $f[2] } else { $f[1] }
            Restarts  = if ($f[3] -match '^\d+$') { [int]$f[3] } else { 0 }
            Port      = $port
            Open      = if ($port) { Test-Port $port } else { $null }   # thử từ Windows, đúng đường app gọi vào
        }
    }
    $network = [pscustomobject]@{
        WslIp    = $wslIp
        NodeIp   = $nodeIp
        Mismatch = [bool]($wslIp -and $nodeIp -and $wslIp -ne $nodeIp)
        Ingress  = $ing
    }

    [pscustomobject]@{
        Running   = $true
        Nodes     = $nodes
        Pods      = $pods
        Total     = $pods.Count
        Healthy   = @($pods | Where-Object Healthy).Count
        Unhealthy = @($pods | Where-Object { -not $_.Healthy }).Count
        Namespaces = @($pods.Namespace | Sort-Object -Unique).Count
        Network   = $network
    }
}

# Sửa lỗi sau khi đổi Wi-Fi / IP: khởi động lại k3s để nhận IP mới, chờ API lên rồi tạo lại pod ingress
function Repair-K3sNetwork {
    if (-not (Test-UbuntuRunning)) { throw 'Ubuntu chưa chạy' }
    $r = Invoke-Wsl ("$KubeEnv systemctl restart k3s || exit 1;" +
        " for i in `$(seq 60); do k3s kubectl get nodes >/dev/null 2>&1 && break; sleep 2; done;" +
        " k3s kubectl delete pod -A -l $IngressSelector --wait=false 2>&1")
    ($r | Out-String).Trim()
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

# ---------- Dọn log tự động mỗi ngày ----------
# Mỗi lần khởi động: nếu hôm nay chưa dọn, cắt bớt file .log cũ hơn ngày hiện tại
# Giữ lại tối đa $LogKeepTailLines dòng cuối + dòng phân cách để vẫn xem được context gần nhất
function Invoke-DailyLogCleanup {
    if (-not (Test-Path $AppsLogDir)) { return }
    $today      = (Get-Date).ToString('yyyy-MM-dd')
    $markerFile = Join-Path $AppsLogDir ".cleanup-$today"
    if (Test-Path $markerFile) { return }          # hôm nay đã dọn rồi

    $keepLines = 200                               # số dòng cuối giữ lại mỗi file
    $cutoffDays = 1                                # cắt log cũ hơn N ngày
    $cutoff = (Get-Date).AddDays(-$cutoffDays)
    $cleaned = 0; $savedKB = 0

    Get-ChildItem $AppsLogDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        try {
            $sizeBefore = $_.Length
            $lines = @(Get-Content $_.FullName -Encoding UTF8 -ErrorAction Stop)
            if ($lines.Count -le $keepLines) { return }    # file nhỏ, bỏ qua
            $kept = $lines[($lines.Count - $keepLines)..($lines.Count - 1)]
            $header = "==== $today  [Log đã được dọn tự động - giữ $keepLines dòng cuối] ===="
            ($header, '') + $kept | Set-Content $_.FullName -Encoding UTF8 -ErrorAction Stop
            $savedKB += [int](($sizeBefore - $_.Length) / 1KB)
            $cleaned++
        } catch { }    # file đang bị app giữ → bỏ qua, lần sau dọn
    }

    # Xoá marker ngày cũ để không tích luỹ
    Get-ChildItem $AppsLogDir -Filter '.cleanup-*' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".cleanup-$today" } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Ghi marker hôm nay
    $today | Set-Content $markerFile -Encoding UTF8
}
Invoke-DailyLogCleanup

if (-not (Test-Path $AppsFile)) {
    $legacyApps = Join-Path $PSScriptRoot 'apps.json'        # bản cài từ mã nguồn để apps.json cạnh script
    if (Test-Path $legacyApps) { Copy-Item $legacyApps $AppsFile }
    else { [pscustomobject]@{ scanRanges = $DefaultScanRanges; apps = @() } | ConvertTo-Json -Depth 5 | Set-Content $AppsFile -Encoding UTF8 }
}

function Get-AppsConfig {
    $cfg = Get-Content $AppsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $ranges = if ($cfg.scanRanges) { @($cfg.scanRanges) } else { $DefaultScanRanges }
    [pscustomobject]@{ Ranges = $ranges; Apps = @($cfg.apps | Where-Object { $_ }); Removed = @($cfg.removed | Where-Object { $_ })
                       Profiles = @($cfg.profiles | Where-Object { $_ }) }
}

# $removed / $profiles = $null: giữ nguyên giá trị đang có trong file
function Save-AppsConfig($ranges, $apps, $removed = $null, $profiles = $null) {
    if ($null -eq $removed -or $null -eq $profiles) { $cur = Get-AppsConfig }
    if ($null -eq $removed) { $removed = $cur.Removed }
    if ($null -eq $profiles) { $profiles = $cur.Profiles }
    [pscustomobject]@{ scanRanges = @($ranges); apps = @($apps); removed = @($removed); profiles = @($profiles) } |
        ConvertTo-Json -Depth 6 | Set-Content $AppsFile -Encoding UTF8
}

# ---------- Bộ app (profile): nhóm app hay chạy cùng nhau ----------
function Save-AppsProfile([string]$name, [string[]]$ids) {
    $name = $name.Trim()
    if (-not $name) { throw 'Tên bộ không được để trống' }
    $cfg = Get-AppsConfig
    $others = @($cfg.Profiles | Where-Object { $_.name -ne $name })
    Save-AppsConfig $cfg.Ranges $cfg.Apps $cfg.Removed (@($others) + [pscustomobject]@{ name = $name; ids = @($ids) })
    "Đã lưu bộ '$name' ($(@($ids).Count) app)"
}
function Remove-AppsProfile([string]$name) {
    $cfg = Get-AppsConfig
    Save-AppsConfig $cfg.Ranges $cfg.Apps $cfg.Removed @($cfg.Profiles | Where-Object { $_.name -ne $name })
    "Đã xoá bộ '$name'"
}

# Bật / tắt tự khởi động lại khi app sập
function Set-DevAppAutoRestart([string[]]$ids, [bool]$on) {
    $cfg = Get-AppsConfig
    foreach ($a in $cfg.Apps) {
        if ($ids -contains $a.id) {
            if ($a.PSObject.Properties['autoRestart']) { $a.autoRestart = $on } else { $a | Add-Member autoRestart $on }
        }
    }
    Save-AppsConfig $cfg.Ranges $cfg.Apps
}

# Gỡ app khỏi panel: chuyển sang "removed" (giữ nguyên cấu hình để khôi phục), lần quét project sau bỏ qua thư mục đó.
# Không đụng tới code / thư mục project.
function Remove-DevApps([string[]]$ids) {
    $cfg = Get-AppsConfig
    $out = @($cfg.Apps | Where-Object { $ids -contains $_.id })
    if (-not $out.Count) { throw 'Không có app nào trong danh mục để gỡ' }
    foreach ($a in $out) { Remove-Item (Join-Path $AppsLogDir "$($a.id).pid") -Force -ErrorAction SilentlyContinue }
    Save-AppsConfig $cfg.Ranges @($cfg.Apps | Where-Object { $ids -notcontains $_.id }) (@($cfg.Removed) + $out)
    "Đã gỡ khỏi panel: " + (($out | ForEach-Object name) -join ', ')
}

function Restore-DevApps([string[]]$ids) {
    $cfg = Get-AppsConfig
    $back = @($cfg.Removed | Where-Object { $ids -contains $_.id })
    $taken = @($cfg.Apps | ForEach-Object id)
    $back = @($back | Where-Object { $taken -notcontains $_.id })      # id đã bị app khác dùng (quét lại) -> bỏ qua
    Save-AppsConfig $cfg.Ranges (@($cfg.Apps) + $back) @($cfg.Removed | Where-Object { $ids -notcontains $_.id })
    "Đã khôi phục $($back.Count) app"
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
    $removedDirs = @($cfg.Removed | Where-Object dir | ForEach-Object { $_.dir.TrimEnd('\').ToLower() })    # app người dùng đã gỡ
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
        if ($removedDirs -contains $p.dir.TrimEnd('\').ToLower()) { continue }
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
                Known = $true; Running = [bool]$tp; Busy = $false; BusyPid = 0; AutoRestart = [bool]$a.autoRestart
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
            BusyPid = if ($p -and -not $mine) { [int]$p.ProcessId } else { 0 }
            AutoRestart = [bool]$a.autoRestart
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

# ---------- CPU / RAM / phản hồi của từng app (tab Ứng dụng) ----------
# CPU tính theo chênh lệch thời gian CPU giữa 2 lần đo -> lưu lần đo trước ở biến toàn cục của runspace
if (-not $global:DevAppCpuPrev) { $global:DevAppCpuPrev = @{} }
function Add-DevAppStats($rows, [switch]$NoHealth) {
    $running = @($rows | Where-Object { $_.Running -and $_.Pid })
    if (-not $running.Count) { return }
    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, WorkingSetSize, KernelModeTime, UserModeTime)
    $byPid = @{}; $children = @{}
    foreach ($p in $all) {
        $byPid[[int]$p.ProcessId] = $p
        $pp = [int]$p.ParentProcessId
        if (-not $children.ContainsKey($pp)) { $children[$pp] = New-Object System.Collections.ArrayList }
        [void]$children[$pp].Add([int]$p.ProcessId)
    }
    $cores = [Environment]::ProcessorCount
    $now = [DateTime]::UtcNow.Ticks
    foreach ($r in $running) {
        # Cây tiến trình: từ tiến trình gốc panel đã chạy (cmd /c ...) nếu còn, cộng tiến trình đang nghe port
        $roots = @([int]$r.Pid)
        $pidFile = Join-Path $AppsLogDir "$($r.Id).pid"
        if (Test-Path $pidFile) { $rp = [int](Get-Content $pidFile | Select-Object -First 1); if ($byPid.ContainsKey($rp)) { $roots += $rp } }
        $seen = @{}; $stack = New-Object System.Collections.Stack
        foreach ($x in $roots) { $stack.Push($x) }
        while ($stack.Count) {
            $id = $stack.Pop()
            if ($seen.ContainsKey($id) -or -not $byPid.ContainsKey($id)) { continue }
            $seen[$id] = $true
            if ($children.ContainsKey($id)) { foreach ($c in $children[$id]) { $stack.Push($c) } }
        }
        $ram = 0; $cpu = 0
        foreach ($id in $seen.Keys) { $p = $byPid[$id]; $ram += [double]$p.WorkingSetSize; $cpu += [double]$p.KernelModeTime + [double]$p.UserModeTime }
        $pct = $null
        $prev = $global:DevAppCpuPrev[$r.Id]
        if ($prev -and $now -gt $prev.T) { $pct = [math]::Max(0, [math]::Round(($cpu - $prev.C) * 100 / (($now - $prev.T) * $cores), 1)) }
        $global:DevAppCpuPrev[$r.Id] = @{ T = $now; C = $cpu }
        $r | Add-Member CpuPct $pct -Force
        $r | Add-Member RamMB ([math]::Round($ram / 1MB)) -Force
    }
    if (-not $NoHealth) {
        foreach ($r in @($running | Where-Object Port)) {
            $h = Test-DevAppHttp $r
            $r | Add-Member HealthMs $h.Ms -Force; $r | Add-Member HealthCode $h.Code -Force; $r | Add-Member HealthOk $h.Ok -Force
        }
    }
}

# Gọi thử http(s)://localhost:port/ - có phản hồi HTTP bất kỳ (kể cả 404) là app còn sống; 5xx = lỗi; không kết nối được = treo
function Test-DevAppHttp($r, [int]$timeoutMs = 2500) {
    if (-not ('DevCertTrust' -as [type])) {
        Add-Type -TypeDefinition @"
using System.Net.Security; using System.Security.Cryptography.X509Certificates;
public static class DevCertTrust {
    static bool Accept(object s, X509Certificate c, X509Chain ch, SslPolicyErrors e) { return true; }
    public static readonly RemoteCertificateValidationCallback Callback = Accept;
}
"@
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $scheme = if ([string]$r.Url -like 'https:*') { 'https' } else { 'http' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $null
    try {
        $req = [Net.HttpWebRequest]::Create("${scheme}://localhost:$($r.Port)/")
        $req.Method = 'GET'; $req.Timeout = $timeoutMs; $req.ReadWriteTimeout = $timeoutMs
        $req.AllowAutoRedirect = $false; $req.Proxy = $null; $req.KeepAlive = $false
        $req.ServerCertificateValidationCallback = [DevCertTrust]::Callback      # chứng chỉ dev localhost tự ký
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
    } catch [Net.WebException] {
        if ($_.Exception.Response) { $resp = $_.Exception.Response; $code = [int]$resp.StatusCode }
        else { return @{ Ok = $false; Ms = [int]$sw.ElapsedMilliseconds; Code = 0 } }
    } catch { return @{ Ok = $false; Ms = [int]$sw.ElapsedMilliseconds; Code = 0 } }
    finally { if ($resp) { $resp.Close() } }
    @{ Ok = ($code -lt 500); Ms = [int]$sw.ElapsedMilliseconds; Code = $code }
}

# Tắt tiến trình đang giữ port (port bị chiếm nên app không chạy được)
function Stop-PortOwner([int]$port) {
    $l = Get-ListeningPorts | Where-Object LocalPort -eq $port | Select-Object -First 1
    if (-not $l) { return "Port $port đã trống" }
    $owner = [int]$l.OwningProcess
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$owner" -Property Name, ExecutablePath
    $pn = if ($p) { $p.Name -replace '\.exe$', '' } else { '?' }
    if ($owner -le 4 -or $SystemProcs -contains $pn -or ([string]$p.ExecutablePath) -like "$env:WINDIR\*") {
        throw "Port $port do Windows giữ ($pn, PID $owner - thường là IIS / http.sys) - không tắt từ panel được"
    }
    Stop-ProcessTree $owner
    Start-Sleep -Milliseconds 500
    if (Get-ListeningPorts | Where-Object LocalPort -eq $port) { throw "Đã tắt $pn (PID $owner) nhưng port $port vẫn bị giữ" }
    "Đã tắt $pn (PID $owner) - port $port đã trống"
}

# Chạy nhiều app theo thứ tự: tool (migrator) chạy xong -> backend -> BFF -> frontend; mỗi đợt chờ app nghe port rồi mới sang đợt sau
function Start-DevAppsOrdered([string[]]$ids, [int]$phaseTimeoutSec = 180) {
    $cfg = @((Get-AppsConfig).Apps | Where-Object { $ids -contains $_.id })
    $msgs = New-Object System.Collections.ArrayList
    $phases = @(@('tool'), @('backend'), @('bff'), @('frontend'))
    $known = @('tool', 'backend', 'bff', 'frontend')
    foreach ($ph in $phases) {
        $apps = @($cfg | Where-Object { $ph -contains $_.type -or ($ph -contains 'backend' -and $known -notcontains $_.type) })
        if (-not $apps.Count) { continue }
        $wait = New-Object System.Collections.ArrayList
        foreach ($a in $apps) {
            try { $m = [string](Start-DevApp $a.id); [void]$msgs.Add($m); if ($m -notlike '*đang chạy rồi') { [void]$wait.Add($a) } }
            catch { [void]$msgs.Add("✗ $($a.id): $($_.Exception.Message)") }
        }
        $deadline = (Get-Date).AddSeconds($phaseTimeoutSec)
        while ($wait.Count -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $cur = if ($ph -contains 'tool') { @() } else { @(Get-DevApps) }
            foreach ($a in @($wait)) {
                $pidFile = Join-Path $AppsLogDir "$($a.id).pid"
                $alive = (Test-Path $pidFile) -and [bool](Get-Process -Id ([int](Get-Content $pidFile | Select-Object -First 1)) -ErrorAction SilentlyContinue)
                if ($ph -contains 'tool') { if (-not $alive) { $wait.Remove($a) }; continue }       # tool: chờ chạy xong
                if (($cur | Where-Object Id -eq $a.id).Running) { $wait.Remove($a) }
                elseif (-not $alive) { [void]$msgs.Add("✗ $($a.id): tiến trình đã thoát trước khi nghe port - xem log"); $wait.Remove($a) }
            }
        }
        foreach ($a in $wait) { [void]$msgs.Add("✗ $($a.id): sau $phaseTimeoutSec giây chưa thấy chạy - vẫn chạy tiếp các app sau") }
    }
    , $msgs.ToArray()
}

# ---------- Xuất / nhập danh mục app (chia sẻ cho người trong team) ----------
function Export-AppsCatalog([string]$path) {
    $cfg = Get-AppsConfig
    [pscustomobject]@{
        format = 'devops-panel-apps'; version = $PanelVersion; exportedAt = (Get-Date).ToString('s'); computer = $env:COMPUTERNAME
        scanRoots = @($PanelConfig.scanRoots); scanRanges = @($cfg.Ranges)
        apps = @($cfg.Apps | Select-Object * -ExcludeProperty autoRestart); profiles = @($cfg.Profiles)
    } | ConvertTo-Json -Depth 6 | Set-Content $path -Encoding UTF8
    "Đã xuất $(@($cfg.Apps).Count) app, $(@($cfg.Profiles).Count) bộ ra $path"
}

# Máy khác thường để code ở thư mục khác -> đổi đường dẫn: thay thư mục gốc cũ bằng thư mục gốc máy này, không được thì dò theo đuôi đường dẫn
function Resolve-ImportedDir([string]$dir, [string[]]$oldRoots, [string[]]$newRoots) {
    if (-not $dir -or (Test-Path $dir)) { return $dir }
    foreach ($o in $oldRoots) {
        $o = $o.TrimEnd('\')
        if ($dir.ToLower().StartsWith($o.ToLower() + '\')) {
            $tail = $dir.Substring($o.Length)
            foreach ($n in $newRoots) { $c = $n.TrimEnd('\') + $tail; if (Test-Path $c) { return $c } }
        }
    }
    $segs = $dir.TrimEnd('\') -split '\\'
    for ($k = [math]::Min(6, $segs.Count - 1); $k -ge 2; $k--) {
        $tail = ($segs[($segs.Count - $k)..($segs.Count - 1)]) -join '\'
        foreach ($n in $newRoots) { $c = Join-Path $n $tail; if (Test-Path $c) { return $c } }
    }
    $dir
}

function Import-AppsCatalog([string]$path) {
    $j = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.apps) { throw 'File không phải danh mục app của Develop Workspace' }
    $cfg = Get-AppsConfig
    $newRoots = @($PanelConfig.scanRoots | Where-Object { $_ -and (Test-Path $_) })
    $oldRoots = @($j.scanRoots | Where-Object { $_ })
    $haveDir = @{}; foreach ($a in $cfg.Apps) { if ($a.dir) { $haveDir[$a.dir.TrimEnd('\').ToLower()] = $a.id } }
    $taken = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($a in $cfg.Apps) { [void]$taken.Add($a.id) }
    $idMap = @{}; $added = @(); $dup = 0; $missing = 0
    foreach ($a in $j.apps) {
        $dir = Resolve-ImportedDir ([string]$a.dir) $oldRoots $newRoots
        $key = ([string]$dir).TrimEnd('\').ToLower()
        if ($key -and $haveDir.ContainsKey($key)) { $idMap[$a.id] = $haveDir[$key]; $dup++; continue }
        $id = if ($taken.Contains($a.id)) { New-AppId $a.name $taken } else { [void]$taken.Add($a.id); $a.id }
        $idMap[$a.id] = $id
        if ($dir -and -not (Test-Path $dir)) { $missing++ }
        $added += [pscustomobject]@{ id = $id; group = $a.group; name = $a.name; type = $a.type; port = $a.port; url = $a.url; dir = $dir; start = $a.start; manual = $true }
        if ($key) { $haveDir[$key] = $id }
    }
    $profNames = @($cfg.Profiles | ForEach-Object name)
    $newProfiles = @(foreach ($p in $j.profiles) {
        if ($profNames -contains $p.name) { continue }
        [pscustomobject]@{ name = $p.name; ids = @($p.ids | ForEach-Object { if ($idMap.ContainsKey($_)) { $idMap[$_] } } | Where-Object { $_ }) }
    })
    Save-AppsConfig $cfg.Ranges (@($cfg.Apps) + $added) $cfg.Removed (@($cfg.Profiles) + $newProfiles)
    "Đã nhập $($added.Count) app mới, $($newProfiles.Count) bộ" + $(if ($dup) { " · $dup app đã có sẵn" } else { '' }) +
        $(if ($missing) { " · $missing app chưa tìm thấy thư mục trên máy này (sửa trong apps.json)" } else { '' })
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
    if (-not $GitExe) { return [pscustomobject]@{ Code = -2; Out = ''; Err = 'Không tìm thấy git.exe' } }
    $psi.FileName = $GitExe
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
    $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'      # status không ghi index -> không tranh khoá với IDE
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

function Get-AppGitInfo([string]$id) { Get-RepoGitInfo (Get-AppDir $id) }

function Get-RepoGitInfo([string]$dir) {
    if (-not $GitExe) { return [pscustomobject]@{ IsRepo = $false; Dir = $dir; Error = 'Máy này chưa cài Git (không thấy git.exe trong PATH / Program Files)' } }
    $top = Invoke-Git $dir @('rev-parse', '--show-toplevel') 20000
    if ($top.Code -ne 0) {
        $err = [string]$top.Err
        if ($err -match 'dubious ownership') {
            $unsafe = if ($err -match "repository at '([^']+)'") { $Matches[1] } else { $dir }
            return [pscustomobject]@{ IsRepo = $false; Dir = $dir; UnsafePath = $unsafe
                Error = 'Git chặn repo vì thư mục thuộc user Windows khác (dubious ownership)' }
        }
        if ($err -match 'not a git repository') { return [pscustomobject]@{ IsRepo = $false; Dir = $dir } }
        return [pscustomobject]@{ IsRepo = $false; Dir = $dir; Error = 'git lỗi: ' + (($err -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)) }
    }

    # 1 lệnh status cho cả nhánh, upstream, ahead/behind và danh sách file sửa
    $branch = ''; $upstream = ''; $ahead = 0; $behind = 0
    $changes = New-Object System.Collections.ArrayList
    foreach ($l in ((Invoke-Git $dir @('-c', 'status.relativePaths=false', 'status', '--porcelain=v2', '--branch')).Out -split "`n")) {
        if ($l -match '^# branch\.head (.+)$') { $branch = $Matches[1] }
        elseif ($l -match '^# branch\.upstream (.+)$') { $upstream = $Matches[1] }
        elseif ($l -match '^# branch\.ab \+(\d+) -(\d+)') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
        elseif ($l -match '^1 (\S\S) (?:\S+ ){6}(.+)$') { [void]$changes.Add(($Matches[1] -replace '\.', ' ') + ' ' + $Matches[2]) }
        elseif ($l -match '^2 (\S\S) (?:\S+ ){7}(.+)$') { [void]$changes.Add(($Matches[1] -replace '\.', ' ') + ' ' + ($Matches[2] -split "`t")[0]) }
        elseif ($l -match '^u (\S\S) (?:\S+ ){8}(.+)$') { [void]$changes.Add("$($Matches[1]) $($Matches[2])") }
        elseif ($l -match '^\? (.+)$') { [void]$changes.Add("?? $($Matches[1])") }
    }
    if ($branch -eq '(detached)') { $branch = 'HEAD' }

    # 1 lệnh cho danh sách nhánh + commit cuối của nhánh hiện tại
    $last = @('', '', '', '')
    $branches = New-Object System.Collections.ArrayList
    $fmt = '%(HEAD)%1f%(refname:short)%1f%(objectname:short)%1f%(contents:subject)%1f%(authorname)%1f%(committerdate:relative)'
    foreach ($l in ((Invoke-Git $dir @('for-each-ref', "--format=$fmt", 'refs/heads')).Out -split "`n")) {
        $f = $l -split [char]0x1f
        if ($f.Count -lt 6) { continue }
        [void]$branches.Add($f[1])
        if ($f[0] -eq '*') { $last = $f[2..5] }
    }
    if (-not $last[0]) { $last = (Invoke-Git $dir @('log', '-1', '--format=%h%x1f%s%x1f%an%x1f%cr')).Out -split [char]0x1f }   # detached HEAD
    $fetchHead = Join-Path $top.Out '.git\FETCH_HEAD'

    [pscustomobject]@{
        IsRepo    = $true
        Dir       = $dir
        Root      = $top.Out -replace '/', '\'
        Remote    = Hide-UrlSecret (Invoke-Git $dir @('config', '--get', 'remote.origin.url')).Out
        Branch    = $branch
        Upstream  = $upstream
        Ahead     = $ahead
        Behind    = $behind
        Dirty     = $changes.Count
        Changes   = @($changes | Select-Object -First 15)
        LastHash  = $last[0]
        LastMsg   = if ($last.Count -gt 1) { $last[1] } else { '' }
        LastAuthor = if ($last.Count -gt 2) { $last[2] } else { '' }
        LastWhen  = if ($last.Count -gt 3) { $last[3] } else { '' }
        Branches  = @($branches)
        LastFetch = if (Test-Path $fetchHead) { (Get-Item $fetchHead).LastWriteTime.ToString('HH:mm dd/MM') } else { '' }
    }
}

# Thêm repo vào safe.directory (git chặn repo do user khác tạo) - chỉ chạy khi người dùng đồng ý
function Add-GitSafeDirectory([string]$path) {
    if (-not $GitExe) { throw 'Không tìm thấy git.exe' }
    $r = Invoke-Git $env:USERPROFILE @('config', '--global', '--add', 'safe.directory', $path)
    if ($r.Code -ne 0) { throw $r.Err }
    "Đã tin cậy repo $path"
}

# Đo thời gian từng bước - nút "Chẩn đoán tốc độ" ở tab Cài đặt
function Get-PerfDiagnostics {
    $ErrorActionPreference = 'SilentlyContinue'
    $lines = New-Object System.Collections.ArrayList
    function Step([string]$name, [scriptblock]$sb) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $note = try { [string](& $sb) } catch { "LỖI: $($_.Exception.Message)" }
        [void]$lines.Add(('{0,-34} {1,7:N0} ms  {2}' -f $name, $sw.ElapsedMilliseconds, $note))
    }
    [void]$lines.Add("Máy: $env:COMPUTERNAME · Windows $([Environment]::OSVersion.Version) · PowerShell $($PSVersionTable.PSVersion) · $($ExecutionContext.SessionState.LanguageMode)")
    [void]$lines.Add("git.exe: $(if ($GitExe) { $GitExe } else { 'KHÔNG THẤY' })")
    [void]$lines.Add('')
    Step 'wsl.exe --list' { $r = Invoke-NativeTimeout (Join-Path $env:WINDIR 'System32\wsl.exe') '--list --quiet' 15000; if ($r.TimedOut) { 'TREO (quá 15s)' } else { "exit $($r.Code)" } }
    Step 'WMI: danh sách tiến trình' { "$(@(Get-CimInstance Win32_Process -Property ProcessId).Count) tiến trình" }
    Step 'WMI: service PostgreSQL' { "$(@(Get-CimInstance Win32_Service -Filter "Name LIKE 'postgresql%'").Count) service" }
    Step 'netstat (port đang nghe)' { "$(@(Get-ListeningPorts).Count) port" }
    if ($GitExe) {
        Step 'Khởi chạy git.exe (x5)' { 1..5 | ForEach-Object { Invoke-Git $env:TEMP @('--version') | Out-Null }; 'trung bình = số ms / 5' }
    }
    Step 'Quét ứng dụng (tab Ứng dụng)' { "$(@(Get-DevApps).Count) dòng" }
    $first = (Get-AppsConfig).Apps | Where-Object { $_.dir -and (Test-Path $_.dir) } | Select-Object -First 1
    if ($first) {
        Step "Đọc git: $($first.name)" { $g = Get-AppGitInfo $first.id; if ($g.Error) { $g.Error } elseif ($g.IsRepo) { "nhánh $($g.Branch)" } else { 'không phải repo' } }
    }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        [void]$lines.Add('')
        [void]$lines.Add("Defender quét thời gian thực: $(if ($mp.RealTimeProtectionEnabled) { 'BẬT' } else { 'tắt' })")
    } catch { }
    $lines -join "`r`n"
}

# ---------- Git cho tất cả repo trong danh mục ----------
function Get-AllReposGitInfo {
    $repos = [ordered]@{}
    foreach ($a in (Get-AppsConfig).Apps) {
        if (-not $a.dir -or -not (Test-Path $a.dir)) { continue }
        $top = Invoke-Git $a.dir @('rev-parse', '--show-toplevel') 20000
        $root = if ($top.Code -eq 0) { $top.Out -replace '/', '\' } else { $a.dir }
        $k = $root.ToLower()
        if (-not $repos.Contains($k)) { $repos[$k] = @{ Root = $root; Apps = New-Object System.Collections.ArrayList } }
        [void]$repos[$k].Apps.Add($a.name)
    }
    foreach ($r in $repos.Values) {
        $g = Get-RepoGitInfo $r.Root
        [pscustomobject]@{
            Root = $r.Root; Name = (Split-Path $r.Root -Leaf); Apps = ($r.Apps -join ', ')
            IsRepo = $g.IsRepo; Error = $g.Error; Branch = $g.Branch; Upstream = $g.Upstream
            Ahead = $g.Ahead; Behind = $g.Behind; Dirty = $g.Dirty; LastFetch = $g.LastFetch
        }
    }
}

# Lỗi git dễ hiểu: bỏ các dòng "hint:", diễn giải lỗi hay gặp
function Format-GitError([string]$root, [string]$msg) {
    if ($msg -match 'Not possible to fast-forward|Diverging branches|have diverged') {
        $c = (Invoke-Git $root @('rev-list', '--left-right', '--count', 'HEAD...@{u}')).Out -split '\s+'
        $ahead = if ($c.Count -ge 2) { $c[0] } else { '?' }; $behind = if ($c.Count -ge 2) { $c[1] } else { '?' }
        return "nhánh ở máy và remote đã lệch nhau (máy có $ahead commit chưa push, remote có $behind commit mới) - panel chỉ pull fast-forward, cần merge hoặc rebase bằng tay"
    }
    if ($msg -match 'would be overwritten by merge') { return 'file đang sửa ở máy trùng với file remote vừa đổi - commit hoặc stash trước rồi pull' }
    if ($msg -match 'no tracking information|no upstream') { return 'nhánh chưa có upstream trên remote - dùng Push + MR để đẩy lên lần đầu' }
    if ($msg -match 'Authentication failed|could not read Username|terminal prompts disabled') { return 'git cần đăng nhập - mở terminal tại repo chạy git fetch một lần để lưu tài khoản' }
    if ($msg -match 'Could not resolve host|unable to access') { return 'không kết nối được tới git server (mạng / VPN?)' }
    (($msg -split "`n" | Where-Object { $_ -notmatch '^\s*hint:' -and $_.Trim() }) -join ' ') -replace '\s+', ' '
}

function Invoke-ReposGit([string[]]$roots, [string]$action) {
    $out = foreach ($root in $roots) {
        $r = switch ($action) {
            'fetch' { Invoke-Git $root @('fetch', '--prune') 120000 }
            'pull'  { Invoke-Git $root @('pull', '--ff-only') 180000 }
            default { throw "Lệnh không hỗ trợ: $action" }
        }
        $msg = ((@($r.Out, $r.Err) | Where-Object { $_ }) -join ' ') -replace '\s+', ' '
        if ($r.Code -eq 0) { "✓ $(Split-Path $root -Leaf): $(if ($msg) { $msg } else { "$action xong" })" }
        else { "✗ $(Split-Path $root -Leaf): $(Format-GitError $root ((@($r.Out, $r.Err) | Where-Object { $_ }) -join "`n"))" }
    }
    , @($out)
}

# Tạo nhánh theo git-flow: feature/ fix/ bugfix/ tách từ main, hotfix/ tách từ production.
# Tách từ origin/<gốc> mới fetch (= pull nhánh gốc rồi tách), không track nhánh gốc, không push.
# $carry = mang theo thay đổi chưa commit sang nhánh mới (git switch tự từ chối nếu xung đột với nhánh gốc)
function New-RepoFlowBranch([string[]]$roots, [string]$type, [string]$name, [bool]$carry = $false) {
    if ($type -notin 'feature', 'fix', 'bugfix', 'hotfix') { throw 'Loại nhánh không hợp lệ' }
    if ($name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { throw 'Tên nhánh chỉ gồm chữ thường, số và dấu gạch ngang (vd prepare-load-goods)' }
    $baseBranch = if ($type -eq 'hotfix') { 'production' } else { 'main' }
    $branch = "$type/$name"
    $out = foreach ($root in $roots) {
        $leaf = Split-Path $root -Leaf
        $dirty = @((Invoke-Git $root @('status', '--porcelain')).Out -split "`n" | Where-Object { $_.Trim() }).Count
        if ($dirty -and -not $carry) { "✗ ${leaf}: còn $dirty file chưa commit - commit hoặc stash trước"; continue }
        $f = Invoke-Git $root @('fetch', 'origin', '--prune') 120000
        if ($f.Code -ne 0) { "✗ ${leaf}: fetch lỗi - $($f.Err)"; continue }
        if ((Invoke-Git $root @('rev-parse', '--verify', '--quiet', "origin/$baseBranch")).Code -ne 0) { "✗ ${leaf}: không có nhánh origin/$baseBranch"; continue }
        if ((Invoke-Git $root @('rev-parse', '--verify', '--quiet', "refs/heads/$branch")).Code -eq 0) { "✗ ${leaf}: nhánh $branch đã có"; continue }
        $r = Invoke-Git $root @('switch', '--no-track', '-c', $branch, "origin/$baseBranch") 60000
        if ($r.Code -eq 0) { "✓ ${leaf}: đã tạo $branch từ origin/$baseBranch" + $(if ($dirty) { " (mang theo $dirty file đang sửa)" } else { '' }) }
        elseif ($r.Err -match 'would be overwritten') { "✗ ${leaf}: thay đổi đang sửa xung đột với origin/$baseBranch - commit / stash trước rồi tạo nhánh" }
        else { "✗ ${leaf}: $($r.Err)" }
    }
    , @($out)
}

# Đường dẫn web của repo (GitLab) từ remote origin: https://host/group/repo.git hoặc git@host:group/repo.git
function Get-RepoWebUrl([string]$root) {
    $u = (Invoke-Git $root @('config', '--get', 'remote.origin.url')).Out.Trim()
    if (-not $u) { return $null }
    if ($u -match '^[\w.-]+@([^:]+):(.+?)(\.git)?$') { return "https://$($Matches[1])/$($Matches[2])" }
    ($u -replace '://[^/@\s]+@', '://') -replace '\.git$', ''
}

# Push nhánh hiện tại rồi trả về link tạo Merge Request đúng nhánh đích theo git-flow:
# feature/ fix/ bugfix/ -> main ; hotfix/ -> production. Không cho push thẳng main / production.
function Push-RepoBranchForMr([string]$root) {
    $branch = (Invoke-Git $root @('rev-parse', '--abbrev-ref', 'HEAD')).Out.Trim()
    if ($branch -in 'main', 'production', 'master', 'HEAD', '') { throw "Đang ở nhánh '$branch' - chỉ push nhánh feature/ fix/ bugfix/ hotfix/ (vào main / production phải qua Merge Request)" }
    $target = if ($branch -like 'hotfix/*') { 'production' } else { 'main' }
    $r = Invoke-Git $root @('push', '-u', 'origin', $branch) 180000
    if ($r.Code -ne 0) { throw "git push lỗi: $($r.Err)" }
    $web = Get-RepoWebUrl $root
    $url = if ($web -match '^https?://') { "$web/-/merge_requests/new?merge_request%5Bsource_branch%5D=$([Uri]::EscapeDataString($branch))&merge_request%5Btarget_branch%5D=$target" } else { $null }
    [pscustomobject]@{ Msg = "Đã push $branch -> mở Merge Request vào $target" + $(if ($branch -like 'hotfix/*') { ' (nhớ cherry-pick sang main sau khi merge)' } else { '' }); Url = $url }
}

# Lịch sử commit dạng cây (graph)
function Get-RepoLogGraph([string]$root, [int]$count = 200, [bool]$all = $true) {
    $args2 = @('log', '--graph', '--date=format:%d/%m/%y %H:%M', "--pretty=format:%h%d  %s  (%an, %ad)", "-n", "$count")
    if ($all) { $args2 += '--all' }
    $r = Invoke-Git $root $args2 60000
    if ($r.Code -ne 0) { throw $r.Err }
    $r.Out
}

# Tóm tắt thư mục làm việc cho tab AI Code: nhánh, số dòng thêm / bớt so với HEAD, số file mới chưa track
function Get-RepoWorkSummary([string]$dir) {
    $b = Invoke-Git $dir @('rev-parse', '--abbrev-ref', 'HEAD') 10000
    if ($b.Code -ne 0) { return [pscustomobject]@{ Repo = $false } }
    $st = (Invoke-Git $dir @('diff', '--shortstat', 'HEAD') 20000).Out
    $new = @((Invoke-Git $dir @('ls-files', '--others', '--exclude-standard') 20000).Out -split "`n" | Where-Object { $_ }).Count
    [pscustomobject]@{
        Repo = $true; Branch = $b.Out.Trim(); New = $new
        Add = $(if ($st -match '(\d+) insertion') { [int]$Matches[1] } else { 0 })
        Del = $(if ($st -match '(\d+) deletion') { [int]$Matches[1] } else { 0 })
    }
}

# ---------- Cửa sổ Git kiểu Git Extensions: nhánh, lịch sử commit, diff, stage / commit ----------
function Get-RepoBranches([string]$root) {
    $fmt = '%(refname)%1f%(refname:short)%1f%(HEAD)%1f%(upstream:short)%1f%(upstream:track)'
    $r = Invoke-Git $root @('for-each-ref', "--format=$fmt", 'refs/heads', 'refs/remotes', 'refs/tags')
    foreach ($l in ($r.Out -split "`n")) {
        $f = $l -split [char]0x1f
        if ($f.Count -lt 5 -or $f[0] -like 'refs/remotes/*/HEAD') { continue }
        $kind = if ($f[0] -like 'refs/heads/*') { 'local' } elseif ($f[0] -like 'refs/remotes/*') { 'remote' } else { 'tag' }
        [pscustomobject]@{ Kind = $kind; Name = $f[1]; Current = ($f[2] -eq '*'); Upstream = $f[3]; Track = $f[4] }
    }
}

# Lịch sử commit + bố cục graph tự tính từ cha của từng commit (thay cho chữ ASCII của git log --graph):
# mỗi commit nằm ở làn Col, màu Color; Segs = các đoạn @(kiểu, làn đầu, làn cuối, màu) để vẽ trong dòng đó
#   kiểu 0 = làn đi xuyên dòng, 1 = nửa trên (từ commit con đổ vào chấm), 2 = nửa dưới (từ chấm ra commit cha)
# Màu gắn với làn từ lúc làn mở nên một nhánh giữ nguyên màu suốt lịch sử.
function Get-RepoCommits([string]$root, [int]$count = 300, [bool]$all = $true) {
    $a = @('-c', 'core.quotePath=false', 'log', '--date-order', '--date=format:%d/%m/%Y %H:%M', '--pretty=format:%H%x1f%h%x1f%P%x1f%an%x1f%ad%x1f%D%x1f%s', '-n', "$count")
    if ($all) { $a += '--all' }
    $r = Invoke-Git $root $a 60000
    if ($r.Code -ne 0) { throw $r.Err }
    $lanes = New-Object System.Collections.ArrayList      # mỗi làn đang chờ commit nào ($null = làn trống)
    $colors = New-Object System.Collections.ArrayList
    $next = 0
    foreach ($l in ($r.Out -split "`n")) {
        $f = $l -split [char]0x1f
        if ($f.Count -lt 7) { continue }
        $h = $f[0]; $parents = @($f[2] -split ' ' | Where-Object { $_ })
        $segs = New-Object System.Collections.ArrayList
        $width = $lanes.Count
        $col = $lanes.IndexOf($h)
        $tip = $col -lt 0                                   # đầu nhánh: chưa commit con nào chờ
        if ($tip) {
            $col = $lanes.IndexOf($null)
            if ($col -lt 0) { $col = $lanes.Add($null); [void]$colors.Add(0) }
            $lanes[$col] = $h; $colors[$col] = $next++
        }
        $color = $colors[$col]
        for ($k = 0; $k -lt $width; $k++) {
            $w = $lanes[$k]
            if ($null -eq $w) { continue }
            if ($w -ne $h) { [void]$segs.Add(@(0, $k, $k, $colors[$k])); continue }
            if ($k -ne $col) { [void]$segs.Add(@(1, $k, $col, $colors[$k])); $lanes[$k] = $null }       # nhánh khác nhập về commit này
            elseif (-not $tip) { [void]$segs.Add(@(1, $col, $col, $color)) }
        }
        $lanes[$col] = $null
        for ($i = 0; $i -lt $parents.Count; $i++) {
            $p = $parents[$i]
            $e = $lanes.IndexOf($p)
            if ($e -ge 0) { [void]$segs.Add(@(2, $col, $e, $(if ($i -eq 0) { $color } else { $colors[$e] }))); continue }     # cha đã có làn chờ
            if ($i -eq 0) { $e = $col }
            else {
                $e = $lanes.IndexOf($null)
                if ($e -lt 0) { $e = $lanes.Add($null); [void]$colors.Add(0) }
                $colors[$e] = $next++
            }
            $lanes[$e] = $p
            [void]$segs.Add(@(2, $col, $e, $colors[$e]))
        }
        while ($lanes.Count -and $null -eq $lanes[$lanes.Count - 1]) { $lanes.RemoveAt($lanes.Count - 1); $colors.RemoveAt($colors.Count - 1) }
        [pscustomobject]@{
            Hash = $h; Short = $f[1]; Author = $f[3]; Date = $f[4]; Refs = $f[5]; Subject = ($f[6..($f.Count - 1)] -join ' ')
            Merge = $parents.Count -gt 1; Col = $col; Color = $color; Lanes = [math]::Max([math]::Max($width, $lanes.Count), $col + 1); Segs = $segs.ToArray()
        }
    }
}

function Get-CommitDetail([string]$root, [string]$hash) {
    if ($hash -notmatch '^[0-9a-f]{7,40}$') { throw 'Mã commit không hợp lệ' }
    $info = (Invoke-Git $root @('show', '-s', '--date=format:%d/%m/%Y %H:%M:%S', "--format=Commit:  %H%nTác giả: %an <%ae>%nNgày:    %ad%nCha:     %P%n%n%B", $hash)).Out
    $files = foreach ($l in ((Invoke-Git $root @('-c', 'core.quotePath=false', 'show', '--format=', '--name-status', '-M', '-m', '--first-parent', $hash)).Out -split "`n")) {
        $f = $l -split "`t"
        if ($f.Count -lt 2) { continue }
        [pscustomobject]@{ Code = $f[0].Substring(0, 1); Path = $f[$f.Count - 1]; Old = $(if ($f.Count -gt 2) { $f[1] } else { '' }) }
    }
    [pscustomobject]@{ Info = $info; Files = @($files) }
}
function Get-CommitFileDiff([string]$root, [string]$hash, [string]$path) {
    if ($hash -notmatch '^[0-9a-f]{7,40}$') { throw 'Mã commit không hợp lệ' }
    (Invoke-Git $root @('-c', 'core.quotePath=false', 'show', '--format=', '-M', '-m', '--first-parent', $hash, '--', $path)).Out
}

# File thay đổi trong thư mục làm việc: mỗi file có thể có 1 dòng "đã stage" và 1 dòng "chưa stage"
function Get-RepoChanges([string]$root) {
    $r = Invoke-Git $root @('-c', 'core.quotePath=false', '-c', 'status.relativePaths=false', 'status', '--porcelain=v2', '--untracked-files=all')
    if ($r.Code -ne 0) { throw $r.Err }
    foreach ($l in ($r.Out -split "`n")) {
        if ($l -match '^1 (\S)(\S) (?:\S+ ){6}(.+)$') { $x = $Matches[1]; $y = $Matches[2]; $path = $Matches[3]; $old = '' }
        elseif ($l -match '^2 (\S)(\S) (?:\S+ ){7}(.+)$') { $x = $Matches[1]; $y = $Matches[2]; $pp = $Matches[3] -split "`t"; $path = $pp[0]; $old = $pp[1] }
        elseif ($l -match '^u \S\S (?:\S+ ){8}(.+)$') { [pscustomobject]@{ Path = $Matches[1]; Code = 'U'; Staged = $false; Old = '' }; continue }
        elseif ($l -match '^\? (.+)$') { [pscustomobject]@{ Path = $Matches[1]; Code = '?'; Staged = $false; Old = '' }; continue }
        else { continue }
        if ($x -ne '.') { [pscustomobject]@{ Path = $path; Code = $x; Staged = $true; Old = $old } }
        if ($y -ne '.') { [pscustomobject]@{ Path = $path; Code = $y; Staged = $false; Old = '' } }
    }
}

function Invoke-RepoStage([string]$root, [string[]]$paths, [bool]$stage, [switch]$All) {
    if ($All) {
        $r = if ($stage) { Invoke-Git $root @('add', '-A') } else { Invoke-Git $root @('reset', '-q') }
        if ($r.Code -ne 0) { throw $r.Err }
        return
    }
    for ($i = 0; $i -lt $paths.Count; $i += 40) {          # chia nhỏ để dòng lệnh không quá dài
        $chunk = $paths[$i..([math]::Min($i + 39, $paths.Count - 1))]
        $r = if ($stage) { Invoke-Git $root (@('add', '-A', '--') + $chunk) } else { Invoke-Git $root (@('reset', '-q', '--') + $chunk) }
        if ($r.Code -ne 0) { throw $r.Err }
    }
}

# Diff của file trong thư mục làm việc (đã stage / chưa stage / file mới chưa track)
function Get-WorkingDiff([string]$root, [string]$path, [bool]$staged, [string]$code) {
    if ($code -eq '?') {
        $full = Join-Path $root $path
        if (-not (Test-Path $full -PathType Leaf)) { return '' }
        if ((Get-Item $full).Length -gt 512KB) { return "(File mới, lớn $([math]::Round((Get-Item $full).Length / 1KB)) KB - không hiển thị)" }
        $lines = @(Get-Content -LiteralPath $full -TotalCount 2000 -Encoding UTF8)
        return "File mới (chưa track): $path`n@@ +1,$($lines.Count) @@`n" + (($lines | ForEach-Object { "+$_" }) -join "`n")
    }
    $a = @('-c', 'core.quotePath=false', 'diff')
    if ($staged) { $a += '--cached' }
    (Invoke-Git $root ($a + @('-M', '--', $path))).Out
}

function Invoke-RepoCommit([string]$root, [string]$message) {
    if (-not $message.Trim()) { throw 'Commit message không được để trống' }
    $staged = @((Invoke-Git $root @('diff', '--cached', '--name-only')).Out -split "`n" | Where-Object { $_ }).Count
    if (-not $staged) { throw 'Chưa có file nào được stage' }
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $message.Trim() + "`n", (New-Object System.Text.UTF8Encoding($false)))
    try { $r = Invoke-Git $root @('commit', '-F', $tmp) 180000 } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    if ($r.Code -ne 0) { throw ((@($r.Out, $r.Err) | Where-Object { $_ }) -join "`n") }
    ($r.Out -split "`n")[0]
}

function Switch-RepoBranch([string]$root, [string]$name, [bool]$isRemote) {
    if ($name -notmatch '^[A-Za-z0-9._/-]+$' -or $name -match '\.\.|^-') { throw 'Tên nhánh không hợp lệ' }
    $dirty = @((Invoke-Git $root @('status', '--porcelain', '--untracked-files=no')).Out -split "`n" | Where-Object { $_.Trim() }).Count
    if ($dirty) { throw "Còn $dirty file đang sửa - commit hoặc stash trước khi đổi nhánh" }
    $target = if ($isRemote) { $name -replace '^[^/]+/', '' } else { $name }       # origin/x -> tạo nhánh local x theo dõi origin/x
    $r = Invoke-Git $root @('switch', $target) 60000
    if ($r.Code -ne 0) { throw $r.Err }
    "Đã chuyển sang $target"
}

# ---------- Kiểm tra / tải bản mới (GitHub Releases) ----------
function ConvertTo-PanelVersion([string]$tag) {
    $v = $null
    if ([version]::TryParse(($tag.Trim() -replace '^[vV]', ''), [ref]$v)) { $v } else { $null }
}
# Bản phát hành mới nhất (không tính bản nháp / pre-release). API GitHub không cần đăng nhập: 60 lần/giờ mỗi IP.
function Get-LatestRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $r = Invoke-RestMethod "https://api.github.com/repos/$UpdateRepo/releases/latest" -UseBasicParsing -TimeoutSec 15 `
        -Headers @{ 'User-Agent' = "PegasusPanel/$PanelVersion"; 'Accept' = 'application/vnd.github+json' }
    $asset = @($r.assets | Where-Object { $_.name -eq 'PegasusPanel-Setup.exe' }) | Select-Object -First 1
    $ver = ConvertTo-PanelVersion $r.tag_name
    [pscustomobject]@{
        Tag = $r.tag_name; Version = [string]$ver; Name = $r.name; Notes = [string]$r.body; Url = $r.html_url
        Published = $(if ($r.published_at) { ([datetime]$r.published_at).ToLocalTime().ToString('dd/MM/yyyy') } else { '' })
        SetupUrl = $asset.browser_download_url; SetupSize = [long]$asset.size
        IsNewer = [bool]($ver -and $ver -gt [version]$PanelVersion)
    }
}
# Tải bộ cài của bản mới về thư mục Temp, kiểm tra đúng file exe rồi trả đường dẫn
function Save-UpdateInstaller([string]$url, [string]$version, [long]$size = 0) {
    if ($url -notmatch '^https://(github\.com|objects\.githubusercontent\.com)/') { throw 'Link tải bộ cài không hợp lệ' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $dest = Join-Path $env:TEMP "PegasusPanel-Setup-$version.exe"
    $wc = New-Object System.Net.WebClient
    $wc.Headers['User-Agent'] = "PegasusPanel/$PanelVersion"
    try { $wc.DownloadFile($url, $dest) } finally { $wc.Dispose() }
    $fi = Get-Item $dest
    $head = [IO.File]::ReadAllBytes($dest)[0..1]
    if ($fi.Length -lt 10KB -or ($size -and $fi.Length -ne $size) -or $head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        throw 'File tải về không đúng bộ cài (bị lỗi khi tải hoặc bị chặn bởi proxy)'
    }
    $dest
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
    if ($r.Code -ne 0) { throw ("git $action lỗi: " + (Format-GitError $dir $msg)) }
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
function Enable-SystemSleepPrivilege {
    if (-not ('PccNativePower' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PccNativePower {
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attributes; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, uint length, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("powrprof.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.U1)]
    static extern bool SetSuspendState([MarshalAs(UnmanagedType.U1)] bool hibernate, [MarshalAs(UnmanagedType.U1)] bool force, [MarshalAs(UnmanagedType.U1)] bool disableWakeEvents);
    public static void EnableShutdownPrivilege() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            LUID luid;
            if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out luid)) throw new Win32Exception(Marshal.GetLastWin32Error());
            TOKEN_PRIVILEGES state = new TOKEN_PRIVILEGES(); state.Count = 1; state.Luid = luid; state.Attributes = 2;
            if (!AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            int error = Marshal.GetLastWin32Error();
            if (error == 1300) throw new Win32Exception(error, "Tài khoản chạy Web Panel chưa được cấp quyền Shutdown.");
        } finally { CloseHandle(token); }
    }
    public static void Sleep() {
        if (!SetSuspendState(false, false, false)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
"@
    }
    [PccNativePower]::EnableShutdownPrivilege()
}

function Invoke-PowerAction([string]$action) {
    switch ($action) {
        'sleep'    { Enable-SystemSleepPrivilege; [PccNativePower]::Sleep() }
        'restart'  { shutdown.exe /r /t 15 /c "${AppName}: khởi động lại sau 15 giây" }
        'shutdown' { shutdown.exe /s /t 15 /c "${AppName}: tắt máy sau 15 giây" }
        'cancel'   { shutdown.exe /a }
    }
}
