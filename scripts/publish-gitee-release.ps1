# publish-gitee-release.ps1 - mirror a built dsh-mini installer to Gitee as a release.
#
# Gitee has no GitHub-Actions equivalent for us, so the mirror release is created
# through the Gitee OpenAPI v5 in two calls:
#   1. POST /repos/{owner}/{repo}/releases                       -> create the release
#   2. POST /repos/{owner}/{repo}/releases/{id}/attach_files     -> attach the exe
# Re-running is safe: an existing tag updates that release instead of duplicating,
# and omitting -Asset only rewrites the release text.
#
# Usage:
#   $env:GITEE_TOKEN = '<personal access token with projects scope>'
#   powershell scripts\publish-gitee-release.ps1 -Tag v0.1.1 -Name 'v0.1.1' `
#       -BodyFile .github\release-notes\v0.1.1.md `
#       -Asset release\DeepSeekHarnessMini-Setup-v0.1.1.exe
#
# Notes / gotchas baked in below:
#   - the token is read from $env:GITEE_TOKEN or -Token and never written to disk
#   - attach_files wants the token in the QUERY STRING; in the multipart body it
#     answers 401 "登录失效,无权限访问该资源" (code 40001)
#   - release notes must be read as UTF-8 explicitly (Windows PowerShell 5.1
#     Get-Content decodes UTF-8-without-BOM with the ANSI codepage -> mojibake)
#   - .NET Framework's HttpClient has no PatchAsync/HttpMethod::Patch; PATCH goes
#     through SendAsync + HttpMethod("PATCH")
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Name = "",
    [string]$BodyFile = "",
    [string]$Body = "",
    [string]$Asset = "",          # empty = only (re)write the release text
    [string]$Owner = "wyr233",
    [string]$Repo = "dsh-mini",
    [string]$Token = ""
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

if ($Token -eq "") { $Token = $env:GITEE_TOKEN }
if ([string]::IsNullOrWhiteSpace($Token)) { Write-Host "FAIL: no token (use -Token or `$env:GITEE_TOKEN)"; exit 1 }
if ($Name -eq "") { $Name = $Tag }
if ($Body -eq "" -and $BodyFile -ne "") {
    if (-not (Test-Path $BodyFile)) { Write-Host "FAIL: body file not found: $BodyFile"; exit 1 }
    $Body = [System.IO.File]::ReadAllText((Resolve-Path $BodyFile).Path, (New-Object System.Text.UTF8Encoding($false)))
}

$api = "https://gitee.com/api/v5/repos/$Owner/$Repo/releases"

function New-FormContent([hashtable]$Fields) {
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    foreach ($k in $Fields.Keys) {
        $pairs.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]'($k, [string]$Fields[$k])))
    }
    # NOTE: the leading comma stops PowerShell from unrolling the list into one
    # positional argument per entry ("cannot find an overload" otherwise).
    return New-Object System.Net.Http.FormUrlEncodedContent -ArgumentList @(, $pairs)
}

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromMinutes(10)

function Send-Form([string]$Method, [string]$Url, [hashtable]$Fields) {
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), $Url)
    $req.Content = New-FormContent $Fields
    return $client.SendAsync($req).Result
}

# ---- create or update the release -------------------------------------
$existingId = $null
try {
    $list = $client.GetStringAsync("$api`?access_token=$Token&per_page=100").Result | ConvertFrom-Json
    $hit = $list | Where-Object { $_.tag_name -eq $Tag } | Select-Object -First 1
    if ($hit) { $existingId = $hit.id }
} catch { Write-Host "-- warning: could not list releases: $($_.Exception.Message)" }

if ($existingId) {
    Write-Host "-- release $Tag already exists (id $existingId), updating it"
    $resp = Send-Form 'PATCH' "$api/$existingId" @{
        access_token = $Token; tag_name = $Tag; name = $Name; body = $Body
    }
} else {
    Write-Host "-- creating release $Tag"
    $resp = Send-Form 'POST' $api @{
        access_token = $Token; tag_name = $Tag; name = $Name; body = $Body; target_commitish = 'main'
    }
}
$json = $resp.Content.ReadAsStringAsync().Result
if (-not $resp.IsSuccessStatusCode) { Write-Host "FAIL: $([int]$resp.StatusCode) $json"; exit 1 }
$release = $json | ConvertFrom-Json
Write-Host "-- release ok: $($release.tag_name) id=$($release.id)"

# ---- attach the installer ---------------------------------------------
if ($Asset -eq "") {
    Write-Host "== gitee release $Tag updated (no attachment requested) =="
    exit 0
}
if (-not (Test-Path $Asset)) { Write-Host "FAIL: asset not found: $Asset"; exit 1 }
$file = Get-Item (Resolve-Path $Asset).Path
Write-Host ("-- uploading {0} ({1:N1} MB) ..." -f $file.Name, ($file.Length / 1MB))

$mp = New-Object System.Net.Http.MultipartFormDataContent
$mp.Add((New-Object System.Net.Http.StringContent($Token)), 'access_token')
$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
$bc = New-Object System.Net.Http.ByteArrayContent((, $bytes))
$bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
$mp.Add($bc, 'file', $file.Name)

$upload = New-Object System.Net.Http.HttpClient
$upload.Timeout = [TimeSpan]::FromMinutes(60)
$upResp = $upload.PostAsync("$api/$($release.id)/attach_files?access_token=$Token", $mp).Result
$upJson = $upResp.Content.ReadAsStringAsync().Result
if (-not $upResp.IsSuccessStatusCode) { Write-Host "FAIL upload: $([int]$upResp.StatusCode) $upJson"; exit 1 }

$done = $upJson | ConvertFrom-Json
Write-Host "-- attached: $($done.browser_download_url)"
Write-Host "== gitee release $Tag published =="
exit 0
