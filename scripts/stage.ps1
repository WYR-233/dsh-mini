# stage.ps1 - assemble the dsh-mini release folder from scratch.
# Works on this machine AND on the GitHub Actions Windows runner:
#   - node_modules is installed with npm (not pnpm): npm produces a flat
#     physical tree with NO junctions/hard links and NO hash-long directory
#     names. pnpm's link-heavy .pnpm layout blows up installer packaging
#     (ISCC chokes on junctions and Windows MAX_PATH). npm also runs
#     dependency build scripts by default (no approve-builds dance).
#   - home is seeded from the clean template in template\home
#   - a portable Node runtime is copied into node\
#   - the tray exe and icons are copied in
# Result: OutDir\ contains exactly what the installer packages.
param(
    [string]$OutDir = "stage",   # relative to repo root
    [string]$NodeDir = "",       # portable node source dir; empty = skip node copy
    [string]$Registry = ""       # npm registry override (e.g. https://registry.npmmirror.com)
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$out = Join-Path $repoRoot $OutDir
$template = Join-Path $repoRoot 'template'

function Invoke-NpmInstall([string]$Dir) {
    Push-Location $Dir
    try {
        # The dev DSH instance exports npm_config_* / HOME env vars that
        # leak into this shell; they would redirect npm's cache into the
        # running instance's folder and deadlock on its cache lock.
        foreach ($v in @('npm_config_cache','npm_config_store_dir','npm_config_registry','HOME','DSH_HOME','TEMP','TMP')) {
            Remove-Item "Env:$v" -ErrorAction SilentlyContinue
        }
        $regArg = ''
        if ($Registry -ne '') { $regArg = " --registry=$Registry" }
        cmd /c "npm install --no-audit --no-fund --loglevel=error --prefer-offline --fetch-timeout=120000 --fetch-retries=3$regArg > npm-install.log 2>&1"
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed in $Dir (see npm-install.log)"
        }
    } finally {
        Pop-Location
    }
}

Write-Host "== staging into $out =="
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$out\app", "$out\home\profiles\web" | Out-Null

# 1) dsh core into app\ (exact rc version, reproducible)
$appPkg = '{"dependencies":{"@deepseek-ai/dsh":"0.1.1-rc.2"}}'
Set-Content -Path "$out\app\package.json" -Value $appPkg -Encoding ASCII
Write-Host "-- npm install (app core, ~1-2 min) --"
Invoke-NpmInstall "$out\app"

# 2) clean home template (no credentials, no settings, no links)
Copy-Item "$template\home\*" "$out\home" -Recurse -Force

# 3) profile plugins (dshmarket) into home\profiles\web\node_modules
Write-Host "-- npm install (web profile) --"
Invoke-NpmInstall "$out\home\profiles\web"

# 4) strip source maps / type declarations (never read at runtime; keeps
#    paths and package size down)
Write-Host "-- stripping .map / .d.ts --"
foreach ($nm in @("$out\app\node_modules", "$out\home\profiles\web\node_modules")) {
    Get-ChildItem $nm -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.map$|\.d\.(ts|mts|cts)$' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 5) portable node runtime
if ($NodeDir -ne "") {
    if (-not (Test-Path "$NodeDir\node.exe")) { throw "NodeDir has no node.exe: $NodeDir" }
    Write-Host "-- copying node runtime --"
    robocopy $NodeDir "$out\node" /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy node failed ($LASTEXITCODE)" }
}

# 5) tray exe + icons + docs
Copy-Item "$repoRoot\assets\DshMini.exe" "$out\DshMini.exe" -Force
Copy-Item "$repoRoot\src\whale-desktop.ico" "$out\whale-desktop.ico" -Force
if (Test-Path "$repoRoot\LICENSE") { Copy-Item "$repoRoot\LICENSE" "$out\LICENSE.txt" -Force }

Write-Host "== stage complete =="
$size = (Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("size: {0:N1} MB" -f ($size / 1MB))
