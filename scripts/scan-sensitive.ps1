# scan-sensitive.ps1 - verify a staged dsh-mini folder contains no
# credentials, settings, or obvious secrets. Exits 1 if anything is found.
param(
    [string]$Target = "stage"   # relative to repo root
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$target = Join-Path $repoRoot $Target
if (-not (Test-Path $target)) { Write-Host "NOT FOUND: $target"; exit 1 }

$bad = @()

# 1) forbidden file names anywhere under home\ (credentials live there in dev)
$forbidden = @('.credentials.yaml', 'settings.yaml', '.env', '*.pem', '*.key', '.anonymous-user-id')
foreach ($f in $forbidden) {
    Get-ChildItem "$target\home" -Recurse -Force -File -Filter $f -ErrorAction SilentlyContinue |
        ForEach-Object { $bad += "forbidden file: $($_.FullName)" }
}

# 2) secret-shaped content in home\ and root-level files
#    (skip app\node_modules: third-party packages trip false positives)
$patterns = @(
    '(?i)\bsk-[a-zA-Z0-9]{16,}',          # OpenAI-style keys
    '(?i)api[_-]?key\s*[:=]\s*["''][^"'']{8,}',  # apiKey assignments
    '(?i)Bearer\s+[a-zA-Z0-9._-]{20,}',   # bearer tokens
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # private keys
)
$files = @(Get-ChildItem "$target\home" -Recurse -Force -File -ErrorAction SilentlyContinue)
$files += @(Get-ChildItem $target -Force -File -ErrorAction SilentlyContinue)
foreach ($file in $files) {
    try {
        $text = Get-Content $file.FullName -Raw -ErrorAction Stop
        foreach ($p in $patterns) {
            if ($text -match $p) { $bad += "pattern hit: $($file.FullName)" }
        }
    } catch { }  # binaries: skip
}

if ($bad.Count -gt 0) {
    Write-Host "== SENSITIVE DATA FOUND =="
    $bad | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "== scan clean: no credentials or secrets found =="
exit 0
