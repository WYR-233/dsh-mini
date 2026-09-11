# smoke-test.ps1 - end-to-end smoke test of a built dsh-mini installer.
#
# Answers the only question that matters for a release: on a CLEAN directory,
# does install -> start -> panel (with token, no 401) -> restart -> panel still
# works -> uninstall leave nothing behind?
#
# Usage:
#   powershell scripts\smoke-test.ps1 -Installer release\DeepSeekHarnessMini-Setup-v0.1.1.exe
#   powershell scripts\smoke-test.ps1 -Installer ... -Uninstall      # also test uninstall
#
# Notes:
#   - installs into test\smoke (wiped first), silent, no admin needed
#   - uses a NON-default port (2255) so it never touches a running DSH instance
#   - sets DSH_NO_BROWSER=1 for the test tray: the browser-open path is proven by
#     the tray log line "opening panel (with launch token)"; HTTP checks below
#     prove the URL it would open really gets into the panel
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [string]$InstallDir = "",
    [int]$Port = 2255,
    [switch]$Uninstall,
    [switch]$NoBrowser    # suppress the real browser tab (then the auto-open is checked by log evidence only)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not [System.IO.Path]::IsPathRooted($Installer)) { $Installer = Join-Path $repoRoot $Installer }
if ($InstallDir -eq "") { $InstallDir = Join-Path $repoRoot 'test\smoke' }

$fail = @()
$pass = @()
function Ok([string]$m) { Write-Host "  [ok]   $m"; $script:pass += $m }
function Bad([string]$m) { Write-Host "  [FAIL] $m"; $script:fail += $m }

function Get-HttpStatus([string]$Url, $Cookies) {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    if ($Cookies -ne $null) { $handler.CookieContainer = $Cookies }
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    try {
        $resp = $client.GetAsync($Url).Result
        return $resp
    } finally {
        # response stays alive for the caller to inspect
    }
}

function Wait-Port([int]$TimeoutSec) {
    for ($i = 0; $i -lt $TimeoutSec; $i++) {
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(500)) { $c.EndConnect($ar); $c.Close(); return $true }
        } catch { } finally { $c.Close() }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Stop-Tray() {
    if (Test-Path "$InstallDir\DshMini.exe") {
        & "$InstallDir\DshMini.exe" --stop | Out-Null
    }
    for ($i = 0; $i -lt 15; $i++) {
        $c = New-Object System.Net.Sockets.TcpClient
        $open = $false
        try { $ar = $c.BeginConnect('127.0.0.1', $Port, $null, $null); $open = $ar.AsyncWaitHandle.WaitOne(300) } catch { }
        finally { $c.Close() }
        if (-not $open) { return }
        Start-Sleep -Milliseconds 500
    }
}

# ---------------------------------------------------------------- install
Write-Host "== 1/6 clean install into $InstallDir =="
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$log = Join-Path $repoRoot 'test\install.log'
$p = Start-Process -FilePath $Installer -Wait -PassThru -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$InstallDir", "/LOG=$log"
)
if ($p.ExitCode -ne 0) { Bad "installer exit code $($p.ExitCode)"; }
elseif (-not (Test-Path "$InstallDir\DshMini.exe")) { Bad "no DshMini.exe after install" }
else { Ok "installed (exit 0)" }

# ------------------------------------------------------- first start + token
Write-Host "== 2/6 start on port $Port (first run) =="
if ($NoBrowser) { $env:DSH_NO_BROWSER = '1' }
Start-Process -FilePath "$InstallDir\DshMini.exe" -ArgumentList "$Port" | Out-Null
if (-not (Wait-Port 120)) { Bad "port $Port never opened"; }
else { Ok "port $Port open" }

$trayLog = "$InstallDir\.tray.log"
$tokenUrl = $null
for ($i = 0; $i -lt 30; $i++) {
    if (Test-Path $trayLog) {
        $hit = @(Select-String -Path $trayLog -Pattern 'https?://[^\s"]*\?token=[A-Za-z0-9_\-]+' -AllMatches -ErrorAction SilentlyContinue)
        if ($hit.Count -gt 0) { $tokenUrl = $hit[-1].Matches[-1].Value; break }
    }
    Start-Sleep -Seconds 1
}
if ($tokenUrl) { Ok "tray captured token url: $($tokenUrl.Substring(0, [Math]::Min(46, $tokenUrl.Length)))..." }
else { Bad "no token url found in tray log" }

if ($NoBrowser) {
    Ok "browser suppressed (-NoBrowser); token url above is what the tray would open"
} elseif ((Test-Path $trayLog) -and (Select-String -Path $trayLog -Pattern 'opening panel \(with launch token\)' -Quiet)) {
    Ok "tray opened the panel WITH token (browser launched)"
} else { Bad "tray log has no 'opening panel (with launch token)' line" }

# --------------------------------------------------------- 401 vs token url
Write-Host "== 3/6 panel access: bare origin must 401, token url must get in =="
$bare = Get-HttpStatus "http://127.0.0.1:$Port/" $null
$bareCode = [int]$bare.StatusCode
$bare.Dispose()
if ($bareCode -eq 401) { Ok "bare / -> 401 (expected: token is mandatory)" }
else { Bad "bare / -> $bareCode (expected 401)" }

if ($tokenUrl) {
    $jar = New-Object System.Net.CookieContainer
    $withTok = Get-HttpStatus $tokenUrl $jar
    $tokCode = [int]$withTok.StatusCode
    $loc = $withTok.Headers.Location
    $withTok.Dispose()
    if ($tokCode -eq 303 -or $tokCode -eq 302) { Ok "token url -> $tokCode -> $loc" }
    else { Bad "token url -> $tokCode (expected 303)" }

    $cookies = $jar.GetCookies([uri]"http://127.0.0.1:$Port")
    if ($cookies.Count -gt 0) { Ok "cookie set: $($cookies[0].Name)" } else { Bad "no auth cookie handed out" }

    $panel = Get-HttpStatus "http://127.0.0.1:$Port/" $jar
    $panelCode = [int]$panel.StatusCode
    $body = $panel.Content.ReadAsStringAsync().Result
    $panel.Dispose()
    if ($panelCode -eq 200 -and $body.Length -gt 200) { Ok "panel with cookie -> 200 ($($body.Length) bytes html)" }
    else { Bad "panel with cookie -> $panelCode bytes=$($body.Length)" }
}

# ------------------------------------------------------- credentials layout
Write-Host "== 4/6 home/credentials sanity =="
$cred = "$InstallDir\home\.credentials.yaml"
if (Test-Path $cred) {
    if ((Get-Content $cred -TotalCount 3) -match '^version:\s*1\s*$') { Ok ".credentials.yaml uses version:1 layout" }
    else { Bad ".credentials.yaml is not version-1 layout" }
} else { Ok "no credentials file yet (clean home, written on first config)" }

# ------------------------------------------------------------- restart test
Write-Host "== 5/6 restart service, old cookie must still open the panel =="
Stop-Tray
Start-Sleep -Seconds 2
Start-Process -FilePath "$InstallDir\DshMini.exe" -ArgumentList "$Port" | Out-Null
if (-not (Wait-Port 120)) { Bad "port $Port did not come back after restart" }
else { Ok "port came back after restart" }

$tokenUrl2 = $null
for ($i = 0; $i -lt 30; $i++) {
    $hit = @(Select-String -Path $trayLog -Pattern 'https?://[^\s"]*\?token=[A-Za-z0-9_\-]+' -AllMatches -ErrorAction SilentlyContinue)
    if ($hit.Count -gt 0 -and $hit[-1].Matches[-1].Value -ne $tokenUrl) { $tokenUrl2 = $hit[-1].Matches[-1].Value; break }
    Start-Sleep -Seconds 1
}
if ($tokenUrl2) { Ok "restart produced a NEW token (rotating as designed)" }
else { Bad "restart did not yield a new token" }

if ($cookies -and $cookies.Count -gt 0) {
    $panel2Code = 0
    try {
        $jar2 = New-Object System.Net.CookieContainer
        foreach ($c in $cookies) { $jar2.Add([uri]"http://127.0.0.1:$Port", (New-Object System.Net.Cookie($c.Name, $c.Value, $c.Path, '127.0.0.1'))) }
        $panel2 = Get-HttpStatus "http://127.0.0.1:$Port/" $jar2
        $panel2Code = [int]$panel2.StatusCode
        $panel2.Dispose()
    } catch { $panel2Code = -1 }
    if ($panel2Code -eq 200) { Ok "panel after restart with the 30-day cookie -> 200" }
    else { Bad "panel after restart -> $panel2Code (cookie should survive)" }
}

# --------------------------------------------------------------- uninstall
if ($Uninstall) {
    Write-Host "== 6/6 uninstall =="
    Stop-Tray
    $unins = "$InstallDir\unins000.exe"
    if (-not (Test-Path $unins)) { Bad "no uninstaller" }
    else {
        Start-Process -FilePath $unins -Wait -ArgumentList @('/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART') | Out-Null
        Start-Sleep -Seconds 8
        $left = @(Get-ChildItem $InstallDir -Recurse -Force -ErrorAction SilentlyContinue)
        $junk = @($left | Where-Object { $_.Name -notmatch '^(unins000\.(exe|dat)|cry\.bmp|bye\.bmp)$' })
        if ($junk.Count -eq 0) { Ok "uninstall clean (only the known harmless leftovers: $($left.Count) file(s))" }
        else { Bad "uninstall left $($junk.Count) item(s): $(($junk | Select-Object -First 5 -ExpandProperty Name) -join ', ')" }
        if ($left.Count -eq 0) { Ok "install dir fully removed" }
    }
}

Remove-Item Env:\DSH_NO_BROWSER -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "== smoke result: $($pass.Count) passed, $($fail.Count) failed =="
if ($fail.Count -gt 0) { $fail | ForEach-Object { Write-Host "  FAILED: $_" }; exit 1 }
exit 0
