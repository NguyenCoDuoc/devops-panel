# DUOCNC DevOps Web Panel - web server nhỏ chỉ nghe 127.0.0.1, mở ra mạng Tailscale bằng `tailscale serve`
# Chạy: powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File WebPanel.ps1
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\DUOCNC_DevOpsWeb')
if (-not $mutex.WaitOne(0)) { exit }

. (Join-Path $PSScriptRoot 'DevOpsCore.ps1')

$Port      = 8787
$HtmlFile  = Join-Path $PSScriptRoot 'webpanel.html'
$IconFile  = Join-Path $PSScriptRoot 'icon-preview.png'
$LogFile   = Join-Path $PSScriptRoot 'webpanel.log'
$CfgFile   = Join-Path $PSScriptRoot 'webpanel.json'

# Chỉ các tài khoản Tailscale trong danh sách này được dùng panel
$Allowed = @('coduoc2502@gmail.com')
if (Test-Path $CfgFile) {
    $cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
    if ($cfg.allowedLogins) { $Allowed = @($cfg.allowedLogins) }
}

function Write-Log([string]$msg) {
    Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8
}

function Send-Response($stream, [int]$code, [string]$type, [byte[]]$body) {
    $reason = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 405 = 'Method Not Allowed'; 500 = 'Internal Server Error' }[$code]
    $head = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`n" +
            "Cache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nX-Frame-Options: DENY`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    if ($body.Length) { $stream.Write($body, 0, $body.Length) }
}

function Send-Json($stream, [int]$code, $obj) {
    Send-Response $stream $code 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 5 -Compress)))
}

function Get-Snapshot {
    $ts = Get-TailscaleInfo
    [pscustomobject]@{
        host       = $env:COMPUTERNAME
        time       = (Get-Date).ToString('HH:mm:ss dd/MM/yyyy')
        uptime     = ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString('d\.hh\:mm')
        tailscale  = $ts
        components = @($Components | ForEach-Object {
            [pscustomobject]@{ id = $_.Id; name = $_.Name; port = [string]$_.Port; remote = $_.Remote; running = [bool](Get-ComponentState $_) }
        })
        disks      = @(Get-DiskInfo)
    }
}

function Invoke-Request($client) {
    $stream = $client.GetStream()
    $stream.ReadTimeout = 5000
    $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 8192, $true)
    $line = $reader.ReadLine()
    if (-not $line) { return }
    $parts = $line.Split(' ')
    if ($parts.Count -lt 2) { Send-Json $stream 400 @{ error = 'bad request' }; return }
    $method = $parts[0]; $path = $parts[1].Split('?')[0]

    $headers = @{}
    while ($true) {
        $h = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($h)) { break }
        $i = $h.IndexOf(':')
        if ($i -gt 0) { $headers[$h.Substring(0, $i).Trim().ToLower()] = $h.Substring($i + 1).Trim() }
    }

    # Xác thực: tailscale serve gắn danh tính người dùng vào header Tailscale-User-Login
    # Không có header = truy cập thẳng trên chính máy này; chỉ chấp nhận khi Host đúng localhost (chống DNS rebinding)
    $login = $headers['tailscale-user-login']
    $isLocal = (-not $login) -and ($headers['host'] -in @("localhost:$Port", "127.0.0.1:$Port"))
    if ($isLocal) { $login = 'local' }
    elseif (-not $login -or ($Allowed -notcontains $login)) {
        Write-Log "DENY  $method $path  login='$login'"
        Send-Json $stream 403 @{ error = 'forbidden' }
        return
    }

    if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        Send-Response $stream 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($HtmlFile)); return
    }
    if ($method -eq 'GET' -and $path -eq '/icon.png') {
        Send-Response $stream 200 'image/png' ([IO.File]::ReadAllBytes($IconFile)); return
    }
    if ($method -eq 'GET' -and $path -eq '/api/status') {
        $snap = Get-Snapshot
        $snap | Add-Member user $login
        Send-Json $stream 200 $snap; return
    }

    if ($method -eq 'GET' -and $path -eq '/api/health') {
        Send-Json $stream 200 (Get-HealthInfo); return
    }
    if ($method -eq 'GET' -and $path -eq '/api/apps') {
        Send-Json $stream 200 @(Get-DevApps); return
    }
    if ($method -eq 'GET' -and $path -match '^/api/apps/git/([a-z0-9-]+)$') {
        try { Send-Json $stream 200 (Get-AppGitInfo $Matches[1]) } catch { Send-Json $stream 400 @{ error = $_.Exception.Message } }
        return
    }
    if ($method -eq 'GET' -and $path -match '^/api/apps/log/([a-z0-9-]+)$') {
        Send-Response $stream 200 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes((Get-DevAppLog $Matches[1] 300))); return
    }
    if ($method -eq 'GET' -and $path -eq '/api/k3s') {
        Send-Json $stream 200 (Get-K3sInfo); return
    }
    if ($method -eq 'GET' -and $path -match '^/api/k3s/logs/([^/]+)/([^/]+)/(current|previous)$') {
        $ns = $Matches[1]; $pod = $Matches[2]; $prev = $Matches[3] -eq 'previous'
        if (-not ((Test-K8sName $ns) -and (Test-K8sName $pod))) { Send-Json $stream 400 @{ error = 'tên không hợp lệ' }; return }
        $text = Get-K3sLogs $ns $pod 300 -Previous:$prev
        Send-Response $stream 200 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($text)); return
    }

    if ($path -like '/api/*') {
        # Chống CSRF: request thay đổi trạng thái phải là POST và có header riêng
        if ($method -ne 'POST' -or $headers['x-devops'] -ne '1') { Send-Json $stream 405 @{ error = 'POST + X-DevOps required' }; return }

        if ($path -match '^/api/component/([a-z0-9]+)/(start|stop|restart)$') {
            $c = $Components | Where-Object Id -eq $Matches[1]
            $act = $Matches[2]
            if (-not $c) { Send-Json $stream 404 @{ error = 'unknown component' }; return }
            if (-not $c.Remote) { Send-Json $stream 403 @{ error = "$($c.Name) chỉ điều khiển được trên máy tính" }; return }
            Write-Log "ACT   $login  $act $($c.Id)"
            switch ($act) {
                'start'   { Start-Component $c }
                'stop'    { Stop-Component $c }
                'restart' { Stop-Component $c; Start-Sleep 2; Start-Component $c }
            }
            Send-Json $stream 200 @{ ok = $true; message = "Đã $act $($c.Name)" }; return
        }

        if ($path -match '^/api/apps/git/([a-z0-9-]+)/(fetch|pull|switch)(?:/(.+))?$') {
            $id = $Matches[1]; $act = $Matches[2]; $br = if ($Matches[3]) { [Uri]::UnescapeDataString($Matches[3]) } else { '' }
            Write-Log "GIT   $login  $act $id $br"
            try { Send-Json $stream 200 @{ ok = $true; message = [string](Invoke-AppGit $id $act $br) } }
            catch { Send-Json $stream 400 @{ error = $_.Exception.Message } }
            return
        }

        if ($path -match '^/api/apps/([a-z0-9-]+)/(start|stop|restart)$') {
            $id = $Matches[1]; $act = $Matches[2]
            Write-Log "APP   $login  $act $id"
            try {
                $msg = switch ($act) {
                    'start'   { Start-DevApp $id }
                    'stop'    { Stop-DevApp $id }
                    'restart' { Stop-DevApp $id | Out-Null; Start-Sleep 2; Start-DevApp $id }
                }
                Send-Json $stream 200 @{ ok = $true; message = [string]$msg }
            } catch { Send-Json $stream 400 @{ error = $_.Exception.Message } }
            return
        }

        if ($path -match '^/api/k3s/restart/([^/]+)/([^/]+)$') {
            $ns = $Matches[1]; $pod = $Matches[2]
            if (-not ((Test-K8sName $ns) -and (Test-K8sName $pod))) { Send-Json $stream 400 @{ error = 'tên không hợp lệ' }; return }
            Write-Log "K3S   $login  restart pod $ns/$pod"
            $r = Restart-K3sPod $ns $pod
            Send-Json $stream 200 @{ ok = $true; message = ($r.Trim()) }; return
        }

        if ($path -match '^/api/power/(sleep|restart|shutdown|cancel)$') {
            $act = $Matches[1]
            Write-Log "POWER $login  $act"
            # Trả lời trước rồi mới thực hiện, để điện thoại nhận được phản hồi
            Send-Json $stream 200 @{ ok = $true; message = "Đã gửi lệnh $act" }
            $stream.Flush(); $client.Close()
            Invoke-PowerAction $act
            return
        }
    }

    Send-Json $stream 404 @{ error = 'not found' }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } catch { Write-Log "Không mở được port $Port : $_"; exit 1 }
Write-Log "START listening 127.0.0.1:$Port, allowed: $($Allowed -join ', ')"

while ($true) {
    $client = $listener.AcceptTcpClient()
    try { Invoke-Request $client }
    catch { Write-Log "ERROR $_" }
    finally { $client.Close() }
}
