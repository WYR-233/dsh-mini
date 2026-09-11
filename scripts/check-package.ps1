# check-package.ps1 - packaging/template gate for a staged dsh-mini folder.
# Verifies the three things that silently break a release:
#   1. the bundled dsh kernel really is the version we meant to ship
#   2. home is CLEAN: no credentials / settings / secrets ride along
#      (and any credentials document must use the version-1 layout that
#      dsh 0.1.5 requires)
#   3. every .bat/.cmd in the package is pure ASCII (csc/cmd read them with
#      the system ANSI codepage; non-ASCII turns into mojibake or hard errors)
# Exits 1 on any failure. Run it after stage.ps1, before ISCC.
param(
    [string]$Target = "stage",   # relative to repo root
    [string]$DshVersion = ""     # expected kernel version; empty = report only
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$target = Join-Path $repoRoot $Target
if (-not (Test-Path $target)) { Write-Host "NOT FOUND: $target"; exit 1 }

$bad = @()

# ---- 1) kernel version -------------------------------------------------
$corePkg = Join-Path $target 'app\node_modules\@deepseek-ai\dsh\package.json'
if (-not (Test-Path $corePkg)) {
    $bad += "missing dsh core: $corePkg"
} else {
    $actual = (Get-Content $corePkg -Raw | ConvertFrom-Json).version
    Write-Host "-- bundled dsh kernel: $actual"
    if ($DshVersion -ne '' -and $actual -ne $DshVersion) {
        $bad += "kernel mismatch: package has $actual, expected $DshVersion"
    }
}

# ---- 2) clean home ----------------------------------------------------
# NOTE: don't name this $home - PowerShell's $HOME is read-only.
$homeDir = Join-Path $target 'home'
$forbidden = @('.credentials.yaml', 'settings.yaml', 'settings.yml', '.env', '*.pem', '*.key', '.anonymous-user-id')
foreach ($f in $forbidden) {
    Get-ChildItem $homeDir -Recurse -Force -File -Filter $f -ErrorAction SilentlyContinue |
        ForEach-Object { $bad += "forbidden file in home: $($_.FullName.Substring($target.Length + 1))" }
}

# Any credentials document that does exist (root or home) must be version 1:
# dsh 0.1.5 refuses to read the pre-release flat layout unless it can migrate it.
Get-ChildItem $target -Recurse -Force -File -Filter '.credentials.yaml' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $head = Get-Content $_.FullName -TotalCount 5
        if (-not ($head -match '^version:\s*1\s*$')) {
            $bad += "credentials not in version-1 layout: $($_.FullName.Substring($target.Length + 1))"
        }
    }

# ---- 3) bat/cmd are ASCII --------------------------------------------
$scripts = @(Get-ChildItem $target -Recurse -Force -File -Include *.bat,*.cmd -ErrorAction SilentlyContinue)
foreach ($s in $scripts) {
    $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
        $bad += "non-ASCII bat/cmd: $($s.FullName.Substring($target.Length + 1))"
    }
}
Write-Host "-- checked $($scripts.Count) bat/cmd file(s) for ASCII"

# ---- 4) required runtime files ---------------------------------------
$required = @(
    'node\node.exe',
    'app\node_modules\@deepseek-ai\dsh\lib\bin.js',
    'DshMini.exe',
    'home\profiles\web\package.json'
)
foreach ($r in $required) {
    if (-not (Test-Path (Join-Path $target $r))) { $bad += "missing required file: $r" }
}

if ($bad.Count -gt 0) {
    Write-Host "== PACKAGE CHECK FAILED =="
    $bad | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "== package check clean: version + clean home + ASCII scripts =="
exit 0
